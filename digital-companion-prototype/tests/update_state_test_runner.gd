extends SceneTree

const StateScript = preload("res://scripts/core/game_state.gd")
const FailedRepository = preload("res://tests/promotion_failure_save_repository.gd")
var checks := 0
var failures := 0
var fixtures: Array = []

func _initialize() -> void:
	_test_training_and_evolution()
	_test_habitat_and_preferences()
	_test_items()
	_test_actual_lifecycle()
	for game: Node in fixtures:
		game._repository.clear()
		game.free()
	print("%s: %d update state checks" % ["PASS" if failures == 0 else "FAIL", checks])
	quit(0 if failures == 0 else 1)

func _game(label: String) -> Node:
	var game := StateScript.new()
	game._repository = SaveRepository.new("/tmp/companion-update-%s-%s.json" % [label, Crypto.new().generate_random_bytes(8).hex_encode()])
	game.state = CareRules.make_new_state(1000.0, "Gentle")
	game._test_clock = 1000.0
	fixtures.append(game)
	_check(game.save_now(), "fixture saved")
	return game

func _check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL: " + label)

func _test_training_and_evolution() -> void:
	var game := _game("training")
	var started: Dictionary = game.start_training("offense")
	_check(started.ok and not game.start_training("hp").ok, "one session at a time")
	_check(not game.start_training_battle(1).ok, "training prevents battle overlap")
	game.advance_care_time(12.0, true, 1012.0)
	game.advance_care_time(120.0, false, 1132.0)
	_check(game.get_training_status().elapsed == 12.0, "focus pause earns no training")
	game._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	game._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	game._test_clock = 1192.0
	game._process(60.0)
	_check(game.get_training_status().elapsed == 12.0, "resume between frames discards suspended delta")
	game.cancel_training()
	_check(not game.complete_training(started.id).ok and game.state.battle_profile.offense == 8, "cancel cannot award")
	var session: Dictionary = game.start_training("offense")
	game.advance_care_time(30.0, true, 1222.0)
	_check(game.state.battle_profile.offense == 10 and game.state.progression.training_history.offense == 1, "training increments selected stat once")
	_check(not game.complete_training(session.id).ok and not game.get_training_status().active, "duplicate completion rejected")
	_check(game.state.care.fatigue == 15.0 and game.state.care.discipline == 44.0, "training care costs and discipline")
	var failure_training := _game("training-failure")
	failure_training.start_training("hp")
	failure_training._repository = FailedRepository.new(failure_training._repository.primary_path)
	failure_training.advance_care_time(30.0, true, 1030.0)
	_check(failure_training.get_training_status().active and failure_training.state.battle_profile.hp == 100, "failed training save keeps completed session retryable without reward")
	var retry_id: String = failure_training.get_training_status().id
	_check(failure_training.complete_training(retry_id).ok and failure_training.state.battle_profile.hp == 120 and not failure_training.complete_training(retry_id).ok, "failed training save retries exactly once")
	game.advance_care_time(120.0, false, 1342.0)
	_check(is_equal_approx(float(game.state.care.fatigue), 13.0), "fatigue recovers outside training")
	game.start_training("hp")
	var reloaded := _game("reload")
	reloaded.state = game._repository.load_state().state
	_check(not reloaded.get_training_status().active, "reload never restores partial training")
	game.cancel_training()
	game.state.care.bond = 24.0
	game.state.progression.active_seconds = 599.0
	game.state.progression.stage_actions = {"feed": true, "play": true, "chat": true}
	var observed := {"count": 0, "durable": false}
	game.evolution_started.connect(func(_from: String, target: String):
		observed.count += 1
		observed.durable = game._repository.load_state().state.identity.species_id == target
	)
	game.note_player_activity()
	game.advance_care_time(1.0, true, 1343.0)
	_check(game.state.identity.species_id == "koromon" and observed.count == 1 and observed.durable, "engaged evolution saved before signal")
	game.state.battle_profile.offense = 12
	game.state.care.discipline = 45.0
	game.state.care.bond = 70.0
	game.state.progression.active_seconds = 1800.0
	game.state.progression.stage_actions = {"feed": true, "play": true, "chat": true}
	var failure := FailedRepository.new(game._repository.primary_path)
	game._repository = failure
	var old_happiness: float = game.state.care.happiness
	var result: Dictionary = game.execute_command("pet")
	_check(not result.accepted and game.state.identity.species_id == "koromon" and game.state.care.happiness == old_happiness and observed.count == 1, "failed evolution save rolls back care and signal")
	_check(game.execute_command("pet").accepted and game.state.identity.species_id == "agumon" and observed.durable, "failed evolution can retry durably")

