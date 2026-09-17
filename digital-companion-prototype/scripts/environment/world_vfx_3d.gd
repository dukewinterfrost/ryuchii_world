class_name WorldVFX3D
extends Sprite3D

var profile: WorldVFXProfile


func configure(texture_value: Texture2D, definition: Dictionary) -> bool:
	if texture_value == null:
		return false
	var alpha_mode := String(definition.get("alphaMode", ""))
	if not EnvironmentPresentationContract.valid_render_priority(definition.get("renderPriority"), alpha_mode == "transparent"):
		return false
	var pixel_size_value: Variant = definition.get("pixelSize")
	if not (pixel_size_value is int or pixel_size_value is float) or not is_finite(float(pixel_size_value)) or float(pixel_size_value) <= 0.0:
		return false
	var next_profile := WorldVFXProfile.from_definition(definition)
	if not next_profile.is_valid():
		return false
	profile = next_profile
	texture = texture_value
	pixel_size = profile.pixel_size
	rotation_degrees = Vector3(profile.plane_tilt_degrees, 0.0, 0.0)
	texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	shaded = false
	ScreenAlignedSprite.apply(self)
	fixed_size = false
	no_depth_test = false
	double_sided = true
	render_priority = profile.render_priority
	if profile.alpha_mode == "alpha-cut":
		alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	elif profile.alpha_mode == "transparent":
		alpha_cut = SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS
	else:
		alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
	set_meta("alpha_mode", profile.alpha_mode)
	set_meta("depth_behavior", profile.depth_behavior)
	set_meta("render_priority", profile.render_priority)
	return true
