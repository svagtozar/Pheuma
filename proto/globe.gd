class_name ProtoGlobe
extends RefCounted
## Прототип: вся планета шаром — рельеф из того же шума по направлению на
## сфере (без швов), цвета из палитры рельефа, низины под жидкостью, шапки у
## полюсов. Место посадки (участок с заводом) — светлая метка.

static func build(planet: Planet, t: ProtoTerrain, radius := 10.0, site := Vector2(0.35, 0.3)) -> Node3D:
	var root := Node3D.new()
	root.name = "globe"
	var n := FastNoiseLite.new()
	n.seed = t.noise.seed
	n.frequency = 1.1
	n.fractal_octaves = 6
	var ridge := FastNoiseLite.new()
	ridge.seed = t.noise.seed + 91
	ridge.frequency = 2.2
	ridge.fractal_octaves = 4
	ridge.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	var volcanic := planet.has_tag("volcanic")
	var frozen := planet.has_tag("frozen") or planet.ambient_temp < -40.0
	var sea := Color(0.95, 0.42, 0.1) if volcanic else (Color(0.75, 0.85, 0.92) if frozen else Color(0.2, 0.36, 0.45))
	var cap := Color(0.9, 0.92, 0.95)
	var sea_level := -0.05 if volcanic else 0.02
	var sm := SphereMesh.new()
	sm.radius = radius
	sm.height = radius * 2.0
	sm.radial_segments = 256
	sm.rings = 128
	var arr := sm.get_mesh_arrays()
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var cols := PackedColorArray()
	cols.resize(verts.size())
	var hs := PackedFloat32Array()
	hs.resize(verts.size())
	for i in verts.size():
		var d := verts[i].normalized()
		var h := n.get_noise_3dv(d * 1.0) * 0.6 + ridge.get_noise_3dv(d) * 0.35
		hs[i] = h
		var lat := absf(d.y)
		var c := t.ground.lerp(t.cliff, clampf((h - 0.05) * 3.0, 0.0, 1.0))
		c = c * (0.85 + 0.3 * n.get_noise_3dv(d * 6.0))
		if h < sea_level:
			c = sea.darkened(clampf((sea_level - h) * 1.5, 0.0, 0.4))
		elif h > 0.32:
			c = c.lightened(0.25)
		if not volcanic and lat > 0.86 - h * 0.2:
			c = cap
		c.a = 1.0
		cols[i] = c
		verts[i] = d * radius * (1.0 + maxf(h, sea_level) * 0.035)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_NORMAL] = null
	arr[Mesh.ARRAY_TANGENT] = null
	var st := SurfaceTool.new()
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	st.create_from(mesh, 0)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.95
	mi.material_override = mat
	root.add_child(mi)
	# Атмосфера — светящийся ободок.
	var atm := MeshInstance3D.new()
	var am := SphereMesh.new()
	am.radius = radius * 1.04
	am.height = am.radius * 2.0
	atm.mesh = am
	var sh := Shader.new()
	sh.code = ATM
	var amat := ShaderMaterial.new()
	amat.shader = sh
	amat.set_shader_parameter("tint", ProtoSky.ground_color(planet).lerp(Color(0.6, 0.75, 1.0), 0.6))
	atm.material_override = amat
	root.add_child(atm)
	# Метка места посадки: широта/долгота в долях.
	var lon := site.x * TAU
	var la := (site.y - 0.5) * PI
	var dir := Vector3(cos(la) * cos(lon), sin(la), cos(la) * sin(lon))
	var mk := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius * 0.004
	cyl.bottom_radius = radius * 0.012
	cyl.height = radius * 0.12
	mk.mesh = cyl
	var mm := StandardMaterial3D.new()
	mm.albedo_color = Color(1.0, 0.95, 0.6)
	mm.emission_enabled = true
	mm.emission = Color(1.0, 0.85, 0.4)
	mm.emission_energy_multiplier = 3.0
	mk.material_override = mm
	root.add_child(mk)
	mk.position = dir * radius * 1.04
	var side := dir.cross(Vector3.FORWARD if absf(dir.z) < 0.9 else Vector3.RIGHT).normalized()
	mk.basis = Basis(side, dir, side.cross(dir))
	root.set_meta("site_dir", dir)
	return root

const ATM := """
shader_type spatial;
render_mode blend_add, unshaded, cull_front;
uniform vec3 tint : source_color;
void fragment() {
	float r = 1.0 - abs(dot(NORMAL, VIEW));
	ALBEDO = tint * pow(r, 3.0) * 1.4;
	ALPHA = 1.0;
}
"""
