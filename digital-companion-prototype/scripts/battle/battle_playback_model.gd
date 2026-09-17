class_name BattlePlaybackModel
extends RefCounted

## Reconstructs completed battles from frozen inputs. Never calls GameState or saves.
const TICK_SECONDS := 1.0 / BattleSimulator.TICKS_PER_SECOND
const SPEEDS := [1, 2, 4]

var error := ""
var _source_result: Dictionary = {}
var _record: Dictionary = {}
var _session: Dictionary = {}
var _next_command_index := 0
var _accumulator := 0.0
var _speed_index := 0
var _started_emitted := false
var _emitted_count := 0


func setup(battle_result: Dictionary) -> void:
	_source_result = {}
	_record = {}
	_session = {}
	_next_command_index = 0
	_accumulator = 0.0
	_speed_index = 0
	_started_emitted = false
	_emitted_count = 0
	error = ""
	var required := ["battle_id", "simulation_version", "seed", "max_ticks", "tick", "fighters", "arena", "content_revisions", "commands", "result"]
	if not bool(battle_result.get("ok", false)) or not bool(battle_result.get("complete", false)) or not battle_result.has_all(required):
		error = "Replay requires a completed battle session."
		return
	if not battle_result.fighters is Array or not battle_result.arena is Dictionary or not battle_result.content_revisions is Dictionary or not battle_result.commands is Array:
		error = "Replay inputs are malformed."
		return
	var record := BattleSimulator.replay_record(battle_result)
	var verified := BattleSimulator.replay(record)
	if not bool(verified.get("ok", false)) or not bool(verified.get("complete", false)) or verified.get("result") != battle_result.result:
		error = "Replay inputs do not reconstruct the completed result."
		return
	_source_result = battle_result.duplicate(true)
	_record = record
	_session = BattleSimulator.create_from_record(record)


func advance(delta_seconds: float) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if is_complete():
		return events
	_emit_started(events)
	if not is_finite(delta_seconds):
		return events
	_accumulator += maxf(0.0, delta_seconds) * float(current_speed())
	# Epsilon only stabilizes the presentation accumulator at exact tick boundaries.
	# Authoritative simulation positions, decisions and attacks remain integer-only.
	while _accumulator + 0.000000001 >= TICK_SECONDS and not is_complete():
		_accumulator = maxf(0.0, _accumulator - TICK_SECONDS)
		events.append_array(_advance_tick())
	return events


func _advance_tick() -> Array[Dictionary]:
	var commands: Array = []
	while _next_command_index < _record.commands.size() and int(_record.commands[_next_command_index].tick) == int(_session.tick) + 1:
		commands.append(_record.commands[_next_command_index])
		_next_command_index += 1
	var events: Array[Dictionary] = []
	for event: Dictionary in BattleSimulator.step(_session, commands):
		events.append(event.duplicate(true))
	_emitted_count += events.size()
	return events


func _emit_started(events: Array[Dictionary]) -> void:
	if not _started_emitted:
		events.append(_session.log[0].duplicate(true))
		_started_emitted = true
		_emitted_count += 1


func skip_to_end() -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if is_complete():
		return events
	_emit_started(events)
	while not is_complete():
		events.append_array(_advance_tick())
	_accumulator = 0.0
	return events


func cycle_speed() -> int:
	_speed_index = (_speed_index + 1) % SPEEDS.size()
	return current_speed()


func current_speed() -> int:
	return SPEEDS[_speed_index]


func is_complete() -> bool:
	return _session.is_empty() or bool(_session.get("complete", false))


func consumed_event_count() -> int:
	return _emitted_count


func get_session() -> Dictionary:
	# Read-only by contract: the view reads positions without copying the event log.
	return _session


func source_result() -> Dictionary:
	return _source_result.duplicate(true)
