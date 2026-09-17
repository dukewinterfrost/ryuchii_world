class_name AssetResourceLibrary
extends RefCounted

## Explicit JSON -> native Godot resources. No collision/navigation is inferred
## from pixels. API reference: docs.godotengine.org/en/4.7/classes/class_tiledata.html

static func read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return value if value is Dictionary else {}


static func load_payload_texture(path: String) -> Texture2D:
	# Generated candidates are bound to PNG bytes, never mutable .png.import
	# settings. Native exports embed these pixels; packaged legacy art is separate.
	if not FileAccess.file_exists(path):
		return null
	var image := Image.new()
	if image.load_png_from_buffer(FileAccess.get_file_as_bytes(path)) != OK or image.is_empty():
		return null
	return ImageTexture.create_from_image(image)


static func assign_stable_ids(resource: Resource) -> void:
	# ResourceSaver normally invents random subresource suffixes. Stable traversal
	# makes native output byte-reproducible across candidate paths and processes.
	_stable_value(resource, {}, [0])


static func _stable_value(value: Variant, seen: Dictionary, serial: Array) -> void:
	if value is Resource:
		if seen.has(value.get_instance_id()):
			return
		seen[value.get_instance_id()] = true
		value.resource_scene_unique_id = "asset_%04d" % int(serial[0])
		serial[0] += 1
		var properties: Array[String] = []
		for property: Dictionary in value.get_property_list():
			if int(property.usage) & PROPERTY_USAGE_STORAGE:
				properties.append(String(property.name))
		properties.sort()
		for property: String in properties:
			_stable_value(value.get(property), seen, serial)
	elif value is Array:
		for item: Variant in value:
			_stable_value(item, seen, serial)
	elif value is Dictionary:
		var keys: Array = value.keys()
		keys.sort()
		for key: Variant in keys:
			_stable_value(value[key], seen, serial)


