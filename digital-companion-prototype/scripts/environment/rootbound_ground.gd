@tool
extends MeshInstance3D
const SheerStage = preload("res://scripts/environment/sheer_stage_mesh.gd")
## Battle presentation only. The 30x36 ground grid plus apron stays flat.
## This same sampler grounds the offline-authored woodland cards.
@export var ground_material: ShaderMaterial
@export var field_center := Vector2(15, 18)
@export var terrain_size := Vector2(180, 240)
@export var flat_half_extents := Vector2(17, 20)
@export var oval_radii := Vector2(27, 23)
@export_range(0.0, 24.0, 0.5) var edge_drop := 12.0
@export_tool_button("Rebuild terrain preview") var rebuild_button = build_ground

func _ready() -> void:
	build_ground()

func height_at_ground(point: Vector2) -> float:
	return SheerStage.height_at(point,field_center,oval_radii,flat_half_extents,edge_drop)

func build_ground() -> void:
	if ground_material == null:
		return
	mesh = SheerStage.build(field_center,oval_radii,flat_half_extents,terrain_size,edge_drop,global_position)
	# Keep the Inspector's Ground Material authoritative and local to this scene.
	# No per-frame regeneration or runtime reset of artist parameters.
	material_override = ground_material
