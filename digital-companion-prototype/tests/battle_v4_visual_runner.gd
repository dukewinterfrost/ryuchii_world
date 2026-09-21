extends Node

const Scene = preload("res://scenes/battle_scene.tscn")
var checks := 0
var failures := 0

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	await get_tree().process_frame
	check(GameState.isolated_mode, "visual fixture never enters real saves")
	if not GameState.isolated_mode:
		get_tree().quit(1)
		return
	GameState.set_process(false)
	GameState.state = CareRules.make_new_state(1000.0)
	GameState.state.identity.merge({"species_id": "agumon", "species_name": "Agumon", "stage": "Rookie"}, true)
	GameState.state.skills = GameDefinitions.default_skills("agumon")
	GameState.battle_paused = false
	var started := GameState.start_training_battle(8811, "green-shade")
	check(started.get("ok", false), "v4 contextual 3D fixture starts")
	if not started.get("ok", false):
		push_error(str(started))
		get_tree().quit(1)
		return
	var scene := Scene.instantiate()
	add_child(scene)
	scene.set_process(false)
	await get_tree().process_frame
	GameState.battle_paused = false
	check(scene._environment_enabled, "fixture exercises the real Sprite-in-3D battle adapter")
	var session: Dictionary = scene.battle
	var actor: Dictionary = session.actors[session.fighter_order[0]]
	var opponent: Dictionary = session.actors[session.fighter_order[1]]
	# Controlled presentation state makes charge screenshots stable at every size.
	actor.pos = [430000, 650000]
	actor.previous_pos = actor.pos.duplicate()
	opponent.pos = [530000, 650000]
	opponent.previous_pos = opponent.pos.duplicate()
	actor.aim = opponent.pos.duplicate()
	actor.current_move = session.combat_config.moves.pepper_breath.duplicate(true)
	actor.current_move.range = 150000
	actor.action = "special_attack"
	actor.phase = "charge"
	actor.windup = 30
	actor.active_ticks = 3
	actor.action_tick = 18
	actor.action_duration = 54
	opponent.aim = actor.pos.duplicate()
	opponent.current_move = session.combat_config.moves.opening_tackle.duplicate(true)
	opponent.action = "rush_attack"
	opponent.phase = "charge"
	opponent.windup = 24
	opponent.active_ticks = 12
	opponent.action_tick = 12
	opponent.action_duration = 63
	var pristine := session.duplicate(true)
	for dimensions: Vector2i in [Vector2i(360, 640), Vector2i(390, 844), Vector2i(844, 390)]:
		get_tree().root.content_scale_size = dimensions
		get_tree().root.size = dimensions
		await get_tree().process_frame
		GameState.battle_paused = false
		scene._layout()
		scene._render_frame(1.0)
		await get_tree().process_frame
		var evidence: Dictionary = scene.presentation_instrumentation()
		for indicator: Dictionary in scene.environment_view._charge_overlay.indicators:
			check(scene.environment_view.presentation_safe_rect.encloses(indicator.rect), "cast text stays inside visible battlefield away from HUD")
			check(indicator.rect.position.y <= float(indicator.anchor_y), "label collision resolution never pushes warnings down over a creature")
		check(scene.environment_view._charge_overlay.indicators.size() == 2, "screen-space charge labels stay anchored above both fighters")
		check(int(evidence.get("groundTelegraphs", 0)) == 2 and int(evidence.get("chargeBars", 0)) == 2, "3D shows both authored attack lanes and charge bars at " + str(dimensions))
		for button: Button in scene.move_buttons.values():
			check(button.is_visible_in_tree() and button.size.x >= 44 and button.size.y >= 44, "direct ability touch target at " + str(dimensions))
		for button: Button in scene.defense_buttons.values():
			check(button.get_global_rect().end.x <= dimensions.x and button.get_global_rect().end.y <= dimensions.y, "defense fits " + str(dimensions))
		await _capture("charge", dimensions)
		scene._toggle_picker("items")
		await get_tree().process_frame
		GameState.battle_paused = false
		scene._refresh_picker()
		for button: Button in scene.defense_buttons.values():
			check(button.is_visible_in_tree() and not button.get_global_rect().intersects(scene._picker.get_global_rect()), "item drawer never covers defense at " + str(dimensions))
		await _capture("items", dimensions)
		scene._close_picker()
	check(session == pristine, "layout, charge rendering, and drawers do not mutate simulation")
	var before_cue := BattlePresentationCues.attack(actor, session.arena)
	var visual_variant := actor.duplicate(true)
	visual_variant.current_move.visual_scale = 5000
	var after_cue := BattlePresentationCues.attack(visual_variant, session.arena)
	check(before_cue.points == after_cue.points, "visual scale does not change telegraph collision geometry")
	visual_variant.current_move.melee_width = 32000
	visual_variant.current_move.kind = "melee"
	var width_cue := BattlePresentationCues.attack(visual_variant, session.arena)
	check(is_equal_approx(float(width_cue.half_width), 16), "authored melee full width becomes correct ground half-width")
	var cue_before: Dictionary = scene.presentation_instrumentation()
	scene._motion.button_pressed = true
	scene._render_frame(1.0)
	check(scene.environment_view.reduced_motion and scene.presentation_instrumentation().chargeBars == cue_before.chargeBars, "reduced motion retains charge information")
	scene._audio.muted = true
	var audio_count: int = scene._audio.played_events.size()
	scene._audio.play_event({"event": "perfect_guard"})
	check(scene._audio.played_events.size() == audio_count, "mute suppresses event audio")
	scene._audio.muted = false
	for kind: String in ["hit", "charge_started", "perfect_guard"]:
		scene._audio.play_event({"event": kind})
	check(scene._audio._tones.size() >= 3 and scene._audio._tones.hit != scene._audio._tones.perfect_guard, "charge, hit and perfect guard use distinct event sounds")
	check(BattlePresentationCues.animation(opponent) == "guard", "opening tackle deliberately uses existing brace pose")
	var bubble: Texture2D = scene.environment_view._projectile_texture("bubble")
	check(bubble != scene.environment_view._projectile_texture("fire"), "authored bubble and fire references use distinct visual effects")
	_test_melee_impact_scale(scene)
	_test_protected_impacts(scene)
	scene._audio.stop_all()
	# Let the audio thread release its finished playback handles before shutdown.
	await get_tree().create_timer(0.2).timeout
	scene.free()
	GameState.clear_active_battle()
	print("Battle v4 visuals: %d checks, %d failures" % [checks, failures])
	get_tree().quit(1 if failures else 0)

