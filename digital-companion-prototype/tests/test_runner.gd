extends SceneTree

## Dependency-free automated checks for the care vertical. Every failed check is
## collected and the process exits nonzero so this works in CI and local scripts.

const CareRulesScript = preload("res://scripts/core/care_rules.gd")
const SaveRepositoryScript = preload("res://scripts/core/save_repository.gd")
const CompanionAssetLibraryScript = preload("res://scripts/world/companion_asset_library.gd")

var _failures := 0
var _checks := 0


func _initialize() -> void:
	_run()


func _run() -> void:
	_test_new_state()
	_test_offline_care_clock()
	_test_commands_and_diminishing_returns()
	_test_cleaning()
	_test_dialogue()
	_test_evolution_line()
	_test_schema_hardening()
	_test_save_and_backup_recovery()
	_test_temp_and_future_save_handling()
	_test_curated_assets()
	_test_atlas_manifest_rejection()
	if _failures == 0:
		print("PASS: %d care prototype checks" % _checks)
		quit(0)
	else:
		push_error("FAIL: %d of %d care prototype checks failed" % [_failures, _checks])
		quit(1)


func _test_new_state() -> void:
	var state: Dictionary = CareRulesScript.make_new_state(1000.0, "Jolly")
	_check(CareRulesScript.state_is_valid(state), "new state satisfies the save contract")
	_check(state["identity"]["species_id"] == "botamon", "new companions begin as Botamon")
	_check(state["identity"]["nature"] == "Jolly", "birth nature is preserved")
	_check(float(state["care"]["bond"]) == 0.0, "bond begins at zero")


func _test_offline_care_clock() -> void:
	var state: Dictionary = CareRulesScript.make_new_state(1000.0)
	var after_first_poop: Dictionary = CareRulesScript.advance_time(state, 1900.0)
	_check(_near(float(after_first_poop["care"]["hunger"]), 75.0), "offline time lowers hunger by elapsed real time")
	_check(int(after_first_poop["care"]["poop_count"]) == 1, "poop appears on its configured interval")
	_check(_near(float(after_first_poop["care"]["virus"]), 0.0), "a newly spawned poop does not penalize earlier clean time")

	var after_dirty_time: Dictionary = CareRulesScript.advance_time(after_first_poop, 2800.0, 25.0)
	_check(int(after_dirty_time["care"]["poop_count"]) == 2, "offline clock can spawn subsequent poop")
	_check(_near(float(after_dirty_time["care"]["virus"]), 1.5), "virus integrates actual dirty exposure")
	_check(_near(float(after_dirty_time["progression"]["active_seconds"]), 25.0), "only supplied engaged time advances active progression")
	_check(float(after_dirty_time["care"]["bond"]) == 0.0, "offline time never removes or invents bond")
	var rollback: Dictionary = CareRulesScript.advance_time(after_dirty_time, 2700.0)
	_check(float(rollback["meta"]["last_update_time"]) == 2800.0, "clock rollback never moves the offline cursor backwards")
	var long_gap: Dictionary = CareRulesScript.advance_time(state, 1000.0 + 900.0 * 1000000.0)
	_check(int(long_gap["care"]["poop_count"]) == CareRulesScript.MAX_POOP, "very long offline catch-up remains bounded at safe poop capacity")
	_check(int(long_gap["care"]["care_mistakes"]) <= CareRulesScript.MAX_CARE_MISTAKES, "very long offline catch-up caps care-mistake arithmetic")


