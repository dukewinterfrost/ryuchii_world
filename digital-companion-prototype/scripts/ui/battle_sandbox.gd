class_name BattleSandbox
extends Control

## Isolated development tool: owns sessions, never calls live settlement or save.
const Sim = preload("res://scripts/battle/battle_simulator.gd")
const Content = preload("res://scripts/battle/combat_content.gd")
const STAT_DEFAULTS := {"hp": 140, "mp": 60, "offense": 10, "defense": 8, "speed": 8, "brains": 8}
var session: Dictionary = {}
var configuration: Dictionary = {}
var table_directory := Content.DIRECTORY
var seed_value := 20260917
var team_size := 1
var mob_fixture := 0
var balance_snapshot: Dictionary = {}
var paused := false
var focus_paused := false
var stat_overrides := {"allies": STAT_DEFAULTS.duplicate(), "enemies": STAT_DEFAULTS.duplicate()}
var commands: Array = []
var last_error := ""
var accumulator := 0.0
var _serial := 0
var _arena := ArenaView.new()
var _forest := BattleWorldPresentation3D.new()
var _forest_enabled := false
var _avatars := {}
var _stage := Control.new()
var _status := Label.new()
var _feedback := Label.new()
var _timings := TextEdit.new()
var _seed := SpinBox.new()
var _team_select := OptionButton.new()
var _settings := ScrollContainer.new()
var _command_buttons: Array[Button] = []
var _meters: Node2D

class FighterMeters extends Node2D:
	var sandbox: BattleSandbox
	func _draw() -> void:
		if sandbox.session.is_empty(): return
		for index: int in sandbox.session.fighter_order.size():
			var id: String = sandbox.session.fighter_order[index]
			var actor: Dictionary = sandbox.session.actors[id]
			var fighter: Dictionary = sandbox.session.fighters[index]
			var point := sandbox._arena.project(Vector2(float(actor.pos[0]), float(actor.pos[1])) / Sim.SCALE) * sandbox._arena.scale + sandbox._arena.position
			if sandbox._forest_enabled:
				point = sandbox._forest.camera.unproject_position(sandbox._forest.fighter_presentations[id].global_position) * sandbox._forest.size / Vector2(sandbox._forest.world_viewport.size)
			var bar := Rect2(point + Vector2(-18, -48), Vector2(36, 4))
			var color := Color("8deac0") if actor.team_id == "allies" else Color("f79a82")
			draw_rect(bar, Color("11201a"))
			bar.size.x *= float(actor.hp) / maxf(1.0, float(fighter.stats.hp))
			draw_rect(bar, color)
			draw_string(ThemeDB.fallback_font, point + Vector2(-18, -51), "%s %d" % ["A" + str(index + 1) if actor.team_id == "allies" else "E" + str(index - sandbox.team_size + 1), actor.hp], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, color)

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_build_ui()
	var loaded := _load_content()
	if loaded.ok:
		configuration = loaded.config
		restart(false)
	else:
		_show_error(String(loaded.error))

