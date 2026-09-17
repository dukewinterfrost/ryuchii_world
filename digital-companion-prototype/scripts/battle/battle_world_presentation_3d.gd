class_name BattleWorldPresentation3D
extends EnvironmentView3D

## Presentation-only battle adapter. BattleSimulator and BattleArena remain the
## sole authorities for movement, collision, attacks, and replay state.

const MAX_PROJECTILE_VFX := 32

var arena_manifest: Dictionary = {}
var fighter_presentations: Dictionary = {}
var fighter_vfx: Dictionary = {}
var projectile_vfx: Dictionary = {}
var missing_art_ids: Array[String] = []
var last_framing_world_points: Array[Vector3] = []

var _effect_records: Dictionary = {}
var _debug_geometry := false
var _fire_texture: Texture2D
var _hit_texture: Texture2D


func configure_battle(arena: Dictionary, package: Dictionary) -> bool:
	clear_battle()
	if not arena.get("environment") is Dictionary or not package.get("pin") is Dictionary:
		return false
	if arena.environment != package.pin:
		return false
	if not configure_package(package):
		return false
	var placements: Variant = arena.get("presentation", {}).get("staticPlacements", [])
	if not placements is Array or not set_static_placements(placements, "arena"):
		unload_environment()
		return false
	arena_manifest = arena.duplicate(true)
	_build_geometry_overlay()
	return true


func configure_fighters(session: Dictionary) -> bool:
	_clear_fighters()
	if environment_manifest.is_empty() or not session.get("fighters") is Array:
		return false
	var pins: Dictionary = session.get("content_revisions", {}).get("visuals", {})
	for fighter: Dictionary in session.fighters:
		var id := String(fighter.get("fighter_id", ""))
		var pin: Dictionary = pins.get(id, {})
		var library: Dictionary = {}
		if pin.has_all(["assetId", "revision"]):
			library = CompanionAssetLibrary.build_pinned(String(fighter.get("species_id", "")),
				String(pin.assetId), String(pin.revision))
		var presentation := CompanionPresentation3D.new()
		presentation.name = (id + " presentation").to_pascal_case()
		if not attach_world_node(presentation):
			presentation.free()
			_clear_fighters()
			return false
		if library.is_empty() or not presentation.configure_library(library, String(fighter.get("species_id", "missing"))):
			missing_art_ids.append(id)
			var marker := Label3D.new()
			marker.text = "ART?"
			marker.font_size = 24
			marker.modulate = Color.SALMON
			marker.position.y = 1.3
			marker.no_depth_test = false
			presentation.add_child(marker)
		fighter_presentations[id] = presentation
		var effect := WorldVFX3D.new()
		effect.name = (id + " hit vfx").to_pascal_case()
		effect.configure(_hit_effect_texture(), _vfx_definition(7))
		effect.visible = false
		attach_world_node(effect)
		fighter_vfx[id] = effect
	frame_session(session, 1.0, true)
	return fighter_presentations.size() == session.fighters.size()


func configure_workshop_battle(arena: Dictionary, region_id: String) -> bool:
	# Explicit isolated review only. Saved art-direction scenes never masquerade
	# as promoted immutable environment packages in gameplay or replay metadata.
	var game := get_tree().root.get_node_or_null("GameState")
	if game == null or not game.isolated_mode:
		return false
	var encounter := EncounterCatalog.resolve(region_id)
	if not encounter.get("ok", false) or encounter.regionId != region_id or arena.get("regionId") != region_id:
		return false
	var folder := "res://tests/fixtures/regions/%s/review/arena" % region_id
	var source := AssetResourceLibrary.read_json(folder.path_join("arena.json"))
	for field: String in ["assetId", "ground", "spawns", "obstacles"]:
		if arena.get(field) != source.get(field):
			return false
	clear_battle()
	var scene_path := "res://scenes/environment_workshop/%s_battle.tscn" % region_id.replace("-", "_")
	var bounds := Rect2(0, 0, float(arena.ground.width), float(arena.ground.height))
	if not _configure_native_stage(scene_path, bounds, "workshop-" + region_id):
		return false
	environment_manifest["builtin"] = false
	environment_manifest["reviewOnly"] = true
	arena_manifest = arena.duplicate(true)
	_build_geometry_overlay()
	return true


