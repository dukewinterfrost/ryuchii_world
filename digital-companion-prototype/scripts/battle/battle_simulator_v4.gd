class_name BattleSimulatorV4
extends RefCounted

## Pure deterministic 30 Hz rules. All content is supplied and pinned at creation.
## No files, Nodes, real-time clock, or engine RNG are consulted by these rules.
const Arena = preload("res://scripts/battle/battle_arena.gd")
# Only pure snapshot validation/normalization methods are used; never defaults/reload.
const ContentSchema = preload("res://scripts/battle/combat_content.gd")
const TICKS_PER_SECOND := 30
const SCALE := 1000
const SIMULATION_VERSION := "battle-v4"
const DEFAULT_MAX_TICKS := 3600
const MAX_MAX_TICKS := 3600
const MAX_SUPPLIES := 1000000000
const BODY_RADIUS := 14000
const ORDERS := ["auto", "attack", "defend", "keep_distance"]
const SUPPORTED_NATURES := ["Bold", "Gentle", "Jolly", "Calm", "Earnest", "Stubborn"]
const ATTACKS := ["basic_attack", "special_attack", "rush_attack"]
const FALLBACKS := {"botamon": "tackle", "koromon": "headbutt", "agumon": "claw"}
const SPECIALS := {"botamon": "acid_bubbles", "koromon": "bubble_blow", "agumon": "pepper_breath"}


static func create_session(battle_id: String, battle_seed: int, player: Dictionary, opponent: Dictionary, arena: Dictionary, max_ticks: int, visuals: Dictionary, supplies: Dictionary, items: Dictionary, encounter_id: String, arena_sha: String, config: Dictionary) -> Dictionary:
	var field: Dictionary = Arena.graybox() if arena.is_empty() else arena
	var arena_problem := Arena.validate(field)
	if not arena_problem.is_empty():
		return _error("invalid arena: " + arena_problem)
	if not field.get("spawns") is Dictionary or not field.spawns.has_all(["player", "opponent"]):
		return _error("arena spawns are missing")
	var roster: Array = []
	for index: int in range(2):
		var fighter: Dictionary = (player if index == 0 else opponent).duplicate(true)
		fighter.team_id = "player" if index == 0 else "enemy"
		fighter.controller_id = "player" if index == 0 else ""
		fighter.spawn = field.spawns["player" if index == 0 else "opponent"].duplicate()
		roster.append(fighter)
	return create_roster_session(battle_id, battle_seed, roster, field, max_ticks, visuals, supplies, items, encounter_id, arena_sha, config)


## Roster entries are snapshots plus team_id, controller_id and arena-unit spawn.
static func create_roster_session(battle_id: String, battle_seed: int, roster: Array, arena: Dictionary, max_ticks: int, visuals: Dictionary, initial_supplies: Dictionary, pinned_items: Dictionary, encounter_id: String, arena_sha: String, config: Dictionary) -> Dictionary:
	if battle_id.strip_edges().is_empty() or battle_id.length() > 96 or encounter_id.length() > 96:
		return _error("invalid battle or encounter identity")
	if max_ticks < 1 or max_ticks > MAX_MAX_TICKS:
		return _error("max_ticks must be between 1 and 3600")
	var problem := validate_config(config)
	if not problem.is_empty():
		return _error("invalid combat configuration: " + problem)
	var field: Dictionary = _integer_copy(Arena.graybox() if arena.is_empty() else arena)
	problem = Arena.validate(field)
	if not problem.is_empty():
		return _error("invalid arena: " + problem)
	if int(field.maxBodyRadius) * SCALE < BODY_RADIUS:
		return _error("arena clearance is too small for these fighters")
	var embedded_sha := String(field.get("contentSha256", ""))
	if arena_sha.is_empty():
		arena_sha = embedded_sha
	if not arena_sha.is_empty() and (not Arena._sha256_pin(arena_sha) or arena_sha != embedded_sha):
		return _error("arena content pin does not match embedded arena")
	if roster.size() < 2 or roster.size() > 24:
		return _error("roster must contain 2–24 fighters")
	var normalized: Dictionary = _integer_copy(config)
	var items: Dictionary = normalized.items if pinned_items.is_empty() else _integer_copy(pinned_items)
	problem = _validate_items(items)
	if not problem.is_empty():
		return _error(problem)
	# Item overrides are pinned as part of the full configuration too.
	normalized.items = items.duplicate(true)
	normalized.sha256 = ContentSchema.snapshot_hash(normalized)
	problem = validate_config(normalized)
	if not problem.is_empty():
		return _error(problem)
	var supplies := {}
	for key: Variant in initial_supplies:
		if not key is String or not items.has(key) or not Arena.integer_between(initial_supplies[key], 0, MAX_SUPPLIES):
			return _error("invalid initial item supplies")
	for key: String in items:
		supplies[key] = int(initial_supplies.get(key, 0))
	var fighters: Array = []
	var actors := {}
	var order: Array = []
	var teams := {}
	for input: Variant in roster:
		if not input is Dictionary:
			return _error("invalid roster entry")
		problem = validate_snapshot(input)
		if not problem.is_empty():
			return _error("invalid fighter snapshot: " + problem)
		for key: String in ["team_id", "controller_id"]:
			if not input.get(key) is String or String(input[key]).length() > 96 or (key == "team_id" and String(input[key]).is_empty()):
				return _error("roster team/controller identities are invalid")
		if not input.get("spawn") is Array or input.spawn.size() != 2:
			return _error("roster spawn must contain two arena-unit coordinates")
		for axis: int in range(2):
			if not Arena.integer_between(input.spawn[axis], 0, 4096):
				return _error("roster spawn coordinates are invalid")
		var fighter: Dictionary = _integer_copy(input)
		for move_id: String in fighter.moves:
			if not normalized.moves.has(move_id) or normalized.moves[move_id] != fighter.moves[move_id]:
				return _error("fighter move does not match pinned combat configuration: " + move_id)
		var id := String(fighter.fighter_id)
		if actors.has(id):
			return _error("fighter IDs must be unique")
		var pos := Arena.to_fixed(fighter.spawn)
		if not Arena.position_clear(field, pos, BODY_RADIUS):
			return _error("roster spawn has no body clearance")
		for previous: String in order:
			if Arena.boxes_overlap(pos, actors[previous].pos, BODY_RADIUS * 2):
				return _error("roster spawn bodies overlap")
		teams[fighter.team_id] = true
		order.append(id)
		fighters.append(fighter)
		actors[id] = {"fighter_id": id, "team_id": fighter.team_id, "controller_id": fighter.controller_id,
			"pos": pos, "previous_pos": pos.duplicate(), "facing": "E", "hp": int(fighter.stats.hp), "mp": int(fighter.stats.mp),
			"action": "idle", "phase": "idle", "action_tick": 0, "action_duration": 1, "action_start": 0,
			"action_serial": 0, "action_id": "", "radius": BODY_RADIUS, "aim": pos.duplicate(), "direction": [0, 0],
			"windup": 0, "active_ticks": 0, "released": false, "hit_targets": [], "current_move": {},
			"order": "auto", "pending_order": "auto", "order_ready_tick": 0, "pending_move": "", "move_ready_tick": 0, "move_expires_tick": 0,
			"cooldowns": {}, "manual_defense_ready_tick": 0, "ai_defense_ready_tick": 0, "defense_manual": false, "guard_perfect_used": false,
			"evade_vector": [0, 0], "seen_threats": {}, "reacted_threats": {}, "next_decision": 1,
			"path": [], "repath_tick": 0, "circle_sign": 1, "blocked_ticks": 0, "tactic": "approach", "tactic_until": 0,
			"target_id": "", "effects": {}, "opening_pending": bool(normalized.natures[fighter.nature].opening_tackle)}
	if teams.size() < 2:
		return _error("battle requires at least two hostile teams")
	for id: Variant in visuals:
		if not id is String or not actors.has(id) or not visuals[id] is Dictionary:
			return _error("invalid visual fighter identity")
		for key: String in ["assetId", "revision"]:
			if not visuals[id].get(key) is String or String(visuals[id][key]).is_empty() or String(visuals[id][key]).length() > 96:
				return _error("visual revision identity is invalid")
	var revisions := {"arena": {"assetId": field.assetId, "revision": field.revision}, "combat": SIMULATION_VERSION, "visuals": visuals.duplicate(true)}
	if not arena_sha.is_empty():
		revisions.arena["contentSha256"] = arena_sha
	if field.get("environment") is Dictionary:
		revisions.environment = field.environment.duplicate(true)
	if not encounter_id.is_empty():
		revisions.encounterId = encounter_id
	var rng := BattleRng.new(battle_seed)
	var session := {"ok": true, "battle_id": battle_id, "simulation_version": SIMULATION_VERSION,
		"seed": battle_seed & BattleRng.MASK_31, "tick": 0, "max_ticks": max_ticks, "complete": false,
		"arena": field, "fighters": fighters, "roster": fighters.duplicate(true), "fighter_order": order, "actors": actors,
		"projectiles": [], "projectile_serial": 0, "log": [], "commands": [], "result": {}, "rng_state": rng.state_value(),
		"combat_config": normalized, "item_definitions": items.duplicate(true), "initial_supplies": supplies.duplicate(true), "supplies": supplies,
		"used_command_ids": {}, "item_ready_tick": 0, "content_revisions": revisions}
	if not encounter_id.is_empty():
		session.encounter_id = encounter_id
	for id: String in order:
		session.actors[id].target_id = _nearest_enemy(session, id)
		if String(session.actors[id].target_id).is_empty():
			return _error("roster fighter has no reachable hostile target")
		session.actors[id].facing = _facing(_subtract(session.actors[session.actors[id].target_id].pos, session.actors[id].pos))
	_emit(session, "battle_started", "", "", "%d creatures enter the arena." % fighters.size())
	return session


