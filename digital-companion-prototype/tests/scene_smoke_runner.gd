extends Node

var _checks := 0
var _failures := 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	await get_tree().process_frame
	_check(GameState.isolated_mode, "scene tests run without reading/writing real companion progress")
	if not GameState.isolated_mode:
		get_tree().quit(1)
		return
	var original_state := GameState.get_state()
	GameState.clear_active_battle()
	GameState.battle_paused = false
	var started := GameState.start_training_battle(2468, "forest")
	_check(started.ok and started.tick == 0 and not started.complete, "training begins as an unfinished live session")
	_check(GameState.get_state() == original_state, "starting battle has not awarded or saved a result")
	var scene_resource := load("res://scenes/battle_scene.tscn") as PackedScene
	_check(scene_resource != null, "live battle scene loads")
	var battle_scene := scene_resource.instantiate()
	get_tree().root.add_child(battle_scene)
	battle_scene.set_process(false)
	await get_tree().process_frame
	_check(battle_scene.order_buttons.size() == 4 and not battle_scene.skip_button.visible and not battle_scene.speed_button.visible, "live UI offers broad orders but no Skip or Speed")
	_check(battle_scene._environment_enabled and battle_scene.environment_view.environment_manifest.get("assetId", "") == started.arena.environment.assetId, "isolated live battle activates only its pinned 3D Environment fixture")
	var fighter_art_loaded: bool = bool(battle_scene.environment_view.fighter_presentations.values().all(func(presentation: CompanionPresentation3D) -> bool: return presentation.sprite.sprite_frames != null)) if battle_scene._environment_enabled else (battle_scene.player_avatar.sprite.sprite_frames != null and battle_scene.opponent_avatar.sprite.sprite_frames != null)
	_check(fighter_art_loaded, "both fighters load their pinned artwork in the active 2D/3D presentation")
	battle_scene._process(0.1)
	_check(GameState.active_battle_result.tick >= 2, "frame accumulator advances live 30Hz simulation")
	battle_scene._give_order("keep_distance")
	battle_scene._process(0.1)
	_check(GameState.active_battle_result.commands.size() == 1 and GameState.active_battle_result.commands[0].order == "keep_distance", "broad UI order is recorded on a simulation tick")
	var before: int = GameState.active_battle_result.tick
	GameState.battle_paused = true
	battle_scene._process(10)
	_check(GameState.active_battle_result.tick == before and battle_scene._accumulator == 0 and battle_scene.clock_label.text == "PAUSED", "focus pause stops simulation and discards stale frame time")
	GameState.battle_paused = false
	battle_scene._process(1.0 / 120)
	_check(GameState.active_battle_result.tick == before, "focus return does not fast-forward missed time")
	battle_scene._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	battle_scene._notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	battle_scene._process(10)
	_check(GameState.active_battle_result.tick == before, "suspension with both focus events between frames discards stale live delta")
	battle_scene._skip()
	_check(GameState.active_battle_result.tick == before, "calling Skip cannot fast-forward a live battle")
	while not GameState.active_battle_result.complete:
		GameState.advance_training_battle()
	battle_scene._process(0)
	_check(GameState.active_battle_result.reward_saved and battle_scene.return_button.visible and not battle_scene.return_button.disabled, "completion settles and enables safe return")
	_check(battle_scene.replay_button.visible and not battle_scene.result_label.text.is_empty(), "completed battle exposes result and replay")
	var settled_state := GameState.get_state()
	var settled_result: Dictionary = GameState.active_battle_result.result.duplicate(true)
	battle_scene._start_replay()
	_check(battle_scene._is_replay and battle_scene.speed_button.visible and battle_scene.skip_button.visible, "Speed and Skip become available only in read-only replay")
	var replay_tick: int = battle_scene.playback.get_session().tick
	battle_scene._notification(NOTIFICATION_APPLICATION_PAUSED)
	battle_scene._notification(NOTIFICATION_APPLICATION_RESUMED)
	battle_scene._process(10)
	_check(battle_scene.playback.get_session().tick == replay_tick, "suspension between frames cannot fast-forward replay")
	battle_scene._audio.played_events.clear()
	for frame: int in 300:
		battle_scene._process(1.0 / 30)
		if not battle_scene._audio.played_events.is_empty():
			break
	_check(not battle_scene._audio.played_events.is_empty(), "normally advancing replay retains event audio")
	var replay_sounds: Array = battle_scene._audio.played_events.duplicate()
	battle_scene._cycle_speed()
	battle_scene._skip()
	_check(battle_scene._audio.played_events == replay_sounds, "Replay Skip adds no sounds for discarded history")
	_check(battle_scene._audio._voices.all(func(voice: AudioStreamPlayer) -> bool: return voice.stream == null and not voice.playing), "Replay Skip stops every current cue")
	_check(battle_scene.playback.is_complete() and battle_scene.playback.get_session().result == settled_result, "replay reaches identical recorded outcome")
	_check(GameState.get_state() == settled_state and GameState.active_battle_result.result == settled_result, "replay cannot award again or alter live result")
	var source_battle: Dictionary = battle_scene.battle
	battle_scene.battle = source_battle.duplicate(true)
	battle_scene.battle.reward_saved = false
	battle_scene._show_result()
	_check(battle_scene.retry_button.visible and battle_scene.return_button.disabled, "pending save blocks return and exposes Retry Save")
	battle_scene.battle = source_battle
	battle_scene._show_result()
	await _drain_audio(battle_scene._audio)
	var runner_scene := get_tree().current_scene
	get_tree().current_scene = battle_scene
	battle_scene._return_to_care()
	await get_tree().process_frame
	await get_tree().process_frame
	var care_scene := get_tree().current_scene
	_check(GameState.active_battle_result.is_empty() and care_scene != null and care_scene.has_method("_start_battle"), "Return leaves completed arena and opens care scene")
	get_tree().current_scene = runner_scene
	if care_scene != null:
		care_scene.free()
	var review_resource := load("res://scenes/asset_review_scene.tscn") as PackedScene
	var review := review_resource.instantiate()
	get_tree().root.add_child(review)
	await get_tree().process_frame
	_check(review.has_method("load_candidate") and GameState.isolated_mode, "asset review scene loads under isolated autoload")
	review.free()
	get_tree().root.content_scale_size = Vector2i(390, 844)
	await _test_render_rates(scene_resource, original_state)
	GameState.state = original_state
	print("%s: %d scene smoke checks" % ["PASS" if _failures == 0 else "FAIL", _checks])
	get_tree().quit(0 if _failures == 0 else 1)


