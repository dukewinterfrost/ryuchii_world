extends SceneTree
## Exercises the actual production resolver/UI with an isolated synthetic save.
## It does not opt into pending regional fixtures for its care-screen evidence.

var checks := 0
var failures := 0
var capture_prefix := "care-reference"

func _initialize() -> void:
	run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL: " + message)

func run() -> void:
	var game := root.get_node("GameState")
	check(game.isolated_mode, "Never open the user's save")
	if not game.isolated_mode:
		quit(1)
		return
	game.set_process(false)
	game.state.identity.species_id = "agumon"
	game.state.identity.species_name = "Agumon"
	game.state.identity.stage = "Rookie"
	game.state.skills = GameDefinitions.default_skills("agumon")
	game._home_package = HabitatAssetLibrary.resolve_region("green-shade", false)
	var baseline: Dictionary = game.state.duplicate(true)
	var care: Node = (load("res://scenes/care_scene.tscn") as PackedScene).instantiate()
	root.add_child(care)
	current_scene = care
	care.habitat.set_process(false)
	var view: EnvironmentView3D = care.habitat.environment_3d
	var candidate_arg := OS.get_cmdline_user_args().find("--foliage-candidate")
	if candidate_arg >= 0 and candidate_arg + 1 < OS.get_cmdline_user_args().size():
		capture_prefix = "care-foliage-compiled"
		check(preload("res://tests/care_foliage_review.gd").apply(view, OS.get_cmdline_user_args()[candidate_arg + 1]), "Native compiled foliage preserves approved pixels and pivots in isolated review")
	elif "--foliage-review" in OS.get_cmdline_user_args():
		capture_prefix = "care-foliage-review"
		check(preload("res://tests/care_foliage_review.gd").apply(view), "Hash-bound foliage preview is isolated from production")
	check(care.habitat.using_3d and view.environment_manifest.get("builtin", false), "Normal care path uses original 3D clearing")
	check(EnvironmentAssetLibrary.active_package().is_empty(), "No pending regional art was promoted/activated")
	check(care.habitat.habitat_manifest == game.get_home_package().habitat, "Ground/navigation authority uses the same resolved scenery footprints")
	for size: Vector2i in [Vector2i(360,640),Vector2i(390,844),Vector2i(430,932)]:
		root.content_scale_size = size
		root.size = size
		for frame: int in 8:
			await process_frame
		view.set_home_follow(care.habitat.avatar.position, true)
		view.set_home_zoom_multiplier(1.0, true)
		var actor: CompanionPresentation3D = care.habitat.avatar_3d
		actor.sprite.pause()
		check(actor.sprite.billboard == BaseMaterial3D.BILLBOARD_ENABLED and not actor.sprite.no_depth_test, "Camera-facing depth-tested companion")
		check(care.habitat.size.y > 200, "Care controls leave a usable world view")
		var cell := Vector2(656,784)
		var screen := view.camera.unproject_position(EnvironmentView3D.ground_to_world(cell))
		var projected: Variant = view.screen_to_ground(screen)
		check(projected is Vector2 and (projected as Vector2).distance_to(cell)<0.1, "Touch ray preserves the ground coordinate")
		var original_basis := view.camera.basis
		for pitch: float in [25.0,35.0,50.0]:
			view.camera.rotation_degrees.x = -pitch
			var corners := actor.visual_world_corners(cell, false)
			var normal := view.camera.global_basis.z.normalized()
			check(corners.size()==4 and absf((corners[1]-corners[0]).dot(normal))<0.0001 and absf((corners[3]-corners[0]).dot(normal))<0.0001, "Sprite envelope stays parallel to camera image plane at " + str(pitch))
		view.camera.basis = original_basis
		if "--capture" in OS.get_cmdline_user_args():
			await RenderingServer.frame_post_draw
			check(root.get_texture().get_image().save_png("/tmp/%s-%dx%d.png" % [capture_prefix,size.x,size.y]) == OK, "Capture complete care screen")
			check(view.world_viewport.get_texture().get_image().save_png("/tmp/%s-world-%dx%d.png" % [capture_prefix,size.x,size.y]) == OK, "Capture care world")
	check(game.state == baseline, "Camera/presentation/captures never mutate the save")
	care.habitat.effects.sample_effect("pet", 0.25)
	care.habitat._sync_care_effects_3d()
	check(care.habitat._effects_card_3d.visible and care.habitat._effects_card_3d.billboard == BaseMaterial3D.BILLBOARD_ENABLED and not care.habitat._effects_card_3d.no_depth_test, "Care hearts remain visible in the depth-tested 3D world")
	care.habitat.begin_edit()
	check(view._debug_root.get_node("CareGrid").visible, "Decorating exposes the ground grid in 3D")
	care.habitat.end_edit()
	check(not view._debug_root.get_node("CareGrid").visible, "Leaving decoration editing hides the grid")
	if "--capture" in OS.get_cmdline_user_args():
		for frame: int in 4:
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/tmp/%s-pet.png" % capture_prefix)
		await check_billboard_pixels()
	if "--interactive" in OS.get_cmdline_user_args() and failures == 0:
		care.habitat.effects.clear_effect()
		care.habitat.set_process(true)
		game.set_process(true)
		root.content_scale_size = Vector2i(390,844)
		root.size = Vector2i(390,844)
		print("FOLIAGE_REVIEW_READY: isolated save; compiled art is NOT promoted")
		return
	care.free()
	current_scene = null
	print("%s: %d care reference checks; %d failures" % ["PASS" if failures==0 else "FAIL",checks,failures])
	quit(0 if failures==0 else 1)


func check_billboard_pixels() -> void:
	# Test actual rendered pixels, not merely the CPU helper or a green flag.
	# A Y-only billboard or fixed-tilt quad foreshortens this square and fails.
	var viewport := SubViewport.new()
	viewport.size = Vector2i(160,160)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var camera := Camera3D.new()
	camera.current = true
	camera.fov = 40.0
	viewport.add_child(camera)
	var pixels := Image.create(8,8,false,Image.FORMAT_RGBA8)
	pixels.fill(Color.MAGENTA)
	var card := Sprite3D.new()
	card.texture = ImageTexture.create_from_image(pixels)
	card.pixel_size = 0.2
	card.shaded = false
	ScreenAlignedSprite.apply(card)
	viewport.add_child(card)
	for pitch: float in [25.0,35.0,50.0]:
		for yaw: float in [-30.0,0.0,30.0]:
			var p := deg_to_rad(pitch)
			var y := deg_to_rad(yaw)
			camera.position = Vector3(sin(y)*cos(p),sin(p),cos(y)*cos(p))*7.0
			camera.look_at(Vector3.ZERO)
			for frame: int in 4:
				await process_frame
			await RenderingServer.frame_post_draw
			var rendered := viewport.get_texture().get_image()
			var low := Vector2i(160,160)
			var high := Vector2i(-1,-1)
			for row: int in 160:
				for col: int in 160:
					var color := rendered.get_pixel(col,row)
					if color.r>0.8 and color.b>0.8 and color.g<0.1:
						low = low.min(Vector2i(col,row))
						high = high.max(Vector2i(col,row))
			var extent := high-low+Vector2i.ONE
			check(extent.x>20 and absi(extent.x-extent.y)<=1, "Rendered square stays unforeshortened at pitch %s/yaw %s: %s" % [pitch,yaw,extent])
	viewport.free()
