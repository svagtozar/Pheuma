class_name ProtoSurfaceState
extends Node
## Состояние поверхности всей планеты для терраформинга: поросль, влага, лёд,
## взрыхлённый грунт. Не в сетках рельефа, а в маленькой текстуре на весь шар
## (шесть граней кубосферы по RES² точек, RGBA8): шейдер рельефа смешивает её
## поверх природного цвета, с шумом по краю пятен — края естественные, хотя
## точка текстуры ~5 м. Трава расползается, лёд тает — сетки не перестраиваются.
## Память: 6 × 256² × 4 байта = 1,5 МБ в видеопамяти и столько же в ОЗУ на всю
## планету (сетки одного подробного куска 1 м — ~0,14 МБ, его тело — ~0,6 МБ).
## Рост и таяние считаются в потоке и только в «живых» плитках (TILE² точек),
## где что-то менялось: спокойная планета не стоит ничего.
##
## Каналы: R — поросль, G — влага, B — лёд и иней, A — взрыхлённый грунт.
## Грани и (u, v) — те же, что у ProtoPlanetStream._dir (равноугольная кубосфера).

const RES := 256
const TILE := 16
const TPF := RES / TILE        # плиток на ребро грани
const VEG := 0
const WET := 1
const ICE := 2
const SOIL := 3

var center := Vector3.ZERO     # центр шара в системе планеты
var radius := 800.0
var data := PackedByteArray()  # 6 граней × RES² × 4 канала
var tex: Texture2DArray
var mats: Array = []           # материалы рельефа, куда подключена текстура

## Климат (задаёт терраформинг): melt > 0 — лёд тает (единиц канала за шаг),
## < 0 — влага замерзает; habit 0..1 — сколько поросли держит место.
var melt := 0.0
var habit := 1.0
var grow := 9.0                # прирост поросли за шаг у края пятна
var dry := 1.0                 # высыхание влаги за шаг
var interval := 1.0            # шаг роста, с (игровое время)

var _active := {}              # номер плитки → true: здесь идёт рост/таяние
var _dirty := PackedByteArray()   # грань → 1, если её пора выгрузить
var _edge := {}                # индекс точки на краю грани → [4 соседа] через шов
var _t := 0.0
var _task := -1
var _next := PackedByteArray()
var _step_tiles: Array = []
var _changed: Array = []
var _upload_t := 0.0
var _pending: Array = []       # мазки, пришедшие во время шага в потоке
var steps := 0                 # сделано шагов (для тестов и лога)

var _brush := FastNoiseLite.new()

func _init(c := Vector3.ZERO, r := 800.0) -> void:
	_brush.frequency = 0.03
	center = c
	radius = r
	data.resize(6 * RES * RES * 4)
	_dirty.resize(6)
	_dirty.fill(1)

## Грань и (u, v) ∈ [0, 1] для направления d — обратное к dir_of.
static func face_uv(d: Vector3) -> Vector3:
	var a := d.abs()
	var f := 0
	var ab: Vector2
	if a.y >= a.x and a.y >= a.z:
		if d.y > 0.0:
			f = 0; ab = Vector2(d.x, d.z) / a.y
		else:
			f = 1; ab = Vector2(d.x, -d.z) / a.y
	elif a.x >= a.z:
		if d.x > 0.0:
			f = 2; ab = Vector2(-d.y, d.z) / a.x
		else:
			f = 3; ab = Vector2(d.y, d.z) / a.x
	else:
		if d.z > 0.0:
			f = 4; ab = Vector2(d.x, d.y) / a.z
		else:
			f = 5; ab = Vector2(-d.x, d.y) / a.z
	return Vector3(atan(ab.x) / (PI * 0.5) + 0.5, atan(ab.y) / (PI * 0.5) + 0.5, f)

## Направление на точку грани f с долями (u, v) — как ProtoPlanetStream._dir.
## u, v чуть за [0, 1] дают точку соседней грани (так ищем соседей через шов).
static func dir_of(f: int, u: float, v: float) -> Vector3:
	var a := tan((u - 0.5) * PI * 0.5)
	var b := tan((v - 0.5) * PI * 0.5)
	var p: Vector3
	match f:
		0: p = Vector3(a, 1.0, b)
		1: p = Vector3(a, -1.0, -b)
		2: p = Vector3(1.0, -a, b)
		3: p = Vector3(-1.0, a, b)
		4: p = Vector3(a, b, 1.0)
		_: p = Vector3(-a, b, -1.0)
	return p.normalized()