func _capture(state: String, dimensions: Vector2i) -> void:
	if "--capture-controls" not in OS.get_cmdline_user_args():
		return
	await RenderingServer.frame_post_draw
	var output := "/tmp/battle-v4-%s-%dx%d.png" % [state, dimensions.x, dimensions.y]
	check(get_viewport().get_texture().get_image().save_png(output) == OK, "capture " + output)

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)


func _test_melee_impact_scale(scene: Node) -> void:
	var original: Dictionary = scene.battle
	var original_copy := original.duplicate(true)
	var target_id := String(original.fighter_order[0])
	var was_3d: bool = scene._environment_enabled
	var canvas_effect := CompanionEffects.new()
	scene.add_child(canvas_effect)
	scene.effects_by_id[target_id] = canvas_effect
	for use_3d: bool in [false, true]:
		var sizes: Array[float] = []
		var cues: Array[Dictionary] = []
		for authored_scale: int in [1000, 2500]:
			# Simulate a new battle pinning a table edit, never mutate a live pin.
			var pinned := original.duplicate(true)
			pinned.combat_config.moves.heavy_claw.visual_scale = authored_scale
			var actor: Dictionary = pinned.actors[target_id]
			actor.current_move = pinned.combat_config.moves.heavy_claw.duplicate(true)
			actor.action = "basic_attack"
			actor.phase = "charge"
			var before := pinned.duplicate(true)
			var cue_before := BattlePresentationCues.attack(actor, pinned.arena, pinned)
			cues.append(cue_before)
			scene.battle = pinned
			scene._environment_enabled = use_3d
			scene._apply_event({"event": "hit", "move_id": "heavy_claw", "target_id": target_id, "tick": int(pinned.tick)})
			if use_3d:
				scene.environment_view._sample_hit_vfx(target_id, BattlePresentationCues.ground(actor.pos), pinned, 1.0)
				sizes.append(scene.environment_view.fighter_vfx[target_id].scale.y)
			else:
				scene._render_effect(target_id, actor, pinned, 1.0)
				sizes.append(canvas_effect.scale.y)
			check(pinned == before and BattlePresentationCues.attack(actor, pinned.arena, pinned) == cue_before, "impact scaling preserves authoritative session and melee telegraph")
		check(cues[0] == cues[1], "editing melee impact visual_scale leaves collision telegraph unchanged")
		check(is_equal_approx(sizes[1] / sizes[0], 2.5), "pinned melee visual_scale scales %s impact only" % ("3D" if use_3d else "2D"))
	scene.battle = original
	scene._environment_enabled = was_3d
	scene.effects_by_id.erase(target_id)
	scene._effect_records.erase(target_id)
	canvas_effect.free()
	scene.environment_view.clear_effects()
	check(original == original_copy, "testing edited impact pins never changes the active battle")


