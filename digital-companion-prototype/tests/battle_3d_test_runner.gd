extends Node

const FIXTURE := "res://tests/fixtures/regions/green-shade/environment/environment.json"
const FrozenV3 = preload("res://scripts/battle/battle_simulator_v3.gd")

var checks := 0
var failures := 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	await get_tree().process_frame
	_test_encounters_and_arena_contract()
	_test_five_region_fixtures()
	_test_live_context_and_story_gate()
	await _test_world_presentation_and_determinism()
	await _test_isolated_reviewer_package()
	await _test_live_scene_replay_vfx_reset()
	await _test_playable_workshop_fields()
	_test_replay_pin()
	print("Battle Sprite-in-3D: %d checks, %d failures" % [checks, failures])
	get_tree().quit(1 if failures else 0)


func _test_encounters_and_arena_contract() -> void:
	var green := EncounterCatalog.resolve("forest-arena")
	check(green.ok and green.encounterId == "encounter.green-shade.rootbound-glade" and green.arenaId == "arena-rootbound-glade", "forest-arena remains a Green Shade compatibility alias")
	check(EncounterCatalog.all_debug_encounters().size() == 5, "all five contextual encounters remain enumerable for debug/review")
	check(not EncounterCatalog.resolve("../../escape").ok, "unknown contextual encounters are rejected")
	var arena := _arena()
	check(BattleArena.validate(arena).is_empty(), "30x36 arena accepts complete environment pin and presentation placements")
	var invalid := arena.duplicate(true)
	invalid.environment.erase("contentSha256")
	check(not BattleArena.validate(invalid).is_empty(), "arena rejects partial environment pins")
	invalid = arena.duplicate(true)
	invalid.presentation.staticPlacements[0].rotationDegrees = 90
	check(not BattleArena.validate(invalid).is_empty(), "arena rejects edge-exposing card rotation")
	var wrong_context := _session(arena, "encounter.shellfish-beach.breaker-cove")
	check(not wrong_context.get("ok", false), "session rejects an encounter mapped to a different arena and region")
	var wrong_region := arena.duplicate(true)
	wrong_region.regionId = "shellfish-beach"
	check(not _session(wrong_region, "encounter.green-shade.rootbound-glade").get("ok", false), "session rejects a swapped arena region identity")


