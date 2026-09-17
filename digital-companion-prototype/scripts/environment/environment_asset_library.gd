class_name EnvironmentAssetLibrary
extends RefCounted

## Resolves immutable environment pins. Callers receive one verified active
## package rather than a mutable catalog entry or an unpinned folder.

const CATALOG := "res://assets/runtime-catalog.json"
const MAX_NATIVE_METADATA_BYTES := 2 * 1024 * 1024

static var _active_package: Dictionary = {}


static func activate_pin(pin: Dictionary, catalog_path := CATALOG) -> Dictionary:
	var catalog := AssetResourceLibrary.read_json(catalog_path)
	return activate_pin_from_catalog(pin, catalog, "res://")


static func activate_pin_from_catalog(pin: Dictionary, catalog: Dictionary, root_prefix: String) -> Dictionary:
	# Unload first: a failed switch must not leave the previous biome active.
	clear_active()
	if not EnvironmentPresentationContract.valid_pin(pin):
		return {}
	var assets: Variant = catalog.get("assets")
	if catalog.get("schemaVersion") != 1 or not assets is Dictionary:
		return {}
	var entry: Variant = assets.get(String(pin.assetId))
	if not entry is Dictionary or String(entry.get("kind", "")) != "environment":
		return {}
	for field: String in ["assetId", "revision", "contentSha256"]:
		if String(entry.get(field, "")) != String(pin[field]):
			return {}
	var relative := String(entry.get("path", ""))
	if not _safe_relative(relative):
		return {}
	var folder := root_prefix.trim_suffix("/") + "/" + relative.trim_prefix("/")
	var metadata := AssetResourceLibrary.read_json(folder.path_join("candidate.json"))
	var manifest := AssetResourceLibrary.read_json(folder.path_join("environment.json"))
	if not _metadata_matches_pin(metadata, pin) or not _manifest_matches_pin(manifest, pin):
		return {}
	if not _payload_hashes_match(folder, metadata.get("files", {})):
		return {}
	if not _native_identity_matches(folder, metadata, manifest):
		return {}
	var textures := _load_textures(folder, manifest.get("textures", {}))
	if textures.is_empty():
		return {}
	_active_package = {
		"pin": pin.duplicate(true),
		"manifest": manifest.duplicate(true),
		"textures": textures,
		"folder": folder,
	}
	return active_package()


static func activate_isolated_dev_fixture(pin: Dictionary, folder: String, isolated_authorized: bool) -> Dictionary:
	## Hash-verified fixture loader for isolated review/test surfaces only.
	## Current fixtures carry native identity metadata; legacy raw fixtures remain
	## supported here only while they are explicitly dev-only and unapproved.
	## Production activation remains approved-catalog gated in activate_pin().
	clear_active()
	if not isolated_authorized or not EnvironmentPresentationContract.valid_pin(pin):
		return {}
	if folder.contains("\\") or ".." in folder.split("/"):
		return {}
	var metadata := AssetResourceLibrary.read_json(folder.path_join("candidate.json"))
	if metadata.get("schemaVersion") != 1 or metadata.get("kind") != "environment" \
			or metadata.get("devFixture") != true or metadata.get("nativeResources") not in [true, false] \
			or metadata.get("reviewStatus") == "approved":
		return {}
	for field: String in ["assetId", "revision", "contentSha256"]:
		if String(metadata.get(field, "")) != String(pin[field]):
			return {}
	if metadata_content_sha256(metadata) != String(pin.contentSha256) or not _payload_hashes_match(folder, metadata.get("files", {})):
		return {}
	var manifest := AssetResourceLibrary.read_json(folder.path_join("environment.json"))
	if not _manifest_matches_pin(manifest, pin):
		return {}
	if metadata.get("nativeResources") == true and not _native_identity_matches(folder, metadata, manifest):
		return {}
	var bindings: Dictionary = manifest.get("textures", {}) if manifest.get("textures") is Dictionary else {}
	if bindings.is_empty() or not metadata.files.has("environment.json"):
		return {}
	for relative: Variant in bindings.values():
		if not metadata.files.has(String(relative)):
			return {}
	var textures := _load_textures(folder, bindings)
	if textures.is_empty():
		return {}
	_active_package = {"pin": pin.duplicate(true), "manifest": manifest.duplicate(true),
		"textures": textures, "folder": folder, "devFixture": true,
		"nativeResources": metadata.get("nativeResources") == true}
	return active_package()


static func active_package() -> Dictionary:
	return _active_package.duplicate(true)


static func clear_active() -> void:
	_active_package.clear()


static func active_pin() -> Dictionary:
	return (_active_package.get("pin", {}) as Dictionary).duplicate(true)


static func catalog_binding_matches(pin: Dictionary, catalog: Dictionary) -> bool:
	if not EnvironmentPresentationContract.valid_pin(pin):
		return false
	var entries: Variant = catalog.get("assets")
	if catalog.get("schemaVersion") != 1 or not entries is Dictionary:
		return false
	var entry: Variant = entries.get(String(pin.assetId))
	return entry is Dictionary and String(entry.get("kind", "")) == "environment" \
		and String(entry.get("assetId", "")) == String(pin.assetId) \
		and String(entry.get("revision", "")) == String(pin.revision) \
		and String(entry.get("contentSha256", "")) == String(pin.contentSha256) \
		and _safe_relative(String(entry.get("path", "")))


