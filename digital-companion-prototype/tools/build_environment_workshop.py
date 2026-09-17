#!/usr/bin/env python3
"""Seed ordinary editable Godot scenes from the verified region packages.

Existing working scenes/textures are NEVER overwritten. This is a one-time
authoring export, not a runtime scene builder or asset approval operation.
"""
import hashlib
import json
import math
from pathlib import Path
import shutil
import struct

ROOT = Path(__file__).resolve().parents[1]
FIXTURES = ROOT / "tests/fixtures/regions"
SCENES = ROOT / "scenes/environment_workshop"
ASSETS = ROOT / "assets/environment_workshop"
REGIONS = ["green-shade", "shellfish-beach", "toy-maze", "mechatropolis", "nephelis-abyss"]


def digest(path):
    return "sha256:" + hashlib.sha256(path.read_bytes()).hexdigest()


def read(path):
    return json.loads(path.read_text())


def res(path):
    return "res://" + path.relative_to(ROOT).as_posix()


def q(value):
    return json.dumps(str(value), ensure_ascii=False)


def vec(values, size=3):
    return f"Vector{size}(" + ", ".join(f"{v:.8g}" for v in values) + ")"


def png_size(path):
    header = path.read_bytes()[:24]
    assert header[:8] == b"\x89PNG\r\n\x1a\n", path
    return struct.unpack(">II", header[16:24])


def copy_once(source, target):
    target.parent.mkdir(parents=True, exist_ok=True)
    if not target.exists():
        shutil.copyfile(source, target)
    if target.suffix == ".png":
        # Seed import policy before Godot sees a new working texture. The editor
        # completes paths/UIDs, but cannot auto-switch pixel art to lossy 3D mode.
        save_once(Path(str(target) + ".import"),
                  '[remap]\nimporter="texture"\ntype="CompressedTexture2D"\n\n'
                  '[params]\ncompress/mode=0\nmipmaps/generate=false\n'
                  'detect_3d/compress_to=0\n')


def save_once(path, text):
    if path.exists():
        print("KEEP manual edits:", path.relative_to(ROOT))
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)
    print("CREATE:", path.relative_to(ROOT))


def actor_resource():
    source = ROOT / "assets/companions/agumon"
    target = ASSETS / "agumon"
    for name in ["atlas.png", "atlas.json", "animation-set.json"]:
        copy_once(source / name, target / name)
    atlas, animations = read(target / "atlas.json"), read(target / "animation-set.json")
    entries, subresources, pivots = [], [], {}
    counter = 0
    for name, clip in animations["clips"].items():
        frames, offsets = [], []
        for frame in clip["frames"]:
            definition = atlas["frames"][frame["atlasFrame"]]
            rectangle = definition["frame"]
            counter += 1
            key = f"Frame{counter}"
            subresources.append(f'[sub_resource type="AtlasTexture" id="{key}"]\natlas = ExtResource("1")\nregion = Rect2({rectangle["x"]}, {rectangle["y"]}, {rectangle["w"]}, {rectangle["h"]})\n')
            frames.append('{"duration": %s, "texture": SubResource(%s)}' % (frame["durationMs"], q(key)))
            pivot = frame.get("pivot", definition.get("pivot", {"x": .5, "y": .5}))
            offsets.append(vec([pivot["x"], pivot["y"]], 2))
        entries.append('{"frames": [%s], "loop": %s, "name": &%s, "speed": 1000.0}' % (", ".join(frames), str(clip.get("kind") == "loop").lower(), q(name)))
        pivots[name] = offsets
    text = f'[gd_resource type="SpriteFrames" load_steps={counter + 2} format=3]\n\n[ext_resource type="Texture2D" path={q(res(target / "atlas.png"))} id="1"]\n\n'
    text += "\n".join(subresources)
    text += '\n[resource]\nanimations = [' + ",\n".join(entries) + ']\nmetadata/workshop_pivots = {'
    text += ", ".join(q(name) + ": [" + ", ".join(values) + "]" for name, values in pivots.items()) + '}\n'
    save_once(target / "spriteframes.tres", text)


class Scene:
    def __init__(self):
        self.external, self.resources, self.nodes = [], [], []

    def ext(self, kind, path):
        key = str(len(self.external) + 1)
        self.external.append(f'[ext_resource type={q(kind)} path={q(path)} id={q(key)}]')
        return f'ExtResource({q(key)})'

    def resource(self, kind, properties):
        key = f"Resource{len(self.resources) + 1}"
        self.resources.append(f'[sub_resource type={q(kind)} id={q(key)}]\n' + properties)
        return f'SubResource({q(key)})'

    def node(self, name, kind, parent=None, properties=""):
        heading = f'[node name={q(name)} type={q(kind)}'
        if parent is not None:
            heading += f' parent={q(parent)}'
        self.nodes.append(heading + ']\n' + properties)

    def text(self):
        return f'[gd_scene load_steps={1 + len(self.external) + len(self.resources)} format=3]\n\n' + "\n\n".join(self.external + self.resources + self.nodes) + "\n"


