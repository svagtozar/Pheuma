class_name BalanceBot
extends RefCounted
## Бот для проверки баланса. Играет по правилам игрока: строит из материалов
## инвентаря, копает руками, ходит (время в пути идёт в симуляцию), изучает
## прокачку. Под каждый тип этапа цели строит настоящую установку и ждёт
## выполнения. Результат — время этапов или причина, почему не вышло.

const DT := 0.25
const STAGE_LIMIT := 900.0      # секунд симуляции на этап

var w: World
var notes: Array = []
var stages: Array = []          # {desc, ok, time, why}
var _stage_start := 0.0

func _init(world: World) -> void:
	w = world

func note(s: String) -> void:
	notes.append("[%.0fс] %s" % [w.time, s])

# ---------------------------------------------------------------- время и перемещение

func run(sec: float) -> void:
	for i in int(ceil(sec / DT)):
		w.tick(DT)

func center(c: Vector2i) -> Vector2:
	return Vector2(c) + Vector2(0.5, 0.5)

func travel(c: Vector2i) -> void:
	var d := w.robot.pos.distance_to(center(c))
	if d > 1.5:
		run(d / w.robot_speed())
		w.robot.pos = center(c) + Vector2(0, 1)

# ---------------------------------------------------------------- материалы

func is_free(c: Vector2i) -> bool:
	return w.planet.buildable(c) and not w.grid.has(c) and not w.planet.deposits.has(c) and not w.tile_overrides.has(c)

func minable(s: Substance) -> bool:
	return s.hardness <= w.robot.mining_hardness() + 0.5

func deposits_of(s: Substance, free_only: bool = false) -> Array:
	var out: Array = []
	for c in w.planet.deposits:
		if w.planet.deposits[c].sub == s.id and w.planet.deposits[c].amount > 1.0:
			if free_only and w.grid.has(c):
				continue
			out.append(c)
	out.sort_custom(func(a, b): return center(a).distance_to(w.robot.pos) < center(b).distance_to(w.robot.pos))
	return out

func mine_mass(s: Substance, mass: float) -> bool:
	if not minable(s) or s.phase_at(w.planet.ambient_temp) != Substance.Phase.SOLID:
		return false
	var guard := 0
	while w.robot.mass_of(s.id) < mass and guard < 400:
		guard += 1
		var deps := deposits_of(s, true)
		if deps.is_empty():
			return false
		travel(deps[0])
		w.robot.pos = center(deps[0]) + Vector2(0, 1)
		var err := w.mine(deps[0], 1.05)
		run(1.0)
		if err != "":
			return false
	return w.robot.mass_of(s.id) >= mass

## Подходящий материал для постройки (из инвентаря или накопать).
func material_for(kind: String, check: Callable = Callable()) -> Substance:
	var cost := w.build_cost(kind)
	var ok := func(s: Substance) -> bool:
		if Buildings.check_material(kind, s, w.planet.ambient_temp) != "":
			return false
		return check.is_null() or check.call(s)
	# Стартовый сплав держим на пусковую шахту и её насосы (им нужно держать 6+ атм),
	# если цель требует отправки на орбиту.
	var reserve := 0.0
	if kind != "launch_silo":
		for raw in w.planet.goal.stages:
			for st in Goals.options(raw):
				if st.type.begins_with("launch") and w.machines_of("launch_silo").is_empty():
					reserve = w.build_cost("launch_silo") + (0.0 if kind == "pump" else 3.0 * w.build_cost("pump"))
	for id in w.robot.inventory:
		var s: Substance = w.db.get_sub(id)
		var spare: float = w.robot.mass_of(id) - (reserve if s == w.starter else 0.0)
		if ok.call(s) and spare >= cost:
			return s
	var cands: Array = w.planet.materials.filter(func(s): return ok.call(s) and minable(s) and not deposits_of(s).is_empty())
	# Безопасные для рук — первыми, среди равных — ближайшие.
	cands.sort_custom(func(a, b):
		var sa := safe_to_handle(a)
		if sa != safe_to_handle(b):
			return sa
		return center(deposits_of(a)[0]).distance_to(w.robot.pos) < center(deposits_of(b)[0]).distance_to(w.robot.pos))
	for s in cands:
		if mine_mass(s, cost + w.robot.mass_of(s.id)):
			return s
	return null

func build(kind: String, c: Vector2i, facing: int, check: Callable = Callable()) -> Machine:
	# Вторая попытка — если материал потерялся в пути (летучее испаряется из рук).
	var err := ""
	for attempt in 2:
		var s := material_for(kind, check)
		if s == null:
			note("нет материала для «%s»" % Buildings.name_of(kind))
			return null
		travel(c)
		err = w.can_place(kind, c, s)
		if err == "":
			return w.place(kind, c, facing, s)
		if w.robot.mass_of(s.id) >= w.build_cost(kind):
			break
	note("не поставить «%s»: %s" % [Buildings.name_of(kind), err])
	return null

