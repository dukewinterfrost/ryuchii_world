class_name CareHabitatView
extends SubViewportContainer

## A screen-space window onto the fixed habitat. Only GameState commits saves.
signal creature_cell_changed(cell: Vector2i)
signal route_completed(guided: bool)
signal waste_selected(slot: int)
signal camera_changed(zoom_multiplier: float, follow: bool)
signal facility_arrived(action: String)
signal draft_changed

const WORLD_SIZE := Vector2(HabitatRules.WIDTH * HabitatRules.CELL_SIZE, HabitatRules.HEIGHT * HabitatRules.CELL_SIZE)
const FALLBACK_WASTE_CELLS := [Vector2i(8, 20), Vector2i(20, 28), Vector2i(32, 20)]
var viewport := SubViewport.new()
var world := Node2D.new()
var ground := Ground.new()
var actors := Node2D.new()
var camera := Camera2D.new()
var avatar := CompanionAvatar.new()
var effects := CompanionEffects.new()
var environment_3d := EnvironmentView3D.new()
var avatar_3d: CompanionPresentation3D
var care_visuals_3d: Node3D
var habitat_manifest: Dictionary = {}
var region_id := HabitatRules.DEFAULT_REGION
var using_3d := false
var presentation_notice := ""
var layout: Dictionary = {}
var draft: Dictionary = {}
var editing := false
var _before_edit_zoom := 1.0
var _flame_frame := -1
var _facility_action := ""
var selected_id := ""
var zoom_multiplier := 1.0
var follow := true
var reduced_motion := false
var _poops: Dictionary = {}
var _decor: Dictionary = {}
var _path: Array[Vector2i] = []
var _guided := false
var _route_is_potty := false
var _roam_wait := 2.0
var _rng := RandomNumberGenerator.new()
var _dragging := false
var _drag_start := Vector2.ZERO
var _drag_previous := Vector2.ZERO
var _drag_moved := false
var _touches: Dictionary = {}
var _focused := true
var _acknowledged_cell := Vector2i(20, 24)
var _camera_save_delay := -1.0
var _care_pause := 0.0
var sleeping := false
var _manual_pan_ground := Vector2.ZERO
var _camera_initialized := false
var _care_textures_3d: Dictionary = {}
var _decor_3d_signature := ""
var _waste_3d_signature := ""
var _effects_viewport_3d: SubViewport
var _effects_source_3d: CompanionEffects
var _effects_card_3d: Sprite3D


func _ready() -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	viewport.transparent_bg = false
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.handle_input_locally = false
	add_child(viewport)
	viewport.add_child(world)
	world.add_child(ground)
	actors.y_sort_enabled = true
	world.add_child(actors)
	actors.add_child(avatar)
	avatar.roaming_enabled = false
	avatar.add_child(effects)
	world.add_child(camera)
	environment_3d.name = "EnvironmentView3D"
	environment_3d.set_anchors_preset(Control.PRESET_FULL_RECT)
	environment_3d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	environment_3d.hide()
	add_child(environment_3d)
	camera.position = WORLD_SIZE * 0.5
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 3.5
	gui_input.connect(_on_field_input)
	resized.connect(_fit_camera)
	_rng.randomize()
	_fit_camera()


func configure_region(package: Dictionary) -> bool:
	_camera_initialized = false
	# A region boundary invalidates every transient route and presentation node.
	# The incoming snapshot is the only source used to hydrate the new avatar and
	# camera state after this reset.
	environment_3d.unload_environment()
	_reset_region_state()
	region_id = HabitatRules.resolve_region_alias(String(package.get("region_id", HabitatRules.DEFAULT_REGION)))
	habitat_manifest = (package.get("habitat", HabitatAssetLibrary.fallback_manifest(region_id)) as Dictionary).duplicate(true)
	var spawn: Array = habitat_manifest.get("spawn", [20, 24])
	_acknowledged_cell = Vector2i(int(spawn[0]), int(spawn[1]))
	avatar.position = cell_center(_acknowledged_cell)
	presentation_notice = String(package.get("notice", ""))
	using_3d = false
	if String(package.get("mode", "fallback-2d")).ends_with("-3d") and package.get("environment_package") is Dictionary:
		using_3d = environment_3d.configure_package(package.environment_package)
		if using_3d:
			using_3d = environment_3d.set_static_placements(habitat_manifest.get("staticPlacements", []), "habitat")
	elif region_id == HabitatRules.DEFAULT_REGION and String(package.get("mode", "")) == "fallback-2d":
		using_3d = environment_3d.configure_care_clearing()
		if using_3d:
			presentation_notice = "Camera-facing care clearing · original native scenery. Regional art packages remain separate."
	if using_3d:
		avatar_3d = CompanionPresentation3D.new()
		avatar_3d.name = "CompanionPresentation3D"
		using_3d = environment_3d.attach_world_node(avatar_3d)
		if using_3d:
			avatar_3d.sprite.position.y = 0.035
	if using_3d:
		care_visuals_3d = Node3D.new()
		care_visuals_3d.name = "HomeCarePresentations"
		using_3d = environment_3d.attach_world_node(care_visuals_3d)
		if using_3d:
			_build_care_effects_3d()
	if not using_3d:
		environment_3d.unload_environment()
		avatar_3d = null
		care_visuals_3d = null
		EnvironmentAssetLibrary.clear_active()
	environment_3d.visible = using_3d
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED if using_3d else SubViewport.UPDATE_ALWAYS
	_sync_3d_decor(layout)
	_fit_camera()
	return using_3d


