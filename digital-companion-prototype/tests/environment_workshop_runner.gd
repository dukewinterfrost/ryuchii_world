extends SceneTree
## Validate that the authoring scenes remain editable and don't rebuild over
## saved scene/material choices. Optional --capture produces real GPU previews.

const REGIONS := ["green_shade", "shellfish_beach", "toy_maze", "mechatropolis", "nephelis_abyss"]
var failures := 0
var checks := 0

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func run() -> void:
	var game_state := root.get_node("GameState")
	check(game_state.is_review_launch(PackedStringArray(["res://scenes/environment_workshop/green_shade_home.tscn"])), "F6 workshop launches must isolate saves")
	check(not game_state.is_review_launch(PackedStringArray(["res://scenes/care_scene.tscn"])), "Normal care launch remains normal")
	for region: String in REGIONS:
		for layout: String in ["home", "battle"]:
			var path := "res://scenes/environment_workshop/%s_%s.tscn" % [region, layout]
			var packed := load(path) as PackedScene
			check(packed != null, path + " loads")
			if packed == null:
				continue
			var scene := packed.instantiate()
			root.add_child(scene)
			current_scene = scene
			await process_frame
			var rig: Node3D = scene.get_node("CameraRig")
			var camera: Camera3D = rig.get_node("Camera3D")
			var floor_node: Node3D = scene.get_node("Floor")
			check(is_equal_approx(rig.rotation_degrees.x, -30), "Shallower initial camera pitch")
			check(camera.keep_aspect == Camera3D.KEEP_WIDTH, "Portrait keeps width")
			var sheer_floor := region == "green_shade" and layout == "battle"
			check(floor_node.get_child_count() == (1 if sheer_floor else 16), "Editable sheer terrain or sixteen source floor patches")
			var patch: MeshInstance3D = floor_node.get_child(0)
			if sheer_floor:
				check(patch.material_override.resource_local_to_scene, "Battle terrain material stays local to its scene")
			else:
				var other_patch: MeshInstance3D = floor_node.get_child(1)
				check(patch.material_override != other_patch.material_override, "Patches have independent material resources")
			var cropped_floor := patch.material_override is ShaderMaterial
			check(patch.material_override.get_shader_parameter("source_texture") != null if cropped_floor else patch.material_override.albedo_texture != null, "Imported external floor texture resolves")
			var actor: AnimatedSprite3D = scene.get_node("Characters").get_child(0).get_node("AnimatedSprite3D")
			check(actor.sprite_frames.has_animation("eat.default"), "Existing eating clip remains editable")
			check(actor.rotation == Vector3.ZERO and actor.billboard == BaseMaterial3D.BILLBOARD_ENABLED, "Sprites stay orthogonal to the camera")
			# Save a changed scene in memory, reload it, and prove no runtime builder
			# reverts the artist's native transforms or patch UV edits.
			rig.pitch_degrees = 24.0
			rig.distance = 42.0
			patch.position.y = 0.2
			if sheer_floor:
				patch.ground_material.set_shader_parameter("source_detail", 0.27)
			elif cropped_floor:
				patch.material_override.set_shader_parameter("tile_meters", Vector2(7, 4))
			else:
				patch.material_override.uv1_offset = Vector3(0.17, 0.23, 0)
			var saved := PackedScene.new()
			check(saved.pack(scene) == OK, "Edited scene packs")
			scene.free()
			var restored := saved.instantiate()
			root.add_child(restored)
			current_scene = restored
			await process_frame
			await process_frame
			check(is_equal_approx(restored.get_node("CameraRig").rotation_degrees.x, -24), "Saved pitch survives running")
			check(is_equal_approx(restored.get_node("CameraRig/Camera3D").position.z, 42), "Saved camera distance survives running")
			var restored_patch: MeshInstance3D = restored.get_node("Floor").get_child(0)
			var mapping_preserved: bool = restored_patch.material_override.get_shader_parameter("tile_meters") == Vector2(7, 4) if cropped_floor else restored_patch.material_override.uv1_offset.is_equal_approx(Vector3(0.17,0.23,0))
			if sheer_floor:
				mapping_preserved = is_equal_approx(float(restored_patch.material_override.get_shader_parameter("source_detail")),0.27)
			check(is_equal_approx(restored_patch.position.y, 0.2) and mapping_preserved, "Saved floor placement and UV edits survive running")
			restored.free()
			current_scene = null
	if "--capture" in OS.get_cmdline_user_args():
		for target: Vector2i in [Vector2i(360,640),Vector2i(390,844),Vector2i(430,932)]:
			root.size = target
			for layout: String in ["home", "battle"]:
				var scene: Node3D = (load("res://scenes/environment_workshop/green_shade_%s.tscn" % layout) as PackedScene).instantiate()
				root.add_child(scene)
				current_scene = scene
				for frame: int in 6:
					await process_frame
				await RenderingServer.frame_post_draw
				var capture := root.get_texture().get_image()
				var path := "/tmp/workshop-%s-%sx%s.png" % [layout,target.x,target.y]
				check(capture.save_png(path) == OK, "Capture " + path)
				scene.free()
				current_scene = null
	print("%s: %d environment workshop checks; %d failures" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(0 if failures == 0 else 1)
