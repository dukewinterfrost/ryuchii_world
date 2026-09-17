extends SceneTree

var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var game := root.get_node("GameState")
	_check(game.isolated_mode, "review tests isolate persistent companion state")
	if not game.isolated_mode:
		quit(1)
		return
	var original: Dictionary = game.get_state()
	var review: Node2D = (load("res://scenes/asset_review_scene.tscn") as PackedScene).instantiate()
	root.add_child(review)
	await process_frame
	review._playing = false
	_check(review._placeholders and review._clip.item_count == 11, "all named placeholders available without a candidate")
	for species_id: String in ["botamon", "koromon", "agumon"]:
		review._avatar.configure(species_id)
		var frames: SpriteFrames = review._avatar.sprite.sprite_frames
		var animations := frames.get_animation_names()
		for index: int in CompanionEffects.EFFECTS.size():
			review._clip.select(index)
			review._elapsed = 0.42
			review._render_animation()
			await process_frame
			_check(review._effects.effect_id == CompanionEffects.EFFECTS[index], species_id + " renders " + CompanionEffects.EFFECTS[index])
			if CompanionEffects.EFFECTS[index] == "feed" and (frames.has_animation("eat") or frames.has_animation("eat.default")):
				_check(String(review._avatar.sprite.animation) in ["eat", "eat.default"], species_id + " feeding preview samples authored eat pose instead of idle fallback")
			_check(review._avatar.sprite.sprite_frames == frames and frames.get_animation_names() == animations and is_zero_approx(review._avatar.sprite.rotation), "overlay never replaces sprite resources or rotates feet")
	var effects: CompanionEffects = review._effects
	effects.play_effect("pet", 0.1)
	effects._process(0.2)
	_check(effects.effect_id.is_empty(), "care effects expire without gameplay mutation")
	effects.sample_effect("stun", 0.4)
	effects._process(99)
	_check(is_equal_approx(effects.progress, 0.4), "battle/review samples never advance using wall clock")
	effects.reduced_motion = true
	effects.sample_effect("hit_fire", 0.4)
	await process_frame
	effects.play_effect("unknown_effect")
	_check(effects.effect_id.is_empty(), "unknown effects fail closed")
	_check(game.get_state() == original, "all effect previews leave real gameplay state unchanged")
	var args := OS.get_cmdline_user_args()
	if "--capture-placeholder-gallery" in args and DisplayServer.get_name() != "headless":
		review.visible = false
		for child: Node in review.get_children():
			if child is CanvasLayer:
				child.visible = false
		# Native renderer contact sheet; no source art processing or replacement.
		for index: int in CompanionEffects.EFFECTS.size():
			var origin := Vector2(50 + (index % 4) * 265, 35 + (index / 4) * 250)
			var avatar := CompanionAvatar.new()
			root.add_child(avatar)
			avatar.configure("agumon")
			avatar.position = origin + Vector2(105, 205)
			avatar.render_combat("idle", "e", 0, 30)
			avatar.sprite.scale = Vector2.ONE * 1.3
			var overlay := CompanionEffects.new()
			avatar.add_child(overlay)
			overlay.scale = Vector2.ONE * 1.3
			overlay.sample_effect(CompanionEffects.EFFECTS[index], 0.35)
			var label := Label.new()
			root.add_child(label)
			label.position = origin
			label.text = CompanionEffects.LABELS[index]
			label.add_theme_font_size_override("font_size", 16)
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/tmp/companion-placeholder-gallery.png")
	review.free()
	print("%s: %d placeholder checks" % ["PASS" if failures.is_empty() else "FAIL", checks])
	for message: String in failures:
		printerr(message)
	quit(0 if failures.is_empty() else 1)


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
