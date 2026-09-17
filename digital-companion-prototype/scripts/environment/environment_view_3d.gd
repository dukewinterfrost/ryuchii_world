class_name EnvironmentView3D
extends SubViewportContainer

## Manifest-driven presentation bridge from deterministic 2D ground coordinates
## into a genuine Godot 3D world. Collision and navigation stay outside this view.

const GROUND_UNITS_PER_CELL := float(EnvironmentPresentationContract.PIXELS_PER_METER)
const PLANE_TILT_DEGREES := -EnvironmentPresentationContract.SPRITE_TILT_DEGREES
const CAMERA_MODE_HOME_FOLLOW := "home-follow"
const CAMERA_MODE_HOME_MANUAL := "home-manual"
const CAMERA_MODE_BATTLE_FRAME := "battle-frame"
const CAMERA_MODE_REVIEW := "review"

var environment_manifest: Dictionary = {}
var world_size_cells := Vector2i.ZERO
var reduced_motion := false
var world_viewport: SubViewport
var world_root: Node3D
var content_root: Node3D
var camera: Camera3D
var stack_roots: Array[Node3D] = []
var rendered_planes: Array[Sprite3D] = []

var _terrain_root: Node3D
var _ambient_root: Node3D
var _placement_root: Node3D
var _debug_root: Node3D
var _world_nodes_root: Node3D
var _textures: Dictionary = {}
var _plane_definitions: Dictionary = {}
var _stack_definitions: Dictionary = {}
var _footprints: Dictionary = {}
var _camera_focus_ground := Vector2.ZERO
var _camera_target_ground := Vector2.ZERO
var _camera_bounds := Rect2()
var _camera_pitch_degrees := 50.0
var _camera_ground_distance := 12.0
var _camera_target_ground_distance := 12.0
var _camera_smoothing_speed := 5.0
var _sprite_tilt_degrees := 8.0
var _dolly_min := 2.0
var _dolly_max := 60.0
var _review_viewpoint_active := false
var _ambient_origin_focus_ground := Vector2.ZERO
var _camera_mode := CAMERA_MODE_HOME_FOLLOW
var _home_ground_distance := 12.0
var _home_zoom_multiplier := 1.0
var battle_zoom_multiplier := 1.0
var _home_follow_ground := Vector2.ZERO
var _manual_pan_ground := Vector2.ZERO
var _battle_bounds := Rect2()
var _battle_world_points: Array[Vector3] = []
var _battle_focus_ground := Vector2.ZERO
var _placed_footprints: Array[Rect2] = []
var _frame_time_samples: Array[float] = []
var _last_load_error := ""
var day_night: HomeDayNightLighting
var _native_parallax: Node3D


func _ready() -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_PASS
	_ensure_world()
	resized.connect(_sync_viewport_size)
	_sync_viewport_size()
	set_process(true)


func _process(delta: float) -> void:
	if delta >= 0.0 and is_finite(delta):
		_frame_time_samples.append(delta * 1000.0)
		if _frame_time_samples.size() > 120:
			_frame_time_samples.pop_front()
	advance_camera(delta)


static func ground_to_world(ground_position: Vector2) -> Vector3:
	return Vector3(ground_position.x / GROUND_UNITS_PER_CELL, 0.0, ground_position.y / GROUND_UNITS_PER_CELL)


static func world_to_ground(world_position: Vector3) -> Vector2:
	return Vector2(world_position.x * GROUND_UNITS_PER_CELL, world_position.z * GROUND_UNITS_PER_CELL)


func configure_from_folder(folder: String) -> bool:
	unload_environment()
	var root := folder.trim_suffix("/")
	if root.is_empty():
		_last_load_error = "Environment folder is empty"
		return false
	var native_path := root.path_join("environment.tres")
	if ResourceLoader.exists(native_path):
		var native := ResourceLoader.load(native_path)
		if native != null and native.has_meta("environment_manifest") and native.has_meta("environment_textures"):
			var native_manifest: Variant = native.get_meta("environment_manifest")
			var native_textures: Variant = native.get_meta("environment_textures")
			if native_manifest is Dictionary and native_textures is Dictionary:
				return configure(native_manifest, root, native_textures)
	var manifest := AssetResourceLibrary.read_json(root.path_join("environment.json"))
	return not manifest.is_empty() and configure(manifest, root)


func load_environment(folder_or_manifest_path: String) -> bool:
	if folder_or_manifest_path.ends_with(".json"):
		var manifest := AssetResourceLibrary.read_json(folder_or_manifest_path)
		if manifest.is_empty():
			unload_environment()
			_last_load_error = "Environment manifest could not be decoded"
			return false
		return configure(manifest, folder_or_manifest_path.get_base_dir())
	return configure_from_folder(folder_or_manifest_path)


func configure_package(package: Dictionary) -> bool:
	if package.is_empty() or not package.get("manifest") is Dictionary or not package.get("textures") is Dictionary:
		unload_environment()
		_last_load_error = "Environment package is incomplete"
		return false
	return configure(package.manifest, String(package.get("folder", "")), package.textures)


func configure_care_clearing() -> bool:
	## Original native scene, not a promoted biome asset or a pending fixture.
	## It presents the existing fallback habitat without changing its ground data.
	var configured := _configure_native_stage("res://scenes/environments/care_clearing.tscn",
		Rect2(0, 0, 1280, 1536), "builtin-care-clearing")
	if configured:
		_dolly_max = 40.0
		var stage := _terrain_root.get_node("CareClearing")
		if stage.has_meta("overview_bounds"):
			environment_manifest["overviewBounds"] = stage.get_meta("overview_bounds")
		set_camera_focus(Vector2(656, 784), true)
		day_night = HomeDayNightLighting.new()
		day_night.name = "HomeDayNightLighting"
		world_root.add_child(day_night)
		var world := world_root.get_node("WorldEnvironment") as WorldEnvironment
		world.environment = world.environment.duplicate(true)
		day_night.configure(_terrain_root.get_node("CareClearing"), world.environment)
	return configured


