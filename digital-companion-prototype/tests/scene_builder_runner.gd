extends SceneTree
## Structural checks run headless. --capture adds real GPU coverage and motion evidence.
var checks := 0
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func run() -> void:
	var game := root.get_node("GameState")
	check(game.isolated_mode, "Only the isolated test save may be used")
	if not game.isolated_mode:
		quit(1)
		return
	game.set_process(false)
	game._home_package = HabitatAssetLibrary.resolve_region("green-shade", false)
	var care: Node = load("res://scenes/care_scene.tscn").instantiate()
	root.add_child(care)
	care.habitat.set_process(false)
	var baseline: Dictionary = game.state.duplicate(true)
	var view: EnvironmentView3D = care.habitat.environment_3d
	view.set_process(false)
	view.day_night.clock.set_preview_hour(12)
	view.day_night.shafts.set_process(false)
	var wrap: Node3D = view._native_parallax
	var transition: Node3D = wrap.get_node("TransitionWoodland")
	var terrain: MeshInstance3D = view._terrain_root.get_node("CareClearing/Ground")
	var cards := transition.find_children("*", "Sprite3D", true, false)
	check(transition.get_child_count() == 4 and cards.size() == 210, "Four named lower depths close the transition and foreground")
	var region_types := {}
	var minimum_height := INF
	var maximum_height := -INF
	for card: Sprite3D in cards:
		var p := card.global_position
		check(p.x < -2 or p.x > 42 or p.z < -2 or p.z > 50, "Transition roots never enter gameplay or its apron")
		check(p.y < -8, "Transition decor is actually below the playable ground")
		check(absf(p.y - terrain.height_at_ground(Vector2(p.x, p.z)) + 0.45) < 0.25, "Bottoms are buried in the same sculpted terrain")
		check(card.modulate.r < 0.55 and card.modulate.g < 0.55 and card.modulate.a == 1.0, "Lower foliage is shaded without partial-alpha sorting")
		check(not card.no_depth_test and card.alpha_cut == SpriteBase3D.ALPHA_CUT_DISCARD and card.texture_filter == BaseMaterial3D.TEXTURE_FILTER_NEAREST, "Layer cutouts retain pixel/depth rules")
		region_types[card.region_rect] = true
		minimum_height = minf(minimum_height, p.y)
		maximum_height = maxf(maximum_height, p.y)
	check(region_types.size() == 3 and maximum_height - minimum_height < 0.01 and is_equal_approx(minimum_height,-16.45), "Three silhouettes share the lowered floor beneath the sheer ledge")
	var rear: Node3D = transition.get_node("RearGrove")
	var side: Node3D = transition.get_node("SideValleys")
	view.set_home_zoom_multiplier(0.65, true)
	view.set_home_manual_pan(Vector2(512, -512), true)
	check(rear.position.distance_to(wrap._bases[rear]) > 0.1, "Distant decor has bounded secondary parallax")
	check(side.position == wrap._bases[side], "Grounded side decor does not slide with the camera")
	view.set_reduced_motion(true)
	check(rear.position == wrap._bases[rear], "Reduced motion restores authored layer bases")
	view.set_reduced_motion(false)
	view.set_home_manual_pan(Vector2.ZERO, true)
	check(is_equal_approx(terrain.edge_drop, 16.0), "The user-approved lowered shoulder remains intact")
	check(is_equal_approx(terrain.get_active_material(0).get_shader_parameter("lower_shadow_strength"), 0.62), "The user-approved dark lower stage is retained")
	check(float(terrain.get_active_material(0).get_shader_parameter("meadow_warmth")) > 0 and float(terrain.get_active_material(0).get_shader_parameter("grass_detail")) > 0, "Reference-led meadow detail is active in the real ground material")
	var args := OS.get_cmdline_user_args()
	var comparison := args.find("--compare-candidate")
	if comparison >= 0 and comparison + 1 < args.size():
		var candidate: Node3D = load(args[comparison + 1]).instantiate()
		check(candidate.get_meta("layout_sha256") == transition.get_meta("layout_sha256"), "Offline authoring semantic hashes match across independent runs")
		for card: Sprite3D in cards:
			var other: Sprite3D = candidate.get_node(transition.get_path_to(card))
			check(card.transform.is_equal_approx(other.transform) and is_equal_approx(card.pixel_size, other.pixel_size) and card.region_rect == other.region_rect and card.flip_h == other.flip_h and card.offset == other.offset and card.modulate.is_equal_approx(other.modulate), "Deterministic actual card placement and appearance")
		candidate.free()
	if "--capture" in args:
		for target: Vector2i in [Vector2i(360,640), Vector2i(390,844), Vector2i(430,932), Vector2i(1280,720)]:
			root.content_scale_size = target
			root.size = target
			await process_frame
			care._set_map_view(true)
			view.set_home_zoom_multiplier(0.0, true)
			view.set_home_manual_pan(Vector2.ZERO, true)
			transition.visible = false
			await process_frame
			RenderingServer.force_draw(false)
			var without := view.world_viewport.get_texture().get_image()
			transition.visible = true
			await process_frame
			RenderingServer.force_draw(false)
			var complete := view.world_viewport.get_texture().get_image()
			var lower_region := Rect2i(0, int(complete.get_height() * 0.57), complete.get_width(), int(complete.get_height() * 0.43))
			if target.x > target.y:
				# Wide overview shows the lowered gap behind the plateau, while a
				# tall portrait exposes the near basin. Don't measure playable turf.
				lower_region = Rect2i(0, int(complete.get_height() * 0.12), complete.get_width(), int(complete.get_height() * 0.20))
			var coverage := changed_ratio(without, complete, lower_region)
			print("Lower-gap coverage %dx%d: %.3f" % [target.x, target.y, coverage])
			check(coverage > 0.10, "New decor visibly fills the lower gap, not just offscreen scene nodes")
			check(complete.save_png("/tmp/scene-builder-complete-%dx%d.png" % [target.x, target.y]) == OK, "Save complete composition evidence")
			check(without.save_png("/tmp/scene-builder-without-%dx%d.png" % [target.x, target.y]) == OK, "Save layers-off comparison evidence")
			view.set_home_zoom_multiplier(0.65, true)
			var depth := (view.camera.position - EnvironmentView3D.ground_to_world(view._camera_focus_ground)).length()
			var world_per_pixel := 2.0 * depth * tan(deg_to_rad(view.camera.fov * 0.5)) / float(view.world_viewport.size.x)
			var reference: Image
			for fraction: float in [0.0, 0.25, 0.5, 0.75, 1.0]:
				view.set_home_manual_pan(Vector2(world_per_pixel * fraction * 32.0, 0), true)
				await process_frame
				RenderingServer.force_draw(false)
				var frame := view.world_viewport.get_texture().get_image()
				if fraction == 0.0:
					reference = frame
				var crop := Rect2i(0, int(frame.get_height()*0.55), int(frame.get_width()*0.28), int(frame.get_height()*0.3))
				print("Subpixel %dx%d %.2f px, changed ratio %.3f" % [target.x, target.y, fraction, changed_ratio(reference, frame, crop)])
				check(frame.save_png("/tmp/scene-builder-subpixel-%dx%d-%02d.png" % [target.x, target.y, int(fraction*100)]) == OK, "Save subpixel review frame")
			view.set_home_manual_pan(Vector2.ZERO, true)
			await process_frame
			RenderingServer.force_draw(false)
			var restored := view.world_viewport.get_texture().get_image()
			var stable_crop := Rect2i(0, int(restored.get_height()*0.55), int(restored.get_width()*0.28), int(restored.get_height()*0.3))
			check(changed_ratio(reference, restored, stable_crop) < 0.001, "Returning to the same camera restores stationary detail without temporal noise")
	for key: String in baseline:
		if key == "habitat":
			for field: String in baseline.habitat:
				if field != "camera":
					check(game.state.habitat[field] == baseline.habitat[field], "Scenery preserves saved habitat: " + field)
		else:
			check(game.state[key] == baseline[key], "Scenery preserves simulation: " + key)
	care.free()
	check(not is_instance_valid(transition), "Scenery nodes are released with the active home")
	print("Scene builder: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func changed_ratio(a: Image, b: Image, crop: Rect2i) -> float:
	var changed := 0
	for y: int in range(crop.position.y, mini(crop.end.y, a.get_height())):
		for x: int in range(crop.position.x, mini(crop.end.x, a.get_width())):
			var first := a.get_pixel(x, y)
			var second := b.get_pixel(x, y)
			if maxf(absf(first.r-second.r), maxf(absf(first.g-second.g), absf(first.b-second.b))) > 0.015:
				changed += 1
	return float(changed) / float(crop.get_area())
