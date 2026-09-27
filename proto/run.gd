class_name ProtoRun
extends RefCounted
## Ран в 3D-прототипе: цель планеты из трёх этапов с развилками, награды за этапы,
## прокачка классов, события планеты, советы «что дальше» и итоги.
## Логика общая с 2D: этапы считает GoalsTracker, карточки наград — Rewards,
## прокачку — Progression и SkillTree над RobotState, события — из data/events.gd.
## Для GoalsTracker и Rewards этот объект — «мир»: у него те же поля, что они
## читают у World (planet, robot, rng, stats, gas, goals, log_event, sound...).
##
## Этапы 2D-цели переводятся в то, что есть в 3D (adapt_goal):
##   p_mine     — добыть kg кристаллов буром (с начала этапа)
##   p_store    — kg продукции в баках завода
##   deliveries — n капсул пришло в баки (как в 2D, счётчик stats.hits)
##   p_process  — n порций обработано дробилкой и печью (с начала этапа)
##   p_parts    — n новых деталей завода (с начала этапа)
##   p_pressure — сеть держит p атм hold секунд
## Источники — завод (ProtoPneumatics), бур (ProtoMining) и груз робота
## (Array[Portion] в метаданных "cargo"); любой может отсутствовать.

const EVENT_FIRST := [150.0, 240.0]   # в 3D-ране события чаще, чем в 2D: карта меньше
const EVENT_GAP := [180.0, 300.0]
const STRIKE_EVERY := 2.5             # с между ударами метеоритов/обломков
const LOG_KEEP := 40

## Что событие делает в 3D (в 2D у них свои последствия — data/events.gd).
const EVENT_TIPS := {
	"meteors": "Уйдите из красного круга: удар рядом выбивает часть груза и ломает детали завода.",
	"ring_debris": "Уйдите из красного круга: обломки выбивают часть груза и ломают детали завода.",
	"geyser": "Деталь завода в круге гейзера бесплатно получит газ — давление в сети вырастет.",
	"storm": "Насосы качают вдвое медленнее, пока буря не стихнет.",
	"quake": "Толчок может порвать трубу завода — будьте готовы поставить её заново.",
	"acid": "Груз в открытом приёмнике разъедает — выгружайте в баки, пока не поздно.",
	"flare": "В круге вспышки бур работает вдвое быстрее — идите туда бурить.",
	"temp_shift": "Среда на время станет на 40 °C другой: давление в сети сдвинется.",
	"spore_bloom": "Споры забивают насосы: качают в три раза медленнее.",
	"time_loop": "Машины работают в полтора раза быстрее, а бур — медленнее.",
}

## Карточки наград, которые в 3D работают по-своему (остальные — как в 2D).
const CARDS_3D := {
	"supply": "С орбиты прилетит капсула: 15 кг кристаллов прямо в груз робота.",
	"repair": "Лопнувшие за ран детали завода встанут на свои места.",
	"survey": "Орбитальный анализ: теги всех материалов планеты станут известны.",
}

# ---- поля «мира» для GoalsTracker и Rewards
var planet: Planet
var robot := RobotState.new()
var rng: Rng
var goals: GoalsTracker
var stats := {"hits": 0}                 # hits — капсулы, пришедшие в баки
var gas := {"vented_total": 0.0}
var launched := {"mass": 0.0, "tags": {}, "exotic": 0.0, "subs": {}}
var excavated := 0.0
var orig_goal := {}                      # цель из генератора (2D)

# ---- источники 3D
var pneu                                 # ProtoPneumatics или null
var mining                               # ProtoMining или null
var body: Node3D                         # робот (груз — мета "cargo")
var crystal: Substance                   # материал друз (для «сброса припасов»)
var mats: Array = []                     # твёрдые материалы (прочность сети)

# ---- ран
var time := 0.0
var mined := 0.0                         # кг добыто за ран
var built := 0                           # деталей поставлено за ран
var processed := 0                       # порций обработано за ран
var briefing_seen := false
var end_shown := false
var log: Array = []                      # [время, текст]
var notes: Array = []                    # новые записи для всплывашек интерфейса
var last_sound := ""