def scene_for(region, layout, env, textures):
    scene = Scene()
    camera_script = scene.ext("Script", "res://scripts/environment/workshop_camera_rig.gd")
    floor_script = scene.ext("Script", "res://scripts/environment/workshop_floor.gd")
    actor_script = scene.ext("Script", "res://scripts/environment/workshop_actor.gd")
    frames = scene.ext("SpriteFrames", res(ASSETS / "agumon/spriteframes.tres"))
    texrefs = {role: scene.ext("Texture2D", res(path)) for role, path in textures.items()}
    kind = "habitat" if layout == "home" else "arena"
    manifest = read(FIXTURES / region / "review" / kind / f"{kind}.json")
    title = manifest["displayName"]
    metadata = '\n'.join([
        'metadata/workshop = true', 'metadata/license = "private-prototype-only"',
        'metadata/source_manifest = ' + q(res(FIXTURES / region / "review" / kind / f"{kind}.json")),
        'metadata/note = "Editable presentation study. Visual edits are saved here; gameplay footprints remain in the source manifest."',
    ])
    scene.node(title.replace(" ", ""), "Node3D", properties=metadata)
    color = env.get("backgroundColor", "#182d31").lstrip("#")
    rgb = [int(color[i:i+2], 16) / 255 for i in (0, 2, 4)]
    environment = scene.resource("Environment", "background_mode = 1\nbackground_color = Color(%s, %s, %s, 1)\n" % tuple(rgb))
    scene.node("WorldEnvironment", "WorldEnvironment", ".", "environment = " + environment)

    chunk = env["terrainChunks"][0]
    floor_role = chunk.get("textureBinding", chunk["source"])
    floor_texture = texrefs[floor_role]
    dimensions = png_size(textures[floor_role])
    scene.node("Floor", "Node3D", ".", f"script = {floor_script}\nfloor_texture = {floor_texture}\npixels_per_meter = 64.0\nmetadata/edit_help = \"Select a patch to replace its material texture, move it, or change UV1 scale/offset. Select Floor for global density.\"")
    rect = chunk["groundRect"]
    # Four by four independent floor patches. Their initial UVs meet exactly;
    # the source crop itself may need painted seam work when repeated.
    patch_w, patch_d = rect[2] / 32 / 4, rect[3] / 32 / 4
    for row in range(4):
        for col in range(4):
            x, z = rect[0] / 32 + col * patch_w, rect[1] / 32 + row * patch_d
            material = scene.resource("StandardMaterial3D", "resource_local_to_scene = true\nshading_mode = 0\ncull_mode = 2\ntexture_filter = 0\nalbedo_texture = %s\nuv1_scale = %s\nuv1_offset = %s\n" % (floor_texture, vec([patch_w * 64 / dimensions[0], patch_d * 64 / dimensions[1], 1]), vec([x * 64 / dimensions[0], z * 64 / dimensions[1], 0])))
            mesh = scene.resource("PlaneMesh", f"resource_local_to_scene = true\nsize = {vec([patch_w, patch_d], 2)}\nsubdivide_width = 4\nsubdivide_depth = 4\n")
            scene.node(f"Patch_{row+1}_{col+1}", "MeshInstance3D", "Floor", f"position = {vec([x + patch_w/2, chunk.get('elevation', 0), z + patch_d/2])}\nmesh = {mesh}\nmaterial_override = {material}\n")

    scene.node("Landmarks", "Node3D", ".")
    planes = {p["id"]: p for p in env["spritePlanes"]}
    stacks = {s["id"]: s for s in env["planeStacks"]}
    placements = manifest.get("staticPlacements", manifest.get("presentation", {}).get("staticPlacements", []))
    points = []
    for index, placement in enumerate(placements):
        position = placement["cell"] if layout == "home" else [v/32 for v in placement["groundPosition"]]
        points.append(position)
        name = f"Landmark_{index+1}"
        scene.node(name, "Node3D", "Landmarks", f"position = {vec([position[0], 0, position[1]])}\nmetadata/source_placement = {q(placement['id'])}")
        for plane_id in stacks[placement["planeStack"]]["planes"]:
            add_plane(scene, planes[plane_id], texrefs, textures, f"Landmarks/{name}")
    scene.node("Ambient", "Node3D", ".")
    for definition in env.get("ambientPlanes", []):
        add_plane(scene, definition, texrefs, textures, "Ambient", "position")

    scene.node("Characters", "Node3D", ".")
    spawns = {"Agumon": manifest["spawn"]} if layout == "home" else {name.capitalize(): [v/32 for v in pos] for name, pos in manifest["spawns"].items()}
    for name, position in spawns.items():
        points.append(position)
        scene.node(name, "Node3D", "Characters", f"position = {vec([position[0], 0, position[1]])}\nmetadata/edit_help = \"Move this root on XZ. Scale this root to resize the character. AnimatedSprite3D exposes clips and Pixel Size.\"")
        scene.node("AnimatedSprite3D", "AnimatedSprite3D", f"Characters/{name}", f"position = Vector3(0, 0.02, 0)\nscript = {actor_script}\nsprite_frames = {frames}\nanimation = &\"idle.default\"\npixel_size = 0.025\ntexture_filter = 0\nalpha_cut = 1\nshaded = false\nbillboard = 1\nflip_h = {str(name == 'Opponent').lower()}\n")
        shadow = scene.resource("StandardMaterial3D", "shading_mode = 0\ntransparency = 1\nalbedo_color = Color(0.08, 0.09, 0.08, 0.24)\n")
        disk = scene.resource("CylinderMesh", "top_radius = 1.0\nbottom_radius = 1.0\nheight = 0.001\nradial_segments = 32\n")
        scene.node("ContactShadow", "MeshInstance3D", f"Characters/{name}", f"position = Vector3(0, 0.012, 0)\nscale = Vector3(1, 1, 0.45)\nmesh = {disk}\nmaterial_override = {shadow}")

    # Frame the actual layout placements + spawns, not invented review positions.
    minx, maxx = min(p[0] for p in points), max(p[0] for p in points)
    minz, maxz = min(p[1] for p in points), max(p[1] for p in points)
    focus = [(minx+maxx)/2, 1.2, (minz+maxz)/2]
    distance = max(36, (maxx-minx+9)/(2*math.tan(math.radians(14))))
    scene.node("CameraRig", "Node3D", ".", f"position = {vec(focus)}\nrotation = {vec([-math.pi/6,0,0])}\nscript = {camera_script}\npitch_degrees = 30.0\ndistance = {distance:.8f}\nmetadata/edit_help = \"Pitch Degrees controls floor angle (30 default, previous 50). Distance zooms. Transform Position pans. Camera3D FOV is editable.\"")
    scene.node("Camera3D", "Camera3D", "CameraRig", f"position = Vector3(0, 0, {distance:.8f})\ncurrent = true\nkeep_aspect = 0\nfov = 28.0\nnear = 0.1\nfar = 400.0\n")
    scene.node("LayoutGuides", "Node3D", ".", "visible = false\nmetadata/edit_help = \"Reference markers only, never physics. Source manifest remains authoritative for gameplay.\"")
    for name, pos in spawns.items():
        scene.node(name + "Spawn", "Marker3D", "LayoutGuides", f"position = {vec([pos[0], 0, pos[1]])}")
    save_once(SCENES / (region.replace("-", "_") + "_" + layout + ".tscn"), scene.text())


