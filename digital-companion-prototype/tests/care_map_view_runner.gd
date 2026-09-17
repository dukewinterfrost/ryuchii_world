extends SceneTree

var checks := 0
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL: " + message)

func run() -> void:
	var game := root.get_node("GameState")
	if not game.isolated_mode:
		quit(1)
		return
	game.set_process(false)
	game._home_package = HabitatAssetLibrary.resolve_region("green-shade", false)
	var care = load("res://scenes/care_scene.tscn").instantiate()
	root.add_child(care)
	care.habitat.set_process(false)
	var baseline: Dictionary = game.state.habitat.duplicate(true)
	var scenery: Node3D = care.habitat.environment_3d._native_parallax
	check(scenery != null and scenery.externally_driven, "live care loads camera-driven forest parallax")
	var sky: Node3D = scenery.get_node("Sky")
	var plant: Node3D = scenery.get_node("MeadowPatch_0")
	var plant_base := plant.position
	scenery.apply_focus(scenery.to_global(scenery.reference_focus), false)
	var sky_base := sky.position
	scenery.apply_focus(scenery.to_global(scenery.reference_focus + Vector3(10, 0, 0)), false)
	check(is_equal_approx(sky.position.x - sky_base.x, 1.8), "scaled care layout uses local-space parallax displacement")
	check(plant.position == plant_base, "grounded plants do not slide with camera")
	scenery.apply_focus(Vector3(100, 0, 100), true)
	check(sky.position == sky_base, "reduced motion restores sky base position")
	for dimensions: Vector2i in [Vector2i(360, 640), Vector2i(390, 844), Vector2i(1280, 720), Vector2i(1920, 1080)]:
		root.content_scale_size = dimensions
		root.size = dimensions
		await process_frame
		care._set_map_view(true)
		for frame: int in 6:
			await process_frame
		care.habitat.environment_3d.advance_camera(10.0)
		check(care.habitat.size.is_equal_approx(Vector2(dimensions)), "map uses full window at " + str(dimensions))
		check(not care._header_panel.visible and not care._care_panel.visible and care._map_bar.visible, "map mode replaces care panels with compact controls")
		var expected_zoom := 0.75 if dimensions.y > dimensions.x else 0.45
		check(not care.habitat.follow and is_equal_approx(care.habitat.zoom_multiplier, expected_zoom), "map starts in aspect-aware manual mid-distance view")
		check(care._map_bar.get_global_rect().end.x <= dimensions.x, "map controls fit portrait and landscape")
		if "--capture" in OS.get_cmdline_user_args():
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("/tmp/care-map-view-%dx%d.png" % [dimensions.x, dimensions.y])
		care._set_map_view(false)
		await process_frame
		check(care._header_panel.visible and care._care_panel.visible and not care._map_bar.visible, "Back restores care UI")
		check(care.habitat.size.y == dimensions.y - 320, "Back restores original field bounds")
	check(game.state.habitat.items == baseline.items and game.state.habitat.creature_cell == baseline.creature_cell, "map viewing changes no decorations or companion location")
	care.queue_free()
	await process_frame
	await process_frame
	print("Care map view: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