func _test_protected_impacts(scene: Node) -> void:
	var original: Dictionary = scene.battle
	var pinned := original.duplicate(true)
	var defender := String(pinned.fighter_order[0])
	var attacker := String(pinned.fighter_order[1])
	# This is the actual post-resolution state: guard stays on the defender,
	# while the simulator has already applied stagger to the melee attacker.
	pinned.actors[defender].action = "guard"
	pinned.actors[attacker].action = "hit"
	var before := pinned.duplicate(true)
	var was_3d: bool = scene._environment_enabled
	var canvas_effect := CompanionEffects.new()
	scene.add_child(canvas_effect)
	scene.effects_by_id[defender] = canvas_effect
	scene.battle = pinned
	for use_3d: bool in [false, true]:
		scene._environment_enabled = use_3d
		scene._effect_records.clear()
		scene.environment_view.clear_effects()
		var audio_before: int = scene._audio.played_events.size()
		scene._apply_event({"event": "perfect_guard", "actor_id": defender, "target_id": attacker, "move_id": "heavy_claw", "tick": int(pinned.tick), "message": "Perfect guard!"})
		scene._apply_event({"event": "hit", "actor_id": attacker, "target_id": defender, "move_id": "heavy_claw", "tick": int(pinned.tick), "damage": 0, "perfect_guard": true, "absorbed": 0, "message": "Hits for 0 through guard."})
		var records: Dictionary = scene.environment_view._effect_records if use_3d else scene._effect_records
		check(records.has(defender) and records[defender].effect == "perfect_guard" and not records.has(attacker), "perfect guard celebrates the defender without a hurt effect on either actor")
		check(scene.event_label.text == "Perfect guard!" and not "hit" in scene._audio.played_events.slice(audio_before), "paired zero-damage hit preserves perfect-guard feedback and suppresses hurt audio")
		if use_3d:
			scene.environment_view._sample_hit_vfx(defender, BattlePresentationCues.ground(pinned.actors[defender].pos), pinned, 1.0)
			scene.environment_view._sample_body_accent(defender, scene.environment_view.fighter_presentations[defender], pinned, 1.0)
			check(scene.environment_view.fighter_vfx[defender].texture == scene.environment_view._protective_effect_texture(true) and scene.environment_view.fighter_presentations[defender].sprite.modulate == Color.WHITE, "3D perfect guard renders a blue shield with no red hurt flash")
		else:
			scene._render_effect(defender, pinned.actors[defender], pinned, 1.0)
			scene._sample_body_accent(defender, scene.player_avatar, pinned, 1.0)
			check(canvas_effect.effect_id == "perfect_guard" and scene.player_avatar.sprite.modulate == Color.WHITE and is_zero_approx(scene.player_avatar.sprite.position.x), "2D perfect guard renders a supported shield with no hurt recoil")
		scene._apply_event({"event": "hit", "actor_id": attacker, "target_id": defender, "move_id": "heavy_claw", "tick": int(pinned.tick), "damage": 0, "perfect_guard": false, "absorbed": 12})
		check(records[defender].effect == "shield_impact", "fully absorbed barrier hits use a shield impact instead of red damage feedback")
		check(pinned == before, "defense presentation preserves simulator-owned guard and attacker stagger")
	scene.battle = original
	scene._environment_enabled = was_3d
	scene.effects_by_id.erase(defender)
	scene._effect_records.clear()
	canvas_effect.free()
	scene.environment_view.clear_effects()
