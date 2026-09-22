@tool
extends MeshInstance3D
const SheerStage = preload("res://scripts/environment/sheer_stage_mesh.gd")
## Presentation-only sheer ledge. The legacy script path is retained for scenes.
## The complete 40x48 gameplay rectangle stays flat.
## No collision shape is generated; HabitatRules remains the navigation authority.
@export var ground_material: ShaderMaterial
@export var terrain_size := Vector2(240, 320)
@export var field_center := Vector2(20, 24)
@export var flat_half_extents := Vector2(22, 26)
@export var oval_radii := Vector2(36, 30.666667)
@export_range(0.0, 30.0, 0.5) var edge_drop := 16.0
@export var rebuild_preview := false:
	set(value):
		if value and is_inside_tree():
			build_ground()


func _ready() -> void:
	build_ground()


func height_at_ground(point: Vector2) -> float:
	return SheerStage.height_at(point,field_center,oval_radii,flat_half_extents,edge_drop)


func build_ground() -> void:
	var sculpted := SheerStage.build(field_center,oval_radii,flat_half_extents,terrain_size,edge_drop,global_position)
	sculpted.surface_set_material(0, ground_material.duplicate())
	mesh = sculpted
	update_tree_shadows()


func update_tree_shadows() -> void:
	# Shared by native F6/editor preview and the active save-aware care view.
	# Material instances remain separate between open scenes and lighting views.
	var material := get_active_material(0) as ShaderMaterial
	if material == null:
		return
	var shadow_points: Array[Vector4] = []
	for branch: String in ["InteriorTrees", "Boundary"]:
		var cards := get_parent().get_node_or_null("ForestParallax/OvalLayout/" + branch)
		if cards == null:
			continue
		for tree: Node3D in cards.get_children():
			# Camera-clearance hiding removes only a rim canopy card, not its
			# physical location/shade. Save-conflicting interior trees do disappear.
			if tree.has_meta("shadow_radius") and (branch == "Boundary" or tree.visible):
				shadow_points.append(Vector4(tree.global_position.x, tree.global_position.z,
					float(tree.get_meta("shadow_radius")), 0.34 if branch == "InteriorTrees" else 0.3))
	while shadow_points.size() < 12:
		shadow_points.append(Vector4.ZERO)
	material.set_shader_parameter("tree_shadows", shadow_points.slice(0, 12))
