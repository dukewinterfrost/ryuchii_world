extends Node

signal state_changed(snapshot: Dictionary)
signal command_resolved(result: Dictionary)
signal evolution_started(from_species: String, to_species: String)
signal save_recovered
signal save_failed
signal save_incompatible(schema_version: int)
signal battle_ready(battle_result: Dictionary)
signal battle_command_resolved(result: Dictionary)
signal training_changed(status: Dictionary)
signal home_region_changed(region_id: String, package: Dictionary)

var state: Dictionary = {}
var _repository := SaveRepository.new()
var _tick_accumulator := 0.0
var _autosave_accumulator := 0.0
var _engagement_seconds_remaining := 0.0
var persistence_notice := ""
var active_battle_result: Dictionary = {}
var isolated_mode := false
var battle_paused := false
var _queued_battle_orders: Array[Dictionary] = []
var _training: Dictionary = {}
var _guidance: Dictionary = {}
var _input_serial := 0
var _session_nonce := Crypto.new().generate_random_bytes(16).hex_encode()
# Injectable clock for isolated deterministic checks; never serialized.
var _test_clock := -1.0
var _discard_next_delta := false
var _home_package: Dictionary = {}

const ENGAGEMENT_WINDOW_SECONDS := 30.0
const AUTOSAVE_INTERVAL_SECONDS := 30.0
const AUTOSAVE_RETRY_SECONDS := 5.0


func _ready() -> void:
	# Asset review, demos, and scene smoke checks must never read/advance/save a
	# real companion. Unit-test instances not added to the tree retain normal I/O.
	for flag: String in ["--asset-review", "--battle-demo", "--battle-sandbox", "--test-mode"]:
		if flag in OS.get_cmdline_user_args():
			isolated_mode = true
	# Editor F6/direct scene launches omit our CLI flag. Detect the review scene
	# in startup arguments before the autoload performs ANY repository access.
	isolated_mode = isolated_mode or is_review_launch(OS.get_cmdline_args())
	if isolated_mode:
		state = CareRules.make_new_state(Time.get_unix_time_from_system(), CareRules.NATURES[0])
		state_changed.emit(get_state())
		return
	var loaded := _repository.load_state()
	if bool(loaded["ok"]):
		state = loaded["state"]
		state = CareRules.advance_time(state, Time.get_unix_time_from_system(), 0.0, false, _active_habitat_manifest())
		if bool(loaded["recovered"]):
			save_recovered.emit()
		if bool(loaded.get("repair_failed", false)):
			persistence_notice = "Your companion loaded, but recovery could not repair the main save file."
			push_error(persistence_notice)
			save_failed.emit()
	else:
		if bool(loaded.get("incompatible", false)):
			persistence_notice = "This save was created by a newer app version. It has been preserved and cannot be opened here."
			push_warning(persistence_notice)
			save_incompatible.emit(int(loaded.get("schema_version", -1)))
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		state = CareRules.make_new_state(Time.get_unix_time_from_system(), CareRules.NATURES[rng.randi_range(0, CareRules.NATURES.size() - 1)])
		save_now()
	state_changed.emit(get_state())


static func is_review_launch(arguments: PackedStringArray) -> bool:
	for argument: String in arguments:
		var path := argument.replace("\\", "/")
		if path.ends_with("/environments/care_clearing.tscn"):
			return true
		if "/environment_workshop/" in path and path.ends_with(".tscn"):
			return true
		if path == "asset_review_scene.tscn" or path.ends_with("/asset_review_scene.tscn"):
			return true
		if path.get_file() in ["battle_sandbox.tscn", "battle_v4_visual_runner.tscn", "battle_sandbox_runner.tscn"]:
			return true
	return false


func _process(delta: float) -> void:
	if isolated_mode:
		return
	if _discard_next_delta:
		_discard_next_delta = false
		_tick_accumulator = 0.0
		# Catch up wall-clock care, never suspended foreground training time.
		advance_care_time(0.001, false, _now_unix())
		return
	_tick_accumulator += delta
	if _tick_accumulator < 1.0:
		return
	var seconds := _tick_accumulator
	_tick_accumulator = 0.0
	advance_care_time(seconds, DisplayServer.window_is_focused() and not battle_paused, _now_unix())


