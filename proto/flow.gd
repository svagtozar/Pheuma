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

const GRAV := 9.8
const VMAX := 4.0            # скорость течения в цвете вершины — до ±4 м/с
var rate := 0.22             # текучесть: 0,24 — вода без вязкости, меньше — гуще
var fric := 0.5              # трение о дно, м/с: поток в трубе гаснет как 1/(1 + fric·dt/слой)
var _dt := 0.1               # последний шаг, с (скорость течения для сетки)
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
var mat: ShaderMaterial              # её шейдер (ProtoLiquids): хозяин ведёт morph
var _was := PackedFloat32Array()     # гладь прошлой сборки по клеткам (NAN — не было)
var _was_h := PackedFloat32Array()   # и её жар
var _was_i := PackedInt32Array()     # где она была (чтобы стереть)

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
	_was.resize(n)
	_was.fill(NAN)
	_was_h.resize(n)
	# Вязкость → скорость растекания и предел текучести.
	var v := ProtoSwim.viscosity(s)
	rate = clampf(0.24 / (1.0 + v * 0.18), 0.08, 0.24)
	yield_h = 0.002 + maxf(0.0, v - 1.5) * 0.015     # вода держит гладь ровной, густое — край
	fric = 0.25 + v * 0.3
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

## Поток в трубе за шаг (объём): прежний, погашенный трением, плюс разгон
## от перепада dh; перепад меньше предела текучести y не разгоняет.
static func _pipe(f: float, keep: float, k: float, dh: float, y: float) -> float:
	var drive := dh - y if dh > y else minf(dh, 0.0)
	return maxf(0.0, f * keep + k * drive)

