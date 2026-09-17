class_name TimeOfDayController
extends Node
## Presentation clock only. Never writes simulation time or a save.
signal lighting_changed(sample: Dictionary)

const HOURS := [0.0, 5.0, 6.0, 8.0, 12.0, 16.0, 18.0, 20.0, 24.0]
const TINTS := [Color("9fafe0"), Color("9fafe0"), Color("d4aaae"), Color.WHITE, Color.WHITE, Color("fff2de"), Color("e8a585"), Color("9fafe0"), Color("9fafe0")]
const SKY_TOP := [Color("111c42"), Color("111c42"), Color("766d9f"), Color("269ac4"), Color("208dbd"), Color("3a91b4"), Color("795d94"), Color("111c42"), Color("111c42")]
const SKY_HORIZON := [Color("526894"), Color("526894"), Color("f4ba91"), Color("b9e2dc"), Color("b4e1db"), Color("e2d5ab"), Color("f0ad73"), Color("526894"), Color("526894")]
const STARS := [1.0, 1.0, 0.2, 0.0, 0.0, 0.0, 0.15, 1.0, 1.0]

# Injectable for deterministic clock/resume tests. Returns local decimal hours.
var clock_source: Callable = local_hour
var displayed_hour := 12.0
var target_hour := 12.0
var preview_hour := -1.0
var _poll_elapsed := 0.0
var _publish_elapsed := 0.0


static func local_hour() -> float:
	var now := Time.get_time_dict_from_system()
	return float(now.hour) + float(now.minute) / 60.0 + float(now.second) / 3600.0


static func sample_time(hour: float) -> Dictionary:
	var h := wrapf(hour if is_finite(hour) else 12.0, 0.0, 24.0)
	var index := 0
	while index < HOURS.size() - 2 and h >= HOURS[index + 1]:
		index += 1
	var blend := smoothstep(HOURS[index], HOURS[index + 1], h)
	var sun_progress := clampf((h - 6.0) / 12.0, 0.0, 1.0)
	var moon_progress := wrapf(h - 18.0, 0.0, 24.0) / 12.0
	var sun_height := sin(sun_progress * PI)
	var moon_height := sin(clampf(moon_progress, 0.0, 1.0) * PI)
	return {
		"hour": h,
		"scenery_tint": TINTS[index].lerp(TINTS[index + 1], blend),
		"sky_top": SKY_TOP[index].lerp(SKY_TOP[index + 1], blend),
		"sky_horizon": SKY_HORIZON[index].lerp(SKY_HORIZON[index + 1], blend),
		"star_visibility": lerpf(STARS[index], STARS[index + 1], blend),
		"sun_position": Vector2(lerpf(0.12, 0.88, sun_progress), 0.78 - sun_height * 0.55),
		"moon_position": Vector2(lerpf(0.12, 0.88, clampf(moon_progress, 0.0, 1.0)), 0.78 - moon_height * 0.55),
		"sun_visibility": smoothstep(0.0, 0.12, sun_height),
		"moon_visibility": smoothstep(0.0, 0.12, moon_height) if moon_progress <= 1.0 else 0.0,
	}


func _ready() -> void:
	resync_clock(true)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_IN and is_node_ready():
		resync_clock()


func resync_clock(immediate := false) -> void:
	var value: float = clock_source.call()
	target_hour = wrapf(value if is_finite(value) else 12.0, 0.0, 24.0)
	_poll_elapsed = 0.0
	if immediate and preview_hour < 0.0:
		displayed_hour = target_hour
		publish()


func set_preview_hour(hour: float) -> void:
	if not is_finite(hour):
		return
	preview_hour = wrapf(hour, 0.0, 24.0)
	displayed_hour = preview_hour
	publish()


func use_local_time() -> void:
	preview_hour = -1.0
	resync_clock()


func _process(delta: float) -> void:
	advance_clock(delta)


func advance_clock(delta: float) -> void:
	if not is_finite(delta) or delta <= 0.0:
		return
	_poll_elapsed += delta
	if _poll_elapsed >= 5.0:
		resync_clock()
	else:
		target_hour = wrapf(target_hour + delta / 3600.0, 0.0, 24.0)
	if preview_hour >= 0.0:
		return
	# Shortest path across midnight; cap delta to avoid a snap after suspension.
	var difference := wrapf(target_hour - displayed_hour + 12.0, 0.0, 24.0) - 12.0
	displayed_hour = wrapf(displayed_hour + difference * (1.0 - exp(-minf(delta, 0.25) * 2.0)), 0.0, 24.0)
	_publish_elapsed += delta
	if _publish_elapsed >= 0.1:
		_publish_elapsed = 0.0
		publish()


func publish() -> void:
	lighting_changed.emit(sample_time(displayed_hour))
