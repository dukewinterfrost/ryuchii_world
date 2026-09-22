class_name BattleGroundCues3D
extends Node3D

## Lightweight mesh cues on the real ground plane, plus camera-facing cast bars.
## This node has no process clock: the adapter supplies an authoritative snapshot.
var mesh_node := MeshInstance3D.new()
var cue_count := 0
var charge_count := 0
var debug_geometry := false
var reduced_motion := false
var _mesh := ImmediateMesh.new()
var _material := StandardMaterial3D.new()

func _ready() -> void:
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.vertex_color_use_as_albedo = true
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_material.no_depth_test = false
	mesh_node.mesh = _mesh
	mesh_node.material_override = _material
	add_child(mesh_node)

func sample(actor: Dictionary, arena: Dictionary, camera: Camera3D, session: Dictionary = {}) -> void:
	_mesh.clear_surfaces()
	cue_count = 0
	charge_count = 0
	var cue := BattlePresentationCues.attack(actor, arena, session)
	var location := BattlePresentationCues.ground(actor.get("pos", [0, 0]))
	var action := String(actor.get("action", ""))
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	if not cue.is_empty():
		cue_count += 1
		var fill: Color = cue.color
		fill.a = 0.28 if cue.phase == "charge" else 0.5
		_quad(cue.points, fill)
		var points: PackedVector2Array = cue.points
		for index: int in 4:
			_line(points[index], points[(index + 1) % 4], 3.6, Color(0.12, 0.06, 0.04, 0.9))
			_line(points[index], points[(index + 1) % 4], 1.8, Color(cue.color, 1))
		if cue.phase == "charge":
			charge_count += 1

	if action == "guard":
		_ring(location, 18, Color("86def2"))
	if actor.get("effects", {}).has("barrier"):
		_ring(location, 23, Color(0.5, 0.85, 1, 0.8))
	if actor.get("effects", {}).has("haste"):
		_ring(location, 15, Color("a8edab"))
	if action in ["evade", "rush_attack"] and not reduced_motion:
		var previous := BattlePresentationCues.ground(actor.get("previous_pos", actor.pos))
		var movement := previous.direction_to(location)
		if not movement.is_zero_approx():
			_line(previous - movement * 12, location, 3, Color(0.65, 0.9, 1, 0.65))
	if debug_geometry:
		var radius := float(actor.get("radius", 12000)) / 1000.0
		var corners := PackedVector2Array([location + Vector2(-radius, -radius), location + Vector2(radius, -radius), location + Vector2(radius, radius), location + Vector2(-radius, radius)])
		for index: int in 4:
			_line(corners[index], corners[(index + 1) % 4], 1.0, Color("62d2f5"))
	# A transparent degenerate triangle keeps empty ImmediateMesh surfaces valid.
	_vertex(location, Color.TRANSPARENT)
	_vertex(location, Color.TRANSPARENT)
	_vertex(location, Color.TRANSPARENT)
	_mesh.surface_end()

func _vertex(point: Vector2, color: Color) -> void:
	_mesh.surface_set_color(color)
	_mesh.surface_add_vertex(EnvironmentView3D.ground_to_world(point) + Vector3(0, 0.04, 0))

func _quad(points: PackedVector2Array, color: Color) -> void:
	for index: int in [0, 1, 2, 0, 2, 3]:
		_vertex(points[index], color)

func _line(start: Vector2, finish: Vector2, width: float, color: Color) -> void:
	var direction := start.direction_to(finish)
	var side := Vector2(-direction.y, direction.x) * width / 2
	_quad(PackedVector2Array([start + side, finish + side, finish - side, start - side]), color)

func _ring(center: Vector2, radius: float, color: Color) -> void:
	for index: int in 32:
		var first := float(index) / 32 * TAU
		var second := float(index + 1) / 32 * TAU
		_line(center + Vector2(cos(first), sin(first)) * radius, center + Vector2(cos(second), sin(second)) * radius, 1.4, color)
