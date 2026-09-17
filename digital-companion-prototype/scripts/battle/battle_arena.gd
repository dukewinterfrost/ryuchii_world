class_name BattleArena
extends RefCounted

## Shared integer ground geometry. Rendering/projection never affects this data.
const SCALE := 1000
const FRACTION := 1000000
const NEIGHBORS := [[0, -1], [-1, 0], [1, 0], [0, 1]]


static func graybox() -> Dictionary:
	return {"schemaVersion": 1, "kind": "arena", "assetId": "graybox", "revision": "1",
		"projection": "square", "ground": {"width": 640, "height": 480, "cellSize": 20},
		"maxBodyRadius": 16, "spawns": {"player": [100, 240], "opponent": [540, 240]},
		"obstacles": [], "tiles": []}


static func validate(arena: Dictionary) -> String:
	if not arena.has_all(["schemaVersion", "kind", "assetId", "revision", "projection", "ground", "maxBodyRadius", "spawns", "obstacles", "tiles"]):
		return "arena fields are missing"
	if arena.schemaVersion != 1 or arena.kind != "arena":
		return "unsupported arena schema"
	for key: String in ["assetId", "revision"]:
		if not arena[key] is String or String(arena[key]).strip_edges().is_empty() or String(arena[key]).length() > 96:
			return "invalid arena identity"
	if arena.has("contentSha256") and not _sha256_pin(arena.contentSha256):
		return "arena contentSha256 is invalid"
	if arena.projection not in ["square", "isometric"]:
		return "invalid arena projection"
	if not arena.ground is Dictionary or not arena.ground.has_all(["width", "height", "cellSize"]):
		return "ground must specify width, height and cellSize"
	var ground: Dictionary = arena.ground
	if not integer_between(ground.width, 80, 4096) or not integer_between(ground.height, 80, 4096) or not integer_between(ground.cellSize, 8, 128):
		return "ground dimensions are invalid"
	if int(ground.width) % int(ground.cellSize) != 0 or int(ground.height) % int(ground.cellSize) != 0:
		return "ground dimensions must be divisible by cellSize"
	if int(ground.width) / int(ground.cellSize) * (int(ground.height) / int(ground.cellSize)) > 16384:
		return "arena navigation grid is too large"
	if not integer_between(arena.maxBodyRadius, 1, 64):
		return "maxBodyRadius is invalid"
	if not arena.obstacles is Array or arena.obstacles.size() > 512:
		return "obstacles must be a bounded array"
	var identities: Dictionary = {}
	for obstacle: Variant in arena.obstacles:
		if not obstacle is Dictionary or not obstacle.has_all(["id", "rect", "movement", "projectile", "sight", "occlusion"]):
			return "obstacle fields are missing"
		if not obstacle.id is String or obstacle.id.is_empty() or identities.has(obstacle.id):
			return "obstacle IDs must be unique nonempty strings"
		identities[obstacle.id] = true
		for flag: String in ["movement", "projectile", "sight", "occlusion"]:
			if not obstacle[flag] is bool:
				return "obstacle flags must be explicit booleans"
		if not obstacle.rect is Array or obstacle.rect.size() != 4:
			return "obstacle rect must contain four integers"
		for n: Variant in obstacle.rect:
			if not integer_between(n, 0, 4096):
				return "obstacle rect is invalid"
		var rect: Array = obstacle.rect
		if int(rect[2]) <= 0 or int(rect[3]) <= 0 or int(rect[0]) + int(rect[2]) > int(ground.width) or int(rect[1]) + int(rect[3]) > int(ground.height):
			return "obstacle rect is outside ground"
	if not arena.spawns is Dictionary or not arena.spawns.has_all(["player", "opponent"]):
		return "both spawn points are required"
	for role: String in ["player", "opponent"]:
		var spawn: Variant = arena.spawns[role]
		if not spawn is Array or spawn.size() != 2 or not integer_between(spawn[0], 0, int(ground.width)) or not integer_between(spawn[1], 0, int(ground.height)):
			return "spawn coordinates must be ground integers"
		var position := to_fixed(spawn)
		if not position_clear(arena, position, int(arena.maxBodyRadius) * SCALE):
			return "spawn lacks body clearance"
		var exits := 0
		for offset: Array in NEIGHBORS:
			var next: Array = [position[0] + offset[0] * int(ground.cellSize) * SCALE, position[1] + offset[1] * int(ground.cellSize) * SCALE]
			if segment_clear(arena, position, next, int(arena.maxBodyRadius) * SCALE, "movement"):
				exits += 1
		if exits < 3:
			return "spawn has insufficient evasion space"
	var player := to_fixed(arena.spawns.player)
	var opponent := to_fixed(arena.spawns.opponent)
	if boxes_overlap(player, opponent, int(arena.maxBodyRadius) * SCALE * 2):
		return "spawn bodies overlap"
	if path(arena, player, opponent, int(arena.maxBodyRadius) * SCALE).is_empty():
		return "spawn regions are disconnected for maximum body size"
	if not arena.tiles is Array or arena.tiles.size() > 16384:
		return "tiles must be a bounded array"
	if arena.has("tileSet"):
		if not arena.tileSet is Dictionary or not arena.tileSet.has_all(["assetId", "revision"]):
			return "tileSet reference is invalid"
		for key: String in ["assetId", "revision"]:
			if not arena.tileSet[key] is String or String(arena.tileSet[key]).is_empty():
				return "tileSet reference must pin identity and revision"
	for tile: Variant in arena.tiles:
		if not tile is Dictionary or not tile.has_all(["cell", "atlas", "alternative"]):
			return "tile fields are invalid"
		for field: String in ["cell", "atlas"]:
			if not tile[field] is Array or tile[field].size() != 2:
				return "tile coordinates are invalid"
			for n: Variant in tile[field]:
				if not integer_between(n, 0, 4096):
					return "tile coordinates must be nonnegative integers"
		if not integer_between(tile.alternative, 0, 2147483647):
			return "tile alternative is invalid"
		if int(tile.cell[0]) >= int(ground.width) / int(ground.cellSize) or int(tile.cell[1]) >= int(ground.height) / int(ground.cellSize):
			return "tile cell is outside ground"
	if arena.has("environment"):
		if not EnvironmentPresentationContract.valid_pin(arena.environment):
			return "arena environment must contain a complete immutable pin"
		var presentation: Variant = arena.get("presentation")
		if not presentation is Dictionary or not presentation.get("staticPlacements") is Array:
			return "environment arena requires presentation staticPlacements"
		if presentation.staticPlacements.size() > EnvironmentPresentationContract.MAX_ARENA_PLACEMENTS:
			return "arena has too many presentation placements"
		var placement_ids: Dictionary = {}
		for placement_value: Variant in presentation.staticPlacements:
			if not placement_value is Dictionary:
				return "arena presentation placement must be an object"
			var placement: Dictionary = placement_value
			if not placement.has_all(["id", "planeStack", "groundPosition", "rotationDegrees"]):
				return "arena presentation placement fields are missing"
			if not placement.id is String or String(placement.id).is_empty() or placement_ids.has(placement.id):
				return "arena presentation placement IDs must be unique"
			placement_ids[placement.id] = true
			if not placement.planeStack is String or String(placement.planeStack).is_empty():
				return "arena presentation placement must reference a plane stack"
			if not placement.groundPosition is Array or placement.groundPosition.size() != 2:
				return "arena presentation groundPosition must contain two integers"
			for coordinate: Variant in placement.groundPosition:
				if not integer_between(coordinate, 0, 4096):
					return "arena presentation groundPosition is invalid"
			if int(placement.groundPosition[0]) > int(ground.width) or int(placement.groundPosition[1]) > int(ground.height):
				return "arena presentation placement is outside ground"
			if not (placement.rotationDegrees is int or placement.rotationDegrees is float) or not is_finite(float(placement.rotationDegrees)) or not is_zero_approx(float(placement.rotationDegrees)):
				return "arena presentation rotation must be zero for fixed cards"
			if placement.has("obstacle") and (not placement.obstacle is String or not identities.has(placement.obstacle)):
				return "arena presentation placement references a missing obstacle"
	return ""


