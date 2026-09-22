# Edit the environments in Godot

**September 17 update:** Rootbound Glade now has an open worn clearing, irregular
woodland, and a sheer ledge. Native forest home uses the same flat-top/vertical
drop geometry. See [the rework and review](ROOTBOUND_GLADE_REVIEW.md). For the
first battle field, edit `Floor/ClearingTerrain → Ground Material`, not the old
16 patches; its camera FOV is 32°. Other regional patch workflows below remain
unchanged.

**September 15 update:** sprite planes now stay camera-facing at every angle.
The old upright/non-billboard working-scene rule is superseded. See
[the current care-screen direction](CARE_REFERENCE_DIRECTION.md) for the native
scene used by the live Green Shade care screen and its remaining visual work.

Double-click `open-environment-workshop.command`. It opens the Green Shade home
scene in the Godot editor. The ten working scenes are in
`res://scenes/environment_workshop/`; open any `.tscn` and press **F6** to preview
that scene. **F8** stops the preview. F5 still launches the normal game.

These are saved, editable scenes with native nodes. They do not construct or
reset their environment every frame. Saving in Godot preserves your edits.
Working PNG imports are lossless with automatic 3D compression disabled;
materials use nearest filtering so the editor does not silently soften the art.
They are presentation working copies; the live game's pinned packages remain
separate until the edited direction is reviewed and integrated.

## Play the regional battle fields

Double-click `open-battle-fields.command`, or run
`res://scenes/environment_workshop/battle_fields.tscn` with F6. Select any of the
five fields to run an actual battle there; **Leave · fields** returns to the
selector. The environment workshop menu also has **Play regional battle fields**.

This route loads the saved `*_battle.tscn` scene into the real battle viewport:
edited floor textures, plane placement, and the saved camera pitch/FOV now show
up in combat, not just in a static editor preview. Static editor character guides
are removed and replaced by simulation-driven fighters and world-space VFX.
Camera framing uses the loaded camera settings rather than the old hard-coded
50-degree pitch. Replay geometry and immutable source pins are unchanged.

Trees, foliage, buildings, and other landmarks are layered `Sprite3D` cards,
not 3D models. The floor and sheer cliff faces use terrain meshes. Sprites remain
camera-facing, nearest-filtered, and depth-tested. No new artwork was generated.

These are explicitly **isolated, unpromoted field reviews**. The launcher/F6
route never reads or writes the real companion save. Live play still resolves
approved catalog packages; this does not silently approve the five private-use
DigimonUP kits. After final field approval, promotion remains a separate step.

`tests/battle_3d_test_runner.gd -- --test-mode --capture-fields` captures every
field at 360×640, 390×844, and 430×932 under `/tmp/battle-field-*.png`. Its checks
cover actual field selection, guide removal, two fighters, saved camera angles,
no modeled foliage, unchanged combat data, and the live approval boundary.

| Select in Scene tree | Adjust in Inspector |
| --- | --- |
| `CameraRig` | **Pitch Degrees**: starts at **30°**, previously 50°. Smaller means a lower, flatter view. **Distance** zooms; **Transform → Position** pans. |
| `CameraRig/Camera3D` | **FOV** (starts at 28°), clipping, and camera preview. |
| `Floor` | **Floor Texture**, **Pixels Per Meter** (starts at 64), **Texture Offset**. Larger density makes the pattern smaller. |
| `Floor/Patch_*` | Move/resize an individual patch; **Material Override → Albedo → Texture** swaps its image; **UV1 → Scale/Offset** adjusts its crop/repetition. Materials are independent. |
| `Landmarks/Landmark_1` | Move/scale the entire tree/building/machine stack. Expand it to adjust individual Sprite3D planes. |
| `Characters/Agumon` or `Player`/`Opponent` | Move or scale the character root. |
| `Characters/*/AnimatedSprite3D` | **Pixel Size**, animation/frames, and sprite orientation. Sprites start upright. Authored frame pivots keep their feet rooted. |
| `LayoutGuides` | Hidden spawn reference markers. Gameplay blockers and routes still belong to the referenced layout manifest. |

In the 3D editor, select a node and press **F** to frame it. Select Camera3D and
enable its **Preview** to see the actual composition. Floor patches are normal
MeshInstance3D nodes: duplicate, move, hide, or replace their materials directly.
Repeating the existing floor crops can expose painted seams; these working
textures are deliberately available for fixing those joins.

The home/battle pairs reference the same editable texture files under
`res://assets/environment_workshop/<region>/`. Replacing `floor.png` updates both
scenes after Godot reimports it. Each scene's transforms and materials are saved
independently. Imported originals and the reviewed fixture packages are preserved.

## Figma floor workflow

[Open the floor texture page](https://www.figma.com/design/syQM2pShfeCTfXms0HmzTB?node-id=66-150)
in the existing Pixel Workshop. Each region has an original Ground reference,
its exact floor crop at native resolution, and a separate patch canvas for
rearranging image fills. Raster pixels remain raster; crop, replace, overlap,
mask, and add editable Figma shapes as needed.

Export the exact crop node as PNG at **1×**, name it `floor.png`, and replace the
matching file in `assets/environment_workshop/<region>/`. For a new full-floor
composition, export the shuffle canvas, assign that PNG to your floor material,
and adjust UV scale/density to suit its new dimensions. There is no automatic
Figma → Godot synchronization.

`tools/build_environment_workshop.py` seeds missing working files only. Running
it again keeps all existing scenes, textures, and manual edits. Initial texture
hashes and dimensions are recorded in `assets/environment_workshop/texture-index.json`.
All copied DigimonUP imagery retains its private-prototype-only classification.
