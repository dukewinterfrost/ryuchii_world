class_name ArenaView
extends Node2D

## Presentation only. Combat uses the same explicit obstacles in BattleArena.
## Ground coordinates remain Euclidean; isometric projection never changes range.

var arena: Dictionary = {}
var tile_set: TileSet
var debug_overlays := false
var dependency_error := ""
var _props: Array[Node2D] = []
var _tile_visuals: Array[Node2D] = []
var _occluding_cells: Dictionary = {}
var _background: Texture2D
var _combat_overlay: Node2D

class CombatOverlay extends Node2D:
	var view: ArenaView
	var session: Dictionary = {}
	func point(value: Array) -> Vector2:
		return view.project(Vector2(float(value[0]), float(value[1])) / BattleSimulator.SCALE)
	func _draw() -> void:
		if session.is_empty():
			return
		for actor: Dictionary in session.get("actors", {}).values():
			var start := point(actor.pos)
			var action := String(actor.get("action", "idle"))
			var tick := int(actor.get("action_tick", 0))
			var windup := int(actor.get("windup", 0))
			if action in ["basic_attack", "special_attack"] and tick < windup + int(actor.get("active_ticks", 0)):
				var ground_start := Vector2(float(actor.pos[0]), float(actor.pos[1])) / BattleSimulator.SCALE
				var aim := Vector2(float(actor.aim[0]), float(actor.aim[1])) / BattleSimulator.SCALE
				var reach := float(BattleSimulator.SPECIAL_RANGE if action == "special_attack" else BattleSimulator.BASIC_RANGE) / BattleSimulator.SCALE
				var direction := ground_start.direction_to(aim)
				var ground_end := view.clipped_attack_end(ground_start, ground_start + direction * reach, 4 if action == "special_attack" else 6)
				var finish := view.project(ground_end)
				var color := Color("ffcc78") if action == "special_attack" else Color("ff8878")
				if tick < windup:
					color.a = 0.35 + 0.5 * float(tick) / maxf(1, windup)
					draw_line(start, finish, color, 2, true)
					draw_circle(finish, 5, color, false, 1.5)
				elif action == "basic_attack":
					# Melee's authored active ray has a 6-ground-unit half-width.
					var side := Vector2(-direction.y, direction.x) * 6
					var points := PackedVector2Array([view.project(ground_start + side), view.project(ground_end + side), view.project(ground_end - side), view.project(ground_start - side)])
					color.a = 0.45
					draw_colored_polygon(points, color)
			if action == "guard":
				draw_arc(start + Vector2(0, -8), 18, -PI, 0, 18, Color("84d5eb"), 2, true)
			elif action == "evade":
				draw_line(point(actor.previous_pos), start, Color(0.75, 0.95, 1, 0.75), 3, true)
			if view.debug_overlays:
				var radius := float(actor.get("radius", BattleSimulator.BODY_RADIUS)) / BattleSimulator.SCALE
				var ground := Vector2(float(actor.pos[0]), float(actor.pos[1])) / BattleSimulator.SCALE
				var body := view._rectangle(Rect2(ground - Vector2.ONE * radius, Vector2.ONE * radius * 2))
				body.append(body[0])
				draw_polyline(body, Color(0.4, 0.85, 1, 0.8), 1, true)
				var path := PackedVector2Array([start])
				for waypoint: Array in actor.get("path", []):
					path.append(point(waypoint))
				if path.size() > 1:
					draw_polyline(path, Color(0.4, 0.85, 1, 0.35), 1, true)
		for projectile: Dictionary in session.get("projectiles", []):
			var position := point(projectile.pos)
			var velocity := Vector2(float(projectile.velocity[0]), float(projectile.velocity[1])).normalized()
			var previous := point(projectile.previous_pos)
			draw_line(previous - velocity * 8, position, Color("ff923d"), 5, true)
			draw_circle(position, maxf(3, float(projectile.get("radius", BattleSimulator.PROJECTILE_RADIUS)) / BattleSimulator.SCALE), Color("ffe5a0"))


func render_session(session: Dictionary) -> void:
	# Presentation only: no simulation calls and no mutation of the live session.
	if _combat_overlay == null:
		_combat_overlay = CombatOverlay.new()
		_combat_overlay.view = self
		_combat_overlay.z_index = 20
		add_child(_combat_overlay)
	_combat_overlay.session = session
	_combat_overlay.queue_redraw()


