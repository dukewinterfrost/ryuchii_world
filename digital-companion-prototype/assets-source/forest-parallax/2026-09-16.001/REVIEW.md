# Forest parallax — source preview

Status: pending human visual approval; not compiled or promoted. No generation calls.

Source archive: `Backgrounds.zip`, SHA-256
`4898fd2eaaf696f5b945c7abae783f9183eb04e1324fd5edb9db1d8736951a5f`.
The `generic/bg_2` full composition and sky are ingested unchanged through the
sprite pipeline. Exact image hashes are recorded in `source-plan.json`.
Working PNGs in `assets/environment_workshop/forest-parallax` are byte-identical
copies, not resampled or destructively cut. Rough masked intermediate layers
were intentionally excluded: separated movement exposes their leftover pixels.

Foliage reuses the sample-approved `care-woodland-foliage/2026-09-15.001`
source (`ee0ed7a9f64646e8205801b671ba06591fa587f7dc79efc1ede5efb390c9743f`).
This does not constitute final approval of the new field composition.

Also inventoried: `ocean-and-clouds-free-pixel-art-backgrounds.zip`, SHA-256
`b9b142a06f5221dda2fc4b48794ef3bfae654f8f1f7f92f330bc50bf6cb6247f`.
It is not used by the forest. Its license text links to Craftpix's license page;
no distribution-rights determination was made. Backgrounds.zip contains no license.
All supplied artwork is restricted to private prototype review pending clearance.

## Edit and preview

Run `open-battle-fields.command`, then choose Green Shade. This is an isolated
playable battle, not a catalog promotion or a real-save mutation.

Open `scenes/environment_workshop/green_shade_battle.tscn` in Godot for the whole
field. Open its `ForestParallax` instance (the separate `forest_parallax.tscn`)
to move individual tree/undergrowth cards. Transform X/Z places roots, Pixel Size
changes size, Region Rect selects an unchanged source quadrant, and Offset is
the authored foot pivot. Keep depth testing and alpha cut enabled.

Direct child metadata `parallax` controls extra movement with camera focus:
sky 0.18, vista 0.08, rear trees 0.025, grounded trees/plants 0.
The controller clamps extra displacement to 3 world units, uses authored base
positions (no accumulated drift), and restores them in reduced-motion mode.
Real depth-buffer perspective still applies to every card. No foliage meshes,
physics bodies, collision changes, or combat RNG are introduced.

Editor transforms are never animated automatically. `Preview Motion` is an
optional F6 camera-ray preview; the playable battle drives focus directly.
The blocker-bound landmark now uses the matching foliage tree; the legacy blue
canopy/interior slices are hidden (retained for reversible authoring). The blocker
itself is unchanged, so collision never becomes invisible.
The floor samples panorama rectangle `(760,700,40,22)` through `forest_floor.gdshader`:
nearest filtering, mirrored world-space tiling and restrained color modulation.
No source pixels were rewritten. `Floor.Source Region` and `Region Tile Meters`
are Inspector-editable; saved per-patch shader settings survive F6.
Only the active region loads these assets. Other four fields are unchanged.

Battle views have − / Fit / +, mouse-wheel and magnify-gesture zoom (65–200%).
Fit restores automatic fighter bounds; closer manual zoom can crop fighters.
The chosen factor survives render ticks and resize, and resets on environment
unload. Camera settings never enter simulation or replay data.

Before promotion, review camera extremes, occlusion, nearest-filter motion and
all three portrait sizes. A passing automated test is not human art approval.

## Verification — 2026-09-16

- Battle Sprite-in-3D runner: 364 checks, zero failures (Compatibility renderer).
- Battle controls runner: 71 checks, zero failures.
- Environment workshop runner: 122 checks, zero failures.
- Historical battle simulation/replay checksum unchanged.
- Working PNG hashes match the immutable source bindings.
- Distinct parallax rates, bounded displacement, zero accumulated drift, grounded
  plants, reduced-motion restoration and depth-tested alpha cuts are covered.
- Captured center/left/right/near/far at 360×640, 390×844 and 430×932.
  Inspected center at all three sizes and all four offset views at 390×844.
  Offset views deliberately override fighter framing for scenery review; normal
  gameplay retains fighter-aware framing. No claim of exhaustive performance or
  subpixel-shimmer certification; those remain final-review work.
- Representative capture: `docs/reviews/forest-parallax/center.png`.
