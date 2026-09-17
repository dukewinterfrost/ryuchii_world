class_name CompanionAvatar
extends Node2D

signal action_finished(action: String)

var sprite := AnimatedSprite2D.new()
var animation_state := CompanionAnimationState.new()
var species_id := ""
var provenance: Dictionary = {}
var _target := Vector2.ZERO
var _wait_seconds := 0.0
var _rng := RandomNumberGenerator.new()
var roam_bounds := Rect2(42.0, 275.0, 306.0, 270.0)
var roaming_enabled := true
var battle_rendering := false
var _active_action: String:
	get: return animation_state.active_action
var _action_locked: bool:
	get: return animation_state.action_locked
var visual_fallback: String:
	get: return animation_state.visual_fallback
var facing: String:
	get: return animation_state.facing
	set(value): animation_state.facing = animation_state.normalized_facing(value)


func _ready() -> void:
	_rng.randomize()
	add_child(sprite)
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.animation_finished.connect(_on_animation_finished)
	sprite.frame_changed.connect(_apply_frame_pivot)
	_target = position


func configure(next_species_id: String) -> void:
	if next_species_id == species_id:
		return
	var loaded := CompanionAssetLibrary.build(next_species_id)
	if loaded.is_empty():
		push_error("No curated companion animation set for: " + next_species_id)
		return
	species_id = next_species_id
	_apply_library(loaded)
	sprite.scale = Vector2.ONE * (1.72 if species_id == "agumon" else 2.05)
	play_loop("idle")


func configure_library(loaded: Dictionary) -> void:
	# Review candidates without promoting or replacing the active care companion.
	if loaded.is_empty():
		return
	species_id = String(loaded.get("manifest", {}).get("subjectId", "candidate"))
	_apply_library(loaded)
	roaming_enabled = false


func _apply_library(loaded: Dictionary) -> void:
	if not animation_state.configure_library(loaded):
		return
	provenance = (loaded.get("provenance", {}) as Dictionary).duplicate(true)
	provenance.merge({
		"revision": loaded.get("revision", "unknown"),
		"status": loaded.get("status", "unknown"),
		"frame_sources": loaded.get("frame_sources", {}),
		"clip_provenance": loaded.get("clip_provenance", {}),
	}, true)
	sprite.sprite_frames = animation_state.frames


func render_combat(action: String, next_facing: String, action_tick: float, action_duration: float) -> void:
	if sprite.sprite_frames == null:
		return
	battle_rendering = true
	var sample := animation_state.sample_combat(action, next_facing, action_tick, action_duration)
	if sample.is_empty():
		return
	sprite.pause()
	sprite.animation = String(sample.animation)
	sprite.flip_h = bool(sample.flipH)
	sprite.rotation = 0.0
	sprite.set_frame_and_progress(int(sample.frame), float(sample.progress))
	_apply_frame_pivot()


func render_battle(actor: Dictionary, interpolation: float = 1.0) -> void:
	var tick := float(actor.get("action_tick", 0)) + clampf(interpolation, 0.0, 1.0)
	render_combat(String(actor.get("action", "idle")), String(actor.get("facing", "e")), tick, float(actor.get("action_duration", 0)))


func _resolve_animation(action: String, requested_facing: String) -> String:
	var selected := animation_state.resolve_animation(action, requested_facing)
	sprite.flip_h = animation_state.flip_h
	return selected


func play_action(action: String) -> void:
	if sprite.sprite_frames == null:
		return
	battle_rendering = false
	var selected := animation_state.begin_action(action)
	if selected.is_empty():
		return
	sprite.flip_h = animation_state.flip_h
	sprite.play(selected)
	_apply_frame_pivot()


func play_loop(animation_name: String) -> void:
	if sprite.sprite_frames == null:
		return
	battle_rendering = false
	var selected := animation_state.begin_loop(animation_name)
	if selected.is_empty():
		return
	sprite.flip_h = animation_state.flip_h
	if sprite.animation != selected or not sprite.is_playing():
		sprite.play(selected)
	_apply_frame_pivot()


func face_care_direction(direction: Vector2) -> void:
	animation_state.set_facing_from_motion(direction)
	rotation = 0.0
	sprite.rotation = 0.0


func is_care_action_playing() -> bool:
	return animation_state.action_locked and not battle_rendering


func _process(delta: float) -> void:
	if species_id.is_empty() or animation_state.action_locked or not roaming_enabled or battle_rendering:
		return
	if _wait_seconds > 0.0:
		_wait_seconds -= delta
		play_loop("idle")
		return
	if _target == Vector2.ZERO or position.distance_to(_target) < 5.0:
		_target = Vector2(
			_rng.randf_range(roam_bounds.position.x, roam_bounds.end.x),
			_rng.randf_range(roam_bounds.position.y, roam_bounds.end.y)
		)
		_wait_seconds = _rng.randf_range(1.2, 3.2)
		return
	var direction := position.direction_to(_target)
	animation_state.set_facing_from_motion(direction)
	var speed := 23.0 if species_id == "agumon" else 18.0
	position += direction * speed * delta
	position.x = clampf(position.x, roam_bounds.position.x, roam_bounds.end.x)
	position.y = clampf(position.y, roam_bounds.position.y, roam_bounds.end.y)
	sprite.rotation = 0.0
	play_loop("move")


func _apply_frame_pivot() -> void:
	if sprite.sprite_frames == null:
		return
	var pivot_value: Variant = animation_state.frame_pivot(String(sprite.animation), sprite.frame)
	if pivot_value == null:
		return
	var frame_texture := sprite.sprite_frames.get_frame_texture(sprite.animation, sprite.frame)
	if frame_texture == null:
		return
	var pivot: Vector2 = pivot_value
	var size := frame_texture.get_size()
	sprite.offset = Vector2(size.x * (0.5 - pivot.x), size.y * (0.5 - pivot.y))


func _on_animation_finished() -> void:
	if battle_rendering:
		return
	var finished_action := animation_state.complete_action()
	var idle := animation_state.resolved_animation
	if not idle.is_empty():
		sprite.flip_h = animation_state.flip_h
		sprite.play(idle)
		_apply_frame_pivot()
	if not finished_action.is_empty():
		action_finished.emit(finished_action)
