class_name HabitatAssetLibrary
extends RefCounted

## Resolves one home region into an approved environment package or a
## deterministic 2D engineering fallback. Review fixtures are opt-in and can
## never silently become production content.

const CATALOG := "res://assets/runtime-catalog.json"
const DEV_INDEX := "res://tests/fixtures/regions/index.json"
const DEV_REVISION := "2026-09-12.001"


static func resolve_region(region_value: String, allow_dev_fixtures := false) -> Dictionary:
	# Region resolution is an activation boundary. Never let the previously
	# selected environment remain globally active when the next habitat or its
	# presentation dependency fails verification.
	EnvironmentAssetLibrary.clear_active()
	var region_id := HabitatRules.resolve_region_alias(region_value)
	if not HabitatRules.region_is_known(region_id):
		return {"ok": false, "error": "Unknown home region.", "region_id": region_id}
	var approved := _approved_package(region_id)
	if bool(approved.get("ok", false)):
		return approved
	if allow_dev_fixtures:
		var fixture := _dev_fixture_package(region_id)
		if bool(fixture.get("ok", false)):
			return fixture
	var reason := String(approved.get("error", "No approved environment package is available."))
	return {
		"ok": true,
		"region_id": region_id,
		"home_name": String(HabitatRules.REGION_HOMES[region_id].name),
		"mode": "fallback-2d",
		"notice": reason + " The deterministic 2D habitat is in use.",
		"habitat": fallback_manifest(region_id),
		"environment_package": {},
	}


static func fallback_manifest(region_value: String) -> Dictionary:
	var region_id := HabitatRules.resolve_region_alias(region_value)
	var habitat_id := String(HabitatRules.REGION_HOMES.get(region_id, HabitatRules.REGION_HOMES[HabitatRules.DEFAULT_REGION]).habitat_id)
	return {
		"schemaVersion": 1,
		"kind": "habitat",
		"assetId": habitat_id,
		"revision": "fallback-v1",
		"environment": {},
		"grid": {"columns": 40, "rows": 48, "cellSize": 32},
		"blockers": [],
		"spawn": [20, 24],
		"wasteAnchors": [[8, 20], [20, 28], [32, 20]],
		"decorationZones": [{"id": "main", "rect": [1, 1, 38, 46]}],
		"staticPlacements": [],
	}


static func validate_manifest(manifest: Dictionary, expected_asset_id := "") -> bool:
	if manifest.get("schemaVersion") != 1 or manifest.get("kind") != "habitat":
		return false
	if not expected_asset_id.is_empty() and String(manifest.get("assetId", "")) != expected_asset_id:
		return false
	if String(manifest.get("assetId", "")).is_empty() or String(manifest.get("revision", "")).is_empty():
		return false
	var grid: Variant = manifest.get("grid")
	if not grid is Dictionary or grid.size() != 3 or int(grid.get("columns", 0)) != 40 \
			or int(grid.get("rows", 0)) != 48 or int(grid.get("cellSize", 0)) != 32:
		return false
	for key: String in ["blockers", "wasteAnchors", "decorationZones", "staticPlacements"]:
		if not manifest.get(key) is Array:
			return false
	if not manifest.get("spawn") is Array or manifest.spawn.size() != 2:
		return false
	var layout := HabitatRules.default_layout_for_manifest(manifest)
	if not HabitatRules.validate_layout(layout, Vector2i(-1, -1), manifest).ok:
		return false
	if not HabitatRules.all_free_cells_reachable(layout, manifest):
		return false
	for anchor: Vector2i in HabitatRules.waste_anchors(manifest):
		if HabitatRules.path_between_cells(layout, Vector2i(int(manifest.spawn[0]), int(manifest.spawn[1])), anchor, manifest).is_empty():
			return false
	return HabitatRules.waste_anchors(manifest).size() == 3


