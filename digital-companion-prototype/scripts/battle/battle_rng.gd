class_name BattleRng
extends RefCounted

## Project-owned integer-only pseudo-random generator for replayable battles.
##
## The constants are fixed as part of BattleSimulator.SIMULATION_VERSION. Battle
## outcomes therefore do not depend on Godot's RandomNumberGenerator implementation.

const MASK_31 := 0x7fffffff
const MULTIPLIER := 1103515245
const INCREMENT := 12345
const ZERO_SEED_FALLBACK := 0x13579bdf

var _state: int


func _init(seed_value: int) -> void:
	_state = seed_value & MASK_31
	if _state == 0:
		_state = ZERO_SEED_FALLBACK


func next_int(max_exclusive: int) -> int:
	if max_exclusive <= 0:
		return 0
	_state = (_state * MULTIPLIER + INCREMENT) & MASK_31
	return _state % max_exclusive


func range_inclusive(minimum: int, maximum: int) -> int:
	if maximum <= minimum:
		return minimum
	return minimum + next_int(maximum - minimum + 1)


func state_value() -> int:
	return _state
