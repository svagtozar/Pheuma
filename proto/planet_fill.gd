class_name ProtoPlanetFill
extends Node3D
## Наполнение шара вне участка (ProtoPlanetStream): поросль и крупные формы
## (ProtoFlora), россыпи залежей и друз, которые можно бурить (ProtoDeposit →
## ProtoMining), и моря в котловинах. Узел — ребёнок шара, так что всё в системе
## планеты и поворачивается вместе с ним.
## Наполняются куски шара (те же, что у рельефа, ~63 м) ближе NEAR к роботу,
## убираются дальше FAR. Содержимое куска — от seed и номера куска: вернулся —
## всё на тех же местах. Флора собирается в потоках; залежи ставятся в основном
## (их единицы на кусок).
## Моря: у планеты с жидкостью котловины (ProtoTerrain.basin_depth), уровень —
## по доле поверхности под водой (океаническим — много); одна оболочка шара по
## клеткам, где дно ниже уровня. Для урона и плавания — зона "sea" (sea_at).

const NEAR := 115.0           # куски ближе (по дуге до середины) — наполняем
const FAR := 175.0            # дальше — убираем
const STEP := 1.5             # шаг поросли, м (как у участка, чуть реже)
const EXTENT := 50.0          # полуширина квадрата выборки вокруг середины куска
const SEA_CLEAR := 110.0      # у участка моря нет (по дуге от середины участка)
const SEA_CELLS := 40         # клеток на грань оболочки моря
const FIND_R := 22.0          # залежь «найдена», если робот подошёл ближе

var stream: ProtoPlanetStream
var terrain: ProtoTerrain
var flora: ProtoFlora
var mining: ProtoMining
var planet: Planet
var seed_value := 0
var lite := false             # Steam Deck: реже поросль, короче видимость
var subs: Array = []          # твёрдые вещества планеты для залежей
var look := {}
var sea_sub: Substance
var sea_mat: ShaderMaterial
var sea_mi: MeshInstance3D
var chunks := {}              # Vector3i → {"node": Node3D, "druses": [узлы]}
var finds := {}               # id → {kind, pos (система планеты), name, color, found}
var built := 0                # кусков наполнено за всё время (для проверок)
var _flora_mat: ShaderMaterial
var _mats := {}               # вещество → материал залежи
var _pending := {}            # кусок → строится в потоке
var _busy := 0
var _last := Vector3.INF
var _again := false           # не все нужные куски запущены — пересмотреть

static func create(s: ProtoPlanetStream, fl: ProtoFlora, p: Planet, seed_v: int) -> ProtoPlanetFill:
	var f := ProtoPlanetFill.new()
	f.name = "fill"
	f.stream = s
	f.terrain = s.terrain
	f.flora = fl
	f.planet = p
	f.seed_value = seed_v
	f.lite = ProtoDeck.active
	f.subs = ProtoSky.solid_mats(p)
	f.look = ProtoDeposit.planet_look(p, s.terrain.style.habit)
	if fl != null and fl.life > 0:
		f._flora_mat = ProtoFlora.material(fl.glow, fl.wind)
	return f

## Жидкость морей и доля поверхности под ними: у океанических — почти половина,
## у лавовых и кислотных — озёра поменьше. Котловины задаются до постройки шара.
func setup_seas(sub: Substance, ambient: float) -> void:
	if sub == null:
		return
	sea_sub = sub
	var share := 0.14
	if planet.has_tag("oceanic"):
		share = 0.45
	elif sub.melt > 300.0 or sub.has("acidic"):
		share = 0.08
	terrain.basin_depth = 14.0 + share * 30.0
	# Уровень: доля выборки направлений вдали от участка ниже него.
	var r := RandomNumberGenerator.new()
	r.seed = seed_value * 31 + 5
	var hs: Array = []
	for i in 1500:
		var d := Vector3(r.randfn(), r.randfn(), r.randfn()).normalized()
		if terrain.arc_from_site(d) > 300.0:
			hs.append(terrain.sphere_h(d))
	hs.sort()
	var lvl: float = hs[int(hs.size() * share)]
	# Кольцо у участка должно остаться сухим: уровень ниже его самых низких мест.
	var ring := INF
	for k in 72:
		var th := k * TAU / 72.0
		for a in [SEA_CLEAR - 15.0, SEA_CLEAR, SEA_CLEAR + 25.0]:
			var ang: float = a / terrain.radius
			ring = minf(ring, terrain.sphere_h(Vector3(sin(ang) * cos(th), cos(ang), sin(ang) * sin(th))))
	terrain.sea_level = minf(lvl, ring - 0.6)
	sea_mat = ProtoLiquids.material(sub, ambient)
	print("Моря: %s, уровень %.1f м (котловины %.0f м, доля %.0f%%)" % [sub.name, terrain.sea_level, terrain.basin_depth, share * 100.0])

