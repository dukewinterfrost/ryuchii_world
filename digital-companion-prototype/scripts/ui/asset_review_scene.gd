extends Node2D

## Read-only human review. Approval receipts are minted only by the explicit CLI
## review --approve flow; opening this scene never approves or promotes anything.

var candidate_path := ""
var candidate: Dictionary = {}
var manifest: Dictionary = {}
var _avatar: CompanionAvatar
var _arena_view: ArenaView
var _environment_view: EnvironmentView3D
var _atlas_sprite: Sprite2D
var _tiles: TileMapLayer
var _library: Dictionary = {}
var _session: Dictionary = {}
var _fighters: Dictionary = {}
var _accumulator := 0.0
var _elapsed := 0.0
var _playing := false
var _debug := true
var _collision_overlay := true
var _navigation_overlay := false
var _occlusion_overlay := false
var _zoom := 2.0
var _background := Color("15201e")
var _status := Label.new()
var _clip := OptionButton.new()
var _facing := OptionButton.new()
var _scrub := HSlider.new()
var _play := Button.new()
var _overlay := CheckButton.new()
var _stage := Rect2(35, 185, 1010, 435)
var _debug_canvas: Node2D
var _placeholders := false
var _effects: CompanionEffects
var _species: OptionButton
var _footer: VBoxContainer
var _target_size_picker: OptionButton
var _environment_actor: CompanionPresentation3D
var _environment_vfx: WorldVFX3D
var _environment_demo_elapsed := 0.0
var _environment_demo_from := Vector2.ZERO
var _environment_demo_to := Vector2.ZERO
var _environment_demo_enabled := false
var _environment_demo_route: Array[Vector2] = []
var _environment_acceptance: Dictionary = {}

class DebugCanvas extends Node2D:
	var reviewer: Node2D
	func _draw() -> void:
		reviewer._draw_debug(self)

func _ready() -> void:
	get_tree().root.content_scale_size = Vector2i(1080, 800)
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_size(Vector2i(1080, 800))
	var args := OS.get_cmdline_user_args()
	_placeholders = "--placeholders" in args
	var at := args.find("--candidate")
	if at >= 0 and at + 1 < args.size():
		candidate_path = String(args[at + 1]).trim_suffix("/")
	_build_ui()
	_debug_canvas = DebugCanvas.new()
	_debug_canvas.reviewer = self
	_debug_canvas.z_index = 20
	add_child(_debug_canvas)
	if not GameState.isolated_mode:
		_status.text = "Review requires --asset-review to isolate the real companion save."
		return
	if _placeholders:
		_load_placeholders()
		return
	if candidate_path.is_empty():
		_status.text = "Launch with --asset-review --candidate ABSOLUTE_CANDIDATE_DIRECTORY"
		return
	load_candidate(candidate_path)


func _load_placeholders() -> void:
	# No candidate, source binding, or approval is created by this playground.
	_avatar = CompanionAvatar.new()
	add_child(_avatar)
	_avatar.configure("agumon")
	_avatar.roaming_enabled = false
	_avatar.position = Vector2(_stage.get_center().x, _stage.end.y - 50)
	_avatar.sprite.scale = Vector2.ONE * _zoom
	_effects = CompanionEffects.new()
	_avatar.add_child(_effects)
	_effects.scale = Vector2.ONE * _zoom
	for index: int in CompanionEffects.EFFECTS.size():
		_clip.add_item(CompanionEffects.LABELS[index])
		_clip.set_item_metadata(index, CompanionEffects.EFFECTS[index])
	_playing = true
	_play.text = "Pause"
	_render_animation()


