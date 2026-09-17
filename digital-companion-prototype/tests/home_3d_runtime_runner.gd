extends Node

var checks := 0
var failures := 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	for region_id: String in HabitatRules.REGION_IDS:
		var resolved := HabitatAssetLibrary.resolve_region(region_id, true)
		_check(resolved.ok and resolved.mode == "review-fixture-3d", "%s resolves only as an explicit review fixture" % region_id)
		_check(resolved.environment_package.get("manifest", {}).get("assetId", "") == "environment-" + region_id, "%s habitat pins the matching environment" % region_id)
		_check(EnvironmentAssetLibrary.active_pin().get("assetId", "") == "environment-" + region_id, "%s is the sole active environment package" % region_id)
	var package := HabitatAssetLibrary.resolve_region("forest", true)
	if not bool(package.get("ok", false)) or package.get("mode") != "review-fixture-3d":
		push_error("FAIL: Green Shade review package unavailable: " + str(package))
		get_tree().quit(1)
		return
	var view := CareHabitatView.new()
	view.size = Vector2(390, 600)
	add_child(view)
	await get_tree().process_frame
	for region_id: String in HabitatRules.REGION_IDS:
		_check(view.configure_region(HabitatAssetLibrary.resolve_region(region_id, true)), "%s review home renders through the shared EnvironmentView3D" % region_id)
	_check(view.configure_region(package), "live home configures the shared 3D environment view")
	var state := CareRules.make_new_state(1000.0)
	state.identity.species_id = "agumon"
	state.identity.species_name = "Agumon"
	state.identity.stage = "Rookie"
	state.skills = GameDefinitions.default_skills("agumon")
	state.care.poop_count = 1
	state.care.poop_slots[1] = true
	state.habitat.items = [
		{"instance_id": "home-planter", "item_id": "planter", "x": 22, "y": 26, "rotation": 0},
		{"instance_id": "home-rug", "item_id": "rug", "x": 18, "y": 27, "rotation": 0},
	]
	state.inventory.decor.planter = 0
	state.inventory.decor.rug = 0
	view.update_snapshot(state)
	await get_tree().process_frame
	_check(view.using_3d and is_instance_valid(view.avatar_3d) and view.environment_3d.environment_manifest.assetId == "environment-green-shade", "3D home owns one environment and one AnimatedSprite3D companion")
	_check(view.avatar_3d.sprite is AnimatedSprite3D and view.avatar_3d.get_ground_position().is_equal_approx(view.avatar.position), "2D gameplay coordinates mirror onto the XZ presentation plane")
	var waste_group := view.care_visuals_3d.get_node("HomeWaste")
	var decor_group := view.care_visuals_3d.get_node("HomeDecor")
	_check(waste_group.get_child_count() == 1 and waste_group.get_child(0) is Sprite3D, "occupied waste uses a real depth-tested Sprite3D in the live home")
	var decor_types := {}
	for child: Node in decor_group.get_children():
		decor_types[String(child.get_meta("care_instance_id", ""))] = child.get_class()
	_check(decor_group.get_child_count() == 2 and decor_types.get("home-planter") == "Sprite3D" and decor_types.get("home-rug") == "MeshInstance3D", "decor uses grounded depth-tested sprite or textured-plane presentations")
	_check(not (waste_group.get_child(0) as Sprite3D).no_depth_test and (waste_group.get_child(0) as Sprite3D).alpha_cut == SpriteBase3D.ALPHA_CUT_DISCARD, "live waste presentation writes and tests depth")
	var waste_sprite := waste_group.get_child(0) as Sprite3D
	_check(is_equal_approx(waste_sprite.offset.y, waste_sprite.texture.get_height() * 0.5) and waste_sprite.position.y < 0.03, "upright care cards use a feet/ground pivot")
	if "--capture-home3d" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		view.environment_3d.world_viewport.get_texture().get_image().save_png("/tmp/home-3d-care-presentations.png")
	var stable_decor_ids: Array[int] = []
	for child: Node in decor_group.get_children():
		stable_decor_ids.append(child.get_instance_id())
	var stable_waste_id := waste_group.get_child(0).get_instance_id()
	for update: int in 120:
		view.update_snapshot(state)
	decor_group = view.care_visuals_3d.get_node("HomeDecor")
	waste_group = view.care_visuals_3d.get_node("HomeWaste")
	var after_decor_ids: Array[int] = []
	for child: Node in decor_group.get_children():
		after_decor_ids.append(child.get_instance_id())
	_check(stable_decor_ids == after_decor_ids and stable_waste_id == waste_group.get_child(0).get_instance_id(), "sustained state refreshes reuse unchanged 3D care presentation nodes")
	var center: Variant = view.project_touch_to_ground(view.size * 0.5)
	_check(center is Vector2 and Rect2(0, 0, 1280, 1536).has_point(center), "screen ray projects to bounded XZ ground")
	_check(view.project_touch_to_ground(Vector2(-1, -1)) == null and view.project_touch_to_ground(view.size + Vector2.ONE) == null, "out-of-bounds touch rays are rejected")
	var cell: Variant = view.project_touch_to_cell(view.size * 0.5)
	_check(cell is Vector2i and HabitatRules.inside(cell), "touch projection produces a valid 40x48 edit cell")
	view.set_follow(true)
	view.avatar.position = CareHabitatView.cell_center(Vector2i(23, 25))
	view._process(0.1)
	_check(view.environment_3d.camera_mode() == EnvironmentView3D.CAMERA_MODE_HOME_FOLLOW, "home camera follows the companion without changing gameplay")
	view.set_follow(false)
	_check(view.environment_3d.camera_mode() == EnvironmentView3D.CAMERA_MODE_HOME_MANUAL, "disabling follow immediately enters fixed-axis manual camera mode")
	view.environment_3d.set_home_manual_pan(Vector2(64, 32), true)
	view.set_zoom(1.7)
	var zoom_distance := view.environment_3d._camera_target_ground_distance
	for frame: int in 120:
		view.environment_3d.update_home_target(view.avatar.position + Vector2(frame, 0), false)
		view.environment_3d.advance_camera(1.0 / 60.0)
	_check(is_equal_approx(view.environment_3d.home_zoom_multiplier(), 1.7) and is_equal_approx(view.environment_3d._camera_target_ground_distance, zoom_distance), "home dolly zoom persists across sustained target and camera updates")
	view.environment_3d.set_home_follow(view.avatar.position, false)
	view.environment_3d.update_home_target(view.avatar.position + Vector2(32, 0), false)
	_check(is_equal_approx(view.environment_3d._camera_target_ground_distance, zoom_distance), "home dolly zoom survives a follow-mode transition")
	view.environment_3d.set_home_manual_pan(Vector2(32, 16), false)
	view.environment_3d.update_home_target(view.avatar.position, false)
	_check(is_equal_approx(view.environment_3d._camera_target_ground_distance, zoom_distance), "home dolly zoom survives manual pan updates")
	view.reduced_motion = true
	view.update_snapshot(state)
	_check(view.environment_3d.reduced_motion, "reduced motion reaches 3D camera smoothing and parallax")
	state.habitat.items = []
	view.update_snapshot(state)
	view.set_follow(true)
	view.set_zoom(1.0)
	view.begin_edit()
	view.place_item("planter")
	var projected_edit_cell: Variant = view.project_touch_to_cell(view.size * 0.5)
	view._dragging = true
	view._motion(view.size * 0.5)
	var placed: Dictionary = view.draft.items[0]
	_check(projected_edit_cell is Vector2i and placed.x == projected_edit_cell.x and placed.y == projected_edit_cell.y, "dragging decoration uses the 3D ray-projected ground cell")
	view.draft.items[0].x = 25
	view.draft.items[0].y = 26
	view._refresh_draft()
	_check(view.draft_validity().ok, "3D decoration draft remains validated by HabitatRules after movement")
	view.end_edit()
	var beach_package := HabitatAssetLibrary.resolve_region("shellfish-beach", true)
	var beach_state := state.duplicate(true)
	beach_state.home_region = "shellfish-beach"
	beach_state.habitat = HabitatRules.default_layout_for_manifest(beach_package.habitat)
	beach_state.habitat.creature_cell = [31, 34]
	beach_state.habitat.camera = {"zoom": 1.45, "follow": false}
	view.begin_route([Vector2i(24, 25), Vector2i(25, 25)], true)
	_check(view.configure_region(beach_package), "switching homes builds the incoming region")
	view.update_snapshot(beach_state)
	_check(view._path.is_empty() and not view._route_is_potty and view.creature_cell() == Vector2i(31, 34), "region switch cancels the old route and hydrates the incoming saved cell")
	_check(view.avatar.position == CareHabitatView.cell_center(Vector2i(31, 34)) and view.avatar_3d.get_ground_position().is_equal_approx(view.avatar.position), "incoming regional snapshot roots both avatars at its acknowledged cell")
	_check(is_equal_approx(view.zoom_multiplier, 1.45) and not view.follow and view.environment_3d.camera_mode() == EnvironmentView3D.CAMERA_MODE_HOME_MANUAL, "incoming region restores its own zoom and follow preference")
	_check(view.environment_3d._home_follow_ground.is_equal_approx(view.avatar.position), "incoming manual camera remains anchored to the selected region's avatar")
	var blocked_manifest: Dictionary = beach_package.habitat.duplicate(true)
	blocked_manifest.blockers.append({"id": "verified-regression-blocker", "rect": [14, 16, 2, 2]})
	var broken_presentation := {"ok": true, "region_id": "shellfish-beach", "mode": "approved-3d", "notice": "broken", "habitat": blocked_manifest, "environment_package": {}}
	_check(not view.configure_region(broken_presentation) and view.habitat_manifest == blocked_manifest, "3D presentation failure preserves the verified habitat grid and blockers")
	_check(EnvironmentAssetLibrary.active_package().is_empty(), "failed presentation clears the globally active environment package")
	var fallback := HabitatAssetLibrary.resolve_region("green-shade", false)
	_check(fallback.mode == "fallback-2d", "production resolver never consumes pending review fixtures")
	_check(view.configure_region(fallback) and view.using_3d and view.environment_3d.environment_manifest.get("builtin", false), "unpromoted Green Shade uses original native care scenery, never pending biome art")
	_check(EnvironmentAssetLibrary.active_package().is_empty(), "generic fallback leaves zero active environment packages")
	view.queue_free()
	await get_tree().process_frame
	print("%s: %d home 3D runtime checks" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)
