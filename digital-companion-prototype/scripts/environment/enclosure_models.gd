class_name EnclosureModels
extends RefCounted
## Layered miniatures. Ground footprint is gameplay-owned; color/facets are presentation.
## All solid parts share one vertex-color material and reusable meshes per model.
static var _meshes: Dictionary = {}
static var _material: ShaderMaterial
const FLAME = preload("res://assets/enclosure/flame-loop.png")
const REEDS = preload("res://assets/enclosure/pond.png")

static func create(kind: String, identity: String, rotation: int = 0) -> Node3D:
	var root := Node3D.new()
	root.name = "Enclosure_" + identity.sha256_text().left(10)
	root.set_meta("care_instance_id", identity)
	root.set_meta("enclosure_model", kind)
	root.rotation.y = -rotation * PI / 2.0
	if not _meshes.has(kind): _meshes[kind] = _build(kind)
	for layer: String in _meshes[kind]:
		var part := MeshInstance3D.new()
		part.name = layer
		part.mesh = _meshes[kind][layer]
		part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(part)
	if kind == "campfire":
		var flame := Sprite3D.new()
		flame.name = "FlameBetweenLogsAndSpit"
		flame.texture = FLAME
		flame.hframes = 4
		flame.pixel_size = 0.048
		flame.position = Vector3(0, 1.28, 0.1)
		flame.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		flame.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		flame.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
		flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		flame.set_meta("enclosure_flame", true)
		flame.set_meta("enclosure_emissive", true)
		root.add_child(flame)
	if kind == "pond":
		var water := MeshInstance3D.new()
		water.name = "RecessedWater"
		water.mesh = _disc(Vector2(3.08, 2.08), 0.115, Color.WHITE)
		var material := ShaderMaterial.new()
		material.shader = preload("res://shaders/enclosure_water.gdshader")
		water.material_override = material
		water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(water)
		for i: int in 2:
			var reeds := Sprite3D.new()
			reeds.name = "RaisedReeds%d" % i
			reeds.texture = REEDS
			reeds.region_enabled = true
			reeds.region_rect = Rect2(37, 5, 40, 43)
			reeds.pixel_size = 0.049 if i == 0 else 0.036
			reeds.position = Vector3(-2.3 + i * 0.55, 1.12 if i == 0 else 0.85, -1.4 - i * 0.28)
			reeds.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
			reeds.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
			reeds.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
			reeds.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(reeds)
	return root

