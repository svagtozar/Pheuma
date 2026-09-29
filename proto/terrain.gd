class_name ProtoTerrain
extends RefCounted
## Предпросмотр объёмного рельефа: поле плотности (плюс — порода, минус — воздух)
## с холмами, руслом реки, котловиной озера, пещерным залом и ходом к нему.
## Поверхность строится методом surface nets в один ArrayMesh с цветом вершин.
## Форма рельефа, пещеры и особые места (вулкан, иглы, кратеры, расщелины,
## парящие глыбы) — по тегам планеты, см. ProtoWorldStyle.

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
var bio := Callable()           # (x, z) → цвет поросли, a — доля (ProtoFlora.carpet)
var ground_model: ProtoGround   # толща: почва, осыпь, пласты (цвет стен и обрывов); null — прежний вид
var patch_noise := FastNoiseLite.new()

var style: ProtoWorldStyle
var cave_h := 4.4             # полувысота зала
var cave_u := Vector3(1, 0, 0)    # длинная ось зала
var cave_v := Vector3(0, 0, 1)
var cave_len := 7.0
var cave_wid := 7.0
# Особые места по тегам.
const VOLC_C := Vector2(14, 16)
var spires: Array = []        # [x, z, радиус основания, высота, y основания]
var craters: Array = []       # Vector3(x, z, радиус)
var fissures: Array = []      # [Vector2 a, Vector2 b, ширина, глубина, рамка]
var floaters: Array = []      # [центр, радиус]
# Правки рельефа игроком (бур копает, насыпь): [центр, радиус, +1 насыпь | -1 выемка],
# по порядку; корзины по XZ — чтобы density() не перебирал все.
var edits: Array = []
var _edit_bins := {}          # Vector2i(x/EDIT_BIN, z/EDIT_BIN) → [индексы правок]
const EDIT_BIN := 8.0

func _init(seed_value: int, st: ProtoWorldStyle = null) -> void:
	style = st if st != null else ProtoWorldStyle.new()
	noise.seed = seed_value
	noise.frequency = style.relief_freq
	noise.fractal_octaves = style.octaves
	lake_r = style.lake_r
	cave_len = style.cave_len
	cave_wid = style.cave_wid
	cave_h = style.cave_h
	cave_r = maxf(cave_len, cave_wid)
	cave_u = Vector3(style.cave_axis.x, 0, style.cave_axis.y).normalized()
	cave_v = Vector3(-cave_u.z, 0, cave_u.x)
	noise3.seed = seed_value + 7
	noise3.frequency = 0.06
	vein_noise.seed = seed_value + 13
	vein_noise.frequency = 0.12
	patch_noise.seed = seed_value + 21
	patch_noise.frequency = 0.07
	lake_c.y = river_z(lake_c.x)
	_features(seed_value)
	_init_far()
	# Дно русла: минимум по всему верховью — река не течёт в гору и всегда врезана.
	bed.resize(sx + 2)
	var m := INF
	for x in range(sx + 1, -1, -1):
		m = min(m, _raw_h(x, river_z(x)) - 2.2)
		bed[x] = m

const PAD_C := Vector2(46, 30)
const PAD_HALF := Vector2(7.5, 5.5)

## Свободно ли место под особую деталь рельефа: не на площадке, не у пещеры,
## не в русле и не в озере.
func free_spot(x: float, z: float, r: float) -> bool:
	var q := Vector2(x, z)
	if x < r + 2.0 or z < r + 2.0 or x > sx - r - 2.0 or z > sz - r - 2.0:
		return false
	if q.distance_to(PAD_C) < 12.0 + r or q.distance_to(Vector2(cave_c.x, cave_c.z)) < cave_r + 5.0 + r:
		return false
	if q.distance_to(Vector2(cave_entry.x, cave_entry.z)) < 6.0 + r:
		return false
	if absf(z - river_z(x)) < 5.0 + r or q.distance_to(lake_c) < lake_r + 3.0 + r:
		return false
	if style.volcano and q.distance_to(VOLC_C) < 12.0 + r:
		return false
	return true

