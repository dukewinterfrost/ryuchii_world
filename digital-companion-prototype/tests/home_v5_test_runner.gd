extends SceneTree

const Rules = preload("res://scripts/core/care_rules.gd")
const Habitat = preload("res://scripts/core/habitat_rules.gd")
const Repository = preload("res://scripts/core/save_repository.gd")
const State = preload("res://scripts/core/game_state.gd")
const HabitatLibrary = preload("res://scripts/environment/habitat_asset_library.gd")

var checks := 0
var failures := 0


func _initialize() -> void:
	_test_new_state_and_aliases()
	_test_v4_migration_and_repository()
	_test_unlock_switch_and_inventory()
	_test_entitlement_integrity()
	_test_authoritative_manifest_automatic_care()
	_test_map_routes()
	print("%s: %d home v5 checks" % ["PASS" if failures == 0 else "FAIL", checks])
	quit(0 if failures == 0 else 1)


func _test_new_state_and_aliases() -> void:
	var state := Rules.make_new_state(1000.0)
	_check(Rules.SAVE_SCHEMA_VERSION == 6 and Rules.state_is_valid(state), "new saves use strict schema v6 with v5 regional layouts")
	_check(state.home_region == "green-shade" and state.habitats.is_empty(), "Green Shade is the only initial home layout")
	_check(state.progression.story_flags == Habitat.default_story_flags(), "future region story flags start locked")
	_check(state.inventory.decor_owned == state.inventory.decor, "new saves persist exact starter decoration entitlements")
	_check(Habitat.resolve_region_alias("forest") == "green-shade" and Habitat.resolve_region_alias("forest-arena") == "green-shade", "forest compatibility aliases resolve to Green Shade")
	_check(Habitat.grid_size() == Vector2i(40, 48) and state.habitat.creature_cell == [20, 24], "home simulation uses the 40x48 centered grid")


func _test_v4_migration_and_repository() -> void:
	var legacy := Rules.make_new_state(1000.0)
	legacy.care.erase("food")
	legacy.erase("home_region")
	legacy.erase("habitats")
	legacy.progression.erase("story_flags")
	legacy.habitat = Habitat.default_layout(Vector2i(10, 12))
	legacy.habitat.items = [{"instance_id": "legacy-planter", "item_id": "planter", "x": 2, "y": 3, "rotation": 0}]
	legacy.inventory.decor.planter = 0
	var migrated := Rules.migrate_state_v4(legacy)
	_check(Rules.state_is_valid(migrated), "v4 state migrates to valid v5")
	_check(migrated.habitat.creature_cell == [20, 24] and migrated.habitat.items[0].x == 12 and migrated.habitat.items[0].y == 15, "legacy habitat content moves intact into Green Shade center")
	_check(migrated.inventory.decor.planter == 0 and migrated.home_region == "green-shade", "migration preserves inventory accounting and assigns Green Shade")
	_check(migrated.inventory.decor_owned.planter == 1, "v4 migration conservatively infers placed plus unplaced ownership")
	var repository := Repository.new("/tmp/home-v5-%d.json" % Time.get_ticks_usec())
	repository.clear()
	var encoded := JSON.stringify({"schemaVersion": 4, "savedAt": 1000.0, "companion": legacy})
	var file := FileAccess.open(repository.primary_path, FileAccess.WRITE)
	file.store_string(encoded)
	file.close()
	var loaded := repository.load_state()
	_check(loaded.ok and loaded.migrated and Rules.state_is_valid(loaded.state), "repository upgrades a v4 primary through the v5 migration")
	_check(FileAccess.get_file_as_string(repository.backup_path) == encoded, "v4 bytes remain available as the rollback generation")
	repository.clear()
	var early_v5 := Rules.make_new_state(1000.0)
	early_v5.care.erase("food")
	early_v5.habitat.items = [{"instance_id": "early-rug", "item_id": "rug", "x": 4, "y": 4, "rotation": 0}]
	early_v5.inventory.decor.rug = 0
	early_v5.inventory.erase("decor_owned")
	repository = Repository.new("/tmp/home-early-v5-%d.json" % Time.get_ticks_usec())
	repository.clear()
	encoded = JSON.stringify({"schemaVersion": 5, "savedAt": 1000.0, "companion": early_v5})
	file = FileAccess.open(repository.primary_path, FileAccess.WRITE)
	file.store_string(encoded)
	file.close()
	loaded = repository.load_state()
	_check(loaded.ok and loaded.migrated and loaded.state.inventory.decor_owned.rug == 1, "early v5 saves missing entitlements migrate losslessly")
	_check(FileAccess.get_file_as_string(repository.backup_path) == encoded, "early v5 bytes remain available as the rollback generation")
	repository.clear()


