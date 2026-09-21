extends SceneTree
## Isolated real-care review: original BG-1 bytes, four edges and clock lighting.
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
	if not game.isolated_mode:
		quit(1)
		return
	game.set_process(false)
	var saved_scene := FileAccess.get_file_as_string("res://scenes/environments/care_clearing.tscn")
	check(saved_scene.contains("wrapped_background_layer.gd") and saved_scene.count("wrap_radius =") == 3, "Saved care scene retains all three 360-degree layers; reload external changes before saving in Godot")
	game._home_package = HabitatAssetLibrary.resolve_region("green-shade", false)
	var baseline: Dictionary = game.state.duplicate(true)
	var care: Node = load("res://scenes/care_scene.tscn").instantiate()
	root.add_child(care)
	care.habitat.set_process(false)
	# Capture after normal care initialization; then all tested operations are
	# presentation-only, with the simulation explicitly paused.
	baseline = game.state.duplicate(true)
	var view: EnvironmentView3D = care.habitat.environment_3d
	var wrap: Node3D = view._native_parallax
	for layer_name: String in ["Sky", "ForestVista", "BackgroundMeadow"]:
		var layer = wrap.get_node(layer_name)
		check(layer.layers == 0 and layer.ribbon is MeshInstance3D, "Source card is replaced by one editable ribbon")
		var center: Vector3 = layer.position+Vector3(0,0,layer.wrap_radius)
		check(Vector2(center.x,center.z).distance_to(Vector2(15,18))<=3.01, "Background layers share the clearing center within bounded parallax")
		var arrays: Array = layer.ribbon.mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		check(vertices.size() == 384*12, "Closed ribbon and lower skirt have all segments")
		check(vertices[0].distance_to(vertices[383*12+2])<0.001, "Last segment closes exactly onto the first")
		check(is_equal_approx(layer.mirrored_u(0),layer.mirrored_u(1)), "Artwork repeats close without a UV seam")
		var radius: float = layer.wrap_radius
		var material: Material = layer.ribbon.get_active_material(0)
		layer.wrap_radius += 1
		check((layer.position+Vector3(0,0,layer.wrap_radius)).distance_to(center)<0.001, "Radius edits preserve wrap center")
		check(layer.ribbon.get_active_material(0)==material, "Radius rebuild retains day/night material")
		layer.wrap_radius = radius
	check(wrap.home_oval_layout and not wrap.get_node("Boundary").visible, "Care uses its own oval, not the old rectangular hedge rows")
	var oval: Node3D = wrap.get_node("OvalLayout")
	var radii: Vector2 = oval.get_meta("inner_radii")
	check(radii.x > radii.y and radii.x > 20, "Clearing is wider left-right and larger than the old base")
	var grass := oval.get_node("GrassDetails").get_children()
	check(grass.size() == 104, "Middle foliage is increased with additional small irregular clusters")
	var plant_types: Dictionary = {}
	var smallest := INF
	var largest := 0.0
	var close_neighbors := 0
	var isolated_plants := 0
	for tuft: Sprite3D in grass:
		check(tuft.pixel_size <= 0.0034 and not tuft.no_depth_test, "Middle foliage remains low and depth-tested")
		plant_types[tuft.region_rect] = true
		smallest = minf(smallest, tuft.pixel_size)
		largest = maxf(largest, tuft.pixel_size)
		var ground := Vector2(tuft.position.x, tuft.position.z) * (4.0 / 3.0)
		check(absf(ground.x - (20.5 + sin(ground.y * 0.19) * 1.7)) > 3.19, "Grass does not crowd the footpath")
		check(((ground - Vector2(20.5, 24.5)) / Vector2(7, 4.5)).length() > 0.99, "Resting spot remains open")
		var nearest := INF
		for other: Sprite3D in grass:
			if other != tuft:
				nearest = minf(nearest, tuft.position.distance_to(other.position))
		if nearest < 1.5: close_neighbors += 1
		if nearest > 2.8: isolated_plants += 1
	check(plant_types.size() >= 2 and largest / smallest > 2.5, "Plant silhouettes and sizes vary, rather than repeating one tuft")
	check(close_neighbors >= 20 and isolated_plants >= 5, "Layout has dense clusters and sparse pockets, not evenly jittered rows")
	check(FileAccess.get_sha256("res://assets/environment_workshop/forest-parallax/foliage.png") == "ee0ed7a9f64646e8205801b671ba06591fa587f7dc79efc1ede5efb390c9743f", "Foliage source bytes remain unchanged")
	var boundary: Node3D = oval.get_node("Boundary")
	check(boundary.get_child_count() == 160, "Edge density is increased in pockets without rebuilding the former 394-card wall")
	var interiors := oval.get_node("InteriorTrees")
	check(interiors.get_child_count() == 3, "Three interior oaks are authored as editable sprite cards")
	var manifest: Dictionary = care.habitat.habitat_manifest
	check(manifest == game.get_home_package().habitat, "Rendering, navigation and committed movement share explicit tree footprints")
	check(manifest.get("nativeTrees", []).size() == 3, "Unoccupied starter clearing enables all three trees")
	check(HabitatRules.all_free_cells_reachable(game.state.habitat, manifest), "Interior trunks preserve full free-cell connectivity")
	for definition: Dictionary in manifest.get("nativeTrees", []):
		var tree: Sprite3D = interiors.get_node(String(definition.id))
		var rect: Array = definition.rect
		check(tree.visible and tree.global_position.distance_to(Vector3(rect[0]+rect[2]*0.5, 0.025, rect[1]+rect[3]*0.5)) < 0.01, "Interior tree roots match their explicit ground footprint")
		check(HabitatRules.blocked_cells(game.state.habitat, manifest).has(Vector2i(rect[0], rect[1])), "The companion cannot walk through a trunk")
	var legacy := HabitatRules.default_layout()
	legacy.items.append({"instance_id": "saved-planter", "item_id": "planter", "x": 8, "y": 11, "rotation": 0})
	var legacy_before := legacy.duplicate(true)
	var resolved: Dictionary = preload("res://scripts/environment/native_care_scenery.gd").resolve(legacy, HabitatAssetLibrary.fallback_manifest("green-shade"))
	check(resolved.nativeTrees.size() == 2 and legacy == legacy_before, "An old decoration omits the conflicting tree without changing the save")
	check(HabitatRules.validate_layout(legacy, Vector2i(-1,-1), resolved).ok, "Existing saved decoration remains valid")
	var occupied := HabitatRules.default_layout()
	occupied.creature_cell = [8, 11]
	occupied.items.append({"instance_id": "saved-potty", "item_id": "digi_potty", "x": 3, "y": 3, "rotation": 0})
	var occupied_result: Dictionary = preload("res://scripts/environment/native_care_scenery.gd").resolve(occupied, HabitatAssetLibrary.fallback_manifest("green-shade"))
	check(occupied_result.nativeTrees.size() == 2, "A companion saved on a new trunk cell is never enclosed by that tree")
	check(HabitatRules.path_to_potty(occupied, Vector2i(-1,-1), occupied_result).size() > 0, "Potty access survives saved-cell tree omission")
	var plain := HabitatAssetLibrary.fallback_manifest("green-shade")
	plain.revision = "future-promoted-revision"
	check(preload("res://scripts/environment/native_care_scenery.gd").resolve(occupied, plain) == plain, "Native working-scene trunks never modify a separately pinned habitat revision")
	view.sync_native_care_trees(resolved.nativeTrees)
	check(not interiors.get_node("InteriorOakWest").visible, "Omitted trunks are hidden in the renderer too")
	view.sync_native_care_trees(manifest.nativeTrees)
	var terrain: MeshInstance3D = view._terrain_root.get_node("CareClearing/Ground")
	var shadows: Array = terrain.get_active_material(0).get_shader_parameter("tree_shadows")
	check(shadows.filter(func(point: Vector4) -> bool: return point.z > 0).size() == 9, "Six rim trees and three interior trees receive rooted painted shade")
	check(terrain.mesh is ArrayMesh, "Outer ground is a genuine sculpted mesh, not just a painted drop")
	var terrain_vertices: PackedVector3Array = terrain.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	for vertex: Vector3 in terrain_vertices:
		var world_vertex := terrain.to_global(vertex)
		if world_vertex.x >= 0 and world_vertex.x <= 40 and world_vertex.z >= 0 and world_vertex.z <= 48:
			check(is_zero_approx(world_vertex.y), "Actual rendered terrain vertices in playable cells stay at ground height")
	for z: int in range(49):
		for x: int in range(41):
			check(is_zero_approx(terrain.height_at_ground(Vector2(x, z))), "The entire playable rectangle remains flat")
	check(terrain.height_at_ground(Vector2(20, -28)) < -12.0, "Terrain drops below the northern clearing edge")
	check(terrain.height_at_ground(Vector2(20, 85)) < -12.0, "Foreground woodland sits below the clearing")
	var lowered_trees := 0
	for card: Sprite3D in boundary.get_children():
		var world := card.global_position
		check(absf(world.y - terrain.height_at_ground(Vector2(world.x, world.z)) - 0.025) < 0.05, "Sparse foliage is rooted on the sloped ground")
		if card.region_rect.position == Vector2.ZERO and world.y < -4:
			lowered_trees += 1
	check(lowered_trees >= 15, "Surrounding tree groups are visibly below the field")
	var ring_count := 0
	var nearest_rim := INF
	var farthest_rim := 0.0
	for card: Sprite3D in boundary.get_children():
		if int(card.get_meta("ring", -1)) == 0:
			var normalized := (Vector2(card.position.x, card.position.z) - Vector2(15, 18)) / radii
			check(absf(normalized.length() - 1.0) < 0.16, "Inner foliage retains the wider oval envelope")
			nearest_rim = minf(nearest_rim, normalized.length())
			farthest_rim = maxf(farthest_rim, normalized.length())
			ring_count += 1
	check(ring_count >= 20 and ring_count <= 40, "Inner rim consists of separated low pockets rather than a continuous hedge")
	check(farthest_rim - nearest_rim > 0.2, "Forest edge has asymmetric pockets and protrusions, not a manicured ring")
	for source: Array in [["reference", "371b65b3612683184030affcb8bdfe190df533ff78034ddcdc91099e6826da19"], ["distant", "537f2a74f01cdcf16c8bfa23bdc9854869717134ccdef3a2d6d1cde0d94a1f63"], ["middle", "7e699e3662a89787c75df7a020881e73a767f29e240cf2c1973c6ee3704c93a6"], ["foreground", "e6b4f554fafec70e5f1971695ff49cef8f22099936351cbcaf8ceeb9bd5fd2c7"]]:
		check(FileAccess.get_sha256("res://assets/environment_workshop/forest-bg1/%s.png" % source[0]) == source[1], "Exact BG-1 source bytes: " + source[0])
	check(wrap.get_node("Sky").texture.resource_path.ends_with("forest-bg1/distant.png"), "Home uses BG-1 distant layer")
	check(wrap.get_node("ForestVista").texture.resource_path.ends_with("forest-bg1/middle.png"), "Home uses BG-1 alpha middle layer")
	check(wrap.get_node("BackgroundMeadow").texture.resource_path.ends_with("forest-bg1/foreground.png"), "Home uses BG-1 foreground layer")
	check(wrap.get_node("Sky").position.z < wrap.get_node("ForestVista").position.z and wrap.get_node("ForestVista").position.z < wrap.get_node("BackgroundMeadow").position.z, "Sky, middle grove and near meadow retain genuine ordered depth")
	check(wrap.get_node("Sky").wrap_radius-wrap.get_node("ForestVista").wrap_radius >= 45 and wrap.get_node("ForestVista").wrap_radius-wrap.get_node("BackgroundMeadow").wrap_radius >= 40, "Background ribbons retain the requested greater depth separation")
	check(float(terrain.get_active_material(0).get_shader_parameter("lower_shadow_strength")) >= 0.55, "Lowered stage has strong stable woodland shade")
	for side: String in ["North", "South", "West", "East"]:
		check(boundary.find_children(side + "_*", "Sprite3D", false, false).size() >= 3, side + " retains sparse woodland pockets")
	for card: Sprite3D in boundary.get_children():
		check(card.position.x < 0 or card.position.x > 30 or card.position.z < 0 or card.position.z > 36, "Boundary roots remain outside playable cells")
		check(not card.no_depth_test and card.alpha_cut == SpriteBase3D.ALPHA_CUT_DISCARD, "Boundary cutouts write/test depth")
	var capture := "--capture" in OS.get_cmdline_user_args()
	for target: Vector2i in [Vector2i(360,640),Vector2i(390,844),Vector2i(430,932),Vector2i(1280,720)]:
		root.content_scale_size = target
		root.size = target
		await process_frame
		care._set_map_view(true)
		view.set_process(false)
		for angle: String in ["center", "north", "south", "west", "east", "near", "overview"]:
			var delta := Vector2.ZERO
			if angle == "north": delta.y = -768
			if angle == "south": delta.y = 768
			if angle == "west": delta.x = -640
			if angle == "east": delta.x = 640
			view.set_home_zoom_multiplier(0.0 if angle == "overview" else (2.0 if angle == "near" else 0.65), true)
			view.set_home_manual_pan(delta, true)
			view.day_night.clock.set_preview_hour(12)
			for frame: int in 3: await process_frame
			var camera := view.camera
			var sky_depth := -camera.to_local(wrap.get_node("Sky").global_position).z
			check(sky_depth > camera.near and sky_depth < camera.far, "BG-1 backdrop stays within the enlarged overview camera's clipping range")
			for layer_name: String in ["Sky", "ForestVista", "BackgroundMeadow"]:
				var layer: Sprite3D = wrap.get_node(layer_name)
				for screen_x: float in [0.0,float(view.world_viewport.size.x)]:
					var screen := Vector2(screen_x,0)
					var origin := layer.to_local(camera.project_ray_origin(screen)) - Vector3(0,0,layer.wrap_radius)
					var direction := layer.global_basis.inverse()*camera.project_ray_normal(screen)
					var a := direction.x*direction.x+direction.z*direction.z
					var b := 2.0*(origin.x*direction.x+origin.z*direction.z)
					var c: float = origin.x*origin.x+origin.z*origin.z-layer.wrap_radius*layer.wrap_radius
					var discriminant: float = b*b-4.0*a*c
					check(discriminant>=0,"Closed ribbon covers the horizontal camera edge: "+layer_name)
					if discriminant>=0 and layer_name=="Sky":
						var t := (-b+sqrt(discriminant))/(2.0*a)
						var hit := origin+direction*t
						check(t>0 and -camera.to_local(camera.project_ray_origin(screen)+camera.project_ray_normal(screen)*t).z<camera.far and hit.y>=-800 and hit.y<=layer.canvas_height()*4.0,"Wrapped sky covers the top corners within camera clipping limits")
			var sky: Sprite3D = wrap.get_node("Sky")
			var sky_height: float = sky.canvas_height() * sky.global_basis.get_scale().y * 4.0
			check(camera.unproject_position(sky.global_position + camera.global_basis.y * sky_height).y <= 0, "Extended sky covers the top of every portrait and wide view")
			var ground: MeshInstance3D = view._terrain_root.get_node("CareClearing/Ground")
			for screen_x: float in [0.0, float(view.world_viewport.size.x)]:
				var screen_point := Vector2(screen_x, view.world_viewport.size.y)
				var origin := camera.project_ray_origin(screen_point)
				var direction := camera.project_ray_normal(screen_point)
				var near_t := 0.0
				var far_t := camera.far
				for step: int in 32:
					var midpoint := (near_t + far_t) * 0.5
					var point := origin + direction * midpoint
					if point.y > ground.height_at_ground(Vector2(point.x, point.z)):
						near_t = midpoint
					else:
						far_t = midpoint
				var hit := origin + direction * far_t
				check(ground.mesh.get_aabb().grow(0.1).has_point(ground.to_local(hit)), "Sculpted terrain covers both bottom corners without exposing its edge")
			for card: Sprite3D in wrap._foreground_cards:
				var height := card.region_rect.size.y * card.pixel_size * card.global_basis.get_scale().y
				check(card.visible == (-camera.to_local(card.global_position).z > height * 1.7), "Foreground clearance follows current camera")
			if capture:
				RenderingServer.force_draw(false)
				view.world_viewport.get_texture().get_image().save_png("/tmp/bg1-%s-%dx%d.png" % [angle,target.x,target.y])
		view.set_home_manual_pan(Vector2.ZERO, true)
		view.set_home_zoom_multiplier(0.45, true)
		for hour: float in [6, 12, 18, 0]:
			view.day_night.clock.set_preview_hour(hour)
			await process_frame
			if capture:
				RenderingServer.force_draw(false)
				view.world_viewport.get_texture().get_image().save_png("/tmp/bg1-time-%02d-%dx%d.png" % [int(hour),target.x,target.y])
	for key: String in baseline:
		if key == "habitat":
			for field: String in baseline.habitat:
				# Existing Field UI deliberately saves camera preferences. Scenery
				# must not change navigation, items, companion or gameplay state.
				if field != "camera":
					check(game.state.habitat.get(field) == baseline.habitat[field], "Unchanged gameplay habitat field: " + field)
		else:
			check(game.state[key] == baseline[key], "Unchanged simulation field: " + key)
	care.free()
	print("BG-1 wrap: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
