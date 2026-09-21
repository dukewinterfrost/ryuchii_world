# Forest Scene Builder — 2026-09-17

This records the earlier slope pass. The later user-requested sheer ledges and
updated first-stage battle are documented in [Rootbound Glade review](ROOTBOUND_GLADE_REVIEW.md).

Implemented in the live native home scene, not an alternate workshop demo.
The goal was to move the existing world toward the supplied meadow reference,
retain the lowered dark shoulder, and use dropped, darkened parallax scenery
to close gaps. The beach is prepared as the next workflow, not built here.

## Result and requirement audit

| Requirement | Current evidence |
| --- | --- |
| More like the reference | Warmer irregular meadow patches, small painted grass groups, rougher path margins, overlapping dark framing and an open mountain skyline. Compare `reference.png`, `before-overview.png`, `complete-overview.png` and `center.png` in the review folder. No reference pixels entered runtime assets. |
| Preserve the liked lowered/dark area | Same sculpted terrain height function, 16-unit shoulder drop, flat 40×48 grid/apron, and 0.62 lower-shadow strength. Runtime assertions and before/after captures verify this. |
| Fill the gap with dropped, darkened parallax decor | 210 new Sprite3D cards in four native layers, all sampled at terrain height ≤ -8.5 and buried another 0.45 units. Cool dark base colors, alpha-cut/depth testing, nearest filtering and day/night tint remain active. |
| Conceal edges and seams | Rear grove silhouettes overlap the terrain/backdrop junction; side valleys and two foreground depths fill the exposed basin/corners. All reviewed camera limits retain backdrop overscan, sky coverage, and foreground clearance. Layers-on/off GPU comparisons show actual visible coverage rather than merely counting nodes. |
| Create a project Scene Builder skill | `.agents/skills/scene-builder/SKILL.md` plus UI metadata and routed forest/beach references. The existing environment skill links to it. Both skills pass the bundled validator; UI metadata and reference existence checks pass. |
| Capture process/findings and prepare the beach | Forest reference documents the active profile, sources, failed approaches, safe offline authoring, grounding and verification. Beach handoff describes shoreline/water/sand depth roles, existing source locations and a first review checkpoint without copying forest density or authorizing generation. |

## Native composition

- `scenes/environments/care_clearing.tscn` instances the new
  `scenes/environment_workshop/care_transition_woodland.tscn`.
- `RearGrove`: 44 overlapping trees/shrubs behind the clearing, secondary
  parallax factor 0.018.
- `SideValleys`: 96 trees, ferns and shrubs outside the left/right slopes.
- `FrontBasin`: 44 cards at two staggered depths below the foreground.
- `ForegroundCanopies`: 26 lower framing cards that close the bottom corners.
- Side/front groups use zero secondary offset, retaining natural perspective
  parallax without sliding their roots. Reduced motion restores authored bases.
- The previous 160-card oval boundary, 104 small interior plants and three
  explicit save-safe interior tree footprints remain. New woodland is entirely
  outside the gameplay grid and adds no collision/navigation blockers.
- Ground material exposes Meadow Warmth (0.55), Grass Detail (0.8), and the
  retained Lower Shadow Strength (0.62). These are native Inspector-editable
  parameters. Important values are explicit, avoiding headless shader-default
  reflection returning null.

## Source/provenance and authoring

Bound source revision remains `forest-bg1-wrap/2026-09-17.001`. No new raster
generation, resampling, recoloring, paid API call, compiled catalog asset or
promotion occurred. All source hashes continue to pass `forest_wrap_runner.gd`.
The user-supplied sources remain private-prototype-only; distribution rights
are not established by this scene edit or review.

| Source | SHA-256 |
| --- | --- |
| Current visual reference (review only) | `97d568be6c84cd6a3a0e63c4399a19e9972861149e1bf8a7f180e2b62ef2964d` |
| Existing foliage atlas | `ee0ed7a9f64646e8205801b671ba06591fa587f7dc79efc1ede5efb390c9743f` |
| BG-1 distant | `537f2a74f01cdcf16c8bfa23bdc9854869717134ccdef3a2d6d1cde0d94a1f63` |
| BG-1 middle | `7e699e3662a89787c75df7a020881e73a767f29e240cf2c1973c6ee3704c93a6` |
| BG-1 foreground | `e6b4f554fafec70e5f1971695ff49cef8f22099936351cbcaf8ceeb9bd5fd2c7` |

