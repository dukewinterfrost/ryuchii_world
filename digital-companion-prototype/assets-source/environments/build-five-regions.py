#!/usr/bin/env python3
"""Build the five non-promoted sprite-in-3D region development packages.

This is deliberately an offline authoring command. It hash-checks private
DigimonUP inputs, writes portable source plans, compiles deterministic crops,
exports native Godot resources, and produces pending-review fixtures. It never
creates review receipts, catalog entries, or promoted assets.
"""

from __future__ import annotations

import argparse
from copy import deepcopy
import importlib.util
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
from uuid import uuid4


HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(ROOT / "tools"))

from sprite_pipeline import VERSION  # noqa: E402
from sprite_pipeline.common import (  # noqa: E402
    digest,
    fingerprint,
    load_json,
    read_bytes,
    tree_hashes,
    write_bytes,
    write_json,
)
from sprite_pipeline.pipeline import Pipeline  # noqa: E402
from sprite_pipeline.validation import (  # noqa: E402
    PRESENTATION_PROFILE,
    validate_arena,
    validate_arena_environment_placements,
    validate_environment,
    validate_habitat,
    validate_plan,
)


REVISION = "2026-09-12.001"
DERIVATION_SCRIPT = HERE / "build-source-derived-cards.py"
LICENSE = {
    "classification": "private-prototype-only",
    "notice": "Private prototype only; do not redistribute or publish DigimonUP-derived art.",
}
REGIONS = {
    "green-shade": {
        "display": "Green Shade",
        "home": "canopy-clearing",
        "home_display": "Canopy Clearing",
        "arena": "rootbound-glade",
        "arena_display": "Rootbound Glade",
        "environment": "environment-green-shade",
        "background": "#142f35",
        "ground_crop": [0, 170, 2048, 390],
        "footprint": [-80, -48, 160, 96],
        "habitat_blocker": [4, 5, 5, 3],
        "habitat_cell": [6, 6],
        "arena_position": [480, 288],
        "source_files": {
            "ground": ("Green_Shade_Ground.png", "8697886e9bab1bd9fbc3e71916f7aafd0ab0302fc6db1ad006b4584055f111c9"),
            "top": ("Green_Shade_Top.png", "5e59100e91d4cb3802bda6de24dc1754709cd9853d3b3e46ebc1c2f6bbcb5622"),
            "feature": ("Green_Shade_Tree.png", "1a1a4e145f21f09199e3ed0afd6f63eb8851011d1bdc20855cb6e461f9b0c364"),
        },
    },
    "shellfish-beach": {
        "display": "Shellfish Beach",
        "home": "tidepool-camp",
        "home_display": "Tidepool Camp",
        "arena": "breaker-cove",
        "arena_display": "Breaker Cove",
        "environment": "environment-shellfish-beach",
        "background": "#187aa5",
        "ground_crop": [0, 219, 2048, 550],
        "footprint": [-240, -48, 480, 96],
        "habitat_blocker": [4, 5, 15, 3],
        "habitat_cell": [11, 6],
        "arena_position": [480, 240],
        "source_files": {
            "ground": ("Shellfish_Beach_Ground.png", "e4adf13337326fb76bbd021aa13967db86304492aa388e0fb5313731f386296b"),
            "top": ("Shellfish_Beach_Top.png", "d58d3fcc09b6fb1c2ab3d65de5c342b1d1bb026966f73ebff092f22a4643758e"),
            "feature": ("Shellfish_Beach_Rock.png", "5a9c24f75e729743710ea2c39bf23a8c4c8bd2d3d2196004794da1983ffb054e"),
        },
        "derived_cards": {
            "crop": [200, 0, 1660, 544], "output": [384, 192], "pixel_size": 0.018,
            "seeds": {"facade": [[1400, 300]], "interior": [[400, 300]], "roof": [[400, 300]]},
            "polygons": {"facade": [], "interior": [],
                         "roof": [[[210, 0], [820, 0], [820, 335], [210, 335]]]},
            "positions": {"facade": [0.0, 0.0, 0.08], "interior": [0.0, 0.0, 0.0],
                          "roof": [0.0, 0.15, -0.08]},
        },
        "feature_cards": [
            ([200, 0, 600, 544], [-4.0, 0.0, 0.06]),
            ([1100, 0, 800, 544], [4.0, 0.0, 0.0]),
            ([200, 0, 600, 544], [0.0, 0.15, -0.06]),
        ],
    },
    "toy-maze": {
        "display": "Toy Maze",
        "home": "wind-up-plaza",
        "home_display": "Wind-Up Plaza",
        "arena": "clockwork-maze",
        "arena_display": "Clockwork Maze",
        "environment": "environment-toy-maze",
        "background": "#b9ebef",
        "ground_crop": [0, 100, 1655, 500],
        "footprint": [-240, -48, 480, 96],
        "habitat_blocker": [12, 5, 15, 3],
        "habitat_cell": [19, 6],
        "arena_position": [480, 240],
        "source_files": {
            "ground": ("Toy Maze_Ground.png", "49ad21ab4993e00508ffcd48f43cf72ef27b5d3b23e2e4d252f729d73d0399bb"),
            "top": ("Toy Maze_Top.png", "0906718f9f27534f275c1c987d61073032d44df25f414dbb1dc2287c1fae82fc"),
            "feature": ("Toy Maze_Village2.png", "7fabc01d3071c247fd9564775c450315f2dfb1709e611d5a1969a201deb8bf0f"),
        },
        "derived_cards": {
            "crop": [0, 0, 1963, 834], "output": [512, 256], "pixel_size": 0.016,
            "seeds": {"facade": [[1000, 400]], "interior": [[1000, 400]], "roof": [[1000, 400]]},
            "polygons": {
                "facade": [[[550, 455], [1110, 445], [1370, 500], [1480, 650], [1480, 834], [520, 834], [520, 620]]],
                "interior": [[[570, 0], [1300, 0], [1400, 160], [1370, 655], [540, 655], [540, 170]]],
                "roof": [[[1280, 75], [1880, 75], [1880, 710], [1260, 710]]],
            },
            "positions": {"facade": [0.0, 0.0, 0.08], "interior": [0.0, 0.0, 0.0],
                          "roof": [0.0, 0.1, -0.08]},
        },
        "feature_cards": [
            ([0, 0, 1963, 834], [-4.0, 0.0, 0.06]),
            ([0, 0, 1963, 834], [4.0, 0.0, 0.0]),
            ([0, 0, 1963, 834], [0.0, 0.12, -0.06]),
        ],
    },
    "mechatropolis": {
        "display": "Mechatropolis",
        "home": "service-deck",
        "home_display": "Service Deck",
        "arena": "reactor-causeway",
        "arena_display": "Reactor Causeway",
        "environment": "environment-mechatropolis",
        "background": "#28343c",
        "ground_crop": [0, 237, 2048, 350],
        "footprint": [-144, -48, 288, 96],
        "habitat_blocker": [5, 5, 9, 3],
        "habitat_cell": [9, 6],
        "arena_position": [480, 240],
        "source_files": {
            "ground": ("Mechatropolis_Ground.png", "67fd2bf3f8801b96eff920b974f0f8161726747ef78e7015da987dfbe4b21219"),
            "top": ("Mechatropolis_Top.png", "2c6a9543d69168eb40553b28bb90f5baebc3dbe226375d90883dc539dd426464"),
            "feature": ("Mechatropolis_Deco.png", "2d28b4768a817d9a762e20d4c5c5bd59597f12177ab37681937c2ab90373741d"),
        },
        "derived_cards": {
            "crop": [0, 0, 1280, 262], "output": [384, 128], "pixel_size": 0.018,
            "seeds": {"facade": [[1000, 160]], "interior": [[100, 150]], "roof": [[1000, 160]]},
            "polygons": {"facade": [], "interior": [],
                         "roof": [[[900, 0], [1280, 0], [1280, 145], [900, 145]]]},
            "positions": {"facade": [0.0, 0.0, 0.08], "interior": [0.0, 0.0, 0.0],
                          "roof": [0.0, 0.12, -0.08]},
        },
        "feature_cards": [
            ([0, 0, 340, 262], [-3.0, 0.0, 0.06]),
            ([900, 0, 380, 262], [3.0, 0.0, 0.0]),
            ([0, 0, 340, 262], [0.0, 0.2, -0.06]),
        ],
    },
    "nephelis-abyss": {
        "display": "Nephelis Abyss",
        "home": "cloudfall-sanctuary",
        "home_display": "Cloudfall Sanctuary",
        "arena": "rift-platform",
        "arena_display": "Rift Platform",
        "environment": "environment-nephelis-abyss",
        "background": "#17335d",
        "ground_crop": [0, 156, 1431, 700],
        "footprint": [-272, -48, 544, 96],
        "habitat_blocker": [2, 5, 17, 3],
        "habitat_cell": [10, 6],
        "arena_position": [480, 240],
        "source_files": {
            "ground": ("Nephelis Abyss_Ground.png", "11efdf86077f25fd4787dbc3b46df8c1ca128dba5ddba0fd84e1d3b0c328ef28"),
            "top": ("Nephelis Abyss_Top.png", "a8e193044454c53314b67ae9aecd475929e14561cf3cf524dfb3796d28674089"),
            "feature": ("Nephelis Abyss_TopDeco.png", "9e6bfda1579eec0e74e5593c1bc2fe7f8da2294a78ab888616de6f5827e96c6d"),
        },
        "derived_cards": {
            "crop": [100, 0, 1850, 809], "output": [512, 256], "pixel_size": 0.017,
            "seeds": {"facade": [[1500, 300]], "interior": [[400, 300]], "roof": [[1500, 300]]},
            "polygons": {"facade": [], "interior": [],
                         "roof": [[[1080, 0], [1950, 0], [1950, 500], [1080, 500]]]},
            "positions": {"facade": [0.0, 0.0, 0.08], "interior": [0.0, 0.0, 0.0],
                          "roof": [0.0, 0.12, -0.08]},
        },
        "feature_cards": [
            ([100, 0, 780, 809], [-5.0, 0.0, 0.06]),
            ([1080, 0, 868, 809], [5.0, 0.0, 0.0]),
            ([100, 0, 780, 809], [0.0, 0.15, -0.06]),
        ],
    },
}


