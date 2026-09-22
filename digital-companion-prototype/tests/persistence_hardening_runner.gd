extends SceneTree

const CareRulesScript = preload("res://scripts/core/care_rules.gd")
const SaveRepositoryScript = preload("res://scripts/core/save_repository.gd")
const GameStateScript = preload("res://scripts/core/game_state.gd")
const PromotionFailureRepositoryScript = preload("res://tests/promotion_failure_save_repository.gd")

var _checks := 0
var _failures := 0


func _initialize() -> void:
	_test_valid_temp_recovery()
	_test_future_schema_preservation()
	_test_v1_migration()
	_test_v2_battle_migration()
	_test_invalid_typed_state()
	_test_failed_save_timestamp_and_stale_engagement()
	_test_failed_battle_promotion_cannot_resurrect_reward()
	if _failures == 0:
		print("PASS: %d persistence hardening checks" % _checks)
		quit(0)
	else:
		push_error("FAIL: %d of %d persistence hardening checks failed" % [_failures, _checks])
		quit(1)


func _test_valid_temp_recovery() -> void:
	var path := _unique_path("temp-recovery")
	var repository = SaveRepositoryScript.new(path)
	repository.clear()
	var old_state: Dictionary = CareRulesScript.make_new_state(1000.0)
	_check(repository.save_state(old_state), "temp recovery fixture writes its old primary")
	var new_state := old_state.duplicate(true)
	new_state["care"]["bond"] = 27.0
	_check(_write(repository.temp_path, _encode(new_state, CareRulesScript.SAVE_SCHEMA_VERSION)), "validated newer temp fixture is written")
	_check(_write(path, "{broken"), "primary corruption fixture is written")
	var loaded: Dictionary = repository.load_state()
	_check(bool(loaded["ok"]) and bool(loaded["recovered"]), "valid temp recovers a corrupt primary")
	_check(is_equal_approx(float(loaded["state"]["care"]["bond"]), 27.0), "temp recovery selects the complete new generation")
	var reloaded: Dictionary = repository.load_state()
	_check(bool(reloaded["ok"]) and not bool(reloaded["recovered"]), "temp recovery repairs the durable primary")
	repository.clear()


func _test_future_schema_preservation() -> void:
	var path := _unique_path("future")
	var repository = SaveRepositoryScript.new(path)
	repository.clear()
	var state: Dictionary = CareRulesScript.make_new_state(1000.0)
	var future_bytes := _encode(state, CareRulesScript.SAVE_SCHEMA_VERSION + 1)
	_check(_write(path, future_bytes), "future-version fixture is written")
	var loaded: Dictionary = repository.load_state()
	_check(not bool(loaded["ok"]) and bool(loaded["incompatible"]), "future schema is reported as incompatible")
	_check(FileAccess.get_file_as_string(path) == future_bytes, "future primary remains byte-identical after load")
	_check(not repository.save_state(state), "older repository refuses to overwrite future data")
	_check(FileAccess.get_file_as_string(path) == future_bytes, "future primary remains byte-identical after refused save")
	repository.clear()


func _test_v1_migration() -> void:
	var path := _unique_path("migration")
	var repository = SaveRepositoryScript.new(path)
	repository.clear()
	var legacy := _literal_v1_state()
	var legacy_bytes := _encode(legacy, 1)
	_check(_write(path, legacy_bytes), "schema-v1 fixture is written")
	var loaded: Dictionary = repository.load_state()
	_check(bool(loaded["ok"]) and bool(loaded.get("migrated", false)), "schema v1 migrates during load")
	_check(loaded["state"]["care"]["poop_slots"] == [true, true, false], "migration derives stable occupied poop slots")
	_check(loaded["state"]["battle_profile"]["implementation_status"] == "active" and loaded["state"]["battle"]["completed_battle_ids"].is_empty(), "v1 migration composes v2 profile and v3 battle-record defaults")
	var durable: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	_check(durable is Dictionary and int(durable["schemaVersion"]) == CareRulesScript.SAVE_SCHEMA_VERSION, "migration rewrites the primary at the current schema")
	_check(FileAccess.file_exists(repository.backup_path) and FileAccess.get_file_as_string(repository.backup_path) == legacy_bytes, "migration preserves the original v1 generation as backup")
	repository.clear()


func _literal_v1_state() -> Dictionary:
	# Literal historical shape: no poop slot identity, battle profile, or battle
	# record. Keeping this independent from make_new_state prevents modern fields
	# from silently weakening migration coverage.
	return {
		"identity": {
			"player_name": "Tamer",
			"companion_name": "Byte",
			"species_id": "botamon",
			"species_name": "Botamon",
			"stage": "Baby",
			"nature": "Gentle",
		},
		"care": {
			"hunger": 78.0,
			"happiness": 72.0,
			"discipline": 42.0,
			"virus": 0.0,
			"bond": 0.0,
			"weight": 5.0,
			"care_mistakes": 0,
			"poop_count": 2,
			"next_poop_at": 1900.0,
		},
		"progression": {
			"active_seconds": 0.0,
			"stage_actions": {},
			"valid_action_counts": {"feed": 0, "play": 0, "chat": 0, "clean": 0},
			"last_action": "",
			"repeat_streak": 0,
			"evolution_count": 0,
		},
		"meta": {
			"birth_time": 1000.0,
			"last_update_time": 1000.0,
			"last_saved_time": 1000.0,
		},
	}


