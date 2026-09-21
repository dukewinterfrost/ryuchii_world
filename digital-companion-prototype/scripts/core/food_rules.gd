class_name FoodRules
extends RefCounted

## Prototype pantry: no currency or limited stock. Timing is save-owned, not UI-owned.
const FOODS := {
	"sweet_potato": {"name": "Sweet potato", "icon": 0},
	"pizza": {"name": "Pizza", "icon": 1},
	"shrimp": {"name": "Shrimp", "icon": 2},
	"pudding": {"name": "Pudding", "icon": 3},
	"rice_ball": {"name": "Rice ball", "icon": 4},
	"strawberry": {"name": "Strawberry", "icon": 5},
	"drumstick": {"name": "Drumstick", "icon": 6},
	"steak": {"name": "Steak", "icon": 7},
	"cake": {"name": "Cake", "icon": 8},
}
static var FAVORITES: Dictionary = GameBalance.setting("food.favorites")
static var DURATION: float = GameBalance.setting("food_rules.DURATION")
static var MAX_FULLNESS: float = GameBalance.setting("food_rules.MAX_FULLNESS")

static func initial() -> Dictionary:
	return {"craving": "", "expires_at": 0.0, "wait_seconds": float(GameBalance.setting("food.initial_wait")), "sequence": 0, "satisfied": 0}

static func favorite(species: String) -> String:
	return String(FAVORITES.get(species, "pudding"))

static func label(food: String) -> String:
	return String(FOODS.get(food, {}).get("name", "Meal"))

static func icon(food: String) -> Texture2D:
	if not FOODS.has(food):
		return null
	return load("res://assets/food/food-%d.png" % int(FOODS[food].icon)) as Texture2D

static func active(state: Dictionary, now: float = -1.0) -> String:
	var data: Dictionary = state.care.get("food", initial())
	var clock := float(state.meta.last_update_time) if now < 0 else now
	if float(state.care.hunger) > MAX_FULLNESS or float(data.expires_at) <= clock:
		return ""
	return String(data.craving)

static func advance(state: Dictionary, now: float, engaged: float) -> void:
	var data: Dictionary = state.care.food
	if not String(data.craving).is_empty():
		if now >= float(data.expires_at) or float(state.care.hunger) > MAX_FULLNESS:
			data.craving = ""
			data.expires_at = 0.0
		return
	if engaged <= 0:
		return
	data.wait_seconds = maxf(0.0, float(data.wait_seconds) - engaged)
	if float(data.wait_seconds) > 0.0 or float(state.care.hunger) > MAX_FULLNESS:
		return
	var sequence := int(data.sequence)
	var keys := FOODS.keys()
	data.craving = favorite(String(state.identity.species_id)) if sequence % 2 == 0 else String(keys[(sequence * 7) % keys.size()])
	data.sequence = mini(sequence + 1, 1000000000)
	data.expires_at = now + DURATION
	data.wait_seconds = float(GameBalance.setting("food.wait_base")) + float((sequence * 73 + 41) % (int(GameBalance.setting("food.wait_jitter")) + 1))

static func valid(data: Variant) -> bool:
	if not data is Dictionary or data.size() != 5 or not data.has_all(["craving", "expires_at", "wait_seconds", "sequence", "satisfied"]):
		return false
	if not data.craving is String or (not data.craving.is_empty() and not FOODS.has(data.craving)):
		return false
	for key: String in ["expires_at", "wait_seconds", "sequence", "satisfied"]:
		var value: Variant = data[key]
		if not (value is int or value is float) or not is_finite(float(value)) or float(value) < 0:
			return false
	if float(data.expires_at) > 253402300799.0 or float(data.wait_seconds) > 420.0:
		return false
	for key: String in ["sequence", "satisfied"]:
		if float(data[key]) != floorf(float(data[key])) or float(data[key]) > 1000000000:
			return false
	return (data.craving.is_empty() and float(data.expires_at) == 0.0) or (not data.craving.is_empty() and float(data.expires_at) > 0.0)