static func build_tileset(manifest: Dictionary, texture: Texture2D) -> Dictionary:
	var errors := validate_tileset(manifest, texture)
	if not errors.is_empty():
		return {"ok": false, "errors": errors}
	manifest = manifest.duplicate(true)
	for tile: Dictionary in manifest.tiles:
		tile["collision"] = movement_polygons(manifest, tile)
	var resource := TileSet.new()
	resource.tile_size = Vector2i(int(manifest.tileSize[0]), int(manifest.tileSize[1]))
	if manifest.get("projection", "square") == "isometric":
		resource.tile_shape = TileSet.TILE_SHAPE_ISOMETRIC
		resource.tile_layout = TileSet.TILE_LAYOUT_DIAMOND_DOWN
	# Layer zero is the documented contract for each authored polygon collection.
	resource.add_physics_layer()
	resource.set_physics_layer_collision_layer(0, 1)
	resource.set_physics_layer_collision_mask(0, 1)
	resource.add_navigation_layer()
	resource.add_occlusion_layer()
	var terrain_sets: Array = manifest.get("terrains", [])
	for set_index: int in terrain_sets.size():
		resource.add_terrain_set()
		var terrain_set: Dictionary = terrain_sets[set_index]
		resource.set_terrain_set_mode(set_index, int(terrain_set.get("mode", 0)))
		var terrains: Array = terrain_set.get("terrains", [])
		for terrain_index: int in terrains.size():
			resource.add_terrain(set_index)
			resource.set_terrain_name(set_index, terrain_index, String(terrains[terrain_index].get("name", "Terrain")))
			resource.set_terrain_color(set_index, terrain_index, Color.from_string(String(terrains[terrain_index].get("color", "#ffffff")), Color.WHITE))
	for layer: Dictionary in manifest.get("customDataLayers", []):
		var index := resource.get_custom_data_layers_count()
		resource.add_custom_data_layer()
		resource.set_custom_data_layer_name(index, String(layer.name))
		resource.set_custom_data_layer_type(index, _custom_type(layer.type))
	var source := TileSetAtlasSource.new()
	source.texture = texture
	source.texture_region_size = resource.tile_size
	source.use_texture_padding = true
	resource.add_source(source, 0)
	var tiles: Array = manifest.get("tiles", [])
	# Create each base before alternatives, regardless of JSON entry ordering.
	for tile: Dictionary in tiles:
		var coords := Vector2i(int(tile.atlas[0]), int(tile.atlas[1]))
		if not source.has_tile(coords):
			source.create_tile(coords)
	for tile: Dictionary in tiles:
		var coords := Vector2i(int(tile.atlas[0]), int(tile.atlas[1]))
		var alternative := int(tile.get("alternative", 0))
		if alternative != 0:
			source.create_alternative_tile(coords, alternative)
		var data := source.get_tile_data(coords, alternative)
		data.probability = float(tile.get("probability", 1.0))
		data.terrain_set = int(tile.get("terrainSet", -1))
		data.terrain = int(tile.get("terrain", -1))
		for bit: String in tile.get("terrainPeering", {}):
			if not data.is_valid_terrain_peering_bit(int(bit)):
				return {"ok": false, "errors": ["terrain peering bit %s is invalid for this projection/mode" % bit]}
			data.set_terrain_peering_bit(int(bit), int(tile.terrainPeering[bit]))
		var collision: Array = tile.get("collision", [])
		data.set_collision_polygons_count(0, collision.size())
		for index: int in collision.size():
			data.set_collision_polygon_points(0, index, polygon(collision[index]))
		var navigation: Array = tile.get("navigation", [])
		if not navigation.is_empty():
			var nav := NavigationPolygon.new()
			var vertices := PackedVector2Array()
			var triangles: Array[PackedInt32Array] = []
			for points: Array in navigation:
				var outline := polygon(points)
				var indices := Geometry2D.triangulate_polygon(outline)
				var offset := vertices.size()
				vertices.append_array(outline)
				nav.add_outline(outline)
				for index: int in range(0, indices.size(), 3):
					triangles.append(PackedInt32Array([indices[index] + offset, indices[index + 1] + offset, indices[index + 2] + offset]))
			nav.vertices = vertices
			for triangle: PackedInt32Array in triangles:
				nav.add_polygon(triangle)
			data.set_navigation_polygon(0, nav)
		var occlusion: Array = tile.get("occlusion", [])
		data.set_occluder_polygons_count(0, occlusion.size())
		for index: int in occlusion.size():
			var occluder := OccluderPolygon2D.new()
			occluder.polygon = polygon(occlusion[index])
			data.set_occluder_polygon(0, index, occluder)
		for key: String in tile.get("customData", {}):
			data.set_custom_data(key, tile.customData[key])
	resource.set_meta("source_manifest", manifest.duplicate(true))
	return {"ok": true, "tileset": resource, "errors": []}