def _verify_external(original: Path, expected: str) -> None:
    actual = digest(read_bytes(original))
    wanted = "sha256:" + expected
    if actual != wanted:
        raise RuntimeError(f"Source hash changed: {original.name}: {actual}, expected {wanted}")


def _load_card_builder():
    spec = importlib.util.spec_from_file_location("source_derived_cards", DERIVATION_SCRIPT)
    if spec is None or spec.loader is None:
        raise RuntimeError("Could not load deterministic source-card builder")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _archive_source(plan_dir: Path, payload: bytes) -> dict:
    value = digest(payload)
    destination = plan_dir / "sources" / (value[7:] + ".png")
    if destination.is_file():
        if digest(read_bytes(destination)) != value:
            raise RuntimeError("Immutable source archive content changed: " + destination.name)
    else:
        write_bytes(ROOT, destination, payload)
    return {"path": destination.relative_to(plan_dir).as_posix(), "sha256": value}


def _build_derived_cards(plan_dir: Path, parent_path: Path, parent_binding: dict,
                         card_spec: dict) -> tuple[dict, dict]:
    from PIL import Image

    module = _load_card_builder()
    local_script = plan_dir / "build-source-derived-cards.py"
    script_payload = read_bytes(DERIVATION_SCRIPT)
    if local_script.is_file():
        if read_bytes(local_script) != script_payload:
            write_bytes(ROOT, local_script, script_payload, replace=True)
    else:
        write_bytes(ROOT, local_script, script_payload)
    script_hash = digest(read_bytes(local_script))
    with Image.open(parent_path) as image:
        parent = image.convert("RGBA")
    source_bindings = {}
    derivations = {}
    common = {
        "profile": "source-component-depth-cards-v1",
        "sourceCropPx": card_spec["crop"],
        "outputSizePx": card_spec["output"],
        "paddingPx": 24,
        "resample": "box",
        "alphaThreshold": 128,
        "minimumOverlapPx": 0,
        "roleSeedsSourcePx": card_spec["seeds"],
        "roleClipPolygonsSourcePx": card_spec["polygons"],
    }
    for role in ("facade", "interior", "roof"):
        parameters = dict(common, role=role)
        output, selected = module.build_card(parent, parameters)
        if not selected:
            raise RuntimeError("Derived feature card selected no source pixels: " + role)
        payload = module.encode_png(output)
        output_role = "feature_" + role
        binding = _archive_source(plan_dir, payload)
        source_bindings[output_role] = binding
        derivations[output_role] = {
            "parentSource": "feature_original",
            "parentSha256": parent_binding["sha256"],
            "recipe": {
                "kind": "scripted-rgba-transform",
                "version": 1,
                "scriptPath": local_script.name,
                "scriptSha256": script_hash,
                "parameters": parameters,
            },
            "outputSha256": binding["sha256"],
        }
    return source_bindings, derivations


