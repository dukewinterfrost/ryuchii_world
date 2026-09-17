class_name CompanionPresentation3D
extends Node3D

signal action_finished(action: String)

const PIXEL_SIZE := 1.0 / 32.0
const PLANE_TILT_DEGREES := 0.0

var sprite := AnimatedSprite3D.new()
var shadow := MeshInstance3D.new()
var animation_state := CompanionAnimationState.new()
var species_id := ""
var provenance: Dictionary = {}
var frame_anchors: Dictionary = {}
var _head_pixels: Dictionary = {}
var battle_rendering := false
var requested_action: String:
	get: return animation_state.requested_action
var resolved_animation: String:
	get: return animation_state.resolved_animation
var visual_fallback: String:
	get: return animation_state.visual_fallback
var facing: String:
	get: return animation_state.facing
	set(value): animation_state.facing = animation_state.normalized_facing(value)


func _ready() -> void:
	_build_shadow()
	_build_sprite()


func configure(next_species_id: String) -> bool:
	var loaded := CompanionAssetLibrary.build(next_species_id)
	if loaded.is_empty():
		push_error("No curated companion animation set for: " + next_species_id)
		return false
	return configure_library(loaded, next_species_id)


func configure_library(loaded: Dictionary, fallback_species_id := "candidate") -> bool:
	if not animation_state.configure_library(loaded):
		return false
	species_id = String(loaded.get("manifest", {}).get("subjectId", fallback_species_id))
	provenance = (loaded.get("provenance", {}) as Dictionary).duplicate(true)
	frame_anchors = loaded.get("anchors", {}).duplicate(true)
	_head_pixels.clear()
	provenance.merge({
		"revision": loaded.get("revision", "unknown"),
		"status": loaded.get("status", "unknown"),
		"frame_sources": loaded.get("frame_sources", {}),
		"clip_provenance": loaded.get("clip_provenance", {}),
	}, true)
	sprite.sprite_frames = animation_state.frames
	play_loop("idle")
	return true


func set_ground_position(ground_position: Vector2) -> void:
	position = EnvironmentView3D.ground_to_world(ground_position)


func get_ground_position() -> Vector2:
	return EnvironmentView3D.world_to_ground(position)


func head_world_position() -> Vector3:
	if sprite.sprite_frames == null:
		return global_position + Vector3.UP
	var texture := sprite.sprite_frames.get_frame_texture(sprite.animation, sprite.frame)
	if texture == null:
		return global_position + Vector3.UP
	var id := texture.get_instance_id()
	if not _head_pixels.has(id):
		var used := texture.get_image().get_used_rect()
		_head_pixels[id] = Vector2(used.get_center().x, used.position.y)
	var point: Vector2 = _head_pixels[id]
	if sprite.flip_h:
		point.x = texture.get_width() - point.x
	var pixels := point - texture.get_size() * 0.5
	return global_position + sprite.position + ScreenAlignedSprite.rendered_basis(sprite) * Vector3(
		(pixels.x + sprite.offset.x) * sprite.pixel_size,
		(-pixels.y + sprite.offset.y) * sprite.pixel_size, 0)


func attachment_offset(anchor_name: String) -> Vector3:
	# Authored anchors are normalized within the untrimmed frame. Older art only
	# has a root; use a sprite-relative mouth/body location, never a ground height.
	var point := Vector2(0.70, 0.55) if anchor_name == "mouth" else Vector2(0.5, 0.65)
	var anchors: Array = frame_anchors.get(String(sprite.animation), [])
	if sprite.frame < anchors.size() and anchors[sprite.frame].has(anchor_name):
		var value: Dictionary = anchors[sprite.frame][anchor_name]
		point = Vector2(float(value.x), float(value.y))
	if sprite.sprite_frames == null:
		return Vector3(0, 1, 0)
	var texture := sprite.sprite_frames.get_frame_texture(sprite.animation, sprite.frame)
	if texture == null:
		return Vector3(0, 1, 0)
	if sprite.flip_h:
		point.x = 1.0 - point.x
	var pixels := (point - Vector2.ONE * 0.5) * texture.get_size()
	return sprite.position + ScreenAlignedSprite.rendered_basis(sprite) * Vector3(
		(pixels.x + sprite.offset.x) * sprite.pixel_size,
		(-pixels.y + sprite.offset.y) * sprite.pixel_size, 0)


func visual_world_corners(ground_position: Vector2, maximum_over_all_frames := true) -> Array[Vector3]:
	## Exact rooted sprite envelope, including authored per-frame pivots, pixel
	## scale, camera-facing basis, and the presentation's small root offset.
	var rect := _maximum_pixel_rect() if maximum_over_all_frames else _current_pixel_rect()
	var result: Array[Vector3] = []
	if rect.size == Vector2.ZERO:
		return result
	var tilt := ScreenAlignedSprite.rendered_basis(sprite)
	var origin := EnvironmentView3D.ground_to_world(ground_position) + sprite.position
	for point: Vector2 in [rect.position, Vector2(rect.end.x, rect.position.y), rect.end,
			Vector2(rect.position.x, rect.end.y)]:
		result.append(origin + tilt * Vector3(point.x * sprite.pixel_size,
			point.y * sprite.pixel_size, 0.0))
	return result