func clipped_attack_end(start: Vector2, finish: Vector2, margin: float) -> Vector2:
	# Telegraphs stop at the playable boundary/first projectile blocker just as the
	# simulation does. They must never draw through the HUD or imply a hidden hit.
	var delta := finish - start
	var fraction := 1.0
	var size := ground_size()
	for axis: int in 2:
		if finish[axis] < margin and delta[axis] < 0:
			fraction = minf(fraction, (margin - start[axis]) / delta[axis])
		elif finish[axis] > size[axis] - margin and delta[axis] > 0:
			fraction = minf(fraction, (size[axis] - margin - start[axis]) / delta[axis])
	var hit := BattleArena.obstruction_fraction(arena, [int(start.x * BattleSimulator.SCALE), int(start.y * BattleSimulator.SCALE)], [int(finish.x * BattleSimulator.SCALE), int(finish.y * BattleSimulator.SCALE)], int(margin * BattleSimulator.SCALE), "projectile")
	if hit >= 0:
		fraction = minf(fraction, float(hit) / BattleArena.FRACTION)
	return start + delta * clampf(fraction, 0, 1)

class ArenaProp extends Node2D:
	var footprint := PackedVector2Array()
	var canopy := false
	var blocking := false
	var special := false
	func _draw() -> void:
		# Deliberately simple engineering markers until reviewed prop art is promoted.
		if blocking:
			draw_colored_polygon(footprint, Color("53664e"))
		elif special:
			draw_colored_polygon(footprint, Color(0.45, 0.7, 0.78, 0.4))
		if canopy:
			draw_line(Vector2.ZERO, Vector2(0, -24), Color("76604b"), 7)
			draw_set_transform(Vector2(0, -31), 0, Vector2(1.5, 1))
			draw_circle(Vector2.ZERO, 21, Color("3e6653"))

class TileVisual extends Node2D:
	var texture: Texture2D
	var texture_region := Rect2()
	var display_rect := Rect2()
	func _draw() -> void:
		if texture != null:
			draw_texture_rect_region(texture, display_rect, texture_region)


func configure(manifest: Dictionary, candidate_folder: String = "") -> void:
	if _combat_overlay != null:
		_combat_overlay.session = {}
		_combat_overlay.queue_redraw()
	for prop: Node2D in _props:
		prop.free()
	_props.clear()
	_clear_tile_visuals()
	arena = manifest.duplicate(true)
	_background = null
	var own_id := String(arena.get("assetId", ""))
	var own_revision := String(arena.get("revision", ""))
	var own_folder := candidate_folder
	if own_folder.is_empty() and _safe_segment(own_id) and _safe_segment(own_revision):
		own_folder = "res://assets/generated/%s/%s" % [own_id, own_revision]
	if not own_folder.is_empty() and arena.has("background"):
		if ResourceLoader.exists(own_folder.path_join("arena.tres")):
			var native := load(own_folder.path_join("arena.tres")) as Resource
			_background = native.get_meta("background_texture", null) as Texture2D
		var background_name := String(arena.background)
		if _background == null and _safe_segment(background_name):
			var background_path := own_folder.path_join(background_name)
			_background = AssetResourceLibrary.load_payload_texture(background_path)
	y_sort_enabled = true
	tile_set = null
	dependency_error = ""
	var dependency: Dictionary = arena.get("tileSet", {})
	if not dependency.is_empty():
		var asset_id := String(dependency.get("assetId", ""))
		var revision := String(dependency.get("revision", ""))
		if not _safe_segment(asset_id) or not _safe_segment(revision):
			dependency_error = "Invalid pinned TileSet identifier"
		else:
			var folder := "res://assets/generated/%s/%s/" % [asset_id, revision]
			if ResourceLoader.exists(folder + "tileset.tres"):
				tile_set = load(folder + "tileset.tres") as TileSet
			else:
				var source := AssetResourceLibrary.read_json(folder + "tileset.json")
				var texture := AssetResourceLibrary.load_payload_texture(folder + "atlas.png")
				if texture != null and not source.is_empty():
					var built := AssetResourceLibrary.build_tileset(source, texture)
					if built.ok:
						tile_set = built.tileset
			if tile_set == null:
				dependency_error = "Missing pinned TileSet %s / %s" % [asset_id, revision]
	_rebuild_tile_visuals()
	for obstacle: Dictionary in arena.get("obstacles", []):
		if tile_set != null and obstacle.get("tileDerived", false):
			continue
		var rect_data: Array = obstacle.get("rect", [])
		if rect_data.size() != 4:
			continue
		var rect := Rect2(float(rect_data[0]), float(rect_data[1]), float(rect_data[2]), float(rect_data[3]))
		var prop := ArenaProp.new()
		prop.position = project(Vector2(rect.get_center().x, rect.end.y))
		prop.footprint = _rectangle(rect)
		for index: int in prop.footprint.size():
			prop.footprint[index] -= prop.position
		# Occlusion is a rendering flag, not a declaration that a solid prop is a
		# tree. Only nonblocking overhead placeholders use the canopy marker.
		prop.canopy = bool(obstacle.get("occlusion", false)) and not bool(obstacle.get("movement", false))
		prop.blocking = bool(obstacle.get("movement", false))
		prop.special = bool(obstacle.get("projectile", false)) or bool(obstacle.get("sight", false))
		add_child(prop)
		_props.append(prop)
	queue_redraw()


