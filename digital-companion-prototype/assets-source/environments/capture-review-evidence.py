#!/usr/bin/env python3
"""Capture hash-bound five-region review evidence with the native GPU renderer.

This command is deliberately separate from compilation. It records evidence for
unapproved development fixtures but never writes approvals or promotes assets.
"""

from __future__ import annotations

import argparse
from pathlib import Path
import shutil
import subprocess
import sys


HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(ROOT / "tools"))

from sprite_pipeline.common import digest, fingerprint, load_json, read_bytes, write_json  # noqa: E402
from sprite_pipeline.validation import PRESENTATION_PROFILE  # noqa: E402


TARGETS = ((360, 640), (390, 844), (430, 932))
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
RENDER_COMMAND = (
    "${GODOT} --path ${PROJECT_ROOT} --script res://tests/region_environment_capture_runner.gd "
    "-- --environment-fixture ${ENVIRONMENT_FIXTURE} --output ${TARGET_OUTPUT} "
    "--size ${WIDTH}x${HEIGHT} --environment-content-sha256 ${CONTENT_SHA256} "
    "--reviewer-build-sha256 ${REVIEWER_BUILD_SHA256} --region-id ${REGION_ID} --test-mode"
)


def _reviewer_build() -> str:
    return fingerprint({path: digest(read_bytes(ROOT / path)) for path in REVIEWER_FILES})


def _hash_capture_records(folder: Path, records: dict) -> dict:
    result = {}
    for key, record in records.items():
        path = folder / record["file"]
        if not path.is_file():
            raise RuntimeError("Capture output is missing: " + str(path))
        result[key] = {**record, "sha256": digest(read_bytes(path))}
    return result


def _shimmer_analysis(folder: Path, records: dict) -> dict:
    """Measure adjacent fractional-camera changes in a stable center crop."""
    from PIL import Image, ImageChops

    ordered = ["000", "025", "050", "075", "100"]
    images = [Image.open(folder / records[key]["file"]).convert("RGBA") for key in ordered]
    width, height = images[0].size
    crop_box = (width // 10, height // 10, width - width // 10, height - height // 10)
    crop_pixels = max(1, (crop_box[2] - crop_box[0]) * (crop_box[3] - crop_box[1]))
    adjacent = {}
    for previous, current, left, right in zip(images, images[1:], ordered, ordered[1:]):
        difference = ImageChops.difference(previous.crop(crop_box), current.crop(crop_box))
        changed = sum(1 for pixel in difference.getdata() if any(pixel))
        adjacent[left + "-" + right] = changed / crop_pixels
    return {
        "stableCropPx": list(crop_box),
        "adjacentChangedPixelRatios": adjacent,
        "maximumAdjacentChangedPixelRatio": max(adjacent.values()),
        "sampleCount": len(images),
    }


def _capture(godot: Path, region_id: str, fixture: Path, output: Path,
             content_sha256: str, reviewer_build: str, width: int, height: int) -> dict:
    if output.exists():
        shutil.rmtree(output)
    output.mkdir(parents=True)
    command = [
        str(godot), "--path", str(ROOT), "--script",
        "res://tests/region_environment_capture_runner.gd", "--",
        "--environment-fixture", str(fixture), "--output", str(output),
        "--size", f"{width}x{height}", "--environment-content-sha256", content_sha256,
        "--reviewer-build-sha256", reviewer_build, "--region-id", region_id, "--test-mode",
    ]
    result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, timeout=180)
    combined = result.stdout + result.stderr
    if result.returncode != 0 or "SCRIPT ERROR:" in combined or "Parse Error:" in combined or \
            "REGION_CAPTURE_OK:" not in combined:
        raise RuntimeError(f"Native capture failed for {region_id} {width}x{height}:\n{combined[-5000:]}")
    run_path = output / "capture-run.json"
    run = load_json(run_path)
    if run.get("displayServer") == "headless":
        raise RuntimeError("Evidence capture used the headless display server")
    if run.get("environmentContentSha256") != content_sha256 or \
            run.get("reviewerBuildSha256") != reviewer_build or \
            run.get("presentationProfile") != PRESENTATION_PROFILE:
        raise RuntimeError("Native capture binding differs from current candidate/reviewer/profile")
    samples = run.get("samples", {})
    if set(samples) != {"behindActor", "frontActor", "opaqueVfx", "translucentVfx"}:
        raise RuntimeError("Depth/VFX samples are incomplete")
    viewpoints = _hash_capture_records(output, run.get("viewpoints", {}))
    shimmer = _hash_capture_records(output, run.get("shimmerSweep", {}))
    if set(viewpoints) != set(VIEWPOINTS) or set(shimmer) != set(SHIMMER_KEYS):
        raise RuntimeError("Capture matrix is incomplete")
    performance = run.get("performance", {})
    if performance.get("sampleFrames", 0) < 120:
        raise RuntimeError("Benchmark is not sustained")
    performance["displayServer"] = run["displayServer"]
    performance["videoAdapter"] = run["videoAdapter"]
    return {
        "captureRunSha256": digest(read_bytes(run_path)),
        "viewpoints": viewpoints,
        "shimmerSweep": shimmer,
        "shimmerAnalysis": _shimmer_analysis(output, shimmer),
        "samples": samples,
        "performance": performance,
    }


