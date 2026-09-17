#!/usr/bin/env python3
"""Rebuild the non-promoted Green Shade runtime fixture deterministically."""

from __future__ import annotations

import argparse
from pathlib import Path
import shutil
import sys
import tempfile


HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
sys.path.insert(0, str(ROOT / "tools"))

from sprite_pipeline.pipeline import Pipeline  # noqa: E402
from sprite_pipeline import VERSION  # noqa: E402
from sprite_pipeline.common import digest, fingerprint, load_json, read_bytes, write_json  # noqa: E402


PLAN = HERE / "source-plan.json"
FIXTURE = ROOT / "tests" / "fixtures" / "environments" / "green-shade-3d-spike"
LEGACY_TERRAIN = (
    "terrain.green-shade-ground-far.png",
    "terrain.green-shade-ground-mid.png",
    "terrain.green-shade-ground-near.png",
)


def _metadata(plan: dict) -> dict:
    payloads = [
        FIXTURE / "environment.json",
        FIXTURE / "environment-validation.json",
        FIXTURE / "environment-review.json",
        *sorted((FIXTURE / "textures").glob("*.png")),
    ]
    files = {
        path.relative_to(FIXTURE).as_posix(): digest(read_bytes(path))
        for path in payloads
    }
    content_sha256 = fingerprint(files)
    signed = {
        "planSha256": digest(read_bytes(PLAN)),
        "compilerVersion": VERSION,
        "sourceHashes": {
            role: source["sha256"] for role, source in sorted(plan["sources"].items())
        },
        "contentSha256": content_sha256,
    }
    return {
        "schemaVersion": 1,
        "kind": "environment-dev-fixture",
        "assetId": plan["assetId"],
        "revision": plan["revision"],
        **signed,
        "files": files,
        "fixtureFingerprint": fingerprint(signed),
    }


def build(check: bool = False) -> None:
    pipeline = Pipeline(ROOT)
    plan, sources = pipeline.plan(PLAN)
    if check:
        actual = load_json(FIXTURE / "fixture.json")
        expected = _metadata(plan)
        if actual != expected:
            raise RuntimeError("Green Shade dev fixture differs from its source plan or payload hashes")
        print(f"verified {plan['assetId']} {plan['revision']} {actual['fixtureFingerprint']}")
        return
    temporary_root = ROOT / "work"
    temporary_root.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="green-shade-dev-fixture-", dir=temporary_root) as temporary:
        staging = Path(temporary)
        pipeline.compile_environment(plan, sources, staging)
        for filename in ("environment.json", "environment-validation.json", "environment-review.json"):
            shutil.copy2(staging / filename, FIXTURE / filename)
        (FIXTURE / "textures").mkdir(parents=True, exist_ok=True)
        for texture in (staging / "textures").glob("*.png"):
            shutil.copy2(texture, FIXTURE / "textures" / texture.name)
    for filename in LEGACY_TERRAIN:
        for suffix in ("", ".import"):
            legacy = FIXTURE / "textures" / (filename + suffix)
            if legacy.is_file():
                legacy.unlink()
    metadata = _metadata(plan)
    write_json(ROOT, FIXTURE / "fixture.json", metadata, replace=True)
    print(f"rebuilt {plan['assetId']} {plan['revision']} {metadata['fixtureFingerprint']} (pending review, not promoted)")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    build(parser.parse_args().check)
