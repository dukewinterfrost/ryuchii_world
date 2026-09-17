extends SceneTree

## Native GPU evidence capture for one exact environment candidate and target.
## This writes images and measurements only. It never creates approval receipts,
## promotes assets, or changes the runtime catalog.

const VIEWPOINTS := ["center", "left", "right", "near", "far"]
const SHIMMER_FRACTIONS := [0.0, 0.25, 0.5, 0.75, 1.0]
const BENCHMARK_FRAMES := 180
const WARMUP_FRAMES := 30


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var values := _arguments(OS.get_cmdline_user_args())
	for required: String in ["environment-fixture", "output", "size", "environment-content-sha256", "reviewer-build-sha256", "region-id"]:
		if not values.has(required):
			printerr("Missing --" + required)
			quit(1)
			return
	var fixture := String(values["environment-fixture"]).trim_suffix("/")
	var output := String(values["output"]).trim_suffix("/")
	var target := _parse_size(String(values["size"]))
	if not fixture.is_absolute_path() or not output.is_absolute_path() or target.x < 1 or target.y < 1:
		printerr("Fixture/output must be absolute and size must be WIDTHxHEIGHT")
		quit(1)
		return
	root.content_scale_size = target
	root.size = target
	var view := EnvironmentView3D.new()
	view.size = target
	root.add_child(view)
	await process_frame
	if not view.configure_from_folder(fixture) or not view.build_review_samples():
		printerr("Environment fixture is not renderable: " + view._last_load_error)
		quit(1)
		return
	var center := _movement_center(view.environment_manifest)
	var behind := CompanionPresentation3D.new()
	behind.name = "BehindLandmarkActor"
	view.attach_world_node(behind)
	if not behind.configure("agumon"):
		printerr("Agumon review actor is unavailable")
		quit(1)
		return
	behind.set_ground_position(center + Vector2(0, -112))
	behind.play_loop("idle")
	var front := CompanionPresentation3D.new()
	front.name = "FrontLandmarkActor"
	view.attach_world_node(front)
	front.configure("agumon")
	front.set_ground_position(center + Vector2(0, 112))
	front.play_loop("idle")
	var opaque_effect := _review_effect("OpaqueReviewVFX", true)
	var translucent_effect := _review_effect("TranslucentReviewVFX", false)
	behind.add_child(opaque_effect)
	front.add_child(translucent_effect)
	DirAccess.make_dir_recursive_absolute(output)
	var viewpoint_records := {}
	for viewpoint: String in VIEWPOINTS:
		if not view.set_review_viewpoint(viewpoint):
			_fail("Missing review viewpoint: " + viewpoint)
			return
		await _settle()
		var actor_bounds := {
			"behind": _project_actor_bounds(view, behind),
			"front": _project_actor_bounds(view, front),
		}
		if not actor_bounds.behind.fullyVisible or not actor_bounds.front.fullyVisible:
			_fail("Sprite-aware actor framing failed at " + viewpoint)
			return
		var filename := viewpoint + ".png"
		if not _capture(output.path_join(filename)):
			_fail("Could not capture viewpoint: " + viewpoint)
			return
		viewpoint_records[viewpoint] = {"file": filename, "actorBounds": actor_bounds}
	var shimmer_records := {}
	var ground_units_per_pixel := (2.0 * 12.0 * tan(deg_to_rad(14.0)) * 32.0) / float(target.x)
	for fraction: float in SHIMMER_FRACTIONS:
		view.set_camera_focus(center + Vector2(ground_units_per_pixel * fraction, 0), true)
		await _settle()
		var key := "%03d" % roundi(fraction * 100.0)
		var filename := "shimmer-" + key + ".png"
		if not _capture(output.path_join(filename)):
			_fail("Could not capture shimmer fraction: " + key)
			return
		shimmer_records[key] = {"fractionPx": fraction, "file": filename}
	view.set_review_viewpoint("center")
	for _index: int in WARMUP_FRAMES:
		await process_frame
	var frame_ms: Array[float] = []
	var draw_calls: Array[int] = []
	var textures_in_frame: Array[int] = []
	for _index: int in BENCHMARK_FRAMES:
		var started := Time.get_ticks_usec()
		await process_frame
		frame_ms.append(float(Time.get_ticks_usec() - started) / 1000.0)
		draw_calls.append(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
		textures_in_frame.append(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED))
	var report := {
		"schemaVersion": 1,
		"kind": "environment-native-capture-run",
		"regionId": String(values["region-id"]),
		"environmentContentSha256": String(values["environment-content-sha256"]),
		"reviewerBuildSha256": String(values["reviewer-build-sha256"]),
		"targetSize": [target.x, target.y],
		"presentationProfile": view.environment_manifest.presentationProfile,
		"displayServer": DisplayServer.get_name(),
		"videoAdapter": RenderingServer.get_video_adapter_name(),
		"samples": {
			"behindActor": behind.name, "frontActor": front.name,
			"opaqueVfx": opaque_effect.name, "translucentVfx": translucent_effect.name,
		},
		"viewpoints": viewpoint_records,
		"shimmerSweep": shimmer_records,
		"performance": {
			"sampleFrames": BENCHMARK_FRAMES,
			"averageFrameMs": _average_float(frame_ms),
			"maximumFrameMs": _maximum_float(frame_ms),
			"averageDrawCalls": _average_int(draw_calls),
			"maximumDrawCalls": _maximum_int(draw_calls),
			"maximumTextureMemoryBytes": _maximum_int(textures_in_frame),
			"environmentInstrumentation": view.instrumentation(),
		},
	}
	var report_path := output.path_join("capture-run.json")
	var file := FileAccess.open(report_path, FileAccess.WRITE)
	if file == null:
		_fail("Could not write capture report")
		return
	file.store_string(JSON.stringify(report, "\t") + "\n")
	file.close()
	view.free()
	print("REGION_CAPTURE_OK:" + report_path)
	quit(0)