func update_snapshot(snapshot: Dictionary) -> void:
	var first_snapshot := not _camera_initialized
	var saved_camera_changed: bool = first_snapshot or layout.get("camera", {}) != snapshot.habitat.camera
	layout = (snapshot.habitat as Dictionary).duplicate(true)
	if using_3d and environment_3d.environment_manifest.get("assetId") == "builtin-care-clearing":
		habitat_manifest = preload("res://scripts/environment/native_care_scenery.gd").resolve(layout, habitat_manifest)
		environment_3d.sync_native_care_trees(habitat_manifest.get("nativeTrees", []))
		environment_3d.suppress_built_scenery(layout)
	# Durable state always wins over an in-flight presentation. This also repairs
	# rejected movement commits without leaving the 2D/3D avatars divergent.
	var incoming_cell := Vector2i(int(layout.creature_cell[0]), int(layout.creature_cell[1]))
	if first_snapshot or incoming_cell != _acknowledged_cell:
		avatar.position = cell_center(incoming_cell)
	_acknowledged_cell = incoming_cell
	if saved_camera_changed:
		zoom_multiplier = float(layout.camera.zoom)
		follow = bool(layout.camera.follow)
	avatar.configure(String(snapshot.identity.species_id))
	var was_sleeping := sleeping
	sleeping = bool(snapshot.care.status.sleeping)
	if sleeping and not was_sleeping:
		stop_route()
		play_loop("idle")
	set_meta("species_id", String(snapshot.identity.species_id))
	environment_3d.set_reduced_motion(reduced_motion)
	if using_3d and is_instance_valid(avatar_3d):
		if avatar_3d.species_id != String(snapshot.identity.species_id):
			avatar_3d.configure(String(snapshot.identity.species_id))
		avatar_3d.set_ground_position(avatar.position)
		if first_snapshot:
			environment_3d.set_home_follow(avatar.position, true)
			environment_3d.set_home_zoom_multiplier(zoom_multiplier, true)
			if not follow:
				environment_3d.set_home_manual_pan(Vector2.ZERO, true)
		elif saved_camera_changed:
			set_follow(follow, false)
			environment_3d.set_home_zoom_multiplier(zoom_multiplier, reduced_motion)
		elif follow:
			environment_3d.update_home_target(avatar.position, reduced_motion)
	elif follow:
		camera.position = (WORLD_SIZE * 0.5).lerp(avatar.position, minf(zoom_multiplier, 1.0))
	_camera_initialized = true
	camera.position_smoothing_enabled = not reduced_motion
	avatar.scale = Vector2.ONE * 0.85
	ground.theme = String(layout.theme)
	if not editing:
		_sync_decor(layout)
	var waste_positions := _waste_positions()
	for slot: int in snapshot.care.poop_slots.size():
		if bool(snapshot.care.poop_slots[slot]) and not _poops.has(slot):
			var poop := PoopVisual.new()
			poop.poop_index = slot
			poop.position = waste_positions[slot]
			poop.input_pickable = false
			actors.add_child(poop)
			_poops[slot] = poop
		elif not bool(snapshot.care.poop_slots[slot]) and _poops.has(slot):
			_poops[slot].queue_free()
			_poops.erase(slot)
	for poop: PoopVisual in _poops.values():
		poop.set_process(not reduced_motion)
	ground.queue_redraw()
	_sync_3d_decor(layout)
	_sync_3d_waste(snapshot.care.poop_slots)
	if using_3d and is_instance_valid(care_visuals_3d):
		for water: MeshInstance3D in care_visuals_3d.find_children("RecessedWater", "MeshInstance3D", true, false):
			var material := water.get_active_material(0) as ShaderMaterial
			if material != null: material.set_shader_parameter("reduced_motion", reduced_motion)
	_fit_camera()