# ---- события
var ev_next := 0.0
var ev := {}                             # {id, phase: warn|active, t, center: Vector3, radius, strike, hit}
var ev_count := 0
var factory_pos := Vector3.ZERO          # центр площадки (гейзер — рядом с заводом)
var pneu_origin_v := Vector3.ZERO        # где на мире клетка (0,0) завода
var robot_pos := Vector3.ZERO            # обновляет сцена
var zone_boost := 1.0                    # множитель бура от события (вспышка, петля)

var _last := {}                          # последние значения счётчиков источников
var _base_key := ""
var _bases := {}
var _ev_rng: Rng

func _init(p: Planet, source_mats: Array = []) -> void:
	planet = p
	mats = source_mats
	rng = Rng.new(p.seed_value)
	_ev_rng = rng.fork("events3d")
	orig_goal = p.goal
	planet.goal = adapt_goal(p.goal, _pressure_cap())
	goals = GoalsTracker.new(self)
	ev_next = _ev_rng.range_f(EVENT_FIRST[0], EVENT_FIRST[1])

## Подключить источники 3D (любые могут быть null) и запомнить их счётчики.
func attach(net, drill, robot_node: Node3D, crystal_sub: Substance, factory_center: Vector3) -> void:
	pneu = net
	mining = drill
	body = robot_node
	crystal = crystal_sub
	factory_pos = factory_center
	resync()

## Счётчики источников — «с этого места»; после загрузки сохранения тоже.
func resync() -> void:
	_last = {"mined": mining.mined_total if mining != null else 0.0,
		"placed": pneu.placed if pneu != null else 0,
		"delivered": pneu.delivered if pneu != null else 0,
		"processed": pneu.processed if pneu != null else 0}

# ---------------------------------------------------------------- этапы

## Предел давления для этапа p_pressure: 60% прочности трубы из лучшего материала.
func _pressure_cap() -> float:
	var best := 0.0
	for m in mats:
		best = maxf(best, ComponentStats.compute("pipe", m).max_p)
	return best * 0.6 if best > 0.0 else 3.0

## Цель 2D → цель 3D: имя и описание те же, этапы — то, что умеет прототип.
static func adapt_goal(goal: Dictionary, p_cap: float = 4.0) -> Dictionary:
	var out := {"n": goal.get("n", "Цель"), "desc": goal.get("desc", ""), "stages": []}
	var stages: Array = goal.get("stages", [])
	for i in stages.size():
		var raw: Dictionary = stages[i]
		if raw.has("alt"):
			var a: Dictionary = adapt_stage(raw.alt[0], i, p_cap)
			var b: Dictionary = adapt_stage(raw.alt[1], i, p_cap)
			if b.type == a.type:
				for t in ["p_mine", "deliveries", "p_process", "p_store", "p_parts", "p_pressure"]:
					if t != a.type:
						b = make_stage(t, i, p_cap)
						break
			out.stages.append({"alt": [a, b]})
		else:
			out.stages.append(adapt_stage(raw, i, p_cap))
	return out

static func adapt_stage(st: Dictionary, i: int, p_cap: float) -> Dictionary:
	var t := "p_mine"
	match str(st.get("type", "")):
		"stockpile_tags", "stockpile_mass", "phasing_contained":
			t = "p_store"
		"launch_mass", "launch_tag", "launch_exotic", "launch_variety", "deliveries":
			t = "deliveries"
		"build_count", "sensor_network":
			t = "p_parts"
		"machines_working":
			t = "p_process"
		"dome_env", "beacon_hold", "vent_gas":
			t = "p_pressure"
	var s := make_stage(t, i, p_cap)
	s.orig = st.get("desc", "")
	return s

