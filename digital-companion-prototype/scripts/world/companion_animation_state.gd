class_name CompanionAnimationState
extends RefCounted

## Presentation-agnostic companion animation policy. Both the 2D and 3D
## adapters delegate clip resolution, action locks, authored pivots, and
## deterministic combat timeline sampling to this object.

const FACINGS := ["n", "ne", "e", "se", "s", "sw", "w", "nw"]
const ANGLE_FACINGS := ["e", "se", "s", "sw", "w", "nw", "n", "ne"]
const SPECIAL_ACTIONS := ["special_attack", "pepper_breath", "pepper-breath"]

var frames: SpriteFrames
var pivots: Dictionary = {}
var manifest: Dictionary = {}
var clip_facings: Dictionary = {}
var legacy_facing := "right"
var facing := "e"
var requested_action := ""
var resolved_animation := ""
var visual_fallback := ""
var flip_h := false
var battle_rendering := false
var action_locked := false
var active_action := ""


func configure_library(loaded: Dictionary) -> bool:
	if loaded.is_empty() or not loaded.get("frames") is SpriteFrames:
		return false
	frames = loaded.frames
	pivots = (loaded.get("pivots", {}) as Dictionary).duplicate(true)
	manifest = (loaded.get("manifest", {}) as Dictionary).duplicate(true)
	clip_facings = (loaded.get("clip_facings", {}) as Dictionary).duplicate(true)
	legacy_facing = String(loaded.get("legacy_facing", "right"))
	facing = normalized_facing(facing)
	return true


func set_facing_from_motion(direction: Vector2) -> String:
	if direction.length_squared() > 0.0001:
		facing = ANGLE_FACINGS[posmod(roundi(direction.angle() / (PI / 4.0)), 8)]
	return facing


func begin_loop(action: String) -> String:
	if frames == null:
		return ""
	battle_rendering = false
	requested_action = action
	resolved_animation = resolve_animation(action, facing)
	action_locked = false
	active_action = ""
	return resolved_animation


func begin_action(action: String) -> String:
	if frames == null:
		return ""
	battle_rendering = false
	requested_action = action
	resolved_animation = resolve_animation(action, facing)
	if resolved_animation.is_empty():
		action_locked = false
		active_action = ""
		return ""
	action_locked = frames.get_animation_loop_mode(resolved_animation) == SpriteFrames.LOOP_NONE
	# A looping visual fallback is useful, but can never own a one-shot lock.
	active_action = action if action_locked else ""
	return resolved_animation


func complete_action() -> String:
	if battle_rendering:
		return ""
	var completed := active_action
	action_locked = false
	active_action = ""
	begin_loop("idle")
	return completed


func sample_combat(action: String, requested_facing: String, action_tick: float, action_duration: float) -> Dictionary:
	if frames == null:
		return {}
	battle_rendering = true
	action_locked = false
	active_action = ""
	facing = normalized_facing(requested_facing)
	requested_action = action
	resolved_animation = resolve_animation(action, facing)
	if resolved_animation.is_empty():
		return {}
	var count := frames.get_frame_count(resolved_animation)
	var fps := frames.get_animation_speed(resolved_animation)
	if count <= 0 or fps <= 0.0:
		return {}
	var total := 0.0
	for index: int in count:
		total += frames.get_frame_duration(resolved_animation, index) / fps
	if total <= 0.0:
		return {}
	var sample_seconds := 0.0
	if frames.get_animation_loop_mode(resolved_animation) != SpriteFrames.LOOP_NONE:
		# Loop sampling never depends on a simulator bookkeeping duration. This is
		# the parity rule shared by Canvas and world-space presentations.
		sample_seconds = fmod(maxf(0.0, action_tick) / 30.0, total)
	elif action_duration > 0.0:
		sample_seconds = clampf(action_tick / action_duration, 0.0, 0.999999) * total
	else:
		sample_seconds = minf(maxf(0.0, action_tick) / 30.0, total - 0.000001)
	var elapsed := 0.0
	for index: int in count:
		var duration := frames.get_frame_duration(resolved_animation, index) / fps
		if sample_seconds < elapsed + duration or index == count - 1:
			return {
				"animation": resolved_animation,
				"frame": index,
				"progress": clampf((sample_seconds - elapsed) / duration, 0.0, 1.0),
				"flipH": flip_h,
			}
		elapsed += duration
	return {}


func resolve_animation(action: String, requested_facing: String) -> String:
	visual_fallback = ""
	flip_h = false
	requested_facing = normalized_facing(requested_facing)
	var bases: Array[String] = [action]
	if action in SPECIAL_ACTIONS:
		bases.assign(SPECIAL_ACTIONS)
	for base: String in bases:
		for candidate: String in [base + "." + requested_facing, base, base + ".default"]:
			if frames.has_animation(candidate):
				_apply_legacy_mirroring(candidate, requested_facing)
				return candidate
	var fallbacks: Dictionary = manifest.get("fallbacks", {})
	for base: String in bases:
		for request: String in [base + "." + requested_facing, base]:
			if fallbacks.has(request) and frames.has_animation(String(fallbacks[request])):
				var approved := String(fallbacks[request])
				visual_fallback = "Authored fallback: %s -> %s" % [request, approved]
				_apply_legacy_mirroring(approved, requested_facing)
				return approved
	var legacy_candidates: Array[String]
	if action in SPECIAL_ACTIONS:
		legacy_candidates.assign(["idle", "idle.default", "idle." + requested_facing])
	else:
		legacy_candidates.assign([action, action + ".default", "idle", "idle.default", "idle." + requested_facing])
	for candidate: String in legacy_candidates:
		if not frames.has_animation(candidate):
			continue
		if action in SPECIAL_ACTIONS:
			visual_fallback = "Limitation: world-space Pepper Breath VFX only; the promoted Agumon set has no dedicated attack body animation"
		else:
			visual_fallback = "Legacy/fallback art: %s.%s -> %s (not eight-direction coverage)" % [action, requested_facing, candidate]
		_apply_legacy_mirroring(candidate, requested_facing)
		return candidate
	visual_fallback = "No art for %s.%s" % [action, requested_facing]
	return ""


func frame_pivot(animation_name: String, frame_index: int) -> Variant:
	if not pivots.has(animation_name):
		return null
	var animation_pivots: Array = pivots[animation_name]
	if frame_index < 0 or frame_index >= animation_pivots.size():
		return null
	return animation_pivots[frame_index]


func normalized_facing(value: String) -> String:
	var normalized := value.to_lower()
	return normalized if normalized in FACINGS else "e"


func _apply_legacy_mirroring(animation_name: String, requested_facing: String) -> void:
	if animation_name.ends_with("." + requested_facing):
		return
	var source_facing := String(clip_facings.get(animation_name, legacy_facing))
	if source_facing not in ["right", "left"]:
		return
	var looks_left := requested_facing in ["nw", "w", "sw"]
	flip_h = looks_left if source_facing == "right" else not looks_left
