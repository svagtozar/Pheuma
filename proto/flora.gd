class_name ProtoFlora
extends RefCounted
## Инопланетная органика по тегам планеты: мох, щетина, ваи, фонарики,
## кораллы, пузыри, трубчатые черви, трутовики в пещере. Всё процедурное:
## набор форм, палитра, рост и густота свои у каждой планеты (по seed).
##   Жизнь (0–3): грибная биосфера +3, океаническая +2, органика среди
##   материалов, плотная атмосфера — плюс; мороз, разреженный воздух, жар,
##   радиация, кислотные дожди — минус. 0 — мёртвая, 3 — буйная.
##   Формы: океан — ваи, кораллы, черви у воды; вулкан — черви и оранжевые
##   маты термофилов; приливный захват и радиация — светящиеся фонарики;
##   плотная атмосфера и слабая тяжесть — парящие пузыри на привязи.
##   Палитра: оттенок от seed, смещённый тегами (яды — жёлто-зелёный,
##   окислитель — красный, сумерки — фиолетовый, океан — бирюза).
## Сетки склеены по кускам карты 27×27 м: низкая поросль без теней, крупные
## формы с тенями, пещера отдельно — десятки вызовов отрисовки на всю флору.
## Качается на ветру в вершинном шейдере (UV.x — гибкость, UV.y — фаза),
## светится по альфе цвета вершины.

const LIFE_NAMES := ["нет", "лишайники", "заросли", "буйная"]
const FORM_NAMES := {"moss": "мох", "tuft": "щетина", "frond": "ваи", "lantern": "фонарики",
	"coral": "кораллы", "bladder": "пузыри", "tubes": "трубчатые черви", "shelf": "трутовики"}
## Крупные формы и их вес по тегам (плюс немного случайности у каждой планеты).
const BIG_FORMS := ["frond", "lantern", "coral", "bladder", "tubes"]
const CHUNK := 27.0

var life := 0
var forms: Array = []          # крупные формы этой планеты
var tuft := false              # щетина среди мха
var hue := 0.3                 # основной оттенок (мох)
var hue2 := 0.4                # стебли и листья
var hue3 := 0.8                # акцент: кончики, пузыри, свечение
var sat := 0.55
var val := 0.45
var glow := 0.4                # сила свечения акцентов
var wind := 0.2
var grow := 1.0                # множитель роста (слабая тяжесть — выше)
var floating := false          # пузыри парят на привязи
var thermo := false            # маты термофилов (вулкан)
var fungal := false

var terrain: ProtoTerrain
var style: ProtoWorldStyle
var rng := RandomNumberGenerator.new()
var noise := FastNoiseLite.new()   # где гуще (и ковёр на грунте, и растения)
var thr := 2.0                     # порог плодородия по уровню жизни
var _geo := {}                 # ключ куска → Geo
var plants := 0
var best := Vector3.INF        # самое густое место с крупной формой (для кадра)
var best_fert := -INF
## Растения, которые робот срезает (ProtoHarvest): {key — кусок сетки, v0..v1 и
## i0..i1 — его вершины и индексы, p — основание, h — высота, r — размах, form, col, cut}.
var items: Array = []
var node: Node3D               # общий узел флоры (на шаре двигается с участком)
var meshes := {}               # ключ куска → MeshInstance3D
var mat: ShaderMaterial
var _dirty := {}               # куски, которые надо пересобрать после среза

