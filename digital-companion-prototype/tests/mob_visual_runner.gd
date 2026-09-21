extends Node

var failures := 0
func _ready() -> void:
	run.call_deferred()

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		printerr("FAIL: " + message)

func run() -> void:
	GameState.set_process(false)
	check(GameState.isolated_mode, "isolated save mode")
	if not GameState.isolated_mode: get_tree().quit(1); return
	GameState.state = CareRules.make_new_state(1000)
	GameState.state.battle.mob_wins = 2
	GameState.battle_paused = false
	var started := GameState.start_training_battle(91, "graybox")
	check(started.ok, "mixed encounter starts")
	var scene := preload("res://scenes/battle_scene.tscn").instantiate()
	add_child(scene)
	scene.set_process(false)
	await get_tree().process_frame
	for width: int in [360, 390, 430]:
		get_tree().root.content_scale_size = Vector2i(width, 780)
		get_tree().root.size = Vector2i(width, 780)
		await get_tree().process_frame
		scene._render_frame(1.0)
		check(scene.enemy_cards.size() == 3, "three enemy cards")
		for card: Button in scene.enemy_cards.values():
			check(card.get_rect().end.x <= width, "card fits portrait")
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("/tmp/mobs-%d.png" % width)
	GameState.battle_paused = false
	scene._focus_enemy("enemy_3")
	GameState.advance_training_battle()
	check(GameState.active_battle_result.actors.player.focus_target_id == "enemy_3", "card focuses fairy")
	scene._focus_at_point(scene._enemy_screen_position("enemy_1") - Vector2(0, 18))
	GameState.advance_training_battle()
	check(GameState.active_battle_result.actors.player.focus_target_id == "enemy_1", "sprite focuses slime")
	scene.queue_free()
	await get_tree().process_frame
	GameState.clear_active_battle()
	GameState.start_training_battle(91)
	scene = preload("res://scenes/battle_scene.tscn").instantiate()
	add_child(scene)
	scene.set_process(false)
	await get_tree().process_frame
	scene._render_frame(1.0)
	check(scene._environment_enabled, "mixed encounter uses 3D environment")
	GameState.battle_paused = false
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = scene.environment_view.get_global_transform().affine_inverse() * (scene._enemy_screen_position("enemy_3") - Vector2(0, 18))
	scene._on_field_zoom_input(click)
	GameState.advance_training_battle()
	check(GameState.active_battle_result.actors.player.focus_target_id == "enemy_3", "3D field input focuses fairy")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("/tmp/mobs-3d.png")
	scene.queue_free()
	await get_tree().process_frame
	print("Mob visual controls: %d failures" % failures)
	get_tree().quit(1 if failures else 0)
