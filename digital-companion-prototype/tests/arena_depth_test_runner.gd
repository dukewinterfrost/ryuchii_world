extends SceneTree

## Synthetic, in-memory geometry/artwork only. No catalog or companion save I/O.
var checks := 0
var failures: Array[String] = []
var gpu := false
var capture := false

class ActorMarker extends Node2D:
	func _draw() -> void:
		draw_rect(Rect2(-10, -32, 20, 32), Color.RED)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	gpu = "--gpu" in OS.get_cmdline_user_args()
	capture = "--capture" in OS.get_cmdline_user_args()
	if gpu and DisplayServer.get_name() == "headless":
		_check(false, "GPU pixel verification requires a real rendering display")
	else:
		for projection: String in ["square", "isometric"]:
			await _test_projection(projection)
	for failure: String in failures:
		printerr("FAIL: " + failure)
	print("%s: %d arena depth checks%s" % ["PASS" if failures.is_empty() else "FAIL", checks, " (GPU pixels verified)" if gpu else " (headless structure)"])
	quit(0 if failures.is_empty() else 1)


func _manifest(projection: String) -> Dictionary:
	return {"schemaVersion": 1, "kind": "arena", "assetId": "depth-fixture", "revision": "test-only",
		"projection": projection, "ground": {"width": 320, "height": 240, "cellSize": 40}, "maxBodyRadius": 16,
		"spawns": {"player": [60, 60], "opponent": [260, 180]},
		"tiles": [{"cell": [3, 2], "atlas": [0, 0], "alternative": 0}],
		"obstacles": [{"id": "tile-3-2", "tileDerived": true, "rect": [120, 80, 40, 40],
			"movement": false, "projectile": false, "sight": false, "occlusion": true}]}


func _test_projection(projection: String) -> void:
	var manifest := _manifest(projection)
	var original := manifest.duplicate(true)
	_check(BattleArena.validate(manifest).is_empty(), projection + " fixture uses valid shared arena geometry")
	var image := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	image.fill(Color.BLUE)
	var native := AssetResourceLibrary.build_tileset({"projection": projection, "tileSize": [16, 16],
		"tiles": [{"atlas": [0, 0], "alternative": 0, "collision": [], "navigation": [], "occlusion": [],
			"combat": {"cellSize": 40, "rect": [0, 0, 40, 40], "movement": false,
				"projectile": false, "sight": false, "occlusion": true}}]}, ImageTexture.create_from_image(image))
	_check(native.ok, projection + " synthetic native TileSet builds")
	if not native.ok:
		return
	var viewport := SubViewport.new()
	viewport.size = Vector2i(640, 360)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var view := ArenaView.new()
	viewport.add_child(view)
	# Inject the already-built resource, avoiding any fake catalog or disk bundle.
	# Production configure invokes the identical helper after loading its pin.
	var empty := manifest.duplicate(true)
	empty.tiles = []
	empty.obstacles = []
	view.configure(empty)
	view.arena = manifest.duplicate(true)
	view.tile_set = native.tileset
	view.position = Vector2(260, 30) if projection == "isometric" else Vector2(30, 30)
	view._rebuild_tile_visuals()
	var actor := ActorMarker.new()
	view.add_child(actor)
	_check(view._tile_visuals.size() == 1 and view._occluding_cells.has("tile-3-2"), projection + " explicit occlusion creates exactly one child tile")
	if view._tile_visuals.is_empty():
		viewport.free()
		return
	var visual: Node2D = view._tile_visuals[0]
	var anchor := Vector2(40, 140) if projection == "isometric" else Vector2(140, 120)
	_check(visual.position == anchor, projection + " visual root uses frontmost projected canonical footprint")
	_check(view.y_sort_enabled and visual.z_index == actor.z_index and visual.get_parent() == actor.get_parent(), projection + " tiles and actors share the same Y-sort group")
	_check(visual.display_rect.position + visual.position == view._tile_display_rect(manifest.tiles[0]).position,
		projection + " moving draw to child preserves exact atlas placement")
	_check(view.arena == original and manifest == original, projection + " building visuals cannot mutate input or simulation geometry")
	for flag: String in ["movement", "projectile", "sight"]:
		_check(BattleArena.segment_clear(view.arena, [110000, 100000], [170000, 100000], 14000, flag),
			projection + " visual canopy does not become a " + flag + " blocker")
	actor.position = anchor + Vector2(0, -2)
	_check(actor.position.y < visual.position.y, projection + " behind actor sorts below canopy")
	if gpu:
		await _verify_pixel(viewport, view, projection, "behind", Color.BLUE)
	actor.position = anchor + Vector2(0, 2)
	_check(actor.position.y > visual.position.y, projection + " front actor sorts above canopy")
	if gpu:
		await _verify_pixel(viewport, view, projection, "front", Color.RED)
	view._rebuild_tile_visuals()
	_check(not is_instance_valid(visual) and view._tile_visuals.size() == 1, projection + " rebuilding replaces owned tile without duplication")
	visual = view._tile_visuals[0]
	view.arena.obstacles[0].occlusion = false
	view._rebuild_tile_visuals()
	_check(not is_instance_valid(visual) and view._tile_visuals.is_empty() and view._occluding_cells.is_empty(), projection + " occlusion false keeps tile in ground pass")
	actor.position = anchor + Vector2(0, -2)
	if gpu:
		await _verify_pixel(viewport, view, projection, "ground", Color.RED)
	for flag: String in ["movement", "projectile", "sight"]:
		view.arena.obstacles[0][flag] = true
	view._rebuild_tile_visuals()
	_check(view._tile_visuals.is_empty(), projection + " physical blocking flags do not imply visual occlusion")
	view.arena.obstacles[0].occlusion = true
	view._rebuild_tile_visuals()
	visual = view._tile_visuals[0]
	view.configure(empty)
	_check(not is_instance_valid(visual) and view._tile_visuals.is_empty() and view._occluding_cells.is_empty(), projection + " reconfigure releases owned tile visuals")
	_check(is_instance_valid(actor) and actor.get_parent() == view, projection + " reconfigure does not free scene-owned fighters")
	viewport.free()
	await process_frame
	_check(not is_instance_valid(actor), projection + " viewport teardown releases remaining scene nodes")


func _verify_pixel(viewport: SubViewport, view: ArenaView, projection: String, phase: String, expected: Color) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	_check(image != null and not image.is_empty(), projection + " " + phase + " GPU frame is readable")
	if image == null or image.is_empty():
		return
	var location := view.position + view.project(Vector2(140, 100))
	var actual := image.get_pixel(int(location.x), int(location.y))
	_check(actual.is_equal_approx(expected), "%s %s actual overlapping pixel %s equals %s" % [projection, phase, actual, expected])
	if capture:
		var folder := ProjectSettings.globalize_path("res://work/sprites/qa")
		DirAccess.make_dir_recursive_absolute(folder)
		var path := folder.path_join("arena-depth-%s-%s.png" % [projection, phase])
		_check(image.save_png(path) == OK, "GPU capture saved: " + path)


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
