class_name CareRules
extends RefCounted

## Pure, deterministic care simulation. It never reads the clock, filesystem, or scene tree.

const SAVE_SCHEMA_VERSION := 11
const LEGACY_BATTLE_ITEMS := ["small_recovery", "mp_recovery"]
static var WIN_ITEM_REWARDS: Dictionary = GameBalance.setting("care_rules.WIN_ITEM_REWARDS")
const Status = preload("res://scripts/core/care_status_rules.gd")
const Food = preload("res://scripts/core/food_rules.gd")
const Definitions = preload("res://scripts/core/game_definitions.gd")
const Habitat = preload("res://scripts/core/habitat_rules.gd")
const MAX_HUNGER := 100.0
const MAX_POOP := 3
const MAX_CARE_MISTAKES := 1000000
const MAX_ACTION_COUNT := 1000000000
const MAX_BATTLE_HISTORY := 100000
const MAX_TIMESTAMP := 253402300799.0
# Persistence-side copy of BattleSimulator battle-v2 snapshot bounds. CareRules
# deliberately does not depend on the simulator class, avoiding a circular core
# dependency; changes to battle-v2 limits must update both contracts and tests.
const BATTLE_MAX_HP := 9999
const BATTLE_MAX_MP := 9999
const BATTLE_MAX_STAT := 999
static var HUNGER_SECONDS_PER_POINT: float = GameBalance.setting("care_rules.HUNGER_SECONDS_PER_POINT")
static var POOP_INTERVAL_SECONDS: float = GameBalance.setting("care_rules.POOP_INTERVAL_SECONDS")
static var VIRUS_PER_DIRTY_HOUR: float = GameBalance.setting("care_rules.VIRUS_PER_DIRTY_HOUR")
static var HAPPINESS_LOSS_PER_DIRTY_HOUR: float = GameBalance.setting("care_rules.HAPPINESS_LOSS_PER_DIRTY_HOUR")

static var EVOLUTION_RULES: Dictionary = Definitions.EVOLUTIONS

const SPECIES_NAMES := {
	"botamon": "Botamon",
	"koromon": "Koromon",
	"agumon": "Agumon",
}

const SPECIES_STAGES := {
	"botamon": "Baby",
	"koromon": "In-Training",
	"agumon": "Rookie",
}

const NATURES := ["Bold", "Gentle", "Jolly", "Calm", "Earnest", "Stubborn"]


static func make_new_state(now_unix: float, nature: String = "Gentle") -> Dictionary:
	var chosen_nature := nature if nature in NATURES else "Gentle"
	return {
		"enclosure": EnclosureRules.initial(),
		"identity": {
			"player_name": "Tamer",
			"companion_name": "Byte",
			"species_id": "botamon",
			"species_name": "Botamon",
			"stage": "Baby",
			"nature": chosen_nature,
		},
		"care": {
			"status": Status.initial(),
			"food": Food.initial(),
			"fatigue": 0.0,
			"potty_habit": 0.0,
			"stage_care_mistakes": 0,
			"hunger": float(GameBalance.setting("care.initial").hunger),
			"happiness": float(GameBalance.setting("care.initial").happiness),
			"discipline": float(GameBalance.setting("care.initial").discipline),
			"virus": 0.0,
			"bond": 0.0,
			"weight": float(GameBalance.setting("care.initial").weight),
			"care_mistakes": 0,
			"poop_count": 0,
			"poop_slots": [false, false, false],
			"next_poop_at": now_unix + POOP_INTERVAL_SECONDS,
		},
		"progression": {
			"story_flags": Habitat.default_story_flags(),
			"last_social_reward_at": 0.0,
			"training_history": {"hp": 0, "mp": 0, "offense": 0, "defense": 0, "speed": 0, "brains": 0},
			"last_training_id": "",
			"active_seconds": 0.0,
			"stage_actions": {},
			"valid_action_counts": {"feed": 0, "play": 0, "chat": 0, "clean": 0, "pet": 0, "praise": 0, "scold": 0},
			"last_action": "",
			"repeat_streak": 0,
			"evolution_count": 0,
		},
		"battle_profile": {
			"hp": int(GameBalance.setting("player.initial_stats")["hp"]),
			"mp": int(GameBalance.setting("player.initial_stats")["mp"]),
			"offense": int(GameBalance.setting("player.initial_stats")["offense"]),
			"defense": int(GameBalance.setting("player.initial_stats")["defense"]),
			"speed": int(GameBalance.setting("player.initial_stats")["speed"]),
			"brains": int(GameBalance.setting("player.initial_stats")["brains"]),
			"implementation_status": "active",
		},
		"battle": {
			"next_serial": 1,
			"mob_wins": 0,
			"completed_battle_ids": [],
			"wins": 0,
			"losses": 0,
			"draws": 0,
			"training_points": 0,
			"last_battle_id": "",
		},
		"inventory": Definitions.default_inventory(),
		"habitat": Habitat.default_layout(),
		"home_region": Habitat.DEFAULT_REGION,
		"habitats": {},
		"skills": Definitions.default_skills("botamon"),
		"meta": {
			"preferences": {"muted": false, "reduced_motion": false},
			"birth_time": now_unix,
			"last_update_time": now_unix,
			"last_saved_time": now_unix,
		},
	}