static func _sha256_pin(value: Variant) -> bool:
	if not value is String or not String(value).begins_with("sha256:") or String(value).length() != 71:
		return false
	for character: String in String(value).trim_prefix("sha256:"):
		if character not in "0123456789abcdef":
			return false
	return true


static func integer_between(value: Variant, minimum: int, maximum: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floor(float(value)) and value >= minimum and value <= maximum


static func to_fixed(point: Array) -> Array:
	return [int(point[0]) * SCALE, int(point[1]) * SCALE]


static func boxes_overlap(a: Array, b: Array, combined_radius: int) -> bool:
	return absi(int(a[0]) - int(b[0])) < combined_radius and absi(int(a[1]) - int(b[1])) < combined_radius


static func position_clear(arena: Dictionary, position: Array, radius: int, flag: String = "movement") -> bool:
	if int(position[0]) < radius or int(position[1]) < radius or int(position[0]) > int(arena.ground.width) * SCALE - radius or int(position[1]) > int(arena.ground.height) * SCALE - radius:
		return false
	for obstacle: Dictionary in arena.obstacles:
		if bool(obstacle[flag]) and point_in_rect(position, expanded_rect(obstacle.rect, radius)):
			return false
	return true


static func point_in_rect(point: Array, rect: Array) -> bool:
	return int(point[0]) >= int(rect[0]) and int(point[1]) >= int(rect[1]) and int(point[0]) <= int(rect[2]) and int(point[1]) <= int(rect[3])


static func expanded_rect(rect: Array, radius: int) -> Array:
	return [int(rect[0]) * SCALE - radius, int(rect[1]) * SCALE - radius, (int(rect[0]) + int(rect[2])) * SCALE + radius, (int(rect[1]) + int(rect[3])) * SCALE + radius]


## Swept segment/AABB entry fraction, integer [0,FRACTION], or -1 for no hit.
static func segment_rect_fraction(start: Array, finish: Array, rect: Array) -> int:
	var enter := 0
	var leave := FRACTION
	for axis: int in [0, 1]:
		var delta := int(finish[axis]) - int(start[axis])
		if delta == 0:
			if int(start[axis]) < int(rect[axis]) or int(start[axis]) > int(rect[axis + 2]):
				return -1
			continue
		var a := int((int(rect[axis]) - int(start[axis])) * FRACTION / delta)
		var b := int((int(rect[axis + 2]) - int(start[axis])) * FRACTION / delta)
		enter = maxi(enter, mini(a, b))
		leave = mini(leave, maxi(a, b))
		if enter > leave:
			return -1
	return enter if leave >= 0 and enter <= FRACTION else -1


static func obstruction_fraction(arena: Dictionary, start: Array, finish: Array, radius: int, flag: String) -> int:
	var earliest := -1
	for obstacle: Dictionary in arena.obstacles:
		if not bool(obstacle[flag]):
			continue
		var hit := segment_rect_fraction(start, finish, expanded_rect(obstacle.rect, radius))
		if hit >= 0 and (earliest < 0 or hit < earliest):
			earliest = hit
	return earliest


## Exact segment entry into the convex volume swept by a translating AABB.
## Unlike an enclosing min/max box, diagonal movement has no phantom corners.
static func swept_box_fraction(start: Array, finish: Array, body_start: Array, body_finish: Array, radius: int) -> int:
	var points: Array = []
	for center: Array in [body_start, body_finish]:
		for x: int in [-radius, radius]:
			for y: int in [-radius, radius]:
				points.append([int(center[0]) + x, int(center[1]) + y])
	points.sort_custom(func(a: Array, b: Array) -> bool: return int(a[0]) < int(b[0]) or (a[0] == b[0] and int(a[1]) < int(b[1])))
	var unique: Array = []
	for point: Array in points:
		if unique.is_empty() or unique.back() != point:
			unique.append(point)
	var lower: Array = []
	var upper: Array = []
	for point: Array in unique:
		while lower.size() >= 2 and _cross(lower[-2], lower[-1], point) <= 0:
			lower.pop_back()
		lower.append(point)
	unique.reverse()
	for point: Array in unique:
		while upper.size() >= 2 and _cross(upper[-2], upper[-1], point) <= 0:
			upper.pop_back()
		upper.append(point)
	lower.pop_back()
	upper.pop_back()
	var polygon: Array = lower + upper
	var enter := 0
	var leave := FRACTION
	for index: int in range(polygon.size()):
		var a: Array = polygon[index]
		var b: Array = polygon[(index + 1) % polygon.size()]
		var first := _cross(a, b, start)
		var last := _cross(a, b, finish)
		if first < 0 and last < 0:
			return -1
		if first < 0:
			var denominator := last - first
			enter = maxi(enter, (-first * FRACTION + denominator - 1) / denominator)
		elif last < 0:
			leave = mini(leave, first * FRACTION / (first - last))
		if enter > leave:
			return -1
	return enter


static func _cross(a: Array, b: Array, c: Array) -> int:
	return (int(b[0]) - int(a[0])) * (int(c[1]) - int(a[1])) - (int(b[1]) - int(a[1])) * (int(c[0]) - int(a[0]))


static func segment_clear(arena: Dictionary, start: Array, finish: Array, radius: int, flag: String = "movement") -> bool:
	return position_clear(arena, finish, radius, flag) and obstruction_fraction(arena, start, finish, radius, flag) < 0


## Deterministic four-neighbor shortest grid path, stable N/W/E/S tie-breaking.
## Every center and edge is checked with the actual finite body footprint.
static func path(arena: Dictionary, start: Array, goal: Array, radius: int) -> Array:
	if segment_clear(arena, start, goal, radius):
		return [goal.duplicate()]
	var cell_size := int(arena.ground.cellSize) * SCALE
	var width := int(arena.ground.width) * SCALE / cell_size
	var height := int(arena.ground.height) * SCALE / cell_size
	var start_cell := _accessible_cell(arena, start, radius, width, height, cell_size)
	var goal_cell := _accessible_cell(arena, goal, radius, width, height, cell_size)
	if start_cell < 0 or goal_cell < 0:
		return []
	var frontier: Array[int] = [start_cell]
	var parents: Dictionary = {start_cell: -1}
	var cursor := 0
	while cursor < frontier.size():
		var current: int = frontier[cursor]
		cursor += 1
		if current == goal_cell:
			var reverse_points: Array = [goal.duplicate()]
			while current >= 0:
				reverse_points.append(_cell_center(current, width, cell_size))
				current = int(parents[current])
			reverse_points.reverse()
			return reverse_points
		var center := _cell_center(current, width, cell_size)
		for offset: Array in NEIGHBORS:
			var x := current % width + int(offset[0])
			var y := current / width + int(offset[1])
			if x < 0 or x >= width or y < 0 or y >= height:
				continue
			var next := y * width + x
			if parents.has(next):
				continue
			if segment_clear(arena, center, _cell_center(next, width, cell_size), radius):
				parents[next] = current
				frontier.append(next)
	return []


static func _cell_center(index: int, width: int, cell_size: int) -> Array:
	return [(index % width) * cell_size + cell_size / 2, (index / width) * cell_size + cell_size / 2]


static func _accessible_cell(arena: Dictionary, point: Array, radius: int, width: int, height: int, cell_size: int) -> int:
	var cx := clampi(int(point[0]) / cell_size, 0, width - 1)
	var cy := clampi(int(point[1]) / cell_size, 0, height - 1)
	for reach: int in range(4):
		for y: int in range(maxi(0, cy - reach), mini(height, cy + reach + 1)):
			for x: int in range(maxi(0, cx - reach), mini(width, cx + reach + 1)):
				var cell := y * width + x
				if segment_clear(arena, point, _cell_center(cell, width, cell_size), radius):
					return cell
	return -1
