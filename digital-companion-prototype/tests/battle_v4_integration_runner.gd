extends SceneTree

const Game = preload("res://scripts/core/game_state.gd")
const Failure = preload("res://tests/promotion_failure_save_repository.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	_test_migration()
	_test_durable_tactical_commands()
	_test_failed_spend()
	_test_rewards_and_isolation()
	print("Battle v4 integration: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _legacy_v7() -> Dictionary:
	var old := CareRules.make_new_state(1000, "Stubborn")
	old.battle.erase("mob_wins")
	old.inventory.items.erase("barrier")
	old.inventory.items.erase("haste")
	old.inventory.items.small_recovery = 0
	old.inventory.consumed_command_ids = ["old-spent-item"]
	old.care.status.sleeping = true
	old.care.status.sleep_remaining = 87.0
	old.care.food.wait_seconds = 77.0
	return old

func _test_migration() -> void:
	var old := _legacy_v7()
	var migrated := CareRules.migrate_state_v7(old)
	check(CareRules.SAVE_SCHEMA_VERSION == 11 and CareRules.state_is_valid(migrated), "v7 save migrates to strict v11")
	check(migrated.care == old.care and migrated.identity == old.identity and migrated.habitats == old.habitats, "migration preserves ongoing sleep, food, nature and regional layouts")
	check(migrated.inventory.items.small_recovery == 0 and migrated.inventory.consumed_command_ids == old.inventory.consumed_command_ids, "old spending and inventory counts remain intact")
	check(migrated.inventory.items.barrier == 2 and migrated.inventory.items.haste == 2, "migration grants exactly two tactical starters")
	migrated.inventory.items.barrier = 0
	migrated.inventory.items.haste = 0
	check(CareRules.migrate_state_v7(migrated) == migrated, "repeated migration never refills spent tactical supplies")
	var partial := old.duplicate(true)
	partial.inventory.items.barrier = 2
	check(CareRules.migrate_state_v7(partial).is_empty(), "partially upgraded malformed inventory is rejected")
	var bad := migrated.duplicate(true)
	bad.inventory.items.haste = -1
	check(not CareRules.state_is_valid(bad), "negative tactical count is rejected")
	var catalog := GameDefinitions.MOVES
	GameDefinitions.MOVES = {}
	check(CareRules.state_is_valid(migrated), "balance metadata cannot make a valid durable save appear corrupt")
	GameDefinitions.MOVES = catalog
	var repo := SaveRepository.new("/tmp/battle-v4-migrate-%d.json" % Time.get_ticks_usec())
	var file := FileAccess.open(repo.primary_path, FileAccess.WRITE)
	var original := JSON.stringify({"schemaVersion": 7, "savedAt": 1000, "companion": old})
	file.store_string(original)
	file.close()
	var loaded := repo.load_state()
	check(loaded.ok and loaded.migrated and loaded.state.inventory.items.barrier == 2, "repository migrates historical envelope")
	check(FileAccess.get_file_as_string(repo.backup_path) == original, "migration retains exact historical backup bytes")
	check(repo.save_state(migrated) and repo.load_state().state.inventory.items.haste == 0, "reload preserves exhausted tactical supplies")
	repo.clear()

func _game(label: String) -> Node:
	var game := Game.new()
	game.state = CareRules.make_new_state(1000, "Bold")
	game._repository = SaveRepository.new("/tmp/battle-v4-%s-%d.json" % [label, Time.get_ticks_usec()])
	game.state.battle_profile.hp = 9999
	return game

func _cleanup(game: Node) -> void:
	game._repository.clear()
	game.free()

func _test_durable_tactical_commands() -> void:
	var game := _game("tactical")
	check(game.start_training_battle(84, "graybox").ok, "live v4 starts")
	check(game.queue_battle_command({"order": "attack"}).ok, "legacy order is normalized before reaching queue bookkeeping")
	check(not game.queue_battle_command({"kind": 17}).ok, "malformed command kind is safely rejected")
	check(game.active_battle_result.simulation_version == "battle-v5" and game.active_battle_result.combat_config.has("sha256"), "live session pins complete normalized combat content")
	var request: Dictionary = game.queue_battle_command({"kind": "item_use", "item_id": "barrier", "command_id": "barrier-durable"})
	check(request.ok and game.state.inventory.items.barrier == 2, "queue reserves without prematurely spending")
	check(not game.queue_battle_command({"kind": "item_use", "item_id": "barrier", "command_id": "barrier-durable"}).ok, "duplicate queued item ID rejected")
	game.advance_training_battle()
	check(game.state.inventory.items.barrier == 1 and game.active_battle_result.actors.player.effects.has("barrier"), "accepted barrier spends and applies together")
	var loaded: Dictionary = game._repository.load_state()
	check(loaded.ok and loaded.state.inventory.items.barrier == 1 and "barrier-durable" in loaded.state.inventory.consumed_command_ids, "durable count and unique command ID exist before further simulation")
	check(not game.queue_battle_command({"kind": "item_use", "item_id": "barrier", "command_id": "barrier-durable"}).ok, "consumed command cannot be replayed")
	check(not game.queue_battle_item("haste").ok and game.state.inventory.items.haste == 2, "shared item cooldown rejects without spending")
	var guarded: Dictionary = game.queue_battle_defense("guard")
	check(guarded.ok and guarded.tick == 2, "manual defense uses exact next-tick command API")
	game.advance_training_battle()
	check(game.active_battle_result.actors.player.action == "guard", "defense is applied on next tick")
	check(not game.queue_battle_defense("dodge").ok, "manual shared defense cooldown rejects repeated defense")
	game.battle_paused = true
	var before: int = game.active_battle_result.tick
	check(not game.queue_battle_defense("guard").ok and game.advance_training_battle().is_empty() and game.active_battle_result.tick == before, "paused live battle cannot advance or accept defense")
	_cleanup(game)
	game = _game("empty")
	game.state.inventory.items.haste = 0
	game.start_training_battle(12, "graybox")
	check(not game.queue_battle_item("haste").ok and not FileAccess.file_exists(game._repository.primary_path), "empty tactical inventory causes no write or effect")
	_cleanup(game)

func _test_failed_spend() -> void:
	var game := _game("failure")
	check(game.save_now(), "save-failure fixture baseline is durable")
	game._repository = Failure.new(game._repository.primary_path)
	game.start_training_battle(113, "graybox")
	check(game.queue_battle_item("barrier").ok and game.queue_battle_defense("guard").ok, "item and independent defense queue together")
	game.advance_training_battle()
	check(game.state.inventory.items.barrier == 2 and game.state.inventory.consumed_command_ids.is_empty(), "failed promotion restores care inventory and consumed IDs")
	check(not game.active_battle_result.actors.player.effects.has("barrier") and game.active_battle_result.commands.size() == 1, "failed durable item never reaches simulator or replay")
	check(game.active_battle_result.actors.player.action == "guard", "independent valid command survives item-save failure revalidation")
	var reloaded := SaveRepository.new(game._repository.primary_path).load_state()
	check(reloaded.ok and reloaded.state.inventory.items.barrier == 2, "failed effect cannot resurrect an uncommitted spent inventory")
	check(game.queue_battle_item("barrier").ok, "failed item remains retryable")
	game.advance_training_battle()
	check(game.state.inventory.items.barrier == 1 and game.active_battle_result.actors.player.effects.has("barrier"), "retry spends exactly once and applies effect")
	_cleanup(game)

func _test_rewards_and_isolation() -> void:
	var state := CareRules.make_new_state(1000)
	GameDefinitions.ITEMS["future_item"] = {"name": "Unreleased"}
	var rewarded := CareRules.apply_battle_reward(state, "explicit-v4-win", "win")
	GameDefinitions.ITEMS.erase("future_item")
	check(rewarded.awarded and rewarded.reward.items == {"small_recovery": 1, "mp_recovery": 1, "barrier": 1, "haste": 1}, "wins explicitly grant approved items only")
	check(not rewarded.state.inventory.items.has("future_item") and CareRules.state_is_valid(rewarded.state), "catalog additions do not expand durable rewards")
	check(not CareRules.apply_battle_reward(rewarded.state, "explicit-v4-win", "win").awarded, "duplicate settlement is a no-op")
	for path: String in ["res://scenes/battle_sandbox.tscn", "scenes/battle_sandbox.tscn", "battle_sandbox.tscn", "res://tests/battle_v4_visual_runner.tscn"]:
		check(Game.is_review_launch(PackedStringArray([path])), "direct review startup isolates " + path)