func advance_care_time(seconds: float, focused: bool, now_unix: float) -> void:
	if seconds <= 0.0 or not is_finite(seconds) or state.is_empty():
		return
	var engaged := 0.0
	if focused and (_engagement_seconds_remaining > 0.0 or not _training.is_empty()):
		engaged = minf(seconds, _engagement_seconds_remaining)
		if not _training.is_empty():
			engaged = seconds
		_engagement_seconds_remaining = maxf(0.0, _engagement_seconds_remaining - seconds)
	elif not focused:
		# Activity before a focus loss must not keep earning active time when the
		# player returns much later.
		_engagement_seconds_remaining = 0.0
	var previous_poop := int(state["care"].get("poop_count", 0))
	var previous_status: Dictionary = state.care.status.duplicate(true)
	state = CareRules.advance_time(state, now_unix, engaged, not _training.is_empty(), _active_habitat_manifest())
	if not _guidance.is_empty() and not CareRules.bathroom_warning(state, now_unix):
		_guidance.clear()
	if focused and not _training.is_empty():
		_training.elapsed = minf(GameDefinitions.TRAINING_SECONDS, float(_training.elapsed) + seconds)
		if float(_training.elapsed) >= GameDefinitions.TRAINING_SECONDS:
			complete_training(String(_training.id))
		training_changed.emit(get_training_status())
	# Evolution is committed durably before presentation, including time-only gates.
	var evolution := CareRules.evolve_if_ready(state)
	if bool(evolution.evolved):
		_commit_candidate(state)
	_autosave_accumulator += seconds
	if previous_poop != int(state["care"].get("poop_count", 0)) or previous_status.sleeping != state.care.status.sleeping or previous_status.wish != state.care.status.wish:
		if save_now():
			_autosave_accumulator = 0.0
		else:
			_autosave_accumulator = AUTOSAVE_INTERVAL_SECONDS - AUTOSAVE_RETRY_SECONDS
	elif _autosave_accumulator >= AUTOSAVE_INTERVAL_SECONDS:
		if save_now():
			_autosave_accumulator = 0.0
		else:
			_autosave_accumulator = AUTOSAVE_INTERVAL_SECONDS - AUTOSAVE_RETRY_SECONDS
	state_changed.emit(get_state())


func execute_command(action: String, payload: String = "") -> Dictionary:
	if action in ["sleep", "wake", "play"] and (not _training.is_empty() or not active_battle_result.is_empty()):
		return {"accepted": false, "rewarded": false, "bond_gain": 0.0, "animation": "idle", "message": "Finish the current activity first.", "state": get_state()}
	note_player_activity()
	var result := CareRules.apply_command(state, action, payload, _now_unix())
	if bool(result["accepted"]):
		var committed := _commit_candidate(result.state)
		if not committed.ok:
			result.accepted = false
			result.rewarded = false
			result.message = committed.error
			result.bond_gain = 0.0
		elif committed.has("evolution"):
			result.evolution = committed.evolution
		if committed.ok and action == "sleep": _guidance.clear()
	result["state"] = get_state()
	command_resolved.emit(result)
	state_changed.emit(get_state())
	return result


func _now_unix() -> float:
	return _test_clock if _test_clock >= 0.0 else Time.get_unix_time_from_system()


func _commit_candidate(candidate: Dictionary, evaluate_evolution: bool = true) -> Dictionary:
	var evolution := CareRules.evolve_if_ready(candidate) if evaluate_evolution else {"evolved": false, "state": candidate.duplicate(true)}
	if not CareRules.state_is_valid(evolution.state):
		return {"ok": false, "error": "The requested change is invalid."}
	var previous := state
	state = evolution.state
	if not save_now():
		state = previous
		return {"ok": false, "error": "Saving failed. No reward or item change was applied; please retry."}
	var result := {"ok": true}
	if bool(evolution.evolved):
		result.evolution = {"from": evolution.from, "to": evolution.to}
		evolution_started.emit(evolution.from, evolution.to)
	state_changed.emit(get_state())
	return result


func note_player_activity(seconds: float = ENGAGEMENT_WINDOW_SECONDS) -> void:
	_engagement_seconds_remaining = maxf(_engagement_seconds_remaining, maxf(0.0, seconds))


func _input(event: InputEvent) -> void:
	if (event is InputEventMouseButton and event.pressed) \
			or (event is InputEventScreenTouch and event.pressed) \
			or (event is InputEventKey and event.pressed and not event.echo):
		note_player_activity()


func get_state() -> Dictionary:
	return state.duplicate(true)


func get_stats() -> Dictionary:
	return CareRules.stats_snapshot(state, _now_unix())


func _unique_input_id(prefix: String) -> String:
	_input_serial += 1
	return "%s:%s:%d" % [prefix, _session_nonce, _input_serial]