static func for_planet(p: Planet, st: ProtoWorldStyle, seed_value: int) -> ProtoFlora:
	var f := ProtoFlora.new()
	f.style = st
	var r := RandomNumberGenerator.new()
	r.seed = seed_value * 97 + 11
	f.rng.seed = seed_value * 53 + 29
	var t := func(tag: String) -> bool: return p.has_tag(tag)
	var org := 0
	for m in p.materials:
		if m.has("organic") or m.has("fibrous"):
			org += 1
	# --- сколько жизни
	var score := minf(org, 3) * 0.45
	if t.call("fungal_biosphere"): score += 3.0
	if t.call("oceanic"): score += 2.0
	if t.call("dense_atmosphere"): score += 0.5
	if t.call("thin_atmosphere"): score -= 2.0
	if t.call("radiation"): score -= 0.5
	if t.call("acid_rain"): score -= 0.4
	if p.ambient_temp < -60.0: score -= 3.0
	elif p.ambient_temp < -20.0: score -= 0.8
	if p.ambient_temp > 100.0: score -= 1.5
	f.life = clampi(roundi(score), 0, 3)
	f.noise.seed = seed_value * 5 + 1
	f.noise.frequency = 0.05
	f.noise.fractal_octaves = 2
	f.thr = [2.0, 0.42, 0.16, -0.08][f.life]
	f.fungal = t.call("fungal_biosphere")
	# --- формы
	var w := {"frond": 0.3, "lantern": 0.3, "coral": 0.3, "bladder": 0.3, "tubes": 0.3}
	if t.call("oceanic"): w.frond += 2.0; w.coral += 2.0; w.tubes += 0.8
	if t.call("volcanic"): w.tubes += 2.0; f.thermo = true
	if t.call("tidally_locked"): w.lantern += 2.0
	if t.call("radiation"): w.lantern += 1.0
	if t.call("fungal_biosphere"): w.bladder += 1.2; w.lantern += 0.8
	if t.call("dense_atmosphere"): w.bladder += 1.5; w.frond += 0.6
	if t.call("low_gravity"): w.bladder += 1.2
	if t.call("toxic_atmosphere"): w.coral += 0.8
	if t.call("acid_rain"): w.tubes += 0.6
	if t.call("crystalline_crust"): w.coral += 0.5
	for k in w:
		w[k] *= r.randf_range(0.5, 1.5)
	var n: int = [0, 0, 2, 3][f.life]
	while f.forms.size() < n:
		var k := _pick(w, r)
		f.forms.append(k)
		w.erase(k)
	f.tuft = f.life >= 1 and not f.fungal and (t.call("oceanic") or r.randf() < 0.65)
	f.floating = t.call("dense_atmosphere") or t.call("low_gravity") or p.gravity < 0.8
	# --- палитра: случайный оттенок, притянутый тегами
	var bias := -1.0
	if t.call("fungal_biosphere"): bias = 0.8
	elif t.call("toxic_atmosphere"): bias = 0.2
	elif t.call("oxidizing_atmosphere"): bias = 0.01
	elif t.call("tidally_locked"): bias = 0.74
	elif t.call("oceanic"): bias = 0.47
	elif t.call("volcanic"): bias = 0.07
	elif t.call("radiation"): bias = 0.3
	var h := r.randf()
	if bias >= 0.0:
		h = fposmod(bias + wrapf(h - bias, -0.5, 0.5) * 0.3, 1.0)
	f.hue = h
	f.hue2 = fposmod(h + r.randf_range(-0.12, 0.12), 1.0)
	f.hue3 = fposmod(h + r.randf_range(0.3, 0.7), 1.0)
	f.sat = r.randf_range(0.45, 0.7)
	f.val = r.randf_range(0.36, 0.55)
	f.glow = 0.35
	if t.call("tidally_locked"): f.glow += 1.0; f.val *= 0.8
	if t.call("radiation"): f.glow += 0.6
	if t.call("fungal_biosphere"): f.glow += 0.4
	f.wind = st.wind + (0.3 if t.call("dense_atmosphere") else 0.12)
	f.grow = clampf(1.0 / sqrt(p.gravity), 0.75, 1.5)
	return f

static func _pick(w: Dictionary, r: RandomNumberGenerator) -> String:
	var sum := 0.0
	for k in w:
		sum += w[k]
	var x := r.randf() * sum
	for k in w:
		x -= w[k]
		if x <= 0.0:
			return k
	return w.keys()[0]

func summary() -> String:
	if life == 0:
		return "жизнь: нет"
	var names := ["мох"]
	if tuft: names.append(FORM_NAMES.tuft)
	for k in forms:
		names.append(FORM_NAMES[k])
	return "жизнь: %s — %s" % [LIFE_NAMES[life], ", ".join(PackedStringArray(names))]

# ---------------------------------------------------------------- расстановка

## Привязка к рельефу до построения сетки: ковёр поросли красит грунт.
## Мох не должен сливаться с грунтом — тогда сдвигаем оттенок.
func attach(terr: ProtoTerrain) -> void:
	terrain = terr
	if life == 0:
		return
	var g := terrain.ground
	if absf(wrapf(hue - g.h, -0.5, 0.5)) < 0.1 and g.s > 0.15:
		hue = fposmod(hue + 0.16, 1.0)
		hue2 = fposmod(hue2 + 0.16, 1.0)
	terrain.bio = carpet

## Плодородие места: шум пятнами плюс близость воды.
func fertility(x: float, z: float) -> float:
	var wet := clampf(1.0 - _water_dist(x, z) / 9.0, 0.0, 1.0)
	return noise.get_noise_2d(x, z) * 1.7 + wet * (0.7 if forms.has("frond") or forms.has("coral") else 0.35)

## Цвет ковра поросли на грунте; a — насколько закрашен (вызывается из потоков рельефа).
func carpet(x: float, z: float) -> Color:
	var f := fertility(x, z) - thr + 0.12
	var h := hue
	var sv := sat
	if thermo and Vector2(x, z).distance_to(ProtoTerrain.VOLC_C) < 26.0:
		h = 0.08; sv = 0.8
	var c := Color.from_hsv(h, sv * 0.9, val * 0.85)
	# Пятнами: мелкий шум рвёт ковёр на куртины.
	var spots := 0.55 + 0.6 * noise.get_noise_2d(x * 4.1 + 300.0, z * 4.1)
	c.a = clampf(f * 2.0 * spots, 0.0, 0.65 if life >= 2 else 0.45)
	return c

## Строит флору в root. keep_clear(p) — false, где ставить нельзя (кадр, робот).
## lite — Steam Deck: реже. Возвращает число сеток.
func build(root: Node3D, terr: ProtoTerrain, keep_clear: Callable, lite := false) -> int:
	terrain = terr
	if life == 0:
		return 0
	var step := 1.35 * (1.3 if lite else 1.0)
	var x := 3.0
	while x < terrain.sx - 3.0:
		var z := 3.0
		while z < terrain.sz - 3.0:
			_try_spot(x + rng.randf_range(-0.6, 0.6) * step, z + rng.randf_range(-0.6, 0.6) * step, keep_clear)
			z += step
		x += step
	if life >= 2 or fungal:
		_cave(keep_clear, lite)
	mat = material(glow, wind)
	node = Node3D.new()
	node.name = "flora"
	root.add_child(node)
	var made := 0
	for k in _geo:
		var g: Geo = _geo[k]
		var m := g.mesh()
		if m == null:
			continue
		var mi := MeshInstance3D.new()
		mi.name = "flora_%s" % k
		mi.mesh = m
		mi.material_override = mat
		if k.begins_with("low"):
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.visibility_range_end = 40.0 if lite else 60.0
			mi.visibility_range_end_margin = 6.0
		node.add_child(mi)
		meshes[k] = mi
		made += 1
	return made

