class_name ProtoFlow
extends RefCounted
## Живая жидкость на сетке рельефа (клетка 1 м): в каждой клетке — глубина слоя.
## За шаг жидкость перетекает к соседям, у которых зеркало ниже (без инерции —
## устойчиво при любом шаге). Вязкая жидкость течёт медленно и держит край
## (предел текучести: лава идёт языками, а не плёнкой). Остывающая жидкость
## (лава) твердеет коркой — корка становится дном для следующих потоков.
## Источники доливают, испарение убавляет; сетка поверхности строится только
## по мокрым клеткам и пересобирается, когда уровень заметно сдвинулся.

const WET := 0.004           # тоньше — клетка сухая, м
const SHOW := 0.03           # тоньше — не рисуем и не считаем зоной, м
const CRUST_TOP := 0.3       # корка рисуется и держит робота над дном, м

var terrain: ProtoTerrain
var sub: Substance
var nx := 0
var nz := 0
var ground := PackedFloat32Array()   # дно: рельеф + корка (NAN — ещё не считали)
var crust := PackedFloat32Array()    # застывший слой, м
var d := PackedFloat32Array()        # глубина жидкости, м
var heat := PackedFloat32Array()     # 1 — горячая, 0 — остыла (только у остывающих)
var hot := PackedByteArray()         # 1 — не остывает (озеро, кратер)
var dried := PackedByteArray()       # 1 — не испаряется (своё ложе озера)

var rate := 0.22             # доля перепада зеркал, что уходит к соседу за шаг (≤ 0,25)
var yield_h := 0.0           # предел текучести: перепад меньше — не течёт, м
var cool := 0.0              # остывание, 1/с на метр слоя (0 — не твердеет)
var evap := 0.0              # испарение вне своего ложа, м/с
var drain := 0.0             # убыль по всей площади (спад паводка), м/с — ставит хозяин
var sources: Array = []      # {i, q}: q — м³/с

var lo := Vector2i(1 << 20, 1 << 20)  # рамка мокрых клеток (включительно)
var hi := Vector2i(-1, -1)
var dirty := true            # поверхность сдвинулась — пора пересобрать сетку
var crust_dirty := false     # корка выросла — пора обновить столкновения (сбрасывает хозяин)
var change := 0.0            # наибольший сдвиг зеркала с прошлой сборки, м
var mesh := ArrayMesh.new()

var _out := PackedFloat32Array()     # отток к 4 соседям (x+, x−, z+, z−) за шаг
## 1 — клетку занимает неподвижная жидкость (русло реки): туда не течём, иначе
## озеро утекало бы под гладь реки и у устья стояло бы ниже неё ступенькой.
var blocked := PackedByteArray()

func _init(t: ProtoTerrain, s: Substance) -> void:
	terrain = t
	sub = s
	nx = t.sx
	nz = t.sz
	var n := nx * nz
	ground.resize(n)
	ground.fill(NAN)
	crust.resize(n)
	d.resize(n)
	heat.resize(n)
	heat.fill(1.0)
	hot.resize(n)
	dried.resize(n)
	blocked.resize(n)
	_out.resize(n * 4)
	# Вязкость → скорость растекания и предел текучести.
	var v := ProtoSwim.viscosity(s)
	rate = clampf(0.24 / (1.0 + v * 0.18), 0.08, 0.24)
	yield_h = 0.002 + maxf(0.0, v - 1.5) * 0.015     # вода держит гладь ровной, густое — край
	if s.melt > 300.0:
		cool = 0.02

func idx(x: int, z: int) -> int:
	return x + z * nx

func cell_of(x: float, z: float) -> int:
	var cx := int(floor(x))
	var cz := int(floor(z))
	if cx < 0 or cz < 0 or cx >= nx or cz >= nz:
		return -1
	return cx + cz * nx

