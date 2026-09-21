extends Node2D

## GameState owns live ticks/rewards; replay owns a separate pure simulation.
const CREAM := Color("f5efda")
const GOLD := Color("efc46c")
const INK := Color("10201b")
const ORDERS := ["auto", "attack", "defend", "keep_distance"]
const ORDER_LABELS := ["Auto", "Attack", "Defend", "Keep distance"]
const BattleCues = preload("res://scripts/battle/battle_presentation_cues.gd")
const BattleAudio = preload("res://scripts/battle/battle_event_audio.gd")
const Effects = preload("res://scripts/world/companion_effects.gd")

var arena_view := ArenaView.new()
var environment_view := BattleWorldPresentation3D.new()
var player_avatar := CompanionAvatar.new()
var opponent_avatar := CompanionAvatar.new()
var playback := BattlePlaybackModel.new()
var battle: Dictionary = {}
var fighter_by_id: Dictionary = {}
var avatars: Dictionary = {}
var enemy_cards: Dictionary = {}
var order_buttons: Dictionary = {}
var player_hp_bar := ProgressBar.new()
var player_mp_bar := ProgressBar.new()
var opponent_hp_bar := ProgressBar.new()
var opponent_mp_bar := ProgressBar.new()
var player_value := Label.new()
var opponent_value := Label.new()
var event_label := Label.new()
var order_label := Label.new()
var clock_label := Label.new()
var art_label := Label.new()
var result_label := Label.new()
var reward_label := Label.new()
var return_button: Button
var replay_button: Button
var retry_button: Button
var speed_button: Button
var skip_button: Button
var _result_panel := PanelContainer.new()
var _hud := Control.new()
var _header_backdrop := ColorRect.new()
var _controls_backdrop := ColorRect.new()
var _header := HBoxContainer.new()
var _order_row := HBoxContainer.new()
var _bottom_row := HBoxContainer.new()
var _geometry := CheckButton.new()
var _title := Label.new()
var _arena_rect := Rect2(15, 120, 360, 539)
var _accumulator := 0.0
var _is_replay := false
var _settlement_seen := false
var _missing_art := ""
var _leaving := false
var _discard_next_delta := false
var move_buttons: Dictionary = {}
var item_buttons: Dictionary = {}
var effects_by_id: Dictionary = {}
var _effect_records: Dictionary = {}
var _action_row := HBoxContainer.new()
var moves_button: Button
var items_button: Button
var _picker := PanelContainer.new()
var _picker_title := Label.new()
var _picker_note := Label.new()
var _picker_feedback := Label.new()
var _picker_scroll := ScrollContainer.new()
var _move_list := VBoxContainer.new()
var _item_list := GridContainer.new()
var _picker_mode := ""
var _picker_close: Button
var _motion := CheckButton.new()
var _zoom_row := HBoxContainer.new()
var _zoom_fit: Button
var _environment_enabled := false
var _presentation_notice := ""
var defense_buttons: Dictionary = {}
var _ability_row := HBoxContainer.new()
var _diagnostics := PanelContainer.new()
var _diagnostics_button: Button
var _audio := BattleAudio.new()
var _feedback_until_msec := 0


func _ready() -> void:
	if "--battle-demo" in OS.get_cmdline_user_args() and GameState.isolated_mode and GameState.active_battle_result.is_empty():
		GameState.state.identity.species_id = "agumon"
		GameState.state.identity.species_name = "Agumon"
		GameState.state.identity.stage = "Rookie"
		GameState.state.identity.companion_name = "Partner"
		GameState.state.skills = GameDefinitions.default_skills("agumon")
		GameState.state.battle_profile.merge({"hp": 92, "mp": 48, "offense": 8, "defense": 7, "speed": 14, "brains": 24}, true)
		GameState.start_training_battle(2468, "forest")
	battle = GameState.active_battle_result # Borrowed, never mutated here.
	add_child(_audio)
	_audio.muted = bool(GameState.state.get("meta", {}).get("preferences", {}).get("muted", false))
	add_child(environment_view)
	add_child(arena_view)
	environment_view.visible = false
	_build_interface()
	_motion.button_pressed = bool(GameState.state.get("meta", {}).get("preferences", {}).get("reduced_motion", false))
	if GameState.has_signal("battle_command_resolved"):
		GameState.connect("battle_command_resolved", _on_battle_command_resolved)
	get_viewport().size_changed.connect(_layout)
	if battle.is_empty() or not battle.get("ok", false):
		event_label.text = "No active battle. Return to your companion to begin training."
		_layout()
		_refresh_controls()
		return
	arena_view.configure(battle.arena)
	_environment_enabled = _configure_environment_presentation()
	arena_view.visible = not _environment_enabled
	for fighter: Dictionary in battle.fighters:
		fighter_by_id[fighter.fighter_id] = fighter
	_configure_fighters()
	_build_picker_entries()
	_layout()
	_render_frame(1)
	_refresh_controls()
	if battle.get("complete", false):
		_show_result()


func _exit_tree() -> void:
	if _environment_enabled:
		environment_view.clear_battle()
	EnvironmentAssetLibrary.clear_active()
	# The legacy adapters are pre-created for an atomic fallback. In a successful
	# 3D session they never enter the tree, so release those otherwise-orphan Nodes.
	for avatar: CompanionAvatar in [player_avatar, opponent_avatar]:
		if is_instance_valid(avatar) and avatar.get_parent() == null:
			if is_instance_valid(avatar.sprite) and avatar.sprite.get_parent() == null:
				avatar.sprite.free()
			avatar.free()


func _process(delta: float) -> void:
	if battle.is_empty() or _leaving:
		return
	if GameState.battle_paused:
		_accumulator = 0
		_discard_next_delta = true
		clock_label.text = "PAUSED"
		_refresh_controls()
		return
	if _discard_next_delta:
		_discard_next_delta = false
		_accumulator = 0
		_render_frame(1)
		return
	if _is_replay:
		for event: Dictionary in playback.advance(delta):
			_apply_event(event)
		_render_frame(1)
		if playback.is_complete():
			_show_result()
		return
	if not battle.get("complete", false):
		_accumulator += minf(maxf(0, delta), 0.25)
		while _accumulator + 1e-9 >= 1.0 / BattleSimulator.TICKS_PER_SECOND and not battle.get("complete", false):
			for event: Dictionary in GameState.advance_training_battle():
				_apply_event(event)
			_accumulator = maxf(0, _accumulator - 1.0 / BattleSimulator.TICKS_PER_SECOND)
		_render_frame(clampf(_accumulator * BattleSimulator.TICKS_PER_SECOND, 0, 1))
	if battle.get("complete", false) and not _settlement_seen:
		_accumulator = 0
		_settlement_seen = true
		_render_frame(1)
		_show_result()


