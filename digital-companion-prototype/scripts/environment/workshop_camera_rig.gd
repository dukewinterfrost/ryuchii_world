@tool
extends Node3D
## Manual art-direction camera. Move this rig to pan; its child camera stays
## on a fixed viewing axis. These controls only update when explicitly edited.

@export_range(10.0, 75.0, 0.5) var pitch_degrees := 30.0:
	set(value):
		pitch_degrees = value
		rotation_degrees.x = -value
@export_range(5.0, 160.0, 0.5) var distance := 36.0:
	set(value):
		distance = value
		if has_node("Camera3D"):
			$Camera3D.position = Vector3(0, 0, value)

# No _process / look_at / follow loop: saved Inspector edits survive F6.
