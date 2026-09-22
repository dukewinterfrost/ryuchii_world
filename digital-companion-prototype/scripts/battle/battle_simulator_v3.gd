class_name BattleSimulatorV3
extends RefCounted

## Pure 30 Hz spatial battle. Ground coordinates and authoritative math are integer.
const Arena = preload("res://scripts/battle/battle_arena.gd")
const Definitions = preload("res://scripts/battle/battle_definitions_v3.gd")
const V2 = preload("res://scripts/battle/battle_simulator_v2.gd")
const SIMULATION_VERSION := "battle-v3"
const ITEM_COOLDOWN_TICKS := 150
const MOVE_REQUEST_TTL := 150
const MAX_SUPPLIES := 1000000000 # Matches durable inventory's action-count cap.
const TICKS_PER_SECOND := 30
const SCALE := 1000
const DEFAULT_MAX_TICKS := 3600
const MAX_MAX_TICKS := 3600
const DEFAULT_MAX_TURNS := DEFAULT_MAX_TICKS
const MAX_HP := 9999
const MAX_MP := 9999
const MAX_STAT := 999
const SPECIAL_MP_COST := 12
const GUARD_MP_RECOVERY := 3
const BODY_RADIUS := 14 * SCALE # AABB half-extent, not a circular radius.
const BASIC_RANGE := 58 * SCALE
const SPECIAL_RANGE := 270 * SCALE
const PROJECTILE_RADIUS := 4 * SCALE
const PROJECTILE_SPEED := 7 * SCALE
const ORDERS := ["auto", "attack", "defend", "keep_distance"]
const SUPPORTED_NATURES := ["Bold", "Gentle", "Jolly", "Calm", "Earnest", "Stubborn"]


static func make_snapshot(fighter_id: String, display_name: String, species_id: String, stage: String, nature: String, stats: Dictionary, skills: Dictionary = {}) -> Dictionary:
	var snapshot := {"fighter_id": fighter_id, "display_name": display_name, "species_id": species_id,
		"stage": stage, "nature": nature, "special": _special_for_species(species_id),
		"stats": {"hp": int(stats.get("hp", 0)), "mp": int(stats.get("mp", 0)), "offense": int(stats.get("offense", 0)),
			"defense": int(stats.get("defense", 0)), "speed": int(stats.get("speed", 0)), "brains": int(stats.get("brains", 0))}}
	snapshot.moves = move_definitions(species_id)
	snapshot.skills = default_skills(species_id) if skills.is_empty() else skills.duplicate(true)
	return snapshot


static func player_snapshot_from_state(state: Dictionary) -> Dictionary:
	var identity: Dictionary = state.get("identity", {})
	return make_snapshot("player", String(identity.get("companion_name", "Partner")), String(identity.get("species_id", "botamon")), String(identity.get("stage", "Baby")), String(identity.get("nature", "Gentle")), state.get("battle_profile", {}), state.get("skills", {}))


static func training_opponent(battle_seed: int) -> Dictionary:
	return make_snapshot("training_opponent", "Training Agumon", "agumon", "Rookie", SUPPORTED_NATURES[(battle_seed & BattleRng.MASK_31) % SUPPORTED_NATURES.size()], {"hp": 92, "mp": 48, "offense": 8, "defense": 7, "speed": 7, "brains": 7})