func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_IN, NOTIFICATION_APPLICATION_RESUMED]:
		# OS suspension may skip every frame between focus-out and focus-in.
		# Discard that first stale delta for BOTH live and read-only replay clocks.
		_accumulator = 0
		_discard_next_delta = true


func _build_interface() -> void:
	var canvas := CanvasLayer.new()
	canvas.layer = 10
	add_child(canvas)
	canvas.add_child(_hud)
	_hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for backdrop: ColorRect in [_header_backdrop, _controls_backdrop]:
		backdrop.color = Color(INK, 0.94)
		backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_hud.add_child(backdrop)
	_title.text = "FOREST TRAINING"
	_label_style(_title, 17, GOLD)
	_hud.add_child(_title)
	clock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_label_style(clock_label, 12, CREAM)
	_hud.add_child(clock_label)
	_header.add_theme_constant_override("separation", 14)
	_hud.add_child(_header)
	_fighter_card("YOUR PARTNER", player_hp_bar, player_mp_bar, player_value)
	_fighter_card("TRAINING FOE", opponent_hp_bar, opponent_mp_bar, opponent_value)
	event_label.text = "Watch their spacing. Give an order when it matters."
	event_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label_style(event_label, 13, CREAM)
	_hud.add_child(event_label)
	_label_style(order_label, 12, GOLD)
	_hud.add_child(order_label)
	_order_row.add_theme_constant_override("separation", 6)
	_hud.add_child(_order_row)
	for index: int in ORDERS.size():
		var order := String(ORDERS[index])
		var button := _button(ORDER_LABELS[index], Vector2(0, 44))
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(_give_order.bind(order))
		_order_row.add_child(button)
		order_buttons[order] = button
	_action_row.add_theme_constant_override("separation", 6)
	_hud.add_child(_action_row)
	moves_button = _button("Moves", Vector2(0, 44))
	moves_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	moves_button.pressed.connect(_toggle_picker.bind("moves"))
	# Retained for compatibility with previous scene callers; abilities are direct.
	moves_button.visible = false
	_action_row.add_child(moves_button)
	for defense: String in ["dodge", "guard"]:
		var button := _button(defense.capitalize(), Vector2(0, 48))
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(_request_defense.bind(defense))
		_action_row.add_child(button)
		defense_buttons[defense] = button
	_ability_row.add_theme_constant_override("separation", 6)
	_hud.add_child(_ability_row)
	items_button = _button("Items [I]", Vector2(0, 48))
	items_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	items_button.pressed.connect(_toggle_picker.bind("items"))
	_action_row.add_child(items_button)
	_label_style(art_label, 10, Color(CREAM, 0.54))
	art_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	art_label.visible = false
	_hud.add_child(art_label)
	_bottom_row.add_theme_constant_override("separation", 6)
	_hud.add_child(_bottom_row)
	_diagnostics_button = _button("View", Vector2(50, 44))
	_diagnostics_button.pressed.connect(func() -> void:
		_diagnostics.visible = not _diagnostics.visible
		_layout())
	_bottom_row.add_child(_diagnostics_button)
	return_button = _button("Leave · no reward", Vector2(128, 34))
	return_button.pressed.connect(_return_to_care)
	_bottom_row.add_child(return_button)
	replay_button = _button("Replay", Vector2(69, 34))
	replay_button.pressed.connect(_start_replay)
	_bottom_row.add_child(replay_button)
	retry_button = _button("Retry save", Vector2(84, 34))
	retry_button.pressed.connect(_retry_save)
	_bottom_row.add_child(retry_button)
	speed_button = _button("1×", Vector2(42, 34))
	speed_button.pressed.connect(_cycle_speed)
	_bottom_row.add_child(speed_button)
	skip_button = _button("Skip", Vector2(47, 34))
	skip_button.pressed.connect(_skip)
	_bottom_row.add_child(skip_button)
	_geometry.text = "Geometry"
	_geometry.custom_minimum_size.y = 44
	_geometry.add_theme_font_size_override("font_size", 10)
	_geometry.toggled.connect(func(value: bool) -> void:
		if _environment_enabled:
			environment_view.set_debug_geometry(value)
		else:
			arena_view.debug_overlays = value
			arena_view.queue_redraw()
			arena_view.render_session(_display_session()))
	_hud.add_child(_diagnostics)
	_diagnostics.add_theme_stylebox_override("panel", _panel(Color("162f26"), GOLD))
	var diagnostic_stack := VBoxContainer.new()
	_diagnostics.add_child(diagnostic_stack)
	diagnostic_stack.add_child(_geometry)
	art_label.reparent(diagnostic_stack)
	art_label.visible = true
	_diagnostics.visible = false
	_motion.text = "Less motion"
	_motion.custom_minimum_size.y = 44
	_motion.add_theme_font_size_override("font_size", 10)
	_motion.toggled.connect(func(value: bool) -> void:
		environment_view.set_reduced_motion(value)
		arena_view.reduced_motion = value
		for effect: CompanionEffects in effects_by_id.values():
			effect.reduced_motion = value)
	diagnostic_stack.add_child(_motion)
	diagnostic_stack.add_child(_zoom_row)
	for label: String in ["−", "Fit", "+"]:
		var button := _button(label, Vector2(44, 36))
		_zoom_row.add_child(button)
		if label == "Fit":
			_zoom_fit = button
			button.pressed.connect(func() -> void: _set_view_zoom(1.0))
		else:
			var factor := 1.15 if label == "+" else 1.0 / 1.15
			button.pressed.connect(func() -> void: _set_view_zoom(environment_view.battle_zoom_multiplier * factor))
	_zoom_row.tooltip_text = "Zoom view · Fit restores both fighters. Mouse wheel or trackpad pinch also zooms."
	environment_view.gui_input.connect(_on_field_zoom_input)
	_result_panel.add_theme_stylebox_override("panel", _panel(Color(0.04, 0.1, 0.08, 0.94), GOLD))
	_result_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(_result_panel)
	var stack := VBoxContainer.new()
	_result_panel.add_child(stack)
	result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label_style(result_label, 23, GOLD)
	stack.add_child(result_label)
	reward_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	reward_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label_style(reward_label, 13, CREAM)
	stack.add_child(reward_label)
	_result_panel.visible = false
	_build_picker()