func _configure_native_stage(scene_path: String, bounds: Rect2, asset_id: String) -> bool:
	_ensure_world()
	unload_environment()
	var packed := load(scene_path) as PackedScene
	if packed == null:
		return false
	var stage := packed.instantiate() as Node3D
	_terrain_root.add_child(stage)
	_native_parallax = stage.get_node_or_null("ForestParallax")
	if _native_parallax != null:
		_native_parallax.externally_driven = true
	# Saved workshop actors are composition guides, not simulation fighters.
	var guides := stage.get_node_or_null("Characters")
	if guides != null:
		guides.free()
	var rig := stage.get_node("CameraRig") as Node3D
	var preview := rig.get_node("Camera3D") as Camera3D
	_camera_pitch_degrees = clampf(-preview.global_rotation_degrees.x, 25.0, 60.0)
	_home_ground_distance = preview.position.length() * cos(deg_to_rad(_camera_pitch_degrees))
	_camera_ground_distance = _home_ground_distance
	_camera_target_ground_distance = _home_ground_distance
	_dolly_min = 5.0
	_dolly_max = 60.0
	_camera_smoothing_speed = 5.0
	_camera_bounds = bounds
	world_size_cells = Vector2i(roundi(bounds.size.x / 32.0), roundi(bounds.size.y / 32.0))
	camera.fov = preview.fov
	camera.keep_aspect = Camera3D.KEEP_WIDTH
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.near = preview.near
	camera.far = preview.far
	preview.current = false
	camera.make_current()
	var authored_world := stage.get_node("WorldEnvironment") as WorldEnvironment
	(world_root.get_node("WorldEnvironment") as WorldEnvironment).environment = authored_world.environment
	authored_world.environment = null
	environment_manifest = {"assetId": asset_id, "revision": "2026-09-15.001", "builtin": true, "nativeScene": scene_path}
	_camera_focus_ground = bounds.get_center()
	_camera_target_ground = _camera_focus_ground
	_home_follow_ground = _camera_focus_ground
	_ambient_origin_focus_ground = _camera_focus_ground
	_camera_mode = CAMERA_MODE_HOME_FOLLOW
	_review_viewpoint_active = false
	_apply_camera_transform()
	return true


func configure(manifest: Dictionary, payload_root: String, embedded_textures: Dictionary = {}) -> bool:
	_ensure_world()
	# Switching is atomic from the caller's perspective: the previous package is
	# unloaded before any new bytes are decoded, and failures leave an empty view.
	unload_environment()
	if not _manifest_shape_within_bounds(manifest):
		_last_load_error = "Environment manifest exceeds runtime bounds"
		push_warning(_last_load_error)
		return false
	var loaded_textures := _resolve_textures(manifest, payload_root, embedded_textures)
	if loaded_textures.is_empty() or not _manifest_is_renderable(manifest, loaded_textures):
		_last_load_error = "Environment manifest is invalid or unrenderable"
		push_warning(_last_load_error)
		return false
	environment_manifest = manifest.duplicate(true)
	_textures = loaded_textures
	_plane_definitions.clear()
	_stack_definitions.clear()
	_footprints.clear()
	for definition: Dictionary in environment_manifest.spritePlanes:
		_plane_definitions[String(definition.id)] = definition
	for definition: Dictionary in environment_manifest.planeStacks:
		_stack_definitions[String(definition.id)] = definition
	for definition: Dictionary in environment_manifest.groundFootprints:
		_footprints[String(definition.id)] = definition
	var camera_profile: Dictionary = environment_manifest.camera
	_camera_bounds = _rect(camera_profile.movementBounds)
	world_size_cells = Vector2i(roundi(_camera_bounds.size.x / GROUND_UNITS_PER_CELL),
			roundi(_camera_bounds.size.y / GROUND_UNITS_PER_CELL))
	_camera_pitch_degrees = float(camera_profile.pitchDegrees)
	_camera_ground_distance = float(camera_profile.groundDistance)
	_camera_target_ground_distance = _camera_ground_distance
	_home_ground_distance = _camera_ground_distance
	_home_zoom_multiplier = 1.0
	_camera_smoothing_speed = float(camera_profile.smoothingSpeed)
	_sprite_tilt_degrees = float(camera_profile.spriteTiltDegrees)
	_dolly_min = float(camera_profile.dollyBounds[0])
	_dolly_max = float(camera_profile.dollyBounds[1])
	_configure_world_environment(environment_manifest)
	_configure_camera(camera_profile)
	_build_terrain(environment_manifest.terrainChunks)
	_build_ambient(environment_manifest.get("ambientPlanes", []))
	_camera_focus_ground = _camera_bounds.get_center()
	_camera_target_ground = _camera_focus_ground
	_ambient_origin_focus_ground = _camera_focus_ground
	_review_viewpoint_active = false
	_camera_mode = CAMERA_MODE_HOME_FOLLOW
	_home_follow_ground = _camera_focus_ground
	_manual_pan_ground = Vector2.ZERO
	_camera_target_ground_distance = _camera_ground_distance
	_apply_camera_transform()
	_camera_focus_ground = _clamp_ground(_camera_focus_ground)
	_camera_target_ground = _camera_focus_ground
	_apply_camera_transform()
	_last_load_error = ""
	return true


func unload_environment() -> void:
	if is_instance_valid(day_night):
		day_night.free()
	day_night = null
	battle_zoom_multiplier = 1.0
	_native_parallax = null
	if content_root != null:
		_clear_environment_content()
	environment_manifest.clear()
	_textures.clear()
	_plane_definitions.clear()
	_stack_definitions.clear()
	_footprints.clear()
	_placed_footprints.clear()
	stack_roots.clear()
	rendered_planes.clear()
	world_size_cells = Vector2i.ZERO
	_battle_bounds = Rect2()
	_battle_world_points.clear()
	_battle_focus_ground = Vector2.ZERO
	_camera_bounds = Rect2()
	_camera_mode = CAMERA_MODE_HOME_FOLLOW
	_manual_pan_ground = Vector2.ZERO
	_home_zoom_multiplier = 1.0
	_camera_target_ground_distance = _camera_ground_distance
	_frame_time_samples.clear()


func attach_world_node(node: Node3D) -> bool:
	_ensure_world()
	if _descendant_count(content_root) + 1 + _descendant_count(node) > EnvironmentPresentationContract.MAX_ACTIVE_NODES:
		push_warning("Environment active node limit reached")
		return false
	if node.get_parent() != null:
		node.reparent(_world_nodes_root)
	else:
		_world_nodes_root.add_child(node)
	register_home_lighting(node)
	return true


func register_home_lighting(node: Node) -> void:
	if is_instance_valid(day_night):
		day_night.register_branch(node)


