class_name ProtoTerrain
extends RefCounted
## Предпросмотр объёмного рельефа: поле плотности (плюс — порода, минус — воздух)
## с холмами, руслом реки, котловиной озера, пещерным залом и ходом к нему.
## Поверхность строится методом surface nets в один ArrayMesh с цветом вершин.

var sx := 80
var sy := 36
var sz := 80
var dens := PackedFloat32Array()
var noise := FastNoiseLite.new()
var noise3 := FastNoiseLite.new()
var vein_noise := FastNoiseLite.new()

# Особые места (в клетках).
var lake_c := Vector2(16, 60)
var lake_r := 9.0
var bed := PackedFloat32Array()   # дно русла по x: только понижается к озеру
var lake_level := 0.0
var cave_c := Vector3(52, 8, 50)
var cave_r := 7.0
var cave_entry := Vector3(40, 0, 66)   # y ставится по поверхности
var river_level := 0.0

var ground := Color(0.36, 0.31, 0.26)
var cliff := Color(0.3, 0.27, 0.25)
var vein := Color(0.5, 0.8, 1.0)
var outcrops: Array = []        # цвета материалов, выходящих на поверхность пятнами
var patch_noise := FastNoiseLite.new()

func _init(seed_value: int) -> void:
	noise.seed = seed_value
	noise.frequency = 0.035
	noise.fractal_octaves = 4
	noise3.seed = seed_value + 7
	noise3.frequency = 0.06
	vein_noise.seed = seed_value + 13
	vein_noise.frequency = 0.12
	patch_noise.seed = seed_value + 21
	patch_noise.frequency = 0.07
	lake_c.y = river_z(lake_c.x)
	# Дно русла: минимум по всему верховью — река не течёт в гору и всегда врезана.
	bed.resize(sx + 2)
	var m := INF
	for x in range(sx + 1, -1, -1):
		m = min(m, _raw_h(x, river_z(x)) - 2.2)
		bed[x] = m

const PAD_C := Vector2(46, 30)
const PAD_HALF := Vector2(7.5, 5.5)

func _raw_h(x: float, z: float) -> float:
	var h := 16.0 + noise.get_noise_2d(x, z) * 9.0
	# Холм посреди карты — на нём площадка завода.
	var dc := Vector2(x, z).distance_to(PAD_C)
	h += max(0.0, 5.0 - dc * 0.25)
	return h

## Высота площадки завода — выровненный рельеф.
func pad_h() -> float:
	return floor(_raw_h(PAD_C.x, PAD_C.y)) + 0.5

func surface_h(x: float, z: float) -> float:
	var h := _raw_h(x, z)
	# Русло: берега откосом к дну, дно понижается к озеру.
	var dr: float = abs(z - river_z(x))
	var b := bed_at(x)
	if x > lake_c.x - 2.0:
		h = min(h, b + max(0.0, dr - 1.6) * 0.8)
	# Котловина озера — ниже воды у устья.
	var dl := Vector2(x, z).distance_to(lake_c)
	h = min(h, lake_level_base() - 1.6 + max(0.0, dl - lake_r * 0.55) * 0.55)
	# Площадка выровнена: внутри прямоугольника ровно, к краям — плавный откос.
	var q := (Vector2(x, z) - PAD_C).abs() - PAD_HALF
	var out: float = Vector2(max(q.x, 0.0), max(q.y, 0.0)).length()
	var k: float = clamp(1.0 - out / 4.0, 0.0, 1.0)
	return lerp(h, pad_h(), k)

func river_z(x: float) -> float:
	return 58.0 + sin(x * 0.09) * 7.0

## Плотность в точке: плюс — порода.
func density(x: float, y: float, z: float) -> float:
	var h := surface_h(x, z)
	var d := h - y
	# Пещерный зал — сплюснутая сфера.
	var q := Vector3(x, y, z) - cave_c
	q.y *= 1.6
	d = min(d, q.length() - cave_r)
	# Чаша подземного озерца в дальней части зала.
	var pq := Vector3(x, y, z) - pool_c()
	pq.y *= 2.6
	d = min(d, pq.length() - pool_r)
	# Ход от склона к залу: капсула с извилиной.
	var a := cave_entry
	var b := cave_c + Vector3(0, 1, 0)
	var t: float = clamp((Vector3(x, y, z) - a).dot(b - a) / (b - a).length_squared(), 0.0, 1.0)
	var p := a.lerp(b, t) + Vector3(sin(t * 6.0) * 2.0, 0, 0)
	d = min(d, Vector3(x, y, z).distance_to(p) - 2.4)
	# Редкие гладкие червоточины глубже поверхности — но не у пещеры.
	if y < h - 4.0 and not cave_box.has_point(Vector3(x, y, z)):
		var w := absf(noise3.get_noise_3d(x, y * 1.4, z))
		d = min(d, (w - 0.035) * 30.0)
	# Пол у края карты и дно — всегда порода.
	if y < 1.5:
		d = max(d, 1.0)
	return d

