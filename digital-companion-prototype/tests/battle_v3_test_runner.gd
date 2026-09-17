extends SceneTree

const Sim = preload("res://scripts/battle/battle_simulator.gd")
const Legacy = preload("res://scripts/battle/battle_simulator_v2.gd")
const Playback = preload("res://scripts/battle/battle_playback_model.gd")
var _checks := 0
var _failures := 0


func _initialize() -> void:
	_test_definitions()
	_test_zero_mp()
	_test_move_requests()
	_test_items()
	_test_replays()
	print("%s: %d battle-v3 checks (%d failures)" % ["PASS" if _failures == 0 else "FAIL", _checks, _failures])
	quit(0 if _failures == 0 else 1)


func _fighter(id: String, species: String = "agumon", nature: String = "Bold", mp: int = 48) -> Dictionary:
	var stage: String = {"botamon": "Baby", "koromon": "In-Training", "agumon": "Rookie"}[species]
	return Sim.make_snapshot(id, id.capitalize(), species, stage, nature, {"hp": 200, "mp": mp, "offense": 10, "defense": 8, "speed": 8, "brains": 8})


func _session(ticks: int = 600) -> Dictionary:
	return Sim.create_session("v3-tests", 42, _fighter("player"), _fighter("opponent"), {}, ticks, {}, {"small_recovery": 3, "mp_recovery": 3})


func _command(id: String, kind: String, value: String, fighter: String = "player") -> Dictionary:
	var command := {"command_id": id, "kind": kind, "fighter_id": fighter}
	command[{"item_use": "item_id", "move_request": "move_id", "order": "order"}[kind]] = value
	return command


func _park(session: Dictionary, id: String, position: Array) -> void:
	var actor: Dictionary = session.actors[id]
	actor.pos = position.duplicate()
	actor.previous_pos = position.duplicate()
	actor.action = "guard"
	actor.action_start = 0
	actor.action_duration = 2000


func _events(session: Dictionary, event_name: String, actor: String = "") -> Array:
	return session.log.filter(func(event: Dictionary) -> bool: return event.event == event_name and (actor.is_empty() or event.actor_id == actor))


func _test_definitions() -> void:
	var player := _fighter("player")
	_check(Sim.validate_snapshot(player).is_empty(), "v3 snapshot validates")
	_check(player.skills.equipped.size() == 3, "Rookie receives three equipped starter skills")
	_check(player.moves.heavy_claw.windup == 30 and player.moves.heavy_claw.active == 3 and player.moves.heavy_claw.duration == 54, "heavy claw preserves specified tick windows")
	_check(player.moves.quick_bite.mp_cost == 4 and player.moves.quick_bite.power == 115, "quick bite balance")
	_check(player.moves.pepper_breath.mp_cost == 12 and player.moves.pepper_breath.power == 150 and player.moves.pepper_breath.duration == 50, "pepper breath retains balance")
	var invalid := player.duplicate(true)
	invalid.moves.claw.mp_cost = 1
	_check(not Sim.validate_snapshot(invalid).is_empty(), "paid fallback rejected")
	invalid = player.duplicate(true)
	invalid.skills.learned.append("claw")
	invalid.skills.equipped.append({"move_id": "claw", "auto": true})
	_check(not Sim.validate_snapshot(invalid).is_empty(), "fallback cannot be equipped")
	invalid = player.duplicate(true)
	invalid.skills.equipped[1] = invalid.skills.equipped[0].duplicate()
	_check(not Sim.validate_snapshot(invalid).is_empty(), "duplicate loadout rejected")
	invalid = player.duplicate(true)
	invalid.moves.quick_bite.active = 40
	_check(not Sim.validate_snapshot(invalid).is_empty(), "impossible active window rejected")
	var session := Sim.create_session("pinned", 1, player, _fighter("opponent"))
	player.moves.quick_bite.power = 500
	player.skills.equipped.clear()
	_check(session.fighters[0].moves.quick_bite.power == 115 and session.fighters[0].skills.equipped.size() == 3, "session copies definitions and loadout")
	_check(not Sim.create_session("bad", 1, _fighter("player"), _fighter("opponent"), {}, 600, {}, {"unknown_item": 1}).ok, "unknown initial supply rejected")
	_check(not Sim.create_session("bad", 1, _fighter("player"), _fighter("opponent"), {}, 600, {}, {"small_recovery": -1}).ok, "negative initial supply rejected")
	_check(Sim.create_session("max-supplies", 1, _fighter("player"), _fighter("opponent"), {}, 600, {}, {"small_recovery": 1000000000}).ok, "valid durable inventory cap starts battle")
	_check(not Sim.create_session("too-many", 1, _fighter("player"), _fighter("opponent"), {}, 600, {}, {"small_recovery": 1000000001}).ok, "inventory over durable cap rejected")
	var no_auto := _fighter("player")
	for slot: Dictionary in no_auto.skills.equipped:
		slot.auto = false
	session = Sim.create_session("no-auto", 2, no_auto, _fighter("opponent"), {}, 450)
	while not session.complete:
		Sim.step(session)
	var used: Array = _events(session, "action_started", "player").filter(func(event: Dictionary) -> bool: return event.get("move_id", "") in ["quick_bite", "heavy_claw", "pepper_breath"])
	_check(used.is_empty(), "disabled automatic skills are never selected")