static func step(session: Dictionary, commands: Array = []) -> Array:
	if not bool(session.get("ok", false)) or bool(session.get("complete", true)) or session.get("simulation_version") != SIMULATION_VERSION:
		return []
	var log_start: int = session.log.size()
	var threats := {}
	# Perception is sampled before this tick's commands/actions. No clairvoyant AI.
	for id: String in session.fighter_order:
		session.actors[id].previous_pos = session.actors[id].pos.duplicate()
		threats[id] = _observable_threat(session, id)
	session.tick = int(session.tick) + 1
	_expire_effects(session)
	for command: Variant in commands:
		var preview := _preflight(command, session, int(session.tick))
		if bool(preview.ok):
			_apply_command(session, preview.command)
	var rng := BattleRng.new(1)
	rng._state = int(session.rng_state)
	for id: String in session.fighter_order:
		_update_actor(session, id, threats[id], rng)
	var hits: Array = []
	# Collect all strikes before applying any damage: same-tick trades can draw.
	for id: String in session.fighter_order:
		_advance_attack(session, id, hits)
	_advance_projectiles(session, hits)
	for hit: Dictionary in hits:
		_damage(session, hit, rng)
	for id: String in session.fighter_order:
		if int(session.actors[id].hp) <= 0:
			session.actors[id].action = "defeat"
			session.actors[id].phase = "idle"
	session.rng_state = rng.state_value()
	var alive_teams := {}
	for id: String in session.fighter_order:
		if int(session.actors[id].hp) > 0:
			alive_teams[session.actors[id].team_id] = true
	if alive_teams.size() <= 1:
		_finish(session, "knockout", String(alive_teams.keys()[0]) if alive_teams.size() == 1 else "")
	elif int(session.tick) >= int(session.max_ticks):
		_finish(session, "time_limit", "")
	return session.log.slice(log_start)


static func preflight_command(session: Dictionary, command: Dictionary) -> Dictionary:
	return _preflight(command, session, int(session.get("tick", 0)) + 1)


static func preflight_commands(session: Dictionary, commands: Array) -> Dictionary:
	if session.get("simulation_version") != SIMULATION_VERSION:
		return _error("commands require battle-v4")
	var shadow := session.duplicate(true)
	shadow.tick = int(session.tick) + 1
	_expire_effects(shadow)
	var accepted: Array = []
	var rejected: Array = []
	for command: Variant in commands:
		var preview := _preflight(command, shadow, int(shadow.tick))
		if bool(preview.ok):
			accepted.append(preview.command)
			_apply_command(shadow, preview.command)
		else:
			rejected.append({"command": command, "error": preview.error})
	return {"ok": true, "commands": accepted, "rejected": rejected}


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
	var raw_id: Variant = command.get("command_id", "order:%d:%d" % [tick, session.commands.size()] if not command.has("kind") and kind == "order" else "")
	if not raw_id is String or String(raw_id).is_empty() or String(raw_id).length() > 128:
		return _error("command identity is missing or invalid")
	if session.used_command_ids.has(raw_id):
		return _error("duplicate command")
	var id := String(command.fighter_id)
	var actor: Dictionary = session.actors[id]
	if actor.controller_id != "player":
		return _error("fighter is not controlled by this player")
	if int(actor.hp) <= 0:
		return _error("fighter is defeated")
	var accepted := {"kind": kind, "command_id": String(raw_id), "fighter_id": id, "tick": tick}
	match kind:
		"order":
			if not command.get("order") is String or command.order not in ORDERS:
				return _error("unknown order")
			accepted.order = command.order
		"move_request":
			var snapshot := _snapshot(session, id)
			if snapshot.stage != "Rookie" or not command.get("move_id") is String or not _equipped(snapshot, command.move_id):
				return _error("move is not learned and equipped")
			if int(actor.mp) < int(snapshot.moves[command.move_id].mp_cost):
				return _error("not enough MP")
			accepted.move_id = command.move_id
		"defense_request":
			if command.get("defense") not in ["dodge", "guard"]:
				return _error("unknown defense")
			if tick < int(actor.manual_defense_ready_tick):
				return _error("defense is cooling down")
			var phase := phase_at(actor, tick)
			if phase in ["active", "recovery"] or (actor.action == "hit" and tick - int(actor.action_start) < int(actor.action_duration)):
				return _error("attack or recovery is committed")
			accepted.defense = command.defense
		"item_use":
			if not command.get("item_id") is String or not session.item_definitions.has(command.item_id):
				return _error("unknown item")
			if int(session.supplies.get(command.item_id, 0)) < 1:
				return _error("no items remaining")
			if tick < int(session.item_ready_tick):
				return _error("items are cooling down")
			var item: Dictionary = session.item_definitions[command.item_id]
			if item.effect == "restore":
				if int(actor[item.stat]) >= int(_snapshot(session, id).stats[item.stat]):
					return _error("that meter is already full")
			elif actor.effects.has(item.effect) and int(actor.effects[item.effect].expires_tick) > tick:
				return _error("that effect is already active")
			accepted.item_id = command.item_id
		_:
			return _error("unknown command kind")
	return {"ok": true, "command": accepted}


