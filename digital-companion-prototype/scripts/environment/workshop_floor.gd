@tool
extends Node3D
## Each patch remains a normal, independently editable MeshInstance3D.
## Changing a field here reapplies mapping to all patches; direct per-patch
## material edits remain intact until you change one of these shared fields.

@export var floor_texture: Texture2D:
	set(value):
		floor_texture = value
		if is_inside_tree():
			apply_mapping()
@export_range(8.0, 256.0, 1.0) var pixels_per_meter := 64.0:
	set(value):
		pixels_per_meter = value
		if is_inside_tree():
			apply_mapping()
@export var texture_offset := Vector2.ZERO:
	set(value):
		texture_offset = value
		if is_inside_tree():
			apply_mapping()
@export var source_region := Rect2(0, 0, 0, 0):
	set(value):
		source_region = value
		if is_inside_tree():
			apply_mapping()
@export var region_tile_meters := Vector2(5, 3):
	set(value):
		region_tile_meters = value
		if is_inside_tree():
			apply_mapping()
@export_tool_button("Apply texture mapping to patches") var apply_button = apply_mapping

func _ready() -> void:
	# Preserve artist-edited, saved ShaderMaterials on F6. Only migrate legacy
	# standard patches once; explicit Inspector controls still reapply mapping.
	if source_region.has_area() and get_child_count() > 0 and not get_child(0).material_override is ShaderMaterial:
		apply_mapping()

func apply_mapping() -> void:
	if floor_texture == null:
		return
	var texture_meters := floor_texture.get_size() / pixels_per_meter
	for child: Node in get_children():
		if not child is MeshInstance3D or not child.mesh is PlaneMesh:
			continue
		var patch := child as MeshInstance3D
		if source_region.has_area():
			var grass := ShaderMaterial.new()
			grass.shader = preload("res://shaders/forest_floor.gdshader")
			grass.set_shader_parameter("source_texture", floor_texture)
			grass.set_shader_parameter("source_region", Vector4(source_region.position.x, source_region.position.y, source_region.size.x, source_region.size.y))
			grass.set_shader_parameter("tile_meters", region_tile_meters)
			patch.material_override = grass
			continue
		var material := patch.material_override as StandardMaterial3D
		if material == null:
			material = StandardMaterial3D.new()
			material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		# Duplicate on edit so one patch/scene never changes another's material.
		material = material.duplicate() as StandardMaterial3D
		material.albedo_texture = floor_texture
		var patch_size: Vector2 = patch.mesh.size
		var scale_uv := patch_size / texture_meters
		var origin := Vector2(patch.position.x, patch.position.z) - patch_size * 0.5
		var offset_uv := origin / texture_meters + texture_offset
		material.uv1_scale = Vector3(scale_uv.x, scale_uv.y, 1)
		material.uv1_offset = Vector3(offset_uv.x, offset_uv.y, 0)
		patch.material_override = material
