class_name DayNightPreview
extends PanelContainer
## Debug-only overlay. Hiding it preserves the override; reset restores local time.
var environment_view: EnvironmentView3D
var slider := HSlider.new()
var time_label := Label.new()
var _last_clock: TimeOfDayController


func _ready() -> void:
	position = Vector2(12, 132)
	custom_minimum_size = Vector2(280, 0)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var style := StyleBoxFlat.new()
	style.bg_color = Color("26362bf2")
	style.set_corner_radius_all(8)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	add_child(box)
	time_label.add_theme_color_override("font_color", Color("f7f3df"))
	box.add_child(time_label)
	slider.min_value = 0.0
	slider.max_value = 24.0
	slider.step = 1.0 / 60.0
	slider.custom_minimum_size = Vector2(256, 28)
	slider.tooltip_text = "Preview any hour; 24:00 wraps to midnight"
	box.add_child(slider)
	slider.value_changed.connect(func(hour: float) -> void:
		var clock := _clock()
		if clock != null:
			clock.set_preview_hour(hour)
	)
	var row := HBoxContainer.new()
	box.add_child(row)
	var reset := Button.new()
	reset.text = "Use local time"
	reset.custom_minimum_size.y = 36
	reset.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reset.pressed.connect(func() -> void:
		var clock := _clock()
		if clock != null:
			clock.use_local_time()
	)
	row.add_child(reset)
	var close := Button.new()
	close.text = "Hide"
	close.custom_minimum_size.y = 36
	close.pressed.connect(hide)
	row.add_child(close)
	hide()


func toggle() -> void:
	if _clock() != null:
		_watch_clock(_clock())
		visible = not visible


func _watch_clock(clock: TimeOfDayController) -> void:
	if clock != _last_clock:
		_last_clock = clock
		clock.tree_exiting.connect(hide, CONNECT_ONE_SHOT)


func _clock() -> TimeOfDayController:
	if is_instance_valid(environment_view) and is_instance_valid(environment_view.day_night):
		return environment_view.day_night.clock
	return null


func _process(_delta: float) -> void:
	var clock := _clock()
	if clock == null:
		hide()
		_last_clock = null
		return
	if clock != _last_clock:
		hide()
		_watch_clock(clock)
	if not visible:
		return
	var minutes := int(floor(clock.displayed_hour * 60.0)) % 1440
	time_label.text = "%s · %02d:%02d" % ["Preview" if clock.preview_hour >= 0.0 else "Local time", minutes / 60, minutes % 60]
	if not slider.has_focus():
		slider.set_value_no_signal(clock.displayed_hour)
