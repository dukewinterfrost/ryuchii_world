extends Node2D

const INK := Color("26362b")
const CREAM := Color("f7f3df")
const SUN := Color("f1bf55")
const Definitions = preload("res://scripts/core/game_definitions.gd")
const HabitatView = preload("res://scripts/ui/care_habitat_view.gd")
var habitat: CareHabitatView
var avatar: CompanionAvatar
var dialogue_label: Label
var status_label: Label
var chat_input: LineEdit
var stats_overlay: ColorRect
var stats_content: VBoxContainer
var evolution_overlay: ColorRect
var evolution_label: Label
var clean_mode := false
var _root: Control
var _care_panel: PanelContainer
var _header_panel: PanelContainer
var _map_bar: PanelContainer
var _map_zoom: Label
var _exploring_map := false
var _food_buttons: Dictionary = {}
var _food_note: Label
var _craving_bubble: CravingBubble
var _rest_note: Label
var _sleep_button: Button
var _wake_button: Button
var _edit_panel: PanelContainer
var _modal: ColorRect
var _pages := {}
var _tabs: TabContainer
var _portrait: TextureRect
var _dials := {}
var _details: Label
var _growth: Label
var _skills_note: Label
var _selectors: Array[OptionButton] = []
var _auto: Array[CheckButton] = []
var _up: Array[Button] = []
var _training_note: Label
var _training_progress: ProgressBar
var _training_cancel: Button
var _training_buttons := {}
var _inventory: Label
var _warning: Button
var _guide: Button
var _follow: Button
var _zoom: Label
var _mute: CheckButton
var _motion: CheckButton
var _edit_note: Label
var _material_note: Label
var _decor_buttons := {}
var _region_buttons := {}
var _environment_note: Label
var _apply: Button
var _audio := {}
var _refreshing := false
var _warning_seen := 0.0
var _focus_modes := {}
var _configured_region := ""
var _day_night_preview: DayNightPreview

func _ready() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(_root)
	var backdrop := ColorRect.new()
	backdrop.color = Color("24392e")
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(backdrop)
	habitat = HabitatView.new()
	habitat.set_anchors_preset(Control.PRESET_FULL_RECT)
	habitat.offset_top = 126
	habitat.offset_bottom = -194
	_root.add_child(habitat)
	avatar = habitat.avatar
	habitat.creature_cell_changed.connect(_on_creature_cell_changed)
	habitat.route_completed.connect(_arrived)
	habitat.facility_arrived.connect(_complete_facility_action)
	habitat.waste_selected.connect(_on_poop_selected)
	habitat.camera_changed.connect(func(zoom: float, follow: bool) -> void:
		_feedback(GameState.set_habitat_camera(zoom, follow))
	)
	habitat.draft_changed.connect(_refresh_edit)
	_build_care()
	_build_map_bar()
	_build_stats()
	_build_pages()
	_craving_bubble = CravingBubble.new()
	_root.add_child(_craving_bubble)
	_craving_bubble.pressed.connect(_thought_pressed)
	_build_edit()
	if OS.is_debug_build():
		_day_night_preview = DayNightPreview.new()
		_day_night_preview.environment_view = habitat.environment_3d
		_root.add_child(_day_night_preview)
	evolution_overlay = _overlay()
	var evolution_box := _overlay_content(evolution_overlay, "BOND AWAKENED")
	evolution_label = _label(evolution_box, "", 25)
	for key: String in ["eat", "eat-done", "evolution"]:
		var player := AudioStreamPlayer.new()
		player.stream = load("res://assets/audio/" + key + ".wav")
		add_child(player)
		_audio[key] = player
	avatar.action_finished.connect(func(action: String) -> void:
		if action == "eat": _audio["eat-done"].play()
	)
	GameState.state_changed.connect(_on_state_changed)
	GameState.evolution_started.connect(_evolve)
	GameState.training_changed.connect(_update_training)
	GameState.home_region_changed.connect(func(_region: String, _package: Dictionary) -> void: _configured_region = "")
	GameState.save_failed.connect(func() -> void: dialogue_label.text = GameState.persistence_notice)
	GameState.save_incompatible.connect(func(_v: int) -> void: dialogue_label.text = GameState.persistence_notice)
	_on_state_changed(GameState.get_state())
	if not GameState.persistence_notice.is_empty(): dialogue_label.text = GameState.persistence_notice

