extends RefCounted
## Isolated foliage composition. Not a runtime import/promotion mechanism.

const PLAN := "res://assets-source/care-woodland-foliage/2026-09-15.001/source-plan.json"

static func apply(view: EnvironmentView3D, candidate_path: String = "") -> bool:
	var game := view.get_tree().root.get_node_or_null("GameState")
	if game == null or not game.isolated_mode:
		return false
	var plan := AssetResourceLibrary.read_json(PLAN)
	var source: Dictionary = plan.get("sources", {}).get("foliage-sheet", {})
	var path := PLAN.get_base_dir().path_join(String(source.get("path", "")))
	if "sha256:" + FileAccess.get_sha256(path) != String(source.get("sha256", "")):
		return false
	var pixels := Image.load_from_file(path)
	if pixels == null or pixels.get_size() != Vector2i(1254,1254):
		return false
	var texture := ImageTexture.create_from_image(pixels)
	var render_texture: Texture2D = texture
	var entries: Dictionary = plan.entries.duplicate(true)
	if not candidate_path.is_empty():
		var candidate := AssetResourceLibrary.read_json(candidate_path.path_join("candidate.json"))
		if candidate.get("assetId") != plan.assetId or candidate.get("revision") != plan.revision or not candidate.get("nativeResources", false):
			return false
		for filename: String in candidate.get("files", {}):
			if filename.is_absolute_path() or ".." in filename.split("/") or "sha256:" + FileAccess.get_sha256(candidate_path.path_join(filename)) != candidate.files[filename]:
				return false
		var frames := load(candidate_path.path_join("atlasframes.tres")) as SpriteFrames
		var atlas := AssetResourceLibrary.read_json(candidate_path.path_join("atlas.json"))
		if frames == null or frames.get_meta("source_manifest", {}) != atlas:
			return false
		for name: String in entries:
			if not frames.has_animation(name) or not atlas.frames.has(name):
				return false
			var region := frames.get_frame_texture(name, 0) as AtlasTexture
			if region == null:
				return false
			var native_pixels := region.get_image()
			var source_rect: Array = entries[name].rect
			var source_pixels := pixels.get_region(Rect2i(source_rect[0], source_rect[1], source_rect[2], source_rect[3]))
			# Compiler normalizes only invisible RGB; all visible RGBA must match.
			for y: int in source_pixels.get_height():
				for x: int in source_pixels.get_width():
					var expected := source_pixels.get_pixel(x, y)
					if expected.a == 0:
						expected = Color(0, 0, 0, 0)
					if native_pixels.get_pixel(x, y) != expected:
						return false
			if atlas.frames[name].get("pivot", {}) != entries[name].pivot:
				return false
			render_texture = region.atlas
			entries[name].rect = [region.region.position.x, region.region.position.y, region.region.size.x, region.region.size.y]
	var stage := view._terrain_root.get_node("CareClearing")
	stage.get_node("BoundaryForest").hide()
	stage.get_node("PathsidePlanting").hide()
	var group := Node3D.new()
	group.name = "FoliageCompiledReview" if not candidate_path.is_empty() else "FoliageSourceReview"
	group.set_meta("review_only", true)
	group.set_meta("source_sha256", source.sha256)
	stage.add_child(group)
	# All tree roots remain outside the playable field. The rear row and staggered
	# near row create genuine depth while their illustrated faces stay camera-aligned.
	for row: int in 2:
		for index: int in 10:
			var x := -7.0 + index*6.0 + row*2.0
			var z := -3.5-row*7.0 + sin(index*1.7)*0.7
			var tree := _card(render_texture, entries.tree, 0.020+row*0.003)
			tree.name = "RearTree_%d_%d" % [row,index]
			tree.position = Vector3(x,0,z)
			tree.modulate = Color(0.78,0.86,0.81) if row == 1 else Color.WHITE
			group.add_child(tree)
	for side: int in [-1,1]:
		for index: int in 11:
			var z := 5.0 + index*4.0 + (0.8 if side<0 else 0.0)
			var center := 20.5+sin(z*0.19)*1.7
			var type := "reeds" if index%3 == 0 else "hedge"
			var card := _card(render_texture, entries[type], 0.0055 if type == "reeds" else 0.0065)
			card.name = "SoftPlant_%d_%d" % [side,index]
			card.position = Vector3(center+side*(5.6+sin(index*2.3)*0.5),0.02,z)
			card.flip_h = side<0
			card.set_meta("traversable", true)
			group.add_child(card)
	return true

static func _card(texture: Texture2D, entry: Dictionary, pixel_size: float) -> Sprite3D:
	var sprite := Sprite3D.new()
	sprite.texture = texture
	sprite.region_enabled = true
	var rect: Array = entry.rect
	sprite.region_rect = Rect2(rect[0],rect[1],rect[2],rect[3])
	sprite.offset = Vector2(rect[2]*(0.5-float(entry.pivot.x)),rect[3]*(float(entry.pivot.y)-0.5))
	sprite.pixel_size = pixel_size
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	sprite.alpha_scissor_threshold = 0.5
	sprite.shaded = false
	ScreenAlignedSprite.apply(sprite)
	return sprite
