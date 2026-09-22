extends SceneTree

const Sim = preload("res://scripts/battle/battle_simulator.gd")
const Core = preload("res://scripts/battle/battle_simulator_v4.gd")
const Content = preload("res://scripts/battle/combat_content.gd")
const Arena = preload("res://scripts/battle/battle_arena.gd")
const Playback = preload("res://scripts/battle/battle_playback_model.gd")
var _checks := 0
var _failures := 0


func _initialize() -> void:
	_test_snapshot_validation()
	_test_defense_and_commitment()
	_test_items()
	_test_movement_and_rush()
	_test_head_on_rush()
	_test_projectiles_and_teams()
	_test_request_queue()
	_test_replays()
	_balance_diagnostic()
	print("%s: %d battle-v4 checks (%d failures)" % ["PASS" if _failures == 0 else "FAIL", _checks, _failures])
	quit(0 if _failures == 0 else 1)


func _fighter(id: String, nature: String = "Gentle", config: Dictionary = {}, hp: int = 200) -> Dictionary:
	return Sim.make_snapshot(id, id.capitalize(), "agumon", "Rookie", nature, {"hp": hp, "mp": 48, "offense": 10, "defense": 8, "speed": 8, "brains": 8}, {}, config)


func _session(config: Dictionary = {}, ticks: int = 600) -> Dictionary:
	var content := Content.defaults() if config.is_empty() else config
	var session := Sim.create_session("v4-tests", 42, _fighter("player", "Gentle", content), _fighter("opponent", "Gentle", content), {}, ticks, {}, {"small_recovery": 3, "mp_recovery": 3, "barrier": 3, "haste": 3}, {}, "", "", content)
	if not bool(session.get("ok", false)):
		push_error(str(session))
	return session


func _command(id: String, kind: String, value: String, fighter: String = "player") -> Dictionary:
	var command := {"command_id": id, "kind": kind, "fighter_id": fighter}
	command[{"item_use": "item_id", "move_request": "move_id", "order": "order", "defense_request": "defense"}[kind]] = value
	return command


func _park(session: Dictionary, id: String, pos: Array) -> void:
	var actor: Dictionary = session.actors[id]
	actor.pos = pos.duplicate()
	actor.previous_pos = pos.duplicate()
	actor.action = "guard"
	actor.phase = "idle"
	actor.action_start = int(session.tick)
	actor.action_duration = 9999
	actor.defense_manual = false
	actor.ai_defense_ready_tick = 9999
	actor.opening_pending = false


func _advance(session: Dictionary, tick: int) -> void:
	while int(session.tick) < tick and not bool(session.complete):
		Sim.step(session)


func _events(session: Dictionary, event: String, id: String = "") -> Array:
	return session.log.filter(func(entry: Dictionary) -> bool: return entry.event == event and (id.is_empty() or entry.actor_id == id))


func _rehash(config: Dictionary) -> Dictionary:
	config.sha256 = Content.snapshot_hash(config)
	return config


func _test_snapshot_validation() -> void:
	var good := _fighter("player")
	_check(Sim.validate_snapshot(good).is_empty(), "v4 valid snapshot")
	for bad: Variant in [null, "oops", [], 7]:
		var snapshot := good.duplicate(true)
		snapshot.stats = bad
		_check(not Sim.validate_snapshot(snapshot).is_empty(), "malformed stat container rejected")
	for key: String in ["species_id", "nature", "stage"]:
		var snapshot := good.duplicate(true)
		snapshot[key] = "unknown"
		_check(not Sim.validate_snapshot(snapshot).is_empty(), "unknown snapshot identity rejected: " + key)
	var malformed := good.duplicate(true)
	malformed.moves.claw.power = "bad"
	_check(not Sim.validate_snapshot(malformed).is_empty(), "malformed pinned move rejected without conversion")
	var session := _session()
	_check(session.simulation_version == "battle-v4", "public factory starts v4")
	_check(session.combat_config.sha256 == Content.snapshot_hash(session.combat_config), "session pins complete coherent content")
	var config := Content.defaults()
	config.moves.pepper_breath.power += 1
	_check(not Sim.create_session("bad", 1, good, _fighter("opponent"), {}, 60, {}, {}, {}, "", "", config).ok, "mismatched config hash rejected")
	_check(not Sim.create_session("bad", 1, good, good).ok, "duplicate fighter IDs rejected")
	_check(not Sim.create_roster_session("bad", 1, [7, "x"]).ok, "malformed roster rejected")
	_check(not Sim.create_session("bad", 1, good, _fighter("opponent"), {}, 60, {}, {"bogus": 1}).ok, "unknown item supply rejected")
	for spawn: Variant in [4, null, [1], [1, 2, 3], ["bad", 3]]:
		var malformed_arena := Arena.graybox()
		malformed_arena.spawns.player = spawn
		_check(not Sim.create_session("bad-spawn", 1, good, _fighter("opponent"), malformed_arena).ok, "malformed arena spawn rejected before wrapper copies it")