func _step(dt: float) -> void:
	_dt = dt
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
	# 1) Отток к соседям — «виртуальные трубы»: поток в трубе копит разгон от
	# перепада зеркал и гаснет трением о дно (тонкий слой тормозит сильнее).
	# Так фронт бежит волной и с разгону, а не расползается ровной плёнкой.
	var kg := GRAV * dt * dt * rate / 0.24
	for z in range(z0, z1 + 1):
		for x in range(x0, x1 + 1):
			var i := x + z * nx
			var o := i * 4
			var di := dd[i]
			if di <= WET:
				out[o] = 0.0; out[o + 1] = 0.0; out[o + 2] = 0.0; out[o + 3] = 0.0
				continue
			var k := kg
			var y := yield_h
			var fr := fric
			if cool > 0.0:
				# Остывая, лава густеет: течёт медленнее и держит толще край —
				# языки встают на склоне, а не стекают до подножия плёнкой.
				var hv := heat[i]
				k *= hv * hv
				fr /= hv * hv + 0.03
				y += (1.0 - hv) * 0.4
			var keep := 1.0 / (1.0 + fr * dt / (di + 0.08))
			var h := gr[i] + di
			var a := 0.0 if x + 1 >= nx or bl[i + 1] == 1 else _pipe(out[o], keep, k, h - gr[i + 1] - dd[i + 1], y)
			var b := 0.0 if x == 0 or bl[i - 1] == 1 else _pipe(out[o + 1], keep, k, h - gr[i - 1] - dd[i - 1], y)
			var c := 0.0 if z + 1 >= nz or bl[i + nx] == 1 else _pipe(out[o + 2], keep, k, h - gr[i + nx] - dd[i + nx], y)
			var e := 0.0 if z == 0 or bl[i - nx] == 1 else _pipe(out[o + 3], keep, k, h - gr[i - nx] - dd[i - nx], y)
			var sum := a + b + c + e
			if sum > di:
				var q := di / sum
				a *= q; b *= q; c *= q; e *= q
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
	# Клетка запаса: гладкий край заходит на сухих соседей.
	b0 = Vector2i(maxi(b0.x - 1, 0), maxi(b0.y - 1, 0))
	b1 = Vector2i(mini(b1.x + 1, nx - 1), mini(b1.y + 1, nz - 1))
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
	# Скорость течения клетки (м/с) из потоков в трубах: шейдер сносит по ней рябь.
	var ux := PackedFloat32Array()
	ux.resize(w * hgt)
	var uz := PackedFloat32Array()
	uz.resize(w * hgt)
	var any := false
	var inv := 0.5 / maxf(_dt, 0.001)
	for z in hgt:
		for x in w:
			var gx := b0.x + x
			var gz := b0.y + z
			var i := idx(gx, gz)
			var k := x + z * w
			if d[i] > SHOW:
				show[k] = 1
				top[k] = g(i) + maxf(d[i], thin)
				ht[k] = heat[i] if cool > 0.0 else 1.0
				any = true
				var o := i * 4
				var fx := _out[o] - _out[o + 1]
				var fz := _out[o + 2] - _out[o + 3]
				if gx + 1 < nx: fx -= _out[(i + 1) * 4 + 1]
				if gx > 0: fx += _out[(i - 1) * 4]
				if gz + 1 < nz: fz -= _out[(i + nx) * 4 + 3]
				if gz > 0: fz += _out[(i - nx) * 4 + 2]
				var dep := maxf(d[i], 0.1)
				ux[k] = clampf(fx * inv / dep, -VMAX, VMAX)
				uz[k] = clampf(fz * inv / dep, -VMAX, VMAX)
			elif crust[i] > 0.02:
				show[k] = 1
				top[k] = g(i) + CRUST_TOP
				ht[k] = 0.0
				any = true
	if not any:
		return
	# Вершины — центры клеток. Край гладкий: «мокрость» клеток (1/0) размыта
	# 3×3, контур — изолиния 0,5 (марширующие треугольники); квадраты у края
	# делим на 2×2, внутри озера — по квадрату на клетку, как раньше.
	var n := w * hgt
	var sv := PackedFloat32Array()
	sv.resize(n)
	var sy := PackedFloat32Array()
	sy.resize(n)
	var sh := PackedFloat32Array()
	sh.resize(n)
	var su := ux.duplicate()
	var sw := uz.duplicate()
	for k in n:
		if show[k] == 1:
			sv[k] = 1.0
			sy[k] = top[k]
			sh[k] = ht[k]
	# Размытие 1-2-1 по x, потом по z (вместе — ядро 3×3 с весами 1/2/4).
	for pass_z in 2:
		var step := w if pass_z == 1 else 1
		var av := sv.duplicate()
		var ay := sy.duplicate()
		var ah := sh.duplicate()
		var au := su.duplicate()
		var aw := sw.duplicate()
		for z in hgt:
			for x in w:
				var k := x + z * w
				var has_lo := (z > 0) if pass_z == 1 else (x > 0)
				var has_hi := (z < hgt - 1) if pass_z == 1 else (x < w - 1)
				var v := av[k] * 2.0
				var y := ay[k] * 2.0
				var h := ah[k] * 2.0
				var u := au[k] * 2.0
				var q := aw[k] * 2.0
				if has_lo:
					v += av[k - step]
					y += ay[k - step]
					h += ah[k - step]
					u += au[k - step]
					q += aw[k - step]
				if has_hi:
					v += av[k + step]
					y += ay[k + step]
					h += ah[k + step]
					u += au[k + step]
					q += aw[k + step]
				sv[k] = v
				sy[k] = y
				sh[k] = h
				su[k] = u
				sw[k] = q
	var vb := PackedFloat32Array()
	vb.resize(n)
	var hc := top.duplicate()
	# Атрибуты вершины: жар, скорость x, z (размытые — течение плавное) и сдвиг
	# к глади прошлой сборки: шейдер ведёт гладь от неё к нынешней (morph).
	var at := PackedVector4Array()
	at.resize(n)
	var dh := PackedFloat32Array()
	dh.resize(n)
	for k in n:
		var bl := sv[k] / 16.0
		var hk := ht[k]
		if show[k] == 1:
			# Мокрая клетка всегда внутри, сухая снаружи: размытие лишь двигает
			# контур между ними (иначе тонкие языки лавы в клетку шириной пропадали).
			vb[k] = maxf(bl, 0.6)
		else:
			vb[k] = minf(bl, 0.45)
			if sv[k] > 0.0:
				hc[k] = sy[k] / sv[k]   # сухая клетка у края — высота соседей
				hk = sh[k] / sv[k]
		var i := idx(b0.x + k % w, b0.y + k / w)
		var was := _was[i]
		# Новая клетка поднимается от дна, а не возникает сразу во всю толщину.
		var dy := (was if not is_nan(was) else minf(g(i), hc[k])) - hc[k]
		at[k] = Vector4(hk, su[k] / 16.0, sw[k] / 16.0, clampf(dy, -3.0, 3.0))
		dh[k] = (_was_h[i] - hk) if not is_nan(was) else 0.0
	for i in _was_i:
		_was[i] = NAN
	_was_i.clear()
	for k in n:
		if vb[k] >= 0.45 or show[k] == 1:
			var i := idx(b0.x + k % w, b0.y + k / w)
			_was[i] = hc[k]
			_was_h[i] = at[k].x
			_was_i.append(i)
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var uvs := PackedVector2Array()
	var ox := b0.x + 0.5
	var oz := b0.y + 0.5
	for z in hgt - 1:
		for x in w - 1:
			var k0 := x + z * w
			var k1 := k0 + 1
			var k2 := k0 + w
			var k3 := k2 + 1
			var v0 := vb[k0]
			var v1 := vb[k1]
			var v2 := vb[k2]
			var v3 := vb[k3]
			if v0 < 0.5 and v1 < 0.5 and v2 < 0.5 and v3 < 0.5:
				continue
			var px := ox + x
			var pz := oz + z
			if v0 > 0.99 and v1 > 0.99 and v2 > 0.99 and v3 > 0.99:
				# Внутри: квадрат целиком.
				var a0 := Vector3(px, hc[k0], pz)
				var a1 := Vector3(px + 1, hc[k1], pz)
				var a2 := Vector3(px, hc[k2], pz + 1)
				var a3 := Vector3(px + 1, hc[k3], pz + 1)
				_tri(a0, a1, a3, at[k0], at[k1], at[k3], dh[k0], dh[k1], dh[k3], verts, norms, cols, uvs)
				_tri(a0, a3, a2, at[k0], at[k3], at[k2], dh[k0], dh[k3], dh[k2], verts, norms, cols, uvs)
				continue
			# У края: 3×3 точки (шаг 0,5 м) билинейно, 4 квадратика по 2 треугольника.
			var gp := PackedVector3Array()
			var gv := PackedFloat32Array()
			var gt := PackedVector4Array()
			var ge := PackedFloat32Array()
			for j in 3:
				var fw := j * 0.5
				for i in 3:
					var fu := i * 0.5
					var y := lerpf(lerpf(hc[k0], hc[k1], fu), lerpf(hc[k2], hc[k3], fu), fw)
					gp.append(Vector3(px + fu, y, pz + fw))
					gv.append(lerpf(lerpf(v0, v1, fu), lerpf(v2, v3, fu), fw))
					gt.append(at[k0].lerp(at[k1], fu).lerp(at[k2].lerp(at[k3], fu), fw))
					ge.append(lerpf(lerpf(dh[k0], dh[k1], fu), lerpf(dh[k2], dh[k3], fu), fw))
			for j in 2:
				for i in 2:
					var c0 := i + j * 3
					var c1 := c0 + 1
					var c2 := c0 + 4
					var c3 := c0 + 3
					_march_tri(gp[c0], gv[c0], gt[c0], ge[c0], gp[c1], gv[c1], gt[c1], ge[c1], gp[c2], gv[c2], gt[c2], ge[c2], verts, norms, cols, uvs)
					_march_tri(gp[c0], gv[c0], gt[c0], ge[c0], gp[c2], gv[c2], gt[c2], ge[c2], gp[c3], gv[c3], gt[c3], ge[c3], verts, norms, cols, uvs)
	if verts.is_empty():
		return
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_TEX_UV] = uvs
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)

