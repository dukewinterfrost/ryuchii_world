extends SceneTree

var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var game_script := load("res://scripts/core/game_state.gd")
	_check(game_script.is_review_launch(PackedStringArray(["--path", "/project", "res://scenes/asset_review_scene.tscn"])), "direct review scene launch isolates before repository access without a custom flag")
	_check(not game_script.is_review_launch(PackedStringArray(["--path", "/project", "res://scenes/care_scene.tscn"])), "normal care scene still uses persistent state")
	var image := Image.create(32, 16, false, Image.FORMAT_RGBA8)
	image.fill(Color.CORAL)
	var texture := ImageTexture.create_from_image(image)
	var atlas := {"frames": {"a": {"frame": {"x": 0, "y": 0, "w": 16, "h": 16}}, "b": {"frame": {"x": 16, "y": 0, "w": 16, "h": 16}}}, "meta": {"size": {"w": 32, "h": 16}}}
	var clip := {"kind": "loop", "events": [{"name": "release", "frame": 1}], "frames": [{"atlasFrame": "a", "durationMs": 100, "pivot": {"x": 0.5, "y": 1.0}, "anchors": {"root": {"x": 0.5, "y": 1.0}}}, {"atlasFrame": "b", "durationMs": 300, "pivot": {"x": 0.5, "y": 1.0}}]}
	var manifest := {"revision": "test", "clips": {"idle.default": clip, "idle.alert": clip, "move.ne": clip, "move.nw": clip}, "fallbacks": {"special_attack.e": "move.ne"}}
	var loaded := CompanionAssetLibrary.build_from_manifests(atlas, manifest, texture)
	_check(not loaded.is_empty(), "valid animation builds")
	_check(loaded.frames.has_animation("move.ne") and loaded.frames.has_animation("move.nw"), "directional clip names are retained")
	_check(loaded.frames.has_animation("idle.default") and loaded.frames.has_animation("idle"), "explicit default alias preserves care callers")
	_check(is_equal_approx(loaded.frames.get_frame_duration("move.ne", 1) / loaded.frames.get_animation_speed("move.ne"), 0.3), "authored frame durations preserved")
	var fast_frame := manifest.duplicate(true)
	fast_frame.clips["move.ne"].frames[0].durationMs = 1
	var fast_loaded := CompanionAssetLibrary.build_from_manifests(atlas, fast_frame, texture)
	_check(is_equal_approx(fast_loaded.frames.get_frame_duration("move.ne", 0) / fast_loaded.frames.get_animation_speed("move.ne"), 0.001), "one millisecond authored duration is not silently clamped")
	_check(loaded.anchors["move.ne"][0].has("root") and loaded.events["move.ne"].size() == 1, "anchors and events preserved as metadata")
	var collision := manifest.duplicate(true)
	collision.clips["idle"] = clip
	_check(not CompanionAssetLibrary.validate_manifest(atlas, collision, texture.get_size()).is_empty(), "actual default alias collision rejected")
	var missing := manifest.duplicate(true)
	missing.requiredActions = ["move"]
	missing.requiredFacings = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
	_check(CompanionAssetLibrary.validate_manifest(atlas, missing, texture.get_size()).size() == 6, "all eight required facings validated")
	var avatar := CompanionAvatar.new()
	root.add_child(avatar)
	avatar.configure_library(loaded)
	avatar.position = Vector2(12, 34)
	avatar.render_combat("move", "NW", 6, 12)
	_check(avatar.sprite.animation == &"move.nw" and not avatar.sprite.flip_h, "directional source not implicitly mirrored")
	_check(avatar.sprite.frame == 1 and not avatar.sprite.is_playing(), "authoritative action timing samples paused frames")
	_check(avatar.position == Vector2(12, 34), "avatar cannot move simulation root")
	_check(avatar.sprite.offset == Vector2(0, -8), "feet pivot remains on root")
	avatar.render_combat("special_attack", "W", 0, 30)
	_check(not avatar.visual_fallback.is_empty(), "legacy artwork fallback explicitly reported")
	avatar.render_combat("special_attack", "E", 0, 30)
	_check(avatar.sprite.animation == &"move.ne" and avatar.visual_fallback.begins_with("Authored fallback:"), "explicit authored fallback is respected before generic legacy fallback")
	avatar.render_combat("idle.alert", "E", 0, 30)
	_check(avatar.sprite.animation == &"idle.alert", "full non-directional clip variant can be sampled")
	avatar.free()
	var directional_only := CompanionAssetLibrary.build_from_manifests(atlas, {"revision": "new-combat", "motionProfile": {"facing": "eight-direction"}, "clips": {"idle.e": clip, "move.ne": clip}}, texture)
	var curated := CompanionAssetLibrary.build_folder("res://assets/companions/agumon")
	var pinned_legacy := CompanionAssetLibrary.build_pinned("agumon", curated.asset_id, curated.revision)
	_check(not pinned_legacy.is_empty() and pinned_legacy.revision == curated.revision and pinned_legacy.asset_id == "agumon", "pinned legacy artwork resolves exact recorded identity and revision")
	var composed := CompanionAssetLibrary.with_legacy_care(directional_only, curated)
	_check(composed.frames.has_animation("eat") and composed.frames.get_frame_count("eat") == curated.frames.get_frame_count("eat"), "combat-only runtime set retains actual curated eat frames")
	_check(composed.frames.get_frame_texture("eat", 0) == curated.frames.get_frame_texture("eat", 0) and composed.clip_provenance.eat.revision == curated.revision, "composed legacy care art keeps source texture and explicit revision provenance")
	_check(not directional_only.frames.has_animation("eat") and not composed.manifest.clips.has("eat.default"), "care composition cannot modify candidate source or claim added directional coverage")
	avatar = CompanionAvatar.new()
	root.add_child(avatar)
	avatar.configure_library(composed)
	avatar.render_combat("move", "NE", 1, 12)
	_check(avatar.sprite.animation == &"move.ne", "composed library prefers new directional combat clip")
	avatar.play_action("eat")
	_check(avatar.sprite.animation == &"eat" and avatar._active_action == "eat", "composed care action retains real eat playback and completion signal action")
	avatar.free()
	var square := [[-8, -8], [8, -8], [8, 8], [-8, 8]]
	var tile := {"atlas": [0, 0], "alternative": 0, "probability": 1.0, "collision": [square], "navigation": [square], "occlusion": [square], "customData": {"walkable": false}, "combat": {"cellSize": 20, "rect": [0, 0, 20, 20], "movement": true, "projectile": true, "sight": false, "occlusion": true}}
	var tile_manifest := {"projection": "square", "tileSize": [16, 16], "tiles": [tile], "customDataLayers": [{"name": "walkable", "type": "bool"}], "terrains": []}
	var result := AssetResourceLibrary.build_tileset(tile_manifest, texture)
	_check(result.ok, "square TileSet builds from explicit geometry")
	if result.ok:
		var data: TileData = result.tileset.get_source(0).get_tile_data(Vector2i.ZERO, 0)
		_check(data.get_collision_polygons_count(0) == 1, "native collision exported")
		_check(data.get_navigation_polygon(0).get_polygon_count() == 2, "navigation triangulated deterministically")
		_check(data.get_occluder_polygons_count(0) == 1, "native occlusion exported")
		_check(data.get_custom_data("walkable") == false, "custom layer values retained")
		var target := OS.get_cache_dir().path_join("godot-native-fixture-%d.tres" % OS.get_process_id())
		AssetResourceLibrary.assign_stable_ids(result.tileset)
		_check(ResourceSaver.save(result.tileset, target, ResourceSaver.FLAG_RELATIVE_PATHS) == OK, "native resource saves")
		_check(ResourceLoader.load(target, "TileSet", ResourceLoader.CACHE_MODE_IGNORE) is TileSet, "embedded resource reloads outside project")
		var other := target.trim_suffix(".tres") + "-other.tres"
		var second := AssetResourceLibrary.build_tileset(tile_manifest, ImageTexture.create_from_image(image.duplicate()))
		AssetResourceLibrary.assign_stable_ids(second.tileset)
		ResourceSaver.save(second.tileset, other, ResourceSaver.FLAG_RELATIVE_PATHS)
		# Native compilation is headless. GPU ImageTexture readback returns fresh
		# Image objects; rendered QA below separately verifies two headless exports.
		if DisplayServer.get_name() == "headless":
			_check(FileAccess.get_file_as_string(target) == FileAccess.get_file_as_string(other), "fresh headless native builds have deterministic resource bytes")
		DirAccess.remove_absolute(target)
		DirAccess.remove_absolute(other)
	var isometric := tile_manifest.duplicate(true)
	isometric.projection = "isometric"
	var iso := AssetResourceLibrary.build_tileset(isometric, texture)
	_check(iso.ok and iso.tileset.tile_shape == TileSet.TILE_SHAPE_ISOMETRIC and iso.tileset.tile_layout == TileSet.TILE_LAYOUT_DIAMOND_DOWN, "isometric diamond-down projection exported")
	var alternative := tile.duplicate(true)
	alternative.alternative = 1
	alternative.probability = 0.25
	isometric.tiles.append(alternative)
	var alternatives := AssetResourceLibrary.build_tileset(isometric, texture)
	_check(alternatives.ok and is_equal_approx(alternatives.tileset.get_source(0).get_tile_data(Vector2i.ZERO, 1).probability, 0.25), "weighted alternatives preserved")
	var invalid := tile_manifest.duplicate(true)
	invalid.tiles[0].atlas = [99, 0]
	_check(not AssetResourceLibrary.build_tileset(invalid, texture).ok, "out-of-atlas tile rejected")
	invalid = tile_manifest.duplicate(true)
	invalid.tiles[0].navigation = [[[0, 0], [1, 1]]]
	_check(not AssetResourceLibrary.build_tileset(invalid, texture).ok, "malformed geometry rejected")
	invalid = tile_manifest.duplicate(true)
	invalid.tiles.append(tile)
	_check(not AssetResourceLibrary.build_tileset(invalid, texture).ok, "duplicate atlas alternative rejected")
	var collision_cases: Array = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/tilesets/combat-collision-cases.json"))
	var case_image := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	case_image.fill(Color.GREEN)
	for fixture: Dictionary in collision_cases:
		var built := AssetResourceLibrary.build_tileset(fixture.manifest, ImageTexture.create_from_image(case_image))
		_check(built.ok == fixture.expectedValid, "shared canonical combat validity: " + fixture.name)
		if fixture.expectedValid and built.ok:
			var canonical: Array = built.tileset.get_meta("source_manifest").tiles[0].collision
			_check(_same_polygons(canonical, fixture.expectedCollision), "shared square/isometric canonical movement geometry: " + fixture.name)
	await _candidate_roundtrip(image, atlas, manifest, tile_manifest)
	print("Asset resource checks: %d passed / %d total" % [checks - failures.size(), checks])
	for failure: String in failures:
		printerr("FAIL: " + failure)
	quit(0 if failures.is_empty() else 1)