## Этап 3D; i — номер этапа (0..2): чем дальше, тем больше нужно.
static func make_stage(t: String, i: int, p_cap: float) -> Dictionary:
	var k := clampi(i, 0, 2)
	match t:
		"p_store":
			var kg: float = [10.0, 20.0, 30.0][k]
			return {"type": t, "kg": kg, "desc": "Накопить в баках завода %.0f кг продукции" % kg,
				"pitch": "Груз — в приёмник, дальше дробилка, печь и баки. Следите за давлением."}
		"deliveries":
			var n: int = [8, 12, 16][k]
			return {"type": t, "n": n, "desc": "Доставить в баки %d капсул" % n,
				"pitch": "Поток груза по трубам: приёмник полон — капсулы идут одна за другой."}
		"p_parts":
			var n: int = [2, 3, 4][k]
			return {"type": t, "n": n, "desc": "Поставить %d новых детали завода" % n,
				"pitch": "Расширить завод: насосы, трубы, машины и баки."}
		"p_process":
			var n: int = [4, 8, 12][k]
			return {"type": t, "n": n, "desc": "Переработать на машинах %d порций" % n,
				"pitch": "Дробилка и печь должны работать без перерыва."}
		"p_pressure":
			var p: float = snappedf(minf([3.0, 3.5, 4.0][k], p_cap), 0.5)
			return {"type": t, "p": maxf(p, 1.5), "hold": 30.0,
				"desc": "Удержать в сети %.1f атм 30 секунд" % maxf(p, 1.5),
				"pitch": "Насосы из прочного материала, слабые детали — убрать."}
	var kg: float = [15.0, 25.0, 35.0][k]
	return {"type": "p_mine", "kg": kg, "desc": "Добыть буром %.0f кг кристаллов" % kg,
		"pitch": "Пещера и друзы: чем дальше в глубину, тем крупнее кристаллы."}

## GoalsTracker зовёт для этапов, которых нет в 2D.
func eval_stage(tr: GoalsTracker, st: Dictionary, dt: float) -> float:
	_check_stage()
	match st.type:
		"p_mine":
			return (mined - _bases.mined) / st.kg
		"p_store":
			return tank_mass() / st.kg
		"p_parts":
			return float(built - _bases.built) / st.n
		"p_process":
			return float(processed - _bases.processed) / st.n
		"p_pressure":
			return tr._hold(net_pressure() >= st.p, st.hold, dt)
	return 0.0

## Начался новый этап или выбран путь — счёт «с начала этапа» заново.
func _check_stage() -> void:
	var key := "%d:%s" % [goals.stage, str(goals.choices.get(str(goals.stage), ""))]
	if key != _base_key:
		_base_key = key
		_bases = {"mined": mined, "built": built, "processed": processed}

## Сколько сделано на текущем этапе: [сейчас, нужно, единица].
func stage_numbers() -> Array:
	var st := goals.current()
	_check_stage()
	var b := _bases
	match st.get("type", ""):
		"p_mine": return [mined - b.mined, st.kg, "кг"]
		"p_store": return [tank_mass(), st.kg, "кг"]
		"deliveries": return [float(stats.hits - goals.base_hits), float(st.n), "капсул"]
		"p_parts": return [float(built - b.built), float(st.n), "деталей"]
		"p_process": return [float(processed - b.processed), float(st.n), "порций"]
		"p_pressure": return [goals.hold, st.hold, "с"]
	return [0.0, 1.0, ""]

func tank_mass() -> float:
	if pneu == null:
		return 0.0
	var s := 0.0
	for c in pneu.parts:
		if pneu.parts[c].kind == "tank":
			s += pneu.mass_in(c)
	return s

func net_pressure() -> float:
	if pneu == null:
		return 0.0
	var best := 0.0
	for c in pneu.parts:
		best = maxf(best, pneu.pressure(c))
	return best

func cargo() -> Array:
	return ProtoMining.cargo_of(body) if body != null else []

func cargo_mass() -> float:
	var s := 0.0
	for p in cargo():
		s += p.mass
	return s

# ---------------------------------------------------------------- «мир» для 2D-логики

func log_event(_cell: Vector2i, text: String) -> void:
	log.append([time, text])
	if log.size() > LOG_KEEP:
		log.pop_front()
	notes.append(text)

func sound(name: String, _cell: Vector2i) -> void:
	last_sound = name

func robot_cell() -> Vector2i:
	return Vector2i.ZERO

# ---------------------------------------------------------------- шаг

func tick(dt: float) -> void:
	time += dt
	_check_stage()
	_pull_sources()
	_apply_passives()
	_events(dt)
	goals.tick(dt)

