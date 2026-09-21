class_name MobContent
extends RefCounted

## File I/O and decimal authoring belong here, never in the integer simulator.
## Returned configurations are independent copies. Reload commits all four tables
## together, so a bad edit cannot invalidate a running or last-valid test battle.
const DIRECTORY := "res://assets/combat"
const SCHEMA_VERSION := "combat-content-v2"
const TICKS_PER_SECOND := 30
const SCALE := 1000
const SPECIES := ["botamon", "koromon", "agumon", "slime_basic", "slime_metal", "slime_spitter", "fairy_healer", "fairy_striker"]
const NATURES := ["Bold", "Gentle", "Jolly", "Calm", "Earnest", "Stubborn"]
const FALLBACKS := {"botamon": "tackle", "koromon": "headbutt", "agumon": "claw", "slime_basic": "slime_bump", "slime_metal": "slime_bump", "slime_spitter": "slime_bump", "fairy_healer": "fairy_strike", "fairy_striker": "fairy_strike"}
const SPECIALS := {"botamon": "acid_bubbles", "koromon": "bubble_blow", "agumon": "pepper_breath", "slime_basic": "slime_shot", "slime_metal": "harden", "slime_spitter": "quick_spit", "fairy_healer": "mend", "fairy_striker": "quick_spark"}
const MOVE_COLUMNS := ["id", "name", "species", "equippable", "kind", "mp_cost", "power_multiplier", "damage_variance", "cast_seconds", "active_seconds", "recovery_seconds", "cooldown_seconds", "range", "melee_width", "projectile_speed", "projectile_radius", "projectile_lifetime_seconds", "movement_while_casting", "rush_speed_multiplier", "auto_weight", "animation", "effect", "visual_scale", "target", "heal_percent", "trigger_percent", "barrier_amount", "effect_seconds"]
const ITEM_COLUMNS := ["id", "name", "effect", "stat", "amount", "duration_seconds", "movement_multiplier"]
const NATURE_COLUMNS := ["id", "opening_tackle", "approach_weight", "circle_weight", "retreat_weight", "guard_weight", "attack_weight"]
const TUNING_COLUMNS := ["id", "value", "unit"]
## Required units and authoring bounds; simulation receives only normalized ints.
const TUNING_SPEC := {
	"speed_base": ["units_per_second", 1, 600], "speed_bonus": ["units_per_second", 0, 1200], "speed_half_stat": ["integer", 1, 999],
	"dodge_duration": ["seconds", 0.033333, 3], "dodge_multiplier": ["multiplier", 1, 10],
	"defense_cooldown": ["seconds", 0.033333, 60], "ai_defense_cooldown": ["seconds", 0.033333, 60],
	"guard_duration": ["seconds", 0.033333, 5], "guard_damage_percent": ["integer", 0, 100],
	"perfect_guard_ticks": ["seconds", 0, 5], "perfect_guard_stagger": ["seconds", 0, 5],
	"item_cooldown": ["seconds", 0.033333, 60], "move_request_ttl": ["seconds", 0.033333, 60],
	"reaction_base": ["seconds", 0.033333, 5], "reaction_min": ["seconds", 0.033333, 5],
	"reaction_brains_divisor": ["integer", 1, 999], "reaction_jitter": ["seconds", 0, 3],
	"decision_min": ["seconds", 0.033333, 5], "decision_max": ["seconds", 0.033333, 5],
	"tactical_commit_min": ["seconds", 0.033333, 5], "tactical_commit_max": ["seconds", 0.033333, 5],
	"guard_mp_recovery": ["integer", 0, 9999],
}

static var _current: Dictionary = {}
static var _errors: Array[String] = []


static func defaults() -> Dictionary:
	if _current.is_empty():
		reload_tables()
	return _current.duplicate(true)


static func last_errors() -> Array[String]:
	return _errors.duplicate()


