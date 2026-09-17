extends Node

const FIXTURE := "res://tests/fixtures/environments/green-shade-3d-spike/environment.json"

var _checks := 0
var _failures := 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var view := EnvironmentView3D.new()
	view.size = Vector2(390, 844)
	add_child(view)
	await get_tree().process_frame
	_check(view.load_environment(FIXTURE), "compiled Environment fixture passes the shared runtime contract")
	if view.environment_manifest.is_empty():
		_finish()
		return
	var stack_id := String(view.environment_manifest.planeStacks[0].id)
	_check(view.set_static_placements([{"id": "runtime-probe", "planeStack": stack_id, "cell": [20, 24], "rotationQuarterTurns": 0}], "habitat"), "runtime placement loads within bounded node limits")

	_test_shared_animation_state(view)
	await _test_camera_modes(view)
	_test_dogleg(view)
	_test_world_vfx()
	_test_load_bounds(view)
	await _test_environment_library()

	var stats := view.instrumentation()
	_check(stats.has("nodes") and stats.has("textures") and stats.has("drawCallEstimate"), "instrumentation exposes node, texture, and draw-call estimates")
	_check(stats.has("averageFrameMs") and stats.has("maximumFrameMs") and stats.frameSamples > 0, "instrumentation exposes sampled frame-time evidence")
	_check(stats.withinRuntimeBounds, "runtime evidence confirms the active package stays inside resource bounds")
	view.queue_free()
	await get_tree().process_frame
	_finish()


func _test_shared_animation_state(view: EnvironmentView3D) -> void:
	var library := _synthetic_animation_library()
	var avatar := CompanionAvatar.new()
	add_child(avatar)
	avatar.configure_library(library)
	var presentation := CompanionPresentation3D.new()
	view.attach_world_node(presentation)
	_check(presentation.configure_library(library), "3D adapter accepts the same synthetic animation library as 2D")
	for tick: float in [0.0, 3.0, 6.0, 11.0, 18.0, 29.0]:
		avatar.render_combat("idle", "E", tick, 30.0)
		presentation.render_combat("idle", "E", tick, 30.0)
		_check(avatar.sprite.frame == presentation.sprite.frame and is_equal_approx(avatar.sprite.frame_progress, presentation.sprite.frame_progress), "2D/3D loop sampling parity holds at tick %.1f" % tick)
	avatar.render_combat("idle", "E", 6.0, 30.0)
	var first_frame := avatar.sprite.frame
	var first_progress := avatar.sprite.frame_progress
	avatar.render_combat("idle", "E", 18.0, 30.0)
	_check(avatar.sprite.frame == first_frame and is_equal_approx(avatar.sprite.frame_progress, first_progress), "positive simulator duration never clamps a looping 2D clip")
	_check(avatar.animation_state is CompanionAnimationState and presentation.animation_state is CompanionAnimationState, "both adapters delegate to the shared animation-state component")
	avatar.queue_free()
	presentation.queue_free()


