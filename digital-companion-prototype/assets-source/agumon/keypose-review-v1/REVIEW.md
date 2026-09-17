# Agumon direction reference — unapproved

This is a human-review reference board, not runtime artwork. The original canonical sprite files and active catalog were not changed.

## Review order

Top row, left to right: N (back), NE (rear-right), E (right), SE (front-right).

Bottom row: S (front), SW (front-left), W (left), NW (rear-left).

## What worked

All eight intended views are present, the 4-by-2 layout is clear, the main orange dinosaur identity is recognizable, and there is no text or scenery. The board is useful for deciding whether the facing design and character proportions are acceptable.

## Technical rejection / remaining work

The built-in generator returned a 1774×887 RGB PNG with a **painted checkerboard**, not actual transparent alpha. One targeted built-in edit was attempted, but it also returned RGB with a checkerboard. The original was retained as the clearer reference; the unsuccessful edit remains at the tool's recorded generated-images path. No API fallback or algorithmic background stripping was used.

Dimensions also do not divide evenly into integer 4×2 cells. This board must not be treated as a usable sprite sheet. Human identity feedback can inform a subsequent corrected generation, but actual transparent, fixed-canvas keyposes and explicit approval are still required before completing any animation. Generated front-view facial proportions and silhouette consistency should be checked against the canonical atlas.

`generation-record.json` contains both exact prompts, reference paths, tool-returned paths and inspection results. No approval receipt was minted and nothing was promoted.