func _build_care() -> void:
	var top := _panel(8, 120, false)
	_header_panel = top
	var box := _stack(top)
	var row := _row(box)
	var portrait_button := _button(row, "", _open_stats, 52)
	_portrait = TextureRect.new()
	_portrait.set_anchors_preset(Control.PRESET_FULL_RECT)
	_portrait.offset_left = 5
	_portrait.offset_right = -5
	_portrait.offset_top = 3
	_portrait.offset_bottom = -3
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait_button.add_child(_portrait)
	portrait_button.tooltip_text = "Companion Status, Growth, and Skills"
	status_label = _label(row, "", 14, INK)
	status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_button(row, "More", func() -> void: _open_page("More"), 54)
	row = _row(box)
	_button(row, "−", func() -> void: habitat.set_zoom(habitat.zoom_multiplier - 0.15), 44)
	_zoom = _label(row, "100%", 12, INK)
	_zoom.tooltip_text = "0%: full map · 100%: companion close-up"
	_zoom.custom_minimum_size.x = 37
	_button(row, "+", func() -> void: habitat.set_zoom(habitat.zoom_multiplier + 0.15), 44)
	_follow = _button(row, "Follow", func() -> void: habitat.set_follow(_follow.button_pressed), 70)
	_follow.toggle_mode = true
	_follow.tooltip_text = "Gently follow your companion. Turn off or drag the field to explore freely."
	_button(row, "Field", func() -> void: _open_page("Background"))
	_warning = _button(_root, "Bathroom time · Guide to potty", _guide_to_potty)
	_warning.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_warning.offset_top = 128
	_warning.offset_left = 12
	_warning.offset_right = -12
	_warning.offset_bottom = 172
	_warning.hide()
	_care_panel = _panel(-188, -8, true)
	box = _stack(_care_panel)
	dialogue_label = _label(box, "A little care, a little adventure.", 14, INK)
	dialogue_label.custom_minimum_size.y = 44
	row = _row(box)
	_button(row, "Feed", func() -> void: _open_page("Food"))
	_button(row, "Pet", func() -> void: _care_action("pet"))
	_button(row, "Talk", func() -> void: _open_page("Talk"))
	row = _row(box)
	for title: String in ["Training", "Tools", "Battles", "Inventory"]:
		_button(row, title, func() -> void:
			if title == "Battles": _start_battle()
			else: _open_page(title)
		).add_theme_font_size_override("font_size", 12)

func _build_stats() -> void:
	stats_overlay = _overlay()
	var stack := _overlay_content(stats_overlay, "COMPANION")
	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var style := StyleBoxFlat.new()
	style.bg_color = Color("315c42")
	style.content_margin_top = 14
	style.content_margin_bottom = 14
	style.content_margin_left = 16
	style.content_margin_right = 16
	_tabs.add_theme_stylebox_override("tab_selected", style)
	_tabs.add_theme_stylebox_override("tab_unselected", style.duplicate())
	_tabs.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	stack.add_child(_tabs)
	stats_content = _tab("Status")
	var row := _row(stats_content)
	for key: String in ["happiness", "fullness", "discipline"]:
		var dial := StatDial.new()
		row.add_child(dial)
		dial.setup(key.to_upper(), 0, SUN if key == "fullness" else Color("85c9a8"))
		_dials[key] = dial
	_details = _label(stats_content, "", 16)
	var growth := _tab("Growth")
	_growth = _label(growth, "", 16)
	_button(growth, "Open Training", func() -> void: stats_overlay.hide(); _open_page("Training"))
	_label(growth, "Growth waits safely until you're ready. No death, forced rebirth, or punishment evolution.", 14)
	var skills := _tab("Skills")
	_skills_note = _label(skills, "", 16)
	for index: int in 3:
		_label(skills, "SLOT %d" % (index + 1), 13)
		var selector := OptionButton.new()
		selector.add_theme_color_override("font_focus_color", CREAM)
		selector.custom_minimum_size.y = 44
		selector.item_selected.connect(func(_choice: int) -> void: _save_skills())
		skills.add_child(selector)
		_selectors.append(selector)
		row = _row(skills)
		var automatic := CheckButton.new()
		automatic.add_theme_color_override("font_focus_color", CREAM)
		automatic.text = "Automatic use"
		automatic.custom_minimum_size.y = 44
		automatic.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		automatic.toggled.connect(func(_v: bool) -> void: _save_skills())
		row.add_child(automatic)
		_auto.append(automatic)
		_up.append(_button(row, "Move up", func() -> void: _move_up(index), 82))
	_label(skills, "The zero-MP melee fallback is always available outside these slots. Order sets move preference; nature and brains guide automatic choices. Loadouts can change only outside combat.", 14)

