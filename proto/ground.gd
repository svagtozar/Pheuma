class_name ProtoGround
extends RefCounted
## Толща планеты: что лежит в точке. Не хранится, а вычисляется из сида и
## глубины под природной поверхностью — 0 байт на всю планету (кора вокселями
## по 1 м на 40 м вглубь — ~320 млн ячеек). Хранятся только правки рельефа
## (ProtoTerrain.edit) и состояние верха (ProtoSurfaceState).
##
## Как в жизни (по порядку событий):
## 1. Пласты отложились горизонтально: пачка разной толщины, изредка тонкие
##    «маркеры» (пепел, тёмный прослой), у одного пласта — горизонт конкреций
##    вдоль напластования.
## 2. Потом их смяло и наклонило: общий наклон и складки (у сейсмичных и
##    кристаллических — круче и чаще).
## 3. Разломы сдвинули пласты: по крутой плоскости одно крыло опущено на
##    несколько метров, в шве — дроблёная порода (брекчия).
## 4. Трещины заполнились другими минералами — жилы: системы почти
##    параллельных крутых трещин, жила то раздувается, то пережимается и
##    обрывается; рудная жила часто идёт по разлому. У вулканических — дайки:
##    толстые прямые стенки застывшей лавы через всю толщу.
## 5. Сверху порода выветрилась: коренная → дресва (разрушенная та же порода,
##    ещё видны пласты) → осыпь/подпочва → почва. На крутом почвы почти нет,
##    в ложбинах толще.
## 6. На холодных — вечная мерзлота под деятельным слоем и ледяные клинья
##    сеткой многоугольников, сужаются вглубь.
## Цвет толщи — для рельефа (ProtoTerrain._color_h), материал — что даёт бур.

const SOIL := 0                # виды слоёв (kind); у первых трёх — и номера слоёв
const SUBSOIL := 1
const ICE := 2
const ROCK := 3                # пласты (номера слоёв с ROCK по порядку пачки)
const VEIN := 4                # жила, конкреции
const FAULT := 5               # брекчия в шве разлома
const DIKE := 6                # дайка

## Слой: {"name", "sub" (Substance или null), "color", "kind"}.
var layers: Array = []
var soil_d := 0.6              # почва на ровном, м
var sub_d := 2.2               # подошва подпочвы на ровном, м
var weather_d := 3.0           # ещё столько — дресва (выветрелая коренная)
var band_h: PackedFloat32Array = []   # пачка пластов снизу вверх, толщины, м (повторяется)
var band_sum := 1.0
var dip := Vector2(0.08, -0.05)       # общий наклон (м по высоте на м вбок)
var fold_amp := 2.0            # складки: размах, м
var fold_len := 90.0           # и длина волны, м
var fold_dir := Vector2(1, 0)
var faults: Array = []         # {"n": Vector3, "d": float, "throw": float, "w": float}
var fault_layer := -1
var vein_sets: Array = []      # {"n", "space", "t", "layer", "on_fault": bool}
var dikes: Array = []          # {"n", "d", "t", "layer"}
var nodule := {}               # {"layer", "band", "at" (доля толщины пласта), "noise", "thr"}
var ice_on := false            # мерзлота
var perm_d := 14.0             # подошва мерзлоты, м
var wedge_d := 3.5             # глубина ледяных клиньев под деятельным слоем, м
var warp := FastNoiseLite.new()
var grain := FastNoiseLite.new()
var swell := FastNoiseLite.new()     # раздув и обрыв жил
var poly := FastNoiseLite.new()      # многоугольники мерзлоты