func _build_picker() -> void:
	_picker.name = "BattleCommandPicker"
	_picker.add_theme_stylebox_override("panel", _panel(Color("162f26"), GOLD))
	_hud.add_child(_picker)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 6)
	_picker.add_child(stack)
	var heading := HBoxContainer.new()
	stack.add_child(heading)
	_picker_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_label_style(_picker_title, 16, GOLD)
	heading.add_child(_picker_title)
	_picker_close = _button("Close", Vector2(68, 44))
	_picker_close.pressed.connect(_close_picker)
	heading.add_child(_picker_close)
	for label: Label in [_picker_note, _picker_feedback]:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_label_style(label, 12, CREAM)
		stack.add_child(label)
	_picker_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_picker_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_picker_scroll.follow_focus = true
	stack.add_child(_picker_scroll)
	var lists := VBoxContainer.new()
	lists.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_picker_scroll.add_child(lists)
	lists.add_child(_move_list)
	lists.add_child(_item_list)
	_move_list.add_theme_constant_override("separation", 5)
	_item_list.columns = 2
	_item_list.add_theme_constant_override("h_separation", 6)
	_item_list.add_theme_constant_override("v_separation", 6)
	_picker.visible = false


func _build_picker_entries() -> void:
	# The fighter's pinned loadout cannot change during battle. Build controls once,
	# preserving keyboard focus while quantities and cooldowns update every frame.
	if battle.is_empty():
		return
	var fighter: Dictionary = battle.fighters[0]
	for slot: Dictionary in fighter.get("skills", {}).get("equipped", []):
		var id := String(slot.move_id)
		var button := _button(id, Vector2(0, 48))
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(_request_move.bind(id))
		button.add_theme_font_size_override("font_size", 11)
		button.custom_minimum_size = Vector2(0, 64)
		button.clip_text = true
		_ability_row.add_child(button)
		move_buttons[id] = button
	for id: String in battle.get("item_definitions", {}):
		var button := _button(id, Vector2(0, 48))
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(_use_item.bind(id))
		button.add_theme_font_size_override("font_size", 11)
		button.clip_text = true
		_item_list.add_child(button)
		item_buttons[id] = button


func _fighter_card(heading: String, hp: ProgressBar, mp: ProgressBar, value: Label) -> void:
	var stack := VBoxContainer.new()
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.add_theme_constant_override("separation", 3)
	_header.add_child(stack)
	var title := Label.new()
	title.text = heading
	_label_style(title, 10, Color(CREAM, 0.6))
	stack.add_child(title)
	_label_style(value, 13, CREAM)
	value.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	value.clip_text = true
	stack.add_child(value)
	for bar: ProgressBar in [hp, mp]:
		bar.show_percentage = false
		bar.custom_minimum_size.y = 6 if bar == hp else 4
		var track := _panel(Color("263e35"), Color.TRANSPARENT, 3)
		var fill := _panel(Color("e59674") if bar == hp else Color("79bace"), Color.TRANSPARENT, 3)
		for style: StyleBoxFlat in [track, fill]:
			style.content_margin_top = 0
			style.content_margin_bottom = 0
		bar.add_theme_stylebox_override("background", track)
		bar.add_theme_stylebox_override("fill", fill)
		stack.add_child(bar)


func _layout() -> void:
	var viewport_size := get_viewport_rect().size
	var landscape := viewport_size.x > viewport_size.y * 1.25
	var control_width := minf(350, viewport_size.x - 24) if landscape else viewport_size.x - 24
	var control_x := viewport_size.x - control_width - 12 if landscape else 12.0
	var controls_top := maxf(112, viewport_size.y - 288)
	if landscape:
		controls_top = 76
	var field_width := control_x - 18 if landscape else viewport_size.x - 24
	_arena_rect = Rect2(12, 112, field_width, maxf(100, (viewport_size.y - 124) if landscape else controls_top - 120))
	_place(_header_backdrop, Vector2.ZERO, Vector2(viewport_size.x, 108 if not landscape else 72))
	_place(_controls_backdrop, Vector2(control_x - 12, controls_top - 5), Vector2(control_width + 24, viewport_size.y - controls_top + 5))
	_place(_title, Vector2(12, 8), Vector2(viewport_size.x - 150, 24))
	_place(clock_label, Vector2(viewport_size.x - 142, 10), Vector2(130, 20))
	_place(_header, Vector2(12, 36), Vector2(viewport_size.x - 24 if not landscape else field_width, 67))
	_place(event_label, Vector2(control_x, controls_top), Vector2(control_width, 34))
	_place(_ability_row, Vector2(control_x, controls_top + 38), Vector2(control_width, 64))
	_place(_action_row, Vector2(control_x, controls_top + 108), Vector2(control_width, 48))
	_place(order_label, Vector2(control_x, controls_top + 160), Vector2(control_width, 18))
	_place(_order_row, Vector2(control_x, controls_top + 182), Vector2(control_width, 44))
	_place(_bottom_row, Vector2(control_x, controls_top + 232), Vector2(control_width, 44))
	_zoom_row.visible = _environment_enabled
	_place(_diagnostics, Vector2(12, 108), Vector2(minf(280, viewport_size.x - 24), 194))
	_place(_result_panel, Vector2(24, _arena_rect.get_center().y - 60), Vector2(maxf(180, field_width - 24), 115))
	# A compact 2×2 inventory replaces only the low-priority orders/footer.
	# The battlefield, equipped abilities and timed defense never get covered.
	_picker_note.size.x = control_width - 18
	_picker_feedback.size.x = control_width - 18
	_place(_picker, Vector2(control_x, controls_top + 162), Vector2(control_width, 116))
	if not battle.is_empty():
		if _environment_enabled:
			environment_view.position = _arena_rect.position if landscape else Vector2.ZERO
			environment_view.size = _arena_rect.size if landscape else viewport_size
			environment_view.presentation_safe_rect = Rect2(Vector2.ZERO, _arena_rect.size) if landscape else _arena_rect
			environment_view.frame_session(_display_session(), 1.0, true)
		else:
			arena_view.fit_to(_arena_rect)
	queue_redraw()