func _test_habitat_and_preferences() -> void:
	var game := _game("habitat")
	var draft: Dictionary = game.get_state().habitat
	draft.items = [{"instance_id": "potty-1", "item_id": "digi_potty", "x": 8, "y": 8, "rotation": 0}]
	_check(game.state.habitat.items.is_empty(), "draft changes are isolated until Apply")
	_check(game.apply_habitat_layout(draft).ok and game.state.inventory.decor.digi_potty == 0, "Apply consumes placed decor")
	_check(game.apply_habitat_layout(draft).ok and game.state.inventory.decor.digi_potty == 0, "repeated Apply never duplicates inventory")
	var canceled_layout: Dictionary = game.get_state().habitat
	canceled_layout.items = []
	game._repository = FailedRepository.new(game._repository.primary_path)
	_check(not game.apply_habitat_layout(canceled_layout).ok and game.state.inventory.decor.digi_potty == 0 and game.state.habitat.items.size() == 1, "failed Apply cannot duplicate returned inventory or remove saved layout")
	var forged: Dictionary = draft.duplicate(true)
	forged.items.append({"instance_id": "potty-2", "item_id": "digi_potty", "x": 2, "y": 2, "rotation": 0})
	_check(not game.apply_habitat_layout(forged).ok, "cannot place unavailable decor")
	game.state.care.next_poop_at = 1020.0
	game.state.care.poop_slots = [false, true, false]
	game.state.care.poop_count = 1
	var guided: Dictionary = game.begin_potty_guidance()
	_check(guided.ok and not game.complete_potty_guidance().ok, "guidance requires actual entrance arrival")
	_check(not game.set_creature_cell(Vector2i(8, 10)), "guidance cannot teleport")
	for cell: Vector2i in guided.path:
		_check(game.set_creature_cell(cell), "route follows legal cardinal step")
	_check(game.complete_potty_guidance().ok and game.state.care.potty_habit == 20.0 and game.state.care.discipline == 44.0, "guided arrival earns habit and discipline")
	_check(game.state.care.poop_slots == [false, true, false] and not game.complete_potty_guidance().ok, "potty preserves waste identity and prevents duplicate reward")
	var empty: Dictionary = game.get_state().habitat
	empty.items = []
	_check(game.apply_habitat_layout(empty).ok and game.state.inventory.decor.digi_potty == 1, "removing decor returns one to inventory")
	_check(game.set_habitat_camera(1.4, false).ok and game.set_habitat_theme("practice").ok and game.set_preferences(true, true).ok, "camera background accessibility are saved")
	var loaded: Dictionary = game._repository.load_state().state
	_check(loaded.habitat.camera.zoom == 1.4 and not loaded.habitat.camera.follow and loaded.meta.preferences.muted and loaded.meta.preferences.reduced_motion, "preferences persist across reload")
	loaded.meta.preferences.muted = "yes"
	_check(not CareRules.state_is_valid(loaded), "malformed preferences rejected")
	loaded.meta.erase("preferences")
	_check(CareRules.state_is_valid(loaded), "older v4 without preferences remains valid")

