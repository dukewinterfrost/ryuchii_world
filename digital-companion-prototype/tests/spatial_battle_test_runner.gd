extends SceneTree

const Sim = preload("res://scripts/battle/battle_simulator.gd")
const Legacy = preload("res://scripts/battle/battle_simulator_v2.gd")
const Arena = preload("res://scripts/battle/battle_arena.gd")
var _checks := 0
var _failures := 0


func _initialize() -> void:
	_test_arenas()
	_test_geometry()
	_test_inputs()
	_test_replay_and_render_chunks()
	_test_live_orders()
	_test_speed_and_reaction()
	_test_physical_evasion_and_sweeps()
	_test_many_seeds()
	_test_high_speed_navigation_and_visual_pins()
	_test_shared_arena_cases()
	print("%s: %d spatial combat checks (%d failures)" % ["PASS" if _failures == 0 else "FAIL", _checks, _failures])
	quit(0 if _failures == 0 else 1)


func _fighter(id: String, speed: int = 8, brains: int = 8) -> Dictionary:
	return Sim.make_snapshot(id, id.capitalize(), "agumon", "Rookie", "Bold", {"hp": 110, "mp": 48, "offense": 10, "defense": 8, "speed": speed, "brains": brains})


func _session(seed: int = 42, arena: Dictionary = {}, ticks: int = 600) -> Dictionary:
	return Sim.create_session("test-battle", seed, _fighter("player"), _fighter("opponent"), arena, ticks)


func _test_arenas() -> void:
	for name: String in ["graybox", "forest"]:
		var arena: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/arenas/%s.json" % name))
		_check(Arena.validate(arena).is_empty(), "%s arena validates" % name)
		var path := Arena.path(arena, Arena.to_fixed(arena.spawns.player), Arena.to_fixed(arena.spawns.opponent), int(arena.maxBodyRadius) * Sim.SCALE)
		var current := Arena.to_fixed(arena.spawns.player)
		var safe := not path.is_empty()
		for point: Array in path:
			safe = safe and Arena.segment_clear(arena, current, point, int(arena.maxBodyRadius) * Sim.SCALE)
			current = point
		_check(safe, "%s navigation edges have finite-body clearance" % name)
	var disconnected := Arena.graybox()
	disconnected.obstacles = [_obstacle([300, 0, 20, 480])]
	_check(not Arena.validate(disconnected).is_empty(), "disconnected spawn regions rejected")
	var blocked := Arena.graybox()
	blocked.obstacles = [_obstacle([90, 230, 20, 20])]
	_check(not Arena.validate(blocked).is_empty(), "blocked spawn rejected")
	var tiny := Arena.graybox()
	tiny.maxBodyRadius = 5
	_check(not _session(1, tiny).ok, "arena below fighter body clearance rejected")
	var malformed := Arena.graybox()
	malformed.obstacles = [{"rect": "bad"}]
	_check(not Arena.validate(malformed).is_empty(), "malformed obstacle rejected safely")
	malformed = Arena.graybox()
	malformed.ground.cellSize = 19
	_check(not Arena.validate(malformed).is_empty(), "partial grid cells rejected")
	var iso := Arena.graybox()
	iso.projection = "isometric"
	var square_run := Sim.simulate("projection", 3, _fighter("player"), _fighter("opponent"), 200)
	var iso_run := Sim.simulate("projection", 3, _fighter("player"), _fighter("opponent"), 200, iso)
	_check(square_run.actors == iso_run.actors and square_run.log == iso_run.log, "isometric presentation does not change combat")


