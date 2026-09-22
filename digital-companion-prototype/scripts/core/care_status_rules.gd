class_name CareStatusRules
extends RefCounted

static var TIRED: float = GameBalance.setting("care_status_rules.TIRED")
static var SLEEPY: float = GameBalance.setting("care_status_rules.SLEEPY")
static var SLEEP_SECONDS: float = GameBalance.setting("care_status_rules.SLEEP_SECONDS")
static var SICK_CHANCE: int = GameBalance.setting("care_status_rules.SICK_CHANCE")

static func initial() -> Dictionary:
	return {"sleeping": false, "sleep_remaining": 0.0, "sleep_reward": false,
		"sleep_need": 0.0, "sick": false, "wish": "", "wish_expires_at": 0.0,
		"wish_wait": float(GameBalance.setting("care.wish_initial_wait")), "wish_sequence": 0, "risk_sequence": 0}

static func wish(state: Dictionary, now: float = -1.0) -> String:
	var s: Dictionary = state.care.status
	var clock := float(state.meta.last_update_time) if now < 0 else now
	if s.sleeping or s.sick or float(state.care.fatigue) >= TIRED or float(s.sleep_need) >= SLEEPY or float(s.wish_expires_at) <= clock:
		return ""
	return String(s.wish)

static func bubble(state: Dictionary) -> String:
	var s: Dictionary = state.care.status
	if s.sleeping: return "sleeping"
	if s.sick: return "sick"
	if float(state.care.fatigue) >= TIRED: return "tired"
	if float(s.sleep_need) >= SLEEPY: return "sleepy"
	if not FoodRules.active(state).is_empty(): return "food"
	return wish(state)

static func clear_wish(s: Dictionary) -> void:
	s.wish = ""
	s.wish_expires_at = 0.0

static func advance(state: Dictionary, elapsed: float, engaged: float, training: bool) -> void:
	var s: Dictionary = state.care.status
	var now := float(state.meta.last_update_time)
	if s.sleeping:
		var resting := minf(elapsed, float(s.sleep_remaining))
		state.care.fatigue = maxf(0, float(state.care.fatigue) - resting * float(GameBalance.setting("care.sleep_fatigue_recovery")))
		s.sleep_need = maxf(0, float(s.sleep_need) - resting)
		s.sleep_remaining = maxf(0, float(s.sleep_remaining) - elapsed)
		if is_zero_approx(float(s.sleep_remaining)):
			s.sleeping = false
			s.sick = false
			s.sleep_need = 0.0
			if s.sleep_reward: state.care.discipline = minf(100, float(state.care.discipline) + int(GameBalance.setting("care.sleep_discipline_gain")))
			s.sleep_reward = false
		return
	s.sleep_need = minf(100, float(s.sleep_need) + maxf(0, engaged) / float(GameBalance.setting("care.sleep_need_seconds_per_point")))
	if not String(s.wish).is_empty():
		if now >= float(s.wish_expires_at) or s.sick or float(state.care.fatigue) >= TIRED or float(s.sleep_need) >= SLEEPY:
			clear_wish(s)
		return
	if training or engaged <= 0 or s.sick or float(state.care.fatigue) >= TIRED or float(s.sleep_need) >= SLEEPY or not FoodRules.active(state).is_empty():
		return
	s.wish_wait = maxf(0, float(s.wish_wait) - engaged)
	if float(s.wish_wait) > 0: return
	var seq := int(s.wish_sequence)
	s.wish = "play" if seq % 2 == 0 else "train"
	s.wish_sequence = mini(1000000000, seq + 1)
	s.wish_expires_at = now + float(GameBalance.setting("care.wish_duration"))
	s.wish_wait = float(GameBalance.setting("care.wish_wait_base")) + float((seq * 73 + 41) % (int(GameBalance.setting("care.wish_wait_jitter")) + 1))

static func sleep_command(state: Dictionary, wake: bool) -> Dictionary:
	var next := state.duplicate(true)
	var s: Dictionary = next.care.status
	if bool(s.sleeping) == not wake:
		return {"state": next, "accepted": false, "rewarded": false, "bond_gain": 0.0, "animation": "idle", "message": "Already sleeping." if not wake else "Already awake."}
	s.sleeping = not wake
	s.sleep_remaining = 0.0 if wake else SLEEP_SECONDS
	s.sleep_reward = not wake and (float(next.care.fatigue) >= 20 or float(s.sleep_need) >= SLEEPY or s.sick)
	clear_wish(s)
	next.care.food.craving = ""
	next.care.food.expires_at = 0.0
	return {"state": next, "accepted": true, "rewarded": false, "bond_gain": 0.0, "animation": "idle", "message": "Awake again. Early waking gives no discipline bonus or sickness recovery." if wake else "Time for a %.0f-second nap. Zzz…" % SLEEP_SECONDS}

static func training_context(state: Dictionary, now: float) -> Dictionary:
	return {"wish_bonus": wish(state, now) == "train", "tired": float(state.care.fatigue) >= TIRED}

static func training_effects(state: Dictionary, context: Dictionary) -> bool:
	var s: Dictionary = state.care.status
	if bool(context.get("wish_bonus", false)): clear_wish(s)
	if not bool(context.get("tired", false)): return false
	# A save-owned sequence makes retrying the same completion produce the same
	# result. Cancellation/relaunch never awards training or rerolls a completion.
	var key := "%s:%s:%d" % [state.identity.companion_name, state.meta.birth_time, int(s.risk_sequence)]
	var roll := key.sha256_text().substr(0, 7).hex_to_int() % 100
	s.risk_sequence = mini(1000000000, int(s.risk_sequence) + 1)
	if roll < SICK_CHANCE:
		s.sick = true
		clear_wish(s)
	return bool(s.sick)

static func valid(value: Variant) -> bool:
	if not value is Dictionary or value.size() != initial().size() or not value.has_all(initial().keys()): return false
	for key: String in ["sleeping", "sleep_reward", "sick"]:
		if not value[key] is bool: return false
	if not value.wish is String or value.wish not in ["", "play", "train"]: return false
	for key: String in ["sleep_remaining", "sleep_need", "wish_expires_at", "wish_wait", "wish_sequence", "risk_sequence"]:
		if not (value[key] is float or value[key] is int) or not is_finite(float(value[key])) or float(value[key]) < 0: return false
	if float(value.sleep_remaining) > 3600.0 or float(value.sleep_need) > 100 or float(value.wish_wait) > 420 or float(value.wish_expires_at) > 253402300799.0: return false
	for key: String in ["wish_sequence", "risk_sequence"]:
		if float(value[key]) != floorf(float(value[key])) or float(value[key]) > 1000000000: return false
	if bool(value.sleeping) != (float(value.sleep_remaining) > 0) or (value.sleep_reward and not value.sleeping): return false
	return (value.wish.is_empty() and float(value.wish_expires_at) == 0) or (not value.wish.is_empty() and float(value.wish_expires_at) > 0)
