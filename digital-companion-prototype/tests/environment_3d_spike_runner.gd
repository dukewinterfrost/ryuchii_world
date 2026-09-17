extends Node

const Sim = preload("res://scripts/battle/battle_simulator.gd")

var _checks := 0
var _failures := 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	await get_tree().process_frame
	var scene_resource := load("res://scenes/green_shade_3d_spike.tscn") as PackedScene
	_check(scene_resource != null, "Green Shade 3D spike scene loads")
	if scene_resource == null:
		_finish()
		return
	var spike := scene_resource.instantiate() as GreenShade3DSpike
	spike.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	get_tree().root.add_child(spike)
	await get_tree().process_frame
	await get_tree().process_frame
	spike.set_process(false)
	spike.environment.set_process(false)

	var environment := spike.environment
	_check(environment is SubViewportContainer and environment.world_viewport != null, "shared EnvironmentView3D owns a SubViewport")
	_check(String(environment.environment_manifest.get("assetId", "")) == "environment-green-shade-3d-spike", "spike renderer is configured from the Green Shade environment manifest")
	_check(String(environment.environment_manifest.get("revision", "")) == "2026-09-12.003" and String(environment.environment_manifest.get("provenance", {}).get("kind", "")) == "source-derived", "spike loads the checked-in compiled source-derived fixture, not mutable source-plan data")
	_check(environment.environment_manifest.get("textures", {}).has("ground"), "manifest binds the extracted Green Shade ground instead of the old habitat backdrop")
	_check(not environment.environment_manifest.terrainChunks.is_empty(), "walkable Green Shade floor uses an explicitly subdivided terrain crop")
	for chunk: Dictionary in environment.environment_manifest.terrainChunks:
		var binding := String(chunk.textureBinding)
		_check(binding.begins_with("terrain.green-shade-ground") and environment._textures.has(binding), "%s resolves its deterministically cropped terrain texture binding" % chunk.id)
		_check(environment._textures[binding].get_size() == Vector2(float(chunk.sourceRegionPx[2]), float(chunk.sourceRegionPx[3])), "%s uses the compiled ground crop without sampling the vertical cliff as floor" % chunk.id)
	_check(environment.world_viewport.own_world_3d, "spike viewport owns an isolated 3D world")
	_check(environment.camera != null and environment.camera.projection == Camera3D.PROJECTION_PERSPECTIVE, "spike uses a perspective Camera3D")
	_check(is_equal_approx(environment.camera.fov, 28.0) and environment.camera.keep_aspect == Camera3D.KEEP_WIDTH, "camera uses 28 degree FOV and KEEP_WIDTH")
	_check(is_equal_approx(environment.camera.rotation_degrees.x, -50.0), "camera keeps the authored 50 degree downward pitch")
	_check(EnvironmentView3D.ground_to_world(Vector2(64, 96)).is_equal_approx(Vector3(2, 0, 3)), "ground coordinates map onto XZ at 32 units per cell")
	_check(EnvironmentView3D.world_to_ground(Vector3(2, 7, 3)).is_equal_approx(Vector2(64, 96)), "XZ coordinates map back without using visual height")
	_check(environment.rendered_planes.size() == 3, "Green Shade tree is split into three depth planes")
	var roles: Array = environment.rendered_planes.map(func(plane: Sprite3D) -> String: return String(plane.get_meta("plane_role", "")))
	_check(roles == ["facade", "interior", "canopy"], "tree plane roles preserve facade/interior/canopy ordering")
	var tree_hashes: Dictionary = environment.environment_manifest.provenance.sourceHashes
	_check(tree_hashes.tree_facade != tree_hashes.tree_interior and tree_hashes.tree_interior != tree_hashes.tree_canopy and tree_hashes.tree_facade != tree_hashes.tree_canopy, "tree layers are separately derived image payloads instead of overlapping opaque row bands")
	for index: int in environment.rendered_planes.size():
		var plane: Sprite3D = environment.rendered_planes[index]
		_check(plane.billboard == BaseMaterial3D.BILLBOARD_ENABLED and not plane.fixed_size, "%s is camera-aligned with perspective scale" % plane.name)
		_check(plane.alpha_cut == SpriteBase3D.ALPHA_CUT_DISCARD and not plane.no_depth_test and not plane.shaded, "%s uses alpha-cut, unshaded, depth-tested rendering" % plane.name)
		_check(is_zero_approx(plane.rotation_degrees.x), "%s supersedes the old eight-degree tilt" % plane.name)
		_check(_texture_has_transparent_perimeter(plane.texture), "%s has a transparent padded perimeter with no rectangular crop edge" % plane.name)
	var footprint_center := Vector2((20.0 + 0.5) * 32.0, (24.0 + 0.5) * 32.0)
	var footprint_value: Array = environment.environment_manifest.groundFootprints[0].rect
	var footprint := Rect2(footprint_center + Vector2(float(footprint_value[0]), float(footprint_value[1])), Vector2(float(footprint_value[2]), float(footprint_value[3])))
	var route_clear := true
	for index: int in GreenShade3DSpike.MOVE_ROUTE.size():
		route_clear = route_clear and not _segment_hits_rect(GreenShade3DSpike.MOVE_ROUTE[index], GreenShade3DSpike.MOVE_ROUTE[(index + 1) % GreenShade3DSpike.MOVE_ROUTE.size()], footprint)
	_check(route_clear, "front/behind demonstration route goes around the authored tree footprint instead of through its root")
	_check(GreenShade3DSpike.MOVE_ROUTE[0].y < footprint.position.y and GreenShade3DSpike.MOVE_ROUTE[1].y > footprint.end.y, "demonstration route includes explicit behind and front depth positions")
	var stack_id := String(environment.environment_manifest.planeStacks[0].id)
	var placement_count := environment._placement_root.get_child_count()
	_check(not environment.set_static_placements([{"id": "invalid-turn", "planeStack": stack_id, "cell": [20, 24], "rotationQuarterTurns": 1}], "habitat"), "environment v1 rejects habitat stack rotation before exposing a card edge")
	_check(environment._placement_root.get_child_count() == placement_count, "rejected v1 rotation preserves the existing valid placement set")
	_check(not environment.set_static_placements([{"id": "invalid-arena-turn", "planeStack": stack_id, "groundPosition": [640, 768], "rotationDegrees": 15}], "arena"), "environment v1 also rejects rotated arena presentation stacks")
	_check(EnvironmentView3D._valid_alpha_depth("alpha-cut", "write") and EnvironmentView3D._valid_alpha_depth("transparent", "prepass"), "renderer accepts the two implemented alpha/depth profiles")
	_check(not EnvironmentView3D._valid_alpha_depth("alpha-cut", "prepass") and not EnvironmentView3D._valid_alpha_depth("transparent", "test-only"), "renderer rejects unsupported alpha/depth combinations instead of silently aliasing them")
	for viewpoint: String in ["center", "left", "right", "near", "far"]:
		_check(environment.set_review_viewpoint(viewpoint), "manifest review viewpoint is renderable: " + viewpoint)
	environment.clear_review_viewpoint()
	_check(environment.screen_to_ground(Vector2(-1, -1)) == null, "screen-to-ground rejects coordinates outside the viewport")

	var companion := spike.companion
	_check(companion != null and companion.sprite is AnimatedSprite3D, "Agumon presentation consumes SpriteFrames through AnimatedSprite3D")
	_check(companion.sprite.sprite_frames != null and companion.sprite.sprite_frames.has_animation("idle"), "existing Agumon SpriteFrames are loaded")
	_check(companion.sprite.texture_filter == BaseMaterial3D.TEXTURE_FILTER_NEAREST, "Agumon uses nearest texture filtering")
	_check(companion.sprite.billboard == BaseMaterial3D.BILLBOARD_ENABLED and not companion.sprite.fixed_size, "Agumon stays camera-aligned in the depth-tested world")
	_check(is_zero_approx(companion.sprite.rotation_degrees.x), "Agumon no longer foreshortens through a fixed plane tilt")
	_check(companion.sprite.alpha_cut == SpriteBase3D.ALPHA_CUT_DISCARD and not companion.sprite.no_depth_test and not companion.sprite.shaded, "Agumon uses alpha-cut, unshaded, depth-tested rendering")
	_check(companion.sprite.offset.y > 0.0, "authored feet pivot is converted into Sprite3D's upward local Y axis")
	_check(companion.shadow != null and companion.shadow.mesh is PlaneMesh, "Agumon has a horizontal contact-shadow quad")

	for action: String in ["idle", "move", "eat", "special_attack", "pepper_breath"]:
		spike.play_demo_action(action)
		_check(companion.requested_action == action and not companion.resolved_animation.is_empty(), "%s resolves to an AnimatedSprite3D clip" % action)
	_check(spike.attack_vfx.visible and spike.attack_vfx is WorldVFX3D and spike.attack_vfx.render_priority == 4, "Pepper Breath preview uses the reusable world-space VFX profile")
	_check(companion.visual_fallback.begins_with("Limitation:") and companion.visual_fallback.contains("no dedicated attack body animation"), "missing promoted attack body art is surfaced as an explicit limitation")
	_check(companion.resolved_animation.begins_with("idle"), "Pepper Breath keeps a neutral body pose rather than relabeling unrelated animation as attack art")
	_check(not companion.is_action_playing(), "looping attack fallback never leaves the action controller locked")
	companion.set_facing_from_motion(Vector2.LEFT)
	spike.advance_demo(0.5)
	_check(spike.attack_vfx.position.x < 0.0 and spike.attack_vfx.flip_h, "world-space Pepper Breath VFX follows the companion's west-facing direction")
	_test_companion_action_contract(environment)

	spike.play_demo_action("move")
	var before := companion.get_ground_position()
	spike.advance_demo(1.0)
	_check(companion.get_ground_position().distance_to(before) > 1.0, "move demo advances Agumon over the XZ ground")
	_check(is_equal_approx(companion.position.y, 0.0), "character gameplay root stays on the ground plane")
	var camera_before := environment.camera.position.x
	spike.pan_camera(Vector2(2, 0))
	environment.advance_camera(1.0)
	_check(not is_equal_approx(environment.camera.position.x, camera_before), "lateral camera translation demonstrates real perspective parallax")
	_test_ambient_parallax(environment)

	for target_size: Vector2i in [Vector2i(360, 640), Vector2i(390, 844), Vector2i(430, 932)]:
		environment.size = target_size
		await get_tree().process_frame
		_check(environment.world_viewport.size == target_size, "SubViewport tracks portrait target %dx%d" % [target_size.x, target_size.y])
	environment.set_camera_focus(Vector2(-10000, 768), true)
	var left_camera_x := environment.camera.position.x
	environment.set_camera_focus(Vector2(10000, 768), true)
	var right_camera_x := environment.camera.position.x
	_check(left_camera_x > 0.0 and left_camera_x <= 20.0, "left camera clamp keeps the visible frustum inside the ground instead of exposing its edge")
	_check(right_camera_x >= 20.0 and right_camera_x < 40.0, "right camera clamp keeps the visible frustum inside the ground instead of exposing its edge")

	await _test_environment_arena_review(environment)
	_test_battle_determinism(environment)
	spike.queue_free()
	await get_tree().process_frame
	_finish()