func start_training(stat: String) -> Dictionary:
	if not _training.is_empty() or not active_battle_result.is_empty():
		return {"ok": false, "error": "Finish or cancel the current activity first."}
	var ready := CareRules.training_readiness(state, stat)
	if not ready.ok:
		return ready
	_training = {"id": _unique_input_id("training"), "stat": stat, "elapsed": 0.0, "care_context": CareStatusRules.training_context(state, _now_unix())}
	_guidance.clear()
	_tick_accumulator = 0.0
	note_player_activity()
	training_changed.emit(get_training_status())
	return {"ok": true, "id": _training.id}


func get_training_status() -> Dictionary:
	var result := _training.duplicate(true)
	result.active = not _training.is_empty()
	result.duration = GameDefinitions.TRAINING_SECONDS
	result.paused = battle_paused
	return result


func cancel_training() -> Dictionary:
	_training.clear()
	training_changed.emit(get_training_status())
	return {"ok": true}


func complete_training(session_id: String) -> Dictionary:
	if _training.is_empty() or session_id != String(_training.id):
		return {"ok": false, "error": "This training session is no longer active."}
	var result := CareRules.complete_training(state, String(_training.stat), session_id, float(_training.elapsed), _training.get("care_context", {}))
	if not result.ok:
		return {"ok": false, "error": result.error}
	var committed := _commit_candidate(result.state)
	if committed.ok:
		var trained_stat := String(_training.stat)
		_training.clear()
		training_changed.emit(get_training_status())
		var note := "Training complete! +%d %s.%s%s" % [result.gain, trained_stat.to_upper(), " Motivation bonus included!" if result.wish_bonus > 0 else "", " Overtraining made me sick. I need a full sleep." if result.became_sick else ""]
		command_resolved.emit({"accepted": true, "message": note, "animation": "happy", "state": get_state()})
	return committed


func apply_habitat_layout(layout: Dictionary) -> Dictionary:
	var built := EnclosureRules.build(state, layout, _active_habitat_manifest())
	if not built.ok: return built
	var result := _commit_candidate(built.state)
	if result.ok: _guidance.clear()
	return result


func quote_habitat_layout(layout: Dictionary) -> Dictionary:
	return EnclosureRules.quote(state, layout, _active_habitat_manifest())


func use_enclosure_facility(action: String) -> Dictionary:
	if not _training.is_empty() or not active_battle_result.is_empty():
		return {"ok": false, "error": "Finish the current activity first."}
	var kind := "pond" if action == "pond" else "campfire"
	if HabitatRules.path_to_facility(state.habitat, kind, _active_habitat_manifest()).size() != 1:
		return {"ok": false, "error": "Walk to the facility entrance first."}
	var result := EnclosureRules.use_facility(state, action, _now_unix(), _active_habitat_manifest())
	if not result.ok: return result
	var committed := _commit_candidate(result.state)
	if committed.ok: committed["message"] = result.message
	return committed


func serve_cooked_meal(meal: String) -> Dictionary:
	if meal not in ["steak", "sweet_potato"] or int(state.enclosure.meals.get(meal, 0)) < 1:
		return {"ok": false, "error": "Cook this meal at a campfire first."}
	if not _training.is_empty() or not active_battle_result.is_empty():
		return {"ok": false, "error": "Finish the current activity first."}
	var result := CareRules.apply_command(state, "feed", meal, _now_unix())
	if not result.accepted: return {"ok": false, "error": result.message}
	result.state.enclosure.meals[meal] -= 1
	var committed := _commit_candidate(result.state)
	if committed.ok: committed["message"] = result.message
	return committed


func refill_prototype_materials() -> Dictionary:
	var candidate := state.duplicate(true)
	candidate.enclosure.materials = EnclosureRules.STARTER.duplicate()
	return _commit_candidate(candidate)


func set_habitat_camera(zoom: float, follow: bool) -> Dictionary:
	if not is_finite(zoom):
		return {"ok": false, "error": "Invalid zoom."}
	var candidate := state.duplicate(true)
	candidate.habitat.camera = {"zoom": clampf(zoom, 0.0, 2.0), "follow": follow}
	return _commit_candidate(candidate, false)


func set_habitat_theme(theme: String) -> Dictionary:
	if theme not in ["verdant", "practice"]:
		return {"ok": false, "error": "Unknown background."}
	var candidate := state.duplicate(true)
	candidate.habitat.theme = theme
	return _commit_candidate(candidate, false)


func set_preferences(muted: bool, reduced_motion: bool) -> Dictionary:
	var candidate := state.duplicate(true)
	candidate.meta.preferences = {"muted": muted, "reduced_motion": reduced_motion}
	return _commit_candidate(candidate, false)