## Оболочка моря: клетки шара, где дно ниже уровня. Строится после шара.
func build_sea() -> void:
	if sea_sub == null or terrain.sea_level == -INF:
		return
	var t := terrain
	var lv := t.sea_level
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var n := SEA_CELLS
	for f in 6:
		for j in n:
			for i in n:
				var ds: Array = []
				for q in [Vector2(i, j), Vector2(i + 1, j), Vector2(i + 1, j + 1), Vector2(i, j + 1)]:
					ds.append(stream._dir(f, q.x / n, q.y / n))
				var mid := stream._dir(f, (i + 0.5) / n, (j + 0.5) / n)
				if t.arc_from_site(mid) < SEA_CLEAR + 20.0:
					continue
				var low := t.sphere_h(mid)
				for d: Vector3 in ds:
					low = minf(low, t.sphere_h(d))
				# Клетка ~30 м: по углам и середине берег, а между ними рельеф может
				# уйти под уровень — тогда край соседней клетки моря висел над
				# впадиной. Близкие к уровню клетки проверяем мельче.
				if low > lv + 0.3 and low < lv + 16.0:
					for sj in 4:
						for si in 4:
							var sd := stream._dir(f, (i + (si + 0.5) / 4.0) / n, (j + (sj + 0.5) / 4.0) / n)
							low = minf(low, t.sphere_h(sd))
				if low > lv + 0.3:
					continue
				var ps: Array = []
				for d: Vector3 in ds:
					ps.append(t.center + d * (t.radius + lv))
				# Оба треугольника смотрят наружу.
				for tri in [[0, 1, 2], [0, 2, 3]]:
					var a: Vector3 = ps[tri[0]]
					var b: Vector3 = ps[tri[1]]
					var c: Vector3 = ps[tri[2]]
					if (b - a).cross(c - a).dot(a - t.center) < 0.0:
						var tmp := b
						b = c
						c = tmp
					for v in [a, b, c]:
						verts.append(v)
						norms.append((v - t.center).normalized())
	if verts.is_empty():
		return
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	sea_mi = MeshInstance3D.new()
	sea_mi.name = "sea"
	sea_mi.mesh = mesh
	sea_mi.material_override = sea_mat
	sea_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(sea_mi)

## Зона жидкости для ProtoHealth / ProtoWater / ProtoPlayer.
func sea_zone(ambient: float) -> Dictionary:
	return {"sub": sea_sub, "temp": ProtoHealth.liquid_temp(sea_sub, ambient), "sea": self, "mat": sea_mat,
		"flow": null, "level": func(_x, _z): return terrain.sea_level, "area": func(_x, _z): return false}

## Глубина моря в мировой точке p (м; ≤ 0 — не в море).
func sea_at(p: Vector3) -> float:
	if sea_sub == null:
		return 0.0
	var v := terrain.to_local * p - terrain.center
	var r := v.length()
	if terrain.arc_from_site(v / r) < SEA_CLEAR + 20.0:
		return 0.0
	return terrain.radius + terrain.sea_level - r

# ---------------------------------------------------------------- куски

func _process(_dt: float) -> void:
	if stream == null or stream.target == null:
		return
	var q := stream.local_pos()
	_find(q)
	if q.distance_to(_last) < 6.0:
		return
	_again = false
	_last = q
	var d := (q - terrain.center).normalized()
	var want: Array = []
	for i in stream._centers.size():
		var a := acos(clampf(stream._centers[i].dot(d), -1.0, 1.0)) * terrain.radius
		var k: Vector3i = stream._keys[i]
		if a < NEAR:
			if not chunks.has(k) and not _pending.has(k):
				want.append([a, k])
		elif a > FAR and chunks.has(k):
			_drop(k)
	want.sort_custom(func(x, y): return x[0] < y[0])
	for w in want:
		if _busy >= 2:
			_again = true      # остальные — когда освободится поток
			break
		_start(w[1])