static func advance_time(state: Dictionary, now_unix: float, engaged_seconds: float = 0.0, training_active: bool = false, habitat_manifest: Dictionary = {}) -> Dictionary:
	var next := state.duplicate(true)
	var meta: Dictionary = next["meta"]
	var care: Dictionary = next["care"]
	var progression: Dictionary = next["progression"]
	var previous_time := float(meta.get("last_update_time", now_unix))
	# Wall clocks can move backwards after a manual adjustment or time sync. Never
	# replay already-accounted-for time or move the durable simulation cursor back.
	var effective_now := maxf(previous_time, now_unix)
	var elapsed := effective_now - previous_time
	if not training_active:
		care["fatigue"] = maxf(0.0, float(care.get("fatigue", 0.0)) - elapsed / float(GameBalance.setting("care.rest_seconds_per_fatigue")))

	care["hunger"] = clampf(float(care.get("hunger", MAX_HUNGER)) - elapsed / HUNGER_SECONDS_PER_POINT, 0.0, MAX_HUNGER)
	var sleeping: bool = care.status.sleeping
	progression["active_seconds"] = maxf(0.0, float(progression.get("active_seconds", 0.0)) + (0.0 if sleeping else maxf(0.0, engaged_seconds)))

	var poop_count := int(care.get("poop_count", 0))
	var poop_slots: Array = (care.get("poop_slots", [false, false, false]) as Array).duplicate()
	var care_mistakes := int(care.get("care_mistakes", 0))
	var next_poop_at := maxf(previous_time, float(care.get("next_poop_at", now_unix + POOP_INTERVAL_SECONDS)))
	# Catch-up is arithmetic regardless of how long the app was closed. Only the at
	# most MAX_POOP newly occupied visual slots require a bounded loop.
	var due_intervals := 0
	if next_poop_at <= effective_now:
		due_intervals = int(floor((effective_now - next_poop_at) / POOP_INTERVAL_SECONDS)) + 1
	# The same pinned habitat manifest that authorizes live movement also
	# authorizes automatic potty use. Presentation failure must never erase its
	# blockers or make an otherwise unreachable entrance usable.
	var automatic_potty := float(care.discipline) >= float(Definitions.CARE_TUNING.potty_discipline_required) \
		and not Habitat.path_to_potty(next.get("habitat", {}), Vector2i(-1, -1), habitat_manifest).is_empty()
	var missed_intervals := 0 if automatic_potty else due_intervals
	var spawned := mini(missed_intervals, MAX_POOP - poop_count)
	var dirty_poops_seconds := elapsed * poop_count
	for spawn_index: int in spawned:
		var event_time := next_poop_at + float(spawn_index) * POOP_INTERVAL_SECONDS
		dirty_poops_seconds += maxf(0.0, effective_now - event_time)
		for slot_index: int in poop_slots.size():
			if not bool(poop_slots[slot_index]):
				poop_slots[slot_index] = true
				break
	poop_count += spawned
	var new_mistakes := maxi(0, missed_intervals - spawned)
	care_mistakes = mini(MAX_CARE_MISTAKES, care_mistakes + new_mistakes)
	care["stage_care_mistakes"] = mini(MAX_CARE_MISTAKES, int(care.get("stage_care_mistakes", 0)) + new_mistakes)
	next_poop_at += float(due_intervals) * POOP_INTERVAL_SECONDS
	care["poop_count"] = poop_count
	care["poop_slots"] = poop_slots
	care["next_poop_at"] = next_poop_at
	care["care_mistakes"] = care_mistakes

	if dirty_poops_seconds > 0.0:
		care["virus"] = clampf(float(care.get("virus", 0.0)) + dirty_poops_seconds / 3600.0 * VIRUS_PER_DIRTY_HOUR, 0.0, 100.0)
		care["happiness"] = clampf(float(care.get("happiness", 50.0)) - dirty_poops_seconds / 3600.0 * HAPPINESS_LOSS_PER_DIRTY_HOUR, 0.0, 100.0)
	if float(care["hunger"]) <= float(GameBalance.setting("care.hungry_threshold")) and elapsed > 0.0:
		care["happiness"] = clampf(float(care.get("happiness", 50.0)) - elapsed / float(GameBalance.setting("care.hungry_happiness_seconds")), 0.0, 100.0)

	meta["last_update_time"] = effective_now
	Food.advance(next, effective_now, 0.0 if training_active or sleeping or care.status.sick else maxf(0.0, engaged_seconds))
	Status.advance(next, elapsed, 0.0 if sleeping else engaged_seconds, training_active)
	return next


static func apply_command(state: Dictionary, action: String, payload: String = "", now_unix: float = -1.0) -> Dictionary:
	if action in ["sleep", "wake"]:
		return Status.sleep_command(state, action == "wake")
	if (state.care.status.sleeping and action != "clean") or (state.care.status.sick and action == "play"):
		return {"state": state.duplicate(true), "accepted": false, "rewarded": false, "bond_gain": 0.0, "animation": "idle", "message": "Let's rest first. Use Tools to sleep or wake up."}
	var next := state.duplicate(true)
	var care: Dictionary = next["care"]
	var progression: Dictionary = next["progression"]
	var accepted := true
	var message := ""
	var animation := "happy"
	var base_bond := 0.0
	var rewarded := true
	var now := float(next.meta.last_update_time) if now_unix < 0.0 else now_unix

	match action:
		"pet", "praise", "scold":
			animation = "happy"
			message = {"pet": "That feels lovely!", "praise": "I'll keep doing my best!", "scold": "Okay, I'll try to do better."}[action]
			var last := float(progression.get("last_social_reward_at", 0.0))
			rewarded = last == 0.0 or now - last >= float(Definitions.CARE_TUNING.social_cooldown)
			if rewarded:
				var changes: Array = Definitions.CARE_TUNING[action]
				care.happiness = clampf(float(care.happiness) + float(changes[0]), 0.0, 100.0)
				care.discipline = clampf(float(care.discipline) + float(changes[1]), 0.0, 100.0)
				progression.last_social_reward_at = maxf(0.001, now)
				base_bond = float(GameBalance.setting("care.pet_bond")) if action == "pet" else 0.0
		"feed":
			if not payload.is_empty() and not Food.FOODS.has(payload):
				accepted = false
				message = "That food isn't in the pantry."
			elif float(care.get("hunger", MAX_HUNGER)) >= float(GameBalance.setting("food.full_threshold")):
				accepted = false
				message = "I'm full right now. Let's save that for later."
			else:
				var craved := not payload.is_empty() and Food.active(next, now) == payload
				var favorite := not payload.is_empty() and Food.favorite(String(next.identity.species_id)) == payload
				care["hunger"] = clampf(float(care["hunger"]) + float(GameBalance.setting("food.hunger_gain")), 0.0, MAX_HUNGER)
				care["happiness"] = clampf(float(care["happiness"]) + float(GameBalance.setting("food.happiness_gain")) + (float(GameBalance.setting("food.favorite_happiness")) if favorite else 0.0) + (float(GameBalance.setting("food.craving_happiness")) if craved else 0.0), 0.0, 100.0)
				care["weight"] = clampf(float(care.get("weight", 5.0)) + float(GameBalance.setting("food.weight_gain")), 1.0, 99.0)
				base_bond = float(GameBalance.setting("food.bond_gain")) + (float(GameBalance.setting("food.craving_bond")) if craved else 0.0)
				message = "That's exactly what I was craving!" if craved else ("%s! My favorite!" % Food.label(payload) if favorite else "That hit the spot!")
				if craved or float(care.hunger) > Food.MAX_FULLNESS:
					care.food.craving = ""
					care.food.expires_at = 0.0
				if craved:
					care.food.satisfied = mini(int(care.food.satisfied) + 1, MAX_ACTION_COUNT)
				animation = "eat"
		"play":
			var requested := Status.wish(next, now) == "play"
			care["happiness"] = clampf(float(care["happiness"]) + float(GameBalance.setting("care.play_happiness")) + (float(GameBalance.setting("care.wish_play_happiness")) if requested else 0.0), 0.0, 100.0)
			care["discipline"] = clampf(float(care["discipline"]) - float(GameBalance.setting("care.play_discipline_cost")), 0.0, 100.0)
			base_bond = float(GameBalance.setting("care.play_bond")) + (float(GameBalance.setting("care.wish_play_bond")) if requested else 0.0)
			message = "Just what I wanted! That was extra fun." if requested else "Again! That was fun."
			if requested: Status.clear_wish(care.status)
		"chat":
			if payload.strip_edges().is_empty():
				accepted = false
				message = "Say something and I'll listen."
			else:
				care["happiness"] = clampf(float(care["happiness"]) + float(GameBalance.setting("care.chat_happiness")), 0.0, 100.0)
				base_bond = float(GameBalance.setting("care.chat_bond"))
				message = companion_reply(next, payload)
				animation = "happy"
		"clean":
			if int(care.get("poop_count", 0)) <= 0:
				accepted = false
				message = "Everything is already tidy."
			else:
				var poop_slots: Array = (care.get("poop_slots", [false, false, false]) as Array).duplicate()
				var selected_slot := -1
				if payload.is_empty():
					for slot_index: int in poop_slots.size():
						if bool(poop_slots[slot_index]):
							selected_slot = slot_index
							break
				elif payload.is_valid_int():
					selected_slot = payload.to_int()
				if selected_slot < 0 or selected_slot >= poop_slots.size() or not bool(poop_slots[selected_slot]):
					accepted = false
					message = "That waste pile is already gone."
				else:
					poop_slots[selected_slot] = false
					care["poop_slots"] = poop_slots
					care["poop_count"] = int(care["poop_count"]) - 1
					care["virus"] = clampf(float(care["virus"]) - float(GameBalance.setting("care.clean_virus_reduction")), 0.0, 100.0)
					care["happiness"] = clampf(float(care["happiness"]) + float(GameBalance.setting("care.clean_happiness")), 0.0, 100.0)
					base_bond = float(GameBalance.setting("care.clean_bond"))
					message = "Fresh field, fresh start!"
		_:
			accepted = false
			message = "I don't know that care action yet."

	var bond_gain := 0.0
	if accepted and rewarded:
		var previous_action := String(progression.get("last_action", ""))
		var streak := int(progression.get("repeat_streak", 0)) + 1 if previous_action == action else 1
		progression["repeat_streak"] = streak
		progression["last_action"] = action
		var multiplier: float = GameBalance.setting("care.repeat_multipliers")[mini(streak - 1, 3)]
		bond_gain = base_bond * multiplier
		care["bond"] = clampf(float(care.get("bond", 0.0)) + bond_gain, 0.0, 100.0)
		var counts: Dictionary = progression.get("valid_action_counts", {})
		counts[action] = int(counts.get(action, 0)) + 1
		progression["valid_action_counts"] = counts
		var stage_actions: Dictionary = progression.get("stage_actions", {})
		stage_actions[action] = true
		if action == "pet":
			stage_actions["play"] = true
		progression["stage_actions"] = stage_actions

	return {
		"state": next,
		"accepted": accepted,
		"message": message,
		"animation": animation,
		"bond_gain": bond_gain,
		"rewarded": accepted and rewarded,
	}