func render_session(session: Dictionary, interpolation := 1.0) -> void:
	if environment_manifest.is_empty() or session.is_empty():
		return
	var alpha := clampf(interpolation, 0.0, 1.0)
	for id: String in fighter_presentations:
		if not session.get("actors", {}).has(id):
			continue
		var actor: Dictionary = session.actors[id]
		var previous := _fixed_ground(actor.get("previous_pos", actor.get("pos", [0, 0])))
		var current := BattleSimulator.ground_position(actor)
		var ground := previous.lerp(current, alpha)
		var presentation: CompanionPresentation3D = fighter_presentations[id]
		presentation.set_ground_position(ground)
		presentation.render_battle(actor, alpha)
		_sample_hit_vfx(id, ground, session, alpha)
	_sync_projectiles(session, alpha)
	frame_session(session, alpha, false)


func record_effect(fighter_id: String, effect_id: String, tick: int, duration_ticks: int) -> void:
	if fighter_vfx.has(fighter_id):
		_effect_records[fighter_id] = {"effect": effect_id, "start": tick, "duration": maxi(1, duration_ticks)}


func set_debug_geometry(enabled: bool) -> void:
	_debug_geometry = enabled
	set_debug_group_visible("BattleObstacles", enabled)


func frame_session(session: Dictionary, interpolation := 1.0, immediate := false) -> bool:
	if session.get("fighter_order", []).is_empty():
		return false
	var alpha := clampf(interpolation, 0.0, 1.0)
	var bounds := Rect2()
	var initialized := false
	var world_points: Array[Vector3] = []
	for id: Variant in session.fighter_order:
		var actor: Dictionary = session.actors.get(id, {})
		if actor.is_empty():
			continue
		var point := _fixed_ground(actor.get("previous_pos", actor.pos)).lerp(BattleSimulator.ground_position(actor), alpha)
		if not initialized:
			bounds = Rect2(point, Vector2.ZERO)
			initialized = true
		else:
			bounds = bounds.expand(point)
		var presentation: CompanionPresentation3D = fighter_presentations.get(String(id))
		if presentation != null:
			world_points.append_array(presentation.visual_world_corners(point, true))
		else:
			world_points.append(ground_to_world(point))
	for projectile: Dictionary in session.get("projectiles", []).slice(0, MAX_PROJECTILE_VFX):
		var previous := _fixed_ground(projectile.get("previous_pos", projectile.get("pos", [0, 0])))
		var current := _fixed_ground(projectile.get("pos", [0, 0]))
		var ground := previous.lerp(current, alpha)
		bounds = bounds.expand(ground)
		var center := _projectile_position(projectile, alpha)
		# Generated Pepper Breath cards are 24px at 1/32 scale and pulse to
		# 1.05x. This envelope deliberately covers the largest animation sample.
		for x: float in [-0.42, 0.42]:
			for y: float in [-0.42, 0.42]:
				world_points.append(center + camera.global_basis.orthonormalized() * Vector3(x, y, 0.0))
	last_framing_world_points = world_points.duplicate()
	return initialized and frame_world_points(world_points, bounds.get_center(), immediate)


func set_reduced_motion(enabled: bool) -> void:
	super.set_reduced_motion(enabled)
	for effect: WorldVFX3D in fighter_vfx.values():
		effect.set_meta("reduced_motion", enabled)
	for effect: WorldVFX3D in projectile_vfx.values():
		effect.set_meta("reduced_motion", enabled)


