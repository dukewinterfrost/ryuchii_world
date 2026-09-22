extends SceneTree
## Native first-stage integration, shared sheer-ledge geometry, and GPU reviews.
const Sheer = preload("res://scripts/environment/sheer_stage_mesh.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func run() -> void:
	var game := root.get_node("GameState")
	check(game.isolated_mode,"Must use isolated save")
	if not game.isolated_mode:
		quit(1)
		return
	game.set_process(false)
	var start: Dictionary = load("res://scripts/environment/battle_field_review.gd").start("green-shade")
	check(start.get("ok",false),"First-stage contextual battle starts")
	if not start.get("ok",false):
		quit(1)
		return
	var battle_scene: Node = load("res://scenes/battle_scene.tscn").instantiate()
	root.add_child(battle_scene)
	battle_scene.set_process(false)
	await process_frame
	var view: BattleWorldPresentation3D = battle_scene.environment_view
	view.set_process(false)
	view.set_reduced_motion(true)
	var baseline := JSON.stringify(game.active_battle_result)
	var stage: Node3D = view._terrain_root.get_child(0)
	check(stage.name == &"RootboundGlade" and view.environment_manifest.get("reviewOnly",false),"Actual battle uses the editable unpromoted first-stage scene")
	check(stage.find_children("*","CollisionShape3D",true,false).is_empty(),"Presentation adds no collision authority")
	var terrain: MeshInstance3D = stage.get_node("Floor/ClearingTerrain")
	test_terrain(terrain,Vector2i(30,36),12.0)
	var home: Node3D = load("res://scenes/environments/care_clearing.tscn").instantiate()
	root.add_child(home)
	test_terrain(home.get_node("Ground"),Vector2i(40,48),16.0)
	home.free()
	for label: String in ["care_oval_foliage","care_transition_woodland"]:
		var old: Node3D = load("res://docs/reviews/rootbound-glade/baseline/%s.tscn" % label).instantiate()
		var current: Node3D = load("res://scenes/environment_workshop/%s.tscn" % label).instantiate()
		var before_cards := old.find_children("*","Sprite3D",true,false)
		check(before_cards.size() == current.find_children("*","Sprite3D",true,false).size(),"Home re-grounding preserves every existing plant")
		for before: Sprite3D in before_cards:
			var after: Sprite3D = current.get_node(old.get_path_to(before))
			check(Vector2(before.position.x,before.position.z).is_equal_approx(Vector2(after.position.x,after.position.z)) and before.scale.is_equal_approx(after.scale) and before.modulate.is_equal_approx(after.modulate) and before.flip_h == after.flip_h and before.offset == after.offset and before.region_rect == after.region_rect and is_equal_approx(before.pixel_size,after.pixel_size),"Home re-grounding only changes elevation, never authored XZ or plant appearance")
		old.free()
		current.free()
	view.camera.make_current()
	var cards := stage.get_node("ForestParallax/Woodland").find_children("*","Sprite3D",true,false)
	check(cards.size() == 236,"Authored woodland retains its deterministic 236-card layout")
	for card: Sprite3D in cards:
		var p := card.global_position
		check(absf(p.y-terrain.height_at_ground(Vector2(p.x,p.z))+float(card.get_meta("buried_root")))<0.01,"Foliage root matches sheer terrain")
		check(not card.no_depth_test and not card.shaded and card.alpha_cut == SpriteBase3D.ALPHA_CUT_DISCARD and card.texture_filter == BaseMaterial3D.TEXTURE_FILTER_NEAREST,"Foliage retains nearest unshaded depth-tested alpha cut")
		if card.get_meta("outside_gameplay"):
			check(not Rect2(-1.5,-1.5,33,39).has_point(Vector2(p.x,p.z)),"Large scenery stays outside gameplay and apron")
		else:
			check(card.pixel_size <= 0.0013 and (p.z<=13 or p.z>=26),"Small grass avoids central duel lane")
	var landmark: Node3D = stage.get_node("Landmarks/Landmark_1")
	check(landmark.position == Vector3(15,0,9) and landmark.get_meta("ground_footprint") == Rect2(400,240,160,96),"Original tree footprint and root are preserved")
	check(BattleArena.validate(battle_scene.battle.arena).is_empty(),"Battle clearances and paths remain valid")
	var sources := {"forest-parallax/foliage":"ee0ed7a9f64646e8205801b671ba06591fa587f7dc79efc1ede5efb390c9743f", "forest-bg1/distant":"537f2a74f01cdcf16c8bfa23bdc9854869717134ccdef3a2d6d1cde0d94a1f63", "forest-bg1/middle":"7e699e3662a89787c75df7a020881e73a767f29e240cf2c1973c6ee3704c93a6", "forest-bg1/foreground":"e6b4f554fafec70e5f1971695ff49cef8f22099936351cbcaf8ceeb9bd5fd2c7"}
	for source: String in sources:
		check(FileAccess.get_sha256("res://assets/environment_workshop/%s.png" % source) == sources[source],"Source bytes unchanged: "+source)
	var captures := "--capture" in OS.get_cmdline_user_args()
	for target: Vector2i in [Vector2i(360,640),Vector2i(390,844),Vector2i(430,932)]:
		root.content_scale_size = target
		root.size = target
		for i: int in 3: await process_frame
		view.frame_session(battle_scene.battle,1.0,true)
		check(view.camera_contains_world_points(view.last_framing_world_points),"Both fighters fit at "+str(target))
		var base_focus := view._camera_focus_ground
		var base_distance := view._camera_ground_distance
		for pose: String in ["center","left","right","near","far"]:
			view._camera_focus_ground = base_focus+Vector2(-192 if pose=="left" else (192 if pose=="right" else 0),0)
			view._camera_ground_distance = base_distance/(2.0 if pose=="near" else (0.65 if pose=="far" else 1.0))
			view._apply_camera_transform()
			for frame: int in 2: await process_frame
			for layer: String in ["Sky","ForestVista","BackgroundMeadow"]:
				var sprite: Sprite3D = stage.get_node("ForestParallax/"+layer)
				var half_width := sprite.texture.get_width()*sprite.pixel_size*0.5
				var left := view.camera.unproject_position(sprite.global_position-view.camera.global_basis.x*half_width)
				var right := view.camera.unproject_position(sprite.global_position+view.camera.global_basis.x*half_width)
				check(left.x <= 0 and right.x >= view.world_viewport.size.x,"Backdrop spans "+pose+" at "+str(target))
			if captures:
				RenderingServer.force_draw(false)
				root.get_texture().get_image().save_png("/tmp/rootbound-%s-%dx%d.png" % [pose,target.x,target.y])
		view._camera_focus_ground = base_focus
		view._camera_ground_distance = base_distance
		view._apply_camera_transform()
		if captures:
			var reference: Image
			var ratios: Array = []
			var units_per_pixel := 2.0*base_distance/cos(deg_to_rad(30.0))*tan(deg_to_rad(16.0))/target.x
			for fraction: float in [0.0,0.25,0.5,0.75,1.0,0.0]:
				view._camera_focus_ground = base_focus+Vector2(fraction*units_per_pixel*32.0,0)
				view._apply_camera_transform()
				for frame: int in 2: await process_frame
				RenderingServer.force_draw(false)
				var sample := view.world_viewport.get_texture().get_image()
				if reference == null: reference = sample
				var crop := Rect2i(int(sample.get_width()*0.15),int(sample.get_height()*0.65),int(sample.get_width()*0.7),int(sample.get_height()*0.2))
				var changed := 0
				for y: int in range(crop.position.y,crop.end.y):
					for x: int in range(crop.position.x,crop.end.x):
						var a := reference.get_pixel(x,y)
						var b := sample.get_pixel(x,y)
						if maxf(absf(a.r-b.r),maxf(absf(a.g-b.g),absf(a.b-b.b)))>0.015: changed += 1
				ratios.append(float(changed)/crop.get_area())
				sample.save_png("/tmp/rootbound-subpixel-%dx%d-%02d.png" % [target.x,target.y,int(fraction*100)])
			check(float(ratios[-1])<0.002,"Fractional camera pan returns to the identical stable ground crop")
			print("Rootbound subpixel %s: %s" % [target,ratios])
	# Standalone world overview makes the cliff and all dressing depths reviewable.
	if captures:
		view.reparent(root)
		battle_scene.visible = false
		root.content_scale_size = Vector2i(1280,720)
		root.size = Vector2i(1280,720)
		view.position = Vector2.ZERO
		view.size = Vector2(1280,720)
		for i: int in 3: await process_frame
		view._camera_focus_ground = Vector2(480,576)
		view._camera_ground_distance = 110.0
		view._apply_camera_transform()
		for frame: int in 2: await process_frame
		check(is_equal_approx(view._camera_ground_distance,110.0),"Overview camera remains at its authored review distance")
		RenderingServer.force_draw(false)
		view.world_viewport.get_texture().get_image().save_png("/tmp/rootbound-overview.png")
		view.reparent(battle_scene)
	# Advancing identical sessions with/without rendering must preserve replays.
	var with_view: Dictionary = battle_scene.battle.duplicate(true)
	var without_view: Dictionary = with_view.duplicate(true)
	for tick: int in 360:
		BattleSimulator.step(with_view)
		view.render_session(with_view,float(tick%3)/2.0)
		BattleSimulator.step(without_view)
	check(JSON.stringify(with_view) == JSON.stringify(without_view),"Native first-stage render leaves 360-tick simulation byte-identical")
	check(BattleSimulator.replay_record(with_view) == BattleSimulator.replay_record(without_view),"Presentation cannot change replay data or checksums")
	print("Rootbound deterministic sample: "+JSON.stringify(with_view).sha256_text())
	check(JSON.stringify(game.active_battle_result) == baseline,"No test presentation operation mutates active battle")
	battle_scene.free()
	check(EnvironmentAssetLibrary.active_package().is_empty(),"No pending art was promoted/activated")
	game.clear_active_battle()
	game.remove_meta("battle_field_review")
	print("Rootbound ledge: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

func test_terrain(terrain: MeshInstance3D, cells: Vector2i, drop: float) -> void:
	for x: int in cells.x+1:
		for z: int in cells.y+1:
			check(is_zero_approx(terrain.height_at_ground(Vector2(x,z))),"Every gameplay cell corner stays on Y=0")
	var arrays := terrain.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var wall_count := 0
	var sloped_faces := 0
	for i: int in vertices.size():
		var p := terrain.to_global(vertices[i])
		if not is_zero_approx(p.y) and not is_equal_approx(p.y,-drop): sloped_faces += 1
		# Godot compresses/decodes normals; allow its small octahedral error.
		if absf(normals[i].y)<0.001: wall_count += 1
	check(sloped_faces == 0 and wall_count == Sheer.SEGMENTS*6,"Cap/lower floor use two heights joined by vertical wall triangles: %d intermediate vertices, %d wall vertices" % [sloped_faces,wall_count])
	for i: int in range(0,vertices.size(),3):
		var normal := (vertices[i+1]-vertices[i]).cross(vertices[i+2]-vertices[i]).normalized()
		check(absf(normal.y)<0.001 or absf(normal.y)>0.999,"Every triangle is horizontal or vertical, measured from geometry")
	for i: int in Sheer.SEGMENTS:
		var angle := TAU*i/Sheer.SEGMENTS
		var direction := Vector2(cos(angle),sin(angle))
		var radius := Sheer.edge_radius(angle,terrain.oval_radii,terrain.flat_half_extents)
		check(is_zero_approx(terrain.height_at_ground(terrain.field_center+direction*(radius-0.05))) and is_equal_approx(terrain.height_at_ground(terrain.field_center+direction*(radius+0.05)),-drop),"Cliff sampler has a sharp ledge, not a hill")