func _test_world_presentation_and_determinism() -> void:
	var arena := _arena()
	var view := BattleWorldPresentation3D.new()
	view.size = Vector2(390, 844)
	add_child(view)
	await get_tree().process_frame
	var package := _fixture_package(arena.environment)
	check(view.configure_battle(arena, package), "battle presentation consumes a complete pinned Environment package")
	var session_a := _session(arena)
	var session_b := _session(arena)
	var historical := _session(arena, "", true)
	check(session_a.ok and session_a.content_revisions.environment == arena.environment, "battle session records the full immutable environment pin")
	check(view.configure_fighters(session_a), "two AnimatedSprite3D fighters attach to the environment viewport")
	check(view.fighter_presentations.size() == 2 and view.fighter_vfx.size() == 2, "two fighters and reusable world-space hit VFX are active")
	for target: Vector2i in EnvironmentPresentationContract.TARGET_SIZES:
		view.size = target
		await get_tree().process_frame
		check(view.frame_session(session_a, 1.0, true), "fighter bounds frame at %dx%d" % [target.x, target.y])
		check(view.camera_contains_world_points(view.last_framing_world_points), "authored sprite pivots remain inside %dx%d" % [target.x, target.y])
		check(is_equal_approx(view.camera.fov, 28.0) and is_equal_approx(view.camera.rotation_degrees.x, -50.0) and is_zero_approx(view.camera.rotation_degrees.y), "battle camera preserves 28 FOV/fixed axis at %dx%d" % [target.x, target.y])
	var extreme := _session(arena)
	extreme.actors.player.pos = [16000, 16000]
	extreme.actors.player.previous_pos = extreme.actors.player.pos.duplicate()
	extreme.actors.training_opponent.pos = [944000, 1136000]
	extreme.actors.training_opponent.previous_pos = extreme.actors.training_opponent.pos.duplicate()
	for viewport_size: Vector2i in EnvironmentPresentationContract.TARGET_SIZES:
		view.size = viewport_size
		await get_tree().process_frame
		check(view.frame_session(extreme, 1.0, true), "legal arena extremes fit the portrait viewport %dx%d" % [viewport_size.x, viewport_size.y])
		check(view.camera_contains_world_points(view.last_framing_world_points), "extreme sprite pixels remain visible in %dx%d" % [viewport_size.x, viewport_size.y])
		check(view._camera_ground_distance <= 60.0 and is_equal_approx(view.camera.fov, 28.0), "extreme framing uses bounded dolly and fixed FOV")
	var pristine := JSON.stringify(session_a)
	for tick: int in 90:
		BattleSimulator.step(session_a)
		view.render_session(session_a, float(tick % 3) / 2.0)
		BattleSimulator.step(session_b)
		FrozenV3.step(historical)
		view.render_session(historical, float(tick % 3) / 2.0)
	check(JSON.stringify(session_a) == JSON.stringify(session_b), "interleaved 3D rendering cannot alter deterministic battle state")
	check(JSON.stringify(historical).sha256_text() == "9100a95c41de8c760b1570e6797c23394b581f606e640d9e70507fbbdfd0fe38", "interleaved presentation preserves the established frozen-v3 deterministic checksum")
	check(pristine != JSON.stringify(session_a), "determinism regression exercised advancing simulation")
	var display := session_a.duplicate(true)
	display.projectiles = [{"id": 999, "owner_id": "player", "move_id": "pepper_breath",
		"pos": [180000, 220000], "previous_pos": [170000, 220000]}]
	view.record_effect("player", "hit_fire", int(display.tick), 18)
	view.render_session(display, 1.0)
	check(view.projectile_vfx.size() == 1 and view.fighter_vfx.player.visible, "Pepper Breath and hit effects render as reusable depth-tested WorldVFX3D")
	check(view.camera_contains_world_points(view.last_framing_world_points), "Pepper Breath projectile is included in camera framing")
	var agumon: CompanionPresentation3D = view.fighter_presentations.player
	agumon.render_combat("special_attack", "e", 20, 60)
	var right_mouth := agumon.attachment_offset("mouth")
	agumon.render_combat("special_attack", "w", 20, 60)
	var left_mouth := agumon.attachment_offset("mouth")
	check(right_mouth.x > left_mouth.x, "mouth attachment mirrors with Agumon's facing")
	check(is_equal_approx(right_mouth.y, left_mouth.y), "mirroring keeps mouth height grounded")
	view.clear_effects()
	display.projectiles[0].pos = display.actors.player.pos.duplicate()
	display.projectiles[0].previous_pos = display.actors.player.pos.duplicate()
	view.render_session(display, 0.0)
	var launched: WorldVFX3D = view.projectile_vfx["999"]
	check(launched.position.is_equal_approx(agumon.position + agumon.attachment_offset("mouth")), "fire starts at the rendered mouth, not the ground root")
	view.record_effect("training_opponent", "hit_fire", int(display.tick), 18)
	view.render_session(display, 1.0)
	check(view.fighter_vfx.training_opponent.visible and view.fighter_vfx.training_opponent.texture == view._fire_effect_texture(), "fire hit renders a distinct flame burst on the enemy")
	display.tick += 19
	view.render_session(display, 1.0)
	check(not view.fighter_vfx.training_opponent.visible, "fire impact expires without leaving a permanent flame")
	view.clear_effects()
	check(view.projectile_vfx.is_empty() and view._effect_records.is_empty() and not view.fighter_vfx.player.visible, "replay reset clears transient 3D VFX nodes and records")
	var before_distance := view._camera_ground_distance
	view.frame_ground_bounds(Rect2(64, 64, 760, 900), Vector2(64, 96), false)
	check(not is_equal_approx(view._camera_target_ground_distance, before_distance), "battle framing sets a dolly target without orbiting")
	view.set_reduced_motion(true)
	check(is_equal_approx(view._camera_ground_distance, view._camera_target_ground_distance) and view.reduced_motion, "reduced motion snaps camera smoothing and secondary parallax")
	var stats := view.battle_instrumentation()
	check(stats.environmentEnabled and stats.fighters == 2 and stats.persistentVfx == 2 and stats.withinRuntimeBounds, "representative two-fighter+VFX instrumentation stays within runtime bounds")
	view.free()