static func create_session(battle_id: String, battle_seed: int, player_snapshot: Dictionary, opponent_snapshot: Dictionary, arena: Dictionary = {}, max_ticks: int = DEFAULT_MAX_TICKS, visual_revisions: Dictionary = {}, initial_supplies: Dictionary = {}, pinned_items: Dictionary = {}, encounter_id: String = "", arena_content_sha256: String = "") -> Dictionary:
	if battle_id.strip_edges().is_empty() or battle_id.length() > 96:
		return _error("battle_id must contain 1–96 characters")
	if max_ticks < 1 or max_ticks > MAX_MAX_TICKS:
		return _error("max_ticks must be between 1 and 3600")
	if encounter_id.length() > 96:
		return _error("encounter_id must be at most 96 characters")
	for snapshot: Dictionary in [player_snapshot, opponent_snapshot]:
		var problem := validate_snapshot(snapshot)
		if not problem.is_empty():
			return _error("invalid fighter snapshot: " + problem)
	if player_snapshot.fighter_id == opponent_snapshot.fighter_id:
		return _error("fighter IDs must be unique")
	var arena_copy: Dictionary = (Arena.graybox() if arena.is_empty() else arena).duplicate(true)
	var problem := Arena.validate(arena_copy)
	if not problem.is_empty():
		return _error("invalid arena: " + problem)
	if not encounter_id.is_empty():
		var encounter := EncounterCatalog.resolve(encounter_id)
		if not bool(encounter.get("ok", false)):
			return _error("invalid contextual encounter identity")
		if String(arena_copy.get("assetId", "")) != String(encounter.arenaId):
			return _error("encounter arena identity does not match embedded arena")
		if String(encounter.regionId) != "debug" and String(arena_copy.get("regionId", "")) != String(encounter.regionId):
			return _error("encounter region identity does not match embedded arena")
	var embedded_arena_sha := String(arena_copy.get("contentSha256", ""))
	if arena_content_sha256.is_empty():
		arena_content_sha256 = embedded_arena_sha
	if not arena_content_sha256.is_empty():
		if not Arena._sha256_pin(arena_content_sha256) or embedded_arena_sha != arena_content_sha256:
			return _error("arena content pin does not match embedded arena")
	if int(arena_copy.maxBodyRadius) * SCALE < BODY_RADIUS:
		return _error("arena clearance is too small for these fighters")
	var items := item_definitions() if pinned_items.is_empty() else pinned_items.duplicate(true)
	var item_problem := _validate_items(items)
	if not item_problem.is_empty():
		return _error(item_problem)
	for key: Variant in initial_supplies:
		if not key is String or not items.has(key) or not Arena.integer_between(initial_supplies[key], 0, MAX_SUPPLIES):
			return _error("invalid initial item supplies")
	var supplies := {}
	for key: String in items:
		supplies[key] = int(initial_supplies.get(key, 0))
	var fighters: Array = [player_snapshot.duplicate(true), opponent_snapshot.duplicate(true)]
	for fighter: Dictionary in fighters:
		for move_id: String in fighter.moves:
			for key: String in ["mp_cost", "power", "range", "windup", "active", "duration"]:
				fighter.moves[move_id][key] = int(fighter.moves[move_id][key])
	var order: Array = [String(fighters[0].fighter_id), String(fighters[1].fighter_id)]
	for id: Variant in visual_revisions:
		if not id is String or id not in order or not visual_revisions[id] is Dictionary or not visual_revisions[id].has_all(["assetId", "revision"]):
			return _error("visual revisions must reference session fighter IDs")
		for field: String in ["assetId", "revision"]:
			if not visual_revisions[id][field] is String or String(visual_revisions[id][field]).is_empty() or String(visual_revisions[id][field]).length() > 96:
				return _error("visual revisions must pin nonempty asset identities and revisions")
	var actors: Dictionary = {}
	for index: int in range(2):
		var position := Arena.to_fixed(arena_copy.spawns["player" if index == 0 else "opponent"])
		actors[order[index]] = {"fighter_id": order[index], "pos": position, "previous_pos": position.duplicate(),
			"facing": "E" if index == 0 else "W", "action": "idle", "action_tick": 0, "action_duration": 1,
			"hp": int(fighters[index].stats.hp), "mp": int(fighters[index].stats.mp), "order": "auto", "pending_order": "auto", "order_ready_tick": 0,
			"radius": BODY_RADIUS, "action_start": 0, "action_serial": 0, "action_id": "", "aim": position.duplicate(),
			"windup": 0, "active_ticks": 0, "released": false, "hit_targets": [], "evade_vector": [0, 0],
			"seen_threats": {}, "reacted_threats": {}, "next_decision": 1 + index * 3, "path": [], "repath_tick": 0,
			"circle_sign": 1 if index == 0 else -1, "blocked_ticks": 0, "current_move": {},
			"pending_move": "", "move_ready_tick": 0, "move_expires_tick": 0}
	var rng := BattleRng.new(battle_seed)
	var content_revisions := {"arena": {"assetId": arena_copy.assetId, "revision": arena_copy.revision}, "combat": SIMULATION_VERSION, "visuals": visual_revisions.duplicate(true)}
	if not arena_content_sha256.is_empty():
		content_revisions.arena["contentSha256"] = arena_content_sha256
	# Presentation pins are recorded but never consulted by the simulation. This
	# preserves authoritative outcomes while making replay presentation immutable.
	if arena_copy.get("environment") is Dictionary:
		content_revisions["environment"] = arena_copy.environment.duplicate(true)
	var session := {"ok": true, "battle_id": battle_id, "simulation_version": SIMULATION_VERSION,
		"seed": battle_seed & BattleRng.MASK_31, "tick": 0, "max_ticks": max_ticks, "complete": false, "arena": arena_copy,
		"fighters": fighters, "fighter_order": order, "actors": actors, "projectiles": [], "log": [], "commands": [],
		"result": {}, "rng_state": rng.state_value(), "projectile_serial": 0,
		"initial_supplies": supplies.duplicate(true), "supplies": supplies, "item_definitions": items,
		"used_command_ids": {}, "item_ready_tick": 0,
		"content_revisions": content_revisions}
	if not encounter_id.is_empty():
		session["encounter_id"] = encounter_id
		session.content_revisions["encounterId"] = encounter_id
	_emit(session, "battle_started", "", "", "%s faces %s." % [fighters[0].display_name, fighters[1].display_name])
	return session


## {fighter_id, order, tick?}; omitted tick means the next tick. Input order is stable.
## Invalid commands are rejected without altering the battle or recorded input.
static func step(session: Dictionary, commands: Array = []) -> Array:
	if session.get("simulation_version") == "battle-v2":
		return V2.step(session, commands)
	if not bool(session.get("ok", false)) or bool(session.get("complete", true)):
		return []
	var log_start: int = session.log.size()
	session.tick = int(session.tick) + 1
	var rng := BattleRng.new(1)
	rng._state = int(session.rng_state)
	for command: Variant in commands:
		var preview := _preflight(command, session, int(session.tick))
		if not preview.ok:
			continue
		var accepted: Dictionary = preview.command
		_apply_command(session, accepted)
	var threats: Dictionary = {}
	# Both perceive the previous tick before either chooses a new action.
	for id: String in session.fighter_order:
		session.actors[id].previous_pos = session.actors[id].pos.duplicate()
		threats[id] = _observable_threat(session, id)
	for id: String in session.fighter_order:
		_update_actor(session, id, threats[id], rng)
	for id: String in session.fighter_order:
		_advance_attack(session, id)
	_advance_projectiles(session, rng)
	for id: String in session.fighter_order:
		_resolve_melee(session, id, rng)
	session.rng_state = rng.state_value()
	var alive: Array = []
	for id: String in session.fighter_order:
		if int(session.actors[id].hp) > 0:
			alive.append(id)
	if alive.size() < 2:
		_finish(session, "knockout", String(alive[0]) if alive.size() == 1 else "")
	elif int(session.tick) >= int(session.max_ticks):
		_finish(session, "time_limit", "")
	return session.log.slice(log_start)


static func simulate(battle_id: String, battle_seed: int, player_snapshot: Dictionary, opponent_snapshot: Dictionary, max_ticks: int = DEFAULT_MAX_TICKS, arena: Dictionary = {}, visual_revisions: Dictionary = {}) -> Dictionary:
	var session := create_session(battle_id, battle_seed, player_snapshot, opponent_snapshot, arena, max_ticks, visual_revisions)
	while bool(session.ok) and not bool(session.complete):
		step(session)
	return session


static func replay_record(session: Dictionary) -> Dictionary:
	if session.get("simulation_version") == "battle-v2":
		return V2.replay_record(session)
	if not bool(session.get("ok", false)):
		return {}
	var record := {"battle_id": session.battle_id, "simulation_version": session.simulation_version, "seed": session.seed,
		"max_ticks": session.max_ticks, "duration_ticks": session.tick, "fighters": session.fighters.duplicate(true),
		"arena": session.arena.duplicate(true), "content_revisions": session.content_revisions.duplicate(true), "commands": session.commands.duplicate(true),
		"initial_supplies": session.initial_supplies.duplicate(true), "item_definitions": session.item_definitions.duplicate(true)}
	if session.has("encounter_id"):
		record["encounter_id"] = String(session.encounter_id)
	return record