static func evolution_readiness(state: Dictionary) -> Dictionary:
	var species_id := String(state["identity"].get("species_id", "botamon"))
	if not Definitions.EVOLUTIONS.has(species_id):
		return {"ready": false, "reason": "This is the final prototype stage."}
	var candidates: Array = Definitions.EVOLUTIONS[species_id].duplicate(true)
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.priority) < int(b.priority))
	var results: Array = []
	for rule: Dictionary in candidates:
		results.append(_candidate_readiness(state, rule))
	var selected: Dictionary = results[0]
	for result: Dictionary in results:
		if bool(result.ready):
			selected = result
			break
	var readiness := selected.duplicate(true)
	readiness["candidates"] = results
	return readiness


static func _candidate_readiness(state: Dictionary, rule: Dictionary) -> Dictionary:
	var progression: Dictionary = state["progression"]
	var care: Dictionary = state["care"]
	var missing: Array[String] = []
	var unmet: Array[String] = []
	var stage_actions: Dictionary = progression.get("stage_actions", {})
	for action: String in rule["required_actions"]:
		if not bool(stage_actions.get(action, false)):
			missing.append(action)
	var active_ok := float(progression.get("active_seconds", 0.0)) >= float(rule["min_active_seconds"])
	var bond_ok := float(care.get("bond", 0.0)) >= float(rule["min_bond"])
	if not active_ok:
		unmet.append("Engaged time: %d / %d minutes" % [int(float(progression.active_seconds) / 60.0), int(float(rule.min_active_seconds) / 60.0)])
	if not bond_ok:
		unmet.append("Bond: %d / %d" % [int(care.bond), int(rule.min_bond)])
	for action: String in missing:
		unmet.append("Spend time together: " + action)
	for stat: String in rule.get("stats", {}):
		if int(state.battle_profile.get(stat, 0)) < int(rule.stats[stat]):
			unmet.append("%s: %d / %d" % [stat.capitalize(), int(state.battle_profile.get(stat, 0)), int(rule.stats[stat])])
	for meter: String in rule.get("care", {}):
		if float(care.get(meter, 0.0)) < float(rule.care[meter]):
			unmet.append("%s: %d / %d" % [meter.capitalize(), int(care.get(meter, 0)), int(rule.care[meter])])
	if rule.has("weight_min") and float(care.weight) < float(rule.weight_min):
		unmet.append("Weight at least %s" % rule.weight_min)
	if rule.has("weight_max") and float(care.weight) > float(rule.weight_max):
		unmet.append("Weight at most %s" % rule.weight_max)
	if rule.has("max_stage_care_mistakes") and int(care.stage_care_mistakes) > int(rule.max_stage_care_mistakes):
		unmet.append("Stage care mistakes at most %s" % rule.max_stage_care_mistakes)
	for move: String in rule.get("learned_moves", []):
		if move not in state.skills.learned:
			unmet.append("Learn " + move.replace("_", " "))
	return {
		"ready": unmet.is_empty(),
		"target": rule["target"],
		"unmet_requirements": unmet,
		"missing_actions": missing,
		"active_ok": active_ok,
		"bond_ok": bond_ok,
	}


static func evolve_if_ready(state: Dictionary) -> Dictionary:
	var readiness := evolution_readiness(state)
	if not bool(readiness.get("ready", false)):
		return {"evolved": false, "state": state.duplicate(true)}
	var next := state.duplicate(true)
	var from_species := String(next["identity"]["species_id"])
	var target := String(readiness["target"])
	next["identity"]["species_id"] = target
	next["identity"]["species_name"] = SPECIES_NAMES[target]
	next["identity"]["stage"] = SPECIES_STAGES[target]
	next["care"]["stage_care_mistakes"] = 0
	if target == "agumon":
		next.skills = Definitions.default_skills(target)
	next["progression"]["stage_actions"] = {}
	next["progression"]["last_action"] = ""
	next["progression"]["repeat_streak"] = 0
	next["progression"]["evolution_count"] = int(next["progression"].get("evolution_count", 0)) + 1
	return {"evolved": true, "from": from_species, "to": target, "state": next}


