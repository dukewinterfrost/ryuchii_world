class_name CompanionAssetLibrary
extends RefCounted

## Converts the curated Phaser-style JSON atlas and animation manifest at runtime.
## Keeping the original JSON beside the PNG preserves revision and frame provenance.

const ROOT := "res://assets/companions/"
const CATALOG := "res://assets/runtime-catalog.json"
const FACINGS := ["n", "ne", "e", "se", "s", "sw", "w", "nw"]


static func build(species_id: String) -> Dictionary:
	# Only an explicitly promoted catalog entry supersedes the legacy care assets.
	var catalog := _read_json(CATALOG)
	var entries: Dictionary = catalog.get("assets", {}) if catalog.get("assets", {}) is Dictionary else {}
	var entry: Variant = entries.get(species_id, entries.get("companion-" + species_id, {}))
	if entry is Dictionary and not entry.is_empty():
		var revision := String(entry.get("revision", ""))
		var asset_id := String(entry.get("assetId", species_id))
		return build_pinned(species_id, asset_id, revision)
	return build_folder(ROOT + species_id + "/")


static func build_pinned(species_id: String, asset_id: String, revision: String) -> Dictionary:
	# A replay must never silently read whatever revision the current catalog names.
	for value: String in [species_id, asset_id, revision]:
		if value.is_empty() or value in [".", ".."] or value.validate_filename() != value:
			push_warning("Invalid pinned companion artwork identifier")
			return {}
	var folder := "res://assets/generated/%s/%s/" % [asset_id, revision]
	var legacy := build_folder(ROOT + species_id + "/")
	if FileAccess.file_exists(folder + "animation-set.json") or ResourceLoader.exists(folder + "spriteframes.tres"):
		var loaded := build_folder(folder)
		if not loaded.is_empty() and loaded.revision == revision and loaded.get("asset_id", "") == asset_id:
			return with_legacy_care(loaded, legacy)
	elif not legacy.is_empty() and legacy.revision == revision and legacy.get("asset_id", species_id) == asset_id:
		return legacy
	push_warning("Pinned companion artwork is unavailable: %s / %s; no current-catalog substitution was made" % [asset_id, revision])
	return {}


static func with_legacy_care(primary: Dictionary, legacy: Dictionary) -> Dictionary:
	# Runtime composition only: never alter a promoted resource, candidate manifest,
	# or its required directional coverage. New combat sets need not erase care art.
	if primary.is_empty():
		return legacy
	if legacy.is_empty():
		return primary
	var result := primary.duplicate(true)
	var frames := (primary.frames as SpriteFrames).duplicate() as SpriteFrames
	result.frames = frames
	result["legacy_care_clips"] = []
	for name: String in legacy.frames.get_animation_names():
		if frames.has_animation(name):
			continue
		frames.add_animation(name)
		frames.set_animation_loop_mode(name, legacy.frames.get_animation_loop_mode(name))
		frames.set_animation_speed(name, legacy.frames.get_animation_speed(name))
		for index: int in legacy.frames.get_frame_count(name):
			frames.add_frame(name, legacy.frames.get_frame_texture(name, index), legacy.frames.get_frame_duration(name, index))
		for field: String in ["pivots", "frame_sources", "anchors", "events", "clip_provenance", "clip_facings"]:
			if not result.has(field):
				result[field] = {}
			if legacy.get(field, {}).has(name):
				result[field][name] = legacy[field][name]
		result.legacy_care_clips.append(name)
	return result