func load_candidate(folder: String) -> void:
	EnvironmentAssetLibrary.clear_active()
	candidate_path = folder.trim_suffix("/")
	candidate = AssetResourceLibrary.read_json(candidate_path.path_join("candidate.json"))
	if candidate.is_empty():
		_status.text = "Missing or invalid candidate.json; no approval was recorded."
		return
	var kind := String(candidate.get("kind", ""))
	if kind == "animation":
		_library = CompanionAssetLibrary.build_folder(candidate_path)
		if _library.is_empty():
			_status.text = "Animation candidate failed validation."
			return
		manifest = _library.manifest
		_avatar = CompanionAvatar.new()
		add_child(_avatar)
		_avatar.configure_library(_library)
		_avatar.position = Vector2(_stage.get_center().x, _stage.end.y - 24)
		_avatar.sprite.scale = Vector2.ONE * _zoom
		var actions: Array[String] = []
		for name: String in manifest.clips:
			# Collapse only true eight-direction variants into the facing selector.
			# Non-directional authored variants (idle.alert, idle.sleepy) stay distinct.
			var action := name.get_slice(".", 0) if name.get_slice(".", 1) in CompanionAssetLibrary.FACINGS else name
			if action not in actions:
				actions.append(action)
		actions.sort()
		for action: String in actions:
			_clip.add_item(action)
		_render_animation()
	elif kind == "tileset":
		manifest = AssetResourceLibrary.read_json(candidate_path.path_join("tileset.json"))
		var tile_set: TileSet
		if ResourceLoader.exists(candidate_path.path_join("tileset.tres")):
			tile_set = load(candidate_path.path_join("tileset.tres")) as TileSet
		if tile_set == null:
			var built := AssetResourceLibrary.build_tileset(manifest, _load_texture(candidate_path.path_join("atlas.png")))
			if not built.ok:
				_status.text = "TileSet validation: " + "; ".join(built.errors)
				return
			tile_set = built.tileset
		_tiles = TileMapLayer.new()
		_tiles.tile_set = tile_set
		_tiles.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_tiles.position = _stage.get_center() - Vector2(80, 50)
		_tiles.scale = Vector2.ONE * _zoom
		_tiles.collision_enabled = false
		_tiles.navigation_enabled = false
		add_child(_tiles)
		_tile_sample()
		_clip.add_item("Authored tile alternatives")
		for index: int in tile_set.get_terrain_sets_count():
			for terrain: int in tile_set.get_terrains_count(index):
				_clip.add_item("Terrain: " + tile_set.get_terrain_name(index, terrain))
				_clip.set_item_metadata(_clip.item_count - 1, [index, terrain])
	elif kind == "atlas":
		manifest = AssetResourceLibrary.read_json(candidate_path.path_join("atlas.json"))
		_atlas_sprite = Sprite2D.new()
		# Review the same embedded pixels promotion deploys, not editor imports.
		if ResourceLoader.exists(candidate_path.path_join("atlasframes.tres")):
			var frames := load(candidate_path.path_join("atlasframes.tres")) as SpriteFrames
			if frames != null:
				for name: String in frames.get_animation_names():
					if frames.get_frame_count(name) > 0:
						var region := frames.get_frame_texture(name, 0) as AtlasTexture
						if region != null:
							_atlas_sprite.texture = region.atlas
							break
		if _atlas_sprite.texture == null:
			_atlas_sprite.texture = _load_texture(candidate_path.path_join("atlas.png"))
		_atlas_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_atlas_sprite.position = _stage.get_center()
		_atlas_sprite.scale = Vector2.ONE * _zoom
		add_child(_atlas_sprite)
		_clip.add_item("Full atlas / padded bounds")
	elif kind == "arena":
		manifest = AssetResourceLibrary.read_json(candidate_path.path_join("arena.json"))
		if manifest.has("environment"):
			if not _load_environment_dependency(manifest.environment):
				return
			if not _environment_view.set_static_placements(manifest.get("presentation", {}).get("staticPlacements", []), "arena"):
				_status.text = "Arena placements cannot be rendered from the pinned Environment."
				return
			_add_environment_viewpoints()
			_add_review_item("Seed 2468 · matched stats", {"type": "bout", "stronger": false})
			_add_review_item("Seed 2468 · faster, intuitive player", {"type": "bout", "stronger": true})
			_set_arena_3d_overlays()
			_activate_environment_review()
		else:
			_arena_view = ArenaView.new()
			add_child(_arena_view)
			_arena_view.configure(manifest, candidate_path)
			_arena_view.debug_overlays = _debug
			_arena_view.fit_to(_stage.grow(-15))
			_clip.add_item("Arena geometry")
			_clip.add_item("Seed 2468 · matched stats")
			_clip.add_item("Seed 2468 · faster, intuitive player")
	elif kind == "environment":
		manifest = AssetResourceLibrary.read_json(candidate_path.path_join("environment.json"))
		_create_environment_view()
		if manifest.is_empty() or not _environment_view.configure_from_folder(candidate_path):
			_status.text = "Environment candidate has no renderable manifest/native resource; it cannot be approved."
			return
		if not _environment_view.build_review_samples():
			_status.text = "Environment plane stacks cannot be rendered; this candidate cannot be approved."
			return
		_add_environment_viewpoints()
		_activate_environment_review()
	elif kind == "habitat":
		manifest = AssetResourceLibrary.read_json(candidate_path.path_join("habitat.json"))
		if manifest.is_empty() or not _load_environment_dependency(manifest.get("environment", {})):
			return
		if not _environment_view.set_static_placements(manifest.get("staticPlacements", []), "habitat"):
			_status.text = "Habitat static placements cannot be rendered from the pinned Environment."
			return
		_add_environment_viewpoints()
		_set_habitat_3d_overlays()
		_activate_environment_review()
	else:
		_status.text = "Unsupported candidate kind: " + kind
		return
	if _environment_view != null:
		_update_environment_review_status()
	else:
		_status.text = "%s / %s · %s · SHA %s\nUnapproved candidate. Inspect, then use the explicit approval command below." % [candidate.get("assetId", "?"), candidate.get("revision", "?"), kind, FileAccess.get_sha256(candidate_path.path_join("candidate.json")).left(16)]
	queue_redraw()