## Копия для куска шара вдали от участка (ProtoPlanetFill): своя случайность и
## свои сетки — строится в потоке, не трогая исходную. Шум и облик общие.
func fork(seed_value: int) -> ProtoFlora:
	var f := ProtoFlora.new()
	for k in ["life", "forms", "tuft", "hue", "hue2", "hue3", "sat", "val", "glow", "wind", "grow",
			"floating", "thermo", "fungal", "terrain", "style", "noise", "thr"]:
		f.set(k, get(k))
	f.rng.seed = seed_value
	f.far = true
	return f

var far := false               # кусок шара: крупные формы — одной сеткой на кусок

## Плодородие вдали от участка: тот же шум, что у ковра поросли на шаре
## (ProtoTerrain.far_key), плюс берег моря (wet 0..1).
func far_fertility(key: Vector2, wet: float) -> float:
	return fertility(key.x, key.y) + wet * (0.7 if forms.has("frond") or forms.has("coral") else 0.35)

## Растение в точке p с нормалью nrm (система куска, Y — вверх). Как _try_spot,
## но место уже выбрано и проверено вызывающим. Сетки — в _geo этой копии.
func far_spot(p: Vector3, nrm: Vector3, fert: float, wet: float) -> void:
	if fert < thr or nrm.y < 0.5:
		return
	var s := rng.randf_range(0.7, 1.25) * (0.75 + 0.25 * clampf(fert - thr, 0.0, 1.0) * 2.0)
	var big_p := 0.04 + 0.04 * life + 0.06 * clampf(fert - thr, 0.0, 1.0)
	plants += 1
	if not forms.is_empty() and nrm.y > 0.78 and rng.randf() < big_p:
		var w := {}
		for k in forms:
			var a := 1.0
			if k in ["frond", "coral"]: a = 0.4 + wet * 3.0
			elif k == "tubes" and thermo: a = 1.5
			w[k] = a
		_form(_pick(w, rng), p, nrm, s * 1.2, _g("big", p))
		return
	var low := _g("low", p)
	var r := rng.randf()
	if fungal and r < 0.35:
		_moss(low, p, nrm, s * 0.8, false)
	elif tuft and r < 0.6:
		_tuft(low, p, nrm, s)
	elif r < 0.8:
		_curls(low, p, s)

func verts() -> int:
	var n := 0
	for k in _geo:
		n += (_geo[k] as Geo).v.size()
	return n

func _g(kind: String, p: Vector3) -> Geo:
	var k := _key(kind, p)
	if not _geo.has(k):
		_geo[k] = Geo.new()
	return _geo[k]

func _key(kind: String, p: Vector3) -> String:
	if kind == "cave" or (far and kind == "big"):
		return "cave"
	return "%s_%d_%d" % [kind, int(floor(p.x / CHUNK)), int(floor(p.z / CHUNK))]

# ---------------------------------------------------------------- срез

## Начало растения в куске kind: где в нём сейчас конец вершин и индексов.
func _begin(kind: String, p: Vector3) -> Array:
	var g := _g(kind, p)
	return [_key(kind, p), g.v.size(), g.idx.size()]

## Конец растения: запомнить его диапазон, высоту и размах (для среза).
func _end(mk: Array, p: Vector3, form: String) -> void:
	var g: Geo = _geo[mk[0]]
	var v1 := g.v.size()
	if v1 == mk[1]:
		return
	var h := 0.0
	var r := 0.0
	for j in range(mk[1], v1):
		var d: Vector3 = g.v[j] - p
		h = maxf(h, d.y)
		r = maxf(r, Vector2(d.x, d.z).length())
	items.append({"key": mk[0], "v0": mk[1], "v1": v1, "i0": mk[2], "i1": g.idx.size(), "p": p,
		"h": h, "r": r, "form": form, "col": g.c[(int(mk[1]) + v1) >> 1], "cut": false})

## Срезать растение i: его вершины стягиваются под основание (кусок пересоберёт
## flush). Возвращает отдельную сетку растения — от основания, для анимации.
func cut(i: int, detach := true) -> ArrayMesh:
	var it: Dictionary = items[i]
	if it.cut:
		return null
	it.cut = true
	var g: Geo = _geo[it.key]
	var p: Vector3 = it.p
	var out: ArrayMesh = null
	if detach:
		var pg := Geo.new()
		for j in range(it.v0, it.v1):
			pg.v.append(g.v[j] - p)
			pg.n.append(g.n[j])
			pg.c.append(g.c[j])
			pg.uv.append(g.uv[j])
		for j in range(it.i0, it.i1):
			pg.idx.append(g.idx[j] - it.v0)
		out = pg.mesh()
	var sink := p - Vector3(0, 0.08, 0)
	for j in range(it.v0, it.v1):
		g.v[j] = sink
		g.uv[j] = Vector2.ZERO     # без качания: иначе стянутые точки разойдутся щепками
	_dirty[it.key] = true
	return out