func _test_commands_and_diminishing_returns() -> void:
	var state: Dictionary = CareRulesScript.make_new_state(1000.0)
	state["care"]["hunger"] = 0.0
	var first: Dictionary = CareRulesScript.apply_command(state, "feed")
	var second: Dictionary = CareRulesScript.apply_command(first["state"], "feed")
	var third: Dictionary = CareRulesScript.apply_command(second["state"], "feed")
	_check(bool(first["accepted"]), "feeding a hungry companion is accepted")
	_check(float(first["bond_gain"]) > float(second["bond_gain"]), "repeated care has diminishing bond return")
	_check(float(second["bond_gain"]) > float(third["bond_gain"]), "diminishing return continues across a spam streak")
	var full_state: Dictionary = third["state"]
	full_state["care"]["hunger"] = 100.0
	var rejected: Dictionary = CareRulesScript.apply_command(full_state, "feed")
	_check(not bool(rejected["accepted"]), "feeding a full companion is rejected")
	_check(float(rejected["bond_gain"]) == 0.0, "invalid care never grants bond")
	var play: Dictionary = CareRulesScript.apply_command(full_state, "play")
	_check(float(play["state"]["care"]["happiness"]) >= float(full_state["care"]["happiness"]), "play improves happiness")


func _test_cleaning() -> void:
	var state: Dictionary = CareRulesScript.make_new_state(1000.0)
	state["care"]["poop_count"] = 3
	state["care"]["poop_slots"] = [true, true, true]
	state["care"]["virus"] = 28.0
	var result: Dictionary = CareRulesScript.apply_command(state, "clean", "1")
	_check(bool(result["accepted"]), "cleanup is accepted when waste exists")
	_check(int(result["state"]["care"]["poop_count"]) == 2, "cleanup removes one selected waste pile")
	_check(result["state"]["care"]["poop_slots"] == [true, false, true], "cleanup preserves stable slot identity for the two untouched piles")
	_check(float(result["state"]["care"]["virus"]) < 28.0, "cleanup reduces virus pressure")
	var empty: Dictionary = result["state"].duplicate(true)
	empty["care"]["poop_count"] = 0
	empty["care"]["poop_slots"] = [false, false, false]
	_check(not bool(CareRulesScript.apply_command(empty, "clean")["accepted"]), "cleanup is rejected on a clean habitat")


func _test_dialogue() -> void:
	var state: Dictionary = CareRulesScript.make_new_state(1000.0, "Bold")
	var first := CareRulesScript.companion_reply(state, "Hello there")
	var second := CareRulesScript.companion_reply(state, "Hello there")
	_check(first == second, "basic dialogue is deterministic")
	_check(first.contains("Alright!"), "birth nature colors deterministic dialogue")
	_check(not bool(CareRulesScript.apply_command(state, "chat", "   ")["accepted"]), "blank chat is not a valid progression action")


func _test_evolution_line() -> void:
	var state: Dictionary = CareRulesScript.make_new_state(1000.0)
	state["care"]["hunger"] = 30.0
	for action: String in ["feed", "play", "chat"]:
		state = CareRulesScript.apply_command(state, action, "hello" if action == "chat" else "")["state"]
	state["care"]["bond"] = 24.0
	state["progression"]["active_seconds"] = 600.0
	var baby_evolution: Dictionary = CareRulesScript.evolve_if_ready(state)
	_check(bool(baby_evolution["evolved"]), "balanced care evolves Botamon")
	_check(baby_evolution["state"]["identity"]["species_id"] == "koromon", "first evolution is Koromon")
	_check(baby_evolution["state"]["progression"]["stage_actions"].is_empty(), "evolution resets stage diversity requirements")

	state = baby_evolution["state"]
	state["care"]["hunger"] = 30.0
	for action: String in ["feed", "play", "chat"]:
		state = CareRulesScript.apply_command(state, action, "hello" if action == "chat" else "")["state"]
	state["care"]["bond"] = 70.0
	state["progression"]["active_seconds"] = 1800.0
	_check(not CareRulesScript.evolution_readiness(state).ready, "Rookie evolution waits for offense and discipline training")
	for index: int in 3:
		state = CareRulesScript.complete_training(state, "offense", "care-test-session-%d" % index, 30.0).state
	var training_evolution: Dictionary = CareRulesScript.evolve_if_ready(state)
	_check(bool(training_evolution["evolved"]), "balanced continued care evolves Koromon")
	_check(training_evolution["state"]["identity"]["species_id"] == "agumon", "second evolution is Agumon")
	_check(not bool(CareRulesScript.evolution_readiness(training_evolution["state"])["ready"]), "Agumon is the final prototype stage")