func _test_zero_mp() -> void:
	for species: String in ["botamon", "koromon", "agumon"]:
		for nature: String in Sim.SUPPORTED_NATURES:
			var session := Sim.create_session("zero-mp-%s-%s" % [species, nature], 83, _fighter("player", species, nature, 0), _fighter("opponent", "agumon", "Bold", 0), {}, 900)
			Sim.step(session, [_command("keep", "order", "keep_distance")])
			while not session.complete:
				Sim.step(session)
			var hits := _events(session, "hit", "player")
			var fallback := Sim._fallback_id(species)
			_check(not hits.is_empty() and hits.all(func(event: Dictionary) -> bool: return event.action_id == fallback), "%s/%s reaches and lands permanent melee at zero MP" % [species, nature])
			_check(_events(session, "projectile_spawned", "player").is_empty(), "%s/%s never emits a zero-MP ranged hit" % [species, nature])


func _test_move_requests() -> void:
	var session := _session()
	_park(session, "opponent", [240000, 240000])
	_park(session, "player", [200000, 240000])
	session.actors.player.action_duration = 40
	var heavy := _command("heavy", "move_request", "heavy_claw")
	Sim.step(session, [heavy])
	_check(session.actors.player.pending_move == "heavy_claw" and session.actors.player.mp == 48, "request acknowledged without MP charge")
	for tick: int in range(29):
		Sim.step(session)
	_check(session.actors.player.action == "guard" and session.actors.player.mp == 48, "request cannot cancel committed recovery")
	while int(session.tick) < 40:
		Sim.step(session)
	_check(session.actors.player.current_move.id == "heavy_claw" and session.actors.player.action_start == 40 and session.actors.player.mp == 40, "request commits after recovery and spends MP once")
	_check(session.actors.player.pending_move.is_empty(), "committed request clears pending slot")
	_check(not Sim.preflight_command(session, heavy).ok, "move request IDs reject duplicates")
	_check(not Sim.preflight_command(session, _command("fallback", "move_request", "claw")).ok, "fallback cannot be explicitly equipped/requested")
	_check(not Sim.preflight_command(session, _command("enemy", "move_request", "quick_bite", "opponent")).ok, "player cannot request enemy move")
	session.actors.player.mp = 0
	_check(not Sim.preflight_command(session, _command("poor", "move_request", "quick_bite")).ok, "unaffordable request rejected")
	var baby := Sim.create_session("baby", 1, _fighter("player", "botamon"), _fighter("opponent"))
	_check(not Sim.preflight_command(baby, _command("locked", "move_request", "acid_bubbles")).ok, "skills requests locked before Rookie")

	session = _session()
	_park(session, "opponent", [400000, 240000])
	session.actors.player.next_decision = 999
	for slot: Dictionary in session.fighters[0].skills.equipped:
		slot.auto = false
	Sim.step(session, [_command("range", "move_request", "quick_bite")])
	var before_reaction := int(session.actors.player.move_ready_tick) - 1
	while int(session.tick) < before_reaction:
		Sim.step(session)
	_check(session.actors.player.mp == 48, "reaction latency does not spend MP")
	while int(session.tick) < 150 and session.actors.player.current_move.is_empty():
		Sim.step(session)
	_check(session.actors.player.current_move.get("id") == "quick_bite", "explicit request works with auto disabled and approaches target")
	_check(Sim._length(Sim._subtract(session.actors.opponent.pos, session.actors.player.pos)) <= Sim.BASIC_RANGE, "melee request commits only at melee range")

	session = _session()
	_park(session, "player", [200000, 240000])
	_park(session, "opponent", [240000, 240000])
	Sim.step(session, [_command("old", "move_request", "heavy_claw")])
	Sim.step(session, [_command("new", "move_request", "quick_bite")])
	_check(session.actors.player.pending_move == "quick_bite" and session.actors.player.move_expires_tick == 152, "new request replaces old with fresh five-second deadline")
	while int(session.tick) < 152:
		Sim.step(session)
	_check(session.actors.player.pending_move.is_empty() and session.actors.player.mp == 48 and _events(session, "move_expired").size() == 1, "request expires during recovery with no MP cost")