func g(i: int) -> float:
	var v := ground[i]
	if is_nan(v):
		# Пол по полю плотности (как видимая сетка), а не по формуле рельефа:
		# на крутом склоне они расходятся на полметра, и тонкий слой прятался бы.
		var px := i % nx + 0.5
		var pz := i / nx + 0.5
		var top := terrain._site_h(px, pz) + 0.6
		if not terrain.edits.is_empty():
			top += terrain.edit_raise(px, pz)
		v = terrain.floor_at(Vector3(px, top, pz)) + crust[i]
		ground[i] = v
	return v

## Рельеф правили в box (бур, насыпь): дно задетых клеток — заново. Жидкость
## остаётся на месте и сама стекает в выкопанную яму (или растекается с насыпи),
## а не висит над ней на прежней высоте.
func reground(box: AABB) -> void:
	var x0 := maxi(int(floor(box.position.x)) - 1, 0)
	var z0 := maxi(int(floor(box.position.z)) - 1, 0)
	var x1 := mini(int(ceil(box.end.x)) + 1, nx - 1)
	var z1 := mini(int(ceil(box.end.z)) + 1, nz - 1)
	var touched := false
	for z in range(z0, z1 + 1):
		for x in range(x0, x1 + 1):
			var i := idx(x, z)
			if is_nan(ground[i]):
				continue
			var old := ground[i]
			ground[i] = NAN
			var v := g(i)
			if absf(v - old) > 0.01:
				touched = true
				if d[i] > WET:
					_grow(x, z)
	if touched:
		_calm = 0
		dirty = true

## Налить до уровня level в клетки области area (Callable(x, z) -> bool);
## keep — своё ложе: не остывает и не сохнет.
func fill(level: float, area: Callable, keep := true) -> void:
	for z in nz:
		for x in nx:
			if not area.call(x + 0.5, z + 0.5):
				continue
			var i := idx(x, z)
			var dep := level - g(i)
			if dep > WET:
				d[i] = dep
				_grow(x, z)
			if keep:
				hot[i] = 1
				dried[i] = 1
	dirty = true

func add_source(x: float, z: float, q: float) -> Dictionary:
	var s := {"i": cell_of(x, z), "q": q}
	sources.append(s)
	return s

## Долить объём vol (м³) в клетку i с жаром heat (частица Rapier осела, ProtoRapierFluid).
func pour(i: int, vol: float, h := 1.0) -> void:
	if i < 0:
		return
	var add := vol          # клетка 1×1 м: объём = толщина слоя
	if cool > 0.0:
		heat[i] = (heat[i] * d[i] + h * add) / (d[i] + add)
	d[i] += add
	_grow(i % nx, i / nx)
	_calm = 0
	dirty = true

func _grow(x: int, z: int) -> void:
	lo = Vector2i(mini(lo.x, x), mini(lo.y, z))
	hi = Vector2i(maxi(hi.x, x), maxi(hi.y, z))

func wet() -> bool:
	return hi.x >= 0

## Зеркало в клетке: дно + слой.
func level_i(i: int) -> float:
	return g(i) + d[i]

## Уровень под точкой (для урона, плавания и воды) — зеркало клетки.
func level_at(x: float, z: float) -> float:
	var i := cell_of(x, z)
	return -INF if i < 0 else g(i) + d[i]

## Жидкость под точкой: слой видим, а остывающая ещё горячая.
func wet_at(x: float, z: float) -> bool:
	var i := cell_of(x, z)
	return i >= 0 and d[i] > SHOW and (cool <= 0.0 or heat[i] > 0.25)

func volume() -> float:
	var v := 0.0
	if not wet():
		return v
	for z in range(lo.y, hi.y + 1):
		for x in range(lo.x, hi.x + 1):
			v += d[idx(x, z)]
	return v

var _calm := 0               # шагов подряд без заметного движения