static func build_folder(folder: String, embed_texture: bool = false) -> Dictionary:
	folder = folder.trim_suffix("/") + "/"
	if not embed_texture and ResourceLoader.exists(folder + "spriteframes.tres"):
		var native := load(folder + "spriteframes.tres") as SpriteFrames
		if native != null and native.has_meta("asset_library"):
			var result: Dictionary = native.get_meta("asset_library").duplicate(true)
			result["frames"] = native
			result["asset_id"] = result.get("asset_id", result.get("manifest", {}).get("assetId", result.get("manifest", {}).get("subjectId", "unknown")))
			return result
	var texture: Texture2D
	# Only legacy care assets depend on imported PNGs in packaged exports. Generated
	# candidates/revisions must ignore editor .import settings, which are not art.
	if not embed_texture and not FileAccess.file_exists(folder + "candidate.json") and ResourceLoader.exists(folder + "atlas.png"):
		texture = load(folder + "atlas.png") as Texture2D
	if texture == null:
		var image := Image.new()
		if image.load_png_from_buffer(FileAccess.get_file_as_bytes(folder + "atlas.png")) != OK or image.is_empty():
			return {}
		texture = ImageTexture.create_from_image(image)
	# Embedded textures let candidates outside res:// and promoted native resources
	# work without relying on editor import state or stale external-resource UIDs.
	var atlas_data := _read_json(folder + "atlas.json")
	var animation_data := _read_json(folder + "animation-set.json")
	return build_from_manifests(atlas_data, animation_data, texture)


static func build_from_manifests(atlas_data: Dictionary, animation_data: Dictionary, texture: Texture2D) -> Dictionary:
	if texture == null or atlas_data.is_empty() or animation_data.is_empty():
		return {}
	var manifest_errors := validate_manifest(atlas_data, animation_data, texture.get_size())
	if not manifest_errors.is_empty():
		push_error("Invalid companion manifest: %s" % "; ".join(manifest_errors))
		return {}

	var sprite_frames := SpriteFrames.new()
	if sprite_frames.has_animation("default"):
		sprite_frames.remove_animation("default")
	var pivots: Dictionary = {}
	var frame_sources: Dictionary = {}
	var anchors: Dictionary = {}
	var events: Dictionary = {}
	var aliases: Dictionary = {}
	var clip_provenance: Dictionary = {}
	var clip_facings: Dictionary = {}
	var atlas_frames: Dictionary = atlas_data.get("frames", {})
	var clips: Dictionary = animation_data.get("clips", {})

	for clip_id: String in clips:
		var clip: Dictionary = clips[clip_id]
		var animation_name := clip_id
		sprite_frames.add_animation(animation_name)
		# Godot clamps relative durations below 0.01. FPS=1000 and millisecond
		# weights preserve even 1ms input exactly: absolute_seconds = weight / FPS.
		sprite_frames.set_animation_loop_mode(animation_name, SpriteFrames.LOOP_LINEAR if String(clip.get("kind", "loop")) == "loop" else SpriteFrames.LOOP_NONE)
		sprite_frames.set_animation_speed(animation_name, 1000.0)
		pivots[animation_name] = []
		frame_sources[animation_name] = []
		anchors[animation_name] = []
		events[animation_name] = clip.get("events", []).duplicate(true)
		clip_provenance[animation_name] = {"revision": animation_data.get("revision", "unknown"), "status": animation_data.get("status", "unknown"), "provenance": animation_data.get("provenance", {}).duplicate(true)}
		clip_facings[animation_name] = String(animation_data.get("motionProfile", {}).get("facing", "right"))
		var clip_frames: Array = clip.get("frames", [])
		for frame_definition: Dictionary in clip_frames:
			var atlas_frame_name := String(frame_definition.get("atlasFrame", ""))
			var atlas_frame: Dictionary = atlas_frames[atlas_frame_name]
			var rectangle: Dictionary = atlas_frame.get("frame", {})
			var subtexture := AtlasTexture.new()
			subtexture.atlas = texture
			subtexture.region = Rect2(
				float(rectangle.get("x", 0)),
				float(rectangle.get("y", 0)),
				float(rectangle.get("w", 1)),
				float(rectangle.get("h", 1))
			)
			sprite_frames.add_frame(animation_name, subtexture, float(frame_definition["durationMs"]))
			var pivot_data: Dictionary = frame_definition.get("pivot", atlas_frame.get("pivot", {"x": 0.5, "y": 0.5}))
			pivots[animation_name].append(Vector2(float(pivot_data.get("x", 0.5)), float(pivot_data.get("y", 0.5))))
			frame_sources[animation_name].append(atlas_frame_name)
			anchors[animation_name].append(frame_definition.get("anchors", {}).duplicate(true))
		# Existing care callers use "idle", "move", "eat". Only an explicit
		# .default gets an alias; NE/NW must never collapse onto the same action.
		if clip_id.ends_with(".default"):
			var alias := clip_id.trim_suffix(".default")
			sprite_frames.duplicate_animation(animation_name, alias)
			pivots[alias] = pivots[animation_name]
			frame_sources[alias] = frame_sources[animation_name]
			anchors[alias] = anchors[animation_name]
			events[alias] = events[animation_name]
			aliases[alias] = animation_name
			clip_provenance[alias] = clip_provenance[animation_name]
			clip_facings[alias] = clip_facings[animation_name]

	return {
		"asset_id": String(animation_data.get("assetId", animation_data.get("subjectId", "unknown"))),
		"frames": sprite_frames,
		"pivots": pivots,
		"frame_sources": frame_sources,
		"anchors": anchors,
		"events": events,
		"aliases": aliases,
		"clip_provenance": clip_provenance,
		"clip_facings": clip_facings,
		"manifest": animation_data.duplicate(true),
		"legacy_facing": String(animation_data.get("motionProfile", {}).get("facing", "right")),
		"revision": String(animation_data.get("revision", "unknown")),
		"status": String(animation_data.get("status", "unknown")),
		"provenance": (animation_data.get("provenance", {}) as Dictionary).duplicate(true),
	}