func _test_items() -> void:
	var game := _game("items")
	_check(game.start_training_battle(42, "graybox").ok, "battle starts with pinned supplies")
	var id: String = game.active_battle_result.fighter_order[0]
	game.active_battle_result.actors[id].hp = 20
	var command := {"kind": "item_use", "item_id": "small_recovery", "command_id": "state-test-recovery"}
	_check(game.queue_battle_command(command).ok and not game.queue_battle_command(command).ok, "duplicate enqueue rejected")
	game.advance_training_battle()
	_check(game.state.inventory.items.small_recovery == 2 and game.active_battle_result.supplies.small_recovery == 2 and game.active_battle_result.actors[id].hp == 70, "accepted tick saves one spend then heals")
	_check(not game.queue_battle_item("mp_recovery").ok, "shared item cooldown rejects without consume")
	_check(game.clear_active_battle(), "abandon incomplete battle")
	_check(game._repository.load_state().state.inventory.items.small_recovery == 2, "abandonment consumption remains durable")
	game.start_training_battle(42, "graybox")
	game.active_battle_result.actors[id].hp = 20
	_check(not game.queue_battle_command(command).ok, "consumed identity cannot replay across abandoned same-seed battle")
	var failure := FailedRepository.new(game._repository.primary_path)
	game._repository = failure
	var reports: Array = []
	game.battle_command_resolved.connect(func(result: Dictionary): reports.append(result))
	_check(game.queue_battle_item("small_recovery").ok, "valid recovery queues before persistence")
	game.advance_training_battle()
	_check(game.state.inventory.items.small_recovery == 2 and game.active_battle_result.supplies.small_recovery == 2 and game.active_battle_result.actors[id].hp == 20, "failed durable save prevents both effect and spend")
	_check(not reports.is_empty() and not reports.back().ok and "Saving failed" in reports.back().error, "save failure produces command feedback")
	game.clear_active_battle()
	game.state.identity.species_id = "agumon"
	game.state.identity.species_name = "Agumon"
	game.state.identity.stage = "Rookie"
	game.state.skills = GameDefinitions.default_skills("agumon")
	_check(game.set_skill_loadout([{"move_id": "heavy_claw", "auto": false}]).ok, "learned ordered loadout editable outside battle")
	_check(not game.set_skill_loadout([{"move_id": "claw", "auto": true}]).ok, "fallback cannot be equipped")
	game.start_training_battle(43, "graybox")
	_check(not game.set_skill_loadout([]).ok, "loadout frozen during battle")

func _test_actual_lifecycle() -> void:
	# Accelerated deterministic playtest: only public care and training APIs earn
	# stats/progression. No assigned bond, time, stats, stage or evolution controls.
	var game := _game("lifecycle")
	var evolution_times: Array = []
	game.evolution_started.connect(func(_from: String, _target: String):
		evolution_times.append(float(game.state.progression.active_seconds))
	)
	var elapsed := 0
	while String(game.state.identity.species_id) != "agumon" and elapsed < 3600:
		game._test_clock = 1000.0 + elapsed
		if float(game.state.care.hunger) < 85.0:
			game.execute_command("feed")
		game.execute_command("chat", "Hello, let's spend some time together.")
		game.execute_command("pet")
		# Training teaches the two required offense gains, and discipline. Additional
		# social care stays low pressure without inventing progression shortcuts.
		if String(game.state.identity.species_id) == "koromon" and int(game.state.battle_profile.offense) < 12 and not game.get_training_status().active:
			game.start_training("offense")
		if float(game.state.care.discipline) < 45.0 and not game.get_training_status().active:
			# A separate social reward window makes Scold's tradeoff explicit.
			game._test_clock += 30.0
			game.advance_care_time(30.0, true, game._test_clock)
			elapsed += 30
			game.execute_command("scold")
		game.note_player_activity()
		elapsed += 30
		game._test_clock = 1000.0 + elapsed
		game.advance_care_time(30.0, true, game._test_clock)
	_check(game.state.identity.species_id == "agumon" and evolution_times.size() == 2, "actual care and training commands complete both evolutions")
	_check(elapsed >= 1800 and elapsed <= 3600 and float(game.state.progression.active_seconds) <= 3600.0, "accelerated mixed interaction reaches Rookie in 30–60 engaged minutes")
	_check(game.state.progression.training_history.offense == 2 and game.state.battle_profile.offense == 12 and game.state.care.discipline >= 45.0, "legitimate targeted sessions satisfy visible Rookie criteria")
	print("Lifecycle reached Agumon after %d simulated seconds; evolution engaged times: %s" % [elapsed, evolution_times])
