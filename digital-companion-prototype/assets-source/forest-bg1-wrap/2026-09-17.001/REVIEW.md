# BG-1 world surround

The latest reference-led woodland/Scene Builder pass is documented in
`docs/FOREST_SCENE_BUILDER_REVIEW.md`. This record retains the preceding
dense-rim pass and its source binding history.

Private native working-scene integration, using the user-supplied BG-1 reference.
No paid generation, no image recoloring/resampling, no catalog promotion and no
fabricated approval receipt. Sources are bound in `source-plan.json`; public and
commercial rights remain unverified. Human visual review remains pending.

## Implemented composition

- `bg_1_layer_3.png`: broad distant mountain/sky backdrop.
- `bg_1_layer_2.png`: middle tree/forest card, registered to the distant canvas
  with a 0.95 perspective scale. Flank copies stay hidden to avoid cropped joins.
- `bg_1_layer_1.png`: foreground meadow, registered at 0.90 scale and partly
  buried behind the shoulder. Layer roots keep real ordered depth, with modest
  separation and distinct bounded parallax, not independently resized artwork.
- The sky uses an upper-sky shader extension above the original canvas, retaining
  the painted mountains/clouds at their original aspect ratio. Portrait views
  no longer expose its rectangular top edge. All three layers overscan the tested
  horizontal camera bounds. Native Godot preview uses the same sky shader.
- `bg_1.png`: retained immutable assembled reference, not flattened over gameplay.
- The perimeter now has 160 cards: 121 shrubs/ferns and 39 trees. This adds
  78 low plants in nine irregular clumps and six rim trees to the previous
  76-card layout, still well below the old 394-card wall. The broad oval remains
  54×46 local units, scaled 4/3 in home. Dense pockets alternate with open
  sightlines; all boundary roots stay outside the 40×48 playable grid.
- Three smaller interior oaks sit at world XZ (9,12), (30,18), and (12,35).
  Their explicit 2×2 trunk footprints are shared by navigation and rendering.
  Existing saved decorations, companion positions and route access take priority:
  a conflicting tree is omitted, not the saved item moved. Only the native
  Green Shade fallback revision is affected; compiled regional packages are not.
- Home has 104 small, traversable plants, 50 more than the previous layout,
  with eight additional irregular interior clusters. Fern/reed and low flowering-bush silhouettes, scale, height,
  facing and restrained tint vary. Broad open pockets remain between clumps;
  the path and resting spot stay clear. The dirt resting spot is horizontally oval.
- The outer terrain is now a subdivided, genuinely sloping mesh: the playable
  grid plus a flat apron stays at Y=0, the surrounding shoulder drops up to
  16 world units, and the rear valley continues lower beneath the backdrop.
  Boundary foliage is grounded on that surface, lowering the tree crowns and
  exposing more mountains and sky. The path fades out down the shoulder.
- Height-based cool woodland shade now darkens the lowered shoulder and low
  foliage, keeping the playable plateau bright. Stable soft painted shade is
  rooted beneath the six new rim trees and three interior trees; no real-time
  shadow maps or 3D tree meshes were added. Native editor/F6 previews seed the
  same shade; the running scene removes shadows for omitted interior trees.
- The added planting uses authoring seed 984012, layered over the earlier
  927541 layout. All transforms are baked into native scene data: no runtime
  randomization, gameplay RNG use, or loss of Inspector editability.
- Battle keeps the existing rectangular composition. Its layout is not changed
  by the home-only `home_oval_layout` switch.
- All foliage is Sprite3D artwork. The old primitive tree/plant/flower branches
  remain hidden and recoverable. Only the non-playable ground is sloped; foliage
  remains 2D artwork, not tree or plant models.
- Near-lens outer foreground cards are hidden to prevent a wall of leaves when
  inspecting the south boundary. Low rim pockets remain rooted in place.
- Home navigation adds only the three explicit, save-safe trunk footprints.
  Spawns, saved items and battle collision/replay data are unchanged. Artwork
  does not generate collision. The existing Field UI intentionally continues
  to save camera preferences.
- Overview framing fits the visible oval rather than only the gameplay grid.
  Ground coverage extends south/west/east, the native far clip includes the
  distant BG-1 sky at full zoom-out. The terrain continues below the field and
  behind the backdrop instead of depending on a wall of foreground foliage.
  No source PNG was changed.

The camera remains fixed-axis (pan/dolly only), so this is a wrap around the
permitted views, not a free-orbit 360° scene. Additional orbit directions would
need new camera and card contracts.

## Time of day — no new raster versions needed

The existing local-time clock drives the same scenery, terrain, companion and
decorations. BG-1 retains its painted clouds/mountains; the sky shader applies
time-aware color and sky treatment. Dawn is rose, midday preserves the reference,
dusk is amber, and night is cool moonlight. Transitions and midnight wrapping
remain smooth and deterministic when the clock is injected for tests.

