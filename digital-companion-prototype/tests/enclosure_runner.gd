extends SceneTree
var checks := 0
var failures := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
func item(kind: String, x: int, y: int, id: String = "") -> Dictionary:
	return {"instance_id": kind if id.is_empty() else id, "item_id": kind, "x": x, "y": y, "rotation": 0}
func _initialize() -> void:
	var state := CareRules.make_new_state(1000)
	var before := state.duplicate(true)
	var draft: Dictionary = state.habitat.duplicate(true)
	draft.items = [item("campfire", 14, 20), item("pond", 25, 16), item("digi_potty", 19, 18)]
	var q := EnclosureRules.quote(state, draft)
	check(q.ok and q.cost == {"wood": 10, "stone": 28, "fiber": 6}, "owned potty is free; new buildings quote exact cost")
	check(state == before, "quote and cancel cannot mutate state")
	var built := EnclosureRules.build(state, draft)
	check(built.ok and CareRules.state_is_valid(built.state), "construction creates valid conserved ownership")
	state = built.state
	check(state.enclosure.materials.wood == 50 and state.enclosure.materials.stone == 32, "materials deducted exactly once")
	check(EnclosureRules.quote(state, draft).cost == {"wood": 0, "stone": 0, "fiber": 0}, "same layout has no second charge")
	draft.items[0].x = 13
	check(EnclosureRules.quote(state, draft).cost.wood == 0, "relocation is free")
	var bad := draft.duplicate(true)
	bad.items[0].x = 25
	check(not EnclosureRules.build(state, bad).ok, "overlap rejected")
	bad = draft.duplicate(true)
	bad.items[1].x = 39
	check(not EnclosureRules.build(state, bad).ok, "out of bounds rejected")
	bad = draft.duplicate(true)
	bad.items.append(item("planter", 15, 24))
	check(not EnclosureRules.build(state, bad).ok, "blocked facility access rejected")
	var broke := before.duplicate(true)
	broke.enclosure.materials.stone = 0
	check(not EnclosureRules.build(broke, draft).ok and broke.enclosure.materials.wood == 60, "insufficient funds rejects transaction")
	var stored: Dictionary = state.habitat.duplicate(true)
	stored.items = []
	var storage := EnclosureRules.build(state, stored)
	check(storage.ok and storage.state.inventory.decor.campfire == 1 and storage.state.enclosure == state.enclosure, "storage preserves object without material refund")
	check(EnclosureRules.quote(storage.state, state.habitat).cost.wood == 0, "stored object can be replaced free")
	var cooked := EnclosureRules.use_facility(state, "cook_meat", 1000)
	check(cooked.ok and cooked.state.enclosure.meals.steak == 1 and cooked.state.enclosure.materials.raw_meat == 5 and cooked.state.enclosure.materials.wood == 49, "cooking consumes ingredient and fuel and saves meal")
	check(not EnclosureRules.use_facility(before, "cook_meat", 1000).ok, "cooking requires campfire")
	state.care.fatigue = 70
	state.care.virus = 10
	var pond := EnclosureRules.use_facility(state, "pond", 1000)
	check(pond.ok and pond.state.care.fatigue == 45 and pond.state.care.virus == 7, "pond restores fatigue and rinses")
	check(not EnclosureRules.use_facility(pond.state, "pond", 1001).ok, "pond cooldown cannot be spammed")
	check(EnclosureRules.use_facility(pond.state, "pond", 1060).ok, "pond ready after cooldown")
	state.care.status.sleeping = true
	check(not EnclosureRules.use_facility(state, "pond", 1000).ok, "sleep prevents facility use")
	state.care.status.sleeping = false
	state.care.discipline = 50
	state.care.potty_habit = 0
	check(CareRules.advance_time(state, 1900).care.poop_count == 0, "discipline alone enables reachable potty")
	var legacy := before.duplicate(true)
	legacy.battle.erase("mob_wins")
	legacy.erase("enclosure")
	for key: String in ["decor", "decor_owned"]:
		legacy.inventory[key].erase("campfire")
		legacy.inventory[key].erase("pond")
	var migrated := CareRules.migrate_state_v8(legacy)
	check(CareRules.state_is_valid(migrated), "real v8 shape migrates")
	migrated.enclosure.materials.wood = 0
	check(CareRules.migrate_state_v8(migrated).enclosure.materials.wood == 0, "migration never refills spent materials")
	var repository := SaveRepository.new("/tmp/enclosure-%d.json" % Time.get_ticks_usec())
	check(repository.save_state(pond.state), "new state saves")
	var loaded := repository.load_state()
	check(loaded.ok and int(loaded.state.enclosure.materials.wood) == int(pond.state.enclosure.materials.wood) and float(loaded.state.enclosure.pond_ready_at) == 1060.0 and loaded.state.habitat.items.size() == 3, "materials buildings and cooldown survive reload")
	repository.clear()
	var manifest := {"assetId": "habitat-canopy-clearing", "revision": "fallback-v1", "blockers": []}
	var trees := EnclosureRules.placement_manifest(before.habitat, manifest)
	var clearing: Dictionary = before.habitat.duplicate(true)
	clearing.items = [item("campfire", 8, 11)]
	check(EnclosureRules.quote(before, clearing, trees).ok, "building over native tree is allowed")
	var resolved := EnclosureRules.placement_manifest(clearing, trees)
	check(not resolved.nativeTrees.any(func(t: Dictionary) -> bool: return t.id == "InteriorOakWest"), "overlapping native tree is suppressed")
	bad = before.duplicate(true)
	bad.enclosure.materials.wood = -1
	check(not CareRules.state_is_valid(bad), "negative materials rejected")
	var rotated := item("pond", 10, 10)
	rotated.rotation = 1
	check(HabitatRules.footprint(rotated).size() == 48 and HabitatRules.facility_entrance(rotated) == Vector2i(9, 13), "rotated pond preserves area and rotates its entrance")
	var two: Dictionary = state.habitat.duplicate(true)
	two.items.append(item("campfire", 30, 30, "second-fire"))
	two.creature_cell = [32, 34]
	check(HabitatRules.path_to_facility(two, "campfire").size() == 1, "nearest of multiple facilities is selected")
	var old := before.duplicate(true)
	old.battle.erase("mob_wins")
	old.habitat.items = [item("digi_potty",17,24),item("campfire",22,24),item("pond",18,19)]
	old.inventory.decor.digi_potty = 0
	old.inventory.decor_owned.campfire = 1
	old.inventory.decor_owned.pond = 1
	old.enclosure.materials.wood = 17
	check(HabitatRules.validate_layout(old.habitat,Vector2i(-1,-1),{},true).ok, "v9 fixture uses authentic small footprints")
	var enlarged := CareRules.migrate_state_v9(old)
	check(not enlarged.is_empty() and CareRules.state_is_valid(enlarged), "v9 crowded placement migrates to valid larger geometry")
	check(enlarged.habitat.items.size() == 3 and enlarged.enclosure.materials.wood == 17 and enlarged.inventory.decor_owned == old.inventory.decor_owned, "enlargement preserves objects ownership and spent materials")
	check(enlarged.habitat.creature_cell == old.habitat.creature_cell and enlarged.habitat.camera == old.habitat.camera, "migration never moves companion or camera")
	check(CareRules.migrate_state_v9(enlarged) == enlarged, "enlargement is idempotent")
	var old_text := JSON.stringify({"schemaVersion":9,"savedAt":1000,"companion":old})
	var old_file := FileAccess.open(repository.primary_path,FileAccess.WRITE)
	old_file.store_string(old_text)
	old_file.close()
	var loaded_old := repository.load_state()
	check(loaded_old.ok and CareRules.state_is_valid(loaded_old.state) and loaded_old.state.habitat.items.size() == 3 and loaded_old.state.enclosure.materials.wood == 17, "v9 envelope loads through repository with enlarged facilities")
	repository.clear()
	print("Enclosure: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