## Пересобрать куски, где что-то срезали.
func flush() -> void:
	for k in _dirty:
		var mi: MeshInstance3D = meshes.get(k)
		if mi != null and is_instance_valid(mi):
			mi.mesh = (_geo[k] as Geo).mesh()
	_dirty.clear()

## Номера срезанных растений (сохранение).
func cut_ids() -> Array:
	var r := []
	for i in items.size():
		if items[i].cut:
			r.append(i)
	return r

## Насколько близко вода (река или озеро), м.
func _water_dist(x: float, z: float) -> float:
	var dr := absf(z - terrain.river_z(x)) - 2.0 if x > terrain.lake_c.x - 2.0 else INF
	var dl := Vector2(x, z).distance_to(terrain.lake_c) - terrain.lake_r
	return maxf(0.0, minf(dr, dl))

## Не на площадке завода, не у входа в пещеру и не в лаве вулкана.
func _allowed(x: float, z: float) -> bool:
	var pad := ProtoTerrain.PAD_C
	if absf(x - pad.x) < 12.0 and z > pad.y - 9.0 and z < pad.y + 19.0:
		return false
	var q := Vector2(x, z)
	if q.distance_to(Vector2(terrain.cave_entry.x, terrain.cave_entry.z)) < 5.0:
		return false
	if style.volcano and q.distance_to(ProtoTerrain.VOLC_C) < 9.0:
		return false
	return true

func _try_spot(x: float, z: float, keep_clear: Callable) -> void:
	if not _allowed(x, z):
		return
	var fert := fertility(x, z)
	if fert < thr:
		return
	var wd := _water_dist(x, z)
	var wet := clampf(1.0 - wd / 9.0, 0.0, 1.0)
	var p := Vector3(x, terrain.floor_at(Vector3(x, terrain.sy, z)), z)
	# Под водой не растём (вода непрозрачна, и так не видно).
	var lvl := maxf(terrain.lake_level, terrain.river_level_at(x)) if wd < 1.0 else -INF
	if p.y < lvl + 0.1 or p.y < 1.5:
		return
	if not keep_clear.call(p):
		return
	var nrm := _normal_at(p + Vector3(0, 0.05, 0))
	if nrm.y < 0.5:
		return
	var s := rng.randf_range(0.7, 1.25) * (0.75 + 0.25 * clampf(fert - thr, 0.0, 1.0) * 2.0)
	var big_p := 0.04 + 0.04 * life + 0.06 * clampf(fert - thr, 0.0, 1.0)
	plants += 1
	if not forms.is_empty() and nrm.y > 0.78 and rng.randf() < big_p:
		# Водные формы жмутся к воде, остальные — подальше.
		var w := {}
		for k in forms:
			var a := 1.0
			if k in ["frond", "coral"]: a = 0.4 + wet * 3.0
			elif k == "tubes" and thermo: a = 1.5
			w[k] = a
		var mk := _begin("big", p)
		var form := _pick(w, rng)
		_form(form, p, nrm, s * 1.2, _g("big", p))
		_end(mk, p, form)
		if fert > best_fert and wd > 1.5 and p.y > terrain.surface_h(x, z) - 0.5:
			best_fert = fert
			best = p
		return
	if forms.is_empty() and fert > best_fert and wd > 1.5 and p.y > terrain.surface_h(x, z) - 0.5:
		best_fert = fert
		best = p
	# Низкая поросль: мох уже ковром на грунте, сверху — щетина, завитки,
	# у грибной биосферы — дождевики.
	var low := _g("low", p)
	var mk := _begin("low", p)
	var r := rng.randf()
	if fungal and r < 0.35:
		_moss(low, p, nrm, s * 0.8, false)
		_end(mk, p, "moss")
	elif tuft and r < 0.6:
		_tuft(low, p, nrm, s)
		_end(mk, p, "tuft")
	elif r < 0.8:
		_curls(low, p, s)
		_end(mk, p, "curls")

func _form(k: String, p: Vector3, nrm: Vector3, s: float, g: Geo) -> void:
	match k:
		"frond": _frond(g, p, s)
		"lantern": _lantern(g, p, s)
		"coral": _coral(g, p, s)
		"bladder": _bladder(g, p, s)
		"tubes": _tubes(g, p, s)
	# У корней — поросль.
	_curls(_g("low", p), p, s * 0.8)

## Пещера: светящийся мох по полу, трутовики на стенах, мелкие формы планеты.
func _cave(keep_clear: Callable, lite: bool) -> void:
	var cc := terrain.cave_c
	var g := _g("cave", cc)
	var want := (18 + 14 * life) * (0.6 if lite else 1.0)
	var made := 0
	for i in 600:
		if made >= want:
			break
		var q := cc + Vector3(rng.randf_range(-1, 1) * terrain.cave_r * 1.3, rng.randf_range(-1.0, 2.0), rng.randf_range(-1, 1) * terrain.cave_r * 1.3)
		if terrain.solid(q.x, q.y, q.z):
			continue
		if rng.randf() < 0.35:
			# На стену: идём вбок до породы.
			var dir := Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized()
			var hit := Vector3.INF
			for j in 60:
				var a := q + dir * (j * 0.15)
				if terrain.solid(a.x, a.y, a.z):
					hit = a - dir * 0.1
					break
			if hit == Vector3.INF or not keep_clear.call(hit):
				continue
			var wn := _normal_at(hit)
			if absf(wn.y) > 0.55:
				continue
			var mk := _begin("cave", hit)
			_shelf(g, hit, wn, rng.randf_range(0.6, 1.2))
			_end(mk, hit, "shelf")
			made += 1
			continue
		var p := Vector3(q.x, terrain.floor_at(q), q.z)
		if terrain.solid(p.x, p.y + 1.0, p.z) or not keep_clear.call(p):
			continue
		var pc := terrain.pool_c()
		if Vector2(p.x, p.z).distance_to(Vector2(pc.x, pc.z)) < terrain.pool_r + 0.4:
			continue
		var nrm := _normal_at(p + Vector3(0, 0.05, 0))
		if nrm.y < 0.5:
			continue
		if not forms.is_empty() and rng.randf() < 0.25:
			var k: String = forms[rng.randi() % forms.size()]
			if k != "bladder" or rng.randf() < 0.5:
				var mk := _begin("cave", p)
				_form(k, p, nrm, rng.randf_range(0.4, 0.6), g)
				_end(mk, p, k)
				made += 1
				continue
		var mk := _begin("cave", p)
		_moss(g, p, nrm, rng.randf_range(0.6, 1.0), true)
		_end(mk, p, "moss")
		made += 1

