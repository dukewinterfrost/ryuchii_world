class_name SaveRepository
extends RefCounted

## Versioned JSON persistence with an independent last-known-good backup.

var primary_path: String
var backup_path: String
var temp_path: String
var replacement_path: String


func _init(base_path: String = "user://companion-save.json") -> void:
	primary_path = base_path
	backup_path = base_path + ".bak"
	temp_path = base_path + ".tmp"
	replacement_path = base_path + ".replace"


func save_state(state: Dictionary) -> bool:
	# An older build must never overwrite data written by a newer schema, even if
	# that data is in a crash-recovery sidecar rather than the primary path.
	for path: String in [primary_path, temp_path, replacement_path, backup_path]:
		if _inspect_path(path)["status"] == "future":
			return false

	var save_time := maxf(
		Time.get_unix_time_from_system(),
		float(state.get("meta", {}).get("last_saved_time", 0.0))
	)
	var envelope := {
		"schemaVersion": CareRules.SAVE_SCHEMA_VERSION,
		"savedAt": save_time,
		"companion": state,
	}
	var encoded := JSON.stringify(envelope, "  ")
	# No stale staged generation may survive into this save attempt.
	_remove_if_present(temp_path)
	if not _write_text(temp_path, encoded):
		_remove_if_present(temp_path)
		return false
	if _inspect_path(temp_path)["status"] != "current":
		_remove_if_present(temp_path)
		return false

	var primary_existed := FileAccess.file_exists(primary_path)
	var current_text := ""
	if FileAccess.file_exists(primary_path):
		current_text = FileAccess.get_file_as_string(primary_path)
		if _inspect_encoded(current_text)["status"] in ["current", "legacy"]:
			if not _write_text(backup_path, current_text):
				_remove_if_present(temp_path)
				return false

	# Move the old primary out of the way without deleting it. If promotion of the
	# validated temp file fails, put the exact old bytes back.
	_remove_if_present(replacement_path)
	if primary_existed and not _rename(primary_path, replacement_path):
		_remove_if_present(temp_path)
		return false
	if not _rename(temp_path, primary_path):
		if primary_existed:
			if not _rename(replacement_path, primary_path) and not current_text.is_empty():
				_write_text(primary_path, current_text)
		# The candidate was never committed. Discard it before returning so a later
		# load cannot promote the failed generation and resurrect its rewards.
		_remove_if_present(temp_path)
		return false
	_remove_if_present(replacement_path)
	return true


func load_state() -> Dictionary:
	var inspected := {
		"primary": _inspect_path(primary_path),
		"temp": _inspect_path(temp_path),
		"replacement": _inspect_path(replacement_path),
		"backup": _inspect_path(backup_path),
	}
	# Any valid-looking future envelope wins over current-schema recovery. This is
	# deliberately conservative: opening a save with an older app must be lossless.
	for label: String in ["primary", "temp", "replacement", "backup"]:
		var candidate: Dictionary = inspected[label]
		if candidate["status"] == "future":
			return {
				"ok": false,
				"recovered": false,
				"incompatible": true,
				"schema_version": candidate["schema_version"],
				"state": {},
			}

	var primary: Dictionary = inspected["primary"]
	if primary["status"] == "current":
		_remove_if_present(temp_path)
		_remove_if_present(replacement_path)
		return {
			"ok": true,
			"recovered": false,
			"incompatible": false,
			"repair_failed": false,
			"state": primary["envelope"]["companion"],
		}
	if primary["status"] == "legacy":
		# Keep the original legacy bytes as a rollback generation before promoting
		# the migrated current-schema envelope.
		var backup_written := _write_text(backup_path, primary["source_encoded"])
		var repaired := backup_written and _restore_primary(primary["encoded"])
		return {
			"ok": true,
			"recovered": true,
			"migrated": true,
			"incompatible": false,
			"repair_failed": not repaired,
			"state": primary["envelope"]["companion"],
		}

	# A validated temp file is the newest complete generation. A replacement file
	# is the prior primary left behind if the process stopped during promotion.
	for label: String in ["temp", "replacement", "backup"]:
		var candidate: Dictionary = inspected[label]
		if candidate["status"] not in ["current", "legacy"]:
			continue
		var backup_written := true
		if candidate["status"] == "legacy" and label != "backup":
			backup_written = _write_text(backup_path, candidate["source_encoded"])
		var repaired := backup_written and _restore_primary(candidate["encoded"])
		return {
			"ok": true,
			"recovered": true,
			"migrated": candidate["status"] == "legacy",
			"incompatible": false,
			"repair_failed": not repaired,
			"state": candidate["envelope"]["companion"],
		}
	return {
		"ok": false,
		"recovered": false,
		"incompatible": false,
		"repair_failed": false,
		"state": {},
	}


func clear() -> void:
	_remove_if_present(primary_path)
	_remove_if_present(backup_path)
	_remove_if_present(temp_path)
	_remove_if_present(replacement_path)


func _read_envelope(path: String) -> Dictionary:
	var inspected := _inspect_path(path)
	return inspected["envelope"] if inspected["status"] in ["current", "legacy"] else {}


