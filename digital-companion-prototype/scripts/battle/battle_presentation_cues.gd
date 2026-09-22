class_name BattlePresentationCues
extends RefCounted

## Read-only rendering geometry shared by the 2D and 3D adapters. All values
## come from the session snapshot; visual scale never enlarges collision cues.
static func ground(value: Variant) -> Vector2:
	return Vector2(float(value[0]), float(value[1])) / 1000.0 if value is Array and value.size() == 2 else Vector2.ZERO

static func charge_fraction(actor: Dictionary) -> float:
	return clampf(float(actor.get("action_tick", 0)) / maxf(1, float(actor.get("windup", 1))), 0, 1)

static func palette(effect: String) -> Color:
	return {"fire": Color("ffb46b"), "hit_fire": Color("ffb46b"), "bubble": Color("8edeee"), "rush": Color("ff867b"), "impact": Color("ffdc88"), "perfect_guard": Color("c4f7ff")}.get(effect, Color("ffdc88"))

static func attack(actor: Dictionary, arena: Dictionary, session: Dictionary = {}) -> Dictionary:
	var action := String(actor.get("action", ""))
	if action not in ["basic_attack", "special_attack", "rush_attack"]:
		return {}
	var tick := int(actor.get("action_tick", 0))
	var phase := String(actor.get("phase", "charge" if tick < int(actor.get("windup", 0)) else "active"))
	if phase not in ["charge", "active"]:
		return {}
	var move: Dictionary = actor.get("current_move", {})
	var start := ground(actor.pos)
	var aim := ground(actor.get("aim", actor.pos))
	var direction := ground(actor.get("direction", [0, 0])).normalized()
	if direction.is_zero_approx():
		direction = start.direction_to(aim)
	if direction.is_zero_approx():
		direction = Vector2.RIGHT
	var move_type := String(move.get("kind", "projectile" if action == "special_attack" else "melee"))
	var reach := float(move.get("range", 260000 if move_type == "projectile" else 48000)) / 1000.0
	var half_width := float(move.get("projectile_radius", 4000)) / 1000.0 if move_type == "projectile" else float(move.get("melee_width", 12000)) / 2000.0
	if move_type == "rush" and not session.is_empty():
		reach = float(BattleSimulator.rush_travel_remaining(session, String(actor.get("fighter_id", "")))) / 1000.0
	var wall_margin := float(actor.get("radius", 14000)) / 1000.0 if move_type == "rush" else half_width
	var finish := clip_end(start, start + direction * reach, wall_margin, arena, "movement" if move_type == "rush" else "projectile")
	var side := Vector2(-direction.y, direction.x) * half_width
	return {"start": start, "finish": finish, "points": PackedVector2Array([start + side, finish + side, finish - side, start - side]), "color": palette(String(move.get("effect", "rush" if move_type == "rush" else "impact"))), "phase": phase, "progress": charge_fraction(actor), "move_type": move_type, "half_width": half_width}

static func clip_end(start: Vector2, finish: Vector2, margin: float, arena: Dictionary, obstacle_kind: String) -> Vector2:
	var delta := finish - start
	var fraction := 1.0
	var size := Vector2(float(arena.get("ground", {}).get("width", 640)), float(arena.get("ground", {}).get("height", 480)))
	for axis: int in 2:
		if finish[axis] < margin and delta[axis] < 0:
			fraction = minf(fraction, (margin - start[axis]) / delta[axis])
		elif finish[axis] > size[axis] - margin and delta[axis] > 0:
			fraction = minf(fraction, (size[axis] - margin - start[axis]) / delta[axis])
	var hit := BattleArena.obstruction_fraction(arena, [roundi(start.x * 1000), roundi(start.y * 1000)], [roundi(finish.x * 1000), roundi(finish.y * 1000)], roundi(margin * 1000), obstacle_kind)
	if hit >= 0:
		fraction = minf(fraction, float(hit) / BattleArena.FRACTION)
	return start + delta * clampf(fraction, 0, 1)

static func animation(actor: Dictionary) -> String:
	var action := String(actor.get("action", "idle"))
	if action in ["basic_attack", "special_attack", "rush_attack"]:
		var authored := String(actor.get("current_move", {}).get("animation", ""))
		if action == "rush_attack":
			# Intentional approved-body fallback: brace, then run. No invented art.
			return "guard" if String(actor.get("phase", "")) == "charge" else ("walk" if String(actor.get("phase", "")) == "active" else "idle")
		if not authored.is_empty():
			return authored
	return action
