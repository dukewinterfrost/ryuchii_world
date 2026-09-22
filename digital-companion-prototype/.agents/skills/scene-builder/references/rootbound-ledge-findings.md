# Rootbound Glade and sheer ledges — September 17

The user replaced the hill/slope direction with a sheer drop for the environment
style. Native home and first-stage battle now share `sheer_stage_mesh.gd`:
horizontal Y=0 cap, vertical cliff triangles, and a lower horizontal floor.
Home drops 16 world units; battle drops 12. `care_sloped_ground.gd` keeps its
legacy filename only; it no longer makes a slope.

## Geometry and placement

- Enlarge the complete irregular ellipse just enough to protect the gameplay
  rectangle and apron. A per-angle max/union with a rectangle created visible
  corner lobes, even after smoothing. An enclosing ellipse keeps the outline
  rounded and preserves 40×48 home / 30×36 battle coordinates.
- Use the polygon-aware shared height sampler for all authored card roots.
  A ledge has only two heights, so old sloped placements otherwise float.
- `tools/reground_home_ledge.gd -- --test-mode --replace` explicitly re-grounds
  the two current home foliage scenes. It preserves XZ, scale, flip, material
  and interior footprint positions. It never runs on game startup; do not run
  it against later intentional hand-edited elevations without checking them.
- `tools/build_rootbound_glade.gd` writes a candidate with `--output`; existing
  output needs explicit `--replace`. It uses a frozen pre-rework scene as the
  base, so rebuilding is not a way to preserve later manual scene edits.
- All trees, ferns and shrubs remain Sprite3D cards. Meshes represent terrain
  and contact shadows, not modeled foliage. No CollisionShape3D is generated.

## Composition and active routes

`scenes/environment_workshop/green_shade_battle.tscn` is the editable first-stage
field. Its 236 woodland/grass cards leave the central attack lane open; the
existing landmark stays at (15,0,9) with ground rect (400,240,160,96).
The floor uses the bound panorama grass crop plus an irregular worn clearing.

The real battle scene loads this native field through **Play regional battle
fields → Rootbound Glade** in isolated mode. Ordinary live play still resolves
approved immutable packages. Working art is not automatically promoted.

BG-1 cards use local base (15,-25,-44), subsequent offsets (0,2.6,5.45), pixel
sizes .10/.095/.09; home scales that set by 4/3. This is forest tuning, not a
universal biome profile. The lower floor occluded the old very low/far cards,
creating a horizontal band. A raised/farther replacement exposed the foreground
card's opaque bottom. Bringing the registered set forward and burying all
bottoms below the lower floor fixed both in the reviewed camera envelope.

F6 starts at a wide editable 128-unit camera distance; live combat still fits
the fighters using fixed 30° pitch / 32° FOV and its existing zoom controls.

## Evidence and useful checks

See `docs/ROOTBOUND_GLADE_REVIEW.md` and `docs/reviews/rootbound-glade/`.
`tests/rootbound_glade_runner.gd` checks both ledges, foliage rooting, unchanged
blockers, three portrait sizes, backdrop coverage and deterministic native
battle rendering. `--capture` emits five viewpoints and a wide overview.

Allow a small tolerance when reading mesh normals: Godot's compressed normal
decode is not exactly zero on vertical faces. Also test triangle normals from
the actual vertex geometry so that tolerance cannot conceal a sloped face.
GPU capture needs process frames after changing a camera transform; forcing
a draw immediately can capture the previous camera despite correct new state.

Original source bytes remain unchanged and private-prototype-only. Native
working scenes and this engineering review are not a human asset approval.