func _build_pages() -> void:
	_modal = _overlay()
	var stack := _overlay_content(_modal, "CARE & ADVENTURE")
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.add_child(scroll)
	var parent := VBoxContainer.new()
	parent.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(parent)
	for title: String in ["Training", "Tools", "Inventory", "More", "Background", "Talk", "Food"]:
		var page := VBoxContainer.new()
		page.add_theme_constant_override("separation", 12)
		parent.add_child(page)
		_pages[title] = page
		_label(page, title, 24)
	var page: VBoxContainer = _pages.Food
	_food_note = _label(page, "", 16)
	_label(page, "Pantry snacks are unlimited in this prototype. Every snack restores 30 Fullness. Favorites give extra Happiness; cravings give extra Happiness and Bond. Missing a craving has no penalty.", 14)
	for food_id: String in FoodRules.FOODS:
		var button := _button(page, FoodRules.label(food_id), func() -> void:
			_care_action("feed", food_id)
			_modal.hide()
		)
		button.icon = FoodRules.icon(food_id)
		button.expand_icon = true
		button.add_theme_constant_override("icon_max_width", 40)
		button.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_food_buttons[food_id] = button
	page = _pages.Training
	_label(page, "30 seconds per session. Fullness ≥20, Fatigue ≤70. Costs 5 Fullness; adds 15 Fatigue, +2 Discipline, −2 Happiness. At 50+ Fatigue, completing training has a 35% sickness risk. A training wish gives +1 extra stat (+5 HP/MP). Focus loss pauses; cancellation gives no reward.", 14)
	_training_note = _label(page, "Choose a session.", 16)
	_training_progress = ProgressBar.new()
	_training_progress.max_value = 30
	_training_progress.custom_minimum_size.y = 24
	page.add_child(_training_progress)
	for stat: String in Definitions.TRAINING:
		var definition: Dictionary = Definitions.TRAINING[stat]
		_training_buttons[stat] = _button(page, "%s · +%d %s" % [definition.name, definition.gain, stat.to_upper()], func() -> void:
			var result := GameState.start_training(stat)
			if not bool(result.ok): _training_note.text = result.error
		)
	_training_cancel = _button(page, "Cancel session · no reward", func() -> void: GameState.cancel_training())
	page = _pages.Tools
	_rest_note = _label(page, "", 16)
	_sleep_button = _button(page, "Sleep · 2-minute rest", func() -> void: _modal.hide(); _care_action("sleep"))
	_wake_button = _button(page, "Wake up early · no rest bonus", func() -> void: _modal.hide(); _care_action("wake"))
	_button(page, "Play together", func() -> void: _modal.hide(); _care_action("play"))
	_label(page, "A full sleep restores fatigue and clears sickness. If tired, sleepy or sick at bedtime, it also grants +2 Discipline. Play wishes give +5 extra Happiness and +3 base Bond. No penalty for missed wishes.", 14)
	for action: String in ["Praise", "Scold"]:
		_button(page, action, func() -> void: _modal.hide(); _care_action(action.to_lower()))
	_label(page, "Pet +4 Happiness. Praise +5 Happiness / −2 Discipline. Scold +5 Discipline / −5 Happiness. These share a 30-second reward cooldown. Praise and Scold give no bond.", 14)
	_button(page, "Pick up poop", _select_clean_tool)
	_guide = _button(page, "Guide to potty", _guide_to_potty)
	_button(page, "Build enclosure", _begin_edit)
	_material_note = _label(page, "", 14)
	_button(page, "Cook meat · 1 raw meat + 1 wood", func() -> void: _facility_action("cook_meat"))
	_button(page, "Cook potato · 1 potato + 1 wood", func() -> void: _facility_action("cook_potato"))
	_button(page, "Serve cooked meat", func() -> void: _serve_meal("steak"))
	_button(page, "Serve cooked potato", func() -> void: _serve_meal("sweet_potato"))
	_button(page, "Pond · Rinse and cool down", func() -> void: _facility_action("pond"))
	_button(page, "Prototype: refill building supplies", func() -> void: GameState.refill_prototype_materials())
	page = _pages.Inventory
	_inventory = _label(page, "", 17)
	_label(page, "Use recoveries in the running battle arena. Wins grant one of each. Decor counts show unplaced items.", 14)
	_button(page, "Place decorations", _begin_edit)
	page = _pages.More
	for destination: String in ["Friends", "Shop", "Equipment"]:
		_label(page, destination + " · Coming later", 20)
	_mute = CheckButton.new()
	_mute.add_theme_color_override("font_focus_color", CREAM)
	_mute.text = "Mute audio"
	_mute.custom_minimum_size.y = 44
	page.add_child(_mute)
	_motion = CheckButton.new()
	_motion.add_theme_color_override("font_focus_color", CREAM)
	_motion.text = "Reduce motion"
	_motion.custom_minimum_size.y = 44
	page.add_child(_motion)
	_mute.toggled.connect(func(_v: bool) -> void: _preferences())
	_motion.toggled.connect(func(_v: bool) -> void: _preferences())
	page = _pages.Background
	if OS.is_debug_build():
		_button(page, "Lighting preview · F7", func() -> void:
			_modal.hide()
			_day_night_preview.toggle()
		)
	_button(page, "Explore map · wide view", func() -> void: _set_map_view(true))
	_button(page, "Focus on companion", func() -> void:
		habitat.set_zoom(1.0)
		habitat.set_follow(true)
		_modal.hide()
	)
	_label(page, "Choose an unlocked home. Review builds expose all five regions; production uses only approved 3D packages and otherwise keeps the safe 2D field.", 16)
	_environment_note = _label(page, "", 13)
	for region: Dictionary in GameState.available_home_regions(true):
		var region_id := String(region.region_id)
		_region_buttons[region_id] = _button(page, String(region.home_name), func() -> void: _select_region(region_id))
	_label(page, "Fallback field appearance", 16)
	for entry: Array in [["verdant", "Verdant Field"], ["practice", "Quiet practice · solid color"]]:
		_button(page, entry[1], func() -> void:
			if _feedback(GameState.set_habitat_theme(entry[0])): _modal.hide()
		)
	page = _pages.Talk
	_label(page, "A moment together. Short local conversations help you bond.", 16)
	chat_input = LineEdit.new()
	chat_input.placeholder_text = "Say something…"
	chat_input.max_length = 500
	chat_input.custom_minimum_size.y = 48
	chat_input.text_submitted.connect(func(_text: String) -> void: _send_chat())
	page.add_child(chat_input)
	_button(page, "Send", _send_chat)