## Насосы к машине. need — какое давление насос должен реально держать
## (предел материала ×0.95); по умолчанию — целевое, но не выше 9 атм.
## Сначала свободные клетки рядом, потом клетки залежи без машин.
func pump_for(m: Machine, target_p: float, count: int = 1, need: float = -1.0) -> int:
	if need < 0.0:
		need = min(target_p, 9.0)
	var strong := func(s): return ComponentStats.compute("pump", s).max_p * 0.95 >= need
	var n := 0
	for pass_i in 2:
		for d in Machine.DIRS:
			if n >= count:
				return n
			var c: Vector2i = m.cell + d
			var two_outs: bool = m.info.has("process") and Processes.PROCESSES[m.info.process].outs == 2
			if c == m.out_cell(0) or (two_outs and c == m.out_cell(1)):
				continue
			var ok := is_free(c) if pass_i == 0 else (w.planet.buildable(c) and not w.grid.has(c) and not w.tile_overrides.has(c))
			if not ok:
				continue
			var p := build("pump", c, 0, strong)
			if p == null:
				p = build("pump", c, 0)
			if p != null:
				p.config.target_p = target_p
				n += 1
	return n

func learn_what_we_can() -> void:
	var changed := true
	while changed:
		changed = false
		for nd in SkillTree.NODES:
			if Progression.can_learn(w.robot, nd.id) == "":
				Progression.learn(w.robot, nd.id)
				note("изучено: %s" % nd.n)
				changed = true

# ---------------------------------------------------------------- установки

## Место у залежи: бур, затем путь машин по выходам (с поворотами для выхода 1).
## outs — выход каждой машины пути (последний элемент — конечная постройка).
func find_site(mat: Substance, outs: Array, splits: Array = []) -> Dictionary:
	while splits.size() < outs.size():
		splits.append(false)
	var deps := deposits_of(mat, true).slice(0, 30)
	deps.sort_custom(func(a, b): return w.planet.deposits[a].amount > w.planet.deposits[b].amount)
	for dep in deps:
		if w.grid.has(dep):
			continue
		for f in 4:
			var cells: Array = []
			var cur: Vector2i = dep
			var dir := f
			var ok := true
			var dumps: Array = []
			for k in outs.size():
				var nd: int = (dir + (outs[k - 1] if k > 0 else 0)) % 4
				# У разделяющей машины второй выход — под сброс.
				if k > 0 and splits[k - 1]:
					var other: Vector2i = cur + Machine.DIRS[(dir + (1 - outs[k - 1])) % 4]
					if not is_free(other) or other in cells.map(func(e): return e[0]):
						ok = false
						break
					dumps.append(other)
				cur = cur + Machine.DIRS[nd]
				dir = nd
				if not is_free(cur) or cur in cells.map(func(e): return e[0]) or cur in dumps:
					ok = false
					break
				cells.append([cur, dir])
			if ok:
				return {"dep": dep, "facing": f, "cells": cells, "dumps": dumps}
	return {}