## Номер точки (без канала) для направления d.
static func cell_of(d: Vector3) -> int:
	var fu := face_uv(d)
	var i := clampi(int(fu.x * RES), 0, RES - 1)
	var j := clampi(int(fu.y * RES), 0, RES - 1)
	return (int(fu.z) * RES + j) * RES + i

static func cell_dir(c: int) -> Vector3:
	var f := c / (RES * RES)
	var r := c % (RES * RES)
	return dir_of(f, (r % RES + 0.5) / RES, (r / RES + 0.5) / RES)

## Состояние в точке q (система планеты), каналы 0..1.
func sample(q: Vector3) -> Color:
	var k := cell_of((q - center).normalized()) * 4
	return Color(data[k] / 255.0, data[k + 1] / 255.0, data[k + 2] / 255.0, data[k + 3] / 255.0)

## Мазок кистью: в круге радиуса r м вокруг q канал ch тянется к value (0..1),
## к краю круга слабее. add — не меньше/не больше value, а прибавить value.
func paint(q: Vector3, r: float, ch: int, value: float, add := false) -> void:
	if _task >= 0:
		_pending.append([q, r, ch, value, add])     # шаг в потоке: мазок — после него
		return
	var d := (q - center).normalized()
	var ang := r / radius
	var lim := cos(ang * 1.5)      # шум края дотягивает кисть до 1,5 радиуса
	var v8 := value * 255.0
	for f in 6:
		# Грань задета, если край круга до неё дотягивается: проверяем по
		# ближайшей к d точке грани (зажатая проекция).
		var fn := dir_of(f, 0.5, 0.5)
		if d.dot(fn) < cos(PI * 0.31 + ang):
			continue
		var p := _project(f, d)
		var span := ang * 1.5 / (PI * 0.5) * 1.6 + 2.0 / RES
		var i0 := clampi(int((p.x - span) * RES), 0, RES - 1)
		var i1 := clampi(int((p.x + span) * RES), 0, RES - 1)
		var j0 := clampi(int((p.y - span) * RES), 0, RES - 1)
		var j1 := clampi(int((p.y + span) * RES), 0, RES - 1)
		var hit := false
		for j in range(j0, j1 + 1):
			for i in range(i0, i1 + 1):
				var cd := dir_of(f, (i + 0.5) / RES, (j + 0.5) / RES)
				var c := cd.dot(d)
				if c < lim:
					continue
				# Край кисти неровный (шум по шару): пятна не круглые.
				var t := acos(clampf(c, -1.0, 1.0)) / maxf(ang, 1.0e-6)
				t += _brush.get_noise_3dv(cd * radius) * 0.45 * smoothstep(0.3, 0.8, t)
				var w := 1.0 - smoothstep(0.55, 1.0, t)
				var k := ((f * RES + j) * RES + i) * 4 + ch
				var old := float(data[k])
				var nv := old + v8 * w if add else lerpf(old, v8, w)
				data[k] = clampi(roundi(nv), 0, 255)
				hit = true
				_active[(f * TPF + j / TILE) * TPF + i / TILE] = true
		if hit:
			_dirty[f] = 1

## (u, v) на грани f для d, даже если d смотрит мимо неё (зажато в [0, 1]).
static func _project(f: int, d: Vector3) -> Vector2:
	var ab: Vector2
	match f:
		0: ab = Vector2(d.x, d.z) / maxf(d.y, 1.0e-3)
		1: ab = Vector2(d.x, -d.z) / maxf(-d.y, 1.0e-3)
		2: ab = Vector2(-d.y, d.z) / maxf(d.x, 1.0e-3)
		3: ab = Vector2(d.y, d.z) / maxf(-d.x, 1.0e-3)
		4: ab = Vector2(d.x, d.y) / maxf(d.z, 1.0e-3)
		_: ab = Vector2(-d.x, d.y) / maxf(-d.z, 1.0e-3)
	ab = ab.clamp(Vector2(-8.0, -8.0), Vector2(8.0, 8.0))
	return Vector2(atan(ab.x) / (PI * 0.5) + 0.5, atan(ab.y) / (PI * 0.5) + 0.5).clamp(Vector2.ZERO, Vector2.ONE)