def _base_environment(region_id: str, spec: dict) -> dict:
    stack_id = region_id + "-landmark.stack"
    footprint_id = region_id + "-landmark.footprint"
    plane_ids = [region_id + "-landmark." + role for role in ("facade", "interior", "roof")]
    cards = spec["derived_cards"]
    planes = []
    for role, plane_id in zip(("facade", "interior", "roof"), plane_ids):
        planes.append({
            "id": plane_id,
            "source": "feature_" + role,
            "pivot": {"x": 0.5, "y": 1.0},
            "localPosition": cards["positions"][role],
            "rotationDegrees": [0, 0, 0],
            "pixelSize": cards["pixel_size"],
            "alphaMode": "alpha-cut",
            "depthBehavior": "write",
            "authoringStatus": "hash-bound-source-derived-card",
        })
    return {
        "regionId": region_id,
        "displayName": spec["display"],
        "developmentStatus": "source-derived-kit-pending-human-review",
        "presentationProfile": deepcopy(PRESENTATION_PROFILE),
        "license": deepcopy(LICENSE),
        "backgroundColor": spec["background"],
        "ambientColor": "#ffffff",
        "ambientEnergy": 1.0,
        "worldScale": {"pixelsPerUnit": 32},
        "camera": {
            "projection": "perspective",
            "fovDegrees": 28,
            "pitchDegrees": 50,
            "keepAspect": "width",
            "spriteTiltDegrees": 8,
            "near": 0.1,
            "far": 200,
            "groundDistance": 12,
            "dollyBounds": [2, 60],
            "smoothingSpeed": 5,
            "movementBounds": [0, 0, 1280, 1536],
        },
        "terrainChunks": [{
            "id": region_id + "-ground",
            "source": "ground",
            "sourceRegionPx": spec["ground_crop"],
            # Presentation terrain deliberately extends beyond the authoritative
            # 40x48 movement bounds. This keeps every fixed-axis review framing
            # on painted ground without enlarging gameplay/navigation space.
            "groundRect": [-512, -512, 2304, 2560],
            "elevation": 0,
            "subdivisions": [18, 20],
            "alphaMode": "opaque",
            "depthBehavior": "write",
        }],
        "spritePlanes": planes,
        "groundFootprints": [{"id": footprint_id, "rect": spec["footprint"]}],
        "navigationProfiles": [{
            "id": "solid",
            "movement": True,
            "waste": True,
            "decoration": True,
        }],
        "planeStacks": [{
            "id": stack_id,
            "planes": plane_ids,
            "groundFootprint": footprint_id,
            "navigation": "solid",
        }],
        # Full-width Top layers have opaque rectangular source boundaries. They
        # remain hash-bound style authority, but are not placed as Sprite3D
        # cards until a naturally terminated/occluded rear band is authored.
        "ambientPlanes": [],
        "reviewViewpoints": [
            {"id": "center", "position": [20, 26, 38], "lookAt": [20, 0, 24]},
            {"id": "left", "position": [14, 26, 38], "lookAt": [20, 0, 24]},
            {"id": "right", "position": [26, 26, 38], "lookAt": [20, 0, 24]},
            {"id": "near", "position": [20, 21, 33], "lookAt": [20, 0, 20]},
            {"id": "far", "position": [20, 31, 45], "lookAt": [20, 0, 24]},
        ],
    }


