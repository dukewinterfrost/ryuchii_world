class_name BattleChargeOverlay
extends Node2D

## Pixel-sized cast indicators anchored above projected approved sprite bounds.
## Rendering inside the 3D SubViewport keeps readable text independent of dolly.
var indicators: Array[Dictionary] = []

func sample(session: Dictionary, presentations: Dictionary, camera: Camera3D, viewport_size: Vector2, safe_rect: Rect2 = Rect2()) -> void:
	indicators.clear()
	var safe := safe_rect if safe_rect.has_area() else Rect2(Vector2.ZERO, viewport_size)
	for id: String in presentations:
		var actor: Dictionary = session.get("actors", {}).get(id, {})
		if String(actor.get("phase", "")) != "charge":
			continue
		var presentation: CompanionPresentation3D = presentations[id]
		var ground := BattlePresentationCues.ground(actor.get("pos", [0, 0]))
		var top := viewport_size.y
		var center := camera.unproject_position(EnvironmentView3D.ground_to_world(ground)).x
		for corner: Vector3 in presentation.visual_world_corners(ground, false):
			top = minf(top, camera.unproject_position(corner).y)
		var width := 108.0
		var rect := Rect2(clampf(center - width / 2, safe.position.x + 4, maxf(safe.position.x + 4, safe.end.x - width - 4)), clampf(top - 38, safe.position.y + 4, maxf(safe.position.y + 4, safe.end.y - 33)), width, 29)
		var anchor_y := rect.position.y
		for existing: Dictionary in indicators:
			if not rect.intersects(existing.rect):
				continue
			# Prefer a small sideways adjustment before stacking. Moving downward
			# would put the warning over the creature whose attack it explains.
			var best := rect
			var best_distance := INF
			var occupied: Rect2 = existing.rect
			for candidate_x: float in [occupied.position.x - width - 4, occupied.end.x + 4]:
				var candidate := Rect2(Vector2(candidate_x, anchor_y), rect.size)
				if not safe.grow(-4).encloses(candidate):
					continue
				var clear := true
				for other: Dictionary in indicators:
					if candidate.intersects(other.rect):
						clear = false
						break
				var distance := absf(candidate_x - rect.position.x)
				if clear and distance < best_distance:
					best = candidate
					best_distance = distance
			if best_distance < INF:
				rect = best
			else:
				rect.position.y = maxf(safe.position.y + 4, occupied.position.y - 32)
		indicators.append({"rect": rect, "anchor_y": anchor_y, "text": String(actor.get("current_move", {}).get("name", "Charging")), "progress": BattlePresentationCues.charge_fraction(actor)})
	queue_redraw()

func _draw() -> void:
	for indicator: Dictionary in indicators:
		var rect: Rect2 = indicator.rect
		draw_rect(rect, Color(0.04, 0.10, 0.08, 0.95))
		draw_rect(rect, Color("efdba4"), false, 1.0)
		draw_string(ThemeDB.fallback_font, rect.position + Vector2(5, 14), String(indicator.text), HORIZONTAL_ALIGNMENT_CENTER, rect.size.x - 10, 12, Color("fff5db"))
		var bar := Rect2(rect.position + Vector2(5, 19), Vector2(rect.size.x - 10, 6))
		draw_rect(bar, Color("526250"))
		bar.size.x *= float(indicator.progress)
		draw_rect(bar, Color("ffc85d"))