## Нормаль поверхности породы по полю плотности (наружу, в воздух).
func _normal_at(p: Vector3) -> Vector3:
	var e := 0.3
	var gr := Vector3(terrain.density(p.x + e, p.y, p.z) - terrain.density(p.x - e, p.y, p.z),
		terrain.density(p.x, p.y + e, p.z) - terrain.density(p.x, p.y - e, p.z),
		terrain.density(p.x, p.y, p.z + e) - terrain.density(p.x, p.y, p.z - e))
	return (-gr).normalized()

# ---------------------------------------------------------------- формы

## Цвет с разбросом; a — свечение (0 — нет).
func _c(h: float, s: float, v: float, lit := 0.0) -> Color:
	var c := Color.from_hsv(fposmod(h + rng.randf_range(-0.03, 0.03), 1.0), clampf(s * rng.randf_range(0.85, 1.1), 0.0, 1.0),
		clampf(v * rng.randf_range(0.8, 1.15), 0.0, 1.0))
	c.a = lit
	return c

static func _up_basis(nrm: Vector3, yaw: float) -> Basis:
	var x := nrm.cross(Vector3.FORWARD if absf(nrm.z) < 0.9 else Vector3.RIGHT).normalized()
	return Basis(x, nrm, x.cross(nrm)).rotated(nrm, yaw)

## Подушки мха (или мицелия, или маты термофилов у вулкана).
func _moss(g: Geo, p: Vector3, nrm: Vector3, s: float, cave: bool) -> void:
	var b := _up_basis(nrm, rng.randf() * TAU)
	var h := hue
	var sv := sat
	var vv := val
	if fungal and rng.randf() < 0.5:
		sv *= 0.25; vv = 0.7           # белёсый мицелий
	if thermo and Vector2(p.x, p.z).distance_to(ProtoTerrain.VOLC_C) < 26.0:
		h = rng.randf_range(0.04, 0.13); sv = 0.8; vv = 0.6   # оранжевые термофилы у вулкана
	var lit := 0.0
	if cave: lit = 0.7
	elif glow > 1.0 and rng.randf() < 0.3: lit = 0.35
	# Подушка: крупный холмик и мелкие вокруг, мягкие и округлые.
	var c0 := _c(h, sv, vv, 0.0)
	for i in rng.randi_range(4, 8):
		var off := Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)) * (0.1 if i == 0 else 0.4) * s
		var r := (rng.randf_range(0.22, 0.34) if i == 0 else rng.randf_range(0.08, 0.2)) * s
		var c := c0.lerp(_c(h, sv, vv), 0.5)
		var top := c.lightened(0.22)
		top.a = lit
		g.blob(p + b * off - nrm * r * 0.25, Vector3(r, r * rng.randf_range(0.55, 0.8), r), b, top, c.darkened(0.45), 0.0, true, 3, 8)
	plants += 1

## Щетина: пучок изогнутых лезвий.
func _tuft(g: Geo, p: Vector3, nrm: Vector3, s: float) -> void:
	var h := rng.randf_range(0.35, 0.9) * s * grow
	var ph := rng.randf()
	var tip_lit := 0.6 if glow > 1.0 else 0.0
	for i in rng.randi_range(5, 10):
		var ang := rng.randf() * TAU
		var out := Vector3(cos(ang), 0, sin(ang))
		var lean := rng.randf_range(0.15, 0.6)
		var o := p + out * rng.randf_range(0.0, 0.15) * s
		var hh := h * rng.randf_range(0.6, 1.2)
		var w := hh * rng.randf_range(0.05, 0.08)
		var root := _c(hue2, sat, val * 0.6)
		var tip := _c(hue2 + 0.04, sat * 0.8, val * 1.35, tip_lit)
		var sp := []
		var sd := []
		var nn := []
		var cc := []
		var fl := []
		for j in 4:
			var t := j / 3.0
			sp.append(o + nrm * hh * t + out * hh * lean * t * t)
			sd.append(out.cross(Vector3.UP).normalized() * w * (1.0 - t * 0.9))
			nn.append((out + Vector3.UP * 0.8).normalized())
			cc.append(root.lerp(tip, t))
			fl.append(t)
		g.strip(sp, sd, nn, cc, fl, ph)