static func for_planet(planet: Planet, ground: Color, cliff: Color, lush := false) -> ProtoGround:
	var g := ProtoGround.new()
	var r := Rng.new(planet.seed_value).fork("strata")
	var sd := planet.seed_value
	g.warp.seed = sd
	g.warp.frequency = 0.02
	g.warp.fractal_octaves = 2
	g.grain.seed = sd + 7
	g.grain.frequency = 0.9
	g.swell.seed = sd + 21
	g.swell.frequency = 0.07
	g.swell.fractal_type = FastNoiseLite.FRACTAL_NONE
	g.poly.seed = sd + 31
	g.poly.noise_type = FastNoiseLite.TYPE_CELLULAR
	g.poly.cellular_return_type = FastNoiseLite.RETURN_DISTANCE2_SUB
	g.poly.frequency = 0.09
	g.poly.fractal_type = FastNoiseLite.FRACTAL_NONE
	var volcanic := planet.has_tag("volcanic")
	var deformed := planet.has_tag("seismic") or planet.has_tag("crystalline_crust")
	g.ice_on = planet.has_tag("frozen") or planet.ambient_temp < -20.0

	# 5. Выветривание: почва, подпочва, дресва.
	g.soil_d = r.range_f(0.35, 0.7) * (1.5 if lush else 1.0)
	g.sub_d = g.soil_d + r.range_f(1.0, 2.2)
	g.weather_d = r.range_f(2.0, 4.0)
	var soil_c := ground.darkened(0.3).lerp(Color(0.22, 0.16, 0.1), 0.5) if lush else ground.darkened(0.06)
	g.layers.append({"name": "почва" if lush else "реголит", "sub": null, "color": soil_c, "kind": SOIL})
	g.layers.append({"name": "подпочва", "sub": null, "color": ground.lerp(cliff, 0.4).lightened(0.12), "kind": SUBSOIL})
	g.layers.append({"name": "лёд", "sub": null, "color": Color(0.8, 0.88, 0.94), "kind": ICE})

	# 1. Пачка пластов из твёрдых материалов планеты.
	var solids: Array = ProtoSky.solid_mats(planet)
	var mats: Array = solids.slice(0, 3)
	if mats.is_empty():
		mats = [null]
	var count := r.range_i(6, 9)
	var last := -1
	for i in count:
		var k := r.range_i(0, mats.size() - 1)
		if k == last and mats.size() > 1:
			k = (k + 1) % mats.size()
		last = k
		var s = mats[k]
		var thin := r.randf() < 0.18
		var c: Color = cliff if s == null else cliff.lerp(s.color, 0.55)
		var name: String = s.name if s != null else "порода"
		if thin:
			# Маркер: тонкий прослой пепла (у вулканических) или тёмного ила.
			c = c.lightened(0.35) if volcanic else c.darkened(0.45)
			name = ("пепел " if volcanic else "прослой ") + name
		c = c * r.range_f(0.85, 1.12)
		c.a = 1.0
		g.layers.append({"name": name, "sub": s, "color": c, "kind": ROCK})
		g.band_h.append(r.range_f(0.3, 0.6) if thin else r.range_f(1.8, 6.5))
	g.band_sum = 0.0
	for b in g.band_h:
		g.band_sum += b

	# 2. Наклон и складки.
	g.dip = Vector2(r.range_f(-0.1, 0.1), r.range_f(-0.1, 0.1))
	var fa := r.range_f(0.0, TAU)
	g.fold_dir = Vector2(cos(fa), sin(fa))
	g.fold_amp = r.range_f(4.0, 9.0) if deformed else r.range_f(0.8, 2.5)
	g.fold_len = r.range_f(45.0, 80.0) if deformed else r.range_f(90.0, 160.0)

	# 3. Разломы: крутая плоскость через участок, одно крыло опущено.
	g.fault_layer = g.layers.size()
	g.layers.append({"name": "брекчия", "sub": mats[0], "color": cliff.darkened(0.35), "kind": FAULT})
	for i in r.range_i(1, 3 if deformed else 2):
		var a := r.range_f(0.0, TAU)
		var steep := r.range_f(0.12, 0.35)          # отклонение от вертикали
		var n := Vector3(cos(a), steep, sin(a)).normalized()
		var c0 := Vector3(r.range_f(10.0, 70.0), 0.0, r.range_f(10.0, 70.0))
		g.faults.append({"n": n, "d": n.dot(c0), "throw": r.range_f(1.5, 7.0) * (1.0 if r.randf() < 0.5 else -1.0),
			"w": r.range_f(0.25, 0.6)})

	# 4. Жилы — из других материалов (рудные, кварцевые).
	var other: Array = solids.slice(3) if solids.size() > 3 else solids.duplicate()
	if other.is_empty():
		other = [null]
	var sets := r.range_i(1, 2) + (1 if deformed else 0)
	for i in sets:
		var s = other[i % other.size()]
		var a := r.range_f(0.0, TAU)
		var n := Vector3(cos(a), r.range_f(0.05, 0.4), sin(a)).normalized()
		var vc: Color = Color(0.82, 0.82, 0.78) if s == null else cliff.lerp(s.color, 0.85).lightened(0.08)
		vc.a = 1.0
		g.vein_sets.append({"n": n, "space": r.range_f(7.0, 16.0), "t": r.range_f(0.12, 0.35),
			"layer": g.layers.size(), "wob": r.range_f(0.6, 2.0)})
		g.layers.append({"name": (s.name if s != null else "кварц") + " (жила)", "sub": s, "color": vc, "kind": VEIN})
	if not g.faults.is_empty():
		# Рудная жила по первому разлому.
		var s = other[other.size() - 1]
		var vc: Color = Color(0.7, 0.62, 0.4) if s == null else cliff.lerp(s.color, 0.9).lightened(0.12)
		vc.a = 1.0
		g.faults[0]["vein"] = g.layers.size()
		g.layers.append({"name": (s.name if s != null else "руда") + " (жила в разломе)", "sub": s, "color": vc, "kind": VEIN})
	if volcanic:
		var dark = solids[0] if not solids.is_empty() else null
		for m in solids:
			if m.color.v < (dark.color.v if dark != null else 1.0):
				dark = m
		var dc: Color = Color(0.16, 0.15, 0.15) if dark == null else dark.color.darkened(0.55).lerp(Color(0.14, 0.13, 0.13), 0.5)
		dc.a = 1.0
		var dl := g.layers.size()
		g.layers.append({"name": (dark.name if dark != null else "базальт") + " (дайка)", "sub": dark, "color": dc, "kind": DIKE})
		for i in r.range_i(1, 2):
			var a := r.range_f(0.0, TAU)
			var n := Vector3(cos(a), r.range_f(0.0, 0.08), sin(a)).normalized()
			var c0 := Vector3(r.range_f(15.0, 65.0), 0.0, r.range_f(15.0, 65.0))
			g.dikes.append({"n": n, "d": n.dot(c0), "t": r.range_f(1.2, 3.5), "layer": dl})

	# 1б. Конкреции: вдоль одного горизонта внутри толстого пласта.
	var host := 0
	for i in g.band_h.size():
		if g.band_h[i] > g.band_h[host]:
			host = i
	var ns = other[0]
	var cn := FastNoiseLite.new()
	cn.seed = sd + 303
	cn.noise_type = FastNoiseLite.TYPE_CELLULAR
	cn.cellular_return_type = FastNoiseLite.RETURN_DISTANCE
	cn.frequency = 0.45
	cn.fractal_type = FastNoiseLite.FRACTAL_NONE
	var nc: Color = Color(0.45, 0.42, 0.4) if ns == null else cliff.lerp(ns.color, 0.8).darkened(0.1)
	nc.a = 1.0
	g.nodule = {"layer": g.layers.size(), "band": host, "at": r.range_f(0.3, 0.7), "noise": cn, "thr": -0.82}
	g.layers.append({"name": (ns.name if ns != null else "кремень") + " (конкреции)", "sub": ns, "color": nc, "kind": VEIN})
	return g