func set_static_placements(placements: Array, placement_mode: String) -> bool:
	if placement_mode not in ["habitat", "arena"] or environment_manifest.is_empty():
		return false
	if placements.size() > (EnvironmentPresentationContract.MAX_HABITAT_PLACEMENTS if placement_mode == "habitat" else EnvironmentPresentationContract.MAX_ARENA_PLACEMENTS):
		return false
	# Environment v1 intentionally keeps every authored card parallel. Turning a
	# single Sprite3D stack around world Y can expose its edge and also makes the
	# presentation disagree with the unrotated authoritative ground footprint.
	# Directional/rotatable stacks require a future schema with separately
	# authored views and footprints; reject them instead of rendering a lie.
	for record: Variant in placements:
		if not record is Dictionary:
			return false
		var placement: Dictionary = record
		var rotation: Variant = placement.get("rotationQuarterTurns", 0) if placement_mode == "habitat" else placement.get("rotationDegrees", 0)
		if not _finite(rotation) or not is_zero_approx(float(rotation)):
			return false
		if not _stack_definitions.has(String(placement.get("planeStack", ""))):
			return false
		var position_value: Variant = placement.get("cell") if placement_mode == "habitat" else placement.get("groundPosition")
		if not _pair(position_value):
			return false
	var requested_nodes := placements.size()
	for record: Dictionary in placements:
		requested_nodes += (_stack_definitions[String(record.planeStack)].planes as Array).size()
	var nodes_without_existing_placements := _descendant_count(content_root) - _descendant_count(_placement_root)
	if nodes_without_existing_placements + requested_nodes > EnvironmentPresentationContract.MAX_ACTIVE_NODES:
		return false
	_clear_children(_placement_root)
	stack_roots.clear()
	rendered_planes.clear()
	_placed_footprints.clear()
	for record: Variant in placements:
		var placement: Dictionary = record
		var stack_id := String(placement.get("planeStack", ""))
		var root := Node3D.new()
		root.name = String(placement.get("id", stack_id)).to_pascal_case()
		if placement_mode == "habitat":
			var cell: Variant = placement.get("cell")
			root.position = ground_to_world(Vector2((float(cell[0]) + 0.5) * GROUND_UNITS_PER_CELL,
					(float(cell[1]) + 0.5) * GROUND_UNITS_PER_CELL))
		else:
			var ground_position: Variant = placement.get("groundPosition")
			root.position = ground_to_world(Vector2(float(ground_position[0]), float(ground_position[1])))
		_placement_root.add_child(root)
		stack_roots.append(root)
		var stack: Dictionary = _stack_definitions[stack_id]
		for plane_id: Variant in stack.planes:
			var sprite := _make_sprite(_plane_definitions[String(plane_id)], "localPosition")
			if sprite == null:
				return false
			root.add_child(sprite)
			rendered_planes.append(sprite)
		var footprint_id := String(stack.get("groundFootprint", ""))
		if _footprints.has(footprint_id):
			var local_rect := _rect(_footprints[footprint_id].rect)
			var origin_ground := world_to_ground(root.position)
			_placed_footprints.append(Rect2(origin_ground + local_rect.position, local_rect.size))
	return true


func placed_footprints() -> Array[Rect2]:
	return _placed_footprints.duplicate()


func build_depth_traversal_route(clearance_ground := 24.0) -> Array[Vector2]:
	if _placed_footprints.is_empty():
		var center := _camera_bounds.get_center()
		return [center + Vector2(0, -96), center + Vector2(0, 96)]
	var combined := _placed_footprints[0]
	for index: int in range(1, _placed_footprints.size()):
		combined = combined.merge(_placed_footprints[index])
	var margin := maxf(clearance_ground, 1.0)
	var behind := Vector2(combined.get_center().x, combined.position.y - margin)
	var front := Vector2(combined.get_center().x, combined.end.y + margin)
	var right := combined.end.x + margin
	var route: Array[Vector2] = [behind, Vector2(right, behind.y), Vector2(right, front.y), front]
	return route if route_segments_are_clear(route, margin * 0.25) else []


func route_segments_are_clear(route: Array[Vector2], footprint_padding := 0.0) -> bool:
	if route.size() < 2:
		return false
	for index: int in route.size() - 1:
		for footprint: Rect2 in _placed_footprints:
			if _segment_hits_rect(route[index], route[index + 1], footprint.grow(maxf(0.0, footprint_padding))):
				return false
	return true


func build_review_samples() -> bool:
	var placements: Array = []
	var stack_ids: Array = _stack_definitions.keys()
	stack_ids.sort()
	var center := _camera_bounds.get_center()
	for index: int in stack_ids.size():
		var offset := Vector2((index - (stack_ids.size() - 1) * 0.5) * 96.0, 0.0)
		placements.append({"id": "review.%d" % index, "planeStack": stack_ids[index],
			"groundPosition": [center.x + offset.x, center.y + offset.y], "rotationDegrees": 0})
	return set_static_placements(placements, "arena")


func set_review_viewpoint(viewpoint_id: String) -> bool:
	if camera == null:
		return false
	for record: Variant in environment_manifest.get("reviewViewpoints", []):
		if record is Dictionary and String(record.get("id", "")) == viewpoint_id:
			# Viewpoints are named evidence requests, not arbitrary camera poses.
			# The runtime derives all five from one fixed axis so cards never expose
			# edges through yaw/orbit drift.
			var center := _camera_bounds.get_center()
			_camera_focus_ground = center
			_camera_ground_distance = _home_ground_distance
			_camera_target_ground_distance = _camera_ground_distance
			if viewpoint_id == "left":
				_camera_focus_ground.x -= minf(32.0, _camera_bounds.size.x * 0.025)
			elif viewpoint_id == "right":
				_camera_focus_ground.x += minf(32.0, _camera_bounds.size.x * 0.025)
			elif viewpoint_id == "near":
				_camera_ground_distance = clampf(_home_ground_distance * 0.78, _dolly_min, _dolly_max)
			elif viewpoint_id == "far":
				_camera_ground_distance = clampf(_home_ground_distance * 1.32, _dolly_min, _dolly_max)
			_camera_target_ground = _camera_focus_ground
			_camera_mode = CAMERA_MODE_REVIEW
			_review_viewpoint_active = true
			_apply_camera_transform()
			return true
	return false


func clear_review_viewpoint() -> void:
	_review_viewpoint_active = false
	_camera_mode = CAMERA_MODE_HOME_FOLLOW
	_camera_ground_distance = _home_ground_distance
	_camera_target_ground_distance = _camera_ground_distance
	_apply_camera_transform()


func set_camera_focus(ground_position: Vector2, immediate := false) -> void:
	_review_viewpoint_active = false
	_camera_mode = CAMERA_MODE_HOME_FOLLOW
	_home_follow_ground = ground_position
	_manual_pan_ground = Vector2.ZERO
	_camera_ground_distance = _home_ground_distance
	_camera_target_ground_distance = _camera_ground_distance
	_camera_target_ground = _clamp_ground(ground_position)
	if immediate or reduced_motion:
		_camera_focus_ground = _camera_target_ground
		_apply_camera_transform()


func nudge_camera_ground(delta_ground: Vector2, immediate := false) -> void:
	set_home_manual_pan(_manual_pan_ground + delta_ground, immediate)


func set_home_follow(ground_position: Vector2, immediate := false) -> void:
	_home_follow_ground = ground_position
	_camera_mode = CAMERA_MODE_HOME_FOLLOW
	_review_viewpoint_active = false
	_manual_pan_ground = Vector2.ZERO
	_camera_target_ground_distance = _home_zoom_distance()
	_camera_target_ground = _home_focus_target()
	if immediate or reduced_motion:
		_camera_focus_ground = _camera_target_ground
		_camera_ground_distance = _camera_target_ground_distance
		_apply_camera_transform()


func update_home_target(ground_position: Vector2, immediate := false) -> void:
	# Manual focus is world-anchored, not an offset carried by the creature.
	if _camera_mode == CAMERA_MODE_HOME_MANUAL:
		return
	_home_follow_ground = ground_position
	_review_viewpoint_active = false
	_camera_target_ground_distance = _home_zoom_distance()
	_camera_target_ground = _home_focus_target()
	if immediate or reduced_motion:
		_camera_focus_ground = _camera_target_ground
		_camera_ground_distance = _camera_target_ground_distance
		_apply_camera_transform()


