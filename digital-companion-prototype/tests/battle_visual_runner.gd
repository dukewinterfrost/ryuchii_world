extends SceneTree

## Actual GPU captures of an isolated seeded battle; no artwork approvals.

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("Visual runner requires a renderer, plus --test-mode --battle-demo")
		quit(1)
		return
	var game := root.get_node("GameState")
	if not game.isolated_mode:
		printerr("Visual runner refuses non-isolated GameState")
		quit(1)
		return
	root.content_scale_size = Vector2i(390, 844)
	root.size = Vector2i(390, 844)
	var scene := (load("res://scenes/battle_scene.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	scene.set_process(false)
	game.battle_paused = false
	await process_frame
	scene._give_order("keep_distance")
	var captured_fire_hit := false
	while not game.active_battle_result.complete:
		scene._process(1.0 / 30)
		if game.active_battle_result.tick > 200 and not game.active_battle_result.projectiles.is_empty():
			break
	await _capture("live-battle")
	scene._geometry.button_pressed = true
	await _capture("live-battle-geometry")
	scene._geometry.button_pressed = false
	while not game.active_battle_result.complete:
		scene._process(1.0 / 30)
		if not captured_fire_hit and scene._environment_enabled:
			for record: Dictionary in scene.environment_view._effect_records.values():
				if record.effect == "hit_fire":
					scene._process(0.1)
					await _capture("battle-fire-impact")
					captured_fire_hit = true
					break
	scene._process(0)
	await _capture("battle-result")
	scene._start_replay()
	scene._cycle_speed()
	scene._process(0)
	scene._process(0.5)
	await _capture("battle-replay")
	scene._skip()
	await _capture("battle-replay-result")
	scene.free()
	quit(0)


func _capture(name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var folder := ProjectSettings.globalize_path("res://work/sprites/qa")
	DirAccess.make_dir_recursive_absolute(folder)
	var destination := folder.path_join(name + ".png")
	root.get_texture().get_image().save_png(destination)
	print(destination)