## Прирост счётчиков источников → опыт классов, знания, известные теги.
func _pull_sources() -> void:
	if mining != null:
		var d: float = mining.mined_total - float(_last.mined)
		if d > 0.0:
			mined += d
			robot.xp.gatherer += d * 0.4
			if crystal != null:
				learn_tags(crystal)
		_last.mined = mining.mined_total
	if pneu == null:
		return
	var np: int = pneu.placed - int(_last.placed)
	if np > 0:
		built += np
		robot.xp.crafter += 2.0 * np
	var nd: int = pneu.delivered - int(_last.delivered)
	if nd > 0:
		stats.hits += nd
		robot.xp.chief += 0.5 * nd
		for id in pneu.produced:
			var s: Substance = planet.db.get_sub(id)
			if s != null:
				learn_tags(s)
	var nr: int = pneu.processed - int(_last.processed)
	if nr > 0:
		processed += nr
		robot.xp.firekeeper += 1.0 * nr
	_last.placed = pneu.placed
	_last.delivered = pneu.delivered
	_last.processed = pneu.processed

## Теги материала — в знания робота; каждые два новых — очко знаний.
func learn_tags(s: Substance) -> int:
	var fresh: Array = []
	for t in s.tags:
		if not robot.known_tags.has(t):
			robot.known_tags[t] = true
			fresh.append(MaterialTags.display(t))
			robot.xp.shaman += 1.0
	if not fresh.is_empty():
		var before := (robot.known_tags.size() - fresh.size()) / 2
		robot.knowledge += robot.known_tags.size() / 2 - before
		log_event(Vector2i.ZERO, "Новые теги: " + ", ".join(PackedStringArray(fresh)))
	return fresh.size()

## Прокачка в 3D: бур (Чутьё залежей), насосы (Раздувание); goal_speed — сам трекер.
func _apply_passives() -> void:
	var ev_id := active_event()
	if mining != null:
		mining.speed_mult = (1.0 + robot.passive("mine_speed")) * zone_boost
	if pneu != null:
		var pm := 1.0 + robot.passive("pump_rate")
		if ev_id == "storm":
			pm *= 0.5
		elif ev_id == "spore_bloom":
			pm /= 3.0
		pneu.pump_mult = pm
		pneu.speed_mult = 1.5 if ev_id == "time_loop" else 1.0

# ---------------------------------------------------------------- события

func active_event() -> String:
	return ev.get("id", "") if ev.get("phase", "") == "active" else ""

func in_zone(p: Vector3) -> bool:
	if ev.is_empty() or float(ev.radius) <= 0.0:
		return false
	return Vector2(p.x, p.z).distance_to(Vector2(ev.center.x, ev.center.z)) <= float(ev.radius)

func _events(dt: float) -> void:
	zone_boost = 1.0
	if ev.is_empty():
		ev_next -= dt
		if ev_next <= 0.0:
			start_event(pick_event())
		return
	ev.t -= dt
	if ev.phase == "warn":
		if ev.t <= 0.0:
			_begin_event()
		return
	_event_active(dt)
	if ev.t <= 0.0:
		_finish_event()

func pick_event() -> String:
	var ids: Array = Events.EVENTS.keys()
	ids.sort()
	var weights := {}
	for id in ids:
		weights[id] = Events.weight(id, planet)
	return _ev_rng.weighted_pick(ids, weights)

## Начать событие с предупреждения. at — центр зоны (для тестов и кадров).
func start_event(id: String, at = null) -> void:
	var d: Dictionary = Events.EVENTS[id]
	var c: Vector3 = at if at != null else _event_center(id)
	var r: float = float(d.radius) * 2.0          # клетка 2D — 2 м
	if id == "geyser":
		r = 3.0
	ev = {"id": id, "phase": "warn", "t": _ev_rng.range_f(d.warn[0], d.warn[1]) * 0.75, "center": c,
		"radius": r, "strike": STRIKE_EVERY, "hit": false, "shift": 0.0}
	sound("alarm", Vector2i.ZERO)
	log_event(Vector2i.ZERO, "Надвигается: %s. %s" % [d.n, EVENT_TIPS.get(id, d.tip)])

func _event_center(id: String) -> Vector3:
	var ang := _ev_rng.range_f(0.0, TAU)
	if id == "geyser":
		return factory_pos + Vector3(cos(ang), 0, sin(ang)) * 5.0
	# Зона рядом с роботом — чтобы было от чего уходить (или куда идти).
	return robot_pos + Vector3(cos(ang), 0, sin(ang)) * _ev_rng.range_f(1.0, 4.0)

