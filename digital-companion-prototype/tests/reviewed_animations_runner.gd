extends SceneTree

const EXPECTED := {
	"botamon": {"idle": [5, 1000], "move": [4, 440], "happy": [11, 990], "eat": [14, 1260]},
	"koromon": {"idle": [5, 1000], "move": [5, 550], "happy": [14, 1260], "eat": [14, 1260]},
	"agumon": {"idle": [5, 1000], "move": [9, 990], "happy": [12, 1080], "eat": [14, 1260], "basic_attack": [12, 720], "special_attack": [18, 1260], "guard": [5, 900], "evade": [10, 600], "hit": [9, 720], "defeat": [9, 1080]},
}
var failures := 0

func _initialize() -> void:
	for species: String in EXPECTED:
		var library := CompanionAssetLibrary.build(species)
		check(not library.is_empty(), species + " loads")
		if library.is_empty():
			continue
		check(library.revision == "2026-09-15.001", species + " uses integrated revision")
		var policy := CompanionAnimationState.new()
		policy.configure_library(library)
		for action: String in EXPECTED[species]:
			var expected: Array = EXPECTED[species][action]
			var clip := policy.resolve_animation(action, "e")
			check(clip == action and policy.visual_fallback.is_empty(), species + " " + action + " resolves dedicated clip")
			check(library.frames.get_frame_count(clip) == expected[0], "actual frame count preserved")
			var duration := 0.0
			for index: int in library.frames.get_frame_count(clip):
				duration += library.frames.get_frame_duration(clip, index) / library.frames.get_animation_speed(clip) * 1000.0
				check(policy.frame_pivot(clip, index) == Vector2(0.5, 0.9375), "fixed ground registration")
			check(is_equal_approx(duration, float(expected[1])), "authored duration preserved")
			policy.resolve_animation(action, "w")
			check(policy.flip_h, "west-facing sprite mirrors right-facing source")
			var is_loop := action in ["idle", "move", "guard"]
			policy.begin_action(action)
			check(policy.action_locked != is_loop, "only one-shots lock care actions")
			var start := policy.sample_combat(action, "e", 0.0, 30.0)
			var end := policy.sample_combat(action, "e", 30.0, 30.0)
			check(start.frame == 0, "battle action starts at first frame")
			if not is_loop:
				check(end.frame == expected[0] - 1, "battle action reaches terminal frame")
		check(policy.resolve_animation("celebrate", "e") == "happy.default", "celebration uses new happy art")
		if species != "agumon":
			check(not library.manifest.clips.has("basic_attack.default"), "infants have no authored combat")
	if failures == 0:
		print("PASS: 18 reviewed animations, 175 frames, timing, care locks and battle sampling")
	quit(1 if failures else 0)

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error("FAIL: " + message)