func _test_geometry() -> void:
	var arena := Arena.graybox()
	arena.obstacles = [_obstacle([200, 100, 1, 300])]
	_check(not Arena.segment_clear(arena, [100000, 240000], [300000, 240000], 14000), "sweep catches thin obstacle without tunneling")
	_check(Arena.segment_rect_fraction([0, 0], [100000, 0], [49000, -1000, 51000, 1000]) == 490000, "integer swept intersection returns exact entry fraction")
	_check(Arena.segment_rect_fraction([0, 5000], [100000, 5000], [49000, -1000, 51000, 1000]) < 0, "parallel swept segment correctly misses")
	_check(Arena.swept_box_fraction([99000, 120000], [101000, 120000], [100000, 100000], [120000, 120000], 1000) < 0, "diagonal swept body excludes empty enclosing-box corners")
	_check(Arena.swept_box_fraction([99000, 110000], [121000, 110000], [100000, 100000], [120000, 120000], 1000) >= 0, "exact swept body catches diagonal path crossing")
	var canopy := _obstacle([200, 100, 20, 300])
	canopy.movement = false
	canopy.projectile = false
	canopy.sight = false
	canopy.occlusion = true
	arena.obstacles = [canopy]
	_check(Arena.segment_clear(arena, [100000, 240000], [300000, 240000], 14000), "occlusion-only canopy does not block navigation")
	_check(Arena.obstruction_fraction(arena, [100000, 240000], [300000, 240000], 0, "sight") < 0, "occlusion-only canopy does not block sight")
	var session := _session()
	session.actors.player.pos = [200000, 240000]
	session.actors.opponent.pos = [240000, 240000]
	session.actors.player.previous_pos = session.actors.player.pos.duplicate()
	session.actors.opponent.previous_pos = session.actors.opponent.pos.duplicate()
	_check(not Sim._move(session, "player", [1, 0], 100000), "fighter cannot tunnel through another fighter")
	_check(not Arena.boxes_overlap(session.actors.player.pos, session.actors.opponent.pos, Sim.BODY_RADIUS * 2), "finite fighter bodies remain separate")
	session.actors.player.previous_pos = [100000, 100000]
	session.actors.player.pos = [88000, 100000]
	session.actors.opponent.previous_pos = [120000, 132000]
	session.actors.opponent.pos = [120000, 132000]
	_check(not Sim._move(session, "opponent", [0, -1], 12000), "relative body sweep rejects simultaneous corner crossing")


func _test_inputs() -> void:
	var player := _fighter("player")
	var opponent := _fighter("opponent")
	var original := JSON.stringify([player, opponent])
	var session := Sim.create_session("immutable", 42, player, opponent)
	player.stats.hp = 1
	opponent.stats.speed = 999
	_check(JSON.stringify(session.fighters) == original, "snapshots deeply copied")
	_check(not Sim.create_session("", 1, _fighter("p"), _fighter("o")).ok, "empty battle identity rejected")
	_check(not Sim.create_session("bad", 1, {}, _fighter("o")).ok, "missing snapshot fields rejected")
	_check(not Sim.create_session("bad", 1, _fighter("same"), _fighter("same")).ok, "duplicate fighter IDs rejected")
	player = _fighter("player")
	player.stats.brains = NAN
	_check(not Sim.create_session("bad", 1, player, _fighter("o")).ok, "nonfinite stat rejected")
	_check(not Sim.create_session("bad", 1, _fighter("p"), _fighter("o"), {}, 3601).ok, "maximum battle duration enforced")
	Sim.step(session, [{"fighter_id": "missing", "order": "attack"}, {"fighter_id": "player", "order": "teleport"}, {"fighter_id": "player", "order": "attack", "tick": 900}, 12])
	_check(session.commands.is_empty(), "malformed, unknown and future commands safely rejected")
	var short_run := _session(42, {}, 2)
	Sim.step(short_run)
	_check(not short_run.complete and short_run.result.is_empty(), "uncompleted battle has no awardable result")
	Sim.step(short_run)
	_check(short_run.complete and short_run.result.outcome == "draw" and short_run.result.reason == "time_limit" and short_run.result.ticks == 2, "tick limit gives exact terminal draw")
	var frozen := JSON.stringify(short_run)
	Sim.step(short_run, [{"fighter_id": "player", "order": "attack"}])
	_check(JSON.stringify(short_run) == frozen, "terminal session immutable to further steps")
	var durable_player := _fighter("player")
	var durable_opponent := _fighter("opponent")
	for fighter: Dictionary in [durable_player, durable_opponent]:
		fighter.stats.hp = 9999
		fighter.stats.defense = 999
		fighter.stats.offense = 0
		fighter.stats.mp = 0
	var full_duration := Sim.simulate("full-time-limit", 1, durable_player, durable_opponent)
	_check(full_duration.result.reason == "time_limit" and full_duration.tick == 3600 and full_duration.result.duration_seconds == 120.0, "default session terminates after exactly120 simulation seconds")


