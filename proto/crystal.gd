class_name ProtoCrystal
extends RefCounted
## Кристалл природной формы: шестигранная призма с неравными гранями (как у
## кварца), слегка сужается к вершине и кончается шестигранной пирамидой,
## вершина чуть смещена. Плоские грани, полупрозрачный материал со свечением
## изнутри.

## len — полная длина от основания (y = 0) до вершины, r — радиус призмы.
static func mesh(len: float, r: float, rng: RandomNumberGenerator) -> ArrayMesh:
	var tip_h := r * rng.randf_range(1.2, 1.9)
	var body := maxf(len - tip_h, r)
	var bot := []
	var top := []
	for i in 6:
		var a := i * TAU / 6.0 + rng.randf_range(-0.12, 0.12)
		var rr := r * rng.randf_range(0.8, 1.15)
		bot.append(Vector3(cos(a) * rr, 0.0, sin(a) * rr))
		top.append(Vector3(cos(a) * rr * 0.9, body, sin(a) * rr * 0.9))
	var apex := Vector3(rng.randf_range(-0.25, 0.25) * r, body + tip_h, rng.randf_range(-0.25, 0.25) * r)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(0xFFFFFFFF)
	for i in 6:
		var j := (i + 1) % 6
		# Боковая грань призмы (лицом наружу).
		_tri(st, bot[i], top[j], top[i])
		_tri(st, bot[i], bot[j], top[j])
		# Грань пирамиды.
		_tri(st, top[i], top[j], apex)
		# Дно (утоплено в породу, но пусть будет закрыто).
		_tri(st, Vector3.ZERO, bot[j], bot[i])
	st.generate_normals()
	return st.commit()

static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	# Выпуклое тело вокруг оси Y: разворачиваем треугольник наружу.
	var cen := Vector3(0, (a.y + b.y + c.y) / 3.0, 0)
	if (b - a).cross(c - a).dot((a + b + c) / 3.0 - cen) < 0.0:
		var t := b
		b = c
		c = t
	st.add_vertex(a)
	st.add_vertex(c)
	st.add_vertex(b)

static func material(col: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(col.lerp(Color.WHITE, 0.25), 0.72)
	m.roughness = 0.08
	m.metallic = 0.1
	m.specular = 0.9
	m.rim_enabled = true
	m.rim = 0.6
	m.rim_tint = 0.3
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = 0.55
	return m
