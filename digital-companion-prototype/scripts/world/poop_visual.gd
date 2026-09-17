class_name PoopVisual
extends Area2D

signal selected(index: int)

var poop_index := 0
var _phase := 0.0


func _ready() -> void:
	input_pickable = true
	var collision := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = 24.0
	collision.shape = shape
	add_child(collision)
	input_event.connect(_on_input_event)
	queue_redraw()


func _process(delta: float) -> void:
	_phase = fmod(_phase + delta * 2.2, TAU)
	queue_redraw()


func _draw() -> void:
	var shadow := Color("553820")
	var brown := Color("704927")
	var light := Color("9b6a39")
	draw_ellipse(Vector2(0, 10), 24.0, 9.0, Color(0.12, 0.13, 0.08, 0.24))
	draw_circle(Vector2(0, 4), 17.0, shadow)
	draw_circle(Vector2(-7, 1), 11.0, brown)
	draw_circle(Vector2(7, 1), 11.0, brown)
	draw_circle(Vector2(0, -8), 10.0, brown)
	draw_circle(Vector2(0, -17), 6.0, light)
	for line_index in 3:
		var points := PackedVector2Array()
		for point_index in 7:
			var y := -30.0 - point_index * 4.0
			var wave := sin(_phase + float(point_index) * 0.9 + float(line_index)) * 3.0
			points.append(Vector2(-12.0 + line_index * 12.0 + wave, y))
		draw_polyline(points, Color(0.28, 0.39, 0.24, 0.42), 2.2, true)
func _on_input_event(_viewport: Node, event: InputEvent, _shape_index: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		selected.emit(poop_index)
	elif event is InputEventScreenTouch and event.pressed:
		selected.emit(poop_index)
