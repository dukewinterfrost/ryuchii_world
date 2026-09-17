extends Node

const Scene = preload("res://scenes/battle_scene.tscn")
const Rules = preload("res://scripts/core/care_rules.gd")
const Definitions = preload("res://scripts/core/game_definitions.gd")
var checks := 0
var failures := 0

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	await get_tree().process_frame
	check(GameState.isolated_mode, "isolated test mode protects real companion saves")
	if not GameState.isolated_mode:
		get_tree().quit(1)
		return
	GameState.set_process(false)
	GameState.battle_paused = false
	get_tree().root.content_scale_size = Vector2i(360, 640)
	get_tree().root.size = Vector2i(360, 640)
	GameState.state = _rookie()
	GameState.start_training_battle(7412, "graybox")
	EnvironmentAssetLibrary._active_package = {"pin": {"assetId": "stale-environment",
		"revision": "old", "contentSha256": "sha256:" + "0".repeat(64)}}
	var scene := Scene.instantiate()
	get_tree().root.add_child(scene)
	scene.set_process(false)
	await get_tree().process_frame
	_resume_fixture(scene)
	check(not scene._environment_enabled and scene.arena_view.visible and not scene.environment_view.visible and scene.presentation_instrumentation().fallback, "missing environment pin keeps the live battle on its safe 2D presentation")
	check(EnvironmentAssetLibrary.active_pin().is_empty(), "2D/no-pin battle clears any previously active Environment package")
	check(scene.find_children("*", "OptionButton", true, false).is_empty(), "player-facing battle UI has no arena selector")
	check(scene.move_buttons.size() == 3 and scene.item_buttons.size() == 2, "pinned loadout and consumables build native controls")
	check(not scene.moves_button.disabled and not scene.items_button.disabled, "Rookie unlocks live moves and items")
	check(scene.item_buttons.small_recovery.disabled, "full HP disables wasteful recovery")
	scene._toggle_picker("moves")
	check(scene._picker.visible and scene._move_list.visible, "move picker opens over arena")
	check(scene._picker.position.y >= scene._arena_rect.end.y and not scene._order_row.visible and not scene._action_row.visible and not scene._bottom_row.visible, "drawer leaves arena visible and removes obscured controls from keyboard navigation")
	if "--capture-controls" in OS.get_cmdline_user_args():
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("/tmp/godot-battle-moves-360x640.png")
		_resume_fixture(scene)
	var tick := int(GameState.active_battle_result.tick)
	scene._process(0.2)
	check(GameState.active_battle_result.tick > tick and scene._picker.visible, "live battle advances while move picker remains open")
	var same_button: Button = scene.move_buttons.quick_bite
	same_button.grab_focus()
	scene._process(0.1)
	check(scene.move_buttons.quick_bite == same_button and same_button.has_focus(), "refresh retains controls and keyboard focus")
	scene._request_move("quick_bite")
	scene._process(0.1)
	check(_command_kind("move_request"), "move picker sends simulation command")
	check(scene._picker_feedback.text.contains("requested") or scene._picker_feedback.text.contains("queued"), "move feedback reaches picker")
	scene._toggle_picker("items")
	var actor: Dictionary = GameState.active_battle_result.actors.player
	actor.hp = 25 # Controlled fixture enables an otherwise-full health item.
	scene._refresh_picker()
	check(not scene.item_buttons.small_recovery.disabled, "injured companion can select recovery")
	if "--capture-controls" in OS.get_cmdline_user_args():
		await get_tree().process_frame
		_resume_fixture(scene)
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("/tmp/godot-battle-items-360x640.png")
		_resume_fixture(scene)
	var before := int(GameState.state.inventory.items.small_recovery)
	scene._use_item("small_recovery")
	scene._process(1.0 / 30.0)
	check(int(GameState.state.inventory.items.small_recovery) == before - 1 and _command_kind("item_use"), "accepted item spends inventory through GameState")
	check(scene.item_buttons.small_recovery.disabled and scene._picker_note.text.contains("ready in"), "shared cooldown disables items with countdown")
	check(scene._picker_feedback.text.contains("restores"), "tick-confirmed item feedback explains restoration")
	var current_tick := int(GameState.active_battle_result.tick)
	GameState.battle_paused = true
	scene._process(10.0)
	check(int(GameState.active_battle_result.tick) == current_tick and scene.items_button.disabled, "focus pause disables commands and freezes simulation")
	GameState.battle_paused = false
	scene._process(0.01)
	scene._on_battle_command_resolved({"ok": false, "error": "Save failed; item not spent."})
	check(scene._picker_feedback.text == "Save failed; item not spent.", "actual tick failures remain visible")
	var pristine := GameState.active_battle_result.duplicate(true)
	scene._apply_event({"event": "hit", "action_id": "pepper_breath", "target_id": "player", "tick": current_tick, "message": "Fire hit"})
	scene._render_frame(1.0)
	check(scene.effects_by_id.player.effect_id == "hit_fire" and GameState.active_battle_result == pristine, "fire hit samples separate visual overlay without combat mutation")
	check(is_zero_approx(scene.player_avatar.rotation) and scene.player_avatar.sprite.scale.y > 0, "effect does not rotate creature or invert feet")
	for size: Vector2i in [Vector2i(360, 640), Vector2i(390, 844)]:
		get_tree().root.content_scale_size = size
		get_tree().root.size = size
		await get_tree().process_frame
		scene._layout()
		check(scene._picker.get_rect().end.x <= size.x and scene._picker.get_rect().end.y <= size.y and scene._bottom_row.get_rect().end.y <= size.y, "command controls fit %dx%d portrait viewport" % [size.x, size.y])
		for button: Node in scene._hud.find_children("*", "BaseButton", true, false):
			check(button.size.y >= 44, "native battle touch target is at least 44px")
	scene.free()
	GameState.clear_active_battle()
	# New untouched deterministic session is used to verify replay isolation.
	GameState.state = _rookie()
	GameState.start_training_battle(5231, "graybox")
	GameState.active_battle_result.max_ticks = 120
	scene = Scene.instantiate()
	get_tree().root.add_child(scene)
	scene.set_process(false)
	while not GameState.active_battle_result.complete:
		GameState.advance_training_battle()
	scene._process(0.0)
	var settled := GameState.get_state()
	scene._start_replay()
	check(scene._is_replay and scene.moves_button.disabled and scene.items_button.disabled, "replay disables all move and item controls")
	scene._toggle_picker("items")
	scene._use_item("small_recovery")
	scene._request_move("heavy_claw")
	scene._give_order("attack")
	check(not scene._picker.visible and GameState.get_state() == settled, "direct replay handlers cannot enqueue commands or mutate inventory")
	scene._skip()
	check(scene.playback.is_complete() and GameState.get_state() == settled, "replay completion preserves settled inventory and rewards")
	scene.free()
	GameState.clear_active_battle()
	GameState.state = Rules.make_new_state(1000.0)
	GameState.start_training_battle(36, "graybox")
	scene = Scene.instantiate()
	get_tree().root.add_child(scene)
	scene.set_process(false)
	check(scene.moves_button.disabled and scene.moves_button.text.contains("Rookie") and scene.move_buttons.is_empty(), "Baby custom skills remain locked while auto attacks remain")
	scene.free()
	GameState.clear_active_battle()
	print("Battle controls: %d checks, %d failures" % [checks, failures])
	get_tree().quit(1 if failures else 0)

func _rookie() -> Dictionary:
	var state := Rules.make_new_state(1000.0)
	state.identity.merge({"species_id": "agumon", "species_name": "Agumon", "stage": "Rookie"}, true)
	state.skills = Definitions.default_skills("agumon")
	state.battle_profile.hp = 200
	return state

func _resume_fixture(scene: Node) -> void:
	# A native automation window can start behind Codex, generating real focus
	# notifications between awaited screenshot frames. The controlled test advances
	# its own clock; focus suspension is exercised explicitly later in this runner.
	GameState.battle_paused = false
	scene._discard_next_delta = false
	scene._render_frame(1.0)

func _command_kind(kind: String) -> bool:
	for command: Dictionary in GameState.active_battle_result.commands:
		if command.get("kind") == kind:
			return true
	return false

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