func _build_ui() -> void:
	var ui := CanvasLayer.new()
	add_child(ui)
	var panel := PanelContainer.new()
	panel.position = Vector2(22, 20)
	panel.size = Vector2(1036, 150)
	ui.add_child(panel)
	var stack := VBoxContainer.new()
	panel.add_child(stack)
	var title := Label.new()
	title.text = "ASSET REVIEW   /   isolated preview — no rewards, no promotion"
	title.add_theme_font_size_override("font_size", 21)
	stack.add_child(title)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(1000, 45)
	stack.add_child(_status)
	var row := HBoxContainer.new()
	stack.add_child(row)
	_clip.custom_minimum_size.x = 285
	row.add_child(_clip)
	_clip.item_selected.connect(_on_clip_selected)
	for facing: String in CompanionAssetLibrary.FACINGS:
		_facing.add_item(facing.to_upper())
	_facing.selected = 2
	row.add_child(_facing)
	_facing.item_selected.connect(func(_index: int) -> void: _render_animation())
	_play.text = "Play"
	row.add_child(_play)
	_play.pressed.connect(func() -> void:
		_playing = not _playing
		_play.text = "Pause" if _playing else "Play"
		if candidate.get("kind", "") == "arena" and _session.is_empty() and _selected_review_type() == "bout":
			_start_bout(bool(_clip.get_item_metadata(_clip.selected).get("stronger", false))))
	_overlay.text = "Geometry / pivots"
	_overlay.button_pressed = true
	row.add_child(_overlay)
	_overlay.toggled.connect(func(value: bool) -> void:
		_debug = value
		if _arena_view != null:
			_arena_view.debug_overlays = value
			_arena_view.queue_redraw()
		_update_environment_overlay_visibility()
		queue_redraw())
	var backdrop := OptionButton.new()
	for label: String in ["Dark", "Light", "Magenta"]:
		backdrop.add_item(label)
	row.add_child(backdrop)
	backdrop.item_selected.connect(func(index: int) -> void:
		_background = [Color("15201e"), Color("eee6d7"), Color("a02c79")][index]
		queue_redraw())
	var layers := HBoxContainer.new()
	stack.add_child(layers)
	if _placeholders:
		_species = OptionButton.new()
		for species_id: String in ["botamon", "koromon", "agumon"]:
			_species.add_item(species_id.capitalize())
		_species.selected = 2
		layers.add_child(_species)
		_species.item_selected.connect(func(index: int) -> void:
			if _avatar != null:
				_avatar.configure(["botamon", "koromon", "agumon"][index])
				_avatar.sprite.scale = Vector2.ONE * _zoom
				_render_animation())
		var reduced := CheckButton.new()
		reduced.text = "Reduced motion"
		layers.add_child(reduced)
		reduced.toggled.connect(func(value: bool) -> void:
			if _effects != null:
				_effects.reduced_motion = value
				_render_animation())
	for label: String in ["Collision", "Navigation", "Occlusion"]:
		var check := CheckButton.new()
		check.text = label
		check.button_pressed = label == "Collision"
		layers.add_child(check)
		check.toggled.connect(func(value: bool) -> void:
			if label == "Collision":
				_collision_overlay = value
			elif label == "Navigation":
				_navigation_overlay = value
			else:
				_occlusion_overlay = value
			_update_environment_overlay_visibility()
			queue_redraw())
	_target_size_picker = OptionButton.new()
	_target_size_picker.name = "PortraitTargetSize"
	for target_size: Vector2i in [Vector2i(360, 640), Vector2i(390, 844), Vector2i(430, 932)]:
		_target_size_picker.add_item("%d × %d" % [target_size.x, target_size.y])
		_target_size_picker.set_item_metadata(_target_size_picker.item_count - 1, target_size)
	_target_size_picker.selected = 1
	_target_size_picker.visible = false
	layers.add_child(_target_size_picker)
	_target_size_picker.item_selected.connect(func(index: int) -> void:
		if _environment_view != null:
			_set_environment_target_size(_target_size_picker.get_item_metadata(index))
			_update_environment_review_status())
	_footer = VBoxContainer.new()
	_footer.position = Vector2(35, 640)
	_footer.size = Vector2(1010, 140)
	ui.add_child(_footer)
	_scrub.min_value = 0
	_scrub.max_value = 1
	_scrub.step = 0.001
	_footer.add_child(_scrub)
	_scrub.value_changed.connect(func(value: float) -> void:
		_elapsed = value * _duration_seconds()
		_render_animation())
	var zoom := HSlider.new()
	zoom.min_value = 0.5
	zoom.max_value = 6
	zoom.step = 0.25
	zoom.value = _zoom
	zoom.tooltip_text = "Preview zoom (0.5×–6×)"
	_footer.add_child(zoom)
	zoom.value_changed.connect(func(value: float) -> void:
		_zoom = value
		if _avatar != null:
			_avatar.sprite.scale = Vector2.ONE * value
		if _effects != null:
			_effects.scale = Vector2.ONE * value
		if _atlas_sprite != null:
			_atlas_sprite.scale = Vector2.ONE * value
		if _tiles != null:
			_tiles.scale = Vector2.ONE * value
		queue_redraw())
	var legend := Label.new()
	legend.text = "Red: movement / body clearance   Amber: projectiles   Blue: sight/navigation   Purple: occlusion   Cyan: roots/bounds"
	legend.add_theme_font_size_override("font_size", 13)
	_footer.add_child(legend)
	var approval := Label.new()
	approval.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	approval.text = "After human review only: ./tools/sprites review --candidate <this directory> --stage final --approve --reviewer <your name> --notes <findings> --no-launch\nApproval is bound to the exact candidate hashes; modified candidates require a new review."
	if _placeholders:
		approval.text = "Engineering placeholders only. Grounded creature poses and independent effect overlays.\nNo artwork approval, companion progress, combat damage, or gameplay status conditions are changed."
	approval.add_theme_font_size_override("font_size", 13)
	_footer.add_child(approval)