func _run_chunked(chunks: Array) -> Dictionary:
	var session := _session(81, {}, 300)
	var cursor := 0
	while not session.complete:
		for ignored: int in range(chunks[cursor % chunks.size()]):
			if session.complete:
				break
			var inputs: Array = []
			if int(session.tick) + 1 == 40:
				inputs = [{"fighter_id": "player", "order": "keep_distance"}]
			elif int(session.tick) + 1 == 160:
				inputs = [{"fighter_id": "player", "order": "attack"}]
			Sim.step(session, inputs)
		cursor += 1
	return session


func _test_replay_and_render_chunks() -> void:
	var session := _run_chunked([1])
	_check(JSON.stringify(session) == JSON.stringify(_run_chunked([2, 1, 4, 3])), "render chunk sizes do not affect simulation or commands")
	var record := Sim.replay_record(session)
	_check(JSON.stringify(session) == JSON.stringify(Sim.replay(record)), "recorded commands and snapshots replay byte-for-byte")
	var roundtrip: Dictionary = JSON.parse_string(JSON.stringify(record))
	_check(Sim.replay(roundtrip).actors == session.actors, "JSON replay roundtrip preserves integer combat state")
	record.simulation_version = "battle-v1"
	_check(not Sim.replay(record).ok, "unsupported replay simulation rejected")
	record = Sim.replay_record(session)
	record.content_revisions.arena.revision = "stale"
	_check(not Sim.replay(record).ok, "mismatched replay content revision rejected")
	record = Sim.replay_record(session)
	record.commands.reverse()
	_check(not Sim.replay(record).ok, "out-of-order replay commands rejected")
	record = Sim.replay_record(session)
	record.fighters = [null, null]
	_check(not Sim.replay(record).ok, "malformed replay fighter array rejected safely")


func _test_live_orders() -> void:
	var session := _session()
	Sim._start_action(session, "player", "special_attack", 50, 27, 1)
	Sim.step(session, [{"fighter_id": "player", "order": "keep_distance"}])
	_check(session.actors.player.action == "special_attack" and session.actors.player.pending_order == "keep_distance", "order acknowledged without cancelling windup")
	for tick: int in range(20):
		Sim.step(session)
	_check(session.actors.player.action == "special_attack" and session.actors.player.order == "auto", "order cannot cancel committed action after reaction delay")
	for tick: int in range(29):
		Sim.step(session)
	_check(session.actors.player.order == "keep_distance", "order becomes persistent tactical intent after recovery")
	_check(session.commands.size() == 1 and session.commands[0].tick == 1, "command accepted tick is recorded exactly once")


func _test_speed_and_reaction() -> void:
	_check(Sim.movement_per_tick(_fighter("p", 30, 8)) > Sim.movement_per_tick(_fighter("p", 4, 8)), "speed increases physical movement")
	_check(Sim.movement_per_tick(_fighter("p", 8, 30)) == Sim.movement_per_tick(_fighter("p", 8, 4)), "brains does not alter physical speed")
	_check(Sim.reaction_ticks(_fighter("p", 8, 30)) < Sim.reaction_ticks(_fighter("p", 8, 4)), "brains reduces observed-threat reaction latency")
	_check(Sim.reaction_ticks(_fighter("p", 30, 8)) == Sim.reaction_ticks(_fighter("p", 4, 8)), "speed does not alter reaction latency")
	_check(Sim.reaction_ticks(_fighter("p", 8, 999)) >= 3, "high brains never provides instantaneous reactions")
	_check(_first_evade_tick(32) == 5 and _first_evade_tick(0) == 21, "observable threat produces measured brains-dependent reaction ticks")
	var session := _session()
	Sim._start_action(session, "opponent", "special_attack", 50, 27, 1)
	session.actors.player.pos = [360000, 240000]
	session.actors.opponent.aim = session.actors.player.pos.duplicate()
	var threat := Sim._observable_threat(session, "player")
	_check(not threat.is_empty(), "visible locked telegraph is observable")
	session.arena.obstacles = [_obstacle([400, 100, 20, 300])]
	_check(Sim._observable_threat(session, "player").is_empty(), "hidden telegraph cannot be perceived through sight blocker")