func _start(k: Vector3i) -> void:
	_busy += 1
	_pending[k] = WorkerThreadPool.add_task(_job.bind(k), false, "наполнение шара")

## Выход из сцены (новая планета, выход из игры): дождаться своих потоков.
func _exit_tree() -> void:
	for k in _pending:
		WorkerThreadPool.wait_for_task_completion(_pending[k])
	_pending.clear()

## Наполнить сразу всё у робота (при загрузке и для кадров).
func build_now() -> void:
	_last = stream.local_pos()
	var d := (_last - terrain.center).normalized()
	var ks: Array = []
	for i in stream._centers.size():
		if acos(clampf(stream._centers[i].dot(d), -1.0, 1.0)) * terrain.radius < NEAR:
			ks.append(stream._keys[i])
	_now_keys = ks
	_now_out = []
	_now_out.resize(ks.size())
	var id := WorkerThreadPool.add_group_task(func(i): _now_out[i] = _arrays(_now_keys[i]), ks.size(), -1, true, "наполнение шара")
	WorkerThreadPool.wait_for_group_task_completion(id)
	for i in ks.size():
		_ready_chunk(ks[i], _now_out[i])
	_now_keys = []
	_now_out = []

var _now_keys: Array = []
var _now_out: Array = []

func _job(k: Vector3i) -> void:
	var out := _arrays(k)
	call_deferred("_done", k, out)

func _done(k: Vector3i, out: Dictionary) -> void:
	if not is_inside_tree():
		return
	_busy -= 1
	_pending.erase(k)
	if _again:
		_last = Vector3.INF
	var d := (stream.local_pos() - terrain.center).normalized()
	var c := stream._dir(k.x, (k.y + 0.5) / stream.n_face, (k.z + 0.5) / stream.n_face)
	if acos(clampf(c.dot(d), -1.0, 1.0)) * terrain.radius > FAR:
		return            # робот уже ушёл
	_ready_chunk(k, out)

func _drop(k: Vector3i) -> void:
	var ch: Dictionary = chunks[k]
	if mining != null:
		var gone: Array = ch.druses
		mining.druses = mining.druses.filter(func(e): return not gone.has(e.node))
	(ch.node as Node3D).queue_free()
	chunks.erase(k)

## Система куска: начало — середина куска на поверхности, Y — от центра планеты.
func chunk_frame(k: Vector3i) -> Transform3D:
	var y := stream._dir(k.x, (k.y + 0.5) / stream.n_face, (k.z + 0.5) / stream.n_face)
	var x := y.cross(Vector3.FORWARD if absf(y.z) < 0.9 else Vector3.RIGHT).normalized()
	var o := terrain.center + y * (terrain.radius + terrain.sphere_h(y))
	return Transform3D(Basis(x, y, x.cross(y)), o)

## Номер куска шара, в который попадает направление d (обратная к _dir).
func key_of(d: Vector3) -> Vector3i:
	var ax := absf(d.x)
	var ay := absf(d.y)
	var az := absf(d.z)
	var f := 0
	var a := 0.0
	var b := 0.0
	if ay >= ax and ay >= az:
		if d.y > 0.0:
			f = 0; a = d.x / d.y; b = d.z / d.y
		else:
			f = 1; a = d.x / -d.y; b = d.z / d.y
	elif ax >= az:
		if d.x > 0.0:
			f = 2; a = -d.y / d.x; b = d.z / d.x
		else:
			f = 3; a = d.y / -d.x; b = d.z / -d.x
	else:
		if d.z > 0.0:
			f = 4; a = d.x / d.z; b = d.y / d.z
		else:
			f = 5; a = d.x / d.z; b = d.y / -d.z
	var n := stream.n_face
	var u := atan(a) / (PI * 0.5) + 0.5
	var v := atan(b) / (PI * 0.5) + 0.5
	return Vector3i(f, clampi(int(u * n), 0, n - 1), clampi(int(v * n), 0, n - 1))

