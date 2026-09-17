extends Node2D

## GameState owns live ticks/rewards; replay owns a separate pure simulation.
const CREAM := Color("f5efda")
const GOLD := Color("efc46c")
const INK := Color("10201b")
const ORDERS := ["auto", "attack", "defend", "keep_distance"]
const ORDER_LABELS := ["Auto", "Attack", "Defend", "Keep distance"]
const Effects = preload("res://scripts/world/companion_effects.gd")

var arena_view := ArenaView.new()
var environment_view := BattleWorldPresentation3D.new()
var player_avatar := CompanionAvatar.new()
var opponent_avatar := CompanionAvatar.new()
var playback := BattlePlaybackModel.new()
var battle: Dictionary = {}
var fighter_by_id: Dictionary = {}
var avatars: Dictionary = {}
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
var _item_list := VBoxContainer.new()
var _picker_mode := ""
var _picker_close: Button
var _motion := CheckButton.new()
var _zoom_row := HBoxContainer.new()
var _zoom_fit: Button
var _environment_enabled := false
var _presentation_notice := ""


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
	add_child(environment_view)
	add_child(arena_view)
	environment_view.visible = false
	_build_interface()
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
		_refresh_picker()
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
	_action_row.add_child(moves_button)
	items_button = _button("Items", Vector2(0, 44))
	items_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	items_button.pressed.connect(_toggle_picker.bind("items"))
	_action_row.add_child(items_button)
	_label_style(art_label, 10, Color(CREAM, 0.54))
	art_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hud.add_child(art_label)
	_bottom_row.add_theme_constant_override("separation", 6)
	_hud.add_child(_bottom_row)
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
	_hud.add_child(_geometry)
	_motion.text = "Less motion"
	_motion.custom_minimum_size.y = 44
	_motion.add_theme_font_size_override("font_size", 10)
	_motion.toggled.connect(func(value: bool) -> void:
		environment_view.set_reduced_motion(value)
		for effect: CompanionEffects in effects_by_id.values():
			effect.reduced_motion = value)
	_hud.add_child(_motion)
	_hud.add_child(_zoom_row)
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
	_item_list.add_theme_constant_override("separation", 5)
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
		_move_list.add_child(button)
		move_buttons[id] = button
	for id: String in battle.get("item_definitions", {}):
		var button := _button(id, Vector2(0, 48))
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(_use_item.bind(id))
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
	var size := get_viewport_rect().size
	_arena_rect = Rect2(15, 120, size.x - 30, maxf(180, size.y - 390))
	_place(_header_backdrop, Vector2.ZERO, Vector2(size.x, 170))
	_place(_controls_backdrop, Vector2(0, size.y - 273), Vector2(size.x, 273))
	_place(_title, Vector2(16, 12), Vector2(size.x - 150, 24))
	_place(clock_label, Vector2(size.x - 150, 15), Vector2(134, 20))
	_place(_header, Vector2(16, 43), Vector2(size.x - 32, 67))
	_place(event_label, Vector2(16, size.y - 261), Vector2(size.x - 32, 34))
	_place(order_label, Vector2(16, size.y - 223), Vector2(size.x - 32, 18))
	_place(_order_row, Vector2(16, size.y - 199), Vector2(size.x - 32, 44))
	_place(_action_row, Vector2(16, size.y - 149), Vector2(size.x - 32, 44))
	_place(art_label, Vector2(16, size.y - 97), Vector2(size.x - 32, 32))
	_place(_bottom_row, Vector2(16, size.y - 52), Vector2(size.x - 32, 44))
	_place(_geometry, Vector2(size.x - 110, 121), Vector2(96, 44))
	_place(_motion, Vector2(18, 121), Vector2(116, 44))
	_zoom_row.visible = _environment_enabled
	_place(_zoom_row, Vector2(size.x - 154, 174), Vector2(138, 36))
	_place(_result_panel, Vector2(40, _arena_rect.get_center().y - 60), Vector2(size.x - 80, 115))
	var drawer_top := _arena_rect.end.y + 4.0
	_place(_picker, Vector2(16, drawer_top), Vector2(size.x - 32, size.y - drawer_top - 8.0))
	if not battle.is_empty():
		if _environment_enabled:
			# The genuine 3D field fills the portrait surface behind CanvasLayer HUD.
			# Camera acceptance is therefore evaluated at the actual device sizes,
			# while the legacy projection remains confined to its old arena rect.
			environment_view.position = Vector2.ZERO
			environment_view.size = size
			environment_view.frame_session(_display_session(), 1.0, true)
		else:
			arena_view.fit_to(_arena_rect)
	queue_redraw()