static func _apply_command(session: Dictionary, command: Dictionary) -> void:
	session.commands.append(command.duplicate(true))
	session.used_command_ids[command.command_id] = true
	var actor: Dictionary = session.actors[command.fighter_id]
	match command.kind:
		"order":
			actor.pending_order = command.order
			actor.order_ready_tick = int(session.tick) + reaction_ticks(_snapshot(session, command.fighter_id), session.combat_config.tuning)
			_emit(session, "command", command.fighter_id, "", "Order acknowledged: %s." % command.order, {"order": command.order})
		"move_request":
			actor.pending_move = command.move_id
			actor.move_ready_tick = int(session.tick)
			actor.move_expires_tick = int(session.tick) + _tune(session, "move_request_ttl")
			_emit(session, "move_requested", command.fighter_id, "", "Move requested: %s." % command.move_id, {"move_id": command.move_id})
		"defense_request":
			if phase_at(actor, int(session.tick)) == "charge":
				_emit(session, "charge_cancelled", command.fighter_id, actor.target_id, "Charging canceled; MP and cooldown remain spent.", {"move_id": actor.current_move.id})
			_start_defense(session, command.fighter_id, String(command.defense), true, _observable_threat(session, command.fighter_id))
		"item_use":
			var item: Dictionary = session.item_definitions[command.item_id]
			var restored := 0
			if item.effect == "restore":
				var before := int(actor[item.stat])
				actor[item.stat] = mini(int(_snapshot(session, command.fighter_id).stats[item.stat]), before + int(item.amount))
				restored = int(actor[item.stat]) - before
			elif item.effect == "barrier":
				actor.effects.barrier = {"amount": int(item.amount), "expires_tick": int(session.tick) + int(item.duration_ticks)}
			elif item.effect == "haste":
				actor.effects.haste = {"movement_multiplier": int(item.movement_multiplier), "expires_tick": int(session.tick) + int(item.duration_ticks)}
			session.supplies[command.item_id] = int(session.supplies[command.item_id]) - 1
			session.item_ready_tick = int(session.tick) + _tune(session, "item_cooldown")
			_emit(session, "item_used", command.fighter_id, command.fighter_id, "%s used." % item.name, {"item_id": command.item_id, "restored": restored, "command_id": command.command_id, "effect": item.effect})


static func phase_at(actor: Dictionary, tick: int) -> String:
	if actor.action not in ATTACKS:
		return "idle"
	var elapsed := tick - int(actor.action_start)
	if elapsed >= int(actor.action_duration):
		return "idle"
	if elapsed < int(actor.windup):
		return "charge"
	if elapsed < int(actor.windup) + int(actor.active_ticks):
		return "active"
	return "recovery"


static func _update_actor(session: Dictionary, id: String, threat: Dictionary, rng: BattleRng) -> void:
	var actor: Dictionary = session.actors[id]
	if int(actor.hp) <= 0:
		return
	var snapshot := _snapshot(session, id)
	var tick := int(session.tick)
	# Register visible tells even while committed. The reaction deadline never
	# starts until perception, and only free actors may act on it.
	if not threat.is_empty() and not actor.seen_threats.has(threat.id):
		actor.seen_threats[threat.id] = tick + maxi(1, reaction_ticks(snapshot, session.combat_config.tuning) + rng.range_inclusive(-_tune(session, "reaction_jitter"), _tune(session, "reaction_jitter")))
	actor.action_tick = tick - int(actor.action_start)
	actor.phase = phase_at(actor, tick)
	if not String(actor.pending_move).is_empty() and tick >= int(actor.move_expires_tick):
		_emit(session, "move_expired", id, "", "Requested move expired.", {"move_id": actor.pending_move})
		actor.pending_move = ""
	if actor.action not in ["idle", "move", "defeat"] and int(actor.action_tick) >= int(actor.action_duration):
		if actor.action in ATTACKS:
			# A deliberate reposition beat separates committed attacks, giving the
			# opponent a visible opening and autonomous defense time to respond.
			_choose_tactic(session, id, rng)
			actor.next_decision = int(actor.tactic_until)
		if actor.action == "guard":
			actor.mp = mini(int(snapshot.stats.mp), int(actor.mp) + _tune(session, "guard_mp_recovery"))
		actor.action = "idle"
		actor.phase = "idle"
		actor.current_move = {}
	if actor.action == "evade":
		if not _move(session, id, actor.evade_vector, _speed(session, id) * _tune(session, "dodge_multiplier") / 1000):
			if int(actor.blocked_ticks) == 0:
				_emit(session, "dodge_blocked", id, "", "No clear escape path.")
			actor.blocked_ticks = int(actor.blocked_ticks) + 1
		return
	if actor.action in ATTACKS:
		if actor.phase == "charge" and bool(actor.current_move.movement_while_casting):
			_move(session, id, actor.direction, _speed(session, id))
		return
	if actor.action not in ["idle", "move"]:
		return
	actor.target_id = _nearest_enemy(session, id)
	if String(actor.target_id).is_empty():
		return
	var enemy: Dictionary = session.actors[actor.target_id]
	if tick >= int(actor.order_ready_tick):
		actor.order = actor.pending_order
	actor.facing = _facing(_subtract(enemy.pos, actor.pos))
	if not String(actor.pending_move).is_empty():
		var requested: Dictionary = snapshot.moves[actor.pending_move]
		if _available(actor, requested, tick):
			if _move_in_range(session, id, requested):
				_commit_move(session, id, requested)
				actor.pending_move = ""
			else:
				_approach_for_move(session, id)
			return
	if not threat.is_empty() and tick >= int(actor.ai_defense_ready_tick):
		var key := String(threat.id)
		if not actor.seen_threats.has(key):
			actor.seen_threats[key] = tick + maxi(1, reaction_ticks(snapshot, session.combat_config.tuning) + rng.range_inclusive(-_tune(session, "reaction_jitter"), _tune(session, "reaction_jitter")))
		if not actor.reacted_threats.has(key) and tick >= int(actor.seen_threats[key]):
			actor.reacted_threats[key] = true
			var nature: Dictionary = session.combat_config.natures[snapshot.nature]
			_start_defense(session, id, "guard" if rng.next_int(100) < int(nature.guard_weight) else "dodge", false, threat)
			return
	if bool(actor.opening_pending):
		var tackle: Dictionary = snapshot.moves.opening_tackle
		if _move_in_range(session, id, tackle):
			actor.opening_pending = false
			_commit_move(session, id, tackle)
		else:
			_approach_for_move(session, id)
		return
	if tick >= int(actor.tactic_until):
		_choose_tactic(session, id, rng)
	if tick >= int(actor.next_decision):
		actor.next_decision = tick + rng.range_inclusive(_tune(session, "decision_min"), _tune(session, "decision_max"))
		var candidates: Array = []
		var total_weight := 0
		for move_id: String in _automatic_moves(snapshot):
			var move: Dictionary = snapshot.moves[move_id]
			if _available(actor, move, tick) and _move_in_range(session, id, move) and int(move.auto_weight) > 0:
				candidates.append(move)
				total_weight += int(move.auto_weight)
		var fallback: Dictionary = snapshot.moves[FALLBACKS[snapshot.species_id]]
		if _available(actor, fallback, tick) and _move_in_range(session, id, fallback):
			candidates.append(fallback)
			total_weight += maxi(1, int(fallback.auto_weight))
		var nature: Dictionary = session.combat_config.natures[snapshot.nature]
		var chance := clampi(int(nature.attack_weight) + (20 if actor.order == "attack" else 0), 0, 100)
		if total_weight > 0 and rng.next_int(100) < chance:
			var roll := rng.next_int(total_weight)
			for move: Dictionary in candidates:
				roll -= maxi(1, int(move.auto_weight))
				if roll < 0:
					_commit_move(session, id, move)
					return
	_tactical_move(session, id)


static func _choose_tactic(session: Dictionary, id: String, rng: BattleRng) -> void:
	var actor: Dictionary = session.actors[id]
	var nature: Dictionary = session.combat_config.natures[_snapshot(session, id).nature]
	var weights: Array = [int(nature.approach_weight), int(nature.circle_weight), int(nature.retreat_weight)]
	if actor.order == "attack":
		weights[0] += 50
	elif actor.order in ["defend", "keep_distance"]:
		weights[2] += 35
	var roll := rng.next_int(maxi(1, int(weights[0]) + int(weights[1]) + int(weights[2])))
	actor.tactic = "approach" if roll < int(weights[0]) else ("circle" if roll < int(weights[0]) + int(weights[1]) else "retreat")
	actor.circle_sign = 1 if rng.next_int(2) == 0 else -1
	actor.tactic_until = int(session.tick) + rng.range_inclusive(_tune(session, "tactical_commit_min"), _tune(session, "tactical_commit_max"))