var pool_r := 3.0

## Центр чаши озерца: у пола зала, дальше от входа.
func pool_c() -> Vector3:
	return cave_c + Vector3(2.6, -cave_r / 1.6 + 0.9, -2.2)

## Уровень воды в чаше — чуть ниже края (пола зала).
func pool_level() -> float:
	return pool_c().y + 0.35

## Коробка вокруг зала и хода: там сетка мельче, а червоточин нет.
var cave_box := AABB()

func build_field() -> void:
	# Зал всегда под толщей породы: опускаем его ниже самой низкой точки поверхности над ним.
	var minh := INF
	for dz in range(-int(cave_r), int(cave_r) + 1, 2):
		for dx in range(-int(cave_r), int(cave_r) + 1, 2):
			minh = minf(minh, surface_h(cave_c.x + dx, cave_c.z + dz))
	cave_c.y = clampf(minh - cave_r / 1.6 - 3.0, 4.5, 10.0)
	cave_entry.y = surface_h(cave_entry.x, cave_entry.z) - 1.0
	var r := Vector3(cave_r + 2.5, cave_r / 1.6 + 2.5, cave_r + 2.5)
	cave_box = AABB(cave_c - r, r * 2.0)
	var tun := AABB(cave_entry, Vector3.ZERO).expand(cave_c + Vector3(0, 1, 0)).grow(3.5)
	cave_box = cave_box.merge(tun)
	cave_box.position.y = maxf(cave_box.position.y, 1.0)
	var n := (sx + 1) * (sy + 1) * (sz + 1)
	dens.resize(n)
	for z in sz + 1:
		for y in sy + 1:
			for x in sx + 1:
				dens[_i(x, y, z)] = density(x, y, z)
	lake_level = lake_level_base()

func bed_at(x: float) -> float:
	var i := clampi(int(floor(x)), 0, sx)
	var f: float = clamp(x - i, 0.0, 1.0)
	return lerp(bed[i], bed[min(i + 1, sx + 1)], f)

## Уровень озера — вода реки у устья.
func lake_level_base() -> float:
	return bed_at(lake_c.x + lake_r) + 0.9

## Уровень реки в точке: дно + глубина; у озера — уровень озера.
func river_level_at(x: float, _z: float = 0.0) -> float:
	return max(bed_at(x) + 0.9, lake_level_base())

func _i(x: int, y: int, z: int) -> int:
	return x + (sx + 1) * (y + (sy + 1) * z)

func solid(x: float, y: float, z: float) -> bool:
	return density(x, y, z) > 0.0

const CORNERS := [Vector3i(0, 0, 0), Vector3i(1, 0, 0), Vector3i(0, 1, 0), Vector3i(1, 1, 0),
	Vector3i(0, 0, 1), Vector3i(1, 0, 1), Vector3i(0, 1, 1), Vector3i(1, 1, 1)]
const EDGES := [[0, 1], [2, 3], [4, 5], [6, 7], [0, 2], [1, 3], [4, 6], [5, 7], [0, 4], [1, 5], [2, 6], [3, 7]]