def _environment_plan(region_id: str, spec: dict, source_root: Path) -> tuple[Path, dict]:
    plan_dir = HERE / region_id / REVISION
    source_dir = plan_dir / "sources"
    for _role, (filename, expected) in spec["source_files"].items():
        _verify_external(source_root / filename, expected)
    from PIL import Image
    with Image.open(source_root / spec["source_files"]["top"][0]) as image:
        spec["top_size"] = list(image.size)
    if region_id == "green-shade":
        spike_dir = HERE / "green-shade" / "spike"
        plan = deepcopy(load_json(spike_dir / "source-plan.json"))
        plan["assetId"] = spec["environment"]
        plan["revision"] = REVISION
        plan["environment"]["regionId"] = region_id
        plan["environment"]["displayName"] = spec["display"]
        plan["environment"]["developmentStatus"] = "spike-art-pending-final-human-review"
        plan["environment"]["groundFootprints"][0]["rect"] = spec["footprint"]
        plan["environment"]["camera"]["dollyBounds"] = [2, 60]
        plan["environment"]["terrainChunks"][0]["groundRect"] = [-512, -512, 2304, 2560]
        plan["environment"]["terrainChunks"][0]["subdivisions"] = [18, 20]
        # The former full-width cliff/forest cards remain omitted. The spike
        # plan supplies only a closed-alpha canopy derivative as ambient art.
        for role, binding in list(plan["sources"].items()):
            original = spike_dir / binding["path"]
            destination = source_dir / original.name
            destination.parent.mkdir(parents=True, exist_ok=True)
            if not destination.exists() or digest(read_bytes(destination)) != binding["sha256"]:
                shutil.copy2(original, destination)
            plan["sources"][role]["path"] = "sources/" + destination.name
        script = spike_dir / "build-derived-tree-planes.py"
        shutil.copy2(script, plan_dir / script.name)
    else:
        original_paths = {role: source_root / filename
                          for role, (filename, _expected) in spec["source_files"].items()}
        originals = {role: _archive_source(plan_dir, read_bytes(path))
                     for role, path in original_paths.items()}
        derived_sources, derivations = _build_derived_cards(
            plan_dir, original_paths["feature"], originals["feature"], spec["derived_cards"])
        plan = {
            "schemaVersion": 1,
            "kind": "environment",
            "assetId": spec["environment"],
            "revision": REVISION,
            "provider": "manual",
            "keyposes": ["sample"],
            "sources": {
                "ground": originals["ground"],
                "top": originals["top"],
                "sample": originals["top"],
                "feature_original": originals["feature"],
                **derived_sources,
            },
            "derivedImages": derivations,
            "provenance": {
                "kind": "source-derived",
                "sourceCollection": "digimonup-texture2d-private",
                "notes": "Exact hash-bound DigimonUP layers; deterministic bounded source crops only. No generated art or approval is represented.",
            },
            "generation": {
                "brief": "Offline source segmentation only. Missing side faces remain pending replacement art; no billable generation is authorized.",
                "jobs": [],
            },
            "environment": _base_environment(region_id, spec),
        }
    plan_path = plan_dir / "source-plan.json"
    write_json(ROOT, plan_path, plan, replace=True)
    validate_plan(plan)
    Pipeline(ROOT).plan(plan_path)
    return plan_path, plan


def _habitat_plan(region_id: str, spec: dict) -> tuple[Path, dict]:
    blocker = spec["habitat_blocker"]
    blocker_id = region_id + "-landmark-footprint"
    plan = {
        "schemaVersion": 1,
        "kind": "habitat",
        "assetId": "habitat-" + spec["home"],
        "revision": REVISION,
        "provider": "manual",
        "sources": {},
        "keyposes": [],
        "provenance": {"kind": "hand-authored"},
        "generation": {"brief": "Authored deterministic 40x48 home layout; no generated art.", "jobs": []},
        "habitat": {
            "regionId": region_id,
            "displayName": spec["home_display"],
            "environment": {"assetId": spec["environment"], "revision": REVISION},
            "grid": {"columns": 40, "rows": 48, "cellSize": 32},
            "blockers": [{"id": blocker_id, "rect": blocker}],
            "spawn": [20, 24],
            "wasteAnchors": [[6, 38], [20, 34], [34, 38]],
            "decorationZones": [
                {"id": "main", "rect": [2, 10, 36, 31]},
                {"id": "entry", "rect": [15, 41, 10, 5]},
            ],
            "staticPlacements": [{
                "id": region_id + "-landmark-home",
                "planeStack": region_id + "-landmark.stack" if region_id != "green-shade" else "green-shade-tree.stack",
                "cell": spec["habitat_cell"],
                "rotationQuarterTurns": 0,
                "blocker": blocker_id,
                "persistent": True,
            }],
        },
    }
    path = ROOT / "assets-source" / "habitats" / spec["home"] / REVISION / "source-plan.json"
    write_json(ROOT, path, plan, replace=True)
    validate_plan(plan)
    return path, plan


def _arena_plan(region_id: str, spec: dict) -> tuple[Path, dict]:
    footprint = spec["footprint"]
    position = spec["arena_position"]
    obstacle_id = region_id + "-landmark-footprint"
    obstacle = {
        "id": obstacle_id,
        "rect": [position[0] + footprint[0], position[1] + footprint[1], footprint[2], footprint[3]],
        "movement": True,
        "projectile": True,
        "sight": True,
        "occlusion": True,
    }
    plan = {
        "schemaVersion": 1,
        "kind": "arena",
        "assetId": "arena-" + spec["arena"],
        "revision": REVISION,
        "provider": "manual",
        "sources": {},
        "keyposes": [],
        "provenance": {"kind": "hand-authored"},
        "generation": {"brief": "Authored deterministic 30x36 battle layout; no generated art.", "jobs": []},
        "arena": {
            "regionId": region_id,
            "displayName": spec["arena_display"],
            "projection": "square",
            "ground": {"width": 960, "height": 1152, "cellSize": 32},
            "maxBodyRadius": 16,
            "spawns": {"player": [144, 560], "opponent": [816, 560]},
            "obstacles": [obstacle],
            "tiles": [],
            "environment": {"assetId": spec["environment"], "revision": REVISION},
            "presentation": {"staticPlacements": [{
                "id": region_id + "-landmark-arena",
                "planeStack": region_id + "-landmark.stack" if region_id != "green-shade" else "green-shade-tree.stack",
                "groundPosition": position,
                "rotationDegrees": 0,
                "obstacle": obstacle_id,
            }]},
        },
    }
    path = ROOT / "assets-source" / "arenas" / spec["arena"] / REVISION / "source-plan.json"
    write_json(ROOT, path, plan, replace=True)
    validate_plan(plan)
    return path, plan


def _export_native(folder: Path) -> None:
    godot = Pipeline(ROOT).godot
    result = subprocess.run([
        godot, "--headless", "--path", str(ROOT), "--script",
        "res://scripts/assets/export_resources.gd", "--", "--asset-review",
        "--candidate", str(folder),
    ], capture_output=True, text=True, timeout=120)
    if result.returncode != 0 or "SCRIPT ERROR" in result.stderr:
        raise RuntimeError("Native export failed:\n" + (result.stdout + result.stderr)[-4000:])