func _configure_fighters() -> void:
	for fighter: Dictionary in battle.fighters:
		if fighter.fighter_id == battle.fighter_order[0]: continue
		var card := _button("", Vector2(100, 40))
		card.add_theme_font_size_override("font_size", 11)
		card.pressed.connect(_focus_enemy.bind(String(fighter.fighter_id)))
		_hud.add_child(card)
		enemy_cards[fighter.fighter_id] = card
	if _environment_enabled:
		if not environment_view.configure_fighters(battle):
			_fallback_to_2d("The forest loaded, but its 3D fighters did not.")
		else:
			avatars = environment_view.fighter_presentations
			if not environment_view.missing_art_ids.is_empty():
				_missing_art = "Missing pinned art — no newer artwork substituted."
			player_hp_bar.max_value = battle.fighters[0].stats.hp
			player_mp_bar.max_value = maxf(1, battle.fighters[0].stats.mp)
			opponent_hp_bar.max_value = battle.fighters[1].stats.hp
			opponent_mp_bar.max_value = maxf(1, battle.fighters[1].stats.mp)
			return
	var pins: Dictionary = battle.get("content_revisions", {}).get("visuals", {})
	for index: int in battle.fighter_order.size():
		var id := String(battle.fighter_order[index])
		var fighter: Dictionary = fighter_by_id[id]
		var avatar := player_avatar if index == 0 else (opponent_avatar if index == 1 else CompanionAvatar.new())
		arena_view.add_child(avatar)
		avatars[id] = avatar
		var pin: Dictionary = pins.get(id, {})
		var library: Dictionary = {}
		if pin.has_all(["assetId", "revision"]):
			library = CompanionAssetLibrary.build_pinned(String(fighter.species_id), String(pin.assetId), String(pin.revision))
		if library.is_empty():
			_missing_art = "Missing pinned art — no newer artwork substituted."
			var marker := Label.new()
			marker.text = "ART?"
			marker.position = Vector2(-16, -15)
			_label_style(marker, 12, Color.SALMON)
			avatar.add_child(marker)
		else:
			avatar.configure_library(library)
		avatar.roaming_enabled = false
		avatar.sprite.scale = Vector2.ONE * 0.54
		var effect := Effects.new()
		effect.reduced_motion = _motion.button_pressed
		effect.name = "BattleEffects"
		effect.scale = Vector2.ONE * 0.54
		avatar.add_child(effect)
		effects_by_id[id] = effect
	player_hp_bar.max_value = battle.fighters[0].stats.hp
	player_mp_bar.max_value = maxf(1, battle.fighters[0].stats.mp)
	opponent_hp_bar.max_value = battle.fighters[1].stats.hp
	opponent_mp_bar.max_value = maxf(1, battle.fighters[1].stats.mp)


func _display_session() -> Dictionary:
	return playback.get_session() if _is_replay else battle


func _render_frame(alpha: float) -> void:
	var session := _display_session()
	if session.is_empty():
		return
	var fallback := false
	if _environment_enabled:
		environment_view.render_session(session, alpha)
		for presentation: CompanionPresentation3D in avatars.values():
			fallback = fallback or not presentation.visual_fallback.is_empty()
	else:
		for id: String in avatars:
			var actor: Dictionary = session.actors[id]
			var previous := Vector2(float(actor.previous_pos[0]), float(actor.previous_pos[1])) / BattleSimulator.SCALE
			var avatar: CompanionAvatar = avatars[id]
			avatar.position = arena_view.project(previous.lerp(BattleSimulator.ground_position(actor), alpha))
			avatar.render_battle(actor, alpha)
			_sample_body_accent(id, avatar, session, alpha)
			_render_effect(id, actor, session, alpha)
			fallback = fallback or not avatar.visual_fallback.is_empty()
		arena_view.render_session(session)
	var player: Dictionary = session.actors[session.fighter_order[0]]
	var target_id := String(player.get("focus_target_id", ""))
	if target_id.is_empty() or not session.actors.has(target_id): target_id = String(player.target_id)
	if target_id.is_empty(): target_id = String(session.fighter_order[1])
	var opponent: Dictionary = session.actors[target_id]
	var target_fighter: Dictionary = fighter_by_id[target_id]
	opponent_hp_bar.max_value = target_fighter.stats.hp
	opponent_mp_bar.max_value = maxf(1, target_fighter.stats.mp)
	_render_enemy_cards(session, target_id)
	player_hp_bar.value = player.hp
	player_mp_bar.value = player.mp
	opponent_hp_bar.value = opponent.hp
	opponent_mp_bar.value = opponent.mp
	player_value.text = "%s\n%d HP / %d MP" % [battle.fighters[0].display_name, player.hp, player.mp]
	opponent_value.text = "%s\n%d HP / %d MP" % [target_fighter.display_name.trim_prefix("Training "), opponent.hp, opponent.mp]
	var seconds := int(session.tick) / BattleSimulator.TICKS_PER_SECOND
	var mode := "REPLAY" if _is_replay else ("DONE" if session.complete else "LIVE")
	clock_label.text = "%s  %02d:%02d" % [mode, seconds / 60, seconds % 60]
	if player.pending_order != player.order:
		order_label.text = "%s queued · currently %s" % [String(player.pending_order).replace("_", " ").to_upper(), String(player.order).replace("_", " ").to_upper()]
	else:
		order_label.text = "%s · autonomous movement" % String(player.order).replace("_", " ").to_upper()
	if _is_replay:
		order_label.text = "RECORDED ORDERS · read-only replay"
	elif not String(player.get("pending_move", "")).is_empty():
		var move_id := String(player.pending_move)
		var move: Dictionary = session.fighters[0].get("moves", {}).get(move_id, {})
		order_label.text = "%s queued · %.1fs" % [String(move.get("name", move_id)), maxf(0, float(int(player.move_expires_tick) - int(session.tick)) / BattleSimulator.TICKS_PER_SECOND)]
	for order: String in order_buttons:
		order_buttons[order].modulate = GOLD if order == player.order else Color.WHITE
	art_label.text = _missing_art if not _missing_art.is_empty() else ("Legacy side-view art · eight-direction set pending approval" if fallback else "Pinned artwork · simulation-owned timing")
	if not _presentation_notice.is_empty():
		art_label.text = _presentation_notice + (" · " + art_label.text if not art_label.text.is_empty() else "")
	_refresh_controls()


func _give_order(order: String) -> void:
	if not _commands_available():
		return
	var result := GameState.queue_battle_order(order)
	if not result.get("ok", false):
		event_label.text = String(result.get("error", "Order unavailable."))
	else:
		order_label.text = "%s acknowledged · applies after reaction/recovery" % order.replace("_", " ").to_upper()


