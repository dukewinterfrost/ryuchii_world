class_name GreenShade3DSpike
extends Control

const ACTIONS := ["idle", "move", "eat", "special_attack", "pepper_breath"]
const ENVIRONMENT_FIXTURE_PATH := "res://tests/fixtures/environments/green-shade-3d-spike/environment.json"
const MOVE_ROUTE := [
	Vector2(544.0, 704.0), # Behind/left of the authored tree footprint.
	Vector2(544.0, 896.0), # In front/left; attacks are reviewed from here.
	Vector2(768.0, 896.0), # In front/right.
	Vector2(768.0, 704.0), # Behind/right.
]
const ACTION_DURATIONS := {
	"idle": 2.0,
	"move": 4.0,
	"eat": 3.0,
	"special_attack": 2.4,
	"pepper_breath": 2.4,
}

@onready var environment: EnvironmentView3D = $EnvironmentView3D
var companion: CompanionPresentation3D
var attack_vfx := WorldVFX3D.new()
var status_label: Label
var current_action := "idle"
var _action_elapsed := 0.0
var _sequence_index := 0
var _route_target_index := 1
var _move_from: Vector2 = MOVE_ROUTE[0]
var _move_to: Vector2 = MOVE_ROUTE[1]
var _camera_pan := Vector2.ZERO


func _ready() -> void:
	if not environment.load_environment(ENVIRONMENT_FIXTURE_PATH):
		push_error("Green Shade spike could not load its compiled non-promoted environment fixture")
		return
	if not environment.set_static_placements([{
		"id": "green-shade-spike-tree",
		"planeStack": "green-shade-tree.stack",
		"cell": [20, 24],
		"rotationQuarterTurns": 0,
	}], "habitat"):
		push_error("Green Shade spike could not place its manifest plane stack")
		return
	companion = CompanionPresentation3D.new()
	companion.name = "AgumonPresentation3D"
	environment.attach_world_node(companion)
	companion.set_ground_position(_move_from)
	companion.configure("agumon")
	_build_attack_vfx()
	_build_controls()
	play_demo_action("idle")
	set_process(true)

func _process(delta: float) -> void:
	advance_demo(delta)


func advance_demo(delta: float) -> void:
	if companion == null:
		return
	_action_elapsed += maxf(delta, 0.0)
	if current_action == "move":
		var progress := clampf(_action_elapsed / float(ACTION_DURATIONS.move), 0.0, 1.0)
		var eased := progress * progress * (3.0 - 2.0 * progress)
		var ground_position := _move_from.lerp(_move_to, eased)
		companion.set_ground_position(ground_position)
		companion.set_facing_from_motion(_move_to - _move_from)
	else:
		_update_attack_vfx()
	environment.update_home_target(companion.get_ground_position())
	if _action_elapsed >= float(ACTION_DURATIONS[current_action]):
		_sequence_index = (_sequence_index + 1) % ACTIONS.size()
		play_demo_action(ACTIONS[_sequence_index])


func play_demo_action(action: String) -> void:
	if action not in ACTIONS or companion == null:
		return
	current_action = action
	_sequence_index = ACTIONS.find(action)
	_action_elapsed = 0.0
	attack_vfx.visible = action in ["special_attack", "pepper_breath"]
	if action == "move":
		_move_from = companion.get_ground_position()
		if _move_from.distance_to(_move_to) < 1.0:
			_route_target_index = (_route_target_index + 1) % MOVE_ROUTE.size()
			_move_to = MOVE_ROUTE[_route_target_index]
		companion.set_facing_from_motion(_move_to - _move_from)
		companion.play_loop("move")
	elif action == "idle":
		companion.play_loop("idle")
	else:
		companion.play_action(action)
	_update_attack_vfx()
	_update_status()


func pan_camera(cell_delta: Vector2) -> void:
	_camera_pan += cell_delta * EnvironmentView3D.GROUND_UNITS_PER_CELL
	_camera_pan.x = clampf(_camera_pan.x, -192.0, 192.0)
	environment.set_home_manual_pan(_camera_pan)


func reset_camera() -> void:
	_camera_pan = Vector2.ZERO
	environment.set_home_follow(companion.get_ground_position())


func _build_attack_vfx() -> void:
	attack_vfx.name = "PepperBreathPreview"
	if not attack_vfx.configure(_make_flame_texture(), {
		"alphaMode": "transparent",
		"depthBehavior": "prepass",
		"renderPriority": 4,
		"pixelSize": 0.07,
	}):
		push_error("Pepper Breath VFX profile is invalid")
		return
	attack_vfx.position = Vector3(0.0, 2.35, 0.55)
	attack_vfx.visible = false
	companion.add_child(attack_vfx)


func _update_attack_vfx() -> void:
	if not attack_vfx.visible:
		return
	var duration := float(ACTION_DURATIONS[current_action])
	var progress := clampf(_action_elapsed / duration, 0.0, 1.0)
	var direction := -1.0 if companion.facing in ["nw", "w", "sw"] else 1.0
	attack_vfx.flip_h = direction < 0.0
	attack_vfx.position.x = direction * lerpf(1.1, 6.4, progress)
	attack_vfx.position.y = 2.35 + sin(progress * PI) * 0.35


func _build_controls() -> void:
	var margin := MarginContainer.new()
	margin.name = "SpikeControls"
	margin.set_anchors_preset(Control.PRESET_TOP_WIDE)
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 12)
	add_child(margin)
	var panel := PanelContainer.new()
	margin.add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	var title := Label.new()
	title.text = "GREEN SHADE • 3D SPIKE"
	box.add_child(title)
	status_label = Label.new()
	status_label.name = "Status"
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(status_label)
	var actions := GridContainer.new()
	actions.columns = 5
	box.add_child(actions)
	for action: String in ACTIONS:
		var button := Button.new()
		button.name = action.to_pascal_case() + "Button"
		button.text = {"special_attack": "Special", "pepper_breath": "Pepper"}.get(action, action.capitalize())
		button.pressed.connect(play_demo_action.bind(action))
		actions.add_child(button)
	var camera_controls := HBoxContainer.new()
	box.add_child(camera_controls)
	for definition: Dictionary in [
		{"text": "Left", "delta": Vector2(-2, 0)},
		{"text": "Follow", "delta": Vector2.ZERO},
		{"text": "Right", "delta": Vector2(2, 0)},
	]:
		var button := Button.new()
		button.text = String(definition.text)
		if definition.delta == Vector2.ZERO:
			button.pressed.connect(reset_camera)
		else:
			button.pressed.connect(pan_camera.bind(definition.delta))
		camera_controls.add_child(button)


func _update_status() -> void:
	if status_label == null:
		return
	var fallback := "" if companion.visual_fallback.is_empty() else "\nNo attack-body clip; VFX-only preview."
	var side := "front" if companion.get_ground_position().y > 832.0 else "behind"
	status_label.text = "Action: %s | Clip: %s | Tree depth: %s%s" % [current_action, companion.resolved_animation, side, fallback]


static func _make_flame_texture() -> Texture2D:
	var image := Image.create(32, 16, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	for y: int in 16:
		for x: int in 32:
			var nx := (float(x) - 15.5) / 16.0
			var ny := (float(y) - 7.5) / 8.0
			if nx * nx + ny * ny <= 1.0:
				var color := Color("ff7f24") if x < 22 else Color("ffd84a")
				color.a = 1.0
				image.set_pixel(x, y, color)
	return ImageTexture.create_from_image(image)