func project(ground: Vector2) -> Vector2:
	return Vector2(ground.x - ground.y, (ground.x + ground.y) * 0.5) if arena.get("projection", "square") == "isometric" else ground


func projected_bounds() -> Rect2:
	var size := ground_size()
	var bounds := Rect2(project(Vector2.ZERO), Vector2.ZERO)
	for corner: Vector2 in [Vector2(size.x, 0), size, Vector2(0, size.y)]:
		bounds = bounds.expand(project(corner))
	return bounds


func fit_to(rect: Rect2) -> void:
	var bounds := projected_bounds()
	if bounds.size.x <= 0 or bounds.size.y <= 0:
		return
	var factor := minf(rect.size.x / bounds.size.x, rect.size.y / bounds.size.y)
	scale = Vector2.ONE * factor
	position = rect.get_center() - bounds.get_center() * factor


func ground_size() -> Vector2:
	return Vector2(float(arena.get("ground", {}).get("width", 640)), float(arena.get("ground", {}).get("height", 480)))


func _draw() -> void:
	if arena.is_empty():
		return
	var bounds := _rectangle(Rect2(Vector2.ZERO, ground_size()))
	draw_colored_polygon(bounds, Color("263e35"))
	if _background != null:
		# Backgrounds are authored in the bundle's declared presentation projection.
		draw_texture_rect(_background, projected_bounds(), false)
	_draw_tiles()
	var cell := float(arena.get("ground", {}).get("cellSize", 20))
	if cell <= 0:
		return
	if tile_set == null or debug_overlays:
		for x: int in range(0, int(ground_size().x) + 1, maxi(1, int(cell))):
			draw_line(project(Vector2(x, 0)), project(Vector2(x, ground_size().y)), Color(0.8, 1, 0.85, 0.07), 1)
		for y: int in range(0, int(ground_size().y) + 1, maxi(1, int(cell))):
			draw_line(project(Vector2(0, y)), project(Vector2(ground_size().x, y)), Color(0.8, 1, 0.85, 0.07), 1)
	for obstacle: Dictionary in arena.get("obstacles", []):
		var data: Array = obstacle.get("rect", [])
		if data.size() != 4:
			continue
		var rect := Rect2(float(data[0]), float(data[1]), float(data[2]), float(data[3]))
		var points := _rectangle(rect)
		# Footprints are authoritative; simple prototype decoration does not enlarge
		# them. Authored TileSet artwork remains visible underneath debug outlines.
		if debug_overlays:
			if obstacle.get("movement", false):
				_outline(points, Color("ff7777"), 2)
				_outline(_rectangle(rect.grow(float(arena.get("maxBodyRadius", 16)))), Color(1, 0.4, 0.4, 0.25), 1)
			if obstacle.get("projectile", false):
				_outline(_rectangle(rect.grow(-2)), Color("ffcb70"), 1)
			if obstacle.get("sight", false):
				_outline(_rectangle(rect.grow(-4)), Color("6cbfff"), 1)
			if obstacle.get("occlusion", false):
				_outline(_rectangle(rect.grow(3)), Color("d58aff"), 1)
			var label := String(obstacle.get("id", "obstacle"))
			draw_string(ThemeDB.fallback_font, project(rect.position) + Vector2(2, -5), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color.WHITE)
	_outline(bounds, Color("92b79c"), 2)
	if debug_overlays:
		for side: String in arena.get("spawns", {}):
			var coordinate: Array = arena.spawns[side]
			var point := project(Vector2(float(coordinate[0]), float(coordinate[1])))
			draw_circle(point, float(arena.get("maxBodyRadius", 16)), Color(0.5, 0.8, 1, 0.5), false, 1.5)
			draw_string(ThemeDB.fallback_font, point + Vector2(20, 0), side, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE)
	if not dependency_error.is_empty():
		draw_string(ThemeDB.fallback_font, project(Vector2(20, 30)), dependency_error, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.SALMON)


