"""Authoring sheets only: never approve, ingest, generate artwork, or promote."""

from copy import deepcopy
from io import BytesIO

from PIL import Image

from .common import identifier, require, write_bytes, write_json
from .validation import FACINGS, ACTIONS, validate_plan

CANVAS = 128
COLUMNS = 8
ANCHORS = {
    "root": {"x": 64 / 128, "y": 120 / 128},
    "mouth": {"x": 80 / 128, "y": 60 / 128},
    "hand": {"x": 84 / 128, "y": 84 / 128},
    "impact": {"x": 64 / 128, "y": 76 / 128},
}


def make_plan(asset_id, revision, action="idle", frames=4, duration_ms=125):
    from .pipeline import template

    identifier(asset_id, "assetId")
    identifier(revision, "revision")
    identifier(action, "action")
    require("." not in action, "Use a semantic action name without a facing suffix")
    require(type(frames) is int and 1 <= frames <= 64, "Choose 1–64 frames per facing")
    require(type(duration_ms) is int and duration_ms > 0, "Duration must be a positive integer")
    plan = template(asset_id, revision, "animation", "manual")
    plan["requiredActions"] = [action] if action in ACTIONS else []
    plan["motionProfile"] = {"rootPolicy": "in-place", "facing": "eight-direction", "requiredAnchors": list(ANCHORS)}
    plan["clips"] = {}
    plan["sheetLayout"] = {
        "cellSize": [128, 128], "columns": COLUMNS, "rows": FACINGS[:],
        "imageSize": [1024, 1024], "format": "RGBA8", "pivotPx": [64, 120],
        "trim": False, "rotate": False, "recenter": False,
        "usedCells": [],
        "note": "Only clips.frames are compiled. Edit anchors per pose. Unused cells stay transparent.",
    }
    plan["generation"]["brief"] = (
        "Author grounded creature poses in the declared 128px cells; north-clockwise facing rows. "
        "Separate all hearts, flames, particles, and UI symbols into effects assets. "
        "Do not draw registration guides into the RGBA sheet. Root remains (64,120); "
        "adjust mouth, hand, and impact anchors for each actual pose."
    )
    for row, facing in enumerate(FACINGS):
        clip_id = action + "." + facing.lower()
        sequence = []
        for index in range(frames):
            page, column = divmod(index, COLUMNS)
            source = "sheet.%s.%04d" % (action, page)
            sequence.append({
                "source": source, "rect": [column * CANVAS, row * CANVAS, CANVAS, CANVAS],
                "durationMs": duration_ms, "pivot": deepcopy(ANCHORS["root"]),
                "anchors": deepcopy(ANCHORS),
            })
            plan["sheetLayout"]["usedCells"].append({"source": source, "cell": [column, row], "clip": clip_id, "frame": index})
        plan["clips"][clip_id] = {
            "semanticAction": action,
            "kind": "loop" if action in ("idle", "move", "guard") else "one-shot",
            "qualityProfile": "directional-combat", "frames": sequence, "events": [],
        }
    validate_plan(plan)
    return plan


def create_sheet_template(pipeline, asset_id, revision, action="idle", frames=4, duration_ms=125):
    plan = make_plan(asset_id, revision, action, frames, duration_ms)
    folder = pipeline.source_root / asset_id / revision
    # All writes use the same traversal/symlink/no-overwrite protection as new.
    require(not folder.exists(), "Revision already exists; choose a new revision")
    sheets = []
    blank = Image.new("RGBA", (1024, 1024), (0, 0, 0, 0))
    stream = BytesIO()
    blank.save(stream, "PNG")
    for page in range((frames + COLUMNS - 1) // COLUMNS):
        name = "sheet.%s.%04d.png" % (action, page)
        write_bytes(pipeline.root, folder / name, stream.getvalue())
        sheets.append(str(folder / name))
    guide = ['<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">',
             '<g fill="none" stroke="#657a80" stroke-width="1">']
    for index in range(9):
        at = index * CANVAS
        guide.append(f'<path d="M {at} 0 V 1024 M 0 {at} H 1024"/>')
    guide.append('</g><g font-family="monospace" font-size="12" fill="#657a80">')
    for row, facing in enumerate(FACINGS):
        for column in range(COLUMNS):
            x, y = column * CANVAS, row * CANVAS
            guide.append(f'<text x="{x + 4}" y="{y + 15}">{facing} · {column + 1}</text>')
            guide.append(f'<path d="M {x + 58} {y + 120} h 12 M {x + 64} {y + 114} v 12" stroke="#d13d85"/>')
    guide.append('</g></svg>')
    write_bytes(pipeline.root, folder / "guide-overlay.svg", "\n".join(guide).encode())
    write_json(pipeline.root, folder / "source-plan.json", plan)
    return {"plan": str(folder / "source-plan.json"), "sheets": sheets,
            "guide": str(folder / "guide-overlay.svg"),
            "next": "Paint declared cells, export without guide, ingest each sheet by its source role; review keyposes then compile. Blank declared cells are rejected."}