def capture(godot: Path, source_root: Path, selected_region: str | None = None) -> None:
    index_path = ROOT / "tests/fixtures/regions/index.json"
    index = load_json(index_path)
    reviewer_build = _reviewer_build()
    for region_id, record in index["regions"].items():
        if selected_region is not None and region_id != selected_region:
            continue
        fixture = ROOT / record["environment"]["path"]
        content_sha256 = record["environment"]["contentSha256"]
        review_root = ROOT / "tests/fixtures/regions" / region_id / "review"
        targets = {}
        for width, height in TARGETS:
            key = f"{width}x{height}"
            targets[key] = _capture(godot, region_id, fixture, review_root / key,
                                    content_sha256, reviewer_build, width, height)
        evidence = {
            "schemaVersion": 1,
            "kind": "environment-native-review-evidence",
            "regionId": region_id,
            "revision": index["revision"],
            "environmentAssetId": record["environment"]["assetId"],
            "environmentContentSha256": content_sha256,
            "reviewerBuildSha256": reviewer_build,
            "reviewerFiles": list(REVIEWER_FILES),
            "presentationProfile": PRESENTATION_PROFILE,
            "renderCommand": RENDER_COMMAND,
            "targets": targets,
            "status": "captured-pending-human-review",
            "approval": None,
        }
        write_json(ROOT, review_root / "evidence.json", evidence, replace=True)
        print(region_id, content_sha256, "captured")
    refresh = subprocess.run([
        sys.executable, str(HERE / "build-five-regions.py"),
        "--source-root", str(source_root),
    ], cwd=ROOT, capture_output=True, text=True, timeout=180)
    if refresh.returncode != 0:
        raise RuntimeError("Evidence was captured but the atomic index refresh failed:\n" +
                           (refresh.stdout + refresh.stderr)[-5000:])
    print(refresh.stdout.strip())


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--godot", type=Path,
                        default=Path("/Applications/Godot.app/Contents/MacOS/Godot"))
    parser.add_argument("--source-root", type=Path, required=True,
                        help="Hash-checked DigimonUP Texture2D source folder")
    parser.add_argument("--region", choices=("green-shade", "shellfish-beach", "toy-maze",
                                              "mechatropolis", "nephelis-abyss"),
                        help="Recapture only one changed region; other evidence is preserved atomically")
    args = parser.parse_args()
    if not args.godot.is_file():
        raise SystemExit("Godot executable is missing: " + str(args.godot))
    capture(args.godot, args.source_root, args.region)
