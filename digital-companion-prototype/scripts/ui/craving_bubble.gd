class_name CravingBubble
extends Button

var food_id := ""
var food_texture: Texture2D

func _ready() -> void:
	custom_minimum_size = Vector2(68, 78)
	size = custom_minimum_size
	flat = true
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

func set_food(value: String) -> void:
	if food_id == value:
		return
	food_id = value
	food_texture = FoodRules.icon(value)
	tooltip_text = "Craving %s · choose a snack" % FoodRules.label(value)
	queue_redraw()

func _draw() -> void:
	var outline := Color("263d2e")
	var cream := Color("fff7db")
	draw_style_box(_box(outline, 12), Rect2(0, 0, 68, 60))
	draw_style_box(_box(cream, 9), Rect2(3, 3, 62, 54))
	draw_circle(Vector2(28, 65), 5, outline)
	draw_circle(Vector2(28, 65), 3, cream)
	draw_circle(Vector2(35, 75), 3, cream)
	if food_texture != null:
		draw_texture_rect(food_texture, Rect2(10, 6, 48, 48), false)
	if has_focus():
		draw_rect(Rect2(1, 1, 66, 58), Color("e8b94d"), false, 2)

func _box(color: Color, radius: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(radius)
	return box