func _test_camera_modes(view: EnvironmentView3D) -> void:
	var target_bounds := Rect2(448, 576, 384, 320)
	for target: Vector2i in EnvironmentPresentationContract.TARGET_SIZES:
		view.size = target
		await get_tree().process_frame
		_check(view.frame_ground_bounds(target_bounds, Vector2(64, 96), true), "battle framing calculates a fixed-axis dolly at %dx%d" % [target.x, target.y])
		_check(view.camera_mode() == EnvironmentView3D.CAMERA_MODE_BATTLE_FRAME, "battle frame mode is explicit")
		_check(_bounds_on_screen(view, target_bounds), "combined fighter ground bounds remain on-screen at %dx%d" % [target.x, target.y])
		_check(is_equal_approx(view.camera.rotation_degrees.x, -50.0) and is_zero_approx(view.camera.rotation_degrees.y), "battle framing keeps fixed pitch and zero yaw")
	view.size = Vector2(390, 844)
	await get_tree().process_frame
	var directions: Array[Vector3] = []
	for viewpoint: String in ["center", "left", "right", "near", "far"]:
		_check(view.set_review_viewpoint(viewpoint), "canonical review viewpoint exists: " + viewpoint)
		directions.append(view.camera_forward_direction())
	for direction: Vector3 in directions:
		_check(direction.is_equal_approx(directions[0]), "review translation/dolly never changes the camera axis")
	view.set_review_viewpoint("center")
	var center_position := view.camera.position
	var center_focus := view._camera_focus_ground
	view.set_review_viewpoint("left")
	_check(is_equal_approx(view.camera.position.x - center_position.x, (view._camera_focus_ground.x - center_focus.x) / 32.0), "left review translates camera and target together")
	view.clear_review_viewpoint()
	view.set_home_follow(Vector2(640, 768), true)
	_check(view.camera_mode() == EnvironmentView3D.CAMERA_MODE_HOME_FOLLOW, "home follow mode tracks a ground target")
	view.set_home_manual_pan(Vector2(64, 0), true)
	_check(view.camera_mode() == EnvironmentView3D.CAMERA_MODE_HOME_MANUAL, "manual home pan is a distinct non-orbiting camera mode")


func _test_dogleg(view: EnvironmentView3D) -> void:
	var route := view.build_depth_traversal_route(36.0)
	_check(route.size() >= 4, "reviewer builds a dogleg route around transformed stack footprints")
	_check(view.route_segments_are_clear(route), "every dogleg traversal segment is clear of authoritative footprints")
	var footprint := view.placed_footprints()[0]
	_check(route[0].y < footprint.position.y and route[-1].y > footprint.end.y, "dogleg includes both behind and front depth positions")
	var evidence := view.acceptance_evidence(route)
	_check(evidence.alphaProfiles.opaque > 0 and evidence.alphaProfiles["alpha-cut"] > 0 and evidence.alphaProfiles.transparent > 0, "acceptance evidence covers opaque, alpha-cut, and translucent depth profiles")
	_check(evidence.traversalSegmentsClear and evidence.fixedPitch and evidence.fixedYaw and evidence.performance.withinRuntimeBounds, "acceptance evidence binds traversal, fixed camera, and performance checks")


func _test_world_vfx() -> void:
	var texture := _test_texture(Color(1, 0.4, 0.1, 0.8))
	var transparent := WorldVFX3D.new()
	_check(transparent.configure(texture, {"alphaMode": "transparent", "depthBehavior": "prepass", "renderPriority": 7, "pixelSize": 0.04}), "world-space VFX accepts explicit translucent prepass profile")
	_check(transparent.alpha_cut == SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS and transparent.render_priority == 7, "VFX adapter applies prepass and authored render priority")
	var cutout := WorldVFX3D.new()
	_check(cutout.configure(texture, {"alphaMode": "alpha-cut", "depthBehavior": "write", "pixelSize": 0.04}), "world-space VFX accepts opaque/alpha-cut depth-write profile")
	_check(cutout.alpha_cut == SpriteBase3D.ALPHA_CUT_DISCARD and cutout.render_priority == 0, "alpha-cut VFX uses depth write and default priority")
	var opaque := WorldVFX3D.new()
	_check(opaque.configure(texture, {"alphaMode": "opaque", "depthBehavior": "write", "pixelSize": 0.04}), "world-space VFX supports the opaque depth-write profile")
	_check(opaque.alpha_cut == SpriteBase3D.ALPHA_CUT_DISABLED and opaque.render_priority == 0, "opaque VFX retains normal depth writing")
	var invalid := WorldVFX3D.new()
	_check(not invalid.configure(texture, {"alphaMode": "transparent", "depthBehavior": "prepass", "renderPriority": 17, "pixelSize": 0.04}), "world-space VFX rejects out-of-contract render priority")
	transparent.free()
	cutout.free()
	opaque.free()
	invalid.free()