func _test_save_and_backup_recovery() -> void:
	var test_path := "/tmp/care-prototype-test-%d.json" % Time.get_ticks_usec()
	var repository = SaveRepositoryScript.new(test_path)
	repository.clear()
	var first: Dictionary = CareRulesScript.make_new_state(1000.0, "Calm")
	_check(repository.save_state(first), "versioned JSON primary save writes successfully")
	var second := first.duplicate(true)
	second["care"]["bond"] = 17.0
	_check(repository.save_state(second), "second save rotates a last-known-good backup")
	var primary := FileAccess.open(test_path, FileAccess.WRITE)
	_check(primary != null, "test can simulate primary save corruption")
	if primary != null:
		primary.store_string("{\"broken\": true}")
		primary.close()
	var recovered: Dictionary = repository.load_state()
	_check(bool(recovered["ok"]), "load falls back after primary corruption")
	_check(bool(recovered["recovered"]), "backup recovery is reported")
	_check(_near(float(recovered["state"]["care"]["bond"]), 0.0), "backup contains the prior valid generation")
	repository.clear()


func _test_schema_hardening() -> void:
	var valid: Dictionary = CareRulesScript.make_new_state(1000.0)
	var malformed := valid.duplicate(true)
	malformed["care"]["hunger"] = "full"
	_check(not CareRulesScript.state_is_valid(malformed), "save schema rejects wrong scalar types")
	malformed = valid.duplicate(true)
	malformed["care"]["poop_count"] = 4
	_check(not CareRulesScript.state_is_valid(malformed), "save schema rejects unsafe poop bounds")
	malformed = valid.duplicate(true)
	malformed["care"]["poop_slots"] = [true, false, false]
	_check(not CareRulesScript.state_is_valid(malformed), "save schema rejects poop count and slot disagreement")
	malformed = valid.duplicate(true)
	malformed["progression"]["valid_action_counts"]["feed"] = "many"
	_check(not CareRulesScript.state_is_valid(malformed), "save schema validates nested action dictionaries")
	malformed = valid.duplicate(true)
	malformed["battle_profile"].erase("brains")
	_check(not CareRulesScript.state_is_valid(malformed), "save schema requires every battle profile key")
	var maximum_battle_profile := valid.duplicate(true)
	maximum_battle_profile["battle_profile"].merge({
		"hp": CareRulesScript.BATTLE_MAX_HP,
		"mp": CareRulesScript.BATTLE_MAX_MP,
		"offense": CareRulesScript.BATTLE_MAX_STAT,
		"defense": CareRulesScript.BATTLE_MAX_STAT,
		"speed": CareRulesScript.BATTLE_MAX_STAT,
		"brains": CareRulesScript.BATTLE_MAX_STAT,
	}, true)
	_check(CareRulesScript.state_is_valid(maximum_battle_profile), "save schema accepts the exact battle-v1 profile maxima")
	for boundary_key: String in ["hp", "mp", "offense", "defense", "speed", "brains"]:
		var above_maximum := maximum_battle_profile.duplicate(true)
		above_maximum["battle_profile"][boundary_key] = int(above_maximum["battle_profile"][boundary_key]) + 1
		_check(not CareRulesScript.state_is_valid(above_maximum), "save schema rejects %s above the battle-v1 maximum" % boundary_key)
	var legacy := valid.duplicate(true)
	legacy["care"].erase("poop_slots")
	_check(CareRulesScript.state_is_valid(CareRulesScript.migrate_state_v1(legacy)), "schema-one saves migrate to the complete slot model")


