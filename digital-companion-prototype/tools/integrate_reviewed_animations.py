"""Compile the September 13 reviewed frames; promotion requires --promote.

John requested integration on September 15: "Can you update the animations in the app".
No generation requests, image transformations, or changes to legacy packs.
"""
import argparse
import hashlib
import json
from pathlib import Path

from sprite_pipeline.pipeline import Pipeline

ROOT = Path(__file__).resolve().parents[1]
RUN = ROOT.parent / "design-workshop/animation-review/2026-09-13-v1"
POSES = ROOT.parent / "design-workshop/keyframe-review/2026-09-12-v1"
REVISION = "2026-09-15.001"
DECISION = 'John requested integration of the displayed animation set: "Can you update the animations in the app" (2026-09-15). This receipt records that integration decision, not a separate review of the compiled atlas.'


def main():
    parser = argparse.ArgumentParser(__doc__)
    parser.add_argument("--promote", action="store_true")
    args = parser.parse_args()
    pipeline = Pipeline(ROOT)
    results = []
    for species in ("botamon", "koromon", "agumon"):
        path = ROOT / "assets-source" / species / REVISION / "source-plan.json"
        clips = [json.loads(p.read_text()) for p in sorted((RUN / "review").glob(species + "-*.json"))]
        if not path.exists():
            path.parent.mkdir(parents=True, exist_ok=True)
            plan = dict(schemaVersion=1, assetId=species, subjectId=species,
                        revision=REVISION, kind="animation", provider="pixellab",
                        sources={}, keyposes=[], canvas=[128, 128], requiredFacings=[],
                        requiredActions=["idle", "move"], clips={},
                        fallbacks={"listen": "idle.default", "celebrate": "happy.default", "play": "happy.default"},
                        paddingPx=2, extrudePx=1, atlasColumns=8,
                        motionProfile={"facing": "right", "rootPolicy": "in-place", "requiredAnchors": ["root"]},
                        provenance={"kind": "generated", "tool": "PixelLab animate-with-text-v3", "reviewRun": "2026-09-13-v1"})
            for clip in clips:
                action = {"basic-attack": "basic_attack", "pepper-breath": "special_attack"}.get(clip["action"], clip["action"])
                plan["keyposes"].append("keypose." + action)
                frames = []
                for frame in clip["frames"]:
                    role = action + ".%04d" % frame["index"]
                    frames.append({"source": role, "durationMs": frame["durationMs"],
                                   "pivot": {"x": 0.5, "y": 0.9375},
                                   "anchors": {"root": {"x": 0.5, "y": 0.9375}}})
                events = [{"frame": len(frames) - 1, "name": "eat-finished"}] if action == "eat" else []
                plan["clips"][action + ".default"] = {"semanticAction": action, "kind": "loop" if clip["loop"] else "one-shot", "frames": frames, "events": events, "qualityProfile": "reviewed-pixellab-v3"}
            path.write_text(json.dumps(plan, indent=2) + "\n")
        for clip in clips:
            action = {"basic-attack": "basic_attack", "pepper-breath": "special_attack"}.get(clip["action"], clip["action"])
            pipeline.ingest(path, POSES / (clip["key"] + ".png"), "keypose." + action)
            for frame in clip["frames"]:
                image = RUN / "review" / frame["path"]
                assert "sha256:" + hashlib.sha256(image.read_bytes()).hexdigest() == frame["sha256"]
                pipeline.ingest(path, image, action + ".%04d" % frame["index"])
        pipeline.review(path=path, stage="keyposes", approve=True, reviewer="John", notes='Previously approved: "These are looking good, run them through the animation machine". ' + DECISION)
        compiled = pipeline.compile(path)
        candidate = Path(compiled["candidate"])
        pipeline.validate(candidate, require_native=True)
        if args.promote:
            receipt = pipeline.review(candidate=candidate, approve=True, reviewer="John", notes=DECISION, no_launch=True)
            compiled.update(pipeline.promote(candidate, Path(receipt["receipt"])))
        results.append(compiled)
        print(json.dumps(compiled), flush=True)
    (RUN / "runtime-integration.json").write_text(json.dumps({"decision": DECISION, "assets": results}, indent=2) + "\n")


if __name__ == "__main__":
    main()
