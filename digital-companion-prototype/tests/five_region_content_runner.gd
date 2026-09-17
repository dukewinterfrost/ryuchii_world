extends SceneTree

## Loads every non-promoted package through the real presentation runtime.
## No catalog activation, save mutation, approval, or promotion occurs.

var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var index := AssetResourceLibrary.read_json("res://tests/fixtures/regions/index.json")
	_check(index.get("schemaVersion") == 1 and index.get("status") == "pending-human-review",
		"five-region index is explicit non-promoted review content")
	_check(index.get("aliases", {}).get("forest") == "green-shade" and
		index.get("aliases", {}).get("forest-arena") == "green-shade",
		"forest compatibility aliases resolve to Green Shade")
	var regions: Dictionary = index.get("regions", {})
	_check(regions.size() == 5, "five stable region records exist")
	for region_id: String in regions:
		var record: Dictionary = regions[region_id]
		var environment_folder := "res://" + String(record.environment.path)
		var view := EnvironmentView3D.new()
		view.size = Vector2i(390, 844)
		root.add_child(view)
		await process_frame
		_check(view.configure_from_folder(environment_folder), region_id + " raw package renders")
		if view.environment_manifest.is_empty():
			view.free()
			continue
		_check(view.environment_manifest.presentationProfile.get("id") ==
			EnvironmentPresentationContract.PROFILE_ID, region_id + " pins canonical profile")
		_check(view.environment_manifest.planeStacks[0].planes.size() >= 3,
			region_id + " landmark has at least three planes")
		var movement: Array = view.environment_manifest.camera.movementBounds
		_check(movement.size() == 4 and int(movement[0]) == 0 and int(movement[1]) == 0 and
			int(movement[2]) == 1280 and int(movement[3]) == 1536,
			region_id + " uses 40x48-cell movement bounds")
		for viewpoint: String in ["center", "left", "right", "near", "far"]:
			_check(view.set_review_viewpoint(viewpoint), region_id + " exposes " + viewpoint + " review")
		view.clear_review_viewpoint()
		var habitat := AssetResourceLibrary.read_json("res://" + String(record.habitat.path))
		_check(int(habitat.grid.columns) == 40 and int(habitat.grid.rows) == 48 and
			int(habitat.grid.cellSize) == 32,
			region_id + " habitat is 40x48 at 32 ground units")
		_check(view.set_static_placements(habitat.staticPlacements, "habitat"),
			region_id + " habitat placements render without yaw")
		var route := view.build_depth_traversal_route(24.0)
		_check(route.size() >= 2 and view.route_segments_are_clear(route, 4.0),
			region_id + " builds a collision-clear depth traversal")
		var arena := AssetResourceLibrary.read_json("res://" + String(record.arena.path))
		_check(int(arena.ground.width) == 960 and int(arena.ground.height) == 1152 and
			int(arena.ground.cellSize) == 32,
			region_id + " arena is 30x36 at 32 ground units")
		_check(BattleArena.validate(arena).is_empty(), region_id + " arena passes runtime geometry validation")
		_check(view.set_static_placements(arena.presentation.staticPlacements, "arena"),
			region_id + " arena presentation uses the same plane stack")
		var stats := view.instrumentation()
		_check(stats.withinRuntimeBounds, region_id + " presentation stays inside runtime limits")
		view.free()
		await process_frame
	_check(index.get("encounters", {}).size() == 5, "five contextual encounter IDs are indexed")
	for failure: String in failures:
		printerr("FAIL: " + failure)
	print("%s: %d five-region content checks" % ["PASS" if failures.is_empty() else "FAIL", checks])
	quit(0 if failures.is_empty() else 1)


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
