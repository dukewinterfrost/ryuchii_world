# Green Shade Sprite-in-3D Spike

`res://scenes/green_shade_3d_spike.tscn` is an isolated technical proof for the
environment presentation layer. It does not replace the current care or battle
scenes and it does not own gameplay collision, navigation, or battle timing.

Run it from the project root:

```sh
/Applications/Godot.app/Contents/MacOS/Godot --path . res://scenes/green_shade_3d_spike.tscn
```

The top controls select `idle`, `move`, `eat`, `special_attack`, and
`pepper_breath`; the camera controls translate the fixed-angle perspective view
laterally. Without input, the scene cycles through the same sequence. The
currently promoted Godot Agumon set has no attack clip. Both attack controls
therefore keep a neutral looping body pose and explicitly report that only the
world-space Pepper Breath VFX is available. They do not relabel the eating or
movement art as an attack. If a later promoted set provides `special_attack`,
`pepper_breath`, or `pepper-breath`, the adapter selects that authored clip.

The spike deliberately proves these boundaries:

- Authoritative `Vector2` ground positions convert to XZ with 32 ground units
  per Godot world unit.
- `AnimatedSprite3D` consumes `CompanionAssetLibrary`'s existing `SpriteFrames`
  and normalized per-frame pivots. One-shot care actions return to idle and
  looping fallbacks never retain the action lock.
- Battle presentation is sampled from simulation ticks through `render_combat`
  and `render_battle`; authored nonuniform frame durations remain intact.
- Opaque sprite planes are unshaded, nearest-filtered, non-billboarded,
  non-fixed-size, alpha-cut, and depth-tested.
- The environment uses a 28-degree perspective camera at a fixed 50-degree
  downward pitch and a fixed eight-degree sprite-plane tilt.
- A single Green Shade tree is cut into facade/root, interior/trunk, and canopy
  cards. The source-density masks use broad, naturally occluded overlap: a
  closed lobed canopy hides the trunk card's top edge and a curved root card
  hides the lower-trunk join. The padded cards are BOX-prefiltered to `256x256`
  before nearest-filtered rendering and sit only `0.012` world units apart.
  This removes both the rectangular canopy bar and the one-pixel slice cracks
  visible in earlier spike revisions.
- Agumon's dogleg walk route stays outside the tree's authored `144x72`
  gameplay footprint. It crosses behind the tree, along its side, in front of
  it, and back along the other side so depth-buffer occlusion is visible without
  implying that artwork generated navigation.
- Agumon has a painted contact-shadow quad and Pepper Breath uses a world-space
  translucent `Sprite3D` preview.
- The UI remains ordinary `Control` nodes above the `SubViewportContainer`.

Run the focused smoke suite with:

```sh
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . \
  res://tests/environment_3d_spike_runner.tscn -- --test-mode
```

The runner validates the coordinate bridge, camera contract, manifest-driven
renderer, sprite material flags, plane stack, pivots, all demo actions, movement,
portrait viewport sizes, one-shot completion, non-locking loop fallbacks,
nonuniform deterministic battle sampling, the five manifest review viewpoints,
source-region crops, frustum-aware edge clamping, screen-ray rejection, and
battle determinism while the 3D view exists.

The spike runtime loads
`res://tests/fixtures/environments/green-shade-3d-spike/environment.json`, a
compiled-schema development fixture, never the authoring source plan. The
fixture was emitted directly by the pipeline's deterministic environment
compiler and deliberately has no approval receipt, candidate metadata, or
catalog entry. This keeps the technical proof runnable without fabricating
human review or weakening the production promotion gate.

The exact `Green_Shade_Ground.png`, `Green_Shade_Tree.png`, and
`Green_Shade_Top.png` files are hash-bound in
`assets-source/environments/green-shade/spike/source-plan.json`. Three bounded,
offset ground chunks are no longer used: one bounded `2048x390` cobblestone
crop is compiled onto one `10x12` subdivided horizontal mesh, leaving no
internal chunk boundary. The lower rooted cliff stays vertical on an upright
rear card; it is never stretched across the floor. The three target-density
tree textures are deterministic source-derived masks made by
`assets-source/environments/green-shade/spike/build-derived-tree-planes.py`;
their colors are reproducibly BOX-prefiltered from the bound source, never
painted or generated. The source plan binds the parent image, script, complete
recipe, and outputs by SHA-256. All of these DigimonUP-derived assets are
`source-derived` and `private-prototype-only`. Visual approval and promotion are
still explicitly required before production use.