`tools/build_woodland_transition.gd` is an offline placement helper using its own
seed 170926 and the shared terrain sampler. The output contains editable native
nodes, not runtime generation. Independent runs match actual card transforms,
regions, pivots, pixel sizes, flips and colors. The semantic layout hash is
`063f87d999cbf0c22c6ae4a7d0fb6c81631f01e7ff19f24d69040f0d0ff3d2a5`.
PackedScene-generated resource/node IDs may differ, so whole-file hashes are
not the determinism test. An attempted overwrite without `--replace` exited 1
and left the existing file SHA-256 unchanged:
`26656c35aac60a4af4d148ab8ec4afe18f1c333d64b3f36bbb1f0dadae8d9928`.

## Validation results

Godot 4.7.2 Compatibility renderer, OpenGL on Apple M5, isolated `--test-mode`.
No user save was loaded or changed.

| Check | Result |
| --- | --- |
| Forest camera/source/navigation matrix | 10,243 checks, 0 failures |
| Scene builder, GPU coverage/motion and independent authored-candidate comparison | 1,320 checks, 0 failures |
| Scene builder headless with authored-candidate comparison | 1,284 checks, 0 failures |
| Scene builder headless suite entrypoint without optional comparison | 1,073 checks, 0 failures |
| Care camera | 94 checks, 0 failures |
| Care reference | 26 checks, 0 failures |
| Care map view | 29 checks, 0 failures |
| Day/night and reduced motion | 78 checks, 0 failures |
| Shared battle Sprite-in-3D presentation | 526 checks, 0 failures |
| Skill validation | Both skill entrypoints valid; new UI metadata and routed references valid |
| Whitespace validation | `git diff --check` clean |

The forest matrix renders center, N/S/E/W, nearest and farthest zoom at
360×640, 390×844, 430×932 and 1280×720, plus dawn/day/dusk/night at each size.
Representative captures and raw validation logs are in
`docs/reviews/forest-scene-builder/`; the full view matrix is under `matrix/`.
The newer scene-builder structural test is included in `tests/run_tests.sh`.

For the layers-on/off comparison, the portrait region covers the lower basin
(bottom 43% of the viewport). Wide overview shows the same type of gap behind
the plateau, so its review region is the rear belt at 12–32% viewport height.
Pixels differing by more than 0.015 in any RGB channel count as affected.

| Viewport | Gap region affected by the new layers |
| --- | --- |
| 360×640 | 34.1% |
| 390×844 | 39.3% |
| 430×932 | 39.4% |
| 1280×720 | 34.6% |

This is coverage evidence, not an assertion that every changed pixel was an
exposed seam. Visual inspection checks the actual junction and open sightlines.

Subpixel captures use 0/0.25/0.5/0.75/1-pixel equivalent horizontal camera steps
with the light-shaft animation frozen. Changed-pixel ratios in a stationary
side-foliage crop increase with displacement (about 10.7–20.7% at 0.25 px,
25.9–41.9% at 1 px, depending on viewport). Returning to the original camera
restores the crop within the <0.1% tolerance at all four sizes. These checks
support stable/reversible detail, not a universal claim of zero pixel stepping.
Motion frames are archived under `subpixel/`.

## Handoff

Restart the running Godot scene to load the edit. Open
`care_transition_woodland.tscn` to move individual lower cards, or the active
care scene to tune its full composition. Regenerate to a separate candidate
before replacing hand edits. The new skill's forest findings explain the
current profile; its beach handoff is ready for the next scene task.

This completes the requested working-scene and skill work. No human catalog
approval was fabricated. Formal asset promotion and sustained mobile-hardware
FPS certification remain separate, unperformed activities.