static func reload_tables(directory: String = DIRECTORY) -> Dictionary:
	var loaded := load_tables(directory)
	_errors.assign(loaded.errors)
	if loaded.ok:
		_current = loaded.config.duplicate(true)
	# On first-load failure this remains empty. Callers must display the errors and
	# disable combat; there is deliberately no hidden numeric balance fallback.
	loaded["previous_config"] = _current.duplicate(true)
	return loaded


static func load_tables(directory: String = DIRECTORY) -> Dictionary:
	var errors: Array[String] = []
	var moves := _read_table(directory.path_join("moves.csv"), MOVE_COLUMNS, errors)
	var items := _read_table(directory.path_join("items.csv"), ITEM_COLUMNS, errors)
	var natures := _read_table(directory.path_join("natures.csv"), NATURE_COLUMNS, errors)
	var tuning := _read_table(directory.path_join("tuning.csv"), TUNING_COLUMNS, errors)
	var config := {"schema_version": SCHEMA_VERSION, "ticks_per_second": TICKS_PER_SECOND, "scale": SCALE,
		"moves": {}, "items": {}, "natures": {}, "tuning": {}, "species": _species_registry()}
	for row: Dictionary in moves:
		var move := _normalize_move(row, errors)
		config.moves[row.id] = move
	for row: Dictionary in items:
		config.items[row.id] = _normalize_item(row, errors)
	for row: Dictionary in natures:
		var nature := {"opening_tackle": _boolean(row, "opening_tackle", errors)}
		if String(row.id) not in NATURES:
			_problem(errors, row, "id", "unknown saved nature")
		for key: String in ["approach_weight", "circle_weight", "retreat_weight", "guard_weight", "attack_weight"]:
			nature[key] = int(_number(row, key, 0, 100, errors, true))
		if int(nature.approach_weight) + int(nature.circle_weight) + int(nature.retreat_weight) == 0:
			_problem(errors, row, "approach_weight", "movement weights cannot all be zero")
		config.natures[row.id] = nature
	for row: Dictionary in tuning:
		if not TUNING_SPEC.has(row.id):
			_problem(errors, row, "id", "unknown tuning key")
			continue
		var spec: Array = TUNING_SPEC[row.id]
		if row.unit != spec[0]:
			_problem(errors, row, "unit", "must be '%s'" % spec[0])
		var value := _number(row, "value", float(spec[1]), float(spec[2]), errors, spec[0] == "integer")
		config.tuning[row.id] = _quantize(value, String(spec[0]))
	_validate_required_rows(config, errors)
	if errors.is_empty():
		config["sha256"] = snapshot_hash(config)
		var problem := validate_snapshot(config)
		if not problem.is_empty():
			errors.append(problem)
	if not errors.is_empty():
		return {"ok": false, "config": {}, "errors": errors, "error": "\n".join(errors)}
	return {"ok": true, "config": config, "errors": errors, "error": ""}


static func moves_for_species(species: String, config: Dictionary = {}) -> Dictionary:
	var source := defaults() if config.is_empty() else config
	var result := {}
	for id: String in source.get("moves", {}):
		if species in source.moves[id].species:
			result[id] = source.moves[id].duplicate(true)
	return result


static func move_metadata(config: Dictionary = {}) -> Dictionary:
	var source := defaults() if config.is_empty() else config
	var result := {}
	for id: String in source.get("moves", {}):
		var move: Dictionary = source.moves[id]
		result[id] = {"name": move.name, "mp": move.mp_cost, "power": move.power,
			"range": "ranged" if move.kind == "projectile" else "melee", "equippable": move.equippable,
			"windup": move.windup, "active": move.active, "duration": move.duration,
			"species": move.species.duplicate(), "content_available": true}
	return result


static func item_metadata(config: Dictionary = {}) -> Dictionary:
	var source := defaults() if config.is_empty() else config
	var result := {}
	for id: String in source.get("items", {}):
		var item: Dictionary = source.items[id]
		result[id] = {"name": item.name, "stat": item.stat, "restore": item.amount,
			"effect": item.effect, "duration_ticks": item.duration_ticks,
			"movement_multiplier": item.movement_multiplier, "content_available": true}
	return result