func battle_instrumentation() -> Dictionary:
	var evidence := instrumentation()
	evidence.merge({
		"fighters": fighter_presentations.size(),
		"persistentVfx": fighter_vfx.size(),
		"projectileVfx": projectile_vfx.size(),
		"missingArt": missing_art_ids.duplicate(),
		"environmentEnabled": not environment_manifest.is_empty(),
		"debugGeometry": _debug_geometry,
	}, true)
	return evidence


func clear_battle() -> void:
	clear_effects()
	_clear_fighters()
	arena_manifest.clear()
	if not environment_manifest.is_empty():
		unload_environment()


func clear_effects() -> void:
	## Replay clocks start with an empty presentation history. Persistent fighter
	## effect nodes remain reusable, but every transient record/projectile is gone.
	_effect_records.clear()
	for effect: WorldVFX3D in fighter_vfx.values():
		effect.visible = false
	for effect: WorldVFX3D in projectile_vfx.values():
		if is_instance_valid(effect):
			effect.free()
	projectile_vfx.clear()
	last_framing_world_points.clear()


func _clear_fighters() -> void:
	for node: Node in fighter_presentations.values():
		if is_instance_valid(node):
			node.free()
	for node: Node in fighter_vfx.values():
		if is_instance_valid(node):
			node.free()
	for node: Node in projectile_vfx.values():
		if is_instance_valid(node):
			node.free()
	fighter_presentations.clear()
	fighter_vfx.clear()
	projectile_vfx.clear()
	missing_art_ids.clear()


func _sync_projectiles(session: Dictionary, alpha: float) -> void:
	var live: Dictionary = {}
	for projectile: Dictionary in session.get("projectiles", []).slice(0, MAX_PROJECTILE_VFX):
		var id := str(projectile.get("id", ""))
		live[id] = true
		if not projectile_vfx.has(id):
			var effect := WorldVFX3D.new()
			effect.name = ("Projectile " + id).to_pascal_case()
			if not effect.configure(_fire_effect_texture(), _vfx_definition(6)) or not attach_world_node(effect):
				effect.free()
				continue
			effect.set_meta("reduced_motion", reduced_motion)
			projectile_vfx[id] = effect
			var owner: CompanionPresentation3D = fighter_presentations.get(String(projectile.get("owner_id", "")))
			var origin := _fixed_ground(projectile.get("previous_pos", projectile.get("pos", [0, 0])))
			effect.set_meta("launch_ground", origin)
			effect.set_meta("launch_offset", owner.attachment_offset("mouth") if owner != null else Vector3(0, 0.8, 0))
			for target_id: String in fighter_presentations:
				if target_id != String(projectile.get("owner_id", "")):
					var target: CompanionPresentation3D = fighter_presentations[target_id]
					effect.set_meta("target_offset", target.attachment_offset("impact"))
					effect.set_meta("travel_distance", maxf(1.0, origin.distance_to(target.get_ground_position())))
		var previous := _fixed_ground(projectile.get("previous_pos", projectile.get("pos", [0, 0])))
		var current := _fixed_ground(projectile.get("pos", [0, 0]))
		var effect: WorldVFX3D = projectile_vfx[id]
		effect.position = _projectile_position(projectile, alpha)
		var phase := float(int(session.get("tick", 0)) % 8) / 8.0
		effect.scale = Vector3.ONE if reduced_motion else Vector3.ONE * (0.9 + 0.15 * sin(phase * TAU))
	for id: String in projectile_vfx.keys():
		if not live.has(id):
			var expired: Node = projectile_vfx[id]
			projectile_vfx.erase(id)
			expired.queue_free()