func _test_companion_action_contract(environment: EnvironmentView3D) -> void:
	var probe := CompanionPresentation3D.new()
	probe.name = "CompanionContractProbe"
	environment.attach_world_node(probe)
	var frames := SpriteFrames.new()
	frames.add_animation("idle")
	frames.set_animation_loop("idle", true)
	frames.set_animation_speed("idle", 1.0)
	frames.add_frame("idle", _test_texture(Color("5fbd68")), 0.1)
	frames.add_frame("idle", _test_texture(Color("357a43")), 0.3)
	frames.add_animation("eat")
	frames.set_animation_loop("eat", false)
	frames.set_animation_speed("eat", 1.0)
	frames.add_frame("eat", _test_texture(Color("ffb43c")), 0.1)
	frames.add_frame("eat", _test_texture(Color("ff7f24")), 0.3)
	var loaded := {
		"frames": frames,
		"manifest": {"subjectId": "contract-probe", "fallbacks": {}},
		"pivots": {
		"idle": [Vector2(0.5, 1.0), Vector2(0.5, 1.0)],
			"eat": [Vector2(0.5, 1.0), Vector2(0.5, 1.0)],
		},
		"clip_facings": {},
		"legacy_facing": "right",
	}
	_check(probe.configure_library(loaded), "3D companion accepts a synthetic behavior-contract SpriteFrames set")
	var completions: Array[String] = []
	probe.action_finished.connect(func(action: String) -> void: completions.append(action))
	probe.play_action("eat")
	_check(probe.is_action_playing(), "one-shot action locks care input while its clip is active")
	probe.sprite.animation_finished.emit()
	_check(completions == ["eat"], "one-shot completion emits the requested action exactly once")
	_check(not probe.is_action_playing() and probe.sprite.animation == "idle" and probe.sprite.is_playing(), "one-shot completion clears the lock and returns to idle")

	probe.play_action("special_attack")
	_check(not probe.is_action_playing(), "a looping neutral fallback cannot lock an unsupported one-shot action")
	_check(probe.visual_fallback.begins_with("Limitation:"), "unsupported attack fallback remains visibly identified as a limitation")

	probe.render_combat("eat", "E", 0.9, 4.0)
	_check(probe.sprite.frame == 0, "deterministic sampling holds the short first authored frame before its boundary")
	probe.render_combat("eat", "E", 1.1, 4.0)
	_check(probe.sprite.frame == 1, "deterministic sampling crosses into the longer second authored frame")
	probe.render_combat("eat", "E", 2.5, 4.0)
	_check(probe.sprite.frame == 1 and is_equal_approx(probe.sprite.frame_progress, 0.5), "combat fitting preserves nonuniform frame timing and within-frame progress")
	probe.render_battle({"action": "eat", "facing": "E", "action_tick": 2, "action_duration": 4}, 0.5)
	_check(probe.sprite.frame == 1 and is_equal_approx(probe.sprite.frame_progress, 0.5), "render_battle samples the same authoritative tick plus interpolation")
	probe.render_combat("idle", "E", 6.0, 30.0)
	_check(probe.sprite.frame == 1 and is_equal_approx(probe.sprite.frame_progress, 1.0 / 3.0), "positive simulator duration does not clamp a looping idle clip to its final frame")
	probe.render_combat("idle", "E", 18.0, 30.0)
	_check(probe.sprite.frame == 1 and is_equal_approx(probe.sprite.frame_progress, 1.0 / 3.0), "loop sampling remains periodic on the authoritative 30 Hz clock")
	probe.queue_free()