# ---------------------------------------------------------------- геометрия

## Высота в «системе пластов» (где пласт лежал до смятия): наклон, складки,
## лёгкий изгиб и сдвиг по разломам.
func _band_y(p: Vector3) -> float:
	var s := Vector2(p.x, p.z).dot(fold_dir)
	var y := p.y + dip.x * p.x + dip.y * p.z + fold_amp * sin(s / fold_len * TAU) + warp.get_noise_3dv(p) * 1.2
	for f: Dictionary in faults:
		if (f.n as Vector3).dot(p) > f.d:
			y += f.throw
	return y

## Пласт (номер в пачке) и доля толщины внутри него.
func _band(y: float) -> Vector2:
	var t := fposmod(y, band_sum)
	for i in band_h.size():
		if t < band_h[i]:
			return Vector2(i, t / band_h[i])
		t -= band_h[i]
	return Vector2(band_h.size() - 1, 1.0)

## Толщина почвы с учётом склона: up — «насколько ровно» (нормаль.y, 1 — ровно).
func _soil(up: float) -> float:
	return soil_d * lerpf(0.15, 1.35, smoothstep(0.55, 0.97, up))

## Коренное тело, секущее пласты (дайка, разлом, жила), или −1.
func _cross(p: Vector3) -> int:
	for dk: Dictionary in dikes:
		if absf((dk.n as Vector3).dot(p) - dk.d) < dk.t * 0.5:
			return dk.layer
	for f: Dictionary in faults:
		var dist := absf((f.n as Vector3).dot(p) - f.d)
		if dist < f.w:
			if f.has("vein") and dist < f.w * 0.45 and swell.get_noise_3dv(p * 0.6) > -0.25:
				return f.vein
			return fault_layer
	for v: Dictionary in vein_sets:
		var n: Vector3 = v.n
		var d: float = n.dot(p) + warp.get_noise_3dv(p * 0.5 + Vector3(40, 0, 0)) * float(v.wob)
		var sp: float = v.space
		var local := fposmod(d, sp)
		var dist := minf(local, sp - local)
		# Раздув и пережим; где шум низкий — трещины нет (жила обрывается).
		var sw := swell.get_noise_3dv(p + n * 13.0)
		if sw < -0.3:
			continue
		if dist < v.t * 0.5 * (0.5 + sw * 1.2 + 0.5):
			return v.layer
	return -1

