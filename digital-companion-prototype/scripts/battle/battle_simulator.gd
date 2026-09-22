class_name BattleSimulator
extends RefCounted

## Public factory/version dispatcher. Only this layer obtains live content.
const Arena = preload("res://scripts/battle/battle_arena.gd")
const Content = preload("res://scripts/battle/mob_content.gd")
const V5 = preload("res://scripts/battle/battle_simulator_v5.gd")
const V2 = preload("res://scripts/battle/battle_simulator_v2.gd")
const V3 = preload("res://scripts/battle/battle_simulator_v3.gd")
const V4 = preload("res://scripts/battle/battle_simulator_v4.gd")
const SIMULATION_VERSION := "battle-v5"
const TICKS_PER_SECOND := 30
const SCALE := 1000
const DEFAULT_MAX_TICKS := 3600
const MAX_MAX_TICKS := 3600
const DEFAULT_MAX_TURNS := DEFAULT_MAX_TICKS
const MAX_HP := 9999
const MAX_MP := 9999
const MAX_STAT := 999
const MAX_SUPPLIES := 1000000000
# Legacy presentation defaults; v4 geometry uses actor.current_move fields.
const BODY_RADIUS := 14000
const BASIC_RANGE := 58000
const SPECIAL_RANGE := 270000
const PROJECTILE_RADIUS := 4000
const PROJECTILE_SPEED := 7000
const ITEM_COOLDOWN_TICKS := 150
const MOVE_REQUEST_TTL := 150
const SPECIAL_MP_COST := 12
const GUARD_MP_RECOVERY := 3
const ORDERS := ["auto", "attack", "defend", "keep_distance"]
const SUPPORTED_NATURES := ["Bold", "Gentle", "Jolly", "Calm", "Earnest", "Stubborn"]


static func make_snapshot(fighter_id: String, display_name: String, species_id: String, stage: String, nature: String, stats: Dictionary, skills: Dictionary = {}, combat_config: Dictionary = {}) -> Dictionary:
	var config := Content.defaults() if combat_config.is_empty() else combat_config
	var moves := Content.moves_for_species(species_id, config)
	var species: Dictionary = config.get("species", {}).get(species_id, {})
	var special_id := String(species.get("special", V4.SPECIALS.get(species_id, "acid_bubbles")))
	var move: Dictionary = moves.get(special_id, {})
	return {"fighter_id": fighter_id, "display_name": display_name, "species_id": species_id, "stage": stage, "nature": nature,
		"basic_move": String(species.get("basic_move", V4.FALLBACKS.get(species_id, "tackle"))),
		"stats": stats.duplicate(true), "moves": moves, "skills": default_skills(species_id) if skills.is_empty() else skills.duplicate(true),
		"special": {"id": special_id, "name": move.get("name", ""), "power": move.get("power", 0), "mp_cost": move.get("mp_cost", 0)}}


static func player_snapshot_from_state(state: Dictionary) -> Dictionary:
	var identity: Dictionary = state.get("identity", {})
	return make_snapshot("player", String(identity.get("companion_name", "Partner")), String(identity.get("species_id", "botamon")), String(identity.get("stage", "Baby")), String(identity.get("nature", "Gentle")), state.get("battle_profile", {}), state.get("skills", {}))


static func training_opponent(battle_seed: int) -> Dictionary:
	return make_snapshot("training_opponent", "Training Agumon", "agumon", "Rookie", SUPPORTED_NATURES[(battle_seed & BattleRng.MASK_31) % SUPPORTED_NATURES.size()], {"hp": 92, "mp": 48, "offense": 8, "defense": 7, "speed": 7, "brains": 7})


static func create_session(battle_id: String, battle_seed: int, player_snapshot: Dictionary, opponent_snapshot: Dictionary, arena: Dictionary = {}, max_ticks: int = DEFAULT_MAX_TICKS, visual_revisions: Dictionary = {}, initial_supplies: Dictionary = {}, pinned_items: Dictionary = {}, encounter_id: String = "", arena_content_sha256: String = "", combat_config: Dictionary = {}) -> Dictionary:
	var field: Dictionary = Arena.graybox() if arena.is_empty() else arena
	var error := _encounter_problem(encounter_id, field)
	if not error.is_empty():
		return {"ok": false, "error": error}
	if combat_config.get("schema_version") == "combat-content-v1":
		return V4.create_session(battle_id, battle_seed, player_snapshot, opponent_snapshot, field, max_ticks, visual_revisions, initial_supplies, pinned_items, encounter_id, arena_content_sha256, combat_config)
	return V5.create_session(battle_id, battle_seed, player_snapshot, opponent_snapshot, field, max_ticks, visual_revisions, initial_supplies, pinned_items, encounter_id, arena_content_sha256, Content.defaults() if combat_config.is_empty() else combat_config)


static func create_roster_session(battle_id: String, battle_seed: int, roster: Array, arena: Dictionary = {}, max_ticks: int = DEFAULT_MAX_TICKS, visual_revisions: Dictionary = {}, initial_supplies: Dictionary = {}, pinned_items: Dictionary = {}, encounter_id: String = "", arena_content_sha256: String = "", combat_config: Dictionary = {}) -> Dictionary:
	var field: Dictionary = Arena.graybox() if arena.is_empty() else arena
	var error := _encounter_problem(encounter_id, field)
	if not error.is_empty():
		return {"ok": false, "error": error}
	if combat_config.get("schema_version") == "combat-content-v1":
		return V4.create_roster_session(battle_id, battle_seed, roster, field, max_ticks, visual_revisions, initial_supplies, pinned_items, encounter_id, arena_content_sha256, combat_config)
	return V5.create_roster_session(battle_id, battle_seed, roster, field, max_ticks, visual_revisions, initial_supplies, pinned_items, encounter_id, arena_content_sha256, Content.defaults() if combat_config.is_empty() else combat_config)