func _test_texture(color: Color) -> Texture2D:
	var image := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	image.fill(color)
	return ImageTexture.create_from_image(image)


func _texture_has_transparent_perimeter(texture: Texture2D) -> bool:
	var image := texture.get_image()
	if image == null or image.get_width() < 2 or image.get_height() < 2:
		return false
	for x: int in image.get_width():
		if image.get_pixel(x, 0).a > 0.0 or image.get_pixel(x, image.get_height() - 1).a > 0.0:
			return false
	for y: int in image.get_height():
		if image.get_pixel(0, y).a > 0.0 or image.get_pixel(image.get_width() - 1, y).a > 0.0:
			return false
	return true


func _segment_hits_rect(from: Vector2, to: Vector2, rect: Rect2) -> bool:
	if rect.has_point(from) or rect.has_point(to):
		return true
	var corners := [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]
	for index: int in corners.size():
		if Geometry2D.segment_intersects_segment(from, to, corners[index], corners[(index + 1) % corners.size()]) != null:
			return true
	return false


func _test_ambient_parallax(environment: EnvironmentView3D) -> void:
	_check(environment._ambient_root.get_child_count() > 0, "Green Shade spike includes a secondary ambient parallax plane")
	if environment._ambient_root.get_child_count() == 0:
		return
	var ambient := environment._ambient_root.get_child(0) as Sprite3D
	var base_position: Vector3 = ambient.get_meta("base_position")
	var factor := float(ambient.get_meta("parallax"))
	var center_value: Array = environment.environment_manifest.camera.movementBounds
	var center := Rect2(float(center_value[0]), float(center_value[1]), float(center_value[2]), float(center_value[3])).get_center()
	environment.set_camera_focus(center + Vector2(64.0, 0.0), true)
	_check(is_equal_approx(ambient.position.x, base_position.x + 2.0 * factor), "ambient parallax follows its authored fraction of camera translation")
	environment.set_reduced_motion(true)
	_check(ambient.position.is_equal_approx(base_position), "reduced motion resets secondary ambient parallax to its authored position")
	environment.set_camera_focus(center - Vector2(64.0, 0.0), true)
	_check(ambient.position.is_equal_approx(base_position), "reduced motion keeps ambient planes fixed while the camera moves")
	environment.set_reduced_motion(false)
	_check(not ambient.position.is_equal_approx(base_position), "secondary ambient parallax resumes only after reduced motion is disabled")
	environment.set_camera_focus(center, true)