func _test_five_region_fixtures() -> void:
	var index := AssetResourceLibrary.read_json("res://tests/fixtures/regions/index.json")
	var regions: Variant = index.get("regions")
	check(regions is Dictionary and regions.size() == 5, "five-region debug index exposes all arena contexts")
	var contextual_records: Variant = index.get("encounters")
	check(contextual_records is Dictionary and contextual_records.size() == 5, "debug index exposes all five canonical contextual encounter IDs")
	if not regions is Dictionary:
		return
	for encounter: Dictionary in EncounterCatalog.all_debug_encounters():
		var encounter_id := String(encounter.encounterId)
		check(contextual_records is Dictionary and contextual_records.has(encounter_id), encounter_id + " is indexed without a player-facing arena selector")
		var resolved := GameState._resolve_training_arena(encounter_id)
		check(resolved.get("ok", false) and resolved.get("source", "") == "isolated-dev-fixture" and String(resolved.arena.assetId) == String(encounter.arenaId), encounter_id + " resolves to its isolated review arena")
		check(String(resolved.arena.get("contentSha256", "")) == String(resolved.get("contentSha256", "")), encounter_id + " carries its immutable arena candidate hash")
	for region_id: String in regions:
		var record: Dictionary = regions[region_id]
		var arena_path := "res://" + String(record.arena.path)
		var arena := AssetResourceLibrary.read_json(arena_path)
		check(BattleArena.validate(arena).is_empty(), region_id + " 30x36 arena passes body-clearance/path-connectivity runtime validation")
		check(int(arena.ground.cellSize) == 32 and int(arena.ground.width) == 960 and int(arena.ground.height) == 1152, region_id + " arena is exactly 30x36 cells")
		var indexed_pin := {"assetId": record.environment.assetId, "revision": record.environment.revision,
			"contentSha256": record.environment.contentSha256}
		check(arena.environment == indexed_pin, region_id + " arena pins its indexed Environment content")
		var pin: Dictionary = arena.environment
		var folder := "res://" + String(record.environment.path)
		check(EnvironmentAssetLibrary.activate_isolated_dev_fixture(pin, folder, true).get("pin", {}) == pin, region_id + " isolated native Environment fixture passes exact metadata/payload/resource identity validation")
		EnvironmentAssetLibrary.clear_active()
		check(EnvironmentAssetLibrary.activate_isolated_dev_fixture(pin, folder, false).is_empty(), region_id + " dev fixture cannot load without an explicit isolated authorization")
	_test_arena_resolver_adversaries(index)


func _test_live_context_and_story_gate() -> void:
	GameState.clear_active_battle()
	GameState.state = CareRules.make_new_state(1000.0)
	GameState.state.home_region = "toy-maze"
	GameState.isolated_mode = true
	var contextual := GameState.start_training_battle(4455)
	check(contextual.get("ok", false) and contextual.encounter_id == "encounter.toy-maze.clockwork-maze"
		and contextual.arena.regionId == "toy-maze", "Battle action derives its encounter from the actual active home")
	GameState.clear_active_battle()
	var locked_game: Variant = load("res://scripts/core/game_state.gd").new()
	locked_game.state = CareRules.make_new_state(1000.0)
	locked_game.isolated_mode = false
	var locked: Dictionary = locked_game.start_training_battle(4455, "encounter.shellfish-beach.breaker-cove")
	check(not locked.get("ok", false) and String(locked.get("error", "")).contains("not been unlocked"), "live encounter start enforces story-region unlocks")
	locked_game.free()
	GameState.state = CareRules.make_new_state(1000.0)