## Surface nets по области: origin — угол, n — число клеток, cell — шаг. Вершина в
## каждой клетке со сменой знака, грань на каждом ребре со сменой знака. skip —
## клетки с центром внутри не строятся (там будет детальная сетка).
## Цвет вершины: rgb — порода, a — видимость неба; UV.x — маска жилы.
func build_mesh(origin := Vector3.ZERO, n := Vector3i(-1, -1, -1), cell := 1.0, skip := AABB()) -> ArrayMesh:
	if n.x < 0:
		n = Vector3i(sx, sy, sz)
	var nx := n.x
	var ny := n.y
	var nz := n.z
	# Поле в узлах: для основной сетки уже посчитано, для детальной — считаем.
	var f := dens
	var reuse := origin == Vector3.ZERO and cell == 1.0 and n == Vector3i(sx, sy, sz)
	if not reuse:
		f = PackedFloat32Array()
		f.resize((nx + 1) * (ny + 1) * (nz + 1))
		for z in nz + 1:
			for y in ny + 1:
				for x in nx + 1:
					f[x + (nx + 1) * (y + (ny + 1) * z)] = density(origin.x + x * cell, origin.y + y * cell, origin.z + z * cell)
	var fi := func(x: int, y: int, z: int) -> int: return x + (nx + 1) * (y + (ny + 1) * z)
	var use_skip := skip.size != Vector3.ZERO
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	var cell_v := PackedInt32Array()
	cell_v.resize(nx * ny * nz)
	cell_v.fill(-1)
	var v := PackedFloat32Array()
	v.resize(8)
	for z in nz:
		for y in ny:
			for x in nx:
				if use_skip and skip.has_point(origin + (Vector3(x, y, z) + Vector3.ONE * 0.5) * cell):
					continue
				var inside := 0
				for k in 8:
					var c: Vector3i = CORNERS[k]
					v[k] = f[x + c.x + (nx + 1) * (y + c.y + (ny + 1) * (z + c.z))]
					if v[k] > 0.0:
						inside += 1
				if inside == 0 or inside == 8:
					continue
				var acc := Vector3.ZERO
				var cnt := 0
				for e in EDGES:
					var a: float = v[e[0]]
					var b: float = v[e[1]]
					if (a > 0.0) != (b > 0.0):
						var t := a / (a - b)
						acc += Vector3(CORNERS[e[0]]).lerp(Vector3(CORNERS[e[1]]), t)
						cnt += 1
				var pos := origin + (Vector3(x, y, z) + acc / cnt) * cell
				var g := Vector3(
					(v[1] + v[3] + v[5] + v[7]) - (v[0] + v[2] + v[4] + v[6]),
					(v[2] + v[3] + v[6] + v[7]) - (v[0] + v[1] + v[4] + v[5]),
					(v[4] + v[5] + v[6] + v[7]) - (v[0] + v[1] + v[2] + v[3]))
				var nrm := (-g).normalized()
				cell_v[x + nx * (y + ny * z)] = verts.size()
				verts.append(pos)
				norms.append(nrm)
				var vein_m := _vein(pos)
				var c4 := _color(pos, nrm, vein_m)
				c4.a = sky_vis(pos)
				cols.append(c4)
				uvs.append(Vector2(vein_m, 0.0))
	var cv := func(c: Vector3i) -> int:
		if c.x < 0 or c.y < 0 or c.z < 0 or c.x >= nx or c.y >= ny or c.z >= nz:
			return -1
		return cell_v[c.x + nx * (c.y + ny * c.z)]
	for z in range(1, nz):
		for y in range(1, ny):
			for x in range(1, nx):
				var s0: bool = f[fi.call(x, y, z)] > 0.0
				if (f[fi.call(x + 1, y, z)] > 0.0) != s0:
					_quad(idx, cv, [Vector3i(x, y - 1, z - 1), Vector3i(x, y, z - 1), Vector3i(x, y, z), Vector3i(x, y - 1, z)], s0)
				if (f[fi.call(x, y + 1, z)] > 0.0) != s0:
					_quad(idx, cv, [Vector3i(x - 1, y, z - 1), Vector3i(x, y, z - 1), Vector3i(x, y, z), Vector3i(x - 1, y, z)], not s0)
				if (f[fi.call(x, y, z + 1)] > 0.0) != s0:
					_quad(idx, cv, [Vector3i(x - 1, y - 1, z), Vector3i(x, y - 1, z), Vector3i(x, y, z), Vector3i(x - 1, y, z)], s0)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return mesh

## Детальная сетка пещеры (шаг 0,5 м) — в паре с основной, построенной с skip.
func build_cave_mesh(cell := 0.5) -> ArrayMesh:
	var n := Vector3i(ceili(cave_box.size.x / cell), ceili(cave_box.size.y / cell), ceili(cave_box.size.z / cell))
	return build_mesh(cave_box.position, n, cell)

## Коробка, которую основная сетка не строит: пещерная, ужатая на клетку,
## чтобы края двух сеток перекрывались.
func coarse_skip() -> AABB:
	return cave_box.grow(-1.0)

func _quad(idx: PackedInt32Array, cv: Callable, cells: Array, flip: bool) -> void:
	var q: Array = []
	for c in cells:
		var vi: int = cv.call(c)
		if vi < 0:
			return
		q.append(vi)
	if flip:
		idx.append_array([q[0], q[2], q[1], q[0], q[3], q[2]])
	else:
		idx.append_array([q[0], q[1], q[2], q[0], q[2], q[3]])

## Видимость неба: под толщей породы темно; у входа в пещеру — полутень.
func sky_vis(p: Vector3) -> float:
	var depth := surface_h(p.x, p.z) - p.y
	var v := clampf(1.0 - (depth - 0.4) / 2.2, 0.0, 1.0)
	v = maxf(v, 0.85 * exp(-p.distance_to(cave_entry) / 3.5))
	return v

