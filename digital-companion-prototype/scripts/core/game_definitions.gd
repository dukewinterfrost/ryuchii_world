class_name GameDefinitions
extends RefCounted

## Prototype balance values. Stable IDs are save/replay identifiers.
static var CARE_TUNING: Dictionary = GameBalance.setting("game_definitions.CARE_TUNING")
const SPECIES := {
	"botamon": {"name": "Botamon", "stage": "Baby", "basic_move": "tackle", "personality": "Cautious, curious, verbally simple"},
	"koromon": {"name": "Koromon", "stage": "In-Training", "basic_move": "headbutt", "personality": "Affectionate, expressive, excitable"},
	"agumon": {"name": "Agumon", "stage": "Rookie", "basic_move": "claw", "personality": "Energetic, brave, lightly mischievous"},
}
static var TRAINING: Dictionary = GameBalance.setting("game_definitions.TRAINING")
static var TRAINING_SECONDS: float = GameBalance.setting("game_definitions.TRAINING_SECONDS")
static var EVOLUTIONS: Dictionary = GameBalance.setting("game_definitions.EVOLUTIONS")
# Stable save identities are independent of editable balance. An invalid table
# must block battle creation, never make a player's existing save look corrupt.
const Content = preload("res://scripts/battle/mob_content.gd")
const MOVE_IDENTITIES := {
	"tackle": {"name": "Tackle", "equippable": false},
	"headbutt": {"name": "Headbutt", "equippable": false},
	"claw": {"name": "Claw", "equippable": false},
	"pepper_breath": {"name": "Pepper Breath", "equippable": true},
	"quick_bite": {"name": "Quick Bite", "equippable": true},
	"heavy_claw": {"name": "Heavy Claw", "equippable": true},
	"acid_bubbles": {"name": "Acid Bubbles", "equippable": false},
	"bubble_blow": {"name": "Bubble Blow", "equippable": false},
	"opening_tackle": {"name": "Opening Tackle", "equippable": false},
}
const ITEM_IDENTITIES := {
	"small_recovery": {"name": "Small Recovery"}, "mp_recovery": {"name": "MP Recovery"},
	"barrier": {"name": "Barrier"}, "haste": {"name": "Haste"},
}
static var MOVES: Dictionary = _move_metadata()
static var ITEMS: Dictionary = _item_metadata()
const LEGACY_DECOR := ["digi_potty", "rug", "planter"]
const OLD_DECOR_SIZES := {"campfire": [2, 2], "pond": [4, 3], "digi_potty": [2, 2], "rug": [3, 2], "planter": [1, 1]}
static var DECOR: Dictionary = GameBalance.setting("game_definitions.DECOR")

static func default_inventory() -> Dictionary:
	var starter_decor: Dictionary = GameBalance.setting("inventory.starter_decor").duplicate(true)
	return {
		"starter_granted": true,
		"items": GameBalance.setting("inventory.starter_items").duplicate(true),
		"decor": starter_decor.duplicate(true),
		# Durable entitlement totals make regional layouts auditable. The sum of
		# every placed instance plus the unplaced count must equal this value.
		"decor_owned": starter_decor.duplicate(true),
		"consumed_command_ids": [],
	}

static func default_skills(species: String) -> Dictionary:
	var learned: Array = ["pepper_breath", "quick_bite", "heavy_claw"] if species == "agumon" else []
	var slots: Array = []
	for move: String in learned:
		slots.append({"move_id": move, "auto": true})
	return {"learned": learned, "equipped": slots}


static func refresh_combat_metadata() -> void:
	MOVES = _move_metadata()
	ITEMS = _item_metadata()


static func _move_metadata() -> Dictionary:
	var result := Content.move_metadata()
	if result.is_empty():
		result = MOVE_IDENTITIES.duplicate(true)
		for id: String in result:
			result[id]["content_available"] = false
	return result


static func _item_metadata() -> Dictionary:
	var result := Content.item_metadata()
	if result.is_empty():
		result = ITEM_IDENTITIES.duplicate(true)
		for id: String in result:
			result[id]["content_available"] = false
	return result
