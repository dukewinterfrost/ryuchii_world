# Rootbound Glade rework and sheer ledges — 2026-09-17

Reworked the first-stage Green Shade battle working scene and applied the user's
follow-up direction—**a sheer drop instead of sloping hills**—to both that field
and the active native forest home. Other regional kits were not rebuilt.

## See and edit it

- Double-click `open-battle-fields.command`, then select **Rootbound Glade**.
  This runs the real combat scene with the edited field in an isolated save.
- Open `scenes/environment_workshop/green_shade_battle.tscn` in Godot. F6 previews
  the whole composition; F8 stops. All scenery remains ordinary editable nodes.
- `Floor/ClearingTerrain`: Ground Material controls grass/soil and source detail;
  Edge Drop controls the sheer wall depth. Rebuild Terrain Preview updates the
  mesh. Re-ground outside plants after changing the edge shape or height.
- `ForestParallax/Woodland`: separate RimPockets, RearGrove, SideValleys,
  FrontBasin and LowGrass groups. Grounded groups never slide with the camera.
- `CameraRig`: 30° pitch, 128-unit overview distance; child camera is 32° FOV.
  Actual combat keeps its existing automatic fighter fit and View/zoom controls.
- The existing tree remains at (15,0,9); its combat footprint is unchanged.

This is an **unpromoted private-prototype working scene**, not a catalog approval.
Ordinary live battles still use their approved pinned packages. The native home
change is active in the existing care scene. Human asset approval/promotion is
still separate; no generation, new source ingestion or paid API call occurred.

## What changed

The battle's rectangular tile patch floor and dense rear tree wall were replaced
with a rounded raised clearing, a restrained worn center, irregular plant
pockets, lower shaded woods and registered BG-1 scenery. There are 236 baked
woodland/grass cards plus the existing landmark. Low grass avoids the main
dueling lane; large scenery stays outside the 30×36 gameplay grid and apron.

`sheer_stage_mesh.gd` now supplies a flat cap, vertical cliff faces and a flat
lower woodland floor. Heights are exactly 0/-12 for battle and 0/-16 for home.
An irregular ellipse encloses the rectangular simulation and apron; it does not
replace collision or navigation with a mesh. This also avoids square corner
lobes from a rectangle/oval union. The cliff shader adds dark, stationary strata.

All 477 existing home cards retained their XZ placement, size, flip, source
region and color; only their elevations were re-grounded. Trees are still 2D
Sprite3D artwork. Terrain meshes do not add 3D tree models or physics bodies.
The original home scenery files and battle scene are retained in the review's
`baseline/` directory, so the pre-rework layouts remain recoverable.

The shallower lower floor occluded the former low/far backgrounds. The revised
three registered cards are closer, wide enough for all tested views and buried
below the lower floor, with woodland silhouettes covering their junctions.

## Verification

Godot 4.7.2, Compatibility renderer, Apple M5. Every listed suite completed with
zero failures and no engine/script errors or resource-leak warnings.

| Suite | Latest result |
| --- | --- |
| Rootbound/native sheer ledges, headless | 7,480 checks |
| Rootbound/native sheer ledges, GPU review | 7,484 checks |
| Home forest camera / grounding matrix | 9,974 checks |
| Home Scene Builder, GPU layers and subpixel review | 1,109 checks |
| Battle Sprite-in-3D / replay integration | 509 checks |
| Editable workshop persistence | 122 checks |
| Home day/night | 78 checks |
| Care camera | 94 checks |
| Battle v4 visual controls/cues | 69 checks |
| Care full-window map view | 29 checks |

Rootbound renders center/left/right/near/far at 360×640, 390×844, 430×932, plus
a 1280×720 world overview. Home captures seven camera positions at all four
sizes plus dawn/day/dusk/night. Close/manual battle inspection can deliberately
crop distant fighters; Fit still frames both. That behavior was not changed.

All terrain triangles were measured as horizontal or vertical, not merely
classified from their material. Every gameplay cell corner remains at Y=0.
Existing battle clearances, spawn data and landmark blockers remain valid.
The render-interleaved and non-rendered 360-tick sessions are byte-identical,
including replay records. Their sample SHA-256 is
`1bab447cb862ff40ee14375e349ae0de228bd840db0b03aa4d8a7f14d68a86c9`.
The established frozen-v3 checksum also passes in the integration suite.

At 0/.25/.5/.75/1-pixel camera translations, the battle's stable ground crop
changes progressively (2.4–3.5% at .25 pixels, 8.9–11.7% at 1 pixel), then
returns to exactly zero changed pixels. Home's return-to-origin check also
passes. Nearest-filtered edges still step; this is not a claim of zero pixel
motion or a certified mobile-device 60 FPS result.

The offline builder's overwrite guard was exercised: an existing output is
rejected without `--replace`. Scene Builder skill validation also passes.

## Evidence and provenance

Captures and complete logs: `docs/reviews/rootbound-glade/`.
Start with `before.png`, `battle-overview.png`, `battle-center.png`, and
`home-overview.png`; `battle/`, `home/` and `subpixel/` contain the review matrix.

Source bindings remain `assets-source/forest-bg1-wrap/2026-09-17.001/` and the
existing private forest working set. No source PNG was edited.

| Unchanged source | SHA-256 |
| --- | --- |
| foliage.png | `ee0ed7a9f64646e8205801b671ba06591fa587f7dc79efc1ede5efb390c9743f` |
| BG-1 distant.png | `537f2a74f01cdcf16c8bfa23bdc9854869717134ccdef3a2d6d1cde0d94a1f63` |
| BG-1 middle.png | `7e699e3662a89787c75df7a020881e73a767f29e240cf2c1973c6ee3704c93a6` |
| BG-1 foreground.png | `e6b4f554fafec70e5f1971695ff49cef8f22099936351cbcaf8ceeb9bd5fd2c7` |
| panorama.png (grass crop only) | `d387a7fed284f1fed691546dae6ca1235af148f86ecf63eec10dd72d7fa2f4a6` |
| First-stage arena fixture JSON | `32e45095ec58642a84fa8df376efa2ac2edcf2f60b5930ede3012b4185372dbc` |
| Runtime catalog | `97b028eae9450c40885084a25c3e09a4f772217e64ffd054123559d4663a138c` |

Battle layout seed: 170927; card-layout SHA-256:
`3d87feab4501f27c30cbd4a8576655a7f2ed813a2f21db772564ccf7ba8af442`.
The layout hash binds the authored card records, not a compiled asset revision.
The existing Rootbound arena/environment pins remain `2026-09-12.001`.
Supplied BG-1/foliage and DigimonUP-derived assets remain private-prototype-only,
not cleared for public or commercial distribution.