func set_home_manual_pan(offset_ground: Vector2, immediate := false) -> void:
	if _camera_mode != CAMERA_MODE_HOME_MANUAL:
		_home_follow_ground = _camera_focus_ground
	_camera_mode = CAMERA_MODE_HOME_MANUAL
	_review_viewpoint_active = false
	_manual_pan_ground = offset_ground
	_camera_target_ground_distance = _home_zoom_distance()
	_camera_target_ground = _home_focus_target()
	if immediate or reduced_motion:
		_camera_focus_ground = _camera_target_ground
		_camera_ground_distance = _camera_target_ground_distance
		_apply_camera_transform()


func set_home_zoom_multiplier(multiplier: float, immediate := false) -> void:
	# Keep the shared FOV fixed; home zoom is a bounded dolly along the one camera
	# axis, matching the profile contract without exposing card edges.
	_home_zoom_multiplier = clampf(multiplier, 0.0, 2.0)
	_camera_target_ground_distance = _home_zoom_distance()
	_camera_target_ground = _home_focus_target()
	if immediate or reduced_motion:
		_camera_focus_ground = _camera_target_ground
		_camera_ground_distance = _camera_target_ground_distance
		_apply_camera_transform()


func home_zoom_multiplier() -> float:
	return _home_zoom_multiplier


func _home_zoom_distance() -> float:
	var focused_distance := clampf(minf(_home_ground_distance, 8.0), _dolly_min, _dolly_max)
	if _home_zoom_multiplier >= 1.0:
		return maxf(_dolly_min, focused_distance / _home_zoom_multiplier)
	return lerpf(_full_map_distance(), focused_distance, _home_zoom_multiplier)


func _home_focus_target() -> Vector2:
	var requested := _home_follow_ground
	if _camera_mode == CAMERA_MODE_HOME_MANUAL:
		return _camera_bounds.get_center() if is_zero_approx(_home_zoom_multiplier) else _clamp_ground(requested + _manual_pan_ground)
	return _camera_bounds.get_center().lerp(_clamp_ground(requested), minf(_home_zoom_multiplier, 1.0))


func _full_map_distance() -> float:
	# Solve the perspective projection for all four ground corners. Unlike a
	# fixed zoom minimum, this fits both wide and tall care viewports at 0%.
	if camera == null or world_viewport == null:
		return _home_ground_distance
	var pitch := deg_to_rad(_camera_pitch_degrees)
	var horizontal := tan(deg_to_rad(camera.fov * 0.5)) * 0.94
	var vertical := horizontal * maxf(1.0, world_viewport.size.y) / maxf(1.0, world_viewport.size.x)
	var required := _dolly_min
	# An expanded authored grove may extend beyond the unchanged save/grid.
	# Only overview framing uses these visual bounds; input/navigation do not.
	var overview: Rect2 = environment_manifest.get("overviewBounds", _camera_bounds)
	for corner: Vector2 in [overview.position, Vector2(overview.end.x, overview.position.y), overview.end, Vector2(overview.position.x, overview.end.y)]:
		var relative := ground_to_world(corner - _camera_bounds.get_center())
		var bias := cos(pitch) * relative.z
		required = maxf(required, cos(pitch) * (bias + absf(relative.x) / horizontal))
		required = maxf(required, cos(pitch) * (bias + absf(sin(pitch) * relative.z) / vertical))
	# Home overview may exceed a biome's close-up dolly range. Battle and review
	# framing retain their own bounds; no gameplay geometry is changed.
	return required + 0.5


func pan_home_by_screen(previous: Vector2, current: Vector2) -> void:
	# Dragging must also work over the scenery/margins outside the editable grid.
	var before: Variant = _ground_intersection(previous)
	var after: Variant = _ground_intersection(current)
	if before == null or after == null or is_zero_approx(_home_zoom_multiplier):
		return
	if _camera_mode != CAMERA_MODE_HOME_MANUAL:
		set_home_manual_pan(Vector2.ZERO, true)
	var delta := world_to_ground(before as Vector3) - world_to_ground(after as Vector3)
	var desired := _clamp_ground(_home_follow_ground + _manual_pan_ground + delta)
	set_home_manual_pan(desired - _home_follow_ground, true)


func frame_ground_bounds(bounds: Rect2, padding_ground := Vector2(64.0, 96.0), immediate := false) -> bool:
	if camera == null or world_viewport == null or bounds.size.x < 0.0 or bounds.size.y < 0.0:
		return false
	var framed := bounds.grow_individual(padding_ground.x, padding_ground.y, padding_ground.x, padding_ground.y)
	var points: Array[Vector3] = []
	for point: Vector2 in [framed.position, Vector2(framed.end.x, framed.position.y),
			framed.end, Vector2(framed.position.x, framed.end.y)]:
		points.append(ground_to_world(point))
	_battle_bounds = bounds
	return frame_world_points(points, bounds.get_center(), immediate)


func set_battle_zoom(multiplier: float) -> void:
	if not is_finite(multiplier):
		return
	battle_zoom_multiplier = clampf(multiplier, 0.65, 2.0)
	if not _battle_world_points.is_empty():
		frame_world_points(_battle_world_points, _battle_focus_ground, true)


func frame_world_points(points: Array[Vector3], focus_ground: Vector2, immediate := false) -> bool:
	## Fits arbitrary rooted sprite/VFX corners without changing the fixed FOV,
	## pitch, or yaw. This is the battle-camera contract used to keep authored
	## pivots and above-ground cards on screen at every portrait target.
	if camera == null or world_viewport == null or points.is_empty():
		return false
	var viewport_size := Vector2(world_viewport.size)
	if viewport_size.x <= 1.0 or viewport_size.y <= 1.0:
		return false
	var pitch := deg_to_rad(_camera_pitch_degrees)
	# KEEP_WIDTH makes the authored FOV the horizontal invariant. Portrait
	# targets gain vertical field of view; they do not narrow the horizontal FOV.
	var tan_horizontal := tan(deg_to_rad(camera.fov * 0.5))
	var tan_vertical := tan_horizontal * viewport_size.y / viewport_size.x
	# Battle framing prioritizes the combatants/VFX. Home's frustum-aware clamp
	# intentionally keeps every screen ray on editable terrain, but applying it
	# here can push fighters off center near an arena edge at a large dolly.
	var target_ground := Vector2(clampf(focus_ground.x, _camera_bounds.position.x, _camera_bounds.end.x),
		clampf(focus_ground.y, _camera_bounds.position.y, _camera_bounds.end.y))
	var focus_world := ground_to_world(target_ground)
	var required_ground_distance := 0.1
	for point: Vector3 in points:
		if not point.is_finite():
			return false
		var relative := point - focus_world
		var depth_bias := sin(pitch) * relative.y + cos(pitch) * relative.z
		var camera_vertical := cos(pitch) * relative.y - sin(pitch) * relative.z
		required_ground_distance = maxf(required_ground_distance,
			cos(pitch) * (depth_bias + absf(relative.x) / maxf(tan_horizontal, 0.0001)))
		required_ground_distance = maxf(required_ground_distance,
			cos(pitch) * (depth_bias + absf(camera_vertical) / maxf(tan_vertical, 0.0001)))
	# A small deterministic margin prevents alpha-cut edge pixels touching the
	# viewport boundary because of floating-point projection rounding.
	required_ground_distance += 0.25
	if required_ground_distance > _dolly_max + 0.0001:
		return false
	# Fit (1x) preserves full fighter bounds. Manual close inspection may crop
	# distant fighters; subsequent render ticks keep the selected magnification.
	_camera_target_ground_distance = clampf(required_ground_distance / battle_zoom_multiplier, _dolly_min, _dolly_max)
	_camera_mode = CAMERA_MODE_BATTLE_FRAME
	_review_viewpoint_active = false
	_battle_world_points = points.duplicate()
	_battle_focus_ground = focus_ground
	_camera_target_ground = target_ground
	if immediate or reduced_motion:
		_camera_focus_ground = _camera_target_ground
		_camera_ground_distance = _camera_target_ground_distance
	_apply_camera_transform()
	return true


