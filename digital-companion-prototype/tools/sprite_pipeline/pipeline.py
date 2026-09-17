"""Compile immutable, provenance-bound candidates; only explicit review promotes."""

from __future__ import annotations

from copy import deepcopy
from datetime import datetime, timezone
import fcntl
from io import BytesIO
import math
import os
from pathlib import Path
import shutil
import subprocess
from uuid import uuid4

from PIL import Image

from . import VERSION, pixellab
from .common import (PipelineError, canonical, digest, fingerprint, identifier, load_json,
                     read_bytes, require, safe_path, sync_dir, tree_hashes, write_bytes, write_json)
from .validation import (ACTIONS, FACINGS, combat_collision, point, validate_arena,
                         validate_arena_environment_placements, validate_environment,
                         validate_habitat, validate_plan, validate_tileset,
                         require_portable_paths, PRESENTATION_PROFILE)


# Environment .tres files contain manifests and immutable dependency bindings,
# never decoded full-resolution pixels. Keep this deliberately well below the
# generic artifact read limit so accidental texture re-embedding fails early.
MAX_ENVIRONMENT_NATIVE_BYTES = 2 * 1024 * 1024


class Pipeline:
    def __init__(self, root: Path, godot: str | None = None):
        self.root = root.absolute()
        self.source_root = self.root / "assets-source"
        self.work_root = self.root / "work" / "sprites"
        self.generated_root = self.root / "assets" / "generated"
        self.godot = godot or os.environ.get("GODOT_PATH") or shutil.which("godot") or \
            "/Applications/Godot.app/Contents/MacOS/Godot"

    def plan(self, path: Path):
        path = safe_path(self.source_root, path.absolute())
        value = load_json(path)
        validate_plan(value)
        sources = {}
        for role, source in value["sources"].items():
            source_path = safe_path(path.parent, path.parent / source["path"])
            require(digest(read_bytes(source_path)) == source["sha256"], "Source hash changed: " + role)
            sources[role] = source_path
        self.validate_derived_images(path, value, sources)
        return value, sources

    @staticmethod
    def _inside_ellipse(x, y, ellipse):
        center_x, center_y, radius_x, radius_y = ellipse
        delta_x, delta_y = x - center_x, y - center_y
        return (delta_x * delta_x * radius_y * radius_y +
                delta_y * delta_y * radius_x * radius_x <=
                radius_x * radius_x * radius_y * radius_y)

    @staticmethod
    def _inside_rect(x, y, rect):
        left, top, width, height = rect
        return left <= x < left + width and top <= y < top + height

    @staticmethod
    def _inside_polygon(x, y, polygon):
        """Integer-only even/odd test used by source-derived card recipes."""
        inside = False
        previous = polygon[-1]
        for current in polygon:
            x1, y1 = previous
            x2, y2 = current
            if (y1 > y) != (y2 > y):
                # Compare without division so the result is stable across hosts.
                left = (x2 - x1) * (y - y1)
                right = (x - x1) * (y2 - y1)
                if (left > right) == (y2 > y1):
                    inside = not inside
            previous = current
        return inside

    @staticmethod
    def _alpha_component(parent, seed, threshold):
        """Return the 4-connected opaque component containing one source seed."""
        width, height = parent.size
        seed_x, seed_y = seed
        require(0 <= seed_x < width and 0 <= seed_y < height,
                "Derived component seed lies outside parent source")
        require(parent.getpixel((seed_x, seed_y))[3] >= threshold,
                "Derived component seed is transparent")
        selected = set()
        pending = [(seed_x, seed_y)]
        while pending:
            x, y = pending.pop()
            if (x, y) in selected or parent.getpixel((x, y))[3] < threshold:
                continue
            selected.add((x, y))
            if x > 0:
                pending.append((x - 1, y))
            if x + 1 < width:
                pending.append((x + 1, y))
            if y > 0:
                pending.append((x, y - 1))
            if y + 1 < height:
                pending.append((x, y + 1))
        return selected

    def _reproduce_rgba_transform(self, parent, parameters):
        """Safe built-in implementation of the declared v1 transform profile."""
        profile = parameters["profile"]
        require(profile in ("green-shade-tree-depth-cards-v2",
                            "source-component-depth-cards-v1"),
                "Unsupported deterministic derived-image profile")
        role = parameters["role"]
        crop_left, crop_top, crop_width, crop_height = parameters["sourceCropPx"]
        require(crop_left + crop_width <= parent.width and crop_top + crop_height <= parent.height,
                "Derived sourceCropPx lies outside parent source")
        padding = parameters["paddingPx"]
        threshold = parameters["alphaThreshold"]
        trunk_rect = parameters.get("trunkRectSourcePx")
        canopy_ellipses = parameters.get("canopyEllipsesSourcePx", [])
        facade_ellipses = parameters.get("facadeEllipsesSourcePx", [])
        card = Image.new("RGBA", (crop_width + padding * 2, crop_height + padding * 2),
                         (0, 0, 0, 0))
        selected = set()
        component_pixels = set()
        role_polygons = []
        if profile == "source-component-depth-cards-v1":
            for seed in parameters["roleSeedsSourcePx"][role]:
                component_pixels.update(self._alpha_component(parent, seed, threshold))
            role_polygons = parameters["roleClipPolygonsSourcePx"][role]
        for local_y in range(crop_height):
            source_y = crop_top + local_y
            for local_x in range(crop_width):
                source_x = crop_left + local_x
                red, green, blue, alpha = parent.getpixel((source_x, source_y))
                if alpha < threshold:
                    continue
                if profile == "green-shade-tree-depth-cards-v2":
                    canopy = any(self._inside_ellipse(source_x, source_y, ellipse)
                                 for ellipse in canopy_ellipses)
                    trunk = self._inside_rect(source_x, source_y, trunk_rect)
                    facade = any(self._inside_ellipse(source_x, source_y, ellipse)
                                 for ellipse in facade_ellipses)
                    include = canopy if role == "canopy" else trunk if role == "interior" else trunk and facade
                else:
                    include = (source_x, source_y) in component_pixels and (
                        not role_polygons or any(self._inside_polygon(source_x, source_y, polygon)
                                                 for polygon in role_polygons))
                if include:
                    card.putpixel((local_x + padding, local_y + padding), (red, green, blue, 255))
                    selected.add((source_x, source_y))
        resampling = getattr(Image, "Resampling", Image).BOX
        reduced = card.resize(tuple(parameters["outputSizePx"]), resample=resampling)
        normalized = Image.new("RGBA", reduced.size, (0, 0, 0, 0))
        for y in range(reduced.height):
            for x in range(reduced.width):
                red, green, blue, alpha = reduced.getpixel((x, y))
                if alpha >= threshold:
                    normalized.putpixel((x, y), (red, green, blue, 255))
        return normalized, selected

    def validate_derived_images(self, path, plan, sources):
        """Reproduce every declared output without executing author scripts."""
        selected_by_group = {}
        for output_role, derivation in sorted(plan.get("derivedImages", {}).items()):
            recipe = derivation["recipe"]
            script = safe_path(path.parent, path.parent / recipe["scriptPath"])
            require(script.is_file() and digest(read_bytes(script)) == recipe["scriptSha256"],
                    "Derived image transformation script hash changed: " + output_role)
            parent_role = derivation["parentSource"]
            with Image.open(sources[parent_role]) as source_image:
                source_image.load()
                parent = source_image.convert("RGBA")
            expected, selected = self._reproduce_rgba_transform(parent, recipe["parameters"])
            with Image.open(sources[output_role]) as output_image:
                output_image.load()
                actual = output_image.convert("RGBA")
            require(actual.size == expected.size and actual.tobytes() == expected.tobytes(),
                    "Derived image pixels do not reproduce from declared parent/recipe: " + output_role)
            encoded = BytesIO()
            expected.save(encoded, format="PNG", optimize=False, compress_level=9)
            require(digest(encoded.getvalue()) == derivation["outputSha256"],
                    "Derived image encoding differs from declared outputSha256: " + output_role)
            parameters = recipe["parameters"]
            group = fingerprint({key: value for key, value in parameters.items() if key != "role"})
            selected_by_group.setdefault(group, {"minimum": parameters["minimumOverlapPx"], "roles": {}})
            require(parameters["role"] not in selected_by_group[group]["roles"],
                    "Derived depth-card group repeats a semantic role")
            selected_by_group[group]["roles"][parameters["role"]] = selected
        for group in selected_by_group.values():
            roles = group["roles"]
            require(set(roles) in ({"canopy", "interior", "facade"},
                                   {"roof", "interior", "facade"}),
                    "Derived depth-card profile requires facade/interior and canopy or roof outputs")
            top_role = "canopy" if "canopy" in roles else "roof"
            require(len(roles[top_role] & roles["interior"]) >= group["minimum"] and
                    len(roles["interior"] & roles["facade"]) >= group["minimum"],
                    "Derived depth cards do not meet minimumOverlapPx")

    def new(self, asset_id, revision, kind, provider):
        identifier(asset_id, "assetId")
        identifier(revision, "revision")
        plan = template(asset_id, revision, kind, provider)
        validate_plan(plan)
        path = self.source_root / asset_id / revision / "source-plan.json"
        write_json(self.root, path, plan)
        return {"plan": str(path), "next": "Ingest source images and edit explicit layout/clip metadata."}

    def ingest(self, path: Path, source: Path, role: str):
        plan, _ = self.plan(path)
        identifier(role, "source role")
        raw = read_bytes(source.absolute())
        pixellab.inspect_png(raw)
        hashed = digest(raw)
        destination = path.parent / "sources" / (hashed[7:] + ".png")
        binding = {"path": destination.relative_to(path.parent).as_posix(), "sha256": hashed}
        if role in plan["sources"]:
            require(plan["sources"][role] == binding, "Source role is immutable; create a new revision or role")
        if destination.exists():
            require(digest(read_bytes(destination)) == hashed, "Source archive content changed")
        else:
            write_bytes(self.root, destination, raw)
        plan["sources"][role] = binding
        write_json(self.root, path, plan, replace=True)
        return {"role": role, **binding, "plan": str(path)}

    def keypose_binding(self, plan):
        require(plan.get("keyposes"), "This plan does not declare keypose/sample gates")
        sources = {}
        for role in plan["keyposes"]:
            require(role in plan["sources"], "Missing keypose/sample source: " + role)
            sources[role] = plan["sources"][role]["sha256"]
        # Adding inbetween source bytes cannot invalidate approved poses, while
        # changing identity, canvas, motion profile or required facings does.
        # Final clip timing/sequences are authored AFTER this gate and receive
        # their own exact-content final approval, rather than freezing templates.
        spec = {key: value for key, value in plan.items() if key not in
                ("sources", "generation", "clips", "fallbacks", "atlasColumns", "paddingPx", "extrudePx")}
        return {"specSha256": fingerprint(spec), "sourceHashes": sources}

    def require_keyposes(self, path, plan):
        if not plan.get("keyposes"):
            require(plan["kind"] != "animation", "Animation plans must declare keypose gates")
            return None
        receipt = path.parent / "keypose-review.json"
        require(receipt.is_file(), "Approve keyposes/samples before completing this candidate")
        value = load_json(receipt)
        require(value.get("stage") == "keyposes" and value.get("decision") == "approved" and
                value.get("binding") == self.keypose_binding(plan) and value.get("reviewer") and
                value.get("reviewedAt"), "Keypose approval is missing or stale")
        return value

    def generate(self, path, job_id=None, execute=False, allow_billable=False, resume=False, transport=pixellab.request):
        plan, sources = self.plan(path)
        generation = plan.get("generation", {})
        jobs = generation.get("jobs", [])
        if plan["provider"] in ("codex-imagegen", "manual"):
            require(not allow_billable and not resume, "These flags apply only to PixelLab")
            brief = {"schemaVersion": 1, "provider": plan["provider"], "assetId": plan["assetId"],
                     "revision": plan["revision"], "planSha256": digest(read_bytes(path)),
                     "brief": generation.get("brief", "Create the declared source roles; preserve identity and pivots."),
                     "requiredFacings": plan.get("requiredFacings", []), "jobs": jobs,
                     "keyposeRoles": plan.get("keyposes", []), "sources": plan["sources"],
                     "next": "Use Codex imagegen in conversation, or author manually; then run ingest. No CLI image API was called."}
            if execute:
                destination = self.work_root / plan["assetId"] / plan["revision"] / "generation-brief.json"
                write_json(self.root, destination, brief, replace=True)
            return dict(brief, dryRun=not execute)
        require(isinstance(jobs, list) and jobs, "PixelLab plan needs generation.jobs")
        require(len({j.get("id") for j in jobs}) == len(jobs), "Duplicate generation job IDs")
        selected = [job for job in jobs if job.get("id") == job_id] if job_id else jobs
        require(len(selected) == 1, "Choose exactly one PixelLab job with --job")
        job = selected[0]
        if job.get("stage") != "keyposes":
            self.require_keyposes(path, plan)
        operation, payload, size = pixellab.prepare(plan, job, sources)
        require(job.get("stage") != "keyposes" or operation == "generate-image-v2",
                "Animation completion cannot bypass the keypose gate")
        binding = {"assetId": plan["assetId"], "revision": plan["revision"], "job": job["id"]}
        directory = self.work_root / plan["assetId"] / plan["revision"] / "jobs" / job["id"]
        safe_path(self.work_root, directory)
        return pixellab.run_job(self.root, directory, binding, operation, payload, size,
                               execute, allow_billable, resume, transport,
                               source_plan_sha256=digest(read_bytes(path)))

    def compile(self, path: Path, native=True):
        plan, sources = self.plan(path)
        approval = self.require_keyposes(path, plan)
        plan_hash = digest(read_bytes(path))
        build_identity = fingerprint({"plan": plan_hash, "compiler": VERSION, "native": native})
        build_id = build_identity[7:23]
        parent = safe_path(self.work_root, self.work_root / plan["assetId"] / plan["revision"])
        candidate = parent / build_id
        if candidate.exists():
            return self.validate(candidate)
        staging = parent / (".build-" + uuid4().hex)
        safe_path(self.root, staging)
        staging.mkdir(parents=True)
        try:
            write_bytes(self.root, staging / "source-plan.json", read_bytes(path))
            if approval:
                write_json(self.root, staging / "keypose-review.json", approval)
            if plan["kind"] in ("animation", "atlas"):
                self.compile_atlas(plan, sources, staging)
            elif plan["kind"] == "tileset":
                role = plan.get("textureSource", "texture")
                require(role in sources, "Missing TileSet texture source")
                raw = read_bytes(sources[role])
                with Image.open(BytesIO(raw)) as image:
                    validate_tileset(plan["tileset"], image.size)
                    require(image.width % plan["tileset"]["tileSize"][0] == 0 and
                            image.height % plan["tileset"]["tileSize"][1] == 0,
                            "Tile atlas must contain whole cells; tiles are never trimmed or rotated")
                write_bytes(self.root, staging / "atlas.png", raw)
                value = dict(deepcopy(plan["tileset"]), schemaVersion=1, kind="tileset",
                             assetId=plan["assetId"], revision=plan["revision"], texture="atlas.png")
                for tile in value["tiles"]:
                    tile["collision"] = combat_collision(tile, value["tileSize"], value["projection"])
                write_json(self.root, staging / "tileset.json", value)
            elif plan["kind"] == "arena":
                value = dict(deepcopy(plan["arena"]), schemaVersion=1, kind="arena",
                             assetId=plan["assetId"], revision=plan["revision"])
                # The same ground footprints derive both native tile collision
                # and these arena obstacles; there is no second geometry source.
                self.validate_arena_dependency(value)
                if plan.get("backgroundSource"):
                    role = plan["backgroundSource"]
                    require(role in sources, "Missing arena background source")
                    write_bytes(self.root, staging / "background.png", read_bytes(sources[role]))
                    value["background"] = "background.png"
                write_json(self.root, staging / "arena.json", value)
                write_json(self.root, staging / "arena-validation.json", validate_arena(value))
            elif plan["kind"] == "environment":
                self.compile_environment(plan, sources, staging)
            else:
                self.compile_habitat(plan, staging)
            metadata = {"schemaVersion": 1, "kind": plan["kind"], "assetId": plan["assetId"],
                        "revision": plan["revision"], "compilerVersion": VERSION,
                        "buildIdentity": build_identity,
                        "sourcePlan": path.relative_to(self.root).as_posix(), "planSha256": plan_hash,
                        "sourceHashes": {role: source["sha256"] for role, source in plan["sources"].items()},
                        "nativeResources": False, "files": {}}
            if plan["kind"] == "environment":
                metadata["nativeDependencies"] = self._environment_native_dependencies(staging)
            if plan["kind"] in ("environment", "habitat"):
                require_portable_paths(metadata, "Candidate metadata")
            write_json(self.root, staging / "candidate.json", metadata)
            exporter = self.root / "scripts" / "assets" / "export_resources.gd"
            if native:
                require(exporter.is_file(), "Native exporter is unavailable; --no-native creates a non-promotable test candidate")
                result = subprocess.run([self.godot, "--headless", "--path", str(self.root), "--script",
                                         "res://scripts/assets/export_resources.gd", "--", "--asset-review",
                                         "--candidate", str(staging)], capture_output=True, text=True, timeout=60)
                require(result.returncode == 0 and "SCRIPT ERROR" not in result.stderr,
                        "Native export failed:\n" + (result.stdout + result.stderr)[-3000:])
                expected = {"animation": "spriteframes.tres", "tileset": "tileset.tres",
                            "atlas": "atlasframes.tres", "arena": "arena.tres",
                            "environment": "environment.tres", "habitat": "habitat.tres"}.get(plan["kind"])
                if expected:
                    require((staging / expected).is_file(), "Native exporter did not produce " + expected)
                if plan["kind"] == "environment":
                    self._validate_environment_native_size(staging)
                metadata["nativeResources"] = True
            if plan["kind"] in ("animation", "atlas", "tileset"):
                png_payloads = ["atlas.png"]
            elif plan["kind"] == "arena":
                png_payloads = ["background.png"] if plan.get("backgroundSource") else []
            elif plan["kind"] == "environment":
                png_payloads = list(load_json(staging / "environment.json")["textures"].values())
            else:
                png_payloads = []
            metadata["files"] = tree_hashes(staging, payload_files=png_payloads)
            metadata["contentSha256"] = fingerprint({key: value for key, value in metadata.items()
                                                    if key != "sourcePlan"})
            write_json(self.root, staging / "candidate.json", metadata, replace=True)
            os.rename(str(staging), str(candidate))
            sync_dir(parent)
        except Exception:
            # Remove only this invocation's exact newly-created staging tree.
            if staging.exists():
                shutil.rmtree(staging)
            raise
        return self.validate(candidate)

    def _environment_native_dependencies(self, folder):
        """Return the exact portable PNG dependency set stored in environment.tres."""
        environment = load_json(folder / "environment.json")
        bindings = environment.get("textures")
        require(isinstance(bindings, dict) and bindings, "Environment texture bindings are missing")
        relatives = list(bindings.values())
        require(len(set(relatives)) == len(relatives),
                "Environment texture roles must bind distinct package files")
        dependencies = {}
        for role, relative in sorted(bindings.items()):
            require(relative == "textures/" + role + ".png",
                    "Environment texture dependency binding is malformed: " + role)
            payload = safe_path(folder, folder / relative)
            dependencies[relative] = digest(read_bytes(payload))
        return dependencies

    @staticmethod
    def _validate_environment_native_size(folder):
        native = folder / "environment.tres"
        require(native.is_file(), "Native exporter did not produce environment.tres")
        require(native.stat().st_size <= MAX_ENVIRONMENT_NATIVE_BYTES,
                "environment.tres exceeds compact native metadata limit; external textures must not be embedded")

    def compile_environment(self, plan, sources, staging):
        source_sizes = {}
        for role, path in sources.items():
            with Image.open(path) as image:
                source_sizes[role] = image.size
        validation = validate_environment(plan["environment"], set(sources), source_sizes)
        roles = {chunk["source"] for chunk in plan["environment"]["terrainChunks"]}
        roles.update(plane["source"] for plane in plan["environment"]["spritePlanes"])
        roles.update(plane["source"] for plane in plan["environment"].get("ambientPlanes", []))
        textures = {}
        for role in sorted(roles):
            relative = "textures/" + role + ".png"
            write_bytes(self.root, staging / relative, read_bytes(sources[role]))
            textures[role] = relative
        environment = deepcopy(plan["environment"])
        for chunk in environment["terrainChunks"]:
            binding = chunk["source"]
            if "sourceRegionPx" in chunk:
                binding = "terrain." + chunk["id"]
                relative = "textures/" + binding + ".png"
                require(binding not in textures,
                        "Derived terrain texture binding collides with a source role: " + binding)
                with Image.open(sources[chunk["source"]]) as original:
                    original.load()
                    image = original.convert("RGBA")
                x, y, width, height = chunk["sourceRegionPx"]
                image = image.crop((x, y, x + width, y + height))
                image.putdata([(0, 0, 0, 0) if pixel[3] == 0 else pixel for pixel in image.getdata()])
                output = BytesIO()
                image.save(output, format="PNG", optimize=False, compress_level=9)
                write_bytes(self.root, staging / relative, output.getvalue())
                textures[binding] = relative
            chunk["textureBinding"] = binding
        # Runtime payload provenance is deliberately rebuilt from safe scalar IDs
        # and immutable digests. Author workstation paths remain source-plan-only.
        provenance_kind = plan["provenance"]["kind"]
        value = dict(environment, schemaVersion=1, kind="environment",
                     assetId=plan["assetId"], revision=plan["revision"], provider=plan["provider"],
                     provenance={"kind": provenance_kind,
                                 "generator": plan["provider"], "compilerVersion": VERSION,
                                 "sourceHashes": {role: plan["sources"][role]["sha256"]
                                                  for role in sorted(plan["sources"]) }},
                     textures=textures)
        require_portable_paths(value, "Environment runtime manifest")
        write_json(self.root, staging / "environment.json", value)
        write_json(self.root, staging / "environment-validation.json", validation)
        write_json(self.root, staging / "environment-review.json", {
            "schemaVersion": 1, "kind": "environment-review", "assetId": plan["assetId"],
            "revision": plan["revision"], "status": "pending-human-review",
            "viewpoints": deepcopy(value["reviewViewpoints"]),
            "checklist": ["depth-and-plane-separation", "card-edge-exposure", "pixel-scale-and-shimmer",
                          "alpha-and-depth-order", "navigation-footprint-alignment", "license-classification"]})

    def validate_environment_crops(self, environment, directory):
        """Prove every derived terrain payload is the exact declared source crop."""
        textures = environment["textures"]
        for chunk in environment["terrainChunks"]:
            if "sourceRegionPx" not in chunk:
                continue
            source_binding = chunk["source"]
            derived_binding = chunk.get("textureBinding")
            require(source_binding in textures and derived_binding in textures and
                    derived_binding != source_binding,
                    "Cropped terrain needs distinct source and derived texture bindings")
            x, y, width, height = chunk["sourceRegionPx"]
            with Image.open(directory / textures[source_binding]) as source_image:
                source_image.load()
                expected = source_image.convert("RGBA").crop((x, y, x + width, y + height))
            expected.putdata([(0, 0, 0, 0) if pixel[3] == 0 else pixel
                              for pixel in expected.getdata()])
            with Image.open(directory / textures[derived_binding]) as derived_image:
                derived_image.load()
                actual = derived_image.convert("RGBA")
            require(actual.size == expected.size and actual.tobytes() == expected.tobytes(),
                    "Compiled terrain crop differs from its hash-bound source region")

    def compile_habitat(self, plan, staging):
        value = dict(deepcopy(plan["habitat"]), schemaVersion=1, kind="habitat",
                     assetId=plan["assetId"], revision=plan["revision"])
        environment = self.validate_environment_dependency(value["environment"])
        validation = validate_habitat(value, environment)
        require_portable_paths(value, "Habitat runtime manifest")
        write_json(self.root, staging / "habitat.json", value)
        write_json(self.root, staging / "habitat-validation.json", validation)
        write_json(self.root, staging / "habitat-review.json", {
            "schemaVersion": 1, "kind": "habitat-review", "assetId": plan["assetId"],
            "revision": plan["revision"], "status": "pending-human-review",
            "environment": deepcopy(value["environment"]),
            "checklist": ["spawn-clearance", "waste-anchor-reachability", "decoration-zone-coverage",
                          "static-placement-footprints", "camera-review"]})

    def compile_atlas(self, plan, sources, staging):
        frames = {}
        clips = deepcopy(plan.get("clips", {}))
        records = []
        if plan["kind"] == "animation":
            for clip_id in sorted(clips):
                for index, frame in enumerate(clips[clip_id]["frames"]):
                    name = clip_id + ".f%04d" % index
                    records.append((name, frame))
        else:
            records = sorted(plan["entries"].items())
        require(1 <= len(records) <= 4096, "Atlas frame count is outside limits")
        images = []
        for name, frame in records:
            require(frame["source"] in sources, "Missing frame source: " + frame["source"])
            with Image.open(sources[frame["source"]]) as original:
                original.load()
                image = original.convert("RGBA")
            if "rect" in frame:
                x, y, w, h = frame["rect"]
                require(x >= 0 and y >= 0 and w > 0 and h > 0 and x+w <= image.width and y+h <= image.height,
                        "Frame crop lies outside source")
                image = image.crop((x, y, x+w, y+h))
            if plan["kind"] == "animation":
                require(image.size == tuple(plan["canvas"]), "Animation frames must use the declared fixed canvas")
                require(image.getchannel("A").getbbox() is not None, "Empty animation frame")
            # Transparent RGB is normalized without alpha threshold, scaling, or
            # per-frame recentering. The authored anchor must not drift.
            image.putdata([(0, 0, 0, 0) if p[3] == 0 else p for p in image.getdata()])
            images.append(image)
        padding = plan.get("paddingPx", 2)
        extrude = plan.get("extrudePx", 1)
        require(type(padding) is int and type(extrude) is int and 0 <= extrude <= padding <= 16,
                "Invalid padding/extrusion")
        cell_w = max(image.width for image in images)+2*padding
        cell_h = max(image.height for image in images)+2*padding
        columns = plan.get("atlasColumns", min(8, math.ceil(math.sqrt(len(images)))))
        require(type(columns) is int and 1 <= columns <= 64, "Invalid atlasColumns")
        dimensions = (columns*cell_w, math.ceil(len(images)/columns)*cell_h)
        require(max(dimensions) <= 16384 and dimensions[0]*dimensions[1] <= 32*1024*1024,
                "Compiled atlas exceeds pixel budget")
        atlas = Image.new("RGBA", dimensions)
        for index, ((name, frame), image) in enumerate(zip(records, images)):
            x, y = (index % columns)*cell_w+padding, (index//columns)*cell_h+padding
            if extrude:
                # Copy exact edge pixels into gutters, never interpolate colors.
                for dy in range(-extrude, image.height+extrude):
                    for dx in range(-extrude, image.width+extrude):
                        if dx < 0 or dy < 0 or dx >= image.width or dy >= image.height:
                            atlas.putpixel((x+dx, y+dy), image.getpixel((max(0, min(dx, image.width-1)),
                                                                     max(0, min(dy, image.height-1)))))
            atlas.paste(image, (x, y))
            frames[name] = {"frame": {"x": x, "y": y, "w": image.width, "h": image.height},
                            "rotated": False, "trimmed": False,
                            "spriteSourceSize": {"x": 0, "y": 0, "w": image.width, "h": image.height},
                            "sourceSize": {"w": image.width, "h": image.height}}
            if plan["kind"] == "atlas" and "pivot" in frame:
                frames[name]["pivot"] = deepcopy(frame["pivot"])
            if plan["kind"] == "animation":
                frame["atlasFrame"] = name
                frame.pop("source")
                frame.pop("rect", None)
        output = BytesIO()
        atlas.save(output, format="PNG", optimize=False, compress_level=9)
        raw = output.getvalue()
        write_bytes(self.root, staging / "atlas.png", raw)
        write_json(self.root, staging / "atlas.json", {"frames": frames, "meta": {"image": "atlas.png",
                   "format": "RGBA8888", "size": {"w": atlas.width, "h": atlas.height}, "scale": "1"}})
        if plan["kind"] == "animation":
            for clip_id, clip in clips.items():
                clip.setdefault("semanticAction", clip_id.split(".")[0])
                clip.setdefault("events", [])
                clip.setdefault("qualityProfile", "pending-human-review")
            value = {"schemaVersion": 1, "assetId": plan["assetId"], "subjectId": plan.get("subjectId", plan["assetId"]),
                     "revision": plan["revision"], "status": "candidate", "clips": clips,
                     "fallbacks": plan.get("fallbacks", {}), "requiredFacings": plan.get("requiredFacings", []),
                     "requiredActions": plan.get("requiredActions", []),
                     "motionProfile": plan.get("motionProfile", {"rootPolicy": "in-place", "facing": "eight-direction",
                                                                 "requiredAnchors": ["root"]}),
                     "atlas": {"image": "atlas.png", "data": "atlas.json", "paddingPx": padding, "extrudePx": extrude},
                     "provenance": {**deepcopy(plan.get("provenance", {})), "generator": plan["provider"],
                                    "compilerVersion": VERSION, "sourceHashes": {k:v["sha256"] for k,v in plan["sources"].items()},
                                    "outputSha256": digest(raw)}}
            write_json(self.root, staging / "animation-set.json", value)

    def validate_arena_dependency(self, value):
        environment = None
        if "environment" in value:
            environment = self.validate_environment_dependency(value["environment"])
        if "tileSet" not in value:
            tileset = None
        else:
            binding = value["tileSet"]
            path = safe_path(self.generated_root, self.generated_root / binding["assetId"] / binding["revision"])
            require((path / "tileset.json").is_file(), "Arena TileSet must be promoted at its pinned revision first")
            metadata = load_json(path / "candidate.json")
            require(metadata.get("kind") == "tileset", "Arena dependency is not a TileSet")
            require(tree_hashes(path) == metadata["files"], "Pinned TileSet content changed")
            tileset = load_json(path / "tileset.json")
            require(tileset["projection"] == value["projection"], "Arena and TileSet projections differ")
            available = {(tuple(tile["atlas"]), tile.get("alternative", 0)): tile for tile in tileset["tiles"]}
            value["obstacles"] = [obstacle for obstacle in value["obstacles"] if not obstacle.get("tileDerived", False)]
            occupied = set()
            for tile in value.get("tiles", []):
                key = (tuple(tile["atlas"]), tile.get("alternative", 0))
                require(key in available, "Placed tile is missing from pinned TileSet")
                require(tuple(tile["cell"]) not in occupied, "Duplicate arena tile placement")
                occupied.add(tuple(tile["cell"]))
                record = available[key]
                require(not record.get("collision") or record.get("combat"),
                        "Placed collision tile lacks a shared combat footprint")
                if record.get("combat"):
                    combat = record["combat"]
                    x, y, w, h = combat["rect"]
                    cell = value["ground"]["cellSize"]
                    require(combat.get("cellSize") == cell, "Arena ground cellSize differs from pinned tile combat.cellSize")
                    require(x+w <= cell and y+h <= cell, "Tile combat footprint escapes its ground cell")
                    obstacle = deepcopy(combat)
                    obstacle.update(id="tile-%d-%d" % tuple(tile["cell"]), tileDerived=True,
                                    rect=[tile["cell"][0]*cell+x, tile["cell"][1]*cell+y, w, h])
                    value["obstacles"].append(obstacle)
            # Store the complete pinned content hash, not only a mutable asset ID.
            require("contentSha256" not in binding or binding["contentSha256"] == metadata["contentSha256"],
                    "Pinned TileSet revision content changed")
            binding["contentSha256"] = metadata["contentSha256"]
        if environment is not None:
            validate_arena_environment_placements(value, environment)

    def validate_environment_dependency(self, binding):
        path = safe_path(self.generated_root, self.generated_root / binding["assetId"] / binding["revision"])
        require((path / "environment.json").is_file(),
                "Environment must be promoted at its pinned revision first")
        metadata = load_json(path / "candidate.json")
        require(metadata.get("kind") == "environment", "Pinned dependency is not an Environment")
        require(metadata.get("assetId") == binding["assetId"] and metadata.get("revision") == binding["revision"],
                "Pinned Environment identity differs from its catalog path")
        require(tree_hashes(path) == metadata.get("files"), "Pinned Environment content changed")
        environment = load_json(path / "environment.json")
        require_portable_paths(environment, "Promoted Environment runtime manifest")
        require(environment.get("assetId") == binding["assetId"] and
                environment.get("revision") == binding["revision"],
                "Pinned Environment manifest identity differs")
        textures = environment.get("textures")
        require(isinstance(textures, dict) and textures and
                all(relative == "textures/" + role + ".png" for role, relative in textures.items()),
                "Promoted Environment texture bindings are malformed")
        source_sizes = {}
        for role, relative in textures.items():
            with Image.open(path / relative) as image:
                source_sizes[role] = image.size
                image.verify()
        validate_environment(environment, set(textures), source_sizes, allow_compiled_bindings=True)
        self.validate_environment_crops(environment, path)
        require("contentSha256" not in binding or binding["contentSha256"] == metadata["contentSha256"],
                "Pinned Environment revision content changed")
        binding["contentSha256"] = metadata["contentSha256"]
        return environment

    def _validate_copied_source_payloads(self, candidate, plan, runtime=None):
        """Bind copied runtime payload bytes to the immutable source-role hashes.

        Candidate tree hashes alone are self-asserted metadata. This second
        comparison reaches back to the approved source plan so replacing a PNG
        and recomputing candidate.json cannot substitute source artwork.
        """
        bindings = []
        if plan["kind"] == "environment":
            require(isinstance(runtime, dict), "Environment runtime manifest is unavailable")
            roles = {chunk["source"] for chunk in plan["environment"]["terrainChunks"]}
            roles.update(plane["source"] for plane in plan["environment"]["spritePlanes"])
            roles.update(plane["source"] for plane in plan["environment"].get("ambientPlanes", []))
            for role in sorted(roles):
                require(runtime.get("textures", {}).get(role) == "textures/" + role + ".png",
                        "Copied Environment source texture binding is malformed: " + role)
                bindings.append((role, runtime["textures"][role]))
        elif plan["kind"] == "tileset":
            bindings.append((plan.get("textureSource", "texture"), "atlas.png"))
        elif plan["kind"] == "arena" and plan.get("backgroundSource"):
            bindings.append((plan["backgroundSource"], "background.png"))
        for role, relative in bindings:
            require(role in plan["sources"], "Copied payload references an undeclared source role: " + role)
            payload = safe_path(candidate, candidate / relative)
            require(payload.is_file() and digest(read_bytes(payload)) == plan["sources"][role]["sha256"],
                    "Copied source-role texture differs from immutable source hash: " + role)

    def _probe_native_resource(self, candidate, metadata):
        """Load the native resource in Godot and verify its embedded identity."""
        expected = {"animation": "spriteframes.tres", "tileset": "tileset.tres",
                    "atlas": "atlasframes.tres", "arena": "arena.tres",
                    "environment": "environment.tres", "habitat": "habitat.tres"}.get(metadata["kind"])
        require(expected is not None, "Unsupported native candidate kind")
        if metadata["kind"] == "environment":
            self._validate_environment_native_size(candidate)
        probe = self.root / "scripts" / "assets" / "probe_native_resource.gd"
        require(probe.is_file(), "Native resource probe is unavailable")
        result = subprocess.run([self.godot, "--headless", "--path", str(self.root), "--script",
                                 "res://scripts/assets/probe_native_resource.gd", "--", "--candidate",
                                 str(candidate)], capture_output=True, text=True, timeout=60)
        marker = "NATIVE_RESOURCE_PROBE_OK:" + metadata["buildIdentity"]
        require(result.returncode == 0 and marker in result.stdout and
                "SCRIPT ERROR" not in result.stderr and "Parse Error" not in result.stderr,
                "Native resource load/probe failed:\n" + (result.stdout + result.stderr)[-3000:])

    def validate(self, candidate: Path, require_native=False):
        candidate = safe_path(self.root, candidate.absolute())
        metadata = load_json(candidate / "candidate.json")
        require(isinstance(metadata, dict) and metadata.get("schemaVersion") == 1, "Invalid candidate manifest")
        if metadata.get("kind") == "environment" and metadata.get("nativeResources") is True:
            self._validate_environment_native_size(candidate)
        actual = tree_hashes(candidate)
        require(actual == metadata.get("files"), "Candidate file tree or content changed")
        signed = {key: value for key, value in metadata.items() if key not in ("sourcePlan", "contentSha256")}
        require(fingerprint(signed) == metadata.get("contentSha256"), "Candidate manifest fingerprint changed")
        plan = load_json(candidate / "source-plan.json")
        validate_plan(plan)
        require(digest(read_bytes(candidate / "source-plan.json")) == metadata["planSha256"], "Candidate source plan changed")
        require(all(metadata[k] == plan[k] for k in ("assetId", "revision", "kind")), "Candidate identity differs from plan")
        require(metadata.get("compilerVersion") == VERSION,
                "Candidate compiler version differs from this validator")
        expected_build_identity = fingerprint({"plan": metadata["planSha256"],
                                               "compiler": metadata["compilerVersion"],
                                               "native": metadata.get("nativeResources") is True})
        require(metadata.get("buildIdentity") == expected_build_identity,
                "Candidate build identity differs from plan/compiler/native inputs")
        require(metadata["sourceHashes"] == {role:source["sha256"] for role,source in plan["sources"].items()},
                "Candidate source hashes differ from plan")
        original = safe_path(self.source_root, self.root / metadata["sourcePlan"])
        original_plan, _ = self.plan(original)
        require(digest(read_bytes(original)) == metadata["planSha256"], "Source plan changed since compilation")
        self.require_keyposes(original, original_plan)
        if require_native:
            require(metadata.get("nativeResources") is True, "Native resources required before promotion")
        if plan["kind"] == "arena":
            arena = load_json(candidate / "arena.json")
            require(arena.get("background") == "background.png" if plan.get("backgroundSource")
                    else "background" not in arena,
                    "Compiled Arena background binding differs from its source plan")
            validate_arena(arena)
            original_arena = deepcopy(arena)
            self.validate_arena_dependency(arena)
            require(arena == original_arena, "Arena tile-derived geometry differs from its pinned TileSet")
        elif plan["kind"] == "environment":
            environment = load_json(candidate / "environment.json")
            require_portable_paths(environment, "Environment runtime manifest")
            require(environment.get("provenance") == {
                        "kind": plan["provenance"]["kind"], "generator": plan["provider"],
                        "compilerVersion": VERSION,
                        "sourceHashes": {role: plan["sources"][role]["sha256"]
                                         for role in sorted(plan["sources"])}},
                    "Compiled Environment provenance differs from canonical source bindings")
            roles = {chunk["source"] for chunk in plan["environment"]["terrainChunks"]}
            roles.update(plane["source"] for plane in plan["environment"]["spritePlanes"])
            roles.update(plane["source"] for plane in plan["environment"].get("ambientPlanes", []))
            expected_textures = {role: "textures/" + role + ".png" for role in sorted(roles)}
            expected_bindings = {}
            for chunk in plan["environment"]["terrainChunks"]:
                binding = chunk["source"]
                if "sourceRegionPx" in chunk:
                    binding = "terrain." + chunk["id"]
                    require(binding not in expected_textures,
                            "Derived terrain texture binding collides with a source role: " + binding)
                    expected_textures[binding] = "textures/" + binding + ".png"
                expected_bindings[chunk["id"]] = binding
            require(environment.get("textures") == expected_textures,
                    "Compiled Environment texture bindings differ from source roles")
            self._validate_copied_source_payloads(candidate, plan, environment)
            expected_dependencies = self._environment_native_dependencies(candidate)
            require(metadata.get("nativeDependencies") == expected_dependencies and
                    all(metadata["files"].get(relative) == sha256
                        for relative, sha256 in expected_dependencies.items()),
                    "Environment native dependency hashes differ from packaged texture payloads")
            compiled_chunks = {chunk["id"]: chunk for chunk in environment["terrainChunks"]}
            require(set(compiled_chunks) == set(expected_bindings) and
                    all(compiled_chunks[chunk_id].get("textureBinding") == binding
                        for chunk_id, binding in expected_bindings.items()),
                    "Compiled terrain textureBinding differs from its deterministic source binding")
            source_sizes = {}
            for role, relative in environment["textures"].items():
                with Image.open(candidate / relative) as image:
                    source_sizes[role] = image.size
                    image.verify()
            self.validate_environment_crops(environment, candidate)
            validate_environment(environment, set(environment["textures"]), source_sizes,
                                 allow_compiled_bindings=True)
            review = load_json(candidate / "environment-review.json")
            require(review.get("status") == "pending-human-review",
                    "Compiled Environment review metadata cannot imply approval")
        elif plan["kind"] == "habitat":
            habitat = load_json(candidate / "habitat.json")
            require_portable_paths(habitat, "Habitat runtime manifest")
            original_habitat = deepcopy(habitat)
            environment = self.validate_environment_dependency(habitat["environment"])
            require(habitat == original_habitat, "Habitat Environment dependency pin differs from promoted content")
            validate_habitat(habitat, environment)
            review = load_json(candidate / "habitat-review.json")
            require(review.get("status") == "pending-human-review",
                    "Compiled Habitat review metadata cannot imply approval")
        if plan["kind"] in ("animation", "atlas"):
            atlas = load_json(candidate / "atlas.json")
            with Image.open(candidate / "atlas.png") as image:
                require(atlas["meta"]["size"] == {"w": image.width, "h": image.height}, "Atlas dimensions differ")
                for frame in atlas["frames"].values():
                    rect = frame["frame"]
                    require(not frame["rotated"] and not frame["trimmed"] and
                            0 <= rect["x"] and 0 <= rect["y"] and rect["w"] > 0 and rect["h"] > 0 and
                            rect["x"]+rect["w"] <= image.width and rect["y"]+rect["h"] <= image.height,
                            "Atlas frame is malformed or out of bounds")
            if plan["kind"] == "animation":
                animation = load_json(candidate / "animation-set.json")
                require(set(animation["clips"]) == set(plan["clips"]), "Compiled clip set differs from plan")
                for clip in animation["clips"].values():
                    for frame in clip["frames"]:
                        require(frame["atlasFrame"] in atlas["frames"], "Clip references missing atlas frame")
                        point(frame["pivot"], "pivot")
        elif plan["kind"] == "tileset":
            self._validate_copied_source_payloads(candidate, plan)
            with Image.open(candidate / "atlas.png") as image:
                tileset = load_json(candidate / "tileset.json")
                validate_tileset(tileset, image.size)
                for tile in tileset["tiles"]:
                    require(tile.get("collision", []) == combat_collision(tile, tileset["tileSize"], tileset["projection"]),
                            "Compiled native collision differs from canonical ground footprint")
        if plan["kind"] == "arena":
            self._validate_copied_source_payloads(candidate, plan)
        if require_native:
            self._probe_native_resource(candidate, metadata)
        return {"ok": True, "candidate": str(candidate), "kind": metadata["kind"],
                "contentSha256": metadata["contentSha256"], "nativeResources": metadata["nativeResources"]}

    def fixture_check(self, path: Path, candidate: Path, require_native=False):
        """Verify a source plan and its entire immutable candidate as one fixture."""
        plan, _sources = self.plan(path)
        result = self.validate(candidate, require_native=require_native)
        metadata = load_json(candidate / "candidate.json")
        require(metadata["planSha256"] == digest(read_bytes(path)),
                "Fixture candidate was not built from the supplied source plan")
        aggregate = fingerprint({
            "schemaVersion": 1,
            "compilerVersion": metadata["compilerVersion"],
            "planSha256": metadata["planSha256"],
            "sourceHashes": {role: plan["sources"][role]["sha256"] for role in sorted(plan["sources"])},
            "candidateContentSha256": metadata["contentSha256"],
        })
        return {**result, "fixtureFingerprint": aggregate}

    def review(self, path=None, candidate=None, stage="final", approve=False, reviewer=None,
               notes="", no_launch=False):
        if stage == "keyposes":
            require(path is not None and candidate is None, "Keypose review requires --plan only")
            plan, sources = self.plan(path)
            binding = self.keypose_binding(plan)
            destination = path.parent / "keypose-review.json"
            preview = {"stage": stage, "binding": binding, "sources": {role: str(sources[role]) for role in plan["keyposes"]}}
        else:
            require(candidate is not None and path is None, "Final review requires --candidate only")
            self.validate(candidate)
            metadata = load_json(candidate / "candidate.json")
            binding = {"assetId": metadata["assetId"], "revision": metadata["revision"],
                       "contentSha256": metadata["contentSha256"]}
            destination = candidate.parent / (candidate.name + ".final-review.json")
            preview = {"stage": stage, "candidate": str(candidate), "binding": binding}
        if approve:
            if stage == "final":
                review_kind = metadata["kind"]
                review_manifest = load_json(candidate / "arena.json") if review_kind == "arena" else {}
                needs_3d_review = review_kind in ("environment", "habitat") or \
                    (review_kind == "arena" and "environment" in review_manifest)
                if needs_3d_review:
                    self.validate(candidate, require_native=True)
                    expected = {"environment": "environment.tres", "habitat": "habitat.tres",
                                "arena": "arena.tres"}[review_kind]
                    require((candidate / expected).is_file(),
                            "Sprite-in-3D final approval requires its renderable native resource")
            require(isinstance(reviewer, str) and reviewer.strip(), "Explicit approval requires --reviewer")
            require(isinstance(notes, str) and notes.strip(), "Explicit approval requires --notes describing the human decision")
            receipt = {"schemaVersion": 1, "stage": stage, "decision": "approved", "binding": binding,
                       "reviewer": reviewer.strip(), "reviewedAt": datetime.now(timezone.utc).isoformat(), "notes": notes}
            if destination.exists():
                previous = load_json(destination)
                require(previous.get("binding") == binding and previous.get("decision") == "approved", "Existing receipt differs; use a new revision")
                return {"receipt": str(destination), **previous}
            write_json(self.root, destination, receipt)
            return {"receipt": str(destination), **receipt}
        if candidate is not None and not no_launch:
            subprocess.Popen([self.godot, "--path", str(self.root), "res://scenes/asset_review_scene.tscn",
                              "--", "--asset-review", "--candidate", str(candidate)])
            preview["launched"] = True
        preview["approval"] = "pending; no approval receipt was created"
        return preview

    def promote(self, candidate: Path, receipt: Path):
        self.validate(candidate, require_native=True)
        metadata = load_json(candidate / "candidate.json")
        review = load_json(receipt.absolute())
        binding = {key:metadata[key] for key in ("assetId", "revision", "contentSha256")}
        require(review.get("schemaVersion") == 1 and review.get("stage") == "final" and
                review.get("decision") == "approved" and review.get("binding") == binding and
                review.get("reviewer") and review.get("reviewedAt") and review.get("notes"),
                "Final human approval is missing or bound to different content")
        destination = safe_path(self.generated_root, self.generated_root / metadata["assetId"] / metadata["revision"])
        catalog_path = self.root / "assets" / "runtime-catalog.json"
        lock_path = self.root / "assets" / ".runtime-catalog.lock"
        safe_path(self.root, lock_path)
        lock_path.parent.mkdir(parents=True, exist_ok=True)
        fd = os.open(str(lock_path), os.O_CREAT | os.O_RDWR | getattr(os, "O_NOFOLLOW", 0), 0o600)
        with os.fdopen(fd, "a+") as lock:
            fcntl.flock(lock.fileno(), fcntl.LOCK_EX)
            if destination.exists():
                existing = load_json(destination / "candidate.json")
                require(existing.get("contentSha256") == metadata["contentSha256"] and
                        tree_hashes(destination) == metadata["files"], "Immutable promoted revision already differs")
            else:
                staging = destination.parent / (".promote-" + uuid4().hex)
                safe_path(self.root, staging)
                staging.mkdir(parents=True)
                try:
                    for relative in sorted(metadata["files"]):
                        source = safe_path(candidate, candidate / relative)
                        raw = read_bytes(source)
                        require(digest(raw) == metadata["files"][relative], "Candidate changed during promotion")
                        write_bytes(self.root, staging / relative, raw)
                    write_json(self.root, staging / "candidate.json", metadata)
                    require(tree_hashes(staging) == metadata["files"], "Promoted copy did not verify")
                    os.rename(str(staging), str(destination))
                    sync_dir(destination.parent)
                finally:
                    if staging.exists():
                        shutil.rmtree(staging)
            catalog = load_json(catalog_path) if catalog_path.exists() else {"schemaVersion": 1, "assets": {}}
            require(catalog.get("schemaVersion") == 1 and isinstance(catalog.get("assets"), dict), "Invalid runtime catalog")
            # Keep final approval evidence outside ignored work and outside the
            # immutable hashed artifact tree (avoids a self-referential hash).
            review_archive = self.root / metadata["sourcePlan"]
            review_archive = review_archive.parent / "reviews" / (metadata["contentSha256"][7:] + ".json")
            safe_path(self.source_root, review_archive)
            if review_archive.exists():
                previous = load_json(review_archive)
                require(previous.get("binding") == binding and previous.get("decision") == "approved",
                        "Archived review evidence differs")
            else:
                write_json(self.root, review_archive, review)
            catalog["assets"][metadata["assetId"]] = {**binding, "kind": metadata["kind"],
                                                       "path": destination.relative_to(self.root).as_posix(),
                                                       "review": review_archive.relative_to(self.root).as_posix()}
            write_json(self.root, catalog_path, catalog, replace=True)
        return {"promoted": str(destination), "catalog": str(catalog_path), **binding}


def template(asset_id, revision, kind, provider):
    plan = {"schemaVersion": 1, "assetId": asset_id, "revision": revision, "kind": kind,
            "provider": provider, "sources": {}, "keyposes": [],
            "provenance": {"kind": "hand-authored" if provider == "manual" else "generated"},
            "generation": {"brief": "Describe this asset, its identity references, and visual constraints.", "jobs": []}}
    if kind == "animation":
        plan.update(subjectId=asset_id, canvas=[128, 128], requiredFacings=FACINGS[:], requiredActions=ACTIONS[:],
                    clips={}, fallbacks={}, paddingPx=2, extrudePx=1)
        for facing in FACINGS:
            plan["keyposes"].append("keypose." + facing.lower())
        for action in ACTIONS:
            for facing in FACINGS:
                clip_id = action + "." + facing.lower()
                plan["clips"][clip_id] = {"semanticAction": action,
                    "kind": "loop" if action in ("idle", "move", "guard") else "one-shot", "events": [],
                    "qualityProfile": "directional-combat", "frames": [{"source": clip_id + ".0000",
                    "durationMs": 100, "pivot": {"x": 0.5, "y": 0.9375},
                    "anchors": {"root": {"x": 0.5, "y": 0.9375}}}]}
    elif kind == "atlas":
        plan.update(entries={"sprite": {"source": "sprite"}}, paddingPx=2, extrudePx=1)
    elif kind == "tileset":
        plan.update(textureSource="texture", keyposes=["sample"], tileset={"projection": "square", "tileSize": [32, 32],
            "tiles": [{"atlas": [0, 0], "alternative": 0, "terrainSet": -1, "terrain": -1, "terrainPeering": {},
                       "probability": 1, "collision": [], "navigation": [], "occlusion": [], "customData": {}}],
            "terrains": [], "customDataLayers": []})
    elif kind == "arena":
        plan["arena"] = {"projection": "square", "ground": {"width": 640, "height": 480, "cellSize": 20},
                         "maxBodyRadius": 16, "spawns": {"player": [100, 240], "opponent": [540, 240]},
                         "obstacles": [], "tiles": []}
    elif kind == "environment":
        plan["keyposes"] = ["sample"]
        viewpoints = {
            "center": [[20, 24, 38], [20, 0, 24]], "left": [[12, 24, 38], [20, 0, 24]],
            "right": [[28, 24, 38], [20, 0, 24]], "near": [[20, 18, 31], [20, 0, 20]],
            "far": [[20, 31, 48], [20, 0, 24]]}
        plan["environment"] = {
            "presentationProfile": deepcopy(PRESENTATION_PROFILE),
            "license": {"classification": "private-prototype-only",
                        "notice": "Private prototype only; do not redistribute or publish source-derived art."},
            "worldScale": {"pixelsPerUnit": 32},
            "camera": {"projection": "perspective", "fovDegrees": 28, "pitchDegrees": 50,
                       "keepAspect": "width", "spriteTiltDegrees": 8, "near": 0.1, "far": 100,
                       "groundDistance": 12, "smoothingSpeed": 5,
                       "dollyBounds": [2, 60],
                       "movementBounds": [0, 0, 1280, 1536]},
            "terrainChunks": [{"id": "ground", "source": "ground", "groundRect": [0, 0, 1280, 1536],
                               "elevation": 0, "subdivisions": [10, 12], "alphaMode": "opaque",
                               "depthBehavior": "write"}],
            "spritePlanes": [{"id": "prop.front", "source": "prop.front", "pivot": {"x": 0.5, "y": 1.0},
                              "localPosition": [0, 0, 0], "rotationDegrees": [0, 0, 0],
                              "pixelSize": 0.03125, "alphaMode": "alpha-cut", "depthBehavior": "write"}],
            "groundFootprints": [{"id": "prop.footprint", "rect": [-16, -8, 32, 16]}],
            "navigationProfiles": [{"id": "solid", "movement": True, "waste": True, "decoration": True}],
            "planeStacks": [{"id": "prop.stack", "planes": ["prop.front"],
                             "groundFootprint": "prop.footprint", "navigation": "solid"}],
            "ambientPlanes": [],
            "reviewViewpoints": [{"id": name, "position": points[0], "lookAt": points[1]}
                                   for name, points in viewpoints.items()]}
    elif kind == "habitat":
        plan["habitat"] = {
            "environment": {"assetId": asset_id + "-environment", "revision": revision},
            "grid": {"columns": 40, "rows": 48, "cellSize": 32},
            "blockers": [], "spawn": [20, 24],
            "wasteAnchors": [[8, 20], [20, 28], [32, 20]],
            "decorationZones": [{"id": "main", "rect": [1, 1, 38, 46]}],
            "staticPlacements": []}
    return plan