static func _metadata_matches_pin(metadata: Dictionary, pin: Dictionary) -> bool:
	return metadata.get("schemaVersion") == 1 and metadata.get("kind") == "environment" \
		and String(metadata.get("assetId", "")) == String(pin.assetId) \
		and String(metadata.get("revision", "")) == String(pin.revision) \
		and String(metadata.get("contentSha256", "")) == String(pin.contentSha256) \
		and metadata_content_sha256(metadata) == String(pin.contentSha256) \
		and metadata.get("nativeResources") == true \
		and metadata.get("files") is Dictionary and not metadata.files.is_empty()


static func metadata_content_sha256(metadata: Dictionary) -> String:
	var signed := metadata.duplicate(true)
	signed.erase("sourcePlan")
	signed.erase("contentSha256")
	# Mirrors sprite_pipeline.common.canonical: sorted compact UTF-8 JSON plus LF.
	return "sha256:" + (JSON.stringify(_canonical_numbers(signed), "", true, true) + "\n").sha256_text()


static func _canonical_numbers(value: Variant) -> Variant:
	# Godot's JSON parser represents every JSON number as float. Restore integral
	# values before hashing so Python's canonical `1` and runtime `1.0` agree.
	if value is float and is_finite(value) and is_equal_approx(value, roundf(value)):
		return int(value)
	if value is Array:
		var result: Array = []
		for item: Variant in value:
			result.append(_canonical_numbers(item))
		return result
	if value is Dictionary:
		var result := {}
		for key: Variant in value:
			result[key] = _canonical_numbers(value[key])
		return result
	return value


static func _manifest_matches_pin(manifest: Dictionary, pin: Dictionary) -> bool:
	return manifest.get("schemaVersion") == 1 and manifest.get("kind") == "environment" \
		and String(manifest.get("assetId", "")) == String(pin.assetId) \
		and String(manifest.get("revision", "")) == String(pin.revision) \
		and EnvironmentPresentationContract.validate_profile(manifest)


static func _payload_hashes_match(folder: String, files: Variant) -> bool:
	if not files is Dictionary or files.size() > EnvironmentPresentationContract.MAX_ACTIVE_TEXTURES + 8:
		return false
	for relative_value: Variant in files:
		var relative := String(relative_value)
		var expected := String(files[relative_value])
		if not _safe_relative(relative) or not expected.begins_with("sha256:") or expected.length() != 71:
			return false
		var path := folder.path_join(relative)
		if not FileAccess.file_exists(path) or "sha256:" + FileAccess.get_sha256(path) != expected:
			return false
	return true


static func _native_identity_matches(folder: String, metadata: Dictionary, manifest: Dictionary) -> bool:
	var native_path := folder.path_join("environment.tres")
	if not ResourceLoader.exists(native_path):
		return false
	var native_file := FileAccess.open(native_path, FileAccess.READ)
	if native_file == null or native_file.get_length() > MAX_NATIVE_METADATA_BYTES:
		return false
	native_file.close()
	var native := ResourceLoader.load(native_path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if native == null or not native.has_meta("candidate_identity"):
		return false
	var identity: Variant = native.get_meta("candidate_identity")
	if not identity is Dictionary:
		return false
	for field: String in ["assetId", "revision", "kind", "compilerVersion", "planSha256", "buildIdentity"]:
		if String(identity.get(field, "")) != String(metadata.get(field, "")):
			return false
	var paths: Variant = native.get_meta("environment_texture_paths", {})
	var hashes: Variant = native.get_meta("environment_texture_hashes", {})
	var dependencies: Variant = metadata.get("nativeDependencies", {})
	var files: Variant = metadata.get("files", {})
	if native.get_meta("environment_manifest", {}) != manifest or paths != manifest.get("textures", {}):
		return false
	if not paths is Dictionary or not hashes is Dictionary or not dependencies is Dictionary \
			or not files is Dictionary or hashes != dependencies:
		return false
	var unique_paths := {}
	for role: Variant in paths:
		var relative := String(paths[role])
		if not _safe_relative(relative) or not relative.begins_with("textures/") \
				or files.get(relative, "") != hashes.get(relative, ""):
			return false
		unique_paths[relative] = true
	return unique_paths.size() == hashes.size()


static func _load_textures(folder: String, bindings: Variant) -> Dictionary:
	if not bindings is Dictionary or bindings.is_empty() or bindings.size() > EnvironmentPresentationContract.MAX_ACTIVE_TEXTURES:
		return {}
	var result := {}
	for role_value: Variant in bindings:
		var role := String(role_value)
		var relative := String(bindings[role_value])
		if role.is_empty() or not relative.begins_with("textures/") or not _safe_relative(relative):
			return {}
		var texture := AssetResourceLibrary.load_payload_texture(folder.path_join(relative))
		if texture == null:
			return {}
		result[role] = texture
	return result


static func _safe_relative(value: String) -> bool:
	return not value.is_empty() and not value.is_absolute_path() and not value.contains("\\") \
		and value not in [".", ".."] and ".." not in value.split("/")