static func replay(record: Dictionary) -> Dictionary:
	if record.get("simulation_version") == "battle-v2":
		return V2.replay(record)
	if not record.has_all(["battle_id", "simulation_version", "seed", "max_ticks", "duration_ticks", "fighters", "arena", "content_revisions", "commands"]):
		return _error("replay fields are missing")
	if record.simulation_version != SIMULATION_VERSION or not record.battle_id is String or not Arena.integer_between(record.seed, -9007199254740991, 9007199254740991):
		return _error("unsupported replay identity or simulation version")
	if not Arena.integer_between(record.max_ticks, 1, MAX_MAX_TICKS) or not Arena.integer_between(record.duration_ticks, 0, int(record.max_ticks)):
		return _error("replay tick bounds are invalid")
	if not record.fighters is Array or record.fighters.size() != 2 or not record.fighters[0] is Dictionary or not record.fighters[1] is Dictionary or not record.arena is Dictionary or not record.commands is Array or record.commands.size() > MAX_MAX_TICKS * 4:
		return _error("replay input shapes are invalid")
	if not record.content_revisions is Dictionary or not record.content_revisions.get("visuals", null) is Dictionary:
		return _error("replay content revisions are invalid")
	if not record.get("initial_supplies") is Dictionary or not record.get("item_definitions") is Dictionary:
		return _error("replay item definitions and initial supplies are missing")
	var session := create_from_record(record)
	if not session.ok:
		return session
	if record.content_revisions != session.content_revisions:
		return _error("replay content revisions do not match embedded arena and rules")
	var previous_tick := 0
	for command: Variant in record.commands:
		if not command is Dictionary or not command.has("tick") or not Arena.integer_between(command.tick, 1, int(record.duration_ticks)) or int(command.tick) < previous_tick or not command.has_all(["kind", "command_id", "fighter_id"]):
			return _error("replay commands are invalid or unordered")
		previous_tick = int(command.tick)
	var cursor := 0
	while int(session.tick) < int(record.duration_ticks) and not bool(session.complete):
		var tick_commands: Array = []
		while cursor < record.commands.size() and int(record.commands[cursor].tick) == int(session.tick) + 1:
			tick_commands.append(record.commands[cursor])
			cursor += 1
		var accepted_before := int(session.commands.size())
		step(session, tick_commands)
		if int(session.commands.size()) - accepted_before != tick_commands.size():
			return _error("replay command rejected by its recorded state")
	if int(session.tick) != int(record.duration_ticks) or cursor != record.commands.size():
		return _error("replay extends past battle completion")
	return session


static func ground_position(actor: Dictionary) -> Vector2:
	return Vector2(float(actor.pos[0]) / SCALE, float(actor.pos[1]) / SCALE)


static func movement_per_tick(snapshot: Dictionary) -> int:
	return 1550 + mini(int(snapshot.stats.speed), 100) * 85


static func reaction_ticks(snapshot: Dictionary) -> int:
	return maxi(3, 20 - mini(int(snapshot.stats.brains), 34) / 2)


## Pure preflight for the NEXT tick. Persist item consumption before passing the
## returned normalized command to step(), with no intervening simulation tick.
static func preflight_command(session: Dictionary, command: Dictionary) -> Dictionary:
	if session.get("simulation_version") != SIMULATION_VERSION:
		return _error("commands require battle-v3")
	return _preflight(command, session, int(session.get("tick", 0)) + 1)



## Batch preflight reserves IDs, supplies and cooldown on an isolated command-only
## copy. This must run immediately before durable item consumption and step().
static func preflight_commands(session: Dictionary, commands: Array) -> Dictionary:
	if session.get("simulation_version") != SIMULATION_VERSION:
		return _error("commands require battle-v3")
	var shadow := session.duplicate(true)
	shadow.tick = int(session.tick) + 1
	var accepted: Array = []
	var rejected: Array = []
	for input: Variant in commands:
		var preview := _preflight(input, shadow, int(shadow.tick))
		if preview.ok:
			accepted.append(preview.command)
			_apply_command(shadow, preview.command)
		else:
			rejected.append({"command": input, "error": preview.error})
	return {"ok": true, "commands": accepted, "rejected": rejected}


static func _apply_command(session: Dictionary, accepted: Dictionary) -> void:
	session.commands.append(accepted.duplicate(true))
	session.used_command_ids[accepted.command_id] = true
	var commanded: Dictionary = session.actors[accepted.fighter_id]
	match accepted.kind:
		"order":
			commanded.pending_order = accepted.order
			commanded.order_ready_tick = int(session.tick) + reaction_ticks(_snapshot(session, accepted.fighter_id))
			_emit(session, "command", accepted.fighter_id, "", "Order acknowledged: %s." % accepted.order, {"order": accepted.order})
		"move_request":
			commanded.pending_move = accepted.move_id
			commanded.move_ready_tick = int(session.tick) + reaction_ticks(_snapshot(session, accepted.fighter_id))
			commanded.move_expires_tick = int(session.tick) + MOVE_REQUEST_TTL
			_emit(session, "move_requested", accepted.fighter_id, "", "Move requested: %s." % accepted.move_id, {"move_id": accepted.move_id})
		"item_use":
			var item: Dictionary = session.item_definitions[accepted.item_id]
			var stat := String(item.stat)
			var before := int(commanded[stat])
			commanded[stat] = mini(int(_snapshot(session, accepted.fighter_id).stats[stat]), before + int(item.amount))
			session.supplies[accepted.item_id] = int(session.supplies[accepted.item_id]) - 1
			session.item_ready_tick = int(session.tick) + ITEM_COOLDOWN_TICKS
			_emit(session, "item_used", accepted.fighter_id, accepted.fighter_id, "%s restores %d %s." % [item.name, int(commanded[stat]) - before, stat.to_upper()], {"item_id": accepted.item_id, "restored": int(commanded[stat]) - before, "command_id": accepted.command_id})