func set_creature_cell(cell: Vector2i) -> bool:
	var current := Vector2i(int(state.habitat.creature_cell[0]), int(state.habitat.creature_cell[1]))
	# Roaming reports consecutive grounded cells, never teleports through props.
	if cell == current:
		return true
	if abs(cell.x - current.x) + abs(cell.y - current.y) != 1:
		return false
	if HabitatRules.path_between_cells(state.habitat, current, cell, _active_habitat_manifest()).size() != 2:
		return false
	state.habitat.creature_cell = [cell.x, cell.y]
	return true


func get_potty_status() -> Dictionary:
	var warning := CareRules.bathroom_warning(state, _now_unix())
	var path := HabitatRules.path_to_potty(state.habitat, Vector2i(-1, -1), _active_habitat_manifest())
	return {"warning": warning, "guiding": not _guidance.is_empty(), "path": path, "can_guide": warning and not path.is_empty(), "automatic": float(state.care.discipline) >= float(GameDefinitions.CARE_TUNING.potty_discipline_required), "remaining": maxf(0.0, float(state.care.next_poop_at) - _now_unix())}


func begin_potty_guidance() -> Dictionary:
	var status := get_potty_status()
	if not status.can_guide or not _training.is_empty() or not active_battle_result.is_empty():
		return {"ok": false, "error": "Guide to a reachable potty during the bathroom warning."}
	_guidance = {"deadline": float(state.care.next_poop_at), "path": status.path.duplicate()}
	return {"ok": true, "path": status.path}


func cancel_potty_guidance() -> void:
	_guidance.clear()


func complete_potty_guidance() -> Dictionary:
	if _guidance.is_empty() or float(_guidance.deadline) != float(state.care.next_poop_at):
		return {"ok": false, "error": "No bathroom guidance is active."}
	var cell := Vector2i(int(state.habitat.creature_cell[0]), int(state.habitat.creature_cell[1]))
	var result := CareRules.complete_potty_guidance(state, _now_unix(), cell, _active_habitat_manifest())
	if not result.ok:
		return {"ok": false, "error": result.error}
	var committed := _commit_candidate(result.state)
	if committed.ok:
		_guidance.clear()
	return committed


func get_home_region() -> String:
	return String(state.get("home_region", HabitatRules.DEFAULT_REGION))


func get_home_package() -> Dictionary:
	var region_id := get_home_region()
	if _home_package.is_empty() or String(_home_package.get("region_id", "")) != region_id:
		_home_package = HabitatAssetLibrary.resolve_region(region_id, isolated_mode)
		if String(_home_package.get("mode", "")).ends_with("-3d") and not HabitatRules.validate_layout(state.habitat, Vector2i(-1, -1), _home_package.habitat).ok:
			# Rendering can be disabled, but a verified habitat's grid/blockers may
			# not be replaced with generic geometry. Invalid movement remains safely
			# blocked until the saved layout is reconciled with that pinned revision.
			_home_package.mode = "verified-habitat-2d"
			_home_package.notice = "The saved layout conflicts with this environment revision. Its verified habitat grid and blockers remain authoritative in 2D."
			_home_package.environment_package = {}
			EnvironmentAssetLibrary.clear_active()
	var package := _home_package.duplicate(true)
	if package.get("mode") == "fallback-2d":
		package.habitat = preload("res://scripts/environment/native_care_scenery.gd").resolve(state.habitat, package.habitat)
	return package


func available_home_regions(include_locked := true) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var flags: Dictionary = state.get("progression", {}).get("story_flags", {})
	for region_id: String in HabitatRules.REGION_IDS:
		var unlocked := isolated_mode or HabitatRules.region_is_unlocked(region_id, flags)
		if include_locked or unlocked:
			result.append({
				"region_id": region_id,
				"home_name": String(HabitatRules.REGION_HOMES[region_id].name),
				"unlocked": unlocked,
				"active": region_id == get_home_region(),
			})
	return result