func _build_ui() -> void:
	var background := ColorRect.new()
	background.color = Color("10221e")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	add_child(margin)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 5)
	margin.add_child(stack)
	var title := Label.new()
	title.text = "Battle sandbox · isolated / no rewards"
	title.add_theme_font_size_override("font_size", 16)
	stack.add_child(title)
	var restarts := HBoxContainer.new()
	stack.add_child(restarts)
	_button(restarts, "Same seed", func() -> void: restart(false))
	_button(restarts, "New seed", func() -> void: restart(true))
	_button(restarts, "Reload balance", reload_tables)
	var options := HBoxContainer.new()
	stack.add_child(options)
	_seed.min_value = 0
	_seed.max_value = 2147483647
	_seed.value = seed_value
	_seed.custom_minimum_size.x = 126
	_seed.get_line_edit().add_theme_font_size_override("font_size", 12)
	_seed.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_seed.tooltip_text = "Seed used by Same seed restart. Changes apply on restart."
	options.add_child(_seed)
	_team_select.fit_to_longest_item = false
	_team_select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_team_select.add_theme_font_size_override("font_size", 12)
	_team_select.add_item("1v1", 1)
	_team_select.add_item("3v3", 3)
	for label: String in ["1 Slime", "3 Slimes", "Slimes + Healer", "Mixed trio", "Metal slime", "Spitter slime", "Offensive fairy"]:
		_team_select.add_item(label, 10 + _team_select.item_count - 2)
	_team_select.item_selected.connect(func(index: int) -> void:
		var choice := _team_select.get_item_id(index)
		mob_fixture = choice - 10 if choice >= 10 else -1
		team_size = choice if choice < 10 else 1)
	options.add_child(_team_select)
	_button(options, "Tuning", func() -> void:
		_settings.visible = not _settings.visible
		_stage.visible = not _settings.visible
		accumulator = 0.0)
	var pause_button := _button(options, "Pause", func() -> void:
		paused = not paused
		accumulator = 0.0)
	pause_button.tooltip_text = "Pause the isolated simulation; resume retains the same tick."
	_settings.custom_minimum_size.y = 190
	_settings.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_settings.visible = false
	stack.add_child(_settings)
	var settings_stack := VBoxContainer.new()
	settings_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_settings.add_child(settings_stack)
	var path := Label.new()
	path.text = "Edit Game Balance.xlsx, apply it, then reload for a fresh battle. Mob stats come from Excel; enemy overrides below apply to 1v1/3v3.\nSeconds are rounded to 30 Hz; sizes below are collision sizes."
	path.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	settings_stack.add_child(path)
	var settings_flags := HBoxContainer.new()
	settings_stack.add_child(settings_flags)
	var geometry := CheckButton.new()
	geometry.text = "Geometry"
	geometry.button_pressed = true
	geometry.toggled.connect(func(value: bool) -> void:
		_forest.set_debug_geometry(value)
		_arena.debug_overlays = value
		_arena.queue_redraw())
	settings_flags.add_child(geometry)
	var motion := CheckButton.new()
	motion.text = "Less motion"
	motion.toggled.connect(func(value: bool) -> void:
		_arena.reduced_motion = value
		_forest.set_reduced_motion(value))
	settings_flags.add_child(motion)
	var grid := GridContainer.new()
	grid.columns = 3
	settings_stack.add_child(grid)
	for name_value: String in ["Apply on restart", "Allies", "Enemies"]:
		var label := Label.new()
		label.text = name_value
		grid.add_child(label)
	for stat: String in STAT_DEFAULTS:
		var label := Label.new()
		label.text = stat.capitalize()
		grid.add_child(label)
		for side: String in ["allies", "enemies"]:
			var spinner := SpinBox.new()
			spinner.min_value = 1 if stat == "hp" else 0
			spinner.max_value = 9999 if stat in ["hp", "mp"] else 999
			spinner.value = STAT_DEFAULTS[stat]
			spinner.value_changed.connect(func(value: float) -> void: stat_overrides[side][stat] = int(value))
			grid.add_child(spinner)
	_timings.editable = false
	_timings.custom_minimum_size = Vector2(0, 180)
	_timings.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	settings_stack.add_child(_timings)
	_stage.custom_minimum_size.y = 170
	_stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_stage.clip_contents = true
	stack.add_child(_stage)
	_stage.add_child(_arena)
	_stage.add_child(_forest)
	_forest.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_meters = FighterMeters.new()
	_meters.sandbox = self
	_meters.z_index = 1000
	_stage.add_child(_meters)
	_arena.debug_overlays = true
	_stage.resized.connect(_fit_stage)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_font_size_override("font_size", 12)
	stack.add_child(_status)
	var defense_row := HBoxContainer.new()
	stack.add_child(defense_row)
	for defense: String in ["dodge", "guard"]:
		_command_buttons.append(_button(defense_row, defense.capitalize(), func() -> void: request({"kind": "defense_request", "defense": defense})))
	var abilities := HBoxContainer.new()
	stack.add_child(abilities)
	for move: String in ["pepper_breath", "quick_bite", "heavy_claw"]:
		_command_buttons.append(_button(abilities, move.replace("_", " ").capitalize(), func() -> void: request({"kind": "move_request", "move_id": move})))
	var item_row := HBoxContainer.new()
	stack.add_child(item_row)
	for item: String in ["small_recovery", "mp_recovery", "barrier", "haste"]:
		var label: String = {"small_recovery": "HP ∞", "mp_recovery": "MP ∞", "barrier": "Barrier ∞", "haste": "Haste ∞"}[item]
		_command_buttons.append(_button(item_row, label, func() -> void: request({"kind": "item_use", "item_id": item})))
	_feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_feedback.custom_minimum_size.y = 34
	_feedback.add_theme_font_size_override("font_size", 12)
	stack.add_child(_feedback)