## Номер слоя в точке p (система участка). under — глубина под природной
## поверхностью (surface_h − y), up — насколько ровно здесь (нормаль.y).
func layer_at(p: Vector3, under: float, up := 1.0) -> int:
	return _info(p, under, up).x

## x — слой; y — выветрелость 0..1 (дресва); z — мерзлота 0/1.
func _info(p: Vector3, under: float, up := 1.0) -> Vector3i:
	var sd := _soil(up)
	var wob := warp.get_noise_2d(p.x * 2.5, p.z * 2.5) * 0.35
	if under < sd:
		return Vector3i(SOIL, 0, 0)
	var frozen := 1 if ice_on and under < perm_d else 0
	# Ледяной клин: по рёбрам многоугольников, сужается вглубь.
	if frozen == 1 and under < sd + wedge_d:
		var e := poly.get_noise_2d(p.x, p.z)
		var w := 0.09 * (1.0 - (under - sd) / wedge_d)
		if e > -1.0 and e + 1.0 < w:
			return Vector3i(ICE, 0, 1)
	if under < sub_d * lerpf(0.4, 1.0, up) + wob:
		return Vector3i(SUBSOIL, 0, frozen)
	var x := _cross(p)
	if x < 0:
		var b := _band(_band_y(p))
		x = ROCK + int(b.x)
		if int(b.x) == int(nodule.band) and absf(b.y - float(nodule.at)) < 0.12 \
				and nodule.noise.get_noise_3dv(Vector3(p.x, p.y * 2.2, p.z)) < nodule.thr:
			x = nodule.layer
	var wz := clampf(1.0 - (under - sub_d) / weather_d, 0.0, 1.0)
	return Vector3i(x, int(wz * 255.0), frozen)

## Цвет толщи в точке.
func color_at(p: Vector3, under: float, up := 1.0) -> Color:
	var inf := _info(p, under, up)
	var k := inf.x
	var gr := grain.get_noise_3dv(p)
	var c: Color = layers[k].color
	var kind: int = layers[k].kind
	if kind == ROCK:
		# Граница пластов — тонкая тёмная линия напластования.
		var b := _band(_band_y(p))
		var h: float = band_h[int(b.x)]
		var edge := minf(b.y, 1.0 - b.y) * h
		c = c * (0.93 + 0.1 * gr) * (0.8 + 0.2 * smoothstep(0.0, 0.3, edge))
	elif kind == FAULT:
		c = c * (0.75 + 0.5 * absf(grain.get_noise_3dv(p * 2.5)))     # обломки
	elif kind == DIKE:
		c = c * (0.9 + 0.1 * gr)
	elif kind == SUBSOIL:
		c = c * (0.85 + 0.3 * absf(gr))                               # галька
	else:
		c = c * (0.95 + 0.08 * gr)
	# Дресва: та же порода, но рыхлая — бледнее, в пятнах подпочвы.
	var wz := inf.y / 255.0
	if wz > 0.0 and kind != SUBSOIL and kind != SOIL:
		var sub_c: Color = layers[SUBSOIL].color
		c = c.lerp(sub_c, wz * (0.45 + 0.35 * smoothstep(-0.2, 0.4, grain.get_noise_3dv(p * 0.6))))
	# Мерзлота: иней в порах.
	if inf.z == 1 and kind != ICE:
		c = c.lerp(layers[ICE].color, 0.22)
	c.a = 1.0
	return c

## Что даёт бур или лопата в точке: {"name", "sub", "kind", "frozen"}.
func dig_yield(p: Vector3, under: float, up := 1.0) -> Dictionary:
	var inf := _info(p, under, up)
	var l: Dictionary = layers[inf.x]
	return {"name": l.name, "sub": l.sub, "kind": int(l.kind), "frozen": inf.z == 1}

func summary() -> String:
	var names: Array = []
	var extra: Array = []
	for l: Dictionary in layers:
		if l.kind == ROCK and not names.has(l.name):
			names.append(l.name)
		elif l.kind == VEIN or l.kind == DIKE:
			extra.append(l.name)
	return "толща: %s %.1f м, подпочва до %.1f м, дресва ещё %.1f м%s; складки %.0f м / %.0f м, разломов %d; пачка: %s; секут: %s" % [
		layers[SOIL].name, soil_d, sub_d, weather_d, ", мерзлота до %.0f м" % perm_d if ice_on else "",
		fold_amp, fold_len, faults.size(), ", ".join(PackedStringArray(names)), ", ".join(PackedStringArray(extra))]
