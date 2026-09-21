class_name BattleWorldPresentation3D
extends EnvironmentView3D

## Presentation-only battle adapter. BattleSimulator and BattleArena remain the
## sole authorities for movement, collision, attacks, and replay state.

const MAX_PROJECTILE_VFX := 32

var arena_manifest: Dictionary = {}
var fighter_presentations: Dictionary = {}
var fighter_vfx: Dictionary = {}
var fighter_cues: Dictionary = {}
var _bubble_texture: Texture2D
var _charge_overlay: BattleChargeOverlay
var presentation_safe_rect := Rect2()
var projectile_vfx: Dictionary = {}
var missing_art_ids: Array[String] = []
var last_framing_world_points: Array[Vector3] = []

var _effect_records: Dictionary = {}
var _debug_geometry := false
var _fire_texture: Texture2D
var _hit_texture: Texture2D
var _shield_texture: Texture2D
var _perfect_guard_texture: Texture2D


func configure_native_battle_field(arena: Dictionary) -> bool:
	clear_battle()
	if not BattleArena.validate(arena).is_empty():
		return false
	var bounds := Rect2(0, 0, float(arena.ground.width), float(arena.ground.height))
	if not _configure_native_stage("res://scenes/environment_workshop/green_shade_battle.tscn", bounds, "builtin-rootbound-glade"):
		return false
	var stage := _terrain_root.get_node("RootboundGlade") as Node3D
	stage.scale = Vector3(bounds.size.x / 960.0, 1.0, bounds.size.y / 1152.0)
	# The working field's sample blocker is not authoritative for saved battles.
	# Draw the session's actual blockers instead; leave simulation/replay untouched.
	var landmarks := stage.get_node_or_null("Landmarks")
	if landmarks != null:
		landmarks.free()
	arena_manifest = arena.duplicate(true)
	_build_geometry_overlay()
	set_debug_group_visible("BattleObstacles", true)
	return true


func configure_home_forest(arena: Dictionary) -> bool:
	clear_battle()
	if not BattleArena.validate(arena).is_empty():
		return false
	var bounds := Rect2(0, 0, float(arena.ground.width), float(arena.ground.height))
	if not _configure_native_stage("res://scenes/environments/care_clearing.tscn", bounds, "builtin-battle-home-forest"):
		return false
	# Fit only scenery to the arena. Actors and authoritative ground units retain
	# their original scale; no care furniture or navigation data enters combat.
	var stage := _terrain_root.get_node("CareClearing") as Node3D
	stage.scale = Vector3(bounds.size.x / 1280.0, 1.0, bounds.size.y / 1536.0)
	var trees := stage.get_node_or_null("ForestParallax/OvalLayout/InteriorTrees")
	if trees != null:
		trees.queue_free()
	arena_manifest = arena.duplicate(true)
	_build_geometry_overlay()
	# The home scenery has no authored battle blockers; keep actual collision
	# footprints visible even when diagnostic overlays are disabled.
	set_debug_group_visible("BattleObstacles", true)
	return true


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


func configure_fighters(session: Dictionary, allow_current_art := false) -> bool:
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
		if library.is_empty() and allow_current_art and pin.is_empty():
			library = CompanionAssetLibrary.build(String(fighter.get("species_id", "")))
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
		var cues := BattleGroundCues3D.new()
		cues.name = (id + " battle cues").to_pascal_case()
		attach_world_node(cues)
		fighter_cues[id] = cues
		var effect := WorldVFX3D.new()
		effect.name = (id + " hit vfx").to_pascal_case()
		effect.configure(_hit_effect_texture(), _vfx_definition(7))
		effect.visible = false
		attach_world_node(effect)
		fighter_vfx[id] = effect
	_charge_overlay = BattleChargeOverlay.new()
	world_viewport.add_child(_charge_overlay)
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
	var source := CombatContent.normalize_snapshot(AssetResourceLibrary.read_json(folder.path_join("arena.json")))
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
		var cues: BattleGroundCues3D = fighter_cues[id]
		cues.debug_geometry = _debug_geometry
		cues.reduced_motion = reduced_motion
		cues.sample(actor, session.get("arena", arena_manifest), camera, session)
		_sample_body_accent(id, presentation, session, alpha)
		_sample_hit_vfx(id, ground, session, alpha)
	_sync_projectiles(session, alpha)
	frame_session(session, alpha, false)
	if _charge_overlay != null:
		_charge_overlay.sample(session, fighter_presentations, camera, Vector2(world_viewport.size), presentation_safe_rect)


func record_effect(fighter_id: String, effect_id: String, tick: int, duration_ticks: int, visual_scale: int = 1000) -> void:
	if fighter_vfx.has(fighter_id):
		_effect_records[fighter_id] = {"effect": effect_id, "start": tick, "duration": maxi(1, duration_ticks), "visual_scale": visual_scale}