static func _preflight(command: Variant, session: Dictionary, tick: int) -> Dictionary:
	if not bool(session.get("ok", false)) or bool(session.get("complete", true)):
		return _error("battle is complete")
	if not command is Dictionary or not command.get("fighter_id") is String or not session.actors.has(command.fighter_id):
		return _error("unknown fighter")
	if not Arena.integer_between(command.get("tick", tick), tick, tick):
		return _error("command must target the next accepted tick")
	var raw_kind: Variant = command.get("kind", "order" if command.has("order") else "")
	if not raw_kind is String:
		return _error("command kind must be text")
	var kind := String(raw_kind)
	# Old order callers remain compatible; all recorded v3 commands have identities.
	var command_id: Variant = command.get("command_id", "order:%d:%d" % [tick, session.commands.size()] if not command.has("kind") and kind == "order" else "")
	if not command_id is String or command_id.is_empty() or command_id.length() > 128:
		return _error("command identity is missing or invalid")
	if session.used_command_ids.has(command_id):
		return _error("duplicate command")
	var id := String(command.fighter_id)
	var actor: Dictionary = session.actors[id]
	if int(actor.hp) <= 0:
		return _error("fighter is defeated")
	var accepted := {"kind": kind, "command_id": command_id, "fighter_id": id, "tick": tick}
	match kind:
		"order":
			if not command.get("order") is String or command.order not in ORDERS:
				return _error("unknown order")
			accepted.order = command.order
		"move_request":
			if id != String(session.fighter_order[0]):
				return _error("only the companion accepts player move requests")
			var snapshot := _snapshot(session, id)
			if snapshot.stage != "Rookie" or not command.get("move_id") is String or not _equipped(snapshot, command.move_id):
				return _error("move is not learned and equipped")
			if int(actor.mp) < int(snapshot.moves[command.move_id].mp_cost):
				return _error("not enough MP")
			accepted.move_id = command.move_id
		"item_use":
			if id != String(session.fighter_order[0]) or not command.get("item_id") is String or not session.item_definitions.has(command.item_id):
				return _error("invalid companion item")
			var item: Dictionary = session.item_definitions[command.item_id]
			if int(session.supplies.get(command.item_id, 0)) < 1:
				return _error("no items remaining")
			if tick < int(session.item_ready_tick):
				return _error("items are cooling down")
			if int(actor[item.stat]) >= int(_snapshot(session, id).stats[item.stat]):
				return _error("that meter is already full")
			accepted.item_id = command.item_id
		_:
			return _error("unknown command kind")
	return {"ok": true, "command": accepted}


static func _command_valid(command: Variant, session: Dictionary, tick: int) -> bool:
	return bool(_preflight(command, session, tick).ok)


## Rebuild tick-zero state from pinned inputs, dispatching older replay versions.
static func create_from_record(record: Dictionary) -> Dictionary:
	if record.get("simulation_version") == "battle-v2":
		return V2.create_session(record.battle_id, int(record.seed), record.fighters[0], record.fighters[1], record.arena, int(record.max_ticks), record.content_revisions.visuals)
	var arena_pin: Variant = record.get("content_revisions", {}).get("arena", {})
	var arena_sha := String(arena_pin.get("contentSha256", "")) if arena_pin is Dictionary else ""
	return create_session(record.battle_id, int(record.seed), record.fighters[0], record.fighters[1], record.arena, int(record.max_ticks), record.content_revisions.visuals, record.get("initial_supplies", {}), record.get("item_definitions", {}), String(record.get("encounter_id", record.content_revisions.get("encounterId", ""))), arena_sha)


static func _update_actor(session: Dictionary, id: String, threat: Dictionary, rng: BattleRng) -> void:
	var actor: Dictionary = session.actors[id]
	var snapshot := _snapshot(session, id)
	var enemy: Dictionary = session.actors[_enemy_id(session, id)]
	if int(actor.hp) <= 0:
		actor.action = "defeat"
		return
	if not String(actor.pending_move).is_empty() and int(session.tick) >= int(actor.move_expires_tick):
		_emit(session, "move_expired", id, "", "Requested move expired.", {"move_id": actor.pending_move})
		actor.pending_move = ""
	actor.action_tick = int(session.tick) - int(actor.action_start)
	if String(actor.action) not in ["idle", "move", "defeat"] and int(actor.action_tick) >= int(actor.action_duration):
		if actor.action == "guard":
			actor.mp = mini(int(snapshot.stats.mp), int(actor.mp) + GUARD_MP_RECOVERY)
		actor.action = "idle"
		actor.action_tick = 0
		actor.action_duration = 1
	if String(actor.action) in ["idle", "move"] and int(session.tick) >= int(actor.order_ready_tick):
		actor.order = actor.pending_order
	if actor.action == "evade":
		_move(session, id, actor.evade_vector, movement_per_tick(snapshot) * 7 / 4)
		return
	if String(actor.action) not in ["idle", "move"]:
		return # Commands cannot cancel committed windup, attack or recovery.
	var to_enemy := _subtract(enemy.pos, actor.pos)
	actor.facing = _facing(to_enemy)
	if not String(actor.pending_move).is_empty() and int(session.tick) >= int(actor.move_ready_tick):
		var requested: Dictionary = snapshot.moves[actor.pending_move]
		if int(actor.mp) >= int(requested.mp_cost):
			if _move_in_range(session, id, requested):
				_commit_move(session, id, requested)
				actor.pending_move = ""
			else:
				_approach_for_move(session, id)
			return
	if not threat.is_empty():
		var key: String = threat.id
		if not actor.seen_threats.has(key):
			actor.seen_threats[key] = int(session.tick)
		if not actor.reacted_threats.has(key) and int(session.tick) - int(actor.seen_threats[key]) >= reaction_ticks(snapshot):
			actor.reacted_threats[key] = true
			if _start_evasion(session, id, threat, snapshot):
				return
	if int(session.tick) < int(actor.next_decision):
		_tactical_move(session, id)
		return
	actor.next_decision = int(session.tick) + 9
	var distance := _length(to_enemy)
	var visible := Arena.obstruction_fraction(session.arena, actor.pos, enemy.pos, 0, "sight") < 0
	var roll := rng.next_int(100)
	var aggressive: bool = actor.order == "attack" or snapshot.nature in ["Bold", "Stubborn", "Earnest"]
	# A zero-MP creature always closes to melee, regardless of keep-distance order.
	if int(actor.mp) > 0 and actor.order == "defend" and distance < 125 * SCALE and roll < 55:
		_start_action(session, id, "guard", 24, 0, 0)
		return
	for move_id: String in _automatic_moves(snapshot):
		var move: Dictionary = snapshot.moves[move_id]
		if int(actor.mp) >= int(move.mp_cost) and _move_in_range(session, id, move):
			var chance := (76 if actor.order == "keep_distance" else 48) if move.kind == "projectile" else (90 if aggressive else 70)
			if roll < chance:
				_commit_move(session, id, move)
				return
	if visible and distance <= BASIC_RANGE and (int(actor.mp) == 0 or roll < (90 if aggressive else 70)):
		_commit_move(session, id, snapshot.moves[_fallback_id(snapshot.species_id)])
	else:
		_tactical_move(session, id)