func select_home_region(region_value: String) -> Dictionary:
	var region_id := HabitatRules.resolve_region_alias(region_value)
	if not HabitatRules.region_is_known(region_id):
		return {"ok": false, "error": "Unknown home region."}
	var flags: Dictionary = state.progression.get("story_flags", {})
	if not isolated_mode and not HabitatRules.region_is_unlocked(region_id, flags):
		return {"ok": false, "error": "That home region has not been unlocked."}
	var package := HabitatAssetLibrary.resolve_region(region_id, isolated_mode)
	if not bool(package.get("ok", false)):
		return {"ok": false, "error": String(package.get("error", "The home region is unavailable."))}
	if region_id == get_home_region():
		_home_package = package
		return {"ok": true, "region_id": region_id, "package": package, "changed": false}
	var candidate := state.duplicate(true)
	if isolated_mode and region_id != HabitatRules.DEFAULT_REGION:
		candidate.progression.story_flags[HabitatRules.REGION_FLAGS[region_id]] = true
	candidate.habitats[get_home_region()] = candidate.habitat.duplicate(true)
	var next_layout: Dictionary
	if candidate.habitats.has(region_id):
		next_layout = candidate.habitats[region_id].duplicate(true)
		candidate.habitats.erase(region_id)
	else:
		next_layout = HabitatRules.default_layout_for_manifest(package.habitat)
	if not HabitatRules.validate_layout(next_layout, Vector2i(-1, -1), package.habitat).ok:
		return {"ok": false, "error": "The saved home layout does not match this region."}
	candidate.home_region = region_id
	candidate.habitat = next_layout
	var committed := _commit_candidate(candidate, false)
	if not bool(committed.get("ok", false)):
		return committed
	_guidance.clear()
	_home_package = package
	home_region_changed.emit(region_id, package.duplicate(true))
	return {"ok": true, "region_id": region_id, "package": package, "changed": true}


func grant_story_flag(flag: String) -> Dictionary:
	if flag not in HabitatRules.STORY_FLAGS:
		return {"ok": false, "error": "Unknown story flag."}
	if bool(state.progression.story_flags.get(flag, false)):
		return {"ok": true, "changed": false}
	var candidate := state.duplicate(true)
	candidate.progression.story_flags[flag] = true
	var committed := _commit_candidate(candidate, false)
	if bool(committed.get("ok", false)):
		committed.changed = true
	return committed


func _active_habitat_manifest() -> Dictionary:
	var package := get_home_package()
	return (package.get("habitat", HabitatAssetLibrary.fallback_manifest(get_home_region())) as Dictionary).duplicate(true)


func set_skill_loadout(slots: Array) -> Dictionary:
	if not active_battle_result.is_empty() or String(state.identity.species_id) != "agumon":
		return {"ok": false, "error": "Skills unlock at Rookie and can be changed outside battle."}
	if slots.size() > 3:
		return {"ok": false, "error": "Choose at most three moves."}
	var seen := {}
	for raw: Variant in slots:
		if not raw is Dictionary or raw.size() != 2 or not raw.has_all(["move_id", "auto"]) or not raw.move_id is String or not raw.auto is bool:
			return {"ok": false, "error": "Invalid move slot."}
		if raw.move_id not in state.skills.learned or seen.has(raw.move_id) or not bool(GameDefinitions.MOVES.get(raw.move_id, {}).get("equippable", false)):
			return {"ok": false, "error": "Choose distinct learned moves; basic attacks always remain available."}
		seen[raw.move_id] = true
	var candidate := state.duplicate(true)
	candidate.skills.equipped = slots.duplicate(true)
	return _commit_candidate(candidate)


