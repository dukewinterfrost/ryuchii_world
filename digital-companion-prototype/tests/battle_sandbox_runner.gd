extends Node

var checks := 0
var failures := 0

func _ready() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func run() -> void:
	var game := get_node("/root/GameState")
	game.set_process(false)
	check(game.isolated_mode, "sandbox test starts without real save access")
	var live_state := JSON.stringify(game.state)
	var live_battle := JSON.stringify(game.active_battle_result)
	var live_tables := JSON.stringify(CombatContent.defaults())
	var sandbox := BattleSandbox.new()
	sandbox.mob_fixture = -1
	add_child(sandbox)
	sandbox.set_process(false)
	await get_tree().process_frame
	check(sandbox._forest_enabled and sandbox._forest.fighter_presentations.size() == 2, "sandbox uses home forest with two 3D fighters")
	check(sandbox.session.get("ok", false) and sandbox.session.tick == 0, "isolated sandbox starts at tick zero")
	check(sandbox.session.fighter_order.size() == 2 and sandbox._avatars.size() == 2, "1v1 fixture has two visible actors")
	check(sandbox.session.initial_supplies.barrier == BattleSimulator.MAX_SUPPLIES, "test inventory cannot be exhausted in any bounded match")
	check(sandbox._arena.debug_overlays and "Effective timing" in sandbox._timings.text and "cast 24 / 0.800" in sandbox._timings.text, "geometry overlay and effective quantized tuning are available")
	# A paused view still needs fresh meter draw commands after the arena refits.
	await get_tree().process_frame
	var meter_draws := [0]
	sandbox._meters.draw.connect(func() -> void: meter_draws[0] += 1)
	var original_stage_size := sandbox._stage.size
	sandbox._stage.size = original_stage_size + Vector2(0, 20)
	await get_tree().process_frame
	await get_tree().process_frame
	check(meter_draws[0] > 0 and sandbox.session.tick == 0, "paused stage resize redraws fighter meters without advancing simulation")
	sandbox._stage.size = original_stage_size
	await get_tree().process_frame
	if "--capture-sandbox" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
		sandbox._render()
		sandbox._forest.frame_session(sandbox.session, 1.0, true)
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("/tmp/ryuchii-sandbox-1v1.png")
	sandbox.focus_paused = false
	check(sandbox.request({"kind": "defense_request", "defense": "guard"}).ok, "sandbox accepts manual defense")
	sandbox._process(1.0 / 30.0)
	check(sandbox.session.actors.player.action == "guard" and sandbox.session.commands.size() == 1, "sandbox records accepted commands on fixed tick")
	sandbox.restart(false)
	for tick: int in 180:
		sandbox._process(1.0 / 30.0)
	var expected := JSON.stringify(sandbox.session)
	sandbox.restart(false)
	for tick: int in 180:
		sandbox._process(1.0 / 30.0)
	check(JSON.stringify(sandbox.session) == expected, "same seed restart reproduces entire tactical sequence")
	var prior_seed := sandbox.seed_value
	sandbox.restart(true)
	check(sandbox.seed_value != prior_seed and sandbox.session.tick == 0, "new seed starts a fresh independent simulation")
	sandbox._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	sandbox._process(12.0)
	check(sandbox.session.tick == 0 and not sandbox.request({"kind": "defense_request", "defense": "guard"}).ok, "focus loss discards elapsed time and blocks input")
	sandbox._notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	sandbox._process(1.0 / 30.0)
	check(sandbox.session.tick == 1, "focus return resumes with no catch-up backlog")
	var directory := "/tmp/ryuchii-sandbox-tables-%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(directory)
	for table: String in ["moves", "items", "natures", "tuning"]:
		DirAccess.copy_absolute(ProjectSettings.globalize_path("res://assets/combat/%s.csv" % table), directory.path_join(table + ".csv"))
	sandbox.table_directory = directory
	var path := directory.path_join("moves.csv")
	var original := FileAccess.get_file_as_string(path)
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(original + "\ninvalid,row\n")
	file.close()
	var config_before := JSON.stringify(sandbox.configuration)
	var session_before := JSON.stringify(sandbox.session)
	check(not sandbox.reload_tables().ok and not sandbox.last_error.is_empty(), "bad table reload reports authoring error")
	check(JSON.stringify(sandbox.configuration) == config_before and JSON.stringify(sandbox.session) == session_before, "invalid reload preserves last valid configuration and running battle")
	file = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(original.replace("Pepper Breath", "Sandbox Breath"))
	file.close()
	sandbox.stat_overrides.allies.hp = 0
	check(CombatContent.load_tables(directory).ok and not sandbox.reload_tables().ok, "valid CSV with an invalid fixture override is rejected safely")
	check(JSON.stringify(sandbox.configuration) == config_before and JSON.stringify(sandbox.session) == session_before, "fixture failure also rolls back configuration transactionally")
	sandbox.stat_overrides.allies.hp = BattleSandbox.STAT_DEFAULTS.hp
	file = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(original.replace("Pepper Breath", "Sandbox Breath"))
	file.close()
	check(sandbox.reload_tables().ok and sandbox.session.tick == 0, "valid reload starts a fresh test battle")
	check(sandbox.configuration.moves.pepper_breath.name == "Sandbox Breath" and JSON.stringify(CombatContent.defaults()) == live_tables, "sandbox table reload does not replace live care/loadout defaults")
	check(JSON.stringify(sandbox.configuration) != config_before, "reloaded session pins edited content")
	sandbox.team_size = 3
	sandbox.stat_overrides.allies.speed = 90
	check(sandbox.restart(false).ok and sandbox.session.fighter_order.size() == 6 and sandbox._avatars.size() == 6, "large 3v3 fixture creates every fighter")
	check(sandbox.session.arena.ground.width == 1000 and sandbox.session.fighters[0].stats.speed == 90, "large arena and stat overrides apply on restart")
	for tick: int in 180:
		sandbox._process(1.0 / 30.0)
	var teams_valid := true
	for actor: Dictionary in sandbox.session.actors.values():
		if not String(actor.target_id).is_empty():
			teams_valid = teams_valid and actor.team_id != sandbox.session.actors[actor.target_id].team_id
	check(teams_valid, "all sandbox targets belong to hostile teams")
	if "--capture-sandbox" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("/tmp/ryuchii-sandbox-3v3.png")
		sandbox._settings.visible = true
		sandbox._stage.visible = false
		sandbox._render()
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("/tmp/ryuchii-sandbox-tuning.png")
	check(JSON.stringify(game.state) == live_state and JSON.stringify(game.active_battle_result) == live_battle, "sandbox commands and battles never change live care, inventory or rewards")
	for table: String in ["moves", "items", "natures", "tuning"]:
		DirAccess.remove_absolute(directory.path_join(table + ".csv"))
	DirAccess.remove_absolute(directory)
	sandbox.table_directory = CombatContent.DIRECTORY
	check(sandbox.reload_tables().ok, "Excel balance reloads into sandbox")
	for fixture_id: int in range(7):
		sandbox.mob_fixture = fixture_id
		check(sandbox.restart(false).ok, "mob fixture starts")
		check(sandbox.session.fighter_order.size() == (4 if fixture_id in [1, 2, 3] else 2), "mob fixture size")
	check(JSON.stringify(game.state) == live_state, "mob sandbox remains isolated")
	sandbox.queue_free()
	await get_tree().process_frame
	print("Battle sandbox: %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