func _first_evade_tick(brains: int) -> int:
	var session := Sim.create_session("reaction", 42, _fighter("player", 8, brains), _fighter("opponent"), {}, 90)
	session.actors.player.pos = [360000, 240000]
	session.actors.player.previous_pos = session.actors.player.pos.duplicate()
	session.actors.player.next_decision = 9999
	Sim._start_action(session, "opponent", "special_attack", 50, 27, 1)
	for tick: int in range(40):
		for event: Dictionary in Sim.step(session):
			if event.event == "evade" and event.actor_id == "player":
				return int(event.tick)
	return -1


func _projectile_session() -> Dictionary:
	var session := _session()
	session.actors.player.pos = [100000, 240000]
	session.actors.opponent.pos = [200000, 240000]
	for id: String in session.fighter_order:
		session.actors[id].previous_pos = session.actors[id].pos.duplicate()
		session.actors[id].action = "guard"
		session.actors[id].action_duration = 999
	session.projectiles = [{"id": 1, "owner_id": "player", "attack_id": "player:1", "pos": [120000, 240000], "previous_pos": [120000, 240000], "velocity": [7000, 0], "remaining": 270000, "born_tick": 0, "power": 150}]
	return session


func _test_physical_evasion_and_sweeps() -> void:
	var stationary := _projectile_session()
	for tick: int in range(20):
		Sim.step(stationary)
	_check(stationary.actors.opponent.hp < 110, "projectile physically intersects a stationary target")
	var evasive := _projectile_session()
	Sim._start_evasion(evasive, "opponent", {"id": "player:1", "origin": [100000, 240000], "direction": [1, 0]}, _fighter("opponent"))
	for tick: int in range(20):
		Sim.step(evasive)
	_check(evasive.actors.opponent.hp == 110 and evasive.actors.opponent.pos[1] != 240000, "early-game speed8 evasion physically leaves projectile path")
	var blocked := _projectile_session()
	blocked.arena.obstacles = [_obstacle([160, 180, 5, 120])]
	for tick: int in range(20):
		Sim.step(blocked)
	_check(blocked.actors.opponent.hp == 110 and blocked.projectiles.is_empty(), "projectile blocker absorbs projectile before target")
	var crossing := _projectile_session()
	crossing.projectiles[0].pos = [180000, 240000]
	crossing.projectiles[0].velocity = [40000, 0]
	crossing.actors.opponent.previous_pos = [200000, 205000]
	crossing.actors.opponent.pos = [200000, 275000]
	crossing.tick = 1
	Sim._advance_projectiles(crossing, BattleRng.new(42))
	_check(crossing.actors.opponent.hp < 110, "relative swept collision catches crossing moving fighter and projectile")
	var melee := _projectile_session()
	melee.projectiles = []
	melee.actors.opponent.pos = [150000, 240000]
	melee.actors.opponent.previous_pos = [150000, 240000]
	Sim._start_action(melee, "player", "basic_attack", 36, 20, 3)
	Sim._resolve_melee(melee, "player", BattleRng.new(42))
	_check(melee.actors.opponent.hp == 110, "melee telegraph causes no premature damage")
	melee.actors.player.action_tick = 20
	Sim._resolve_melee(melee, "player", BattleRng.new(42))
	var hp: int = melee.actors.opponent.hp
	Sim._resolve_melee(melee, "player", BattleRng.new(42))
	_check(hp < 110 and melee.actors.opponent.hp == hp, "active melee hits once per target")