func start_training_battle(seed_value: int = -1, encounter_id: String = "") -> Dictionary:
	var combat_config := MobContent.defaults()
	if combat_config.is_empty():
		return {"ok": false, "error": "Battle tables need correction: " + "; ".join(MobContent.last_errors())}
	if not state.is_empty() and (state.care.status.sleeping or state.care.status.sick):
		return {"ok": false, "error": "Rest before battling while sick or asleep."}
	note_player_activity()
	if state.is_empty():
		return {"ok": false, "error": "Companion state is unavailable."}
	if not _training.is_empty():
		return {"ok": false, "error": "Finish or cancel training before battling."}
	if not active_battle_result.is_empty():
		if not bool(active_battle_result.get("complete", false)):
			return {"ok": false, "error": "A training battle is already running."}
		if not bool(active_battle_result.get("reward_saved", false)):
			return {"ok": false, "error": "Save the completed battle reward before starting another match."}
	if state.battle.completed_battle_ids.size() >= CareRules.MAX_BATTLE_HISTORY:
		return {"ok": false, "error": "The training battle history is full."}
	var contextual_id := encounter_id
	if contextual_id.is_empty():
		contextual_id = EncounterCatalog.encounter_for_region(get_home_region())
	var resolved_context := EncounterCatalog.resolve(contextual_id)
	if not bool(resolved_context.get("ok", false)):
		return resolved_context
	if String(resolved_context.regionId) != "debug" and not isolated_mode \
			and not HabitatRules.region_is_unlocked(String(resolved_context.regionId), state.progression.story_flags):
		return {"ok": false, "error": "That region has not been unlocked by the story."}
	var resolved_arena := _resolve_training_arena(String(resolved_context.encounterId))
	if not bool(resolved_arena.ok):
		return resolved_arena
	var battle_seed := seed_value
	if battle_seed < 0:
		battle_seed = int(Time.get_ticks_usec() & BattleRng.MASK_31)
	battle_seed = battle_seed & BattleRng.MASK_31
	var battle_id := CareRules.make_battle_id(state, battle_seed)
	var player := BattleSimulator.player_snapshot_from_state(state)
	var mob_encounter := MobCatalog.encounter(int(state.battle.get("mob_wins", 0)), battle_seed)
	var roster_result := MobCatalog.roster(player, mob_encounter, resolved_arena.arena, combat_config)
	if not roster_result.ok: return roster_result
	var visual_pins: Dictionary = {}
	for fighter: Dictionary in roster_result.roster:
		var library := CompanionAssetLibrary.build(String(fighter.species_id))
		if library.is_empty():
			return {"ok": false, "error": "Creature artwork is unavailable for " + String(fighter.species_id)}
		visual_pins[fighter.fighter_id] = {"assetId": String(library.get("asset_id", fighter.species_id)), "revision": String(library.revision)}
	var session := BattleSimulator.create_roster_session(battle_id, battle_seed, roster_result.roster,
		resolved_arena.arena, BattleSimulator.DEFAULT_MAX_TICKS, visual_pins,
		state.inventory.items, {}, String(resolved_arena.encounterId),
		String(resolved_arena.get("contentSha256", "")), combat_config)
	session["mob_encounter"] = mob_encounter.id
	if not bool(session.get("ok", false)):
		return session
	session["reward"] = {}
	session["reward_saved"] = false
	session["settlement_error"] = ""
	session["arena_source"] = resolved_arena.get("source", "")
	session["arena_notice"] = resolved_arena.get("notice", "")
	_queued_battle_orders.clear()
	_guidance.clear()
	active_battle_result = session
	# Starting combat does not resolve it, reserve a reward, change the save serial,
	# or require a save. An abandoned unfinished session therefore grants nothing.
	battle_ready.emit(active_battle_result.duplicate(true))
	return active_battle_result.duplicate(true)


func queue_battle_order(order: String) -> Dictionary:
	return queue_battle_command({"kind": "order", "order": order})


func queue_battle_move(move_id: String) -> Dictionary:
	return queue_battle_command({"kind": "move_request", "move_id": move_id})


func queue_battle_defense(defense: String) -> Dictionary:
	return queue_battle_command({"kind": "defense_request", "defense": defense})


func queue_battle_item(item_id: String) -> Dictionary:
	return queue_battle_command({"kind": "item_use", "item_id": item_id})


func queue_battle_command(input: Dictionary) -> Dictionary:
	if active_battle_result.is_empty() or bool(active_battle_result.get("complete", true)):
		return {"ok": false, "error": "There is no live battle to command."}
	if battle_paused:
		return {"ok": false, "error": "The battle is paused."}
	var tick := int(active_battle_result.tick) + 1
	var command := input.duplicate(true)
	command.fighter_id = String(active_battle_result.fighter_order[0])
	command.tick = tick
	if not command.has("command_id"):
		command.command_id = _unique_input_id("battle")
	if command.get("command_id") in state.inventory.consumed_command_ids:
		return {"ok": false, "error": "This item request was already consumed."}
	for queued: Dictionary in _queued_battle_orders:
		if queued.get("command_id") == command.get("command_id"):
			return {"ok": false, "error": "This request is already queued."}
	var preview := BattleSimulator.preflight_commands(active_battle_result, _queued_battle_orders + [command])
	for rejected: Dictionary in preview.get("rejected", []):
		if rejected.command.get("command_id") == command.command_id:
			return {"ok": false, "error": rejected.error}
	var normalized: Dictionary = {}
	for accepted: Dictionary in preview.get("commands", []):
		if accepted.get("command_id") == command.command_id:
			normalized = accepted
			break
	if normalized.is_empty():
		return {"ok": false, "error": "The battle request could not be validated."}
	command = normalized.duplicate(true)
	if command.kind == "item_use" and state.inventory.consumed_command_ids.size() >= CareRules.MAX_BATTLE_HISTORY:
		return {"ok": false, "error": "The durable item history is full."}
	_queued_battle_orders.append(command)
	note_player_activity()
	return {"ok": true, "command_id": command.command_id, "tick": tick, "command": command.duplicate(true)}