func _begin_event() -> void:
	var d: Dictionary = Events.EVENTS[ev.id]
	ev.phase = "active"
	ev.t = _ev_rng.range_f(d.dur[0], d.dur[1]) * 0.75
	log_event(Vector2i.ZERO, "Началось: " + d.n)
	match ev.id:
		"quake":
			_break_random("pipe")
		"temp_shift":
			if pneu != null:
				ev.shift = -40.0 if planet.ambient_temp > 20.0 else 40.0
				pneu.gas.ambient += ev.shift

func _event_active(dt: float) -> void:
	match ev.id:
		"meteors", "ring_debris":
			if in_zone(robot_pos):
				ev.hit = true
			ev.strike -= dt
			if ev.strike <= 0.0:
				ev.strike = STRIKE_EVERY
				_strike()
		"geyser":
			if pneu != null:
				for c in pneu.parts:
					var wp: Vector3 = ProtoPneumatics.cell_pos(pneu_origin(), c)
					if in_zone(wp):
						pneu.gas.add_gas(pneu.parts[c].id, 0.6 * dt)
						break
		"acid":
			if pneu != null:
				for c in pneu.parts:
					if pneu.parts[c].kind == "intake":
						for p in pneu.parts[c].items:
							p.mass *= 1.0 - 0.02 * dt
		"flare":
			if in_zone(robot_pos):
				zone_boost = 2.0
		"time_loop":
			zone_boost = 0.7

func pneu_origin() -> Vector3:
	return pneu_origin_v

## Удар метеорита или обломка: случайная точка зоны; робот рядом — теряет груз.
func _strike() -> void:
	var ang := _ev_rng.range_f(0.0, TAU)
	var at: Vector3 = ev.center + Vector3(cos(ang), 0, sin(ang)) * _ev_rng.range_f(0.0, float(ev.radius))
	ev.last_strike = at
	if in_zone(robot_pos) and Vector2(robot_pos.x, robot_pos.z).distance_to(Vector2(at.x, at.z)) < float(ev.radius) * 0.6:
		var loss := 0.2 * (1.0 - robot.passive("hazard_resist"))
		var lost := 0.0
		for p in cargo():
			lost += p.mass * loss
			p.mass *= 1.0 - loss
		var list := cargo()
		for i in range(list.size() - 1, -1, -1):
			if list[i].mass < 0.05:
				list.remove_at(i)
		if lost > 0.05:
			log_event(Vector2i.ZERO, "Удар рядом! Выбито %.1f кг груза" % lost)
	if pneu != null:
		for c in pneu.parts.keys():
			var wp: Vector3 = ProtoPneumatics.cell_pos(pneu_origin(), c)
			if Vector2(wp.x, wp.z).distance_to(Vector2(at.x, at.z)) < 1.5:
				pneu._burst(c)
				log_event(Vector2i.ZERO, "Удар разбил деталь завода")
				break

func _break_random(kind: String) -> void:
	if pneu == null:
		return
	var cells: Array = pneu.parts.keys().filter(func(c): return pneu.parts[c].kind == kind)
	if cells.is_empty():
		return
	cells.sort()
	var c: Vector2i = _ev_rng.pick(cells)
	pneu._burst(c)
	log_event(Vector2i.ZERO, "Толчок порвал трубу завода")

func _finish_event() -> void:
	var d: Dictionary = Events.EVENTS[ev.id]
	if ev.id == "temp_shift" and pneu != null:
		pneu.gas.ambient -= float(ev.shift)
	if ev.id in ["meteors", "ring_debris"] and not ev.hit:
		robot.xp.hunter += 4.0
		log_event(Vector2i.ZERO, "Робот переждал «%s» вне зоны: опыт охотника" % d.n)
	robot.xp.hunter += 1.0
	ev_count += 1
	log_event(Vector2i.ZERO, "Прошло: " + d.n)
	ev = {}
	ev_next = _ev_rng.range_f(EVENT_GAP[0], EVENT_GAP[1])

## Строка для баннера: "" — события нет.
func event_line() -> String:
	if ev.is_empty():
		return ""
	var d: Dictionary = Events.EVENTS[ev.id]
	if ev.phase == "warn":
		return "Надвигается: %s — через %d с" % [d.n, ceili(ev.t)]
	return "%s — ещё %d с" % [d.n, ceili(ev.t)]

