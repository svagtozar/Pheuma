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
		lake.drain = clampf((cur - goal - 0.04) * 0.06, 0.0, 0.03)
		var rising := goal > lake_level0 + 0.15 and flood_k(t + 5.0) > flood_k(t)
		if rising and not _flooding:
			_say("Паводок: река несёт больше, озеро выходит из берегов — низины у воды зальёт.")
		_flooding = rising
	if lava != null:
		if erupt_left > 0.0:
			erupt_left -= TICK
			_vent.q = ERUPT_Q
			if erupt_left <= 0.0:
				_vent.q = 0.0
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
