extends Node

var checks := 0
var failures := 0

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	await get_tree().process_frame
	_check(GameState.isolated_mode, "tests never use actual companion saves")
	if not GameState.isolated_mode: get_tree().quit(1); return
	GameState.set_process(false)
	var state := GameState.get_state()
	GameState.state = state
	var packed := load("res://scenes/care_scene.tscn") as PackedScene
	var care := packed.instantiate()
	get_tree().root.add_child(care)
	care.habitat.set_process(false)
	await get_tree().process_frame
	_check(care._pages.size() == 7 and care._tabs.get_tab_count() == 3, "persistent destinations, food picker and status/growth/skills exist")
	var before: int = care.stats_content.get_instance_id()
	var dial_id: int = care._dials.fullness.get_instance_id()
	care._open_stats()
	care._on_state_changed(GameState.get_state())
	await get_tree().process_frame
	_check(care.stats_overlay.visible and before == care.stats_content.get_instance_id() and dial_id == care._dials.fullness.get_instance_id(), "stats updates preserve nodes and focus")
	var focus := get_viewport().gui_get_focus_owner()
	_check(care._care_panel.find_children("*", "Button", true, false)[0].focus_mode == Control.FOCUS_NONE and focus != null and care.stats_overlay.is_ancestor_of(focus), "modal traps focus away from obscured care actions")
	_check(focus != null and focus.get_theme_color("font_focus_color") == Color("26362b"), "focused light buttons retain dark readable text")
	_check(care._dials.fullness.value == GameState.state.care.hunger, "full gauge means fed")
	_check(care._selectors[0].disabled, "Baby skills are locked")
	care.stats_overlay.hide()
	care._begin_edit()
	care.habitat.place_item("digi_potty")
	_check(care.habitat.draft_validity().ok and GameState.state.habitat.items.is_empty(), "draft placement valid and uncommitted")
	care._end_edit()
	_check(GameState.state.habitat.items.is_empty() and GameState.state.inventory.decor.digi_potty == 1, "Cancel leaves layout and inventory untouched")
	care._begin_edit()
	care.habitat.place_item("digi_potty")
	GameState.set_habitat_camera(1.35, false)
	GameState.set_habitat_theme("practice")
	care._apply_edit()
	_check(GameState.state.habitat.items.size() == 1 and GameState.state.inventory.decor.digi_potty == 0, "Apply atomically places inventory")
	_check(GameState.state.habitat.camera.zoom == 1.35 and GameState.state.habitat.theme == "practice", "Apply preserves independent camera and background preferences")
	care.habitat._path.clear()
	care.habitat._path.append(Vector2i(11, 12))
	care.habitat._process(0.1)
	care.habitat.begin_edit()
	_check(care.habitat.avatar.position == care.habitat.cell_center(Vector2i(20, 24)), "editing midroute snaps to acknowledged cell")
	care.habitat.end_edit()
	GameState.state.identity.species_id = "agumon"
	GameState.state.identity.species_name = "Agumon"
	GameState.state.identity.stage = "Rookie"
	GameState.state.skills = GameDefinitions.default_skills("agumon")
	care._on_state_changed(GameState.get_state())
	care._care_action("feed")
	var eat_clip: StringName = care.avatar.sprite.animation
	care.habitat._path.clear()
	care.habitat._path.append(Vector2i(11, 12))
	care.habitat._process(0.1)
	_check(care.avatar.sprite.animation == eat_clip and care.avatar.is_care_action_playing(), "roaming does not interrupt a one-shot meal")
	_check(care.avatar.rotation == 0 and care.avatar.sprite.rotation == 0, "feet remain upright")
	care.habitat.stop_route()
	care.avatar.play_loop("idle")
	var habit_before: float = GameState.state.care.potty_habit
	GameState.state.care.next_poop_at = Time.get_unix_time_from_system() + 20
	care.habitat.begin_route(HabitatRules.path_to_potty(GameState.state.habitat), false)
	care.chat_input.text = "Hello friend"
	care._send_chat()
	_check(care.habitat._route_is_potty and not care.habitat._path.is_empty(), "conversation pauses rather than cancels automatic potty route")
	care.avatar.play_loop("idle")
	for tick: int in 600: care.habitat._process(0.1)
	_check(not care.habitat._route_is_potty and GameState.state.care.potty_habit == habit_before, "automatic arrival grants no guided habit reward")
	care.habitat.set_zoom(9)
	_check(care.habitat.zoom_multiplier == 2, "zoom upper bound")
	care.habitat.set_zoom(0)
	_check(care.habitat.zoom_multiplier == 0.0, "0% zoom shows the full map")
	care.habitat.set_zoom(1.35)
	# Each region owns its durable cell and camera state. A UI-driven switch must
	# discard any route from the old map and hydrate the selected snapshot.
	GameState.state.progression.story_flags["story.region.shellfish_beach"] = true
	GameState.state.habitat.creature_cell = [7, 8]
	GameState.state.habitat.camera = {"zoom": 1.2, "follow": true}
	var beach_layout := HabitatRules.default_layout(Vector2i(31, 34))
	beach_layout.camera = {"zoom": 1.55, "follow": false}
	GameState.state.habitats["shellfish-beach"] = beach_layout
	GameState._home_package = {}
	care._on_state_changed(GameState.get_state())
	care.habitat.begin_route([Vector2i(8, 8), Vector2i(9, 8)], true)
	care._select_region("shellfish-beach")
	_check(GameState.state.home_region == "shellfish-beach" and care.habitat.creature_cell() == Vector2i(31, 34), "region UI restores the selected home's distinct saved cell")
	_check(care.habitat._path.is_empty() and care.habitat.avatar.position == CareHabitatView.cell_center(Vector2i(31, 34)), "region UI cancels the prior map route and rehydrates the avatar")
	_check(is_equal_approx(care.habitat.zoom_multiplier, 1.55) and not care.habitat.follow, "region UI restores the selected home's camera preferences")
	care.habitat.begin_route([Vector2i(32, 34)], false)
	care._on_creature_cell_changed(Vector2i(10, 10))
	_check(care.habitat._path.is_empty() and care.habitat.creature_cell() == Vector2i(31, 34) and care.habitat.avatar.position == CareHabitatView.cell_center(Vector2i(31, 34)), "rejected movement commit cancels the stale route and resynchronizes presentation")
	care._open_page("Training")
	_check(care._pages.Training.visible and not care._pages.Tools.visible, "navigation switches existing pages")
	care._modal.hide()
	GameState.state.identity.species_id = "agumon"
	GameState.state.identity.species_name = "Agumon"
	GameState.state.identity.stage = "Rookie"
	GameState.state.skills = GameDefinitions.default_skills("agumon")
	care._on_state_changed(GameState.get_state())
	_check(not care._selectors[0].disabled and care._selectors[0].item_count == 4, "Rookie exposes three learned moves")
	care._move_up(1)
	_check(GameState.state.skills.equipped[0].move_id == "quick_bite", "move ordering persists through GameState")
	for dimensions: Vector2i in [Vector2i(360, 640), Vector2i(390, 844)]:
		get_tree().root.content_scale_size = dimensions
		get_tree().root.size = dimensions
		await get_tree().process_frame
		await get_tree().process_frame
		_check(care._care_panel.get_global_rect().end.y <= dimensions.y and care.habitat.size.y > 200, "care layout fits %s" % dimensions)
		if "--capture-care" in OS.get_cmdline_user_args():
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("/tmp/care-%dx%d.png" % [dimensions.x, dimensions.y])
		care._open_stats()
		await get_tree().process_frame
		if "--capture-care" in OS.get_cmdline_user_args():
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("/tmp/care-stats-%dx%d.png" % [dimensions.x, dimensions.y])
		care.stats_overlay.hide()
		if "--capture-care" in OS.get_cmdline_user_args():
			GameState.set_habitat_theme("verdant")
			care._begin_edit()
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("/tmp/care-edit-%dx%d.png" % [dimensions.x, dimensions.y])
			care._end_edit()
			care._open_page("Training")
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("/tmp/care-training-%dx%d.png" % [dimensions.x, dimensions.y])
			care._modal.hide()
	packed = null
	care.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(0.1).timeout
	print("%s: %d care UI checks" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)