func event_tip() -> String:
	return EVENT_TIPS.get(ev.get("id", ""), "")

# ---------------------------------------------------------------- награды и прокачка

func card(id: String) -> Dictionary:
	var c: Dictionary = Rewards.CARDS[id]
	return {"n": c.n, "desc": CARDS_3D.get(id, c.desc)}

## Взять карточку: общие (знания, чертёж, слот) — как в 2D, остальные — по-3D-шному.
func take_reward(id: String) -> String:
	if not id in goals.reward_pending:
		return ""
	if not CARDS_3D.has(id):
		return goals.take_reward(id)
	goals.reward_pending = []
	var msg := ""
	match id:
		"supply":
			var s: Substance = crystal if crystal != null else World.starter_substance()
			var list := cargo()
			var p := Portion.new(s, 15.0, planet.ambient_temp)
			var merged := false
			for q in list:
				if q.substance == s:
					q.absorb(p)
					merged = true
			if not merged:
				list.append(p)
			msg = "+15 кг: " + s.name
		"repair":
			var n := 0
			if pneu != null:
				for b in pneu.burst_log:
					if not pneu.parts.has(b[1]) and not pneu.place(b[0], b[1], b[2], b[3]).is_empty():
						n += 1
				pneu.burst_log.clear()
				_last.placed = pneu.placed          # починка — не новая постройка
			msg = "Восстановлено деталей: %d" % n
		"survey":
			var n := 0
			for m in planet.materials:
				n += learn_tags(m)
			msg = "Новых тегов: %d" % n
	sound("fanfare", Vector2i.ZERO)
	log_event(Vector2i.ZERO, "Награда: %s — %s" % [Rewards.CARDS[id].n, msg])
	return msg

func learn(id: String) -> String:
	var err := Progression.learn(robot, id)
	if err == "":
		log_event(Vector2i.ZERO, "Изучено: " + SkillTree.node(id).n)
	return err

func main_role() -> String:
	var best := "gatherer"
	for c in SkillTree.CLASS_ORDER:
		if robot.xp[c] > robot.xp[best]:
			best = c
	return SkillTree.CLASSES[best].n

## Итоги рана: [подпись, значение].
func summary() -> Array:
	var r := robot
	return [
		["Планета", "%s — %s" % [planet.name, orig_goal.get("n", planet.goal.n)]],
		["Время", SaveGame.format_time(time)],
		["Этапы", "выполнены все" if goals.completed else "%d из %d" % [goals.stage, planet.goal.stages.size()]],
		["Добыто кристаллов", "%.0f кг" % mined],
		["Капсул в баки", "%d" % stats.hits],
		["Обработано порций", "%d" % processed],
		["Деталей поставлено", "%d" % built],
		["Известно тегов", "%d из %d" % [r.known_tags.size(), MaterialTags.TAGS.size()]],
		["Прокачка", "узлов %d, знаний осталось %d, чертежей %d из %d" % [r.learned.size(), r.knowledge, r.blueprints.size(), Modules.MODULES.size()]],
		["Событий пережито", "%d" % ev_count],
		["Главная роль робота", main_role()],
	]

# ---------------------------------------------------------------- совет «что дальше»

