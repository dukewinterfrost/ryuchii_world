class_name EnclosureRules
extends RefCounted

const Definitions = preload("res://scripts/core/game_definitions.gd")
const Habitat = preload("res://scripts/core/habitat_rules.gd")
static var STARTER: Dictionary = GameBalance.setting("enclosure_rules.STARTER")
static var POND_RECOVERY: float = GameBalance.setting("enclosure_rules.POND_RECOVERY")
static var POND_COOLDOWN: float = GameBalance.setting("enclosure_rules.POND_COOLDOWN")

static func initial() -> Dictionary:
	return {"materials": STARTER.duplicate(), "meals": {"steak": 0, "sweet_potato": 0}, "pond_ready_at": 0.0}

static func valid(value: Variant) -> bool:
	if not value is Dictionary or value.size() != 3 or not value.has_all(["materials", "meals", "pond_ready_at"]): return false
	for key: String in ["materials", "meals"]:
		if not value[key] is Dictionary: return false
		var expected: Array = STARTER.keys() if key == "materials" else ["steak", "sweet_potato"]
		if value[key].size() != expected.size(): return false
		for id: String in expected:
			var count: Variant = value[key].get(id)
			if not (count is int or count is float) or not is_finite(float(count)) or float(count) < 0 or float(count) > 1000000000 or floorf(float(count)) != float(count): return false
	var time: Variant = value.pond_ready_at
	return (time is int or time is float) and is_finite(float(time)) and float(time) >= 0 and float(time) <= 253402300799.0

static func placement_manifest(layout: Dictionary, original: Dictionary) -> Dictionary:
	# Only explicitly removable native scenery is relaxed. Authored boundaries stay.
	return preload("res://scripts/environment/native_care_scenery.gd").resolve(layout, original)

static func quote(state: Dictionary, draft: Dictionary, manifest: Dictionary = {}) -> Dictionary:
	var proposed := draft.duplicate(true)
	proposed.creature_cell = state.habitat.creature_cell.duplicate()
	proposed.camera = state.habitat.camera.duplicate(true)
	proposed.theme = state.habitat.theme
	var check := Habitat.validate_layout(proposed, Vector2i(-1, -1), placement_manifest(proposed, manifest))
	if not check.ok: return check
	var available: Dictionary = state.inventory.decor.duplicate(true)
	var bought := {}
	var cost := {"wood": 0, "stone": 0, "fiber": 0}
	for item: Dictionary in state.habitat.items:
		available[item.item_id] = int(available.get(item.item_id, 0)) + 1
	for item: Dictionary in proposed.items:
		if int(available.get(item.item_id, 0)) > 0:
			available[item.item_id] -= 1
		else:
			bought[item.item_id] = int(bought.get(item.item_id, 0)) + 1
			for material: String in Definitions.DECOR[item.item_id].cost:
				cost[material] += int(Definitions.DECOR[item.item_id].cost[material])
	for material: String in cost:
		if int(state.enclosure.materials[material]) < int(cost[material]):
			return {"ok": false, "error": "Not enough %s: need %d, have %d." % [material, cost[material], state.enclosure.materials[material]], "cost": cost}
	return {"ok": true, "error": "", "cost": cost, "bought": bought, "available": available, "layout": proposed}

static func build(state: Dictionary, draft: Dictionary, manifest: Dictionary = {}) -> Dictionary:
	var result := quote(state, draft, manifest)
	if not result.ok: return result
	var next := state.duplicate(true)
	next.habitat = result.layout
	next.inventory.decor = result.available
	for kind: String in result.bought:
		next.inventory.decor_owned[kind] += int(result.bought[kind])
	for material: String in result.cost:
		next.enclosure.materials[material] -= int(result.cost[material])
	return {"ok": true, "state": next, "cost": result.cost}

static func use_facility(state: Dictionary, action: String, now: float, manifest: Dictionary = {}) -> Dictionary:
	if state.care.status.sleeping: return {"ok": false, "error": "Wake up before using a facility."}
	var kind := "pond" if action == "pond" else "campfire"
	if action not in ["pond", "cook_meat", "cook_potato"]: return {"ok": false, "error": "Unknown facility action."}
	if Habitat.path_to_facility(state.habitat, kind, manifest).is_empty():
		return {"ok": false, "error": "Build a reachable %s first." % kind}
	var next := state.duplicate(true)
	if action == "pond":
		if now < float(state.enclosure.pond_ready_at): return {"ok": false, "error": "Pond ready in %d seconds." % ceili(float(state.enclosure.pond_ready_at) - now)}
		if float(state.care.fatigue) <= 0 and float(state.care.virus) <= 0: return {"ok": false, "error": "Already refreshed."}
		next.care.fatigue = maxf(0, float(next.care.fatigue) - POND_RECOVERY)
		next.care.virus = maxf(0, float(next.care.virus) - float(GameBalance.setting("building.pond_virus_recovery")))
		next.enclosure.pond_ready_at = now + POND_COOLDOWN
		return {"ok": true, "state": next, "message": "Rinsed and cooled down. Fatigue −%.0f, virus −%.0f." % [POND_RECOVERY, float(GameBalance.setting("building.pond_virus_recovery"))]}
	var ingredient := "raw_meat" if action == "cook_meat" else "potato"
	var meal := "steak" if action == "cook_meat" else "sweet_potato"
	if int(next.enclosure.materials[ingredient]) < int(GameBalance.setting("building.cooking_ingredient_cost")) or int(next.enclosure.materials.wood) < int(GameBalance.setting("building.cooking_wood_cost")):
		return {"ok": false, "error": "Cooking needs %d %s and %d wood." % [int(GameBalance.setting("building.cooking_ingredient_cost")), ingredient.replace("_", " "), int(GameBalance.setting("building.cooking_wood_cost"))]}
	next.enclosure.materials[ingredient] -= int(GameBalance.setting("building.cooking_ingredient_cost"))
	next.enclosure.materials.wood -= int(GameBalance.setting("building.cooking_wood_cost"))
	next.enclosure.meals[meal] += 1
	return {"ok": true, "state": next, "message": "Cooked %s. Ready to serve." % meal.replace("_", " ")}

static func enlarge_legacy_layout(layout: Dictionary, inventory: Dictionary) -> Dictionary:
	if Habitat.validate_layout(layout).ok: return layout.duplicate(true)
	var next := layout.duplicate(true)
	next.items = []
	var occupied := {Vector2i(int(layout.creature_cell[0]), int(layout.creature_cell[1])): true}
	for source: Dictionary in layout.items:
		var origin := Vector2i(int(source.x), int(source.y))
		var candidates: Array[Vector2i] = []
		for y: int in Habitat.HEIGHT:
			for x: int in Habitat.WIDTH: candidates.append(Vector2i(x, y))
		candidates.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
			var da := absi(a.x-origin.x)+absi(a.y-origin.y)
			var db := absi(b.x-origin.x)+absi(b.y-origin.y)
			return da < db if da != db else (a.y < b.y if a.y != b.y else a.x < b.x))
		var placed := false
		for cell: Vector2i in candidates:
			var item := source.duplicate(true)
			item.x = cell.x
			item.y = cell.y
			var cells := Habitat.footprint(item)
			if cells.any(func(c: Vector2i) -> bool: return not Habitat.inside(c) or occupied.has(c)): continue
			next.items.append(item)
			if Habitat.validate_layout(next).ok:
				for c: Vector2i in cells: occupied[c] = true
				placed = true
				break
			next.items.pop_back()
		if not placed:
			# Full enclosures return an owned object to storage, never delete it or charge again.
			inventory.decor[source.item_id] += 1
	return next