## Построить установку по плану; sink — вид конечной постройки или [вид, проверка материала].
func build_chain(pl: Dictionary, sink) -> Machine:
	var steps: Array = pl.steps
	var outs: Array = steps.map(func(st): return st.out) + [0]
	var splits: Array = steps.map(func(st): return st.op == "process" and Processes.PROCESSES[st.pid].outs == 2) + [false]
	var site := find_site(pl.mat, outs, splits)
	if site.is_empty():
		note("нет места для установки у залежи %s" % pl.mat.name)
		return null
	var drill := build("drill", site.dep, site.facing, func(s): return s.hardness + 0.5 >= pl.mat.hardness)
	if drill == null:
		return null
	for i in steps.size():
		var st: Dictionary = steps[i]
		var e: Array = site.cells[i]
		var fac: int = site.cells[i + 1][1] if st.out == 0 else (site.cells[i + 1][1] + 3) % 4
		var chk := Callable()
		if st.has("source"):
			var src: Substance = st.source
			# Облучатель лучше строить прямо из радиоактивного материала — тогда источник вечный.
			if Buildings.check_material(st.kind, src, w.planet.ambient_temp) == "":
				mine_mass(src, w.build_cost(st.kind) + 1.0)
				chk = func(s): return s.has("radioactive")
		var m := build(st.kind, e[0], fac, chk)
		if m == null and not chk.is_null():
			m = build(st.kind, e[0], fac)
		if m == null:
			return null
		if st.op == "treat":
			_feeders.append([st.reagent, m])
		elif st.has("source") and not m.built_from.has("radioactive"):
			_feeders.append([st.source, m])
		var gmin: float = Processes.PROCESSES[st.pid].get("gas_min", 0.0) if st.op == "process" else 0.0
		if gmin > 0.0:
			pump_for(m, 10.0 if st.pid == "compressor" else gmin + 1.5, 2 if st.pid == "compressor" else 1)
	for dc in site.dumps:
		build("container", dc, 0)
	var se: Array = site.cells[steps.size()]
	# Летучее, жидкое и газ — только в закрытый бак, иначе улетит из контейнера.
	if sink is String and sink == "container" and pl.has("final"):
		var fp: Portion = pl.final
		var amb_phase: int = fp.substance.phase_at(w.planet.ambient_temp)
		if amb_phase != Substance.Phase.SOLID or fp.has("volatile") or fp.has("antigravitic"):
			sink = "tank"
	var sk: String = sink if sink is String else sink[0]
	var chk2: Callable = Callable() if sink is String else sink[1]
	var cargo: Substance = pl.final.substance if pl.has("final") else pl.mat
	if chk2.is_null() and sk != "launch_silo":
		chk2 = sink_check(cargo)
	var snk := build(sk, se[0], se[1], chk2)
	if snk == null and not chk2.is_null() and sink is String:
		snk = build(sk, se[0], se[1])
	if snk == null:
		return null
	if sk == "launch_silo":
		pump_for(snk, 9.5, 3, 6.5)
	note("установка: %s → %s" % [Planner.describe(pl), snk.display_name()])
	_chains.append({"pl": pl, "sink": sink, "drill": drill, "gen": _chain_gen, "done": false})
	return snk

## Установки: план, конечная постройка, бур. Когда залежь бура кончилась —
## цепочка переносится на другую залежь того же материала (не больше двух переносов).
var _chains: Array = []
var _chain_gen := 0

func _relocate_exhausted() -> void:
	for ch in _chains.duplicate():
		var d: Machine = ch.drill
		if ch.done or ch.gen >= 2 or not w.machines.has(d.id) or d.status != "залежь пуста":
			continue
		if deposits_of(ch.pl.mat, true).is_empty():
			continue
		ch.done = true
		note("залежь кончилась у %d,%d — переношу установку" % [d.cell.x, d.cell.y])
		_chain_gen = ch.gen + 1
		build_chain(ch.pl, ch.sink)
		_chain_gen = 0

## Материал не портит хранилища и не горит в руках робота.
func safe_to_handle(s: Substance) -> bool:
	return Handling.safe_to_carry(s, w.planet, w.robot.passive("safe_fire") > 0.0)

## Кислотный груз разъедает хранилище — нужен стойкий материал стенок.
func sink_check(cargo: Substance) -> Callable:
	if cargo == null or not cargo.has("acidic"):
		return Callable()
	return func(s): return Handling.CORROSION_PROOF.any(func(t): return s.has(t))

## Установка, которая производит материал с тегом в конечную постройку.
func produce(tag: String, sink = "container") -> Machine:
	var mats: Array = w.planet.materials.filter(func(s): return not deposits_of(s).is_empty())
	learn_what_we_can()
	# Сначала — из безопасного сырья: кислота разъедает хранилища, а самовозгорающееся
	# горит в руках. Если так не выходит — из любого.
	var pl := Planner.plan(w, tag, mats.filter(func(s): return safe_to_handle(s)))
	if pl.is_empty():
		pl = Planner.plan(w, tag, mats)
	if pl.is_empty():
		note("планировщик: «%s» не получить из материалов планеты" % MaterialTags.display(tag))
		return null
	note("план для «%s»: %s" % [MaterialTags.display(tag), Planner.describe(pl)])
	for k in pl.locked:
		if not unlock(k):
			note("не открыть «%s»" % Buildings.name_of(k))
			return null
	for st in pl.steps:
		var rg: Substance = st.get("reagent", st.get("source"))
		if rg != null and not mine_mass(rg, 12.0):
			note("не добыть реагент %s" % rg.name)
			return null
	return build_chain(pl, sink)

var _feeders: Array = []   # [реагент, машина] — подкладывать в боковой вход

## Подкладывать реагенты в машины и топливо в печь купола, пока идёт ожидание.
var _stall := {}    # id машины → [с какого времени не хватает давления, сколько насосов добавлено]