## Sorted keys and integral-number normalization make JSON replay roundtrips hash
## identically. Hash includes complete normalized presentation and combat content.
static func snapshot_hash(config: Dictionary) -> String:
	var copy: Dictionary = normalize_snapshot(config)
	copy.erase("sha256")
	return "sha256:" + JSON.stringify(copy, "", true, true).sha256_text()


static func normalize_snapshot(config: Dictionary) -> Dictionary:
	return _canonical(config)


static func _canonical(value: Variant) -> Variant:
	if value is Dictionary:
		var result := {}
		var keys: Array = value.keys()
		keys.sort()
		for key: Variant in keys:
			result[key] = _canonical(value[key])
		return result
	if value is Array:
		var result: Array = []
		for entry: Variant in value:
			result.append(_canonical(entry))
		return result
	if value is float and is_finite(value) and value == floor(value):
		return int(value)
	return value


## Pure validation for untrusted pinned replay content. No cache or file access.
static func validate_snapshot(config: Dictionary) -> String:
	if config.get("schema_version") != SCHEMA_VERSION or config.get("ticks_per_second") != 30 or config.get("scale") != 1000:
		return "combat configuration version or units are invalid"
	for table: String in ["moves", "items", "natures", "tuning", "species"]:
		if not config.get(table) is Dictionary or config[table].is_empty() or config[table].size() > 256:
			return "%s.csv row 1 column id: missing or oversized content table" % table
	for species_id: Variant in config.species:
		var species: Variant = config.species[species_id]
		if not species_id is String or not _valid_id(species_id) or not species is Dictionary or not species.get("basic_move") is String or not species.get("special") is String or not species.get("stage") is String:
			return "invalid species registry"
	for id: Variant in config.moves:
		if not id is String or not _valid_id(id) or not config.moves[id] is Dictionary:
			return "moves.csv row 1 column id: invalid move identity"
		var move: Dictionary = config.moves[id]
		if move.get("id") != id or not _short_text(move.get("name")) or move.get("kind") not in ["melee", "projectile", "rush", "heal", "barrier"]:
			return "moves.csv row 1 column kind: invalid pinned move '%s'" % id
		if not move.get("species") is Array or move.species.is_empty() or move.species.size() > 256:
			return "moves.csv row 1 column species: invalid species for '%s'" % id
		var seen := {}
		for species: Variant in move.species:
			if not config.species.has(species) or seen.has(species):
				return "moves.csv row 1 column species: invalid or duplicate species for '%s'" % id
			seen[species] = true
		if not move.get("equippable") is bool or not move.get("movement_while_casting") is bool:
			return "moves.csv row 1 column equippable: boolean flags required for '%s'" % id
		var limits := {"mp_cost": [0, 9999], "power": [1, 1000], "damage_variance": [0, 100], "windup": [0, 900], "active": [1, 900], "recovery": [0, 900], "cooldown": [0, 3600], "range": [1000, 4096000], "melee_width": [0, 512000], "projectile_speed": [0, 1000000], "projectile_radius": [0, 128000], "projectile_lifetime": [0, 3600], "rush_speed_multiplier": [0, 10000], "auto_weight": [0, 100], "visual_scale": [100, 10000]}
		for key: String in limits:
			if not _integer(move.get(key), int(limits[key][0]), int(limits[key][1])):
				return "moves.csv row 1 column %s: invalid normalized value for '%s'" % [key, id]
		if not _integer(move.get("duration"), 1, 2700) or int(move.duration) != int(move.windup) + int(move.active) + int(move.recovery):
			return "moves.csv row 1 column recovery_seconds: invalid total duration for '%s'" % id
		if move.kind == "projectile" and (int(move.projectile_speed) <= 0 or int(move.projectile_radius) <= 0 or int(move.projectile_lifetime) <= 0):
			return "moves.csv row 1 column projectile_speed: projectile geometry/lifetime required for '%s'" % id
		if move.kind in ["melee", "rush"] and int(move.melee_width) <= 0:
			return "moves.csv row 1 column melee_width: positive collision width required for '%s'" % id
		if move.kind == "rush" and int(move.rush_speed_multiplier) <= 0:
			return "moves.csv row 1 column rush_speed_multiplier: positive multiplier required for '%s'" % id
		if move.get("target") not in ["enemy", "self", "ally_slime"]:
			return "moves target is invalid"
		for key: String in ["heal_percent", "trigger_percent", "barrier_amount", "effect_duration"]:
			if not _integer(move.get(key), 0, 9999):
				return "invalid support move field: " + key
		if move.kind == "heal" and (move.target != "ally_slime" or int(move.heal_percent) < 1 or int(move.heal_percent) > 1000 or int(move.trigger_percent) < 1 or int(move.trigger_percent) > 1000):
			return "heal requires an ally target and positive percentages"
		if move.kind == "barrier" and (move.target not in ["self", "ally_slime"] or int(move.barrier_amount) < 1 or int(move.effect_duration) < 1):
			return "barrier requires positive amount and duration"
		if move.kind in ["melee", "projectile", "rush"] and move.target != "enemy":
			return "damage moves require enemy targets"
		if move.get("animation") not in ["basic_attack", "special_attack"] or move.get("effect") not in ["impact", "fire", "bubble", "rush", "heal", "ward", "spark"]:
			return "moves.csv row 1 column animation: unknown presentation reference for '%s'" % id
	for id: Variant in config.items:
		if not id is String or not _valid_id(id) or not config.items[id] is Dictionary:
			return "items.csv row 1 column id: invalid item identity"
		var item: Dictionary = config.items[id]
		if not _short_text(item.get("name")) or item.get("effect") not in ["restore", "barrier", "haste"] or not _integer(item.get("amount"), 0 if item.get("effect") == "haste" else 1, 0 if item.get("effect") == "haste" else 9999) or not _integer(item.get("duration_ticks"), 0, 3600) or not _integer(item.get("movement_multiplier"), 1000, 10000):
			return "items.csv row 1 column effect: invalid item '%s'" % id
		if item.effect == "restore" and item.get("stat") not in ["hp", "mp"]:
			return "items.csv row 1 column stat: recovery requires hp or mp"
		if item.effect != "restore" and (item.get("stat") != "" or int(item.duration_ticks) < 1):
			return "items.csv row 1 column duration_seconds: tactical item requires a duration and no meter"
	for id: Variant in config.natures:
		if id not in NATURES or not config.natures[id] is Dictionary:
			return "natures.csv row 1 column id: unknown nature"
		var nature: Dictionary = config.natures[id]
		if not nature.get("opening_tackle") is bool:
			return "natures.csv row 1 column opening_tackle: expected boolean"
		for key: String in ["approach_weight", "circle_weight", "retreat_weight", "guard_weight", "attack_weight"]:
			if not _integer(nature.get(key), 0, 100):
				return "natures.csv row 1 column %s: invalid weight" % key
		if int(nature.approach_weight) + int(nature.circle_weight) + int(nature.retreat_weight) == 0:
			return "natures.csv row 1 column approach_weight: movement weights cannot all be zero"
	for key: Variant in config.tuning:
		if not TUNING_SPEC.has(key):
			return "tuning.csv row 1 column id: unknown tuning key"
		var spec: Array = TUNING_SPEC[key]
		if not _integer(config.tuning[key], _quantize(float(spec[1]), String(spec[0])), _quantize(float(spec[2]), String(spec[0]))):
			return "tuning.csv row 1 column value: invalid normalized '%s'" % key
	var errors: Array[String] = []
	_validate_required_rows(config, errors)
	if not errors.is_empty():
		return errors[0]
	if config.get("sha256") != snapshot_hash(config):
		return "combat configuration hash does not match its pinned content"
	return ""