static func _tactical_move(session: Dictionary, id: String) -> void:
	var actor: Dictionary = session.actors[id]
	var enemy: Dictionary = session.actors[_enemy_id(session, id)]
	var snapshot := _snapshot(session, id)
	var delta := _subtract(enemy.pos, actor.pos)
	var distance := _length(delta)
	# Approach tolerance must remain inside BASIC_RANGE (38 + 18 < 58).
	var desired := 38 * SCALE
	if int(actor.mp) == 0 or _automatic_moves(snapshot).is_empty():
		desired = 38 * SCALE
	elif actor.order == "keep_distance":
		desired = 175 * SCALE if _has_affordable_projectile(snapshot, int(actor.mp)) else 38 * SCALE
	elif actor.order == "defend":
		desired = 100 * SCALE
	elif snapshot.nature in ["Calm", "Gentle"] and _has_affordable_projectile(snapshot, int(actor.mp)):
		desired = 105 * SCALE
	var vector: Array
	if distance > desired + 18 * SCALE or Arena.obstruction_fraction(session.arena, actor.pos, enemy.pos, 0, "sight") >= 0:
		vector = _approach_vector(session, id, enemy.pos)
	elif distance < desired - 14 * SCALE:
		vector = [-int(delta[0]), -int(delta[1])]
	else:
		vector = [-int(delta[1]) * int(actor.circle_sign), int(delta[0]) * int(actor.circle_sign)]
	var travel := movement_per_tick(snapshot)
	if not actor.path.is_empty():
		travel = mini(travel, _length(vector)) # Do not overshoot close grid waypoints.
	var moved := _move(session, id, vector, travel)
	actor.action = "move" if moved else "idle"
	actor.action_duration = 24
	actor.action_tick = int(session.tick) % 24
	if not moved:
		actor.blocked_ticks = int(actor.blocked_ticks) + 1
		if int(actor.blocked_ticks) >= 12:
			actor.circle_sign = -int(actor.circle_sign)
			actor.repath_tick = 0
			actor.blocked_ticks = 0
	else:
		actor.blocked_ticks = 0


static func _approach_vector(session: Dictionary, id: String, goal: Array) -> Array:
	var actor: Dictionary = session.actors[id]
	if Arena.segment_clear(session.arena, actor.pos, goal, BODY_RADIUS):
		actor.path = []
		return _subtract(goal, actor.pos)
	if int(session.tick) >= int(actor.repath_tick) or actor.path.is_empty():
		actor.path = Arena.path(session.arena, actor.pos, goal, BODY_RADIUS)
		actor.repath_tick = int(session.tick) + 30
	while not actor.path.is_empty() and _length(_subtract(actor.path[0], actor.pos)) < 4 * SCALE:
		actor.path.pop_front()
	return [0, 0] if actor.path.is_empty() else _subtract(actor.path[0], actor.pos)


static func _move(session: Dictionary, id: String, vector: Array, speed: int) -> bool:
	var actor: Dictionary = session.actors[id]
	var other: Dictionary = session.actors[_enemy_id(session, id)]
	var offset := _scaled(vector, speed)
	if offset == [0, 0]:
		return false
	for movement: Array in [offset, [offset[0], 0], [0, offset[1]]]:
		if movement == [0, 0]:
			continue
		var next := [int(actor.pos[0]) + int(movement[0]), int(actor.pos[1]) + int(movement[1])]
		var other_box := [int(other.pos[0]) - BODY_RADIUS * 2, int(other.pos[1]) - BODY_RADIUS * 2, int(other.pos[0]) + BODY_RADIUS * 2, int(other.pos[1]) + BODY_RADIUS * 2]
		var combined := BODY_RADIUS * 2
		var relative_start := _subtract(actor.previous_pos, other.previous_pos)
		var relative_end := _subtract(next, other.pos)
		var relative_hit := Arena.segment_rect_fraction(relative_start, relative_end, [-combined, -combined, combined, combined])
		if relative_hit < 0 and Arena.segment_clear(session.arena, actor.pos, next, BODY_RADIUS) and Arena.segment_rect_fraction(actor.pos, next, other_box) < 0:
			actor.pos = next
			return true
	return false


static func _start_action(session: Dictionary, id: String, action: String, duration: int, windup: int, active: int) -> void:
	var actor: Dictionary = session.actors[id]
	if action in ["basic_attack", "special_attack"] and actor.current_move.is_empty():
		var move_id: String = _snapshot(session, id).special.id if action == "special_attack" else _fallback_id(_snapshot(session, id).species_id)
		actor.current_move = _snapshot(session, id).moves[move_id].duplicate(true)
	elif action not in ["basic_attack", "special_attack"]:
		actor.current_move = {}
	actor.action = action
	actor.action_start = int(session.tick)
	actor.action_tick = 0
	actor.action_duration = duration
	actor.windup = windup
	actor.active_ticks = active
	actor.action_serial = int(actor.action_serial) + 1
	actor.action_id = "%s:%d" % [id, actor.action_serial]
	actor.aim = session.actors[_enemy_id(session, id)].pos.duplicate()
	actor.released = false
	actor.hit_targets = []
	actor.facing = _facing(_subtract(actor.aim, actor.pos))
	_emit(session, "action_started", id, _enemy_id(session, id), "%s prepares %s." % [_snapshot(session, id).display_name, action.replace("_", " ")], {"action_id": action, "move_id": actor.current_move.get("id", ""), "action_name": actor.current_move.get("name", action.replace("_", " ").capitalize()), "windup": windup, "duration": duration, "aim": actor.aim.duplicate()})


