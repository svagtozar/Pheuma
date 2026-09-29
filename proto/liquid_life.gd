class_name ProtoLiquidLife
extends Node
## Живые жидкости превью: озеро и лава на ProtoFlow.
## - Паводок: раз в цикл река несёт больше, озеро поднимается, вода выходит
##   из берегов и растекается по низинам, потом спадает; лужи в низинах сохнут.
## - Извержение (вулкан): кратер переполняется, лава стекает языками по склону,
##   заливает низины и застывает коркой — по корке можно ходить.
## Шаг симуляции — 10 раз в секунду, сетка поверхности пересобирается не чаще
## 4 раз в секунду (Deck — 2) и только если уровень сдвинулся.

const TICK := 0.1
const FLOOD_PERIOD := 300.0      # цикл паводка, с
const FLOOD_Q := 10.0            # приток на подъёме, м³/с
const ERUPT_FIRST := 45.0        # первое извержение, с от начала
const ERUPT_GAP := [150.0, 220.0]
const ERUPT_DUR := 30.0
const ERUPT_Q := 7.0             # м³/с из жерла

var terrain: ProtoTerrain
var lake: ProtoFlow              # озеро (с ним и лава, если озеро лавовое)
var lava: ProtoFlow              # поток из вулкана или null
var lake_level0 := 0.0
var flood_amp := 2.0             # на сколько поднимается озеро в паводок, м
var flood_phase := 0.0           # сдвиг цикла, с
var t := 0.0
var erupt_next := ERUPT_FIRST
var erupt_left := 0.0
var notes: Callable              # (text) — сообщение игроку (тост рана)
var _acc := 0.0
var _mesh_t := 0.0
var _crust_t := 0.0
var _mouth: Dictionary = {}
var _vent: Dictionary = {}
var _crust_body: StaticBody3D
var _crust_shape: CollisionShape3D
var _flooding := false
var _vent_c := Vector2.ZERO
var _rng := RandomNumberGenerator.new()
## Опыт Rapier (--rapier=pure|hybrid, ProtoRapierFluid): извержение бьёт
## фонтаном частиц, паводок втекает в озеро струёй. hybrid — осевшие частицы
## сдают объём сетке; pure — жидкость приходит только частицами.
var rapier_mode := ""
var lava_fx: ProtoRapierFluid
var lake_fx: ProtoRapierFluid
var _lava_em: Dictionary = {}
var _lake_em: Dictionary = {}
var _rapier_log := 0.0
var _phys_sum := 0.0
var _phys_n := 0

## Озеро: заливка ложа до level по области in_lake; ртом реки питается паводок.
func setup_lake(t_: ProtoTerrain, s: Substance, level: float, in_lake: Callable, seed_value: int) -> ProtoFlow:
	terrain = t_
	lake = ProtoFlow.new(terrain, s)
	lake.fill(level, in_lake)
	lake_level0 = level
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 31 + 5
	_rng.seed = seed_value * 17 + 9
	flood_amp = rng.randf_range(1.6, 2.4) * (0.6 if s.melt > 300.0 else 1.0)
	flood_phase = rng.randf_range(0.0, 60.0)
	_mouth = lake.add_source(terrain.lake_c.x + terrain.lake_r * 0.7, terrain.lake_c.y, 0.0)
	lake.evap = 0.004
	lake.rebuild()
	return lake

## Вулкан: жерло в кратере. Своя сетка, даже если озеро тоже лавовое: рамка
## считаемых клеток у каждой своя, и спокойное озеро засыпает.
func setup_volcano(s: Substance) -> ProtoFlow:
	_vent_c = ProtoTerrain.VOLC_C
	lava = ProtoFlow.new(terrain, s)
	var vc := _vent_c
	# Кратер налит до прежнего диска лавы и не остывает.
	lava.fill(23.6, func(x, z): return Vector2(x, z).distance_to(vc) < 3.6)
	_vent = lava.add_source(vc.x, vc.y, 0.0)
	lava.rebuild()
	return lava