func _candidate_roundtrip(image: Image, atlas: Dictionary, animation: Dictionary, tile_manifest: Dictionary) -> void:
	var base := OS.get_cache_dir().path_join("godot-asset-roundtrip-%d" % OS.get_process_id())
	var folders: Array[String] = [base + "-a", base + "-b"]
	for folder: String in folders:
		DirAccess.make_dir_recursive_absolute(folder)
		image.save_png(folder.path_join("atlas.png"))
		_json(folder.path_join("atlas.json"), atlas)
		_json(folder.path_join("animation-set.json"), animation)
		_json(folder.path_join("candidate.json"), {"kind": "animation", "assetId": "fixture", "revision": "test", "schemaVersion": 1})
		var output: Array = []
		var code := OS.execute(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--script", "res://scripts/assets/export_resources.gd", "--", "--asset-review", "--candidate", folder], output, true)
		_check(code == 0 and not str(output).contains("SCRIPT ERROR"), "standalone native exporter succeeds")
	_check(FileAccess.get_sha256(folders[0].path_join("spriteframes.tres")) == FileAccess.get_sha256(folders[1].path_join("spriteframes.tres")), "animation native builds identical across fresh processes and paths")
	_check(not FileAccess.get_file_as_string(folders[0].path_join("spriteframes.tres")).contains(base), "native resource does not capture candidate paths")
	var native := CompanionAssetLibrary.build_folder(folders[0])
	_check(not native.is_empty() and native.frames.has_animation("move.nw"), "promoted embedded animation library reloads")
	var review_scene := load("res://scenes/asset_review_scene.tscn") as PackedScene
	var review := review_scene.instantiate()
	root.add_child(review)
	review.load_candidate(folders[0])
	await process_frame
	_check(review._avatar != null and review._avatar.sprite.sprite_frames.has_animation("move.ne"), "native animation review scene loads candidate")
	var selectable_variants: Array[String] = []
	for index: int in review._clip.item_count:
		selectable_variants.append(review._clip.get_item_text(index))
	_check("idle.alert" in selectable_variants and "idle.default" in selectable_variants, "review keeps non-directional variants independently selectable")
	_check(not FileAccess.file_exists(folders[0].path_join("review.json")), "opening review does not forge an approval")
	await _capture_review("synthetic-animation")
	review.free()
	_json(folders[0].path_join("candidate.json"), {"kind": "tileset", "assetId": "SYNTHETIC-TEST-ONLY", "revision": "test", "schemaVersion": 1})
	_json(folders[0].path_join("tileset.json"), tile_manifest)
	review = review_scene.instantiate()
	root.add_child(review)
	review.load_candidate(folders[0])
	await process_frame
	_check(review._tiles != null and review._tiles.get_used_cells().size() == 30, "TileSet review uses native TileMapLayer sample")
	await _capture_review("synthetic-tileset")
	review.free()
	_json(folders[0].path_join("candidate.json"), {"kind": "arena", "assetId": "fixture-arena", "revision": "test", "schemaVersion": 1})
	_json(folders[0].path_join("arena.json"), BattleArena.graybox())
	review = review_scene.instantiate()
	root.add_child(review)
	review.load_candidate(folders[0])
	review._start_bout(true)
	_check(not review._session.is_empty() and review._session.ok, "arena review starts seeded pure simulation bout")
	var before_overlay := JSON.stringify(review._session)
	review._arena_view.debug_overlays = false
	review._arena_view.render_session(review._session)
	_check(JSON.stringify(review._session) == before_overlay and review._arena_view._combat_overlay.visible, "combat feedback stays visible with diagnostics off and cannot mutate simulation")
	var clipped: Vector2 = review._arena_view.clipped_attack_end(Vector2(100, 100), Vector2(1000, 100), 4)
	_check(clipped.x <= review._arena_view.ground_size().x - 4 and is_equal_approx(clipped.y, 100), "attack telegraph stays inside playable boundary")
	var before: int = review._session.tick
	review._process(0.1)
	_check(review._session.tick > before, "arena review advances test bout without GameState")
	await process_frame
	await _capture_review("graybox-arena")
	review.free()
	var invalid_arena := BattleArena.graybox()
	invalid_arena.spawns.player = [-10, 20]
	_json(folders[0].path_join("arena.json"), invalid_arena)
	var output: Array = []
	var code := OS.execute(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--script", "res://scripts/assets/export_resources.gd", "--", "--asset-review", "--candidate", folders[0]], output, true)
	_check(code != 0 and str(output).contains("Arena runtime validation"), "native arena exporter rejects runtime-invalid spawn geometry")
	for folder: String in folders:
		for file: String in ["atlas.png", "atlas.json", "animation-set.json", "candidate.json", "spriteframes.tres", "arena.json", "tileset.json"]:
			if FileAccess.file_exists(folder.path_join(file)):
				DirAccess.remove_absolute(folder.path_join(file))
		DirAccess.remove_absolute(folder)


func _capture_review(label: String) -> void:
	if "--capture-review" not in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var folder := ProjectSettings.globalize_path("res://work/sprites/qa")
	DirAccess.make_dir_recursive_absolute(folder)
	var destination := folder.path_join("native-review-" + label + ".png")
	root.get_texture().get_image().save_png(destination)
	print("Synthetic review QA screenshot: " + destination)


func _json(path: String, value: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(value))
	file.close()


func _same_polygons(actual: Array, expected: Array) -> bool:
	if actual.size() != expected.size():
		return false
	for index: int in actual.size():
		if actual[index].size() != expected[index].size():
			return false
		for vertex: int in actual[index].size():
			for axis: int in 2:
				if not is_equal_approx(float(actual[index][vertex][axis]), float(expected[index][vertex][axis])):
					return false
	return true


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
