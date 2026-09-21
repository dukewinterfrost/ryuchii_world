extends RefCounted
## Shared presentation geometry: flat playable cap, vertical cliff, lower floor.
## Never emits physics. The explicit ground manifests still own navigation.
const SEGMENTS := 256

static func edge_radius(angle: float, radii: Vector2, flat_extents: Vector2) -> float:
	var ray := Vector2(cos(angle),sin(angle))
	# Expand the oval as a whole to contain the rectangular grid/apron. Taking
	# a per-angle max with a rectangle produces conspicuous square corner lobes.
	var safe_radii := radii * maxf(1.0,((flat_extents+Vector2.ONE*0.75)/radii).length()/0.94)
	var ellipse := 1.0 / (ray / safe_radii).length()
	# Modest irregularity preserves an organic oval without eating the grid/apron.
	ellipse *= 1.0 + sin(angle*3.0+0.7)*0.025 + sin(angle*7.0-0.4)*0.014
	return ellipse

static func height_at(point: Vector2, center: Vector2, radii: Vector2, flat_extents: Vector2, drop: float) -> float:
	var relative := point-center
	# Match the authored polygon, not an analytic curve between its samples.
	var angle := fposmod(relative.angle(),TAU)
	var index := int(floor(angle/TAU*SEGMENTS))
	var a := TAU*index/SEGMENTS
	var b := TAU*(index+1)/SEGMENTS
	var first := Vector2(cos(a),sin(a))*edge_radius(a,radii,flat_extents)
	var second := Vector2(cos(b),sin(b))*edge_radius(b,radii,flat_extents)
	var ray := relative.normalized()
	var line := second-first
	var cross := ray.cross(line)
	var radius := first.cross(line)/cross if absf(cross)>0.00001 else first.length()
	return 0.0 if relative.length() <= radius else -drop

static func build(center: Vector2, radii: Vector2, flat_extents: Vector2, extent: Vector2, drop: float, origin: Vector3) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	for i: int in SEGMENTS:
		var a := TAU*i/SEGMENTS
		var b := TAU*(i+1)/SEGMENTS
		var da := Vector2(cos(a),sin(a))
		var db := Vector2(cos(b),sin(b))
		var pa := center+da*edge_radius(a,radii,flat_extents)
		var pb := center+db*edge_radius(b,radii,flat_extents)
		var top_a := Vector3(pa.x,0,pa.y)
		var top_b := Vector3(pb.x,0,pb.y)
		var low_a := top_a-Vector3(0,drop,0)
		var low_b := top_b-Vector3(0,drop,0)
		var outer_a := center+da*minf(extent.x*0.5/maxf(absf(da.x),0.00001),extent.y*0.5/maxf(absf(da.y),0.00001))
		var outer_b := center+db*minf(extent.x*0.5/maxf(absf(db.x),0.00001),extent.y*0.5/maxf(absf(db.y),0.00001))
		var far_a := Vector3(outer_a.x,-drop,outer_a.y)
		var far_b := Vector3(outer_b.x,-drop,outer_b.y)
		var outward := Vector3(da.x+db.x,0,da.y+db.y).normalized()
		for face: Array in [[Vector3(center.x,0,center.y),top_a,top_b,Vector3.UP],
			[top_a,low_a,top_b,outward],[top_b,low_a,low_b,outward],
			[low_a,far_a,low_b,Vector3.UP],[low_b,far_a,far_b,Vector3.UP]]:
			for j: int in 3:
				var p: Vector3 = face[j]
				vertices.append(p-origin)
				normals.append(face[3])
				uvs.append(Vector2(p.x,p.z)/extent)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	var result := ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	return result