def _candidate_metadata(folder: Path, plan_path: Path, plan: dict, kind: str,
                        payload_pngs: list[str], extras: dict | None = None,
                        native: bool = True) -> dict:
    plan_hash = digest(read_bytes(plan_path))
    metadata = {
        "schemaVersion": 1,
        "kind": kind,
        "assetId": plan["assetId"],
        "revision": plan["revision"],
        "compilerVersion": VERSION,
        "buildIdentity": fingerprint({"plan": plan_hash, "compiler": VERSION, "native": native}),
        "sourcePlan": plan_path.relative_to(ROOT).as_posix(),
        "planSha256": plan_hash,
        "sourceHashes": {role: record["sha256"] for role, record in plan.get("sources", {}).items()},
        "nativeResources": False,
        "devFixture": True,
        "reviewStatus": "pending-human-review",
        "files": {},
    }
    if extras:
        metadata.update(extras)
    if kind == "environment":
        manifest = load_json(folder / "environment.json")
        metadata["nativeDependencies"] = {
            relative: digest(read_bytes(folder / relative))
            for relative in sorted(manifest["textures"].values())
        }
    write_json(ROOT, folder / "candidate.json", metadata, replace=True)
    if native:
        _export_native(folder)
        metadata["nativeResources"] = True
    metadata["files"] = tree_hashes(folder, payload_files=payload_pngs)
    metadata["contentSha256"] = fingerprint({key: value for key, value in metadata.items()
                                               if key != "sourcePlan"})
    write_json(ROOT, folder / "candidate.json", metadata, replace=True)
    return metadata


def _build_environment_fixture(plan_path: Path, plan: dict, fixture: Path) -> tuple[dict, dict]:
    pipeline = Pipeline(ROOT)
    loaded, sources = pipeline.plan(plan_path)
    with tempfile.TemporaryDirectory(prefix="five-region-env-", dir=ROOT / "work") as temporary:
        staging = Path(temporary)
        pipeline.compile_environment(loaded, sources, staging)
        write_bytes(ROOT, staging / "source-plan.json", read_bytes(plan_path))
        if fixture.exists():
            shutil.rmtree(fixture)
        shutil.copytree(staging, fixture)
    manifest = load_json(fixture / "environment.json")
    review_path = fixture / "environment-review.json"
    review = load_json(review_path)
    review.update({
        "subjectManifestSha256": digest(read_bytes(fixture / "environment.json")),
        "reviewerBuildSha256": _reviewer_build_sha256(),
        "presentationProfile": deepcopy(PRESENTATION_PROFILE),
        "renderCommand": "${PYTHON} assets-source/environments/capture-review-evidence.py --source-root ${DIGIMONUP_TEXTURE2D}",
    })
    write_json(ROOT, review_path, review, replace=True)
    pngs = list(manifest["textures"].values())
    # Native environment resources contain only the manifest and relative PNG
    # dependency hashes/paths. Pixel payloads stay as compact external files.
    metadata = _candidate_metadata(fixture, plan_path, plan, "environment", pngs, native=True)
    if (fixture / "environment.tres").stat().st_size > 2 * 1024 * 1024:
        raise RuntimeError("Environment native resource embedded pixel payloads")
    return metadata, manifest


def _layout_manifest(plan: dict, environment_metadata: dict, environment: dict) -> tuple[dict, dict, str]:
    kind = plan["kind"]
    value = deepcopy(plan[kind])
    value.update(schemaVersion=1, kind=kind, assetId=plan["assetId"], revision=plan["revision"])
    value["environment"]["contentSha256"] = environment_metadata["contentSha256"]
    if kind == "habitat":
        validation = validate_habitat(value, environment)
        review = {
            "schemaVersion": 1, "kind": "habitat-review", "assetId": plan["assetId"],
            "revision": plan["revision"], "status": "pending-human-review",
            "environment": deepcopy(value["environment"]),
            "checklist": ["spawn-clearance", "waste-anchor-reachability", "decoration-zone-coverage",
                          "static-placement-footprints", "camera-review"],
        }
    else:
        validation = validate_arena(value)
        validate_arena_environment_placements(value, environment)
        review = {
            "schemaVersion": 1, "kind": "arena-review", "assetId": plan["assetId"],
            "revision": plan["revision"], "status": "pending-human-review",
            "environment": deepcopy(value["environment"]),
            "checklist": ["body-clearance", "spawn-connectivity", "evasion-patches",
                          "static-placement-footprints", "battle-camera-framing"],
        }
    return value, {"validation": validation, "review": review}, kind


def _build_layout_fixture(plan_path: Path, plan: dict, environment_folder: Path,
                          environment_metadata: dict, environment: dict, fixture: Path) -> tuple[dict, dict]:
    manifest, reports, kind = _layout_manifest(plan, environment_metadata, environment)
    if fixture.exists():
        shutil.rmtree(fixture)
    fixture.mkdir(parents=True)
    write_bytes(ROOT, fixture / "source-plan.json", read_bytes(plan_path))
    write_json(ROOT, fixture / (kind + ".json"), manifest)
    write_json(ROOT, fixture / (kind + "-validation.json"), reports["validation"])
    reports["review"].update({
        "subjectManifestSha256": digest(read_bytes(fixture / (kind + ".json"))),
        "environmentContentSha256": environment_metadata["contentSha256"],
        "reviewerBuildSha256": _reviewer_build_sha256(),
        "presentationProfile": deepcopy(PRESENTATION_PROFILE),
        "renderCommand": "${PYTHON} assets-source/environments/capture-review-evidence.py --source-root ${DIGIMONUP_TEXTURE2D}",
    })
    write_json(ROOT, fixture / (kind + "-review.json"), reports["review"])
    shutil.copytree(environment_folder, fixture / "environment",
                    ignore=shutil.ignore_patterns("*.import"))
    metadata = _candidate_metadata(
        fixture, plan_path, plan, kind, [],
        {"environmentPackage": "environment",
         "environmentContentSha256": environment_metadata["contentSha256"]},
    )
    return metadata, manifest