func maintain() -> void:
	for m in w.machines.values():
		var starving: bool = m.status.begins_with("мало давления") or (m.kind == "launch_silo" and not m.items.is_empty() and w.gas.pressure(m.id) < 6.0)
		if not starving:
			_stall.erase(m.id)
			continue
		var e: Array = _stall.get(m.id, [w.time, 0])
		_stall[m.id] = e
		if w.time - e[0] > 60.0 and e[1] < 3:
			e[0] = w.time
			e[1] += 1
			var silo: bool = m.kind == "launch_silo"
			if pump_for(m, 9.5 if silo else 3.0, 1, 6.5 if silo else 2.5) > 0:
				note("добавлен насос к «%s»" % m.display_name())
	# Приёмник на выходе разрушен (событие, кислота) — ставим новый.
	for m in w.machines.values():
		if m.out_queue.is_empty():
			continue
		var oc: Vector2i = m.out_cell(int(m.out_queue[0][1]))
		if w.machine_at(oc) != null or not w.planet.buildable(oc) or _rebuilt.get(oc, 0) >= 2:
			continue
		_rebuilt[oc] = _rebuilt.get(oc, 0) + 1
		var cargo: Portion = m.out_queue[0][0]
		var sealed_needed: bool = cargo.has("volatile") or cargo.phase() != Substance.Phase.SOLID
		var kind := "tank" if sealed_needed else "container"
		var chk := sink_check(cargo.substance)
		var rebuilt := build(kind, oc, m.facing, chk)
		if rebuilt == null and not chk.is_null():
			rebuilt = build(kind, oc, m.facing)
		if rebuilt != null:
			note("восстановлен приёмник у «%s»" % m.display_name())
	_relocate_exhausted()
	_maintain_feed()

var _rebuilt := {}

func _maintain_feed() -> void:
	if not _feed.is_empty() and w.machines.has(_feed[1].id) and _feed[1].items.is_empty():
		var fs: Substance = _feed[0]
		if w.robot.mass_of(fs.id) < 2.0:
			mine_mass(fs, 12.0)
		travel(_feed[1].cell)
		w.robot.selected = fs.id
		w.insert_into(_feed[1].cell, false, min(6.0, w.robot.mass_of(fs.id)))
	for pair in _feeders:
		var rg: Substance = pair[0]
		var m: Machine = pair[1]
		if not w.machines.has(m.id):
			continue
		if m.reagent == null or m.reagent.mass < 2.0:
			if w.robot.mass_of(rg.id) < 3.0:
				mine_mass(rg, 10.0)
			if w.robot.mass_of(rg.id) < 0.5:
				continue
			travel(m.cell)
			w.robot.selected = rg.id
			w.insert_into(m.cell, true, min(5.0, w.robot.mass_of(rg.id)))

# ---------------------------------------------------------------- прокачка

const UNLOCK_LIMIT := 900.0

func node_unlocking(kind: String) -> String:
	for nd in SkillTree.NODES:
		if kind in nd.get("unlock", []):
			return nd.id
	return ""

## Открыть постройку: изучить узел (и предыдущие), набрав опыт класса и знания.
func unlock(kind: String) -> bool:
	if w.robot.unlocked.has(kind):
		return true
	var id := node_unlocking(kind)
	if id == "":
		return false
	var chain: Array = []
	var cur := id
	while cur != "":
		chain.push_front(cur)
		cur = SkillTree.prev_of(cur)
	var t0 := w.time
	for nid in chain:
		if w.robot.learned.has(nid):
			continue
		var nd := SkillTree.node(nid)
		while Progression.can_learn(w.robot, nid) != "":
			if w.time - t0 > UNLOCK_LIMIT:
				note("не хватило времени на узел «%s»: %s" % [nd.n, Progression.can_learn(w.robot, nid)])
				return false
			if w.robot.xp[nd.cls] < nd.xp:
				if not farm_xp(nd.cls):
					note("не набрать опыт «%s»" % SkillTree.CLASSES[nd.cls].n)
					return false
			elif w.robot.knowledge < nd.cost:
				if not farm_knowledge():
					note("не набрать знаний")
					return false
		Progression.learn(w.robot, nid)
		note("изучено ради «%s»: %s" % [Buildings.name_of(kind), nd.n])
	return w.robot.unlocked.has(kind)

var _farm := {}