func _test_arena_resolver_adversaries(index: Dictionary) -> void:
	var green := EncounterCatalog.resolve("green-shade")
	var record: Dictionary = index.regions["green-shade"].arena
	var folder := "res://" + String(record.reviewPackage)
	var resolved := ArenaAssetLibrary.resolve_isolated_dev_fixture(green, folder,
		String(record.contentSha256), true)
	check(resolved.get("ok", false), "hash-verified native arena review package resolves only in isolated mode")
	check(not ArenaAssetLibrary.resolve_isolated_dev_fixture(green, folder,
		"sha256:" + "0".repeat(64), true).get("ok", false), "tampered arena candidate content hash is rejected")
	check(not ArenaAssetLibrary.resolve_isolated_dev_fixture(green, folder,
		String(record.contentSha256), false).get("ok", false), "dev arena package cannot enter live resolution")
	var metadata := AssetResourceLibrary.read_json(folder.path_join("candidate.json"))
	var approved_metadata := metadata.duplicate(true)
	approved_metadata.devFixture = false
	approved_metadata.reviewStatus = "approved"
	approved_metadata.contentSha256 = EnvironmentAssetLibrary.metadata_content_sha256(approved_metadata)
	var approved_entry := {"assetId": green.arenaId, "revision": approved_metadata.revision,
		"contentSha256": approved_metadata.contentSha256}
	check(ArenaAssetLibrary._metadata_matches(approved_metadata, approved_entry, green.arenaId, false), "live arena metadata requires an approved non-fixture candidate hash")
	approved_metadata.reviewStatus = "pending-human-review"
	check(not ArenaAssetLibrary._metadata_matches(approved_metadata, approved_entry, green.arenaId, false), "pending arena metadata cannot enter live play")
	var tampered_files: Dictionary = metadata.files.duplicate(true)
	tampered_files["arena.json"] = "sha256:" + "0".repeat(64)
	check(not ArenaAssetLibrary._payload_hashes_match(folder, tampered_files), "tampered arena payload hash is rejected")
	var swapped := AssetResourceLibrary.read_json("res://" + String(index.regions["shellfish-beach"].arena.path))
	check(not ArenaAssetLibrary._manifest_matches(swapped, green, metadata), "swapped region arena manifest is rejected")
	var swapped_catalog := {"schemaVersion": 1, "assets": {"not-the-arena-id": {
		"kind": "arena", "assetId": green.arenaId, "revision": metadata.revision,
		"contentSha256": metadata.contentSha256, "path": String(record.reviewPackage)}}}
	check(not ArenaAssetLibrary.resolve_approved_from_catalog(green, swapped_catalog, "res://").get("ok", false), "catalog key must equal the encounter and entry arena ID")


func _test_replay_pin() -> void:
	var arena := _arena()
	var session := _session(arena, "encounter.green-shade.rootbound-glade")
	while not session.complete:
		BattleSimulator.step(session)
	var record := BattleSimulator.replay_record(session)
	check(record.arena.environment == arena.environment and record.content_revisions.environment == arena.environment, "replay serializes pinned environment and unchanged arena geometry")
	check(record.encounter_id == "encounter.green-shade.rootbound-glade" and record.content_revisions.encounterId == record.encounter_id, "replay preserves the contextual encounter identity")
	check(record.content_revisions.arena.contentSha256 == arena.contentSha256, "replay pins the immutable arena candidate hash")
	check(record.arena.ground == arena.ground and record.arena.spawns == arena.spawns and record.arena.obstacles == arena.obstacles, "replay retains ground, spawn, and obstacle fields verbatim")
	check(JSON.stringify(BattleSimulator.replay(record)) == JSON.stringify(session), "environment-backed replay reconstructs byte-identically")
	var tampered := record.duplicate(true)
	tampered.content_revisions.arena.contentSha256 = "sha256:" + "f".repeat(64)
	check(not BattleSimulator.replay(tampered).get("ok", false), "replay rejects an arena package hash mismatch")
	var legacy_arena := BattleArena.graybox()
	var legacy_shape := _session(legacy_arena)
	check(not legacy_shape.content_revisions.has("environment"), "environment-free battle-v3 records retain their prior content revision shape")


func _test_isolated_reviewer_package() -> void:
	var review := (load("res://scenes/asset_review_scene.tscn") as PackedScene).instantiate()
	add_child(review)
	await get_tree().process_frame
	var folder := ProjectSettings.globalize_path("res://tests/fixtures/regions/green-shade/review/arena")
	review.load_candidate(folder)
	await get_tree().process_frame
	check(review._environment_view != null and review.manifest.assetId == "arena-rootbound-glade", "isolated reviewer accepts a hash-verified adjacent raw Environment package")
	review._start_bout(false)
	check(review._session.get("ok", false) and review._fighters.size() == 2, "environment-backed arena reviewer starts a real two-fighter bout without the 2D view")
	review.free()