static func _build(kind: String) -> Dictionary:
	var out := {}
	if kind == "pond":
		out["GroundContact"] = _disc(Vector2(3.92, 2.92), 0.025, Color("625846"))
		var rim := _start()
		for i: int in 22:
			var a := TAU * i / 22.0
			var p := Vector3(cos(a) * 3.43, 0.27, sin(a) * 2.43)
			_rock(rim, p, Vector3(0.56 + 0.05 * (i % 3), 0.29 + 0.05 * (i % 2), 0.43), Color(["a48c69", "927c62", "bba47c", "817465"][i % 4]), a)
		out["RaisedStoneRim"] = _finish(rim)
		var steps := _start()
		_box(steps, Vector3(0, 0.16, 2.53), Vector3(2.1, 0.29, 0.63), Color("cdb58b"))
		_box(steps, Vector3(0, 0.08, 2.83), Vector3(2.3, 0.14, 0.28), Color("a88e68"))
		out["EntrySteps"] = _finish(steps)
	elif kind == "campfire":
		out["GroundContact"] = _disc(Vector2(2.35, 1.88), 0.026, Color("695b45"))
		out["CharcoalBed"] = _disc(Vector2(1.65, 1.32), 0.06, Color("382e29"))
		var stones := _start()
		for i: int in 14:
			var a := TAU * i / 14.0
			_rock(stones, Vector3(cos(a) * 1.85, 0.32, sin(a) * 1.42), Vector3(0.4, 0.35, 0.35), Color(["8e9289", "777e79", "abb0a0"][i % 3]), a)
		out["StoneRing"] = _finish(stones)
		var logs := _start()
		for i: int in 3:
			_box(logs, Vector3(0, 0.32 + i * 0.21, 0), Vector3(2.45, 0.35, 0.38), Color("815033"), -0.7 + i * 0.75)
			_box(logs, Vector3(0, 0.515 + i * 0.21, 0), Vector3(1.95, 0.055, 0.08), Color("b18148"), -0.7 + i * 0.75)
		out["CrossedLogs"] = _finish(logs)
		var spit := _start()
		for x: float in [-1.6, 1.6]:
			_box(spit, Vector3(x, 1.58, -0.25), Vector3(0.19, 3.05, 0.19), Color("815834"))
			_box(spit, Vector3(x - 0.055, 1.58, -0.13), Vector3(0.045, 2.94, 0.045), Color("b3864b"))
		_box(spit, Vector3(0, 2.8, -0.25), Vector3(3.85, 0.16, 0.16), Color("b18856"))
		out["UprightCookingSpit"] = _finish(spit)
	elif kind == "digi_potty":
		out["GroundContact"] = _disc(Vector2(1.88, 1.82), 0.025, Color("645d43"))
		var timber := _start()
		_box(timber, Vector3(0, 0.14, 0), Vector3(3.35, 0.26, 3.35), Color("8e633b"))
		for i: int in 5:
			_box(timber, Vector3(-1.22 + i * 0.61, 1.56, -1.30), Vector3(0.56, 2.63, 0.23), Color("bd915b") if i % 2 else Color("a67949"))
		_box(timber, Vector3(0, 2.84, -1.3), Vector3(3.16, 0.18, 0.3), Color("d0a56b"))
		_box(timber, Vector3(0, 0.31, 1.32), Vector3(2.15, 0.31, 0.73), Color("c29860"))
		out["WoodenBackAndStep"] = _finish(timber)
		var bowl := _start()
		_ring(bowl, Vector2(1.18, 1.02), Vector2(0.86, 0.71), 0.26, 0.43, Color("548f77"))
		_ring(bowl, Vector2(1.31, 1.14), Vector2(0.86, 0.71), 0.41, 1.39, Color("70b597"))
		_ring(bowl, Vector2(1.4, 1.23), Vector2(0.89, 0.74), 1.38, 1.58, Color("c1e5c5"))
		out["RaisedCeramicBowl"] = _finish(bowl)
		out["RecessedBowlInterior"] = _disc(Vector2(0.86, 0.72), 0.64, Color("315d54"))
	elif kind == "planter":
		out["GroundContact"] = _disc(Vector2(0.93, 0.88), 0.025, Color("625b42"))
		var pot := _start()
		_box(pot, Vector3(0, 0.48, 0), Vector3(1.45, 0.91, 1.4), Color("a97450"))
		_box(pot, Vector3(0, 0.99, 0), Vector3(1.65, 0.17, 1.59), Color("c48d60"))
		_box(pot, Vector3(0, 1.085, 0), Vector3(1.32, 0.06, 1.28), Color("473c2d"))
		out["TerracottaPot"] = _finish(pot)
		var leaves := _start()
		for i: int in 7:
			var a := i * TAU / 7
			_rock(leaves, Vector3(cos(a) * 0.39, 1.4 + float(i % 3) * 0.3, sin(a) * 0.4), Vector3(0.46, 0.59, 0.39), Color(["638b43", "3f7144", "84a74d"][i % 3]), a)
		out["LayeredFoliage"] = _finish(leaves)
	elif kind == "rug":
		var rug := _start()
		_box(rug, Vector3(0, 0.055, 0), Vector3(4.85, 0.08, 3.85), Color("bb955c"))
		_box(rug, Vector3(0, 0.102, 0), Vector3(4.28, 0.018, 3.28), Color("456d60"))
		for i: int in 9:
			for z: float in [-1.91, 1.91]: _box(rug, Vector3(-2.05 + i * 0.5, 0.06, z), Vector3(0.2, 0.065, 0.16), Color("dec48b"))
		out["WovenMatAndFringe"] = _finish(rug)
	return out