func _test_load_bounds(active_view: EnvironmentView3D) -> void:
	var bad := active_view.environment_manifest.duplicate(true)
	bad.ambientPlanes = []
	for index: int in EnvironmentPresentationContract.MAX_AMBIENT_PLANES + 1:
		bad.ambientPlanes.append({})
	var probe := EnvironmentView3D.new()
	probe.size = Vector2(390, 844)
	add_child(probe)
	_check(not probe.configure(bad, "res://", active_view._textures), "direct runtime loading rejects manifests above bounded counts")
	_check(probe.environment_manifest.is_empty() and probe.instrumentation().nodes <= 5, "failed package load leaves no partially decoded environment active")
	probe.free()


func _test_environment_library() -> void:
	var root := "/tmp/digital-companion-environment-library-runtime-test"
	var first := _write_test_package(root, "environment-library-a", "r1", "1")
	var second := _write_test_package(root, "environment-library-b", "r2", "2")
	_check(not first.is_empty() and not second.is_empty(), "test packages for EnvironmentAssetLibrary are writable")
	if first.is_empty() or second.is_empty():
		return
	var catalog := {"schemaVersion": 1, "assets": {
		first.pin.assetId: {"kind": "environment", "assetId": first.pin.assetId, "revision": first.pin.revision, "contentSha256": first.pin.contentSha256, "path": first.relative},
		second.pin.assetId: {"kind": "environment", "assetId": second.pin.assetId, "revision": second.pin.revision, "contentSha256": second.pin.contentSha256, "path": second.relative},
	}}
	var bad_pin: Dictionary = first.pin.duplicate(true)
	bad_pin.revision = "mismatch"
	_check(EnvironmentAssetLibrary.activate_pin_from_catalog(bad_pin, catalog, root).is_empty(), "EnvironmentAssetLibrary rejects a source pin mismatch")
	_check(EnvironmentAssetLibrary.active_package().is_empty(), "failed pin resolution cannot retain a previous active package")
	bad_pin = first.pin.duplicate(true)
	bad_pin.contentSha256 = "sha256:" + "0".repeat(64)
	_check(EnvironmentAssetLibrary.activate_pin_from_catalog(bad_pin, catalog, root).is_empty(), "EnvironmentAssetLibrary rejects mismatched package content identity")
	_check(not EnvironmentAssetLibrary.activate_pin_from_catalog(first.pin, catalog, root).is_empty(), "full Environment pin resolves from the catalog")
	_check(EnvironmentAssetLibrary.active_pin() == first.pin, "active package exposes its complete immutable pin")
	_check(not EnvironmentAssetLibrary.activate_pin_from_catalog(second.pin, catalog, root).is_empty(), "a second verified Environment package can be activated")
	_check(EnvironmentAssetLibrary.active_pin() == second.pin and EnvironmentAssetLibrary.active_package().manifest.assetId == second.pin.assetId, "activating a region unloads the prior package and exposes only one active package")
	EnvironmentAssetLibrary.clear_active()