func _process(delta: float) -> void:
	if not _playing:
		return
	if _environment_demo_enabled and _session.is_empty():
		_advance_environment_demo(delta)
	if _avatar != null:
		_elapsed = fmod(_elapsed + delta, _duration_seconds())
		_scrub.set_value_no_signal(_elapsed / _duration_seconds())
		_render_animation()
	if not _session.is_empty() and not _session.get("complete", false):
		_accumulator += minf(delta, 0.25)
		while _accumulator >= 1.0 / 30.0 and not _session.complete:
			BattleSimulator.step(_session)
			_accumulator -= 1.0 / 30.0
		for fighter_id: String in _fighters:
			var actor: Dictionary = _session.actors[fighter_id]
			var fighter: Variant = _fighters[fighter_id]
			if fighter is CompanionPresentation3D:
				var next_ground := BattleSimulator.ground_position(actor)
				fighter.set_ground_position(next_ground)
				fighter.render_battle(actor, _accumulator * 30)
			else:
				fighter.position = _arena_view.project(BattleSimulator.ground_position(actor))
				fighter.render_battle(actor, _accumulator * 30)
		if _arena_view != null:
			_arena_view.render_session(_session)
		elif _environment_view != null:
			var first := BattleSimulator.ground_position(_session.actors.player)
			var second := BattleSimulator.ground_position(_session.actors.opponent)
			_environment_view.frame_ground_bounds(Rect2(first.min(second), (second - first).abs()), Vector2(96, 128))
		_status.text = "Arena test · seed 2468 · tick %d · player HP %s / opponent HP %s\nEngineering battle preview; legacy sprite fallback is shown until directional art is approved." % [_session.tick, _session.actors.player.hp, _session.actors.opponent.hp]
		queue_redraw()


func _render_animation() -> void:
	if _avatar == null or _clip.item_count == 0:
		return
	if _placeholders:
		var effect_id := String(_clip.get_item_metadata(_clip.selected))
		var pose := "idle"
		if effect_id == "feed":
			pose = "eat"
		elif effect_id in ["basic_attack", "special_attack"]:
			pose = effect_id
		elif effect_id.begins_with("hit_") or effect_id == "knocked_down":
			pose = "hit"
		_avatar.render_combat(pose, _facing.get_item_text(_facing.selected), _elapsed * 30, 36)
		_effects.scale = Vector2(-_zoom if _facing.get_item_text(_facing.selected) in ["NW", "W", "SW"] else _zoom, _zoom)
		_effects.sample_effect(effect_id, _elapsed / 1.2)
		_status.text = "PLACEHOLDER · %s · %s\n%s" % [_avatar.species_id.capitalize(), _clip.get_item_text(_clip.selected), _avatar.visual_fallback if not _avatar.visual_fallback.is_empty() else "Existing grounded pose with independent effect overlay; no gameplay condition."]
		queue_redraw()
		return
	_avatar.render_combat(_clip.get_item_text(_clip.selected), _facing.get_item_text(_facing.selected), _elapsed * 30, _duration_seconds() * 30)
	if not _avatar.visual_fallback.is_empty():
		_status.text = _avatar.visual_fallback + "\nCandidate remains unapproved."
	queue_redraw()


func _duration_seconds() -> float:
	if _placeholders:
		return 1.2
	if _avatar == null or _avatar.sprite.sprite_frames == null:
		return 1.0
	var frames := _avatar.sprite.sprite_frames
	var name := String(_avatar.sprite.animation)
	if not frames.has_animation(name):
		return 1.0
	var duration := 0.0
	for index: int in frames.get_frame_count(name):
		duration += frames.get_frame_duration(name, index) / frames.get_animation_speed(name)
	return maxf(0.001, duration)


