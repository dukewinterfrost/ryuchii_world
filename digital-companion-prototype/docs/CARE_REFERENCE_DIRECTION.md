# Camera-facing care screen — September 15 direction

The user's three references supersede the old fixed eight-degree sprite tilt.
Characters, upright sprite props, and sprite VFX now use full camera-orientation
billboarding: their planes stay parallel to the camera's image plane. This is
not a change to orthographic camera projection. Ground remains perspective XZ,
sprites retain perspective scale, and depth tests remain enabled.

`ScreenAlignedSprite` owns this rendering policy. CPU sprite/VFX framing uses the
camera basis as well; changing only the billboard flag would leave incorrect
framing bounds. Archived v1 manifest values and approval receipts are not edited
to pretend those historical assets were reviewed under the new renderer.

## Actual care screen

Normal Green Shade care now presents its existing fallback gameplay grid through
`res://scenes/environments/care_clearing.tscn`. It contains original native mesh
scenery and procedural materials, not promoted DigimonUP review fixtures. Solid
trees remain outside the playable 40×48 field; the low meadow plants are explicitly
traversable. Existing habitat items, navigation, inventory, and saved cells remain
authoritative. Broken approved packages still retain the safe failure path.

Open the native scene in Godot to edit `Ground`, `BoundaryForest`,
`PathsidePlanting`, `MeadowFlowers`, or `CameraRig`. The live renderer reads the
saved camera's pitch, distance, FOV, and clipping values. Its follow position is
driven by the companion, rather than the preview rig's absolute location.
The native scene's direct/F6 launch is isolated from the player's save.
The seed script `tools/build_care_clearing.py` never overwrites existing edits.

Care hearts/feed effects reuse the established drawings in a transparent texture
on a depth-tested, camera-facing card. The decoration grid/selection also renders
on the ground in 3D. Waste picking uses a screen-space 44-pixel minimum target.

## Verification and remaining visual work

### Care forest parallax integration — 2026-09-16

At the user's request, the native care clearing now instances the editable
`forest_parallax.tscn` scenery at 4/3 scale for the 40×48 habitat. The previous
BoundaryForest and PathsidePlanting remain editable but hidden. Ground, flowers,
navigation, decorations and save geometry are unchanged. Camera focus drives
secondary sky/vista/rear-tree motion; rooted foliage stays fixed and Reduced
Motion restores authored positions. World focus is converted into local space
so the scaled scene does not drift.

This is private-prototype integration, not a compiled catalog promotion or a
fabricated final approval. No sources were changed or generated. The existing
forest-parallax revision is `2026-09-16.001`; the reused foliage source is
`care-woodland-foliage/2026-09-15.001`. Verified working PNG SHA-256 values:

- panorama: `d387a7fed284f1fed691546dae6ca1235af148f86ecf63eec10dd72d7fa2f4a6`
- sky: `84748c7233ee9465fd2931578e726ed92d546e3505a3fa4b40da8c939368ce10`
- foliage: `ee0ed7a9f64646e8205801b671ba06591fa587f7dc79efc1ede5efb390c9743f`

Supplied background rights remain unverified; public/commercial distribution
is not cleared. Final visual approval remains separate from this integration.

### Wide map framing (Cult of the Lamb reference)

Field → Explore map provides a full-window exploration mode with compact camera
controls. Landscape starts at 45% zoom; portrait starts at 75% to keep the creature
readable and reduce exposed terrain boundaries. Manual panning starts enabled;
Focus restores 100% companion follow. Back/Escape restores the care HUD, retaining
the selected camera preferences. Zero percent still means the complete map.

The reference informs the broad elevated view and screen-space UI, not copied
artwork. This is a framing iteration using the existing original clearing, not
a finished match for its populated, illustrated village. Landmark composition,
organic foliage and environmental density still need a visual art pass. No
pending woodland artwork was promoted. The isolated `care_map_view_runner.gd`
checks four portrait/landscape sizes and optionally captures GPU screenshots.

`tests/care_reference_runner.gd` uses an isolated synthetic save but explicitly
resolves the **production** Green Shade package (not pending review fixtures).
Its optional `--capture` mode captures all three portrait sizes and tests actual
rendered square proportions at nine combinations of camera pitch/yaw. Care/home,
workshop, and battle checks cover navigation, scene edits, and replay determinism.

The current original clearing is a first visual pass. The reference direction
still calls for a fuller, more organic layered environment; passing mechanics
tests alone does not establish final visual fidelity. No new art approval or
promotion receipt has been issued. Existing Digimon-derived character assets
retain their private-prototype-only handling.

A generated four-prop woodland kit is now staged at
`assets-source/care-woodland-foliage/2026-09-15.001/`. Its isolated review is
enabled only with `--test-mode --capture --foliage-review` on the care reference
runner. Review screenshots use the distinct `care-foliage-review` prefix. The
source sample awaits human approval; do not treat it as live or promoted art.

Godot's [SpriteBase3D billboard documentation](https://docs.godotengine.org/en/stable/classes/class_spritebase3d.html#class-spritebase3d-property-billboard)
describes the underlying renderer feature.
