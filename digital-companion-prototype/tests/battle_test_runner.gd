extends SceneTree

const Rules = preload("res://scripts/core/care_rules.gd")
const Repository = preload("res://scripts/core/save_repository.gd")
const Sim = preload("res://scripts/battle/battle_simulator.gd")
const Playback = preload("res://scripts/battle/battle_playback_model.gd")
const Game = preload("res://scripts/core/game_state.gd")
const FailingRepository = preload("res://tests/promotion_failure_save_repository.gd")
var _checks := 0
var _failures := 0


func _initialize() -> void:
	_test_start_and_abandon()
	_test_commands_and_focus()
	_test_successful_completion_and_reload()
	_test_failed_completion_retry()
	_test_render_accumulators()
	_test_playback()
	_test_shared_contracts()
	print("%s: %d live battle integration checks" % ["PASS" if _failures == 0 else "FAIL", _checks])
	quit(0 if _failures == 0 else 1)


func _game(label: String, isolated: bool = false) -> Node:
	var game := Game.new()
	game.state = Rules.make_new_state(Time.get_unix_time_from_system(), "Earnest")
	game._repository = Repository.new("/tmp/battle-v3-test-%s-%d.json" % [label, Time.get_ticks_usec()])
	game._repository.clear()
	game.isolated_mode = isolated
	return game


func _cleanup(game: Node) -> void:
	game._repository.clear()
	game.free()


func _complete(game: Node, max_ticks: int = 120) -> void:
	# Small synthetic fixtures exercise the same terminal transition as 3600 ticks.
	# The production entrypoint always uses BattleSimulator.DEFAULT_MAX_TICKS.
	game.active_battle_result.max_ticks = max_ticks
	while not game.active_battle_result.complete:
		game.advance_training_battle()


func _test_start_and_abandon() -> void:
	var game := _game("launch")
	var before := JSON.stringify(game.state)
	var started: Dictionary = game.start_training_battle(8080)
	_check(started.ok and started.tick == 0 and not started.complete and started.result.is_empty(), "start exposes an uncompleted tick-zero session")
	_check(JSON.stringify(game.state) == before and not FileAccess.file_exists(game._repository.primary_path), "starting neither awards nor writes care progress")
	_check(started.battle_id == Rules.make_battle_id(game.state, 8080) and started.battle_id.begins_with("battle-v2-"), "new sessions use versioned v2 reward identity")
	_check(started.arena.assetId == "arena-rootbound-glade" and started.arena.regionId == "green-shade" and started.arena.ground.width == 360, "default training arena uses the active Green Shade contextual identity")
	_check(started.content_revisions.visuals.has_all(["player", "training_opponent"]), "both fighter artwork revisions pinned at start")
	_check(not game.start_training_battle(9).ok, "a live session blocks an overlapping match")
	_check(not game.finish_training_battle().ok, "uncompleted session cannot receive a reward")
	game.advance_training_battle()
	_check(game.clear_active_battle() and game.get_active_battle().is_empty(), "unfinished match may be abandoned")
	_check(JSON.stringify(game.state) == before and game.state.battle.completed_battle_ids.is_empty(), "abandonment grants no reward or processed ID")
	_check(not game.start_training_battle(4, "../../bad").ok and not game.start_training_battle(4, "missing-arena").ok, "unknown and escaping arena identifiers rejected")
	_check(game.start_training_battle(4, "graybox").ok, "simple test arena remains selectable")
	_cleanup(game)


func _test_commands_and_focus() -> void:
	var game := _game("commands")
	game.start_training_battle(3, "graybox")
	_check(not game.queue_battle_order("teleport").ok, "unsupported coaching order rejected")
	var queued: Dictionary = game.queue_battle_order("keep_distance")
	_check(queued.ok and queued.tick == 1 and game.active_battle_result.commands.is_empty(), "order queued for next authoritative tick")
	game._notification(MainLoop.NOTIFICATION_APPLICATION_FOCUS_OUT)
	game.advance_training_battle()
	_check(game.battle_paused and game.active_battle_result.tick == 0, "focus loss pauses simulation instead of accumulating battle time")
	_check(not game.queue_battle_order("attack").ok, "paused battle rejects new orders")
	game._notification(MainLoop.NOTIFICATION_APPLICATION_FOCUS_IN)
	game.advance_training_battle()
	_check(not game.battle_paused and game.active_battle_result.tick == 1 and game.active_battle_result.commands.size() == 1, "focus return resumes at one tick with original queued order")
	game.queue_battle_order("defend")
	game.queue_battle_order("attack")
	game.advance_training_battle()
	_check(game.active_battle_result.commands.size() == 3 and game.active_battle_result.commands[1].tick == 2 and game.active_battle_result.commands[2].order == "attack", "same-tick orders retain submission order")
	game._notification(MainLoop.NOTIFICATION_APPLICATION_PAUSED)
	_check(game.battle_paused, "application pause pauses combat")
	game._notification(MainLoop.NOTIFICATION_APPLICATION_RESUMED)
	_check(not game.battle_paused, "application resume releases combat pause")
	game.clear_active_battle()
	game.start_training_battle(3, "graybox")
	game.advance_training_battle()
	_check(game.active_battle_result.commands.is_empty(), "abandoned match commands cannot leak into its replacement")
	_cleanup(game)