func _clear_tile_visuals() -> void:
	for visual: Node2D in _tile_visuals:
		visual.free()
	_tile_visuals.clear()
	_occluding_cells.clear()


func _rebuild_tile_visuals() -> void:
	# Only explicit visual occlusion moves artwork into the actor Y-sort group.
	# The canonical tile-derived footprint supplies its root; collision flags and
	# atlas transparency never infer depth or alter authoritative combat geometry.
	_clear_tile_visuals()
	if tile_set == null or not tile_set.has_source(0):
		return
	var source := tile_set.get_source(0) as TileSetAtlasSource
	if source == null:
		return
	var footprints: Dictionary = {}
	for obstacle: Dictionary in arena.get("obstacles", []):
		if obstacle.get("tileDerived", false) and obstacle.get("occlusion", false):
			footprints[String(obstacle.id)] = obstacle.rect
	for tile: Dictionary in _sorted_tiles():
		var key := "tile-%d-%d" % [int(tile.cell[0]), int(tile.cell[1])]
		if not footprints.has(key):
			continue
		var atlas := Vector2i(int(tile.atlas[0]), int(tile.atlas[1]))
		if not source.has_tile(atlas) or not source.has_alternative_tile(atlas, int(tile.get("alternative", 0))):
			continue
		var data: Array = footprints[key]
		var rect := Rect2(float(data[0]), float(data[1]), float(data[2]), float(data[3]))
		var front := rect.end if arena.get("projection", "square") == "isometric" else Vector2(rect.get_center().x, rect.end.y)
		var visual := TileVisual.new()
		visual.name = key
		visual.position = project(front)
		visual.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		visual.texture = source.texture
		visual.texture_region = source.get_tile_texture_region(atlas)
		visual.display_rect = _tile_display_rect(tile)
		visual.display_rect.position -= visual.position
		add_child(visual)
		_tile_visuals.append(visual)
		_occluding_cells[key] = true
	queue_redraw()


func _tile_display_rect(tile: Dictionary) -> Rect2:
	var cell := float(arena.get("ground", {}).get("cellSize", 20))
	var ground := Vector2(float(tile.cell[0]) + 0.5, float(tile.cell[1]) + 0.5) * cell
	var display_size := Vector2(cell * 2, cell) if arena.get("projection", "square") == "isometric" else Vector2.ONE * cell
	return Rect2(project(ground) - display_size * 0.5, display_size)


func _sorted_tiles() -> Array:
	var isometric: bool = arena.get("projection", "square") == "isometric"
	var tiles: Array = arena.get("tiles", []).duplicate()
	tiles.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ay := float(a.cell[0]) + float(a.cell[1]) if isometric else float(a.cell[1])
		var by := float(b.cell[0]) + float(b.cell[1]) if isometric else float(b.cell[1])
		return ay < by if ay != by else float(a.cell[0]) < float(b.cell[0]))
	return tiles


func _draw_tiles() -> void:
	if tile_set == null or not tile_set.has_source(0):
		return
	var source := tile_set.get_source(0) as TileSetAtlasSource
	if source == null:
		return
	for tile: Dictionary in _sorted_tiles():
		if _occluding_cells.has("tile-%d-%d" % [int(tile.cell[0]), int(tile.cell[1])]):
			continue # Drawn once by a Y-sorted child, not again behind the actors.
		var atlas := Vector2i(int(tile.atlas[0]), int(tile.atlas[1]))
		var alternative := int(tile.get("alternative", 0))
		if not source.has_tile(atlas) or not source.has_alternative_tile(atlas, alternative):
			continue
		var region := source.get_tile_texture_region(atlas)
		draw_texture_rect_region(source.texture, _tile_display_rect(tile), region)


func _rectangle(rect: Rect2) -> PackedVector2Array:
	return PackedVector2Array([project(rect.position), project(Vector2(rect.end.x, rect.position.y)), project(rect.end), project(Vector2(rect.position.x, rect.end.y))])


func _outline(points: PackedVector2Array, color: Color, width: float) -> void:
	var closed := points.duplicate()
	closed.append(points[0])
	draw_polyline(closed, color, width, true)


static func _safe_segment(value: String) -> bool:
	return not value.is_empty() and value not in [".", ".."] and value.validate_filename() == value and not value.contains("/") and not value.contains("\\")
