# Sprite-in-3D authoring and review

Use this reference when composing or reviewing environment depth. Preserve the checked-in environment, habitat, and arena schemas rather than creating parallel formats.

## Manifest contract

An `environment` v1 plan declares:

- `license.classification` and a non-empty notice. DigimonUP sources use `private-prototype-only`.
- `worldScale.pixelsPerUnit` and a perspective camera using `keepAspect: "width"`, FOV, pitch, sprite tilt, near/far planes, and ground-space movement bounds.
- One or more `terrainChunks` with a source role, ground rectangle, elevation, subdivisions, alpha mode, and depth behavior.
- One or more `spritePlanes` with source role, normalized pivot, local 3D position, rotation, pixel size, alpha mode, and depth behavior.
- Named `groundFootprints` and explicit `navigationProfiles`; each plane stack references one of each plus its component plane IDs.
- Optional transparent `ambientPlanes` with a 3D position, parallax value,
  explicit render priority, and `prepass` depth behavior.
- Exactly the `center`, `left`, `right`, `near`, and `far` review viewpoints.

Compilation copies each referenced, hash-bound PNG unchanged to `textures/<role>.png`; it emits `environment.json`, `environment-validation.json`, `environment-review.json`, and `environment.tres`. Review metadata is always emitted as pending, never as implicit approval.

A `habitat` v1 plan pins a promoted environment by `assetId` and `revision`. It has the exact 40×48×32 grid, explicit cell blockers, one free spawn, exactly three unique reachable waste anchors, at least one usable decoration zone, and static placements. A movement-blocking plane stack placement must reference a separate habitat blocker. Compilation adds the environment content hash and emits the habitat JSON, validation, pending-review metadata, and native resource.

An environment-backed arena keeps the existing ground, spawn, obstacle, tile, and combat validation. `arena.environment` pins a promoted environment; `arena.presentation.staticPlacements` names a plane stack, integer ground position, rotation, and optional obstacle. A movement-blocking stack must reference an explicit arena obstacle. Environment presentation never changes simulator geometry.

## Coordinate and presentation profile

- Gameplay owns a flat `Vector2` ground. Presentation maps `(x, y)` to `(x / 32, 0, y / 32)` in 3D XZ space.
- Begin from the shared profile: perspective `Camera3D`, 28° FOV, 50° downward pitch, `KEEP_WIDTH`, and sprite planes tilted 8° backward toward the camera.
- The camera may translate and dolly but not orbit. Sprite billboarding and fixed-size rendering remain disabled.
- Keep camera, tilt, pixel scale, and plane spacing in one validated profile. Do not tune each map into a different visual system.
- Characters and opaque props use nearest filtering, unshaded rendering, depth testing, and alpha-cut discard. Translucent VFX use an opaque depth prepass and explicit render priority while retaining depth testing.
- Use painted contact-shadow quads. Avoid realistic lights, GI, volumetrics, and real-time character shadows unless a later approved art direction replaces this profile.

## Slice roles

- **Ground:** horizontal walkable or decorative surface. Large terrain should be chunked or subdivided rather than stretched across one oversized plane.
- **Facade:** upright front face rooted at the landmark's gameplay footprint.
- **Roof/interior:** a distinct plane behind and/or above the facade that reveals modest parallax.
- **Side:** optional depth cue visible within the permitted camera translation, never a substitute for footprint data.
- **Canopy:** elevated foreground/overhead silhouette. It may be movement-free even when its trunk blocks movement.
- **Rear:** distant terrain or skyline outside gameplay interaction.
- **Ambient:** non-authoritative clouds, surf, particles, glows, or other effects.

Prefer source-plan crop rectangles over destructively rewriting a source PNG. Preserve transparent margins when they carry the intended pivot or prevent edge clipping. Generated material is limited to missing terrain extensions, seams, side faces, roof slices, and reusable prop families; the bound source set remains the style authority.

When a plane needs a deterministic derivative instead of a crop, add a
`derivedImages` record that binds the parent source hash, transformation script
hash, complete versioned recipe, and output hash. Prefer target-density cards to
feeding very large art through nearest-neighbor minification. For stacked tree
cards, use a closed natural canopy silhouette and at least eight source pixels
of overlap hidden beneath an occluding silhouette. Reject open crops, long
straight opaque runs adjacent to padding, and one-pixel joins.

## Plane stacks

A reusable tree, building, cliff, or machine stack must have:

- A named set of ground/facade/roof/side/canopy/rear planes with explicit textures, pivots, transforms, pixel scale, alpha behavior, and depth behavior.
- One gameplay footprint in ground coordinates, stored separately from visual planes.
- Optional sight, projectile, and occlusion records that remain independent of movement.
- A root position shared by the home and battle placement systems.
- Camera-safe spacing: enough separation to reveal depth, but not enough to look detached when viewed from the center, left, or right camera bounds.

Never add a second collision authority to a render plane. A canopy, roof, or rear plane is not blocking unless the explicit ground record says so.

## Layout rules

- Build each biome kit once, then make a distinct home layout and battle layout from it.
- Home: protect the companion spawn, waste/potty anchors, decoration zones, and path connectivity after placed solid decorations are included.
- Battle: preserve body-expanded spawn clearance, reachable spawn-to-spawn routes, three clear cardinal exits per spawn, and usable evasion patches. Use the existing arena validator rather than visual judgment alone.
- Keep character sprites, combat effects, and props in the same depth-tested world. Keep HUD and input chrome in the existing 2D UI layer.
- Ray-project touch or pointer input onto the XZ ground; 3D physics must not become the gameplay authority.

## Required review views

Capture and inspect all five views at the project's target portrait sizes:

1. **Center:** baseline framing and overall scale.
2. **Camera-left:** maximum permitted left translation.
3. **Camera-right:** maximum permitted right translation.
4. **Near:** closest allowed camera/actor composition.
5. **Far:** farthest allowed camera/actor composition.

At each view, exercise an actor behind and in front of at least three landmarks, plus an opaque effect and a translucent effect. Review with nearest filtering and the production compatibility renderer.

Also capture camera translations at 0, 0.25, 0.5, 0.75, and 1 display pixel.
Measure the changed-pixel ratio in a stable crop: a nearest-filtered card may
step once at a pixel boundary, but it must not accumulate intermediate blended
colors or expose alternating seam rows. For adjacent terrain cards, compare both
sides of every join; prefer a single bounded chunk when the available source
does not contain genuinely adjoining regions.

Reject the candidate for any of the following:

- A card edge becomes visible within camera bounds.
- Facade, roof, side, or canopy layers separate like an accordion.
- Transparent pixels flicker, reorder, halo, or hide a nearer actor incorrectly.
- Pixel edges shimmer during camera motion, indicating interpolation or unstable pixel scale.
- Actor, prop, doorway, footprint, or effect scale conflicts with gameplay spacing.
- A painted wall appears blocking but has no footprint, or a footprint blocks apparently open ground.
- Contact shadows float, clip through the ground, or imply a different root.
- Camera movement or reduced-motion behavior changes simulation state.

Approval notes should identify the views and target sizes actually reviewed. A review receipt records the decision; it does not cure an omitted test or grant distribution rights.