func _test_defense_and_commitment() -> void:
	var session := _session()
	_park(session, "player", [200000, 240000])
	_park(session, "opponent", [380000, 240000])
	session.actors.player.action = "idle"
	Sim.step(session, [_command("cast", "move_request", "pepper_breath")])
	_check(session.actors.player.phase == "charge" and session.actors.player.mp == 36, "manual ability starts charge and spends MP immediately")
	var ready := int(session.actors.player.cooldowns.pepper_breath)
	var original_pos: Array = session.actors.player.pos.duplicate()
	Sim.step(session, [_command("cancel", "defense_request", "dodge")])
	_check(session.actors.player.action == "evade" and session.actors.player.mp == 36 and session.actors.player.cooldowns.pepper_breath == ready, "dodge cancels charge without refunding MP/cooldown")
	_check(session.actors.player.pos != original_pos and session.actors.player.manual_defense_ready_tick == 62, "manual dodge acts next tick with independent two-second cooldown")
	_check(_events(session, "charge_cancelled", "player").size() == 1, "charge cancellation event emitted once")
	_park(session, "player", [200000, 240000])
	_advance(session, 60)
	_check(_events(session, "projectile_spawned", "player").is_empty(), "canceled charge cannot release ghost projectile")
	_check(not Sim.preflight_command(session, _command("soon", "defense_request", "guard")).ok, "shared manual cooldown rejects early guard")
	Sim.step(session)
	_check(Sim.preflight_command(session, _command("ready", "defense_request", "guard")).ok, "manual defense releases at exact next-tick boundary")
	_check(not Sim.preflight_command(session, _command("enemy", "defense_request", "guard", "opponent")).ok, "enemy rejects player commands")

	# The state still says charge, but next tick is the active boundary.
	session = _session()
	_park(session, "player", [200000, 240000])
	_park(session, "opponent", [240000, 240000])
	Core._commit_move(session, "player", session.fighters[0].moves.heavy_claw)
	_advance(session, int(session.actors.player.windup) - 1)
	_check(session.actors.player.phase == "charge", "active boundary fixture retains previous charge phase")
	_check(not Sim.preflight_command(session, _command("late", "defense_request", "guard")).ok, "next-tick preflight rejects defense at release boundary")
	Sim.step(session, [_command("late", "defense_request", "guard")])
	_check(not session.used_command_ids.has("late"), "rejected defense never queues for later")
	_check(not Sim.preflight_command(session, _command("active", "defense_request", "dodge")).ok, "active attack cannot be canceled")
	_advance(session, int(session.actors.player.windup) + int(session.actors.player.active_ticks))
	_check(not Sim.preflight_command(session, _command("recovery", "defense_request", "guard")).ok, "attack recovery remains committed")

	var guarded_damage: Array = []
	for timing: int in [1, 28, 34]:
		session = _session()
		_park(session, "player", [200000, 240000])
		_park(session, "opponent", [240000, 240000])
		Core._commit_move(session, "opponent", session.fighters[1].moves.heavy_claw)
		_advance(session, timing - 1)
		Sim.step(session, [_command("guard-%d" % timing, "defense_request", "guard")])
		_advance(session, 35)
		guarded_damage.append(200 - int(session.actors.player.hp))
		_check(_events(session, "perfect_guard").size() == (1 if timing == 28 else 0), "only correctly timed guard is perfect at tick %d" % timing)
	_check(int(guarded_damage[1]) == 0 and int(guarded_damage[0]) > 0 and int(guarded_damage[2]) > 0, "early, perfect and late defense have different outcomes")

	session = _session()
	_park(session, "player", [200000, 240000])
	_park(session, "opponent", [240000, 240000])
	Core._start_defense(session, "player", "guard", false, {})
	_check(session.actors.player.manual_defense_ready_tick == 0 and session.actors.player.ai_defense_ready_tick == 60, "AI defense does not consume manual readiness")
	var hit := Core._hit_intent("opponent", "player", session.fighters[1].moves.claw, true)
	Core._damage(session, hit, BattleRng.new(1))
	_check(_events(session, "perfect_guard").is_empty() and int(session.actors.player.hp) < 200, "AI guard never earns perfect guard")
	Sim.step(session, [_command("override", "defense_request", "dodge")])
	_check(session.actors.player.action == "evade", "manual defense overrides autonomous defense")


