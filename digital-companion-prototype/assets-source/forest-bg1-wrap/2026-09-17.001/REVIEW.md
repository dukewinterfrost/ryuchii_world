# BG-1 world surround

Private native working-scene integration, using the user-supplied BG-1 reference.
No paid generation, no image recoloring/resampling, no catalog promotion and no
fabricated approval receipt. Sources are bound in `source-plan.json`; public and
commercial rights remain unverified. Human visual review remains pending.

## Implemented composition

- `bg_1_layer_3.png`: broad distant mountain/sky backdrop.
- `bg_1_layer_2.png`: transparent middle tree/forest cards across center and flanks.
- `bg_1_layer_1.png`: transparent foreground meadow, placed in front of that band.
- `bg_1.png`: retained immutable assembled reference, not flattened over gameplay.
- The earlier sample-approved foliage sheet surrounds the home in a wider,
  gently irregular oval, with three staggered hedge rings, outer canopy rings,
  and deeper foreground forest. The inner oval is 54×46 local units, scaled
  4/3 in home. Roots stay outside the existing 40×48 playable grid.
- Home has 54 small, traversable plants in eight unequal clumps plus seven
  sparse singles. Fern/reed and low flowering-bush silhouettes, scale, height,
  facing and restrained tint vary. Broad open pockets remain between clumps;
  the path and resting spot stay clear. The dirt resting spot is horizontally oval.
- The forest rim has uneven angular spacing, asymmetric depth, and mixed-height
  fern and shrub groups, backed by trees of varying sizes. It retains a broad
  horizontal oval but no longer reads as evenly spaced hedge rows. The layout
  is baked into native scene transforms with authoring seed 91863: no runtime
  randomization, gameplay RNG use, or loss of Inspector editability.
- Battle keeps the existing rectangular composition. Its layout is not changed
  by the home-only `home_oval_layout` switch.
- All foliage is Sprite3D artwork. The old primitive tree/plant/flower branches
  remain hidden and recoverable. Floor is still a horizontal mesh.
- Near-lens outer foreground cards are hidden to prevent a wall of leaves when
  inspecting the south boundary. Rooted inner hedges remain in place.
- Navigation, spawns, save items, collision and battle replay data are unchanged.
  The existing Field UI continues to save camera preferences, intentionally.
- Overview framing fits the visible oval rather than only the gameplay grid.
  Ground coverage extends south/west/east, the native far clip includes the
  distant BG-1 sky at full zoom-out, and extra foreground cards conceal the
  terrain edge in tall portrait views. No source PNG was changed.

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
  small middle grass tufts; every card is directly editable in Godot.
- `scenes/environments/care_clearing.tscn`: active home integration, overview
  bounds, ground extent and camera clipping range.
- `scripts/environment/forest_parallax.gd`: bounded camera offsets and clearance.
- `shaders/home_day_night_sky.gdshader`: BG-1-preserving sky treatment.
- `scripts/environment/time_of_day_controller.gd`: existing shared clock profile.

Working PNGs in `assets/environment_workshop/forest-bg1` are exact copies of the
ingested sources. Replacing a bound source requires a new source revision.

## Verification

`forest_wrap_runner.gd`: 4,886 assertions pass: all three layer bindings, all
four BG-1 source hashes and the reused foliage hash, asymmetric oval positions,
mixed plant silhouettes/scales, dense-vs-sparse spacing and footpath clearance,
outside-map roots, alpha/depth rules, camera clearance, backdrop clipping,
foreground ground coverage and unchanged gameplay state. Rendered center,
N/S/E/W and overview at 360×640,
390×844, 430×932, and 1280×720; rendered dawn/day/dusk/night at each size.

Existing suites: care camera 94 checks, day/night 67 checks, care map view 29 checks, care reference 26
checks, environment workshop 122 checks, battle 526 checks; zero failures. Battle retains its historic
deterministic checksum. These checks do not constitute human art approval or
mobile-hardware performance certification.

Representative reviewed captures are in `docs/reviews/forest-bg1/`.
The `organic-` captures show the latest larger home composition; older captures
remain as historical review evidence. The reused foliage atlas retains SHA-256
`ee0ed7a9f64646e8205801b671ba06591fa587f7dc79efc1ede5efb390c9743f`.

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