func _toggle_picker(mode: String) -> void:
	if not _commands_available():
		return
	if _picker.visible and _picker_mode == mode:
		_close_picker()
		return
	if mode == "moves":
		if not move_buttons.is_empty():
			move_buttons.values()[0].grab_focus()
		return
	_picker_mode = mode
	_picker_feedback.text = ""
	_picker.visible = true
	_sync_drawer_visibility()
	_refresh_picker()
	_layout()
	items_button.grab_focus()


func _close_picker() -> void:
	_picker.visible = false
	_sync_drawer_visibility()
	if _picker_mode == "moves":
		moves_button.grab_focus()
	else:
		items_button.grab_focus()


func _set_view_zoom(value: float) -> void:
	if not _environment_enabled:
		return
	environment_view.set_battle_zoom(value)
	_zoom_fit.text = "Fit" if is_equal_approx(environment_view.battle_zoom_multiplier, 1.0) else "%d%%" % roundi(environment_view.battle_zoom_multiplier * 100)


func _on_field_zoom_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_focus_at_point(environment_view.get_global_transform() * event.position)
	elif event is InputEventScreenTouch and event.pressed:
		_focus_at_point(environment_view.get_global_transform() * event.position)
	if not _environment_enabled or _picker.visible:
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			_set_view_zoom(environment_view.battle_zoom_multiplier * (1.1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.1))
			environment_view.accept_event()
	elif event is InputEventMagnifyGesture:
		_set_view_zoom(environment_view.battle_zoom_multiplier * event.factor)
		environment_view.accept_event()


func _input(event: InputEvent) -> void:
	# _input handles Space before a focused Button consumes it as ui_accept.
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	var key: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
	if key == KEY_ESCAPE and _picker.visible:
		_close_picker()
	elif key == KEY_SPACE:
		_request_defense("dodge")
	elif key == KEY_G:
		_request_defense("guard")
	elif key == KEY_I:
		_toggle_picker("items")
	elif key in [KEY_1, KEY_2, KEY_3]:
		var index := int(key) - KEY_1
		if index < move_buttons.size():
			_request_move(String(move_buttons.keys()[index]))
	else:
		return
	get_viewport().set_input_as_handled()


func _sync_drawer_visibility() -> void:
	# Never hide defense, equipped moves, feedback, or orders behind a drawer.
	_action_row.visible = true
	_ability_row.visible = true
	_order_row.visible = not _picker.visible
	_bottom_row.visible = not _picker.visible
	event_label.visible = true
	order_label.visible = not _picker.visible


func _commands_available() -> bool:
	return not _is_replay and not _leaving and not GameState.battle_paused and not battle.is_empty() and not bool(battle.get("complete", true))


func _request_defense(defense: String) -> void:
	if not _commands_available():
		return
	var result: Dictionary = GameState.call("queue_battle_defense", defense)
	_command_feedback((defense.capitalize() + " requested for the next tick.") if result.get("ok", false) else String(result.get("error", "Defense unavailable.")))
	_refresh_picker()


func _refresh_picker() -> void:
	var session := _display_session()
	if session.is_empty():
		return
	var fighter: Dictionary = session.fighters[0]
	var actor: Dictionary = session.actors[session.fighter_order[0]]
	var stopped := _is_replay or bool(session.complete) or GameState.battle_paused or int(actor.hp) <= 0
	var rookie := String(fighter.stage) == "Rookie"
	moves_button.text = "Moves" if rookie else "Moves · Rookie"
	moves_button.tooltip_text = "Request an equipped move while the battle continues." if rookie else "Custom moves unlock at Rookie. Your companion still attacks automatically."
	moves_button.disabled = stopped or not rookie
	items_button.disabled = stopped or not session.has("item_definitions")
	_picker_title.text = "Equipped moves" if _picker_mode == "moves" else "Combat items"
	_picker_title.get_parent().visible = false
	_picker_note.visible = false
	_picker_feedback.visible = false
	items_button.text = "Close items [I]" if _picker.visible else "Items [I]"
	_move_list.visible = _picker_mode == "moves"
	_item_list.visible = _picker_mode == "items"
	var prefix := "Paused while unfocused." if GameState.battle_paused else "Battle continues."
	if _is_replay:
		prefix = "Replay is read-only."
	if _picker_mode == "moves":
		_picker_note.text = prefix + (" Requests wait for range and recovery." if rookie else " Moves unlock at Rookie.")
		if rookie and move_buttons.is_empty():
			_picker_note.text += " Equip moves in the Skills tab before battle."
	else:
		var cooldown := maxf(0, float(int(session.get("item_ready_tick", 0)) - int(session.tick)) / BattleSimulator.TICKS_PER_SECOND)
		_picker_note.text = prefix + (" Items ready in %.1fs." % cooldown if cooldown > 0 else " One item every %.1f seconds." % (float(session.get("combat_config", {}).get("tuning", {}).get("item_cooldown", 150)) / 30.0))
	for defense: String in defense_buttons:
		var remaining := maxf(0, float(int(actor.get("manual_defense_ready_tick", 0)) - int(session.tick)) / 30.0)
		var label := "Dodge [Space]" if defense == "dodge" else "Guard [G]"
		var phase := String(actor.get("phase", ""))
		if phase in ["active", "recovery"]:
			label = defense.capitalize() + " · committed"
		elif remaining > 0:
			label = "%s · %.1fs" % [defense.capitalize(), remaining]
		defense_buttons[defense].text = label
		# Keep committed-phase presses enabled for immediate explanatory feedback.
		defense_buttons[defense].disabled = stopped or int(session.tick) + 1 < int(actor.get("manual_defense_ready_tick", 0))
		defense_buttons[defense].tooltip_text = "Cancels charging. Active attacks and recovery must finish."
	var slot_index := 0
	for id: String in move_buttons:
		var move: Dictionary = fighter.get("moves", {}).get(id, {})
		var cost := int(move.get("mp_cost", 0))
		var enabled := false
		for slot: Dictionary in fighter.get("skills", {}).get("equipped", []):
			if slot.move_id == id:
				enabled = bool(slot.auto)
		var reason := "Need %d MP" % cost if int(actor.mp) < cost else ("Auto on" if enabled else "Manual only")
		if String(actor.get("pending_move", "")) == id:
			reason = "Queued · %.1fs remaining" % maxf(0, float(int(actor.move_expires_tick) - int(session.tick)) / BattleSimulator.TICKS_PER_SECOND)
		var remaining := maxf(0, float(int(actor.get("cooldowns", {}).get(id, 0)) - int(session.tick)) / 30.0)
		if remaining > 0:
			reason = "CD %.1fs" % remaining
		if String(actor.get("pending_move", "")) == id:
			reason = "Pending"
		if String(actor.get("current_move", {}).get("id", "")) == id and String(actor.get("phase", "")) == "charge":
			reason = "Cast %d%%" % roundi(BattleCues.charge_fraction(actor) * 100)
		slot_index += 1
		move_buttons[id].text = "%d · %s\n%d MP · %s" % [slot_index, String(move.get("name", id)), cost, reason]
		move_buttons[id].disabled = stopped or not rookie or int(actor.mp) < cost
		move_buttons[id].tooltip_text = "%s · %d MP · %s. Request replaces any older request; MP is spent only when charging begins." % [String(move.get("name", id)), cost, reason]
	for id: String in item_buttons:
		var item: Dictionary = session.get("item_definitions", {}).get(id, {})
		if item.is_empty():
			item_buttons[id].disabled = true
			continue
		var amount := int(session.get("supplies", {}).get(id, 0))
		var stat := String(item.get("stat", ""))
		var effect := String(item.get("effect", id))
		var tactical := id in ["barrier", "haste"] or effect in ["barrier", "haste"]
		var full := bool(actor.get("effects", {}).has(effect)) if tactical else (not stat.is_empty() and int(actor.get(stat, 0)) >= int(fighter.stats.get(stat, 0)))
		var cooling := int(session.tick) + 1 < int(session.get("item_ready_tick", 0))
		var reason := "Restore %d %s" % [int(item.get("amount", 0)), stat.to_upper()]
		if tactical:
			reason = "Absorb %d damage · %.1fs" % [int(item.get("amount", 30)), float(item.get("duration_ticks", 180)) / 30.0] if effect == "barrier" else "+%d%% movement · %.1fs" % [roundi((float(item.get("movement_multiplier", 1350)) / 1000.0 - 1.0) * 100), float(item.get("duration_ticks", 180)) / 30.0]
		if amount <= 0:
			reason = "None remaining"
		elif full:
			reason = (effect.capitalize() + " already active") if tactical else ("%s already full" % stat.to_upper())
		elif cooling:
			reason = "Ready in %.1fs" % (float(int(session.item_ready_tick) - int(session.tick)) / BattleSimulator.TICKS_PER_SECOND)
		elif int(actor.hp) <= 0:
			reason = "Companion cannot use items"
		item_buttons[id].text = "%s ×%d\n%s" % [String(item.name), amount, reason]
		item_buttons[id].disabled = stopped or amount <= 0 or full or cooling
		item_buttons[id].tooltip_text = "Items are spent when accepted and stay spent if you leave the battle."