func setup_rapier(mode: String, ambient: float) -> void:
	if not ProtoRapierFluid.available():
		print("Rapier: нет аддона или движок физики не Rapier3D (tools/rapier.sh) — жидкости как были")
		return
	rapier_mode = mode
	if mode == "off":
		return                   # только замер физики (для сравнения)
	if lava != null:
		lava_fx = ProtoRapierFluid.new()
		lava_fx.name = "rapier_lava"
		lava_fx.cool_time = 25.0
		add_child(lava_fx)
		lava_fx.setup(lava.sub, ambient, lava, mode == "hybrid")
		lava_fx.set_ground(_vent_c, 9 if mode == "hybrid" else 16)
		# Фонтан из жерла, наклонён к самому низкому краю кратера — туда лава и стекает.
		var side := _low_rim()
		var top := lava.level_at(_vent_c.x, _vent_c.y) + 0.4
		print("Rapier: фонтан лавы из (%.1f, %.1f, %.1f) к краю %s" % [_vent_c.x, top, _vent_c.y, side])
		_lava_em = lava_fx.add_emitter(Vector3(_vent_c.x, top, _vent_c.y), Vector3(side.x, 0, side.y) * 4.2 + Vector3.UP * 7.0,
			ProtoRapierFluid.rate_for(ERUPT_Q), 1.6)
		_lava_em.on = false
	if lake != null:
		lake_fx = ProtoRapierFluid.new()
		lake_fx.name = "rapier_lake"
		add_child(lake_fx)
		lake_fx.setup(lake.sub, ambient, lake, mode == "hybrid")
		# Струя из устья реки: паводок втекает в озеро.
		var mx := terrain.lake_c.x + terrain.lake_r * 0.7
		var mz := terrain.lake_c.y
		_lake_em = lake_fx.add_emitter(Vector3(mx, terrain.river_level_at(mx) + 0.6, mz), Vector3(-3.5, 0.5, 0),
			0.0, 0.8)
		lake_fx.set_ground(Vector2(mx, mz), 10)
		print("Rapier: приток озера из (%.1f, %.1f, %.1f), озеро %.1f м" % [mx, terrain.river_level_at(mx) + 0.6, mz, lake.level_at(terrain.lake_c.x, terrain.lake_c.y)])

func _low_rim() -> Vector2:
	var low := INF
	var side := Vector2(1, 0)
	for k in 24:
		var dd := Vector2(cos(TAU * k / 24.0), sin(TAU * k / 24.0))
		var hh := terrain.surface_h(_vent_c.x + dd.x * 4.6, _vent_c.y + dd.y * 4.6)
		if hh < low:
			low = hh
			side = dd
	return side

func flows() -> Array:
	var a := []
	if lake != null:
		a.append(lake)
	if lava != null and lava != lake:
		a.append(lava)
	return a

## Цель паводка 0..1 в момент tt: спокойно — подъём — стоит — спад.
func flood_k(tt: float) -> float:
	var p := fposmod(tt + flood_phase, FLOOD_PERIOD) / FLOOD_PERIOD
	if p < 0.3:
		return 0.0
	if p < 0.5:
		return smoothstep(0.3, 0.5, p)
	if p < 0.62:
		return 1.0
	return 1.0 - smoothstep(0.62, 0.95, p)

func lake_level() -> float:
	return lake.level_at(terrain.lake_c.x, terrain.lake_c.y)

func crust_cells() -> int:
	var n := 0
	if lava != null:
		for c in lava.crust:
			if c > 0.02:
				n += 1
	return n

func erupting() -> bool:
	return erupt_left > 0.0

## Прокрутить время вперёд без сеток (кадры, тесты).
func advance(sec: float) -> void:
	var n := int(sec / TICK)
	for i in n:
		_tick()
	for f in flows():
		f.rebuild()
	_update_crust()

func _process(dt: float) -> void:
	_acc += dt
	var steps := 0
	while _acc >= TICK and steps < 3:
		_acc -= TICK
		_tick()
		steps += 1
	_acc = minf(_acc, TICK)
	_mesh_t -= dt
	if _mesh_t <= 0.0:
		_mesh_t = 0.5 if ProtoDeck.active else 0.25
		for f in flows():
			if f.dirty:
				f.rebuild()
	if rapier_mode != "":
		_phys_sum += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
		_phys_n += 1
		_rapier_log -= dt
		if _rapier_log <= 0.0:
			_rapier_log = 5.0
			if OS.has_environment("RAPIER_COLLIDERS"):
				_dump_colliders(get_tree().root)
			if rapier_mode == "off":
				print("Rapier off: физика в кадре %.2f мс (среднее за 5 с)" % (_phys_sum / maxf(_phys_n, 1)))
			for fx in [lava_fx, lake_fx]:
				if fx != null:
					print("Rapier %s: частиц %d, в сетку сдано %.1f м³, физика в кадре %.2f мс (среднее за 5 с), из них скрипт %.2f мс/шаг" % [fx.name,
						fx.count(), fx.handed, _phys_sum / maxf(_phys_n, 1), fx.script_us / 1000.0 / maxf(fx.script_n, 1)])
					print("  ушли: упали %d, лимит %d, возраст %d; провалились %d, пропали в движке %d" % [fx.lost_fall, fx.lost_cap, fx.lost_age, fx.fell_through, fx.lost_engine])
					fx.script_us = 0
					fx.script_n = 0
			_phys_sum = 0.0
			_phys_n = 0
	_crust_t -= dt
	if _crust_t <= 0.0:
		_crust_t = 1.5
		_update_crust()