func _test_successful_completion_and_reload() -> void:
	var game := _game("settle")
	game.start_training_battle(42, "graybox")
	game.state.care.hunger = 31.0
	game.state.care.happiness = 63.0
	game.state.care.bond = 17.0
	game.state.identity.companion_name = "Changed During Battle"
	_complete(game)
	_check(game.active_battle_result.complete and game.active_battle_result.reward_saved, "terminal tick atomically settles its reward")
	_check(game.state.care.hunger == 31.0 and game.state.care.happiness == 63.0 and game.state.identity.companion_name == "Changed During Battle", "settlement preserves care and identity changes since battle start")
	_check(game.state.care.bond == 18.0 and game.state.battle.training_points == 2, "draw applies modest reward to latest bond state")
	var battle_id: String = game.active_battle_result.battle_id
	var loaded: Dictionary = game._repository.load_state()
	_check(loaded.ok and loaded.state.battle.completed_battle_ids == [battle_id] and loaded.state.care.bond == 18.0, "reward and exact completed ID survive reload together")
	var before := JSON.stringify(game.state)
	var duplicate: Dictionary = game.finish_training_battle()
	_check(duplicate.ok and not duplicate.awarded and JSON.stringify(game.state) == before, "repeated completion is a stable no-op")
	var claimed := Rules.apply_battle_reward(loaded.state, battle_id, "draw")
	_check(not claimed.awarded and claimed.state == loaded.state, "reloaded save rejects duplicate reward")
	var snapshot: Dictionary = game.get_active_battle()
	snapshot.actors.player.hp = 0
	_check(game.active_battle_result.actors.player.hp != 0, "status snapshots cannot mutate live actor data")
	_check(not game.queue_battle_order("attack").ok and game.advance_training_battle().is_empty(), "completed battle cannot be commanded or advanced")
	_check(game.clear_active_battle(), "durably completed battle may be left")
	_check(game.start_training_battle(42, "graybox").battle_id != battle_id, "next completed serial yields a distinct battle identity")
	_cleanup(game)


func _test_failed_completion_retry() -> void:
	var game := _game("retry")
	_check(game.save_now(), "retry fixture saves a clean prebattle baseline")
	var path: String = game._repository.primary_path
	game._repository = FailingRepository.new(path)
	_check(game.start_training_battle(6161, "graybox").ok, "unwritable completion does not pre-resolve or prevent live start")
	game.state.care.hunger = 44.0
	game.state.care.bond = 9.0
	_complete(game, 90)
	_check(game.active_battle_result.complete and not game.active_battle_result.reward_saved and not game.active_battle_result.settlement_error.is_empty(), "failed terminal save retains a retryable completed session")
	_check(game.state.care.hunger == 44.0 and game.state.care.bond == 9.0 and game.state.battle.completed_battle_ids.is_empty(), "failed settlement rolls back only reward, preserving newest care")
	_check(not game.clear_active_battle() and not game.start_training_battle(8).ok, "unsaved completed reward cannot be silently discarded by navigation or a new match")
	_check(not FileAccess.file_exists(game._repository.temp_path), "failed staged promotion leaves no recoverable reward candidate")
	var baseline := Repository.new(path).load_state()
	_check(baseline.ok and baseline.state.battle.completed_battle_ids.is_empty(), "reload does not resurrect an uncommitted reward")
	game.state.care.happiness = 28.0
	var retried: Dictionary = game.finish_training_battle()
	_check(retried.ok and retried.awarded and game.active_battle_result.reward_saved, "explicit retry settles the same completed match once")
	_check(game.state.care.hunger == 44.0 and game.state.care.happiness == 28.0 and game.state.care.bond == 10.0, "retry applies reward to care changes made after the failure")
	var loaded: Dictionary = Repository.new(path).load_state()
	_check(loaded.state.battle.completed_battle_ids.size() == 1 and loaded.state.battle.next_serial == 2 and loaded.state.care.bond == 10.0, "retry durably commits exactly one ID, serial and reward")
	_check(not game.finish_training_battle().awarded, "successful retry cannot award again")
	_cleanup(game)


