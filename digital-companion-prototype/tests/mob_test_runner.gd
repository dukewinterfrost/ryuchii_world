extends SceneTree

var failures := 0
var checks := 0

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: " + label)

func _initialize() -> void:
	var loaded := MobContent.load_tables()
	check(loaded.ok, "mob content loads: " + loaded.error)
	if not loaded.ok:
		quit(1)
		return
	var config: Dictionary = loaded.config
	var hero := BattleSimulator.make_snapshot("player", "Partner", "agumon", "Rookie", "Gentle", {"hp": 100, "mp": 60, "offense": 8, "defense": 8, "speed": 8, "brains": 8}, {}, config)
	var arena := BattleArena.graybox()
	for wins: int in [0, 1, 2, 3, 10]:
		var encounter := MobCatalog.encounter(wins, 31)
		check(encounter.members.size() == (1 if wins == 0 else 3), "encounter group size")
		var assembled := MobCatalog.roster(hero, encounter, arena, config)
		check(assembled.ok, "safe roster assembly")
		var session := BattleSimulator.create_roster_session("mob-test-%d" % wins, 31, assembled.roster, arena, 900, {}, {}, {}, "", "", config)
		check(session.ok, "roster validates: " + String(session.get("error", "")))
		if not session.ok: continue
		var target := String(session.fighter_order[-1])
		var cmd := {"kind": "focus_target", "fighter_id": "player", "target_id": target, "command_id": "focus-1"}
		check(BattleSimulator.preflight_command(session, cmd).ok, "focus accepted")
		BattleSimulator.step(session, [cmd])
		check(session.actors.player.focus_target_id == target, "focus persists")
		while not session.complete: BattleSimulator.step(session)
		var record := BattleSimulator.replay_record(session)
		var replayed := BattleSimulator.replay(record)
		check(replayed.ok and replayed.result == session.result, "v5 replay deterministic")
	for id: String in MobCatalog.creatures():
		var mob := MobCatalog.snapshot(id, "mob", config)
		check(mob.skills.equipped.size() == 3, id + " has three abilities")
		check(BattleSimulator.validate_snapshot(mob).is_empty(), id + " valid snapshot")
	var team := MobCatalog.roster(hero, MobCatalog.encounter(2, 1), arena, config)
	var healing := BattleSimulator.create_roster_session("healing", 1, team.roster, arena, 900, {}, {}, {}, "", "", config)
	if healing.ok:
		healing.actors.enemy_1.hp = 10
		BattleSimulatorV5._commit_move(healing, "enemy_3", config.moves.mend)
		for tick: int in 31: BattleSimulator.step(healing)
		check(healing.actors.enemy_1.hp == 19, "Mend restores exactly 25 percent")
		check(healing.actors.enemy_3.mp == 52, "Mend spends MP once")
		check(healing.actors.player.hp == 100, "Mend cannot heal hostiles")
	_test_support_and_focus(hero, config, arena)
	_test_settlement()
	var fresh := CareRules.make_new_state(1000)
	check(CareRules.state_is_valid(fresh), "new save validates")
	var old := fresh.duplicate(true)
	old.battle.erase("mob_wins")
	var migrated := CareRules.migrate_state_v10(old)
	check(not migrated.is_empty() and migrated.battle.mob_wins == 0 and migrated.battle_profile == fresh.battle_profile, "old save starts intro and preserves stats")
	print("Mobs: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)


func _test_support_and_focus(hero: Dictionary, config: Dictionary, arena: Dictionary) -> void:
	var roster := MobCatalog.roster(hero, MobCatalog.encounter(2, 1), arena, config)
	var session := BattleSimulator.create_roster_session("support-boundaries", 1, roster.roster, arena, 900, {}, {}, {}, "", "", config)
	var healer: Dictionary = session.actors.enemy_3
	var first: Dictionary = session.actors.enemy_1
	var second: Dictionary = session.actors.enemy_2
	first.hp = 18
	second.hp = 9
	check(BattleSimulatorV5._support_target(session, "enemy_3", config.moves.mend) == "enemy_2", "healer chooses lowest HP percentage")
	first.hp = 9
	check(BattleSimulatorV5._support_target(session, "enemy_3", config.moves.mend) == "enemy_1", "heal ties use fighter order")
	first.hp = 0
	check(BattleSimulatorV5._support_target(session, "enemy_3", config.moves.mend) == "enemy_2", "heal skips defeated ally")
	healer.support_target_id = "enemy_1"
	BattleSimulatorV5._release_support(session, "enemy_3", config.moves.mend)
	check(first.hp == 0, "heal never revives")
	healer.support_target_id = "enemy_2"
	second.hp = 35
	BattleSimulatorV5._release_support(session, "enemy_3", config.moves.mend)
	check(second.hp == 36, "heal clamps to max HP")
	second.hp = 22
	check(BattleSimulatorV5._support_target(session, "enemy_3", config.moves.mend).is_empty(), "60 percent threshold suppresses healthy healing")
	second.hp = 9
	var old_pos: Array = healer.pos.duplicate()
	healer.pos = [0, 0]
	check(BattleSimulatorV5._support_target(session, "enemy_3", config.moves.mend).is_empty(), "heal respects range")
	healer.pos = old_pos
	var old_obstacles: Array = session.arena.obstacles.duplicate(true)
	var middle_y := int((int(healer.pos[1]) + int(second.pos[1])) / 2000)
	session.arena.obstacles.append({"id": "heal-wall", "rect": [0, middle_y, 640, 4], "movement": false, "projectile": false, "sight": true, "occlusion": false})
	check(BattleSimulatorV5._support_target(session, "enemy_3", config.moves.mend).is_empty(), "heal respects line of sight")
	session.arena.obstacles = old_obstacles
	healer.mp = 0
	check(not BattleSimulatorV5._available(healer, config.moves.mend, int(session.tick)), "no MP means no heal")
	check(BattleSimulatorV5._available(healer, config.moves.fairy_strike, int(session.tick)), "no MP still allows basic melee")
	healer.mp = 60
	healer.support_target_id = "enemy_2"
	BattleSimulatorV5._release_support(session, "enemy_3", config.moves.ward)
	check(second.effects.has("barrier") and second.effects.barrier.amount == config.moves.ward.barrier_amount, "ward creates finite absorption")
	var cmd := {"kind": "focus_target", "fighter_id": "player", "command_id": "invalid-focus", "target_id": "enemy_1"}
	check(not BattleSimulator.preflight_command(session, cmd).ok, "cannot focus defeated enemy")
	cmd.target_id = "player"
	check(not BattleSimulator.preflight_command(session, cmd).ok, "cannot focus self")
	first.hp = 36
	var player: Dictionary = session.actors.player
	player.target_id = "enemy_1"
	BattleSimulatorV5._commit_move(session, "player", config.moves.pepper_breath)
	var aim: Array = player.aim.duplicate()
	cmd.target_id = "enemy_3"
	BattleSimulator.step(session, [cmd])
	check(player.aim == aim and player.target_id == "enemy_1" and player.focus_target_id == "enemy_3", "focus during charge preserves committed aim")
	healer.hp = 0
	for tick: int in 100: BattleSimulator.step(session)
	check(player.focus_target_id.is_empty() and player.target_id in ["enemy_1", "enemy_2"], "dead focus retargets surviving hostile")
	for id: String in MobCatalog.creatures():
		var mob := MobCatalog.snapshot(id, "enemy", config)
		mob.merge({"team_id": "enemy", "controller_id": "", "spawn": [160,240]}, true)
		var partner := hero.duplicate(true)
		partner.merge({"team_id": "player", "controller_id": "player", "spawn": [100,240]}, true)
		for slot: Dictionary in mob.skills.equipped:
			var match_data := BattleSimulator.create_roster_session("move-check", 3, [partner, mob], arena, 90, {}, {}, {}, "", "", config)
			var move: Dictionary = config.moves[slot.move_id]
			BattleSimulatorV5._commit_move(match_data, "enemy", move)
			check(match_data.actors.enemy.mp == int(mob.stats.mp) - int(move.mp_cost) and match_data.actors.enemy.current_move.id == slot.move_id, id + " commits " + slot.move_id)


func _test_settlement() -> void:
	var game := preload("res://scripts/core/game_state.gd").new()
	game.state = CareRules.make_new_state(1000)
	var repository := PromotionFailureSaveRepository.new("/tmp/mob-settlement-%d.json" % Time.get_ticks_usec())
	repository.fail_next_promotion = false
	game._repository = repository
	for outcome: String in ["loss", "draw", "win"]:
		check(game.start_training_battle(41, "graybox").ok, "settlement fixture starts")
		game.active_battle_result.complete = true
		game.active_battle_result.result = {"outcome": outcome}
		if outcome == "win":
			repository.fail_next_promotion = true
			check(not game.finish_training_battle().ok and game.state.battle.mob_wins == 0, "failed save never advances intro")
		check(game.finish_training_battle().ok, "settlement saves " + outcome)
		check(game.state.battle.mob_wins == (1 if outcome == "win" else 0), "only saved win advances intro")
		game.finish_training_battle()
		check(game.state.battle.mob_wins == (1 if outcome == "win" else 0), "repeated settlement is idempotent")
		game.clear_active_battle()
	check(repository.load_state().state.battle.mob_wins == 1, "intro progress survives reload")
	repository.clear()
	game.free()