func camera_contains_world_points(points: Array[Vector3], margin_pixels := 1.0) -> bool:
	if camera == null or world_viewport == null:
		return false
	var viewport_size := Vector2(world_viewport.size)
	for point: Vector3 in points:
		if camera.is_position_behind(point):
			return false
		var projected := camera.unproject_position(point)
		if projected.x < margin_pixels or projected.y < margin_pixels \
				or projected.x > viewport_size.x - margin_pixels \
				or projected.y > viewport_size.y - margin_pixels:
			return false
	return true


func camera_forward_direction() -> Vector3:
	return -camera.global_transform.basis.z.normalized() if camera != null else Vector3.ZERO


func camera_mode() -> String:
	return _camera_mode


func set_reduced_motion(enabled: bool) -> void:
	reduced_motion = enabled
	if enabled:
		_camera_focus_ground = _camera_target_ground
		_camera_ground_distance = _camera_target_ground_distance
	_apply_camera_transform()


func advance_camera(delta: float) -> void:
	if camera == null or _review_viewpoint_active or environment_manifest.is_empty():
		return
	if _camera_mode == CAMERA_MODE_BATTLE_FRAME:
		_camera_target_ground = Vector2(clampf(_camera_target_ground.x, _camera_bounds.position.x, _camera_bounds.end.x),
			clampf(_camera_target_ground.y, _camera_bounds.position.y, _camera_bounds.end.y))
	else:
		_camera_target_ground = _clamp_ground(_camera_target_ground)
	if reduced_motion:
		_camera_focus_ground = _camera_target_ground
		_camera_ground_distance = _camera_target_ground_distance
	else:
		var speed := minf(_camera_smoothing_speed, 3.5) if _camera_mode == CAMERA_MODE_HOME_FOLLOW else _camera_smoothing_speed
		var weight := 1.0 - exp(-speed * maxf(delta, 0.0))
		_camera_focus_ground = _camera_focus_ground.lerp(_camera_target_ground, weight)
		if _camera_mode != CAMERA_MODE_BATTLE_FRAME:
			_camera_focus_ground = _clamp_ground(_camera_focus_ground)
		_camera_ground_distance = lerpf(_camera_ground_distance, _camera_target_ground_distance, weight)
	_apply_camera_transform()


func screen_to_ground(screen_position: Vector2) -> Variant:
	if camera == null or environment_manifest.is_empty():
		return null
	var viewport_size := Vector2(world_viewport.size)
	if screen_position.x < 0.0 or screen_position.y < 0.0 or screen_position.x > viewport_size.x or screen_position.y > viewport_size.y:
		return null
	var hit: Variant = _ground_intersection(screen_position)
	if hit == null:
		return null
	var ground := world_to_ground(hit as Vector3)
	return ground if _camera_bounds.has_point(ground) or _on_rect_end(ground, _camera_bounds) else null


func instrumentation() -> Dictionary:
	var node_count := _descendant_count(content_root) if content_root != null else 0
	var draw_call_estimate := _renderable_count(content_root) if content_root != null else 0
	var average_frame_ms := 0.0
	var maximum_frame_ms := 0.0
	for sample: float in _frame_time_samples:
		average_frame_ms += sample
		maximum_frame_ms = maxf(maximum_frame_ms, sample)
	if not _frame_time_samples.is_empty():
		average_frame_ms /= _frame_time_samples.size()
	return {
		"activePin": EnvironmentAssetLibrary.active_pin(),
		"nodes": node_count,
		"textures": _textures.size(),
		"drawCallEstimate": draw_call_estimate,
		"frameSamples": _frame_time_samples.size(),
		"averageFrameMs": average_frame_ms,
		"maximumFrameMs": maximum_frame_ms,
		"withinRuntimeBounds": node_count <= EnvironmentPresentationContract.MAX_ACTIVE_NODES \
			and _textures.size() <= EnvironmentPresentationContract.MAX_ACTIVE_TEXTURES,
		"cameraMode": _camera_mode,
		"spriteOrientationProfile": ScreenAlignedSprite.PROFILE_ID,
		"portraitTarget": [world_viewport.size.x, world_viewport.size.y] if world_viewport != null else [0, 0],
		"lastLoadError": _last_load_error,
	}


func acceptance_evidence(route: Array[Vector2]) -> Dictionary:
	var alpha_profiles := {"opaque": 0, "alpha-cut": 0, "transparent": 0}
	for chunk: Variant in environment_manifest.get("terrainChunks", []):
		if chunk is Dictionary:
			var alpha_mode := String(chunk.get("alphaMode", "opaque"))
			alpha_profiles[alpha_mode] = int(alpha_profiles.get(alpha_mode, 0)) + 1
	for plane: Sprite3D in rendered_planes:
		var alpha_mode := String(plane.get_meta("alpha_mode", "alpha-cut"))
		alpha_profiles[alpha_mode] = int(alpha_profiles.get(alpha_mode, 0)) + 1
	for child: Node in _ambient_root.get_children():
		if child is Sprite3D:
			var alpha_mode := String(child.get_meta("alpha_mode", "transparent"))
			alpha_profiles[alpha_mode] = int(alpha_profiles.get(alpha_mode, 0)) + 1
	return {
		"viewpoint": _camera_mode,
		"fixedPitch": is_equal_approx(camera.rotation_degrees.x, -EnvironmentPresentationContract.PITCH_DEGREES),
		"fixedYaw": is_zero_approx(camera.rotation_degrees.y),
		"traversalSegmentsClear": route_segments_are_clear(route),
		"alphaProfiles": alpha_profiles,
		"performance": instrumentation(),
	}