## Весь канал сразу: fn(d: Vector3) → 0..1 (например, иней по всей холодной планете).
func fill(ch: int, fn: Callable) -> void:
	for c in 6 * RES * RES:
		data[c * 4 + ch] = clampi(roundi(float(fn.call(cell_dir(c))) * 255.0), 0, 255)
	_dirty.fill(1)
	for t in 6 * TPF * TPF:
		_active[t] = true

# ---------------------------------------------------------------- рост и таяние

func _process(dt: float) -> void:
	_t += dt
	if _task >= 0 and WorkerThreadPool.is_task_completed(_task):
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
		_finish()
	if _task < 0 and _t >= interval and not _active.is_empty():
		_t = 0.0
		_begin()
		_task = WorkerThreadPool.add_task(_run, false, "поверхность")
	_upload_t += dt
	if _upload_t >= 0.25:
		_upload_t = 0.0
		upload()

## Сразу n шагов (превью, тесты, перемотка при загрузке).
func step_now(n := 1) -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
		_finish()
	for s in n:
		if _active.is_empty():
			break
		_begin()
		_run()
		_finish()

func _begin() -> void:
	_step_tiles = _active.keys()
	_active = {}
	_next = data.duplicate()
	_changed = []

## Шаг в потоке: читает data, пишет _next; только в живых плитках.
func _run() -> void:
	for t: int in _step_tiles:
		if _step_tile(t):
			_changed.append(t)

func _finish() -> void:
	data = _next
	_next = PackedByteArray()
	steps += 1
	var pend := _pending
	_pending = []
	for p: Array in pend:
		paint(p[0], p[1], p[2], p[3], p[4])
	for t: int in _changed:
		_dirty[t / (TPF * TPF)] = 1
		# Живы плитка и соседи (поросль ползёт через край плитки и грани).
		_active[t] = true
		for nt in _tile_neighbors(t):
			_active[nt] = true

func _tile_neighbors(t: int) -> Array:
	var f := t / (TPF * TPF)
	var r := t % (TPF * TPF)
	var tx := r % TPF
	var ty := r / TPF
	var out: Array = []
	for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var x: int = tx + o.x
		var y: int = ty + o.y
		if x >= 0 and y >= 0 and x < TPF and y < TPF:
			out.append((f * TPF + y) * TPF + x)
		else:
			# Через шов: соседняя грань по направлению за краем.
			var c := cell_of(dir_of(f, (x * TILE + TILE * 0.5) / RES, (y * TILE + TILE * 0.5) / RES))
			var cf := c / (RES * RES)
			var cr := c % (RES * RES)
			out.append((cf * TPF + (cr / RES) / TILE) * TPF + (cr % RES) / TILE)
	return out

## Четыре соседа точки (номера без канала), через шов граней — тоже.
func _nb(f: int, i: int, j: int) -> Array:
	var c := (f * RES + j) * RES + i
	if i > 0 and j > 0 and i < RES - 1 and j < RES - 1:
		return [c - 1, c + 1, c - RES, c + RES]
	if _edge.has(c):
		return _edge[c]
	var out: Array = []
	for o in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
		var x: int = i + o.x
		var y: int = j + o.y
		if x >= 0 and y >= 0 and x < RES and y < RES:
			out.append((f * RES + y) * RES + x)
		else:
			out.append(cell_of(dir_of(f, (x + 0.5) / RES, (y + 0.5) / RES)))
	_edge[c] = out     # из потока: словарь пишет только этот шаг, главный поток не читает
	return out