func _button(parent: Node, label: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = label
	button.custom_minimum_size.y = 44
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.add_theme_font_size_override("font_size", 12)
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

static func fixture(config: Dictionary, seed_number: int, count: int = 1, overrides: Dictionary = {}) -> Dictionary:
	var arena := BattleArena.graybox()
	if count == 3:
		arena.assetId = "sandbox-teams"
		arena.ground = {"width": 1000, "height": 680, "cellSize": 20}
		arena.spawns = {"player": [180, 340], "opponent": [820, 340]}
		arena.obstacles = [{"id": "north-rock", "rect": [470, 160, 60, 70], "movement": true, "projectile": true, "sight": true, "occlusion": false}, {"id": "south-rock", "rect": [470, 450, 60, 70], "movement": true, "projectile": true, "sight": true, "occlusion": false}]
	var roster: Array = []
	for side: String in ["allies", "enemies"]:
		for index: int in count:
			var id := "player" if side == "allies" and index == 0 else "%s-%d" % [side, index]
			var stats: Dictionary = overrides.get(side, STAT_DEFAULTS).duplicate(true)
			var actor := Sim.make_snapshot(id, "%s %d" % [side.capitalize(), index + 1], "agumon", "Rookie", "Bold", stats, {}, config)
			actor["team_id"] = side
			actor["controller_id"] = "player" if id == "player" else ""
			actor["spawn"] = ([180 if side == "allies" else 820, 180 + index * 160] if count == 3 else [100 if side == "allies" else 540, 240])
			roster.append(actor)
	var supplies := {}
	for item: String in config.get("items", {}):
		supplies[item] = Sim.MAX_SUPPLIES
	return Sim.create_roster_session("sandbox-%d-%dv%d" % [seed_number, count, count], seed_number, roster, arena, Sim.DEFAULT_MAX_TICKS, {}, supplies, {}, "", "", config)

func restart(new_seed: bool = false) -> Dictionary:
	var next_seed := seed_value
	if new_seed:
		next_seed = int(Time.get_ticks_usec()) & BattleRng.MASK_31
	elif is_instance_valid(_seed):
		next_seed = int(_seed.value)
	var next := fixture(configuration, next_seed, team_size, stat_overrides) if mob_fixture < 0 else _mob_session(next_seed)
	if not next.get("ok", false):
		_show_error(String(next.get("error", "The sandbox fixture could not start.")))
		return next
	seed_value = next_seed
	_seed.value = seed_value
	_team_select.select(2 + mob_fixture if mob_fixture >= 0 else (1 if team_size == 3 else 0))
	session = next
	commands.clear()
	_serial = 0
	accumulator = 0.0
	last_error = ""
	_feedback.text = "Test supplies are unlimited. Commands control your partner."
	for avatar: Node in _avatars.values():
		avatar.free()
	_avatars.clear()
	_arena.configure(session.arena)
	_forest_enabled = _forest.configure_home_forest(session.arena) and _forest.configure_fighters(session, true)
	_forest.visible = _forest_enabled
	_arena.visible = not _forest_enabled
	_forest.set_debug_geometry(_arena.debug_overlays)
	for id: String in session.fighter_order:
		var avatar := CompanionAvatar.new()
		avatar.roaming_enabled = false
		_arena.add_child(avatar)
		avatar.configure(String(session.fighters[session.fighter_order.find(id)].species_id))
		avatar.scale = Vector2.ONE * 0.6
		_avatars[id] = avatar
	_update_timings()
	_fit_stage()
	_render()
	return {"ok": true}

func reload_tables() -> Dictionary:
	var loaded := _load_content()
	if not loaded.ok:
		_show_error("Reload rejected; last valid battle retained. " + String(loaded.error))
		return loaded
	# Keep sandbox edits local: never replace the live care/loadout content cache.
	var previous := configuration
	configuration = loaded.config.duplicate(true)
	var started := restart(false)
	if not started.ok:
		configuration = previous
		_show_error("Reload rejected; last valid battle retained. " + String(started.error))
	return started

func request(input: Dictionary) -> Dictionary:
	if paused or focus_paused or _settings.visible or session.is_empty() or bool(session.get("complete", true)):
		return _reject("Resume a running sandbox battle to give a command.")
	var command := input.duplicate(true)
	_serial += 1
	command["command_id"] = "sandbox-command-%d" % _serial
	command["fighter_id"] = "player"
	command["tick"] = int(session.tick) + 1
	var checked := Sim.preflight_commands(session, commands + [command])
	for rejected: Dictionary in checked.get("rejected", []):
		if rejected.command.command_id == command.command_id:
			return _reject(String(rejected.error))
	commands.append(command)
	_feedback.text = "Accepted for tick %d" % command.tick
	return {"ok": true, "command": command}

func _reject(message: String) -> Dictionary:
	_feedback.text = message
	return {"ok": false, "error": message}

func _show_error(message: String) -> void:
	last_error = message
	_feedback.text = message

func _process(delta: float) -> void:
	if paused or focus_paused or _settings.visible or session.is_empty() or bool(session.get("complete", true)):
		accumulator = 0.0
		_render()
		return
	accumulator += minf(delta, 0.25)
	while accumulator >= 1.0 / 30.0 and not session.complete:
		accumulator -= 1.0 / 30.0
		Sim.step(session, commands)
		commands.clear()
	_render()

func _render() -> void:
	if session.is_empty(): return
	if _forest_enabled:
		_forest.render_session(session)
	_arena.render_session(session)
	for id: String in _avatars:
		var actor: Dictionary = session.actors[id]
		var avatar: CompanionAvatar = _avatars[id]
		avatar.position = _arena.project(Vector2(float(actor.pos[0]), float(actor.pos[1])) / Sim.SCALE)
		avatar.render_battle(actor, 0.0)
		avatar.modulate = Color.WHITE if int(actor.hp) > 0 else Color(0.6, 0.6, 0.6, 0.4)
		avatar.z_index = int(float(actor.pos[1]) / Sim.SCALE)
	var player: Dictionary = session.actors.player
	_status.text = "Seed %d · %.1f s · %s\nHP %d · MP %d · %s · %s" % [seed_value, float(session.tick) / 30.0, "Complete: " + String(session.result.get("outcome", "draw")) if session.complete else ("Paused" if paused or focus_paused or _settings.visible else "Running"), player.hp, player.mp, String(player.get("phase", "")), String(player.get("action", "idle"))]
	for button: Button in _command_buttons:
		button.disabled = paused or focus_paused or _settings.visible or bool(session.complete)
	_meters.queue_redraw()

func _fit_stage() -> void:
	if not session.is_empty() and _stage.size.x > 0:
		_forest.size = _stage.size
		if _forest_enabled:
			_forest.frame_session(session, 1.0, true)
		_arena.fit_to(Rect2(Vector2(6, 6), _stage.size - Vector2(12, 12)))
		# Meter draw commands use the arena transform in sibling coordinates.
		# Container resize must refresh them even while simulation processing stops.
		_meters.queue_redraw()

func _update_timings() -> void:
	var lines: PackedStringArray = ["Pinned config " + String(configuration.get("sha256", "")), "Effective timing: ticks / seconds (30 Hz)"]
	for id: String in configuration.get("moves", {}):
		var move: Dictionary = configuration.moves[id]
		lines.append("%s: cast %d / %.3f; active %d / %.3f; recovery %d / %.3f; cooldown %d / %.3f; radius %.3f; visual ×%.2f" % [id, move.windup, float(move.windup) / 30.0, move.active, float(move.active) / 30.0, move.recovery, float(move.recovery) / 30.0, move.cooldown, float(move.cooldown) / 30.0, float(move.projectile_radius) / Sim.SCALE, float(move.visual_scale) / 1000.0])
	_timings.text = "\n".join(lines)

func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED]:
		focus_paused = true
		accumulator = 0.0
	elif what in [NOTIFICATION_APPLICATION_FOCUS_IN, NOTIFICATION_APPLICATION_RESUMED]:
		focus_paused = false
		accumulator = 0.0