static func validate_manifest(atlas_data: Dictionary, animation_data: Dictionary, texture_size: Vector2) -> Array[String]:
	var errors: Array[String] = []
	for property: String in ["provenance", "motionProfile", "fallbacks"]:
		if not animation_data.get(property, {}) is Dictionary:
			errors.append(property + " must be a dictionary")
	for property: String in ["requiredActions", "requiredFacings"]:
		if not animation_data.get(property, []) is Array:
			errors.append(property + " must be an array of strings")
		else:
			for value: Variant in animation_data.get(property, []):
				if not value is String or value.is_empty():
					errors.append(property + " must contain non-empty strings")
	if not errors.is_empty():
		return errors
	if texture_size.x <= 0.0 or texture_size.y <= 0.0:
		errors.append("atlas texture dimensions must be positive")

	var atlas_frames_value: Variant = atlas_data.get("frames")
	if not atlas_frames_value is Dictionary or (atlas_frames_value as Dictionary).is_empty():
		errors.append("atlas.frames must be a non-empty dictionary")
		return errors
	var atlas_frames: Dictionary = atlas_frames_value
	var atlas_meta_value: Variant = atlas_data.get("meta")
	if not atlas_meta_value is Dictionary:
		errors.append("atlas.meta must be a dictionary")
	else:
		var atlas_size_value: Variant = (atlas_meta_value as Dictionary).get("size")
		if not atlas_size_value is Dictionary:
			errors.append("atlas.meta.size must be a dictionary")
		else:
			var declared_size: Dictionary = atlas_size_value
			if not _is_positive_number(declared_size.get("w")) or not _is_positive_number(declared_size.get("h")):
				errors.append("atlas.meta.size dimensions must be positive numbers")
			elif not is_equal_approx(float(declared_size["w"]), texture_size.x) or not is_equal_approx(float(declared_size["h"]), texture_size.y):
				errors.append("atlas.meta.size must match the texture dimensions")

	for frame_name_value: Variant in atlas_frames:
		var frame_name := String(frame_name_value)
		var frame_value: Variant = atlas_frames[frame_name_value]
		if frame_name.is_empty() or not frame_value is Dictionary:
			errors.append("atlas frame names must map to dictionaries")
			continue
		var frame_entry: Dictionary = frame_value
		if bool(frame_entry.get("rotated", false)):
			errors.append("atlas frame %s uses unsupported rotation" % frame_name)
		var rectangle_value: Variant = frame_entry.get("frame")
		if not rectangle_value is Dictionary:
			errors.append("atlas frame %s is missing its rectangle" % frame_name)
			continue
		var rectangle: Dictionary = rectangle_value
		if not _is_nonnegative_number(rectangle.get("x")) or not _is_nonnegative_number(rectangle.get("y")) \
				or not _is_positive_number(rectangle.get("w")) or not _is_positive_number(rectangle.get("h")):
			errors.append("atlas frame %s has an invalid rectangle" % frame_name)
			continue
		var right := float(rectangle["x"]) + float(rectangle["w"])
		var bottom := float(rectangle["y"]) + float(rectangle["h"])
		if right > texture_size.x or bottom > texture_size.y:
			errors.append("atlas frame %s extends outside the texture" % frame_name)

	var clips_value: Variant = animation_data.get("clips")
	if not clips_value is Dictionary or (clips_value as Dictionary).is_empty():
		errors.append("animation clips must be a non-empty dictionary")
		return errors
	var clips: Dictionary = clips_value
	for fallback_key: Variant in animation_data.get("fallbacks", {}):
		var fallback_target: Variant = animation_data.fallbacks[fallback_key]
		if not fallback_key is String or not fallback_target is String or not clips.has(fallback_target):
			errors.append("fallbacks must map requests to authored clip IDs")
	for clip_id_value: Variant in clips:
		var clip_id := String(clip_id_value)
		var clip_value: Variant = clips[clip_id_value]
		if clip_id.is_empty() or not clip_value is Dictionary:
			errors.append("animation clip names must map to dictionaries")
			continue
		if clip_id.ends_with(".default") and clips.has(clip_id.trim_suffix(".default")):
			errors.append("animation alias collides with an authored clip: %s" % clip_id)
		var clip: Dictionary = clip_value
		if not clip.get("events", []) is Array:
			errors.append("animation %s events must be an array" % clip_id)
		if String(clip.get("kind", "")) not in ["loop", "one-shot", "hold", "transition"]:
			errors.append("animation %s has an unsupported kind" % clip_id)
		var clip_frames_value: Variant = clip.get("frames")
		if not clip_frames_value is Array or (clip_frames_value as Array).is_empty():
			errors.append("animation %s must contain at least one frame" % clip_id)
			continue
		for frame_index: int in (clip_frames_value as Array).size():
			var frame_definition_value: Variant = (clip_frames_value as Array)[frame_index]
			if not frame_definition_value is Dictionary:
				errors.append("animation %s frame %d must be a dictionary" % [clip_id, frame_index])
				continue
			var frame_definition: Dictionary = frame_definition_value
			if not frame_definition.get("anchors", {}) is Dictionary:
				errors.append("animation %s frame %d anchors must be a dictionary" % [clip_id, frame_index])
			var atlas_frame_name := String(frame_definition.get("atlasFrame", ""))
			if atlas_frame_name.is_empty() or not atlas_frames.has(atlas_frame_name):
				errors.append("animation %s frame %d references a missing atlas frame" % [clip_id, frame_index])
			if not _is_positive_number(frame_definition.get("durationMs")) or float(frame_definition["durationMs"]) != floorf(float(frame_definition["durationMs"])):
				errors.append("animation %s frame %d must have a positive integer millisecond duration" % [clip_id, frame_index])
			var pivot_value: Variant = frame_definition.get("pivot")
			if not pivot_value is Dictionary or not _is_unit_number((pivot_value as Dictionary).get("x")) or not _is_unit_number((pivot_value as Dictionary).get("y")):
				errors.append("animation %s frame %d must have a normalized pivot" % [clip_id, frame_index])
	for action: String in animation_data.get("requiredActions", []):
		for facing: String in animation_data.get("requiredFacings", []):
			if facing.to_lower() not in FACINGS:
				errors.append("unsupported facing: %s" % facing)
			elif not clips.has(action + "." + facing.to_lower()):
				errors.append("missing required directional clip: %s.%s" % [action, facing.to_lower()])
	return errors


static func _is_number(value: Variant) -> bool:
	return value is int or value is float


static func _is_positive_number(value: Variant) -> bool:
	return _is_number(value) and float(value) > 0.0 and not is_nan(float(value)) and not is_inf(float(value))


static func _is_nonnegative_number(value: Variant) -> bool:
	return _is_number(value) and float(value) >= 0.0 and not is_nan(float(value)) and not is_inf(float(value))


static func _is_unit_number(value: Variant) -> bool:
	return _is_nonnegative_number(value) and float(value) <= 1.0


static func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}