func set_facing_from_motion(direction: Vector2) -> void:
	animation_state.set_facing_from_motion(direction)
	sprite.rotation_degrees = Vector3(PLANE_TILT_DEGREES, 0.0, 0.0)


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
	sprite.rotation_degrees = Vector3(PLANE_TILT_DEGREES, 0.0, 0.0)
	sprite.set_frame_and_progress(int(sample.frame), float(sample.progress))
	_apply_frame_pivot()


func render_battle(actor: Dictionary, interpolation: float = 1.0) -> void:
	var tick := float(actor.get("action_tick", 0)) + clampf(interpolation, 0.0, 1.0)
	render_combat(String(actor.get("action", "idle")), String(actor.get("facing", "e")), tick, float(actor.get("action_duration", 0)))


func play_loop(action: String) -> bool:
	if sprite.sprite_frames == null:
		return false
	battle_rendering = false
	var selected := animation_state.begin_loop(action)
	if selected.is_empty():
		return false
	sprite.flip_h = animation_state.flip_h
	if sprite.animation != selected or not sprite.is_playing():
		sprite.play(selected)
	_apply_frame_pivot()
	return true


func play_action(action: String) -> bool:
	if sprite.sprite_frames == null:
		return false
	battle_rendering = false
	var selected := animation_state.begin_action(action)
	if selected.is_empty():
		return false
	sprite.flip_h = animation_state.flip_h
	sprite.play(selected)
	_apply_frame_pivot()
	return true


func is_action_playing() -> bool:
	return animation_state.action_locked and not battle_rendering


func _build_sprite() -> void:
	sprite.name = "AnimatedSprite3D"
	sprite.pixel_size = PIXEL_SIZE
	sprite.position.y = 0.30
	sprite.rotation_degrees.x = PLANE_TILT_DEGREES
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sprite.shaded = false
	ScreenAlignedSprite.apply(sprite)
	sprite.fixed_size = false
	sprite.no_depth_test = false
	sprite.double_sided = true
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	sprite.animation_finished.connect(_on_animation_finished)
	sprite.frame_changed.connect(_apply_frame_pivot)
	add_child(sprite)


func _build_shadow() -> void:
	shadow.name = "ContactShadow"
	var plane := PlaneMesh.new()
	plane.size = Vector2(3.2, 1.45)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_texture = _make_shadow_texture()
	plane.material = material
	shadow.mesh = plane
	shadow.position.y = 0.01
	add_child(shadow)


func _apply_frame_pivot() -> void:
	if sprite.sprite_frames == null:
		return
	var pivot_value: Variant = animation_state.frame_pivot(String(sprite.animation), sprite.frame)
	if pivot_value == null:
		return
	var texture := sprite.sprite_frames.get_frame_texture(sprite.animation, sprite.frame)
	if texture == null:
		return
	var pivot: Vector2 = pivot_value
	var size := texture.get_size()
	sprite.offset = Vector2(size.x * (0.5 - pivot.x), size.y * (pivot.y - 0.5))


func _current_pixel_rect() -> Rect2:
	if sprite.sprite_frames == null or not sprite.sprite_frames.has_animation(sprite.animation):
		return Rect2()
	var texture := sprite.sprite_frames.get_frame_texture(sprite.animation, sprite.frame)
	if texture == null:
		return Rect2()
	return Rect2(-texture.get_size() * 0.5 + sprite.offset, texture.get_size())


func _maximum_pixel_rect() -> Rect2:
	if sprite.sprite_frames == null:
		return Rect2()
	var result := Rect2()
	var initialized := false
	for animation: StringName in sprite.sprite_frames.get_animation_names():
		for frame: int in sprite.sprite_frames.get_frame_count(animation):
			var texture := sprite.sprite_frames.get_frame_texture(animation, frame)
			if texture == null:
				continue
			var pivot_value: Variant = animation_state.frame_pivot(String(animation), frame)
			var pivot := Vector2(0.5, 0.5) if pivot_value == null else pivot_value as Vector2
			var size := texture.get_size()
			var offset := Vector2(size.x * (0.5 - pivot.x), size.y * (pivot.y - 0.5))
			var frame_rect := Rect2(-size * 0.5 + offset, size)
			result = frame_rect if not initialized else result.merge(frame_rect)
			initialized = true
	return result


func _on_animation_finished() -> void:
	if battle_rendering:
		return
	var completed := animation_state.complete_action()
	var idle := animation_state.resolved_animation
	if not idle.is_empty():
		sprite.flip_h = animation_state.flip_h
		sprite.play(idle)
		_apply_frame_pivot()
	if not completed.is_empty():
		action_finished.emit(completed)


static func _make_shadow_texture() -> Texture2D:
	var image := Image.create(32, 16, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	for y: int in 16:
		for x: int in 32:
			var nx := (float(x) + 0.5 - 16.0) / 15.0
			var ny := (float(y) + 0.5 - 8.0) / 7.0
			var radius := nx * nx + ny * ny
			if radius <= 1.0:
				image.set_pixel(x, y, Color(0.035, 0.055, 0.035, (1.0 - radius) * 0.48))
	return ImageTexture.create_from_image(image)