## Завитки: короткие стебельки, скрученные улиткой на макушке.
func _curls(g: Geo, p: Vector3, s: float) -> void:
	var ph := rng.randf()
	var base := _c(hue2, sat, val * 0.65)
	var tip := _c(hue2 + 0.05, sat * 1.1, val * 1.25, 0.5 if glow > 1.0 else 0.0)
	for i in rng.randi_range(3, 6):
		var h := rng.randf_range(0.2, 0.5) * s * grow
		var ang := rng.randf() * TAU
		var out := Vector3(cos(ang), 0, sin(ang))
		var o := p + out * rng.randf_range(0.0, 0.25) * s + Vector3.DOWN * 0.03
		var pts := []
		var rads := []
		var cols := []
		var fl := []
		var r := h * 0.07
		# Ножка вверх, затем улитка: вперёд, вниз и назад, радиус сжимается.
		var stem := h * 0.6
		var rc := h * 0.22
		var ctr := o + Vector3.UP * stem + out * rc
		for j in 9:
			var t := j / 8.0
			var q := o + Vector3.UP * stem * (j / 3.0)
			if j > 3:
				var a := (j - 3) / 5.0 * PI * 1.6
				q = ctr + (-out * cos(a) + Vector3.UP * sin(a)) * rc * (1.0 - 0.45 * (j - 3) / 5.0)
			pts.append(q)
			rads.append(r * (1.0 - t * 0.55))
			cols.append(base.lerp(tip, t))
			fl.append(t)
		g.tube(pts, rads, cols, fl, ph, 4)
	plants += 1

## Ваи: розетка широких листьев дугой.
func _frond(g: Geo, p: Vector3, s: float) -> void:
	var L := rng.randf_range(1.2, 2.4) * s * grow
	var W := L * rng.randf_range(0.12, 0.2)
	var n := rng.randi_range(5, 8)
	var ph := rng.randf()
	for i in n:
		var ang := TAU * i / n + rng.randf_range(-0.3, 0.3)
		var out := Vector3(cos(ang), 0, sin(ang))
		var side := out.cross(Vector3.UP).normalized()
		var up := rng.randf_range(0.7, 1.3)
		var base := _c(hue2, sat, val * 0.7)
		var tip := _c(hue2 + 0.05, sat, val * 1.3, 0.25 if glow > 1.0 else 0.0)
		var sp := []
		var sd := []
		var nn := []
		var cc := []
		var fl := []
		for j in 6:
			var t := j / 5.0
			sp.append(p + out * L * t * 0.85 + Vector3.UP * L * up * (t - t * t * 0.95))
			var wt := W * sin(PI * minf(t * 1.05, 1.0)) + 0.01
			sd.append(side * wt)
			nn.append((Vector3.UP * (1.0 - t) - out * 0.4 + out * t * 0.8).normalized())
			var col := base.lerp(tip, t)
			if j == 3: col = col.lerp(_c(hue3, sat, val * 1.2), 0.35)     # поперечная полоса
			cc.append(col)
			fl.append(t * 1.3)
		g.strip(sp, sd, nn, cc, fl, ph + i * 0.13)
	var bud := _c(hue3, sat * 1.1, val * 1.4, 0.4)
	g.blob(p + Vector3.UP * 0.1 * L, Vector3.ONE * 0.12 * L, Basis(), bud, bud.darkened(0.3), 0.1, false)
	plants += 1

## Фонарики: стебли со светящейся луковицей на макушке.
func _lantern(g: Geo, p: Vector3, s: float) -> void:
	for k in rng.randi_range(1, 3):
		var h := minf(rng.randf_range(1.4, 3.2) * s * grow, 4.5)
		var o := p + Vector3(rng.randf_range(-0.4, 0.4), -0.05, rng.randf_range(-0.4, 0.4)) * s
		var lean := Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)) * 0.35
		var ph := rng.randf()
		var stem := _c(hue2, sat * 0.8, val * 0.55)
		var pts := []
		var rads := []
		var cols := []
		var fl := []
		for j in 6:
			var t := j / 5.0
			pts.append(o + Vector3.UP * h * t + lean * h * t * t)
			rads.append(lerpf(0.08, 0.035, t) * s)
			cols.append(stem.lightened(t * 0.25))
			fl.append(t)
		g.tube(pts, rads, cols, fl, ph, 5)
		var r := rng.randf_range(0.16, 0.3) * s
		var bulb := _c(hue3, sat * 1.15, 0.9, 1.0)
		var top: Vector3 = pts[5]
		# Луковица свисает с загнутой макушки.
		g.blob(top + Vector3(0, -r * 0.6, 0) + lean * r, Vector3(r, r * 1.35, r), Basis(), bulb, bulb.darkened(0.2), 1.0, false, 4, 8)
	_tuft(g, p, Vector3.UP, s * 0.6)

## Коралл: ветвистые трубки со светящимися кончиками.
func _coral(g: Geo, p: Vector3, s: float) -> void:
	var ph := rng.randf()
	var hgt := 2.2 * s * grow
	for k in rng.randi_range(2, 3):
		var d := (Vector3.UP + Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)) * 0.35).normalized()
		_branch(g, p + Vector3(rng.randf_range(-0.2, 0.2), -0.05, rng.randf_range(-0.2, 0.2)), d,
			rng.randf_range(0.5, 0.8) * s * grow, 0.08 * s, 2 if rng.randf() < 0.6 else 3, p.y, hgt, ph)
	plants += 1