func _process(delta: float) -> void:
	var frame := 0 if reduced_motion else int(Time.get_ticks_msec() / 125) % 4
	if frame != _flame_frame:
		_flame_frame = frame
		if using_3d and is_instance_valid(care_visuals_3d):
			var group := care_visuals_3d.get_node_or_null("HomeDecor")
			if group != null:
				for card: Node in group.find_children("*", "Sprite3D", true, false):
					if card is Sprite3D and card.get_meta("enclosure_flame", false): card.frame = frame
		elif not using_3d:
			for visual: Node2D in _decor.values():
				if visual.item.item_id == "campfire":
					visual.flame_frame = frame
					visual.queue_redraw()
	_sync_care_effects_3d()
	if _camera_save_delay >= 0:
		_camera_save_delay -= delta
		if _camera_save_delay < 0:
			camera_changed.emit(zoom_multiplier, follow)
	if layout.is_empty() or not _focused:
		return
	_care_pause = maxf(0.0, _care_pause - delta)
	if sleeping or editing or avatar.is_care_action_playing() or _care_pause > 0.0:
		return
	if not _path.is_empty():
		var destination := cell_center(_path[0])
		var direction := avatar.position.direction_to(destination)
		avatar.face_care_direction(direction)
		avatar.play_loop("move")
		if using_3d and is_instance_valid(avatar_3d):
			avatar_3d.set_facing_from_motion(direction)
			avatar_3d.play_loop("move")
		avatar.position = avatar.position.move_toward(destination, (110.0 if _route_is_potty else 42.0) * minf(delta, 0.1))
		if avatar.position.distance_to(destination) < 0.1:
			var arrived: Vector2i = _path.pop_front()
			_acknowledged_cell = arrived
			creature_cell_changed.emit(arrived)
			if _path.is_empty():
				avatar.play_loop("idle")
				if using_3d and is_instance_valid(avatar_3d): avatar_3d.play_loop("idle")
				_roam_wait = _rng.randf_range(2.0, 5.0)
				if not _facility_action.is_empty():
					var action := _facility_action
					_facility_action = ""
					facility_arrived.emit(action)
				if _route_is_potty:
					var was_guided := _guided
					_route_is_potty = false
					_guided = false
					route_completed.emit(was_guided)
	else:
		_roam_wait -= delta
		if _roam_wait <= 0.0:
			var dimensions := HabitatRules.grid_size(habitat_manifest)
			var goal := Vector2i(_rng.randi_range(2, dimensions.x - 3), _rng.randi_range(3, dimensions.y - 3))
			_path = HabitatRules.path_between_cells(layout, creature_cell(), goal, habitat_manifest)
			if not _path.is_empty():
				_path.pop_front()
			_roam_wait = 2.0
	if using_3d and is_instance_valid(avatar_3d):
		avatar_3d.set_ground_position(avatar.position)
		environment_3d.update_home_target(avatar.position, reduced_motion)
	if follow and not using_3d:
		camera.position = (WORLD_SIZE * 0.5).lerp(avatar.position, minf(zoom_multiplier, 1.0))
	_clamp_camera()


func creature_cell() -> Vector2i:
	return _acknowledged_cell


static func cell_center(cell: Vector2i) -> Vector2:
	return Vector2(cell) * 32.0 + Vector2(16, 16)


func begin_route(path: Array, guided: bool) -> void:
	_facility_action = ""
	_path.clear()
	for cell: Vector2i in path:
		_path.append(cell)
	_guided = guided
	_route_is_potty = true
	if _path.is_empty():
		_route_is_potty = false


func begin_facility_route(path: Array, action: String) -> void:
	stop_route()
	for cell: Vector2i in path: _path.append(cell)
	_facility_action = action if not _path.is_empty() else ""


func stop_route() -> void:
	_facility_action = ""
	_path.clear()
	avatar.position = cell_center(_acknowledged_cell)
	_roam_wait = 3.0
	_route_is_potty = false
	_guided = false
	avatar.play_loop("idle")
	if using_3d and is_instance_valid(avatar_3d):
		avatar_3d.set_ground_position(avatar.position)
		avatar_3d.play_loop("idle")


func play_action(action: String) -> void:
	avatar.play_action(action)
	if using_3d and is_instance_valid(avatar_3d):
		avatar_3d.play_action(action)


func play_loop(action: String) -> void:
	avatar.play_loop(action)
	if using_3d and is_instance_valid(avatar_3d):
		avatar_3d.play_loop(action)


func set_zoom(value: float) -> void:
	zoom_multiplier = clampf(value, 0.0, 2.0)
	if using_3d:
		environment_3d.set_home_zoom_multiplier(zoom_multiplier, reduced_motion)
	_fit_camera()
	_camera_save_delay = 0.35


func set_follow(value: bool, notify := true) -> void:
	follow = value
	if follow:
		camera.position = avatar.position
		_manual_pan_ground = Vector2.ZERO
		if using_3d: environment_3d.set_home_follow(avatar.position, reduced_motion)
	elif using_3d:
		# Toggle-off is itself the transition to manual mode; the player should
		# not have to drag once before camera updates stop following the avatar.
		environment_3d.set_home_manual_pan(Vector2.ZERO if environment_3d.camera_mode() != EnvironmentView3D.CAMERA_MODE_HOME_MANUAL else environment_3d._manual_pan_ground, true)
	elif not follow:
		camera.position = camera.get_screen_center_position()
		camera.reset_smoothing()
	_clamp_camera()
	if notify:
		camera_changed.emit(zoom_multiplier, follow)