static func _normalize_move(row: Dictionary, errors: Array[String]) -> Dictionary:
	var kind := String(row.kind)
	if kind not in ["melee", "projectile", "rush", "heal", "barrier"]:
		_problem(errors, row, "kind", "must be melee, projectile, or rush")
	var species: Array = []
	for value: String in String(row.species).split("|"):
		var id := value.strip_edges()
		if not _valid_id(id) or id in species:
			_problem(errors, row, "species", "unknown or duplicate species '%s'" % id)
		else:
			species.append(id)
	var move := {"id": row.id, "name": row.name, "kind": kind, "species": species,
		"equippable": _boolean(row, "equippable", errors),
		"mp_cost": int(_number(row, "mp_cost", 0, 9999, errors, true)),
		"power": roundi(_number(row, "power_multiplier", 0.01, 10, errors) * 100),
		"damage_variance": roundi(_number(row, "damage_variance", 0, 1, errors) * 100),
		"windup": roundi(_number(row, "cast_seconds", 0, 30, errors) * 30),
		"active": roundi(_number(row, "active_seconds", 0.033333, 30, errors) * 30),
		"recovery": roundi(_number(row, "recovery_seconds", 0, 30, errors) * 30),
		"cooldown": roundi(_number(row, "cooldown_seconds", 0, 120, errors) * 30),
		"range": roundi(_number(row, "range", 1, 4096, errors) * SCALE),
		"melee_width": roundi(_number(row, "melee_width", 0.001 if kind in ["melee", "rush"] else 0, 512, errors) * SCALE),
		"projectile_speed": roundi(_number(row, "projectile_speed", 0.03 if kind == "projectile" else 0, 30000, errors) * SCALE / 30),
		"projectile_radius": roundi(_number(row, "projectile_radius", 0.001 if kind == "projectile" else 0, 128, errors) * SCALE),
		"projectile_lifetime": roundi(_number(row, "projectile_lifetime_seconds", 0.033333 if kind == "projectile" else 0, 120, errors) * 30),
		"movement_while_casting": _boolean(row, "movement_while_casting", errors),
		"rush_speed_multiplier": roundi(_number(row, "rush_speed_multiplier", 0.001 if kind == "rush" else 0, 10, errors) * 1000),
		"auto_weight": int(_number(row, "auto_weight", 0, 100, errors, true)),
		"animation": row.animation, "effect": row.effect,
		"visual_scale": roundi(_number(row, "visual_scale", 0.1, 10, errors) * 1000)}
	move["target"] = row.target
	move["heal_percent"] = roundi(_number(row, "heal_percent", 0, 1, errors) * 1000)
	move["trigger_percent"] = roundi(_number(row, "trigger_percent", 0, 1, errors) * 1000)
	move["barrier_amount"] = int(_number(row, "barrier_amount", 0, 9999, errors, true))
	move["effect_duration"] = roundi(_number(row, "effect_seconds", 0, 120, errors) * 30)
	move["duration"] = int(move.windup) + int(move.active) + int(move.recovery)
	if not _short_text(row.name):
		_problem(errors, row, "name", "must contain 1–96 characters")
	if row.animation not in ["basic_attack", "special_attack"]:
		_problem(errors, row, "animation", "unknown animation reference")
	if row.effect not in ["impact", "fire", "bubble", "rush", "heal", "ward", "spark"]:
		_problem(errors, row, "effect", "unknown procedural effect reference")
	if row.id in FALLBACKS.values() or row.id == "opening_tackle":
		if int(move.mp_cost) != 0:
			_problem(errors, row, "mp_cost", "permanent basic attacks and the opening tackle must stay free")
		if bool(move.equippable):
			_problem(errors, row, "equippable", "innate attacks cannot occupy an equipped slot")
		var required_kind := "rush" if row.id == "opening_tackle" else "melee"
		if kind != required_kind:
			_problem(errors, row, "kind", "this permanent attack must remain %s" % required_kind)
	if row.id in ["pepper_breath", "quick_bite", "heavy_claw"] and not bool(move.equippable):
		_problem(errors, row, "equippable", "saved starter abilities must remain equippable")
	return move