## Шаг dt секунд. Спокойная жидкость (ни притока, ни убыли, ни остывания,
## гладь стоит) считается раз в 10 шагов: озеро в покое почти ничего не стоит.
func step(dt: float) -> void:
	var fed := drain > 0.0
	for s in sources:
		if s.q > 0.0:
			fed = true
	if fed or _calm < 20:
		_calm_dt = 0.0
	else:
		_calm_dt += dt
		if _calm % 10 != 0:
			_calm += 1
			return
		dt = _calm_dt
		_calm_dt = 0.0
	_step(dt)

var _calm_dt := 0.0

var _gb0 := Vector2i(1 << 20, 1 << 20)   # где дно уже посчитано (рамка)
var _gb1 := Vector2i(-1, -1)

## Досчитать дно в рамке с запасом в клетку (внутренний цикл читает ground напрямую).
func _ensure_ground(x0: int, z0: int, x1: int, z1: int) -> void:
	x0 = maxi(x0 - 1, 0); z0 = maxi(z0 - 1, 0)
	x1 = mini(x1 + 1, nx - 1); z1 = mini(z1 + 1, nz - 1)
	if x0 >= _gb0.x and z0 >= _gb0.y and x1 <= _gb1.x and z1 <= _gb1.y:
		return
	# Считаем всю общую рамку: иначе в ней остались бы дыры между двумя прежними.
	_gb0 = Vector2i(mini(_gb0.x, x0), mini(_gb0.y, z0))
	_gb1 = Vector2i(maxi(_gb1.x, x1), maxi(_gb1.y, z1))
	for z in range(_gb0.y, _gb1.y + 1):
		for x in range(_gb0.x, _gb1.x + 1):
			g(x + z * nx)