func _on_clip_selected(index: int) -> void:
	_elapsed = 0
	var metadata: Variant = _clip.get_item_metadata(index)
	if metadata is Dictionary:
		if metadata.get("type") == "depth-demo":
			_start_environment_demo()
			return
		if metadata.get("type") == "viewpoint":
			_environment_demo_enabled = false
			_playing = false
			_play.text = "Play"
			if _environment_view != null:
				var viewpoint_id := String(metadata.id)
				if _environment_view.set_review_viewpoint(viewpoint_id):
					_environment_acceptance["interactive/" + viewpoint_id] = _environment_view.acceptance_evidence(_environment_demo_route)
					_update_environment_review_status()
			return
		if metadata.get("type") == "bout":
			_start_bout(bool(metadata.get("stronger", false)))
			return
	if candidate.get("kind", "") == "arena":
		if index > 0:
			_start_bout(index == 2)
		else:
			_playing = false
			_play.text = "Play"
			_arena_view.render_session({})
	elif _tiles != null:
		_tile_sample()
		if index > 0:
			var selection: Array = _clip.get_item_metadata(index)
			var cells: Array[Vector2i] = []
			for x: int in 6:
				for y: int in 5:
					cells.append(Vector2i(x, y))
			_tiles.set_cells_terrain_connect(cells, int(selection[0]), int(selection[1]))
		queue_redraw()
	else:
		_render_animation()


func _tile_sample() -> void:
	_tiles.clear()
	var tiles: Array = manifest.get("tiles", [])
	for x: int in 6:
		for y: int in 5:
			var tile: Dictionary = tiles[(x + y * 6) % tiles.size()]
			_tiles.set_cell(Vector2i(x, y), 0, Vector2i(int(tile.atlas[0]), int(tile.atlas[1])), int(tile.get("alternative", 0)))


func _start_bout(stronger: bool) -> void:
	if _arena_view == null and _environment_view == null:
		return
	for fighter: Variant in _fighters.values():
		if is_instance_valid(fighter):
			fighter.free()
	_fighters.clear()
	_environment_demo_enabled = false
	if _environment_actor != null:
		_environment_actor.visible = false
	if _environment_vfx != null:
		_environment_vfx.visible = false
	var player := BattleSimulator.training_opponent(2468)
	player["fighter_id"] = "player"
	player["display_name"] = "Review player"
	if stronger:
		player.stats.speed = 30
		player.stats.brains = 40
	var opponent := BattleSimulator.training_opponent(2468)
	opponent["fighter_id"] = "opponent"
	_session = BattleSimulator.create_session("review-2468", 2468, player, opponent, manifest)
	if not _session.get("ok", false):
		_status.text = "Arena combat validation failed: " + str(_session.get("error", "unknown"))
		_session.clear()
		return
	for id: String in _session.actors:
		var actor: Dictionary = _session.actors[id]
		if _environment_view != null:
			var presentation := CompanionPresentation3D.new()
			_environment_view.attach_world_node(presentation)
			presentation.configure("agumon")
			presentation.set_ground_position(BattleSimulator.ground_position(actor))
			presentation.play_loop("idle")
			_fighters[id] = presentation
		else:
			var avatar := CompanionAvatar.new()
			_arena_view.add_child(avatar)
			avatar.configure("agumon")
			avatar.sprite.scale = Vector2.ONE * 0.5
			avatar.roaming_enabled = false
			avatar.position = _arena_view.project(BattleSimulator.ground_position(actor))
			_fighters[id] = avatar
	_accumulator = 0
	if _arena_view != null:
		_arena_view.render_session(_session)
	elif _environment_view != null:
		var first := BattleSimulator.ground_position(_session.actors.player)
		var second := BattleSimulator.ground_position(_session.actors.opponent)
		_environment_view.clear_review_viewpoint()
		_environment_view.frame_ground_bounds(Rect2(first.min(second), (second - first).abs()), Vector2(96, 128), true)
	_playing = true
	_play.text = "Pause"


func _create_environment_view() -> void:
	if _environment_view != null:
		return
	_environment_view = EnvironmentView3D.new()
	_environment_view.name = "EnvironmentReview3D"
	_environment_view.position = _stage.position + Vector2(15, 15)
	_environment_view.size = _stage.size - Vector2(30, 30)
	add_child(_environment_view)


func _load_environment_dependency(binding: Variant) -> bool:
	if not binding is Dictionary:
		_status.text = "Candidate has no valid pinned Environment binding."
		return false
	var package := EnvironmentAssetLibrary.activate_pin(binding)
	if package.is_empty() and GameState.isolated_mode and _verified_dev_review_candidate():
		# Deliberately separate from production activation: only an explicitly
		# marked, hash-verified review package may resolve its adjacent Environment.
		var relative := String(candidate.get("environmentPackage", ""))
		if relative == "environment":
			package = EnvironmentAssetLibrary.activate_isolated_dev_fixture(binding, candidate_path.path_join(relative), true)
	if package.is_empty():
		_status.text = "Pinned Environment is missing or differs from the approved runtime catalog."
		return false
	_create_environment_view()
	if not _environment_view.configure_package(package):
		EnvironmentAssetLibrary.clear_active()
		_status.text = "Pinned Environment cannot be rendered; this candidate cannot be approved."
		return false
	return true