static func _approved_package(region_id: String) -> Dictionary:
	var asset_id := String(HabitatRules.REGION_HOMES[region_id].habitat_id)
	var catalog := AssetResourceLibrary.read_json(CATALOG)
	var entries: Variant = catalog.get("assets")
	if catalog.get("schemaVersion") != 1 or not entries is Dictionary:
		return {"ok": false, "error": "The approved runtime catalog is unavailable."}
	var entry: Variant = entries.get(asset_id)
	if not entry is Dictionary or entry.get("kind") != "habitat" or entry.get("assetId") != asset_id:
		return {"ok": false, "error": "This region has not passed habitat review."}
	var relative := String(entry.get("path", ""))
	if not _safe_relative(relative):
		return {"ok": false, "error": "The approved habitat catalog path is invalid."}
	var folder := "res://" + relative.trim_prefix("/")
	var metadata := AssetResourceLibrary.read_json(folder.path_join("candidate.json"))
	var habitat := AssetResourceLibrary.read_json(folder.path_join("habitat.json"))
	if not _candidate_matches(metadata, entry, asset_id) or not validate_manifest(habitat, asset_id):
		return {"ok": false, "error": "The approved habitat package failed identity validation."}
	if String(habitat.get("revision", "")) != String(entry.get("revision", "")) or not _payload_hashes_match(folder, metadata.get("files")):
		return {"ok": false, "error": "The approved habitat package failed integrity validation."}
	if not _native_habitat_matches(folder, metadata, habitat):
		return {"ok": false, "error": "The approved habitat native resource failed identity validation."}
	var environment_pin: Variant = habitat.get("environment")
	if not environment_pin is Dictionary:
		return _verified_habitat_2d(region_id, habitat, "The habitat's 3D environment pin is unavailable.")
	var environment_package := EnvironmentAssetLibrary.activate_pin(environment_pin)
	if environment_package.is_empty():
		# The signed habitat grid and blockers remain authoritative even if its 3D
		# textures cannot be presented. Falling back to a generic empty field here
		# would silently change movement and automatic-care outcomes.
		return _verified_habitat_2d(region_id, habitat, "The approved 3D environment could not be loaded.")
	return {
		"ok": true,
		"region_id": region_id,
		"home_name": String(HabitatRules.REGION_HOMES[region_id].name),
		"mode": "approved-3d",
		"notice": "",
		"habitat": habitat,
		"environment_package": environment_package,
	}


static func _verified_habitat_2d(region_id: String, habitat: Dictionary, reason: String) -> Dictionary:
	EnvironmentAssetLibrary.clear_active()
	return {
		"ok": true,
		"region_id": region_id,
		"home_name": String(HabitatRules.REGION_HOMES[region_id].name),
		"mode": "verified-habitat-2d",
		"notice": reason + " Its verified habitat grid and blockers remain active in 2D.",
		"habitat": habitat.duplicate(true),
		"environment_package": {},
	}


static func _dev_fixture_package(region_id: String) -> Dictionary:
	var index := AssetResourceLibrary.read_json(DEV_INDEX)
	var regions: Variant = index.get("regions")
	if index.get("schemaVersion") != 1 or not regions is Dictionary or not regions.get(region_id) is Dictionary:
		return {"ok": false, "error": "No review fixture is available for this region."}
	var record: Dictionary = regions[region_id]
	var habitat_record: Variant = record.get("habitat")
	if not habitat_record is Dictionary:
		return {"ok": false, "error": "The review habitat record is invalid."}
	var habitat_path := _dev_resource_path(String(habitat_record.get("path", "")))
	if habitat_path.is_empty():
		return {"ok": false, "error": "The review habitat path is not isolated."}
	var habitat := AssetResourceLibrary.read_json(habitat_path)
	var expected_id := String(HabitatRules.REGION_HOMES[region_id].habitat_id)
	if not validate_manifest(habitat, expected_id) or String(habitat.get("revision", "")) != DEV_REVISION:
		return {"ok": false, "error": "The review habitat failed its v1 contract."}
	var review_package := _dev_resource_path(String(habitat_record.get("reviewPackage", habitat.get("reviewPackage", habitat_path.get_base_dir()))))
	if review_package.is_empty():
		return {"ok": false, "error": "The review package path is not isolated."}
	var candidate := AssetResourceLibrary.read_json(review_package.path_join("candidate.json"))
	if candidate.get("devFixture") != true or String(candidate.get("environmentPackage", "")) != "environment":
		return {"ok": false, "error": "The review package lacks an explicit dev-fixture marker."}
	if candidate.get("kind") != "habitat" or String(candidate.get("assetId", "")) != expected_id \
			or String(candidate.get("revision", "")) != DEV_REVISION \
			or String(candidate.get("contentSha256", "")) != String(habitat_record.get("contentSha256", "")) \
			or not _payload_hashes_match(review_package, candidate.get("files")):
		return {"ok": false, "error": "The review habitat package failed integrity validation."}
	var expected_habitat_hash := String(candidate.get("files", {}).get("habitat.json", ""))
	if expected_habitat_hash != "sha256:" + FileAccess.get_sha256(habitat_path):
		return {"ok": false, "error": "The indexed habitat differs from its review package."}
	var environment_record: Variant = record.get("environment")
	if not environment_record is Dictionary:
		return {"ok": false, "error": "The review environment record is invalid."}
	var environment_path := review_package.path_join("environment/environment.json")
	if not _safe_resource_path(environment_path):
		return {"ok": false, "error": "The review environment path is not isolated."}
	var environment := AssetResourceLibrary.read_json(environment_path)
	var environment_candidate := AssetResourceLibrary.read_json(environment_path.get_base_dir().path_join("candidate.json"))
	var pin: Variant = habitat.get("environment")
	if not pin is Dictionary or not _environment_identity_matches(pin, environment, environment_candidate) \
			or not _environment_identity_matches(environment_record, environment, environment_candidate):
		return {"ok": false, "error": "The review environment does not match the habitat pin."}
	if not _payload_hashes_match(environment_path.get_base_dir(), environment_candidate.get("files")):
		return {"ok": false, "error": "The review environment failed integrity validation."}
	var environment_package := EnvironmentAssetLibrary.activate_isolated_dev_fixture(pin, environment_path.get_base_dir(), true)
	if environment_package.is_empty():
		return {"ok": false, "error": "The review environment textures are incomplete."}
	return {
		"ok": true,
		"region_id": region_id,
		"home_name": String(habitat.get("displayName", HabitatRules.REGION_HOMES[region_id].name)),
		"mode": "review-fixture-3d",
		"notice": "Review fixture — not promoted for production.",
		"habitat": habitat,
		"environment_package": environment_package,
	}


