class_name WorldVFXProfile
extends Resource

@export_enum("opaque", "alpha-cut", "transparent") var alpha_mode := "transparent"
@export_enum("write", "prepass") var depth_behavior := "prepass"
@export_range(-16, 16, 1) var render_priority := 0
@export var pixel_size := 1.0 / 32.0
@export var plane_tilt_degrees := 0.0


func is_valid() -> bool:
	return pixel_size > 0.0 and is_finite(pixel_size) \
		and EnvironmentPresentationContract.valid_alpha_depth(alpha_mode, depth_behavior) \
		and EnvironmentPresentationContract.valid_render_priority(render_priority, alpha_mode == "transparent")


static func from_definition(definition: Dictionary) -> WorldVFXProfile:
	var profile := WorldVFXProfile.new()
	profile.alpha_mode = String(definition.get("alphaMode", ""))
	profile.depth_behavior = String(definition.get("depthBehavior", ""))
	profile.render_priority = int(definition.get("renderPriority", 0))
	profile.pixel_size = float(definition.get("pixelSize", 1.0 / 32.0))
	profile.plane_tilt_degrees = 0.0
	return profile
