extends SceneTree

## Native build step; only writes into the explicitly supplied candidate folder.
## Environment textures remain immutable raw PNG payloads beside the resource.
## The .tres stores only portable relative bindings and their exact hashes.

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var index := args.find("--candidate")
	if index < 0 or index + 1 >= args.size():
		_fail("Usage: --candidate ABSOLUTE_CANDIDATE_DIRECTORY --asset-review")
		return
	var folder := String(args[index + 1]).trim_suffix("/")
	var candidate := AssetResourceLibrary.read_json(folder.path_join("candidate.json"))
	if candidate.is_empty() or not folder.is_absolute_path():
		_fail("Expected an absolute candidate directory containing candidate.json")
		return
	var kind := String(candidate.get("kind", ""))
	var resource: Resource
	var output := ""
	if kind == "animation":
		# Share one lossless embedded atlas across all frames. Raw ImageTexture
		# serialization exceeds the candidate size limit for full animation sets.
		var atlas := AssetResourceLibrary.read_json(folder.path_join("atlas.json"))
		var animation := AssetResourceLibrary.read_json(folder.path_join("animation-set.json"))
		var library := CompanionAssetLibrary.build_from_manifests(atlas, animation, _atlas_texture(folder.path_join("atlas.png")))
		if library.is_empty():
			_fail("Animation candidate did not validate")
			return
		resource = library.frames
		library.erase("frames")
		resource.set_meta("asset_library", library)
		output = "spriteframes.tres"
	elif kind == "tileset":
		var manifest := AssetResourceLibrary.read_json(folder.path_join("tileset.json"))
		var texture := _texture(folder.path_join("atlas.png"))
		var result := AssetResourceLibrary.build_tileset(manifest, texture)
		if not result.ok:
			_fail("; ".join(result.errors))
			return
		resource = result.tileset
		output = "tileset.tres"
	elif kind == "atlas":
		var atlas := AssetResourceLibrary.read_json(folder.path_join("atlas.json"))
		var texture := _atlas_texture(folder.path_join("atlas.png"))
		var animation := {"revision": candidate.revision, "clips": {}}
		for name: String in atlas.get("frames", {}):
			animation.clips[name] = {"kind": "hold", "frames": [{"atlasFrame": name, "durationMs": 1000, "pivot": atlas.frames[name].get("pivot", {"x": 0.5, "y": 0.5})}]}
		var library := CompanionAssetLibrary.build_from_manifests(atlas, animation, texture)
		if library.is_empty():
			_fail("Atlas candidate did not validate")
			return
		resource = library.frames
		resource.set_meta("source_manifest", atlas)
		output = "atlasframes.tres"
	elif kind == "arena":
		var arena := AssetResourceLibrary.read_json(folder.path_join("arena.json"))
		if arena.is_empty():
			_fail("Arena candidate is missing arena.json")
			return
		var problem := BattleArena.validate(arena)
		if not problem.is_empty():
			_fail("Arena runtime validation: " + problem)
			return
		resource = Resource.new()
		resource.set_meta("arena_manifest", arena)
		if arena.has("background"):
			if not ArenaView._safe_segment(String(arena.background)):
				_fail("Arena background must be a filename in the candidate directory")
				return
			var background := _texture(folder.path_join(String(arena.background)))
			if background == null:
				_fail("Arena background texture is missing or invalid")
				return
			resource.set_meta("background_texture", background)
		output = "arena.tres"
	elif kind == "environment":
		var environment := AssetResourceLibrary.read_json(folder.path_join("environment.json"))
		if environment.is_empty():
			_fail("Environment candidate is missing environment.json")
			return
		var texture_package := _environment_texture_package(folder, environment.get("textures", {}))
		if texture_package.is_empty():
			_fail("Environment candidate has no valid external textures")
			return
		var expected_dependencies: Variant = candidate.get("nativeDependencies", {})
		if not expected_dependencies is Dictionary or expected_dependencies != texture_package.hashes:
			_fail("Environment external texture hashes differ from candidate metadata")
			return
		# Native export is the final renderability gate used by the approval flow.
		# Exercise the same manifest-driven renderer the reviewer/runtime will use.
		var render_probe := EnvironmentView3D.new()
		if not render_probe.configure(environment, folder, texture_package.textures):
			render_probe.free()
			_fail("Environment candidate cannot be rendered by EnvironmentView3D")
			return
		render_probe.free()
		resource = Resource.new()
		resource.set_meta("environment_manifest", environment)
		resource.set_meta("environment_texture_paths", texture_package.paths)
		resource.set_meta("environment_texture_hashes", texture_package.hashes)
		output = "environment.tres"
	elif kind == "habitat":
		var habitat := AssetResourceLibrary.read_json(folder.path_join("habitat.json"))
		if habitat.is_empty() or not habitat.get("environment", {}) is Dictionary or not habitat.environment.has("contentSha256"):
			_fail("Habitat candidate needs habitat.json with a pinned Environment content hash")
			return
		resource = Resource.new()
		resource.set_meta("habitat_manifest", habitat)
		output = "habitat.tres"
	else:
		_fail("Unsupported candidate kind: " + kind)
		return
	resource.set_meta("candidate_identity", {
		"assetId": String(candidate.get("assetId", "")),
		"revision": String(candidate.get("revision", "")),
		"kind": kind,
		"compilerVersion": String(candidate.get("compilerVersion", "")),
		"planSha256": String(candidate.get("planSha256", "")),
		"buildIdentity": String(candidate.get("buildIdentity", "")),
	})
	AssetResourceLibrary.assign_stable_ids(resource)
	var error := ResourceSaver.save(resource, folder.path_join(output), ResourceSaver.FLAG_RELATIVE_PATHS)
	if error != OK:
		_fail("Native resource write failed: " + error_string(error))
		return
	print(JSON.stringify({"ok": true, "resource": output}))
	quit(0)


func _texture(path: String) -> Texture2D:
	return AssetResourceLibrary.load_payload_texture(path)


func _atlas_texture(path: String) -> Texture2D:
	# Lossless, self-contained storage avoids serializing millions of raw RGBA
	# integers into a .tres. The payload PNG and reviewed pixels stay unchanged.
	var original := _texture(path)
	if original == null:
		return null
	var texture := PortableCompressedTexture2D.new()
	texture.keep_compressed_buffer = true
	texture.create_from_image(original.get_image(), PortableCompressedTexture2D.COMPRESSION_MODE_LOSSLESS)
	return texture


func _environment_texture_package(folder: String, bindings: Variant) -> Dictionary:
	if not bindings is Dictionary:
		return {}
	var paths := {}
	var hashes := {}
	var textures := {}
	for role: String in bindings:
		var relative := String(bindings[role])
		if relative.is_absolute_path() or not relative.begins_with("textures/") or relative.contains("\\") or ".." in relative.split("/"):
			return {}
		var absolute := folder.path_join(relative)
		if not FileAccess.file_exists(absolute):
			return {}
		var texture := _texture(absolute)
		if texture == null:
			return {}
		paths[role] = relative
		textures[role] = texture
		hashes[relative] = "sha256:" + FileAccess.get_sha256(absolute)
	return {"paths": paths, "hashes": hashes, "textures": textures}


func _fail(message: String) -> void:
	printerr(message)
	quit(1)
