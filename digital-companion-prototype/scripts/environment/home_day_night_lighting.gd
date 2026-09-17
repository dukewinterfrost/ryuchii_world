class_name HomeDayNightLighting
extends Node
## Instance-scoped tint bindings; no global shader parameters or shared mutation.
var clock := TimeOfDayController.new()
var current_sample: Dictionary = TimeOfDayController.sample_time(12.0)
var _bindings: Dictionary = {}
var _sky_materials: Array[ShaderMaterial] = []
var _environment: Environment


func configure(stage: Node3D, environment: Environment) -> void:
	_environment = environment
	for path: String in ["ForestParallax/Sky", "ForestParallax/ForestVista"]:
		var card := stage.get_node_or_null(path) as Sprite3D
		if card == null:
			continue
		# BG-1 middle/foreground already contain real transparent silhouettes.
		# Tint them normally; only the distant sky gets sky-specific treatment.
		var bg1 := stage.get_node("ForestParallax/Sky").has_meta("bg1_sky")
		if bg1 and not card.has_meta("bg1_sky"):
			continue
		var material := ShaderMaterial.new()
		material.shader = preload("res://shaders/home_day_night_sky.gdshader")
		material.set_shader_parameter("artwork", card.texture)
		material.set_shader_parameter("is_panorama", path.ends_with("ForestVista"))
		material.set_shader_parameter("preserve_artwork", bg1)
		# Bring the authored sky opening down to the visible distant horizon.
		# Its original tall card showed only the painted ground in Field view.
		var base_position := card.position
		if not bg1:
			base_position.y -= 56.0 if path.ends_with("ForestVista") else 80.0
		stage.get_node("ForestParallax").set_layer_base_position(card, base_position)
		card.material_override = material
		card.set_meta("day_night_sky", true)
		_sky_materials.append(material)
	register_branch(stage)
	clock.name = "LocalTime"
	clock.lighting_changed.connect(_apply_sample)
	add_child(clock)


func register_branch(node: Node) -> void:
	if node.has_meta("day_night_sky"):
		return
	var id := node.get_instance_id()
	if not _bindings.has(id):
		var entry: Dictionary = {}
		if node is SpriteBase3D:
			entry = {"node": weakref(node), "base_color": node.modulate}
		elif node is MeshInstance3D and node.mesh != null:
			var materials: Array = []
			for surface: int in node.mesh.get_surface_count():
				var original: Material = node.get_active_material(surface)
				if original is BaseMaterial3D:
					var local := original.duplicate() as BaseMaterial3D
					node.set_surface_override_material(surface, local)
					materials.append({"material": local, "base_color": local.albedo_color})
				elif original is ShaderMaterial and original.shader in [preload("res://shaders/care_clearing_ground.gdshader"), preload("res://shaders/care_foliage.gdshader")]:
					var local := original.duplicate() as ShaderMaterial
					node.set_surface_override_material(surface, local)
					materials.append({"material": local})
			# Surface overrides must take precedence over the authored override.
			if not materials.is_empty():
				node.material_override = null
				entry = {"node": weakref(node), "materials": materials}
		if not entry.is_empty():
			_bindings[id] = entry
			node.tree_exiting.connect(_remove_binding.bind(id), CONNECT_ONE_SHOT)
			_apply_binding(entry)
	for child: Node in node.get_children():
		register_branch(child)


func _remove_binding(id: int) -> void:
	_bindings.erase(id)


func _apply_sample(sample: Dictionary) -> void:
	current_sample = sample
	for entry: Dictionary in _bindings.values():
		_apply_binding(entry)
	for material: ShaderMaterial in _sky_materials:
		for key: String in ["scenery_tint", "sky_top", "sky_horizon", "sun_position", "moon_position", "sun_visibility", "moon_visibility", "star_visibility"]:
			material.set_shader_parameter(key, sample[key])
	if _environment != null:
		_environment.background_color = sample.sky_horizon


func _apply_binding(entry: Dictionary) -> void:
	var node: Node = entry.node.get_ref()
	if node == null:
		return
	var tint: Color = current_sample.scenery_tint
	if node is SpriteBase3D:
		node.modulate = entry.base_color * tint
	else:
		for binding: Dictionary in entry.materials:
			if binding.material is ShaderMaterial:
				binding.material.set_shader_parameter("day_night_tint", tint)
			else:
				binding.material.albedo_color = binding.base_color * tint