static func _start() -> SurfaceTool:
	var s := SurfaceTool.new()
	s.begin(Mesh.PRIMITIVE_TRIANGLES)
	return s

static func _finish(s: SurfaceTool) -> ArrayMesh:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = preload("res://shaders/enclosure_surfaces.gdshader")
	s.set_material(_material)
	return s.commit()

static func _quad(s: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, color: Color) -> void:
	s.set_color(color)
	for v: Vector3 in [a,b,c,a,c,d]: s.add_vertex(v)

static func _box(s: SurfaceTool, center: Vector3, size: Vector3, color: Color, angle := 0.0) -> void:
	var points: Array[Vector3] = []
	for y: float in [-0.5,0.5]:
		for z: float in [-0.5,0.5]:
			for x: float in [-0.5,0.5]: points.append(center + (Vector3(x,y,z) * size).rotated(Vector3.UP, angle))
	var faces := [[4,5,7,6],[0,1,5,4],[2,6,7,3],[0,4,6,2],[1,3,7,5]]
	for i: int in faces.size():
		var f: Array = faces[i]
		_quad(s, points[f[0]],points[f[1]],points[f[2]],points[f[3]],color * [1.1,0.76,0.88,0.67,0.93][i])

static func _rock(s: SurfaceTool, center: Vector3, radius: Vector3, color: Color, angle: float) -> void:
	for i: int in 7:
		var a := TAU * i / 7 + angle
		var b := TAU * (i + 1) / 7 + angle
		var low_a := center + Vector3(cos(a)*radius.x, -radius.y*0.65, sin(a)*radius.z)
		var low_b := center + Vector3(cos(b)*radius.x, -radius.y*0.65, sin(b)*radius.z)
		var high_a := center + Vector3(cos(a)*radius.x*0.72, radius.y*0.65, sin(a)*radius.z*0.72)
		var high_b := center + Vector3(cos(b)*radius.x*0.72, radius.y*0.65, sin(b)*radius.z*0.72)
		_quad(s,low_a,low_b,high_b,high_a,color * (0.7 + 0.16 * (sin(a)+1)))
		_quad(s,high_a,high_b,center+Vector3(0,radius.y,0),center+Vector3(0,radius.y,0),color * (1.0 + 0.08*cos(a)))

static func _disc(radii: Vector2, y: float, color: Color) -> ArrayMesh:
	var s := _start()
	for i: int in 32:
		var a := TAU * i / 32
		var b := TAU * (i + 1) / 32
		_quad(s,Vector3.ZERO+Vector3(0,y,0),Vector3(cos(a)*radii.x,y,sin(a)*radii.y),Vector3(cos(b)*radii.x,y,sin(b)*radii.y),Vector3(0,y,0),color)
	return _finish(s)

static func _ring(s: SurfaceTool, outer: Vector2, inner: Vector2, bottom: float, top: float, color: Color) -> void:
	for i: int in 20:
		var a := TAU*i/20
		var b := TAU*(i+1)/20
		var o1 := Vector3(cos(a)*outer.x,top,sin(a)*outer.y)
		var o2 := Vector3(cos(b)*outer.x,top,sin(b)*outer.y)
		var i1 := Vector3(cos(a)*inner.x,top,sin(a)*inner.y)
		var i2 := Vector3(cos(b)*inner.x,top,sin(b)*inner.y)
		_quad(s,o1,o2,i2,i1,color.lightened(0.12))
		_quad(s,o1,Vector3(o1.x,bottom,o1.z),Vector3(o2.x,bottom,o2.z),o2,color*(0.74+0.18*(sin(a)+1)))
		_quad(s,i1,i2,Vector3(i2.x,bottom,i2.z),Vector3(i1.x,bottom,i1.z),color*0.55)