func _step(dt: float) -> void:
	for s in sources:
		var i: int = s.i
		if i < 0 or s.q <= 0.0:
			continue
		var add: float = s.q * dt
		if cool > 0.0:
			heat[i] = (heat[i] * d[i] + add) / (d[i] + add)
		d[i] += add
		_grow(i % nx, i / nx)
	if not wet():
		return
	# Рамка с запасом в клетку: туда жидкость может перетечь за шаг.
	var x0 := maxi(lo.x - 1, 0)
	var z0 := maxi(lo.y - 1, 0)
	var x1 := mini(hi.x + 1, nx - 1)
	var z1 := mini(hi.y + 1, nz - 1)
	_ensure_ground(x0, z0, x1, z1)
	var gr := ground
	var dd := d
	var out := _out
	var bl := blocked
	# 1) Отток каждой клетки к соседям с зеркалом ниже, не больше её слоя.
	for z in range(z0, z1 + 1):
		for x in range(x0, x1 + 1):
			var i := x + z * nx
			var o := i * 4
			var di := dd[i]
			if di <= WET:
				out[o] = 0.0; out[o + 1] = 0.0; out[o + 2] = 0.0; out[o + 3] = 0.0
				continue
			var r := rate
			var y := yield_h
			if cool > 0.0:
				# Остывая, лава густеет: течёт медленнее и держит толще край —
				# языки встают на склоне, а не стекают до подножия плёнкой.
				var hv := heat[i]
				r *= hv * hv
				y += (1.0 - hv) * 0.4
			var h := gr[i] + di - y
			var a := 0.0 if x + 1 >= nx or bl[i + 1] == 1 else maxf(0.0, h - gr[i + 1] - dd[i + 1]) * r
			var b := 0.0 if x == 0 or bl[i - 1] == 1 else maxf(0.0, h - gr[i - 1] - dd[i - 1]) * r
			var c := 0.0 if z + 1 >= nz or bl[i + nx] == 1 else maxf(0.0, h - gr[i + nx] - dd[i + nx]) * r
			var e := 0.0 if z == 0 or bl[i - nx] == 1 else maxf(0.0, h - gr[i - nx] - dd[i - nx]) * r
			var sum := a + b + c + e
			if sum > di:
				var k := di / sum
				a *= k; b *= k; c *= k; e *= k
			out[o] = a; out[o + 1] = b; out[o + 2] = c; out[o + 3] = e
	# 2) Перенос; тепло смешивается с притоком; остывание, испарение, корка.
	var nlo := Vector2i(1 << 20, 1 << 20)
	var nhi := Vector2i(-1, -1)
	var moved := 0.0
	var cooling := false
	for z in range(z0, z1 + 1):
		for x in range(x0, x1 + 1):
			var i := x + z * nx
			var o := i * 4
			var gone := out[o] + out[o + 1] + out[o + 2] + out[o + 3]
			var inn := 0.0
			var inh := 0.0
			if x > x0:
				var f := out[(i - 1) * 4]
				inn += f; inh += f * heat[i - 1]
			if x < x1:
				var f := out[(i + 1) * 4 + 1]
				inn += f; inh += f * heat[i + 1]
			if z > z0:
				var f := out[(i - nx) * 4 + 2]
				inn += f; inh += f * heat[i - nx]
			if z < z1:
				var f := out[(i + nx) * 4 + 3]
				inn += f; inh += f * heat[i + nx]
			var old := d[i]
			var nd := old - gone + inn
			if nd <= WET and old <= WET:
				continue
			if cool > 0.0 and nd > WET:
				heat[i] = (heat[i] * (old - gone) + inh) / nd
			if dried[i] == 0:
				nd -= evap * dt
			nd -= drain * dt
			if cool > 0.0 and hot[i] == 0 and nd > WET:
				cooling = true
				heat[i] -= cool * dt / (nd + 0.15)
				if heat[i] <= 0.1:
					# Застыла: слой уходит в корку, корка — новое дно.
					crust[i] += nd
					ground[i] = g(i) + nd
					nd = 0.0
					crust_dirty = true
					crust_box_lo = Vector2i(mini(crust_box_lo.x, x), mini(crust_box_lo.y, z))
					crust_box_hi = Vector2i(maxi(crust_box_hi.x, x), maxi(crust_box_hi.y, z))
					dirty = true
			if nd <= WET:
				nd = 0.0
				heat[i] = 1.0
			else:
				nlo = Vector2i(mini(nlo.x, x), mini(nlo.y, z))
				nhi = Vector2i(maxi(nhi.x, x), maxi(nhi.y, z))
			moved = maxf(moved, absf(nd - old))
			d[i] = nd
	lo = nlo
	hi = nhi
	_calm = 0 if moved > 0.002 or cooling else _calm + 1
	change += moved
	if change > 0.01:
		dirty = true

# ---------------------------------------------------------------- сетка