func _configure_fighters() -> void:
	if _environment_enabled:
		if not environment_view.configure_fighters(battle):
			_fallback_to_2d("The pinned environment loaded, but its 3D fighters did not.")
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
		var avatar := player_avatar if index == 0 else opponent_avatar
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
			_render_effect(id, actor, session, alpha)
			fallback = fallback or not avatar.visual_fallback.is_empty()
		arena_view.render_session(session)
	var player: Dictionary = session.actors[session.fighter_order[0]]
	var opponent: Dictionary = session.actors[session.fighter_order[1]]
	player_hp_bar.value = player.hp
	player_mp_bar.value = player.mp
	opponent_hp_bar.value = opponent.hp
	opponent_mp_bar.value = opponent.mp
	player_value.text = "%s\n%d HP / %d MP" % [battle.fighters[0].display_name, player.hp, player.mp]
	opponent_value.text = "%s\n%d HP / %d MP" % [battle.fighters[1].display_name.trim_prefix("Training "), opponent.hp, opponent.mp]
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
	_refresh_picker()


func _give_order(order: String) -> void:
	if _is_replay or battle.is_empty() or battle.get("complete", false):
		return
	var result := GameState.queue_battle_order(order)
	if not result.get("ok", false):
		event_label.text = String(result.get("error", "Order unavailable."))
	else:
		order_label.text = "%s acknowledged · applies after reaction/recovery" % order.replace("_", " ").to_upper()


func _toggle_picker(mode: String) -> void:
	if battle.is_empty() or battle.get("complete", false) or _is_replay:
		return
	if _picker.visible and _picker_mode == mode:
		_close_picker()
		return
	_picker_mode = mode
	_picker_feedback.text = ""
	_picker.visible = true
	_sync_drawer_visibility()
	_refresh_picker()
	_picker_close.grab_focus()


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
	if not _environment_enabled or _picker.visible:
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			_set_view_zoom(environment_view.battle_zoom_multiplier * (1.1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.1))
			environment_view.accept_event()
	elif event is InputEventMagnifyGesture:
		_set_view_zoom(environment_view.battle_zoom_multiplier * event.factor)
		environment_view.accept_event()


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and _picker.visible:
		_close_picker()
		get_viewport().set_input_as_handled()


func _sync_drawer_visibility() -> void:
	# The drawer replaces the command strip while leaving the battle visible.
	# Hidden buttons also leave the keyboard focus chain until the drawer closes.
	for control: Control in [_order_row, _action_row, _bottom_row, event_label, order_label, art_label]:
		control.visible = not _picker.visible


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
	_picker_feedback.visible = not _picker_feedback.text.is_empty()
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
		_picker_note.text = prefix + (" Items ready in %.1fs." % cooldown if cooldown > 0 else " One item every 5 seconds.")
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
		move_buttons[id].text = "%s · %d MP\n%s" % [String(move.get("name", id)), cost, reason]
		move_buttons[id].disabled = stopped or not rookie or int(actor.mp) < cost
		move_buttons[id].tooltip_text = "Request replaces any older request; MP is spent only when the move begins."
	for id: String in item_buttons:
		var item: Dictionary = session.get("item_definitions", {}).get(id, {})
		if item.is_empty():
			item_buttons[id].disabled = true
			continue
		var amount := int(session.get("supplies", {}).get(id, 0))
		var stat := String(item.stat)
		var full := int(actor[stat]) >= int(fighter.stats[stat])
		var cooling := int(session.tick) < int(session.get("item_ready_tick", 0))
		var reason := "Restore %d %s" % [int(item.amount), stat.to_upper()]
		if amount <= 0:
			reason = "None remaining"
		elif full:
			reason = "%s already full" % stat.to_upper()
		elif cooling:
			reason = "Ready in %.1fs" % (float(int(session.item_ready_tick) - int(session.tick)) / BattleSimulator.TICKS_PER_SECOND)
		elif int(actor.hp) <= 0:
			reason = "Companion cannot use items"
		item_buttons[id].text = "%s ×%d\n%s" % [String(item.name), amount, reason]
		item_buttons[id].disabled = stopped or amount <= 0 or full or cooling
		item_buttons[id].tooltip_text = "Items are spent when accepted and stay spent if you leave the battle."