## Один «подход» к набору опыта класса. false — если способа нет.
func farm_xp(cls: String) -> bool:
	var soft: Array = w.planet.materials.filter(func(s): return minable(s) and s.phase_at(w.planet.ambient_temp) == Substance.Phase.SOLID and not deposits_of(s).is_empty())
	match cls:
		"gatherer":
			return not soft.is_empty() and mine_mass(soft[0], w.robot.mass_of(soft[0].id) + 5.0)
		"crafter", "chief":
			var kind := "container" if cls == "crafter" else "sensor"
			var c := _free_near(w.planet.spawn)
			for i in 5:
				var m := build(kind, c, 0)
				if m == null:
					return false
				w.remove_at(c)
			return true
		"firekeeper":
			if not _farm.has("furnace") or not w.machines.has(_farm.furnace.id):
				var c := _free_near(w.planet.spawn)
				var f := build("furnace", c, 0)
				if f == null:
					return false
				pump_for(f, 2.5, 1)
				_farm.furnace = f
				build("container", c + Vector2i(1, 0), 0)
			if soft.is_empty():
				return false
			var fu: Machine = _farm.furnace
			mine_mass(soft[0], 6.0)
			travel(fu.cell)
			w.robot.selected = soft[0].id
			w.insert_into(fu.cell, false, min(6.0, w.robot.mass_of(soft[0].id)))
			run(12.0)
			return true
		"shaman":
			return farm_knowledge()
		"hunter":
			if not w.robot.has_module("hook"):
				if not w.robot.blueprints.has("hook"):
					return false
				var fab = w.machines_of("fabricator")
				if fab.is_empty():
					var fb := build("fabricator", _free_near(w.planet.spawn), 0)
					if fb == null:
						return false
					fab = [fb]
				travel(fab[0].cell)
				if w.fabricate("hook", w.starter) != "":
					var s2 := material_for("fabricator")
					if s2 == null or w.fabricate("hook", s2) != "":
						return false
				w.robot.equip(w.robot.modules[-1].uid)
			for i in 5:
				while w.robot.tank < 1.0:
					w.refill_robot(1.0)
					run(1.0)
				var dst := w.robot.cell() + Vector2i(3, 0)
				if not w.walkable(dst):
					dst = w.robot.cell() - Vector2i(3, 0)
				Abilities.use(w, "hook", center(dst))
				run(1.1)
			return true
	return false

## Знания: анализ новых материалов, первые постройки новых видов, открытия в машинах.
func farm_knowledge() -> bool:
	var k0 := w.robot.knowledge
	for s in w.planet.materials:
		if not w.is_analyzed(s) and not deposits_of(s).is_empty():
			travel(deposits_of(s)[0])
			w.analyze(s)
			if w.robot.knowledge > k0 + 1:
				return true
	for k in Buildings.KINDS:
		if w.robot.unlocked.has(k) and not w.built_kinds.has(k) and Buildings.KINDS[k].cat in [0, 1, 2, 3] and k != "drill":
			var c := _free_near(w.planet.spawn)
			var m := build(k, c, 0)
			if m != null:
				w.remove_at(c)
				return true
	var before := w.robot.knowledge
	_experiment()
	return w.robot.knowledge > before or w.robot.knowledge > k0

## Прогнать образцы через машины и обработчик ради новых тегов и взаимодействий.
## Лаборатория строится один раз; перепробованные пары запоминаются.
## Возвращает false, когда пробовать больше нечего.
var _lab_machines := {}
var _tried := {}

func _experiment(max_tries: int = 8) -> bool:
	if not _farm.has("lab"):
		_lab()
		_farm.lab = true
	var pids: Array = []
	for pid in Processes.PROCESSES:
		if pid in ["filter", "magnet_sep", "irradiator"]:
			continue
		if w.robot.unlocked.has(Planner.kind_of(pid)):
			pids.append(pid)
	pids.sort()
	var tries := 0
	for pid in pids:
		if not _lab_machines.has(pid) or not w.machines.has(_lab_machines[pid].id):
			var c := _free_near(w.planet.spawn)
			var m := build(Planner.kind_of(pid), c, 0)
			if m == null:
				continue
			build("container", c + Vector2i(1, 0), 0)
			if Processes.PROCESSES[pid].get("gas_min", 0.0) > 0.0:
				pump_for(m, 10.0 if pid == "compressor" else 3.0, 1)
			_lab_machines[pid] = m
		var lm: Machine = _lab_machines[pid]
		var samples: Array = w.robot.inventory.keys().filter(func(id): return w.robot.mass_of(id) >= 1.0)
		samples.sort()
		for id in samples:
			if pid == "treater":
				for id2 in samples:
					var key := "%s:%s:%s" % [pid, id2, id]
					if id2 == id or _tried.has(key) or w.robot.mass_of(id2) < 1.0 or w.robot.mass_of(id) < 1.0:
						continue
					_tried[key] = true
					var ir := Interactions.apply(w.db.get_sub(id2).tags, w.db.get_sub(id).tags)
					if ir.keys.is_empty():
						continue
					travel(lm.cell)
					if lm.reagent != null:
						w.robot.add_item(lm.reagent)
						lm.reagent = null
					w.robot.selected = id2
					w.insert_into(lm.cell, true, 1.0)
					w.robot.selected = id
					w.insert_into(lm.cell, false, 1.0)
					run(4.0)
					tries += 1
					if tries >= max_tries:
						return true
			else:
				var key := "%s:%s" % [pid, id]
				if _tried.has(key):
					continue
				_tried[key] = true
				travel(lm.cell)
				w.robot.selected = id
				w.insert_into(lm.cell, false, 1.0)
				run(Processes.PROCESSES[pid].dur + 1.0)
				tries += 1
				if tries >= max_tries:
					return true
	# Продукты лаборатории — тоже образцы.
	for pid in _lab_machines:
		var lm: Machine = _lab_machines[pid]
		var out = w.machine_at(lm.cell + Vector2i(1, 0))
		if out != null and not out.items.is_empty():
			travel(out.cell)
			w.take_from(out.cell)
			tries += 1
	return tries > 0

