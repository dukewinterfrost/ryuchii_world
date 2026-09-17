class_name EnvironmentPresentationContract
extends RefCounted

## Runtime mirror of the environment v1 compiler contract. Keeping these
## constants in one place prevents permissive direct-manifest loading from
## drifting away from catalog/export validation.

const PROFILE_ID := "sprite-in-3d-portrait-v1"
const PROFILE_VERSION := 1
const PIXELS_PER_METER := 32
const FOV_DEGREES := 28.0
const PITCH_DEGREES := 50.0
const SPRITE_TILT_DEGREES := 8.0
const KEEP_ASPECT := "width"
const TARGET_SIZES := [Vector2i(360, 640), Vector2i(390, 844), Vector2i(430, 932)]
const RENDER_PRIORITY_MIN := -16
const RENDER_PRIORITY_MAX := 16
const MAX_TERRAIN_CHUNKS := 64
const MAX_SPRITE_PLANES := 512
const MAX_PLANE_STACKS := 256
const MAX_AMBIENT_PLANES := 64
const MAX_ACTIVE_NODES := 4096
const MAX_ACTIVE_TEXTURES := 640
const MAX_HABITAT_PLACEMENTS := 512
const MAX_ARENA_PLACEMENTS := 256


static func validate_profile(manifest: Dictionary) -> bool:
	var profile: Variant = manifest.get("presentationProfile")
	if not profile is Dictionary:
		return false
	var expected := {
		"id": PROFILE_ID,
		"version": PROFILE_VERSION,
		"pixelsPerMeter": PIXELS_PER_METER,
		"fovDegrees": FOV_DEGREES,
		"pitchDegrees": PITCH_DEGREES,
		"spriteTiltDegrees": SPRITE_TILT_DEGREES,
		"keepAspect": KEEP_ASPECT,
	}
	if profile.size() != expected.size():
		return false
	for field: String in expected:
		if not profile.has(field):
			return false
		if expected[field] is float:
			if not _finite(profile[field]) or not is_equal_approx(float(profile[field]), float(expected[field])):
				return false
		elif profile[field] != expected[field]:
			return false
	var camera: Variant = manifest.get("camera")
	var world_scale: Variant = manifest.get("worldScale")
	return camera is Dictionary and world_scale is Dictionary \
		and world_scale.get("pixelsPerUnit") == PIXELS_PER_METER \
		and is_equal_approx(float(camera.get("fovDegrees", -1)), FOV_DEGREES) \
		and is_equal_approx(float(camera.get("pitchDegrees", -1)), PITCH_DEGREES) \
		and is_equal_approx(float(camera.get("spriteTiltDegrees", -1)), SPRITE_TILT_DEGREES) \
		and camera.get("keepAspect") == KEEP_ASPECT


static func valid_alpha_depth(alpha_mode: String, depth_behavior: String) -> bool:
	return (alpha_mode in ["opaque", "alpha-cut"] and depth_behavior == "write") \
		or (alpha_mode == "transparent" and depth_behavior == "prepass")


static func valid_render_priority(value: Variant, required: bool) -> bool:
	if value == null:
		return not required
	# JSON numbers decode as floats in Godot; preserve the integer schema by
	# accepting only finite, mathematically integral numeric values.
	if not _finite(value) or not is_equal_approx(float(value), roundf(float(value))):
		return false
	if not required:
		return int(value) == 0
	return int(value) >= RENDER_PRIORITY_MIN and int(value) <= RENDER_PRIORITY_MAX


static func priority_for(definition: Dictionary) -> int:
	return int(definition.get("renderPriority", 0))


static func valid_pin(value: Variant) -> bool:
	if not value is Dictionary or value.size() != 3:
		return false
	for field: String in ["assetId", "revision", "contentSha256"]:
		if not value.has(field) or not value[field] is String or String(value[field]).is_empty():
			return false
	return String(value.contentSha256).begins_with("sha256:") and String(value.contentSha256).length() == 71


static func _finite(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))
