class_name ScreenAlignedSprite
extends RefCounted
## Full camera-orientation billboarding, not position-facing look_at or Y-only
## billboarding. Depth, perspective scale, and authored foot pivots stay intact.

const PROFILE_ID := "screen-aligned-sprites-v2"

static func apply(sprite: SpriteBase3D) -> void:
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.rotation = Vector3.ZERO
	sprite.fixed_size = false
	sprite.no_depth_test = false
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST

static func rendered_basis(sprite: SpriteBase3D) -> Basis:
	# Billboard rotation happens in the renderer, not Node3D.global_basis.
	# CPU framing must use the same camera basis or it will clip tall animations.
	var camera: Camera3D = sprite.get_viewport().get_camera_3d() if sprite.is_inside_tree() else null
	var basis := camera.global_basis.orthonormalized() if camera != null else Basis.IDENTITY
	var dimensions := sprite.global_basis.get_scale() if sprite.is_inside_tree() else sprite.scale
	return Basis(basis.x * absf(dimensions.x), basis.y * absf(dimensions.y), basis.z * absf(dimensions.z))