def _inventory() -> dict:
    records = []
    seen = set()
    for region_id, spec in REGIONS.items():
        for role, (filename, source_hash) in spec["source_files"].items():
            key = (filename, source_hash)
            if key in seen:
                continue
            seen.add(key)
            records.append({
                "regionId": region_id,
                "role": role,
                "sourceCollection": "digimonup-texture2d-private",
                "sourceRelativePath": filename,
                "sha256": "sha256:" + source_hash,
                "licenseClassification": "private-prototype-only",
                "distributionStatus": "not-cleared",
            })
    return {
        "schemaVersion": 1,
        "kind": "environment-source-inventory",
        "revision": REVISION,
        "notice": LICENSE["notice"],
        "sources": sorted(records, key=lambda record: (record["regionId"], record["role"])),
    }


TARGET_SIZES = ((360, 640), (390, 844), (430, 932))
VIEWPOINTS = ("center", "left", "right", "near", "far")
SHIMMER_KEYS = ("000", "025", "050", "075", "100")
REVIEWER_FILES = (
    "tests/region_environment_capture_runner.gd",
    "scripts/environment/environment_view_3d.gd",
    "scripts/environment/companion_presentation_3d.gd",
    "scripts/environment/world_vfx_3d.gd",
    "scripts/environment/world_vfx_profile.gd",
    "scripts/environment/environment_presentation_contract.gd",
)


def _reviewer_build_sha256() -> str:
    return fingerprint({path: digest(read_bytes(ROOT / path)) for path in REVIEWER_FILES})


def _capture_record(region_root: Path, environment_metadata: dict) -> dict:
    evidence_path = region_root / "review" / "evidence.json"
    if not evidence_path.is_file():
        return {"status": "not-captured", "targets": {}, "reason": "evidence-record-missing"}
    evidence = load_json(evidence_path)
    current = (evidence.get("environmentContentSha256") == environment_metadata["contentSha256"] and
               evidence.get("reviewerBuildSha256") == _reviewer_build_sha256() and
               evidence.get("presentationProfile") == PRESENTATION_PROFILE and
               set(evidence.get("targets", {})) == {f"{width}x{height}" for width, height in TARGET_SIZES})
    if not current:
        return {"status": "stale", "targets": {}, "reason": "hash-build-or-profile-binding-differs"}
    for width, height in TARGET_SIZES:
        key = f"{width}x{height}"
        target = evidence["targets"].get(key, {})
        if set(target.get("viewpoints", {})) != set(VIEWPOINTS) or \
                set(target.get("shimmerSweep", {})) != set(SHIMMER_KEYS) or \
                int(target.get("shimmerAnalysis", {}).get("sampleCount", 0)) != 5:
            return {"status": "stale", "targets": {}, "reason": key + " evidence-matrix-incomplete"}
        for record in list(target["viewpoints"].values()) + list(target["shimmerSweep"].values()):
            path = region_root / "review" / key / record["file"]
            if not path.is_file() or digest(read_bytes(path)) != record["sha256"]:
                return {"status": "stale", "targets": {}, "reason": key + " capture-hash-differs"}
        performance = target.get("performance", {})
        if performance.get("sampleFrames", 0) < 120 or performance.get("displayServer") == "headless":
            return {"status": "stale", "targets": {}, "reason": key + " is-not-sustained-native-gpu"}
    return {
        "status": "captured-pending-human-review",
        "evidenceSha256": digest(read_bytes(evidence_path)),
        "reviewerBuildSha256": evidence["reviewerBuildSha256"],
        "renderCommand": evidence["renderCommand"],
        "targets": evidence["targets"],
    }