func _build_edit() -> void:
	_edit_panel = _panel(-412, -8, true)
	_edit_panel.hide()
	var box := _stack(_edit_panel)
	_edit_note = _label(box, "", 12, INK)
	_edit_note.custom_minimum_size.y = 30
	var choices := GridContainer.new()
	choices.columns = 2
	choices.add_theme_constant_override("h_separation", 7)
	choices.add_theme_constant_override("v_separation", 7)
	box.add_child(choices)
	for item: String in Definitions.DECOR:
		_decor_buttons[item] = _button(choices, "", func() -> void: habitat.place_item(item))
		_decor_buttons[item].add_theme_font_size_override("font_size", 12)
	var row := _row(box)
	for entry: Array in [["←", Vector2i.LEFT], ["↑", Vector2i.UP], ["↓", Vector2i.DOWN], ["→", Vector2i.RIGHT]]:
		_button(row, entry[0], func() -> void: habitat.nudge_selected(entry[1]), 44)
	_button(row, "Rotate", func() -> void: habitat.rotate_selected())
	_button(box, "Remove selected → inventory", func() -> void: habitat.remove_selected())
	row = _row(box)
	_apply = _button(row, "Build / Apply", _apply_edit)
	_button(row, "Cancel", _end_edit)

func _on_state_changed(snapshot: Dictionary) -> void:
	if snapshot.is_empty(): return
	_refreshing = true
	var preferences: Dictionary = snapshot.meta.get("preferences", {})
	_mute.set_pressed_no_signal(bool(preferences.get("muted", false)))
	_motion.set_pressed_no_signal(bool(preferences.get("reduced_motion", false)))
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"), _mute.button_pressed)
	habitat.reduced_motion = _motion.button_pressed
	habitat.effects.reduced_motion = _motion.button_pressed
	var region_id := String(snapshot.get("home_region", HabitatRules.DEFAULT_REGION))
	if _configured_region != region_id:
		habitat.configure_region(GameState.get_home_package())
		_configured_region = region_id
	habitat.update_snapshot(snapshot)
	var favorite := FoodRules.favorite(String(snapshot.identity.species_id))
	var craving := FoodRules.active(snapshot)
	_food_note.text = "Favorite: %s%s" % [FoodRules.label(favorite), "\nCraving: " + FoodRules.label(craving) if not craving.is_empty() else ""]
	for food_id: String in _food_buttons:
		_food_buttons[food_id].text = FoodRules.label(food_id) + (" · Favorite" if food_id == favorite else "") + (" · Craving" if food_id == craving else "")
		_food_buttons[food_id].disabled = float(snapshot.care.hunger) >= 96.0
	_craving_bubble.set_status(CareStatusRules.bubble(snapshot), craving)
	_craving_bubble.reduced_motion = habitat.reduced_motion
	var stock: Dictionary = snapshot.enclosure.materials
	_material_note.text = "Supplies: %d wood · %d stone · %d fiber\nRaw meat %d · Potatoes %d\nCooked meat %d · Cooked potatoes %d" % [stock.wood, stock.stone, stock.fiber, stock.raw_meat, stock.potato, snapshot.enclosure.meals.steak, snapshot.enclosure.meals.sweet_potato]
	var status: Dictionary = snapshot.care.status
	_rest_note.text = "Fatigue: %d / 100 · Sleepiness: %d / 100%s%s" % [roundi(snapshot.care.fatigue), roundi(status.sleep_need), "\nSick — complete a full sleep to recover." if status.sick else "", "\nSleeping: %ds remaining" % ceili(status.sleep_remaining) if status.sleeping else ""]
	_sleep_button.visible = not status.sleeping
	_wake_button.visible = status.sleeping
	status_label.text = "%s · %s\n%s · %s · %s" % [snapshot.identity.companion_name, snapshot.identity.species_name, snapshot.identity.stage, snapshot.identity.nature, HabitatRules.REGION_HOMES[region_id].name]
	if is_instance_valid(_environment_note):
		_environment_note.text = habitat.presentation_notice if not habitat.presentation_notice.is_empty() else "3D environment package active."
	for region: Dictionary in GameState.available_home_regions(true):
		var button: Button = _region_buttons.get(region.region_id)
		if button != null:
			button.disabled = not bool(region.unlocked) or bool(region.active)
			button.text = "%s%s" % [region.home_name, " · Current" if region.active else (" · Locked" if not region.unlocked else "")]
	if avatar.sprite.sprite_frames != null:
		_portrait.texture = avatar.sprite.sprite_frames.get_frame_texture(avatar.sprite.animation, 0)
	_follow.set_pressed_no_signal(habitat.follow)
	_zoom.text = "%d%%" % roundi(habitat.zoom_multiplier * 100)
	_populate_stats()
	var inventory_lines: Array[String] = []
	for item: String in Definitions.ITEMS:
		inventory_lines.append("%s × %d" % [Definitions.ITEMS[item].name, snapshot.inventory.items[item]])
	inventory_lines.append("\nDecorations")
	for item: String in Definitions.DECOR:
		inventory_lines.append("%s × %d" % [Definitions.DECOR[item].name, snapshot.inventory.decor[item]])
	_inventory.text = "\n".join(inventory_lines)
	_update_training(GameState.get_training_status())
	var potty := GameState.get_potty_status()
	var warning := bool(potty.get("warning", false))
	_warning.visible = warning and not habitat.editing
	_warning.text = "Bathroom · %ds · %s" % [maxi(0, ceili(float(potty.get("remaining", 0)))), "Going to potty" if habitat._route_is_potty else "Guide to potty"]
	_warning.disabled = not bool(potty.get("can_guide", false)) or habitat._route_is_potty
	_guide.disabled = _warning.disabled
	if warning and bool(potty.get("automatic", false)) and not habitat.editing and not habitat._route_is_potty and _warning_seen != float(snapshot.care.next_poop_at):
		_warning_seen = float(snapshot.care.next_poop_at)
		habitat.begin_route(potty.get("path", []), false)
	elif not warning and habitat._route_is_potty:
		habitat.stop_route()
		GameState.cancel_potty_guidance()
	_refreshing = false