static func _tactical_move(session: Dictionary, id: String) -> void:
	var actor: Dictionary = session.actors[id]
	var enemy: Dictionary = session.actors[actor.target_id]
	var snapshot := _snapshot(session, id)
	var delta := _subtract(enemy.pos, actor.pos)
	var distance := _length(delta)
	var melee_range := int(snapshot.moves[FALLBACKS[snapshot.species_id]].range)
	var desired := maxi(BODY_RADIUS * 2 + 1000, melee_range * 2 / 3)
	if actor.order == "keep_distance" and _has_affordable_projectile(snapshot, int(actor.mp)):
		desired = 150000
	elif actor.order == "defend" and int(actor.mp) > 0:
		desired = 90000
	var vector: Array
	if distance > desired + 18000 or Arena.obstruction_fraction(session.arena, actor.pos, enemy.pos, 0, "sight") >= 0:
		vector = _approach_vector(session, id, enemy.pos)
	elif distance < BODY_RADIUS * 2 + 5000 or (actor.tactic == "retreat" and int(actor.mp) > 0):
		vector = [-int(delta[0]), -int(delta[1])]
	elif actor.tactic == "approach" and distance > desired:
		vector = delta
	else:
		vector = [-int(delta[1]) * int(actor.circle_sign), int(delta[0]) * int(actor.circle_sign)]
	var travel := _speed(session, id)
	if not actor.path.is_empty():
		travel = mini(travel, _length(vector))
	var moved := _move(session, id, vector, travel)
	actor.action = "move" if moved else "idle"
	actor.phase = "idle"
	actor.action_tick = int(session.tick) % 24
	actor.action_duration = 24
	actor.blocked_ticks = 0 if moved else int(actor.blocked_ticks) + 1
	if int(actor.blocked_ticks) >= 12:
		actor.circle_sign = -int(actor.circle_sign)
		actor.repath_tick = 0
		actor.blocked_ticks = 0


static func _nearest_enemy(session: Dictionary, id: String) -> String:
	var actor: Dictionary = session.actors[id]
	var closest := ""
	var distance := 2147483647
	for other_id: String in session.fighter_order:
		var other: Dictionary = session.actors[other_id]
		if other.team_id == actor.team_id or int(other.hp) <= 0:
			continue
		var candidate := _length(_subtract(other.pos, actor.pos))
		if candidate >= distance:
			continue
		if not Arena.segment_clear(session.arena, actor.pos, other.pos, BODY_RADIUS) and Arena.path(session.arena, actor.pos, other.pos, BODY_RADIUS).is_empty():
			continue
		closest = other_id
		distance = candidate
	return closest


static func _approach_vector(session: Dictionary, id: String, goal: Array) -> Array:
	var actor: Dictionary = session.actors[id]
	if Arena.segment_clear(session.arena, actor.pos, goal, BODY_RADIUS):
		actor.path = []
		return _subtract(goal, actor.pos)
	if int(session.tick) >= int(actor.repath_tick) or actor.path.is_empty():
		actor.path = Arena.path(session.arena, actor.pos, goal, BODY_RADIUS)
		actor.repath_tick = int(session.tick) + 30
	while not actor.path.is_empty() and _length(_subtract(actor.path[0], actor.pos)) < 4000:
		actor.path.pop_front()
	return [0, 0] if actor.path.is_empty() else _subtract(actor.path[0], actor.pos)


static func _approach_for_move(session: Dictionary, id: String) -> void:
	var actor: Dictionary = session.actors[id]
	var vector := _approach_vector(session, id, session.actors[actor.target_id].pos)
	actor.action = "move" if _move(session, id, vector, mini(_speed(session, id), _length(vector))) else "idle"
	actor.phase = "idle"


static func _move(session: Dictionary, id: String, vector: Array, speed: int) -> bool:
	var actor: Dictionary = session.actors[id]
	var offset := _scaled(vector, speed)
	for movement: Array in [offset, [offset[0], 0], [0, offset[1]]]:
		if movement == [0, 0]:
			continue
		var finish := _add(actor.pos, movement)
		if not Arena.segment_clear(session.arena, actor.pos, finish, BODY_RADIUS):
			continue
		var blocked := false
		for other_id: String in session.fighter_order:
			if other_id == id or int(session.actors[other_id].hp) <= 0:
				continue
			var other: Dictionary = session.actors[other_id]
			var radius := BODY_RADIUS * 2
			var hit := Arena.segment_rect_fraction(_subtract(actor.pos, other.pos), _subtract(finish, other.pos), [-radius, -radius, radius, radius])
			if hit >= 0:
				blocked = true
				break
		if not blocked:
			actor.pos = finish
			return true
	return false


static func _commit_move(session: Dictionary, id: String, move: Dictionary) -> void:
	var actor: Dictionary = session.actors[id]
	actor.mp = int(actor.mp) - int(move.mp_cost)
	actor.cooldowns[move.id] = int(session.tick) + int(move.cooldown)
	actor.current_move = move.duplicate(true)
	_start_action(session, id, "special_attack" if move.kind == "projectile" else ("rush_attack" if move.kind == "rush" else "basic_attack"), int(move.duration), int(move.windup), int(move.active))
	actor.phase = "charge" if int(move.windup) > 0 else "active"
	_emit(session, "charge_started", id, actor.target_id, "%s charges %s." % [_snapshot(session, id).display_name, move.name], {"move_id": move.id, "windup": actor.windup, "duration": actor.action_duration, "aim": actor.aim.duplicate()})


static func _start_action(session: Dictionary, id: String, action: String, duration: int, windup: int = 0, active: int = 0) -> void:
	var actor: Dictionary = session.actors[id]
	actor.action = action
	actor.action_start = int(session.tick)
	actor.action_tick = 0
	actor.action_duration = duration
	actor.windup = windup
	actor.active_ticks = active
	actor.action_serial = int(actor.action_serial) + 1
	actor.action_id = "%s:%d" % [id, actor.action_serial]
	actor.released = false
	actor.hit_targets = []
	actor.blocked_ticks = 0
	if not String(actor.target_id).is_empty():
		actor.aim = session.actors[actor.target_id].pos.duplicate()
		actor.direction = _subtract(actor.aim, actor.pos)
		actor.facing = _facing(actor.direction)
	if action not in ATTACKS:
		actor.current_move = {}
		actor.phase = "idle"
	_emit(session, "action_started", id, actor.target_id, "%s prepares %s." % [_snapshot(session, id).display_name, action.replace("_", " ")], {"action_id": action, "move_id": actor.current_move.get("id", ""), "action_name": actor.current_move.get("name", action.replace("_", " ").capitalize()), "windup": windup, "duration": duration, "aim": actor.aim.duplicate()})


static func _start_defense(session: Dictionary, id: String, defense: String, manual: bool, threat: Dictionary) -> void:
	var actor: Dictionary = session.actors[id]
	var vector: Array = []
	if defense == "dodge":
		vector = _escape_vector(session, id, threat)
		if vector.is_empty() and not manual:
			defense = "guard"
	_start_action(session, id, "evade" if defense == "dodge" else "guard", _tune(session, "dodge_duration" if defense == "dodge" else "guard_duration"))
	actor.defense_manual = manual
	actor.guard_perfect_used = false
	if manual:
		actor.manual_defense_ready_tick = int(session.tick) + _tune(session, "defense_cooldown")
	else:
		actor.ai_defense_ready_tick = int(session.tick) + _tune(session, "ai_defense_cooldown")
	if defense == "dodge":
		actor.evade_vector = vector if not vector.is_empty() else [0, 0]
		_emit(session, "evade", id, actor.target_id, "%s dodges." % _snapshot(session, id).display_name, {"manual": manual})
		if vector.is_empty():
			_emit(session, "dodge_blocked", id, "", "No clear escape path.")
			actor.blocked_ticks = 1
	_emit(session, "defense_started", id, "", "%s: %s." % ["Player defense" if manual else "Autonomous defense", defense], {"defense": defense, "manual": manual})


