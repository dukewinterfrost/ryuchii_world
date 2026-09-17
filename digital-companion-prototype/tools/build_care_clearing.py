#!/usr/bin/env python3
"""Seed the original, native-mesh care garden once; never overwrite artist edits.

No external artwork, model downloads, image generation, or asset promotion.
All solid scenery is outside the existing 40x48 gameplay field. Small flowers
and grass are deliberately traversable, not a second collision authority.
"""
import math
import random
from build_environment_workshop import ROOT, Scene, vec, save_once


def main():
    scene = Scene()
    ground_shader = scene.ext("Shader", "res://shaders/care_clearing_ground.gdshader")
    leaf_shader = scene.ext("Shader", "res://shaders/care_foliage.gdshader")
    rig_script = scene.ext("Script", "res://scripts/environment/workshop_camera_rig.gd")
    scene.node("CareClearing", "Node3D", properties='metadata/art_direction = "Original camera-facing care garden v1"\nmetadata/gameplay = "Visual only; all solid scenery outside 40x48 field"')
    ground_material = scene.resource("ShaderMaterial", f"shader = {ground_shader}\n")
    floor = scene.resource("PlaneMesh", f"size = Vector2(100, 120)\nsubdivide_width = 48\nsubdivide_depth = 48\nmaterial = {ground_material}\n")
    scene.node("Ground", "MeshInstance3D", ".", f"position = Vector3(20, 0, 24)\nmesh = {floor}\n")
    materials = {}
    for name, color in {"Leaf":(.22,.43,.14),"LeafSun":(.40,.57,.18),"LeafDeep":(.10,.29,.14),"Bark":(.27,.18,.10),"Stone":(.43,.47,.34),"Petal":(.93,.72,.28)}.items():
        materials[name] = scene.resource("ShaderMaterial", f"shader = {leaf_shader}\nshader_parameter/base_color = Color({color[0]}, {color[1]}, {color[2]}, 1)\n")
    sphere = scene.resource("SphereMesh", "radius = 1.0\nheight = 2.0\nradial_segments = 10\nrings = 5\n")
    trunk = scene.resource("CylinderMesh", "top_radius = 0.24\nbottom_radius = 0.45\nheight = 4.0\nradial_segments = 7\nrings = 1\n")
    blade = scene.resource("PrismMesh", "size = Vector3(0.10, 0.55, 0.22)\n")
    def mesh(name, parent, shape, color, position, scale=(1,1,1), rotation=(0,0,0)):
        scene.node(name,"MeshInstance3D",parent,f"mesh = {shape}\nmaterial_override = {materials[color]}\nposition = {vec(position)}\nscale = {vec(scale)}\nrotation = {vec(rotation)}\n")
    rng = random.Random(915)
    scene.node("BoundaryForest", "Node3D", ".")
    spots = [(x,z) for z in (-4,52) for x in range(-5,47,4)] + [(x,z) for x in (-4,44) for z in range(0,50,5)]
    for i,(x,z) in enumerate(spots):
        path=f"BoundaryForest/Tree_{i:02d}"
        size=rng.uniform(.85,1.3)
        scene.node(f"Tree_{i:02d}","Node3D","BoundaryForest",f"position = {vec([x,0,z])}\nscale = {vec([size,size,size])}\nmetadata/outside_gameplay = true")
        mesh("Trunk",path,trunk,"Bark",(0,2,0))
        for j,(dx,dy,dz,s) in enumerate([(-1.2,4.0,0,1.8),(1.1,4.4,.3,1.9),(0,5.3,-.2,1.8)]):
            mesh(f"Crown_{j}",path,sphere,"LeafSun" if j==2 else "Leaf",(dx,dy,dz),(s,1.35,s))
    scene.node("MeadowFlowers", "Node3D", ".", 'metadata/traversable = true')
    # Low flowers and grass occupy the lawn, leaving the path/central clearing open.
    for i in range(180):
        x,z=rng.uniform(1,39),rng.uniform(1,47)
        center=20.5+math.sin(z*.19)*1.7
        if abs(x-center)<3.4 or ((x-20.5)**2+((z-24.5)*.78)**2)<30:
            continue
        name=f"Tuft_{i:03d}"
        parent=f"MeadowFlowers/{name}"
        scene.node(name,"Node3D","MeadowFlowers",f"position = {vec([x,.015,z])}\nrotation = {vec([0,rng.random()*6.28,0])}")
        for j in range(3):
            mesh(f"Blade_{j}",parent,blade,"LeafSun",((j-1)*.16,.23,0),(1,rng.uniform(.6,1.0),1),(0,j*1.6,(j-1)*.35))
        if i%3==0:
            mesh("Flower",parent,sphere,"Petal",(.10,.48,0),(.10,.065,.10))
    scene.node("PathsidePlanting", "Node3D", ".", 'metadata/traversable = true')
    for i in range(10):
        for side in (-1, 1):
            z = 8 + i * 4
            x = 20.5 + math.sin(z * .19) * 1.7 + side * (5 + math.sin(z * .7) * .7)
            name = f"Plant_{i}_{'L' if side < 0 else 'R'}"
            parent = f"PathsidePlanting/{name}"
            scene.node(name, "Node3D", "PathsidePlanting", f"position = {vec([x,0,z])}\n")
            for j in range(7):
                angle = j * math.tau / 7
                mesh(f"Leaf_{j}", parent, sphere, "LeafSun" if j % 3 == 0 else "Leaf", (.35*math.sin(angle),.40,.35*math.cos(angle)), (.24,.12,.85), (-.5,angle,0))
    scene.node("CameraRig","Node3D",".",f"script = {rig_script}\nposition = Vector3(20.5, 0, 24.5)\nrotation_degrees = Vector3(-30,0,0)\npitch_degrees = 30.0\ndistance = 23.0\n")
    scene.node("Camera3D","Camera3D","CameraRig","position = Vector3(0,0,23)\ncurrent = true\nkeep_aspect = 0\nfov = 32.0\nnear = 0.1\nfar = 220.0\n")
    env=scene.resource("Environment","background_mode = 1\nbackground_color = Color(0.10,0.19,0.12,1)\n")
    scene.node("WorldEnvironment","WorldEnvironment",".",f"environment = {env}\n")
    scene.node("CompanionSpawn","Marker3D",".","position = Vector3(20.5,0,24.5)\n")
    save_once(ROOT/"scenes/environments/care_clearing.tscn",scene.text())


if __name__ == "__main__":
    main()