func wait_until(cond: Callable, limit: float) -> bool:
	var t0 := w.time
	while w.time - t0 < limit:
		if cond.call():
			return true
		run(5.0)
		maintain()
		learn_what_we_can()
	return cond.call()

# ---------------------------------------------------------------- этапы

func play() -> void:
	learn_what_we_can()
	var goal: Dictionary = w.planet.goal
	for i in goal.stages.size():
		_take_reward()
		if w.goals.choice_pending():
			var alts: Array = w.goals.raw_stage(i).alt
			var pick := 0
			for k in alts.size():
				if PREFER.find(alts[k].type) < PREFER.find(alts[pick].type):
					pick = k
			w.goals.choose(pick)
			note("выбран путь: %s" % alts[pick].desc)
		var st: Dictionary = w.goals.current()
		_stage_start = w.time
		var why := do_stage(st)
		var ok: bool = w.goals.stage > i or w.goals.completed
		if not ok and why == "":
			ok = wait_until(func(): return w.goals.stage > i or w.goals.completed, STAGE_LIMIT - (w.time - _stage_start))
			if not ok:
				why = "не успел за %.0f мин (прогресс %d%%)" % [STAGE_LIMIT / 60.0, int(w.goals.progress * 100)]
				for m in w.machines.values():
					if m.kind in ["pump", "pipe", "sensor", "gate_not", "fabricator"]:
						continue
					note("  %s %d,%d: %s, груз %.1f кг%s" % [m.display_name(), m.cell.x, m.cell.y, m.status if m.status != "" else "—", m.total_mass(),
						", реагент %.1f" % m.reagent.mass if m is Processor and m.reagent != null else ""])
		stages.append({"desc": st.desc, "ok": ok, "time": w.time - _stage_start, "why": why})
		if not ok:
			return
	_take_reward()

## Какие типы этапов бот выбирает охотнее (раньше в списке — лучше).
const PREFER := ["stockpile_tags", "launch_mass", "launch_tag", "build_count", "discover_tags", "stockpile_mass",
	"machines_working", "deliveries", "beacon_hold", "discover_exotic", "launch_exotic", "discover_interactions",
	"sensor_network", "dome_env", "phasing_contained"]
const REWARD_PREFER := ["supply", "slot", "knowledge", "blueprint", "repair", "survey"]

func _take_reward() -> void:
	var offer: Array = w.goals.reward_pending
	if offer.is_empty():
		return
	for id in REWARD_PREFER:
		if id in offer:
			note("награда: %s — %s" % [Rewards.CARDS[id].n, w.goals.take_reward(id)])
			return