static func _candidate_matches(metadata: Dictionary, entry: Dictionary, asset_id: String) -> bool:
	for field: String in ["revision", "contentSha256"]:
		if String(metadata.get(field, "")) != String(entry.get(field, "")):
			return false
	return metadata.get("schemaVersion") == 1 and metadata.get("kind") == "habitat" \
		and metadata.get("assetId") == asset_id and metadata.get("nativeResources") == true \
		and EnvironmentAssetLibrary.metadata_content_sha256(metadata) == String(metadata.get("contentSha256", ""))


static func _payload_hashes_match(folder: String, files: Variant) -> bool:
	if not files is Dictionary or files.is_empty() or files.size() > EnvironmentPresentationContract.MAX_ACTIVE_TEXTURES + 16:
		return false
	for relative_value: Variant in files:
		var relative := String(relative_value)
		if not _safe_relative(relative):
			return false
		var expected := String(files[relative_value])
		var path := folder.path_join(relative)
		if not expected.begins_with("sha256:") or expected.length() != 71 or not FileAccess.file_exists(path) \
				or "sha256:" + FileAccess.get_sha256(path) != expected:
			return false
	return true


static func _native_habitat_matches(folder: String, metadata: Dictionary, manifest: Dictionary) -> bool:
	var path := folder.path_join("habitat.tres")
	if not ResourceLoader.exists(path):
		return false
	var resource := ResourceLoader.load(path)
	if resource == null or not resource.has_meta("candidate_identity") or not resource.has_meta("habitat_manifest"):
		return false
	var identity: Variant = resource.get_meta("candidate_identity")
	var native_manifest: Variant = resource.get_meta("habitat_manifest")
	return identity is Dictionary and native_manifest is Dictionary \
		and String(identity.get("kind", "")) == "habitat" \
		and String(identity.get("assetId", "")) == String(metadata.get("assetId", "")) \
		and String(identity.get("revision", "")) == String(metadata.get("revision", "")) \
		and String(native_manifest.get("assetId", "")) == String(manifest.get("assetId", "")) \
		and String(native_manifest.get("revision", "")) == String(manifest.get("revision", ""))


static func _load_textures(folder: String, bindings: Variant) -> Dictionary:
	if not bindings is Dictionary or bindings.is_empty():
		return {}
	var textures := {}
	for role_value: Variant in bindings:
		var relative := String(bindings[role_value])
		if not relative.begins_with("textures/") or not _safe_relative(relative):
			return {}
		var texture := AssetResourceLibrary.load_payload_texture(folder.path_join(relative))
		if texture == null:
			return {}
		textures[String(role_value)] = texture
	return textures


static func _environment_identity_matches(pin: Dictionary, manifest: Dictionary, metadata: Dictionary) -> bool:
	for field: String in ["assetId", "revision"]:
		if String(pin.get(field, "")) != String(manifest.get(field, "")):
			return false
	return metadata.get("devFixture") == true and metadata.get("kind") == "environment" \
		and String(metadata.get("assetId", "")) == String(manifest.get("assetId", "")) \
		and String(metadata.get("revision", "")) == String(manifest.get("revision", "")) \
		and String(pin.get("contentSha256", "")) == String(metadata.get("contentSha256", ""))


static func _safe_relative(value: String) -> bool:
	return not value.is_empty() and not value.is_absolute_path() and not value.contains("\\") \
		and value not in [".", ".."] and ".." not in value.split("/")


static func _safe_resource_path(value: String) -> bool:
	return not value.contains("\\") and ".." not in value.trim_prefix("res://").split("/")


static func _dev_resource_path(value: String) -> String:
	if value.begins_with("res://tests/fixtures/regions/") and _safe_resource_path(value):
		return value
	if value.begins_with("tests/fixtures/regions/") and _safe_relative(value):
		return "res://" + value
	return ""