## Observes already-visible telegraphs/projectiles, never an enemy's future choices.
static func _observable_threat(session: Dictionary, id: String) -> Dictionary:
	var actor: Dictionary = session.actors[id]
	var enemy: Dictionary = session.actors[_enemy_id(session, id)]
	var box := [int(actor.pos[0]) - BODY_RADIUS - 10 * SCALE, int(actor.pos[1]) - BODY_RADIUS - 10 * SCALE, int(actor.pos[0]) + BODY_RADIUS + 10 * SCALE, int(actor.pos[1]) + BODY_RADIUS + 10 * SCALE]
	if String(enemy.action) in ["basic_attack", "special_attack"] and int(enemy.action_tick) <= int(enemy.windup) and Arena.obstruction_fraction(session.arena, actor.pos, enemy.pos, 0, "sight") < 0:
		var direction := _subtract(enemy.aim, enemy.pos)
		var ray := _scaled(direction, SPECIAL_RANGE if enemy.action == "special_attack" else BASIC_RANGE)
		var finish := [int(enemy.pos[0]) + int(ray[0]), int(enemy.pos[1]) + int(ray[1])]
		if Arena.segment_rect_fraction(enemy.pos, finish, box) >= 0:
			return {"id": enemy.action_id, "origin": enemy.pos.duplicate(), "direction": direction}
	for projectile: Dictionary in session.projectiles:
		if projectile.owner_id == id or Arena.obstruction_fraction(session.arena, actor.pos, projectile.pos, 0, "sight") >= 0:
			continue
		var horizon := _scaled(projectile.velocity, 120 * SCALE)
		var finish := [int(projectile.pos[0]) + int(horizon[0]), int(projectile.pos[1]) + int(horizon[1])]
		if Arena.segment_rect_fraction(projectile.pos, finish, box) >= 0:
			return {"id": projectile.attack_id, "origin": projectile.pos.duplicate(), "direction": projectile.velocity.duplicate()}
	return {}


static func _start_evasion(session: Dictionary, id: String, threat: Dictionary, snapshot: Dictionary) -> bool:
	var actor: Dictionary = session.actors[id]
	var side: Array = [-int(threat.direction[1]) * int(actor.circle_sign), int(threat.direction[0]) * int(actor.circle_sign)]
	var choices: Array = [side, [-int(side[0]), -int(side[1])]]
	if int(snapshot.stats.brains) >= 12:
		choices.append(_subtract(actor.pos, threat.origin))
	var best: Array = []
	var best_clearance := -1
	for choice: Array in choices:
		var delta := _scaled(choice, movement_per_tick(snapshot) * 7 / 4 * 12)
		var finish := [int(actor.pos[0]) + int(delta[0]), int(actor.pos[1]) + int(delta[1])]
		if not Arena.segment_clear(session.arena, actor.pos, finish, BODY_RADIUS) or Arena.boxes_overlap(finish, session.actors[_enemy_id(session, id)].pos, BODY_RADIUS * 2):
			continue
		var clearance := mini(mini(int(finish[0]), int(finish[1])), mini(int(session.arena.ground.width) * SCALE - int(finish[0]), int(session.arena.ground.height) * SCALE - int(finish[1])))
		if clearance > best_clearance:
			best = choice
			best_clearance = clearance
		if int(snapshot.stats.brains) < 12:
			break
	if best.is_empty():
		_start_action(session, id, "guard", 24, 0, 0)
		return true
	_start_action(session, id, "evade", 12, 0, 0)
	actor.evade_vector = best
	_emit(session, "evade", id, _enemy_id(session, id), "%s reacts to an incoming attack." % snapshot.display_name, {"threat_id": threat.id, "reaction_ticks": reaction_ticks(snapshot)})
	_move(session, id, best, movement_per_tick(snapshot) * 7 / 4)
	return true


static func _advance_attack(session: Dictionary, id: String) -> void:
	var actor: Dictionary = session.actors[id]
	if int(actor.hp) <= 0 or actor.action != "special_attack" or int(actor.action_tick) != int(actor.windup) or bool(actor.released):
		return
	actor.released = true
	session.projectile_serial = int(session.projectile_serial) + 1
	var projectile := {"id": int(session.projectile_serial), "owner_id": id, "attack_id": actor.action_id,
		"pos": actor.pos.duplicate(), "previous_pos": actor.pos.duplicate(), "velocity": _scaled(_subtract(actor.aim, actor.pos), PROJECTILE_SPEED),
		"radius": PROJECTILE_RADIUS, "remaining": SPECIAL_RANGE, "born_tick": int(session.tick), "power": int(actor.current_move.power), "move_id": actor.current_move.id}
	session.projectiles.append(projectile)
	_emit(session, "projectile_spawned", id, _enemy_id(session, id), "%s releases %s." % [_snapshot(session, id).display_name, actor.current_move.name], {"action_id": actor.current_move.id, "projectile_id": projectile.id})


static func _advance_projectiles(session: Dictionary, rng: BattleRng) -> void:
	var survivors: Array = []
	for projectile: Dictionary in session.projectiles:
		var target_id := _enemy_id(session, projectile.owner_id)
		var target: Dictionary = session.actors[target_id]
		var start: Array = projectile.pos
		var finish := [int(start[0]) + int(projectile.velocity[0]), int(start[1]) + int(projectile.velocity[1])]
		var block := Arena.obstruction_fraction(session.arena, start, finish, PROJECTILE_RADIUS, "projectile")
		# Relative sweep prevents a moving target tunneling through a moving projectile.
		var target_start: Array = target.pos if int(projectile.born_tick) == int(session.tick) else target.previous_pos
		var relative_start := _subtract(start, target_start)
		var relative_end := _subtract(finish, target.pos)
		var radius := BODY_RADIUS + PROJECTILE_RADIUS
		var hit := Arena.segment_rect_fraction(relative_start, relative_end, [-radius, -radius, radius, radius])
		if hit >= 0 and (block < 0 or hit < block) and int(target.hp) > 0:
			_damage(session, projectile.owner_id, target_id, int(projectile.power), String(projectile.get("move_id", _snapshot(session, projectile.owner_id).special.id)), rng)
			continue
		if block >= 0:
			_emit(session, "projectile_blocked", projectile.owner_id, "", "An obstacle blocks the projectile.", {"projectile_id": projectile.id})
			continue
		projectile.previous_pos = start.duplicate()
		projectile.pos = finish
		projectile.remaining = int(projectile.remaining) - PROJECTILE_SPEED
		if int(projectile.remaining) > 0 and Arena.position_clear(session.arena, finish, PROJECTILE_RADIUS, "projectile"):
			survivors.append(projectile)
	session.projectiles = survivors


