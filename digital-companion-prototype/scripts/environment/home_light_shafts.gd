class_name HomeLightShafts
extends Node3D
## Lightweight depth-tested light ribbons for the Compatibility renderer.
## Positions are fixed in the clearing, independent of camera/gameplay state.
const BEAMS := [
	Vector4(13.0, 16.0, 3.6, 22.0),
	Vector4(24.0, 22.0, 4.4, 25.0),
	Vector4(29.0, 30.0, 3.2, 23.0),
	Vector4(23.0, 27.0, 3.4, 18.0),
	Vector4(23.0, 41.0, 3.4, 22.0),
]
var materials: Array[ShaderMaterial] = []
var reduced_motion := false
var animation_time := 0.0
var daylight_strength := 0.0
var moonlight_strength := 0.0


func _ready() -> void:
	for index: int in BEAMS.size():
		var beam: Vector4 = BEAMS[index]
		var ribbon := MeshInstance3D.new()
		ribbon.name = "Shaft%d" % index
		ribbon.position = Vector3(beam.x, 0.08, beam.y)
		ribbon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# The shader billboards and leans vertices beyond their authored bounds.
		ribbon.custom_aabb = AABB(Vector3(-20, -1, -beam.w), Vector3(40, beam.w + 2, beam.w * 2))
		var quad := QuadMesh.new()
		quad.size = Vector2(beam.z, beam.w)
		quad.center_offset = Vector3(0, beam.w * 0.5, 0)
		var material := ShaderMaterial.new()
		material.shader = preload("res://shaders/home_light_shafts.gdshader")
		material.set_shader_parameter("phase", float(index) * 1.73)
		quad.material = material
		ribbon.mesh = quad
		materials.append(material)
		add_child(ribbon)


func apply_sample(sample: Dictionary) -> void:
	daylight_strength = float(sample.sun_visibility) * (1.0 - float(sample.star_visibility)) * 0.22
	moonlight_strength = float(sample.moon_visibility) * float(sample.star_visibility) * 0.16
	var strength := daylight_strength + moonlight_strength
	visible = strength > 0.0001
	var moon_weight := moonlight_strength / maxf(strength, 0.00001)
	var color := Color("ffe7b0").lerp(Color("afcbff"), moon_weight)
	var source: Vector2 = (sample.sun_position as Vector2).lerp(sample.moon_position, moon_weight)
	for material: ShaderMaterial in materials:
		material.set_shader_parameter("shaft_color", color)
		material.set_shader_parameter("strength", strength)
		material.set_shader_parameter("lean", (source.x - 0.78) * 24.0)


func set_reduced_motion(enabled: bool) -> void:
	reduced_motion = enabled


func _process(delta: float) -> void:
	if reduced_motion or not visible or not is_finite(delta) or delta <= 0.0:
		return
	animation_time += minf(delta, 0.1)
	for material: ShaderMaterial in materials:
		material.set_shader_parameter("animation_time", animation_time)