func _populate_stats() -> void:
	var state := GameState.get_state()
	var stats := GameState.get_stats()
	for key: String in _dials: _dials[key].value = float(stats.get(key, 0))
	var lines: Array[String] = ["%s · %s · %s nature" % [stats.name, stats.stage, stats.nature], ""]
	for key: String in ["hp", "mp", "offense", "defense", "speed", "brains"]:
		lines.append("%s    %d" % [key.to_upper(), state.battle_profile[key]])
	for key: String in ["bond", "fatigue", "virus", "potty_habit"]:
		lines.append("%s    %d / 100" % [key.replace("_", " ").capitalize(), roundi(float(state.care[key]))])
	lines.append("Age    %d days\nWeight    %.1f G\nActive time    %dm\nCare mistakes    %d lifetime / %d stage\nField waste    %d\nBattle record    %d W / %d L / %d D" % [stats.age_days, stats.weight, floori(float(stats.active_seconds) / 60), state.care.care_mistakes, state.care.stage_care_mistakes, state.care.poop_count, state.battle.wins, state.battle.losses, state.battle.draws])
	_details.text = "\n".join(lines)
	_details.text += "\nFavorite food    " + FoodRules.label(FoodRules.favorite(String(state.identity.species_id)))
	_details.text += "\nSleepiness    %d / 100\nCondition    %s" % [roundi(state.care.status.sleep_need), "Sleeping" if state.care.status.sleeping else ("Sick — needs rest" if state.care.status.sick else ("Tired" if state.care.fatigue >= CareStatusRules.TIRED else "Well"))]
	var readiness := CareRules.evolution_readiness(state)
	lines.clear()
	if readiness.has("target"):
		lines.append("Next form: " + CareRules.SPECIES_NAMES[String(readiness.target)] + "\n\nUnmet requirements:")
		for unmet: Variant in readiness.get("unmet_requirements", []): lines.append("• " + String(unmet))
		if readiness.get("unmet_requirements", []).is_empty(): lines.append("Ready to evolve.")
	else: lines.append("Agumon is the final form in this prototype.")
	lines.append("\nTraining history")
	for stat: String in Definitions.TRAINING:
		lines.append("%s: %d completed" % [stat.capitalize(), state.progression.training_history.get(stat, 0)])
	lines.append("\nCare this stage: %s meal · %s play/pet · %s chat" % ["✓" if state.progression.stage_actions.get("feed", false) else "—", "✓" if state.progression.stage_actions.get("play", false) else "—", "✓" if state.progression.stage_actions.get("chat", false) else "—"])
	_growth.text = "\n".join(lines)
	_refresh_skills(state)

func _refresh_skills(state: Dictionary) -> void:
	var before := _refreshing
	_refreshing = true
	var unlocked: bool = state.identity.species_id == "agumon"
	_skills_note.text = "Three slots · choose order and automatic use." if unlocked else "Skills unlock at Rookie. Your companion keeps its built-in attacks until then."
	for index: int in 3:
		var selector := _selectors[index]
		if selector.item_count != state.skills.learned.size() + 1:
			selector.clear()
			selector.add_item("Empty slot")
			selector.set_item_metadata(0, "")
			for move: String in state.skills.learned:
				var metadata: Dictionary = Definitions.MOVES.get(move, Definitions.MOVE_IDENTITIES.get(move, {}))
				var cost := "%d MP" % int(metadata.mp) if metadata.has("mp") else "table unavailable"
				selector.add_item("%s · %s" % [metadata.get("name", move), cost])
				selector.set_item_metadata(selector.item_count - 1, move)
		var equipped: Dictionary = state.skills.equipped[index] if index < state.skills.equipped.size() else {}
		for choice: int in selector.item_count:
			if selector.get_item_metadata(choice) == equipped.get("move_id", ""): selector.select(choice)
		selector.disabled = not unlocked
		_auto[index].set_pressed_no_signal(bool(equipped.get("auto", true)))
		_auto[index].disabled = not unlocked or equipped.is_empty()
		_up[index].disabled = not unlocked or index == 0 or equipped.is_empty()
	_refreshing = before

func _save_skills() -> void:
	if _refreshing: return
	var slots: Array = []
	for index: int in 3:
		var move := String(_selectors[index].get_selected_metadata())
		if not move.is_empty(): slots.append({"move_id": move, "auto": _auto[index].button_pressed})
	var result := GameState.set_skill_loadout(slots)
	if not bool(result.ok):
		_refresh_skills(GameState.get_state())
		_skills_note.text = result.error

func _move_up(index: int) -> void:
	var slots: Array = GameState.get_state().skills.equipped.duplicate(true)
	if index <= 0 or index >= slots.size(): return
	var prior: Dictionary = slots[index - 1]
	slots[index - 1] = slots[index]
	slots[index] = prior
	_feedback(GameState.set_skill_loadout(slots))

