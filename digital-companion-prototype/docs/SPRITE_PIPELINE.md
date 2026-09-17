# Sprite and arena pipeline

Codex coordinates creation; this project owns deterministic compilation,
validation, Godot resources, and runtime selection. Python 3.9+ and Pillow 11.3.0
are required. The old web-app project is not a runtime dependency and was not
modified.

## Setup and operations

From the Godot project directory:

```sh
python3 -m venv .venv-sprites
.venv-sprites/bin/python -m pip install -r tools/sprite_pipeline/requirements.txt
./tools/sprites --help
./tools/sprites new --asset my-companion --revision v1 --kind animation --provider codex-imagegen
./tools/sprites generate --plan assets-source/my-companion/v1/source-plan.json
./tools/sprites ingest --plan assets-source/my-companion/v1/source-plan.json --input /absolute/pose.png --role keypose.n
./tools/sprites review --plan assets-source/my-companion/v1/source-plan.json --stage keyposes
```

The launcher prefers `.venv-sprites/bin/python`; `SPRITE_PYTHON` overrides it.
Godot is selected through `--godot`, `GODOT_PATH`, PATH, or the standard macOS
installation. Nothing automatically installs dependencies or submits paid work.

`new` supports `animation`, `atlas` (effects, UI, props), `tileset`, and `arena`.
Edit the source plan to declare actual frames, timings, crops, and geometry.
`ingest` copies each PNG into its source revision and binds a role to SHA-256;
existing roles cannot silently change. Images are never accepted directly as
runtime assets. Correcting an already bound pose uses a new source revision.

After a human actually reviews all key poses or the environment sample, record
their decision explicitly. Never invent the reviewer, decision, or notes:

```sh
./tools/sprites review --plan assets-source/my-companion/v1/source-plan.json --stage keyposes --approve --reviewer 'Actual reviewer' --notes 'Actual decision'
# Ingest completed frames; expand clip sequences/timing in the plan.
./tools/sprites compile --plan assets-source/my-companion/v1/source-plan.json
./tools/sprites validate --candidate /absolute/candidate-directory
./tools/sprites review --candidate /absolute/candidate-directory
./tools/sprites review --candidate /absolute/candidate-directory --approve --reviewer 'Actual reviewer' --notes 'Actual final decision' --no-launch
./tools/sprites promote --candidate /absolute/candidate-directory --review /absolute/final-review.json
```

Keypose approval binds exact source bytes and identity, canvas, required actions/
facings, and motion profile. Completing clip sequences does not invalidate that
first gate. Final approval binds the entire compiled tree, including native
resources; changed inputs, changed output files, or extra files invalidate it.
Approval receipts are local audit evidence, not cryptographic human identity
verification. Only record them in response to a real human decision.

`review` without `--approve` never writes approval. Final review opens the Godot
review scene; `--no-launch` only prints review metadata. Review and exporter
processes pass `--asset-review`, isolating them from the actual companion save.
`compile --no-native` supports compiler testing only and cannot be promoted.

## Standard creature sheets and temporary effects

Create a reusable authoring sheet with the project compiler CLI:

```sh
./tools/sprites sheet-template --asset my-companion --revision idle-v1 --action idle --frames 4 --duration-ms 125
```

This creates blank **1024×1024 RGBA8 PNGs**, an optional **guide-overlay.svg**,
and an ordinary validated `source-plan.json` in the new source revision.
Each cell is **128×128**, eight columns run in time order, and rows run
**N, NE, E, SE, S, SW, W, NW**. Frames after column eight continue on another
sheet. The root/foot pivot is always **(64,120)**, normalized as **(0.5,0.9375)**.
The SVG is a separate registration guide: never bake its grid or labels into art.
The blank PNGs are authoring resources, not candidate or runtime artwork.

`clips.frames` is the authoritative used-cell list with explicit source role,
rectangle, duration, pivot, and root/mouth/hand/impact anchors. `sheetLayout`
documents the initial sheet layout for authors. Only declared clip frames enter
the compiler; unused transparent cells are ignored, and a declared empty cell
fails compilation. Change the non-root anchor coordinates to match each actual
pose; defaults are registration suggestions, not inferred anatomy. Frame durations
may vary within a clip. Never trim, rotate atlas cells, or automatically recenter.

