extends SceneTree
## Isolated real-care review: original BG-1 bytes, four edges and clock lighting.
var checks := 0
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func run() -> void:
	var game := root.get_node("GameState")
	if not game.isolated_mode:
		quit(1)
		return
	game.set_process(false)
	game._home_package = HabitatAssetLibrary.resolve_region("green-shade", false)
	var baseline: Dictionary = game.state.duplicate(true)
	var care: Node = load("res://scenes/care_scene.tscn").instantiate()
	root.add_child(care)
	care.habitat.set_process(false)
	# Capture after normal care initialization; then all tested operations are
	# presentation-only, with the simulation explicitly paused.
	baseline = game.state.duplicate(true)
	var view: EnvironmentView3D = care.habitat.environment_3d
	var wrap: Node3D = view._native_parallax
	check(wrap.home_oval_layout and not wrap.get_node("Boundary").visible, "Care uses its own oval, not the old rectangular hedge rows")
	var oval: Node3D = wrap.get_node("OvalLayout")
	var radii: Vector2 = oval.get_meta("inner_radii")
	check(radii.x > radii.y and radii.x > 20, "Clearing is wider left-right and larger than the old base")
	var grass := oval.get_node("GrassDetails").get_children()
	check(grass.size() == 54, "Middle foliage combines eight unequal clusters and sparse singles")
	var plant_types: Dictionary = {}
	var smallest := INF
	var largest := 0.0
	var close_neighbors := 0
	var isolated_plants := 0
	for tuft: Sprite3D in grass:
		check(tuft.pixel_size <= 0.0034 and not tuft.no_depth_test, "Middle foliage remains low and depth-tested")
		plant_types[tuft.region_rect] = true
		smallest = minf(smallest, tuft.pixel_size)
		largest = maxf(largest, tuft.pixel_size)
		var ground := Vector2(tuft.position.x, tuft.position.z) * (4.0 / 3.0)
		check(absf(ground.x - (20.5 + sin(ground.y * 0.19) * 1.7)) > 3.19, "Grass does not crowd the footpath")
		check(((ground - Vector2(20.5, 24.5)) / Vector2(7, 4.5)).length() > 0.99, "Resting spot remains open")
		var nearest := INF
		for other: Sprite3D in grass:
			if other != tuft:
				nearest = minf(nearest, tuft.position.distance_to(other.position))
		if nearest < 1.5: close_neighbors += 1
		if nearest > 2.8: isolated_plants += 1
	check(plant_types.size() >= 2 and largest / smallest > 2.5, "Plant silhouettes and sizes vary, rather than repeating one tuft")
	check(close_neighbors >= 20 and isolated_plants >= 5, "Layout has dense clusters and sparse pockets, not evenly jittered rows")
	check(FileAccess.get_sha256("res://assets/environment_workshop/forest-parallax/foliage.png") == "ee0ed7a9f64646e8205801b671ba06591fa587f7dc79efc1ede5efb390c9743f", "Foliage source bytes remain unchanged")
	var boundary: Node3D = oval.get_node("Boundary")
	var ring_count := 0
	var nearest_rim := INF
	var farthest_rim := 0.0
	for card: Sprite3D in boundary.get_children():
		if int(card.get_meta("ring", -1)) == 0:
			var normalized := (Vector2(card.position.x, card.position.z) - Vector2(15, 18)) / radii
			check(absf(normalized.length() - 1.0) < 0.16, "Inner foliage retains the wider oval envelope")
			nearest_rim = minf(nearest_rim, normalized.length())
			farthest_rim = maxf(farthest_rim, normalized.length())
			ring_count += 1
	check(ring_count == 64, "The oval has a complete 64-card inner foliage ring")
	check(farthest_rim - nearest_rim > 0.2, "Forest edge has asymmetric pockets and protrusions, not a manicured ring")
	for source: Array in [["reference", "371b65b3612683184030affcb8bdfe190df533ff78034ddcdc91099e6826da19"], ["distant", "537f2a74f01cdcf16c8bfa23bdc9854869717134ccdef3a2d6d1cde0d94a1f63"], ["middle", "7e699e3662a89787c75df7a020881e73a767f29e240cf2c1973c6ee3704c93a6"], ["foreground", "e6b4f554fafec70e5f1971695ff49cef8f22099936351cbcaf8ceeb9bd5fd2c7"]]:
		check(FileAccess.get_sha256("res://assets/environment_workshop/forest-bg1/%s.png" % source[0]) == source[1], "Exact BG-1 source bytes: " + source[0])
	check(wrap.get_node("Sky").texture.resource_path.ends_with("forest-bg1/distant.png"), "Home uses BG-1 distant layer")
	check(wrap.get_node("ForestVista").texture.resource_path.ends_with("forest-bg1/middle.png"), "Home uses BG-1 alpha middle layer")
	check(wrap.get_node("BackgroundMeadow").texture.resource_path.ends_with("forest-bg1/foreground.png"), "Home uses BG-1 foreground layer")
	for side: String in ["North", "South", "West", "East"]:
		check(boundary.find_children(side + "_*", "Sprite3D", false, false).size() >= 24, side + " has overlapping inner and outer foliage")
	for card: Sprite3D in boundary.get_children():
		check(card.position.x < 0 or card.position.x > 30 or card.position.z < 0 or card.position.z > 36, "Boundary roots remain outside playable cells")
		check(not card.no_depth_test and card.alpha_cut == SpriteBase3D.ALPHA_CUT_DISCARD, "Boundary cutouts write/test depth")
	var capture := "--capture" in OS.get_cmdline_user_args()
	for target: Vector2i in [Vector2i(360,640),Vector2i(390,844),Vector2i(430,932),Vector2i(1280,720)]:
		root.content_scale_size = target
		root.size = target
		await process_frame
		care._set_map_view(true)
		view.set_process(false)
		for angle: String in ["center", "north", "south", "west", "east", "overview"]:
			var delta := Vector2.ZERO
			if angle == "north": delta.y = -768
			if angle == "south": delta.y = 768
			if angle == "west": delta.x = -640
			if angle == "east": delta.x = 640
			view.set_home_zoom_multiplier(0.0 if angle == "overview" else 0.65, true)
			view.set_home_manual_pan(delta, true)
			view.day_night.clock.set_preview_hour(12)
			for frame: int in 3: await process_frame
			var camera := view.camera
			var sky_depth := -camera.to_local(wrap.get_node("Sky").global_position).z
			check(sky_depth > camera.near and sky_depth < camera.far, "BG-1 backdrop stays within the enlarged overview camera's clipping range")
			var ground: MeshInstance3D = view._terrain_root.get_node("CareClearing/Ground")
			for screen_x: float in [0.0, float(view.world_viewport.size.x)]:
				var screen_point := Vector2(screen_x, view.world_viewport.size.y)
				var hit: Variant = Plane(Vector3.UP, 0).intersects_ray(camera.project_ray_origin(screen_point), camera.project_ray_normal(screen_point))
				check(hit is Vector3 and ground.mesh.get_aabb().grow(0.01).has_point(ground.to_local(hit)), "Foreground terrain covers both bottom corners without exposing its edge")
			for card: Sprite3D in wrap._foreground_cards:
				var height := card.region_rect.size.y * card.pixel_size * card.global_basis.get_scale().y
				check(card.visible == (-camera.to_local(card.global_position).z > height * 1.7), "Foreground clearance follows current camera")
			if capture:
				RenderingServer.force_draw(false)
				view.world_viewport.get_texture().get_image().save_png("/tmp/bg1-%s-%dx%d.png" % [angle,target.x,target.y])
		view.set_home_manual_pan(Vector2.ZERO, true)
		view.set_home_zoom_multiplier(0.45, true)
		for hour: float in [6, 12, 18, 0]:
			view.day_night.clock.set_preview_hour(hour)
			await process_frame
			if capture:
				RenderingServer.force_draw(false)
				view.world_viewport.get_texture().get_image().save_png("/tmp/bg1-time-%02d-%dx%d.png" % [int(hour),target.x,target.y])
	for key: String in baseline:
		if key == "habitat":
			for field: String in baseline.habitat:
				# Existing Field UI deliberately saves camera preferences. Scenery
				# must not change navigation, items, companion or gameplay state.
				if field != "camera":
					check(game.state.habitat.get(field) == baseline.habitat[field], "Unchanged gameplay habitat field: " + field)
		else:
			check(game.state[key] == baseline[key], "Unchanged simulation field: " + key)
	care.free()
	print("BG-1 wrap: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