static func _normalize_item(row: Dictionary, errors: Array[String]) -> Dictionary:
	if row.effect not in ["restore", "barrier", "haste"]:
		_problem(errors, row, "effect", "must be restore, barrier, or haste")
	if not _short_text(row.name):
		_problem(errors, row, "name", "must contain 1–96 characters")
	if (row.effect == "restore" and row.stat not in ["hp", "mp"]) or (row.effect != "restore" and row.stat != ""):
		_problem(errors, row, "stat", "restore requires hp/mp; tactical effects require an empty stat")
	return {"name": row.name, "effect": row.effect, "stat": row.stat,
		"amount": int(_number(row, "amount", 0 if row.effect == "haste" else 1, 0 if row.effect == "haste" else 9999, errors, true)),
		"duration_ticks": roundi(_number(row, "duration_seconds", 0 if row.effect == "restore" else 0.033333, 120, errors) * 30),
		"movement_multiplier": roundi(_number(row, "movement_multiplier", 1, 10, errors) * 1000)}


static func _validate_required_rows(config: Dictionary, errors: Array[String]) -> void:
	for species: String in config.species:
		var basic_id := String(config.species[species].basic_move)
		var special_id := String(config.species[species].special)
		for id: String in [basic_id, special_id, "opening_tackle"]:
			if not config.moves.has(id) or species not in config.moves[id].get("species", []):
				errors.append("moves.csv row 1 column id: required move '%s' missing for %s" % [id, species])
		if config.moves.has(basic_id):
			var basic: Dictionary = config.moves[basic_id]
			if basic.get("kind") != "melee" or basic.get("mp_cost") != 0 or basic.get("equippable") != false:
				errors.append("moves.csv row 1 column mp_cost: '%s' must remain a free, non-equippable melee fallback" % basic_id)
	for id: String in ["pepper_breath", "quick_bite", "heavy_claw"]:
		if not config.moves.has(id) or not bool(config.moves[id].get("equippable", false)) or "agumon" not in config.moves[id].get("species", []):
			errors.append("moves.csv row 1 column equippable: saved starter move '%s' must remain equippable for agumon" % id)
	if config.moves.has("opening_tackle") and (config.moves.opening_tackle.get("kind") != "rush" or config.moves.opening_tackle.get("equippable") != false or config.moves.opening_tackle.get("mp_cost") != 0):
		errors.append("moves.csv row 1 column kind: opening_tackle must remain a free innate rush")
	for id: String in ["small_recovery", "mp_recovery", "barrier", "haste"]:
		if not config.items.has(id):
			errors.append("items.csv row 1 column id: saved item '%s' is required" % id)
	for id: String in NATURES:
		if not config.natures.has(id):
			errors.append("natures.csv row 1 column id: saved nature '%s' is required" % id)
	for key: String in TUNING_SPEC:
		if not config.tuning.has(key):
			errors.append("tuning.csv row 1 column id: required tuning '%s' is missing" % key)
	for pair: Array in [["decision_min", "decision_max"], ["tactical_commit_min", "tactical_commit_max"], ["reaction_min", "reaction_base"], ["perfect_guard_ticks", "guard_duration"]]:
		if config.tuning.has_all(pair) and int(config.tuning[pair[0]]) > int(config.tuning[pair[1]]):
			errors.append("tuning.csv row 1 column value: %s must not exceed %s" % [pair[0], pair[1]])


