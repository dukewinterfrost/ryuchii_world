@tool
extends AnimatedSprite3D
## Keeps the existing animation pivots when changing clips in the Inspector.
## SpriteFrames, Pixel Size, Transform, and animation controls are native Godot.

@export var play_on_run := true
@export var use_authored_pivots := true

func _ready() -> void:
	ScreenAlignedSprite.apply(self)
	frame_changed.connect(_apply_pivot)
	animation_changed.connect(_apply_pivot)
	_apply_pivot()
	if not Engine.is_editor_hint() and play_on_run:
		play(animation)

func _apply_pivot() -> void:
	if not use_authored_pivots or sprite_frames == null:
		return
	var pivots: Dictionary = sprite_frames.get_meta("workshop_pivots", {})
	var frames: Array = pivots.get(String(animation), [])
	if frame < 0 or frame >= frames.size():
		return
	var texture := sprite_frames.get_frame_texture(animation, frame)
	if texture != null:
		var pivot: Vector2 = frames[frame]
		offset = texture.get_size() * Vector2(0.5 - pivot.x, pivot.y - 0.5)
