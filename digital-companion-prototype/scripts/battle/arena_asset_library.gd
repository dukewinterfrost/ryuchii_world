class_name ArenaAssetLibrary
extends RefCounted

## Immutable runtime resolver for arena candidates. Live play accepts only an
## approved catalog entry whose key, metadata, native Resource, JSON manifest,
## payload hashes, encounter identity, and Environment dependency all agree.

const CATALOG := "res://assets/runtime-catalog.json"
const MAX_PACKAGE_FILES := EnvironmentPresentationContract.MAX_ACTIVE_TEXTURES + 24
const MAX_NATIVE_BYTES := 2 * 1024 * 1024


static func resolve_approved(encounter: Dictionary, catalog_path := CATALOG,
		root_prefix := "res://") -> Dictionary:
	var catalog := AssetResourceLibrary.read_json(catalog_path)
	return resolve_approved_from_catalog(encounter, catalog, root_prefix)


static func resolve_approved_from_catalog(encounter: Dictionary, catalog: Dictionary,
		root_prefix: String) -> Dictionary:
	var problem := _encounter_problem(encounter)
	if not problem.is_empty():
		return {"ok": false, "error": problem}
	var entries: Variant = catalog.get("assets")
	if catalog.get("schemaVersion") != 1 or not entries is Dictionary:
		return {"ok": false, "error": "The approved runtime catalog is unavailable."}
	var arena_id := String(encounter.arenaId)
	var entry: Variant = entries.get(arena_id)
	if not entry is Dictionary or String(entry.get("kind", "")) != "arena" \
			or String(entry.get("assetId", "")) != arena_id:
		return {"ok": false, "error": "This encounter has no approved arena catalog entry."}
	var relative := String(entry.get("path", ""))
	if not _safe_relative(relative):
		return {"ok": false, "error": "The approved arena catalog path is invalid."}
	var folder := root_prefix.trim_suffix("/") + "/" + relative.trim_prefix("/")
	return _resolve_package(encounter, folder, entry, false, catalog, root_prefix)


static func resolve_isolated_dev_fixture(encounter: Dictionary, folder: String,
		expected_content_sha256: String, isolated_authorized: bool) -> Dictionary:
	if not isolated_authorized:
		return {"ok": false, "error": "Arena review fixtures require isolated authorization."}
	if not folder.begins_with("res://tests/fixtures/regions/") or not folder.ends_with("/review/arena") \
			or folder.contains("\\") or ".." in folder.split("/"):
		return {"ok": false, "error": "The arena review package path is invalid."}
	var expected := {"assetId": String(encounter.get("arenaId", "")),
		"contentSha256": expected_content_sha256}
	return _resolve_package(encounter, folder, expected, true, {}, "")


static func _resolve_package(encounter: Dictionary, folder: String, expected: Dictionary,
		dev_fixture: bool, catalog: Dictionary, root_prefix: String) -> Dictionary:
	var problem := _encounter_problem(encounter)
	if not problem.is_empty():
		return {"ok": false, "error": problem}
	var metadata := AssetResourceLibrary.read_json(folder.path_join("candidate.json"))
	var manifest := AssetResourceLibrary.read_json(folder.path_join("arena.json"))
	if not _metadata_matches(metadata, expected, String(encounter.arenaId), dev_fixture):
		return {"ok": false, "error": "The arena candidate identity or approval state is invalid."}
	if not _payload_hashes_match(folder, metadata.get("files")):
		return {"ok": false, "error": "The arena candidate payload failed integrity validation."}
	if not _manifest_matches(manifest, encounter, metadata):
		return {"ok": false, "error": "The arena manifest does not match its encounter or candidate."}
	if not _native_matches(folder, metadata, manifest):
		return {"ok": false, "error": "The arena native Resource failed identity validation."}
	var environment_pin: Dictionary = manifest.environment
	var environment_package: Dictionary = {}
	if dev_fixture:
		environment_package = EnvironmentAssetLibrary.activate_isolated_dev_fixture(
			environment_pin, folder.path_join("environment"), true)
	else:
		# The same catalog must contain the exact dependency. Activation rechecks
		# its candidate, native Resource, manifest, and every texture hash.
		environment_package = EnvironmentAssetLibrary.activate_pin_from_catalog(
			environment_pin, catalog, root_prefix)
	if environment_package.is_empty():
		return {"ok": false, "error": "The arena's pinned Environment dependency is unavailable."}
	EnvironmentAssetLibrary.clear_active()
	var arena := manifest.duplicate(true)
	# This runtime envelope pin is not authored gameplay geometry. It lets replay
	# validation bind the embedded arena bytes to the candidate package hash.
	arena["contentSha256"] = String(metadata.contentSha256)
	return {"ok": true, "arena": arena, "source": "isolated-dev-fixture" if dev_fixture else "approved-catalog",
		"notice": "Unpromoted environment fixture · isolated review only" if dev_fixture else "",
		"encounterId": String(encounter.encounterId), "regionId": String(encounter.regionId),
		"contentSha256": String(metadata.contentSha256), "environmentPackage": environment_package}


