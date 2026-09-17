extends SceneTree

## Called only inside the Python suite's isolated copied project. No real art,
## catalog, receipts, or companion saves are modified by this probe.

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var folder := ProjectSettings.localize_path(String(args[args.find("--candidate") + 1]))
	var metadata := AssetResourceLibrary.read_json(folder.path_join("candidate.json"))
	var name := "background.png" if metadata.kind == "arena" else "atlas.png"
	var raw := AssetResourceLibrary.load_payload_texture(folder.path_join(name))
	var imported := load(folder.path_join(name)) as Texture2D
	if raw == null or imported == null or raw.get_size() == imported.get_size():
		printerr("The fixture must have genuinely different PNG import size settings: %s raw=%s imported=%s" % [folder, raw.get_size() if raw != null else Vector2.ZERO, imported.get_size() if imported != null else Vector2.ZERO])
		quit(1)
		return
	var scene := load("res://scenes/asset_review_scene.tscn") as PackedScene
	var review := scene.instantiate()
	root.add_child(review)
	# _ready reads the same --candidate argument and loads exactly once.
	var shown: Texture2D
	match metadata.kind:
		"animation":
			var frames: SpriteFrames = review._library.frames
			shown = (frames.get_frame_texture(frames.get_animation_names()[0], 0) as AtlasTexture).atlas
			var rebuilt := CompanionAssetLibrary.build_folder(folder, true)
			var rebuilt_frames: SpriteFrames = rebuilt.frames
			var rebuilt_texture := (rebuilt_frames.get_frame_texture(rebuilt_frames.get_animation_names()[0], 0) as AtlasTexture).atlas
			if rebuilt_texture.get_image().get_data() != raw.get_image().get_data():
				printerr("Animation export used mutable import settings")
				quit(1)
				return
		"atlas":
			shown = review._atlas_sprite.texture
		"tileset":
			shown = (review._tiles.tile_set.get_source(0) as TileSetAtlasSource).texture
		"arena":
			shown = review._arena_view._background
	if shown == null or shown.get_image().get_data() != raw.get_image().get_data():
		printerr("Review pixels differ from the hash-bound raw PNG payload")
		quit(1)
		return
	print("Imported PNG differs; reviewed native and raw payload pixels agree")
	review.free()
	quit(0)