func _test_items() -> void:
	var session := _session()
	_park(session, "player", [100000, 240000])
	_park(session, "opponent", [540000, 240000])
	var heal := _command("heal", "item_use", "small_recovery")
	_check(not Sim.preflight_command(session, heal).ok, "full HP item rejected")
	session.actors.player.hp = 120
	session.actors.player.mp = 1
	var before := JSON.stringify(session)
	var preview := Sim.preflight_commands(session, [heal, heal, _command("mp", "item_use", "mp_recovery"), _command("order", "order", "attack")])
	_check(JSON.stringify(session) == before, "batch preflight never mutates live battle")
	_check(preview.commands.size() == 2 and preview.rejected.size() == 2, "batch reserves duplicate IDs and shared cross-item cooldown")
	_check(preview.commands[0].tick == 1 and preview.commands[0].kind == "item_use", "preflight normalizes next tick")
	# This models the required save-failure branch: omit an unpersisted item.
	Sim.step(session, [preview.commands[1]])
	_check(session.actors.player.hp == 120 and session.supplies.small_recovery == 3, "omitting item after failed save leaves HP and supply unchanged")
	preview = Sim.preflight_command(session, heal)
	Sim.step(session, [preview.command])
	_check(session.actors.player.hp == 170 and session.supplies.small_recovery == 2 and session.item_ready_tick == 152, "accepted item restores exactly 50 and spends one next tick")
	_check(not Sim.preflight_command(session, heal).ok, "accepted item ID cannot be reused")
	var recover_mp := _command("recover-mp", "item_use", "mp_recovery")
	_check(not Sim.preflight_command(session, recover_mp).ok, "HP and MP items share cooldown")
	while int(session.tick) < 151:
		Sim.step(session)
	_check(Sim.preflight_command(session, recover_mp).ok, "item cooldown releases at exact 150-tick boundary")
	Sim.step(session, [recover_mp])
	_check(session.actors.player.mp == 25 and session.supplies.mp_recovery == 2, "MP item restores exactly 24")
	session.item_ready_tick = 0
	session.actors.player.hp = 190
	Sim.step(session, [_command("cap", "item_use", "small_recovery")])
	_check(session.actors.player.hp == 200, "recovery clamps to maximum HP")
	session.item_ready_tick = 0
	session.actors.player.mp = 47
	Sim.step(session, [_command("mp-cap", "item_use", "mp_recovery")])
	_check(session.actors.player.mp == 48, "recovery clamps to maximum MP")
	session.actors.player.hp = 1
	session.supplies.small_recovery = 0
	_check(not Sim.preflight_command(session, _command("empty", "item_use", "small_recovery")).ok, "empty inventory cannot heal")
	session.supplies.small_recovery = 1
	session.actors.player.hp = 0
	_check(not Sim.preflight_command(session, _command("dead", "item_use", "small_recovery")).ok, "items cannot revive a defeated fighter")
	_check(not Sim.preflight_command(session, _command("enemy-heal", "item_use", "small_recovery", "opponent")).ok, "enemy item target rejected")
	session.actors.player.hp = 1
	_check(not Sim.preflight_command(session, {"kind": {}, "fighter_id": "player", "command_id": "bad"}).ok, "malformed command discriminant rejected safely")
	_check(not Sim.preflight_command(session, {"kind": "item_use", "fighter_id": "player", "item_id": "small_recovery"}).ok, "new item command requires explicit identity")