func _load_content() -> Dictionary:
	if table_directory != Content.DIRECTORY:
		return Content.load_tables(table_directory)
	var live := GameBalance._data
	var live_error := GameBalance.error
	GameBalance.reload()
	var loaded := MobContent.load_tables()
	if loaded.ok: balance_snapshot = GameBalance.data().duplicate(true)
	GameBalance._data = live
	GameBalance.error = live_error
	return loaded


func _mob_session(seed_number: int) -> Dictionary:
	if configuration.get("schema_version") != MobContent.SCHEMA_VERSION:
		return {"ok": false, "error": "Mob fixtures require the applied Excel balance."}
	var live := GameBalance._data
	GameBalance._data = balance_snapshot
	var encounter := MobCatalog.encounter(mini(mob_fixture, 3), seed_number)
	if mob_fixture >= 4: encounter.members = [["slime_metal"], ["slime_spitter"], ["fairy_striker"]][mob_fixture - 4]
	var hero := Sim.make_snapshot("player", "Partner", "agumon", "Rookie", "Bold", stat_overrides.allies, {}, configuration)
	var arena := BattleArena.graybox()
	var assembled := MobCatalog.roster(hero, encounter, arena, configuration)
	GameBalance._data = live
	if not assembled.ok: return assembled
	var supplies := {}
	for item: String in configuration.items: supplies[item] = Sim.MAX_SUPPLIES
	return Sim.create_roster_session("sandbox-mobs-%d" % seed_number, seed_number, assembled.roster, arena, Sim.DEFAULT_MAX_TICKS, {}, supplies, {}, "", "", configuration)