func _verified_dev_review_candidate() -> bool:
	if candidate.get("devFixture") != true or candidate.get("kind") not in ["arena", "habitat"]:
		return false
	if candidate.get("nativeResources") != true or not candidate.get("files") is Dictionary or candidate.files.is_empty():
		return false
	if String(candidate.get("contentSha256", "")) != EnvironmentAssetLibrary.metadata_content_sha256(candidate):
		return false
	for relative_value: Variant in candidate.files:
		var relative := String(relative_value)
		if not _safe_dev_relative(relative):
			return false
		var expected := String(candidate.files[relative_value])
		var path := candidate_path.path_join(relative)
		if not expected.begins_with("sha256:") or expected.length() != 71 or not FileAccess.file_exists(path) or "sha256:" + FileAccess.get_sha256(path) != expected:
			return false
	var kind := String(candidate.kind)
	var manifest_file := kind + ".json"
	var native_file := kind + ".tres"
	if not candidate.files.has(manifest_file) or not candidate.files.has(native_file) or not ResourceLoader.exists(candidate_path.path_join(native_file)):
		return false
	var native := ResourceLoader.load(candidate_path.path_join(native_file))
	if native == null or not native.has_meta("candidate_identity"):
		return false
	var identity: Variant = native.get_meta("candidate_identity")
	if not identity is Dictionary or String(identity.get("kind", "")) != kind \
			or String(identity.get("assetId", "")) != String(candidate.get("assetId", "")) \
			or String(identity.get("revision", "")) != String(candidate.get("revision", "")):
		return false
	var review_manifest := AssetResourceLibrary.read_json(candidate_path.path_join(manifest_file))
	return not review_manifest.is_empty() and review_manifest.get("environment") == manifest.get("environment")


func _safe_dev_relative(value: String) -> bool:
	return not value.is_empty() and not value.is_absolute_path() and not value.contains("\\") \
		and value not in [".", ".."] and ".." not in value.split("/")


func _add_environment_viewpoints() -> void:
	_add_review_item("Depth traversal + VFX", {"type": "depth-demo"})
	for id: String in ["center", "left", "right", "near", "far"]:
		_add_review_item(id.capitalize() + " camera", {"type": "viewpoint", "id": id})
	_environment_view.clear_review_viewpoint()


func _activate_environment_review() -> void:
	if _environment_view == null:
		return
	_target_size_picker.visible = true
	_set_environment_target_size(Vector2i(390, 844))
	if not is_instance_valid(_environment_actor):
		_environment_actor = CompanionPresentation3D.new()
		_environment_actor.name = "DepthReviewActor"
		_environment_view.attach_world_node(_environment_actor)
		_environment_actor.configure("agumon")
		_environment_vfx = _make_environment_review_vfx()
		_environment_actor.add_child(_environment_vfx)
	var bounds_value: Variant = _environment_view.environment_manifest.get("camera", {}).get("movementBounds")
	if bounds_value is Array and bounds_value.size() == 4:
		var bounds := Rect2(float(bounds_value[0]), float(bounds_value[1]), float(bounds_value[2]), float(bounds_value[3]))
		_environment_demo_route = _environment_view.build_depth_traversal_route(36.0)
		if _environment_demo_route.size() < 2 or not _environment_view.route_segments_are_clear(_environment_demo_route):
			_status.text = "No collision-clear depth traversal can be constructed around the authored footprints."
			return
		_environment_demo_from = _environment_demo_route[0]
		_environment_demo_to = _environment_demo_route[1]
	_record_environment_acceptance_matrix()
	_start_environment_demo()


func _set_environment_target_size(target_size: Vector2i) -> void:
	if target_size not in EnvironmentPresentationContract.TARGET_SIZES:
		return
	get_tree().root.content_scale_size = Vector2i(1080, 1280)
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_size(Vector2i(1080, 1280))
	_stage = Rect2(Vector2((1080.0 - target_size.x) * 0.5, 185.0), Vector2(target_size))
	_environment_view.position = _stage.position
	_environment_view.size = _stage.size
	_footer.position = Vector2(35.0, _stage.end.y + 10.0)
	_environment_acceptance["%dx%d" % [target_size.x, target_size.y]] = _environment_view.instrumentation()
	queue_redraw()