## Маска жилы: в толще у пещеры, полосами по 3D-шуму.
func _vein(p: Vector3) -> float:
	if surface_h(p.x, p.z) - p.y < 1.5 or p.distance_to(cave_c) > cave_r + 3.5:
		return 0.0
	return smoothstep(0.27, 0.33, vein_noise.get_noise_3d(p.x, p.y * 1.3, p.z))

## Затенение впадин: доля породы вокруг точки (дёшево, по полю плотности).
func _crevice(p: Vector3, nrm: Vector3) -> float:
	var solid_n := 0
	for d in [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, -1, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]:
		if (d as Vector3).dot(nrm) < -0.3:
			continue
		if density(p.x + d.x * 1.3 + nrm.x * 0.5, p.y + d.y * 1.3 + nrm.y * 0.5, p.z + d.z * 1.3 + nrm.z * 0.5) > 0.0:
			solid_n += 1
	return 1.0 - solid_n * 0.12

## Пол под точкой: вниз по полю плотности до породы (снаружи и в пещере).
func floor_at(p: Vector3) -> float:
	var y := minf(p.y, surface_h(p.x, p.z) + 0.5)
	if not solid(p.x, y - 0.05, p.z):
		while y > 1.0 and not solid(p.x, y - 0.1, p.z):
			y -= 0.1
	return y

## Цвет породы. Снаружи: ровное — грунт, круто — обрыв с пластами, пятна выходов.
## Под толщей (пещера): пол — светлый осадок, стены — порода с явными пластами,
## свод — темнее; жилы — цвет жилы. Впадины темнее.
func _color(p: Vector3, n: Vector3, vein_m: float = 0.0) -> Color:
	var h := surface_h(p.x, p.z)
	var under := h - p.y
	var c := ground
	var strata := 0.5 + 0.5 * sin(p.y * 1.7 + noise.get_noise_2d(p.x * 3.0, p.z * 3.0) * 2.0)
	if under > 1.5 or (under > 0.6 and n.y < -0.2):
		if n.y > 0.55:
			c = ground.lerp(Color(0.62, 0.55, 0.45), 0.35).lightened(0.12)
			c = c * (0.9 + 0.2 * patch_noise.get_noise_2d(p.x * 2.0, p.z * 2.0))
		elif n.y < -0.35:
			c = cliff.darkened(0.35)
		else:
			var band := 0.5 + 0.5 * sin(p.y * 3.1 + noise.get_noise_3d(p.x * 2.0, p.y, p.z * 2.0) * 1.5)
			c = cliff.lerp(ground, 0.3) * (0.72 + 0.4 * band)
		c = c.lerp(vein, vein_m)
		c = c * _crevice(p, n)
	else:
		var steep: float = clamp((0.8 - n.y) * 2.0, 0.0, 1.0)
		c = c.lerp(cliff * (0.85 + 0.3 * strata), steep)
		var depth: float = clamp((under - 1.5) / 6.0, 0.0, 1.0)
		c = c.darkened(depth * 0.45)
		# Выходы материалов на ровных местах — пятнами, у каждого пятна свой материал.
		if not outcrops.is_empty() and n.y > 0.88 and depth < 0.3:
			var pn := patch_noise.get_noise_2d(p.x, p.z)
			if pn > 0.35:
				var k := int(floor((patch_noise.get_noise_2d(p.x * 0.3 + 100.0, p.z * 0.3) + 1.0) * 0.5 * outcrops.size())) % outcrops.size()
				c = c.lerp(outcrops[k], clamp((pn - 0.35) * 3.0, 0.0, 0.5))
	c = c * (0.94 + 0.12 * noise.get_noise_2d(p.x * 5.0, p.z * 5.0))
	c.a = 1.0
	return c

## Шейдер рельефа: цвет вершины; видимость неба гасит общий свет и солнце, а
## фары и светящиеся кристаллы освещают в полную силу. Жилы слабо светятся.
const SHADER := """
shader_type spatial;
render_mode cull_disabled;
uniform vec3 vein_glow : source_color = vec3(0.5, 0.8, 1.0);
varying float sky;
void vertex() {
	sky = COLOR.a;
}
void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 0.92;
	AO = mix(0.06, 1.0, sky);
	AO_LIGHT_AFFECT = 0.0;
	EMISSION = vein_glow * UV.x * 0.35;
}
void light() {
	float k = LIGHT_IS_DIRECTIONAL ? sky : 1.0;
	DIFFUSE_LIGHT += clamp(dot(NORMAL, LIGHT), 0.0, 1.0) * ATTENUATION * LIGHT_COLOR * k / PI;
}
"""

func material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = SHADER
	m.shader = sh
	m.set_shader_parameter("vein_glow", vein)
	return m

## Ровная площадка под завод на вершине холма: высота и центр.
func plateau() -> Vector3:
	return Vector3(PAD_C.x, pad_h(), PAD_C.y)