## Шаг одной плитки. Правила (байты 0..255):
## лёд тает на melt, талая вода мочит грунт; влага сохнет на dry;
## поросль растёт у края пятна до потолка места: habit × (нет льда) × (влага);
## где потолок ниже — отмирает; поросль затягивает взрыхлённый грунт.
func _step_tile(t: int) -> bool:
	var f := t / (TPF * TPF)
	var r := t % (TPF * TPF)
	var i0 := (r % TPF) * TILE
	var j0 := (r / TPF) * TILE
	var changed := false
	var src := data
	for j in range(j0, j0 + TILE):
		for i in range(i0, i0 + TILE):
			var c := (f * RES + j) * RES + i
			var k := c * 4
			var veg := src[k]
			var wet := src[k + 1]
			var ice := src[k + 2]
			var soil := src[k + 3]
			var nwet := float(wet)
			var nice := float(ice)
			if melt > 0.0 and ice > 0:
				var m := minf(melt, nice)
				nice -= m
				nwet += m * 0.9
			elif melt < 0.0 and wet > 0:
				var m := minf(-melt, nwet)
				nwet -= m
				nice += m
			nwet = maxf(0.0, nwet - dry)
			# Поросль: лучший из соседей — «семя» с краю.
			var best := veg
			if i > 0 and j > 0 and i < RES - 1 and j < RES - 1:
				best = maxi(maxi(best, maxi(src[k - 4], src[k + 4])), maxi(src[k - RES * 4], src[k + RES * 4]))
				# По диагонали — чуть слабее: пятно растёт кругом, а не ромбом.
				var diag := maxi(maxi(src[k - RES * 4 - 4], src[k - RES * 4 + 4]), maxi(src[k + RES * 4 - 4], src[k + RES * 4 + 4]))
				best = maxi(best, int(diag * 0.8))
			else:
				for n: int in _nb(f, i, j):
					best = maxi(best, src[n * 4])
			var cap := 255.0 * habit * (1.0 - nice / 255.0) * (0.3 + 0.7 * minf(1.0, nwet / 140.0 + 0.25))
			var nveg := float(veg)
			if nveg < cap and best > 40:
				nveg = minf(cap, nveg + grow * (0.35 + 0.65 * best / 255.0))
			elif nveg > cap:
				nveg = maxf(cap, nveg - 6.0)
			var nsoil := maxf(0.0, soil - nveg / 80.0)
			var o := [clampi(roundi(nveg), 0, 255), clampi(roundi(nwet), 0, 255),
				clampi(roundi(nice), 0, 255), clampi(roundi(nsoil), 0, 255)]
			for q in 4:
				if o[q] != src[k + q]:
					_next[k + q] = o[q]
					changed = true
	return changed

# ---------------------------------------------------------------- для шейдера

## Выгрузить изменённые грани в видеопамять (по грани целиком, 256 КБ).
func upload() -> void:
	if tex == null:
		var imgs: Array[Image] = []
		for f in 6:
			imgs.append(_face_image(f))
		tex = Texture2DArray.new()
		tex.create_from_images(imgs)
		_dirty.fill(0)
		for m: ShaderMaterial in mats:
			m.set_shader_parameter("surf", tex)
		return
	for f in 6:
		if _dirty[f] == 1:
			_dirty[f] = 0
			tex.update_layer(_face_image(f), f)

func _face_image(f: int) -> Image:
	var n := RES * RES * 4
	return Image.create_from_data(RES, RES, false, Image.FORMAT_RGBA8, data.slice(f * n, (f + 1) * n))

## Подключить к материалу рельефа (ProtoTerrain.material()). veg — цвет поросли.
func bind(m: ShaderMaterial, veg: Color, veg2: Color) -> void:
	mats.append(m)
	m.set_shader_parameter("surf_on", true)
	m.set_shader_parameter("surf_center", center)
	m.set_shader_parameter("veg_col", veg)
	m.set_shader_parameter("veg_col2", veg2)
	if tex != null:
		m.set_shader_parameter("surf", tex)

# ---------------------------------------------------------------- сохранение

## Для ProtoSave: сжатые байты (нетронутая планета — сотни байт) и живые плитки.
func save_dict() -> Dictionary:
	return {"res": RES, "data": Marshalls.raw_to_base64(data.compress(FileAccess.COMPRESSION_ZSTD)),
		"active": _active.keys(), "melt": melt, "habit": habit}

func load_dict(d: Dictionary) -> void:
	if int(d.get("res", 0)) != RES:
		return
	var raw := Marshalls.base64_to_raw(String(d.get("data", "")))
	var got := raw.decompress(RES * RES * 24, FileAccess.COMPRESSION_ZSTD)
	if got.size() != data.size():
		return
	data = got
	_active = {}
	for t in d.get("active", []):
		_active[int(t)] = true
	melt = float(d.get("melt", 0.0))
	habit = float(d.get("habit", 1.0))
	_dirty.fill(1)

## Байт в видеопамяти (и столько же в ОЗУ).
static func bytes() -> int:
	return 6 * RES * RES * 4
