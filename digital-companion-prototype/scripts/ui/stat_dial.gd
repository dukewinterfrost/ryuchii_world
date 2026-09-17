class_name StatDial
extends Control

var value := 0.0:
	set(next_value):
		value = clampf(next_value, 0.0, 100.0)
		if is_instance_valid(value_label):
			value_label.text = "%d" % roundi(value)
		queue_redraw()
var accent := Color("75c576")
var title_label := Label.new()
var value_label := Label.new()


func _ready() -> void:
	custom_minimum_size = Vector2(104, 118)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.position = Vector2(0, 83)
	title_label.size = Vector2(104, 26)
	title_label.add_theme_font_size_override("font_size", 13)
	add_child(title_label)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	value_label.position = Vector2(0, 21)
	value_label.size = Vector2(104, 44)
	value_label.add_theme_font_size_override("font_size", 22)
	add_child(value_label)
	value_label.text = "%d" % roundi(value)


func setup(title: String, next_value: float, next_accent: Color) -> void:
	title_label.text = title
	accent = next_accent
	value = next_value


func _draw() -> void:
	var center := Vector2(52, 47)
	var start := -PI * 0.75
	var end := PI * 0.75
	draw_arc(center, 35.0, start, end, 42, Color(1, 1, 1, 0.14), 8.0, true)
	draw_arc(center, 35.0, start, lerpf(start, end, value / 100.0), 42, accent, 8.0, true)