func _fit_camera() -> void:
	if size.x < 1 or size.y < 1:
		return
	var fit := minf(size.x / WORLD_SIZE.x, size.y / WORLD_SIZE.y)
	camera.zoom = Vector2.ONE * fit * (1.0 + 4.0 * zoom_multiplier)
	if is_zero_approx(zoom_multiplier):
		camera.position = WORLD_SIZE * 0.5
	_clamp_camera()


func _clamp_camera() -> void:
	camera.position = camera.position.clamp(Vector2.ZERO, WORLD_SIZE)
	camera.force_update_scroll()


func _world_position(local: Vector2) -> Vector2:
	return viewport.canvas_transform.affine_inverse() * local


func project_touch_to_ground(local: Vector2) -> Variant:
	if using_3d:
		return environment_3d.screen_to_ground(local)
	var point := _world_position(local)
	return point if Rect2(Vector2.ZERO, WORLD_SIZE).has_point(point) else null


func project_touch_to_cell(local: Vector2) -> Variant:
	var ground_position: Variant = project_touch_to_ground(local)
	if ground_position == null:
		return null
	var cell := Vector2i((ground_position as Vector2) / float(HabitatRules.CELL_SIZE))
	return cell if HabitatRules.inside(cell, HabitatRules.grid_size(habitat_manifest)) else null


func _on_field_input(event: InputEvent) -> void:
	if event is InputEventMagnifyGesture:
		set_zoom(zoom_multiplier + (event.factor - 1.0) * maxf(zoom_multiplier, 0.5))
		accept_event()
	elif event is InputEventMouseButton:
		if event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			set_zoom(zoom_multiplier + (0.1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -0.1))
			accept_event()
		elif event.button_index == MOUSE_BUTTON_LEFT:
			_pointer(event.position, event.pressed)
	elif event is InputEventMouseMotion and _dragging:
		_motion(event.position)
	elif event is InputEventScreenTouch:
		if event.pressed:
			_touches[event.index] = event.position
		else:
			_touches.erase(event.index)
		if _touches.size() <= 1:
			_pointer(event.position, event.pressed)
		else:
			_dragging = false
	elif event is InputEventScreenDrag:
		if _touches.size() == 2:
			var old_points: Array = _touches.values()
			var old_distance: float = old_points[0].distance_to(old_points[1])
			_touches[event.index] = event.position
			var points: Array = _touches.values()
			if old_distance > 0:
				set_zoom(zoom_multiplier + (points[0].distance_to(points[1]) / old_distance - 1.0) * maxf(zoom_multiplier, 0.5))
			accept_event()
		elif _dragging:
			_touches[event.index] = event.position
			_motion(event.position)
	elif event is InputEventKey and event.pressed and not event.echo and editing:
		var step := Vector2i.ZERO
		match event.keycode:
			KEY_LEFT: step = Vector2i.LEFT
			KEY_RIGHT: step = Vector2i.RIGHT
			KEY_UP: step = Vector2i.UP
			KEY_DOWN: step = Vector2i.DOWN
			KEY_R: rotate_selected()
			KEY_DELETE, KEY_BACKSPACE: remove_selected()
		if step != Vector2i.ZERO:
			nudge_selected(step)
		accept_event()


func _pointer(point: Vector2, pressed: bool) -> void:
	if pressed:
		grab_focus()
		_dragging = true
		_drag_start = point
		_drag_previous = point
		_drag_moved = false
		if editing:
			var projected: Variant = project_touch_to_cell(point)
			if projected == null:
				return
			var cell: Vector2i = projected
			for item: Dictionary in draft.items:
				if cell in HabitatRules.footprint(item):
					selected_id = item.instance_id
					_refresh_draft()
					break
	else:
		if _dragging and not _drag_moved and not editing:
			var projected: Variant = project_touch_to_ground(point)
			if projected == null:
				_dragging = false
				return
			for slot: int in _poops:
				# Minimum 44 screen-pixel touch target even when zoomed out.
				var hit := (projected as Vector2).distance_to(_waste_positions()[slot]) < maxf(28.0, 22.0 / camera.zoom.x)
				if using_3d:
					var waste_screen := environment_3d.camera.unproject_position(EnvironmentView3D.ground_to_world(_waste_positions()[slot]))
					hit = point.distance_to(waste_screen) <= 22.0
				if hit:
					waste_selected.emit(slot)
		_dragging = false
		if not editing and _drag_moved:
			camera_changed.emit(zoom_multiplier, follow)
	accept_event()