func _branch(g: Geo, a: Vector3, d: Vector3, len: float, r: float, depth: int, y0: float, hgt: float, ph: float) -> void:
	var b := a + d * len
	var m := a.lerp(b, 0.5) + Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)) * len * 0.1
	var ca := _c(hue, sat, val * (0.7 + 0.15 * (3 - depth)))
	var cb := ca.lerp(_c(hue3, sat, val * 1.3), 0.5 if depth > 0 else 1.0)
	cb.a = 0.8 if depth == 0 else 0.0
	var fl := func(q: Vector3) -> float: return clampf((q.y - y0) / hgt, 0.0, 1.2)
	g.tube([a, m, b], [r, r * 0.85, r * 0.7], [ca, ca.lerp(cb, 0.5), cb], [fl.call(a), fl.call(m), fl.call(b)], ph, 5)
	if depth == 0:
		g.blob(b, Vector3.ONE * r * 1.3, Basis(), cb, cb, fl.call(b), false, 2, 5)
		return
	for i in rng.randi_range(2, 3):
		var nd := (d + Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.2, 0.4), rng.randf_range(-1, 1)) * 0.65 + Vector3.UP * 0.25).normalized()
		_branch(g, b, nd, len * rng.randf_range(0.6, 0.8), r * 0.7, depth - 1, y0, hgt, ph)

## Пузыри: мешки у земли; при плотном воздухе или слабой тяжести — парят на привязи.
func _bladder(g: Geo, p: Vector3, s: float) -> void:
	var ph := rng.randf()
	for i in rng.randi_range(2, 4):
		var r := rng.randf_range(0.25, 0.6) * s
		var o := p + Vector3(rng.randf_range(-0.6, 0.6), 0, rng.randf_range(-0.6, 0.6)) * s
		var c := _c(hue3, sat * 0.9, val * 1.3, 0.3)
		g.blob(o + Vector3.UP * r * 0.8, Vector3(r, r * rng.randf_range(0.8, 1.3), r), Basis(), c, c.darkened(0.4), 0.15, false)
	if floating:
		for i in rng.randi_range(1, 2):
			var h := rng.randf_range(2.5, 5.5) * grow
			var r := rng.randf_range(0.35, 0.75) * s
			var o := p + Vector3(rng.randf_range(-0.5, 0.5), 0, rng.randf_range(-0.5, 0.5))
			var line := _c(hue2, sat * 0.5, val * 0.8)
			var pts := []
			var rads := []
			var cols := []
			var fl := []
			for j in 5:
				var t := j / 4.0
				pts.append(o + Vector3.UP * h * t)
				rads.append(0.025)
				cols.append(line)
				fl.append(t * 2.5)
			g.tube(pts, rads, cols, fl, ph + i * 0.3, 3)
			var c := _c(hue3, sat, val * 1.4, 0.6)
			g.blob(o + Vector3.UP * (h + r * 0.9), Vector3(r, r * 1.2, r), Basis(), c.lightened(0.1), c.darkened(0.25), 2.5, false)
	plants += 1

## Трубчатые черви: пучок трубок с плюмажем на макушке.
func _tubes(g: Geo, p: Vector3, s: float) -> void:
	var ph := rng.randf()
	var shell := _c(hue2, sat * 0.55, val * 1.1)
	for i in rng.randi_range(4, 9):
		var h := rng.randf_range(0.3, 1.1) * s * grow
		var r := rng.randf_range(0.03, 0.06) * s
		var o := p + Vector3(rng.randf_range(-0.5, 0.5), -0.05, rng.randf_range(-0.5, 0.5)) * s
		var bend := Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)) * 0.15 * h
		var top := o + Vector3.UP * h + bend
		# Кольчатая трубка: светлые и тёмные кольца.
		var pts := []
		var rads := []
		var cols := []
		var fl := []
		for j in 5:
			var t := j / 4.0
			pts.append(o + Vector3.UP * h * t + bend * t * t)
			rads.append(r * (1.25 - 0.25 * t))
			cols.append(shell.darkened(0.35 * (1.0 - t)) if j % 2 == 0 else shell.lightened(0.15))
			fl.append(t * 0.6)
		g.tube(pts, rads, cols, fl, ph, 5)
		# Плюмаж — веер коротких лепестков.
		var plume := _c(hue3, sat * 1.2, 0.8, 0.7)
		for k in 5:
			var ang := TAU * k / 5.0 + rng.randf()
			var out := Vector3(cos(ang), 0, sin(ang))
			var L := r * rng.randf_range(2.5, 4.0)
			g.strip([top, top + (Vector3.UP + out * 0.8) * L * 0.5, top + (Vector3.UP * 0.6 + out) * L],
				[out.cross(Vector3.UP) * r * 0.5, out.cross(Vector3.UP) * r * 0.6, out.cross(Vector3.UP) * r * 0.1],
				[Vector3.UP, Vector3.UP, (Vector3.UP + out).normalized()], [plume.darkened(0.2), plume, plume.lightened(0.2)],
				[0.6, 0.9, 1.2], ph)
	plants += 1

