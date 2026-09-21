extends SceneTree
var failures := 0
var checks := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(label)
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var game := root.get_node("GameState")
	if not game.isolated_mode: quit(1); return
	game.set_process(false)
	game.state = CareRules.make_new_state(1000)
	var draft: Dictionary = game.state.habitat.duplicate(true)
	draft.items = []
	var places := {"digi_potty":[11,22],"campfire":[23,22],"pond":[16,12],"rug":[17,28],"planter":[27,29]}
	for kind: String in places:
		draft.items.append({"instance_id":kind,"item_id":kind,"x":places[kind][0],"y":places[kind][1],"rotation":0})
	var built := EnclosureRules.build(game.state,draft)
	check(built.ok,"large showcase layout is valid")
	if not built.ok: quit(1); return
	game.state = built.state
	game._home_package = HabitatAssetLibrary.resolve_region("green-shade", false)
	var care := (load("res://scenes/care_scene.tscn") as PackedScene).instantiate()
	root.add_child(care)
	current_scene = care
	care.habitat.set_process(false)
	root.content_scale_size = Vector2i(390,844)
	root.size = Vector2i(390,844)
	for frame: int in 8: await process_frame
	var env: EnvironmentView3D = care.habitat.environment_3d
	env.set_process(false)
	env.day_night.clock.set_process(false)
	for frame: int in 8: await process_frame
	var group: Node3D = care.habitat.care_visuals_3d.get_node("HomeDecor")
	check(group.get_child_count()==5,"all five props use independent layered models")
	for model: Node3D in group.get_children():
		check(model.has_meta("enclosure_model"),"model has semantic identity")
		check(model.get_child_count()>=1,"model contains ground-aligned structure")
	var water: MeshInstance3D = group.find_children("RecessedWater","MeshInstance3D",true,false)[0]
	check(water.get_active_material(0) is ShaderMaterial,"pond water has a dedicated recessed surface")
	var flames: Array[Node] = group.find_children("FlameBetweenLogsAndSpit","Sprite3D",true,false)
	check(flames.size()==1 and flames[0].hframes==4,"campfire reuses the four-frame sprite atlas")
	care.habitat.reduced_motion = true
	care.habitat.update_snapshot(game.state)
	care.habitat._process(0)
	check(water.get_active_material(0).get_shader_parameter("reduced_motion") == true and flames[0].frame == 0,"reduced motion freezes both water and flame")
	for hour: float in [12.0,23.0]:
		env.day_night._apply_sample(TimeOfDayController.sample_time(hour))
		for kind: String in ["all","digi_potty","campfire","pond","rug","planter"]:
			var focus := Vector2(20,23)
			if kind != "all":
				var size: Array = GameDefinitions.DECOR[kind].size
				focus = Vector2(places[kind][0]+size[0]*0.5,places[kind][1]+size[1]*0.5)
			env.set_home_follow(focus*32,true)
			env.set_home_zoom_multiplier(0.62 if kind=="all" else 0.95,true)
			env.advance_camera(10)
			for frame: int in 3: await process_frame
			await RenderingServer.frame_post_draw
			env.world_viewport.get_texture().get_image().save_png("/tmp/enclosure-depth-%s-%s.png" % [kind,"day" if hour==12 else "night"])
			if kind=="pond" and hour==12:
				for reed: Node3D in group.find_children("RaisedReeds*","Sprite3D",true,false): reed.hide()
				await process_frame
				await RenderingServer.frame_post_draw
				env.world_viewport.get_texture().get_image().save_png("/tmp/enclosure-depth-pond-no-reeds.png")
				for reed: Node3D in group.find_children("RaisedReeds*","Sprite3D",true,false): reed.show()
	env.day_night._apply_sample(TimeOfDayController.sample_time(12.0))
	var state_before: Dictionary = game.state.duplicate(true)
	for kind: String in ["digi_potty","campfire","pond"]:
		var size: Array = GameDefinitions.DECOR[kind].size
		var center := Vector2(places[kind][0]+size[0]*0.5,places[kind][1]+size[1]*0.5)
		env.set_home_follow(center*32,true)
		env.set_home_zoom_multiplier(0.95,true)
		env.advance_camera(10)
		for side: int in [-1,1]:
			care.habitat.avatar_3d.set_ground_position((center+Vector2(0,side*(size[1]*0.5+0.55)))*32)
			await process_frame
			await RenderingServer.frame_post_draw
			env.world_viewport.get_texture().get_image().save_png("/tmp/enclosure-depth-%s-actor-%s.png" % [kind,"behind" if side<0 else "front"])
	check(game.state == state_before,"depth and camera review never mutates saved placement")
	care.free()
	current_scene = null
	print("Enclosure depth: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