Paint the sheets, ingest them using roles such as `sheet.idle.0000`, and ingest
the eight keyposes under their declared roles. Continue with the existing
keypose-review → compile → final-review → promote workflow above. Source hashes,
two-pixel padding, one-pixel extrusion, per-frame anchors, and authored timing
remain governed by the existing compiler. Creating a template grants no approval.
Choose the sheet layout before keypose review; changing layout metadata after
approval requires a new keypose review.

Preview temporary care/combat effects without a candidate or real save:

```sh
/Applications/Godot.app/Contents/MacOS/Godot --path . res://scenes/asset_review_scene.tscn -- --asset-review --placeholders
```

The selector exposes feeding plus/happy face, petting hearts, sickness, basic
melee, species special, general/fire/poison/freeze hits, knockdown, and stun.
Switch among all three species, facing, zoom, time scrub, and reduced motion.
Legacy pose fallbacks are labeled. These are presentation placeholders; poison,
freeze, knockdown, sickness, and stun have no new gameplay effects.

`CompanionEffects` is a separate Node2D under an avatar's ground root:
`play_effect(id, seconds=1.2)` runs a care overlay; `sample_effect(id, progress)`
samples battle/review time in [0,1]; `clear_effect()` removes it. Set
`reduced_motion` and scale the node to the creature's displayed canvas size.
It never changes creature frames, moves the avatar, emits gameplay events, or
applies damage. Ground root is (0,0), with positive X facing right; for a leftward
attack mirror this effect node's X scale, never rotate the creature.
The procedural overlays use Godot's documented
[custom drawing API](https://docs.godotengine.org/en/stable/tutorials/2d/custom_drawing_in_2d.html).

Offline checks:

```sh
.venv-sprites/bin/python -m unittest discover -s tests -p test_sprite_pipeline.py
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script res://tests/placeholder_effects_runner.gd -- --asset-review --placeholders
```

## Providers and billing

`codex-imagegen` returns a conversation brief and source roles. Use Codex's image
tool, inspect its results, and ingest approved candidates. The Python CLI does
not pretend it can invoke Codex's image tool. `manual` follows the same flow.
`generate --execute` for those two providers only saves the brief under `work`.

PixelLab uses the real documented `/v2/generate-image-v2` and
`/v2/animate-with-text-v3` endpoints. A `generation.jobs` entry supplies `id`,
`stage` (`keyposes` or `final`), `operation`, `description`, and a fixed positive
`seed`. Image jobs use `imageSize: [w,h]` and optional source-role `references`.
Animation jobs use source-role `firstFrame`, optional `lastFrame`, and an even
`frameCount` from 4 to 16. Animation dimensions are at most 256 square and the
total requested pixel count at most 524,288. Completion requires approved poses.

```sh
export PIXELLAB_API_TOKEN='your-token'
./tools/sprites generate --plan /absolute/source-plan.json --job keypose-n
./tools/sprites generate --plan /absolute/source-plan.json --job keypose-n --execute --allow-billable
./tools/sprites generate --plan /absolute/source-plan.json --job keypose-n --resume
```

The default is zero-network, zero-write dry-run. Each execution submits exactly
one job, writes durable submission intent before POST, and persists the returned
job ID before GET. Each invocation performs at most one status GET; resume after
5–10 seconds while processing. A failed/uncertain POST is never retried. If no
job ID was returned, reconcile the provider account before choosing a new job.
Resume binds the same asset, revision, job, operation, and exact transmitted
request hash. Unrelated source ingestion or edits to other jobs do not strand a
pending job; changing its referenced image bytes or request parameters is still
rejected. The original full source-plan hash is retained separately as provenance.
Completed provider PNG bytes are preserved, bounded, checked
for requested dimensions, and remain unapproved. Output frame count is reported,
not silently relabeled or forced to equal the requested count.

## Portable manifests and battlefield geometry

Animation plans declare fixed `canvas: [w,h]`, `requiredFacings` (uppercase N, NE,
E, SE, S, SW, W, NW), `requiredActions`, `keyposes`, and full `action.variant` clip
IDs such as `basic_attack.ne`. Legacy `.default` remains supported. Each frame
has `source`, optional `[x,y,width,height]` crop, positive `durationMs`, normalized
`pivot`, and named normalized `anchors`; clips retain `events`, `kind`, and
`qualityProfile`. No trimming, rotating, per-frame recentering, scaling, or alpha
threshold is applied. Atlas gutters copy exact edge pixels. The compiler emits
the established `atlas.json`, `atlas.png`, and `animation-set.json` contract.

TileSet plans use `textureSource` and `tileset` with `projection`, `tileSize`,
`tiles`, `terrains`, and `customDataLayers`. Every tile explicitly identifies
`atlas:[x,y]` and `alternative`; alternative zero must exist. Tile metadata
supports probability, terrain sets/peering, polygon arrays `collision`,
`navigation`, `occlusion`, and typed `customData`. Polygon points are local
texture coordinates. Tiles retain complete grid cells and never trim or rotate.
Native Godot validation additionally checks polygon intersections, peering modes,
and typed layer references before producing `tileset.tres`.

Compiler 1.3.1 preserves atlas-entry `pivot` metadata in `atlas.json` and uses
Godot's [lossless PortableCompressedTexture2D](https://docs.godotengine.org/en/stable/classes/class_portablecompressedtexture2d.html)
for self-contained native atlas storage. This avoids oversized raw pixel arrays
in `.tres` without changing source pixels or relaxing file limits. Native atlas
validation checks every frame region and compares the decoded texture bytes to
the compiled PNG. Previously compiled candidates remain untouched; recompile
source plans with the current compiler before requesting new final approvals.

Arena manifests have integer `ground:{width,height,cellSize}`, `maxBodyRadius`,
`spawns:{player:[x,y],opponent:[x,y]}`, and explicit obstacle records:

```json
{"id":"rock","rect":[270,70,80,50],"movement":true,"projectile":true,"sight":false,"occlusion":false}
```

Projection is `square` or `isometric`; it never changes ground-unit combat
distances. Optional `tileSet:{assetId,revision}` must reference an already promoted
revision; `tiles` place `{cell:[x,y],atlas:[x,y],alternative:0}` records. The compiler
pins dependency content hashes. A TileSet tile with collision must declare
`combat:{cellSize,rect:[dx,dy,w,h],movement,projectile,sight,occlusion}`. Its rectangle
is the single movement-collision authority, in explicit ground units within its
declared cell. Arena `ground.cellSize` must match it. Both the Python compiler
and native exporter derive the local tile collision polygon from that rectangle,
tile pixel size, and square/isometric projection; a separately supplied collision
polygon cannot override it. `movement:false` emits no native collision polygon.
The compiler derives shared `tile-x-y` arena obstacles from the same record.
Projectile/sight/occlusion flags remain independent. No footprint is inferred
from image alpha or visual perspective, and decorative canopy can remain
movement-free. Navigation and occlusion visual polygons are separate authored
metadata and never override the shared movement footprint.

Arena validation uses body-expanded obstacle sweeps, four-neighbor connectivity,
three clear cardinal exits per spawn, reachable spawn-to-spawn routes, and open
evasion patches. It rejects thin separating walls, disconnected walkable islands,
overlapping spawns, and unusable clearance. This production-layout gate is
deliberately stricter than the runtime's minimum structural validation. Terrain
art does not replace these checks or the review scene's seeded test bouts.

## Sprite-in-3D environments and habitats

Environment v1 keeps gameplay geometry in ground pixels while presenting art on
an XZ world at exactly 32 pixels per meter. Every manifest pins the canonical
`sprite-in-3d-portrait-v1` presentation profile (version 1, 32 pixels/meter,
28-degree FOV, 50-degree pitch, +8-degree sprite tilt, `KEEP_WIDTH`). These
constants cannot drift by biome. `camera.movementBounds` bounds focus/panning,
and an ordered `camera.dollyBounds` (2–60 meters) bounds fixed-axis framing.
`terrainChunks` define ground rectangles, subdivisions, and explicit texture
roles. `spritePlanes` and `ambientPlanes` define authored pivots, positions,
pixel scale, alpha mode, and depth behavior. `planeStacks` group those cards but
refer to a separately authored `groundFootprint` and navigation profile. Artwork
alpha never creates gameplay collision.

The v1 camera does not orbit and authored cards may not yaw. Every sprite-plane
`rotationDegrees.y`, habitat `rotationQuarterTurns`, and arena-presentation
`rotationDegrees` must be zero. Use an authored directional stack in a future
schema version rather than turning a flat stack edge-on. X/Z card rotations are
allowed for in-plane composition and restrained pitch adjustments. Opaque and
alpha-cut material records must use `depthBehavior: "write"`; translucent
records must use `"prepass"`. The unsupported `"test-only"` mode is rejected.
Ambient planes are therefore always transparent/prepass.
Every transparent/prepass plane also declares an integer `renderPriority` from
-16 through 16; opaque and alpha-cut cards use priority 0. Environment v1 caps
terrain chunks at 64, sprite planes at 512, stacks at 256, ambient planes at 64,
habitat placements at 512, and arena presentation placements at 256.

A terrain chunk may select an exact bounded source rectangle:

```json
{
  "id": "clearing",
  "source": "ground",
  "sourceRegionPx": [128, 96, 768, 512],
  "groundRect": [0, 0, 1280, 1536],
  "elevation": 0,
  "subdivisions": [10, 12],
  "alphaMode": "opaque",
  "depthBehavior": "write"
}
```

Compilation preserves the immutable hash of the complete `ground` source and
deterministically extracts the declared RGBA region. The emitted chunk retains
`source` and `sourceRegionPx`, adds `textureBinding: "terrain.clearing"`, and
the runtime texture table points that binding at
`textures/terrain.clearing.png`. Uncropped terrain uses its source role as the
binding. Runtime code must resolve `textureBinding`, falling back to `source`
for compatible manifests, and must not crop the already-derived texture again.
Validation compares every derived pixel with the hash-bound original region.

Authored source cuts use `derivedImages`, keyed by output source role. Each
record binds the parent role/hash, output hash, a portable transformation-script
path and digest, and a versioned declarative recipe. The compiler never executes
that authoring script: it reproduces supported recipes internally and compares
both decoded RGBA pixels and deterministic PNG output hashes. The initial
`green-shade-tree-depth-cards-v2` recipe records crop/output sizes, padding,
alpha threshold, BOX resampling, masks, minimum overlap, and semantic card role.
Changing the script, parent, parameters, or output invalidates the source plan.

Environment provenance uses one canonical kind: `hand-authored`, `generated`,
`source-derived`, or `hybrid`. DigimonUP cuts use `source-derived` with the
`private-prototype-only` license notice. Every filesystem source binding must be
relative to its source plan. Absolute POSIX, home-relative, UNC, Windows-drive,
or `file:` paths are rejected recursively anywhere in environment and habitat
plans—including generation briefs and nested metadata—and are not emitted in
runtime manifests or candidate metadata.
Known DigimonUP source hashes are held in a project registry. A matching source
cannot claim `commercial-use-cleared` or `public-domain` merely by changing its
filename or metadata; validation requires `private-prototype-only`. Derived
DigimonUP sprite-plane sources must include a machine-verifiable `derivedImages`
record.

Environment compilation still requires a real sample/keypose review and emits a
candidate whose environment review status is pending. Habitat manifests pin an
already promoted environment content hash. Neither deterministic cropping nor
native export bypasses final human review or promotion.

## Storage, rollout, and verification

The September 13 PixelLab review set is integrated as `2026-09-15.001` for
Botamon, Koromon, and Agumon, following John's September 15 request to update
the app. `assets/runtime-catalog.json` selects these packs: 18 clips and 175
frames, with the reviewed timings and fixed (64,120) registration. Botamon and
Koromon have four care clips each; Agumon has four care and six battle clips.
The right-facing artwork uses the existing horizontal mirroring policy.
Listen uses idle, and celebrate/play use happy. Pepper Breath remains a body
animation accompanied by the separate world projectile effects.

`tools/integrate_reviewed_animations.py` imports the exact hash-checked review
frames, compiles native resources, and validates them. `--promote` records the
existing integration instruction and selects the packs through normal promotion;
it submits no provider requests. Source plans and approval records are preserved
under `assets-source/<species>/2026-09-15.001`. The old packs remain available
for pinned historical replays. Compiler 1.3.2 uses the lossless embedded atlas
texture for animation exports too, keeping larger sets below the payload limit.
`tests/reviewed_animations_runner.gd` verifies catalog selection, all clip counts
and durations, mirroring, care locks, and battle terminal-frame sampling.

Versioned source plans live in `assets-source`; candidates and provider receipts
live in ignored `work/sprites`. Promotion copies approved bytes into immutable
`assets/generated/<assetId>/<revision>` and atomically replaces
`assets/runtime-catalog.json` under a writer lock. Catalog entries retain old
assets and select a complete revision, never half-written files. Existing assets
remain the fallback until an approved replacement is promoted. Agumon and forest
source templates are supplied, but their artwork and approval are intentionally
pending; one-frame animation placeholders are not production animations.
Promotion also archives final approval in the source revision's `reviews` folder
and links it from the catalog, so cleanup of ignored candidates cannot erase the
human review trail.

The payload hash includes every file except root `candidate.json` (whose fields
are separately hash-bound) and a regular `<known-payload>.png.import` sidecar
beside a PNG already listed in `candidate.json.files`. Godot creates these local
editor caches after import; promotion does not copy them. Orphan/unrelated
sidecars, symlinks, extra scripts/settings, and changed PNG/JSON/native resource
bytes still invalidate review. This narrow exception is safe because generated
PNG export and runtime decode the exact hash-bound raw bytes with
`Image.load_png_from_buffer`; Godot import settings cannot alter those pixels.
Environment `.tres` files store only relative texture bindings and their exact
SHA-256 dependency map, never decoded full-resolution pixel arrays. Legacy care
assets retain normal Godot
imports for packaged-game compatibility. See Godot's
[import process](https://docs.godotengine.org/en/4.7/tutorials/assets_pipeline/import_process.html).

Promotion-time validation runs a separate headless Godot probe which loads the
native `.tres`, checks its concrete resource type, compares required manifest
and relative dependency metadata, verifies the exact plan/compiler/native build
identity, hashes and decodes every external environment PNG, and configures the
real `EnvironmentView3D`. Missing, swapped, tampered, absolute, or escaping
texture paths fail the probe. Environment native metadata is capped at 2 MiB so
accidental pixel embedding cannot silently return. A `nativeResources` boolean
or a file with a `.tres` suffix is not renderability evidence by itself.

Use `fixture-check` to verify a source plan and complete immutable candidate as
one reproducible unit and print its aggregate fingerprint:

```sh
./tools/sprites fixture-check \
  --plan assets-source/environments/green-shade/spike/source-plan.json \
  --candidate work/sprites/<asset>/<revision>/<build-id> \
  --require-native
```

The deliberately non-promoted Green Shade development fixture has its own
read-only equivalent:

```sh
.venv-sprites/bin/python assets-source/environments/green-shade/spike/build-dev-fixture.py --check
```

```sh
.venv-sprites/bin/python -m unittest discover -s tests -p test_sprite_pipeline.py -v
SPRITE_NATIVE_TESTS=1 .venv-sprites/bin/python -m unittest discover -s tests -p test_sprite_pipeline.py -v
```

The offline suite uses synthetic pixels and synthetic approvals only inside
temporary directories, and mocks paid transport. The optional native test invokes
installed Godot against those temporary candidates, including a real editor
import/reimport with changed PNG settings, unchanged review pixels, idempotent
promotion, and pinned TileSet dependency checks. No provider credits are used.

Implementation sources: the previous web project's pinned-source compiler and
non-retrying PixelLab adapters; [PixelLab OpenAPI](https://api.pixellab.ai/v2/openapi.json)
(payloads checked 2026-09-09); Godot's [SpriteFrames](https://docs.godotengine.org/en/4.7/classes/class_spriteframes.html),
[TileData](https://docs.godotengine.org/en/4.7/classes/class_tiledata.html), and
[ResourceSaver](https://docs.godotengine.org/en/4.7/classes/class_resourcesaver.html)
interfaces for the companion native exporter.