func _test_environment_arena_review(environment: EnvironmentView3D) -> void:
	var review_scene := load("res://scenes/asset_review_scene.tscn") as PackedScene
	var review: Node = review_scene.instantiate()
	get_tree().root.add_child(review)
	await get_tree().process_frame
	review.set_process(false)
	review.candidate = {"kind": "arena", "assetId": "environment-arena-review", "revision": "test"}
	review.manifest = BattleArena.graybox()
	var fixture_metadata := AssetResourceLibrary.read_json("res://tests/fixtures/environments/green-shade-3d-spike/fixture.json")
	review.manifest["environment"] = {
		"assetId": environment.environment_manifest.assetId,
		"revision": environment.environment_manifest.revision,
		"contentSha256": fixture_metadata.contentSha256,
	}
	review.manifest["presentation"] = {"staticPlacements": []}
	review._create_environment_view()
	_check(review._environment_view.configure(environment.environment_manifest, "res://", environment._textures), "environment-backed arena review configures its real 3D view")
	_check(review._environment_view.build_review_samples(), "environment-backed arena review renders plane stacks")
	review._add_environment_viewpoints()
	review._activate_environment_review()
	_check(review._stage.size == Vector2(390, 844) and review._environment_view.size == Vector2(390, 844), "environment reviewer defaults to the 390×844 portrait target")
	_check(review._target_size_picker.item_count == 3 and review._clip.item_count == 6, "environment reviewer exposes all portrait targets and depth/viewpoint controls")
	for target_size: Vector2i in [Vector2i(360, 640), Vector2i(390, 844), Vector2i(430, 932)]:
		review._set_environment_target_size(target_size)
		_check(review._stage.size == Vector2(target_size) and review._environment_view.size == Vector2(target_size), "production reviewer renders the %d×%d portrait target at native logical size" % [target_size.x, target_size.y])
	review._set_environment_target_size(Vector2i(390, 844))
	var review_before: Vector2 = review._environment_actor.get_ground_position()
	review._advance_environment_demo(0.5)
	_check(review._environment_actor.get_ground_position().distance_to(review_before) > 1.0, "environment review actor traverses from front to behind the plane stack")
	_check(review._environment_vfx.visible and review._environment_vfx.alpha_cut == SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS, "environment review includes a visible depth-tested translucent VFX sample")
	_check(review._environment_vfx.render_priority == 3 and review._environment_acceptance.size() >= 15, "reviewer records priority and portrait/viewpoint acceptance evidence")
	review._start_bout(true)
	var bout_ok: bool = review._arena_view == null and not review._session.is_empty() and review._session.get("ok", false)
	_check(bout_ok, "environment-backed arena starts a real seeded bout without a 2D ArenaView")
	if not bout_ok:
		review.free()
		return
	_check(review._fighters.size() == 2 and review._fighters.values().all(func(fighter: Variant) -> bool: return fighter is CompanionPresentation3D), "environment-backed arena bout creates two AnimatedSprite3D fighters")
	_check(review._environment_view.camera_mode() == EnvironmentView3D.CAMERA_MODE_BATTLE_FRAME, "environment-backed arena uses fixed-axis battle framing rather than midpoint-only follow")
	var before_tick: int = review._session.tick
	review._process(0.1)
	_check(review._session.tick > before_tick, "environment-backed arena bout advances and renders without dereferencing a null ArenaView")
	review.queue_free()
	await get_tree().process_frame