static func _resolve_melee(session: Dictionary, id: String, rng: BattleRng) -> void:
	var actor: Dictionary = session.actors[id]
	if int(actor.hp) <= 0 or actor.action != "basic_attack" or int(actor.action_tick) < int(actor.windup) or int(actor.action_tick) >= int(actor.windup) + int(actor.active_ticks):
		return
	var target_id := _enemy_id(session, id)
	if target_id in actor.hit_targets:
		return
	var target: Dictionary = session.actors[target_id]
	var direction := _scaled(_subtract(actor.aim, actor.pos), BASIC_RANGE)
	var finish := [int(actor.pos[0]) + int(direction[0]), int(actor.pos[1]) + int(direction[1])]
	var radius := BODY_RADIUS + 6 * SCALE
	# Exact swept body volume against the fixed attack ray, never homing aim.
	var hit := Arena.swept_box_fraction(actor.pos, finish, target.previous_pos, target.pos, radius)
	var block := Arena.obstruction_fraction(session.arena, actor.pos, finish, 6 * SCALE, "projectile")
	if hit >= 0 and (block < 0 or hit < block) and int(target.hp) > 0:
		actor.hit_targets.append(target_id)
		_damage(session, id, target_id, int(actor.current_move.get("power", 100)), String(actor.current_move.get("id", "basic_attack")), rng)


static func _damage(session: Dictionary, actor_id: String, target_id: String, power: int, action_id: String, rng: BattleRng) -> void:
	var actor: Dictionary = session.actors[actor_id]
	var target: Dictionary = session.actors[target_id]
	var snapshot := _snapshot(session, actor_id)
	var enemy_snapshot := _snapshot(session, target_id)
	var amount := maxi(1, int(snapshot.stats.offense) * power / 100 - int(enemy_snapshot.stats.defense) * 45 / 100 + int(snapshot.stats.brains) / 20 + rng.range_inclusive(-2, 2))
	var guarded: bool = target.action == "guard"
	if guarded:
		amount = maxi(1, (amount + 1) / 2)
	target.hp = maxi(0, int(target.hp) - amount)
	_emit(session, "hit", actor_id, target_id, "%s hits %s for %d%s." % [snapshot.display_name, enemy_snapshot.display_name, amount, " through guard" if guarded else ""], {"action_id": action_id, "damage": amount, "guarded": guarded, "target_hp": target.hp, "actor_mp": actor.mp})
	if int(target.hp) <= 0:
		target.action = "defeat"
		target.action_start = int(session.tick)
		target.action_tick = 0
		target.action_duration = 30
	elif target.action in ["idle", "move"]:
		target.action = "hit"
		target.action_start = int(session.tick)
		target.action_tick = 0
		target.action_duration = 6


static func _finish(session: Dictionary, reason: String, winner_id: String) -> void:
	session.complete = true
	var hp: Dictionary = {}
	var mp: Dictionary = {}
	for id: String in session.fighter_order:
		hp[id] = int(session.actors[id].hp)
		mp[id] = int(session.actors[id].mp)
	var outcome := "draw" if winner_id.is_empty() else ("win" if winner_id == session.fighter_order[0] else "loss")
	session.result = {"outcome": outcome, "winner_id": winner_id, "reason": reason, "ticks": int(session.tick), "duration_seconds": float(session.tick) / TICKS_PER_SECOND, "final_hp": hp, "final_mp": mp}
	_emit(session, "battle_finished", winner_id, "", "Training battle complete: %s." % outcome)


static func _emit(session: Dictionary, event: String, actor_id: String, target_id: String, message: String, extra: Dictionary = {}) -> void:
	var entry := {"tick": int(session.tick), "event": event, "actor_id": actor_id, "target_id": target_id, "action_id": "", "action_name": "", "damage": 0, "target_hp": 0, "actor_mp": 0, "guarded": false, "message": message}
	entry.merge(extra, true)
	session.log.append(entry)


static func _snapshot(session: Dictionary, id: String) -> Dictionary:
	return session.fighters[0] if session.fighter_order[0] == id else session.fighters[1]


static func _enemy_id(session: Dictionary, id: String) -> String:
	return session.fighter_order[1] if session.fighter_order[0] == id else session.fighter_order[0]


static func _subtract(a: Array, b: Array) -> Array:
	return [int(a[0]) - int(b[0]), int(a[1]) - int(b[1])]


static func _length(vector: Array) -> int:
	var squared := int(vector[0]) * int(vector[0]) + int(vector[1]) * int(vector[1])
	if squared == 0:
		return 0
	var root := squared
	var next := (root + 1) / 2
	while next < root:
		root = next
		next = (root + squared / root) / 2
	return root


static func _scaled(vector: Array, magnitude: int) -> Array:
	var length := _length(vector)
	return [0, 0] if length == 0 else [int(vector[0]) * magnitude / length, int(vector[1]) * magnitude / length]


static func _facing(vector: Array) -> String:
	var x := int(vector[0])
	var y := int(vector[1])
	if absi(y) * 1000 < absi(x) * 414:
		return "E" if x >= 0 else "W"
	if absi(x) * 1000 < absi(y) * 414:
		return "S" if y >= 0 else "N"
	return ("S" if y >= 0 else "N") + ("E" if x >= 0 else "W")


