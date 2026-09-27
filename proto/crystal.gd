class_name ProtoCrystal
extends RefCounted
## Кристалл природной формы: шестигранная призма с неравными гранями (как у
## кварца), слегка сужается к вершине и кончается шестигранной пирамидой,
## вершина чуть смещена. Плоские грани, полупрозрачный материал со свечением
## изнутри; у основания кристалл мутный, к вершине прозрачнее.

## Облик (habit) по тегам планеты (ProtoWorldStyle.habit):
##   prism — призма кварца, needle — тонкие иглы льда, blade — плоские лезвия
##   обсидиана, cube — кубы (как пирит) при сильной тяжести, shard — трёхгранные
##   осколки на сейсмических планетах.
## len — полная длина от основания (y = 0) до вершины, r — радиус призмы.
static func mesh(len: float, r: float, rng: RandomNumberGenerator, habit := "prism") -> ArrayMesh:
	var sides := 6
	var tip_k := rng.randf_range(1.2, 1.9)
	var taper := 0.9
	var flat := 1.0
	var jitter := 0.12
	match habit:
		"needle":
			r *= 0.45; len *= 1.35; tip_k = rng.randf_range(3.0, 5.0); taper = 0.7
		"blade":
			flat = 0.3; tip_k = rng.randf_range(0.6, 1.0); r *= 1.3
		"cube":
			sides = 4; tip_k = 0.0; taper = 1.0; jitter = 0.0; len = r * rng.randf_range(1.8, 2.4); r *= 1.25
		"shard":
			sides = 3; tip_k = rng.randf_range(2.0, 3.2); jitter = 0.35; taper = 0.75
	var tip_h := r * tip_k
	var body := maxf(len - tip_h, r)
	var bot := []
	var top := []
	var a0 := PI / 4.0 if sides == 4 else 0.0
	for i in sides:
		var a := a0 + i * TAU / sides + rng.randf_range(-jitter, jitter)
		var rr := r * (1.0 if sides == 4 else rng.randf_range(0.8, 1.15))
		bot.append(Vector3(cos(a) * rr, 0.0, sin(a) * rr * flat))
		top.append(Vector3(cos(a) * rr * taper, body, sin(a) * rr * taper * flat))
	var apex := Vector3(rng.randf_range(-0.25, 0.25) * r, body + tip_h, rng.randf_range(-0.25, 0.25) * r * flat)
	if sides == 4:
		apex = Vector3(0, body, 0)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(0xFFFFFFFF)
	var top_y := body + tip_h
	for i in sides:
		var j := (i + 1) % sides
		# Боковая грань призмы (лицом наружу).
		_tri(st, top_y, bot[i], top[j], top[i])
		_tri(st, top_y, bot[i], bot[j], top[j])
		# Грань пирамиды.
		_tri(st, top_y, top[i], top[j], apex)
		# Дно (утоплено в породу, но пусть будет закрыто).
		_tri(st, top_y, Vector3.ZERO, bot[j], bot[i])
	st.generate_normals()
	return st.commit()

static func _tri(st: SurfaceTool, top_y: float, a: Vector3, b: Vector3, c: Vector3) -> void:
	# Выпуклое тело вокруг оси Y: разворачиваем треугольник наружу.
	# Центр тела — посередине высоты: так верное направление и у плоской верхушки куба.
	var cen := Vector3(0, top_y * 0.45, 0)
	if (b - a).cross(c - a).dot((a + b + c) / 3.0 - cen) < 0.0:
		var t := b
		b = c
		c = t
	for v in [a, c, b]:
		st.set_color(_haze(v.y / top_y))
		st.add_vertex(v)

## Мутность по высоте: основание молочное и плотное, вершина чистая.
static func _haze(h: float) -> Color:
	var k := clampf(h, 0.0, 1.0)
	return Color(1.0, 1.0, 1.0, 1.0).lerp(Color(0.8, 0.9, 1.0, 0.5), k)

## glow — сила свечения изнутри, alpha — прозрачность (лёд прозрачнее).
static func material(col: Color, glow := 0.7, alpha := 0.85) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.albedo_color = Color(col.lerp(Color.WHITE, 0.1), alpha)
	m.roughness = 0.08
	m.metallic = 0.1
	m.metallic_specular = 0.9
	m.rim_enabled = true
	m.rim = 0.6
	m.rim_tint = 0.3
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = glow
	return m