def _automated_review(region_id: str, spec: dict, environment: dict,
                      environment_folder: Path, environment_metadata: dict,
                      captures: dict) -> dict:
    from PIL import Image

    checks = {
        "canonicalProfile": environment["presentationProfile"] == PRESENTATION_PROFILE,
        "fixedCardYaw": all(abs(float(plane["rotationDegrees"][1])) < 0.0001
                            for plane in environment["spritePlanes"]),
        "threePlaneLandmark": all(len(stack["planes"]) >= 3 for stack in environment["planeStacks"]),
        "singleTerrainChunkNoJoin": len(environment["terrainChunks"]) == 1,
        "explicitFootprint": bool(environment["groundFootprints"]),
        "cameraBounds": environment["camera"]["movementBounds"] == [0, 0, 1280, 1536],
        "battleDollyCapacity": environment["camera"]["dollyBounds"] == [2, 60],
        "noPlaceholders": "placeholder" not in environment.get("developmentStatus", "").lower() and
            all("placeholder" not in plane.get("authoringStatus", "").lower()
                for plane in environment["spritePlanes"]),
        "distinctPlanePayloads": len({environment["textures"][plane["source"]]
                                      for plane in environment["spritePlanes"]}) ==
                                 len(environment["spritePlanes"]),
        "cameraSafeAmbientEdges": all(plane.get("edgePolicy") in
                                      ("camera-safe-rear-band", "natural-alpha-silhouette")
                                      for plane in environment.get("ambientPlanes", [])),
        "currentNativeEvidence": captures.get("status") == "captured-pending-human-review",
        "sustained60Fps": captures.get("status") == "captured-pending-human-review" and all(
            float(target.get("performance", {}).get("averageFrameMs", 1000.0)) <= 1000.0 / 60.0
            and int(target.get("performance", {}).get("sampleFrames", 0)) >= 120
            for target in captures.get("targets", {}).values()),
        "shimmerSweepMeasured": captures.get("status") == "captured-pending-human-review" and all(
            int(target.get("shimmerAnalysis", {}).get("sampleCount", 0)) == 5
            for target in captures.get("targets", {}).values()),
    }
    terrain = environment["terrainChunks"][0]
    checks["cameraSafeTerrainMargin"] = terrain["groundRect"] == [-512, -512, 2304, 2560]
    terrain_texture = environment_folder / environment["textures"][terrain["textureBinding"]]
    with Image.open(terrain_texture) as ground_image:
        ground = ground_image.convert("RGBA")
        checks["opaqueGroundCrop"] = all(alpha == 255 for alpha in ground.getchannel("A").getdata())
    edge_records = []
    source_textures = environment["textures"]
    for plane in environment["spritePlanes"]:
        with Image.open(environment_folder / source_textures[plane["source"]]) as source_image:
            image = source_image.convert("RGBA")
        x, y, width, height = plane.get("sourceRegionPx", [0, 0, image.width, image.height])
        crop = image.crop((x, y, x + width, y + height))
        alpha = crop.getchannel("A")
        boundaries = {
            "top": sum(value > 0 for value in alpha.crop((0, 0, width, 1)).getdata()) / width,
            "left": sum(value > 0 for value in alpha.crop((0, 0, 1, height)).getdata()) / height,
            "right": sum(value > 0 for value in alpha.crop((width - 1, 0, width, height)).getdata()) / height,
            # A grounded opaque base is expected and is recorded, not rejected.
            "bottom": sum(value > 0 for value in alpha.crop((0, height - 1, width, height)).getdata()) / width,
        }
        # Transparent padding can conceal a hard source cut inside the canvas.
        # Record the longest opaque run at the visible silhouette's top edge.
        # Grounded bottom edges are expected and are recorded but not rejected.
        bbox = alpha.getbbox()
        silhouette_top_ratio = 0.0
        if bbox is not None:
            left, top, right, _bottom = bbox
            bbox_width = max(1, right - left)
            longest = 0
            current = 0
            for column in range(left, right):
                if alpha.getpixel((column, top)) > 0:
                    current += 1
                    longest = max(longest, current)
                else:
                    current = 0
            silhouette_top_ratio = longest / bbox_width
        boundary_max = max(boundaries["top"], boundaries["left"], boundaries["right"])
        occluded_top = str(plane.get("edgePolicy", "")).startswith("occluded-by:")
        passes = boundary_max <= 0.02 and (silhouette_top_ratio <= 0.20 or occluded_top)
        edge_records.append({"plane": plane["id"], "nonTransparentBoundaryRatio": boundaries,
                             "maximumRejectedCanvasBoundaryRatio": boundary_max,
                             "canvasBoundaryThreshold": 0.02,
                             "visibleSilhouetteTopCutRatio": silhouette_top_ratio,
                             "silhouetteTopCutThreshold": 0.20,
                             "occlusionPolicy": plane.get("edgePolicy"),
                             "passes": passes})
    checks["noOpaqueCardBoundary"] = all(record["passes"] for record in edge_records)
    risks = []
    if not checks["noPlaceholders"]:
        risks.append("Placeholder cards are not acceptable environment evidence.")
    if not checks["noOpaqueCardBoundary"]:
        risks.append("At least one sprite card exceeds the 2% opaque-boundary threshold.")
    if not checks["currentNativeEvidence"]:
        risks.append("Native evidence is missing or stale for the current content hash/reviewer build/profile.")
    if not checks["sustained60Fps"]:
        risks.append("Sustained native GPU evidence does not meet the 60 FPS average-frame budget at every target size.")
    status = "pass" if all(checks.values()) else "fail"
    review = {
        "schemaVersion": 1,
        "kind": "environment-automated-review",
        "regionId": region_id,
        "revision": REVISION,
        "environmentContentSha256": environment_metadata["contentSha256"],
        "reviewerBuildSha256": _reviewer_build_sha256(),
        "presentationProfile": deepcopy(PRESENTATION_PROFILE),
        "renderCommand": "${PYTHON} assets-source/environments/capture-review-evidence.py --source-root ${DIGIMONUP_TEXTURE2D}",
        "automatedStatus": status,
        "humanReviewStatus": "pending-human-review",
        "checks": checks,
        "alphaEdgeMeasurements": edge_records,
        "artBlockers": risks,
        "note": "Automated checks do not approve art or authorize promotion. A fail remains visible until evidence is regenerated or art is replaced.",
    }
    write_json(ROOT, environment_folder.parent / "review" / "automated-qa.json", review, replace=True)
    return review