func advance_training_battle() -> Array:
	if battle_paused or active_battle_result.is_empty() or bool(active_battle_result.get("complete", true)):
		return []
	var inputs := _queued_battle_orders.duplicate(true)
	_queued_battle_orders.clear()
	var unspent: Array = []
	for input: Dictionary in inputs:
		if input.command_id in state.inventory.consumed_command_ids:
			battle_command_resolved.emit({"ok": false, "command": input, "error": "This item request was already consumed."})
		else:
			unspent.append(input)
	var preview := BattleSimulator.preflight_commands(active_battle_result, unspent)
	for rejected: Dictionary in preview.get("rejected", []):
		battle_command_resolved.emit({"ok": false, "command": rejected.command, "error": rejected.error})
	var accepted: Array = preview.get("commands", [])
	var candidate := state.duplicate(true)
	var items: Array = []
	var other: Array = []
	var can_spend := true
	for command: Dictionary in accepted:
		if command.kind == "item_use":
			items.append(command)
			if int(candidate.inventory.items.get(command.item_id, 0)) <= 0 or candidate.inventory.consumed_command_ids.size() >= CareRules.MAX_BATTLE_HISTORY:
				can_spend = false
			else:
				candidate.inventory.items[command.item_id] = int(candidate.inventory.items[command.item_id]) - 1
				candidate.inventory.consumed_command_ids.append(command.command_id)
		else:
			other.append(command)
	if not items.is_empty():
		var committed := _commit_candidate(candidate, false) if can_spend else {"ok": false, "error": "Item inventory is unavailable."}
		if not committed.ok:
			for command: Dictionary in items:
				battle_command_resolved.emit({"ok": false, "command": command, "error": committed.error})
			# Recheck requests which might have depended on a rejected MP recovery.
			preview = BattleSimulator.preflight_commands(active_battle_result, other)
			accepted = preview.get("commands", [])
			for rejected: Dictionary in preview.get("rejected", []):
				battle_command_resolved.emit({"ok": false, "command": rejected.command, "error": rejected.error})
	var events := BattleSimulator.step(active_battle_result, accepted)
	for command: Dictionary in accepted:
		battle_command_resolved.emit({"ok": true, "command": command})
	if bool(active_battle_result.complete):
		finish_training_battle()
	return events


func finish_training_battle() -> Dictionary:
	if active_battle_result.is_empty() or not bool(active_battle_result.get("ok", false)) or not bool(active_battle_result.get("complete", false)) or active_battle_result.get("simulation_version") != BattleSimulator.SIMULATION_VERSION:
		return {"ok": false, "error": "Only this session's completed battle can be settled.", "retryable": false}
	var battle_id := String(active_battle_result.battle_id)
	if bool(active_battle_result.get("reward_saved", false)):
		return {"ok": true, "awarded": false, "battle_id": battle_id, "reward": active_battle_result.reward.duplicate(true)}
	# Apply to the latest care state, not the snapshot captured when combat began.
	var reward_result := CareRules.apply_battle_reward(state, battle_id, String(active_battle_result.result.get("outcome", "")))
	if not bool(reward_result.get("awarded", false)):
		if reward_result.get("reason") == "already_awarded":
			active_battle_result.reward_saved = true
			active_battle_result.settlement_error = ""
			return {"ok": true, "awarded": false, "battle_id": battle_id, "reward": active_battle_result.reward.duplicate(true)}
		var error := "Battle reward could not be settled: %s" % reward_result.get("reason", "unknown")
		active_battle_result.settlement_error = error
		return {"ok": false, "error": error, "retryable": false}
	if active_battle_result.has("mob_encounter") and active_battle_result.result.get("outcome") == "win":
		reward_result.state.battle.mob_wins = mini(CareRules.MAX_ACTION_COUNT, int(reward_result.state.battle.mob_wins) + 1)
	var committed := _commit_candidate(reward_result.state)
	if not committed.ok:
		# The repository discards uncommitted staged files. Roll back ONLY this reward
		# candidate; care changes made during combat remain active and retryable.
		active_battle_result.settlement_error = "Battle complete, but its reward has not been saved. Keep the app open and retry."
		return {"ok": false, "error": active_battle_result.settlement_error, "retryable": true}
	active_battle_result.reward = reward_result.reward.duplicate(true)
	active_battle_result.reward_saved = true
	active_battle_result.settlement_error = ""
	state_changed.emit(get_state())
	return {"ok": true, "awarded": true, "battle_id": battle_id, "reward": active_battle_result.reward.duplicate(true)}