func do_stage(st: Dictionary) -> String:
	match st.type:
		"build_count":
			var n := 0
			for c in w.planet.deposits.keys():
				if w.machines_of(st.kind).size() >= st.n:
					break
				var s: Substance = w.db.get_sub(w.planet.deposits[c].sub)
				if st.kind == "drill" and not w.grid.has(c):
					if build("drill", c, 0, func(m): return m.hardness + 0.5 >= s.hardness) != null:
						n += 1
			if st.kind == "beacon":
				return _beacon(0.0)
			return ""
		"stockpile_tags":
			for t in st.tags:
				if w.stored_with_tag(t) < st.tags[t]:
					if produce(t) == null:
						return "не получить «%s»" % MaterialTags.display(t)
			return ""
		"launch_mass":
			var any: Array = w.planet.materials.filter(func(s): return minable(s) and s.phase_at(w.planet.ambient_temp) == Substance.Phase.SOLID and not deposits_of(s).is_empty())
			if any.is_empty():
				return "нечего добывать для отправки"
			return "" if build_chain({"mat": any[0], "steps": [], "locked": []}, "launch_silo") != null else "не построить шахту"
		"launch_tag":
			return "" if produce(st.tag, "launch_silo") != null else "не получить «%s» для отправки" % MaterialTags.display(st.tag)
		"launch_exotic":
			for t in MaterialTags.exotic_tags():
				if produce(t, "launch_silo") != null:
					return ""
			return "не получить ни одного невозможного тега"
		"discover_tags", "discover_exotic", "discover_interactions":
			return _discover(st)
		"sensor_network":
			return _sensors(st.n)
		"stockpile_mass":
			# Уже лежащее + новые линии «бур → контейнер» с запасом: старые линии
			# могли остановиться (залежь кончилась), на их свободное место не рассчитываем.
			var have := 0.0
			for m in w.machines.values():
				if m.is_storage():
					have += m.total_mass()
			var cap := have
			var any := _soft_materials()
			var guard := 0
			while cap < st.mass * 1.3 and guard < 8 and not any.is_empty():
				guard += 1
				var snk := build_chain({"mat": any[guard % any.size()], "steps": [], "locked": []}, "container")
				if snk == null:
					break
				cap += snk.capacity()
			return "" if cap >= st.mass else "не хватило места под запас"
		"machines_working":
			# Буры новых линий ждут выключенными, пока не готовы все линии, — иначе первые
			# контейнеры переполнятся раньше, чем заработает последняя печь.
			var any := _soft_materials()
			var n := 0
			var drills: Array = []
			for i in st.n + 3:
				if n >= st.n or any.is_empty():
					break
				var before := {}
				for id in w.machines:
					before[id] = true
				var pl := {"mat": any[i % any.size()], "steps": [{"op": "process", "pid": "furnace", "kind": "furnace", "out": 0}], "locked": []}
				if build_chain(pl, "container") != null:
					n += 1
				for m in w.machines.values():
					if m.kind == "drill" and not before.has(m.id):
						m.manual_off = true
						drills.append(m)
			for d in drills:
				d.manual_off = false
			return "" if n >= st.n else "не поставить %d линий обработки" % st.n
		"deliveries":
			return _deliveries()
		"dome_env":
			return _dome(st)
		"beacon_hold":
			return _beacon(st.pressure)
		"phasing_contained":
			var anch := produce("anchoring")
			if anch == null:
				return "не получить якорный материал"
			if not wait_until(func(): return anch.total_mass() >= 9.0, 400.0):
				return "якорный материал не накопился"
			travel(anch.cell)
			w.take_from(anch.cell)
			var chk := func(s): return s.has("anchoring")
			return "" if produce("phasing", ["tank", chk]) != null else "не получить фазирующее или бак из якорного"
	return "бот не умеет этап «%s»" % st.type

func _soft_materials() -> Array:
	return w.planet.materials.filter(func(s): return minable(s) and s.phase_at(w.planet.ambient_temp) == Substance.Phase.SOLID and not deposits_of(s, true).is_empty())

## Бур → пушка (+насос) ~~> приёмник → контейнер.
func _deliveries() -> String:
	var any := _soft_materials()
	if any.is_empty():
		return "нечего возить"
	for s in any:
		for dep in deposits_of(s, true).slice(0, 20):
			for f in 4:
				var d: Vector2i = Machine.DIRS[f]
				var ok := true
				for k in [1, 5, 6]:
					if not is_free(dep + d * k):
						ok = false
				var pc: Vector2i = dep + d + Machine.DIRS[(f + 1) % 4]
				if not ok or not is_free(pc):
					continue
				if build("drill", dep, f, func(m): return m.hardness + 0.5 >= s.hardness) == null:
					return "не поставить бур"
				var cannon := build("cannon", dep + d, f)
				var recv := build("receiver", dep + d * 5, f)
				var box := build("container", dep + d * 6, f)
				if cannon == null or recv == null or box == null:
					return "не собрать пушечную линию"
				var p := build("pump", pc, 0)
				if p != null:
					p.config.target_p = 5.0
				w.link_cannon(cannon.cell, recv.cell)
				note("пушечная линия %d,%d → %d,%d" % [cannon.cell.x, cannon.cell.y, recv.cell.x, recv.cell.y])
				return ""
	return "нет места под пушечную линию"

func _free_near(c: Vector2i) -> Vector2i:
	for r in range(2, 30):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var q := c + Vector2i(dx, dy)
				if is_free(q) and is_free(q + Vector2i(1, 0)) and is_free(q + Vector2i(0, 1)) and is_free(q + Vector2i(1, 1)) and is_free(q + Vector2i(-1, 0)) and is_free(q + Vector2i(0, -1)):
					return q
	return c

func _lab() -> void:
	# Образцы всех добываемых материалов и анализ.
	for s in w.planet.materials:
		if not deposits_of(s).is_empty():
			travel(deposits_of(s)[0])
			w.analyze(s)
			if minable(s):
				mine_mass(s, 3.0)
	learn_what_we_can()

