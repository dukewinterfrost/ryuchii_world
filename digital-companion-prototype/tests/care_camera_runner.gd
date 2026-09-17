extends SceneTree

var checks := 0
var failures := 0


func _initialize() -> void:
	run.call_deferred()


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)


func run() -> void:
	var game := root.get_node("GameState")
	if not game.isolated_mode:
		quit(1)
		return
	game.set_process(false)
	var view := CareHabitatView.new()
	root.add_child(view)
	view.set_process(false)
	check(view.configure_region(HabitatAssetLibrary.resolve_region("green-shade", false)), "production care clearing configures")
	var state := CareRules.make_new_state(1000.0)
	view.update_snapshot(state)
	var env := view.environment_3d
	env.set_process(false)
	for dimensions: Vector2i in [Vector2i(360, 320), Vector2i(390, 524), Vector2i(430, 612)]:
		view.size = dimensions
		await process_frame
		env._sync_viewport_size()
		view.set_zoom(0.0)
		env.advance_camera(10.0)
		var corners: Array[Vector3] = []
		for point: Vector2 in [Vector2.ZERO, Vector2(1280, 0), Vector2(1280, 1536), Vector2(0, 1536)]:
			corners.append(EnvironmentView3D.ground_to_world(point))
		check(env.camera_contains_world_points(corners, 0.0), "0% fits all map corners at " + str(dimensions))
		if "--capture" in OS.get_cmdline_user_args():
			await RenderingServer.frame_post_draw
			env.world_viewport.get_texture().get_image().save_png("/tmp/care-camera-%dx%d-overview.png" % [dimensions.x, dimensions.y])
		var overview_distance := env._camera_ground_distance
		view.set_zoom(1.0)
		view.set_follow(true)
		env.update_home_target(view.avatar.position, true)
		env.advance_camera(10.0)
		check(env._camera_ground_distance < overview_distance * 0.5, "default zoom is a companion close-up")
		if "--capture" in OS.get_cmdline_user_args():
			await RenderingServer.frame_post_draw
			env.world_viewport.get_texture().get_image().save_png("/tmp/care-camera-%dx%d-close.png" % [dimensions.x, dimensions.y])
		for zoom: float in [0.5, 1.0, 2.0]:
			view.set_zoom(zoom)
			view.set_follow(true)
			env.update_home_target(Vector2(500, 600), true)
			var start := env._camera_focus_ground
			env.update_home_target(Vector2(800, 900), false)
			check(env._camera_focus_ground.is_equal_approx(start), "follow does not snap on target update")
			env.advance_camera(1.0 / 60.0)
			check(env._camera_focus_ground.distance_to(start) > 0.0 and env._camera_focus_ground.distance_to(start) < start.distance_to(env._camera_target_ground), "follow eases toward target")
			var frozen := env._camera_focus_ground
			view.set_follow(false)
			check(env._camera_focus_ground.is_equal_approx(frozen), "turning follow off freezes the currently visible focus")
			for frame: int in 60:
				env.update_home_target(Vector2(1100, 1200), false)
				env.advance_camera(1.0 / 60.0)
			check(env._camera_focus_ground.is_equal_approx(frozen), "manual focus ignores roaming")
			env.pan_home_by_screen(Vector2(view.size.x - 2, 2), Vector2(view.size.x - 52, 52))
			check(not env._camera_focus_ground.is_equal_approx(frozen), "drag moves camera at chosen zoom")
			var panned := env._camera_focus_ground
			# Unrelated state refresh must not reset unsaved local controls or pan.
			view.update_snapshot(state)
			check(not view.follow and is_equal_approx(view.zoom_multiplier, zoom), "snapshot preserves pending camera controls")
			check(env._camera_focus_ground.is_equal_approx(panned), "snapshot preserves manual map position")
			for edge: Vector2 in [Vector2(0, 0), Vector2(1280, 1536)]:
				env.set_home_manual_pan(edge - env._home_follow_ground, true)
				check(env._camera_target_ground.is_equal_approx(edge), "manual mode reaches map edges at any nonzero zoom")
		view.set_zoom(0.0)
		var pinch := InputEventMagnifyGesture.new()
		pinch.factor = 1.2
		view._on_field_input(pinch)
		check(view.zoom_multiplier > 0.0, "pinch can zoom in from 0%")
	# A snapshot acknowledging the same cell must not rewind sub-cell motion.
	view.avatar.position += Vector2(7, 3)
	var walking_position := view.avatar.position
	view.update_snapshot(state)
	check(view.avatar.position == walking_position, "state refresh preserves continuous movement between cell commits")
	check(game.set_habitat_camera(0.0, false).ok and HabitatRules.validate_layout(game.state.habitat).ok, "0% camera value survives save validation")
	# Verify the 2D fallback has the same nonzero physical scale at logical 0%.
	view.configure_region({"region_id": "shellfish-beach", "mode": "fallback-2d"})
	view.update_snapshot(state)
	view.set_zoom(0.0)
	check(view.camera.zoom.x > 0.0 and view.camera.position == CareHabitatView.WORLD_SIZE * 0.5, "2D fallback 0% fits map without division by zero")
	view.queue_free()
	await process_frame
	await process_frame
	print("Care camera: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
