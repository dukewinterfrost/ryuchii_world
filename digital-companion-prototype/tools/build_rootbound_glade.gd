extends SceneTree
## Explicit offline authoring. No startup randomization; saved cards are editable.
const ATLAS := "res://assets/environment_workshop/forest-parallax/foliage.png"
const SHA := "ee0ed7a9f64646e8205801b671ba06591fa587f7dc79efc1ede5efb390c9743f"
const TEMPLATE := "res://docs/reviews/rootbound-glade/baseline/green_shade_battle.tscn"
const SEED := 170927
var rng := RandomNumberGenerator.new()
var stage: Node3D
var ground := preload("res://scripts/environment/rootbound_ground.gd").new()
var atlas: Texture2D
var count := 0
var records: Array = []

func _initialize() -> void:
	build.call_deferred()

func build() -> void:
	var args := OS.get_cmdline_user_args()
	var index := args.find("--output")
	if "--test-mode" not in args or index < 0 or index+1 >= args.size():
		fail("Use --test-mode --output <candidate.tscn> [--replace].")
		return
	var output := args[index+1]
	if not output.ends_with(".tscn") or (FileAccess.file_exists(output) and "--replace" not in args):
		fail("Refusing to overwrite existing hand-edited scene without --replace.")
		return
	if FileAccess.get_sha256(ATLAS) != SHA:
		fail("Source bytes differ from bound foliage hash.")
		return
	atlas = load(ATLAS)
	rng.seed = SEED
	stage = (load(TEMPLATE) as PackedScene).instantiate()
	stage.set_meta("layout_seed", SEED)
	stage.set_meta("art_direction", "Rootbound Glade: worn open arena, irregular planted shoulder, lowered woodland, registered BG-1 skyline")
	stage.set_meta("source_sha256", SHA)
	for branch: String in ["Floor", "ForestParallax", "Ambient"]:
		stage.get_node(branch).free()
	var floor_root := group(stage, "Floor")
	ground.name = "ClearingTerrain"
	ground.position = Vector3(15,0,18)
	var material := ShaderMaterial.new()
	material.resource_local_to_scene = true
	material.shader = load("res://shaders/rootbound_ground.gdshader")
	material.set_shader_parameter("source_texture", load("res://assets/environment_workshop/forest-parallax/panorama.png"))
	material.set_shader_parameter("source_region", Vector4(760,700,40,22))
	material.set_shader_parameter("lower_shadow_strength", 0.62)
	material.set_shader_parameter("source_detail", 0.18)
	ground.ground_material = material
	ground.material_override = material
	floor_root.add_child(ground)
	ground.owner = stage
	ground.set_meta("edit_help", "30x36 grid and two-unit apron remain flat. Edit Ground Material for soil/grass; rebuild terrain after geometry tuning. Re-ground outside cards with the same sampler.")
	var parallax := group(stage, "ForestParallax")
	parallax.set_script(load("res://scripts/environment/forest_parallax.gd"))
	parallax.preview_motion = true
	background(parallax)
	var dressing := group(parallax, "Woodland")
	dressing.set_meta("depth_layers", true)
	var rim := group(dressing,"RimPockets")
	# Uneven islands with deliberate horizon openings, not an evenly spaced ring.
	for pocket: Vector3 in [Vector3(-10,-3,9),Vector3(2,-7,6),Vector3(29,-5,11),Vector3(42,5,9),Vector3(-9,19,10),Vector3(40,27,7),Vector3(-2,42,11),Vector3(31,43,9)]:
		for i: int in int(pocket.z):
			var point := Vector2(pocket.x,pocket.y)+Vector2(rng.randf_range(-4.6,4.6),rng.randf_range(-3.2,3.2))
			if Rect2(-1.5,-1.5,33,39).has_point(point):
				continue
			card(rim,point,"bush" if i%3 else "fern",rng.randf_range(0.004,0.007),0.83)
	# A handful of full trees at different rim depths. None adds an invisible blocker.
	for point: Vector2 in [Vector2(-7,1),Vector2(36,2),Vector2(-6,25),Vector2(40,31),Vector2(3,-7),Vector2(26,43)]:
		card(rim,point,"tree",rng.randf_range(0.010,0.014),0.82)
	var rear := group(dressing,"RearGrove")
	rear.set_meta("parallax",0.018)
	for i: int in 16:
		var point := Vector2(-44+i*7.6+rng.randf_range(-2.5,2.5),rng.randf_range(-32,-22))
		card(rear,point,"tree",rng.randf_range(0.018,0.026),0.48)
		card(rear,point+Vector2(rng.randf_range(-4,4),4),"bush",rng.randf_range(0.008,0.013),0.47)
	var sides := group(dressing,"SideValleys")
	for side: int in [-1,1]:
		for i: int in 10:
			var point := Vector2(15+side*rng.randf_range(34,43),-10+i*7+rng.randf_range(-3,3))
			card(sides,point,"tree",rng.randf_range(0.014,0.021),0.39)
			for j: int in 2:
				card(sides,point+Vector2(rng.randf_range(-4,4),rng.randf_range(-4,4)),"fern" if j else "bush",rng.randf_range(0.006,0.011),0.45)
	var front := group(dressing,"FrontBasin")
	for i: int in 22:
		var point := Vector2(-24+(i%11)*8+rng.randf_range(-3,3),58+(i/11)*16+rng.randf_range(-5,5))
		card(front,point,"tree" if i%3 else "bush",rng.randf_range(0.014,0.021),0.35)
		card(front,point+Vector2(rng.randf_range(-4,4),-3),"fern" if i%2 else "bush",rng.randf_range(0.006,0.011),0.42)
	var grass := group(dressing,"LowGrass")
	for i: int in 38:
		var point := Vector2(rng.randf_range(1,29),rng.randf_range(1,35))
		# Keep the duel's broad central lane and spawn circles uncluttered.
		if (point.y > 13 and point.y < 26) or Rect2(12,6.5,6,5).has_point(point):
			continue
		card(grass,point,"fern",rng.randf_range(0.0007,0.0013),0.90)
	# Only one gameplay landmark, matching the unchanged [400,240,160,96] rect.
	var landmark := stage.get_node("Landmarks/Landmark_1") as Node3D
	landmark.set_meta("ground_footprint",Rect2(400,240,160,96))
	landmark.set_meta("edit_help","This trunk is the existing combat blocker. Its ground root/footprint must stay synchronized; rim plants are outside gameplay.")
	stage.get_node("CameraRig").distance = 128.0
	stage.get_node("CameraRig").position = Vector3(15,0,18)
	stage.get_node("CameraRig/Camera3D").fov = 32.0
	stage.get_node("CameraRig/Camera3D").far = 600.0
	stage.set_meta("layout_sha256",JSON.stringify(records).sha256_text())
	var packed := PackedScene.new()
	var result := packed.pack(stage)
	if result == OK:
		result = ResourceSaver.save(packed,output)
	if result != OK:
		fail(error_string(result))
		return
	print("PASS: Rootbound Glade saved, %d cards, seed %d, layout %s" % [count,SEED,stage.get_meta("layout_sha256")])
	stage.free()
	quit(0)