func _test_unlock_switch_and_inventory() -> void:
	var game := State.new()
	game.state = Rules.make_new_state(1000.0)
	game._repository = Repository.new("/tmp/home-switch-%d.json" % Time.get_ticks_usec())
	game._repository.clear()
	_check(not game.select_home_region("shellfish-beach").ok, "production cannot select a locked home")
	_check(game.grant_story_flag("story.region.shellfish_beach").ok, "story hook unlocks Shellfish Beach")
	var switched := game.select_home_region("shellfish-beach")
	_check(switched.ok and switched.package.mode == "fallback-2d" and game.state.home_region == "shellfish-beach", "unlocked region selects with deterministic 2D fallback while unapproved")
	var beach: Dictionary = game.state.habitat.duplicate(true)
	beach.items = [{"instance_id": "beach-planter", "item_id": "planter", "x": 22, "y": 24, "rotation": 0}]
	_check(game.apply_habitat_layout(beach).ok and game.state.inventory.decor.planter == 0, "placing decor in one home consumes global inventory once")
	_check(game.select_home_region("forest-arena").ok and game.state.home_region == "green-shade", "legacy arena alias selects the Green Shade home")
	var green: Dictionary = game.state.habitat.duplicate(true)
	green.items = [{"instance_id": "forged-planter", "item_id": "planter", "x": 18, "y": 24, "rotation": 0}]
	_check(not game.apply_habitat_layout(green).ok, "decor stored in another home cannot be duplicated")
	_check(game.select_home_region("shellfish-beach").ok and game.state.habitat.items[0].instance_id == "beach-planter", "returning to a region restores its independent layout")
	beach = game.state.habitat.duplicate(true)
	beach.items = []
	_check(game.apply_habitat_layout(beach).ok and game.state.inventory.decor.planter == 1, "removing regional decor returns exactly one global inventory item")
	_check(game.select_home_region("green-shade").ok and Rules.state_is_valid(game.state), "multi-region state remains valid after repeated switches")
	game._repository.clear()
	game.free()


func _test_entitlement_integrity() -> void:
	var forged_gain := Rules.make_new_state(1000.0)
	forged_gain.habitat.items = [{"instance_id": "forged-planter", "item_id": "planter", "x": 5, "y": 5, "rotation": 0}]
	_check(not Rules.state_is_valid(forged_gain), "a forged placed decoration without inventory debit is rejected")
	var forged_loss := Rules.make_new_state(1000.0)
	forged_loss.inventory.decor.planter = 0
	_check(not Rules.state_is_valid(forged_loss), "silent decoration loss is rejected against persisted ownership")
	var duplicate_regions := Rules.make_new_state(1000.0)
	duplicate_regions.progression.story_flags["story.region.shellfish_beach"] = true
	duplicate_regions.habitat.items = [{"instance_id": "same-id", "item_id": "rug", "x": 4, "y": 4, "rotation": 0}]
	duplicate_regions.inventory.decor.rug = 0
	var beach := Habitat.default_layout(Vector2i(18, 20))
	beach.items = [{"instance_id": "same-id", "item_id": "rug", "x": 12, "y": 12, "rotation": 0}]
	duplicate_regions.habitats["shellfish-beach"] = beach
	duplicate_regions.inventory.decor_owned.rug = 2
	_check(not Rules.state_is_valid(duplicate_regions), "duplicate instance identities across regions are rejected even when totals balance")


func _test_authoritative_manifest_automatic_care() -> void:
	var game := State.new()
	game.state = Rules.make_new_state(1000.0)
	game._repository = Repository.new("/tmp/home-potty-manifest-%d.json" % Time.get_ticks_usec())
	game._repository.clear()
	game.state.habitat.items = [{"instance_id": "potty", "item_id": "digi_potty", "x": 3, "y": 3, "rotation": 0}]
	game.state.inventory.decor.digi_potty = 0
	game.state.care.potty_habit = 60.0
	game.state.care.discipline = 50.0
	var verified := HabitatLibrary.fallback_manifest("green-shade")
	verified.blockers = [{"id": "sealed-potty-entrance", "rect": [3, 5, 1, 1]}]
	game._home_package = {"region_id": "green-shade", "mode": "verified-habitat-2d", "habitat": verified, "environment_package": {}}
	_check(not Habitat.path_to_potty(game.state.habitat).is_empty(), "generic geometry would permit the automatic potty route")
	game.advance_care_time(900.0, false, 1900.0)
	_check(game.state.care.poop_count == 1, "GameState time advancement honors the active manifest blocker")
	game._repository.clear()
	game.free()


func _test_map_routes() -> void:
	var fallback := HabitatLibrary.fallback_manifest("green-shade")
	var layout := Habitat.default_layout_for_manifest(fallback)
	for goal: Vector2i in [Vector2i(0, 0), Vector2i(39, 0), Vector2i(0, 47), Vector2i(39, 47)]:
		_check(not Habitat.path_between_cells(layout, Vector2i(20, 24), goal, fallback).is_empty(), "fallback route reaches %s" % goal)
	_check(Habitat.all_free_cells_reachable(layout, fallback), "fallback home has one connected walkable region")
	var index := AssetResourceLibrary.read_json(HabitatLibrary.DEV_INDEX)
	_check(index.get("schemaVersion") == 1 and index.get("regions") is Dictionary, "five-region review index is present")
	if not index.get("regions") is Dictionary:
		return
	for region_id: String in Habitat.REGION_IDS:
		var record: Variant = index.regions.get(region_id)
		_check(record is Dictionary, "%s review record exists" % region_id)
		if not record is Dictionary:
			continue
		var path := HabitatLibrary._dev_resource_path(String(record.get("habitat", {}).get("path", "")))
		var manifest := AssetResourceLibrary.read_json(path)
		_check(HabitatLibrary.validate_manifest(manifest, Habitat.REGION_HOMES[region_id].habitat_id), "%s habitat manifest and routes validate" % region_id)
		var regional_layout := Habitat.default_layout_for_manifest(manifest)
		for anchor: Vector2i in Habitat.waste_anchors(manifest):
			_check(not Habitat.path_between_cells(regional_layout, Vector2i(int(manifest.spawn[0]), int(manifest.spawn[1])), anchor, manifest).is_empty(), "%s waste anchor %s is reachable" % [region_id, anchor])


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)