func _request_move(move_id: String) -> void:
	if not _commands_available():
		return
	if not GameState.has_method("queue_battle_move"):
		_command_feedback("Move commands are unavailable.")
		return
	var result: Dictionary = GameState.call("queue_battle_move", move_id)
	_command_feedback("Move queued for the next tick." if bool(result.get("ok", false)) else String(result.get("error", "Move unavailable.")))


func _use_item(item_id: String) -> void:
	if not _commands_available():
		return
	if not GameState.has_method("queue_battle_item"):
		_command_feedback("Item commands are unavailable.")
		return
	var result: Dictionary = GameState.call("queue_battle_item", item_id)
	_command_feedback("Item queued for the next tick." if bool(result.get("ok", false)) else String(result.get("error", "Item unavailable.")))


func _on_battle_command_resolved(result: Dictionary) -> void:
	if _is_replay or _leaving:
		return
	if not bool(result.get("ok", false)):
		_command_feedback(String(result.get("error", "Command could not be applied.")))
	_refresh_picker()


func _command_feedback(message: String) -> void:
	_feedback_until_msec = Time.get_ticks_msec() + 1600
	event_label.text = message
	_picker_feedback.text = message
	_picker_feedback.visible = false


func _apply_event(event: Dictionary, play_audio := true) -> void:
	var kind := String(event.get("event", ""))
	# A perfect guard emits its reward event followed by a zero-damage hit.
	# The latter is combat bookkeeping, not a hurt response or a second sound.
	if kind == "hit" and bool(event.get("perfect_guard", false)):
		return
	var shielded := kind == "hit" and int(event.get("damage", -1)) == 0 and int(event.get("absorbed", 0)) > 0
	var event_message := String(event.get("message", ""))
	if shielded:
		event_message = "Barrier absorbed %d damage." % int(event.absorbed)
	if kind == "item_used" and int(event.get("restored", 0)) > 0:
		var item: Dictionary = _display_session().get("item_definitions", {}).get(String(event.get("item_id", "")), {})
		event_message = "%s restores %d %s." % [item.get("name", "Item"), int(event.restored), String(item.get("stat", "")).to_upper()]
	if play_audio:
		_audio.muted = bool(GameState.state.get("meta", {}).get("preferences", {}).get("muted", false))
		_audio.play_event({"event": "defense_started"} if shielded else event)
	if kind in ["hit", "evade", "projectile_blocked", "command", "battle_finished", "move_requested", "move_expired", "item_used", "charge_started", "charge_cancelled", "attack_released", "defense_started", "perfect_guard", "rush_collision", "effect_expired", "healed", "warded", "support_missed"]:
		if Time.get_ticks_msec() >= _feedback_until_msec or kind in ["perfect_guard", "charge_cancelled", "defense_started"]:
			var message := event_message
			if not message.is_empty():
				event_label.text = message
	if kind in ["move_requested", "move_expired", "item_used"]:
		_picker_feedback.text = event_message
	if kind == "hit":
		var action := String(event.get("move_id", event.get("action_id", "")))
		var definition: Dictionary = _display_session().get("combat_config", {}).get("moves", {}).get(action, {})
		var effect := "shield_impact" if shielded else ("hit_fire" if String(definition.get("effect", "fire" if action in ["pepper_breath", "fireball"] else "impact")) == "fire" else "hit_general")
		_record_effect(String(event.get("target_id", "")), effect, int(event.tick), 18, int(definition.get("visual_scale", 1000)))
	elif kind in ["healed", "warded"]:
		_record_effect(String(event.get("target_id", "")), "feed" if kind == "healed" else "shield_impact", int(event.tick), 24)
	elif kind == "perfect_guard":
		_command_feedback(event_message if not event_message.is_empty() else "Perfect guard!")
		_record_effect(String(event.get("actor_id", event.get("fighter_id", ""))), "perfect_guard", int(event.tick), 18)
	elif kind == "item_used":
		_record_effect(String(event.get("target_id", "")), "feed", int(event.tick), 24)