func _test_items() -> void:
	var session := _session()
	_park(session, "player", [200000, 240000])
	_park(session, "opponent", [500000, 240000])
	var before := JSON.stringify(session)
	var preview := Sim.preflight_commands(session, [_command("barrier", "item_use", "barrier"), _command("barrier", "item_use", "barrier"), _command("haste", "item_use", "haste"), _command("guard", "defense_request", "guard")])
	_check(JSON.stringify(session) == before, "batch preflight leaves original state and RNG untouched")
	_check(preview.commands.size() == 2 and preview.rejected.size() == 2, "batch reserves command IDs and cross-item cooldown")
	Sim.step(session, preview.commands)
	_check(session.supplies.barrier == 2 and session.actors.player.effects.barrier.amount == 30, "barrier use spends one and absorbs thirty")
	var hit := Core._hit_intent("opponent", "player", session.fighters[1].moves.heavy_claw, true)
	Core._damage(session, hit, BattleRng.new(1))
	_check(session.actors.player.effects.barrier.amount == 30 and session.actors.player.hp == 200, "perfect guard precedes barrier consumption")
	session.tick = 8
	Core._damage(session, hit, BattleRng.new(1))
	_check(int(session.actors.player.effects.barrier.amount) < 30 and session.actors.player.hp == 200, "ordinary guard reduces damage before barrier")
	session.item_ready_tick = 0
	_check(not Sim.preflight_command(session, _command("stack", "item_use", "barrier")).ok, "active barrier cannot stack or spend another item")
	session.actors.player.effects.barrier.expires_tick = 9
	_check(Sim.preflight_command(session, _command("expire", "item_use", "barrier")).ok, "effect expiry considered at next accepted tick")
	Sim.step(session, [_command("expire", "item_use", "barrier")])
	_check(_events(session, "effect_expired").size() == 1 and session.actors.player.effects.barrier.expires_tick == 189, "expired barrier replaced exactly on boundary")
	session.item_ready_tick = 0
	var speed := Core._speed(session, "player")
	Sim.step(session, [_command("haste-now", "item_use", "haste")])
	_check(Core._speed(session, "player") == speed * 1350 / 1000, "haste increases authoritative movement by thirty-five percent")
	session.supplies.haste = 0
	session.item_ready_tick = 0
	_check(not Sim.preflight_command(session, _command("empty", "item_use", "haste")).ok, "empty inventory rejects tactical effect")
	session.actors.player.hp = 100
	preview = Sim.preflight_command(session, _command("heal", "item_use", "small_recovery"))
	Sim.step(session)
	_check(session.actors.player.hp == 100 and session.supplies.small_recovery == 3, "withheld command after save failure cannot apply effect")
	Sim.step(session, [_command("heal", "item_use", "small_recovery")])
	_check(session.actors.player.hp == 150 and session.supplies.small_recovery == 2, "restore effects preserve exact cost and amount")
	_check(not Sim.preflight_command(session, _command("heal", "item_use", "small_recovery")).ok, "duplicate persisted command rejected")


