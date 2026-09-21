class_name MobCatalog
extends RefCounted

const Arena = preload("res://scripts/battle/battle_arena.gd")

static func creatures() -> Dictionary:
	var result := {}
	for row: Dictionary in GameBalance.table("creatures"):
		result[row.id] = row
	return result

static func snapshot(id: String, fighter_id: String, config: Dictionary) -> Dictionary:
	var definition: Dictionary = creatures().get(id, {})
	if definition.is_empty(): return {}
	var stats := {}
	for key: String in ["hp", "mp", "offense", "defense", "speed", "brains"]:
		stats[key] = int(definition[key])
	var learned: Array = String(definition.moves).split("|")
	var slots: Array = []
	for move: String in learned: slots.append({"move_id": move, "auto": true})
	return BattleSimulator.make_snapshot(fighter_id, definition.name, id, "Rookie", definition.nature, stats, {"learned": learned, "equipped": slots}, config)

static func encounter(wins: int, seed_value: int) -> Dictionary:
	var rows := GameBalance.table("encounters")
	var index := mini(wins, rows.size() - 1)
	if index < 0: return {}
	var entry: Dictionary = rows[index].duplicate(true)
	var members: Array = String(entry.members).split("|")
	if entry.id == "mixed_groups":
		var rng := BattleRng.new(seed_value)
		var slimes: Array = []
		var fairies: Array = []
		for row: Dictionary in GameBalance.table("creatures"):
			if row.id.begins_with("slime"): slimes.append(row.id)
			elif row.id.begins_with("fairy"): fairies.append(row.id)
		members = [slimes[rng.next_int(slimes.size())], slimes[rng.next_int(slimes.size())]]
		var pool: Array = slimes + fairies
		members.append(pool[rng.next_int(pool.size())])
	entry.members = members
	return entry

static func roster(player: Dictionary, encounter_data: Dictionary, arena: Dictionary, config: Dictionary) -> Dictionary:
	var result: Array = []
	var hero := player.duplicate(true)
	hero.merge({"team_id": "player", "controller_id": "player", "spawn": arena.spawns.player.duplicate()}, true)
	result.append(hero)
	for index: int in encounter_data.members.size():
		var fighter := snapshot(encounter_data.members[index], "enemy_%d" % (index + 1), config)
		if fighter.is_empty(): return {"ok": false, "error": "Unknown creature in encounter."}
		var spawn := _spawn(arena, result, index)
		if spawn.is_empty(): return {"ok": false, "error": "Arena has no safe mob formation."}
		fighter.merge({"team_id": "enemy", "controller_id": "", "spawn": spawn}, true)
		result.append(fighter)
	return {"ok": true, "roster": result}

static func _spawn(arena: Dictionary, roster_data: Array, index: int) -> Array:
	var origin: Array = arena.spawns.opponent
	var candidates: Array = []
	var formation := [[0, 0], [-1, -1], [-1, 1]]
	var preferred: Array = formation[mini(index, 2)]
	candidates.append([int(origin[0]) + int(preferred[0]) * 70, int(origin[1]) + int(preferred[1]) * 70])
	for ring: int in range(9):
		for offset: Array in [[0, 0], [0, -1], [0, 1], [-1, 0], [1, 0], [-1, -1], [-1, 1], [1, -1], [1, 1]]:
			candidates.append([int(origin[0]) + int(offset[0]) * ring * 70, int(origin[1]) + int(offset[1]) * ring * 70])
	for candidate: Array in candidates:
		var pos := Arena.to_fixed(candidate)
		if not Arena.position_clear(arena, pos, 14000): continue
		var clear := true
		for fighter: Dictionary in roster_data:
			if Arena.boxes_overlap(pos, Arena.to_fixed(fighter.spawn), 50000): clear = false
		if clear and not Arena.path(arena, pos, Arena.to_fixed(arena.spawns.player), 14000).is_empty():
			return candidate
	return []