func _request_move(move_id: String) -> void:
	if _is_replay or battle.is_empty() or bool(battle.get("complete", true)):
		return
	if not GameState.has_method("queue_battle_move"):
		_command_feedback("Move commands are unavailable.")
		return
	var result: Dictionary = GameState.call("queue_battle_move", move_id)
	_command_feedback("Move queued for the next tick." if bool(result.get("ok", false)) else String(result.get("error", "Move unavailable.")))


func _use_item(item_id: String) -> void:
	if _is_replay or battle.is_empty() or bool(battle.get("complete", true)):
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
	event_label.text = message
	_picker_feedback.text = message
	_picker_feedback.visible = not message.is_empty()


func _apply_event(event: Dictionary) -> void:
	var kind := String(event.get("event", ""))
	if kind in ["hit", "evade", "projectile_blocked", "command", "battle_finished", "move_requested", "move_expired", "item_used"]:
		event_label.text = String(event.get("message", ""))
	if kind in ["move_requested", "move_expired", "item_used"]:
		_picker_feedback.text = String(event.get("message", ""))
	if kind == "hit":
		var action := String(event.get("action_id", ""))
		var effect := "hit_fire" if action in ["pepper_breath", "fireball"] else "hit_general"
		_record_effect(String(event.get("target_id", "")), effect, int(event.tick), 18)
	elif kind == "item_used":
		_record_effect(String(event.get("target_id", "")), "feed", int(event.tick), 24)


func _record_effect(id: String, effect: String, tick: int, duration: int) -> void:
	if _environment_enabled:
		environment_view.record_effect(id, effect, tick, duration)
		return
	if effects_by_id.has(id):
		_effect_records[id] = {"effect": effect, "start": tick, "duration": duration}


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
			effect.sample_effect(String(record.effect), maxf(0, elapsed) / float(record.duration))
			return
		_effect_records.erase(id)
	if String(actor.action) in ["basic_attack", "special_attack"]:
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
			reward_label.text += "\nRecovery +1 · MP Recovery +1"
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
		button.disabled = complete or _is_replay or battle.is_empty()
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
	for event: Dictionary in playback.skip_to_end():
		_apply_event(event)
	_render_frame(1)
	_show_result()


func _return_to_care() -> void:
	if not GameState.clear_active_battle():
		event_label.text = "Save this completed result before leaving."
		return
	_leaving = true
	if GameState.isolated_mode and GameState.has_meta("battle_field_review"):
		GameState.remove_meta("battle_field_review")
		get_tree().change_scene_to_file("res://scenes/environment_workshop/battle_fields.tscn")
		return
	get_tree().change_scene_to_file("res://scenes/care_scene.tscn")


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, get_viewport_rect().size), INK)
	draw_rect(_arena_rect.grow(1), Color("5b7868"), false, 1)


func _configure_environment_presentation() -> bool:
	# Every presentation switch starts empty. A missing/no-pin arena must never
	# inherit the Environment package activated by a previous home or battle.
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
	var pin: Variant = battle.get("arena", {}).get("environment")
	if not pin is Dictionary:
		_presentation_notice = "2D arena fallback"
		return false
	var package := _activate_environment_package(pin)
	if package.is_empty():
		_presentation_notice = "Pinned 3D environment unavailable · safe 2D fallback"
		return false
	if not environment_view.configure_battle(battle.arena, package):
		EnvironmentAssetLibrary.clear_active()
		_presentation_notice = "Pinned 3D environment invalid · safe 2D fallback"
		return false
	environment_view.visible = true
	_presentation_notice = "Pinned Sprite-in-3D environment"
	var encounter := EncounterCatalog.resolve(String(battle.get("encounter_id", battle.arena.assetId)))
	if bool(encounter.get("ok", false)):
		_title.text = String(encounter.title)
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