func _test_movement_and_rush() -> void:
	var previous := -1
	for speed: int in [0, 1, 8, 50, 100, 500, 999]:
		var fighter := _fighter("player")
		fighter.stats.speed = speed
		var measured := Sim.movement_per_tick(fighter, Content.defaults().tuning)
		_check(measured > previous, "movement increases across full stat range: %d" % speed)
		previous = measured
	var session := _session()
	_park(session, "player", [200000, 240000])
	_park(session, "opponent", [300000, 240000])
	Core._commit_move(session, "opponent", session.fighters[1].moves.opening_tackle)
	_advance(session, 23)
	_check(session.actors.opponent.pos == [300000, 240000] and session.actors.opponent.phase == "charge", "opening tackle tells for twenty-four ticks")
	Sim.step(session, [_command("dodge", "defense_request", "dodge")])
	_advance(session, 60)
	_check(_events(session, "hit", "opponent").is_empty(), "timely physical dodge avoids locked tackle without RNG")

	session = _session()
	_park(session, "player", [200000, 240000])
	_park(session, "opponent", [300000, 240000])
	session.actors.opponent.current_move = session.fighters[1].moves.opening_tackle.duplicate(true)
	Core._commit_move(session, "opponent", session.actors.opponent.current_move)
	_advance(session, 55)
	_check(_events(session, "rush_collision").size() == 1 and _events(session, "hit", "opponent").size() == 1, "rush strikes once and stops on target body")
	_check(int(session.actors.opponent.pos[0]) >= 228000, "rush cannot tunnel through creature")

	var config := Content.defaults()
	config.moves.opening_tackle.rush_speed_multiplier = 10000
	_rehash(config)
	var field := Arena.graybox()
	field.obstacles.append({"id": "rush-wall", "rect": [280, 180, 20, 120], "movement": true, "projectile": true, "sight": false, "occlusion": true})
	session = Sim.create_session("wall", 1, _fighter("player", "Gentle", config), _fighter("opponent", "Gentle", config), field, 100, {}, {}, {}, "", "", config)
	_park(session, "player", [200000, 240000])
	_park(session, "opponent", [340000, 240000])
	Core._commit_move(session, "player", session.fighters[0].moves.opening_tackle)
	_advance(session, 30)
	_check(_events(session, "rush_collision").size() == 1 and session.actors.player.phase == "recovery", "obstacle stops rush immediately into recovery")
	_check(int(session.actors.player.pos[0]) < 266000 and session.actors.player.pos[1] == 240000, "rush never slides or tunnels through obstacle")
	var collision_tick := int(_events(session, "rush_collision")[0].tick)
	_check(int(session.actors.player.action_start) + int(session.actors.player.action_duration) == collision_tick + 27, "collision retains full authored recovery")

	for nature: String in ["Bold", "Stubborn", "Earnest"]:
		session = Sim.create_session("opening", 2, _fighter("player", nature), _fighter("opponent"), {}, 300)
		_advance(session, 160)
		var attacks: Array = _events(session, "charge_started", "player")
		_check(not attacks.is_empty() and attacks[0].move_id == "opening_tackle", "%s prioritizes opening tackle" % nature)


func _test_head_on_rush() -> void:
	var session := Sim.create_session("head-on", 1, _fighter("player", "Bold"), _fighter("opponent", "Bold"), {}, 150)
	var clear := true
	while not session.complete:
		Sim.step(session)
		if Arena.boxes_overlap(session.actors.player.pos, session.actors.opponent.pos, Core.BODY_RADIUS * 2):
			clear = false
	_check(clear, "simultaneous head-on rushes never interpenetrate bodies")
	_check(_events(session, "rush_collision").size() == 2, "both aggressive fighters exercise head-on rush collision")
	_check(not Core._escape_vector(session, "player", {}).is_empty() and not Core._escape_vector(session, "opponent", {}).is_empty(), "head-on rush leaves escape routes for both fighters")
	var slow := _fighter("player", "Bold")
	slow.stats.speed = 0
	session = Sim.create_session("slow-rush", 1, slow, _fighter("opponent"), {}, 150)
	_park(session, "player", [200000, 240000])
	_park(session, "opponent", [370000, 240000])
	_check(not Core._move_in_range(session, "player", session.fighters[0].moves.opening_tackle), "slow rush approaches beyond nominal table range when travel cannot reach")
	session.actors.opponent.pos = [320000, 240000]
	_check(Core._move_in_range(session, "player", session.fighters[0].moves.opening_tackle), "slow rush becomes legal within physical travel plus contact")
	Core._commit_move(session, "player", session.fighters[0].moves.opening_tackle)
	var initial_travel := Sim.rush_travel_remaining(session, "player")
	_advance(session, 24)
	_check(Sim.rush_travel_remaining(session, "player") < initial_travel, "telegraph remaining rush travel decreases after first active step")

	# The table's wide attack footprint must not graze through a side wall even
	# when the creature's narrower physical body has an unobstructed center path.
	for shielded: bool in [false, true]:
		var config := Content.defaults()
		config.moves.opening_tackle.melee_width = 100000
		_rehash(config)
		var field := Arena.graybox()
		if shielded:
			field.obstacles.append({"id": "side-wall", "rect": [230, 260, 100, 15], "movement": true, "projectile": true, "sight": true, "occlusion": true})
		session = Sim.create_session("wide-rush", 1, _fighter("player", "Gentle", config), _fighter("opponent", "Gentle", config), field, 100, {}, {}, {}, "", "", config)
		_park(session, "player", [200000, 240000])
		_park(session, "opponent", [270000, 300000])
		Core._commit_move(session, "player", session.fighters[0].moves.opening_tackle)
		session.actors.player.direction = [1, 0]
		_advance(session, 43)
		_check(_events(session, "hit", "player").size() == (0 if shielded else 1), "authored wide rush respects side obstacle: %s" % shielded)
		_check(_events(session, "rush_collision").is_empty(), "side obstacle leaves physical center path clear")