func _live_at_fps(fps: int) -> Dictionary:
	var game := _game("fps-%d" % fps, true)
	game.start_training_battle(8181, "graybox")
	game.active_battle_result.max_ticks = 300
	var accumulator := 0.0
	var frames := 0
	while not game.active_battle_result.complete and frames < fps * 11:
		accumulator += 1.0 / float(fps)
		while accumulator + 0.000000001 >= 1.0 / 30.0 and not game.active_battle_result.complete:
			accumulator = maxf(0.0, accumulator - 1.0 / 30.0)
			var tick: int = game.active_battle_result.tick + 1
			if tick == 40:
				game.queue_battle_command({"kind": "order", "order": "keep_distance", "command_id": "fps-order-40"})
			elif tick == 160:
				game.queue_battle_command({"kind": "order", "order": "attack", "command_id": "fps-order-160"})
			game.advance_training_battle()
		frames += 1
	var result: Dictionary = {"record": Sim.replay_record(game.active_battle_result), "actors": game.active_battle_result.actors.duplicate(true), "log": game.active_battle_result.log.duplicate(true), "result": game.active_battle_result.result.duplicate(true)}
	_cleanup(game)
	return result


func _test_render_accumulators() -> void:
	var expected := JSON.stringify(_live_at_fps(30))
	_check(JSON.stringify(_live_at_fps(60)) == expected, "actual60 FPS accumulator preserves30 Hz commands and outcomes")
	_check(JSON.stringify(_live_at_fps(144)) == expected, "actual144 FPS accumulator preserves30 Hz commands and outcomes")


func _test_playback() -> void:
	var game := _game("replay", true)
	game.start_training_battle(9191, "graybox")
	game.queue_battle_order("keep_distance")
	_complete(game, 450)
	var source: Dictionary = game.get_active_battle()
	var source_bytes := JSON.stringify(source)
	var care_bytes := JSON.stringify(game.state)
	var expected_events: String = JSON.stringify(source.log)
	for fps: int in [30, 60, 144]:
		var replay := Playback.new()
		replay.setup(source)
		_check(replay.error.is_empty() and replay.get_session().tick == 0, "replay%d FPS reconstructs from tick zero" % fps)
		var emitted: Array = []
		while not replay.is_complete():
			emitted.append_array(replay.advance(1.0 / fps))
		_check(JSON.stringify(emitted) == expected_events and replay.get_session().result == source.result, "replay%d FPS reproduces command-driven event stream and result" % fps)
		_check(replay.consumed_event_count() == source.log.size(), "replay%d FPS event count includes initial event exactly once" % fps)
	var fast := Playback.new()
	fast.setup(source)
	_check(fast.cycle_speed() == 2 and fast.cycle_speed() == 4 and fast.current_speed() == 4, "replay speed controls cycle1x2x4x")
	var fast_events: Array = []
	while not fast.is_complete():
		fast_events.append_array(fast.advance(0.1))
	_check(JSON.stringify(fast_events) == expected_events, "accelerated replay preserves full event stream")
	var skipped := Playback.new()
	skipped.setup(source)
	_check(JSON.stringify(skipped.skip_to_end()) == expected_events and skipped.is_complete(), "skip simulates recorded inputs through exact terminal state")
	_check(JSON.stringify(source) == source_bytes and JSON.stringify(game.state) == care_bytes, "replays never mutate source session or award additional care rewards")
	_check(JSON.stringify(skipped.source_result()) == source_bytes, "source_result preserves frozen completed input and reward receipt")
	var live: Dictionary = game.start_training_battle(5, "graybox")
	skipped.setup(live)
	_check(not skipped.error.is_empty() and skipped.get_session().is_empty(), "live session cannot be passed off as a completed replay")
	var forged := source.duplicate(true)
	forged.result.outcome = "win"
	skipped.setup(forged)
	_check(not skipped.error.is_empty(), "replay rejects a result inconsistent with recorded inputs")
	_cleanup(game)


func _test_shared_contracts() -> void:
	var state := Rules.make_new_state(1000.0)
	state.battle_profile.merge({"hp": Rules.BATTLE_MAX_HP, "mp": Rules.BATTLE_MAX_MP, "offense": Rules.BATTLE_MAX_STAT, "defense": Rules.BATTLE_MAX_STAT, "speed": Rules.BATTLE_MAX_STAT, "brains": Rules.BATTLE_MAX_STAT}, true)
	_check(Rules.state_is_valid(state) and Sim.validate_snapshot(Sim.player_snapshot_from_state(state)).is_empty(), "persisted maximum stat bounds match spatial snapshots")
	for outcome: String in ["win", "draw", "loss"]:
		var rewarded := Rules.apply_battle_reward(Rules.make_new_state(1000.0), "reward-" + outcome, outcome)
		_check(rewarded.awarded and rewarded.reward.training_points == {"win": 3, "draw": 2, "loss": 1}[outcome] and Rules.state_is_valid(rewarded.state), "unchanged%s reward contract and save schema" % outcome)
	_check(Game.is_review_launch(PackedStringArray(["res://scenes/asset_review_scene.tscn"])), "direct review startup remains isolated before repository access")


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("not ok %d - %s" % [_checks, message])