func _test_replays() -> void:
	var session := _session(900)
	var used_items := 0
	while not session.complete:
		var commands: Array = []
		if int(session.tick) in [0, 70, 200]:
			commands.append(_command("order-%d" % session.tick, "order", "attack"))
		if int(session.tick) in [110, 390]:
			commands.append(_command("move-%d" % session.tick, "move_request", "quick_bite"))
		if int(session.actors.player.hp) < 180 and int(session.supplies.small_recovery) > 0:
			commands.append(_command("heal-%d" % session.tick, "item_use", "small_recovery"))
		elif int(session.actors.player.mp) < 30 and int(session.supplies.mp_recovery) > 0:
			commands.append(_command("mp-%d" % session.tick, "item_use", "mp_recovery"))
		var preview := Sim.preflight_commands(session, commands)
		for command: Dictionary in preview.commands:
			if command.kind == "item_use":
				used_items += 1
		Sim.step(session, preview.commands)
	_check(used_items > 1, "replay scenario exercised real accepted item uses")
	var record := Sim.replay_record(session)
	_check(record.initial_supplies.small_recovery == 3 and record.item_definitions.mp_recovery.amount == 24, "replay pins initial supplies and item definitions")
	var replay := Sim.replay(record)
	_check(JSON.stringify(replay) == JSON.stringify(session), "v3 command replay reconstructs full session byte-for-byte")
	var roundtrip := Sim.replay(JSON.parse_string(JSON.stringify(record)))
	_check(roundtrip.get("actors") == session.actors and roundtrip.get("supplies") == session.supplies, "JSON replay preserves integer moves, state, and inventory")
	var changed := record.duplicate(true)
	changed.commands.append(changed.commands[-1].duplicate(true))
	_check(not Sim.replay(changed).ok, "replay rejects duplicated command identity")
	changed = record.duplicate(true)
	changed.initial_supplies = {"small_recovery": 0, "mp_recovery": 0}
	_check(not Sim.replay(changed).ok, "replay rejects impossible item input")
	var playback := Playback.new()
	playback.setup(session)
	_check(playback.error.is_empty(), "v3 playback accepts completed item battle")
	playback.skip_to_end()
	_check(playback.get_session().actors == session.actors and playback.get_session().supplies == session.supplies, "presentation playback uses pinned item state without durable inventory")

	var old_player := Legacy.make_snapshot("player", "Player", "agumon", "Rookie", "Bold", {"hp": 110, "mp": 48, "offense": 10, "defense": 8, "speed": 8, "brains": 8})
	var old_enemy := old_player.duplicate(true)
	old_enemy.fighter_id = "opponent"
	old_enemy.display_name = "Opponent"
	var old := Legacy.simulate("golden-battle-v2", 20260909, old_player, old_enemy, 900)
	_check(JSON.stringify(old).sha256_text() == "f684c88673239c31bfbadffce63f05b017d3874706e49008baf5634af49d7bfe", "battle-v2 golden remains byte-for-byte unchanged")
	_check(JSON.stringify(Sim.replay(Sim.replay_record(old))) == JSON.stringify(old), "public replay dispatch preserves battle-v2")
	playback = Playback.new()
	playback.setup(old)
	_check(playback.error.is_empty(), "legacy battle playback sets up using version dispatch")
	playback.skip_to_end()
	_check(playback.get_session().actors == old.actors, "legacy playback finishes with original actors")


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)