## Одна строка: что делать сейчас. glyph(actions) даёт подпись кнопки (клавиатура/геймпад).
func advise(glyph: Callable) -> String:
	if goals.completed:
		return "Цель выполнена! %s — меню: итоги и новая планета." % glyph.call([ProtoControls.MENU])
	if not goals.reward_pending.is_empty():
		return "Этап выполнен — выберите награду."
	if goals.choice_pending():
		return "Выберите путь для следующего этапа."
	if not ev.is_empty():
		if ev.id in ["meteors", "ring_debris"] and in_zone(robot_pos):
			return "Уйдите из красного круга — туда падают камни!"
		if ev.id == "flare" and ev.phase == "active" and not in_zone(robot_pos):
			return "Вспышка: в её круге бур работает вдвое быстрее."
	var st := goals.current()
	var drill: String = glyph.call([ProtoControls.WORK])
	var unload: String = glyph.call([&"cargo_unload"])
	var build: String = glyph.call([&"build_mode"])
	var cg := cargo_mass()
	match st.get("type", ""):
		"p_mine":
			return "Спуститесь в пещеру к друзам и бурите (%s)." % drill
		"p_parts":
			return "Стройка: %s — режим, деталь ставится перед роботом (%s)." % [build, glyph.call([&"build_place"])]
		"p_pressure":
			if pneu != null and net_pressure() < st.p * 0.7:
				return "Давления мало: поставьте ещё насос (%s — стройка) из прочного материала." % build
			return "Держите давление не ниже %.1f атм: насосы работают, детали целы." % st.p
	# Этапы завода: сначала сырьё, потом давление, потом место в баках.
	if pneu != null:
		var intake_kg := 0.0
		for c in pneu.parts:
			if pneu.parts[c].kind == "intake":
				intake_kg += pneu.mass_in(c)
		if intake_kg < 0.5 and cg < 0.5:
			return "Заводу нужно сырьё: выбурите кристаллы в пещере (%s)." % drill
		if intake_kg < 0.5:
			return "Отнесите груз к приёмнику и выгрузите (%s)." % unload
		if net_pressure() - planet.atm_pressure < ProtoPneumatics.MOVE_P:
			return "Капсулы стоят — нет давления. Поставьте насос у труб (%s — стройка)." % build
		var free := 0.0
		for c in pneu.parts:
			if pneu.parts[c].kind == "tank":
				free += ProtoPneumatics.KINDS.tank.cap - pneu.mass_in(c)
		if free < 2.0:
			return "Баки полны — поставьте ещё бак на выходе линии."
		if cg > 0.5:
			return "Выгрузите груз в приёмник (%s), завод всё переработает." % unload
	return "Завод работает. Пока он крутится — добудьте ещё кристаллов (%s)." % drill

# ---------------------------------------------------------------- сохранение

func to_dict() -> Dictionary:
	var r := robot
	return {"time": time, "mined": mined, "built": built, "processed": processed, "hits": stats.hits,
		"briefing": briefing_seen, "end_shown": end_shown,
		"robot": {"xp": r.xp.duplicate(), "knowledge": r.knowledge, "learned": r.learned.keys(),
			"blueprints": r.blueprints.keys(), "tags": r.known_tags.keys(), "bonus_slots": r.bonus_slots},
		"goals": {"stage": goals.stage, "hold": goals.hold, "progress": goals.progress, "completed": goals.completed,
			"choices": goals.choices.duplicate(), "reward": goals.reward_pending.duplicate(), "base_hits": goals.base_hits},
		"events": {"next": ev_next, "count": ev_count}, "stage_key": _base_key, "bases": _bases.duplicate()}

func from_dict(d: Dictionary) -> void:
	time = float(d.get("time", 0.0))
	mined = float(d.get("mined", 0.0))
	built = int(d.get("built", 0))
	processed = int(d.get("processed", 0))
	stats.hits = int(d.get("hits", 0))
	briefing_seen = bool(d.get("briefing", true))
	end_shown = bool(d.get("end_shown", false))
	var rd: Dictionary = d.get("robot", {})
	for c in rd.get("xp", {}):
		robot.xp[c] = float(rd.xp[c])
	robot.knowledge = int(rd.get("knowledge", robot.knowledge))
	for k in rd.get("learned", []):
		robot.learned[str(k)] = true
	for k in rd.get("blueprints", []):
		robot.blueprints[str(k)] = true
	for k in rd.get("tags", []):
		robot.known_tags[str(k)] = true
	robot.bonus_slots = int(rd.get("bonus_slots", 0))
	var g: Dictionary = d.get("goals", {})
	goals.stage = int(g.get("stage", 0))
	goals.hold = float(g.get("hold", 0.0))
	goals.progress = float(g.get("progress", 0.0))
	goals.completed = bool(g.get("completed", false))
	goals.choices = (g.get("choices", {}) as Dictionary).duplicate()
	goals.reward_pending = (g.get("reward", []) as Array).duplicate()
	goals.base_hits = int(g.get("base_hits", 0))
	var e: Dictionary = d.get("events", {})
	ev_next = float(e.get("next", ev_next))
	ev_count = int(e.get("count", 0))
	_base_key = str(d.get("stage_key", ""))
	_bases = (d.get("bases", {}) as Dictionary).duplicate()
	if not _bases.has("mined"):
		_base_key = ""
	resync()