func _start_environment_demo() -> void:
	if _environment_view == null or _environment_actor == null:
		return
	_session.clear()
	for fighter: Variant in _fighters.values():
		if is_instance_valid(fighter):
			fighter.free()
	_fighters.clear()
	_environment_view.clear_review_viewpoint()
	_environment_demo_enabled = true
	_environment_demo_elapsed = 0.0
	_environment_actor.visible = true
	_environment_actor.set_ground_position(_environment_demo_from)
	_environment_actor.set_facing_from_motion(_environment_demo_to - _environment_demo_from)
	_environment_actor.play_loop("move")
	_environment_vfx.visible = true
	_playing = true
	_play.text = "Pause"
	_update_environment_review_status()


func _advance_environment_demo(delta: float) -> void:
	if _environment_actor == null or _environment_vfx == null or _environment_demo_route.size() < 2:
		return
	var traversal: Array[Vector2] = _environment_demo_route.duplicate()
	for index: int in range(_environment_demo_route.size() - 2, 0, -1):
		traversal.append(_environment_demo_route[index])
	var segment_count := traversal.size()
	var total_duration := float(segment_count) * 1.25
	_environment_demo_elapsed = fmod(_environment_demo_elapsed + maxf(delta, 0.0), total_duration)
	var segment_float := _environment_demo_elapsed / 1.25
	var segment_index := mini(floori(segment_float), segment_count - 1)
	var next_index := (segment_index + 1) % traversal.size()
	var progress := segment_float - floorf(segment_float)
	var from := traversal[segment_index]
	var to := traversal[next_index]
	var direction := to - from
	var ground_position := from.lerp(to, progress)
	_environment_actor.set_ground_position(ground_position)
	_environment_actor.set_facing_from_motion(direction)
	_environment_actor.render_combat("move", _environment_actor.facing, _environment_demo_elapsed * 30.0, 1.0)
	_environment_vfx.position.x = 2.1 + sin(_environment_demo_elapsed * 5.0) * 0.35
	_environment_vfx.modulate.a = 0.72 + sin(_environment_demo_elapsed * 7.0) * 0.18
	_environment_view.set_home_follow(ground_position)
	_update_environment_review_status()


func _update_environment_review_status() -> void:
	if _environment_view == null:
		return
	var stats := _environment_view.instrumentation()
	_status.text = "%s / %s · %s · %d×%d portrait target\nDepth traversal clear: %s · alpha-cut actor + prepass VFX · nodes %d · textures %d · draws≈%d · avg %.2f ms." % [
		candidate.get("assetId", "?"), candidate.get("revision", "?"), candidate.get("kind", "environment"),
		roundi(_environment_view.size.x), roundi(_environment_view.size.y),
		str(_environment_view.route_segments_are_clear(_environment_demo_route)), int(stats.nodes), int(stats.textures), int(stats.drawCallEstimate), float(stats.averageFrameMs)]


func _record_environment_acceptance_matrix() -> void:
	if _environment_view == null:
		return
	_environment_acceptance.clear()
	for target: Vector2i in EnvironmentPresentationContract.TARGET_SIZES:
		_set_environment_target_size(target)
		for viewpoint: String in ["center", "left", "right", "near", "far"]:
			if _environment_view.set_review_viewpoint(viewpoint):
				_environment_acceptance["%dx%d/%s" % [target.x, target.y, viewpoint]] = _environment_view.acceptance_evidence(_environment_demo_route)
	_set_environment_target_size(Vector2i(390, 844))
	_environment_view.clear_review_viewpoint()


