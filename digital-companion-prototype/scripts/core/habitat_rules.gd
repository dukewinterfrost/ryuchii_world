class_name HabitatRules
extends RefCounted

## Deterministic ground-grid authority for every home region. Rendering and 3D
## physics are deliberately absent: environment manifests only contribute
## explicit blocker cells and authored anchors to these pure rules.

const Definitions = preload("res://scripts/core/game_definitions.gd")
const WIDTH := 40
const HEIGHT := 48
const CELL_SIZE := 32
const LEGACY_WIDTH := 20
const LEGACY_HEIGHT := 24
const LEGACY_CENTER_OFFSET := Vector2i(10, 12)
const DEFAULT_REGION := "green-shade"
const REGION_IDS := ["green-shade", "shellfish-beach", "toy-maze", "mechatropolis", "nephelis-abyss"]
const REGION_ALIASES := {
	"forest": DEFAULT_REGION,
	"forest-arena": DEFAULT_REGION,
	"green_shade": DEFAULT_REGION,
}
const REGION_HOMES := {
	"green-shade": {"name": "Canopy Clearing", "habitat_id": "habitat-canopy-clearing"},
	"shellfish-beach": {"name": "Tidepool Camp", "habitat_id": "habitat-tidepool-camp"},
	"toy-maze": {"name": "Wind-Up Plaza", "habitat_id": "habitat-wind-up-plaza"},
	"mechatropolis": {"name": "Service Deck", "habitat_id": "habitat-service-deck"},
	"nephelis-abyss": {"name": "Cloudfall Sanctuary", "habitat_id": "habitat-cloudfall-sanctuary"},
}
const REGION_FLAGS := {
	"shellfish-beach": "story.region.shellfish_beach",
	"toy-maze": "story.region.toy_maze",
	"mechatropolis": "story.region.mechatropolis",
	"nephelis-abyss": "story.region.nephelis_abyss",
}
const STORY_FLAGS := [
	"story.region.shellfish_beach",
	"story.region.toy_maze",
	"story.region.mechatropolis",
	"story.region.nephelis_abyss",
]


static func resolve_region_alias(value: String) -> String:
	var normalized := value.strip_edges().to_lower().replace("_", "-")
	return String(REGION_ALIASES.get(normalized, normalized))


static func region_is_known(value: String) -> bool:
	return resolve_region_alias(value) in REGION_IDS


static func region_is_unlocked(region_id: String, story_flags: Dictionary) -> bool:
	var resolved := resolve_region_alias(region_id)
	if resolved == DEFAULT_REGION:
		return true
	return bool(story_flags.get(REGION_FLAGS.get(resolved, ""), false))


static func default_story_flags() -> Dictionary:
	var result := {}
	for flag: String in STORY_FLAGS:
		result[flag] = false
	return result


static func default_layout(spawn := Vector2i(20, 24)) -> Dictionary:
	return {
		"theme": "verdant",
		"items": [],
		"camera": {"zoom": 1.0, "follow": true},
		"creature_cell": [spawn.x, spawn.y],
	}


static func default_layout_for_manifest(manifest: Dictionary) -> Dictionary:
	var spawn := _manifest_cell(manifest.get("spawn"), Vector2i(20, 24))
	return default_layout(spawn)


static func migrate_legacy_layout(layout: Dictionary) -> Dictionary:
	if not _validate_layout_shape(layout, LEGACY_WIDTH, LEGACY_HEIGHT, {}, Vector2i(-1, -1), true).ok:
		return {}
	var migrated := layout.duplicate(true)
	var old_creature := Vector2i(int(layout.creature_cell[0]), int(layout.creature_cell[1]))
	var next_creature := old_creature + LEGACY_CENTER_OFFSET
	migrated.creature_cell = [next_creature.x, next_creature.y]
	for item: Dictionary in migrated.items:
		item.x = int(item.x) + LEGACY_CENTER_OFFSET.x
		item.y = int(item.y) + LEGACY_CENTER_OFFSET.y
	return migrated if validate_layout(migrated, Vector2i(-1, -1), {}, true).ok else {}