static func validate_snapshot(snapshot: Dictionary) -> String:
	var base := snapshot.duplicate(true)
	base.erase("moves")
	base.erase("skills")
	var problem := V2.validate_snapshot(base)
	if not problem.is_empty():
		return problem
	if not snapshot.get("moves") is Dictionary or not snapshot.get("skills") is Dictionary:
		return "pinned moves and skills are required"
	var moves: Dictionary = snapshot.moves
	var fallback := _fallback_id(snapshot.species_id)
	if not moves.has(fallback) or not moves.has(snapshot.special.id):
		return "permanent melee fallback is missing"
	for id: Variant in moves:
		if not id is String or not moves[id] is Dictionary:
			return "invalid move shape"
		var move: Dictionary = moves[id]
		if not move.has_all(["id", "name", "kind", "mp_cost", "power", "range", "windup", "active", "duration"]) or move.id != id or not move.name is String or move.kind not in ["melee", "projectile"]:
			return "invalid move identity"
		for key: String in ["mp_cost", "power", "range", "windup", "active", "duration"]:
			if not Arena.integer_between(move[key], 0, MAX_MP * SCALE):
				return "invalid move numeric value"
		if int(move.power) < 1 or int(move.power) > 500 or int(move.duration) < 1 or int(move.duration) > 300 or int(move.active) < 1 or int(move.windup) + int(move.active) > int(move.duration) or int(move.range) != (BASIC_RANGE if move.kind == "melee" else SPECIAL_RANGE):
			return "invalid move combat bounds"
	if moves[fallback].kind != "melee" or int(moves[fallback].mp_cost) != 0:
		return "fallback must be free melee"
	var skills: Dictionary = snapshot.skills
	if not skills.get("learned") is Array or not skills.get("equipped") is Array or skills.equipped.size() > 3:
		return "invalid skill loadout"
	var seen := {}
	for id: Variant in skills.learned:
		if not id is String or not moves.has(id) or id == fallback or seen.has(id):
			return "invalid learned move"
		seen[id] = true
	seen.clear()
	for slot: Variant in skills.equipped:
		if not slot is Dictionary or not slot.get("move_id") is String or not slot.get("auto") is bool or slot.move_id not in skills.learned or seen.has(slot.move_id):
			return "invalid equipped move"
		seen[slot.move_id] = true
	return ""



static func _fallback_id(species: String) -> String:
	return String(Definitions.SPECIES.get(species, Definitions.SPECIES.botamon).basic_move)


static func default_skills(species: String) -> Dictionary:
	return Definitions.default_skills(species)


## Pinned, normalized definitions are independent of future balance-file changes.
static func move_definitions(species: String) -> Dictionary:
	var moves := {}
	var ids: Array = [_fallback_id(species)]
	if species == "agumon":
		ids.append_array(["quick_bite", "heavy_claw"])
	for id: String in ids:
		var source: Dictionary = Definitions.MOVES[id]
		moves[id] = {"id": id, "name": source.name, "kind": "melee", "mp_cost": int(source.mp),
			"power": int(source.power), "range": BASIC_RANGE, "windup": int(source.get("windup", 20)),
			"active": int(source.get("active", 3)), "duration": int(source.get("duration", 36))}
	var special := _special_for_species(species)
	moves[special.id] = {"id": special.id, "name": special.name, "kind": "projectile", "mp_cost": special.mp_cost,
		"power": special.power, "range": SPECIAL_RANGE, "windup": 27, "active": 1, "duration": 50}
	return moves


static func item_definitions() -> Dictionary:
	var result := {}
	for id: String in Definitions.ITEMS:
		var source: Dictionary = Definitions.ITEMS[id]
		result[id] = {"name": source.name, "stat": source.stat, "amount": int(source.restore)}
	return result


static func _validate_items(items: Dictionary) -> String:
	if items.size() != 2 or not items.has_all(["small_recovery", "mp_recovery"]):
		return "item definitions are missing"
	for id: String in items:
		var item: Variant = items[id]
		if not item is Dictionary or not item.get("name") is String or item.get("stat") not in ["hp", "mp"] or not Arena.integer_between(item.get("amount"), 1, MAX_HP):
			return "invalid item definition"
	return ""


static func _equipped(snapshot: Dictionary, id: String) -> bool:
	if id not in snapshot.skills.learned or not snapshot.moves.has(id):
		return false
	for slot: Dictionary in snapshot.skills.equipped:
		if slot.move_id == id:
			return true
	return false


static func _automatic_moves(snapshot: Dictionary) -> Array[String]:
	var result: Array[String] = []
	if snapshot.stage != "Rookie":
		result.append(String(snapshot.special.id))
		return result
	for slot: Dictionary in snapshot.skills.equipped:
		if bool(slot.auto):
			result.append(String(slot.move_id))
	return result


static func _has_affordable_projectile(snapshot: Dictionary, mp: int) -> bool:
	for id: String in _automatic_moves(snapshot):
		var move: Dictionary = snapshot.moves[id]
		if move.kind == "projectile" and mp >= int(move.mp_cost):
			return true
	return false


static func _move_in_range(session: Dictionary, id: String, move: Dictionary) -> bool:
	var actor: Dictionary = session.actors[id]
	var enemy: Dictionary = session.actors[_enemy_id(session, id)]
	if _length(_subtract(enemy.pos, actor.pos)) > int(move.range):
		return false
	if Arena.obstruction_fraction(session.arena, actor.pos, enemy.pos, 0, "sight") >= 0:
		return false
	return move.kind == "melee" or Arena.obstruction_fraction(session.arena, actor.pos, enemy.pos, PROJECTILE_RADIUS, "projectile") < 0


static func _approach_for_move(session: Dictionary, id: String) -> void:
	var actor: Dictionary = session.actors[id]
	var enemy: Dictionary = session.actors[_enemy_id(session, id)]
	var vector := _approach_vector(session, id, enemy.pos)
	var speed := mini(movement_per_tick(_snapshot(session, id)), _length(vector))
	actor.action = "move" if _move(session, id, vector, speed) else "idle"
	actor.action_duration = 24
	actor.action_tick = int(session.tick) % 24


static func _commit_move(session: Dictionary, id: String, move: Dictionary) -> void:
	var actor: Dictionary = session.actors[id]
	actor.mp = int(actor.mp) - int(move.mp_cost)
	actor.current_move = move.duplicate(true)
	_start_action(session, id, "special_attack" if move.kind == "projectile" else "basic_attack", int(move.duration), int(move.windup), int(move.active))


static func _special_for_species(species_id: String) -> Dictionary:
	match species_id:
		"agumon": return {"id": "pepper_breath", "name": "Pepper Breath", "power": 150, "mp_cost": SPECIAL_MP_COST}
		"koromon": return {"id": "bubble_blow", "name": "Bubble Blow", "power": 140, "mp_cost": SPECIAL_MP_COST}
		_: return {"id": "acid_bubbles", "name": "Acid Bubbles", "power": 130, "mp_cost": SPECIAL_MP_COST}


static func _error(message: String) -> Dictionary:
	return {"ok": false, "error": message}