static func _encounter_problem(id: String, arena: Dictionary) -> String:
	if id.is_empty():
		return ""
	var encounter := EncounterCatalog.resolve(id)
	if not bool(encounter.get("ok", false)) or arena.get("assetId") != encounter.get("arenaId"):
		return "encounter arena identity does not match embedded arena"
	if encounter.get("regionId") != "debug" and arena.get("regionId") != encounter.get("regionId"):
		return "encounter region identity does not match embedded arena"
	return ""


static func step(session: Dictionary, commands: Array = []) -> Array:
	match session.get("simulation_version"):
		"battle-v2": return V2.step(session, commands)
		"battle-v3": return V3.step(session, commands)
		"battle-v4": return V4.step(session, commands)
		"battle-v5": return V5.step(session, commands)
	return []


static func simulate(battle_id: String, battle_seed: int, player_snapshot: Dictionary, opponent_snapshot: Dictionary, max_ticks: int = DEFAULT_MAX_TICKS, arena: Dictionary = {}, visual_revisions: Dictionary = {}, combat_config: Dictionary = {}) -> Dictionary:
	var session := create_session(battle_id, battle_seed, player_snapshot, opponent_snapshot, arena, max_ticks, visual_revisions, {}, {}, "", "", combat_config)
	while bool(session.get("ok", false)) and not bool(session.complete):
		step(session)
	return session


static func preflight_command(session: Dictionary, command: Dictionary) -> Dictionary:
	match session.get("simulation_version"):
		"battle-v3": return V3.preflight_command(session, command)
		"battle-v4": return V4.preflight_command(session, command)
		"battle-v5": return V5.preflight_command(session, command)
	return {"ok": false, "error": "commands require battle-v3 or battle-v4"}


static func preflight_commands(session: Dictionary, commands: Array) -> Dictionary:
	return V3.preflight_commands(session, commands) if session.get("simulation_version") == "battle-v3" else (V4.preflight_commands(session, commands) if session.get("simulation_version") == "battle-v4" else V5.preflight_commands(session, commands))


static func replay_record(session: Dictionary) -> Dictionary:
	match session.get("simulation_version"):
		"battle-v2": return V2.replay_record(session)
		"battle-v3": return V3.replay_record(session)
		"battle-v4": return V4.replay_record(session)
		"battle-v5": return V5.replay_record(session)
	return {}


static func replay(record: Dictionary) -> Dictionary:
	match record.get("simulation_version"):
		"battle-v2", "battle-v3":
			var problem := _legacy_record_problem(record)
			if not problem.is_empty():
				return {"ok": false, "error": problem}
			return V2.replay(record) if record.simulation_version == "battle-v2" else V3.replay(record)
		"battle-v4": return V4.replay(record)
		"battle-v5": return V5.replay(record)
	return {"ok": false, "error": "unsupported replay simulation version"}


static func create_from_record(record: Dictionary) -> Dictionary:
	if record.get("simulation_version") == "battle-v5":
		return V5.create_from_record(record)
	if record.get("simulation_version") == "battle-v4":
		return V4.create_from_record(record)
	if record.get("simulation_version") not in ["battle-v2", "battle-v3"]:
		return {"ok": false, "error": "unsupported replay simulation version"}
	# Frozen create_from_record assumes a previously verified shape.
	var verified := replay(record)
	if not bool(verified.get("ok", false)):
		return verified
	return V3.create_from_record(record)


static func _legacy_record_problem(record: Dictionary) -> String:
	if not record.get("fighters") is Array or record.fighters.size() != 2 or not record.get("content_revisions") is Dictionary or not record.get("commands") is Array or not record.get("arena") is Dictionary:
		return "legacy replay inputs are malformed"
	for input: Variant in record.fighters:
		if not input is Dictionary or not input.get("stats") is Dictionary or not input.get("special") is Dictionary:
			return "legacy fighter snapshot is malformed"
	return ""


static func validate_snapshot(snapshot: Dictionary) -> String:
	return V5.validate_snapshot(snapshot)


static func move_definitions(species: String, combat_config: Dictionary = {}) -> Dictionary:
	return Content.moves_for_species(species, combat_config)


static func item_definitions() -> Dictionary:
	return Content.defaults().get("items", {}).duplicate(true)


static func default_skills(species: String) -> Dictionary:
	var learned: Array = ["pepper_breath", "quick_bite", "heavy_claw"] if species == "agumon" else []
	var equipped: Array = []
	for id: String in learned:
		equipped.append({"move_id": id, "auto": true})
	return {"learned": learned, "equipped": equipped}


static func _fallback_id(species: String) -> String:
	return String(V5.FALLBACKS.get(species, "tackle"))


static func ground_position(actor: Dictionary) -> Vector2:
	return Vector2(float(actor.pos[0]) / SCALE, float(actor.pos[1]) / SCALE)


static func movement_per_tick(snapshot: Dictionary, tuning: Dictionary = {}) -> int:
	return V4.movement_per_tick(snapshot, tuning)


static func reaction_ticks(snapshot: Dictionary, tuning: Dictionary = {}) -> int:
	return V4.reaction_ticks(snapshot, tuning)


static func _length(vector: Array) -> int:
	return V4._length(vector)


static func _subtract(a: Array, b: Array) -> Array:
	return V4._subtract(a, b)


static func rush_travel_remaining(session: Dictionary, fighter_id: String) -> int:
	return V4.rush_travel_remaining(session, fighter_id)