static func _escape_vector(session: Dictionary, id: String, threat: Dictionary) -> Array:
	var actor: Dictionary = session.actors[id]
	var direction: Array = threat.get("direction", actor.direction)
	if direction == [0, 0] and not String(actor.target_id).is_empty():
		direction = _subtract(session.actors[actor.target_id].pos, actor.pos)
	if direction == [0, 0]:
		direction = [1, 0]
	var side := [-int(direction[1]) * int(actor.circle_sign), int(direction[0]) * int(actor.circle_sign)]
	var choices: Array = [side, [-int(side[0]), -int(side[1])], [-int(direction[0]), -int(direction[1])], [int(direction[0]), int(direction[1])]]
	var best: Array = []
	var best_score := -1
	var travel := _speed(session, id) * _tune(session, "dodge_multiplier") / 1000 * _tune(session, "dodge_duration")
	for choice: Array in choices:
		var finish := _add(actor.pos, _scaled(choice, travel))
		if not Arena.segment_clear(session.arena, actor.pos, finish, BODY_RADIUS):
			continue
		var blocked := false
		for other_id: String in session.fighter_order:
			if other_id == id or int(session.actors[other_id].hp) <= 0:
				continue
			var radius := BODY_RADIUS * 2
			if Arena.segment_rect_fraction(_subtract(actor.pos, session.actors[other_id].pos), _subtract(finish, session.actors[other_id].pos), [-radius, -radius, radius, radius]) >= 0:
				blocked = true
				break
		if blocked:
			continue
		var score := mini(mini(int(finish[0]), int(finish[1])), mini(int(session.arena.ground.width) * SCALE - int(finish[0]), int(session.arena.ground.height) * SCALE - int(finish[1])))
		if score > best_score:
			best = choice
			best_score = score
		if int(_snapshot(session, id).stats.brains) < 12:
			break
	return best


static func _observable_threat(session: Dictionary, id: String) -> Dictionary:
	var actor: Dictionary = session.actors[id]
	var radius := BODY_RADIUS + 10000
	for enemy_id: String in session.fighter_order:
		var enemy: Dictionary = session.actors[enemy_id]
		if enemy.team_id == actor.team_id or int(enemy.hp) <= 0 or enemy.action not in ATTACKS or enemy.current_move.is_empty():
			continue
		if phase_at(enemy, int(session.tick)) not in ["charge", "active"] or Arena.obstruction_fraction(session.arena, actor.pos, enemy.pos, 0, "sight") >= 0:
			continue
		var finish := _add(enemy.pos, _scaled(enemy.direction, int(enemy.current_move.range)))
		if Arena.segment_rect_fraction(_subtract(enemy.pos, actor.pos), _subtract(finish, actor.pos), [-radius, -radius, radius, radius]) >= 0:
			return {"id": enemy.action_id, "origin": enemy.pos.duplicate(), "direction": enemy.direction.duplicate()}
	for projectile: Dictionary in session.projectiles:
		if projectile.team_id == actor.team_id or Arena.obstruction_fraction(session.arena, actor.pos, projectile.pos, 0, "sight") >= 0:
			continue
		var finish := _add(projectile.pos, _scaled(projectile.velocity, 120000))
		if Arena.segment_rect_fraction(_subtract(projectile.pos, actor.pos), _subtract(finish, actor.pos), [-radius, -radius, radius, radius]) >= 0:
			return {"id": projectile.attack_id, "origin": projectile.pos.duplicate(), "direction": projectile.velocity.duplicate()}
	return {}


static func _advance_attack(session: Dictionary, id: String, hits: Array) -> void:
	var actor: Dictionary = session.actors[id]
	if int(actor.hp) <= 0 or actor.action not in ATTACKS or actor.phase != "active":
		return
	var move: Dictionary = actor.current_move
	if not bool(actor.released):
		actor.released = true
		_emit(session, "attack_released", id, actor.target_id, "%s releases %s." % [_snapshot(session, id).display_name, move.name], {"move_id": move.id})
		if move.kind == "projectile":
			session.projectile_serial = int(session.projectile_serial) + 1
			var projectile := {"id": int(session.projectile_serial), "owner_id": id, "team_id": actor.team_id, "attack_id": actor.action_id,
				"pos": actor.pos.duplicate(), "previous_pos": actor.pos.duplicate(), "velocity": _scaled(actor.direction, int(move.projectile_speed)),
				"radius": int(move.projectile_radius), "remaining": int(move.range), "lifetime": int(move.projectile_lifetime),
				"born_tick": int(session.tick), "power": int(move.power), "damage_variance": int(move.damage_variance), "move_id": move.id,
				"effect": move.effect, "visual_scale": int(move.visual_scale)}
			session.projectiles.append(projectile)
			_emit(session, "projectile_spawned", id, actor.target_id, "%s releases %s." % [_snapshot(session, id).display_name, move.name], {"action_id": move.id, "move_id": move.id, "projectile_id": projectile.id})
	if move.kind == "rush":
		_advance_rush(session, id, hits)
	elif move.kind == "melee":
		var finish := _add(actor.pos, _scaled(actor.direction, int(move.range)))
		var width := int(move.melee_width) / 2
		var block := Arena.obstruction_fraction(session.arena, actor.pos, finish, width, "projectile")
		for target_id: String in session.fighter_order:
			var target: Dictionary = session.actors[target_id]
			if target.team_id == actor.team_id or int(target.hp) <= 0 or target_id in actor.hit_targets:
				continue
			var hit := Arena.swept_box_fraction(actor.pos, finish, target.previous_pos, target.pos, BODY_RADIUS + width)
			if hit >= 0 and (block < 0 or hit < block):
				actor.hit_targets.append(target_id)
				hits.append(_hit_intent(id, target_id, move, true))


static func _advance_rush(session: Dictionary, id: String, hits: Array) -> void:
	var actor: Dictionary = session.actors[id]
	var move: Dictionary = actor.current_move
	var start: Array = actor.pos
	var finish := _add(start, _scaled(actor.direction, _speed(session, id) * int(move.rush_speed_multiplier) / 1000))
	var block := Arena.obstruction_fraction(session.arena, start, finish, BODY_RADIUS, "movement")
	var bounds := _boundary_fraction(session.arena, start, finish, BODY_RADIUS)
	if bounds >= 0 and (block < 0 or bounds < block):
		block = bounds
	var target_id := ""
	for other_id: String in session.fighter_order:
		if other_id == id or int(session.actors[other_id].hp) <= 0:
			continue
		var other: Dictionary = session.actors[other_id]
		var radius := BODY_RADIUS * 2
		var hit := Arena.segment_rect_fraction(_subtract(start, other.previous_pos), _subtract(finish, other.pos), [-radius, -radius, radius, radius])
		# Earlier actors have already moved this tick. Their current body must
		# also stop us, otherwise two head-on rushes can end interpenetrating.
		var static_hit := Arena.segment_rect_fraction(_subtract(start, other.pos), _subtract(finish, other.pos), [-radius, -radius, radius, radius])
		if static_hit >= 0 and (hit < 0 or static_hit < hit):
			hit = static_hit
		if hit >= 0 and (block < 0 or hit < block):
			block = hit
			target_id = other_id
	# Authored rush width is the attack footprint. Physical body collision uses
	# BODY_RADIUS independently; a wider strike can graze without moving bodies.
	# Its volume must also respect projectile/attack-blocking side obstacles.
	var attack_block := Arena.obstruction_fraction(session.arena, start, finish, int(move.melee_width) / 2, "projectile")
	for other_id: String in session.fighter_order:
		var other: Dictionary = session.actors[other_id]
		if other.team_id == actor.team_id or int(other.hp) <= 0 or other_id in actor.hit_targets:
			continue
		var radius := BODY_RADIUS + int(move.melee_width) / 2
		var contact := Arena.segment_rect_fraction(_subtract(start, other.previous_pos), _subtract(finish, other.pos), [-radius, -radius, radius, radius])
		var static_contact := Arena.segment_rect_fraction(_subtract(start, other.pos), _subtract(finish, other.pos), [-radius, -radius, radius, radius])
		if static_contact >= 0 and (contact < 0 or static_contact < contact):
			contact = static_contact
		if contact >= 0 and (block < 0 or contact <= block) and (attack_block < 0 or contact < attack_block):
			actor.hit_targets.append(other_id)
			hits.append(_hit_intent(id, other_id, move, true))
	if block < 0:
		actor.pos = finish
		return
	# Stop just short of contact. Rush never uses ordinary wall sliding.
	actor.pos = _add(start, _scaled(_subtract(finish, start), maxi(0, _length(_subtract(finish, start)) * block / Arena.FRACTION - 1)))
	actor.phase = "recovery"
	# Preserve the charge elapsed window; shorten active and keep full recovery.
	actor.active_ticks = maxi(0, int(session.tick) - int(actor.action_start) - int(actor.windup))
	actor.action_duration = int(session.tick) - int(actor.action_start) + int(move.recovery)
	_emit(session, "rush_collision", id, target_id, "Rush stopped; recovery begins.", {"move_id": move.id, "blocked": target_id.is_empty()})