func _test_live_scene_replay_vfx_reset() -> void:
	GameState.clear_active_battle()
	GameState.state = CareRules.make_new_state(1000.0)
	GameState.state.identity.merge({"species_id": "agumon", "species_name": "Agumon", "stage": "Rookie"}, true)
	GameState.state.skills = GameDefinitions.default_skills("agumon")
	GameState.isolated_mode = true
	var started := GameState.start_training_battle(8811, "green-shade")
	check(started.get("ok", false), "isolated live scene starts the contextual 3D arena")
	if not started.get("ok", false):
		return
	GameState.active_battle_result.max_ticks = 1
	GameState.advance_training_battle()
	var scene := (load("res://scenes/battle_scene.tscn") as PackedScene).instantiate()
	add_child(scene)
	await get_tree().process_frame
	check(scene._environment_enabled, "live contextual battle uses the verified isolated 3D package")
	check(scene.environment_view.position == Vector2.ZERO and scene.environment_view.size == scene.get_viewport_rect().size,
		"live 3D battle field fills the portrait viewport beneath the HUD")
	scene.environment_view.record_effect("player", "hit_fire", 0, 30)
	var stale_projectile := WorldVFX3D.new()
	stale_projectile.configure(scene.environment_view._fire_effect_texture(), scene.environment_view._vfx_definition(6))
	scene.environment_view.attach_world_node(stale_projectile)
	scene.environment_view.projectile_vfx["stale"] = stale_projectile
	scene.environment_view.fighter_vfx.player.visible = true
	scene._start_replay()
	check(scene._is_replay and scene.environment_view._effect_records.is_empty()
		and scene.environment_view.projectile_vfx.is_empty()
		and not scene.environment_view.fighter_vfx.player.visible,
		"BattleScene replay start clears every transient 3D VFX record and node")
	scene.free()
	GameState.clear_active_battle()
	GameState.state = CareRules.make_new_state(1000.0)