static func _read_table(path: String, columns: Array, errors: Array[String]) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	if path.get_base_dir() == DIRECTORY:
		var source: Array = GameBalance.table(path.get_file().get_basename())
		for index: int in source.size():
			var row: Dictionary = {"_file": path.get_file(), "_row": index + 2}
			for column: String in columns:
				row[column] = str(source[index].get(column, ""))
			rows.append(row)
		if rows.is_empty(): errors.append("Missing balance table: " + path)
		return rows
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		errors.append("%s row 1 column file: cannot open table (%s)" % [path.get_file(), error_string(FileAccess.get_open_error())])
		return rows
	if file.get_length() > 262144:
		errors.append("%s row 1 column file: table exceeds 256 KiB" % path.get_file())
		return rows
	var header: PackedStringArray = file.get_csv_line()
	if not header.is_empty():
		header[0] = header[0].trim_prefix("\ufeff")
	var seen := {}
	var valid_header := true
	for key: String in header:
		if key not in columns or seen.has(key):
			errors.append("%s row 1 column %s: unknown or duplicate column" % [path.get_file(), key])
			valid_header = false
		seen[key] = true
	for key: String in columns:
		if key not in header:
			errors.append("%s row 1 column %s: required column is missing" % [path.get_file(), key])
			valid_header = false
	if not valid_header or header.size() != columns.size() or seen.size() != columns.size():
		return rows
	var ids := {}
	var line := 1
	while not file.eof_reached():
		line += 1
		var fields := file.get_csv_line()
		if fields.size() == 1 and fields[0].strip_edges().is_empty():
			continue
		var row := {"_file": path.get_file(), "_row": line}
		if fields.size() != header.size():
			errors.append("%s row %d column row: expected %d cells, got %d" % [path.get_file(), line, header.size(), fields.size()])
			continue
		for index: int in range(header.size()):
			row[header[index]] = fields[index].strip_edges()
		if not _valid_id(row.id, path.get_file() == "natures.csv") or ids.has(row.id):
			_problem(errors, row, "id", "invalid or duplicate stable ID")
			continue
		ids[row.id] = true
		rows.append(row)
		if rows.size() > 256:
			_problem(errors, row, "id", "table may contain at most 256 rows")
			break
	return rows