func set_debug_rectangles(group_name: String, rectangles: Array, color: Color) -> bool:
	var previous := _debug_root.get_node_or_null(group_name)
	if previous != null:
		previous.free()
	var group := Node3D.new()
	group.name = group_name
	_debug_root.add_child(group)
	for value: Variant in rectangles:
		if not value is Array or value.size() != 4:
			return false
		var rect := _rect(value)
		var mesh_instance := MeshInstance3D.new()
		var mesh := PlaneMesh.new()
		mesh.size = Vector2(rect.size.x / GROUND_UNITS_PER_CELL, rect.size.y / GROUND_UNITS_PER_CELL)
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.albedo_color = color
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		mesh.material = material
		mesh_instance.mesh = mesh
		mesh_instance.position = ground_to_world(rect.get_center()) + Vector3(0.0, 0.035, 0.0)
		group.add_child(mesh_instance)
	return true


func set_debug_group_visible(group_name: String, visible: bool) -> void:
	var group := _debug_root.get_node_or_null(group_name)
	if group != null:
		group.visible = visible


func _ensure_world() -> void:
	if world_root != null:
		return
	world_viewport = SubViewport.new()
	world_viewport.name = "WorldViewport"
	world_viewport.own_world_3d = true
	world_viewport.transparent_bg = false
	world_viewport.handle_input_locally = false
	world_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(world_viewport)
	world_root = Node3D.new()
	world_root.name = "EnvironmentWorld"
	world_viewport.add_child(world_root)
	content_root = Node3D.new()
	content_root.name = "Content"
	world_root.add_child(content_root)
	_terrain_root = Node3D.new()
	_terrain_root.name = "Terrain"
	content_root.add_child(_terrain_root)
	_ambient_root = Node3D.new()
	_ambient_root.name = "Ambient"
	content_root.add_child(_ambient_root)
	_placement_root = Node3D.new()
	_placement_root.name = "Placements"
	content_root.add_child(_placement_root)
	_debug_root = Node3D.new()
	_debug_root.name = "DebugOverlays"
	content_root.add_child(_debug_root)
	_world_nodes_root = Node3D.new()
	_world_nodes_root.name = "WorldNodes"
	content_root.add_child(_world_nodes_root)
	var world_environment := WorldEnvironment.new()
	world_environment.name = "WorldEnvironment"
	world_root.add_child(world_environment)
	camera = Camera3D.new()
	camera.name = "PresentationCamera"
	camera.current = true
	world_root.add_child(camera)


func _clear_environment_content() -> void:
	for root: Node3D in [_terrain_root, _ambient_root, _placement_root, _debug_root, _world_nodes_root]:
		_clear_children(root)
	stack_roots.clear()
	rendered_planes.clear()
	_placed_footprints.clear()


func _configure_world_environment(manifest: Dictionary) -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color.from_string(String(manifest.get("backgroundColor", "#182d31")), Color("182d31"))
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color.from_string(String(manifest.get("ambientColor", "#ffffff")), Color.WHITE)
	environment.ambient_light_energy = float(manifest.get("ambientEnergy", 1.0))
	(world_root.get_node("WorldEnvironment") as WorldEnvironment).environment = environment


func _configure_camera(profile: Dictionary) -> void:
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.fov = float(profile.fovDegrees)
	camera.keep_aspect = Camera3D.KEEP_WIDTH
	camera.near = float(profile.near)
	camera.far = float(profile.far)


func _build_terrain(chunks: Array) -> void:
	for chunk: Dictionary in chunks:
		var ground_rect := _rect(chunk.groundRect)
		var mesh_instance := MeshInstance3D.new()
		mesh_instance.name = String(chunk.id).to_pascal_case()
		var mesh := PlaneMesh.new()
		mesh.size = ground_rect.size / GROUND_UNITS_PER_CELL
		mesh.subdivide_width = int(chunk.subdivisions[0])
		mesh.subdivide_depth = int(chunk.subdivisions[1])
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		var texture_binding := String(chunk.get("textureBinding", chunk.get("source", "")))
		material.albedo_texture = _textures[texture_binding]
		material.render_priority = int(chunk.get("renderPriority", 0))
		_configure_material_alpha(material, String(chunk.get("alphaMode", "opaque")), String(chunk.get("depthBehavior", "write")))
		mesh.material = material
		mesh_instance.mesh = mesh
		mesh_instance.position = ground_to_world(ground_rect.get_center()) + Vector3(0.0, float(chunk.get("elevation", 0)), 0.0)
		_terrain_root.add_child(mesh_instance)


func _build_ambient(planes: Array) -> void:
	for definition: Dictionary in planes:
		var sprite := _make_sprite(definition, "position")
		if sprite != null:
			sprite.set_meta("parallax", float(definition.get("parallax", 1.0)))
			sprite.set_meta("base_position", sprite.position)
			_ambient_root.add_child(sprite)


func _make_sprite(definition: Dictionary, position_field: String) -> Sprite3D:
	var source := String(definition.get("source", ""))
	if not _textures.has(source):
		return null
	var sprite := Sprite3D.new()
	sprite.name = String(definition.id).to_pascal_case()
	sprite.texture = _textures[source]
	var render_size := sprite.texture.get_size()
	if definition.has("sourceRegionPx"):
		var region: Array = definition.sourceRegionPx
		sprite.region_enabled = true
		sprite.region_rect = Rect2(float(region[0]), float(region[1]), float(region[2]), float(region[3]))
		render_size = Vector2(float(region[2]), float(region[3]))
	sprite.pixel_size = float(definition.pixelSize)
	var pivot: Dictionary = definition.pivot
	sprite.offset = Vector2(render_size.x * (0.5 - float(pivot.x)), render_size.y * (float(pivot.y) - 0.5))
	sprite.position = _vector3(definition[position_field])
	var authored_rotation := _vector3(definition.rotationDegrees)
	sprite.rotation_degrees = authored_rotation + Vector3(-_sprite_tilt_degrees, 0.0, 0.0)
	_configure_sprite(sprite, String(definition.alphaMode), String(definition.depthBehavior))
	sprite.render_priority = EnvironmentPresentationContract.priority_for(definition)
	sprite.set_meta("alpha_mode", String(definition.alphaMode))
	sprite.set_meta("depth_behavior", String(definition.depthBehavior))
	sprite.set_meta("render_priority", sprite.render_priority)
	var role := String(definition.get("role", String(definition.id).get_slice(".", String(definition.id).get_slice_count(".") - 1)))
	sprite.set_meta("plane_role", role)
	return sprite


func _apply_camera_transform() -> void:
	if camera == null:
		return
	var focus := ground_to_world(_camera_focus_ground)
	var height := tan(deg_to_rad(_camera_pitch_degrees)) * _camera_ground_distance
	camera.position = focus + Vector3(0.0, height, _camera_ground_distance)
	camera.rotation_degrees = Vector3(-_camera_pitch_degrees, 0.0, 0.0)
	_apply_ambient_parallax(_camera_focus_ground)


func _apply_ambient_parallax(focus_ground: Vector2) -> void:
	if is_instance_valid(_native_parallax):
		_native_parallax.apply_focus(ground_to_world(focus_ground), reduced_motion)
	if _ambient_root == null:
		return
	var focus_delta := ground_to_world(focus_ground - _ambient_origin_focus_ground)
	for child: Node in _ambient_root.get_children():
		if not child is Sprite3D or not child.has_meta("base_position"):
			continue
		var sprite := child as Sprite3D
		var base_position: Vector3 = sprite.get_meta("base_position")
		var factor := 0.0 if reduced_motion else float(sprite.get_meta("parallax", 0.0))
		# Following a fraction of camera translation produces a controlled
		# secondary parallax layer on top of genuine perspective. Y stays authored.
		sprite.position = base_position + Vector3(focus_delta.x * factor, 0.0, focus_delta.z * factor)