Use the running care scene's **Field** button and zoom controls to inspect the
surround. **F7**, or **More → Background → Lighting preview**, exposes the time
slider. “Use local time” restores the clock. Restart an already-running scene
to load these resource changes.

## Editable files

- `scenes/environment_workshop/forest_parallax.tscn`: layer positions, pixel scale,
  pivots, flank copies and per-layer parallax metadata.
- `scenes/environment_workshop/forest_boundary.tscn`: individual foliage cards.
- `scenes/environment_workshop/care_oval_foliage.tscn`: home-only oval rings and
  small middle grass tufts; every card is directly editable in Godot. The
  `Boundary` and `InteriorTrees` branches contain the added cards.
- `scenes/environments/care_clearing.tscn`: active home integration, overview
  bounds, home-only background overrides, ground extent and camera clipping range.
- `scripts/environment/care_sloped_ground.gd`: presentation-only terrain profile.
  Select `Ground` in Godot to adjust Edge Drop or Slope End, then toggle Rebuild
  Preview. Foliage transforms are authored separately; reposition roots if the
  slope profile is edited. Rebuild Preview also refreshes painted tree shadows.
  Do not shrink the flat apron into playable cells.
- `scripts/environment/native_care_scenery.gd`: explicit interior-tree rectangles
  and conflict resolution. If moving an interior tree in Godot, update its
  matching rectangle here too and rerun the root/footprint and route checks.
- `shaders/care_clearing_ground.gdshader`: lower-stage shade strength and soft
  tree-shadow treatment. These are presentation-only colors, not physics.
- `scripts/environment/forest_parallax.gd`: bounded camera offsets and clearance.
- `shaders/home_day_night_sky.gdshader`: BG-1-preserving sky treatment.
- `scripts/environment/time_of_day_controller.gd`: existing shared clock profile.

Working PNGs in `assets/environment_workshop/forest-bg1` are exact copies of the
ingested sources. Replacing a bound source requires a new source revision.

## Verification

`forest_wrap_runner.gd`: 4,363 assertions pass: all three layer bindings, all
four BG-1 source hashes and the reused foliage hash, asymmetric oval positions,
mixed plant silhouettes/scales, dense-vs-sparse spacing and footpath clearance,
outside-map roots, alpha/depth rules, camera clearance, backdrop clipping,
104 small interior plants, clustered rim density, nine added trees, explicit
trunk/root alignment, saved-decoration/companion conflicts, potty access,
grounded shade, horizontal backdrop overscan and extended portrait sky, both the
terrain function and actual mesh vertices staying flat in playable cells,
sculpted foreground coverage and unchanged saved gameplay state. Rendered center,
N/S/E/W, closest zoom and overview at 360×640,
390×844, 430×932, and 1280×720; rendered dawn/day/dusk/night at each size.

Relevant suites rerun: care camera 94 checks, day/night 78 checks, care map view
29 checks, care reference 26 checks, environment workshop 122 checks, home/save
v5 59 checks, care/habitat v4 38 checks, battle 526 checks; zero failures. Battle retains its historic
deterministic checksum. These checks do not constitute human art approval or
mobile-hardware performance certification.

Representative implementation-review captures are in `docs/reviews/forest-bg1/`.
The `dense-woodland-` captures show this latest pass; `open-rim-` and older captures
remain historical evidence. These are agent visual checks, not human approval.
Subpixel shimmer metrics and sustained mobile-hardware FPS are not certified by
this pass. The reused foliage atlas retains SHA-256
`ee0ed7a9f64646e8205801b671ba06591fa587f7dc79efc1ede5efb390c9743f`.
The removed foliage placements can be recovered from
`layout-history/organic-oval-before-open-rim.tscn`; the immediately preceding
sparse layout is `layout-history/open-rim-before-density.tscn`. No source art was deleted.

## Natural planting reference pass

Following the user's request to remove the overly planned appearance, inspected
the [Cult of the Lamb camp showcase](https://cdn.cloudflare.steamstatic.com/steam/apps/1313140/ss_89d47a4ad019aa21c799e3c1a73b8de57d350a5c.1920x1080.jpg?t=1649928777)
and the [starter clearing screenshot](https://www.mobygames.com/game/188798/cult-of-the-lamb/screenshots/windows/1142732/).
The compositional takeaway is uneven vegetation masses, larger focal clumps
with smaller nearby plants, irregular forest silhouettes and generous negative
space, not uniform scatter over the entire ground. This is an interpretation of
the screenshots, not a claim about that game's placement algorithm. No reference
art was imported or copied into the project.
No compiled asset IDs were produced; the source revision is
`forest-bg1-wrap/2026-09-17.001`. Final packaging/promotion must follow real review.

The referenced attachment and the archived assembled BG-1 reference have the
same SHA-256 (`371b65b3612683184030affcb8bdfe190df533ff78034ddcdc91099e6826da19`).
The requested native care-world integration is active; pending review here is
for future asset-catalog packaging/promotion, not an alternate hidden demo.