func _discover(st: Dictionary) -> String:
	var idx: int = w.planet.goal.stages.find(st)
	var done := func() -> bool: return w.goals.stage > idx or w.goals.completed
	var t0 := w.time
	_lab()
	while not done.call() and w.time - t0 < STAGE_LIMIT:
		learn_what_we_can()
		if not _experiment():
			# Идеи кончились — попробуем открыть новую машину и продолжить.
			var opened := false
			for k in ["distiller", "electrolyzer", "compressor", "sinter", "loom", "centrifuge", "decompressor"]:
				if not w.robot.unlocked.has(k) and unlock(k):
					opened = true
					break
			if not opened:
				break
		run(5.0)
	return "" if done.call() else "кончились идеи для открытий (тегов %d, взаимодействий %d)" % [w.robot.known_tags.size(), w.robot.known_interactions.size()]

func _sensors(n: int) -> String:
	var c := _free_near(w.planet.spawn)
	var valve := build("valve", c, 0)
	if valve == null:
		return "не поставить клапан"
	for i in n:
		var sc := _free_near(c)
		var s := build("sensor", sc, 0)
		if s == null:
			return "не поставить датчик"
		var wire_sub: Substance = w.db.get_sub(w.robot.selected) if w.robot.selected != "" else w.starter
		var err := w.add_wire(sc, c, 0, wire_sub)
		if err != "":
			return "провод: " + err
	return ""

func _dome(st: Dictionary) -> String:
	var c := _free_near(w.planet.spawn)
	var dome := build("dome", c, 0, func(s): return s.has("insulating")) if not w.planet.materials.filter(func(s): return s.has("insulating")).is_empty() else null
	if dome == null:
		dome = build("dome", c, 0)
	if dome == null:
		return "не построить купол"
	var target_p: float = clamp(1.1, st.p[0] + 0.1, st.p[1] - 0.1)
	if w.planet.atm_pressure < st.p[0]:
		pump_for(dome, target_p, 1)
	elif w.planet.atm_pressure > st.p[1]:
		# Плотная атмосфера: насос в режиме откачки.
		for d in Machine.DIRS:
			if is_free(dome.cell + d):
				var pm := build("pump", dome.cell + d, 0)
				if pm != null:
					pm.config.reverse = true
					pm.config.target_p = target_p
				break
	var amb := w.planet.ambient_temp
	if amb >= st.t[0] and amb <= st.t[1]:
		return ""
	var heat: bool = amb < st.t[0]
	var kind := "furnace" if heat else "condenser"
	# Бур → печь/конденсатор → купол, датчик T на куполе управляет машиной через НЕ.
	var any: Array = w.planet.materials.filter(func(s): return minable(s) and s.phase_at(amb) == Substance.Phase.SOLID and not deposits_of(s).is_empty())
	if any.is_empty():
		return "нечем кормить печь купола"
	var fm := build(kind, Vector2i(c.x - 1, c.y), 0)
	if fm == null:
		return "не поставить %s у купола" % Buildings.name_of(kind)
	if heat:
		pump_for(fm, clamp(1.3, 1.25, st.p[1] - 0.05), 1)
	var sensor := build("sensor", Vector2i(c.x, c.y - 1), 1)
	if sensor != null:
		sensor.config.mode = "temp"
		sensor.config.threshold = (st.t[0] + st.t[1]) / 2.0
		if heat:
			var inv := build("gate_not", Vector2i(c.x - 1, c.y - 1), 0)
			if inv != null:
				w.add_wire(sensor.cell, inv.cell, 0, w.starter)
				w.add_wire(inv.cell, fm.cell, 0, w.starter)
		else:
			w.add_wire(sensor.cell, fm.cell, 0, w.starter)
	# Кормим машину: бур на ближайшей залежи далеко — носим руками.
	var feed: Substance = any[0]
	_feed = [feed, fm]
	return ""

var _feed: Array = []

func _beacon(pressure: float) -> String:
	var need := func(s: Substance) -> bool: return s.has("conductive") or s.has("crystalline")
	var sub := material_for("beacon", need)
	if sub == null:
		var src := produce("crystalline")
		if src == null:
			src = produce("conductive")
		if src == null or not wait_until(func(): return src.total_mass() >= 16.0, 400.0):
			return "нет материала для маяка"
		travel(src.cell)
		w.take_from(src.cell)
	var c := _free_near(w.planet.spawn)
	var b := build("beacon", c, 0, need)
	if b == null:
		return "не построить маяк"
	if pressure > 0.0:
		if b.stats.max_p < pressure + 0.3:
			return "материал маяка держит только %.1f атм" % b.stats.max_p
		pump_for(b, min(pressure + 0.5, b.stats.max_p * 0.9), 2)
	return ""