## Точка поверхности по направлению d (система планеты).
func _surf(d: Vector3) -> Vector3:
	return terrain.center + d * (terrain.radius + terrain.sphere_h(d))

## В потоке: сетки флоры и места залежей куска (всё в системе куска).
func _arrays(k: Vector3i) -> Dictionary:
	var t := terrain
	var fr := chunk_frame(k)
	var inv := fr.affine_inverse()
	var e1 := fr.basis.x
	var e3 := fr.basis.z
	var y0 := fr.basis.y
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value, k.x, k.y, k.z])
	var fl: ProtoFlora = flora.fork(rng.randi()) if flora != null and flora.life > 0 else null
	var step := STEP * (1.35 if lite else 1.0)
	var R := t.radius
	var sea := t.sea_level
	var spots: Array = []          # ровные места для залежей: [p, nrm]
	var steep: Array = []          # склоны — для жил и пластов
	var a := -EXTENT
	var n := 0
	while a < EXTENT:
		var b := -EXTENT
		while b < EXTENT:
			var ja := a + rng.randf_range(-0.6, 0.6) * step
			var jb := b + rng.randf_range(-0.6, 0.6) * step
			b += step
			var d := (y0 * R + e1 * ja + e3 * jb).normalized()
			if key_of(d) != k:
				continue
			var P := _surf(d)
			# Участок — со своей флорой и залежами.
			if d.y > 0.5 and t.out_dist(t.center.x + d.x * (R + 16.0) / d.y, t.center.z + d.z * (R + 16.0) / d.y) < 2.0:
				continue
			var hgt := (P - t.center).length() - R
			if hgt < sea + 0.25:
				continue
			n += 1
			var wet := clampf(1.0 - (hgt - sea) / 5.0, 0.0, 1.0) if sea > -INF else 0.0
			var fert := fl.far_fertility(ProtoTerrain.far_key(P), wet) if fl != null else -INF
			var probe := n % 23 == 0
			if not probe and (fl == null or fert < fl.thr):
				continue
			# Нормаль по двум соседним точкам.
			var e := 0.6 / R
			var pa := _surf((d + e1 * e).normalized())
			var pb := _surf((d + e3 * e).normalized())
			var nrm := (pb - P).cross(pa - P).normalized()
			if nrm.dot(d) < 0.0:
				nrm = -nrm
			var lp := inv * P
			var ln := (fr.basis.inverse() * nrm).normalized()
			if probe:
				if ln.y > 0.85:
					spots.append([lp, ln])
				elif ln.y > 0.35 and ln.y < 0.7:
					steep.append([lp, ln])
			if fl != null:
				fl.far_spot(lp, ln, fert, wet)
		a += step
	var geos: Array = []
	if fl != null:
		for key in fl._geo:
			var g: ProtoFlora.Geo = fl._geo[key]
			if g.v.is_empty():
				continue
			geos.append([key, g.v, g.n, g.c, g.uv, g.idx])
	# Россыпь залежей — в каждом втором-третьем куске: 2–4 штуки рядом.
	var deps: Array = []
	if not subs.is_empty() and not spots.is_empty() and rng.randf() < 0.45:
		var c: Array = spots[rng.randi() % spots.size()]
		var s_i := rng.randi() % subs.size()
		var cnt := rng.randi_range(2, 4)
		var form := ProtoDeposit.form_for(subs[s_i])
		var pool: Array = spots if ProtoDeposit.on_floor(form) or steep.is_empty() else steep
		pool = pool.filter(func(s): return (s[0] as Vector3).distance_to(c[0]) < 12.0)
		pool.shuffle()
		for s in pool:
			if deps.size() >= cnt:
				break
			if deps.any(func(o): return (o[0] as Vector3).distance_to(s[0]) < 2.2):
				continue
			deps.append([s[0], s[1], s_i, rng.randf_range(1.1, 1.6), rng.randi()])
	return {"frame": fr, "geos": geos, "deps": deps, "plants": fl.plants if fl else 0}

