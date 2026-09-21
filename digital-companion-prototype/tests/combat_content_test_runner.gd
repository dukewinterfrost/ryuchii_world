extends SceneTree

const Content = preload("res://scripts/battle/combat_content.gd")
const Definitions = preload("res://scripts/core/game_definitions.gd")
const V2 = preload("res://scripts/battle/battle_simulator_v2.gd")
const V3 = preload("res://scripts/battle/battle_simulator_v3.gd")
const FIXTURES := "res://tests/fixtures/combat/"
var _checks := 0
var _failures := 0
var _directory := ""


func _initialize() -> void:
	_directory = "/tmp/ryuchii-combat-content-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	DirAccess.make_dir_recursive_absolute(_directory)
	_test_content()
	_test_roundtrip_and_isolation()
	_test_invalid_tables()
	_test_transactional_reload()
	_test_legacy_replays()
	_clean_temp()
	print("%s: %d combat content and frozen replay checks (%d failures)" % ["PASS" if _failures == 0 else "FAIL", _checks, _failures])
	quit(0 if _failures == 0 else 1)


func _test_content() -> void:
	var loaded := Content.load_tables()
	_check(loaded.ok, "canonical tables load: " + String(loaded.error))
	if not loaded.ok:
		return
	var config: Dictionary = loaded.config
	_check(Content.validate_snapshot(config).is_empty(), "normalized snapshot validates")
	_check(config.moves.size() == 9 and config.items.size() == 4 and config.natures.size() == 6, "complete move/item/nature catalog")
	_check(config.moves.acid_bubbles.power == 130 and config.moves.bubble_blow.power == 140, "baby specials use the canonical table")
	_check(config.moves.heavy_claw.windup == 30 and config.moves.heavy_claw.active == 3 and config.moves.heavy_claw.recovery == 21, "seconds quantized independently to 30Hz integer phases")
	_check(config.moves.opening_tackle.windup == 24 and config.moves.opening_tackle.recovery == 27 and config.moves.opening_tackle.rush_speed_multiplier == 2500, "opening tackle defaults")
	_check(config.moves.pepper_breath.projectile_speed == 7000 and config.moves.pepper_breath.projectile_radius == 4000, "projectile units/sec and radius converted to fixed-point")
	_check(config.moves.claw.melee_width == 12000, "melee width stores full width, separate from body radius")
	_check(config.moves.heavy_claw.visual_scale == 1250 and config.moves.heavy_claw.melee_width == 18000, "visual scale and collision size are independent")
	_check(config.items.barrier.amount == 30 and config.items.barrier.duration_ticks == 180, "barrier absorption and duration")
	_check(config.items.haste.amount == 0 and config.items.haste.movement_multiplier == 1350 and config.items.haste.duration_ticks == 180, "haste multiplier is its sole speed authority")
	_check(config.tuning.speed_base == 2000 and config.tuning.speed_bonus == 6000 and config.tuning.speed_half_stat == 50, "speed curve normalized once")
	_check(config.tuning.defense_cooldown == 60 and config.tuning.perfect_guard_ticks == 6 and config.tuning.item_cooldown == 150, "defense/item timing defaults")
	for species: String in Content.SPECIES:
		var moves := Content.moves_for_species(species, config)
		_check(moves.has_all([Content.FALLBACKS[species], Content.SPECIALS[species], "opening_tackle"]), "%s has permanent attack, special and innate tackle" % species)
	for nature: String in ["Bold", "Earnest", "Stubborn"]:
		_check(config.natures[nature].opening_tackle, "%s retains identity and maps to aggressive opening" % nature)
	_check(Definitions.MOVES.heavy_claw.mp == config.moves.heavy_claw.mp_cost, "care/loadout metadata shares canonical move cost")
	_check(Definitions.ITEMS.barrier.restore == config.items.barrier.amount, "item metadata shares canonical item effect")
	_check(Definitions.default_inventory().items.barrier == 2 and Definitions.default_inventory().items.haste == 2, "new saves receive two tactical items")
	_check(_integer_tree(config), "normalized content contains no floating simulation values")