func _record_effect(id: String, effect: String, tick: int, duration: int, visual_scale: int = 1000) -> void:
	if _environment_enabled:
		environment_view.record_effect(id, effect, tick, duration, visual_scale)
		return
	if effects_by_id.has(id):
		_effect_records[id] = {"effect": effect, "start": tick, "duration": duration, "visual_scale": visual_scale}


func _render_effect(id: String, actor: Dictionary, session: Dictionary, alpha: float) -> void:
	if not effects_by_id.has(id):
		return
	var effect: CompanionEffects = effects_by_id[id]
	effect.scale = Vector2(-0.54 if String(actor.facing) in ["W", "NW", "SW"] else 0.54, 0.54)
	# Sample only simulation time: no real-time tween, damage, state mutation, or
	# creature-frame substitution. Paused clocks freeze effects and replays match.
	var sample_tick := maxf(0, float(int(session.tick) - 1) + alpha)
	if _effect_records.has(id):
		var record: Dictionary = _effect_records[id]
		var elapsed := sample_tick - float(record.start)
		if elapsed < float(record.duration):
			effect.scale *= float(record.get("visual_scale", 1000)) / 1000.0
			effect.sample_effect(String(record.effect), maxf(0, elapsed) / float(record.duration))
			return
		_effect_records.erase(id)
	if String(actor.action) in ["basic_attack", "special_attack", "rush_attack"]:
		effect.sample_effect(String(actor.action), clampf((float(actor.action_tick) + alpha) / maxf(1, float(actor.action_duration)), 0, 1))
	else:
		effect.clear_effect()


func _show_result() -> void:
	if battle.is_empty():
		return
	var summary: Dictionary = battle.get("result", {})
	result_label.text = {"win": "TRAINING WON", "loss": "LESSON LEARNED", "draw": "TRAINING DRAW"}.get(String(summary.get("outcome", "")), "TRAINING COMPLETE")
	if battle.get("reward_saved", false):
		var reward: Dictionary = battle.get("reward", {})
		reward_label.text = "+%d bond · +%d training\n%s" % [int(reward.get("bond", 0)), int(reward.get("training_points", 0)), "Replay complete · original reward unchanged" if _is_replay else "Progress saved"]
		if reward.get("items", {}) is Dictionary and not reward.get("items", {}).is_empty():
			reward_label.text += "\nRecovery +1 · MP +1 · Barrier +1 · Haste +1"
	else:
		reward_label.text = "Result complete — save pending.\nKeep this session open and retry saving."
		if not String(battle.get("settlement_error", "")).is_empty():
			event_label.text = String(battle.settlement_error)
	_result_panel.visible = true
	_picker.visible = false
	_sync_drawer_visibility()
	_refresh_controls()


func _refresh_controls() -> void:
	var complete: bool = not battle.is_empty() and battle.get("complete", false)
	var saved: bool = complete and battle.get("reward_saved", false)
	for button: Button in order_buttons.values():
		button.disabled = complete or _is_replay or battle.is_empty() or GameState.battle_paused
	return_button.text = "Return" if complete or battle.is_empty() else "Leave · no reward"
	if GameState.isolated_mode and GameState.has_meta("battle_field_review"):
		return_button.text = "Fields" if complete else "Leave · fields"
	return_button.disabled = complete and not saved
	replay_button.visible = saved and (not _is_replay or playback.is_complete())
	retry_button.visible = complete and not saved
	speed_button.visible = _is_replay and not playback.is_complete()
	skip_button.visible = _is_replay and not playback.is_complete()
	_refresh_picker()


func _retry_save() -> void:
	var result := GameState.finish_training_battle()
	if not result.get("ok", false):
		event_label.text = String(result.get("error", "Saving is still unavailable."))
	_show_result()


func _start_replay() -> void:
	if not battle.get("complete", false):
		return
	playback.setup(battle)
	if playback.get_session().is_empty():
		event_label.text = "Replay could not be loaded: " + playback.error
		return
	_is_replay = true
	_picker.visible = false
	_sync_drawer_visibility()
	_effect_records.clear()
	if _environment_enabled:
		environment_view.clear_effects()
	_accumulator = 0
	_result_panel.visible = false
	event_label.text = "Replaying the same seed, arena, artwork, and recorded orders."
	speed_button.text = "1×"
	_render_frame(1)
	_refresh_controls()


func _cycle_speed() -> void:
	if _is_replay:
		speed_button.text = "%d×" % playback.cycle_speed()


func _skip() -> void:
	if not _is_replay:
		return
	_audio.stop_all()
	for event: Dictionary in playback.skip_to_end():
		# Consume skipped presentation history without playing a whole bout's
		# cues in a single frame. Normally advancing replay still plays each cue.
		_apply_event(event, false)
	_render_frame(1)
	_show_result()


func _return_to_care() -> void:
	if not GameState.clear_active_battle():
		event_label.text = "Save this completed result before leaving."
		return
	_leaving = true
	_audio.stop_all()
	if GameState.isolated_mode and GameState.has_meta("battle_field_review"):
		GameState.remove_meta("battle_field_review")
		get_tree().change_scene_to_file("res://scenes/environment_workshop/battle_fields.tscn")
		return
	get_tree().change_scene_to_file("res://scenes/care_scene.tscn")


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, get_viewport_rect().size), INK)
	draw_rect(_arena_rect.grow(1), Color("5b7868"), false, 1)


func _configure_environment_presentation() -> bool:
	# Reset prior packages before selecting the editable native battle field.
	# Arena geometry and replay content pins remain authoritative and unchanged.
	environment_view.clear_battle()
	environment_view.visible = false
	EnvironmentAssetLibrary.clear_active()
	var field_review := String(GameState.get_meta("battle_field_review", ""))
	if GameState.isolated_mode and not field_review.is_empty():
		if not environment_view.configure_workshop_battle(battle.get("arena", {}), field_review):
			_presentation_notice = "Editable battle field unavailable · safe 2D fallback"
			return false
		environment_view.visible = true
		_presentation_notice = "Editable regional field · unpromoted isolated review"
		_title.text = String(EncounterCatalog.resolve(field_review).title)
		return true
	if not environment_view.configure_native_battle_field(battle.get("arena", {})):
		_presentation_notice = "Battle field unavailable · safe 2D fallback"
		return false
	environment_view.visible = true
	_presentation_notice = "Rootbound Glade · native prototype battle field"
	return true