static func companion_reply(state: Dictionary, utterance: String) -> String:
	var species := String(state["identity"].get("species_id", "botamon"))
	var nature := String(state["identity"].get("nature", "Gentle"))
	var text := utterance.to_lower()
	if "hello" in text or "hi" in text or "hey" in text:
		return _voice(species, nature, "Hi! I was hoping you'd stop by.")
	if "how are" in text:
		var mood := "great" if float(state["care"].get("happiness", 50.0)) >= 60.0 else "a little quiet"
		return _voice(species, nature, "I'm %s. Being here with you helps." % mood)
	if "food" in text or "hungry" in text:
		return _voice(species, nature, "I could always inspect a snack very carefully.")
	if "love" in text:
		return _voice(species, nature, "That makes me feel ten feet tall.")
	return _voice(species, nature, "I heard you. Tell me one more thing about that.")


static func _voice(species: String, nature: String, line: String) -> String:
	var prefix := ""
	match nature:
		"Bold": prefix = "Alright! "
		"Jolly": prefix = "Hehe! "
		"Calm": prefix = "Mm. "
		"Earnest": prefix = "I'll remember the feeling. "
		"Stubborn": prefix = "I was already thinking that. "
		_: prefix = ""
	if species == "botamon":
		return prefix + line.replace("I was hoping you'd stop by.", "Hi... I'm glad you're here.")
	if species == "agumon":
		return prefix + line.replace("one more thing", "the exciting part")
	return prefix + line


static func stats_snapshot(state: Dictionary, now_unix: float) -> Dictionary:
	var care: Dictionary = state["care"]
	var identity: Dictionary = state["identity"]
	var progression: Dictionary = state["progression"]
	var meta: Dictionary = state["meta"]
	var battle: Dictionary = state["battle_profile"]
	return {
		"name": identity["companion_name"],
		"species": identity["species_name"],
		"stage": identity["stage"],
		"nature": identity["nature"],
		"age_days": maxi(0, int((now_unix - float(meta["birth_time"])) / 86400.0)),
		"weight": float(care["weight"]),
		"hunger": float(care["hunger"]),
		"fullness": float(care["hunger"]),
		"fatigue": float(care.get("fatigue", 0.0)),
		"potty_habit": float(care.get("potty_habit", 0.0)),
		"stage_care_mistakes": int(care.get("stage_care_mistakes", 0)),
		"training_history": progression.get("training_history", {}).duplicate(true),
		"happiness": float(care["happiness"]),
		"discipline": float(care["discipline"]),
		"virus": float(care["virus"]),
		"bond": float(care["bond"]),
		"care_mistakes": int(care["care_mistakes"]),
		"poop_count": int(care["poop_count"]),
		"active_seconds": float(progression["active_seconds"]),
		"actions": progression["valid_action_counts"].duplicate(true),
		"battle": battle.duplicate(true),
		"battle_record": state["battle"].duplicate(true),
	}


static func make_battle_id(state: Dictionary, battle_seed: int) -> String:
	var serial := int(state.get("battle", {}).get("next_serial", 1))
	return "battle-v2-s%08x-n%06d" % [battle_seed & 0x7fffffff, serial]


static func apply_battle_reward(state: Dictionary, battle_id: String, outcome: String) -> Dictionary:
	var next := state.duplicate(true)
	if battle_id.strip_edges().is_empty() or battle_id.length() > 96:
		return {"state": next, "awarded": false, "reason": "invalid_battle_id", "reward": {}}
	if outcome not in ["win", "loss", "draw"]:
		return {"state": next, "awarded": false, "reason": "invalid_outcome", "reward": {}}
	var battle: Dictionary = next.get("battle", {})
	var completed: Array = battle.get("completed_battle_ids", [])
	if battle_id in completed:
		return {"state": next, "awarded": false, "reason": "already_awarded", "reward": {}}
	if completed.size() >= MAX_BATTLE_HISTORY:
		return {"state": next, "awarded": false, "reason": "history_full", "reward": {}}
	var reward: Dictionary = GameBalance.setting("rewards.outcomes")[outcome].duplicate(true)
	completed = completed.duplicate()
	completed.append(battle_id)
	battle["completed_battle_ids"] = completed
	battle["next_serial"] = int(battle.get("next_serial", 1)) + 1
	battle["wins"] = int(battle.get("wins", 0)) + (1 if outcome == "win" else 0)
	battle["losses"] = int(battle.get("losses", 0)) + (1 if outcome == "loss" else 0)
	battle["draws"] = int(battle.get("draws", 0)) + (1 if outcome == "draw" else 0)
	battle["training_points"] = int(battle.get("training_points", 0)) + int(reward["training_points"])
	battle["last_battle_id"] = battle_id
	next["battle"] = battle
	var care: Dictionary = next["care"]
	care["bond"] = clampf(float(care.get("bond", 0.0)) + float(reward["bond"]), 0.0, 100.0)
	if outcome == "win":
		reward["items"] = WIN_ITEM_REWARDS.duplicate()
		for item: String in WIN_ITEM_REWARDS:
			next.inventory.items[item] = mini(MAX_ACTION_COUNT, int(next.inventory.items[item]) + int(WIN_ITEM_REWARDS[item]))
	return {"state": next, "awarded": true, "reason": "awarded", "reward": reward}


static func training_readiness(state: Dictionary, stat: String) -> Dictionary:
	if state.care.status.sleeping or state.care.status.sick:
		return {"ok": false, "error": "Finish a full sleep before training while sick or asleep."}
	if not Definitions.TRAINING.has(stat):
		return {"ok": false, "error": "Unknown training session."}
	if float(state.care.hunger) < float(GameBalance.setting("training.min_fullness")):
		return {"ok": false, "error": "Feed your companion before training (%.0f fullness required)." % float(GameBalance.setting("training.min_fullness"))}
	if float(state.care.fatigue) > float(GameBalance.setting("training.max_fatigue")):
		return {"ok": false, "error": "Rest before training (fatigue must be %.0f or less)." % float(GameBalance.setting("training.max_fatigue"))}
	return {"ok": true, "error": ""}