static func validate_tileset(manifest: Dictionary, texture: Texture2D) -> Array[String]:
	var errors: Array[String] = []
	if texture == null:
		errors.append("tileset texture is required")
		return errors
	if manifest.get("projection", "square") not in ["square", "isometric"]:
		errors.append("projection must be square or isometric")
	for field: String in ["terrains", "customDataLayers"]:
		if not manifest.get(field, []) is Array:
			errors.append(field + " must be an array")
	if not errors.is_empty():
		return errors
	var size: Variant = manifest.get("tileSize")
	if not _pair(size) or not _positive_int(size[0]) or not _positive_int(size[1]):
		errors.append("tileSize must contain two positive integer dimensions")
		return errors
	var tiles: Variant = manifest.get("tiles")
	if not tiles is Array or tiles.is_empty():
		errors.append("tiles must be a non-empty array")
		return errors
	var terrain_sets: Array = manifest.get("terrains", [])
	for set_data: Variant in terrain_sets:
		if not set_data is Dictionary or not _nonnegative_int(set_data.get("mode", 0)) or int(set_data.get("mode", 0)) not in [0, 1, 2] or not set_data.get("terrains", []) is Array:
			errors.append("terrain sets require mode 0, 1, or 2 and a terrains array")
		else:
			for terrain: Variant in set_data.get("terrains", []):
				if not terrain is Dictionary or not terrain.get("name", "") is String:
					errors.append("terrain definitions must contain string names")
	var layers: Dictionary = {}
	for layer: Variant in manifest.get("customDataLayers", []):
		if not layer is Dictionary or String(layer.get("name", "")).is_empty() or _custom_type(layer.get("type", "")) == TYPE_NIL:
			errors.append("custom data layers require a name and bool/int/float/string type")
		elif layers.has(layer.name):
			errors.append("duplicate custom data layer: " + String(layer.name))
		else:
			layers[layer.name] = _custom_type(layer.type)
	if not errors.is_empty():
		return errors
	var seen: Dictionary = {}
	var bases: Dictionary = {}
	for tile: Variant in tiles:
		if not tile is Dictionary or not _pair(tile.get("atlas")):
			errors.append("tile must provide an atlas coordinate pair")
			continue
		var coordinate: Array = tile.atlas
		var alternative: Variant = tile.get("alternative", 0)
		if not _nonnegative_int(coordinate[0]) or not _nonnegative_int(coordinate[1]) or not _nonnegative_int(alternative) or int(alternative) >= 4096:
			errors.append("tile coordinates and alternative must be nonnegative integers (alternative <4096)")
			continue
		if not tile.get("terrainPeering", {}) is Dictionary or not tile.get("customData", {}) is Dictionary:
			errors.append("terrainPeering and customData must be dictionaries")
			continue
		if not _finite(tile.get("terrainSet", -1)) or not _finite(tile.get("terrain", -1)):
			errors.append("terrain set and terrain must be integer references")
			continue
		var combat: Variant = tile.get("combat")
		if combat == null and not tile.get("collision", []) is Array:
			errors.append("collision must be a polygon array")
			continue
		if combat == null and not tile.get("collision", []).is_empty():
			errors.append("collision requires a canonical ground-unit combat footprint")
			continue
		if combat != null:
			if not combat is Dictionary or not _positive_int(combat.get("cellSize")) or not combat.get("rect") is Array or combat.rect.size() != 4:
				errors.append("combat requires positive integer cellSize and a four-number ground rectangle")
				continue
			var good_rect := true
			for coordinate_value: Variant in combat.rect:
				good_rect = good_rect and _nonnegative_int(coordinate_value)
			if not good_rect or float(combat.rect[2]) <= 0 or float(combat.rect[3]) <= 0 or float(combat.rect[0]) + float(combat.rect[2]) > float(combat.cellSize) or float(combat.rect[1]) + float(combat.rect[3]) > float(combat.cellSize):
				errors.append("combat rectangle must stay within its declared ground cell")
				continue
			for flag: String in ["movement", "projectile", "sight", "occlusion"]:
				if not combat.get(flag) is bool:
					errors.append("combat flags must be explicit booleans")
		if (float(coordinate[0]) + 1) * float(size[0]) > texture.get_width() or (float(coordinate[1]) + 1) * float(size[1]) > texture.get_height():
			errors.append("tile extends beyond atlas texture")
		var key := "%s:%s:%s" % [coordinate[0], coordinate[1], alternative]
		if seen.has(key):
			errors.append("duplicate atlas coordinate/alternative: " + key)
		seen[key] = true
		if int(alternative) == 0:
			bases[str(coordinate)] = true
		if not CompanionAssetLibrary._is_positive_number(tile.get("probability", 1)):
			errors.append("tile probability must be finite and positive")
		var set_index := int(tile.get("terrainSet", -1))
		var terrain_index := int(tile.get("terrain", -1))
		if set_index < -1 or set_index >= terrain_sets.size():
			errors.append("tile references an invalid terrain set")
		elif set_index == -1 and (terrain_index != -1 or not tile.get("terrainPeering", {}).is_empty()):
			errors.append("terrain and peering require a terrain set")
		elif set_index >= 0:
			var terrain_count: int = terrain_sets[set_index].get("terrains", []).size()
			if terrain_index < -1 or terrain_index >= terrain_count:
				errors.append("tile references an invalid terrain")
			for bit: String in tile.get("terrainPeering", {}):
				var value := int(tile.terrainPeering[bit])
				if not bit.is_valid_int() or int(bit) < 0 or int(bit) > 15 or value < -1 or value >= terrain_count:
					errors.append("invalid terrain peering reference")
		for property: String in ["collision", "navigation", "occlusion"]:
			var polygons: Variant = movement_polygons(manifest, tile) if property == "collision" else tile.get(property, [])
			if not polygons is Array:
				errors.append(property + " must be an array of polygons")
				continue
			for points: Variant in polygons:
				if not _valid_polygon(points):
					errors.append(property + " contains an invalid or self-intersecting polygon")
		for name: String in tile.get("customData", {}):
			if not layers.has(name):
				errors.append("undefined custom data layer: " + name)
			elif typeof(tile.customData[name]) != int(layers[name]) and not (int(layers[name]) in [TYPE_INT, TYPE_FLOAT] and CompanionAssetLibrary._is_number(tile.customData[name])):
				errors.append("wrong custom data type: " + name)
	for tile: Variant in tiles:
		if tile is Dictionary and _pair(tile.get("atlas")) and not bases.has(str(tile.atlas)):
			errors.append("every atlas coordinate requires an authored base alternative 0")
	return errors


