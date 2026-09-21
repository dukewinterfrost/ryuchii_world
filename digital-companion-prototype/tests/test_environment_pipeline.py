"""Environment/habitat v1 compiler and dependency contract tests."""

from copy import deepcopy
from contextlib import nullcontext
from io import BytesIO
import sys
from pathlib import Path
import os
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch

from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
from sprite_pipeline.common import PipelineError, digest, fingerprint, load_json, tree_hashes, write_json
from sprite_pipeline.pipeline import MAX_ENVIRONMENT_NATIVE_BYTES, Pipeline, template
from sprite_pipeline.validation import (validate_arena, validate_arena_environment_placements, validate_environment,
                                        validate_habitat, validate_plan)


def png(color=(48, 112, 60, 255)):
    image = Image.new("RGBA", (16, 16), color)
    stream = BytesIO()
    image.save(stream, "PNG")
    return stream.getvalue()


class EnvironmentPipelineTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name).resolve()
        self.pipeline = Pipeline(self.root)
        self.source = self.root / "input.png"
        self.source.write_bytes(png())

    def tearDown(self):
        self.temp.cleanup()

    def save_plan(self, plan):
        path = self.root / "assets-source" / plan["assetId"] / plan["revision"] / "source-plan.json"
        write_json(self.root, path, plan, replace=path.exists())
        return path

    def ingest_environment(self, path):
        for role in ("sample", "ground", "prop.front"):
            self.pipeline.ingest(path, self.source, role)
        self.pipeline.review(path=path, stage="keyposes", approve=True, reviewer="Fixture reviewer",
                             notes="Synthetic environment sample approved for an isolated test")

    def native_compile(self, path):
        exporter = self.root / "scripts/assets/export_resources.gd"
        exporter.parent.mkdir(parents=True, exist_ok=True)
        exporter.write_text("# Native export test double")

        def export(command, **_kwargs):
            staging = Path(command[command.index("--candidate") + 1])
            kind = load_json(staging / "candidate.json")["kind"]
            output = {"environment": "environment.tres", "habitat": "habitat.tres", "arena": "arena.tres"}[kind]
            (staging / output).write_text('[gd_resource type="Resource" format=3]\n[resource]\n')
            return subprocess.CompletedProcess(command, 0, "ok", "")

        with patch("sprite_pipeline.pipeline.subprocess.run", side_effect=export):
            return Path(self.pipeline.compile(path)["candidate"])

    def approve_and_promote(self, candidate, real_native_probe=False):
        # Most tests isolate Python dependency/promotion behavior. Installed-
        # Godot integration below exercises the real native probe; this named
        # test double cannot turn a dummy resource into accepted evidence.
        context = nullcontext() if real_native_probe else \
            patch.object(self.pipeline, "_probe_native_resource", return_value=None)
        with context:
            receipt = self.pipeline.review(candidate=candidate, approve=True, reviewer="Fixture reviewer",
                                           notes="Synthetic final approval for an isolated test")
            return Path(self.pipeline.promote(candidate, Path(receipt["receipt"]))["promoted"])

    def promoted_environment(self):
        plan = template("green-shade-environment", "v1", "environment", "manual")
        path = self.save_plan(plan)
        self.ingest_environment(path)
        candidate = self.native_compile(path)
        return plan, self.approve_and_promote(candidate)

    def test_environment_template_is_explicit_private_sprite_in_3d_contract(self):
        plan = template("green-shade-environment", "v1", "environment", "manual")
        validate_plan(plan)
        environment = plan["environment"]
        self.assertEqual(environment["license"]["classification"], "private-prototype-only")
        self.assertEqual(environment["worldScale"], {"pixelsPerUnit": 32})
        self.assertEqual(environment["camera"]["projection"], "perspective")
        self.assertEqual(environment["camera"]["keepAspect"], "width")
        self.assertEqual({view["id"] for view in environment["reviewViewpoints"]},
                         {"center", "left", "right", "near", "far"})
        self.assertEqual(validate_environment(environment)["planeStacks"], 1)

    def test_environment_rejects_implicit_license_and_visual_geometry_inference(self):
        environment = template("green-shade-environment", "v1", "environment", "manual")["environment"]
        del environment["license"]
        with self.assertRaisesRegex(PipelineError, "license classification"):
            validate_environment(environment)
        environment = template("green-shade-environment", "v1", "environment", "manual")["environment"]
        del environment["planeStacks"][0]["groundFootprint"]
        with self.assertRaisesRegex(PipelineError, "groundFootprint"):
            validate_environment(environment)
        environment = template("green-shade-environment", "v1", "environment", "manual")["environment"]
        environment["planeStacks"][0]["navigation"] = "inferred-from-alpha"
        with self.assertRaisesRegex(PipelineError, "navigation reference"):
            validate_environment(environment)

    def test_environment_compile_binds_textures_and_emits_pending_review_metadata(self):
        plan = template("green-shade-environment", "v1", "environment", "manual")
        path = self.save_plan(plan)
        for role in ("ground", "prop.front"):
            self.pipeline.ingest(path, self.source, role)
        with self.assertRaisesRegex(PipelineError, "Approve keyposes"):
            self.pipeline.compile(path, native=False)
        self.pipeline.ingest(path, self.source, "sample")
        self.pipeline.review(path=path, stage="keyposes", approve=True, reviewer="Fixture reviewer",
                             notes="Synthetic sample approval for an isolated test")
        candidate = Path(self.pipeline.compile(path, native=False)["candidate"])
        environment = load_json(candidate / "environment.json")
        self.assertEqual(environment["textures"], {
            "ground": "textures/ground.png", "prop.front": "textures/prop.front.png"})
        self.assertTrue((candidate / "textures/ground.png").is_file())
        metadata = load_json(candidate / "candidate.json")
        self.assertEqual(metadata["nativeDependencies"], {
            relative: metadata["files"][relative]
            for relative in environment["textures"].values()})
        review = load_json(candidate / "environment-review.json")
        self.assertEqual(review["status"], "pending-human-review")
        self.assertFalse(list(candidate.parent.glob("*.final-review.json")))
        self.pipeline.validate(candidate)

    def test_habitat_compile_requires_and_hash_pins_promoted_environment(self):
        _plan, promoted = self.promoted_environment()
        habitat = template("green-shade-home", "v1", "habitat", "manual")
        habitat["habitat"]["environment"] = {"assetId": "green-shade-environment", "revision": "v1"}
        path = self.save_plan(habitat)
        candidate = self.native_compile(path)
        compiled = load_json(candidate / "habitat.json")
        self.assertTrue(compiled["environment"]["contentSha256"].startswith("sha256:"))
        self.assertEqual(compiled["environment"]["contentSha256"],
                         load_json(promoted / "candidate.json")["contentSha256"])
        self.assertEqual(load_json(candidate / "habitat-review.json")["status"], "pending-human-review")
        self.pipeline.validate(candidate)
        promoted_habitat = self.approve_and_promote(candidate)
        self.assertTrue((promoted_habitat / "habitat.tres").is_file())
        catalog = load_json(self.root / "assets/runtime-catalog.json")
        self.assertEqual(catalog["assets"]["green-shade-home"]["kind"], "habitat")

    def test_habitat_rejects_missing_or_stale_environment_pin(self):
        habitat = template("missing-home", "v1", "habitat", "manual")
        path = self.save_plan(habitat)
        with self.assertRaisesRegex(PipelineError, "promoted"):
            self.pipeline.compile(path, native=False)
        self.promoted_environment()
        habitat = template("green-shade-home", "v1", "habitat", "manual")
        habitat["habitat"]["environment"] = {"assetId": "green-shade-environment", "revision": "v1",
                                                "contentSha256": "sha256:" + "0" * 64}
        with self.assertRaisesRegex(PipelineError, "content changed"):
            self.pipeline.compile(self.save_plan(habitat), native=False)

    def test_habitat_grid_anchor_and_connectivity_contract(self):
        habitat = template("green-shade-home", "v1", "habitat", "manual")["habitat"]
        self.assertEqual(validate_habitat(habitat)["wasteAnchors"], 3)
        wrong_grid = deepcopy(habitat)
        wrong_grid["grid"]["columns"] = 39
        with self.assertRaisesRegex(PipelineError, "exactly 40x48"):
            validate_habitat(wrong_grid)
        blocked_anchor = deepcopy(habitat)
        blocked_anchor["blockers"] = [{"id": "waste-rock", "rect": [8, 20, 1, 1]}]
        with self.assertRaisesRegex(PipelineError, "Waste anchor is blocked"):
            validate_habitat(blocked_anchor)
        disconnected = deepcopy(habitat)
        disconnected["blockers"] = [{"id": "wall", "rect": [0, 25, 40, 1]}]
        with self.assertRaisesRegex(PipelineError, "unreachable|disconnected"):
            validate_habitat(disconnected)

    def test_static_visuals_require_separate_blocker_authority(self):
        environment = template("green-shade-environment", "v1", "environment", "manual")["environment"]
        habitat = template("green-shade-home", "v1", "habitat", "manual")["habitat"]
        habitat["staticPlacements"] = [{"id": "tree", "planeStack": "prop.stack", "cell": [4, 4],
                                         "rotationQuarterTurns": 0}]
        with self.assertRaisesRegex(PipelineError, "explicit habitat blocker"):
            validate_habitat(habitat, environment)
        habitat["blockers"] = [{"id": "tree-footprint", "rect": [4, 4, 1, 1]}]
        habitat["staticPlacements"][0]["blocker"] = "tree-footprint"
        self.assertEqual(validate_habitat(habitat, environment)["staticPlacements"], 1)

    def test_arena_can_pin_environment_without_changing_combat_geometry(self):
        self.promoted_environment()
        arena = template("green-shade-arena", "v1", "arena", "manual")
        arena["arena"]["environment"] = {"assetId": "green-shade-environment", "revision": "v1"}
        arena["arena"]["obstacles"] = [{"id": "tree-footprint", "rect": [294, 82, 32, 16],
                                          "movement": True, "projectile": True,
                                          "sight": False, "occlusion": True}]
        arena["arena"]["presentation"] = {"staticPlacements": [{"id": "tree", "planeStack": "prop.stack",
                                                                    "groundPosition": [310, 90],
                                                                    "rotationDegrees": 0,
                                                                    "obstacle": "tree-footprint"}]}
        candidate = Path(self.pipeline.compile(self.save_plan(arena), native=False)["candidate"])
        compiled = load_json(candidate / "arena.json")
        self.assertTrue(compiled["environment"]["contentSha256"].startswith("sha256:"))
        self.assertEqual(compiled["obstacles"], arena["arena"]["obstacles"])
        self.pipeline.validate(candidate)

    def test_plane_crop_is_source_bounded_and_provenance_is_sanitized(self):
        plan = template("cropped-environment", "v1", "environment", "manual")
        plan["environment"]["spritePlanes"][0]["sourceRegionPx"] = [2, 3, 8, 7]
        unsafe = deepcopy(plan)
        unsafe["provenance"] = {"kind": "hand-authored", "originalPath": "/Users/private/author/file.png"}
        with self.assertRaisesRegex(PipelineError, "absolute filesystem paths"):
            validate_plan(unsafe)
        for unsafe_path in ("/Users/private/author/file.png", "~/author/file.png",
                            "file:///private/author/file.png", r"\\server\share\file.png"):
            unsafe = deepcopy(plan)
            unsafe["generation"]["brief"] = {"nested": ["reference", "Use " + unsafe_path]}
            with self.subTest(unsafe_path=unsafe_path):
                with self.assertRaisesRegex(PipelineError, "absolute filesystem paths"):
                    validate_plan(unsafe)
        unsafe = deepcopy(plan)
        unsafe["generation"]["metadata"] = {"/private/author/key": "also reject dictionary keys"}
        with self.assertRaisesRegex(PipelineError, "absolute filesystem paths"):
            validate_plan(unsafe)
        unsafe = deepcopy(plan)
        unsafe["sources"]["ground"] = {"path": "C:\\private\\ground.png", "sha256": "sha256:" + "0" * 64}
        with self.assertRaisesRegex(PipelineError, "absolute filesystem paths"):
            validate_plan(unsafe)
        plan["provenance"] = {"kind": "source-derived", "sourceCollection": "private-test-fixture"}
        plan["generation"]["brief"] = "Method notes: https://example.invalid/environment-authoring"
        path = self.save_plan(plan)
        self.ingest_environment(path)
        candidate = Path(self.pipeline.compile(path, native=False)["candidate"])
        compiled = load_json(candidate / "environment.json")
        self.assertEqual(compiled["spritePlanes"][0]["sourceRegionPx"], [2, 3, 8, 7])
        self.assertEqual(compiled["provenance"]["kind"], "source-derived")
        self.assertNotIn("sourceCollection", compiled["provenance"])
        self.assertNotIn("/Users/", candidate.joinpath("environment.json").read_text())
        self.assertEqual(compiled["provenance"]["sourceHashes"], {
            role: binding["sha256"] for role, binding in load_json(path)["sources"].items()})

        invalid = template("bad-crop", "v1", "environment", "manual")
        invalid["environment"]["spritePlanes"][0]["sourceRegionPx"] = [12, 12, 8, 8]
        invalid_path = self.save_plan(invalid)
        self.ingest_environment(invalid_path)
        with self.assertRaisesRegex(PipelineError, "outside its source texture"):
            self.pipeline.compile(invalid_path, native=False)

    def test_terrain_crop_is_deterministic_and_retains_original_hash_binding(self):
        pixels = Image.new("RGBA", (16, 16))
        for y in range(16):
            for x in range(16):
                pixels.putpixel((x, y), (x * 8, y * 8, x + y, 255 if (x + y) % 3 else 0))
        stream = BytesIO()
        pixels.save(stream, "PNG")
        self.source.write_bytes(stream.getvalue())
        plan = template("terrain-crop", "v1", "environment", "manual")
        plan["environment"]["terrainChunks"][0]["sourceRegionPx"] = [2, 3, 8, 7]
        path = self.save_plan(plan)
        self.ingest_environment(path)
        candidate = Path(self.pipeline.compile(path, native=False)["candidate"])
        compiled = load_json(candidate / "environment.json")
        chunk = compiled["terrainChunks"][0]
        self.assertEqual(chunk["source"], "ground")
        self.assertEqual(chunk["sourceRegionPx"], [2, 3, 8, 7])
        self.assertEqual(chunk["textureBinding"], "terrain.ground")
        self.assertEqual(compiled["textures"]["terrain.ground"], "textures/terrain.ground.png")
        self.assertEqual(compiled["provenance"]["sourceHashes"]["ground"],
                         load_json(path)["sources"]["ground"]["sha256"])
        with Image.open(candidate / "textures/terrain.ground.png") as derived:
            self.assertEqual(derived.size, (8, 7))
            actual = derived.convert("RGBA")
        expected = pixels.crop((2, 3, 10, 10))
        expected.putdata([(0, 0, 0, 0) if pixel[3] == 0 else pixel for pixel in expected.getdata()])
        self.assertEqual(actual.tobytes(), expected.tobytes())
        self.pipeline.validate(candidate)

    def test_environment_rejects_untruthful_alpha_depth_combinations(self):
        for alpha_mode, depth_behavior in (("opaque", "prepass"), ("alpha-cut", "prepass"),
                                           ("transparent", "write"), ("transparent", "test-only")):
            environment = template("depth-test", "v1", "environment", "manual")["environment"]
            environment["spritePlanes"][0].update(alphaMode=alpha_mode,
                                                    depthBehavior=depth_behavior)
            with self.subTest(alpha_mode=alpha_mode, depth_behavior=depth_behavior):
                with self.assertRaisesRegex(PipelineError, "requires depthBehavior|invalid depthBehavior"):
                    validate_environment(environment)
        environment = template("depth-test", "v1", "environment", "manual")["environment"]
        environment["spritePlanes"][0].update(alphaMode="transparent", depthBehavior="prepass",
                                                renderPriority=0)
        validate_environment(environment)
        environment["terrainChunks"][0]["depthBehavior"] = "test-only"
        with self.assertRaisesRegex(PipelineError, "invalid depthBehavior"):
            validate_environment(environment)

    def test_terrain_texture_binding_is_compiler_owned(self):
        environment = template("binding-test", "v1", "environment", "manual")["environment"]
        environment["terrainChunks"][0]["textureBinding"] = "spoofed.binding"
        with self.assertRaisesRegex(PipelineError, "compiler-owned"):
            validate_environment(environment)

    def test_fixed_card_v1_rejects_local_and_placement_y_rotation(self):
        environment = template("green-shade-environment", "v1", "environment", "manual")["environment"]
        environment["spritePlanes"][0]["rotationDegrees"] = [0, 90, 0]
        with self.assertRaisesRegex(PipelineError, "rotationDegrees.y must be 0"):
            validate_environment(environment)

        environment = template("green-shade-environment", "v1", "environment", "manual")["environment"]
        habitat = template("green-shade-home", "v1", "habitat", "manual")["habitat"]
        habitat["blockers"] = [{"id": "tree-footprint", "rect": [4, 4, 1, 1]}]
        habitat["staticPlacements"] = [{"id": "tree", "planeStack": "prop.stack", "cell": [4, 4],
                                         "rotationQuarterTurns": 1, "blocker": "tree-footprint"}]
        with self.assertRaisesRegex(PipelineError, "rotationQuarterTurns must be 0"):
            validate_habitat(habitat, environment)

        arena = template("green-shade-arena", "v1", "arena", "manual")["arena"]
        arena["environment"] = {"assetId": "green-shade-environment", "revision": "v1"}
        arena["obstacles"] = [{"id": "tree-footprint", "rect": [302, 74, 16, 32],
                               "movement": True, "projectile": True,
                               "sight": False, "occlusion": True}]
        arena["presentation"] = {"staticPlacements": [{"id": "tree", "planeStack": "prop.stack",
                                                         "groundPosition": [310, 90],
                                                         "rotationDegrees": 90,
                                                         "obstacle": "tree-footprint"}]}
        with self.assertRaisesRegex(PipelineError, "rotationDegrees must be 0"):
            validate_arena_environment_placements(arena, environment)

    def test_habitat_rejects_absolute_path_in_nested_authoring_metadata(self):
        habitat = template("portable-home", "v1", "habitat", "manual")
        habitat["generation"]["brief"] = {"notes": ["source", "/private/tmp/reference.png"]}
        with self.assertRaisesRegex(PipelineError, "absolute filesystem paths"):
            validate_plan(habitat)

    def test_every_plan_kind_rejects_obfuscated_nonportable_paths(self):
        cases = ("source:/Users/private/reference.png", "host:/private/tmp/reference.png",
                 "[C:/Users/private/reference.png]", "embedded=~/private/reference.png",
                 r"\\server\share\reference.png")
        for kind in ("environment", "habitat", "arena", "atlas"):
            for unsafe_path in cases:
                plan = template("portable-check", "v1", kind, "manual")
                plan["generation"]["brief"] = {"nested": [unsafe_path]}
                with self.subTest(kind=kind, unsafe_path=unsafe_path):
                    with self.assertRaisesRegex(PipelineError, "absolute filesystem paths"):
                        validate_plan(plan)

    def test_environment_bounds_honor_nonzero_movement_origin(self):
        environment = template("offset-environment", "v1", "environment", "manual")["environment"]
        environment["camera"]["movementBounds"] = [100, 200, 1280, 1536]
        environment["terrainChunks"][0]["groundRect"] = [100, 200, 1280, 1536]
        validate_environment(environment)
        environment["terrainChunks"][0]["groundRect"] = [0, 0, 1280, 1536]
        with self.assertRaisesRegex(PipelineError, "movementBounds"):
            validate_environment(environment)

    def test_environment_profile_counts_and_transparent_priority_are_bounded(self):
        environment = template("bounded-environment", "v1", "environment", "manual")["environment"]
        environment["presentationProfile"]["fovDegrees"] = 29
        with self.assertRaisesRegex(PipelineError, "presentationProfile"):
            validate_environment(environment)
        environment = template("bounded-environment", "v1", "environment", "manual")["environment"]
        transparent = deepcopy(environment["spritePlanes"][0])
        transparent.update(id="mist", alphaMode="transparent", depthBehavior="prepass")
        environment["spritePlanes"].append(transparent)
        with self.assertRaisesRegex(PipelineError, "renderPriority"):
            validate_environment(environment)
        environment["spritePlanes"][-1]["renderPriority"] = 17
        with self.assertRaisesRegex(PipelineError, "renderPriority"):
            validate_environment(environment)
        environment["spritePlanes"][-1]["renderPriority"] = 4
        validate_environment(environment)
        environment["terrainChunks"] *= 65
        with self.assertRaisesRegex(PipelineError, "count is outside limits"):
            validate_environment(environment)

    def test_all_environment_node_and_placement_counts_are_bounded(self):
        environment = template("bounded-environment", "v1", "environment", "manual")["environment"]
        environment["spritePlanes"] = [
            dict(deepcopy(environment["spritePlanes"][0]), id="plane-%03d" % index)
            for index in range(513)]
        with self.assertRaisesRegex(PipelineError, "spritePlanes count"):
            validate_environment(environment)

        environment = template("bounded-environment", "v1", "environment", "manual")["environment"]
        environment["planeStacks"] = [
            dict(deepcopy(environment["planeStacks"][0]), id="stack-%03d" % index)
            for index in range(257)]
        with self.assertRaisesRegex(PipelineError, "planeStacks count"):
            validate_environment(environment)

        environment = template("bounded-environment", "v1", "environment", "manual")["environment"]
        ambient = dict(deepcopy(environment["spritePlanes"][0]), source="prop.front",
                       alphaMode="transparent", depthBehavior="prepass", renderPriority=-1,
                       parallax=0.5)
        ambient["position"] = ambient.pop("localPosition")
        environment["ambientPlanes"] = [dict(deepcopy(ambient), id="ambient-%03d" % index)
                                        for index in range(65)]
        with self.assertRaisesRegex(PipelineError, "ambientPlanes count"):
            validate_environment(environment)

        habitat = template("bounded-habitat", "v1", "habitat", "manual")["habitat"]
        habitat["staticPlacements"] = [
            {"id": "placement-%03d" % index, "planeStack": "prop.stack", "cell": [1, 1],
             "rotationQuarterTurns": 0} for index in range(513)]
        with self.assertRaisesRegex(PipelineError, "bounded array"):
            validate_habitat(habitat)

        arena = template("bounded-arena", "v1", "arena", "manual")["arena"]
        arena["environment"] = {"assetId": "bounded-environment", "revision": "v1"}
        arena["presentation"] = {"staticPlacements": [
            {"id": "placement-%03d" % index, "planeStack": "prop.stack",
             "groundPosition": [1, 1], "rotationDegrees": 0} for index in range(257)]}
        with self.assertRaisesRegex(PipelineError, "presentation.staticPlacements"):
            validate_arena(arena)

    def test_known_digimonup_hash_cannot_claim_commercial_clearance(self):
        plan = template("restricted-environment", "v1", "environment", "manual")
        plan["sources"]["ground"] = {
            "path": "sources/known.png",
            "sha256": "sha256:8697886e9bab1bd9fbc3e71916f7aafd0ab0302fc6db1ad006b4584055f111c9",
        }
        plan["environment"]["license"] = {
            "classification": "commercial-use-cleared", "notice": "Incorrect test claim"}
        with self.assertRaisesRegex(PipelineError, "Known DigimonUP.*private-prototype-only"):
            validate_plan(plan)
        derivative = template("restricted-derivative", "v1", "atlas", "manual")
        derivative["sources"]["sprite"] = {
            "path": "sources/derived.png",
            "sha256": "sha256:7f89c24546a0e33210c75b49a49cf204184d999e40e3084542b322d2f91611e6",
        }
        derivative["license"] = {
            "classification": "public-domain", "notice": "Incorrect derivative test claim"}
        with self.assertRaisesRegex(PipelineError, "Known DigimonUP.*private-prototype-only"):
            validate_plan(derivative)

    def test_candidate_rejects_source_texture_substitution_even_if_resigned(self):
        plan = template("substitution-environment", "v1", "environment", "manual")
        path = self.save_plan(plan)
        self.ingest_environment(path)
        candidate = Path(self.pipeline.compile(path, native=False)["candidate"])
        (candidate / "textures/prop.front.png").write_bytes(png((220, 10, 10, 255)))
        metadata = load_json(candidate / "candidate.json")
        metadata["files"] = tree_hashes(candidate)
        metadata["contentSha256"] = fingerprint({
            key: value for key, value in metadata.items() if key not in ("sourcePlan", "contentSha256")})
        write_json(self.root, candidate / "candidate.json", metadata, replace=True)
        with self.assertRaisesRegex(PipelineError, "source-role texture differs"):
            self.pipeline.validate(candidate)

    def test_dummy_native_resource_cannot_satisfy_load_probe(self):
        plan = template("dummy-native-environment", "v1", "environment", "manual")
        path = self.save_plan(plan)
        self.ingest_environment(path)
        candidate = self.native_compile(path)
        self.assertTrue((candidate / "environment.tres").is_file())
        with self.assertRaisesRegex(PipelineError, "Native resource probe is unavailable|load/probe failed"):
            self.pipeline.validate(candidate, require_native=True)

    def test_environment_native_dependency_metadata_and_resource_size_are_bounded(self):
        plan = template("bounded-native-environment", "v1", "environment", "manual")
        path = self.save_plan(plan)
        self.ingest_environment(path)
        candidate = self.native_compile(path)
        metadata = load_json(candidate / "candidate.json")

        dependency_paths = sorted(metadata["nativeDependencies"])
        attacked = deepcopy(metadata)
        attacked["nativeDependencies"][dependency_paths[0]] = "sha256:" + "0" * 64
        attacked["contentSha256"] = fingerprint({
            key: value for key, value in attacked.items()
            if key not in ("sourcePlan", "contentSha256")})
        write_json(self.root, candidate / "candidate.json", attacked, replace=True)
        with self.assertRaisesRegex(PipelineError, "native dependency hashes"):
            self.pipeline.validate(candidate)

        oversized = deepcopy(metadata)
        (candidate / "environment.tres").write_bytes(b"x" * (MAX_ENVIRONMENT_NATIVE_BYTES + 1))
        oversized["files"] = tree_hashes(candidate)
        oversized["contentSha256"] = fingerprint({
            key: value for key, value in oversized.items()
            if key not in ("sourcePlan", "contentSha256")})
        write_json(self.root, candidate / "candidate.json", oversized, replace=True)
        with self.assertRaisesRegex(PipelineError, "compact native metadata limit"):
            self.pipeline.validate(candidate)

    def test_fixture_check_returns_aggregate_content_fingerprint(self):
        plan = template("fixture-environment", "v1", "environment", "manual")
        path = self.save_plan(plan)
        self.ingest_environment(path)
        candidate = Path(self.pipeline.compile(path, native=False)["candidate"])
        result = self.pipeline.fixture_check(path, candidate)
        self.assertTrue(result["fixtureFingerprint"].startswith("sha256:"))

    def test_green_shade_derived_tree_cards_reproduce_and_recipe_tamper_fails(self):
        project = Path(__file__).resolve().parents[1]
        source_path = project / "assets-source/environments/green-shade/spike/source-plan.json"
        source_plan, _sources = Pipeline(project).plan(source_path)
        self.assertEqual(set(source_plan["derivedImages"]),
                         {"tree_canopy", "tree_interior", "tree_facade"})

        copied_path = self.save_plan(source_plan)
        copied_path.parent.joinpath("sources").mkdir()
        for binding in source_plan["sources"].values():
            source = source_path.parent / binding["path"]
            destination = copied_path.parent / binding["path"]
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, destination)
        shutil.copy2(source_path.parent / "build-derived-tree-planes.py",
                     copied_path.parent / "build-derived-tree-planes.py")
        tampered = load_json(copied_path)
        tampered["derivedImages"]["tree_canopy"]["recipe"]["parameters"]["sourceCropPx"][0] += 1
        write_json(self.root, copied_path, tampered, replace=True)
        with self.assertRaisesRegex(PipelineError, "pixels do not reproduce"):
            self.pipeline.plan(copied_path)

    def test_sprite_in_3d_approval_requires_native_renderable_candidate(self):
        plan = template("review-environment", "v1", "environment", "manual")
        path = self.save_plan(plan)
        self.ingest_environment(path)
        candidate = Path(self.pipeline.compile(path, native=False)["candidate"])
        with self.assertRaisesRegex(PipelineError, "Native resources"):
            self.pipeline.review(candidate=candidate, approve=True, reviewer="Fixture reviewer",
                                 notes="Must not mint review for an unrenderable candidate")

    @unittest.skipUnless(os.environ.get("SPRITE_NATIVE_TESTS") == "1",
                         "Set SPRITE_NATIVE_TESTS=1 for installed Godot integration")
    def test_real_godot_exports_environment_and_habitat_resources(self):
        project = Path(__file__).resolve().parents[1]
        shutil.copytree(project / "assets" / "balance", self.root / "assets" / "balance", dirs_exist_ok=True)
        shutil.copytree(project / "scripts", self.root / "scripts")
        shutil.copytree(project / "scenes", self.root / "scenes")
        shutil.copytree(project / "shaders", self.root / "shaders")
        shutil.copy2(project / "project.godot", self.root / "project.godot")
        (self.root / "assets/habitat").mkdir(parents=True)
        (self.root / "assets/habitat/verdant-field.png").write_bytes(png())
        (self.root / "assets/enclosure").mkdir(parents=True)
        for texture in ("digi_potty.png", "campfire.png", "pond.png", "flame-loop.png"):
            (self.root / "assets/enclosure" / texture).write_bytes(png())
        imported = subprocess.run([self.pipeline.godot, "--headless", "--path", str(self.root), "--import",
                                   "--", "--test-mode"], capture_output=True, text=True, timeout=60)
        self.assertEqual(imported.returncode, 0, imported.stdout + imported.stderr)
        self.assertNotIn("SCRIPT ERROR", imported.stderr)

        environment = template("green-shade-environment", "v1", "environment", "manual")
        environment["environment"]["terrainChunks"][0]["sourceRegionPx"] = [0, 0, 8, 8]
        environment_path = self.save_plan(environment)
        for role, color in (("sample", (48, 112, 60, 255)),
                            ("ground", (22, 92, 44, 255)),
                            ("prop.front", (116, 62, 30, 255))):
            self.source.write_bytes(png(color))
            self.pipeline.ingest(environment_path, self.source, role)
        self.pipeline.review(path=environment_path, stage="keyposes", approve=True,
                             reviewer="Fixture reviewer",
                             notes="Synthetic environment sample approved for an isolated test")
        environment_candidate = Path(self.pipeline.compile(environment_path)["candidate"])
        self.assertTrue((environment_candidate / "environment.tres").is_file())
        self.assertLess((environment_candidate / "environment.tres").stat().st_size,
                        MAX_ENVIRONMENT_NATIVE_BYTES)
        native_text = (environment_candidate / "environment.tres").read_text()
        self.assertIn("environment_texture_paths", native_text)
        self.assertIn("environment_texture_hashes", native_text)
        self.assertNotIn("environment_textures", native_text)
        self.assertNotIn("ImageTexture", native_text)
        compiled_environment = load_json(environment_candidate / "environment.json")
        self.assertEqual(compiled_environment["terrainChunks"][0]["textureBinding"], "terrain.ground")
        self.assertEqual(compiled_environment["textures"]["terrain.ground"], "textures/terrain.ground.png")
        original_native_export = (environment_candidate / "environment.tres").read_bytes()
        reexported = subprocess.run([
            self.pipeline.godot, "--headless", "--path", str(self.root), "--script",
            "res://scripts/assets/export_resources.gd", "--", "--asset-review",
            "--candidate", str(environment_candidate)], capture_output=True, text=True, timeout=60)
        self.assertEqual(reexported.returncode, 0, reexported.stdout + reexported.stderr)
        self.assertEqual((environment_candidate / "environment.tres").read_bytes(),
                         original_native_export)

        # The native probe must exercise every external dependency rather than
        # merely accepting a loadable .tres and self-asserted candidate flag.
        texture_paths = compiled_environment["textures"]
        ground_path = environment_candidate / texture_paths["ground"]
        prop_path = environment_candidate / texture_paths["prop.front"]
        ground_bytes, prop_bytes = ground_path.read_bytes(), prop_path.read_bytes()
        ground_path.unlink()
        with self.assertRaisesRegex(PipelineError, "load/probe failed"):
            self.pipeline._probe_native_resource(environment_candidate,
                                                 load_json(environment_candidate / "candidate.json"))
        ground_path.write_bytes(ground_bytes)
        ground_path.write_bytes(prop_bytes)
        prop_path.write_bytes(ground_bytes)
        with self.assertRaisesRegex(PipelineError, "load/probe failed"):
            self.pipeline._probe_native_resource(environment_candidate,
                                                 load_json(environment_candidate / "candidate.json"))
        ground_path.write_bytes(ground_bytes)
        prop_path.write_bytes(png((250, 4, 220, 255)))
        with self.assertRaisesRegex(PipelineError, "load/probe failed"):
            self.pipeline._probe_native_resource(environment_candidate,
                                                 load_json(environment_candidate / "candidate.json"))
        prop_path.write_bytes(prop_bytes)
        self.pipeline.validate(environment_candidate, require_native=True)

        # A self-consistently re-signed candidate containing a dummy .tres must
        # still fail because approval asks Godot to load and inspect the file.
        native_path = environment_candidate / "environment.tres"
        original_native = native_path.read_bytes()
        original_metadata = load_json(environment_candidate / "candidate.json")
        native_path.write_text("not a Godot resource")
        attacked_metadata = deepcopy(original_metadata)
        attacked_metadata["files"] = tree_hashes(environment_candidate)
        attacked_metadata["contentSha256"] = fingerprint({
            key: value for key, value in attacked_metadata.items()
            if key not in ("sourcePlan", "contentSha256")})
        write_json(self.root, environment_candidate / "candidate.json", attacked_metadata, replace=True)
        with self.assertRaisesRegex(PipelineError, "load/probe failed"):
            self.pipeline.validate(environment_candidate, require_native=True)
        native_path.write_bytes(original_native)
        write_json(self.root, environment_candidate / "candidate.json", original_metadata, replace=True)

        promoted = self.approve_and_promote(environment_candidate, real_native_probe=True)
        self.assertIn("environment_manifest", (promoted / "environment.tres").read_text())
        self.assertIn("environment_texture_paths", (promoted / "environment.tres").read_text())
        self.assertNotIn("ImageTexture", (promoted / "environment.tres").read_text())

        habitat = template("green-shade-home", "v1", "habitat", "manual")
        habitat["habitat"]["environment"] = {"assetId": "green-shade-environment", "revision": "v1"}
        habitat_candidate = Path(self.pipeline.compile(self.save_plan(habitat))["candidate"])
        self.assertTrue((habitat_candidate / "habitat.tres").is_file())
        self.assertIn("habitat_manifest", (habitat_candidate / "habitat.tres").read_text())

        # Package the real full-resolution Green Shade development fixture
        # without creating any approval receipt or catalog entry.
        green_source = project / "tests/fixtures/environments/green-shade-3d-spike"
        green_candidate = self.root / "work/green-shade-native-dev"
        shutil.copytree(green_source / "textures", green_candidate / "textures",
                        ignore=shutil.ignore_patterns("*.import"))
        shutil.copy2(green_source / "environment.json", green_candidate / "environment.json")
        green_manifest = load_json(green_candidate / "environment.json")
        green_dependencies = {
            relative: digest((green_candidate / relative).read_bytes())
            for relative in green_manifest["textures"].values()
        }
        green_metadata = {
            "schemaVersion": 1, "kind": "environment",
            "assetId": green_manifest["assetId"], "revision": green_manifest["revision"],
            "compilerVersion": "native-package-dev-check-v1",
            "planSha256": "sha256:" + "1" * 64,
            "buildIdentity": "sha256:" + "2" * 64,
            "sourceHashes": green_manifest["provenance"]["sourceHashes"],
            "nativeResources": False, "nativeDependencies": green_dependencies, "files": {},
        }
        write_json(self.root, green_candidate / "candidate.json", green_metadata)
        exported = subprocess.run([
            self.pipeline.godot, "--headless", "--path", str(self.root), "--script",
            "res://scripts/assets/export_resources.gd", "--", "--asset-review",
            "--candidate", str(green_candidate)], capture_output=True, text=True, timeout=60)
        self.assertEqual(exported.returncode, 0, exported.stdout + exported.stderr)
        self.assertNotIn("SCRIPT ERROR", exported.stderr)
        green_metadata["nativeResources"] = True
        green_metadata["files"] = tree_hashes(
            green_candidate, payload_files=list(green_manifest["textures"].values()))
        green_metadata["contentSha256"] = fingerprint({
            key: value for key, value in green_metadata.items() if key != "sourcePlan"})
        write_json(self.root, green_candidate / "candidate.json", green_metadata, replace=True)
        green_native_bytes = (green_candidate / "environment.tres").stat().st_size
        green_payload_bytes = sum((green_candidate / relative).stat().st_size
                                  for relative in green_manifest["textures"].values())
        print("GREEN_SHADE_NATIVE_SIZE_BYTES=%d EXTERNAL_TEXTURE_BYTES=%d" %
              (green_native_bytes, green_payload_bytes))
        self.assertLess(green_native_bytes, MAX_ENVIRONMENT_NATIVE_BYTES)
        self.assertNotIn("ImageTexture", (green_candidate / "environment.tres").read_text())
        self.pipeline._probe_native_resource(green_candidate, green_metadata)


if __name__ == "__main__":
    unittest.main()