func _make_environment_review_vfx() -> WorldVFX3D:
	var effect := WorldVFX3D.new()
	effect.name = "DepthReviewVFX"
	var image := Image.create(24, 24, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	for y: int in 24:
		for x: int in 24:
			var radius := Vector2(float(x) - 11.5, float(y) - 11.5).length()
			if radius <= 10.5:
				image.set_pixel(x, y, Color(1.0, 0.32 + (10.5 - radius) * 0.035, 0.08, 0.88))
	if not effect.configure(ImageTexture.create_from_image(image), {
		"alphaMode": "transparent",
		"depthBehavior": "prepass",
		"renderPriority": 3,
		"pixelSize": 0.055,
	}):
		push_error("Reviewer VFX profile is invalid")
		return effect
	effect.position = Vector3(2.1, 2.0, 0.08)
	return effect


func _add_review_item(label: String, metadata: Dictionary) -> void:
	_clip.add_item(label)
	_clip.set_item_metadata(_clip.item_count - 1, metadata)


func _selected_review_type() -> String:
	if _clip.item_count == 0:
		return ""
	var metadata: Variant = _clip.get_item_metadata(_clip.selected)
	return String(metadata.get("type", "")) if metadata is Dictionary else ""


func _set_habitat_3d_overlays() -> void:
	var collision: Array = []
	for blocker: Dictionary in manifest.get("blockers", []):
		collision.append([float(blocker.rect[0]) * 32.0, float(blocker.rect[1]) * 32.0,
			float(blocker.rect[2]) * 32.0, float(blocker.rect[3]) * 32.0])
	var navigation: Array = []
	for zone: Dictionary in manifest.get("decorationZones", []):
		navigation.append([float(zone.rect[0]) * 32.0, float(zone.rect[1]) * 32.0,
			float(zone.rect[2]) * 32.0, float(zone.rect[3]) * 32.0])
	_environment_view.set_debug_rectangles("Collision", collision, Color(1.0, 0.3, 0.3, 0.42))
	_environment_view.set_debug_rectangles("Navigation", navigation, Color(0.3, 0.55, 1.0, 0.23))
	_update_environment_overlay_visibility()


func _set_arena_3d_overlays() -> void:
	var movement: Array = []
	var sight: Array = []
	var occlusion: Array = []
	for obstacle: Dictionary in manifest.get("obstacles", []):
		if obstacle.get("movement", false) or obstacle.get("projectile", false):
			movement.append(obstacle.rect)
		if obstacle.get("sight", false):
			sight.append(obstacle.rect)
		if obstacle.get("occlusion", false):
			occlusion.append(obstacle.rect)
	_environment_view.set_debug_rectangles("Collision", movement, Color(1.0, 0.3, 0.3, 0.42))
	_environment_view.set_debug_rectangles("Navigation", sight, Color(0.3, 0.55, 1.0, 0.3))
	_environment_view.set_debug_rectangles("Occlusion", occlusion, Color(0.75, 0.35, 1.0, 0.34))
	_update_environment_overlay_visibility()


func _update_environment_overlay_visibility() -> void:
	if _environment_view == null:
		return
	_environment_view.set_debug_group_visible("Collision", _debug and _collision_overlay)
	_environment_view.set_debug_group_visible("Navigation", _debug and _navigation_overlay)
	_environment_view.set_debug_group_visible("Occlusion", _debug and _occlusion_overlay)


func _draw() -> void:
	draw_rect(Rect2(0, 0, 1080, 800), Color("0c1515"))
	draw_rect(_stage, _background)
	draw_rect(_stage, Color("68887b"), false, 1)
	if _debug_canvas != null:
		_debug_canvas.queue_redraw()


func _draw_debug(canvas: Node2D) -> void:
	if not _debug:
		return
	if _avatar != null and _avatar.sprite.sprite_frames != null:
		var sprite := _avatar.sprite
		var texture := sprite.sprite_frames.get_frame_texture(sprite.animation, sprite.frame)
		if texture != null:
			var size := texture.get_size() * sprite.scale
			var top := _avatar.position + sprite.offset * sprite.scale - size * 0.5
			canvas.draw_rect(Rect2(top, size), Color.CYAN, false, 1)
			canvas.draw_line(_avatar.position - Vector2(10, 0), _avatar.position + Vector2(10, 0), Color.CYAN, 2)
			canvas.draw_line(_avatar.position - Vector2(0, 10), _avatar.position + Vector2(0, 10), Color.CYAN, 2)
	elif _atlas_sprite != null and _atlas_sprite.texture != null:
		var origin := _atlas_sprite.position - _atlas_sprite.texture.get_size() * _zoom * 0.5
		for frame: Dictionary in manifest.get("frames", {}).values():
			var rect: Dictionary = frame.frame
			canvas.draw_rect(Rect2(origin + Vector2(rect.x, rect.y) * _zoom, Vector2(rect.w, rect.h) * _zoom), Color.CYAN, false, 1)
	elif _tiles != null:
		_draw_tile_overlays(canvas)


func _draw_tile_overlays(canvas: Node2D) -> void:
	var source := _tiles.tile_set.get_source(0) as TileSetAtlasSource
	for cell: Vector2i in _tiles.get_used_cells():
		var data := source.get_tile_data(_tiles.get_cell_atlas_coords(cell), _tiles.get_cell_alternative_tile(cell))
		var origin := _tiles.position + _tiles.map_to_local(cell) * _zoom
		if _collision_overlay:
			for index: int in data.get_collision_polygons_count(0):
				_draw_polygon_outline(canvas, data.get_collision_polygon_points(0, index), origin, Color.SALMON)
		var nav := data.get_navigation_polygon(0)
		if nav != null and _navigation_overlay:
			for index: int in nav.get_outline_count():
				_draw_polygon_outline(canvas, nav.get_outline(index), origin, Color.CORNFLOWER_BLUE)
		if _occlusion_overlay:
			for index: int in data.get_occluder_polygons_count(0):
				_draw_polygon_outline(canvas, data.get_occluder_polygon(0, index).polygon, origin, Color.MEDIUM_PURPLE)


func _draw_polygon_outline(canvas: Node2D, points: PackedVector2Array, origin: Vector2, color: Color) -> void:
	var transformed := PackedVector2Array()
	for point: Vector2 in points:
		transformed.append(origin + point * _zoom)
	if not transformed.is_empty():
		transformed.append(transformed[0])
		canvas.draw_polyline(transformed, color, 1.5)


func _load_texture(path: String) -> Texture2D:
	return AssetResourceLibrary.load_payload_texture(path)