func _clamp_ground(value: Vector2) -> Vector2:
	if _camera_bounds.size == Vector2.ZERO:
		return value
	var result := Vector2(clampf(value.x, _camera_bounds.position.x, _camera_bounds.end.x),
		clampf(value.y, _camera_bounds.position.y, _camera_bounds.end.y))
	# The original clearing includes scenery/terrain beyond the editable map.
	# Clamp the focus, not its entire frustum; otherwise a portrait camera pushes
	# the companion against the top of the screen to avoid seeing beyond the grid.
	if bool(environment_manifest.get("builtin", false)) or _camera_mode in [CAMERA_MODE_HOME_FOLLOW, CAMERA_MODE_HOME_MANUAL]:
		return result
	if camera == null or world_viewport == null or world_viewport.size.x <= 1 or world_viewport.size.y <= 1:
		return result
	var offsets: Array[Vector2] = []
	for corner: Vector2 in [Vector2.ZERO, Vector2(world_viewport.size.x, 0), Vector2(world_viewport.size), Vector2(0, world_viewport.size.y)]:
		var hit: Variant = _ground_intersection(corner)
		if hit != null:
			offsets.append(world_to_ground(hit as Vector3) - _camera_focus_ground)
	if offsets.size() != 4:
		return result
	var minimum := offsets[0]
	var maximum := offsets[0]
	for offset: Vector2 in offsets:
		minimum = minimum.min(offset)
		maximum = maximum.max(offset)
	var low := _camera_bounds.position - minimum
	var high := _camera_bounds.end - maximum
	result.x = _clamp_axis(result.x, low.x, high.x, _camera_bounds.get_center().x)
	result.y = _clamp_axis(result.y, low.y, high.y, _camera_bounds.get_center().y)
	return result


func _ground_intersection(screen_position: Vector2) -> Variant:
	var ray_origin := camera.project_ray_origin(screen_position)
	var ray_direction := camera.project_ray_normal(screen_position)
	return Plane(Vector3.UP, 0.0).intersects_ray(ray_origin, ray_direction)


func _sync_viewport_size() -> void:
	if world_viewport == null:
		return
	if not stretch:
		world_viewport.size = Vector2i(maxi(1, roundi(size.x)), maxi(1, roundi(size.y)))
	if not environment_manifest.is_empty() and _camera_mode == CAMERA_MODE_BATTLE_FRAME and _battle_world_points.is_empty():
		_camera_mode = CAMERA_MODE_HOME_FOLLOW
	if not environment_manifest.is_empty() and _camera_mode == CAMERA_MODE_BATTLE_FRAME:
		frame_world_points(_battle_world_points, _battle_focus_ground, true)
	elif not environment_manifest.is_empty() and not _review_viewpoint_active:
		if _camera_mode in [CAMERA_MODE_HOME_FOLLOW, CAMERA_MODE_HOME_MANUAL]:
			_camera_target_ground_distance = _home_zoom_distance()
			_camera_ground_distance = _camera_target_ground_distance
			_camera_target_ground = _home_focus_target()
		_camera_focus_ground = _clamp_ground(_camera_focus_ground)
		_camera_target_ground = _clamp_ground(_camera_target_ground)
		_apply_camera_transform()


func _resolve_textures(manifest: Dictionary, payload_root: String, embedded: Dictionary) -> Dictionary:
	var bindings: Variant = manifest.get("textures")
	if not bindings is Dictionary or bindings.is_empty() or bindings.size() > EnvironmentPresentationContract.MAX_ACTIVE_TEXTURES:
		return {}
	var result := {}
	for role: Variant in bindings:
		var role_name := String(role)
		if embedded.has(role_name) and embedded[role_name] is Texture2D:
			result[role_name] = embedded[role_name]
			continue
		var relative := String(bindings[role])
		if relative.is_absolute_path() or not relative.begins_with("textures/") or relative.contains("\\") or ".." in relative.split("/"):
			return {}
		var texture := AssetResourceLibrary.load_payload_texture(payload_root.path_join(relative))
		if texture == null:
			return {}
		result[role_name] = texture
	return result


func _manifest_is_renderable(manifest: Dictionary, textures: Dictionary) -> bool:
	if manifest.get("schemaVersion") != 1 or manifest.get("kind") != "environment":
		return false
	if not EnvironmentPresentationContract.validate_profile(manifest):
		return false
	var camera_profile: Variant = manifest.get("camera")
	if not camera_profile is Dictionary or camera_profile.get("projection") != "perspective" or camera_profile.get("keepAspect") != "width":
		return false
	for field: String in ["fovDegrees", "pitchDegrees", "spriteTiltDegrees", "near", "far", "groundDistance", "smoothingSpeed"]:
		if not _finite(camera_profile.get(field)):
			return false
	if not _quad(camera_profile.get("movementBounds")):
		return false
	if not _pair(camera_profile.get("dollyBounds")):
		return false
	var movement_bounds := _rect(camera_profile.movementBounds)
	var dolly_min := float(camera_profile.dollyBounds[0])
	var dolly_max := float(camera_profile.dollyBounds[1])
	if movement_bounds.size.x <= 0.0 or movement_bounds.size.y <= 0.0 \
		or float(camera_profile.near) <= 0.0 or float(camera_profile.far) <= float(camera_profile.near) \
		or float(camera_profile.groundDistance) <= 0.0 or float(camera_profile.smoothingSpeed) < 0.0 \
		or dolly_min < 2.0 or dolly_max > 60.0 or dolly_min > dolly_max \
		or float(camera_profile.groundDistance) < dolly_min or float(camera_profile.groundDistance) > dolly_max:
		return false
	var planes: Variant = manifest.get("spritePlanes")
	var stacks: Variant = manifest.get("planeStacks")
	var terrain: Variant = manifest.get("terrainChunks")
	if not planes is Array or planes.is_empty() or not stacks is Array or stacks.is_empty() or not terrain is Array or terrain.is_empty():
		return false
	var plane_ids := {}
	for record: Variant in planes:
		if not _valid_plane(record, textures, "localPosition"):
			return false
		var plane_id := String(record.get("id", ""))
		if plane_id.is_empty() or plane_ids.has(plane_id):
			return false
		plane_ids[plane_id] = true
	for record: Variant in manifest.get("ambientPlanes", []):
		if not _valid_plane(record, textures, "position"):
			return false
	for chunk: Variant in terrain:
		var texture_binding := String(chunk.get("textureBinding", chunk.get("source", ""))) if chunk is Dictionary else ""
		if not chunk is Dictionary or not textures.has(texture_binding) or not _quad(chunk.get("groundRect")) or not _pair(chunk.get("subdivisions")):
			return false
		if not _valid_alpha_depth(String(chunk.get("alphaMode", "opaque")), String(chunk.get("depthBehavior", "write"))):
			return false
		var chunk_alpha := String(chunk.get("alphaMode", "opaque"))
		if not EnvironmentPresentationContract.valid_render_priority(chunk.get("renderPriority"), chunk_alpha == "transparent"):
			return false
	var footprint_ids := {}
	for footprint: Variant in manifest.get("groundFootprints", []):
		if not footprint is Dictionary or String(footprint.get("id", "")).is_empty() or footprint_ids.has(String(footprint.id)) or not _quad(footprint.get("rect")):
			return false
		var footprint_rect := _rect(footprint.rect)
		if footprint_rect.size.x <= 0.0 or footprint_rect.size.y <= 0.0:
			return false
		footprint_ids[String(footprint.id)] = true
	var stack_ids := {}
	for stack: Variant in stacks:
		if not stack is Dictionary or not stack.get("planes") is Array or stack.planes.is_empty():
			return false
		var stack_id := String(stack.get("id", ""))
		if stack_id.is_empty() or stack_ids.has(stack_id) or not footprint_ids.has(String(stack.get("groundFootprint", ""))):
			return false
		stack_ids[stack_id] = true
		for plane_id: Variant in stack.planes:
			if not plane_ids.has(String(plane_id)):
				return false
	var viewpoints := {}
	for record: Variant in manifest.get("reviewViewpoints", []):
		if not record is Dictionary or not _triple(record.get("position")) or not _triple(record.get("lookAt")):
			return false
		viewpoints[String(record.get("id", ""))] = true
	for required: String in ["center", "left", "right", "near", "far"]:
		if not viewpoints.has(required):
			return false
	return viewpoints.size() == 5