## Часть треугольника, где мокрость ≥ 0,5 (марширующие треугольники).
static func _march_tri(pa: Vector3, va: float, ta: Vector4, ea: float, pb: Vector3, vb: float, tb: Vector4, eb: float,
		pc: Vector3, vc: float, tc: Vector4, ec: float, verts: PackedVector3Array, norms: PackedVector3Array,
		cols: PackedColorArray, uvs: PackedVector2Array) -> void:
	var ia := va >= 0.5
	var ib := vb >= 0.5
	var ic := vc >= 0.5
	if ia and ib and ic:
		_tri(pa, pb, pc, ta, tb, tc, ea, eb, ec, verts, norms, cols, uvs)
		return
	if not ia and not ib and not ic:
		return
	# Повернём, чтобы «особая» вершина (одна внутри или одна снаружи) была первой.
	if ia == ib:
		var p := pa; var v := va; var t := ta; var e := ea
		pa = pc; va = vc; ta = tc; ea = ec
		pc = pb; vc = vb; tc = tb; ec = eb
		pb = p; vb = v; tb = t; eb = e
	elif ia == ic:
		var p := pa; var v := va; var t := ta; var e := ea
		pa = pb; va = vb; ta = tb; ea = eb
		pb = pc; vb = vc; tb = tc; eb = ec
		pc = p; vc = v; tc = t; ec = e
	var sab := (0.5 - va) / (vb - va)
	var sac := (0.5 - va) / (vc - va)
	var qab := pa.lerp(pb, sab)
	var qac := pa.lerp(pc, sac)
	var tab := ta.lerp(tb, sab)
	var tac := ta.lerp(tc, sac)
	var eab := lerpf(ea, eb, sab)
	var eac := lerpf(ea, ec, sac)
	if va >= 0.5:
		_tri(pa, qab, qac, ta, tab, tac, ea, eab, eac, verts, norms, cols, uvs)
	else:
		_tri(qab, pb, pc, tab, tb, tc, eab, eb, ec, verts, norms, cols, uvs)
		_tri(qab, pc, qac, tab, tc, tac, eab, ec, eac, verts, norms, cols, uvs)