static func _encounter_problem(encounter: Dictionary) -> String:
	if not encounter.get("ok", false) or not encounter.has_all(["encounterId", "arenaId", "regionId"]):
		return "The contextual encounter identity is invalid."
	for key: String in ["encounterId", "arenaId", "regionId"]:
		var value := String(encounter.get(key, ""))
		if value.is_empty() or value.length() > 96 or value.contains("\\") or ".." in value.split("/"):
			return "The contextual encounter identity is invalid."
	return ""


static func _metadata_matches(metadata: Dictionary, expected: Dictionary, arena_id: String,
		dev_fixture: bool) -> bool:
	if metadata.get("schemaVersion") != 1 or metadata.get("kind") != "arena" \
			or String(metadata.get("assetId", "")) != arena_id \
			or String(expected.get("assetId", "")) != arena_id \
			or String(metadata.get("revision", "")) != String(expected.get("revision", metadata.get("revision", ""))) \
			or String(metadata.get("contentSha256", "")) != String(expected.get("contentSha256", "")) \
			or EnvironmentAssetLibrary.metadata_content_sha256(metadata) != String(metadata.get("contentSha256", "")) \
			or metadata.get("nativeResources") != true:
		return false
	if dev_fixture:
		return metadata.get("devFixture") == true and metadata.get("reviewStatus") == "pending-human-review"
	return metadata.get("devFixture", false) == false and metadata.get("reviewStatus") == "approved"


static func _manifest_matches(manifest: Dictionary, encounter: Dictionary,
		metadata: Dictionary) -> bool:
	if not BattleArena.validate(manifest).is_empty() or not manifest.has("environment"):
		return false
	if String(manifest.get("assetId", "")) != String(encounter.arenaId) \
			or String(manifest.get("revision", "")) != String(metadata.revision) \
			or String(manifest.get("regionId", "")) != String(encounter.regionId):
		return false
	var pin: Variant = manifest.environment
	return pin is Dictionary and EnvironmentPresentationContract.valid_pin(pin) \
		and String(metadata.get("environmentContentSha256", "")) == String(pin.contentSha256)


static func _payload_hashes_match(folder: String, files: Variant) -> bool:
	if not files is Dictionary or files.is_empty() or files.size() > MAX_PACKAGE_FILES:
		return false
	if not files.has_all(["arena.json", "arena.tres"]):
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


static func _native_matches(folder: String, metadata: Dictionary, manifest: Dictionary) -> bool:
	var path := folder.path_join("arena.tres")
	if not ResourceLoader.exists(path):
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > MAX_NATIVE_BYTES:
		return false
	file.close()
	var native := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if native == null or not native.has_meta("candidate_identity") or not native.has_meta("arena_manifest"):
		return false
	var identity: Variant = native.get_meta("candidate_identity")
	var native_manifest: Variant = native.get_meta("arena_manifest")
	if not identity is Dictionary or not native_manifest is Dictionary or native_manifest != manifest:
		return false
	for field: String in ["assetId", "revision", "kind", "compilerVersion", "planSha256", "buildIdentity"]:
		if String(metadata.get(field, "")).is_empty() \
				or String(identity.get(field, "")) != String(metadata.get(field, "")):
			return false
	return String(identity.get("kind", "")) == "arena"


static func _safe_relative(value: String) -> bool:
	return not value.is_empty() and not value.is_absolute_path() and not value.contains("\\") \
		and value not in [".", ".."] and ".." not in value.split("/")