static func footprint(item: Dictionary, legacy_geometry := false) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if not Definitions.DECOR.has(item.get("item_id", "")):
		return cells
	var size: Array = Definitions.OLD_DECOR_SIZES[item.item_id] if legacy_geometry else Definitions.DECOR[item.item_id].size
	var w := int(size[0]) if int(item.get("rotation", 0)) % 2 == 0 else int(size[1])
	var h := int(size[1]) if int(item.get("rotation", 0)) % 2 == 0 else int(size[0])
	for y: int in h:
		for x: int in w:
			cells.append(Vector2i(int(item.x) + x, int(item.y) + y))
	return cells


static func potty_entrance(item: Dictionary) -> Vector2i:
	return facility_entrance(item)


static func facility_entrance(item: Dictionary, legacy_geometry := false) -> Vector2i:
	var definition: Dictionary = Definitions.DECOR[item.item_id]
	var size: Array = Definitions.OLD_DECOR_SIZES[item.item_id] if legacy_geometry else definition.size
	var e: Array = ([1, 3] if item.item_id == "pond" else [0, 2]) if legacy_geometry else definition.get("entrance", [0, size[1]])
	var offset := Vector2i(int(e[0]), int(e[1]))
	match int(item.get("rotation", 0)) % 4:
		1: offset = Vector2i(int(size[1]) - 1 - offset.y, offset.x)
		2: offset = Vector2i(int(size[0]) - 1 - offset.x, int(size[1]) - 1 - offset.y)
		3: offset = Vector2i(offset.y, int(size[0]) - 1 - offset.x)
	return Vector2i(int(item.x), int(item.y)) + offset


static func path_to_facility(layout: Dictionary, kind: String, habitat_manifest: Dictionary = {}) -> Array[Vector2i]:
	var start := Vector2i(int(layout.creature_cell[0]), int(layout.creature_cell[1]))
	var best: Array[Vector2i] = []
	for item: Dictionary in layout.items:
		if item.item_id == kind:
			var path := path_between_cells(layout, start, facility_entrance(item), habitat_manifest)
			if not path.is_empty() and (best.is_empty() or path.size() < best.size()): best = path
	return best


static func validate_layout(layout: Dictionary, creature_cell: Vector2i = Vector2i(-1, -1), habitat_manifest: Dictionary = {}, legacy_geometry := false) -> Dictionary:
	var dimensions := grid_size(habitat_manifest)
	return _validate_layout_shape(layout, dimensions.x, dimensions.y, habitat_manifest, creature_cell, legacy_geometry)


static func path_to_potty(layout: Dictionary, creature_cell: Vector2i = Vector2i(-1, -1), habitat_manifest: Dictionary = {}) -> Array[Vector2i]:
	var empty: Array[Vector2i] = []
	if not bool(validate_layout(layout, creature_cell, habitat_manifest).ok):
		return empty
	if creature_cell == Vector2i(-1, -1):
		creature_cell = Vector2i(int(layout.creature_cell[0]), int(layout.creature_cell[1]))
	var blocked := blocked_cells(layout, habitat_manifest)
	var dimensions := grid_size(habitat_manifest)
	for item: Dictionary in layout.items:
		if item.item_id == "digi_potty":
			return _path(creature_cell, potty_entrance(item), blocked, dimensions)
	return empty


static func path_between_cells(layout: Dictionary, start: Vector2i, goal: Vector2i, habitat_manifest: Dictionary = {}) -> Array[Vector2i]:
	var empty: Array[Vector2i] = []
	if not bool(validate_layout(layout, start, habitat_manifest).ok):
		return empty
	return _path(start, goal, blocked_cells(layout, habitat_manifest), grid_size(habitat_manifest))