func _test_battle_determinism(environment: EnvironmentView3D) -> void:
	var player := Sim.make_snapshot("player", "Partner", "agumon", "Rookie", "Bold", {"hp": 110, "mp": 48, "offense": 10, "defense": 8, "speed": 8, "brains": 8})
	var opponent := Sim.make_snapshot("opponent", "Training Agumon", "agumon", "Rookie", "Gentle", {"hp": 92, "mp": 48, "offense": 8, "defense": 7, "speed": 7, "brains": 7})
	var baseline := Sim.simulate("3d-view-is-presentation-only", 731, player, opponent, 180)
	var with_view_alive := Sim.create_session("3d-view-is-presentation-only", 731, player, opponent, {}, 180)
	var probes: Dictionary = {}
	for fighter_id: String in with_view_alive.actors:
		var probe := CompanionPresentation3D.new()
		environment.attach_world_node(probe)
		probe.configure("agumon")
		probes[fighter_id] = probe
	while not with_view_alive.complete:
		Sim.step(with_view_alive)
		for fighter_id: String in probes:
			var actor: Dictionary = with_view_alive.actors[fighter_id]
			probes[fighter_id].set_ground_position(Sim.ground_position(actor))
			probes[fighter_id].render_battle(actor, 0.5)
	var baseline_bytes := JSON.stringify(baseline)
	_check(JSON.stringify(with_view_alive) == baseline_bytes, "interleaved AnimatedSprite3D rendering leaves battle state and replay inputs byte-identical")
	var fingerprint := baseline_bytes.sha256_text()
	print("  sprite-in-3D battle fingerprint: " + fingerprint)
	_check(fingerprint == "66b5c883a5f54008b90ed07ba6d71fd62f11b43a6d65f764295ef3e9825d9484", "sprite-in-3D canonical simulation fingerprint remains established")
	for probe: CompanionPresentation3D in probes.values():
		probe.queue_free()


func _finish() -> void:
	print("%s: %d environment 3D spike checks" % ["PASS" if _failures == 0 else "FAIL", _checks])
	get_tree().quit(0 if _failures == 0 else 1)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("FAIL: " + message)