func _motion(point: Vector2) -> void:
	if point.distance_to(_drag_start) > 4.0:
		_drag_moved = true
	if editing and not selected_id.is_empty():
		var projected: Variant = project_touch_to_cell(point)
		if projected == null:
			return
		var cell: Vector2i = projected
		var dimensions := HabitatRules.grid_size(habitat_manifest)
		for item: Dictionary in draft.items:
			if item.instance_id == selected_id:
				item.x = clampi(cell.x, 0, dimensions.x - 1)
				item.y = clampi(cell.y, 0, dimensions.y - 1)
				_refresh_draft()
	elif not editing:
		if not _drag_moved:
			return
		if follow:
			set_follow(false)
		if using_3d:
			environment_3d.pan_home_by_screen(_drag_previous, point)
			_manual_pan_ground = environment_3d._manual_pan_ground
		else:
			if not is_zero_approx(zoom_multiplier):
				camera.position -= (point - _drag_previous) / camera.zoom
			camera.reset_smoothing()
			_clamp_camera()
	_drag_previous = point
	accept_event()


func begin_edit() -> void:
	stop_route()
	_before_edit_zoom = zoom_multiplier
	zoom_multiplier = minf(zoom_multiplier, 0.65)
	if using_3d: environment_3d.set_home_zoom_multiplier(zoom_multiplier, true)
	_fit_camera()
	editing = true
	draft = layout.duplicate(true)
	draft.creature_cell = [creature_cell().x, creature_cell().y]
	selected_id = ""
	_refresh_draft()


func end_edit() -> void:
	zoom_multiplier = _before_edit_zoom
	if using_3d: environment_3d.set_home_zoom_multiplier(zoom_multiplier, true)
	_fit_camera()
	editing = false
	draft.clear()
	selected_id = ""
	ground.editing = false
	if using_3d:
		environment_3d.set_debug_group_visible("CareGrid", false)
		environment_3d.set_debug_group_visible("CareSelection", false)
		environment_3d.set_debug_group_visible("CareEntrances", false)
	_sync_decor(layout)
	_sync_3d_decor(layout)
	ground.queue_redraw()


func place_item(item_id: String) -> void:
	if not editing:
		return
	selected_id = "decor-%s-%d" % [item_id, Time.get_ticks_usec()]
	var focus := avatar.position + _manual_pan_ground if using_3d else camera.position
	var cell := Vector2i(focus / 32.0) + Vector2i(2, 1)
	var dimensions := HabitatRules.grid_size(habitat_manifest)
	var footprint: Array = GameDefinitions.DECOR[item_id].size
	draft.items.append({"instance_id": selected_id, "item_id": item_id, "x": clampi(cell.x, 0, dimensions.x - int(footprint[0])), "y": clampi(cell.y, 0, dimensions.y - int(footprint[1])), "rotation": 0})
	_refresh_draft()


func rotate_selected() -> void:
	for item: Dictionary in draft.get("items", []):
		if item.instance_id == selected_id:
			item.rotation = (int(item.rotation) + 1) % 4
	_refresh_draft()


func nudge_selected(step: Vector2i) -> void:
	var dimensions := HabitatRules.grid_size(habitat_manifest)
	for item: Dictionary in draft.get("items", []):
		if item.instance_id == selected_id:
			item.x = clampi(int(item.x) + step.x, 0, dimensions.x - 1)
			item.y = clampi(int(item.y) + step.y, 0, dimensions.y - 1)
	_refresh_draft()


func remove_selected() -> void:
	for index: int in draft.get("items", []).size():
		if draft.items[index].instance_id == selected_id:
			draft.items.remove_at(index)
			break
	selected_id = ""
	_refresh_draft()


func draft_validity() -> Dictionary:
	return HabitatRules.validate_layout(draft, creature_cell(), EnclosureRules.placement_manifest(draft, habitat_manifest))


func _refresh_draft() -> void:
	ground.editing = true
	ground.layout = draft
	ground.selected_id = selected_id
	ground.valid = bool(draft_validity().ok)
	var game := get_node_or_null("/root/GameState")
	if game != null and not game.state.is_empty(): ground.valid = ground.valid and bool(game.quote_habitat_layout(draft).ok)
	_sync_decor(draft)
	_sync_3d_decor(draft)
	if using_3d:
		var lines: Array = []
		for x: int in HabitatRules.WIDTH + 1:
			lines.append([x * 32, 0, 1, WORLD_SIZE.y])
		for y: int in HabitatRules.HEIGHT + 1:
			lines.append([0, y * 32, WORLD_SIZE.x, 1])
		environment_3d.set_debug_rectangles("CareGrid", lines, Color(0.95, 0.98, 0.79, 0.48))
		var selection: Array = []
		var entrances: Array = []
		for item: Dictionary in draft.get("items", []):
			if GameDefinitions.DECOR[item.item_id].has("entrance"):
				var entry := HabitatRules.facility_entrance(item)
				entrances.append([entry.x * 32 + 6, entry.y * 32 + 6, 20, 20])
			if String(item.instance_id) == selected_id:
				for cell: Vector2i in HabitatRules.footprint(item):
					selection.append([cell.x * 32 + 1, cell.y * 32 + 1, 30, 30])
		environment_3d.set_debug_rectangles("CareEntrances", entrances, Color(1, 0.85, 0.35, 0.8))
		environment_3d.set_debug_rectangles("CareSelection", selection, Color(0.45, 0.93, 0.60, 0.44) if ground.valid else Color(1.0, 0.2, 0.25, 0.45))
	ground.queue_redraw()
	draft_changed.emit()


