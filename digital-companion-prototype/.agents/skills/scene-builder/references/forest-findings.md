# Forest reference and seam-concealment findings

**Later September 17 direction:** the user replaced the sloping shoulder with
a sheer ledge in home and battle. Read [the ledge findings](rootbound-ledge-findings.md)
for the current geometry, re-grounding and background positions. The slope
experiments and numeric camera registration below describe the earlier pass.

## Current composition and source authority

The September 17 reference depicts a warm, irregular grassy clearing, a winding
dirt path, overlapping dark foreground growth and an open mountain skyline.
The implementation adopts those relationships without copying its art or
regenerating existing textures. It preserves the user's lowered dark shoulder.

Native home scene: `scenes/environments/care_clearing.tscn`.
Source bindings: `assets-source/forest-bg1-wrap/2026-09-17.001/source-plan.json`.
BG-1 supplies distant/middle/foreground PNGs; the existing 1254×1254 foliage atlas
has SHA-256 `ee0ed7a9f64646e8205801b671ba06591fa587f7dc79efc1ede5efb390c9743f`.
These source bytes remain unchanged and private-prototype-only.

## What worked

- Keep the flat 40×48 gameplay rectangle plus apron; slope only the visual
  shoulder. `care_sloped_ground.gd` is the shared height sampler for mesh and
  offline foliage placement. Duplicating the height formula in another language
  would let tree roots drift after terrain edits.
- The bright rim is not the place to fill every hole. A separate
  `care_transition_woodland.tscn` supplies lowered RearGrove, SideValleys,
  FrontBasin and ForegroundCanopies layers. The original oval's 160 boundary
  cards, 104 small plants and three save-safe interior oaks remain intact.
- New transition roots are buried 0.45 world units. The rear layer has a small
  0.018 secondary parallax factor; grounded side/front groups use zero. Depth
  still changes through the perspective camera. All are Sprite3D cutouts.
- The helper moves any too-high transition root farther out into the basin
  until sampled terrain is at or below -8.5. Lowering just its Y would bury or
  detach the plant from the ground rather than giving it a valid lower position.
- Lowered decor uses cool dark base modulation, then receives the existing
  day/night tint once. Its silhouette overlaps the ground/backdrop junction,
  so the dark basin reads as a forest rather than an empty untextured apron.
- Warm meadow patches and quantized, spatially varied grass marks add detail
  to the playable ground. Apply this only on the plateau; leave the lower
  terrain's 0.62 shadow strength and height profile intact. Path-edge noise
  roughens the margin without changing navigation or the central resting spot.

## Fragile areas and rejected approaches

- Independently shrinking middle/near background images broke their canvas
  registration. Large depth separations made foreground artwork loom at wide
  zoom. Current background relative scales are 1 / 0.95 / 0.90, referenced to
  world camera (20,27.7128,72); these are local forest tuning, not beach defaults.
- A farther backdrop behind the whole terrain exposed a dark raised-looking
  far mesh border. Fix the ordering/overlap, not just the color of the gap.
- A short sky card exposes a rectangular top in portrait. The current sky
  shader extends the clear upper sky with remapped UVs; painted mountains retain
  their aspect ratio. Extending a cyan horizon gradient upward produced an
  obvious band; the extension now uses upper-sky colors.
- Dense plants with equal spacing or identical base heights still read as rows.
  Use uneven clumps and stagger depths. At the lowest foreground, inspect the
  bottom corners separately; filling the rear does not close those gaps.
- Secondary parallax applied in the wrong parent's coordinate space can move
  nested cards too far. Cache local bases and convert the world delta into that
  parent's basis. Explicit Vector3 typing avoids GDScript inference failures.
- Godot PackedScene serialization adds varying node/resource IDs. Compare the
  actual transforms/material settings and the helper's semantic layout hash,
  not whole-file hashes, to verify repeatable authoring. Source PNG hashes still
  bind exact bytes.
- The headless renderer may return null for an implicit shader default. Important
  editable art-direction values are explicitly bound in the scene's material;
  GPU captures still verify their rendered effect.

## Editing and repeatable authoring

Open the live care scene or open `care_transition_woodland.tscn` directly. Nodes
are ordinary editable sprite cards. Rebuilding is an optional authoring action,
not something that runs on startup. Write a separate candidate first:

```sh
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . \
  --script res://tools/build_woodland_transition.gd -- \
  --test-mode --output /tmp/woodland-candidate.tscn
```

Do not add `--replace` to an existing hand-edited scene unless replacement is
the intended action. The helper samples seed 170926 with its own RNG and checks
the atlas hash. A terrain-profile change requires re-grounding the transition
cards and the original oval foliage, followed by a visual review.

The active three interior trunk rectangles remain in
`scripts/environment/native_care_scenery.gd`. Moving those three roots requires
updating the corresponding rectangles; transition woodland remains outside
the gameplay grid and adds no blockers.

## Evidence

Current pass evidence and final captures live in `docs/reviews/forest-scene-builder/`
and `docs/FOREST_SCENE_BUILDER_REVIEW.md`. The relevant automated entry points are
`tests/forest_wrap_runner.gd` and `tests/scene_builder_runner.gd`, with the
existing care-camera, map-view, reference and day/night suites. A completion
report must cite the latest run, not inherited counts from the earlier sparse
or dense-rim passes. Human art approval and mobile-device FPS certification are
separate gates.