func _test_many_seeds() -> void:
	var forest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/arenas/forest.json"))
	var safe := true
	var deterministic := true
	var evades := 0
	var hits := 0
	for seed: int in range(12):
		var session := _session(seed + 1, forest if seed % 3 == 0 else {}, 750)
		while not session.complete:
			Sim.step(session)
			for id: String in session.fighter_order:
				var actor: Dictionary = session.actors[id]
				safe = safe and Arena.position_clear(session.arena, actor.pos, Sim.BODY_RADIUS) and actor.hp >= 0 and actor.hp <= 110 and actor.mp >= 0 and actor.mp <= 48
				safe = safe and actor.pos[0] is int and actor.pos[1] is int
			safe = safe and not Arena.boxes_overlap(session.actors.player.pos, session.actors.opponent.pos, Sim.BODY_RADIUS * 2)
		for event: Dictionary in session.log:
			evades += int(event.event == "evade")
			hits += int(event.event == "hit")
		if seed < 3:
			deterministic = deterministic and JSON.stringify(Sim.replay(Sim.replay_record(session))) == JSON.stringify(session)
	_check(safe, "12 seeds maintain finite-body clearance and HP/MP/fixed-point invariants every tick")
	_check(deterministic, "multiple seeded arenas replay byte-identically")
	_check(evades > 0 and hits > 0, "early-game brains8 battles include both natural evasions and actual hits")
	print("  Seeded scenario events: %d evades, %d hits" % [evades, hits])


func _test_high_speed_navigation_and_visual_pins() -> void:
	var arena := Arena.graybox()
	arena.obstacles = [_obstacle([285, 140, 70, 200])]
	for speed: int in [100, 999]:
		var fast := Sim.create_session("fast-route", 3, _fighter("player", speed), _fighter("opponent"), arena, 600)
		fast.actors.opponent.action = "guard"
		fast.actors.opponent.action_duration = 9999
		fast.actors.player.next_decision = 9999
		var reached := false
		for tick: int in range(240):
			Sim.step(fast)
			if fast.actors.player.pos[0] > 400000:
				reached = true
				break
		_check(reached, "speed%d fighter traverses obstacle route without waypoint oscillation" % speed)
	var pins := {"player": {"assetId": "agumon", "revision": "test-approved-1"}, "opponent": {"assetId": "agumon", "revision": "test-approved-2"}}
	var pinned := Sim.create_session("visual-pins", 9, _fighter("player"), _fighter("opponent"), {}, 90, pins)
	pins.player.revision = "changed-after-start"
	for tick: int in range(90):
		Sim.step(pinned)
	_check(pinned.content_revisions.visuals.player.revision == "test-approved-1", "fighter visual revisions captured immutably")
	_check(JSON.stringify(Sim.replay(Sim.replay_record(pinned))) == JSON.stringify(pinned), "replay preserves exact pinned fighter visual revisions")
	_check(not Sim.create_session("bad-pins", 1, _fighter("player"), _fighter("opponent"), {}, 90, {"missing": {"assetId": "a", "revision": "1"}}).ok, "visual pins with foreign fighter ID rejected")
	var old_fighters: Array = []
	for id: String in ["player", "opponent"]:
		var current := _fighter(id)
		old_fighters.append(Legacy.make_snapshot(id, current.display_name, current.species_id, current.stage, current.nature, current.stats))
	var golden := Legacy.simulate("golden-battle-v2", 20260909, old_fighters[0], old_fighters[1], 900)
	print("  battle-v2 golden fingerprint: %s" % JSON.stringify(golden).sha256_text())
	_check(JSON.stringify(golden).sha256_text() == "f684c88673239c31bfbadffce63f05b017d3874706e49008baf5634af49d7bfe", "battle-v2 canonical fixture fingerprint")
	var large_seed := Sim.create_session("large-seed", 0x7fffffffffffffff, _fighter("player"), _fighter("opponent"), {}, 1)
	Sim.step(large_seed)
	var restored := Sim.replay(JSON.parse_string(JSON.stringify(Sim.replay_record(large_seed))))
	_check(restored.actors == large_seed.actors, "31-bit canonical seed survives large-input JSON replay")


func _test_shared_arena_cases() -> void:
	var corpus: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/arenas/shared-arena-cases.json"))
	if not corpus is Array:
		_check(false, "shared arena corpus loads")
		return
	for fixture: Dictionary in corpus:
		_check(Arena.validate(fixture.arena).is_empty() == bool(fixture.expectedValid), "shared arena fixture: " + String(fixture.name))


func _obstacle(rect: Array) -> Dictionary:
	return {"id": "test-obstacle", "rect": rect, "movement": true, "projectile": true, "sight": true, "occlusion": false}


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)