func _decode_envelope(encoded: String) -> Dictionary:
	var inspected := _inspect_encoded(encoded)
	return inspected["envelope"] if inspected["status"] in ["current", "legacy"] else {}


func _inspect_path(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"status": "missing", "schema_version": -1, "envelope": {}, "encoded": "", "source_encoded": ""}
	var encoded := FileAccess.get_file_as_string(path)
	var inspected := _inspect_encoded(encoded)
	inspected["source_encoded"] = encoded
	return inspected


func _inspect_encoded(encoded: String) -> Dictionary:
	var parser := JSON.new()
	if parser.parse(encoded) != OK:
		return {"status": "invalid", "schema_version": -1, "envelope": {}, "encoded": encoded}
	var parsed: Variant = parser.data
	if not parsed is Dictionary:
		return {"status": "invalid", "schema_version": -1, "envelope": {}, "encoded": encoded}
	var envelope: Dictionary = parsed
	var raw_version: Variant = envelope.get("schemaVersion", null)
	if not _is_integer_number(raw_version):
		return {"status": "invalid", "schema_version": -1, "envelope": {}, "encoded": encoded}
	var schema_version := int(raw_version)
	if schema_version > CareRules.SAVE_SCHEMA_VERSION:
		return {"status": "future", "schema_version": schema_version, "envelope": envelope, "encoded": encoded}
	if schema_version != CareRules.SAVE_SCHEMA_VERSION and schema_version not in [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]:
		return {"status": "invalid", "schema_version": schema_version, "envelope": {}, "encoded": encoded}
	var saved_at: Variant = envelope.get("savedAt", null)
	if not _is_nonnegative_number(saved_at):
		return {"status": "invalid", "schema_version": schema_version, "envelope": {}, "encoded": encoded}
	if not envelope.get("companion", null) is Dictionary:
		return {"status": "invalid", "schema_version": schema_version, "envelope": {}, "encoded": encoded}
	if schema_version in [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]:
		var migrated_state: Dictionary
		match schema_version:
			1: migrated_state = CareRules.migrate_state_v1(envelope["companion"])
			2: migrated_state = CareRules.migrate_state_v2(envelope["companion"])
			3: migrated_state = CareRules.migrate_state_v3(envelope["companion"])
			4: migrated_state = CareRules.migrate_state_v4(envelope["companion"])
			5: migrated_state = CareRules.migrate_state_v5(envelope["companion"])
			6: migrated_state = CareRules.migrate_state_v6(envelope["companion"])
			7: migrated_state = CareRules.migrate_state_v7(envelope["companion"])
			8: migrated_state = CareRules.migrate_state_v8(envelope["companion"])
			9: migrated_state = CareRules.migrate_state_v9(envelope["companion"])
			10: migrated_state = CareRules.migrate_state_v10(envelope["companion"])
		if migrated_state.is_empty():
			return {"status": "invalid", "schema_version": schema_version, "envelope": {}, "encoded": encoded}
		var migrated_envelope := envelope.duplicate(true)
		migrated_envelope["schemaVersion"] = CareRules.SAVE_SCHEMA_VERSION
		migrated_envelope["companion"] = migrated_state
		return {
			"status": "legacy",
			"schema_version": schema_version,
			"envelope": migrated_envelope,
			"encoded": JSON.stringify(migrated_envelope, "  "),
		}
	if not CareRules.state_is_valid(envelope["companion"]):
		return {"status": "invalid", "schema_version": schema_version, "envelope": {}, "encoded": encoded}
	return {"status": "current", "schema_version": schema_version, "envelope": envelope, "encoded": encoded}


func _restore_primary(encoded: String) -> bool:
	# Always stage and validate recovery bytes as well; backup recovery should have
	# the same crash behavior as an ordinary save.
	_remove_if_present(temp_path)
	if not _write_text(temp_path, encoded):
		_remove_if_present(temp_path)
		return false
	if _inspect_path(temp_path)["status"] != "current":
		_remove_if_present(temp_path)
		return false
	_remove_if_present(replacement_path)
	var primary_existed := FileAccess.file_exists(primary_path)
	if primary_existed and not _rename(primary_path, replacement_path):
		_remove_if_present(temp_path)
		return false
	if not _rename(temp_path, primary_path):
		if primary_existed:
			_rename(replacement_path, primary_path)
		_remove_if_present(temp_path)
		return false
	_remove_if_present(replacement_path)
	return true


func _is_integer_number(value: Variant) -> bool:
	return (value is int or value is float) \
		and not is_nan(float(value)) \
		and not is_inf(float(value)) \
		and float(value) >= 0.0 \
		and floor(float(value)) == float(value)


func _is_nonnegative_number(value: Variant) -> bool:
	return (value is int or value is float) \
		and not is_nan(float(value)) \
		and not is_inf(float(value)) \
		and float(value) >= 0.0 \
		and float(value) <= CareRules.MAX_TIMESTAMP


func _write_text(path: String, content: String) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(content)
	file.flush()
	var write_error := file.get_error()
	file.close()
	return write_error == OK


func _remove_if_present(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _rename(from_path: String, to_path: String) -> bool:
	return DirAccess.rename_absolute(
		ProjectSettings.globalize_path(from_path),
		ProjectSettings.globalize_path(to_path)
	) == OK
