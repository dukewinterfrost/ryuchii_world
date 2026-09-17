from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys

from .common import PipelineError
from .pipeline import Pipeline
from .validation import KINDS, PROVIDERS


def main(argv=None):
    parser = argparse.ArgumentParser(description="Project-owned, human-approved sprite and environment pipeline")
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--godot", help="Godot executable (defaults to GODOT_PATH or local Godot)")
    sub = parser.add_subparsers(dest="command", required=True)
    new = sub.add_parser("new", help="Create a versioned source-plan template")
    new.add_argument("--asset", required=True)
    new.add_argument("--revision", required=True)
    new.add_argument("--kind", choices=KINDS, required=True)
    new.add_argument("--provider", choices=PROVIDERS, default="manual")
    sheet = sub.add_parser("sheet-template", help="Create blank 128px, eight-facing RGBA sheets and explicit frame manifest")
    sheet.add_argument("--asset", required=True)
    sheet.add_argument("--revision", required=True)
    sheet.add_argument("--action", default="idle")
    sheet.add_argument("--frames", type=int, default=4, help="Frames per facing; starts another sheet after eight")
    sheet.add_argument("--duration-ms", type=int, default=125)
    ingest = sub.add_parser("ingest", help="Preserve a source PNG and record its SHA-256")
    ingest.add_argument("--plan", type=Path, required=True)
    ingest.add_argument("--input", type=Path, required=True)
    ingest.add_argument("--role", required=True)
    generate = sub.add_parser("generate", help="Dry-run a provider request or emit a Codex/manual brief")
    generate.add_argument("--plan", type=Path, required=True)
    generate.add_argument("--job")
    generate.add_argument("--execute", action="store_true")
    generate.add_argument("--allow-billable", action="store_true")
    generate.add_argument("--resume", action="store_true", help="GET-only resume; never resubmit POST")
    compile_parser = sub.add_parser("compile", help="Build an immutable candidate and native resources")
    compile_parser.add_argument("--plan", type=Path, required=True)
    compile_parser.add_argument("--no-native", action="store_true", help="Offline compiler tests only; candidate cannot promote")
    validate = sub.add_parser("validate", help="Verify exact files, hashes, source bindings, and geometry")
    validate.add_argument("--candidate", type=Path, required=True)
    validate.add_argument("--require-native", action="store_true",
                          help="Also load/probe the native resource in headless Godot")
    fixture = sub.add_parser("fixture-check", help="Verify one source plan and its complete candidate fingerprint")
    fixture.add_argument("--plan", type=Path, required=True)
    fixture.add_argument("--candidate", type=Path, required=True)
    fixture.add_argument("--require-native", action="store_true")
    review = sub.add_parser("review", help="Preview, or explicitly record a real human approval")
    review.add_argument("--plan", type=Path)
    review.add_argument("--candidate", type=Path)
    review.add_argument("--stage", choices=("keyposes", "final"), default="final")
    review.add_argument("--approve", action="store_true")
    review.add_argument("--reviewer")
    review.add_argument("--notes", default="")
    review.add_argument("--no-launch", action="store_true")
    promote = sub.add_parser("promote", help="Copy approved immutable outputs and atomically update catalog")
    promote.add_argument("--candidate", type=Path, required=True)
    promote.add_argument("--review", type=Path, required=True)
    args = parser.parse_args(argv)
    pipeline = Pipeline(args.root, args.godot)
    try:
        if args.command == "new":
            result = pipeline.new(args.asset, args.revision, args.kind, args.provider)
        elif args.command == "sheet-template":
            from .sheet_template import create_sheet_template
            result = create_sheet_template(pipeline, args.asset, args.revision, args.action, args.frames, args.duration_ms)
        elif args.command == "ingest":
            result = pipeline.ingest(args.plan.absolute(), args.input.absolute(), args.role)
        elif args.command == "generate":
            result = pipeline.generate(args.plan.absolute(), args.job, args.execute, args.allow_billable, args.resume)
        elif args.command == "compile":
            result = pipeline.compile(args.plan.absolute(), native=not args.no_native)
        elif args.command == "validate":
            result = pipeline.validate(args.candidate.absolute(), require_native=args.require_native)
        elif args.command == "fixture-check":
            result = pipeline.fixture_check(args.plan.absolute(), args.candidate.absolute(),
                                            require_native=args.require_native)
        elif args.command == "review":
            result = pipeline.review(args.plan.absolute() if args.plan else None,
                                     args.candidate.absolute() if args.candidate else None,
                                     args.stage, args.approve, args.reviewer, args.notes, args.no_launch)
        else:
            result = pipeline.promote(args.candidate.absolute(), args.review.absolute())
        print(json.dumps(result, indent=2, sort_keys=True))
        return 0
    except (PipelineError, OSError, ValueError, KeyError, TypeError) as error:
        print("sprites: " + str(error), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