## В основном потоке: узел куска, сетки флоры, залежи.
func _ready_chunk(k: Vector3i, out: Dictionary) -> void:
	if chunks.has(k):
		return
	var node := Node3D.new()
	node.name = "fill_%d_%d_%d" % [k.x, k.y, k.z]
	node.transform = out.frame
	add_child(node)
	for g: Array in out.geos:
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = g[1]
		arr[Mesh.ARRAY_NORMAL] = g[2]
		arr[Mesh.ARRAY_COLOR] = g[3]
		arr[Mesh.ARRAY_TEX_UV] = g[4]
		arr[Mesh.ARRAY_INDEX] = g[5]
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		var mi := MeshInstance3D.new()
		mi.mesh = m
		mi.material_override = _flora_mat
		if String(g[0]).begins_with("low"):
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.visibility_range_end = 40.0 if lite else 60.0
			mi.visibility_range_end_margin = 6.0
		else:
			mi.visibility_range_end = 150.0
			mi.visibility_range_end_margin = 15.0
		node.add_child(mi)
	var dr: Array = []
	var mined: Array = stream.get_parent().get_meta("mined_far", []) if stream.get_parent() else []
	for i in out.deps.size():
		var e: Array = out.deps[i]
		var s: Substance = subs[e[2]]
		var form := ProtoDeposit.form_for(s)
		if not _mats.has(s):
			_mats[s] = ProtoDeposit.material(s, form, look)
		var r := RandomNumberGenerator.new()
		r.seed = e[4]
		var dn := ProtoDeposit.build(s, form, e[3], r, look, _mats[s])
		node.add_child(dn)
		ProtoDeposit.place(dn, (e[0] as Vector3) - (e[1] as Vector3) * 0.04, e[1], r)
		var id := "%d_%d_%d_%d" % [k.x, k.y, k.z, i]
		dn.name = "far_%s" % id
		dn.set_meta("far_id", id)
		if mined.has(id):
			dn.queue_free()
			continue
		if mining != null:
			mining.add_druse(dn)
			dr.append(dn)
	record_find(k, out)
	chunks[k] = {"node": node, "druses": dr}
	built += 1

## После загрузки: выбуренные россыпи в уже наполненных кусках убрать.
func hide_mined(ids: Array) -> void:
	for k in chunks:
		var ch: Dictionary = chunks[k]
		for dn: Node3D in ch.druses.duplicate():
			if is_instance_valid(dn) and ids.has(str(dn.get_meta("far_id", ""))):
				ch.druses.erase(dn)
				if mining != null:
					mining.druses = mining.druses.filter(func(e): return e.node != dn)
				dn.queue_free()

## Метка россыпи куска (одна на кусок) — для радара и глобуса.
func record_find(k: Vector3i, out: Dictionary, found := false) -> void:
	if out.deps.is_empty():
		return
	var id := "%d_%d_%d_0" % [k.x, k.y, k.z]
	if finds.has(id):
		return
	var e: Array = out.deps[0]
	var s: Substance = subs[e[2]]
	var form := ProtoDeposit.form_for(s)
	var kind := "druse" if form == "druse" else "deposit"
	finds[id] = {"kind": kind, "pos": out.frame * (e[0] as Vector3), "name": "%s: %s" % [ProtoDeposit.NAMES[form].capitalize(), s.name],
		"color": ProtoMapData.KINDS[kind][1], "found": found, "under": false}

## Метки россыпей: найдена, если робот подошёл (для радара и карты-глобуса).
func _find(q: Vector3) -> void:
	for id in finds:
		var f: Dictionary = finds[id]
		if not f.found and (f.pos as Vector3).distance_to(q) < FIND_R:
			f.found = true

## Найденные россыпи — для сохранения (ProtoSave через ProtoMapData).
func save_finds() -> Array:
	var out: Array = []
	for id in finds:
		var f: Dictionary = finds[id]
		if f.found:
			out.append({"id": id, "kind": f.kind, "name": f.name, "p": [f.pos.x, f.pos.y, f.pos.z]})
	return out

func load_finds(a: Array) -> void:
	for e in a:
		if not (e is Dictionary) or not e.has("id"):
			continue
		var p: Array = e.get("p", [0, 0, 0])
		var kind := str(e.get("kind", "deposit"))
		finds[str(e.id)] = {"kind": kind, "pos": Vector3(float(p[0]), float(p[1]), float(p[2])),
			"name": str(e.get("name", "")), "color": ProtoMapData.KINDS.get(kind, ["", Color.WHITE])[1],
			"found": true, "under": false}