func _build_care_effects_3d() -> void:
	# Reuse the existing effect drawings and clock. Only their presentation moves
	# into a depth-tested camera-facing card; care outcomes remain unchanged.
	_effects_viewport_3d = SubViewport.new()
	_effects_viewport_3d.name = "CareEffectTexture"
	_effects_viewport_3d.size = Vector2i(256, 256)
	_effects_viewport_3d.transparent_bg = true
	_effects_viewport_3d.world_2d = World2D.new()
	_effects_viewport_3d.render_target_update_mode = SubViewport.UPDATE_DISABLED
	avatar_3d.add_child(_effects_viewport_3d)
	_effects_source_3d = CompanionEffects.new()
	_effects_source_3d.position = Vector2(128, 192)
	_effects_viewport_3d.add_child(_effects_source_3d)
	_effects_card_3d = Sprite3D.new()
	_effects_card_3d.name = "CameraFacingCareEffects"
	_effects_card_3d.texture = _effects_viewport_3d.get_texture()
	_effects_card_3d.pixel_size = 1.0 / 32.0
	_effects_card_3d.offset = Vector2(0, 112)
	_effects_card_3d.alpha_cut = SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS
	_effects_card_3d.render_priority = 8
	ScreenAlignedSprite.apply(_effects_card_3d)
	_effects_card_3d.hide()
	avatar_3d.add_child(_effects_card_3d)


func _sync_care_effects_3d() -> void:
	if not using_3d or not is_instance_valid(_effects_card_3d):
		return
	var active := not effects.effect_id.is_empty()
	_effects_card_3d.visible = active
	_effects_viewport_3d.render_target_update_mode = SubViewport.UPDATE_ALWAYS if active else SubViewport.UPDATE_DISABLED
	_effects_source_3d.reduced_motion = reduced_motion
	_effects_source_3d.sample_effect(effects.effect_id, effects.progress)


func _sync_decor(source: Dictionary) -> void:
	var seen := {}
	for item: Dictionary in source.items:
		seen[item.instance_id] = true
		if not _decor.has(item.instance_id):
			var visual := Decor.new()
			actors.add_child(visual)
			_decor[item.instance_id] = visual
		_decor[item.instance_id].configure(item)
	for id: String in _decor.keys():
		if not seen.has(id):
			_decor[id].queue_free()
			_decor.erase(id)


func _sync_3d_decor(source: Dictionary) -> void:
	if not using_3d or not is_instance_valid(care_visuals_3d):
		return
	var signature := JSON.stringify(source.get("items", []))
	if signature == _decor_3d_signature and care_visuals_3d.has_node("HomeDecor"):
		return
	_decor_3d_signature = signature
	var group := _replace_3d_group("HomeDecor")
	for item: Dictionary in source.get("items", []):
		var cells := HabitatRules.footprint(item)
		if cells.is_empty():
			continue
		var bounds := Rect2(Vector2(cells[0]) * 32.0, Vector2.ONE * 32.0)
		for cell: Vector2i in cells:
			bounds = bounds.merge(Rect2(Vector2(cell) * 32.0, Vector2.ONE * 32.0))
		var model := EnclosureModels.create(String(item.item_id), String(item.instance_id), int(item.rotation))
		model.position = EnvironmentView3D.ground_to_world(bounds.get_center())
		group.add_child(model)

	environment_3d.register_home_lighting(group)


func _sync_3d_waste(slots: Array) -> void:
	if not using_3d or not is_instance_valid(care_visuals_3d):
		return
	var signature := JSON.stringify([slots, HabitatRules.waste_anchors(habitat_manifest)])
	if signature == _waste_3d_signature and care_visuals_3d.has_node("HomeWaste"):
		return
	_waste_3d_signature = signature
	var group := _replace_3d_group("HomeWaste")
	var positions := _waste_positions()
	for slot: int in mini(slots.size(), positions.size()):
		if bool(slots[slot]):
			var center: Vector2 = positions[slot]
			group.add_child(_make_upright_card_3d("waste-%d" % slot, Rect2(center - Vector2(12, 12), Vector2(24, 24)), _care_texture_3d("waste")))

	environment_3d.register_home_lighting(group)


