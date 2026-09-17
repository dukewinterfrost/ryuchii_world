extends Control
## Playable field reviews use the real battle scene with an isolated companion.

func _ready() -> void:
	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.offset_left = 20
	column.offset_right = -20
	column.offset_top = 28
	column.offset_bottom = -20
	column.add_theme_constant_override("separation", 14)
	add_child(column)
	var title := Label.new()
	title.text = "REGIONAL BATTLE FIELDS"
	title.add_theme_font_size_override("font_size", 22)
	column.add_child(title)
	var note := Label.new()
	note.text = "Playable reviews of your saved Godot fields.\n2D scenery cards on a 3D ground plane.\nPrivate prototype · unpromoted art · isolated save."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(note)
	for encounter: Dictionary in EncounterCatalog.all_debug_encounters():
		var button := Button.new()
		button.text = String(encounter.title).capitalize()
		button.custom_minimum_size.y = 56
		button.disabled = not GameState.isolated_mode
		button.pressed.connect(func() -> void:
			var result := start(String(encounter.regionId))
			if result.get("ok", false):
				get_tree().change_scene_to_file("res://scenes/battle_scene.tscn")
			else:
				note.text = String(result.get("error", "Field unavailable")))
		column.add_child(button)


static func start(region_id: String) -> Dictionary:
	var game: Node = (Engine.get_main_loop() as SceneTree).root.get_node("GameState")
	if not game.isolated_mode:
		return {"ok": false, "error": "Field reviews require an isolated save."}
	if not game.clear_active_battle():
		return {"ok": false, "error": "Finish the previous isolated result first."}
	game.state = CareRules.make_new_state(1000.0)
	game.state.identity.merge({"species_id": "agumon", "species_name": "Agumon", "stage": "Rookie"}, true)
	game.state.skills = GameDefinitions.default_skills("agumon")
	var result: Dictionary = game.start_training_battle(2468, region_id)
	if result.get("ok", false):
		game.set_meta("battle_field_review", region_id)
	return result