func _process(_delta: float) -> void:
	_update_craving_bubble()
	if is_instance_valid(_map_zoom):
		_map_zoom.text = "%d%%" % roundi(habitat.zoom_multiplier * 100)
	if is_instance_valid(_training_note): _update_training(GameState.get_training_status())
	if is_instance_valid(_zoom):
		_zoom.text = "%d%%" % roundi(habitat.zoom_multiplier * 100)
		_follow.set_pressed_no_signal(habitat.follow)

func _update_training(status: Dictionary) -> void:
	var active := bool(status.get("active", false))
	_training_progress.value = float(status.get("elapsed", 0))
	_training_progress.visible = active
	_training_cancel.visible = active
	_training_note.text = "%s · %ds / 30s%s" % [String(status.get("stat", "")).capitalize(), floori(float(status.get("elapsed", 0))), " · Paused" if status.get("paused", false) else ""] if active else "Choose a session. Fatigue recovers 1 point per minute outside training."
	var state := GameState.get_state()
	if not active and state.care.fatigue >= CareStatusRules.TIRED:
		_training_note.text = "Tired! Training now risks sickness (35%). Sleep in Tools first, or choose Train anyway."
	elif not active and CareStatusRules.wish(state) == "train":
		_training_note.text = "Motivated! Start a session now for +1 extra stat (+5 HP/MP)."
	elif not active and (state.care.status.sick or state.care.status.sleeping):
		_training_note.text = "Rest first. A full sleep clears sickness."
	for stat: String in _training_buttons:
		_training_buttons[stat].disabled = active or not bool(CareRules.training_readiness(state, stat).ok)
		var definition: Dictionary = Definitions.TRAINING[stat]
		_training_buttons[stat].text = ("Train anyway · " if state.care.fatigue >= CareStatusRules.TIRED else "") + "%s · +%d %s" % [definition.name, definition.gain, stat.to_upper()]

func _thought_pressed() -> void:
	match _craving_bubble.status_kind:
		"food": _open_page("Food")
		"play": _care_action("play")
		"train": _open_page("Training")
		_: _open_page("Tools")

func _care_action(action: String, payload: String = "") -> void:
	var result := GameState.execute_command(action, payload)
	dialogue_label.text = result.message
	if bool(result.accepted):
		habitat._care_pause = 1.5
		habitat.play_action(result.animation)
		if action == "feed": _audio.eat.play(); habitat.effects.play_effect("feed")
		elif action == "pet": habitat.effects.play_effect("pet")

func _update_craving_bubble() -> void:
	if not is_instance_valid(_craving_bubble):
		return
	_craving_bubble.visible = not _craving_bubble.status_kind.is_empty() and not habitat.editing and not _modal.visible and not stats_overlay.visible and not evolution_overlay.visible
	if not _craving_bubble.visible:
		return
	var head := Vector2.ZERO
	var feet := Vector2.ZERO
	if habitat.using_3d and is_instance_valid(habitat.avatar_3d):
		var camera := habitat.environment_3d.camera
		var root_position := habitat.avatar_3d.position
		if camera.is_position_behind(root_position):
			_craving_bubble.hide()
			return
		head = camera.unproject_position(habitat.avatar_3d.head_world_position())
		feet = camera.unproject_position(root_position)
	else:
		head = habitat.viewport.canvas_transform * (habitat.avatar.position + Vector2(0, -100))
		feet = habitat.viewport.canvas_transform * habitat.avatar.position
	# Keep the request visible when a close-up crops the head, but do not pin
	# an off-screen companion's bubble to the edge during manual exploration.
	if head.x < 0 or head.x > habitat.size.x or head.y > habitat.size.y or feet.y < 0:
		_craving_bubble.hide()
		return
	_craving_bubble.position = habitat.position + Vector2(clampf(head.x - 34, 4, habitat.size.x - 72), maxf(4, head.y - 84))

func _send_chat() -> void:
	var result := GameState.execute_command("chat", chat_input.text.strip_edges())
	dialogue_label.text = result.message
	if bool(result.accepted):
		chat_input.clear()
		_modal.hide()
		habitat._care_pause = 1.5
		habitat.play_action(result.animation)


func _select_region(region_id: String) -> void:
	var result := GameState.select_home_region(region_id)
	if not _feedback(result):
		return
	# The committed state_changed signal has already hydrated the incoming map.
	# home_region_changed invalidates the cache after that signal, so acknowledge
	# the region here without configuring the presentation a second time.
	_configured_region = String(result.region_id)
	dialogue_label.text = "%s is now home.%s" % [HabitatRules.REGION_HOMES[region_id].name, " " + habitat.presentation_notice if not habitat.presentation_notice.is_empty() else ""]
	_modal.hide()


func _on_creature_cell_changed(cell: Vector2i) -> void:
	if GameState.set_creature_cell(cell):
		return
	# The simulation authority rejected this presentation step (for example, a
	# newly pinned blocker). Cancel the stale route and rehydrate both renderers
	# from the last acknowledged durable cell.
	habitat.stop_route()
	habitat.update_snapshot(GameState.get_state())

func _select_clean_tool() -> void:
	_modal.hide()
	clean_mode = not habitat._poops.is_empty()
	dialogue_label.text = "Cleanup tool ready — tap a pile in the field." if clean_mode else "The field is already clean."

func _on_poop_selected(index: int) -> void:
	if not clean_mode:
		dialogue_label.text = "Choose Pick up poop from Tools first."
		return
	var result := GameState.execute_command("clean", str(index))
	dialogue_label.text = result.message
	clean_mode = false