func _activate_environment_package(pin: Dictionary) -> Dictionary:
	var package := EnvironmentAssetLibrary.activate_pin(pin)
	if not package.is_empty() or not GameState.isolated_mode or String(battle.get("arena_source", "")) != "isolated-dev-fixture":
		return package
	var index := AssetResourceLibrary.read_json("res://tests/fixtures/regions/index.json")
	var regions: Variant = index.get("regions")
	if not regions is Dictionary:
		return {}
	for record_value: Variant in regions.values():
		if not record_value is Dictionary:
			continue
		var environment: Variant = record_value.get("environment")
		if not environment is Dictionary or String(environment.get("assetId", "")) != String(pin.assetId):
			continue
		var relative := String(environment.get("path", ""))
		if not relative.begins_with("tests/fixtures/regions/") or not relative.ends_with("/environment") or ".." in relative.split("/"):
			return {}
		var metadata := AssetResourceLibrary.read_json("res://" + relative.path_join("candidate.json"))
		if metadata.get("devFixture") != true or metadata.get("reviewStatus") == "approved":
			return {}
		return EnvironmentAssetLibrary.activate_isolated_dev_fixture(pin, "res://" + relative, true)
	return {}


func _fallback_to_2d(message: String) -> void:
	_environment_enabled = false
	environment_view.clear_battle()
	environment_view.visible = false
	arena_view.visible = true
	EnvironmentAssetLibrary.clear_active()
	_presentation_notice = message + " Safe 2D fallback active."


func presentation_instrumentation() -> Dictionary:
	if _environment_enabled:
		return environment_view.battle_instrumentation()
	return {"environmentEnabled": false, "fallback": true, "avatars": avatars.size(),
		"effects": effects_by_id.size(), "notice": _presentation_notice}


func _button(label: String, minimum: Vector2) -> Button:
	var button := Button.new()
	button.text = label
	button.custom_minimum_size = Vector2(maxf(44, minimum.x), maxf(44, minimum.y))
	button.focus_mode = Control.FOCUS_ALL
	button.add_theme_font_size_override("font_size", 12)
	button.add_theme_color_override("font_color", CREAM)
	button.add_theme_stylebox_override("normal", _panel(Color("29473a"), Color("48614f")))
	button.add_theme_stylebox_override("hover", _panel(Color("3c5c47"), GOLD))
	button.add_theme_stylebox_override("pressed", _panel(Color("193126"), GOLD))
	button.add_theme_stylebox_override("disabled", _panel(Color("1c2d26"), Color("2d4135")))
	button.add_theme_stylebox_override("focus", _panel(Color.TRANSPARENT, GOLD, 8))
	return button


func _panel(color: Color, border: Color, radius: int = 8) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border
	style.set_border_width_all(1 if border.a > 0 else 0)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	return style


func _label_style(label: Label, size: int, color: Color) -> void:
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)


func _place(control: Control, point: Vector2, size: Vector2) -> void:
	control.position = point
	control.size = size


func _sample_body_accent(id: String, avatar: CompanionAvatar, session: Dictionary, alpha: float) -> void:
	avatar.sprite.modulate = Color.WHITE
	avatar.sprite.position.x = 0
	if not _effect_records.has(id):
		return
	var record: Dictionary = _effect_records[id]
	if not String(record.effect).begins_with("hit"):
		return
	var elapsed := float(int(session.tick) - int(record.start)) + alpha
	if elapsed >= 0 and elapsed < 7:
		avatar.sprite.modulate = Color(1.0, 0.65, 0.5).lerp(Color.WHITE, elapsed / 7.0)
		if not _motion.button_pressed:
			avatar.sprite.position.x += sin(elapsed / 7.0 * PI) * 4.0


func _focus_enemy(id: String) -> void:
	if not _commands_available(): return
	var response := GameState.queue_battle_command({"kind": "focus_target", "target_id": id})
	if not response.get("ok", false): event_label.text = response.get("error", "Target unavailable.")


func _enemy_screen_position(id: String) -> Vector2:
	if _environment_enabled and avatars.has(id):
		var world: Node3D = avatars[id]
		return environment_view.position + environment_view.camera.unproject_position(world.global_position) * environment_view.size / Vector2(environment_view.world_viewport.size)
	if avatars.has(id): return (avatars[id] as Node2D).global_position
	return Vector2.ZERO


func _render_enemy_cards(session: Dictionary, focused: String) -> void:
	var screen := get_viewport_rect().size
	var index := 0
	for id: String in enemy_cards:
		var actor: Dictionary = session.actors[id]
		var card: Button = enemy_cards[id]
		card.visible = int(actor.hp) > 0
		card.disabled = not _commands_available()
		var move_name := String(actor.get("current_move", {}).get("name", "")) if actor.get("phase") == "charge" else ""
		card.text = "%s%s\n%d/%d%s" % ["◎ " if id == focused else "", fighter_by_id[id].display_name, actor.hp, fighter_by_id[id].stats.hp, " · " + move_name if not move_name.is_empty() else ""]
		card.modulate = GOLD if id == focused else Color.WHITE
		card.size = Vector2(minf(120, (screen.x - 24 - 2 * (enemy_cards.size() - 1)) / enemy_cards.size()), 44)
		card.position = Vector2(12 + index * (card.size.x + 2), _arena_rect.position.y + 4)
		index += 1


func _unhandled_input(event: InputEvent) -> void:
	if not _commands_available(): return
	var point := Vector2.ZERO
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT: point = event.position
	elif event is InputEventScreenTouch and event.pressed: point = event.position
	else: return
	_focus_at_point(point)


func _focus_at_point(point: Vector2) -> void:
	if not _commands_available() or _picker.visible or not _arena_rect.has_point(point): return
	var nearest := ""
	var distance := 48.0
	for id: String in enemy_cards:
		if int(battle.actors[id].hp) <= 0: continue
		var candidate := point.distance_to(_enemy_screen_position(id) - Vector2(0, 18))
		if candidate < distance:
			distance = candidate
			nearest = id
	if not nearest.is_empty():
		_focus_enemy(nearest)
		get_viewport().set_input_as_handled()
