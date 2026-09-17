extends SceneTree

## Independent promotion-time native-resource gate. Loading a candidate's .tres
## in the engine proves it is not a dummy file and verifies that its embedded
## manifest/dependency metadata belongs to the exact compiler build under review.
## Environment dependencies are then hash-checked, decoded from their raw PNG
## payloads, and configured through the real renderer. A loadable .tres alone is
## deliberately insufficient evidence.

const MAX_ENVIRONMENT_NATIVE_BYTES := 2 * 1024 * 1024

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var index := args.find("--candidate")
	if index < 0 or index + 1 >= args.size():
		_fail("Usage: --candidate ABSOLUTE_CANDIDATE_DIRECTORY")
		return
	var folder := String(args[index + 1]).trim_suffix("/")
	var candidate := AssetResourceLibrary.read_json(folder.path_join("candidate.json"))
	if candidate.is_empty() or not folder.is_absolute_path():
		_fail("Native probe needs an absolute candidate directory and candidate.json")
		return
	var kind := String(candidate.get("kind", ""))
	var filename := {
		"animation": "spriteframes.tres",
		"atlas": "atlasframes.tres",
		"tileset": "tileset.tres",
		"arena": "arena.tres",
		"environment": "environment.tres",
		"habitat": "habitat.tres",
	}.get(kind, "") as String
	if filename.is_empty():
		_fail("Unsupported native resource kind: " + kind)
		return
	var native_path := folder.path_join(filename)
	if kind == "environment":
		var native_file := FileAccess.open(native_path, FileAccess.READ)
		if native_file == null or native_file.get_length() > MAX_ENVIRONMENT_NATIVE_BYTES:
			_fail("Native Environment resource exceeds compact metadata limit")
			return
		native_file.close()
	var localized := ProjectSettings.localize_path(native_path)
	var resource := ResourceLoader.load(localized, "", ResourceLoader.CACHE_MODE_IGNORE)
	if resource == null:
		_fail("Native resource could not be loaded: " + filename)
		return
	if kind in ["animation", "atlas"] and not resource is SpriteFrames:
		_fail("Expected SpriteFrames for " + kind)
		return
	if kind == "tileset" and not resource is TileSet:
		_fail("Expected TileSet")
		return
	var expected_identity := {
		"assetId": String(candidate.get("assetId", "")),
		"revision": String(candidate.get("revision", "")),
		"kind": kind,
		"compilerVersion": String(candidate.get("compilerVersion", "")),
		"planSha256": String(candidate.get("planSha256", "")),
		"buildIdentity": String(candidate.get("buildIdentity", "")),
	}
	if not resource.has_meta("candidate_identity") or resource.get_meta("candidate_identity") != expected_identity:
		_fail("Native resource build identity differs from candidate")
		return
	if kind == "environment":
		var environment := AssetResourceLibrary.read_json(folder.path_join("environment.json"))
		if resource.get_meta("environment_manifest", {}) != environment:
			_fail("Native Environment manifest metadata differs")
			return
		var paths: Variant = resource.get_meta("environment_texture_paths", {})
		var hashes: Variant = resource.get_meta("environment_texture_hashes", {})
		var expected_dependencies: Variant = candidate.get("nativeDependencies", {})
		var files: Variant = candidate.get("files", {})
		if not paths is Dictionary or paths != environment.get("textures", {}):
			_fail("Native Environment texture path metadata differs")
			return
		if not hashes is Dictionary or not expected_dependencies is Dictionary or hashes != expected_dependencies:
			_fail("Native Environment dependency hash metadata differs")
			return
		if not files is Dictionary or hashes.size() != _unique_path_count(paths):
			_fail("Native Environment dependency set differs")
			return
		var textures := {}
		for role: String in paths:
			var relative := String(paths[role])
			if not _safe_texture_path(relative) or not hashes.has(relative) or files.get(relative, "") != hashes[relative]:
				_fail("Native Environment texture binding is unsafe or unbound: " + role)
				return
			var absolute := folder.path_join(relative)
			if not FileAccess.file_exists(absolute) or "sha256:" + FileAccess.get_sha256(absolute) != hashes[relative]:
				_fail("Native Environment texture hash differs: " + role)
				return
			var texture := AssetResourceLibrary.load_payload_texture(absolute)
			if texture == null:
				_fail("Native Environment texture cannot be decoded: " + role)
				return
			textures[role] = texture
		var render_probe := EnvironmentView3D.new()
		if not render_probe.configure(environment, folder, textures):
			render_probe.free()
			_fail("Native Environment dependencies cannot configure EnvironmentView3D")
			return
		render_probe.free()
	elif kind == "habitat":
		if resource.get_meta("habitat_manifest", {}) != AssetResourceLibrary.read_json(folder.path_join("habitat.json")):
			_fail("Native Habitat manifest metadata differs")
			return
	elif kind == "arena":
		var arena := AssetResourceLibrary.read_json(folder.path_join("arena.json"))
		if resource.get_meta("arena_manifest", {}) != arena:
			_fail("Native Arena manifest metadata differs")
			return
		if arena.has("background") and not resource.get_meta("background_texture", null) is Texture2D:
			_fail("Native Arena background texture is missing")
			return
	elif kind == "animation":
		if not resource.get_meta("asset_library", {}) is Dictionary:
			_fail("Native animation asset library metadata is missing")
			return
	elif kind == "atlas":
		var atlas := AssetResourceLibrary.read_json(folder.path_join("atlas.json"))
		if resource.get_meta("source_manifest", {}) != atlas:
			_fail("Native atlas source metadata differs")
			return
		var expected := AssetResourceLibrary.load_payload_texture(folder.path_join("atlas.png"))
		var frames := resource as SpriteFrames
		for entry: String in atlas.get("frames", {}):
			if not frames.has_animation(entry) or frames.get_frame_count(entry) != 1:
				_fail("Native atlas entry is missing: " + entry)
				return
			var region := frames.get_frame_texture(entry, 0) as AtlasTexture
			var rect: Dictionary = atlas.frames[entry].frame
			if region == null or region.atlas == null or region.region != Rect2(rect.x, rect.y, rect.w, rect.h):
				_fail("Native atlas region differs: " + entry)
				return
			var decoded := region.atlas.get_image()
			if expected == null or decoded == null or decoded.get_size() != expected.get_image().get_size() or decoded.get_data() != expected.get_image().get_data():
				_fail("Native atlas pixels differ from PNG payload: " + entry)
				return
	print("NATIVE_RESOURCE_PROBE_OK:" + String(candidate.get("buildIdentity", "")))
	quit(0)


func _fail(message: String) -> void:
	printerr(message)
	quit(1)


func _safe_texture_path(relative: String) -> bool:
	return not relative.is_empty() and not relative.is_absolute_path() \
		and relative.begins_with("textures/") and not relative.contains("\\") \
		and ".." not in relative.split("/")


func _unique_path_count(paths: Dictionary) -> int:
	var unique := {}
	for relative: Variant in paths.values():
		unique[String(relative)] = true
	return unique.size()