func _projectile_position(projectile: Dictionary, alpha: float) -> Vector3:
	var previous := _fixed_ground(projectile.get("previous_pos", projectile.get("pos", [0, 0])))
	var ground := previous.lerp(_fixed_ground(projectile.get("pos", [0, 0])), alpha)
	var effect: WorldVFX3D = projectile_vfx.get(str(projectile.get("id", "")))
	if effect == null:
		return ground_to_world(ground) + Vector3(0, 0.8, 0)
	var origin: Vector2 = effect.get_meta("launch_ground", ground)
	var fraction := clampf(origin.distance_to(ground) / float(effect.get_meta("travel_distance", 1.0)), 0, 1)
	var start: Vector3 = effect.get_meta("launch_offset", Vector3(0, 0.8, 0))
	var finish: Vector3 = effect.get_meta("target_offset", start)
	return ground_to_world(ground) + start.lerp(finish, fraction)


func _sample_hit_vfx(id: String, ground: Vector2, session: Dictionary, alpha: float) -> void:
	var effect: WorldVFX3D = fighter_vfx.get(id)
	if effect == null:
		return
	effect.visible = false
	if not _effect_records.has(id):
		return
	var record: Dictionary = _effect_records[id]
	var elapsed := maxf(0.0, float(int(session.get("tick", 0)) - 1) + alpha - float(record.start))
	var fraction := elapsed / float(record.duration)
	if fraction >= 1.0:
		_effect_records.erase(id)
		return
	effect.visible = true
	var fiery := String(record.effect) == "hit_fire"
	effect.texture = _fire_effect_texture() if fiery else _hit_effect_texture()
	var target: CompanionPresentation3D = fighter_presentations.get(id)
	var impact := target.attachment_offset("impact") if target != null else Vector3(0, 1, 0)
	# Sit just in front of the body card so the impact is not hidden inside it;
	# retain depth testing against environmental occluders.
	effect.position = ground_to_world(ground) + impact + camera.global_basis.z * 0.15 + Vector3(0, 0 if reduced_motion else fraction * 0.6, 0)
	var scale_value := 1.2 if reduced_motion else 0.8 + sin(fraction * PI) * (1.5 if fiery else 0.65)
	effect.scale = Vector3.ONE * scale_value
	effect.modulate = Color(1.0, 1.0 if fiery else 0.55, 1.0 if fiery else 0.18, 1.0 - fraction)


func _build_geometry_overlay() -> void:
	var rectangles: Array = []
	for obstacle: Dictionary in arena_manifest.get("obstacles", []):
		if bool(obstacle.get("movement", false)):
			rectangles.append(obstacle.rect)
	set_debug_rectangles("BattleObstacles", rectangles, Color(0.9, 0.2, 0.15, 0.28))
	set_debug_geometry(_debug_geometry)


func _fixed_ground(value: Variant) -> Vector2:
	if not value is Array or value.size() != 2:
		return Vector2.ZERO
	return Vector2(float(value[0]), float(value[1])) / BattleSimulator.SCALE


func _vfx_definition(priority: int) -> Dictionary:
	return {"alphaMode": "transparent", "depthBehavior": "prepass", "renderPriority": priority, "pixelSize": 1.0 / 32.0}


func _fire_effect_texture() -> Texture2D:
	if _fire_texture == null:
		_fire_texture = _pixel_effect_texture(Color("ff5b1f"), Color("ffe6a3"), false)
	return _fire_texture


func _hit_effect_texture() -> Texture2D:
	if _hit_texture == null:
		_hit_texture = _pixel_effect_texture(Color("ffc84d"), Color("fff5bf"), true)
	return _hit_texture


static func _pixel_effect_texture(primary: Color, highlight: Color, burst: bool) -> Texture2D:
	var image := Image.create(24, 24, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	for y: int in 24:
		for x: int in 24:
			var delta := Vector2(x - 11.5, y - 11.5)
			var inside := absf(delta.x) + absf(delta.y) < (11.0 if burst else 8.0)
			if not burst:
				inside = delta.length_squared() < 75.0 or (x < 9 and absf(delta.y) < float(9 - x) * 0.45)
			if inside:
				image.set_pixel(x, y, highlight if delta.length_squared() < 20.0 else primary)
	return ImageTexture.create_from_image(image)