func _test_roundtrip_and_isolation() -> void:
	var config := Content.defaults()
	var parsed: Dictionary = JSON.parse_string(JSON.stringify(config))
	_check(Content.snapshot_hash(config) == Content.snapshot_hash(parsed), "content hash survives JSON integral floats")
	_check(Content.validate_snapshot(parsed).is_empty(), "untrusted JSON snapshot validates independently of live tables")
	var normalized := Content.normalize_snapshot(parsed)
	_check(_integer_tree(normalized), "replay normalization restores integer types")
	var copy := Content.defaults()
	copy.moves.claw.power = 999
	copy.moves.claw.species.append("alien")
	_check(Content.defaults().moves.claw.power == 100 and Content.defaults().moves.claw.species.size() == 1, "callers cannot mutate cached content")
	copy = Content.moves_for_species("agumon")
	copy.heavy_claw.mp_cost = 0
	_check(Content.defaults().moves.heavy_claw.mp_cost == 8, "species catalog is independently copied")
	copy = config.duplicate(true)
	copy.moves.claw.power = 120
	_check(not Content.validate_snapshot(copy).is_empty(), "edited pinned content must match its hash")
	copy = config.duplicate(true)
	copy.tuning.speed_half_stat = 0
	copy.sha256 = Content.snapshot_hash(copy)
	_check(not Content.validate_snapshot(copy).is_empty(), "valid hash cannot permit zero speed-curve divisor")
	copy = config.duplicate(true)
	copy.moves.pepper_breath.projectile_speed = 0
	copy.sha256 = Content.snapshot_hash(copy)
	_check(not Content.validate_snapshot(copy).is_empty(), "pinned projectiles require nonzero speed")


func _test_invalid_tables() -> void:
	_invalid_cell("moves", 1, "mp_cost", "-1", "moves.csv row 2 column mp_cost")
	_invalid_cell("moves", 1, "mp_cost", "2", "moves.csv row 2 column mp_cost")
	_invalid_cell("moves", 9, "mp_cost", "2", "moves.csv row 10 column mp_cost")
	_invalid_cell("moves", 1, "id", "bad/id", "moves.csv row 2 column id")
	_invalid_cell("moves", 2, "id", "tackle", "moves.csv row 3 column id")
	_invalid_cell("moves", 1, "species", "unknown", "moves.csv row 2 column species")
	_invalid_cell("moves", 1, "power_multiplier", "NaN", "moves.csv row 2 column power_multiplier")
	_invalid_cell("moves", 1, "movement_while_casting", "maybe", "moves.csv row 2 column movement_while_casting")
	_invalid_cell("moves", 4, "projectile_speed", "0", "moves.csv row 5 column projectile_speed")
	_invalid_cell("moves", 4, "projectile_radius", "0", "moves.csv row 5 column projectile_radius")
	_invalid_cell("moves", 1, "animation", "missing_animation", "moves.csv row 2 column animation")
	_invalid_cell("items", 4, "amount", "35", "items.csv row 5 column amount")
	_invalid_cell("items", 3, "duration_seconds", "0", "items.csv row 4 column duration_seconds")
	_invalid_cell("items", 1, "stat", "speed", "items.csv row 2 column stat")
	_invalid_cell("natures", 1, "attack_weight", "101", "natures.csv row 2 column attack_weight")
	_invalid_cell("tuning", 1, "unit", "seconds", "tuning.csv row 2 column unit")
	_invalid_cell("tuning", 3, "value", "0", "tuning.csv row 4 column value")
	for renamed: String in ["identity", "unknown_column"]:
		_copy_tables()
		var path := _directory.path_join("moves.csv")
		var text := FileAccess.get_file_as_string(path)
		_write(path, renamed + text.substr(2)) # Same-width header; missing `id`.
		var result := Content.load_tables(_directory)
		_check(not result.ok and "row 1 column id" in result.error and renamed in result.error, "same-width renamed ID header fails safely")
	_copy_tables()
	var path := _directory.path_join("moves.csv")
	_write(path, FileAccess.get_file_as_string(path).replace("id,name,", "id,id,"))
	var result := Content.load_tables(_directory)
	_check(not result.ok and "row 1 column id" in result.error, "duplicate header fails safely")
	_copy_tables()
	DirAccess.remove_absolute(_directory.path_join("tuning.csv"))
	result = Content.load_tables(_directory)
	_check(not result.ok and "tuning.csv row 1 column file" in result.error, "missing table reports filename and location")