## Caller owns the transient active session and foreground elapsed time. Never
## restore an active session from disk. Commit this returned state before showing rewards.
static func complete_training(state: Dictionary, stat: String, session_id: String, elapsed_seconds: float, context: Dictionary = {}) -> Dictionary:
	var result := {"ok": false, "state": state.duplicate(true), "error": "Training session is incomplete or already awarded."}
	if not Definitions.TRAINING.has(stat) or session_id.is_empty() or session_id.length() > 96 or elapsed_seconds < Definitions.TRAINING_SECONDS or not is_finite(elapsed_seconds) or session_id == String(state.progression.last_training_id):
		return result
	var next: Dictionary = result.state
	if state.care.status.sleeping or state.care.status.sick: return result
	var motivation := Status.training_context(state, float(state.meta.last_update_time)) if context.is_empty() else context
	var definition: Dictionary = Definitions.TRAINING[stat]
	var bonus := (int(GameBalance.setting("training.wish_meter_bonus")) if stat in ["hp", "mp"] else int(GameBalance.setting("training.wish_stat_bonus"))) if motivation.get("wish_bonus", false) else 0
	next.battle_profile[stat] = maxi(int(next.battle_profile[stat]), mini(int(definition.cap), int(next.battle_profile[stat]) + int(definition.gain) + bonus))
	next.care.fatigue = minf(100.0, float(next.care.fatigue) + float(GameBalance.setting("training.fatigue_gain")))
	next.care.hunger = maxf(0.0, float(next.care.hunger) - float(GameBalance.setting("training.hunger_cost")))
	next.care.discipline = minf(100.0, float(next.care.discipline) + float(GameBalance.setting("training.discipline_gain")))
	next.care.happiness = maxf(0.0, float(next.care.happiness) - float(GameBalance.setting("training.happiness_cost")))
	next.progression.training_history[stat] = mini(MAX_ACTION_COUNT, int(next.progression.training_history[stat]) + 1)
	next.progression.last_training_id = session_id
	result.ok = true
	result.error = ""
	result["gain"] = int(next.battle_profile[stat]) - int(state.battle_profile[stat])
	result["wish_bonus"] = bonus
	result["became_sick"] = Status.training_effects(next, motivation)
	return result


static func bathroom_warning(state: Dictionary, now_unix: float) -> bool:
	var remaining := float(state.care.next_poop_at) - now_unix
	return remaining >= 0.0 and remaining <= float(Definitions.CARE_TUNING.potty_warning)


static func complete_potty_guidance(state: Dictionary, now_unix: float, creature_cell: Vector2i, habitat_manifest: Dictionary = {}) -> Dictionary:
	var result := {"ok": false, "state": state.duplicate(true), "error": "Guide your companion to a reachable potty during the bathroom warning."}
	if not bathroom_warning(state, now_unix):
		return result
	var path := Habitat.path_to_potty(state.habitat, creature_cell, habitat_manifest)
	if path.size() != 1:
		return result
	var next: Dictionary = result.state
	next.care.next_poop_at = float(next.care.next_poop_at) + POOP_INTERVAL_SECONDS
	next.care.potty_habit = minf(100.0, float(next.care.potty_habit) + float(GameBalance.setting("care.potty_habit_gain")))
	next.care.discipline = minf(100.0, float(next.care.discipline) + float(GameBalance.setting("training.discipline_gain")))
	next.habitat.creature_cell = [creature_cell.x, creature_cell.y]
	result.ok = true
	result.error = ""
	return result


static func state_is_valid(state: Dictionary) -> bool:
	if not state.get("battle") is Dictionary or not _integer_in_range(state.battle.get("mob_wins"), 0, MAX_ACTION_COUNT): return false
	var projected := state.duplicate(true)
	projected.battle.erase("mob_wins")
	return _state_v10_is_valid(projected)


static func migrate_state_v10(value: Dictionary) -> Dictionary:
	if state_is_valid(value): return value.duplicate(true)
	if not _state_v10_is_valid(value): return {}
	var next := value.duplicate(true)
	next.battle["mob_wins"] = 0
	return next


static func _state_v10_is_valid(state: Dictionary) -> bool:
	if not EnclosureRules.valid(state.get("enclosure")): return false
	if not state.get("inventory") is Dictionary: return false
	for key: String in ["decor", "decor_owned"]:
		if not state.inventory.get(key) is Dictionary or not _has_exact_keys(state.inventory[key], Definitions.DECOR.keys()): return false
	var legacy := state.duplicate(true)
	legacy.erase("enclosure")
	return _state_v8_is_valid(legacy, false)


static func migrate_state_v8(value: Dictionary) -> Dictionary:
	if state_is_valid(value): return value.duplicate(true)
	if not _state_v8_is_valid(value): return {}
	var next := value.duplicate(true)
	next["enclosure"] = EnclosureRules.initial()
	for key: String in ["decor", "decor_owned"]:
		for kind: String in Definitions.DECOR:
			if not next.inventory[key].has(kind): next.inventory[key][kind] = 0
	return migrate_state_v9(next)


static func migrate_state_v9(value: Dictionary) -> Dictionary:
	# The envelope chooses this migration exactly once; a geometrically valid
	# larger layout needs no relocation and preserves all balances verbatim.
	if state_is_valid(value): return value.duplicate(true)
	if _state_v10_is_valid(value): return migrate_state_v10(value)
	if not EnclosureRules.valid(value.get("enclosure")) or not _state_v8_is_valid(value, true): return {}
	var next := value.duplicate(true)
	next.habitat = EnclosureRules.enlarge_legacy_layout(next.habitat, next.inventory)
	for region: String in next.habitats:
		next.habitats[region] = EnclosureRules.enlarge_legacy_layout(next.habitats[region], next.inventory)
	return migrate_state_v10(next)


static func _state_v8_is_valid(state: Dictionary, legacy_geometry := true) -> bool:
	if not state.get("inventory") is Dictionary or not state.inventory.get("items") is Dictionary \
			or not _has_exact_keys(state.inventory.items, Definitions.ITEM_IDENTITIES.keys()):
		return false
	for item: String in ["barrier", "haste"]:
		if not _integer_in_range(state.inventory.items[item], 0, MAX_ACTION_COUNT):
			return false
	var legacy := state.duplicate(true)
	legacy.inventory.items.erase("barrier")
	legacy.inventory.items.erase("haste")
	return _state_v7_is_valid(legacy, legacy_geometry)


static func _state_v7_is_valid(state: Dictionary, legacy_geometry := true) -> bool:
	if not state.get("care") is Dictionary or not Status.valid(state.care.get("status")):
		return false
	var legacy := state.duplicate(true)
	legacy.care.erase("status")
	return _state_v6_is_valid(legacy, legacy_geometry)


static func migrate_state_v7(value: Dictionary) -> Dictionary:
	if state_is_valid(value): return value.duplicate(true)
	if not _state_v7_is_valid(value): return {}
	var next := value.duplicate(true)
	# Schema advancement is the one-time starter grant marker. An already migrated
	# save, including one whose tactical supplies were spent, is never refilled.
	next.inventory.items["barrier"] = 2
	next.inventory.items["haste"] = 2
	return migrate_state_v8(next)


static func _state_v6_is_valid(state: Dictionary, legacy_geometry := true) -> bool:
	if not state.get("care") is Dictionary or not Food.valid(state.care.get("food")):
		return false
	var legacy := state.duplicate(true)
	legacy.care.erase("food")
	return _state_v5_is_valid(legacy, legacy_geometry)