def add_plane(scene, definition, texrefs, textures, parent, position_field="localPosition"):
    role = definition["source"]
    region = definition.get("sourceRegionPx")
    width, height = region[2:] if region else png_size(textures[role])
    pivot = definition["pivot"]
    offset = [width*(.5-pivot["x"]), height*(pivot["y"]-.5)]
    rotation = definition.get("rotationDegrees", [0,0,0])
    properties = f"texture = {texrefs[role]}\nposition = {vec(definition[position_field])}\nrotation = {vec([math.radians(v) for v in rotation])}\noffset = {vec(offset,2)}\npixel_size = {definition['pixelSize']}\ntexture_filter = 0\nshaded = false\nbillboard = 1\nalpha_cut = {2 if definition['alphaMode']=='transparent' else 1}\nrender_priority = {definition.get('renderPriority',0)}\n"
    if region:
        properties += 'region_enabled = true\nregion_rect = Rect2(' + ', '.join(map(str, region)) + ')\n'
    scene.node(definition["id"].replace("-", "_").replace(".", "_"), "Sprite3D", parent, properties)


def main():
    actor_resource()
    inventory = []
    for region in REGIONS:
        folder = FIXTURES / region / "environment"
        env = read(folder / "environment.json")
        candidate = read(folder / "candidate.json")
        textures = {}
        for role, relative in env["textures"].items():
            source = folder / relative
            # Verify exactly the bytes bound by the existing environment package.
            expected = candidate["files"][relative]
            if isinstance(expected, dict):
                expected = expected["sha256"]
            assert digest(source) == expected, source
            filename = "floor.png" if role.startswith("terrain.") else role + ".png"
            target = ASSETS / region / filename
            copy_once(source, target)
            textures[role] = target
            if role == "ground" or role.startswith("terrain."):
                inventory.append({"region":region,"role":role,"source":res(source),"sourceSha256":digest(source),"workingTexture":res(target),"size":list(png_size(target)),"license":"private-prototype-only"})
        for layout in ["home", "battle"]:
            scene_for(region, layout, env, textures)
    save_once(ASSETS / "texture-index.json", json.dumps(inventory, indent=2)+"\n")


if __name__ == "__main__":
    main()