func _test_request_queue() -> void:
	var session := _session()
	_park(session, "player", [200000, 240000])
	_park(session, "opponent", [500000, 240000])
	Sim.step(session, [_command("old", "move_request", "heavy_claw")])
	Sim.step(session, [_command("new", "move_request", "quick_bite")])
	_check(session.actors.player.pending_move == "quick_bite" and session.actors.player.move_expires_tick == 152, "latest request replaces pending with fresh five-second lifetime")
	_advance(session, 152)
	_check(session.actors.player.pending_move == "" and session.actors.player.mp == 48 and _events(session, "move_expired").size() == 1, "unavailable request expires without MP charge")
	session = _session()
	_park(session, "opponent", [380000, 240000])
	session.actors.player.pos = [200000, 240000]
	session.actors.player.previous_pos = [200000, 240000]
	session.actors.player.ai_defense_ready_tick = 9999
	for slot: Dictionary in session.fighters[0].skills.equipped:
		slot.auto = false
	Sim.step(session, [_command("approach", "move_request", "quick_bite")])
	var first_mp := int(session.actors.player.mp)
	while not session.complete and session.actors.player.pending_move != "":
		Sim.step(session)
	_check(first_mp == 48 and _events(session, "charge_started", "player").size() == 1 and session.actors.player.mp == 44, "disabled auto skill request approaches and charges once in legal range")

	# Stages retain their free permanent attack at zero MP, even while told to
	# keep distance; the innate opening rush is also free, and never a projectile.
	for species: String in ["botamon", "koromon", "agumon"]:
		var stage := String({"botamon": "Baby", "koromon": "In-Training", "agumon": "Rookie"}[species])
		var first := Sim.make_snapshot("player", "Player", species, stage, "Gentle", {"hp": 200, "mp": 0, "offense": 10, "defense": 8, "speed": 8, "brains": 8})
		var opponent := _fighter("opponent")
		opponent.stats.mp = 0
		session = Sim.create_session("zero-mp", 29, first, opponent, {}, 600)
		Sim.step(session, [_command("distance", "order", "keep_distance")])
		_advance(session, 600)
		_check(not _events(session, "hit", "player").is_empty() and _events(session, "projectile_spawned", "player").is_empty(), "%s keeps free basic attacks at zero MP" % species)