func _guide_to_potty() -> void:
	var result := GameState.begin_potty_guidance()
	if not _feedback(result): return
	_modal.hide()
	habitat.begin_route(result.path, true)
	dialogue_label.text = "Let's follow the path to the potty."

func _arrived(guided: bool) -> void:
	if not guided:
		dialogue_label.text = "Your companion knows where to go."
		return
	if _feedback(GameState.complete_potty_guidance()):
		dialogue_label.text = "Potty habit +20 · Discipline +2."
		habitat.effects.play_effect("pet")

func _open_stats() -> void:
	clean_mode = false
	_modal.hide()
	_populate_stats()
	stats_overlay.show()
	_sync_modal_focus.call_deferred()

func _open_page(title: String) -> void:
	clean_mode = false
	for key: String in _pages: _pages[key].visible = key == title
	_modal.show()
	_update_craving_bubble()
	_sync_modal_focus.call_deferred()
	if title == "Talk": chat_input.grab_focus()

func _begin_edit() -> void:
	_modal.hide()
	if bool(GameState.get_training_status().get("active", false)):
		dialogue_label.text = "Finish or cancel training before decorating."
		return
	GameState.cancel_potty_guidance()
	habitat.begin_edit()
	_care_panel.hide()
	_edit_panel.show()
	habitat.offset_bottom = -272
	_warning.hide()
	_refresh_edit()

func _refresh_edit() -> void:
	if not habitat.editing: return
	var valid := GameState.quote_habitat_layout(habitat.draft)
	_apply.disabled = not bool(valid.ok)
	var state := GameState.get_state()
	var stock: Dictionary = state.enclosure.materials
	_edit_note.text = "Wood %d · Stone %d · Fiber %d\n" % [stock.wood, stock.stone, stock.fiber]
	if valid.ok:
		_edit_note.text += "Cost: %d wood · %d stone · %d fiber\nDrag / arrows · Rotate · Green = ready" % [valid.cost.wood, valid.cost.stone, valid.cost.fiber]
	else: _edit_note.text += String(valid.error)
	for item: String in _decor_buttons:
		var available := int(state.inventory.decor[item])
		for placed: Dictionary in state.habitat.items:
			if placed.item_id == item: available += 1
		for placed: Dictionary in habitat.draft.items:
			if placed.item_id == item: available -= 1
		var d: Dictionary = Definitions.DECOR[item]
		var costs: Array[String] = []
		for material: String in d.cost: costs.append("%d %s" % [d.cost[material], material])
		_decor_buttons[item].text = "%s · %d×%d\n%s" % [d.name, d.size[0], d.size[1], "Stored ×%d" % available if available > 0 else " + ".join(costs)]
		_decor_buttons[item].disabled = false

func _facility_action(action: String) -> void:
	var state := GameState.get_state()
	if state.care.status.sleeping or GameState.get_training_status().active:
		dialogue_label.text = "Finish resting or training first."
		_modal.hide()
		return
	var kind := "pond" if action == "pond" else "campfire"
	var path := HabitatRules.path_to_facility(state.habitat, kind, habitat.habitat_manifest)
	_modal.hide()
	if path.is_empty():
		dialogue_label.text = "Build a reachable %s first." % kind
		return
	GameState.cancel_potty_guidance()
	habitat.begin_facility_route(path, action)
	dialogue_label.text = "Heading to the %s…" % kind

func _complete_facility_action(action: String) -> void:
	var result := GameState.use_enclosure_facility(action)
	dialogue_label.text = String(result.get("message", result.get("error", "")))
	_modal.hide()
	if result.ok: habitat.play_action("happy")

func _serve_meal(meal: String) -> void:
	var result := GameState.serve_cooked_meal(meal)
	dialogue_label.text = String(result.get("message", result.get("error", "")))
	_modal.hide()
	if result.ok: habitat.play_action("eat")

func _apply_edit() -> void:
	var result := GameState.apply_habitat_layout(habitat.draft)
	if bool(result.ok): _end_edit(); dialogue_label.text = "Habitat saved."
	else: _edit_note.text = result.error

func _end_edit() -> void:
	habitat.end_edit()
	habitat.offset_bottom = -194
	_edit_panel.hide()
	_care_panel.show()

func _preferences() -> void:
	if not _refreshing: _feedback(GameState.set_preferences(_mute.button_pressed, _motion.button_pressed))

func _exit_tree() -> void:
	for player: AudioStreamPlayer in _audio.values():
		player.stop()
		player.stream = null

func _start_battle() -> void:
	var encounter_id := EncounterCatalog.encounter_for_region(GameState.get_home_region())
	if not _feedback(GameState.start_training_battle(-1, encounter_id)): return
	if get_tree().change_scene_to_file("res://scenes/battle_scene.tscn") != OK:
		GameState.clear_active_battle()
		dialogue_label.text = "Could not open the arena. No reward was applied."

func _evolve(from_species: String, to_species: String) -> void:
	evolution_overlay.show()
	evolution_label.text = "%s → %s" % [CareRules.SPECIES_NAMES[from_species], CareRules.SPECIES_NAMES[to_species]]
	_audio.evolution.play()
	if not _motion.button_pressed:
		evolution_label.modulate.a = 0
		create_tween().tween_property(evolution_label, "modulate:a", 1.0, 0.6)
	await get_tree().create_timer(1.0 if _motion.button_pressed else 2.4).timeout
	evolution_overlay.hide()

