class_name BattleSimulatorV2
extends RefCounted

## Pure 30 Hz spatial battle. Ground coordinates and authoritative math are integer.
const Arena = preload("res://scripts/battle/battle_arena.gd")
const SIMULATION_VERSION := "battle-v2"
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


static func make_snapshot(fighter_id: String, display_name: String, species_id: String, stage: String, nature: String, stats: Dictionary) -> Dictionary:
	return {"fighter_id": fighter_id, "display_name": display_name, "species_id": species_id,
		"stage": stage, "nature": nature, "special": _special_for_species(species_id),
		"stats": {"hp": int(stats.get("hp", 0)), "mp": int(stats.get("mp", 0)), "offense": int(stats.get("offense", 0)),
			"defense": int(stats.get("defense", 0)), "speed": int(stats.get("speed", 0)), "brains": int(stats.get("brains", 0))}}


static func player_snapshot_from_state(state: Dictionary) -> Dictionary:
	var identity: Dictionary = state.get("identity", {})
	return make_snapshot("player", String(identity.get("companion_name", "Partner")), String(identity.get("species_id", "botamon")), String(identity.get("stage", "Baby")), String(identity.get("nature", "Gentle")), state.get("battle_profile", {}))


static func training_opponent(battle_seed: int) -> Dictionary:
	return make_snapshot("training_opponent", "Training Agumon", "agumon", "Rookie", SUPPORTED_NATURES[(battle_seed & BattleRng.MASK_31) % SUPPORTED_NATURES.size()], {"hp": 92, "mp": 48, "offense": 8, "defense": 7, "speed": 7, "brains": 7})


static func create_session(battle_id: String, battle_seed: int, player_snapshot: Dictionary, opponent_snapshot: Dictionary, arena: Dictionary = {}, max_ticks: int = DEFAULT_MAX_TICKS, visual_revisions: Dictionary = {}) -> Dictionary:
	if battle_id.strip_edges().is_empty() or battle_id.length() > 96:
		return _error("battle_id must contain 1–96 characters")
	if max_ticks < 1 or max_ticks > MAX_MAX_TICKS:
		return _error("max_ticks must be between 1 and 3600")
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
	if int(arena_copy.maxBodyRadius) * SCALE < BODY_RADIUS:
		return _error("arena clearance is too small for these fighters")
	var fighters: Array = [player_snapshot.duplicate(true), opponent_snapshot.duplicate(true)]
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
			"circle_sign": 1 if index == 0 else -1, "blocked_ticks": 0}
	var rng := BattleRng.new(battle_seed)
	var session := {"ok": true, "battle_id": battle_id, "simulation_version": SIMULATION_VERSION,
		"seed": battle_seed & BattleRng.MASK_31, "tick": 0, "max_ticks": max_ticks, "complete": false, "arena": arena_copy,
		"fighters": fighters, "fighter_order": order, "actors": actors, "projectiles": [], "log": [], "commands": [],
		"result": {}, "rng_state": rng.state_value(), "projectile_serial": 0,
		"content_revisions": {"arena": {"assetId": arena_copy.assetId, "revision": arena_copy.revision}, "combat": SIMULATION_VERSION, "visuals": visual_revisions.duplicate(true)}}
	_emit(session, "battle_started", "", "", "%s faces %s." % [fighters[0].display_name, fighters[1].display_name])
	return session


## {fighter_id, order, tick?}; omitted tick means the next tick. Input order is stable.
## Invalid commands are rejected without altering the battle or recorded input.
static func step(session: Dictionary, commands: Array = []) -> Array:
	if not bool(session.get("ok", false)) or bool(session.get("complete", true)):
		return []
	var log_start: int = session.log.size()
	session.tick = int(session.tick) + 1
	var rng := BattleRng.new(1)
	rng._state = int(session.rng_state)
	for command: Variant in commands:
		if not _command_valid(command, session, int(session.tick)):
			continue
		var accepted := {"tick": int(session.tick), "fighter_id": String(command.fighter_id), "order": String(command.order)}
		session.commands.append(accepted)
		var commanded: Dictionary = session.actors[accepted.fighter_id]
		commanded.pending_order = accepted.order
		commanded.order_ready_tick = int(session.tick) + reaction_ticks(_snapshot(session, accepted.fighter_id))
		_emit(session, "command", accepted.fighter_id, "", "Order acknowledged: %s." % accepted.order, {"order": accepted.order})
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
	if not bool(session.get("ok", false)):
		return {}
	return {"battle_id": session.battle_id, "simulation_version": session.simulation_version, "seed": session.seed,
		"max_ticks": session.max_ticks, "duration_ticks": session.tick, "fighters": session.fighters.duplicate(true),
		"arena": session.arena.duplicate(true), "content_revisions": session.content_revisions.duplicate(true), "commands": session.commands.duplicate(true)}