func _manifest_shape_within_bounds(manifest: Dictionary) -> bool:
	if not manifest is Dictionary:
		return false
	var terrain: Variant = manifest.get("terrainChunks")
	var planes: Variant = manifest.get("spritePlanes")
	var stacks: Variant = manifest.get("planeStacks")
	var ambient: Variant = manifest.get("ambientPlanes", [])
	var textures: Variant = manifest.get("textures")
	return terrain is Array and terrain.size() > 0 and terrain.size() <= EnvironmentPresentationContract.MAX_TERRAIN_CHUNKS \
		and planes is Array and planes.size() > 0 and planes.size() <= EnvironmentPresentationContract.MAX_SPRITE_PLANES \
		and stacks is Array and stacks.size() > 0 and stacks.size() <= EnvironmentPresentationContract.MAX_PLANE_STACKS \
		and ambient is Array and ambient.size() <= EnvironmentPresentationContract.MAX_AMBIENT_PLANES \
		and textures is Dictionary and textures.size() > 0 and textures.size() <= EnvironmentPresentationContract.MAX_ACTIVE_TEXTURES


func _valid_plane(value: Variant, textures: Dictionary, position_field: String) -> bool:
	if not value is Dictionary or not textures.has(String(value.get("source", ""))) or not _triple(value.get(position_field)) or not _triple(value.get("rotationDegrees")):
		return false
	if not value.get("pivot") is Dictionary or not _finite(value.pivot.get("x")) or not _finite(value.pivot.get("y")) or not _finite(value.get("pixelSize")):
		return false
	if value.has("sourceRegionPx"):
		if not _quad(value.sourceRegionPx):
			return false
		var region: Array = value.sourceRegionPx
		var texture: Texture2D = textures[String(value.source)]
		if float(region[0]) < 0 or float(region[1]) < 0 or float(region[2]) <= 0 or float(region[3]) <= 0 or float(region[0]) + float(region[2]) > texture.get_width() or float(region[1]) + float(region[3]) > texture.get_height():
			return false
	var authored_rotation := _vector3(value.rotationDegrees)
	if not is_zero_approx(authored_rotation.y):
		return false
	var alpha_mode := String(value.get("alphaMode", ""))
	return _valid_alpha_depth(alpha_mode, String(value.get("depthBehavior", ""))) \
		and EnvironmentPresentationContract.valid_render_priority(value.get("renderPriority"), alpha_mode == "transparent")


static func _valid_alpha_depth(alpha_mode: String, depth_behavior: String) -> bool:
	return EnvironmentPresentationContract.valid_alpha_depth(alpha_mode, depth_behavior)


static func _configure_sprite(sprite: Sprite3D, alpha_mode: String, depth_behavior: String) -> void:
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sprite.shaded = false
	ScreenAlignedSprite.apply(sprite)
	sprite.fixed_size = false
	sprite.no_depth_test = false
	sprite.double_sided = true
	if alpha_mode == "alpha-cut":
		sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	elif alpha_mode == "transparent" and depth_behavior == "prepass":
		sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS
	else:
		sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED


static func _configure_material_alpha(material: StandardMaterial3D, alpha_mode: String, depth_behavior: String) -> void:
	if alpha_mode == "opaque":
		return
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR if alpha_mode == "alpha-cut" else BaseMaterial3D.TRANSPARENCY_ALPHA
	if depth_behavior == "prepass":
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS


static func _clear_children(node: Node) -> void:
	for child: Node in node.get_children():
		child.free()


static func _rect(value: Array) -> Rect2:
	return Rect2(float(value[0]), float(value[1]), float(value[2]), float(value[3]))


static func _vector3(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))


static func _pair(value: Variant) -> bool:
	return value is Array and value.size() == 2 and _finite(value[0]) and _finite(value[1])


static func _triple(value: Variant) -> bool:
	return value is Array and value.size() == 3 and _finite(value[0]) and _finite(value[1]) and _finite(value[2])


static func _quad(value: Variant) -> bool:
	return value is Array and value.size() == 4 and _finite(value[0]) and _finite(value[1]) and _finite(value[2]) and _finite(value[3])


static func _finite(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))


static func _clamp_axis(value: float, low: float, high: float, fallback: float) -> float:
	return clampf(value, low, high) if low <= high else fallback


static func _on_rect_end(point: Vector2, rect: Rect2) -> bool:
	return point.x >= rect.position.x and point.y >= rect.position.y and point.x <= rect.end.x and point.y <= rect.end.y


static func _segment_hits_rect(from: Vector2, to: Vector2, rect: Rect2) -> bool:
	if rect.has_point(from) or rect.has_point(to) or _on_rect_end(from, rect) or _on_rect_end(to, rect):
		return true
	var corners := [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]
	for index: int in corners.size():
		if Geometry2D.segment_intersects_segment(from, to, corners[index], corners[(index + 1) % corners.size()]) != null:
			return true
	return false


static func _descendant_count(root: Node) -> int:
	var count := 0
	for child: Node in root.get_children():
		count += 1 + _descendant_count(child)
	return count


static func _renderable_count(root: Node) -> int:
	var count := 0
	for child: Node in root.get_children():
		if child is Sprite3D or child is AnimatedSprite3D or child is MeshInstance3D:
			count += 1
		count += _renderable_count(child)
	return count