func background(parent: Node3D) -> void:
	# Registered canvases at 1/.95/.90 scale around a fixed-axis reference lens.
	var paths := ["distant","middle","foreground"]
	var names := ["Sky","ForestVista","BackgroundMeadow"]
	for i: int in 3:
		var sprite := Sprite3D.new()
		sprite.name = names[i]
		sprite.texture = load("res://assets/environment_workshop/forest-bg1/%s.png" % paths[i])
		sprite.offset = Vector2(0,sprite.texture.get_height()/2.0)
		sprite.position = Vector3(15,-25+i*2.6,-44+i*5.45)
		sprite.pixel_size = 0.10*(1.0-i*0.05)
		sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
		sprite.set_meta("parallax",[0.12,0.06,0.025][i])
		parent.add_child(sprite)
		sprite.owner = stage
		if i == 0:
			var material := ShaderMaterial.new()
			material.shader = load("res://shaders/home_day_night_sky.gdshader")
			material.set_shader_parameter("artwork",sprite.texture)
			material.set_shader_parameter("preserve_artwork",true)
			material.set_shader_parameter("sky_top",Color(0.12549,0.55294,0.74118))
			material.set_shader_parameter("sky_horizon",Color(0.70588,0.88235,0.85882))
			sprite.material_override = material

func group(parent: Node3D, label: String) -> Node3D:
	var node := Node3D.new()
	node.name = label
	parent.add_child(node)
	node.owner = stage
	return node

func card(parent: Node3D, point: Vector2, kind: String, pixel_size: float, value: float) -> void:
	var sprite := Sprite3D.new()
	sprite.name = "%s_%03d" % [kind.capitalize(),count]
	count += 1
	var height := ground.height_at_ground(point)
	var bury := 0.3 if height < -1 else 0.03
	sprite.position = Vector3(point.x,height-bury,point.y)
	sprite.texture = atlas
	sprite.region_enabled = true
	sprite.region_rect = Rect2(0,0,627,627) if kind == "tree" else (Rect2(627,0,627,627) if kind == "bush" else Rect2(0,627,627,627))
	sprite.offset = Vector2(-24,268.5) if kind == "tree" else (Vector2(22,252.5) if kind == "bush" else Vector2(-18,217.5))
	sprite.pixel_size = pixel_size
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	sprite.flip_h = rng.randf() < 0.5
	var tone := rng.randf_range(0.91,1.06)*value
	sprite.modulate = Color(tone*0.88,tone,tone*0.88,1)
	sprite.set_meta("buried_root",bury)
	sprite.set_meta("outside_gameplay",parent.name != &"LowGrass")
	sprite.set_meta("camera_clearance",parent.name != &"LowGrass")
	sprite.set_meta("depth_role",String(parent.name))
	parent.add_child(sprite)
	sprite.owner = stage
	records.append([String(parent.name),sprite.position,sprite.region_rect,sprite.pixel_size,sprite.flip_h,sprite.modulate])

func fail(message: String) -> void:
	push_error(message)
	if is_instance_valid(stage): stage.free()
	elif is_instance_valid(ground): ground.free()
	quit(1)
