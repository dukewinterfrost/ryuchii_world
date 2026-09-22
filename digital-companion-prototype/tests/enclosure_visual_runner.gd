extends SceneTree
func _initialize() -> void:
	run.call_deferred()
func run() -> void:
	var game := root.get_node("GameState")
	if not game.isolated_mode:
		quit(1)
		return
	game.set_process(false)
	game.state = CareRules.make_new_state(1000)
	game.state.care.fatigue = 60
	var draft: Dictionary = game.state.habitat.duplicate(true)
	draft.items = [{"instance_id":"potty","item_id":"digi_potty","x":13,"y":23,"rotation":0},{"instance_id":"fire","item_id":"campfire","x":23,"y":23,"rotation":0},{"instance_id":"pond","item_id":"pond","x":16,"y":14,"rotation":0}]
	var built := EnclosureRules.build(game.state, draft)
	if not built.ok: push_error(built.error); quit(1); return
	game.state = built.state
	game._home_package = HabitatAssetLibrary.resolve_region("green-shade", false)
	var care := (load("res://scenes/care_scene.tscn") as PackedScene).instantiate()
	root.add_child(care)
	current_scene = care
	care.habitat.set_process(false)
	root.content_scale_size = Vector2i(390,844)
	root.size = Vector2i(390,844)
	care.habitat.set_zoom(0.66)
	for frame: int in 12: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/tmp/enclosure-play.png")
	care._begin_edit()
	care.habitat.selected_id = "fire"
	care.habitat._refresh_draft()
	for frame: int in 5: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/tmp/enclosure-build.png")
	if care._edit_panel.get_global_rect().end.y > root.size.y or care._apply.get_global_rect().end.y > root.size.y:
		push_error("Build controls extend below the phone viewport")
		quit(1)
		return
	care._end_edit()
	care.habitat.set_process(false)
	care._facility_action("pond")
	var timeout := 0.0
	while float(game.state.care.fatigue) > 35 and timeout < 15:
		care.habitat._focused = true
		care.habitat._process(0.1)
		await process_frame
		timeout += 0.1
	if float(game.state.care.fatigue) != 35:
		push_error("Pond route failed: " + str([game.state.habitat.creature_cell, care.habitat._path, care.dialogue_label.text]))
		quit(1)
		return
	care.habitat.set_process(false)
	care.habitat.configure_region({"region_id": "shellfish-beach", "mode": "fallback-2d"})
	care.habitat.update_snapshot(game.state)
	for frame: int in 5: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/tmp/enclosure-fallback.png")
	print("Enclosure visual: routed pond action, 3D and 2D captures passed")
	care.free()
	current_scene = null
	quit(0)