func set_debug_geometry(enabled: bool) -> void:
	_debug_geometry = enabled
	set_debug_group_visible("BattleObstacles", enabled or environment_manifest.get("assetId", "") == "builtin-battle-home-forest")


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
		var corners: Array[Vector3] = presentation.visual_world_corners(point, true) if presentation != null else []
		if corners.is_empty():
			# Missing-art markers still need a visible, camera-framed envelope.
			world_points.append(ground_to_world(point) + Vector3(-0.5, 0, 0))
			world_points.append(ground_to_world(point) + Vector3(0.5, 1.8, 0))
		else:
			world_points.append_array(corners)
	for projectile: Dictionary in session.get("projectiles", []).slice(0, MAX_PROJECTILE_VFX):
		var previous := _fixed_ground(projectile.get("previous_pos", projectile.get("pos", [0, 0])))
		var current := _fixed_ground(projectile.get("pos", [0, 0]))
		var ground := previous.lerp(current, alpha)
		bounds = bounds.expand(ground)
		var center := _projectile_position(projectile, alpha)
		# Generated Pepper Breath cards are 24px at 1/32 scale and pulse to
		# 1.05x. This envelope deliberately covers the largest animation sample.
		var extent := 0.42 * float(projectile.get("visual_scale", 1000)) / 1000.0
		for x: float in [-extent, extent]:
			for y: float in [-extent, extent]:
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
		"groundTelegraphs": _cue_total("cue_count"),
		"chargeBars": _cue_total("charge_count"),
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
	if is_instance_valid(_charge_overlay):
		_charge_overlay.free()
	_charge_overlay = null
	for node: Node in fighter_presentations.values():
		if is_instance_valid(node):
			node.free()
	for node: Node in fighter_vfx.values():
		if is_instance_valid(node):
			node.free()
	for node: Node in projectile_vfx.values():
		if is_instance_valid(node):
			node.free()
	for node: Node in fighter_cues.values():
		if is_instance_valid(node):
			node.free()
	fighter_cues.clear()
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
			if not effect.configure(_projectile_texture(String(projectile.get("effect", "fire"))), _vfx_definition(6)) or not attach_world_node(effect):
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
		var visual_scale := float(projectile.get("visual_scale", 1000)) / 1000.0
		effect.scale = Vector3.ONE * visual_scale * (1.0 if reduced_motion else (0.9 + 0.15 * sin(phase * TAU)))
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
	var protective := String(record.effect) in ["perfect_guard", "shield_impact"]
	effect.texture = _protective_effect_texture(String(record.effect) == "perfect_guard") if protective else (_fire_effect_texture() if fiery else _hit_effect_texture())
	var target: CompanionPresentation3D = fighter_presentations.get(id)
	var impact := target.attachment_offset("impact") if target != null else Vector3(0, 1, 0)
	# Sit just in front of the body card so the impact is not hidden inside it;
	# retain depth testing against environmental occluders.
	effect.position = ground_to_world(ground) + impact + camera.global_basis.z * 0.15 + Vector3(0, 0 if reduced_motion else fraction * 0.6, 0)
	var scale_value := 1.2 if reduced_motion else 0.8 + sin(fraction * PI) * (1.5 if fiery else 0.65)
	effect.scale = Vector3.ONE * scale_value * (float(record.get("visual_scale", 1000)) / 1000.0)
	effect.modulate = Color(0.4, 1.0, 0.6, 1.0 - fraction) if String(record.effect) == "feed" else Color(1.0, 1.0 if fiery or protective else 0.55, 1.0 if fiery or protective else 0.18, 1.0 - fraction)


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


func _cue_total(property: String) -> int:
	var total := 0
	for cue: BattleGroundCues3D in fighter_cues.values():
		total += int(cue.get(property))
	return total


func _projectile_texture(effect: String) -> Texture2D:
	if effect == "bubble":
		if _bubble_texture == null:
			_bubble_texture = _pixel_effect_texture(Color("62bfe4"), Color("d5f8ff"), false)
		return _bubble_texture
	if effect in ["impact", "rush"]:
		return _hit_effect_texture()
	return _fire_effect_texture()


func _sample_body_accent(id: String, presentation: CompanionPresentation3D, session: Dictionary, alpha: float) -> void:
	presentation.sprite.modulate = Color.WHITE
	presentation.sprite.position.x = 0
	if not _effect_records.has(id):
		return
	var record: Dictionary = _effect_records[id]
	if not String(record.effect).begins_with("hit"):
		return
	var elapsed := float(int(session.tick) - int(record.start)) + alpha
	if elapsed >= 0 and elapsed < 7:
		presentation.sprite.modulate = Color(1.0, 0.65, 0.5).lerp(Color.WHITE, elapsed / 7.0)
		if not reduced_motion:
			presentation.sprite.position.x = sin(elapsed / 7.0 * PI) * 0.12


func _protective_effect_texture(perfect: bool) -> Texture2D:
	var cached := _perfect_guard_texture if perfect else _shield_texture
	if cached != null:
		return cached
	var image := Image.create(24, 24, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	for y: int in range(3, 23):
		var half_width := 9 if y < 12 else roundi(9.0 * float(22 - y) / 10.0)
		for x: int in range(12 - half_width, 13 + half_width):
			var border: bool = absi(x - 12) >= half_width - 1 or y <= 4
			image.set_pixel(x, y, Color("8aebff") if border else Color(0.15, 0.5, 0.8, 0.25))
	if perfect:
		for pixel: int in range(7, 18):
			image.set_pixel(12, pixel, Color("f1ffff"))
			image.set_pixel(pixel, 12, Color("f1ffff"))
	cached = ImageTexture.create_from_image(image)
	if perfect:
		_perfect_guard_texture = cached
	else:
		_shield_texture = cached
	return cached
