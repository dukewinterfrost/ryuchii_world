@tool
extends Node3D
## Presentation-only, editable layered scenery. Never owns collision or RNG.
## Direct children, plus named groups under metadata/depth_layers roots, carry
## metadata/parallax (0 = normal grounded perspective).
@export var reference_focus := Vector3(15, 0, 18)
@export_range(0.0, 8.0, 0.1) var maximum_shift := 3.0
@export var preview_motion := false
@export var home_oval_layout := false

var externally_driven := false
var _bases: Dictionary = {}
var _foreground_cards: Array[Sprite3D] = []

func _ready() -> void:
	if home_oval_layout:
		# Keep the battle's rectangular composition intact. Home has its own
		# authored oval cards, whose Inspector transforms remain editable.
		for child: Node in get_children():
			if child is Node3D and (child.name == &"Boundary" or String(child.name).begins_with("RearTree_") or String(child.name).begins_with("EdgeTree_") or String(child.name).begins_with("Undergrowth_") or String(child.name).begins_with("MeadowPatch_")):
				child.visible = false
	for child in get_children():
		if child is Node3D:
			_bases[child] = child.position
			if child.get_meta("depth_layers", false):
				for layer: Node3D in child.get_children():
					_bases[layer] = layer.position
				for card: Node in child.find_children("*", "Sprite3D", true, false):
					if card.get_meta("camera_clearance", false):
						_foreground_cards.append(card)
	var boundary := get_node_or_null("OvalLayout/Boundary" if home_oval_layout else "Boundary")
	if boundary != null:
		for card: Node in boundary.get_children():
			if card is Sprite3D and (String(card.name).begins_with("South_Forest_") or card.get_meta("camera_clearance", false)):
				_foreground_cards.append(card)

func set_layer_base_position(layer: Node3D, base_position: Vector3) -> void:
	if _bases.has(layer):
		_bases[layer] = base_position
		layer.position = base_position

func apply_focus(focus: Vector3, reduced_motion: bool) -> void:
	# Care reuses the 30x36 composition at 40x48 scale. Convert the world-space
	# camera focus before applying offsets to the authored local card positions.
	var delta := to_local(focus) - reference_focus
	delta.y = 0
	for child: Node3D in _bases:
		var factor := 0.0 if reduced_motion else float(child.get_meta("parallax", 0.0))
		# Nested authored depth layers may use their own scale or rotation.
		var local_delta: Vector3 = child.get_parent().global_basis.inverse() * global_basis * delta
		var shift := (local_delta * factor).limit_length(maximum_shift)
		child.position = _bases[child] + shift
	# The camera can pan right up to the southern boundary. A card between the
	# lens and the inspected field must not become a full-screen wall of leaves.
	# Hide only very near outer-forest cards; the rooted inner hedge stays intact.
	var camera := get_viewport().get_camera_3d()
	if camera != null:
		for card: Sprite3D in _foreground_cards:
			var depth := -camera.to_local(card.global_position).z
			var height := card.region_rect.size.y * card.pixel_size * card.global_basis.get_scale().y
			card.visible = depth > height * 1.7 and not bool(card.get_meta("built_over", false))

func _process(_delta: float) -> void:
	# Inspector transforms never get overwritten in the editor. F6 preview is
	# opt-in; gameplay drives focus explicitly so dolly does not slide plants.
	if Engine.is_editor_hint() or externally_driven or not preview_motion:
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var hit: Variant = Plane(Vector3.UP, 0).intersects_ray(camera.global_position, -camera.global_basis.z)
	if hit is Vector3:
		apply_focus(hit, false)