static func _boundary_fraction(arena: Dictionary, start: Array, finish: Array, radius: int) -> int:
	var earliest := -1
	var maxima: Array = [int(arena.ground.width) * SCALE - radius, int(arena.ground.height) * SCALE - radius]
	for axis: int in range(2):
		var delta := int(finish[axis]) - int(start[axis])
		if delta == 0:
			continue
		var fraction := -1
		if int(finish[axis]) < radius:
			fraction = (radius - int(start[axis])) * Arena.FRACTION / delta
		elif int(finish[axis]) > int(maxima[axis]):
			fraction = (int(maxima[axis]) - int(start[axis])) * Arena.FRACTION / delta
		if fraction >= 0 and (earliest < 0 or fraction < earliest):
			earliest = fraction
	return earliest


static func _advance_projectiles(session: Dictionary, hits: Array) -> void:
	var survivors: Array = []
	for projectile: Dictionary in session.projectiles:
		var start: Array = projectile.pos
		var travel := mini(_length(projectile.velocity), int(projectile.remaining))
		var finish := _add(start, _scaled(projectile.velocity, travel))
		var block := Arena.obstruction_fraction(session.arena, start, finish, int(projectile.radius), "projectile")
		var bounds := _boundary_fraction(session.arena, start, finish, int(projectile.radius))
		if bounds >= 0 and (block < 0 or bounds < block):
			block = bounds
		var target_id := ""
		for other_id: String in session.fighter_order:
			var target: Dictionary = session.actors[other_id]
			if target.team_id == projectile.team_id or int(target.hp) <= 0:
				continue
			var previous: Array = target.pos if int(projectile.born_tick) == int(session.tick) else target.previous_pos
			var radius := BODY_RADIUS + int(projectile.radius)
			var hit := Arena.segment_rect_fraction(_subtract(start, previous), _subtract(finish, target.pos), [-radius, -radius, radius, radius])
			if hit >= 0 and (block < 0 or hit < block):
				block = hit
				target_id = other_id
		if not target_id.is_empty():
			hits.append({"actor_id": projectile.owner_id, "target_id": target_id, "move_id": projectile.move_id, "power": projectile.power, "variance": projectile.damage_variance, "melee": false})
			continue
		if block >= 0:
			_emit(session, "projectile_blocked", projectile.owner_id, "", "An obstacle blocks the projectile.", {"projectile_id": projectile.id})
			continue
		projectile.previous_pos = start.duplicate()
		projectile.pos = finish
		projectile.remaining = int(projectile.remaining) - travel
		projectile.lifetime = int(projectile.lifetime) - 1
		if int(projectile.remaining) > 0 and int(projectile.lifetime) > 0:
			survivors.append(projectile)
	session.projectiles = survivors


static func _hit_intent(id: String, target_id: String, move: Dictionary, melee: bool) -> Dictionary:
	return {"actor_id": id, "target_id": target_id, "move_id": move.id, "power": int(move.power), "variance": int(move.damage_variance), "melee": melee}


static func _damage(session: Dictionary, hit: Dictionary, rng: BattleRng) -> void:
	var actor: Dictionary = session.actors[hit.actor_id]
	var target: Dictionary = session.actors[hit.target_id]
	var snapshot := _snapshot(session, hit.actor_id)
	var defender := _snapshot(session, hit.target_id)
	var base := maxi(1, int(snapshot.stats.offense) * int(hit.power) / 100 - int(defender.stats.defense) * 45 / 100 + int(snapshot.stats.brains) / 20)
	var amount := maxi(1, base * (100 + rng.range_inclusive(-int(hit.variance), int(hit.variance))) / 100)
	var guarded: bool = target.action == "guard" and int(session.tick) - int(target.action_start) < int(target.action_duration)
	var perfect: bool = guarded and bool(target.defense_manual) and not bool(target.guard_perfect_used) and int(session.tick) - int(target.action_start) < _tune(session, "perfect_guard_ticks")
	if perfect:
		amount = 0
		target.guard_perfect_used = true
		_emit(session, "perfect_guard", hit.target_id, hit.actor_id, "Perfect guard!", {"move_id": hit.move_id})
		# Already collected strikes still resolve, enabling fair same-tick trades.
		if bool(hit.melee):
			_start_action(session, hit.actor_id, "hit", _tune(session, "perfect_guard_stagger"))
	elif guarded:
		amount = maxi(1, amount * _tune(session, "guard_damage_percent") / 100)
	var absorbed := 0
	if amount > 0 and target.effects.has("barrier"):
		absorbed = mini(amount, int(target.effects.barrier.amount))
		amount -= absorbed
		target.effects.barrier.amount = int(target.effects.barrier.amount) - absorbed
		if int(target.effects.barrier.amount) <= 0:
			target.effects.erase("barrier")
			_emit(session, "effect_expired", hit.target_id, "", "Barrier depleted.", {"effect": "barrier", "reason": "depleted"})
	target.hp = maxi(0, int(target.hp) - amount)
	_emit(session, "hit", hit.actor_id, hit.target_id, "%s hits %s for %d%s." % [snapshot.display_name, defender.display_name, amount, " through guard" if guarded else ""], {"action_id": hit.move_id, "move_id": hit.move_id, "damage": amount, "guarded": guarded, "perfect_guard": perfect, "absorbed": absorbed, "target_hp": int(target.hp), "actor_mp": int(actor.mp)})
	if amount > 0 and target.action in ["idle", "move"]:
		_start_action(session, hit.target_id, "hit", 6)


static func _expire_effects(session: Dictionary) -> void:
	for id: String in session.fighter_order:
		var actor: Dictionary = session.actors[id]
		for effect: String in actor.effects.keys():
			if int(actor.effects[effect].expires_tick) <= int(session.tick):
				actor.effects.erase(effect)
				_emit(session, "effect_expired", id, "", "%s expired." % effect.capitalize(), {"effect": effect, "reason": "duration"})