func _test_temp_and_future_save_handling() -> void:
	var test_path := "/tmp/care-recovery-test-%d.json" % Time.get_ticks_usec()
	var repository = SaveRepositoryScript.new(test_path)
	repository.clear()
	var state: Dictionary = CareRulesScript.make_new_state(1000.0)
	_check(repository.save_state(state), "temp-recovery fixture writes a primary")
	var newest := state.duplicate(true)
	newest["care"]["bond"] = 33.0
	var temp_envelope := {"schemaVersion": CareRulesScript.SAVE_SCHEMA_VERSION, "savedAt": 2000.0, "companion": newest}
	_write_test_file(repository.temp_path, JSON.stringify(temp_envelope))
	_write_test_file(repository.primary_path, "{broken")
	var recovered: Dictionary = repository.load_state()
	_check(bool(recovered["ok"]) and bool(recovered["recovered"]), "valid temp recovers after an interrupted primary replacement")
	_check(_near(float(recovered["state"]["care"]["bond"]), 33.0), "temp recovery selects the newest complete generation")
	repository.clear()
	var future_bytes := JSON.stringify({"schemaVersion": CareRulesScript.SAVE_SCHEMA_VERSION + 1, "savedAt": 3000.0, "companion": {}})
	_write_test_file(repository.primary_path, future_bytes)
	var future: Dictionary = repository.load_state()
	_check(not bool(future["ok"]) and bool(future["incompatible"]), "future schema is distinguished from corrupt data")
	_check(not repository.save_state(state), "current build refuses to overwrite a future-schema save")
	_check(FileAccess.get_file_as_string(repository.primary_path) == future_bytes, "future-schema bytes remain untouched")
	repository.clear()


func _test_curated_assets() -> void:
	for species_id: String in ["botamon", "koromon", "agumon"]:
		var asset: Dictionary = CompanionAssetLibraryScript.build(species_id)
		_check(not asset.is_empty(), "%s curated atlas loads" % species_id)
		if asset.is_empty():
			continue
		var frames: SpriteFrames = asset["frames"]
		_check(frames.has_animation("idle"), "%s has an idle animation" % species_id)
		_check(frames.has_animation("move"), "%s has a roam animation" % species_id)
	_check((CompanionAssetLibraryScript.build("agumon")["frames"] as SpriteFrames).has_animation("eat"), "Agumon has the compiled eating animation")


func _test_atlas_manifest_rejection() -> void:
	var atlas: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/companions/agumon/atlas.json"))
	var animations: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/companions/agumon/animation-set.json"))
	_check(CompanionAssetLibraryScript.validate_manifest(atlas, animations, Vector2(512, 640)).is_empty(), "curated atlas manifest passes strict validation")
	var missing_frame := animations.duplicate(true)
	missing_frame["clips"]["idle.default"]["frames"][0]["atlasFrame"] = "missing.frame"
	_check(not CompanionAssetLibraryScript.validate_manifest(atlas, missing_frame, Vector2(512, 640)).is_empty(), "atlas validation rejects missing frame references")
	var bad_bounds := atlas.duplicate(true)
	bad_bounds["frames"]["agumon.idle.default.f0000"]["frame"]["x"] = 511
	_check(not CompanionAssetLibraryScript.validate_manifest(bad_bounds, animations, Vector2(512, 640)).is_empty(), "atlas validation rejects rectangles outside the texture")
	var zero_duration := animations.duplicate(true)
	zero_duration["clips"]["idle.default"]["frames"][0]["durationMs"] = 0
	_check(not CompanionAssetLibraryScript.validate_manifest(atlas, zero_duration, Vector2(512, 640)).is_empty(), "atlas validation rejects non-positive frame durations")
	var empty_animation := animations.duplicate(true)
	empty_animation["clips"]["idle.default"]["frames"] = []
	_check(not CompanionAssetLibraryScript.validate_manifest(atlas, empty_animation, Vector2(512, 640)).is_empty(), "atlas validation rejects empty animations")


func _write_test_file(path: String, content: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(content)
		file.close()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("  ok %02d - %s" % [_checks, message])
	else:
		_failures += 1
		push_error("not ok %02d - %s" % [_checks, message])


func _near(actual: float, expected: float, tolerance: float = 0.001) -> bool:
	return absf(actual - expected) <= tolerance
