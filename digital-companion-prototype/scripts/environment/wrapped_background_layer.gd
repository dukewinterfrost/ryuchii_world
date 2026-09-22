@tool
extends Sprite3D
## Retains the existing texture/lighting binding, but displays a closed scenery
## ribbon instead of a billboard. Trees and gameplay never belong to this mesh.
@export_range(40.0,240.0,1.0) var wrap_radius := 120.0:
	set(value):
		if is_inside_tree(): position.z += wrap_radius-value
		wrap_radius = value
		if is_inside_tree(): rebuild_wrap()
@export_range(2,8,2) var artwork_repeats := 4:
	set(value):
		artwork_repeats = value
		if is_inside_tree(): rebuild_wrap()
@export_range(0.5,2.0,0.05) var height_scale := 1.0:
	set(value):
		height_scale = value
		if is_inside_tree(): rebuild_wrap()
@export_tool_button("Rebuild background wrap") var rebuild_button = rebuild_wrap
@export_range(0.0,2.0,0.05) var artwork_phase := 1.5:
	set(value):
		artwork_phase = value
		if is_inside_tree(): rebuild_wrap()
var ribbon: MeshInstance3D
const SEGMENTS := 384

func _ready() -> void:
	# Hide only this source billboard, not the child mesh or any tree nodes.
	layers = 0
	rebuild_wrap()

func canvas_height() -> float:
	return TAU*wrap_radius/artwork_repeats * texture.get_height()/texture.get_width()*height_scale

func rebuild_wrap() -> void:
	if texture == null: return
	if not is_instance_valid(ribbon):
		ribbon = MeshInstance3D.new()
		ribbon.name = "BackgroundRibbon"
		add_child(ribbon,false,Node.INTERNAL_MODE_BACK)
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var height := canvas_height()
	for i: int in SEGMENTS:
		var a := TAU*i/SEGMENTS
		var b := TAU*(i+1)/SEGMENTS
		var pa := Vector3(sin(a)*wrap_radius,0,(1.0-cos(a))*wrap_radius)
		var pb := Vector3(sin(b)*wrap_radius,0,(1.0-cos(b))*wrap_radius)
		var ua := mirrored_u(float(i)/SEGMENTS)
		var ub := mirrored_u(float(i+1)/SEGMENTS)
		var inward := Vector3(-sin((a+b)*0.5),0,cos((a+b)*0.5))
		for corner: Array in [[pa,Vector2(ua,1)],[pa+Vector3.UP*height,Vector2(ua,0)],[pb,Vector2(ub,1)],
			[pb,Vector2(ub,1)],[pa+Vector3.UP*height,Vector2(ua,0)],[pb+Vector3.UP*height,Vector2(ub,0)]]:
			vertices.append(corner[0])
			normals.append(inward)
			uvs.append(corner[1])
		# Continue the bottom edge below the world's lower floor. This closes
		# gaps exposed by perspective between widely separated artwork layers.
		for corner: Array in [[pa+Vector3.DOWN*200,Vector2(ua,1)],[pa,Vector2(ua,1)],[pb+Vector3.DOWN*200,Vector2(ub,1)],
			[pb+Vector3.DOWN*200,Vector2(ub,1)],[pa,Vector2(ua,1)],[pb,Vector2(ub,1)]]:
			vertices.append(corner[0])
			normals.append(inward)
			uvs.append(corner[1])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	var mesh_data := ArrayMesh.new()
	mesh_data.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	ribbon.mesh = mesh_data
	# Preserve the instance-local day/night binding when geometry is rebuilt.
	if ribbon.material_override == null and ribbon.get_surface_override_material(0) == null:
		refresh_wrapped_material()

func mirrored_u(turn: float) -> float:
	# Mirrored repeats join the same edge texels. No new raster derivatives.
	return absf(1.0-fposmod(turn*artwork_repeats+artwork_phase,2.0))

func refresh_wrapped_material() -> void:
	if not is_instance_valid(ribbon): return
	if material_override is ShaderMaterial:
		var sky := material_override as ShaderMaterial
		sky.set_shader_parameter("wrapped_background",true)
		ribbon.material_override = sky
		# The sky shader extends the upper clear sky above the original canvas.
		ribbon.extra_cull_margin = canvas_height()*4.0
	else:
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		material.texture_repeat = false
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		material.alpha_scissor_threshold = 0.5
		material.albedo_texture = texture
		material.cull_mode = BaseMaterial3D.CULL_BACK
		ribbon.material_override = material
