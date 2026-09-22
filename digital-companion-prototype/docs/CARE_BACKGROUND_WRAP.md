# Care clearing background wrap — working scene

## September 21 restoration and live battle routing

Restored the three wrap overrides after the active care file again matched the
old scene except for its UID. Preserved the current UID, woodland transforms,
nested woodland instance, ground and all tree placements. The old file remains
untouched. The checked generator's `save_once` refuses existing output; no
automatic overwrite was found. A stale editor save is a possibility, not a
confirmed cause. In Godot, reload externally modified scenes before saving;
do not keep an older editor copy over the disk version.

Normal battles now use `green_shade_battle.tscn` via
`configure_native_battle_field`, not the care clearing. The field is fitted to
the session bounds; workshop guide actors and its sample landmark are removed
from the runtime instance. Session-owned blockers remain visible and the arena
snapshot/simulation/replay data is unchanged. Isolated regional review keeps
its existing route and landmarks. This is a user-requested native-prototype
route, not an immutable catalog promotion or licensing clearance.

GPU checks: care wrap 16,017; normal battle controls 76. Headless battle 3D:
509 checks. All passed. Inspected the fresh care and normal-battle captures.
Regression checks now assert the saved wrap and the actual normal-battle path.

The care scene now uses three closed, mirrored-artwork ribbons in place of its
three rear billboard cards. This is a working presentation change, not an asset
promotion. Existing BG-1 images are reused unchanged; private-prototype source
restrictions still apply.

Open `scenes/environments/care_clearing.tscn` in Godot. Under `ForestParallax`,
select `Sky`, `ForestVista`, or `BackgroundMeadow`:

- **Wrap Radius** changes distance while preserving the XZ center.
- **Height Scale** changes the artwork height.
- **Artwork Phase** slides the mirrored panorama around the ribbon.
- **Position Y** adjusts its vertical registration.
- **Rebuild Background Wrap** refreshes the editor mesh.

Local radii are 130 / 85 / 45. With the existing parent scale, world radii are
173.33 / 113.33 / 60, with gaps of 60 and 53.33 world units instead of about 7.27.
The original bounded parallax offsets remain active. Meshes rebuild only on
authoring edits; they do not rebuild every frame. Day/night material bindings
are retained during rebuilds. No physics, navigation, camera or save changes.

## Review status

Structural/camera coverage checks pass, but visual approval is **pending**:
the unchanged large lower forest floor can still create a visible horizontal
transition between the separated artwork bands, particularly when zoomed out.
The wrap is editable and functional; this transition is not claimed finished.
Do not solve it by moving the user's trees or silently promoting new artwork.

Reviewed live-care captures at 360×640, 390×844, 430×932 and 1280×720, with
center/edge pans, near/overview zoom, and 00/06/12/18 lighting. These are desktop
Compatibility-renderer checks, not a mobile performance certification.

The oval foliage, transition woodland, original boundary and battle scene
hashes match the pre-change snapshot exactly. Ground, gameplay and source PNGs
were not edited. The scene-builder/environment guidance kept this scoped to
editable presentation nodes and prevented generation or promotion.

Regression suites: care camera 94, care map 29, day/night 78, battle 3D 509,
scene builder 1,073 checks, all passing. The wrap suite additionally checks
closed geometry/UV seams, radius-center preservation, material binding reuse,
camera-ray coverage and unchanged gameplay state.