## Трутовики: полукруглые полки ярусами на стене.
func _shelf(g: Geo, p: Vector3, wn: Vector3, s: float) -> void:
	var side := wn.cross(Vector3.UP).normalized()
	var b := Basis(side, Vector3.UP, wn)
	for i in rng.randi_range(2, 4):
		var r := rng.randf_range(0.18, 0.4) * s
		var o := p + Vector3.UP * (i * 0.3 * s + rng.randf_range(-0.05, 0.05)) + side * rng.randf_range(-0.25, 0.25) * s
		var c := _c(hue3 if rng.randf() < 0.5 else hue, sat * 0.8, val * 1.3, 0.6)
		g.blob(o + wn * r * 0.35, Vector3(r, r * 0.22, r * 0.8), b, c.lightened(0.15), c.darkened(0.3), 0.0, false)
	plants += 1

# ---------------------------------------------------------------- сетка и материал

const SHADER := """
shader_type spatial;
render_mode cull_disabled;
uniform float glow = 1.0;
uniform float wind = 0.2;
// UV.x — гибкость (0 у корня), UV.y — фаза; альфа цвета — свечение.
void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float ph = TIME * (0.9 + wind * 0.8) + wp.x * 0.23 + wp.z * 0.19 + UV.y * 6.2831;
	float b = UV.x * UV.x * (0.05 + wind * 0.1);
	VERTEX.x += sin(ph) * b;
	VERTEX.z += cos(ph * 0.83) * b * 0.7;
}
void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 0.8;
	EMISSION = COLOR.rgb * COLOR.a * glow;
}
"""

static var _shader: Shader

static func material(glow_k: float, wind_k: float) -> ShaderMaterial:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER
	var m := ShaderMaterial.new()
	m.shader = _shader
	m.set_shader_parameter("glow", 0.5 + glow_k * 1.3)
	m.set_shader_parameter("wind", wind_k)
	return m

## Сетка одного куска: трубки, ленты и эллипсоиды в общие массивы.
class Geo:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()
	var uv := PackedVector2Array()
	var idx := PackedInt32Array()

	func mesh() -> ArrayMesh:
		if v.is_empty():
			return null
		var a := []
		a.resize(Mesh.ARRAY_MAX)
		a[Mesh.ARRAY_VERTEX] = v
		a[Mesh.ARRAY_NORMAL] = n
		a[Mesh.ARRAY_COLOR] = c
		a[Mesh.ARRAY_TEX_UV] = uv
		a[Mesh.ARRAY_INDEX] = idx
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
		return m

	## Трубка по ломаной; radii, cols, flex — по точкам.
	func tube(pts: Array, radii: Array, cols: Array, flex: Array, ph: float, seg := 5) -> void:
		var base := v.size()
		var k := pts.size()
		for i in k:
			var t: Vector3 = (pts[mini(i + 1, k - 1)] - pts[maxi(i - 1, 0)]).normalized()
			var a := t.cross(Vector3.RIGHT if absf(t.x) < 0.9 else Vector3.FORWARD).normalized()
			var b := t.cross(a)
			for s in seg:
				var ang := TAU * s / seg
				var d := a * cos(ang) + b * sin(ang)
				v.append(pts[i] + d * float(radii[i]))
				n.append(d)
				c.append(cols[i])
				uv.append(Vector2(flex[i], ph))
		for i in k - 1:
			for s in seg:
				var s2 := (s + 1) % seg
				var p0 := base + i * seg + s
				var p1 := base + i * seg + s2
				var p2 := p0 + seg
				var p3 := p1 + seg
				idx.append_array([p0, p2, p1, p1, p2, p3])

	## Лента (лист, лезвие): по хребту spine, полуширина side, нормали nrm.
	func strip(spine: Array, side: Array, nrm: Array, cols: Array, flex: Array, ph: float) -> void:
		var base := v.size()
		for i in spine.size():
			v.append(spine[i] - side[i])
			v.append(spine[i] + side[i])
			for j in 2:
				n.append(nrm[i])
				c.append(cols[i])
				uv.append(Vector2(flex[i], ph))
		for i in spine.size() - 1:
			var a := base + i * 2
			# Лицевая сторона — туда, куда смотрит нормаль (иначе свет с изнанки).
			var geo: Vector3 = (side[i] as Vector3).cross(spine[i + 1] - spine[i])
			if geo.dot(nrm[i]) < 0.0:
				idx.append_array([a, a + 1, a + 2, a + 1, a + 3, a + 2])
			else:
				idx.append_array([a, a + 2, a + 1, a + 1, a + 2, a + 3])

	## Эллипсоид (или верхняя полусфера): полуоси r в базисе b, цвет сверху и снизу.
	func blob(ctr: Vector3, r: Vector3, b: Basis, top: Color, bottom: Color, flex: float, hemi := false, lat := 3, lon := 6) -> void:
		var base := v.size()
		var rings := lat + 1
		var th_max := PI * 0.5 if hemi else PI
		for i in rings:
			var th := th_max * i / lat
			for j in lon:
				var ph := TAU * j / lon
				var u := Vector3(sin(th) * cos(ph), cos(th), sin(th) * sin(ph))
				v.append(ctr + b * Vector3(u.x * r.x, u.y * r.y, u.z * r.z))
				n.append((b * Vector3(u.x / r.x, u.y / r.y, u.z / r.z)).normalized())
				c.append(top.lerp(bottom, th / PI) if not hemi else top.lerp(bottom, th / th_max))
				uv.append(Vector2(flex, 0.0))
		for i in lat:
			for j in lon:
				var j2 := (j + 1) % lon
				var p0 := base + i * lon + j
				var p1 := base + i * lon + j2
				var p2 := p0 + lon
				var p3 := p1 + lon
				idx.append_array([p0, p2, p1, p1, p2, p3])
