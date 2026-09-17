#!/usr/bin/env python3
"""Fail closed when private DigimonUP environment bytes enter export roots."""

from __future__ import annotations

from pathlib import Path
import sys


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))

from sprite_pipeline.common import digest, load_json, read_bytes  # noqa: E402


RESTRICTED_SOURCE_ROOTS = (
    ROOT / "assets-source",
    ROOT / "tests/fixtures/regions",
    ROOT / "tests/fixtures/environments",
)
PUBLIC_OUTPUT_ROOTS = (ROOT / "build", ROOT / "dist", ROOT / "exports")


def check() -> list[str]:
    errors: list[str] = []
    inventory = load_json(ROOT / "assets-source/environments/SOURCE_INVENTORY.json")
    restricted_hashes = {record["sha256"] for record in inventory.get("sources", [])}
    for source_root in RESTRICTED_SOURCE_ROOTS:
        if not (source_root / ".gdignore").is_file():
            errors.append(str(source_root.relative_to(ROOT)) + " needs .gdignore")
    for output_root in PUBLIC_OUTPUT_ROOTS:
        if not output_root.is_dir():
            continue
        for path in output_root.rglob("*"):
            if path.is_file() and path.stat().st_size <= 128 * 1024 * 1024:
                if digest(read_bytes(path)) in restricted_hashes:
                    errors.append("restricted source byte in public output: " + str(path.relative_to(ROOT)))
    presets = ROOT / "export_presets.cfg"
    if presets.is_file():
        text = presets.read_text(encoding="utf-8")
        for excluded in ("assets-source/*", "tests/fixtures/regions/*", "tests/fixtures/environments/*"):
            if excluded not in text:
                errors.append("export_presets.cfg must exclude " + excluded)
    return errors


if __name__ == "__main__":
    failures = check()
    if failures:
        for failure in failures:
            print("FAIL:", failure)
        raise SystemExit(1)
    print("PASS: restricted environment sources are excluded from Godot/public export roots")