func _test_render_rates(scene_resource: PackedScene, original_state: Dictionary) -> void:
	var baseline := ""
	for fps: int in [30, 60, 144]:
		GameState.clear_active_battle()
		GameState.state = original_state.duplicate(true)
		GameState.battle_paused = false
		GameState.start_training_battle(2468, "forest")
		var scene := scene_resource.instantiate()
		get_tree().root.add_child(scene)
		scene.set_process(false)
		var first_order := false
		var second_order := false
		for frame: int in fps * 121:
			if GameState.active_battle_result.complete:
				break
			if GameState.active_battle_result.tick >= 60 and not first_order:
				# UI order handling is covered above. Pin input identity here so the
				# exact replay comparison varies only render cadence, not random IDs.
				GameState.queue_battle_command({"kind": "order", "order": "keep_distance", "command_id": "scene-fps-order-61"})
				first_order = true
			if GameState.active_battle_result.tick >= 120 and not second_order:
				GameState.queue_battle_command({"kind": "order", "order": "attack", "command_id": "scene-fps-order-121"})
				second_order = true
			scene._process(1.0 / fps)
			if frame == fps * 10 - 1:
				_check(GameState.active_battle_result.complete or GameState.active_battle_result.tick == 300, "actual scene %.0f FPS advances exactly300ticks in10seconds" % fps)
		var result: Dictionary = GameState.active_battle_result
		_check(result.complete and result.reward_saved, "actual scene %d FPS reaches settled completion" % fps)
		var fingerprint := JSON.stringify({"log": result.log, "result": result.result, "commands": result.commands, "actors": result.actors})
		if baseline.is_empty():
			baseline = fingerprint
		else:
			_check(fingerprint == baseline, "actual scene %d FPS preserves exact command ticks, log and outcome" % fps)
		await _drain_audio(scene._audio)
		scene.free()
	GameState.clear_active_battle()


func _drain_audio(audio: BattleEventAudio) -> void:
	# Whole bouts run synchronously here. A fixed timer does not establish that
	# the audio mixer caught up, so track actual WAV ownership: every pending
	# playback retains its WAV. Use wall time to bound the cleanup assertion.
	var streams: Array = audio._tones.values().map(func(stream: AudioStreamWAV) -> WeakRef: return weakref(stream))
	audio.stop_all()
	audio._tones.clear()
	var deadline := Time.get_ticks_msec() + 2000
	while streams.any(func(stream: WeakRef) -> bool: return stream.get_ref() != null) and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	var retained := streams.filter(func(stream: WeakRef) -> bool: return stream.get_ref() != null).size()
	_check(retained == 0, "stopped battle audio releases all mixer references before scene teardown (%d WAVs retained)" % retained)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("FAIL: " + message)