static func migrate_state_v6(value: Dictionary) -> Dictionary:
	if state_is_valid(value): return value.duplicate(true)
	if not _state_v6_is_valid(value): return {}
	var next := value.duplicate(true)
	next.care["status"] = Status.initial()
	return migrate_state_v7(next)


static func migrate_state_v5(value: Dictionary) -> Dictionary:
	if state_is_valid(value):
		return value.duplicate(true)
	var migrated := value.duplicate(true)
	if not _state_v5_is_valid(migrated):
		migrated = migrate_state_v5_missing_decor_ownership(migrated)
		if migrated.is_empty():
			return {}
	if not _state_v5_is_valid(migrated):
		return {}
	migrated.care["food"] = Food.initial()
	return migrate_state_v6(migrated)


static func _state_v5_is_valid(state: Dictionary, legacy_geometry := true) -> bool:
	state = state.duplicate(true)
	state.erase("enclosure")
	if not _has_exact_keys(state, ["identity", "care", "progression", "battle_profile", "battle", "meta", "habitat", "home_region", "habitats", "inventory", "skills"]):
		return false
	for section: String in ["identity", "care", "progression", "battle_profile", "battle", "meta", "habitat", "inventory", "skills"]:
		if not state[section] is Dictionary:
			return false
	if not state.home_region is String or Habitat.resolve_region_alias(state.home_region) != state.home_region or not Habitat.region_is_known(state.home_region):
		return false
	if not state.habitats is Dictionary or state.habitats.size() >= Habitat.REGION_IDS.size() or state.habitats.has(state.home_region):
		return false
	for region_value: Variant in state.habitats:
		if not region_value is String or Habitat.resolve_region_alias(region_value) != region_value or not Habitat.region_is_known(region_value):
			return false
		if not state.habitats[region_value] is Dictionary or not bool(Habitat.validate_layout(state.habitats[region_value], Vector2i(-1, -1), {}, legacy_geometry).ok):
			return false
	var care: Dictionary = state.care
	for meter: String in ["fatigue", "potty_habit"]:
		if not _number_in_range(care.get(meter), 0.0, 100.0):
			return false
	if not _integer_in_range(care.get("care_mistakes"), 0, MAX_CARE_MISTAKES) or not _integer_in_range(care.get("stage_care_mistakes"), 0, MAX_CARE_MISTAKES):
		return false
	if int(care.stage_care_mistakes) > int(care.care_mistakes):
		return false
	var progress: Dictionary = state.progression
	if not progress.get("story_flags") is Dictionary or not _has_exact_keys(progress.story_flags, Habitat.STORY_FLAGS):
		return false
	for flag: String in Habitat.STORY_FLAGS:
		if not progress.story_flags[flag] is bool:
			return false
	if not Habitat.region_is_unlocked(state.home_region, progress.story_flags):
		return false
	for inactive_region: String in state.habitats:
		if not Habitat.region_is_unlocked(inactive_region, progress.story_flags):
			return false
	if not bool(Habitat.validate_layout(state.habitat, Vector2i(-1, -1), {}, legacy_geometry).ok):
		return false
	var placed_ids := {}
	var placed_totals := {}
	for item_id: String in Definitions.DECOR:
		placed_totals[item_id] = 0
	for regional_layout: Dictionary in [state.habitat] + state.habitats.values():
		for placed: Dictionary in regional_layout.items:
			if placed_ids.has(placed.instance_id):
				return false
			placed_ids[placed.instance_id] = true
			placed_totals[placed.item_id] = int(placed_totals.get(placed.item_id, 0)) + 1
	if not _number_in_range(progress.get("last_social_reward_at"), 0.0, MAX_TIMESTAMP) or not progress.get("last_training_id") is String or String(progress.last_training_id).length() > 96:
		return false
	if not progress.get("training_history") is Dictionary or not _has_exact_keys(progress.training_history, Definitions.TRAINING.keys()):
		return false
	for stat: String in Definitions.TRAINING:
		if not _integer_in_range(progress.training_history[stat], 0, MAX_ACTION_COUNT):
			return false
	var inventory: Dictionary = state.inventory
	if not _has_exact_keys(inventory, ["starter_granted", "items", "decor", "decor_owned", "consumed_command_ids"]) or inventory.starter_granted != true:
		return false
	if not inventory.items is Dictionary or not _has_exact_keys(inventory.items, LEGACY_BATTLE_ITEMS) \
			or not inventory.decor is Dictionary or not (_has_exact_keys(inventory.decor, Definitions.DECOR.keys()) or _has_exact_keys(inventory.decor, Definitions.LEGACY_DECOR)) \
			or not inventory.decor_owned is Dictionary or not (_has_exact_keys(inventory.decor_owned, Definitions.DECOR.keys()) or _has_exact_keys(inventory.decor_owned, Definitions.LEGACY_DECOR)):
		return false
	for collection: Dictionary in [inventory.items, inventory.decor, inventory.decor_owned]:
		for key: String in collection:
			if not _integer_in_range(collection[key], 0, MAX_ACTION_COUNT):
				return false
	for item_id: String in Definitions.DECOR:
		if int(inventory.decor.get(item_id, 0)) + int(placed_totals[item_id]) != int(inventory.decor_owned.get(item_id, 0)):
			return false
	if not inventory.consumed_command_ids is Array or inventory.consumed_command_ids.size() > MAX_BATTLE_HISTORY:
		return false
	var seen := {}
	for id: Variant in inventory.consumed_command_ids:
		if not id is String or id.is_empty() or id.length() > 160 or seen.has(id):
			return false
		seen[id] = true
	var skills: Dictionary = state.skills
	if not _has_exact_keys(skills, ["learned", "equipped"]) or not skills.learned is Array or not skills.equipped is Array or skills.equipped.size() > 3:
		return false
	seen.clear()
	for move: Variant in skills.learned:
		if not move is String or not Definitions.MOVE_IDENTITIES.has(move) or not bool(Definitions.MOVE_IDENTITIES[move].equippable) or seen.has(move):
			return false
		seen[move] = true
	seen.clear()
	for slot: Variant in skills.equipped:
		if not slot is Dictionary or not _has_exact_keys(slot, ["move_id", "auto"]) or not slot.move_id is String or slot.move_id not in skills.learned or not slot.auto is bool or seen.has(slot.move_id):
			return false
		seen[slot.move_id] = true
	var legacy := state.duplicate(true)
	if state.meta.has("preferences"):
		var preferences: Variant = state.meta.preferences
		if not preferences is Dictionary or not _has_exact_keys(preferences, ["muted", "reduced_motion"]) or not preferences.muted is bool or not preferences.reduced_motion is bool:
			return false
		legacy.meta.erase("preferences")
	for section: String in ["habitat", "home_region", "habitats", "inventory", "skills"]:
		legacy.erase(section)
	for key: String in ["fatigue", "potty_habit", "stage_care_mistakes"]:
		legacy.care.erase(key)
	for key: String in ["story_flags", "last_social_reward_at", "training_history", "last_training_id"]:
		legacy.progression.erase(key)
	# Validate v4's extended social counters, then project to the retained strict
	# v3 validator so all historical limits and backup guarantees stay intact.
	if not progress.get("stage_actions") is Dictionary or not progress.get("valid_action_counts") is Dictionary or not _has_exact_keys(progress.valid_action_counts, ["feed", "play", "chat", "clean", "pet", "praise", "scold"]):
		return false
	for action: String in ["pet", "praise", "scold"]:
		if not _integer_in_range(progress.valid_action_counts[action], 0, MAX_ACTION_COUNT):
			return false
		if progress.stage_actions.has(action) and not progress.stage_actions[action] is bool:
			return false
		legacy.progression.valid_action_counts.erase(action)
		legacy.progression.stage_actions.erase(action)
	if legacy.progression.get("last_action") in ["pet", "praise", "scold"]:
		legacy.progression.last_action = ""
	return _legacy_state_is_valid(legacy)


