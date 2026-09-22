# Battle effects source library — 17 September 2026

Free source assets collected for Ryuchii World. These are source candidates, not runtime-integrated or user-approved effects.

See [the source catalog and move coverage](../../../docs/BATTLE_EFFECT_SOURCES.md) for recommended packs, external downloads not yet acquired, license notes and adaptation work.

Downloaded here:

- `kenney-particle-pack/`: original archive and extracted CC0 particle textures.
- `kenney-impact-sounds/`: original archive, 130 OGG sounds and supplied license.
- `kenney-rpg-audio/`: original archive, 51 OGG sounds plus preview and supplied license.
- `mikodrak-spell-effects/`: original archive, ten transparent PNG sequences and preview GIFs.
- `second-bubble/`: original archive and nine 16×16 frames. Ignore `__MACOSX`/AppleDouble metadata when importing.
- `natural-privateer-bubble-pop/`: original 48×48 PNG spritesheet, authored in 16×16 cells.

All six downloaded sources are listed as CC0 by their creator/source pages. Preserve the bundled notices and `CREDITS.md`. Archives and image bytes have not been modified. The source manifest records hashes and URLs; the inventory skips archive metadata and verifies images can be decoded. `.gdignore` keeps source archives, duplicate image variants, Unity examples and review files out of Godot's automatic import scan.

The renderer still uses its existing procedural effects. Slicing, frame timing, pivots, facing, tint, palette consistency, sound audition/mixing and in-game review remain integration work. This task did not claim or fabricate final artwork approval.
