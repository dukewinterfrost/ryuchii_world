class_name GameBalance
extends RefCounted

## One atomic generated bundle, authored in Game Balance.xlsx. Never reads saves.
const PATH := "res://assets/balance/game-balance.json"
static var _data: Dictionary = {}
static var error := ""

static func data() -> Dictionary:
	if _data.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if not parsed is Dictionary or parsed.get("schema") != "game-balance-v1" or not parsed.get("tables") is Dictionary:
			error = "Game balance is missing or invalid. Run Apply Game Balance."
			return {}
		_data = _normalize_numbers(parsed)
	return _data

static func table(id: String) -> Array:
	return data().get("tables", {}).get(id, []).duplicate(true)

static func setting(id: String) -> Variant:
	var settings: Dictionary = data().get("settings", {})
	if not settings.has(id):
		error = "Missing game balance setting: " + id
		push_error(error)
		return null
	return settings[id]

static func reload() -> void:
	_data = {}
	error = ""
	data()


static func _normalize_numbers(value: Variant) -> Variant:
	if value is Dictionary:
		for key: Variant in value: value[key] = _normalize_numbers(value[key])
	elif value is Array:
		for index: int in value.size(): value[index] = _normalize_numbers(value[index])
	elif value is float and is_finite(value) and value == floorf(value):
		return int(value)
	return value