## Пересобрать поверхность: мокрые клетки и корка. Вершина угла — среднее
## зеркал соседних показанных клеток (озеро — ровная гладь, поток на склоне —
## наклонная лента); цвет вершины r — жар (шейдер рисует остывшее коркой).
func rebuild() -> void:
	dirty = false
	change = 0.0
	mesh.clear_surfaces()
	var b0 := lo
	var b1 := hi
	if crust_box_hi.x >= 0:
		b0 = Vector2i(mini(b0.x, crust_box_lo.x), mini(b0.y, crust_box_lo.y))
		b1 = Vector2i(maxi(b1.x, crust_box_hi.x), maxi(b1.y, crust_box_hi.y))
	if b1.x < 0:
		return
	var w := b1.x - b0.x + 1
	var hgt := b1.y - b0.y + 1
	# Сетка рельефа сглажена и чуть выше рельефа по формуле: тонкий слой лавы
	# и корку поднимаем, чтобы склон не протыкал их пятнами.
	var thin := 0.3 if cool > 0.0 else 0.12
	var top := PackedFloat32Array()
	top.resize(w * hgt)
	var ht := PackedFloat32Array()
	ht.resize(w * hgt)
	var show := PackedByteArray()
	show.resize(w * hgt)
	var any := false
	for z in hgt:
		for x in w:
			var i := idx(b0.x + x, b0.y + z)
			var k := x + z * w
			if d[i] > SHOW:
				show[k] = 1
				top[k] = g(i) + maxf(d[i], thin)
				ht[k] = heat[i] if cool > 0.0 else 1.0
				any = true
			elif crust[i] > 0.02:
				show[k] = 1
				top[k] = g(i) + CRUST_TOP
				ht[k] = 0.0
				any = true
	if not any:
		return
	# Углы: среднее по показанным соседним клеткам (каждая клетка — в свои 4 угла).
	var cw := w + 1
	var cy := PackedFloat32Array()
	cy.resize(cw * (hgt + 1))
	var ch := PackedFloat32Array()
	ch.resize(cw * (hgt + 1))
	var cn := PackedFloat32Array()
	cn.resize(cw * (hgt + 1))
	for z in hgt:
		for x in w:
			var k := x + z * w
			if show[k] == 0:
				continue
			var c0 := x + z * cw
			for cc in [c0, c0 + 1, c0 + cw, c0 + cw + 1]:
				cy[cc] += top[k]
				ch[cc] += ht[k]
				cn[cc] += 1.0
	for cc in cy.size():
		if cn[cc] > 0.0:
			cy[cc] /= cn[cc]
			ch[cc] /= cn[cc]
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	for z in hgt:
		for x in w:
			if show[x + z * w] == 0:
				continue
			var c0 := x + z * cw
			var p0 := Vector3(b0.x + x, cy[c0], b0.y + z)
			var p1 := Vector3(b0.x + x + 1, cy[c0 + 1], b0.y + z)
			var p2 := Vector3(b0.x + x + 1, cy[c0 + cw + 1], b0.y + z + 1)
			var p3 := Vector3(b0.x + x, cy[c0 + cw], b0.y + z + 1)
			var h0 := ch[c0]
			var h1 := ch[c0 + 1]
			var h2 := ch[c0 + cw + 1]
			var h3 := ch[c0 + cw]
			var n1 := (p2 - p0).cross(p1 - p0).normalized()
			var n2 := (p3 - p0).cross(p2 - p0).normalized()
			verts.append_array([p0, p1, p2, p0, p2, p3])
			norms.append_array([n1, n1, n1, n2, n2, n2])
			cols.append_array([Color(h0, h0, h0), Color(h1, h1, h1), Color(h2, h2, h2),
				Color(h0, h0, h0), Color(h2, h2, h2), Color(h3, h3, h3)])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_COLOR] = cols
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)

# ---------------------------------------------------------------- корка

var crust_box_lo := Vector2i(1 << 20, 1 << 20)
var crust_box_hi := Vector2i(-1, -1)

## Карта высот для столкновений по корке: вершины — центры клеток рамки,
## без корки — чуть ниже рельефа (там пол — сетка рельефа). [позиция, форма] или [].
func crust_shape() -> Array:
	if crust_box_hi.x < 0:
		return []
	var b0 := crust_box_lo - Vector2i(1, 1)
	var b1 := crust_box_hi + Vector2i(1, 1)
	b0 = Vector2i(maxi(b0.x, 0), maxi(b0.y, 0))
	b1 = Vector2i(mini(b1.x, nx - 1), mini(b1.y, nz - 1))
	var w := b1.x - b0.x + 1
	var h := b1.y - b0.y + 1
	var data := PackedFloat32Array()
	data.resize(w * h)
	for z in h:
		for x in w:
			var i := idx(b0.x + x, b0.y + z)
			data[x + z * w] = g(i) + CRUST_TOP if crust[i] > 0.02 else g(i) - 0.3
	var hs := HeightMapShape3D.new()
	hs.map_width = w
	hs.map_depth = h
	hs.map_data = data
	# Форма по центру: вершина (0, 0) — в центре клетки b0.
	return [Vector3(b0.x + 0.5 + (w - 1) * 0.5, 0.0, b0.y + 0.5 + (h - 1) * 0.5), hs]