func _reset_region_state() -> void:
	_path.clear()
	_guided = false
	_route_is_potty = false
	_roam_wait = 3.0
	editing = false
	draft.clear()
	selected_id = ""
	layout.clear()
	_manual_pan_ground = Vector2.ZERO
	_decor_3d_signature = ""
	_waste_3d_signature = ""
	zoom_multiplier = 1.0
	follow = true
	camera.position = WORLD_SIZE * 0.5
	for node: Node in _poops.values():
		node.free()
	_poops.clear()
	for node: Node in _decor.values():
		node.free()
	_decor.clear()
	avatar_3d = null
	care_visuals_3d = null
	avatar.play_loop("idle")


func _replace_3d_group(group_name: String) -> Node3D:
	var previous := care_visuals_3d.get_node_or_null(group_name)
	if previous != null:
		previous.free()
	var group := Node3D.new()
	group.name = group_name
	care_visuals_3d.add_child(group)
	return group


func _make_upright_card_3d(node_name: String, ground_bounds: Rect2, texture: Texture2D) -> Sprite3D:
	var sprite := Sprite3D.new()
	sprite.name = "Care_%s" % node_name.sha256_text().left(12)
	sprite.set_meta("care_instance_id", node_name)
	sprite.texture = texture
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sprite.shaded = false
	ScreenAlignedSprite.apply(sprite)
	sprite.fixed_size = false
	sprite.no_depth_test = false
	sprite.double_sided = true
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	var texture_size := Vector2(texture.get_size())
	sprite.pixel_size = ground_bounds.size.x / maxf(1.0, texture_size.x) / 32.0
	sprite.position = EnvironmentView3D.ground_to_world(Vector2(ground_bounds.get_center().x, ground_bounds.end.y))
	# Pivot the texture at bottom-center, matching authored companion foot pivots.
	# The tiny lift avoids ground z-fighting without changing its gameplay root.
	sprite.offset = Vector2(0, texture_size.y * 0.5)
	sprite.position.y = 0.02
	sprite.rotation = Vector3.ZERO
	return sprite


func _make_ground_card_3d(node_name: String, ground_bounds: Rect2, texture: Texture2D) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = "Care_%s" % node_name.sha256_text().left(12)
	instance.set_meta("care_instance_id", node_name)
	var plane := PlaneMesh.new()
	plane.size = ground_bounds.size / 32.0
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	material.albedo_texture = texture
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	plane.material = material
	instance.mesh = plane
	instance.position = EnvironmentView3D.ground_to_world(ground_bounds.get_center()) + Vector3(0, 0.025, 0)
	return instance


func _care_texture_3d(kind: String) -> Texture2D:
	if kind in ["digi_potty", "campfire", "pond", "flame"]:
		return load("res://assets/enclosure/%s.png" % kind) as Texture2D
	if _care_textures_3d.has(kind):
		return _care_textures_3d[kind]
	var dimensions := {"digi_potty": Vector2i(32, 32), "rug": Vector2i(48, 32), "planter": Vector2i(16, 24), "waste": Vector2i(16, 16)}.get(kind, Vector2i(16, 16)) as Vector2i
	var image := Image.create(dimensions.x, dimensions.y, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	match kind:
		"digi_potty":
			_paint_pixels(image, Rect2i(3, 8, 26, 20), Color("c8e4d8"))
			_paint_pixels(image, Rect2i(7, 12, 18, 12), Color("ecf6e9"))
			_paint_pixels(image, Rect2i(11, 15, 10, 7), Color("527d73"))
		"rug":
			_paint_pixels(image, Rect2i(1, 1, 46, 30), Color("c5a86c"))
			_paint_pixels(image, Rect2i(5, 5, 38, 22), Color("487366"))
		"planter":
			_paint_pixels(image, Rect2i(3, 13, 10, 10), Color("9c6850"))
			_paint_pixels(image, Rect2i(2, 6, 7, 9), Color("426e43"))
			_paint_pixels(image, Rect2i(8, 2, 7, 13), Color("719a55"))
		"waste":
			_paint_pixels(image, Rect2i(3, 9, 10, 5), Color("4a2b16"))
			_paint_pixels(image, Rect2i(5, 5, 7, 6), Color("65401f"))
			_paint_pixels(image, Rect2i(7, 2, 4, 5), Color("7b542b"))
	var texture := ImageTexture.create_from_image(image)
	_care_textures_3d[kind] = texture
	return texture


static func _paint_pixels(image: Image, rect: Rect2i, color: Color) -> void:
	for y: int in range(rect.position.y, rect.end.y):
		for x: int in range(rect.position.x, rect.end.x):
			image.set_pixel(x, y, color)


func _waste_positions() -> Array[Vector2]:
	var cells := HabitatRules.waste_anchors(habitat_manifest)
	if cells.size() != 3:
		cells = FALLBACK_WASTE_CELLS.duplicate()
	var result: Array[Vector2] = []
	for cell: Vector2i in cells:
		result.append(cell_center(cell))
	return result


func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED]:
		_focused = false
	elif what in [NOTIFICATION_APPLICATION_FOCUS_IN, NOTIFICATION_APPLICATION_RESUMED]:
		_focused = true