func _feedback(result: Dictionary) -> bool:
	if not bool(result.get("ok", false)): dialogue_label.text = String(result.get("error", "Please try again."))
	return bool(result.get("ok", false))

func _unhandled_key_input(event: InputEvent) -> void:
	if OS.is_debug_build() and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F7:
		_day_night_preview.toggle()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_cancel"):
		if habitat.editing: _end_edit()
		elif stats_overlay.visible: stats_overlay.hide()
		elif _modal.visible: _modal.hide()
		elif _exploring_map: _set_map_view(false)
		else: clean_mode = false
		get_viewport().set_input_as_handled()


func _build_map_bar() -> void:
	_map_bar = _panel(8, 68, false)
	_map_bar.anchor_right = 0.0
	_map_bar.offset_right = 352
	var row := _row(_stack(_map_bar))
	_button(row, "Back", func() -> void: _set_map_view(false), 64)
	_button(row, "−", func() -> void: habitat.set_zoom(habitat.zoom_multiplier - 0.1), 44)
	_map_zoom = _label(row, "45%", 12, INK)
	_map_zoom.custom_minimum_size.x = 37
	_button(row, "+", func() -> void: habitat.set_zoom(habitat.zoom_multiplier + 0.1), 44)
	_button(row, "Focus", func() -> void:
		habitat.set_zoom(1.0)
		habitat.set_follow(true)
	, 70)
	_map_bar.hide()


func _set_map_view(enabled: bool) -> void:
	if habitat.editing:
		_end_edit()
	_exploring_map = enabled
	_modal.hide()
	_header_panel.visible = not enabled
	_care_panel.visible = not enabled
	_map_bar.visible = enabled
	habitat.offset_top = 0 if enabled else 126
	habitat.offset_bottom = 0 if enabled else -194
	if enabled:
		# A playable mid-distance composition, not the tiny full-map overview.
		# Tall windows need a closer crop to avoid exposing the terrain's far edge.
		habitat.set_zoom(0.75 if _root.size.y > _root.size.x else 0.45)
		habitat.set_follow(true)
		if habitat.using_3d:
			habitat.environment_3d.update_home_target(habitat.avatar.position, true)
		habitat.set_follow(false)
		habitat.grab_focus()
	else:
		_follow.grab_focus()

func _tab(title: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = title
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_tabs.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 12)
	scroll.add_child(box)
	return box

func _overlay() -> ColorRect:
	var overlay := ColorRect.new()
	overlay.color = Color("172b23")
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.hide()
	_root.add_child(overlay)
	overlay.visibility_changed.connect(_sync_modal_focus)
	return overlay

func _sync_modal_focus() -> void:
	var active: Control = null
	for child: Node in _root.get_children():
		if child is ColorRect and child.visible and child != _root.get_child(0): active = child
	for raw: Node in _root.find_children("*", "Control", true, false):
		var control := raw as Control
		var id := control.get_instance_id()
		if not _focus_modes.has(id): _focus_modes[id] = control.focus_mode
		control.focus_mode = _focus_modes[id] if active == null or active.is_ancestor_of(control) else Control.FOCUS_NONE
	if active != null:
		var focused := get_viewport().gui_get_focus_owner()
		if focused == null or not active.is_ancestor_of(focused):
			for raw: Node in active.find_children("*", "Button", true, false):
				var button := raw as Button
				if button.is_visible_in_tree() and not button.disabled:
					button.grab_focus()
					break

func _overlay_content(overlay: Control, title: String) -> VBoxContainer:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + side, 12)
	overlay.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	margin.add_child(box)
	var row := _row(box)
	var heading := _label(row, title, 21)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_button(row, "Close", func() -> void: overlay.hide(), 64)
	return box

func _panel(top: float, bottom: float, bottom_anchor: bool) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE if bottom_anchor else Control.PRESET_TOP_WIDE)
	panel.offset_left = 10
	panel.offset_right = -10
	panel.offset_top = top
	panel.offset_bottom = bottom
	var style := StyleBoxFlat.new()
	style.bg_color = Color("f0f1dc")
	style.set_corner_radius_all(14)
	panel.add_theme_stylebox_override("panel", style)
	_root.add_child(panel)
	return panel

func _stack(parent: Node) -> VBoxContainer:
	var margin := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + side, 10)
	parent.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 7)
	margin.add_child(box)
	return box

func _row(parent: Node) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	parent.add_child(row)
	return row

func _label(parent: Node, text: String, font_size: int = 16, color: Color = CREAM) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)
	return label

func _button(parent: Node, title: String, action: Callable, width: float = 0) -> Button:
	var button := Button.new()
	button.text = title
	button.custom_minimum_size = Vector2(width, 44)
	if width == 0: button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.add_theme_font_size_override("font_size", 14)
	for key: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]: button.add_theme_color_override(key, INK)
	for key: String in ["normal", "hover", "pressed"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color("cee0be") if key != "pressed" else Color("b3cd9b")
		style.set_corner_radius_all(9)
		style.content_margin_left = 5
		style.content_margin_right = 5
		button.add_theme_stylebox_override(key, style)
	button.pressed.connect(action)
	parent.add_child(button)
	return button
