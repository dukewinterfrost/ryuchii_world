class_name CravingBubble
extends Button

var food_id := ""
var food_texture: Texture2D
var status_kind := ""
var reduced_motion := false
var phase := 0.0

func set_status(kind: String, food: String = "") -> void:
	set_food(food if kind == "food" else "")
	if status_kind != kind:
		status_kind = kind
		phase = 0.0
		queue_redraw()
	if kind != "food":
		tooltip_text = {"sleepy": "Sleepy · open rest controls", "sleeping": "Sleeping · open rest controls", "tired": "Tired from training · rest before overtraining", "sick": "Sick · a full sleep helps recovery", "play": "Wants to play · tap for extra happiness and bond", "train": "Wants to train · choose a stat for a small bonus"}.get(kind, "")

func _process(delta: float) -> void:
	if not visible or status_kind not in ["play", "train", "sleepy", "sleeping"]: return
	phase = 0.0 if reduced_motion else fmod(phase + delta, 20.0)
	queue_redraw()

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
	elif status_kind in ["sleepy", "sleeping"]:
		for i: int in 3:
			draw_string(ThemeDB.fallback_font, Vector2(10 + i * 17, 44 - i * 9 - roundf(sin(phase * 3 + i) * 2)), "Z", HORIZONTAL_ALIGNMENT_LEFT, -1, 15 + i * 3, Color("536da5"))
	elif status_kind == "play":
		var lift := roundf(absf(sin(phase * 4)) * 19)
		draw_line(Vector2(15, 49), Vector2(53, 49), Color("c4c9b1"), 3)
		draw_circle(Vector2(34, 36 - lift), 12, Color("29394b"))
		draw_circle(Vector2(34, 36 - lift), 9, Color("f09361"))
		draw_line(Vector2(26, 36 - lift), Vector2(42, 36 - lift), Color("ffcf73"), 4)
	elif status_kind == "train":
		var punch := 10.0 if sin(phase * 7) > 0 else 0.0
		var ink := Color("374c69")
		draw_circle(Vector2(28, 14), 6, ink)
		for limb: Array in [[Vector2(28, 22), Vector2(30, 35)], [Vector2(30, 35), Vector2(20, 48)], [Vector2(30, 35), Vector2(42, 47)], [Vector2(28, 25), Vector2(16, 31)], [Vector2(28, 25), Vector2(40 + punch, 22)]]:
			draw_line(limb[0], limb[1], ink, 4)
		draw_rect(Rect2(37 + punch, 18, 8, 8), Color("d65f50"))
	elif status_kind in ["tired", "sick"]:
		var sick := status_kind == "sick"
		draw_style_box(_box(Color("334e6b"), 12), Rect2(13, 9, 42, 40))
		draw_style_box(_box(Color("a5c37d") if sick else Color("88bce2"), 9), Rect2(16, 12, 36, 34))
		draw_line(Vector2(21, 26), Vector2(28, 26), Color("334e6b"), 3)
		draw_line(Vector2(39, 26), Vector2(46, 26), Color("334e6b"), 3)
		draw_rect(Rect2(30, 34, 8, 5), Color("334e6b"))
		if sick:
			draw_line(Vector2(38, 39), Vector2(52, 35), Color("fff7db"), 4)
		else:
			draw_circle(Vector2(49, 32), 3, Color("327bbe"))
	if has_focus():
		draw_rect(Rect2(1, 1, 66, 58), Color("e8b94d"), false, 2)

func _box(color: Color, radius: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(radius)
	return box