static func blocked_cells(layout: Dictionary, habitat_manifest: Dictionary = {}) -> Dictionary:
	var solid := _static_blocked_cells(habitat_manifest)
	for item: Dictionary in layout.get("items", []):
		if Definitions.DECOR.get(item.get("item_id", ""), {}).get("solid", false):
			for cell: Vector2i in footprint(item):
				solid[cell] = true
	return solid


static func grid_size(habitat_manifest: Dictionary = {}) -> Vector2i:
	var grid: Variant = habitat_manifest.get("grid")
	if grid is Dictionary and _integer(grid.get("columns")) and _integer(grid.get("rows")):
		return Vector2i(int(grid.columns), int(grid.rows))
	return Vector2i(WIDTH, HEIGHT)


static func waste_anchors(habitat_manifest: Dictionary = {}) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for value: Variant in habitat_manifest.get("wasteAnchors", [[8, 20], [20, 28], [32, 20]]):
		if _pair_of_integers(value):
			result.append(Vector2i(int(value[0]), int(value[1])))
	return result


static func decoration_cell_allowed(cell: Vector2i, habitat_manifest: Dictionary = {}) -> bool:
	var dimensions := grid_size(habitat_manifest)
	if not inside(cell, dimensions) or _static_blocked_cells(habitat_manifest).has(cell):
		return false
	var zones: Variant = habitat_manifest.get("decorationZones")
	if not zones is Array or zones.is_empty():
		return true
	for value: Variant in zones:
		if value is Dictionary and _rect_contains_cell(value.get("rect"), cell):
			return true
	return false


static func all_free_cells_reachable(layout: Dictionary, habitat_manifest: Dictionary = {}) -> bool:
	if not validate_layout(layout, Vector2i(-1, -1), habitat_manifest).ok:
		return false
	var dimensions := grid_size(habitat_manifest)
	var blocked := blocked_cells(layout, habitat_manifest)
	var start := Vector2i(int(layout.creature_cell[0]), int(layout.creature_cell[1]))
	var visited := {start: true}
	var queue: Array[Vector2i] = [start]
	var cursor := 0
	while cursor < queue.size():
		var current := queue[cursor]
		cursor += 1
		for step: Vector2i in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
			var neighbor := current + step
			if inside(neighbor, dimensions) and not blocked.has(neighbor) and not visited.has(neighbor):
				visited[neighbor] = true
				queue.append(neighbor)
	return visited.size() == dimensions.x * dimensions.y - blocked.size()


static func inside(cell: Vector2i, dimensions := Vector2i(WIDTH, HEIGHT)) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < dimensions.x and cell.y < dimensions.y


static func _validate_layout_shape(layout: Dictionary, width: int, height: int, habitat_manifest: Dictionary, creature_cell: Vector2i, legacy_geometry := false) -> Dictionary:
	if not layout.has_all(["theme", "items", "camera", "creature_cell"]) or layout.size() != 4:
		return {"ok": false, "error": "Incomplete habitat layout."}
	if layout.theme not in ["verdant", "practice"] or not layout.items is Array or layout.items.size() > width * height:
		return {"ok": false, "error": "Invalid habitat theme or items."}
	if not layout.camera is Dictionary or not layout.camera.has_all(["zoom", "follow"]) or layout.camera.size() != 2 or not _number(layout.camera.zoom) or float(layout.camera.zoom) < 0.0 or float(layout.camera.zoom) > 2.0 or not layout.camera.follow is bool:
		return {"ok": false, "error": "Invalid habitat camera."}
	if not _pair_of_integers(layout.creature_cell):
		return {"ok": false, "error": "Invalid creature position."}
	if creature_cell == Vector2i(-1, -1):
		creature_cell = Vector2i(int(layout.creature_cell[0]), int(layout.creature_cell[1]))
	var dimensions := Vector2i(width, height)
	if not inside(creature_cell, dimensions):
		return {"ok": false, "error": "Creature is outside the habitat."}
	var occupied := {}
	var solid := _static_blocked_cells(habitat_manifest)
	var ids := {}
	for raw: Variant in layout.items:
		if not raw is Dictionary or not raw.has_all(["instance_id", "item_id", "x", "y", "rotation"]) or raw.size() != 5:
			return {"ok": false, "error": "Invalid placed item."}
		var item: Dictionary = raw
		if not item.instance_id is String or item.instance_id.is_empty() or item.instance_id.length() > 96 or ids.has(item.instance_id) or not Definitions.DECOR.has(item.item_id):
			return {"ok": false, "error": "Invalid item identity."}
		if not _integer(item.x) or not _integer(item.y) or not _integer(item.rotation) or int(item.rotation) < 0 or int(item.rotation) > 3:
			return {"ok": false, "error": "Items must snap to the grid."}
		ids[item.instance_id] = true
		for cell: Vector2i in footprint(item, legacy_geometry):
			if not inside(cell, dimensions) or occupied.has(cell) or solid.has(cell) or not decoration_cell_allowed(cell, habitat_manifest):
				return {"ok": false, "error": "Items overlap, block authored scenery, or extend outside the decoration zone."}
			occupied[cell] = true
			if Definitions.DECOR[item.item_id].solid:
				solid[cell] = true
	if solid.has(creature_cell):
		return {"ok": false, "error": "An item blocks the creature."}
	for item: Dictionary in layout.items:
		if Definitions.DECOR[item.item_id].has("entrance") and _path(creature_cell, facility_entrance(item, legacy_geometry), solid, dimensions).is_empty():
			return {"ok": false, "error": "Every facility entrance must remain reachable."}
	return {"ok": true, "error": ""}


