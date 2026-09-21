extends SceneTree
## Run with --test-mode. Add --capture under a graphical Compatibility renderer.
var checks := 0
var failures := 0
var fake_hour := 23.9

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL: " + message)

func run() -> void:
	var game := root.get_node("GameState")
	check(game.isolated_mode, "Use only the isolated save")
	if not game.isolated_mode:
		quit(1)
		return
	game.set_process(false)
	for hour: float in [0.0, 5.0, 6.0, 8.0, 12.0, 16.0, 18.0, 20.0, 24.0]:
		var sample := TimeOfDayController.sample_time(hour)
		var tint: Color = sample.scenery_tint
		check(tint.r > 0.4 and tint.g > 0.4 and tint.b > 0.4 and tint.a == 1.0, "Readable lighting at %s" % hour)
		check(sample.star_visibility >= 0 and sample.star_visibility <= 1, "Bounded stars at %s" % hour)
		var before := TimeOfDayController.sample_time(hour - 0.0001)
		var after := TimeOfDayController.sample_time(hour + 0.0001)
		check((before.scenery_tint as Color).is_equal_approx(after.scenery_tint), "Tint continuous at %s" % hour)
	check(TimeOfDayController.sample_time(0.0) == TimeOfDayController.sample_time(24.0), "Midnight wraps exactly")
	check(TimeOfDayController.sample_time(NAN) == TimeOfDayController.sample_time(12.0), "Invalid time defaults safely")
	check(TimeOfDayController.sample_time(12.0).sun_visibility > 0.99 and TimeOfDayController.sample_time(12.0).moon_visibility == 0.0, "Sun at noon")
	check(TimeOfDayController.sample_time(0.0).moon_visibility > 0.99 and TimeOfDayController.sample_time(0.0).sun_visibility == 0.0, "Moon at midnight")
	check(TimeOfDayController.sample_time(12.0).star_visibility == 0.0, "No daytime stars")
	var clock := TimeOfDayController.new()
	clock.clock_source = func() -> float: return fake_hour
	root.add_child(clock)
	clock.set_process(false)
	check(is_equal_approx(clock.displayed_hour, 23.9), "Clock starts at local time")
	fake_hour = 0.1
	clock.resync_clock()
	clock.advance_clock(0.1)
	check(clock.displayed_hour > 23.9, "Midnight correction travels forward across midnight")
	clock.set_preview_hour(18.0)
	clock.advance_clock(60.0)
	check(clock.displayed_hour == 18.0, "Preview stays frozen")
	clock.use_local_time()
	check(clock.preview_hour < 0 and clock.displayed_hour == 18.0, "Reset leaves preview with no immediate snap")
	for step: int in 100:
		clock.advance_clock(0.1)
	check(absf(clock.displayed_hour - fake_hour) < 0.01, "Reset converges to current clock")
	fake_hour = 8.0
	var previous := clock.displayed_hour
	clock._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	check(clock.target_hour == 8.0 and clock.displayed_hour == previous, "Focus resamples time without snapping")
	clock.advance_clock(3600.0)
	check(clock.displayed_hour > previous and clock.displayed_hour < 8.0, "Long suspension blends clock correction")
	fake_hour = 16.0
	clock.advance_clock(5.0)
	check(clock.target_hour == 16.0, "Periodic sampling catches timezone/clock changes")
	clock.free()

	game.state.identity.species_id = "agumon"
	game.state.identity.species_name = "Agumon"
	game.state.identity.stage = "Rookie"
	game.state.skills = GameDefinitions.default_skills("agumon")
	game._home_package = HabitatAssetLibrary.resolve_region("green-shade", false)
	var baseline: Dictionary = game.state.duplicate(true)
	var care: Node = load("res://scenes/care_scene.tscn").instantiate()
	root.add_child(care)
	current_scene = care
	care.habitat.set_process(false)
	root.content_scale_size = Vector2i(390, 844)
	root.size = Vector2i(390, 844)
	await process_frame
	var view: EnvironmentView3D = care.habitat.environment_3d
	check(view.day_night != null, "Built-in home has lighting")
	var lighting := view.day_night
	var shafts := lighting.shafts
	check(shafts.get_child_count() == 5, "Bounded set of five world light shafts")
	lighting.clock.set_preview_hour(12.0)
	check(shafts.daylight_strength > 0 and shafts.moonlight_strength == 0, "Daylight shafts use the sun")
	var day_color: Color = shafts.materials[0].get_shader_parameter("shaft_color")
	check(day_color.r > day_color.b, "Daylight shafts are warm")
	lighting.clock.set_preview_hour(0.0)
	check(shafts.moonlight_strength > 0 and shafts.daylight_strength == 0, "Moonlight shafts use the moon")
	var night_color: Color = shafts.materials[0].get_shader_parameter("shaft_color")
	check(night_color.b > night_color.r, "Moonlight shafts are cool")
	for boundary: float in [6.0, 18.0]:
		lighting.clock.set_preview_hour(boundary)
		check(not shafts.visible, "Shafts fade at the horizon at %s" % boundary)
	lighting.clock.set_preview_hour(0.0)
	view.set_reduced_motion(true)
	var frozen_time := shafts.animation_time
	shafts._process(1.0)
	check(shafts.animation_time == frozen_time, "Reduced motion freezes shaft shimmer")
	view.set_reduced_motion(false)
	shafts._process(0.1)
	check(shafts.animation_time > frozen_time, "Shaft shimmer resumes")
	var rooted_position: Vector3 = shafts.get_child(0).global_position
	view.set_home_manual_pan(Vector2(96, -64), true)
	check(shafts.get_child(0).global_position == rooted_position, "Camera pan leaves shafts rooted in the world")
	view.set_home_follow(care.habitat.avatar.position, true)
	var noon := TimeOfDayController.sample_time(12.0)
	var midnight := TimeOfDayController.sample_time(0.0)
	lighting.clock.set_preview_hour(0.0)
	var avatar: SpriteBase3D = care.habitat.avatar_3d.sprite
	check(avatar.modulate.is_equal_approx(midnight.scenery_tint), "Companion gets moonlight")
	var ground := view._terrain_root.get_node("CareClearing/Ground") as MeshInstance3D
	var material := ground.get_active_material(0) as ShaderMaterial
	check((material.get_shader_parameter("day_night_tint") as Color).is_equal_approx(midnight.scenery_tint), "Unshaded ground gets moonlight")
	var local_scene: Node = load("res://scenes/environments/care_clearing.tscn").instantiate()
	var original_ground := local_scene.get_node("Ground") as MeshInstance3D
	check(original_ground.get_active_material(0) != material, "Authored ground material is never shared with tinted instance")
	check(original_ground.get_active_material(0).get_shader_parameter("day_night_tint") == null or original_ground.get_active_material(0).get_shader_parameter("day_night_tint") == Color.WHITE, "Authored ground stays untinted")
	local_scene.free()
	var decorated: Dictionary = baseline.duplicate(true)
	decorated.habitat.items = [{"instance_id": "night-planter", "item_id": "planter", "x": 22, "y": 26, "rotation": 0}, {"instance_id": "night-rug", "item_id": "rug", "x": 18, "y": 27, "rotation": 0}]
	decorated.care.poop_slots[0] = true
	care.habitat.update_snapshot(decorated)
	var decor: Node = care.habitat.care_visuals_3d.get_node("HomeDecor")
	for item: Node in decor.get_children():
		if item is SpriteBase3D:
			check(item.modulate.is_equal_approx(midnight.scenery_tint), "New planter is tinted before its first frame")
		else:
			check((item.get_active_material(0) as BaseMaterial3D).albedo_color.is_equal_approx(midnight.scenery_tint), "New rug is tinted before its first frame")
	var waste: Sprite3D = care.habitat.care_visuals_3d.get_node("HomeWaste").get_child(0)
	check(waste.modulate.is_equal_approx(midnight.scenery_tint), "New waste gets current tint")
	var tree := view._terrain_root.get_node("CareClearing/ForestParallax/RearTree_0_0") as Sprite3D
	var original_color: Color = lighting._bindings[tree.get_instance_id()].base_color
	for step: int in 100:
		lighting.clock.set_preview_hour(0.0)
	check(tree.modulate.is_equal_approx(original_color * midnight.scenery_tint), "Repeated lighting does not compound authored tint")
	lighting.clock.set_preview_hour(12.0)
	check(tree.modulate.is_equal_approx(original_color), "Noon restores original scenery color")
	check(avatar.modulate.is_equal_approx(noon.scenery_tint), "Noon restores companion")
	care.habitat.update_snapshot(baseline)
	var binding_count := lighting._bindings.size()
	for iteration: int in 4:
		care.habitat.update_snapshot(decorated)
		care.habitat.update_snapshot(baseline)
	check(lighting._bindings.size() == binding_count, "Removed decor bindings are released")
	care._day_night_preview.toggle()
	await process_frame
	check(care._day_night_preview.visible, "Preview opens")
	care._day_night_preview.slider.value = 3.5
	check(is_equal_approx(lighting.clock.preview_hour, 3.5), "Preview slider controls time")
	care._day_night_preview.hide()
	lighting.clock.use_local_time()
	check(lighting.clock.preview_hour < 0, "Preview reset restores local clock")
	check(game.state == baseline, "Lighting, decoration previews and clock never mutate saved state")

	for hour: float in [6.0, 12.0, 18.0, 0.0]:
		lighting.clock.set_preview_hour(hour)
		view.set_home_follow(care.habitat.avatar.position, true)
		view.set_home_zoom_multiplier(1.0, true)
		for frame: int in 4:
			await process_frame
		if "--capture" in OS.get_cmdline_user_args():
			await RenderingServer.frame_post_draw
			check(root.get_texture().get_image().save_png("/tmp/day-night-home-%02d.png" % int(hour)) == OK, "Capture home at %s" % hour)
		care.habitat.offset_top = 0
		care.habitat.offset_bottom = 0
		view.set_home_zoom_multiplier(0.75, true)
		for frame: int in 4:
			await process_frame
		if "--capture" in OS.get_cmdline_user_args():
			await RenderingServer.frame_post_draw
			check(view.world_viewport.get_texture().get_image().save_png("/tmp/day-night-wide-%02d.png" % int(hour)) == OK, "Capture wide sky at %s" % hour)
		care.habitat.offset_top = 126
		care.habitat.offset_bottom = -194
		view.set_home_manual_pan(Vector2(96, -128), true)
		var center := Vector2(view.world_viewport.size) * 0.5
		check(view.screen_to_ground(center) is Vector2, "Pan/zoom retains ground projection")
	# Inspect the real preview over the narrowest supported Field viewport.
	root.content_scale_size = Vector2i(360, 640)
	root.size = Vector2i(360, 640)
	care.habitat.offset_top = 0
	care.habitat.offset_bottom = 0
	view.set_home_zoom_multiplier(0.75, true)
	view.set_home_manual_pan(Vector2(-96, 64), true)
	lighting.clock.set_preview_hour(0.0)
	for frame: int in 4:
		await process_frame
	if "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		check(view.world_viewport.get_texture().get_image().save_png("/tmp/day-night-pan-360x640.png") == OK, "Capture panned narrow Field view")
	care._day_night_preview.toggle()
	for frame: int in 2:
		await process_frame
	check(care._day_night_preview.get_global_rect().end.x <= root.size.x, "Preview fits a narrow phone")
	if "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png("/tmp/day-night-preview.png") == OK, "Capture development preview")
	var old_clock := lighting.clock
	check(care.habitat.configure_region(HabitatAssetLibrary.resolve_region("green-shade", true)), "Switch to regional fixture")
	check(not is_instance_valid(shafts), "Region switch destroys light shafts")
	check(view.day_night == null and not is_instance_valid(old_clock), "Region switch destroys clock and lighting")
	await process_frame
	check(not care._day_night_preview.visible, "Preview hidden outside built-in clearing")
	check(care.habitat.configure_region(game._home_package), "Return to built-in clearing")
	check(view.day_night != null and view.day_night.clock.preview_hour < 0, "Return starts fresh local-time clock")
	print("PASS: %d day/night checks; %d failures" % [checks, failures])
	quit(1 if failures else 0)
