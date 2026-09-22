---
name: scene-builder
description: Compose, tune, and visually verify editable sprite-in-3D environments in this Godot digital-companion project. Use for reference-led world dressing, terrain transitions, parallax layers, seam concealment, or preparing the next biome; not character animation generation.
---

# Scene Builder

Build a complete-looking world around the playable ground, not just a decorated
rectangle. Work in native Godot scenes so the user can continue art direction
in the Inspector. The active forest implementation and its evidence are in
[forest findings](references/forest-findings.md). For the next region, read
[beach handoff](references/beach-handoff.md); preparing it does not authorize
building or promoting that region yet.

The current user direction is **flat tops and sheer drops, not sloping hills**.
For native first-stage battle dressing or ledge geometry, read
[Rootbound and ledge findings](references/rootbound-ledge-findings.md).

## Start from the actual scene

- Inspect the user's reference image and the current runtime capture. Identify
  the visual relationships to preserve: playable-area emphasis, silhouette
  overlap, horizon opening, density variation, and warm/cool or light/dark depth.
  A reference is art direction, not permission to import its pixels or replace
  the user's existing style authority.
- Trace the live scene resolver before editing a workshop fixture. Native home
  currently uses `scenes/environments/care_clearing.tscn`, not a promoted biome
  package. Inspect the current code rather than assuming that remains true.
- Native home currently uses a fixed 30-degree camera pitch, 32-degree FOV,
  perspective dolly and camera-facing Sprite3D cards. These intentionally differ
  from the original non-billboarding spike profile. Keep the active user-selected
  presentation unless the request changes it; do not silently migrate profiles.
- Preserve unrelated work and capture the current baseline before a composition
  pass. Source PNG hashes and existing save/navigation invariants are evidence,
  not substitutes for looking at the result.

## Compose in depth

1. Establish the playable shape and camera envelope. Ground XZ maps to 2D
   gameplay at 32 ground pixels per world unit. Home is 40×48 cells. The visual
   shoulder now drops vertically; playable vertices, spawns, potty routes and decoration
   rules remain governed by `HabitatRules`, not mesh collisions.
2. Author distinct roles: readable playable ground, irregular rim accents,
   lowered transition woodland/rocks, foreground framing, distant scenery and
   sky. Density should vary within and between depths. Avoid reproducing a
   continuous tall hedge at the playable rim to hide a gap farther away.
3. Conceal a seam at its real depth with overlapping natural silhouettes. Bury
   the lower transparent-card boundary slightly beneath the terrain. Use varied
   spacing, scale, silhouette and restrained tint; keep negative space where
   the reference calls for a view. Pure random jitter of evenly spaced rows is
   usually insufficient. Camera-facing foreground cards need lens clearance.
4. Shade lowered decor along with lowered terrain. Keep alpha opaque/discard,
   depth testing on, nearest filtering and unshaded materials. Use painted
   contact/canopy shade, not realistic shadow maps. Keep day/night tint
   instance-scoped and multiply it once over the authored base color.
5. Preserve each layered background's intended canvas and pivot. Scale and
   position separated cards for perspective registration; don't resize each
   independently by eye. Check both their sides and the top at portrait and
   wide zoom limits. Extend clear sky in the shader when needed instead of
   stretching mountains or flattening all layers into one picture.
6. Keep grounded decoration stationary. Natural perspective already provides
   parallax; add only small secondary offsets to non-interactive distant layers.
   Convert offsets to the layer parent's coordinate space and respect reduced
   motion. No runtime placement randomization or gameplay RNG calls.

## Authoring and verification

- Use individual native Sprite3D nodes or PackedScene instances with meaningful
  layer names. A deterministic offline authoring helper may save initial
  placements; it must not overwrite later Inspector edits implicitly. The
  current helper is `tools/build_woodland_transition.gd` and refuses existing
  output without `--replace`. It is forest-specific, not a universal biome kit.
- Interior solids need explicit ground footprints, kept in sync with their
  authored roots. Existing saves take priority; omit conflicting optional
  scenery rather than moving a user's items. Low grass remains traversable.
- Render the live path in isolated `--test-mode`: center, left/right, front/back,
  closest and farthest zoom at 360×640, 390×844, 430×932, plus the wide editor
  view. Check dawn/day/dusk/night and foreground lens clearance. Freeze animated
  effects when measuring frame differences.
- Compare layers on/off to prove they actually cover the target gap. Inspect
  the images for floating roots, cut bars, exposed edges, repetition and a
  canopy wall hiding the playable field. Record subpixel-motion observations
  separately from navigation tests; assertion counts do not prove visual quality.
- Re-run relevant home, camera, day/night and shared battle presentation tests.
  Require success markers as well as process exit codes: Godot can exit zero
  after a parse error. Stop a failed preview by its verified process handle;
  don't leave it running and mistake old screenshots for new evidence.
- Save new review captures, source identities, exact test results and remaining
  limitations. Update the findings after real experiments, distinguishing
  reusable principles from values specific to one forest scene.

## Source and approval boundary

Reuse bound source bytes. New slices/derivatives or pipeline packaging follow
the project's `digital-companion-environments` skill and `docs/SPRITE_PIPELINE.md`.
User-supplied BG-1/foliage sources and DigimonUP sources remain private-prototype
only unless rights are independently cleared. Paid generation and promotion
need their respective explicit authorizations; working-scene implementation or
agent visual review is not a human asset-approval receipt.