func _write_test_package(root: String, asset_id: String, revision: String, digit: String) -> Dictionary:
	var relative := asset_id + "/" + revision
	var folder := root.path_join(relative)
	if DirAccess.make_dir_recursive_absolute(folder.path_join("textures")) != OK:
		return {}
	var fixture := AssetResourceLibrary.read_json(FIXTURE).duplicate(true)
	fixture.assetId = asset_id
	fixture.revision = revision
	var bindings: Dictionary = fixture.textures
	var files := {}
	for role: String in bindings:
		var source_path := FIXTURE.get_base_dir().path_join(String(bindings[role]))
		var target_path := folder.path_join(String(bindings[role]))
		var bytes := FileAccess.get_file_as_bytes(source_path)
		var stream := FileAccess.open(target_path, FileAccess.WRITE)
		if stream == null:
			return {}
		stream.store_buffer(bytes)
		stream.close()
		files[String(bindings[role])] = "sha256:" + FileAccess.get_sha256(target_path)
	var manifest_path := folder.path_join("environment.json")
	var manifest_stream := FileAccess.open(manifest_path, FileAccess.WRITE)
	if manifest_stream == null:
		return {}
	manifest_stream.store_string(JSON.stringify(fixture, "", true))
	manifest_stream.close()
	files["environment.json"] = "sha256:" + FileAccess.get_sha256(manifest_path)
	var identity := {
		"assetId": asset_id,
		"revision": revision,
		"kind": "environment",
		"compilerVersion": "runtime-fixture-v1",
		"planSha256": "sha256:" + digit.repeat(64),
		"buildIdentity": "sha256:" + digit.repeat(64),
	}
	var dependencies := {}
	for relative_path: Variant in bindings.values():
		dependencies[String(relative_path)] = files[String(relative_path)]
	var native := Resource.new()
	native.set_meta("candidate_identity", identity)
	native.set_meta("environment_manifest", fixture)
	native.set_meta("environment_texture_paths", bindings)
	native.set_meta("environment_texture_hashes", dependencies)
	var native_path := folder.path_join("environment.tres")
	if ResourceSaver.save(native, native_path) != OK:
		return {}
	files["environment.tres"] = "sha256:" + FileAccess.get_sha256(native_path)
	var metadata := {"schemaVersion": 1, "kind": "environment", "assetId": asset_id,
		"revision": revision, "compilerVersion": identity.compilerVersion,
		"planSha256": identity.planSha256, "buildIdentity": identity.buildIdentity,
		"nativeResources": true, "nativeDependencies": dependencies, "files": files, "nonce": digit}
	var content_sha := EnvironmentAssetLibrary.metadata_content_sha256(metadata)
	var pin := {"assetId": asset_id, "revision": revision, "contentSha256": content_sha}
	metadata["contentSha256"] = content_sha
	var metadata_stream := FileAccess.open(folder.path_join("candidate.json"), FileAccess.WRITE)
	if metadata_stream == null:
		return {}
	metadata_stream.store_string(JSON.stringify(metadata, "", true))
	metadata_stream.close()
	return {"pin": pin, "relative": relative}


func _bounds_on_screen(view: EnvironmentView3D, bounds: Rect2) -> bool:
	for point: Vector2 in [bounds.position, Vector2(bounds.end.x, bounds.position.y), bounds.end, Vector2(bounds.position.x, bounds.end.y)]:
		var world := EnvironmentView3D.ground_to_world(point)
		if view.camera.is_position_behind(world):
			return false
		var screen := view.camera.unproject_position(world)
		if screen.x < -0.5 or screen.y < -0.5 or screen.x > view.world_viewport.size.x + 0.5 or screen.y > view.world_viewport.size.y + 0.5:
			return false
	return true


func _synthetic_animation_library() -> Dictionary:
	var frames := SpriteFrames.new()
	frames.add_animation("idle")
	frames.set_animation_loop("idle", true)
	frames.set_animation_speed("idle", 1.0)
	frames.add_frame("idle", _test_texture(Color("5fbd68")), 0.1)
	frames.add_frame("idle", _test_texture(Color("357a43")), 0.3)
	return {
		"frames": frames,
		"manifest": {"subjectId": "parity-probe", "fallbacks": {}},
		"pivots": {"idle": [Vector2(0.5, 1.0), Vector2(0.5, 1.0)]},
		"clip_facings": {},
		"legacy_facing": "right",
	}


func _test_texture(color: Color) -> Texture2D:
	var image := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	image.fill(color)
	return ImageTexture.create_from_image(image)


func _finish() -> void:
	print("%s: %d environment runtime architecture checks" % ["PASS" if _failures == 0 else "FAIL", _checks])
	get_tree().quit(0 if _failures == 0 else 1)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("FAIL: " + message)