func _test_playable_workshop_fields() -> void:
	var reviewer = preload("res://scripts/environment/battle_field_review.gd")
	GameState.isolated_mode = true
	for encounter: Dictionary in EncounterCatalog.all_debug_encounters():
		var region := String(encounter.regionId)
		var started: Dictionary = reviewer.start(region)
		check(started.get("ok", false), region + " playable field starts a real isolated battle")
		if not started.get("ok", false):
			continue
		var before := JSON.stringify(GameState.active_battle_result)
		var scene := (load("res://scenes/battle_scene.tscn") as PackedScene).instantiate()
		add_child(scene)
		scene.set_process(false)
		await get_tree().process_frame
		var view: BattleWorldPresentation3D = scene.environment_view
		check(scene._environment_enabled and view.environment_manifest.get("reviewOnly", false), region + " battle consumes saved editable field, not stale package art")
		check(String(view.environment_manifest.get("nativeScene", "")).ends_with(region.replace("-", "_") + "_battle.tscn"), region + " uses its own battle field")
		check(view.fighter_presentations.size() == 2 and not scene.arena_view.visible, region + " has exactly two real 3D fighters and no 2D arena overlay")
		var stage := view._terrain_root.get_child(0)
		if region == "green-shade":
			var floor_material: Material = stage.get_node("Floor").get_child(0).material_override
			check(floor_material is ShaderMaterial and floor_material.get_shader_parameter("source_region") == Vector4(760, 700, 40, 22), "forest floor samples grassy source region rather than cracked stone")
			check(not stage.get_node("Landmarks/Landmark_1/green_shade_tree_canopy").visible and not stage.get_node("Landmarks/Landmark_1/green_shade_tree_interior").visible, "mismatched legacy tree slices are hidden")
			for source: Array in [["panorama", "d387a7fed284f1fed691546dae6ca1235af148f86ecf63eec10dd72d7fa2f4a6"], ["sky", "84748c7233ee9465fd2931578e726ed92d546e3505a3fa4b40da8c939368ce10"], ["foliage", "ee0ed7a9f64646e8205801b671ba06591fa587f7dc79efc1ede5efb390c9743f"]]:
				check(FileAccess.get_sha256("res://assets/environment_workshop/forest-parallax/%s.png" % source[0]) == source[1], "forest working texture preserves bound source bytes: " + source[0])
			var layers: Node3D = stage.get_node("ForestParallax")
			var sky: Sprite3D = layers.get_node("Sky")
			var vista: Sprite3D = layers.get_node("ForestVista")
			var plant: Sprite3D = layers.get_node("Woodland/RimPockets").get_child(0)
			layers.apply_focus(layers.reference_focus, false)
			var sky_base := sky.position
			var vista_base := vista.position
			var plant_base := plant.position
			layers.apply_focus(layers.reference_focus + Vector3(5, 0, 4), false)
			var shifted := sky.position
			check(sky.position.distance_to(sky_base) > vista.position.distance_to(vista_base), "forest distant layers have distinct parallax ratios")
			check(plant.position == plant_base, "forest ground foliage never slides with camera")
			for repeat: int in 100:
				layers.apply_focus(layers.reference_focus + Vector3(5, 0, 4), false)
			check(sky.position == shifted, "forest repeated updates cannot accumulate drift")
			layers.apply_focus(layers.reference_focus + Vector3(500, 0, 500), false)
			check(sky.position.distance_to(sky_base) <= layers.maximum_shift + 0.001, "forest parallax is bounded at extreme focus")
			view.set_reduced_motion(true)
			check(sky.position == sky_base and vista.position == vista_base, "forest reduced motion restores authored layer positions")
			view.set_reduced_motion(false)
			for card: Sprite3D in layers.find_children("*", "Sprite3D", true, false):
				check(not card.no_depth_test and card.alpha_cut == SpriteBase3D.ALPHA_CUT_DISCARD, "forest cards retain opaque depth-tested cutouts")
		check(stage.get_node_or_null("Characters") == null, region + " removes static editor actor guides")
		var prop_cards := stage.find_children("*", "Sprite3D", true, false)
		check(not prop_cards.is_empty(), region + " scenery consists of layered 2D cards")
		for mesh: Node in stage.find_children("*", "MeshInstance3D", true, false):
			check(String(mesh.get_path()).contains("/Floor/"), region + " uses meshes only for flat terrain, never foliage models")
		for target: Vector2i in EnvironmentPresentationContract.TARGET_SIZES:
			get_tree().root.content_scale_size = target
			get_tree().root.size = target
			for frame: int in 3:
				await get_tree().process_frame
			check(view.frame_session(scene.battle, 1.0, true) and view.camera_contains_world_points(view.last_framing_world_points), region + " keeps fighters framed at " + str(target))
			check(is_equal_approx(view.camera.rotation_degrees.x, -30.0), region + " reads the saved shallower camera angle")
			if region == "green-shade":
				var fit_distance := view._camera_ground_distance
				scene._set_view_zoom(1.5)
				view.frame_session(scene.battle, 1.0, true)
				check(view._camera_ground_distance < fit_distance, "zoom in survives automatic battle reframing")
				scene._set_view_zoom(0.75)
				check(view._camera_ground_distance > fit_distance, "zoom out increases camera distance")
				var wheel := InputEventMouseButton.new()
				wheel.button_index = MOUSE_BUTTON_WHEEL_UP
				wheel.pressed = true
				scene._on_field_zoom_input(wheel)
				check(view.battle_zoom_multiplier > 0.75, "mouse wheel zooms forest view")
				var pinch := InputEventMagnifyGesture.new()
				pinch.factor = 100.0
				scene._on_field_zoom_input(pinch)
				check(view.battle_zoom_multiplier == 2.0, "pinch zoom is bounded")
				scene._zoom_fit.pressed.emit()
				check(is_equal_approx(view._camera_ground_distance, fit_distance) and view.camera_contains_world_points(view.last_framing_world_points), "Fit button restores both fighters")
			if "--capture-fields" in OS.get_cmdline_user_args():
				RenderingServer.force_draw(false)
				check(get_viewport().get_texture().get_image().save_png("/tmp/battle-field-%s-%dx%d.png" % [region,target.x,target.y]) == OK, region + " capture")
				if region == "green-shade":
					var saved_focus := view._camera_focus_ground
					var saved_distance := view._camera_ground_distance
					view.set_process(false)
					for direction: String in ["left", "right", "near", "far"]:
						view._camera_focus_ground = saved_focus + Vector2(-192 if direction == "left" else (192 if direction == "right" else 0), 0)
						view._camera_ground_distance = saved_distance * (0.75 if direction == "near" else (1.25 if direction == "far" else 1.0))
						view._apply_camera_transform()
						RenderingServer.force_draw(false)
						check(get_viewport().get_texture().get_image().save_png("/tmp/forest-%s-%dx%d.png" % [direction,target.x,target.y]) == OK, "forest " + direction + " depth review capture")
					view._camera_focus_ground = saved_focus
					view._camera_ground_distance = saved_distance
					view._apply_camera_transform()
					view.set_process(true)
		check(JSON.stringify(GameState.active_battle_result) == before, region + " presentation does not mutate combat or replay pins")
		check(EnvironmentAssetLibrary.active_package().is_empty(), region + " review does not activate unapproved catalog art")
		scene.free()
		GameState.clear_active_battle()
	GameState.remove_meta("battle_field_review")
	GameState.state = CareRules.make_new_state(1000.0)
	get_tree().root.content_scale_size = Vector2i(390,844)
	get_tree().root.size = Vector2i(390,844)
	GameState.isolated_mode = false
	check(not reviewer.start("green-shade").get("ok", false), "working fields cannot bypass live approval gates")
	GameState.isolated_mode = true