func _arguments(args: PackedStringArray) -> Dictionary:
	var values := {}
	var index := 0
	while index < args.size():
		var argument := String(args[index])
		if argument.begins_with("--") and index + 1 < args.size():
			values[argument.trim_prefix("--")] = String(args[index + 1])
			index += 2
		else:
			index += 1
	return values


func _parse_size(value: String) -> Vector2i:
	var pieces := value.to_lower().split("x")
	return Vector2i(int(pieces[0]), int(pieces[1])) if pieces.size() == 2 else Vector2i.ZERO


func _movement_center(manifest: Dictionary) -> Vector2:
	var bounds: Array = manifest.camera.movementBounds
	return Vector2(float(bounds[0]) + float(bounds[2]) * 0.5,
		float(bounds[1]) + float(bounds[3]) * 0.5)


func _settle() -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw


func _capture(path: String) -> bool:
	var image := root.get_texture().get_image()
	return image != null and not image.is_empty() and image.save_png(path) == OK


func _project_actor_bounds(view: EnvironmentView3D, actor: CompanionPresentation3D) -> Dictionary:
	var points: Array[Vector3] = []
	for x: float in [-2.0, 2.0]:
		for y: float in [0.0, 4.35]:
			points.append(actor.global_position + Vector3(x, y, 0))
	var minimum := Vector2(INF, INF)
	var maximum := Vector2(-INF, -INF)
	for point: Vector3 in points:
		if view.camera.is_position_behind(point):
			return {"fullyVisible": false, "reason": "behind-camera"}
		var screen := view.camera.unproject_position(point)
		minimum = minimum.min(screen)
		maximum = maximum.max(screen)
	var viewport := Vector2(view.world_viewport.size)
	var margin := 2.0
	return {
		"minimum": [minimum.x, minimum.y], "maximum": [maximum.x, maximum.y],
		"fullyVisible": minimum.x >= margin and minimum.y >= margin and
			maximum.x <= viewport.x - margin and maximum.y <= viewport.y - margin,
	}


func _review_effect(effect_name: String, opaque: bool) -> WorldVFX3D:
	var effect := WorldVFX3D.new()
	effect.name = effect_name
	var image := Image.create(24, 24, false, Image.FORMAT_RGBA8)
	if opaque:
		image.fill(Color(1.0, 0.83, 0.12, 1.0))
	else:
		image.fill(Color(0, 0, 0, 0))
		for y: int in 24:
			for x: int in 24:
				var radius := Vector2(float(x) - 11.5, float(y) - 11.5).length()
				if radius <= 10.5:
					image.set_pixel(x, y, Color(1.0, 0.38, 0.08, 0.62))
	var configured := effect.configure(ImageTexture.create_from_image(image), {
		"alphaMode": "opaque" if opaque else "transparent",
		"depthBehavior": "write" if opaque else "prepass",
		"renderPriority": 0 if opaque else 3,
		"pixelSize": 0.055,
	})
	if not configured:
		printerr("Could not configure review VFX: " + effect_name)
	effect.position = Vector3(0.7, 2.0, 0.08)
	return effect


func _average_float(values: Array[float]) -> float:
	var total := 0.0
	for value: float in values:
		total += value
	return total / float(values.size()) if not values.is_empty() else 0.0


func _maximum_float(values: Array[float]) -> float:
	var result := 0.0
	for value: float in values:
		result = maxf(result, value)
	return result


func _average_int(values: Array[int]) -> float:
	var total := 0
	for value: int in values:
		total += value
	return float(total) / float(values.size()) if not values.is_empty() else 0.0


func _maximum_int(values: Array[int]) -> int:
	var result := 0
	for value: int in values:
		result = maxi(result, value)
	return result


func _fail(message: String) -> void:
	printerr(message)
	quit(1)
