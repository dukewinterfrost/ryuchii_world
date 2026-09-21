extends SceneTree

const Rules = preload("res://scripts/core/care_rules.gd")
const Habitat = preload("res://scripts/core/habitat_rules.gd")
const Repository = preload("res://scripts/core/save_repository.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	var original := Rules.make_new_state(1000.0)
	check(Rules.state_is_valid(original), "v5 new state validates")
	var legacy := _legacy(original)
	legacy.care.poop_slots = [true, false, true]
	legacy.care.poop_count = 2
	legacy.care.bond = 37.0
	legacy.battle_profile.offense = 39
	var migrated := Rules.migrate_state_v3(legacy)
	check(Rules.state_is_valid(migrated), "v3 migrates through v4 to valid v5")
	check(migrated.care.poop_slots == [true, false, true] and migrated.care.bond == 37.0 and migrated.battle_profile.offense == 39, "migration preserves waste identity and progress")
	migrated.inventory.items.small_recovery = 1
	check(Rules.migrate_state_v3(migrated).inventory.items.small_recovery == 1, "repeated migration never refills supplies")
	var repository := Repository.new("/tmp/care-v4-%d.json" % Time.get_ticks_usec())
	var encoded := JSON.stringify({"schemaVersion": 3, "savedAt": 1000.0, "companion": legacy})
	var file := FileAccess.open(repository.primary_path, FileAccess.WRITE)
	file.store_string(encoded)
	file.close()
	var loaded := repository.load_state()
	check(loaded.ok and loaded.migrated and Rules.state_is_valid(loaded.state), "repository upgrades legacy primary")
	check(FileAccess.get_file_as_string(repository.backup_path) == encoded, "migration retains original legacy backup")
	check(repository.save_state(migrated) and repository.load_state().state.inventory.items.small_recovery == 1, "v5 inventory round trip")
	repository.clear()
	var pet := Rules.apply_command(original, "pet", "", 1000.0)
	check(pet.state.care.happiness == 76.0 and pet.rewarded, "pet happiness reward")
	var praise := Rules.apply_command(pet.state, "praise", "", 1001.0)
	check(praise.accepted and not praise.rewarded and praise.state == pet.state, "social actions share cooldown but still respond")
	praise = Rules.apply_command(pet.state, "praise", "", 1030.0)
	check(praise.state.care.discipline == 40.0 and praise.bond_gain == 0.0, "praise trades discipline for happiness without bond")
	var scold := Rules.apply_command(praise.state, "scold", "", 1060.0)
	check(scold.state.care.discipline == 45.0 and scold.bond_gain == 0.0, "scold trades happiness for discipline without bond")
	var dirty := Rules.advance_time(original, 1900.0)
	check(Rules.apply_command(dirty, "clean").state.care.discipline == original.care.discipline, "cleaning never trains discipline")
	var train := Rules.complete_training(original, "offense", "session-1", 29.0)
	check(not train.ok, "unfinished training grants nothing")
	train = Rules.complete_training(original, "offense", "session-1", 30.0)
	check(train.ok and train.state.battle_profile.offense == 10 and train.state.care.fatigue == 15.0 and train.state.care.hunger == 73.0, "training targeted stat and care cost")
	check(not Rules.complete_training(train.state, "offense", "session-1", 30.0).ok, "training completion idempotent")
	check(Rules.advance_time(train.state, 1120.0).care.fatigue == 13.0, "fatigue recovers offline")
	check(Rules.advance_time(train.state, 1120.0, 0.0, true).care.fatigue == 15.0, "active training suppresses recovery")
	train.state.care.hunger = 19.0
	check(not Rules.training_readiness(train.state, "hp").ok, "hungry companion cannot start training")
	train.state.care.hunger = 40.0
	train.state.care.fatigue = 71.0
	check(not Rules.training_readiness(train.state, "hp").ok, "tired companion cannot start training")
	var layout := Habitat.default_layout()
	layout.items.append({"instance_id": "potty-1", "item_id": "digi_potty", "x": 3, "y": 3, "rotation": 0})
	check(Habitat.validate_layout(layout).ok, "potty placement valid")
	var path := Habitat.path_to_potty(layout)
	check(not path.is_empty() and path.back() == Vector2i(4, 7), "path reaches potty entrance")
	check(not Habitat.path_between_cells(layout, Vector2i(10, 12), Vector2i(3, 3)).size(), "roaming cannot enter solid prop")
	var overlap := layout.duplicate(true)
	overlap.items.append({"instance_id": "planter-1", "item_id": "planter", "x": 3, "y": 3, "rotation": 0})
	check(not Habitat.validate_layout(overlap).ok, "overlapping props rejected")
	var blocked := layout.duplicate(true)
	blocked.items.append({"instance_id": "planter-1", "item_id": "planter", "x": 4, "y": 7, "rotation": 0})
	check(not Habitat.validate_layout(blocked).ok, "blocked potty entrance rejected")
	var potty_state := original.duplicate(true)
	potty_state.habitat = layout
	check(Rules.bathroom_warning(potty_state, 1870.0) and not Rules.bathroom_warning(potty_state, 1869.0), "warning begins 30 seconds before bathroom interval")
	check(not Rules.complete_potty_guidance(potty_state, 1875.0, Vector2i(10, 12)).ok, "guidance must reach entrance before completion")
	var guided := Rules.complete_potty_guidance(potty_state, 1875.0, Vector2i(4, 7))
	check(guided.ok and guided.state.care.potty_habit == 20.0 and guided.state.care.discipline == 44.0 and guided.state.care.next_poop_at == 2800.0, "guided potty awards habit and skips one bathroom event")
	check(not Rules.complete_potty_guidance(guided.state, 1875.0, Vector2i(4, 7)).ok, "repeated guidance cannot duplicate reward")
	potty_state.care.potty_habit = 60.0
	potty_state.care.discipline = 50.0
	var offline := Rules.advance_time(potty_state, 1000.0 + 900.0 * 1000000.0)
	check(offline.care.poop_count == 0 and offline.care.virus == 0.0 and offline.care.potty_habit == 60.0 and offline.care.discipline == 50.0, "long offline automatic potty use remains bounded and grants no training")
	potty_state.care.poop_count = 1
	potty_state.care.poop_slots = [false, true, false]
	offline = Rules.advance_time(potty_state, 1900.0)
	check(offline.care.poop_slots == [false, true, false] and offline.care.virus > 0, "automatic potty preserves existing dirt exposure and slot")
	potty_state.habitat = Habitat.default_layout()
	check(Rules.advance_time(potty_state, 1900.0).care.poop_count == 2, "missing potty falls back to floor waste")
	var reward := Rules.apply_battle_reward(original, "fixture-win", "win")
	check(reward.state.inventory.items.small_recovery == 4 and reward.state.inventory.items.mp_recovery == 4, "win grants consumables")
	check(not Rules.apply_battle_reward(reward.state, "fixture-win", "win").awarded, "settlement cannot duplicate items")
	var bad := original.duplicate(true)
	bad.skills.equipped = [{"move_id": "claw", "auto": true}]
	check(not Rules.state_is_valid(bad), "fallback move cannot be equipped")
	bad = original.duplicate(true)
	bad.inventory.items.small_recovery = -1
	check(not Rules.state_is_valid(bad), "inventory rejects negative quantities")
	for malformed: Variant in [[], {}, "oops"]:
		bad = original.duplicate(true)
		bad.care.care_mistakes = malformed
		check(not Rules.state_is_valid(bad), "lifetime care mistakes rejects %s without conversion errors" % type_string(typeof(malformed)))
	print("Care v4: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _legacy(state: Dictionary) -> Dictionary:
	state = state.duplicate(true)
	state.meta.erase("preferences")
	var result := state.duplicate(true)
	result.battle.erase("mob_wins")
	result.erase("enclosure")
	result.erase("home_region")
	result.erase("habitats")
	result.progression.erase("story_flags")
	for key: String in ["habitat", "inventory", "skills"]:
		result.erase(key)
	for key: String in ["fatigue", "potty_habit", "stage_care_mistakes", "food", "status"]:
		result.care.erase(key)
	for key: String in ["last_social_reward_at", "training_history", "last_training_id"]:
		result.progression.erase(key)
	for action: String in ["pet", "praise", "scold"]:
		result.progression.valid_action_counts.erase(action)
	return result

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
