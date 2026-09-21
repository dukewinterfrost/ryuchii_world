class_name BattleDefinitionsV3
extends RefCounted

## Prototype balance values. Stable IDs are save/replay identifiers.
const CARE_TUNING := {"social_cooldown": 30.0, "pet": [4.0, 0.0], "praise": [5.0, -2.0], "scold": [-5.0, 5.0], "potty_warning": 30.0, "potty_habit_required": 60.0, "potty_discipline_required": 50.0}
const SPECIES := {
	"botamon": {"name": "Botamon", "stage": "Baby", "basic_move": "tackle", "personality": "Cautious, curious, verbally simple"},
	"koromon": {"name": "Koromon", "stage": "In-Training", "basic_move": "headbutt", "personality": "Affectionate, expressive, excitable"},
	"agumon": {"name": "Agumon", "stage": "Rookie", "basic_move": "claw", "personality": "Energetic, brave, lightly mischievous"},
}
const TRAINING := {
	"hp": {"name": "Stamina", "gain": 20, "cap": 9999}, "mp": {"name": "Focus", "gain": 20, "cap": 9999},
	"offense": {"name": "Strength", "gain": 2, "cap": 999}, "defense": {"name": "Endurance", "gain": 2, "cap": 999},
	"speed": {"name": "Agility", "gain": 2, "cap": 999}, "brains": {"name": "Wisdom", "gain": 2, "cap": 999},
}
const TRAINING_SECONDS := 30.0
const EVOLUTIONS := {
	"botamon": [{"target": "koromon", "priority": 0, "stage": "In-Training", "min_active_seconds": 600.0, "min_bond": 24.0, "required_actions": ["feed", "play", "chat"], "stats": {}, "care": {}, "learned_moves": []}],
	"koromon": [{"target": "agumon", "priority": 0, "stage": "Rookie", "min_active_seconds": 1800.0, "min_bond": 70.0, "required_actions": ["feed", "play", "chat"], "stats": {"offense": 12}, "care": {"discipline": 45}, "learned_moves": []}],
}
const MOVES := {
	"tackle": {"name": "Tackle", "mp": 0, "power": 100, "range": "melee", "equippable": false},
	"headbutt": {"name": "Headbutt", "mp": 0, "power": 100, "range": "melee", "equippable": false},
	"claw": {"name": "Claw", "mp": 0, "power": 100, "range": "melee", "equippable": false},
	"pepper_breath": {"name": "Pepper Breath", "mp": 12, "range": "ranged", "equippable": true},
	"quick_bite": {"name": "Quick Bite", "mp": 4, "power": 115, "range": "melee", "equippable": true},
	"heavy_claw": {"name": "Heavy Claw", "mp": 8, "power": 180, "range": "melee", "windup": 30, "active": 3, "duration": 54, "equippable": true},
}
const ITEMS := {
	"small_recovery": {"name": "Small Recovery", "stat": "hp", "restore": 50},
	"mp_recovery": {"name": "MP Recovery", "stat": "mp", "restore": 24},
}
const DECOR := {
	"digi_potty": {"name": "Digi Potty", "size": [2, 2], "solid": true, "entrance": [0, 2]},
	"rug": {"name": "Rug", "size": [3, 2], "solid": false},
	"planter": {"name": "Planter", "size": [1, 1], "solid": true},
}

static func default_inventory() -> Dictionary:
	var starter_decor := {"digi_potty": 1, "rug": 1, "planter": 1}
	return {
		"starter_granted": true,
		"items": {"small_recovery": 3, "mp_recovery": 3},
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