func _resolve_training_arena(encounter_or_arena_id: String) -> Dictionary:
	if not ArenaView._safe_segment(encounter_or_arena_id):
		return {"ok": false, "error": "Invalid arena identifier."}
	var encounter := EncounterCatalog.resolve(encounter_or_arena_id)
	if not bool(encounter.get("ok", false)):
		return encounter
	if String(encounter.regionId) != "debug" and not isolated_mode \
			and not HabitatRules.region_is_unlocked(String(encounter.regionId), state.progression.story_flags):
		return {"ok": false, "error": "That region has not been unlocked by the story."}
	var approved := ArenaAssetLibrary.resolve_approved(encounter)
	if bool(approved.get("ok", false)):
		return approved
	if isolated_mode:
		var fixture := _resolve_isolated_encounter_fixture(encounter)
		if bool(fixture.get("ok", false)):
			return fixture
	var fallback := String(encounter.get("legacyFallback", ""))
	if fallback not in ["forest", "graybox"]:
		return {"ok": false, "error": "No approved arena is available for " + String(encounter.encounterId)}
	var manifest := AssetResourceLibrary.read_json("res://assets/arenas/%s.json" % fallback)
	# Compatibility artwork can back the canonical Green Shade encounter, but the
	# live session/replay identity stays contextual and cannot claim another arena.
	manifest["assetId"] = String(encounter.arenaId)
	if String(encounter.regionId) != "debug":
		manifest["regionId"] = String(encounter.regionId)
	var problem := BattleArena.validate(manifest)
	if not problem.is_empty():
		return {"ok": false, "error": "Training arena failed validation: " + problem}
	return {"ok": true, "arena": manifest, "source": "handcrafted-engineering-layout",
		"notice": String(approved.get("error", "The approved arena is unavailable.")) + " The handcrafted training layout is in use.",
		"encounterId": encounter.encounterId, "regionId": encounter.regionId, "contentSha256": ""}


func _resolve_isolated_encounter_fixture(encounter: Dictionary) -> Dictionary:
	# Test/review fixtures are never a production catalog fallback. Their arena
	# geometry remains useful in isolated mode while promotion is approval-gated.
	var index := AssetResourceLibrary.read_json("res://tests/fixtures/regions/index.json")
	var contextual_records: Variant = index.get("encounters")
	var regions: Variant = index.get("regions")
	if index.get("schemaVersion") != 1 or not contextual_records is Dictionary or not regions is Dictionary:
		return {}
	var contextual: Variant = contextual_records.get(String(encounter.encounterId))
	var region: Variant = regions.get(String(encounter.regionId))
	if not contextual is Dictionary or not region is Dictionary or not region.get("arena") is Dictionary:
		return {}
	var arena_record: Dictionary = region.arena
	if String(contextual.get("regionId", "")) != String(encounter.regionId) \
			or String(arena_record.get("assetId", "")) != String(encounter.arenaId) \
			or String(contextual.get("arena", "")) != String(arena_record.get("path", "")):
		return {}
	var review_path := String(arena_record.get("reviewPackage", ""))
	if not review_path.begins_with("tests/fixtures/regions/") or not review_path.ends_with("/review/arena"):
		return {}
	return ArenaAssetLibrary.resolve_isolated_dev_fixture(encounter, "res://" + review_path,
		String(arena_record.get("contentSha256", "")), true)


func get_active_battle() -> Dictionary:
	return active_battle_result.duplicate(true)


func clear_active_battle() -> bool:
	if not active_battle_result.is_empty() and bool(active_battle_result.get("complete", false)) and not bool(active_battle_result.get("reward_saved", false)):
		return false
	active_battle_result.clear()
	_queued_battle_orders.clear()
	return true


func save_now() -> bool:
	if isolated_mode:
		return true
	var previous_saved_time := float(state["meta"].get("last_saved_time", 0.0))
	var save_time := maxf(previous_saved_time, Time.get_unix_time_from_system())
	var candidate := state.duplicate(true)
	candidate["meta"]["last_saved_time"] = save_time
	if not _repository.save_state(candidate):
		persistence_notice = "Saving failed. Your in-memory progress is still active; keep the app open and try again."
		push_error(persistence_notice)
		save_failed.emit()
		return false
	# The in-memory timestamp advances only after the complete replacement has
	# succeeded. Failed writes remain honestly retryable.
	state["meta"]["last_saved_time"] = save_time
	persistence_notice = ""
	return true


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		_tick_accumulator = 0.0
		_discard_next_delta = true
		_engagement_seconds_remaining = 0.0
		battle_paused = true
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN or what == NOTIFICATION_APPLICATION_RESUMED:
		_tick_accumulator = 0.0
		_discard_next_delta = true
		battle_paused = false
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_IN, NOTIFICATION_APPLICATION_RESUMED]:
		training_changed.emit(get_training_status())
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED:
		if not state.is_empty():
			save_now()