## Треугольник лицом вверх (порядок вершин — по часовой, если смотреть сверху).
## h: x — жар, y, z — скорость x, z, w — сдвиг к прошлой глади; e — сдвиг к
## прошлому жару. Цвет: r — жар, g, b — скорость (0,5 — стоит, ±VMAX — 0 и 1);
## UV — сдвиги (шейдер ведёт от прошлой сборки к нынешней).
static func _tri(p0: Vector3, p1: Vector3, p2: Vector3, h0: Vector4, h1: Vector4, h2: Vector4,
		e0: float, e1: float, e2: float,
		verts: PackedVector3Array, norms: PackedVector3Array, cols: PackedColorArray, uvs: PackedVector2Array) -> void:
	var nn := (p2 - p0).cross(p1 - p0)
	if nn.y < 0.0:
		var tp := p1; p1 = p2; p2 = tp
		var th := h1; h1 = h2; h2 = th
		var te := e1; e1 = e2; e2 = te
		nn = -nn
	var n := nn.normalized()
	verts.append(p0); verts.append(p1); verts.append(p2)
	norms.append(n); norms.append(n); norms.append(n)
	cols.append(Color(h0.x, 0.5 + h0.y * 0.5 / VMAX, 0.5 + h0.z * 0.5 / VMAX))
	cols.append(Color(h1.x, 0.5 + h1.y * 0.5 / VMAX, 0.5 + h1.z * 0.5 / VMAX))
	cols.append(Color(h2.x, 0.5 + h2.y * 0.5 / VMAX, 0.5 + h2.z * 0.5 / VMAX))
	uvs.append(Vector2(h0.w, e0)); uvs.append(Vector2(h1.w, e1)); uvs.append(Vector2(h2.w, e2))

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