func _features(seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 31 + 5
	for i in 300:
		if craters.size() >= style.craters:
			break
		var r := rng.randf_range(4.5, 8.5) if craters.size() > 0 else 10.0
		var x := rng.randf_range(0, sx)
		var z := rng.randf_range(0, sz)
		if free_spot(x, z, r * 0.6):
			craters.append(Vector3(x, z, r))
	for i in 400:
		if fissures.size() >= style.fissures:
			break
		var a := Vector2(rng.randf_range(0, sx), rng.randf_range(0, sz))
		var b := a + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(12.0, 22.0)
		var ok := true
		for k in 5:
			var m := a.lerp(b, k / 4.0)
			if not free_spot(m.x, m.y, 1.5):
				ok = false
		if ok:
			fissures.append([a, b, rng.randf_range(2.4, 3.4), rng.randf_range(6.0, 9.0), Rect2(a, Vector2.ZERO).expand(b).grow(3.0)])
	for i in 400:
		if spires.size() >= style.spires:
			break
		var r := rng.randf_range(1.2, 2.6)
		var x := rng.randf_range(0, sx)
		var z := rng.randf_range(0, sz)
		if free_spot(x, z, r):
			var hh := rng.randf_range(5.0, 11.0) * (1.4 if style.gravity < 0.8 else 1.0)
			spires.append([x, z, r, hh, 0.0])
	for i in 300:
		if floaters.size() >= style.floaters:
			break
		# По сетке 3×3, чтобы глыбы висели по всей карте, а не кучей.
		var k := floaters.size() % 9
		var r := rng.randf_range(2.4, 4.2)
		var x := (k % 3 + rng.randf()) * sx / 3.0
		var z := (floorf(k / 3.0) + rng.randf()) * sz / 3.0
		if Vector2(x, z).distance_to(PAD_C) > 10.0 and x > 6 and z > 6 and x < sx - 6 and z < sz - 6 \
				and Vector2(x, z).distance_to(Vector2(cave_c.x, cave_c.z)) > cave_r + 2.0:
			floaters.append([Vector3(x, 0.0, z), r])
	# Высоты — после того, как рельеф известен.
	for s in spires:
		s[4] = _raw_h(s[0], s[1]) - 1.5
	for f in floaters:
		var c: Vector3 = f[0]
		# Остриё снизу длиной r / 0,55 — висит над землёй, плоский верх под потолком карты.
		var r: float = f[1]
		c.y = minf(_raw_h(c.x, c.z) + r / 0.55 + rng.randf_range(2.5, 6.0), sy - r / 2.2 - 1.0)
		f[0] = c

func _raw_h(x: float, z: float) -> float:
	var n := noise.get_noise_2d(x, z)
	if style.ridged > 0.0:
		# Гребни: острые хребты по нулевой линии шума.
		n = lerpf(n, 0.75 - 2.2 * absf(n), style.ridged)
	var h := 16.0 + n * style.relief_amp
	if style.terrace > 0.0:
		var st := style.terrace
		var f: float = h / st - floor(h / st)
		h = lerpf(h, (floor(h / st) + smoothstep(0.7, 1.0, f)) * st, 0.85)
	if style.dunes > 0.0:
		h += style.dunes * sin(x * 0.72 + z * 0.41 + noise.get_noise_2d(x * 2.0, z * 2.0) * 3.0)
	if style.volcano:
		var dv := Vector2(x, z).distance_to(VOLC_C)
		h = maxf(h, 29.0 - dv * 1.0 + noise.get_noise_2d(x * 3.0, z * 3.0) * 0.8)
		if dv < 4.2:
			h = minf(h, 22.5 + dv * 0.8)
	for c in craters:
		var dd: float = Vector2(x, z).distance_to(Vector2(c.x, c.y)) / c.z
		if dd < 1.8:
			h += c.z * 0.2 * exp(-pow((dd - 1.0) * 3.0, 2.0))
			if dd < 1.0:
				h -= c.z * 0.5 * (1.0 - dd * dd)
	# Холм посреди карты — на нём площадка завода.
	var dc := Vector2(x, z).distance_to(PAD_C)
	h += max(0.0, 5.0 - dc * 0.25)
	return h

## Высота площадки завода — выровненный рельеф.
func pad_h() -> float:
	return floor(_raw_h(PAD_C.x, PAD_C.y)) + 0.5

## Высота поверхности под мировой точкой (x, z). Без шара — рельеф участка.
## С шаром (sphere) участок — площадка на «макушке» планеты-шара, вокруг —
## остальной шар; to_local переводит мир в систему планеты (шар поворачивается
## под роботом, см. ProtoPlanetStream).
func surface_h(x: float, z: float) -> float:
	if not sphere or (flat_frame and x >= 0.0 and z >= 0.0 and x <= sx and z <= sz):
		return _site_h(x, z)
	var y := 16.0
	for i in 2:
		var q := to_local * Vector3(x, y, z)
		var d := (q - center).normalized()
		y = (to_world * (center + d * (radius + sphere_h(d)))).y
	return y

# --- Планета-шар вокруг участка ---
var sphere := false
var radius := 800.0           # радиус шара по «нулю» высот участка, м
var center := Vector3.ZERO    # центр шара в системе планеты (под серединой участка)
var to_local := Transform3D.IDENTITY   # мир → планета
var to_world := Transform3D.IDENTITY   # планета → мир
var flat_frame := true        # шар не повёрнут: планета = мир
const BLEND := 30.0           # ширина перехода от участка к остальному шару, м
var _far := FastNoiseLite.new()
var _far_big := FastNoiseLite.new()
var _basin := FastNoiseLite.new()
## Моря вдали от участка: глубина котловин (0 — сухая планета) и уровень моря
## над radius (−INF — морей нет). Задаёт ProtoPlanetFill до постройки шара.
var basin_depth := 0.0
var sea_level := -INF

## Включить шар радиуса r: центр под серединой участка.
func make_sphere(r: float) -> void:
	sphere = true
	radius = r
	center = Vector3(sx * 0.5, -r, sz * 0.5)

func set_frame(f: Transform3D) -> void:
	to_world = f
	to_local = f.affine_inverse()
	flat_frame = f.is_equal_approx(Transform3D.IDENTITY)

func _init_far() -> void:
	_far.seed = noise.seed
	_far.frequency = style.relief_freq
	_far.fractal_octaves = style.octaves
	_far_big.seed = noise.seed + 91
	_far_big.frequency = 0.0022
	_far_big.fractal_octaves = 5
	_far_big.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_basin.seed = noise.seed + 177
	_basin.frequency = 0.0028
	_basin.fractal_octaves = 3

## Насколько точка за краем участка по горизонтали (0 — внутри).
func out_dist(x: float, z: float) -> float:
	return Vector2(maxf(maxf(-x, x - sx), 0.0), maxf(maxf(-z, z - sz), 0.0)).length()

## Высота поверхности шара над radius по направлению d от центра (система
## планеты). У участка шар проходит ровно через его рельеф: точка на луче, где
## высота равна рельефу участка; дальше — плавно к рельефу остального шара.
func sphere_h(d: Vector3) -> float:
	var out := 1.0e9
	if d.y > 0.3:
		var t := (radius + 16.0) / d.y
		var p := center + d * t
		out = out_dist(p.x, p.z)
		if out < BLEND:
			for i in 3:
				p = center + d * ((radius + _site_h(p.x, p.z)) / d.y)
			var hs := (p - center).length() - radius
			if out <= 0.0:
				return hs
			return lerpf(hs, far_h(d, out), smoothstep(0.0, BLEND, out))
	return far_h(d, out)

## Рельеф остального шара: шум по точке на сфере (без швов); вдали от участка —
## крупные хребты.
func far_h(d: Vector3, out: float) -> float:
	var q := d * radius
	var n := _far.get_noise_3dv(q)
	if style.ridged > 0.0:
		n = lerpf(n, 0.75 - 2.2 * absf(n), style.ridged)
	var h := 16.0 + n * style.relief_amp
	if style.terrace > 0.0:
		var st := style.terrace
		var f: float = h / st - floor(h / st)
		h = lerpf(h, (floor(h / st) + smoothstep(0.7, 1.0, f)) * st, 0.85)
	h += _far_big.get_noise_3dv(q) * 30.0 * smoothstep(40.0, 420.0, out) - 4.0 * smoothstep(20.0, 120.0, out)
	if basin_depth > 0.0:
		# Котловины морей: не ближе ~100 м к участку, чтобы море его не залило.
		var b := _basin.get_noise_3dv(q)
		h -= smoothstep(-0.05, 0.35, b) * basin_depth * smoothstep(90.0, 260.0, out)
		return maxf(h, 3.0 - basin_depth)
	return maxf(h, 3.0)

## Точка «на плоскости» для шума цвета, поросли и плодородия вдали от участка:
## та же, что берёт шар для цвета вершин (без швов, у участка ≈ x, z).
static func far_key(p: Vector3) -> Vector2:
	return Vector2(p.x + p.y * 0.37, p.z - p.y * 0.61)

## Направление d (система планеты) → расстояние по дуге от середины участка, м.
func arc_from_site(d: Vector3) -> float:
	return acos(clampf(d.y, -1.0, 1.0)) * radius

## Плотность в системе планеты: у участка — его объёмный рельеф (пещера и
## прочее), дальше — шар; глубже 1,5 м над radius — сплошная порода.
func sphere_density(q: Vector3) -> float:
	if q.x >= 0.0 and q.z >= 0.0 and q.x <= sx and q.z <= sz and q.y > -10.0 and q.y < sy + 10.0:
		return _site_density(q.x, q.y, q.z)
	var v := q - center
	var r := v.length()
	var hgt := r - radius
	var dd := sphere_h(v / r) - hgt
	if hgt < 1.5:
		dd = maxf(dd, 1.0)
	return dd

func _site_h(x: float, z: float) -> float:
	var h := _raw_h(x, z)
	# Русло: берега откосом к дну, дно понижается к озеру.
	var dr: float = abs(z - river_z(x))
	var b := bed_at(x)
	if x > lake_c.x - 2.0:
		h = min(h, b + max(0.0, dr - 1.6) * 0.8)
		# Вал вдоль берега: где рельеф рядом с руслом ниже воды (река идёт по
		# гребню), берег насыпан на 0,8 м выше глади и сходит на нет откосом —
		# иначе вода стекала бы сбоку с обрыва.
		if dr < 14.0:
			h = max(h, min(b + max(0.0, dr - 1.6) * 0.8, b + 1.7) - max(0.0, dr - 4.0) * 0.8)
	# Котловина озера — ниже воды у устья; к середине глубже (≈4 м): там робот
	# уходит под воду с головой (ProtoSwim).
	var dl := Vector2(x, z).distance_to(lake_c)
	var bowl := 2.6 * (1.0 - smoothstep(0.0, lake_r * 0.6, dl))
	h = min(h, lake_level_base() - 1.6 - bowl + max(0.0, dl - lake_r * 0.55) * 0.55)
	# Площадка выровнена: внутри прямоугольника ровно, к краям — плавный откос.
	var q := (Vector2(x, z) - PAD_C).abs() - PAD_HALF
	var out: float = Vector2(max(q.x, 0.0), max(q.y, 0.0)).length()
	var k: float = clamp(1.0 - out / 4.0, 0.0, 1.0)
	return lerp(h, pad_h(), k)

func river_z(x: float) -> float:
	return style.river_z(x)

## Плотность в точке: плюс — порода.
## h — высота поверхности над точкой, если уже известна (считается по столбцу).
func density(x: float, y: float, z: float, h := NAN) -> float:
	if not sphere or (flat_frame and x >= 0.0 and z >= 0.0 and x <= sx and z <= sz):
		return _site_density(x, y, z, h)
	return sphere_density(to_local * Vector3(x, y, z))

## Плотность рельефа участка (система планеты).
func _site_density(x: float, y: float, z: float, h := NAN) -> float:
	if is_nan(h):
		h = _site_h(x, z)
	var d := h - y
	# Скальные иглы: конусы из породы, с неровными боками.
	for s in spires:
		if absf(x - s[0]) > s[2] + 1.0 or absf(z - s[1]) > s[2] + 1.0:
			continue
		var dy: float = y - s[4]
		if dy > -1.0 and dy < s[3] + 1.0:
			var dh := Vector2(x - s[0], z - s[1]).length()
			var ra: float = s[2] * (1.0 - clampf(dy / s[3], 0.0, 1.0)) + 0.1
			d = max(d, (ra - dh) * 0.9 + noise3.get_noise_3d(x * 2.0, y * 2.0, z * 2.0) * 0.4)
	# Парящие глыбы: плоский верх, острый низ.
	for f in floaters:
		var q0: Vector3 = Vector3(x, y, z) - f[0]
		if absf(q0.x) < 6.0 and absf(q0.z) < 6.0 and absf(q0.y) < 8.0:
			q0.y *= 2.2 if q0.y > 0.0 else 0.55
			d = max(d, f[1] - q0.length() + noise3.get_noise_3d(x * 1.5, y * 1.5, z * 1.5) * 1.1)
	# Расщелины: узкие трещины, к низу сходятся.
	for fs in fissures:
		if not fs[4].has_point(Vector2(x, z)):
			continue
		var dist := _seg_dist(Vector2(x, z), fs[0], fs[1])
		if dist < 3.0 and y > h - fs[3] - 1.0 and y < river_roof(x, z):
			var w: float = fs[2] * clampf((y - (h - fs[3])) / fs[3], 0.0, 1.0)
			d = min(d, dist - w + noise.get_noise_2d(x * 4.0, z * 4.0) * 0.25)
	var dpool := INF
	var dtun := INF
	# Зал, озерцо и ход — только рядом с ними: дальше они всё равно не ближе
	# поверхности (до build_field коробки нет — считаем всегда).
	if cave_near.size == Vector3.ZERO or cave_near.has_point(Vector3(x, y, z)):
		# Пещерный зал — эллипсоид, форма по тегам.
		var dc := cave_dist(Vector3(x, y, z))
		# Чаша подземного озерца в дальней части зала.
		var pq := Vector3(x, y, z) - (_pool_c if cave_near.size != Vector3.ZERO else pool_c())
		pq.y *= 2.6
		dpool = pq.length() - pool_r
		dc = min(dc, dpool)
		# Ход от склона к залу: капсула с извилиной; под руслом провисает ниже дна.
		# (по плану: ось у реки провисает, и по наклонному отрезку t уехало бы).
		var a := Vector2(cave_entry.x, cave_entry.z)
		var ab := Vector2(cave_c.x, cave_c.z) - a
		var t: float = clamp((Vector2(x, z) - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
		dtun = Vector3(x, y, z).distance_to(tunnel_point(t)) - TUN_R
		dc = min(dc, dtun)
		if dc < d:
			# Свод у реки не выше river_roof(): река течёт над залом и ходом, а не
			# проваливается в них.
			dc = maxf(dc, y - river_roof(x, z))
		d = min(d, dc)
	# Редкие гладкие червоточины глубже поверхности — но не у пещеры и не под рекой.
	if style.worms > 0.0 and y < h - 4.0 and not cave_box.has_point(Vector3(x, y, z)) \
			and y < river_roof(x, z) - 1.0:
		var w := absf(noise3.get_noise_3d(x, y * 1.4, z))
		d = min(d, (w - style.worms) * 30.0)
	if not edits.is_empty():
		d = _apply_edits(x, y, z, d)
	# Пол у края карты и дно — всегда порода (кроме чаши озерца: зал бывает
	# на самом дне, и чаша тогда уходит ниже; и хода под низким руслом).
	if y < 1.5 and not ((dpool < 0.0 or dtun < 0.0) and y > TUN_FLOOR):
		d = max(d, 1.0)
	return d

# ---------------------------------------------------------------- правка рельефа

## Можно ли править рельеф в точке: не площадка завода (она укреплена), не край
## карты и не дно.
func can_edit(c: Vector3) -> bool:
	var q := (Vector2(c.x, c.z) - PAD_C).abs() - PAD_HALF
	if q.x < 1.0 and q.y < 1.0:
		return false
	return c.x > 2.0 and c.z > 2.0 and c.x < sx - 2.0 and c.z < sz - 2.0 and c.y > 2.5 and c.y < sy - 2.0

## Выемка (add = false) или насыпь шаром радиуса r. Поле в узлах вокруг
## пересчитывается; возвращает задетую область (для перестройки сеток).
func edit(c: Vector3, r: float, add: bool) -> AABB:
	var i := edits.size()
	edits.append([c, r, 1.0 if add else -1.0])
	for bx in range(floori((c.x - r) / EDIT_BIN), floori((c.x + r) / EDIT_BIN) + 1):
		for bz in range(floori((c.z - r) / EDIT_BIN), floori((c.z + r) / EDIT_BIN) + 1):
			var k := Vector2i(bx, bz)
			if not _edit_bins.has(k):
				_edit_bins[k] = []
			_edit_bins[k].append(i)
	var box := AABB(c - Vector3.ONE * (r + 1.0), Vector3.ONE * (2.0 * r + 2.0))
	if not dens.is_empty():
		var sxn := sx + 1
		var syz := (sx + 1) * (sy + 1)
		for z in range(maxi(0, floori(box.position.z)), mini(sz, ceili(box.end.z)) + 1):
			for x in range(maxi(0, floori(box.position.x)), mini(sx, ceili(box.end.x)) + 1):
				var h := surface_h(x, z)
				for y in range(maxi(0, floori(box.position.y)), mini(sy, ceili(box.end.y)) + 1):
					dens[x + sxn * y + syz * z] = density(x, y, z, h)
	return box

## Правки поверх природного поля: по порядку, как CSG (насыпь после выемки — сверху).
func _apply_edits(x: float, y: float, z: float, d: float) -> float:
	var list = _edit_bins.get(Vector2i(floori(x / EDIT_BIN), floori(z / EDIT_BIN)))
	if list == null:
		return d
	var p := Vector3(x, y, z)
	for i in list:
		var e: Array = edits[i]
		var dist: float = p.distance_to(e[0]) - float(e[1])
		if dist > 0.8:
			if e[2] > 0.0:
				d = maxf(d, -dist)
			else:
				d = minf(d, dist)
			continue
		# Неровный край: лунка и куча не идеальные шары.
		dist += noise3.get_noise_3d(x * 2.3, y * 2.3, z * 2.3) * 0.18
		d = maxf(d, -dist) if e[2] > 0.0 else minf(d, dist)
	return d

## Насколько насыпи подняли верх над природной поверхностью в столбце (x, z).
func edit_raise(x: float, z: float) -> float:
	var list = _edit_bins.get(Vector2i(floori(x / EDIT_BIN), floori(z / EDIT_BIN)))
	if list == null:
		return 0.0
	var top := 0.0
	var h := surface_h(x, z)
	for i in list:
		var e: Array = edits[i]
		if e[2] < 0.0:
			continue
		var c: Vector3 = e[0]
		var dxz := Vector2(x - c.x, z - c.z).length()
		if dxz < e[1]:
			top = maxf(top, c.y + sqrt(e[1] * e[1] - dxz * dxz) - h)
	return top

func edits_to_array() -> Array:
	return edits.map(func(e): return [e[0].x, e[0].y, e[0].z, e[1], e[2]])

## Правки из сохранения; возвращает задетую область (сетки перестроить).
func edits_from_array(a: Array) -> AABB:
	var box := AABB()
	for e in a:
		var b := edit(Vector3(float(e[0]), float(e[1]), float(e[2])), float(e[3]), float(e[4]) > 0.0)
		box = b if box.size == Vector3.ZERO else box.merge(b)
	return box

## Расстояние до зала (минус — внутри): эллипсоид по осям стиля; у лавовой
## трубы плоский пол, у трещины неровные стены.
func cave_dist(p: Vector3) -> float:
	var q := p - cave_c
	var l := Vector3(q.dot(cave_u) / cave_len, q.y / cave_h, q.dot(cave_v) / cave_wid)
	var dc := (l.length() - 1.0) * minf(minf(cave_len, cave_wid), cave_h)
	match style.cave:
		"tube", "grotto":
			dc = maxf(dc, -(q.y + cave_h * 0.6))
		"fissure":
			dc += noise3.get_noise_3d(p.x * 1.2, p.y * 0.5, p.z * 1.2) * 0.9
		"ice", "geode":
			dc += noise3.get_noise_3d(p.x * 0.8, p.y * 0.8, p.z * 0.8) * 0.5
	return dc

## Высота пола зала относительно центра над точкой (смещение в плане).
func cave_floor_rel(off: Vector2) -> float:
	var o := Vector3(off.x, 0, off.y)
	var k := pow(o.dot(cave_u) / cave_len, 2.0) + pow(o.dot(cave_v) / cave_wid, 2.0)
	var f := -cave_h * sqrt(maxf(0.0, 1.0 - k))
	if style.cave == "tube" or style.cave == "grotto":
		f = maxf(f, -cave_h * 0.6)
	return f

const TUN_R := 2.4            # радиус хода в пещеру, м
const TUN_FLOOR := 0.3        # ниже пол хода не опускается (под рекой — ниже каменного дна)
const TUN_SLOPE := 1.0        # круче ход к реке не ныряет (робот лезет и по 1,6)
const ROOF := 1.8             # толща породы между дном русла и сводом под ним, м
const ROOF_DZ := 6.5          # до скольки метров от оси русла свод держится под дном
const ROOF_OUT := 10.0        # дальше от оси русла свод не ограничен

## Выше этого у реки нельзя вырезать зал и ход: под руслом и берегами — толща
## ROOF под дном (тоньше двух узлов поля — сетка теряет перемычку), дальше от
## воды свод поднимается откосом. Прежде зал и ход пробивали дно и берег, и
## река срывалась в квадратную дыру. Где русло почти на каменном дне, свод не
## ниже роста робота над полом хода: там перемычка тоньше.
func river_roof(x: float, z: float) -> float:
	var dz := absf(z - river_z(x))
	if x <= lake_c.x - 2.0 or dz > ROOF_OUT:
		return INF
	# Дно к озеру только понижается, но бывает уступом: свод — по дну на 1,5 м
	# ниже по течению, чтобы и под уступом перемычка была не тоньше ROOF.
	return maxf(bed_at(x - 1.5) - ROOF + maxf(0.0, dz - ROOF_DZ) * 1.5, TUN_FLOOR + 2.6)

## Точка оси хода от входа (t = 0) к залу (t = 1). Под рекой ось опускается под
## river_roof (свод срезан ровно, до пола — в рост робота), к ней — не круче
## TUN_SLOPE; у входа — как было.
func tunnel_point(t: float) -> Vector3:
	var p := _tunnel_base(t)
	if not _tun_cap.is_empty():
		var f := t * (_tun_cap.size() - 1)
		var i := mini(int(f), _tun_cap.size() - 2)
		p.y = minf(p.y, lerpf(_tun_cap[i], _tun_cap[i + 1], f - i))
	return p

## Ось хода без провисания: прямая от входа к залу с извилиной поперёк (тогда
## проекция точки на отрезок в плане даёт то же t).
func _tunnel_base(t: float) -> Vector3:
	var ab := Vector2(cave_c.x - cave_entry.x, cave_c.z - cave_entry.z).normalized()
	return cave_entry.lerp(cave_c + Vector3(0, 1, 0), t) + Vector3(-ab.y, 0, ab.x) * sin(t * 6.0) * 2.0

## Потолок оси хода по t: под рекой — river_roof − 0,2, от этих мест вверх
## откосом TUN_SLOPE (по длине хода); пусто, если ход реку не задевает.
var _tun_cap := PackedFloat32Array()

func _tunnel_cap() -> void:
	_tun_cap = PackedFloat32Array()
	const N := 64
	var need := PackedFloat32Array()
	var any := false
	for i in N + 1:
		var p := _tunnel_base(float(i) / N)
		var r := river_roof(p.x, p.z) - 0.2
		need.append(maxf(r, TUN_R + TUN_FLOOR))
		any = any or r < p.y
	if not any:
		return
	var step := Vector2(cave_c.x - cave_entry.x, cave_c.z - cave_entry.z).length() / N * TUN_SLOPE
	_tun_cap.resize(N + 1)
	for i in N + 1:
		var c := INF
		for j in N + 1:
			c = minf(c, need[j] + absi(i - j) * step)
		_tun_cap[i] = c

static func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var t := clampf((p - a).dot(b - a) / (b - a).length_squared(), 0.0, 1.0)
	return p.distance_to(a.lerp(b, t))

var pool_r := 3.0

const POOL_OFF := Vector2(2.6, -2.2)   # чаша озерца от центра зала, м

## Центр чаши озерца: в полу зала, дальше от входа. Чаша сплюснута (полувысота
## pool_r / 2,6 ≈ 1,15 м): центр чуть выше края — вода глубиной около 0,8 м.
func pool_c() -> Vector3:
	return Vector3(cave_c.x + POOL_OFF.x, pool_rim() + 0.1, cave_c.z + POOL_OFF.y)

## Уровень воды в чаше — чуть ниже края (самого низкого места пола вокруг).
func pool_level() -> float:
	return pool_rim() - 0.2

## Радиус глади озерца: сечение сплюснутой чаши на уровне воды (с запасом
## под стенку).
func pool_surface_r() -> float:
	var dy := (pool_level() - pool_c().y) * 2.6
	return sqrt(maxf(0.0, pool_r * pool_r - dy * dy)) + 0.12

## Край чаши: самое низкое место настоящего пола зала вокруг неё (по полю зала,
## а не по эллипсоиду: у расщелин и ледяных залов пол неровный, у труб — плоский,
## а ниже 1,5 м всегда порода). Прежде центр ставился на 0,9 м выше пола по
## эллипсоиду, и вода висела над полом зала плоской плёнкой.
func pool_rim() -> float:
	if not is_nan(_pool_rim):
		return _pool_rim
	var rim := INF
	for k in 16:
		var a := TAU * k / 16.0
		for rr: float in [pool_r + 0.3, pool_r + 0.8]:
			var q := Vector3(cave_c.x + POOL_OFF.x + cos(a) * rr, cave_c.y, cave_c.z + POOL_OFF.y + sin(a) * rr)
			q.y = minf(q.y, river_roof(q.x, q.z) - 0.1)   # под рекой свод срезан
			if cave_dist(q) > 0.0:
				continue            # стена зала — там край выше
			var y := q.y
			while y > 1.5 and cave_dist(Vector3(q.x, y - 0.05, q.z)) < 0.0:
				y -= 0.05
			rim = minf(rim, y)
	if rim == INF:
		rim = cave_c.y + cave_floor_rel(POOL_OFF)
	_pool_rim = rim           # build_field сбрасывает, когда опускает зал
	return rim

var _pool_rim := NAN

## Коробка вокруг зала и хода: там сетка мельче, а червоточин нет.
var cave_box := AABB()
## Где density вообще считает зал, озерцо и ход (коробка с запасом: ход виляет
## на 2 м вбок, а за запасом их расстояние больше, чем у поверхности рядом).
var cave_near := AABB()
var _pool_c := Vector3.ZERO

func build_field() -> void:
	# Зал всегда под толщей породы: опускаем его ниже самой низкой точки поверхности над ним.
	var minh := INF
	for dz in range(-int(cave_r), int(cave_r) + 1, 2):
		for dx in range(-int(cave_r), int(cave_r) + 1, 2):
			minh = minf(minh, surface_h(cave_c.x + dx, cave_c.z + dz))
	cave_c.y = clampf(minh - cave_h - 3.0, cave_h * 0.75 + 1.5, 12.0)
	cave_entry.y = surface_h(cave_entry.x, cave_entry.z) - 1.0
	_tunnel_cap()
	_pool_rim = NAN
	pool_rim()
	var r := Vector3(cave_r + 2.5, cave_h + 2.5, cave_r + 2.5)
	cave_box = AABB(cave_c - r, r * 2.0)
	var tun := AABB(cave_entry, Vector3.ZERO).expand(cave_c + Vector3(0, 1, 0)).grow(3.5)
	for i in 21:
		tun = tun.expand(tunnel_point(i / 20.0) - Vector3(0, TUN_R + 1.0, 0))   # ход провисает под рекой
	cave_box = cave_box.merge(tun)
	# Дно коробки — над каменным дном карты, но под чашей озерца (она может
	# уходить ниже 1,5 м, если пол зала лежит на каменном дне).
	cave_box.position.y = maxf(cave_box.position.y, minf(1.0, pool_rim() - 1.3))
	_pool_c = pool_c()
	cave_near = cave_box.grow(6.0)
	_fill = PackedFloat32Array()
	_fill.resize((sx + 1) * (sy + 1) * (sz + 1))
	_parallel(_fill_slice.bind(Vector3.ZERO, Vector3i(sx, sy, sz), 1.0), sz + 1)
	dens = _fill
	_fill = PackedFloat32Array()
	lake_level = lake_level_base()

## Узлы области из готового поля (шаг 1 м): origin — угол в узлах.
func _copy_field(o: Vector3i, n: Vector3i) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize((n.x + 1) * (n.y + 1) * (n.z + 1))
	var sxn := sx + 1
	var syz := (sx + 1) * (sy + 1)
	var j := 0
	for z in n.z + 1:
		for y in n.y + 1:
			var i0 := o.x + sxn * (o.y + y) + syz * (o.z + z)
			for x in n.x + 1:
				out[j] = dens[i0 + x]
				j += 1
	return out

## Поле в узлах области (для build_field и детальной сетки) — по слоям z в потоках.
## Пишем в член _fill: у локального массива, захваченного лямбдой, каждый поток
## делал бы свою копию.
var _fill := PackedFloat32Array()

func _fill_slice(z: int, origin: Vector3, n: Vector3i, cell: float) -> void:
	var base := (n.x + 1) * (n.y + 1) * z
	var pz := origin.z + z * cell
	for x in n.x + 1:
		var px := origin.x + x * cell
		var h := surface_h(px, pz)
		for y in n.y + 1:
			_fill[base + x + (n.x + 1) * y] = density(px, origin.y + y * cell, pz, h)

## count задач task(i) на пуле потоков; ждём все. Генерация читает только
## шум и списки особых мест — это безопасно из нескольких потоков.
func _parallel(task: Callable, count: int) -> void:
	if count <= 0:
		return
	var id := WorkerThreadPool.add_group_task(task, count, -1, true, "рельеф")
	WorkerThreadPool.wait_for_group_task_completion(id)

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
## skip_depth: клетки коробки skip пропускаются, только если глубже этого под
## поверхностью (иначе на поверхности над пещерой виден шов двух сеток);
## shallow: не строить клетки мельче этой глубины (детальной сетке — поверхность не нужна).
func build_mesh(origin := Vector3.ZERO, n := Vector3i(-1, -1, -1), cell := 1.0, skip := AABB(),
		skip_depth := 2.0, shallow := -INF) -> ArrayMesh:
	if n.x < 0:
		n = Vector3i(sx, sy, sz)
	var nx := n.x
	var ny := n.y
	var nz := n.z
	# Поле в узлах: для основной сетки уже посчитано, для детальной — считаем.
	var f := dens
	var reuse := origin == Vector3.ZERO and cell == 1.0 and n == Vector3i(sx, sy, sz)
	# Кусок основной сетки (шаг 1 м, узлы внутри поля) — тоже из готового поля.
	var part := not reuse and not dens.is_empty() and cell == 1.0 and origin == origin.floor() \
		and origin.x >= 0.0 and origin.y >= 0.0 and origin.z >= 0.0 \
		and origin.x + nx <= sx and origin.y + ny <= sy and origin.z + nz <= sz
	if part:
		f = _copy_field(Vector3i(origin), n)
	elif not reuse:
		_fill = PackedFloat32Array()
		_fill.resize((nx + 1) * (ny + 1) * (nz + 1))
		_parallel(_fill_slice.bind(origin, n, cell), nz + 1)
		f = _fill
		_fill = PackedFloat32Array()
	var sxn := nx + 1
	var syz := (nx + 1) * (ny + 1)
	var use_skip := skip.size != Vector3.ZERO
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cell_v := PackedInt32Array()
	cell_v.resize(nx * ny * nz)
	cell_v.fill(-1)
	var v := PackedFloat32Array()
	v.resize(8)
	# Смещения восьми углов клетки в поле.
	var co := PackedInt32Array()
	for k in 8:
		var c: Vector3i = CORNERS[k]
		co.append(c.x + sxn * c.y + syz * c.z)
	# Сначала вершины и нормали (дёшево), цвет — потом в потоках.
	for z in nz:
		for x in nx:
			# Высота поверхности над столбцом клеток — одна на столбец.
			var ccx := origin.x + (x + 0.5) * cell
			var ccz := origin.z + (z + 0.5) * cell
			var col_h := surface_h(ccx, ccz) if use_skip or shallow > -INF else 0.0
			for y in ny:
				var i0 := x + sxn * y + syz * z
				var inside := 0
				for k in 8:
					v[k] = f[i0 + co[k]]
					if v[k] > 0.0:
						inside += 1
				if inside == 0 or inside == 8:
					continue
				var ccy := origin.y + (y + 0.5) * cell
				if use_skip and skip.has_point(Vector3(ccx, ccy, ccz)) and col_h - ccy > skip_depth:
					continue
				if shallow > -INF and col_h - ccy < shallow:
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
				var g := Vector3(
					(v[1] + v[3] + v[5] + v[7]) - (v[0] + v[2] + v[4] + v[6]),
					(v[2] + v[3] + v[6] + v[7]) - (v[0] + v[1] + v[4] + v[5]),
					(v[4] + v[5] + v[6] + v[7]) - (v[0] + v[1] + v[2] + v[3]))
				cell_v[x + nx * (y + ny * z)] = verts.size()
				verts.append(origin + (Vector3(x, y, z) + acc / cnt) * cell)
				norms.append((-g).normalized())
	# Грани: на каждом ребре со сменой знака — четырёхугольник из вершин соседних клеток.
	var idx := PackedInt32Array()
	var cnx := nx
	var cny := nx * ny
	for z in range(1, nz):
		for y in range(1, ny):
			for x in range(1, nx):
				var i0 := x + sxn * y + syz * z
				var s0: bool = f[i0] > 0.0
				var c0 := x + cnx * y + cny * z
				if (f[i0 + 1] > 0.0) != s0:
					_quad(idx, cell_v[c0 - cnx - cny], cell_v[c0 - cny], cell_v[c0], cell_v[c0 - cnx], s0)
				if (f[i0 + sxn] > 0.0) != s0:
					_quad(idx, cell_v[c0 - 1 - cny], cell_v[c0 - cny], cell_v[c0], cell_v[c0 - 1], not s0)
				if (f[i0 + syz] > 0.0) != s0:
					_quad(idx, cell_v[c0 - 1 - cnx], cell_v[c0 - cnx], cell_v[c0], cell_v[c0 - 1], s0)
	# Цвет, видимость неба и маска жилы — по вершинам, кусками в потоках.
	_attr_pos = verts
	_attr_nrm = norms
	_attr_col = PackedColorArray()
	_attr_col.resize(verts.size())
	_attr_uv = PackedVector2Array()
	_attr_uv.resize(verts.size())
	_parallel(_attr_chunk, ceili(verts.size() / float(ATTR_CHUNK)))
	if idx.is_empty():
		return ArrayMesh.new()        # в куске нет поверхности (весь порода или воздух)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_COLOR] = _attr_col
	arr[Mesh.ARRAY_TEX_UV] = _attr_uv
	arr[Mesh.ARRAY_INDEX] = idx
	_attr_pos = PackedVector3Array()
	_attr_nrm = PackedVector3Array()
	_attr_col = PackedColorArray()
	_attr_uv = PackedVector2Array()
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return mesh

const ATTR_CHUNK := 512
var _attr_pos := PackedVector3Array()
var _attr_nrm := PackedVector3Array()
var _attr_col := PackedColorArray()
var _attr_uv := PackedVector2Array()

func _attr_chunk(k: int) -> void:
	for i in range(k * ATTR_CHUNK, mini((k + 1) * ATTR_CHUNK, _attr_pos.size())):
		var pos := _attr_pos[i]
		var h := surface_h(pos.x, pos.z)
		var vein_m := _vein_h(pos, h)
		var c4 := _color_h(pos, _attr_nrm[i], vein_m, h)
		c4.a = _sky_vis_h(pos, h)
		_attr_col[i] = c4
		_attr_uv[i] = Vector2(vein_m, 0.0)

## Детальная сетка пещеры (шаг 0,5 м) — в паре с основной, построенной с skip.
func build_cave_mesh(cell := 0.5) -> ArrayMesh:
	var n := Vector3i(ceili(cave_box.size.x / cell), ceili(cave_box.size.y / cell), ceili(cave_box.size.z / cell))
	return build_mesh(cave_box.position, n, cell, AABB(), 0.0, 1.0)

## Коробка, которую основная сетка не строит: пещерная, ужатая на клетку,
## чтобы края двух сеток перекрывались.
func coarse_skip() -> AABB:
	return cave_box.grow(-1.0)

func _quad(idx: PackedInt32Array, a: int, b: int, c: int, d: int, flip: bool) -> void:
	if a < 0 or b < 0 or c < 0 or d < 0:
		return
	if flip:
		idx.append_array([a, c, b, a, d, c])
	else:
		idx.append_array([a, b, c, a, c, d])

## Видимость неба: под толщей породы темно; у входа в пещеру — полутень.
func sky_vis(p: Vector3) -> float:
	return _sky_vis_h(p, surface_h(p.x, p.z))

## То же при известной высоте поверхности h над точкой.
func _sky_vis_h(p: Vector3, h: float) -> float:
	var depth := h - p.y
	var v := clampf(1.0 - (depth - 0.4) / 2.2, 0.0, 1.0)
	v = maxf(v, 0.85 * exp(-p.distance_to(cave_entry) / 3.5))
	return v

## Маска жилы: в толще у пещеры, полосами по 3D-шуму.
func _vein(p: Vector3) -> float:
	return _vein_h(p, surface_h(p.x, p.z))

func _vein_h(p: Vector3, h: float) -> float:
	if h - p.y < 1.5 or p.distance_to(cave_c) > cave_r + 3.5:
		return 0.0
	return smoothstep(0.27, 0.33, vein_noise.get_noise_3d(p.x, p.y * 1.3, p.z))

## Затенение впадин: доля породы вокруг точки (дёшево, по полю плотности).
const CREVICE_DIRS := [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, -1, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]

func _crevice(p: Vector3, nrm: Vector3) -> float:
	var solid_n := 0
	for d: Vector3 in CREVICE_DIRS:
		if d.dot(nrm) < -0.3:
			continue
		if field_at(p + d * 1.3 + nrm * 0.5) > 0.0:
			solid_n += 1
	return 1.0 - solid_n * 0.12

## Плотность из готового поля (трилинейно по узлам 1 м) — в разы дешевле
## density(); вне поля или до build_field — точная density().
func field_at(p: Vector3) -> float:
	if dens.is_empty() or p.x < 0.0 or p.y < 0.0 or p.z < 0.0 or p.x >= sx or p.y >= sy or p.z >= sz:
		return density(p.x, p.y, p.z)
	var x := int(p.x)
	var y := int(p.y)
	var z := int(p.z)
	var fx := p.x - x
	var fy := p.y - y
	var fz := p.z - z
	var sxn := sx + 1
	var syz := (sx + 1) * (sy + 1)
	var i := x + sxn * y + syz * z
	var c00 := lerpf(dens[i], dens[i + 1], fx)
	var c10 := lerpf(dens[i + sxn], dens[i + sxn + 1], fx)
	var c01 := lerpf(dens[i + syz], dens[i + syz + 1], fx)
	var c11 := lerpf(dens[i + syz + sxn], dens[i + syz + sxn + 1], fx)
	return lerpf(lerpf(c00, c10, fy), lerpf(c01, c11, fy), fz)

## Пол под точкой: вниз по полю плотности до породы (снаружи и в пещере).
func floor_at(p: Vector3) -> float:
	var y := minf(p.y, surface_h(p.x, p.z) + 0.5 + (edit_raise(p.x, p.z) if not edits.is_empty() else 0.0))
	if not solid(p.x, y - 0.05, p.z):
		while y > 1.0 and not solid(p.x, y - 0.1, p.z):
			y -= 0.1
	return y

## Цвет породы. Снаружи: ровное — грунт, круто — обрыв с пластами, пятна выходов.
## Под толщей (пещера): пол — светлый осадок, стены — порода с явными пластами,
## свод — темнее; жилы — цвет жилы. Впадины темнее.
func _color(p: Vector3, n: Vector3, vein_m: float = 0.0) -> Color:
	return _color_h(p, n, vein_m, surface_h(p.x, p.z))

func _color_h(p: Vector3, n: Vector3, vein_m: float, h: float) -> Color:
	var under := h - p.y
	var c := ground
	var strata := 0.5 + 0.5 * sin(p.y * 1.7 + noise.get_noise_2d(p.x * 3.0, p.z * 3.0) * 2.0)
	if under > 1.5 or (under > 0.6 and n.y < -0.2):
		if ground_model != null:
			# Стены пещер и ходов — слои толщи: пласты полосами, мерзлота, осыпь у верха.
			c = ground_model.color_at(p, under, maxf(n.y, 0.0))
			if n.y > 0.55:
				c = c.lerp(Color(0.62, 0.55, 0.45), 0.2).lightened(0.08)
				c = c * (0.9 + 0.2 * patch_noise.get_noise_2d(p.x * 2.0, p.z * 2.0))
			elif n.y < -0.35:
				c = c.darkened(0.3)
		elif n.y > 0.55:
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
		if ground_model != null:
			# На крутом почва не держится: обрыв показывает осыпь и пласты.
			if steep > 0.0:
				c = c.lerp(ground_model.color_at(p, under + steep * 3.0, n.y), steep)
		else:
			c = c.lerp(cliff * (0.85 + 0.3 * strata), steep)
		var depth: float = clamp((under - 1.5) / 6.0, 0.0, 1.0)
		c = c.darkened(depth * 0.45)
		# Выходы материалов на ровных местах — пятнами, у каждого пятна свой материал.
		if not outcrops.is_empty() and n.y > 0.88 and depth < 0.3:
			var pn := patch_noise.get_noise_2d(p.x, p.z)
			if pn > 0.35:
				var k := int(floor((patch_noise.get_noise_2d(p.x * 0.3 + 100.0, p.z * 0.3) + 1.0) * 0.5 * outcrops.size())) % outcrops.size()
				c = c.lerp(outcrops[k], clamp((pn - 0.35) * 3.0, 0.0, 0.5))
		# Поросль ковром по ровному (у живых планет).
		if bio.is_valid() and n.y > 0.5 and depth < 0.5:
			var bc: Color = bio.call(p.x, p.z)
			c = c.lerp(Color(bc.r, bc.g, bc.b), bc.a * clampf((n.y - 0.5) * 3.0, 0.0, 1.0))
	c = c * (0.94 + 0.12 * noise.get_noise_2d(p.x * 5.0, p.z * 5.0))
	c.a = 1.0
	return c

## Шейдер рельефа: цвет вершины; видимость неба гасит общий свет и солнце, а
## фары и светящиеся кристаллы освещают в полную силу. Жилы слабо светятся.
const SHADER := """
shader_type spatial;
render_mode cull_disabled;
uniform vec3 vein_glow : source_color = vec3(0.5, 0.8, 1.0);
uniform float sink = 0.0;      // грубая сетка шара: опустить у робота под подробные куски
uniform vec3 eye;
uniform vec3 sink_center;
// Состояние поверхности (ProtoSurfaceState): R поросль, G влага, B лёд, A грунт —
// шесть граней кубосферы; в системе планеты (она же система сетки рельефа).
uniform bool surf_on = false;
uniform sampler2DArray surf : filter_linear, repeat_disable;
uniform vec3 surf_center;
uniform vec3 veg_col : source_color = vec3(0.3, 0.5, 0.25);
uniform vec3 veg_col2 : source_color = vec3(0.45, 0.55, 0.2);
uniform vec3 ice_col : source_color = vec3(0.84, 0.9, 0.96);
uniform vec3 soil_col : source_color = vec3(0.2, 0.15, 0.11);
varying float sky;
varying vec3 pl_pos;
varying vec3 pl_n;
varying float gloss;
void vertex() {
	sky = COLOR.a;
	pl_pos = VERTEX;
	pl_n = NORMAL;
	if (sink > 0.0) {
		vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
		float k = 1.0 - smoothstep(130.0, 160.0, length(wp - eye));
		VERTEX -= normalize(VERTEX - sink_center) * sink * k;
	}
}
float hash3(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.71, 0.113, 0.419));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}
float vnoise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash3(i), hash3(i + vec3(1, 0, 0)), f.x),
			mix(hash3(i + vec3(0, 1, 0)), hash3(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash3(i + vec3(0, 0, 1)), hash3(i + vec3(1, 0, 1)), f.x),
			mix(hash3(i + vec3(0, 1, 1)), hash3(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}
// Грань и (u, v) — как ProtoSurfaceState.face_uv.
vec3 face_uv(vec3 d) {
	vec3 a = abs(d);
	float f;
	vec2 ab;
	if (a.y >= a.x && a.y >= a.z) {
		if (d.y > 0.0) { f = 0.0; ab = vec2(d.x, d.z) / a.y; } else { f = 1.0; ab = vec2(d.x, -d.z) / a.y; }
	} else if (a.x >= a.z) {
		if (d.x > 0.0) { f = 2.0; ab = vec2(-d.y, d.z) / a.x; } else { f = 3.0; ab = vec2(d.y, d.z) / a.x; }
	} else {
		if (d.z > 0.0) { f = 4.0; ab = vec2(d.x, d.y) / a.z; } else { f = 5.0; ab = vec2(-d.x, d.y) / a.z; }
	}
	return vec3(atan(ab) / (PI * 0.5) + 0.5, f);
}
void fragment() {
	vec3 col = COLOR.rgb;
	float rough = 0.92;
	gloss = 0.0;
	if (surf_on) {
		vec3 d = normalize(pl_pos - surf_center);
		vec4 s = texture(surf, face_uv(d));
		if (s.r + s.g + s.b + s.a > 0.004) {     // нетронутая планета — без шума
			float up = clamp(dot(normalize(pl_n), d), 0.0, 1.0);
			// Шум рвёт края пятен: точка текстуры ~5 м, а край — куртинами по метру.
			float n1 = vnoise(pl_pos * 0.23);
			float n2 = vnoise(pl_pos * 0.9 + 7.0);
			float nz = n1 * 0.65 + n2 * 0.35 - 0.5;
			float open_sky = smoothstep(0.35, 0.75, sky);
			float soil = smoothstep(0.2, 0.55, s.a + nz * 0.5) * open_sky;
			col = mix(col, soil_col * (0.8 + 0.4 * n2), soil * 0.85);
			float wet = s.g * open_sky;
			col *= 1.0 - 0.38 * wet;
			float veg = smoothstep(0.28, 0.52, s.r + nz * 0.55) * smoothstep(0.5, 0.82, up) * open_sky;
			// Гуще и реже куртинами, два оттенка, мелкая рябь; в редкой — виден грунт.
			float dense = vnoise(pl_pos * 0.045 + 11.0);
			vec3 vc = mix(veg_col, veg_col2, smoothstep(0.3, 0.7, vnoise(pl_pos * 0.08 + 3.0)));
			vc *= 0.7 + 0.5 * vnoise(pl_pos * 2.7) + 0.15 * (dense - 0.5);
			col = mix(col, vc, veg * mix(0.55, 1.0, smoothstep(0.25, 0.75, dense)));
			float ice = smoothstep(0.3, 0.55, s.b + nz * 0.5 + (up - 0.75) * 0.35) * open_sky;
			col = mix(col, ice_col * (0.9 + 0.12 * n2), ice);
			rough = mix(rough, 0.62, max(wet * (1.0 - veg), ice));
			gloss = max(wet * (1.0 - veg) * 0.3, ice * 0.12);
		}
	}
	ALBEDO = col;
	ROUGHNESS = rough;
	AO = mix(0.06, 1.0, sky);
	AO_LIGHT_AFFECT = 0.0;
	EMISSION = vein_glow * UV.x * 0.35;
}
void light() {
	float k = LIGHT_IS_DIRECTIONAL ? sky : 1.0;
	DIFFUSE_LIGHT += clamp(dot(NORMAL, LIGHT), 0.0, 1.0) * ATTENUATION * LIGHT_COLOR * k / PI;
	if (gloss > 0.0) {
		// Мокрый грунт и лёд блестят на солнце.
		vec3 h = normalize(LIGHT + VIEW);
		SPECULAR_LIGHT += pow(clamp(dot(NORMAL, h), 0.0, 1.0), 48.0) * gloss * ATTENUATION * LIGHT_COLOR * k;
	}
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