static func _finish(session: Dictionary, reason: String, winner_team: String) -> void:
	session.complete = true
	var hp := {}
	var mp := {}
	var winner_id := ""
	for id: String in session.fighter_order:
		hp[id] = int(session.actors[id].hp)
		mp[id] = int(session.actors[id].mp)
		if winner_id.is_empty() and session.actors[id].team_id == winner_team and int(session.actors[id].hp) > 0:
			winner_id = id
	var outcome := "draw" if winner_team.is_empty() else ("win" if winner_team == session.actors[session.fighter_order[0]].team_id else "loss")
	session.result = {"outcome": outcome, "winner_id": winner_id, "winner_team_id": winner_team, "reason": reason, "ticks": int(session.tick), "duration_seconds": float(session.tick) / TICKS_PER_SECOND, "final_hp": hp, "final_mp": mp}
	_emit(session, "battle_finished", winner_id, "", "Battle complete: %s." % outcome)


static func movement_per_tick(snapshot: Dictionary, tuning: Dictionary = {}) -> int:
	var speed := clampi(int(snapshot.stats.speed), 0, 999)
	return int(tuning.get("speed_base", 2000)) + int(tuning.get("speed_bonus", 6000)) * speed / (maxi(1, int(tuning.get("speed_half_stat", 50))) + speed)


static func reaction_ticks(snapshot: Dictionary, tuning: Dictionary = {}) -> int:
	return maxi(int(tuning.get("reaction_min", 3)), int(tuning.get("reaction_base", 20)) - int(snapshot.stats.brains) / maxi(1, int(tuning.get("reaction_brains_divisor", 2))))


static func _speed(session: Dictionary, id: String) -> int:
	var speed := movement_per_tick(_snapshot(session, id), session.combat_config.tuning)
	var actor: Dictionary = session.actors[id]
	if actor.effects.has("haste") and int(actor.effects.haste.expires_tick) > int(session.tick):
		speed = speed * int(actor.effects.haste.movement_multiplier) / 1000
	return speed


## Remaining center travel, after this tick has been simulated. Used by the
## telegraph adapter and engagement check so displayed reach follows stat/item
## tuning, including a Haste effect that expires during the anticipated rush.
static func rush_travel_remaining(session: Dictionary, id: String) -> int:
	if not session.get("actors", {}).has(id):
		return 0
	var actor: Dictionary = session.actors[id]
	var move: Dictionary = actor.current_move
	if move.get("kind") != "rush" or actor.phase not in ["charge", "active"]:
		return 0
	var first_tick := int(actor.action_start) + int(actor.windup)
	var remaining := int(actor.active_ticks)
	if actor.phase == "active":
		first_tick = int(session.tick) + 1
		remaining = maxi(0, int(actor.windup) + int(actor.active_ticks) - int(actor.action_tick) - 1)
	return _rush_travel_for_ticks(session, id, move, remaining, first_tick)


static func _rush_travel_for_ticks(session: Dictionary, id: String, move: Dictionary, count: int, first_tick: int) -> int:
	var base := movement_per_tick(_snapshot(session, id), session.combat_config.tuning)
	var haste: Dictionary = session.actors[id].effects.get("haste", {})
	var travel := 0
	for offset: int in range(count):
		var speed := base
		if int(haste.get("expires_tick", 0)) > first_tick + offset:
			speed = speed * int(haste.get("movement_multiplier", 1000)) / 1000
		travel += speed * int(move.rush_speed_multiplier) / 1000
	return travel


static func _available(actor: Dictionary, move: Dictionary, tick: int) -> bool:
	return int(actor.mp) >= int(move.mp_cost) and tick >= int(actor.cooldowns.get(move.id, 0))


static func _move_in_range(session: Dictionary, id: String, move: Dictionary) -> bool:
	var actor: Dictionary = session.actors[id]
	if String(actor.target_id).is_empty():
		return false
	var enemy: Dictionary = session.actors[actor.target_id]
	var engagement_range := int(move.range)
	if move.kind == "rush":
		var physical_reach := _rush_travel_for_ticks(session, id, move, int(move.active), int(session.tick) + int(move.windup)) + BODY_RADIUS + int(move.melee_width) / 2
		engagement_range = mini(engagement_range, maxi(BODY_RADIUS * 2, physical_reach - 3000))
	if _length(_subtract(enemy.pos, actor.pos)) > engagement_range:
		return false
	if Arena.obstruction_fraction(session.arena, actor.pos, enemy.pos, 0, "sight") >= 0:
		return false
	return move.kind != "projectile" or Arena.obstruction_fraction(session.arena, actor.pos, enemy.pos, int(move.projectile_radius), "projectile") < 0


static func _equipped(snapshot: Dictionary, id: String) -> bool:
	if not snapshot.moves.has(id) or id not in snapshot.skills.learned:
		return false
	for slot: Dictionary in snapshot.skills.equipped:
		if slot.move_id == id:
			return true
	return false


static func _automatic_moves(snapshot: Dictionary) -> Array[String]:
	var moves: Array[String] = []
	if snapshot.stage != "Rookie":
		moves.append(String(snapshot.special.id))
	else:
		for slot: Dictionary in snapshot.skills.equipped:
			if bool(slot.auto):
				moves.append(String(slot.move_id))
	return moves


static func _has_affordable_projectile(snapshot: Dictionary, mp: int) -> bool:
	for id: String in _automatic_moves(snapshot):
		if snapshot.moves[id].kind == "projectile" and mp >= int(snapshot.moves[id].mp_cost):
			return true
	return false


static func _snapshot(session: Dictionary, id: String) -> Dictionary:
	return session.fighters[session.fighter_order.find(id)]


static func _tune(session: Dictionary, key: String) -> int:
	return int(session.combat_config.tuning[key])


static func _emit(session: Dictionary, event: String, actor_id: String, target_id: String, message: String, extra: Dictionary = {}) -> void:
	var entry := {"tick": int(session.tick), "event": event, "actor_id": actor_id, "target_id": target_id, "action_id": "", "action_name": "", "damage": 0, "target_hp": 0, "actor_mp": 0, "guarded": false, "message": message}
	entry.merge(extra, true)
	session.log.append(entry)


static func _add(a: Array, b: Array) -> Array:
	return [int(a[0]) + int(b[0]), int(a[1]) + int(b[1])]


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


static func _integer_copy(value: Variant) -> Variant:
	if value is Dictionary:
		var copy := {}
		for key: Variant in value:
			copy[key] = _integer_copy(value[key])
		return copy
	if value is Array:
		var copy: Array = []
		for child: Variant in value:
			copy.append(_integer_copy(child))
		return copy
	if value is float and is_finite(value) and value == floor(value):
		return int(value)
	return value


static func _error(message: String) -> Dictionary:
	return {"ok": false, "error": message}


static func validate_config(config: Dictionary) -> String:
	return ContentSchema.validate_snapshot(config)


static func _validate_items(items: Dictionary) -> String:
	if items.is_empty() or items.size() > 256:
		return "item definitions are missing"
	for id: Variant in items:
		if not id is String or not items[id] is Dictionary:
			return "invalid item identity"
		var item: Dictionary = items[id]
		if not item.get("name") is String or item.get("effect") not in ["restore", "barrier", "haste"]:
			return "invalid item effect"
		if not Arena.integer_between(item.get("amount"), 0, 9999) or not Arena.integer_between(item.get("duration_ticks"), 0, 3600) or not Arena.integer_between(item.get("movement_multiplier"), 1000, 10000):
			return "invalid item values"
		if item.effect == "restore" and (item.get("stat") not in ["hp", "mp"] or int(item.amount) < 1):
			return "recovery requires hp or mp and a positive amount"
		if item.effect != "restore" and (item.get("stat") != "" or int(item.duration_ticks) < 1):
			return "tactical effect duration is invalid"
	return ""