static func _number(row: Dictionary, column: String, minimum: float, maximum: float, errors: Array[String], integer_only: bool = false) -> float:
	var text := String(row[column])
	if not text.is_valid_float():
		_problem(errors, row, column, "expected a number")
		return minimum
	var value := text.to_float()
	if not is_finite(value) or value < minimum or value > maximum or (integer_only and value != floor(value)):
		_problem(errors, row, column, "must be %sfrom %s to %s" % ["an integer " if integer_only else "", minimum, maximum])
		return minimum
	return value


static func _boolean(row: Dictionary, column: String, errors: Array[String]) -> bool:
	var value := String(row[column]).to_lower()
	if value not in ["true", "false"]:
		_problem(errors, row, column, "must be true or false")
	return value == "true"


static func _problem(errors: Array[String], row: Dictionary, column: String, message: String) -> void:
	errors.append("%s row %d column %s: %s" % [row._file, row._row, column, message])


static func _valid_id(value: String, allow_uppercase: bool = false) -> bool:
	if value.is_empty() or value.length() > 96:
		return false
	var alphabet := "abcdefghijklmnopqrstuvwxyz0123456789_" + ("ABCDEFGHIJKLMNOPQRSTUVWXYZ" if allow_uppercase else "")
	for character: String in value:
		if character not in alphabet:
			return false
	return true


static func _short_text(value: Variant) -> bool:
	return value is String and not value.strip_edges().is_empty() and value.length() <= 96


static func _integer(value: Variant, minimum: int, maximum: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floor(float(value)) and value >= minimum and value <= maximum


static func _quantize(value: float, unit: String) -> int:
	match unit:
		"seconds": return roundi(value * TICKS_PER_SECOND)
		"units_per_second": return roundi(value * SCALE / TICKS_PER_SECOND)
		"multiplier": return roundi(value * 1000)
		_: return roundi(value)


static func _species_registry() -> Dictionary:
	var registry := {
		"botamon": {"basic_move": "tackle", "special": "acid_bubbles", "stage": "Baby"},
		"koromon": {"basic_move": "headbutt", "special": "bubble_blow", "stage": "In-Training"},
		"agumon": {"basic_move": "claw", "special": "pepper_breath", "stage": "Rookie"}}
	for row: Dictionary in GameBalance.table("creatures"):
		registry[row.id] = {"basic_move": row.basic_move, "special": String(row.moves).split("|")[0], "stage": "Rookie"}
	return registry