static func _static_blocked_cells(habitat_manifest: Dictionary) -> Dictionary:
	var result := {}
	var dimensions := grid_size(habitat_manifest)
	for value: Variant in habitat_manifest.get("blockers", []):
		if not value is Dictionary or not _rect_of_integers(value.get("rect")):
			continue
		var rect: Array = value.rect
		for y: int in range(int(rect[1]), int(rect[1]) + int(rect[3])):
			for x: int in range(int(rect[0]), int(rect[0]) + int(rect[2])):
				var cell := Vector2i(x, y)
				if inside(cell, dimensions):
					result[cell] = true
	return result


static func _path(start: Vector2i, goal: Vector2i, blocked: Dictionary, dimensions: Vector2i) -> Array[Vector2i]:
	var empty: Array[Vector2i] = []
	if not inside(start, dimensions) or not inside(goal, dimensions) or blocked.has(start) or blocked.has(goal):
		return empty
	var queue: Array[Vector2i] = [start]
	var parents := {start: start}
	var cursor := 0
	while cursor < queue.size():
		var cell := queue[cursor]
		cursor += 1
		if cell == goal:
			var result: Array[Vector2i] = [goal]
			while result.back() != start:
				result.append(parents[result.back()])
			result.reverse()
			return result
		for step: Vector2i in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
			var neighbor := cell + step
			if inside(neighbor, dimensions) and not blocked.has(neighbor) and not parents.has(neighbor):
				parents[neighbor] = cell
				queue.append(neighbor)
	return empty


static func _manifest_cell(value: Variant, fallback: Vector2i) -> Vector2i:
	return Vector2i(int(value[0]), int(value[1])) if _pair_of_integers(value) else fallback


static func _rect_contains_cell(value: Variant, cell: Vector2i) -> bool:
	if not _rect_of_integers(value):
		return false
	return cell.x >= int(value[0]) and cell.y >= int(value[1]) \
		and cell.x < int(value[0]) + int(value[2]) and cell.y < int(value[1]) + int(value[3])


static func _rect_of_integers(value: Variant) -> bool:
	return value is Array and value.size() == 4 and _integer(value[0]) and _integer(value[1]) \
		and _integer(value[2]) and _integer(value[3]) and int(value[2]) > 0 and int(value[3]) > 0


static func _pair_of_integers(value: Variant) -> bool:
	return value is Array and value.size() == 2 and _integer(value[0]) and _integer(value[1])


static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))


static func _integer(value: Variant) -> bool:
	return _number(value) and floor(float(value)) == float(value)