func _test_transactional_reload() -> void:
	_check(Content.reload_tables().ok, "restore canonical cache before transactional test")
	var original := Content.defaults()
	_copy_tables()
	_change_cell("moves", 1, "power_multiplier", "1.2")
	var reloaded := Content.reload_tables(_directory)
	_check(reloaded.ok and Content.defaults().moves.tackle.power == 120, "valid reload replaces complete cached content")
	_check(original.moves.tackle.power == 100 and original.sha256 != Content.defaults().sha256, "existing config stays pinned after reload")
	var good := Content.defaults()
	_change_cell("moves", 1, "power_multiplier", "broken")
	reloaded = Content.reload_tables(_directory)
	_check(not reloaded.ok and Content.defaults() == good and reloaded.previous_config == good, "invalid reload retains last valid content")
	_check(not Content.last_errors().is_empty(), "failed reload exposes actionable errors")
	_check(Content.reload_tables().ok and Content.last_errors().is_empty(), "subsequent correction clears errors and restores cache")


func _test_legacy_replays() -> void:
	var before: Array[String] = []
	for version: String in ["v2", "v3"]:
		var record: Dictionary = Content.normalize_snapshot(JSON.parse_string(FileAccess.get_file_as_string(FIXTURES + "battle-" + version + "-golden-record.json")))
		var session: Dictionary = V2.replay(record) if version == "v2" else V3.replay(record)
		var expected := FileAccess.get_file_as_string(FIXTURES + "battle-" + version + "-golden-terminal.sha256").strip_edges()
		_check(session.ok and session.complete and JSON.stringify(session).sha256_text() == expected, "frozen %s reconstructs original entire terminal state" % version)
		before.append(JSON.stringify(session))
	_copy_tables()
	_change_cell("moves", 1, "power_multiplier", "4.2")
	_change_cell("items", 1, "amount", "200")
	_check(Content.reload_tables(_directory).ok, "new live balance reloads for replay independence check")
	for index: int in range(2):
		var version: String = ["v2", "v3"][index]
		var record: Dictionary = Content.normalize_snapshot(JSON.parse_string(FileAccess.get_file_as_string(FIXTURES + "battle-" + version + "-golden-record.json")))
		var session: Dictionary = V2.replay(record) if version == "v2" else V3.replay(record)
		_check(JSON.stringify(session) == before[index], "frozen %s ignores edited move and item tables" % version)
	_check(V3.item_definitions().size() == 2 and V3.move_definitions("botamon").tackle.power == 100, "v3 defaults retain original two items and original moves")
	Content.reload_tables()


func _integer_tree(value: Variant) -> bool:
	if value is float:
		return false
	if value is Dictionary:
		for key: Variant in value:
			if not _integer_tree(value[key]):
				return false
	if value is Array:
		for entry: Variant in value:
			if not _integer_tree(entry):
				return false
	return true


func _copy_tables() -> void:
	for name: String in ["moves", "items", "natures", "tuning"]:
		_write(_directory.path_join(name + ".csv"), FileAccess.get_file_as_string(Content.DIRECTORY.path_join(name + ".csv")))


func _invalid_cell(table: String, row: int, column: String, replacement: String, expected: String) -> void:
	_copy_tables()
	_change_cell(table, row, column, replacement)
	var result := Content.load_tables(_directory)
	_check(not result.ok and expected in result.error, "invalid %s row %d %s gives exact location" % [table, row + 1, column])


func _change_cell(table: String, row: int, column: String, replacement: String) -> void:
	var path := _directory.path_join(table + ".csv")
	var lines := FileAccess.get_file_as_string(path).split("\n")
	var columns := lines[0].strip_edges().split(",")
	var values := lines[row].strip_edges().split(",")
	values[columns.find(column)] = replacement
	lines[row] = ",".join(values)
	_write(path, "\n".join(lines))


func _write(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)


func _clean_temp() -> void:
	for name: String in ["moves", "items", "natures", "tuning"]:
		DirAccess.remove_absolute(_directory.path_join(name + ".csv"))
	DirAccess.remove_absolute(_directory)


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("FAIL: " + label)