func _test_projectiles_and_teams() -> void:
	var config := Content.defaults()
	config.moves.pepper_breath.projectile_speed = 600000
	config.moves.pepper_breath.range = 900000
	_rehash(config)
	var session := _session(config)
	_park(session, "player", [100000, 240000])
	_park(session, "opponent", [500000, 240000])
	Core._commit_move(session, "player", session.fighters[0].moves.pepper_breath)
	_advance(session, 27)
	_check(_events(session, "hit", "player").size() == 1, "fast projectile sweeps entire travel segment")
	var field := Arena.graybox()
	field.obstacles.append({"id": "projectile-wall", "rect": [300, 160, 20, 160], "movement": true, "projectile": true, "sight": false, "occlusion": true})
	session = Sim.create_session("projectile-wall", 1, _fighter("player", "Gentle", config), _fighter("opponent", "Gentle", config), field, 100, {}, {}, {}, "", "", config)
	_park(session, "player", [100000, 240000])
	_park(session, "opponent", [500000, 240000])
	Core._commit_move(session, "player", session.fighters[0].moves.pepper_breath)
	_advance(session, 27)
	_check(_events(session, "hit").is_empty() and _events(session, "projectile_blocked").size() == 1, "fast projectile cannot tunnel through obstacle")

	var roster: Array = []
	field = Arena.graybox()
	field.ground.width = 1000
	field.ground.height = 800
	for index: int in range(6):
		var fighter := _fighter("fighter-%d" % index, "Bold")
		fighter.team_id = "allies" if index < 3 else "enemies"
		fighter.controller_id = "player" if index == 0 else ""
		fighter.spawn = [100 if index < 3 else 900, 200 + (index % 3) * 200]
		roster.append(fighter)
	session = Sim.create_roster_session("teams", 13, roster, field, 400)
	_check(session.ok and session.actors.size() == 6, "larger-field three-versus-three session starts")
	_advance(session, 400)
	for id: String in session.fighter_order:
		var target := String(session.actors[id].target_id)
		_check(target.is_empty() or session.actors[id].team_id != session.actors[target].team_id, "team targeting excludes ally for " + id)
	_check(_events(session, "hit").all(func(hit: Dictionary) -> bool: return session.actors[hit.actor_id].team_id != session.actors[hit.target_id].team_id), "team attacks never damage allies")
	_check(Sim.replay(Sim.replay_record(session)).actors == session.actors, "team roster replay reconstructs all actors")

	# Matching release ticks gather hits before applying defeat.
	session = _session()
	_park(session, "player", [200000, 240000])
	_park(session, "opponent", [240000, 240000])
	session.actors.player.hp = 1
	session.actors.opponent.hp = 1
	Core._commit_move(session, "player", session.fighters[0].moves.claw)
	Core._commit_move(session, "opponent", session.fighters[1].moves.claw)
	_advance(session, 60)
	_check(session.complete and session.result.outcome == "draw" and session.result.reason == "knockout", "simultaneous strikes permit double knockout draw")
	_check(session.actors.player.hp == 0 and session.actors.opponent.hp == 0, "simultaneous damage resolves both collected strikes")


func _test_replays() -> void:
	var session := _session({}, 480)
	while not session.complete:
		var commands: Array = []
		if int(session.tick) % 60 == 0:
			commands.append(_command("guard-%d" % session.tick, "defense_request", "guard"))
		if int(session.tick) % 120 == 0:
			commands.append(_command("move-%d" % session.tick, "move_request", "quick_bite"))
		if int(session.tick) == 10:
			commands.append(_command("barrier", "item_use", "barrier"))
		Sim.step(session, commands)
	var record := Sim.replay_record(session)
	var replay := Sim.replay(record)
	_check(replay.ok and JSON.stringify(replay) == JSON.stringify(session), "v4 replay reconstructs complete byte-identical state")
	replay = Sim.replay(JSON.parse_string(JSON.stringify(record)))
	_check(replay.ok and replay.actors == session.actors and replay.log == session.log, "JSON roundtrip restores integer authoritative data")
	var changed := Content.defaults()
	changed.moves.claw.power = 800
	_rehash(changed)
	var unrelated := Sim.create_session("new-content", 5, _fighter("player", "Gentle", changed), _fighter("opponent", "Gentle", changed), {}, 60, {}, {}, {}, "", "", changed)
	_check(unrelated.ok and Sim.replay(record).actors == session.actors, "new content cannot change pinned replay")
	for key: String in ["roster", "combat_config", "content_revisions", "commands", "item_definitions"]:
		var bad := record.duplicate(true)
		bad[key] = "bad"
		_check(not Sim.replay(bad).ok, "malformed replay safely rejects: " + key)
	var bad := record.duplicate(true)
	bad.simulation_version = "battle-v99"
	_check(not Sim.replay(bad).ok, "unknown replay version rejects")
	bad = record.duplicate(true)
	bad.commands.insert(1, bad.commands[0].duplicate(true))
	_check(not Sim.replay(bad).ok, "replay rejects duplicate accepted command")
	var smooth := Playback.new()
	var chunky := Playback.new()
	smooth.setup(session)
	chunky.setup(session)
	_check(smooth.error.is_empty() and chunky.error.is_empty(), "playback accepts completed v4 battle")
	while not smooth.is_complete():
		smooth.advance(1.0 / 120)
	while not chunky.is_complete():
		chunky.advance(0.37)
	_check(smooth.get_session().actors == chunky.get_session().actors and smooth.get_session().log == chunky.get_session().log, "render chunk size never changes combat outcome or log")