func _test_v2_battle_migration() -> void:
	var path := _unique_path("battle-migration")
	var repository = SaveRepositoryScript.new(path)
	repository.clear()
	var legacy: Dictionary = _literal_v1_state()
	legacy.care.poop_slots = [true, true, false]
	legacy["battle_profile"] = {"hp": 100, "mp": 60, "offense": 8, "defense": 8, "speed": 8, "brains": 8, "implementation_status": "reserved"}
	_check(_write(path, _encode(legacy, 2)), "schema-v2 care-only fixture is written")
	var loaded: Dictionary = repository.load_state()
	_check(bool(loaded["ok"]) and bool(loaded.get("migrated", false)), "schema v2 migrates into the battle-capable save contract")
	_check(loaded["state"]["battle"]["completed_battle_ids"].is_empty() and loaded["state"]["battle_profile"]["implementation_status"] == "active", "v2 migration initializes battle identity and activates the profile")
	repository.clear()


func _test_invalid_typed_state() -> void:
	var path := _unique_path("invalid")
	var repository = SaveRepositoryScript.new(path)
	repository.clear()
	var invalid: Dictionary = CareRulesScript.make_new_state(1000.0)
	invalid["care"]["hunger"] = "lots"
	_check(_write(path, _encode(invalid, CareRulesScript.SAVE_SCHEMA_VERSION)), "invalid typed fixture is written")
	var loaded: Dictionary = repository.load_state()
	_check(not bool(loaded["ok"]) and not bool(loaded["incompatible"]), "malformed current-schema state is rejected")
	repository.clear()


func _test_failed_save_timestamp_and_stale_engagement() -> void:
	var game_state = GameStateScript.new()
	game_state.state = CareRulesScript.make_new_state(1000.0)
	game_state._repository = SaveRepositoryScript.new("/tmp/missing-%d/save.json" % Time.get_ticks_usec())
	var before := float(game_state.state["meta"]["last_saved_time"])
	_check(not game_state.save_now(), "unwritable save destination reports failure")
	_check(float(game_state.state["meta"]["last_saved_time"]) == before, "failed save does not advance the in-memory timestamp")
	game_state._engagement_seconds_remaining = 30.0
	game_state._notification(MainLoop.NOTIFICATION_APPLICATION_FOCUS_OUT)
	_check(float(game_state._engagement_seconds_remaining) == 0.0, "focus loss clears stale engagement credit")
	game_state.free()


func _test_failed_battle_promotion_cannot_resurrect_reward() -> void:
	var path := _unique_path("battle-promotion-failure")
	var baseline_repository = SaveRepositoryScript.new(path)
	baseline_repository.clear()
	var baseline: Dictionary = CareRulesScript.make_new_state(1000.0, "Calm")
	_check(baseline_repository.save_state(baseline), "promotion-failure fixture writes the previous primary")
	var failing_repository = PromotionFailureRepositoryScript.new(path)
	var game_state = GameStateScript.new()
	game_state.state = baseline.duplicate(true)
	game_state._repository = failing_repository
	var attempted: Dictionary = game_state.start_training_battle(6161)
	_check(bool(attempted.get("ok", false)) and not bool(attempted.get("complete", true)), "live battle starts without prematurely attempting reward persistence")
	game_state.active_battle_result.max_ticks = 60
	while not game_state.active_battle_result.complete:
		game_state.advance_training_battle()
	_check(game_state.state["battle"]["completed_battle_ids"].is_empty() and game_state.active_battle_result.complete and not game_state.active_battle_result.reward_saved, "failed completion rolls back reward identity while retaining a retryable terminal session")
	_check(not FileAccess.file_exists(failing_repository.temp_path), "failed promotion discards the uncommitted valid temp candidate")
	var reloaded: Dictionary = baseline_repository.load_state()
	_check(bool(reloaded["ok"]), "old primary remains recoverable after failed candidate promotion")
	_check(reloaded["state"]["battle"]["completed_battle_ids"].is_empty() and int(reloaded["state"]["battle"]["next_serial"]) == 1 and is_zero_approx(float(reloaded["state"]["care"]["bond"])), "reload cannot resurrect failed battle reward, processed ID, serial, or bond")
	game_state.free()
	baseline_repository.clear()


func _encode(state: Dictionary, schema_version: int) -> String:
	return JSON.stringify({
		"schemaVersion": schema_version,
		"savedAt": 1000.0,
		"companion": state,
	}, "  ")


func _unique_path(label: String) -> String:
	return "/tmp/care-%s-%d.json" % [label, Time.get_ticks_usec()]


func _write(path: String, content: String) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(content)
	file.flush()
	var result := file.get_error() == OK
	file.close()
	return result


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("  ok %02d - %s" % [_checks, message])
	else:
		_failures += 1
		push_error("not ok %02d - %s" % [_checks, message])