def build(source_root: Path) -> dict:
    fixture_parent = ROOT / "tests" / "fixtures"
    final_fixture_root = fixture_parent / "regions"
    fixture_parent.mkdir(parents=True, exist_ok=True)
    fixture_root = Path(tempfile.mkdtemp(prefix=".regions-build-", dir=fixture_parent))
    write_bytes(ROOT, fixture_root / ".gdignore",
                b"# Development-only private-prototype review fixtures.\n")
    # Preserve prior evidence as an input to the binding check. It remains
    # current only when every content/reviewer/profile/file hash still matches.
    if final_fixture_root.is_dir():
        for region_id in REGIONS:
            previous_review = final_fixture_root / region_id / "review"
            next_review = fixture_root / region_id / "review"
            for name in [*(f"{width}x{height}" for width, height in TARGET_SIZES), "evidence.json"]:
                source = previous_review / name
                destination = next_review / name
                if source.is_dir():
                    shutil.copytree(source, destination)
                elif source.is_file():
                    destination.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copy2(source, destination)
    index = {
        "schemaVersion": 1,
        "kind": "five-region-environment-dev-index",
        "revision": REVISION,
        "status": "pending-human-review",
        "licenseClassification": "private-prototype-only",
        "aliases": {"forest": "green-shade", "forest-arena": "green-shade"},
        "regions": {},
        "encounters": {},
    }
    try:
        for region_id, spec in REGIONS.items():
            environment_plan_path, environment_plan = _environment_plan(region_id, spec, source_root)
            habitat_plan_path, habitat_plan = _habitat_plan(region_id, spec)
            arena_plan_path, arena_plan = _arena_plan(region_id, spec)
            region_root = fixture_root / region_id
            env_meta, environment = _build_environment_fixture(
                environment_plan_path, environment_plan, region_root / "environment")
            habitat_meta, habitat = _build_layout_fixture(
                habitat_plan_path, habitat_plan, region_root / "environment", env_meta, environment,
                region_root / "review" / "habitat")
            arena_meta, arena = _build_layout_fixture(
                arena_plan_path, arena_plan, region_root / "environment", env_meta, environment,
                region_root / "review" / "arena")
            write_json(ROOT, region_root / "habitat.json", habitat, replace=True)
            write_json(ROOT, region_root / "arena.json", arena, replace=True)
            captures = _capture_record(region_root, env_meta)
            automated_review = _automated_review(region_id, spec, environment, region_root / "environment",
                                                 env_meta, captures)
            index["regions"][region_id] = {
            "displayName": spec["display"],
            "homeId": spec["home"],
            "arenaId": spec["arena"],
            "environment": {
                "assetId": spec["environment"], "revision": REVISION,
                "contentSha256": env_meta["contentSha256"],
                "path": f"tests/fixtures/regions/{region_id}/environment",
            },
            "habitat": {
                "assetId": habitat_plan["assetId"], "revision": REVISION,
                "contentSha256": habitat_meta["contentSha256"],
                "path": f"tests/fixtures/regions/{region_id}/habitat.json",
                "reviewPackage": f"tests/fixtures/regions/{region_id}/review/habitat",
            },
            "arena": {
                "assetId": arena_plan["assetId"], "revision": REVISION,
                "contentSha256": arena_meta["contentSha256"],
                "path": f"tests/fixtures/regions/{region_id}/arena.json",
                "reviewPackage": f"tests/fixtures/regions/{region_id}/review/arena",
            },
            "review": {
                "automatedStatus": automated_review["automatedStatus"],
                "humanStatus": "pending-human-review",
                "artBlockers": automated_review["artBlockers"],
                "captures": captures,
            },
            }
            encounter_id = "encounter." + region_id + "." + spec["arena"]
            index["encounters"][encounter_id] = {
                "regionId": region_id,
                "arenaId": spec["arena"],
                "arena": f"tests/fixtures/regions/{region_id}/arena.json",
            }
        signed = {
            "revision": REVISION,
            "licenseClassification": index["licenseClassification"],
            "regions": index["regions"],
            "encounters": index["encounters"],
        }
        index["aggregateFingerprint"] = fingerprint(signed)
        write_json(ROOT, fixture_root / "index.json", index, replace=True)
        write_json(ROOT, HERE / "SOURCE_INVENTORY.json", _inventory(), replace=True)
        backup = fixture_parent / (".regions-backup-" + uuid4().hex)
        if final_fixture_root.exists():
            os.rename(final_fixture_root, backup)
        try:
            os.rename(fixture_root, final_fixture_root)
        except Exception:
            if backup.exists() and not final_fixture_root.exists():
                os.rename(backup, final_fixture_root)
            raise
        if backup.exists():
            shutil.rmtree(backup)
        return index
    except Exception:
        if fixture_root.exists():
            shutil.rmtree(fixture_root)
        raise


def check(source_root: Path) -> dict:
    index_path = ROOT / "tests" / "fixtures" / "regions" / "index.json"
    if not index_path.is_file():
        raise RuntimeError("Five-region fixture index is missing; run without --check first")
    index = load_json(index_path)
    expected_inventory = _inventory()
    if load_json(HERE / "SOURCE_INVENTORY.json") != expected_inventory:
        raise RuntimeError("Source inventory differs from the checked-in contract")
    signed = {
        "revision": index["revision"],
        "licenseClassification": index["licenseClassification"],
        "regions": index["regions"],
        "encounters": index["encounters"],
    }
    if index.get("aggregateFingerprint") != fingerprint(signed):
        raise RuntimeError("Five-region aggregate fingerprint differs")
    for region_id, spec in REGIONS.items():
        region = index["regions"][region_id]
        env_folder = ROOT / region["environment"]["path"]
        env_meta = load_json(env_folder / "candidate.json")
        if env_meta.get("contentSha256") != region["environment"]["contentSha256"]:
            raise RuntimeError(region_id + " environment pin differs")
        if tree_hashes(env_folder) != env_meta["files"]:
            raise RuntimeError(region_id + " environment payload hashes differ")
        if fingerprint({key: value for key, value in env_meta.items()
                        if key not in ("sourcePlan", "contentSha256")}) != env_meta["contentSha256"]:
            raise RuntimeError(region_id + " environment content hash differs")
        environment = load_json(env_folder / "environment.json")
        validate_environment(environment, set(environment["textures"]), allow_compiled_bindings=True)
        for kind in ("habitat", "arena"):
            package = ROOT / region[kind]["reviewPackage"]
            meta = load_json(package / "candidate.json")
            if not meta.get("devFixture") or meta.get("environmentPackage") != "environment":
                raise RuntimeError(region_id + " " + kind + " is not explicitly isolated")
            if tree_hashes(package) != meta["files"]:
                raise RuntimeError(region_id + " " + kind + " payload hashes differ")
            if meta.get("contentSha256") != region[kind]["contentSha256"]:
                raise RuntimeError(region_id + " " + kind + " fingerprint differs")
        for role, (filename, expected) in spec["source_files"].items():
            if digest(read_bytes(source_root / filename)) != "sha256:" + expected:
                raise RuntimeError(f"{region_id} {role} external source hash differs")
    return index


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-root", type=Path, required=True,
                        help="DigimonUP Texture2D authoring directory (never written into manifests)")
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    result = check(args.source_root) if args.check else build(args.source_root)
    print(f"{result['status']} {len(result['regions'])} regions {result['aggregateFingerprint']}")