func _balance_diagnostic() -> void:
	for mode: String in ["auto", "periodic", "reactive"]:
		var durations: Array = []
		var draws := 0
		var hits := 0
		var evades := 0
		var signatures := {}
		var wins := 0
		var total_player_hp := 0
		for seed: int in range(24):
			var first := _fighter("player", Sim.SUPPORTED_NATURES[seed % 6], {}, 110)
			var second := _fighter("opponent", Sim.SUPPORTED_NATURES[(seed + 2) % 6], {}, 110)
			var session := Sim.create_session("balance", seed + 100, first, second)
			while not session.complete:
				var commands: Array = []
				if mode == "periodic" and int(session.tick) % 75 == 0:
					commands.append(_command("guard-%d" % session.tick, "defense_request", "guard"))
				if mode == "periodic" and int(session.tick) % 180 == 20:
					commands.append(_command("move-%d" % session.tick, "move_request", "heavy_claw"))
				if mode == "reactive":
					commands.append_array(_reactive_commands(session))
				Sim.step(session, commands)
			durations.append(float(session.tick) / 30)
			wins += 1 if session.result.outcome == "win" else 0
			total_player_hp += int(session.actors.player.hp)
			draws += 1 if session.result.outcome == "draw" else 0
			hits += _events(session, "hit").size()
			evades += _events(session, "evade").size()
			signatures[JSON.stringify(session.log).sha256_text()] = true
		durations.sort()
		print("BALANCE %s n=24 p10=%.1fs median=%.1fs p90=%.1fs draws=%d wins=%d avg_player_hp=%.1f hits=%d evades=%d" % [mode, durations[2], (float(durations[11]) + float(durations[12])) / 2, durations[21], draws, wins, float(total_player_hp) / 24, hits, evades])
		_check(signatures.size() == 24, "seed/nature combinations yield varied tactical sequences")


## This policy sees only already visible actions, geometry and projectiles. It
## never reads an enemy's future random choices or future simulation state.
func _reactive_commands(session: Dictionary) -> Array:
	var commands: Array = []
	var actor: Dictionary = session.actors.player
	var enemy: Dictionary = session.actors.opponent
	var distance := Core._length(Core._subtract(enemy.pos, actor.pos))
	var defense := ""
	if enemy.action in Core.ATTACKS and not enemy.current_move.is_empty():
		var move: Dictionary = enemy.current_move
		var until_release := int(enemy.windup) - int(enemy.action_tick)
		if enemy.phase == "charge" and until_release <= 3:
			if move.kind == "melee" and distance <= int(move.range) + Core.BODY_RADIUS:
				defense = "guard"
			elif move.kind == "projectile":
				defense = "dodge"
		elif enemy.phase == "active" and move.kind == "rush":
			var per_tick := Core._speed(session, "opponent") * int(move.rush_speed_multiplier) / 1000
			if distance <= Core.BODY_RADIUS * 2 + per_tick * 3:
				defense = "guard"
	for projectile: Dictionary in session.projectiles:
		if projectile.team_id != actor.team_id and Core._length(Core._subtract(projectile.pos, actor.pos)) < 80000:
			defense = "dodge"
	if not defense.is_empty():
		commands.append(_command("reactive-defense-%d" % session.tick, "defense_request", defense))
	if enemy.phase == "recovery" and actor.phase == "idle" and actor.action in ["idle", "move"] and distance <= 58000:
		commands.append(_command("punish-%d" % session.tick, "move_request", "quick_bite"))
	return commands


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)
