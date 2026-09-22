extends SceneTree
## Offline authoring only. Outputs editable Sprite3D cards, never runtime RNG.
## --output <res://...tscn> [--replace] --test-mode
const SEED := 170926
const ATLAS := "res://assets/environment_workshop/forest-parallax/foliage.png"
const ATLAS_SHA := "ee0ed7a9f64646e8205801b671ba06591fa587f7dc79efc1ede5efb390c9743f"
const WORLD_SCALE := 4.0 / 3.0
var rng := RandomNumberGenerator.new()
var scene := Node3D.new()
var terrain := preload("res://scripts/environment/care_sloped_ground.gd").new()
var atlas: Texture2D
var count := 0
var layout_records: Array = []

func _initialize() -> void:
	if "--test-mode" not in OS.get_cmdline_user_args():
		fail("Offline authoring requires --test-mode; do not run against a live save.")
		return
	build.call_deferred()

func build() -> void:
	var args := OS.get_cmdline_user_args()
	var output_index := args.find("--output")
	if output_index < 0 or output_index + 1 >= args.size():
		fail("Supply --output; an existing scene also requires --replace.")
		return
	var output := args[output_index + 1]
	if not output.ends_with(".tscn") or (FileAccess.file_exists(output) and "--replace" not in args):
		fail("Refusing to replace existing/manual work without --replace: " + output)
		return
	if FileAccess.get_sha256(ATLAS) != ATLAS_SHA:
		fail("Foliage bytes changed; bind a new revision before generating placements.")
		return
	atlas = load(ATLAS)
	rng.seed = SEED
	scene.name = "TransitionWoodland"
	scene.set_meta("depth_layers", true)
	scene.set_meta("layout_seed", SEED)
	scene.set_meta("source_sha256", ATLAS_SHA)
	scene.set_meta("edit_help", "Editable lower woodland: overlapping dark pockets conceal the shoulder/backdrop gap. Never part of navigation. Rebuild writes a candidate unless --replace is explicit.")
	var rear := layer("RearGrove", 0.018)
	# A staggered back-grove silhouette. Broad crowns cover the joins; narrow
	# shrubs hide root/bottom boundaries. Never a duplicated panorama crop strip.
	for i: int in 22:
		var point := Vector2(-58.0 + i * 7.3 + rng.randf_range(-2.4, 2.4), rng.randf_range(-43.0, -28.0))
		card(rear, point, "tree", rng.randf_range(0.019, 0.026), 0.35)
		card(rear, point + Vector2(rng.randf_range(-5, 5), 5.0), "bush", rng.randf_range(0.009, 0.015), 0.39)
	var sides := layer("SideValleys", 0.0)
	for sign_x: int in [-1, 1]:
		for i: int in 12:
			var point := Vector2(20 + sign_x * rng.randf_range(43, 56), -15 + i * 8.0 + rng.randf_range(-3, 3))
			card(sides, point, "tree", rng.randf_range(0.015, 0.026), 0.38)
			for j: int in 3:
				card(sides, point + Vector2(rng.randf_range(-5, 5), rng.randf_range(-5, 5)), "fern" if j == 0 else "bush", rng.randf_range(0.006, 0.012), 0.43)
	var front := layer("FrontBasin", 0.0)
	# Two broken, overlapping depths close the empty foreground basin, leaving
	# asymmetrical apertures into dark ground instead of a manicured hedge ring.
	for row: int in 2:
		for i: int in 11:
			var point := Vector2(-31.0 + i * 10.0 + rng.randf_range(-3.5, 3.5), 76.0 + row * 19.0 + rng.randf_range(-7, 7))
			card(front, point, "tree" if (i + row) % 3 != 0 else "bush", rng.randf_range(0.016, 0.024), 0.32 + row * 0.025)
			card(front, point + Vector2(rng.randf_range(-5, 5), rng.randf_range(-5, 5)), "fern" if i % 3 == 0 else "bush", rng.randf_range(0.008, 0.015), 0.40)
	var near := layer("ForegroundCanopies", 0.0)
	for i: int in 13:
		var point := Vector2(-41.0 + i * 10.0 + rng.randf_range(-4.0, 4.0), rng.randf_range(116.0, 133.0))
		card(near, point, "tree", rng.randf_range(0.021, 0.029), 0.28)
		card(near, point + Vector2(rng.randf_range(-5, 5), -6.0), "fern" if i % 2 == 0 else "bush", rng.randf_range(0.010, 0.018), 0.34)
	scene.set_meta("layout_sha256", JSON.stringify(layout_records).sha256_text())
	var packed := PackedScene.new()
	var result := packed.pack(scene)
	if result == OK:
		result = ResourceSaver.save(packed, output)
	if result != OK:
		fail("Could not save authored scene: " + error_string(result))
		return
	print("PASS: wrote %d native transition cards, seed %d, to %s" % [count, SEED, output])
	scene.free()
	terrain.free()
	quit(0)

func layer(label: String, parallax: float) -> Node3D:
	var branch := Node3D.new()
	branch.name = label
	scene.add_child(branch)
	branch.owner = scene
	branch.set_meta("parallax", parallax)
	layout_records.append([label, parallax])
	return branch

func card(branch: Node3D, world: Vector2, kind: String, pixel_size: float, value: float) -> void:
	# Keep this band in the actual basin, not up on the bright shoulder. Moving
	# outward rather than lowering Y alone preserves contact with the ground.
	for attempt: int in 32:
		if terrain.height_at_ground(world) <= -8.5:
			break
		world += (world - Vector2(20, 24)).normalized() * 0.75
	assert(world.x < -2 or world.x > 42 or world.y < -2 or world.y > 50)
	var sprite := Sprite3D.new()
	sprite.name = "%s_%03d" % [kind.capitalize(), count]
	count += 1
	sprite.position = Vector3(world.x, terrain.height_at_ground(world) - 0.45, world.y) / WORLD_SCALE
	sprite.texture = atlas
	sprite.region_enabled = true
	sprite.region_rect = Rect2(0, 0, 627, 627) if kind == "tree" else (Rect2(627, 0, 627, 627) if kind == "bush" else Rect2(0, 627, 627, 627))
	sprite.offset = Vector2(-24, 268.5) if kind == "tree" else (Vector2(22, 252.5) if kind == "bush" else Vector2(-18, 217.5))
	sprite.pixel_size = pixel_size
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	sprite.shaded = false
	sprite.flip_h = rng.randf() < 0.5
	var variation := rng.randf_range(0.88, 1.09)
	sprite.modulate = Color(value * 0.82, value, value * 0.98, 1.0) * Color(variation, variation, variation, 1.0)
	sprite.set_meta("outside_gameplay", true)
	sprite.set_meta("buried_root", 0.45)
	sprite.set_meta("camera_clearance", true)
	sprite.set_meta("depth_role", String(branch.name))
	branch.add_child(sprite)
	sprite.owner = scene
	layout_records.append([String(branch.name), String(sprite.name), sprite.position,
		sprite.region_rect, sprite.offset, sprite.pixel_size, sprite.flip_h, sprite.modulate])

func fail(message: String) -> void:
	push_error(message)
	scene.free()
	terrain.free()
	quit(1)