static func validate_snapshot(snapshot: Dictionary) -> String:
	for key: String in ["fighter_id", "display_name", "species_id", "stage", "nature"]:
		if not snapshot.get(key) is String or String(snapshot[key]).strip_edges().is_empty() or String(snapshot[key]).length() > 96:
			return "invalid fighter identity"
	if not FALLBACKS.has(snapshot.species_id) or snapshot.nature not in SUPPORTED_NATURES:
		return "unknown species or nature"
	if snapshot.stage != {"botamon": "Baby", "koromon": "In-Training", "agumon": "Rookie"}[snapshot.species_id]:
		return "species and stage do not agree"
	if not snapshot.get("stats") is Dictionary:
		return "fighter stats are missing"
	for key: String in ["hp", "mp", "offense", "defense", "speed", "brains"]:
		if not Arena.integer_between(snapshot.stats.get(key), 1 if key == "hp" else 0, 9999 if key in ["hp", "mp"] else 999):
			return "invalid fighter stat: " + key
	if not snapshot.get("moves") is Dictionary or snapshot.moves.is_empty() or snapshot.moves.size() > 256 or not snapshot.get("skills") is Dictionary:
		return "pinned moves and skills are required"
	if not snapshot.get("special") is Dictionary or snapshot.special.get("id") != SPECIALS[snapshot.species_id]:
		return "invalid species special"
	var fallback := String(FALLBACKS[snapshot.species_id])
	if not snapshot.moves.has_all([fallback, String(SPECIALS[snapshot.species_id]), "opening_tackle"]):
		return "required innate moves are missing"
	for id: Variant in snapshot.moves:
		if not id is String or not snapshot.moves[id] is Dictionary:
			return "invalid pinned move identity"
		var move: Dictionary = snapshot.moves[id]
		if move.get("id") != id or not move.get("name") is String or move.get("kind") not in ["melee", "projectile", "rush"]:
			return "invalid pinned move"
		if not move.get("species") is Array or snapshot.species_id not in move.species or not move.get("equippable") is bool or not move.get("movement_while_casting") is bool:
			return "invalid move availability"
		for key: String in ["mp_cost", "power", "range", "windup", "active", "duration", "recovery", "cooldown", "damage_variance", "melee_width", "projectile_speed", "projectile_radius", "projectile_lifetime", "rush_speed_multiplier", "auto_weight", "visual_scale"]:
			if not Arena.integer_between(move.get(key), 0, 4096000):
				return "invalid move value: " + key
		if int(move.duration) < 1 or int(move.active) < 1 or int(move.duration) != int(move.windup) + int(move.active) + int(move.recovery) or int(move.power) < 1 or int(move.range) < 1:
			return "invalid move duration, power or range"
		if move.kind == "projectile" and (int(move.projectile_speed) < 1 or int(move.projectile_radius) < 1 or int(move.projectile_lifetime) < 1):
			return "projectile requires geometry and lifetime"
		if move.kind == "rush" and int(move.rush_speed_multiplier) < 1:
			return "rush requires a speed multiplier"
		if not move.get("animation") is String or not move.get("effect") is String:
			return "move presentation references are missing"
	if snapshot.moves[fallback].kind != "melee" or int(snapshot.moves[fallback].mp_cost) != 0 or bool(snapshot.moves[fallback].equippable):
		return "permanent fallback must be free non-equippable melee"
	if snapshot.moves.opening_tackle.kind != "rush" or int(snapshot.moves.opening_tackle.mp_cost) != 0 or bool(snapshot.moves.opening_tackle.equippable):
		return "opening tackle must be free and innate"
	var skills: Dictionary = snapshot.skills
	if not skills.get("learned") is Array or not skills.get("equipped") is Array or skills.learned.size() > 256 or skills.equipped.size() > 3:
		return "invalid skill loadout"
	var seen := {}
	for id: Variant in skills.learned:
		if not id is String or not snapshot.moves.has(id) or not bool(snapshot.moves[id].equippable) or seen.has(id):
			return "invalid learned move"
		seen[id] = true
	seen.clear()
	for slot: Variant in skills.equipped:
		if not slot is Dictionary or not slot.get("move_id") is String or not slot.get("auto") is bool or slot.move_id not in skills.learned or seen.has(slot.move_id):
			return "invalid equipped move"
		seen[slot.move_id] = true
	return ""


static func replay_record(session: Dictionary) -> Dictionary:
	if not bool(session.get("ok", false)):
		return {}
	var record := {"battle_id": session.battle_id, "simulation_version": SIMULATION_VERSION, "seed": session.seed,
		"max_ticks": session.max_ticks, "duration_ticks": session.tick, "fighters": session.fighters.duplicate(true),
		"roster": session.roster.duplicate(true), "arena": session.arena.duplicate(true), "combat_config": session.combat_config.duplicate(true),
		"content_revisions": session.content_revisions.duplicate(true), "commands": session.commands.duplicate(true),
		"initial_supplies": session.initial_supplies.duplicate(true), "item_definitions": session.item_definitions.duplicate(true)}
	if session.has("encounter_id"):
		record.encounter_id = session.encounter_id
	return record


static func _validate_record(record: Dictionary) -> String:
	if record.get("simulation_version") != SIMULATION_VERSION or not record.get("battle_id") is String or not Arena.integer_between(record.get("seed"), -9007199254740991, 9007199254740991):
		return "unsupported replay identity or simulation version"
	if not Arena.integer_between(record.get("max_ticks"), 1, MAX_MAX_TICKS) or not Arena.integer_between(record.get("duration_ticks"), 0, int(record.max_ticks)):
		return "replay tick bounds are invalid"
	for key: String in ["arena", "combat_config", "content_revisions", "initial_supplies", "item_definitions"]:
		if not record.get(key) is Dictionary:
			return "replay object missing: " + key
	if not record.content_revisions.get("visuals") is Dictionary or not record.content_revisions.get("arena") is Dictionary:
		return "replay content revisions are invalid"
	if not record.get("roster") is Array or not record.get("fighters") is Array or record.roster != record.fighters or not record.get("commands") is Array or record.commands.size() > MAX_MAX_TICKS * 16:
		return "replay roster or commands are invalid"
	if record.has("encounter_id") and not record.encounter_id is String:
		return "replay encounter identity is invalid"
	if record.content_revisions.has("encounterId") and not record.content_revisions.encounterId is String:
		return "replay encounter pin is invalid"
	if record.content_revisions.arena.has("contentSha256") and not record.content_revisions.arena.contentSha256 is String:
		return "replay arena pin is invalid"
	return ""


static func create_from_record(record: Dictionary) -> Dictionary:
	var problem := _validate_record(record)
	if not problem.is_empty():
		return _error(problem)
	var pin: Dictionary = record.content_revisions.arena
	var session := create_roster_session(record.battle_id, int(record.seed), record.roster, record.arena, int(record.max_ticks), record.content_revisions.visuals, record.initial_supplies, record.item_definitions, String(record.get("encounter_id", record.content_revisions.get("encounterId", ""))), String(pin.get("contentSha256", "")), record.combat_config)
	if bool(session.ok) and session.content_revisions != record.content_revisions:
		return _error("replay content revisions do not match embedded arena and rules")
	return session


static func replay(record: Dictionary) -> Dictionary:
	var session := create_from_record(record)
	if not bool(session.ok):
		return session
	var previous_tick := 0
	for command: Variant in record.commands:
		if not command is Dictionary or not Arena.integer_between(command.get("tick"), 1, int(record.duration_ticks)) or int(command.tick) < previous_tick or not command.has_all(["kind", "command_id", "fighter_id"]):
			return _error("replay commands are invalid or unordered")
		previous_tick = int(command.tick)
	var cursor := 0
	while int(session.tick) < int(record.duration_ticks) and not bool(session.complete):
		var inputs: Array = []
		while cursor < record.commands.size() and int(record.commands[cursor].tick) == int(session.tick) + 1:
			inputs.append(record.commands[cursor])
			cursor += 1
		var before: int = session.commands.size()
		step(session, inputs)
		if session.commands.size() - before != inputs.size():
			return _error("replay command rejected by its recorded state")
	if int(session.tick) != int(record.duration_ticks) or cursor != record.commands.size():
		return _error("replay extends past battle completion")
	return session