static func movement_polygons(manifest: Dictionary, tile: Dictionary) -> Array:
	# combat.rect + its ground-cell scale are the SINGLE collision authority.
	# Legacy/freehand movement polygons cannot silently disagree with live combat.
	var combat: Dictionary = tile.get("combat", {})
	if combat.is_empty() or not combat.get("movement", false):
		return []
	var rect: Array = combat.rect
	var size: Array = manifest.tileSize
	var cell := float(combat.cellSize)
	var points: Array = []
	for corner: Vector2 in [Vector2(rect[0], rect[1]), Vector2(rect[0] + rect[2], rect[1]), Vector2(rect[0] + rect[2], rect[1] + rect[3]), Vector2(rect[0], rect[1] + rect[3])]:
		if manifest.get("projection", "square") == "isometric":
			points.append([(corner.x - corner.y) * float(size[0]) / (2 * cell), (corner.x + corner.y - cell) * float(size[1]) / (2 * cell)])
		else:
			points.append([corner.x / cell * float(size[0]) - float(size[0]) * 0.5, corner.y / cell * float(size[1]) - float(size[1]) * 0.5])
	return [points]


static func polygon(points: Array) -> PackedVector2Array:
	var result := PackedVector2Array()
	for point: Array in points:
		result.append(Vector2(float(point[0]), float(point[1])))
	return result


static func _valid_polygon(value: Variant) -> bool:
	if not value is Array or value.size() < 3:
		return false
	for point: Variant in value:
		if not _pair(point) or not _finite(point[0]) or not _finite(point[1]):
			return false
	return not Geometry2D.triangulate_polygon(polygon(value)).is_empty()


static func _pair(value: Variant) -> bool:
	return value is Array and value.size() == 2


static func _finite(value: Variant) -> bool:
	return CompanionAssetLibrary._is_number(value) and is_finite(float(value))


static func _nonnegative_int(value: Variant) -> bool:
	return _finite(value) and float(value) >= 0 and float(value) == floorf(float(value))


static func _positive_int(value: Variant) -> bool:
	return _nonnegative_int(value) and float(value) > 0


static func _custom_type(value: Variant) -> int:
	if value is String:
		return {"bool": TYPE_BOOL, "int": TYPE_INT, "float": TYPE_FLOAT, "string": TYPE_STRING}.get(value, TYPE_NIL)
	return int(value) if value in [TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING] else TYPE_NIL
