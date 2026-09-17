class_name CompanionEffects
extends Node2D

## Presentation only. Attach under the ground root, separate from creature pixels.
## sample_effect is for authoritative battle/review time; play_effect is for care.
## No gameplay signals, damage, status conditions, sprite changes, or root motion.
## Drawing follows CanvasItem._draw/queue_redraw:
## https://docs.godotengine.org/en/stable/tutorials/2d/custom_drawing_in_2d.html
const EFFECTS: Array[String] = ["feed", "pet", "sickness", "basic_attack", "special_attack", "hit_general", "hit_fire", "hit_poison", "hit_freeze", "knocked_down", "stun"]
const LABELS: Array[String] = ["Feeding plus + happy face", "Petting hearts", "Sickness indicator", "Basic melee", "Species special", "General hit", "Fire hit", "Poison hit", "Freeze hit", "Knockdown", "Stun"]

var reduced_motion := false
var effect_id := ""
var progress := 0.0
var _seconds := 1.2
var _elapsed := 0.0
var _automatic := false


func _ready() -> void:
	z_index = 5
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	set_process(false)


func play_effect(id: String, seconds: float = 1.2) -> void:
	if id not in EFFECTS:
		clear_effect()
		return
	effect_id = id
	_seconds = maxf(seconds, 0.05)
	_elapsed = 0.0
	progress = 0.0
	_automatic = true
	set_process(true)
	queue_redraw()


func sample_effect(id: String, fraction: float) -> void:
	_automatic = false
	set_process(false)
	effect_id = id if id in EFFECTS else ""
	progress = clampf(fraction, 0.0, 1.0)
	queue_redraw()


func clear_effect() -> void:
	effect_id = ""
	_automatic = false
	set_process(false)
	queue_redraw()


func _process(delta: float) -> void:
	if not _automatic:
		return
	_elapsed += maxf(delta, 0.0)
	progress = minf(_elapsed / _seconds, 1.0)
	if progress >= 1.0:
		clear_effect()
	else:
		queue_redraw()


func _draw() -> void:
	if effect_id.is_empty():
		return
	var t := 0.35 if reduced_motion else progress
	var fade := 1.0 if reduced_motion else clampf((1.0 - progress) * 3.0, 0.0, 1.0)
	var lift := 0.0 if reduced_motion else -20.0 * t
	var cream := Color(1.0, 0.93, 0.68, fade)
	var mint := Color(0.42, 1.0, 0.65, fade)
	match effect_id:
		"feed":
			_plus(Vector2(33, -67 + lift), 7, mint)
			var face := Vector2(-26, -83 + lift)
			draw_circle(face, 12, cream)
			draw_circle(face + Vector2(-4, -3), 1.5, Color("193c36"))
			draw_circle(face + Vector2(4, -3), 1.5, Color("193c36"))
			draw_arc(face + Vector2(0, 1), 5, 0.15, PI - 0.15, 9, Color("193c36"), 2)
		"pet":
			for index: int in 3:
				_heart(Vector2(-30 + index * 29, -78 + lift - (12 if index == 1 else 0)), 7, Color(1.0, 0.39, 0.58, fade))
		"sickness":
			for index: int in 3:
				var center := Vector2(-26 + index * 26, -68 + lift * 0.3)
				draw_circle(center, 5 + index % 2 * 2, Color(0.61, 0.75, 0.23, fade * 0.7))
				draw_circle(center + Vector2(1, -2), 1.5, cream)
		"basic_attack":
			for index: int in 3:
				draw_line(Vector2(15 + index * 7, -66), Vector2(35 + index * 7, -39), cream, 3)
		"special_attack":
			var center := Vector2(28 + 38 * t, -52)
			draw_circle(center, 10 + 4 * sin(t * PI), Color(1.0, 0.43, 0.13, fade))
			draw_circle(center + Vector2(3, 0), 5, cream)
			draw_line(center - Vector2(19, 0), center - Vector2(8, 0), cream, 3)
		"hit_general":
			_burst(Vector2(0, -50), 18 + 7 * t, cream)
		"hit_fire":
			for index: int in 3:
				var point := Vector2(-19 + index * 19, -8)
				var height := 31 + 7 * sin(t * TAU + index)
				draw_colored_polygon(PackedVector2Array([point + Vector2(-9, 0), point + Vector2(-6, -height * 0.5), point + Vector2(2, -height), point + Vector2(11, 0)]), Color(1.0, 0.32, 0.08, fade * 0.8))
		"hit_poison":
			for index: int in 4:
				draw_circle(Vector2(-25 + index * 16, -22 + lift - index % 2 * 21), 6, Color(0.72, 0.37, 0.85, fade * 0.85))
		"hit_freeze":
			var ice := Color(0.4, 0.85, 1.0, fade)
			for index: int in 3:
				var center := Vector2(-23 + index * 23, -45 - index % 2 * 28)
				for axis: int in 3:
					var ray := Vector2(9, 0).rotated(axis * PI / 3)
					draw_line(center - ray, center + ray, ice, 2)
		"knocked_down":
			# Dust and falling chevrons stand in for future authored grounded poses.
			for index: int in 4:
				draw_circle(Vector2(-31 + index * 21, -3 - 5 * sin(t * PI)), 5, Color(0.82, 0.75, 0.56, fade * 0.7))
			var y := -87 + 10 * t
			draw_polyline(PackedVector2Array([Vector2(-8, y), Vector2(0, y + 7), Vector2(8, y)]), cream, 3)
		"stun":
			for index: int in 3:
				var angle := index * TAU / 3 + (0.0 if reduced_motion else t * TAU)
				_plus(Vector2(cos(angle) * 29, -86 + sin(angle) * 7), 4, cream)


func _plus(center: Vector2, radius: float, color: Color) -> void:
	draw_line(center - Vector2(radius, 0), center + Vector2(radius, 0), color, 3)
	draw_line(center - Vector2(0, radius), center + Vector2(0, radius), color, 3)


func _heart(center: Vector2, radius: float, color: Color) -> void:
	draw_circle(center + Vector2(-radius * 0.4, -radius * 0.3), radius * 0.65, color)
	draw_circle(center + Vector2(radius * 0.4, -radius * 0.3), radius * 0.65, color)
	draw_colored_polygon(PackedVector2Array([center + Vector2(-radius, -radius * 0.2), center + Vector2(radius, -radius * 0.2), center + Vector2(0, radius)]), color)


func _burst(center: Vector2, radius: float, color: Color) -> void:
	for index: int in 8:
		var direction := Vector2.RIGHT.rotated(index * TAU / 8)
		draw_line(center + direction * radius * 0.4, center + direction * radius, color, 3)