static func replay(record: Dictionary) -> Dictionary:
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
	var session := create_session(record.battle_id, int(record.seed), record.fighters[0], record.fighters[1], record.arena, int(record.max_ticks), record.content_revisions.visuals)
	if not session.ok:
		return session
	if record.content_revisions != session.content_revisions:
		return _error("replay content revisions do not match embedded arena and rules")
	var previous_tick := 0
	for command: Variant in record.commands:
		if not command is Dictionary or not command.has("tick") or not Arena.integer_between(command.tick, 1, int(record.duration_ticks)) or int(command.tick) < previous_tick or not _command_valid(command, session, int(command.tick)):
			return _error("replay commands are invalid or unordered")
		previous_tick = int(command.tick)
	var cursor := 0
	while int(session.tick) < int(record.duration_ticks) and not bool(session.complete):
		var tick_commands: Array = []
		while cursor < record.commands.size() and int(record.commands[cursor].tick) == int(session.tick) + 1:
			tick_commands.append(record.commands[cursor])
			cursor += 1
		step(session, tick_commands)
	if int(session.tick) != int(record.duration_ticks) or cursor != record.commands.size():
		return _error("replay extends past battle completion")
	return session


static func ground_position(actor: Dictionary) -> Vector2:
	return Vector2(float(actor.pos[0]) / SCALE, float(actor.pos[1]) / SCALE)


static func movement_per_tick(snapshot: Dictionary) -> int:
	return 1550 + mini(int(snapshot.stats.speed), 100) * 85


static func reaction_ticks(snapshot: Dictionary) -> int:
	return maxi(3, 20 - mini(int(snapshot.stats.brains), 34) / 2)


static func _command_valid(command: Variant, session: Dictionary, tick: int) -> bool:
	return command is Dictionary and command.has_all(["fighter_id", "order"]) and command.fighter_id is String and session.actors.has(command.fighter_id) and command.order is String and command.order in ORDERS and Arena.integer_between(command.get("tick", tick), tick, tick)


static func _update_actor(session: Dictionary, id: String, threat: Dictionary, rng: BattleRng) -> void:
	var actor: Dictionary = session.actors[id]
	var snapshot := _snapshot(session, id)
	var enemy: Dictionary = session.actors[_enemy_id(session, id)]
	if int(actor.hp) <= 0:
		actor.action = "defeat"
		return
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
	var clear_shot := Arena.obstruction_fraction(session.arena, actor.pos, enemy.pos, PROJECTILE_RADIUS, "projectile") < 0
	var roll := rng.next_int(100)
	var aggressive: bool = actor.order == "attack" or snapshot.nature in ["Bold", "Stubborn", "Earnest"]
	if actor.order == "defend" and distance < 125 * SCALE and roll < 55:
		_start_action(session, id, "guard", 24, 0, 0)
	elif int(actor.mp) < SPECIAL_MP_COST and distance > 100 * SCALE and roll < 26:
		_start_action(session, id, "guard", 24, 0, 0)
	elif visible and clear_shot and distance <= SPECIAL_RANGE and distance > 78 * SCALE and int(actor.mp) >= int(snapshot.special.mp_cost) and roll < (76 if actor.order == "keep_distance" else 48):
		actor.mp = int(actor.mp) - int(snapshot.special.mp_cost)
		_start_action(session, id, "special_attack", 50, 27, 1)
	elif visible and distance <= BASIC_RANGE and roll < (25 if actor.order == "keep_distance" else (90 if aggressive else 70)):
		_start_action(session, id, "basic_attack", 36, 20, 3)
	else:
		_tactical_move(session, id)