func _tick() -> void:
	t += TICK
	if lake != null:
		# Паводок: к цели ведёт приток у устья (подъём) или общая убыль (спад).
		var goal := lake_level0 + flood_amp * flood_k(t)
		var cur := lake_level()
		# Мёртвая зона: в покое озеро не подпитывается и засыпает (ProtoFlow.step).
		_mouth.q = clampf((goal - cur - 0.04) * 12.0, 0.0, FLOOD_Q)
		if lake_fx != null:
			# Приток идёт струёй частиц, а не прямо в клетку устья.
			_lake_em.rate = ProtoRapierFluid.rate_for(_mouth.q)
			_mouth.q = 0.0
		lake.drain = clampf((cur - goal - 0.04) * 0.06, 0.0, 0.03)
		var rising := goal > lake_level0 + 0.15 and flood_k(t + 5.0) > flood_k(t)
		if rising and not _flooding:
			_say("Паводок: река несёт больше, озеро выходит из берегов — низины у воды зальёт.")
		_flooding = rising
	if lava != null:
		if erupt_left > 0.0:
			erupt_left -= TICK
			_vent.q = ERUPT_Q
			if lava_fx != null:
				_vent.q = 0.0          # лава вылетает фонтаном частиц
				_lava_em.on = true
			if erupt_left <= 0.0:
				_vent.q = 0.0
				if lava_fx != null:
					_lava_em.on = false
				erupt_next = t + _rng.randf_range(ERUPT_GAP[0], ERUPT_GAP[1])
		elif t >= erupt_next:
			erupt_left = ERUPT_DUR
			_say("Извержение! Лава переливается через край кратера и стекает в низины — держитесь выше.")
	for f in flows():
		f.step(TICK)

func _say(text: String) -> void:
	if notes.is_valid():
		notes.call(text)
	else:
		print(text)

## Столкновения по застывшей корке: робот ходит по ней, а не тонет.
func _update_crust() -> void:
	if lava == null or not lava.crust_dirty:
		return
	lava.crust_dirty = false
	var r := lava.crust_shape()
	if r.is_empty():
		return
	if _crust_body == null:
		_crust_body = StaticBody3D.new()
		_crust_body.name = "crust_collision"
		_crust_body.collision_layer = RobotGround.LAYER
		_crust_body.collision_mask = 0
		_crust_shape = CollisionShape3D.new()
		_crust_body.add_child(_crust_shape)
		add_child(_crust_body)
	_crust_body.position = r[0]
	_crust_shape.shape = r[1]

func _dump_colliders(n: Node) -> void:
	if n is CollisionShape3D and n.shape != null:
		var sz := Vector3.ZERO
		var sh: Shape3D = n.shape
		if sh is BoxShape3D: sz = sh.size
		elif sh is HeightMapShape3D: sz = Vector3(sh.map_width, 0, sh.map_depth)
		elif sh is ConcavePolygonShape3D:
			var f: PackedVector3Array = sh.get_faces()
			if f.size() > 0:
				var bb := AABB(f[0], Vector3.ZERO)
				for q in f: bb = bb.expand(q)
				sz = bb.size
		elif sh is SphereShape3D: sz = Vector3.ONE * sh.radius * 2
		elif sh is WorldBoundaryShape3D: sz = Vector3.INF
		if sz.x * sz.z > 400.0 or sz == Vector3.ZERO:
			print("collider ", n.get_path(), " ", sh.get_class(), " ", sz)
	for c in n.get_children():
		_dump_colliders(c)
