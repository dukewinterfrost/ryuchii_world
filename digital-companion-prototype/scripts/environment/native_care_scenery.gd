extends RefCounted
## Explicit trunk footprints for native care scenery, never inferred from art.
## Existing saves win: omit a conflicting tree instead of moving saved items.
const TREES := [
	{"id": "InteriorOakWest", "rect": [8, 11, 2, 2]},
	{"id": "InteriorOakEast", "rect": [29, 17, 2, 2]},
	{"id": "InteriorOakSouth", "rect": [11, 34, 2, 2]},
]
static var _cache: Dictionary = {}


static func resolve(layout: Dictionary, original: Dictionary) -> Dictionary:
	var manifest := original.duplicate(true)
	if manifest.get("assetId") != "habitat-canopy-clearing" or manifest.get("revision") != "fallback-v1" or layout.is_empty():
		return manifest
	manifest.blockers = (manifest.get("blockers", []) as Array).filter(func(blocker: Dictionary) -> bool:
		return not String(blocker.get("id", "")).begins_with("native-tree-"))
	manifest.erase("nativeTrees")
	var cell := Vector2i(int(layout.creature_cell[0]), int(layout.creature_cell[1]))
	var occupied: Array = []
	for tree: Dictionary in TREES:
		var rect: Array = tree.rect
		occupied.append(Rect2i(rect[0], rect[1], rect[2], rect[3]).has_point(cell))
	var signature := JSON.stringify([manifest, layout.items, occupied])
	if _cache.has(signature):
		return _cache[signature].duplicate(true)
	manifest.nativeTrees = []
	for tree: Dictionary in TREES:
		var candidate := manifest.duplicate(true)
		candidate.blockers.append({"id": "native-tree-" + tree.id, "rect": tree.rect.duplicate()})
		if not HabitatRules.validate_layout(layout, Vector2i(-1, -1), candidate).ok:
			continue
		if not HabitatRules.all_free_cells_reachable(layout, candidate):
			continue
		var anchors_ok := true
		for anchor: Vector2i in HabitatRules.waste_anchors(candidate):
			if HabitatRules.path_between_cells(layout, cell, anchor, candidate).is_empty():
				anchors_ok = false
				break
		if anchors_ok:
			candidate.nativeTrees.append(tree.duplicate(true))
			manifest = candidate
	if _cache.size() >= 16:
		_cache.clear()
	_cache[signature] = manifest.duplicate(true)
	return manifest