static func _tactical_move(session: Dictionary, id: String) -> void:
	var actor: Dictionary = session.actors[id]
	var enemy: Dictionary = session.actors[_enemy_id(session, id)]
	var snapshot := _snapshot(session, id)
	var delta := _subtract(enemy.pos, actor.pos)
	var distance := _length(delta)
	var desired := 43 * SCALE
	if actor.order == "keep_distance":
		desired = 175 * SCALE if int(actor.mp) >= SPECIAL_MP_COST else 90 * SCALE
	elif actor.order == "defend":
		desired = 100 * SCALE
	elif snapshot.nature in ["Calm", "Gentle"] and int(actor.mp) >= SPECIAL_MP_COST:
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
	_emit(session, "action_started", id, _enemy_id(session, id), "%s prepares %s." % [_snapshot(session, id).display_name, action.replace("_", " ")], {"action_id": action, "action_name": _snapshot(session, id).special.name if action == "special_attack" else action.replace("_", " ").capitalize(), "windup": windup, "duration": duration, "aim": actor.aim.duplicate()})


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
		"radius": PROJECTILE_RADIUS, "remaining": SPECIAL_RANGE, "born_tick": int(session.tick), "power": int(_snapshot(session, id).special.power)}
	session.projectiles.append(projectile)
	_emit(session, "projectile_spawned", id, _enemy_id(session, id), "%s releases %s." % [_snapshot(session, id).display_name, _snapshot(session, id).special.name], {"action_id": _snapshot(session, id).special.id, "projectile_id": projectile.id})


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
			_damage(session, projectile.owner_id, target_id, int(projectile.power), _snapshot(session, projectile.owner_id).special.id, rng)
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
		_damage(session, id, target_id, 100, "basic_attack", rng)


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
	var required := ["fighter_id", "display_name", "species_id", "stage", "nature", "special", "stats"]
	if snapshot.size() != required.size() or not snapshot.has_all(required):
		return "unexpected or missing top-level fields"
	for key: String in ["fighter_id", "display_name", "species_id", "stage"]:
		if not snapshot[key] is String or String(snapshot[key]).strip_edges().is_empty() or String(snapshot[key]).length() > 96:
			return "%s is invalid" % key
	if not snapshot.nature is String or snapshot.nature not in SUPPORTED_NATURES:
		return "nature is unsupported"
	if not snapshot.special is Dictionary or snapshot.special.size() != 4 or not snapshot.special.has_all(["id", "name", "power", "mp_cost"]):
		return "special fields are invalid"
	for key: String in ["id", "name"]:
		if not snapshot.special[key] is String or String(snapshot.special[key]).is_empty():
			return "special identity is invalid"
	if not Arena.integer_between(snapshot.special.power, 1, 500) or not Arena.integer_between(snapshot.special.mp_cost, 0, MAX_MP):
		return "special values are out of bounds"
	if not snapshot.stats is Dictionary or snapshot.stats.size() != 6 or not snapshot.stats.has_all(["hp", "mp", "offense", "defense", "speed", "brains"]):
		return "stat fields are invalid"
	if not Arena.integer_between(snapshot.stats.hp, 1, MAX_HP) or not Arena.integer_between(snapshot.stats.mp, 0, MAX_MP):
		return "HP or MP is out of bounds"
	for key: String in ["offense", "defense", "speed", "brains"]:
		if not Arena.integer_between(snapshot.stats[key], 0, MAX_STAT):
			return "%s is out of bounds" % key
	return ""


static func _special_for_species(species_id: String) -> Dictionary:
	match species_id:
		"agumon": return {"id": "pepper_breath", "name": "Pepper Breath", "power": 150, "mp_cost": SPECIAL_MP_COST}
		"koromon": return {"id": "bubble_blow", "name": "Bubble Blow", "power": 140, "mp_cost": SPECIAL_MP_COST}
		_: return {"id": "acid_bubbles", "name": "Acid Bubbles", "power": 130, "mp_cost": SPECIAL_MP_COST}


static func _error(message: String) -> Dictionary:
	return {"ok": false, "error": message}