static func _legacy_state_is_valid(state: Dictionary) -> bool:
	if not _has_exact_keys(state, ["identity", "care", "progression", "battle_profile", "battle", "meta"]):
		return false
	for section: String in ["identity", "care", "progression", "battle_profile", "battle", "meta"]:
		if not state[section] is Dictionary:
			return false
	var identity: Dictionary = state["identity"]
	var care: Dictionary = state["care"]
	var progression: Dictionary = state["progression"]
	var battle: Dictionary = state["battle_profile"]
	var battle_record: Dictionary = state["battle"]
	var meta: Dictionary = state["meta"]
	if not _has_exact_keys(identity, ["player_name", "companion_name", "species_id", "species_name", "stage", "nature"]):
		return false
	for name_key: String in ["player_name", "companion_name"]:
		if not identity[name_key] is String or (identity[name_key] as String).strip_edges().is_empty() or (identity[name_key] as String).length() > 64:
			return false
	var species_value: Variant = identity.get("species_id")
	if not species_value is String or not SPECIES_NAMES.has(species_value):
		return false
	var species_id: String = species_value
	if identity.get("species_name") != SPECIES_NAMES[species_id] or identity.get("stage") != SPECIES_STAGES[species_id]:
		return false
	if not identity.get("nature") is String or identity["nature"] not in NATURES:
		return false

	if not _has_exact_keys(care, ["hunger", "happiness", "discipline", "virus", "bond", "weight", "care_mistakes", "poop_count", "poop_slots", "next_poop_at"]):
		return false
	for meter_key: String in ["hunger", "happiness", "discipline", "virus", "bond"]:
		if not _number_in_range(care[meter_key], 0.0, 100.0):
			return false
	if not _number_in_range(care["weight"], 1.0, 99.0):
		return false
	if not _integer_in_range(care["care_mistakes"], 0, MAX_CARE_MISTAKES) or not _integer_in_range(care["poop_count"], 0, MAX_POOP):
		return false
	if not care["poop_slots"] is Array or (care["poop_slots"] as Array).size() != MAX_POOP:
		return false
	var occupied_slots := 0
	for slot_value: Variant in care["poop_slots"]:
		if not slot_value is bool:
			return false
		if slot_value:
			occupied_slots += 1
	if occupied_slots != int(care["poop_count"]):
		return false
	if not _number_in_range(care["next_poop_at"], 0.0, MAX_TIMESTAMP):
		return false

	if not _has_exact_keys(progression, ["active_seconds", "stage_actions", "valid_action_counts", "last_action", "repeat_streak", "evolution_count"]):
		return false
	if not _number_in_range(progression["active_seconds"], 0.0, MAX_TIMESTAMP):
		return false
	if not progression["stage_actions"] is Dictionary or not progression["valid_action_counts"] is Dictionary:
		return false
	var supported_actions := ["feed", "play", "chat", "clean"]
	for action_key: Variant in (progression["stage_actions"] as Dictionary):
		if not action_key is String or action_key not in supported_actions or not progression["stage_actions"][action_key] is bool:
			return false
	if not _has_exact_keys(progression["valid_action_counts"], supported_actions):
		return false
	for action_key: String in supported_actions:
		if not _integer_in_range(progression["valid_action_counts"][action_key], 0, MAX_ACTION_COUNT):
			return false
	if not progression["last_action"] is String or progression["last_action"] not in ["", "feed", "play", "chat", "clean"]:
		return false
	if not _integer_in_range(progression["repeat_streak"], 0, MAX_ACTION_COUNT) or not _integer_in_range(progression["evolution_count"], 0, 2):
		return false

	if not _has_exact_keys(battle, ["hp", "mp", "offense", "defense", "speed", "brains", "implementation_status"]):
		return false
	for battle_key: String in ["hp", "mp", "offense", "defense", "speed", "brains"]:
		var minimum := 1 if battle_key == "hp" else 0
		var maximum := BATTLE_MAX_HP if battle_key == "hp" else (BATTLE_MAX_MP if battle_key == "mp" else BATTLE_MAX_STAT)
		if not _integer_in_range(battle[battle_key], minimum, maximum):
			return false
	if battle["implementation_status"] != "active":
		return false

	if not _has_exact_keys(battle_record, ["next_serial", "completed_battle_ids", "wins", "losses", "draws", "training_points", "last_battle_id"]):
		return false
	for count_key: String in ["next_serial", "wins", "losses", "draws", "training_points"]:
		if not _integer_in_range(battle_record[count_key], 0 if count_key != "next_serial" else 1, MAX_ACTION_COUNT):
			return false
	if not battle_record["completed_battle_ids"] is Array or (battle_record["completed_battle_ids"] as Array).size() > MAX_BATTLE_HISTORY:
		return false
	var unique_battle_ids: Dictionary = {}
	for battle_id_value: Variant in battle_record["completed_battle_ids"]:
		if not battle_id_value is String or (battle_id_value as String).strip_edges().is_empty() or (battle_id_value as String).length() > 96:
			return false
		if unique_battle_ids.has(battle_id_value):
			return false
		unique_battle_ids[battle_id_value] = true
	if not battle_record["last_battle_id"] is String or (battle_record["last_battle_id"] as String).length() > 96:
		return false
	if not (battle_record["last_battle_id"] as String).is_empty() and not unique_battle_ids.has(battle_record["last_battle_id"]):
		return false
	if int(battle_record["wins"]) + int(battle_record["losses"]) + int(battle_record["draws"]) != (battle_record["completed_battle_ids"] as Array).size():
		return false

	if not _has_exact_keys(meta, ["birth_time", "last_update_time", "last_saved_time"]):
		return false
	for timestamp_key: String in ["birth_time", "last_update_time", "last_saved_time"]:
		if not _number_in_range(meta[timestamp_key], 0.0, MAX_TIMESTAMP):
			return false
	if float(meta["last_update_time"]) < float(meta["birth_time"]):
		return false
	if float(meta["last_saved_time"]) != 0.0 and float(meta["last_saved_time"]) < float(meta["birth_time"]):
		return false
	if float(care["next_poop_at"]) < float(meta["last_update_time"]):
		return false
	return true