class Ground extends Node2D:
	var theme := "verdant"
	var editing := false
	var layout: Dictionary = {}
	var selected_id := ""
	var valid := true
	var art: Texture2D = preload("res://assets/habitat/verdant-field.png")
	func _draw() -> void:
		draw_rect(Rect2(Vector2(-3000, -3000), Vector2(6640, 6768)), Color("24392e"))
		if theme == "verdant":
			draw_texture_rect(art, Rect2(Vector2.ZERO, WORLD_SIZE), false)
		else:
			draw_rect(Rect2(Vector2.ZERO, WORLD_SIZE), Color("83a18a"))
		if editing:
			for x: int in HabitatRules.WIDTH + 1:
				draw_line(Vector2(x * 32, 0), Vector2(x * 32, WORLD_SIZE.y), Color(1, 1, 0.9, 0.25), 1)
			for y: int in HabitatRules.HEIGHT + 1:
				draw_line(Vector2(0, y * 32), Vector2(WORLD_SIZE.x, y * 32), Color(1, 1, 0.9, 0.25), 1)
			for item: Dictionary in layout.get("items", []):
				var color := Color(0.35, 0.9, 0.65, 0.38) if valid else Color(1, 0.2, 0.25, 0.5)
				for cell: Vector2i in HabitatRules.footprint(item):
					draw_rect(Rect2(Vector2(cell) * 32, Vector2.ONE * 32), color, item.instance_id == selected_id, -1 if item.instance_id == selected_id else 2)
				if GameDefinitions.DECOR[item.item_id].has("entrance"):
					draw_circle(Vector2(HabitatRules.potty_entrance(item)) * 32 + Vector2(16, 16), 10, Color("ffe798"))


class Decor extends Node2D:
	const BUILDING_ART := {
		"digi_potty": preload("res://assets/enclosure/digi_potty.png"),
		"campfire": preload("res://assets/enclosure/campfire.png"),
		"pond": preload("res://assets/enclosure/pond.png"),
	}
	const FLAME_ART = preload("res://assets/enclosure/flame-loop.png")
	var flame_frame := 0
	var item: Dictionary = {}
	var footprint_size := Vector2.ZERO
	func configure(value: Dictionary) -> void:
		item = value.duplicate(true)
		var cells := HabitatRules.footprint(item)
		var far := Vector2i(int(item.x), int(item.y))
		for cell: Vector2i in cells:
			far.x = maxi(far.x, cell.x)
			far.y = maxi(far.y, cell.y)
		footprint_size = Vector2(far - Vector2i(int(item.x), int(item.y)) + Vector2i.ONE) * 32
		position = Vector2(int(item.x) * 32, (far.y + 1) * 32)
		z_index = -1 if item.item_id == "rug" else 0
		queue_redraw()
	func _draw() -> void:
		var center := Vector2(footprint_size.x * 0.5, -footprint_size.y * 0.5)
		if String(item.get("item_id", "")) in ["digi_potty", "campfire", "pond"]:
			var texture: Texture2D = BUILDING_ART[item.item_id]
			var height := footprint_size.x * texture.get_height() / float(texture.get_width())
			draw_texture_rect(texture, Rect2(Vector2(0, -height), Vector2(footprint_size.x, height)), false)
			if item.item_id == "campfire":
				var flame: Texture2D = FLAME_ART
				draw_texture_rect_region(flame, Rect2(Vector2(footprint_size.x * 0.25, -height * 0.70), Vector2.ONE * footprint_size.x * 0.5), Rect2(flame_frame * 64, 0, 64, 64))
			return
		match String(item.get("item_id", "")):
			"rug":
				draw_rect(Rect2(Vector2(3, -footprint_size.y + 3), footprint_size - Vector2(6, 6)), Color("c5a86c"))
				draw_rect(Rect2(Vector2(9, -footprint_size.y + 9), footprint_size - Vector2(18, 18)), Color("487366"), false, 3)
			"planter":
				draw_set_transform(center, 0, Vector2.ONE * footprint_size.x / 32.0)
				center = Vector2.ZERO
				draw_rect(Rect2(center + Vector2(-12, -4), Vector2(24, 20)), Color("9c6850"))
				draw_circle(center + Vector2(-6, -12), 10, Color("426e43"))
				draw_circle(center + Vector2(7, -20), 12, Color("719a55"))
			"digi_potty":
				draw_rect(Rect2(center + Vector2(-23, -30), Vector2(46, 43)), Color("c8e4d8"))
				draw_circle(center, 22, Color("ecf6e9"))
				draw_circle(center, 13, Color("527d73"))
				var entrance := Vector2(HabitatRules.potty_entrance(item)) * 32 + Vector2(16, 16) - position
				draw_line(center, center.lerp(entrance, 0.57), Color("efc760"), 5)
				draw_circle(center.lerp(entrance, 0.57), 4, Color("efc760"))
