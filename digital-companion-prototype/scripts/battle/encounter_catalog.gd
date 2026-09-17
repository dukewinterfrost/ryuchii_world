class_name EncounterCatalog
extends RefCounted

## Contextual encounter identities are stable gameplay-facing keys. They resolve
## to arena asset identities without exposing an arena picker in the live UI.
## Review/debug tools may enumerate every record through all_debug_encounters().

const DEFAULT_ENCOUNTER := "encounter.green-shade.rootbound-glade"
const RECORDS := {
	"encounter.green-shade.rootbound-glade": {
		"arenaId": "arena-rootbound-glade", "regionId": "green-shade",
		"title": "ROOTBOUND GLADE", "legacyFallback": "forest",
	},
	"encounter.shellfish-beach.breaker-cove": {
		"arenaId": "arena-breaker-cove", "regionId": "shellfish-beach",
		"title": "BREAKER COVE", "legacyFallback": "",
	},
	"encounter.toy-maze.clockwork-maze": {
		"arenaId": "arena-clockwork-maze", "regionId": "toy-maze",
		"title": "CLOCKWORK MAZE", "legacyFallback": "",
	},
	"encounter.mechatropolis.reactor-causeway": {
		"arenaId": "arena-reactor-causeway", "regionId": "mechatropolis",
		"title": "REACTOR CAUSEWAY", "legacyFallback": "",
	},
	"encounter.nephelis-abyss.rift-platform": {
		"arenaId": "arena-rift-platform", "regionId": "nephelis-abyss",
		"title": "RIFT PLATFORM", "legacyFallback": "",
	},
}
const ALIASES := {
	"forest": "encounter.green-shade.rootbound-glade",
	"forest-arena": "encounter.green-shade.rootbound-glade",
	"green-shade": "encounter.green-shade.rootbound-glade",
	"rootbound-glade": "encounter.green-shade.rootbound-glade",
	"arena-rootbound-glade": "encounter.green-shade.rootbound-glade",
	"training.green-shade": "encounter.green-shade.rootbound-glade",
	"shellfish-beach": "encounter.shellfish-beach.breaker-cove",
	"breaker-cove": "encounter.shellfish-beach.breaker-cove",
	"arena-breaker-cove": "encounter.shellfish-beach.breaker-cove",
	"training.shellfish-beach": "encounter.shellfish-beach.breaker-cove",
	"toy-maze": "encounter.toy-maze.clockwork-maze",
	"clockwork-maze": "encounter.toy-maze.clockwork-maze",
	"arena-clockwork-maze": "encounter.toy-maze.clockwork-maze",
	"training.toy-maze": "encounter.toy-maze.clockwork-maze",
	"mechatropolis": "encounter.mechatropolis.reactor-causeway",
	"reactor-causeway": "encounter.mechatropolis.reactor-causeway",
	"arena-reactor-causeway": "encounter.mechatropolis.reactor-causeway",
	"training.mechatropolis": "encounter.mechatropolis.reactor-causeway",
	"nephelis-abyss": "encounter.nephelis-abyss.rift-platform",
	"rift-platform": "encounter.nephelis-abyss.rift-platform",
	"arena-rift-platform": "encounter.nephelis-abyss.rift-platform",
	"training.nephelis-abyss": "encounter.nephelis-abyss.rift-platform",
}


static func resolve(value: String) -> Dictionary:
	var requested := value.strip_edges()
	if requested.is_empty():
		requested = DEFAULT_ENCOUNTER
	if requested in ["graybox", "debug.graybox"]:
		return {"ok": true, "encounterId": "debug.graybox", "arenaId": "graybox",
			"regionId": "debug", "title": "GRAYBOX", "legacyFallback": "graybox"}
	var encounter_id := String(ALIASES.get(requested, requested))
	if not RECORDS.has(encounter_id):
		return {"ok": false, "error": "Unknown contextual encounter: " + requested}
	var result: Dictionary = RECORDS[encounter_id].duplicate(true)
	result.merge({"ok": true, "encounterId": encounter_id}, true)
	return result


static func encounter_for_arena(arena_id: String) -> String:
	var resolved := resolve(arena_id)
	return String(resolved.get("encounterId", "")) if bool(resolved.get("ok", false)) else ""


static func encounter_for_region(region_id: String) -> String:
	for encounter_id: String in RECORDS:
		if String(RECORDS[encounter_id].regionId) == region_id:
			return encounter_id
	return ""


static func all_debug_encounters() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for encounter_id: String in RECORDS:
		var record: Dictionary = RECORDS[encounter_id].duplicate(true)
		record["encounterId"] = encounter_id
		result.append(record)
	return result