static func migrate_state_v1(legacy_state: Dictionary) -> Dictionary:
	var migrated := legacy_state.duplicate(true)
	if not migrated.get("care") is Dictionary:
		return {}
	var care: Dictionary = migrated["care"]
	if not _integer_in_range(care.get("poop_count"), 0, MAX_POOP):
		return {}
	var slots: Array[bool] = []
	for slot_index: int in MAX_POOP:
		slots.append(slot_index < int(care["poop_count"]))
	care["poop_slots"] = slots
	# Authentic schema-v1 saves predate all battle data. Reconstruct the v2
	# profile first, then let migrate_state_v2 add the v3 record/reward fields.
	if not migrated.has("battle_profile"):
		migrated["battle_profile"] = {
			"hp": 100,
			"mp": 60,
			"offense": 8,
			"defense": 8,
			"speed": 8,
			"brains": 8,
			"implementation_status": "reserved",
		}
	return migrate_state_v2(migrated)


static func migrate_state_v2(legacy_state: Dictionary) -> Dictionary:
	var migrated := legacy_state.duplicate(true)
	if not migrated.get("battle_profile") is Dictionary:
		return {}
	var profile: Dictionary = migrated["battle_profile"]
	profile["implementation_status"] = "active"
	if not migrated.has("battle"):
		migrated["battle"] = {
			"next_serial": 1,
			"completed_battle_ids": [],
			"wins": 0,
			"losses": 0,
			"draws": 0,
			"training_points": 0,
			"last_battle_id": "",
		}
	return migrate_state_v3(migrated)


static func migrate_state_v3(legacy_state: Dictionary) -> Dictionary:
	# Idempotence matters when a recovered legacy envelope is inspected repeatedly.
	if state_is_valid(legacy_state):
		return legacy_state.duplicate(true)
	if not _legacy_state_is_valid(legacy_state):
		return {}
	var migrated := legacy_state.duplicate(true)
	migrated.care["fatigue"] = 0.0
	migrated.care["potty_habit"] = 0.0
	migrated.care["stage_care_mistakes"] = 0
	migrated.progression["last_social_reward_at"] = 0.0
	migrated.progression["last_training_id"] = ""
	migrated.progression["training_history"] = {"hp": 0, "mp": 0, "offense": 0, "defense": 0, "speed": 0, "brains": 0}
	for action: String in ["pet", "praise", "scold"]:
		migrated.progression.valid_action_counts[action] = 0
	# Build the historical 20x24 v4 habitat first. migrate_state_v4 performs the
	# one-time centering translation into the 40x48 Green Shade home.
	migrated["habitat"] = Habitat.default_layout(Vector2i(10, 12))
	migrated["inventory"] = Definitions.default_inventory()
	migrated.inventory.items.erase("barrier")
	migrated.inventory.items.erase("haste")
	migrated["skills"] = Definitions.default_skills(String(migrated.identity.species_id))
	return migrate_state_v4(migrated)


static func migrate_state_v4(legacy_state: Dictionary) -> Dictionary:
	# Idempotence is required for crash recovery inspecting the same sidecar more
	# than once. A current-schema value is returned byte-for-value equivalent.
	if state_is_valid(legacy_state):
		return legacy_state.duplicate(true)
	if not legacy_state is Dictionary or not legacy_state.get("progression") is Dictionary \
			or not legacy_state.get("habitat") is Dictionary:
		return {}
	if legacy_state.has("home_region") or legacy_state.has("habitats") \
			or legacy_state.progression.has("story_flags"):
		return {}
	var centered := Habitat.migrate_legacy_layout(legacy_state.habitat)
	if centered.is_empty():
		return {}
	var migrated := legacy_state.duplicate(true)
	migrated.progression["story_flags"] = Habitat.default_story_flags()
	migrated["home_region"] = Habitat.DEFAULT_REGION
	migrated["habitats"] = {}
	migrated["habitat"] = centered
	_add_inferred_decor_ownership(migrated)
	return migrate_state_v5(migrated)


static func migrate_state_v5_missing_decor_ownership(value: Dictionary) -> Dictionary:
	# Early v5 builds had regional layouts but no durable entitlement totals.
	# Infer the smallest lossless ownership set from what is actually present.
	# All other strict v5 validation (including globally unique instance IDs)
	# still runs after inference, so malformed regional saves remain rejected.
	if not value is Dictionary or not value.get("inventory") is Dictionary \
			or value.inventory.has("decor_owned"):
		return {}
	var migrated := value.duplicate(true)
	_add_inferred_decor_ownership(migrated)
	return migrated if _state_v5_is_valid(migrated) else {}


static func _add_inferred_decor_ownership(state: Dictionary) -> void:
	if not state.get("inventory") is Dictionary or not state.inventory.get("decor") is Dictionary:
		return
	var totals := {}
	for item_id: String in Definitions.DECOR:
		totals[item_id] = int(state.inventory.decor.get(item_id, 0))
	var layouts: Array = []
	if state.get("habitat") is Dictionary:
		layouts.append(state.habitat)
	if state.get("habitats") is Dictionary:
		layouts.append_array(state.habitats.values())
	for layout_value: Variant in layouts:
		if not layout_value is Dictionary or not layout_value.get("items") is Array:
			continue
		for placed_value: Variant in layout_value.items:
			if placed_value is Dictionary and Definitions.DECOR.has(placed_value.get("item_id", "")):
				var item_id := String(placed_value.item_id)
				totals[item_id] = int(totals[item_id]) + 1
	state.inventory["decor_owned"] = totals


static func _has_exact_keys(dictionary: Dictionary, required_keys: Array) -> bool:
	return dictionary.size() == required_keys.size() and dictionary.has_all(required_keys)


static func _is_finite_number(value: Variant) -> bool:
	return (value is int or value is float) and not is_nan(float(value)) and not is_inf(float(value))


static func _number_in_range(value: Variant, minimum: float, maximum: float) -> bool:
	return _is_finite_number(value) and float(value) >= minimum and float(value) <= maximum


static func _integer_in_range(value: Variant, minimum: int, maximum: int) -> bool:
	return _is_finite_number(value) and floor(float(value)) == float(value) and float(value) >= minimum and float(value) <= maximum