func _arena() -> Dictionary:
	var manifest := AssetResourceLibrary.read_json(FIXTURE)
	var pin := {"assetId": String(manifest.assetId), "revision": String(manifest.revision), "contentSha256": "sha256:" + "a".repeat(64)}
	var arena := {"schemaVersion": 1, "kind": "arena", "assetId": "arena-rootbound-glade", "revision": "2026-09-12.001",
		"regionId": "green-shade", "contentSha256": "sha256:" + "b".repeat(64),
		"projection": "square", "ground": {"width": 960, "height": 1152, "cellSize": 32}, "maxBodyRadius": 16,
		"spawns": {"player": [192, 576], "opponent": [768, 576]}, "obstacles": [], "tiles": [],
		"environment": pin, "presentation": {"staticPlacements": []}}
	if not manifest.get("planeStacks", []).is_empty():
		arena.presentation.staticPlacements.append({"id": "center-tree", "planeStack": manifest.planeStacks[0].id,
			"groundPosition": [480, 300], "rotationDegrees": 0})
	return arena


func _session(arena: Dictionary, encounter_id := "", historical_v3 := false) -> Dictionary:
	var first := FrozenV3.training_opponent(8181) if historical_v3 else BattleSimulator.training_opponent(8181)
	first.fighter_id = "player"
	first.display_name = "Player"
	var second := FrozenV3.training_opponent(8181) if historical_v3 else BattleSimulator.training_opponent(8181)
	# A historical replay checksum must pin its historical art identity; the
	# current runtime catalog is independently allowed to promote new artwork.
	var library := CompanionAssetLibrary.build_folder("res://assets/companions/agumon/")
	var pins := {"player": {"assetId": library.asset_id, "revision": library.revision},
		"training_opponent": {"assetId": library.asset_id, "revision": library.revision}}
	if historical_v3:
		return FrozenV3.create_session("battle-3d-test", 8181, first, second, arena, 90, pins, {}, {}, encounter_id,
			String(arena.get("contentSha256", "")))
	return BattleSimulator.create_session("battle-3d-test", 8181, first, second, arena, 90, pins, {}, {}, encounter_id,
		String(arena.get("contentSha256", "")))


func _fixture_package(pin: Dictionary) -> Dictionary:
	var manifest := AssetResourceLibrary.read_json(FIXTURE)
	var textures := {}
	for role: String in manifest.textures:
		textures[role] = AssetResourceLibrary.load_payload_texture(FIXTURE.get_base_dir().path_join(String(manifest.textures[role])))
	return {"pin": pin.duplicate(true), "manifest": manifest, "textures": textures, "folder": FIXTURE.get_base_dir()}


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
