# Woodland foliage — sample approved; compiled review pending

John approved the displayed foliage direction with “I approve the foilage” on
2026-09-15. The exact decision is in `keypose-review.json`. This is sample
approval, not permission to promote the final in-game package.

The original native clearing from the previous goal turn did not yet match the
organic scenery in the user's references. This four-prop kit is a new visual
direction, generated with the built-in image tool. The initial result was edited
with that same tool to restore complete silhouettes and transparent gutters.

- Source: `sources/ee0ed7a9f64646e8205801b671ba06591fa587f7dc79efc1ede5efb390c9743f.png`
- Dimensions: 1254×1254 RGBA, four 627×627 regions.
- Alpha-cut threshold: 0.5; all four opaque silhouettes remain inside their regions.
- The full generation and correction prompts are in `source-plan.json`.
- `generation-record.json` records the observed opaque bounds and source hash.
- No source pixels were edited or resampled by a local script. The preview uses
  texture regions, authored pivots, nearest filtering, and camera-facing Sprite3D.

The isolated composition is `tests/care_foliage_review.gd`, invoked by:

```sh
/Applications/Godot.app/Contents/MacOS/Godot --path . \
  --script res://tests/care_reference_runner.gd -- \
  --test-mode --capture --foliage-review
```

The renderer refuses this source-art path outside an isolated test/review save.
Normal live care remains on the native original scene. No final approval or
promotion receipt has been created.

## Compiled candidate

- Asset/revision: `care-woodland-foliage/2026-09-15.001`.
- Source SHA-256: `ee0ed7a9f64646e8205801b671ba06591fa587f7dc79efc1ede5efb390c9743f`.
- Compiler: 1.3.1.
- Directory: `work/sprites/care-woodland-foliage/2026-09-15.001/3305576bfa113936`.
- Content SHA-256: `f35e8990be98753d83c9a44cb399941d10264cec469209ea7763f5cb68e74f14`.
- Native `atlasframes.tres` contains four entries with retained foot pivots.
- Lossless native texture storage avoids the oversized textual RGBA resource
  found during the first compile. The 16 MiB artifact cap is unchanged.
- Earlier compiler-1.3.0 candidate `31a178c2e4671fa9` is superseded and unapproved;
  it remains in work storage, not the runtime catalog.

Run `./open-foliage-review.command` from the project directory (or double-click
the launcher in Finder) to validate and inspect the actual compiled native kit
in the care screen. This uses a synthetic isolated save, not your companion.

Compiled screenshots: `compiled-preview-360x640.png`,
`compiled-preview-390x844.png`, and `compiled-preview-430x932.png`.
The earlier `care-preview-*.png` files remain as sample-review history.

Validation passed, including native loading and exact decoded atlas comparison.
The compiled care preview passed 42 checks: all visible source RGBA and pivots,
three portrait sizes, input projection, save isolation, VFX/grid behavior, and
actual GPU square proportions across nine camera-angle combinations. This is
mechanical evidence, not a complete environmental performance/depth audit.

Next decision: approve or revise the compiled in-game composition. Normal care
art and the runtime catalog remain unchanged. Do not infer final approval from
an automatic goal continuation. No new generation was run for this approval.

Checks so far: 42 care reference checks passed, including actual GPU proportions
at nine camera angle combinations. This establishes mechanics, not final visual
approval. Private-prototype handling remains in place.
