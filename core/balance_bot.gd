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

func deposits_of(s: Substance) -> Array:
	var out: Array = []
	for c in w.planet.deposits:
		if w.planet.deposits[c].sub == s.id and w.planet.deposits[c].amount > 1.0:
			out.append(c)
	out.sort_custom(func(a, b): return center(a).distance_to(w.robot.pos) < center(b).distance_to(w.robot.pos))
	return out

func mine_mass(s: Substance, mass: float) -> bool:
	if not minable(s) or s.phase_at(w.planet.ambient_temp) != Substance.Phase.SOLID:
		return false
	var guard := 0
	while w.robot.mass_of(s.id) < mass and guard < 400:
		guard += 1
		var deps := deposits_of(s)
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
	for id in w.robot.inventory:
		var s: Substance = w.db.get_sub(id)
		if ok.call(s) and w.robot.mass_of(id) >= cost:
			return s
	var cands: Array = w.planet.materials.filter(func(s): return ok.call(s) and minable(s) and not deposits_of(s).is_empty())
	cands.sort_custom(func(a, b): return center(deposits_of(a)[0]).distance_to(w.robot.pos) < center(deposits_of(b)[0]).distance_to(w.robot.pos))
	for s in cands:
		if mine_mass(s, cost + w.robot.mass_of(s.id)):
			return s
	return null

func build(kind: String, c: Vector2i, facing: int, check: Callable = Callable()) -> Machine:
	var s := material_for(kind, check)
	if s == null:
		note("нет материала для «%s»" % Buildings.name_of(kind))
		return null
	travel(c)
	var err := w.can_place(kind, c, s)
	if err != "":
		note("не поставить «%s»: %s" % [Buildings.name_of(kind), err])
		return null
	return w.place(kind, c, facing, s)

func pump_for(m: Machine, target_p: float, count: int = 1) -> int:
	var n := 0
	for d in Machine.DIRS:
		if n >= count:
			break
		var c: Vector2i = m.cell + d
		if not is_free(c) or c == m.out_cell(0) or (m.info.has("process") and c == m.out_cell(1)):
			continue
		var p := build("pump", c, 0)
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
func find_site(mat: Substance, outs: Array) -> Dictionary:
	for dep in deposits_of(mat).slice(0, 25):
		for f in 4:
			var cells: Array = []
			var cur: Vector2i = dep
			var dir := f
			var ok := true
			for k in outs.size():
				var nd: int = (dir + (outs[k - 1] if k > 0 else 0)) % 4
				cur = cur + Machine.DIRS[nd]
				dir = nd
				if not is_free(cur) or cur in cells:
					ok = false
					break
				cells.append([cur, dir])
			if ok:
				return {"dep": dep, "facing": f, "cells": cells}
	return {}

## Построить установку по плану; sink — вид постройки на конце ("container",
## "launch_silo") или [вид, проверка материала].
func build_chain(pl: Dictionary, sink) -> Machine:
	var procs: Array = pl.get("procs", [])
	if pl.kind == "treat":
		procs = ["treater"]
	var outs: Array = pl.get("out", [])
	if outs.size() < procs.size():
		outs = procs.map(func(_p): return 0)
	outs = outs + [0]
	var site := find_site(pl.mat, outs)
	if site.is_empty():
		note("нет места для установки у залежи %s" % pl.mat.name)
		return null
	var drill := build("drill", site.dep, site.facing, func(s): return s.hardness + 0.5 >= pl.mat.hardness)
	if drill == null:
		return null
	var last: Machine = null
	for i in procs.size():
		var e: Array = site.cells[i]
		var kind: String = procs[i] if procs[i] != "treater" else "treater"
		for k in Buildings.KINDS:
			if Buildings.KINDS[k].get("process", "") == procs[i]:
				kind = k
		var fac: int = site.cells[i + 1][1] if outs[i] == 0 else (site.cells[i + 1][1] + 3) % 4
		var m := build(kind, e[0], fac)
		if m == null:
			return null
		var gmin: float = Processes.PROCESSES[procs[i]].get("gas_min", 0.0)
		if gmin > 0.0:
			pump_for(m, 10.0 if procs[i] == "compressor" else gmin + 1.5, 2 if procs[i] == "compressor" else 1)
		last = m
	var se: Array = site.cells[procs.size()]
	var sk: String = sink if sink is String else sink[0]
	var chk: Callable = Callable() if sink is String else sink[1]
	var snk := build(sk, se[0], se[1], chk)
	if snk == null:
		return null
	if sk == "launch_silo":
		pump_for(snk, 9.5, 3)
	note("установка: %s → %s" % [Planner.describe(pl), snk.display_name()])
	return snk

## Произвести mass кг материала с тегом в контейнер (и при нужде забрать в инвентарь).
func produce(tag: String, sink = "container") -> Machine:
	var mats: Array = w.planet.materials.filter(func(s): return not deposits_of(s).is_empty())
	var pl := Planner.plan(w, tag, mats)
	if pl.is_empty():
		learn_what_we_can()
		pl = Planner.plan(w, tag, mats)
	if pl.is_empty():
		note("не нашёл способа получить «%s»" % MaterialTags.display(tag))
		return null
	if pl.kind == "treat" and not mine_mass(pl.reagent, 15.0):
		note("не добыть реагент %s" % pl.reagent.name)
		return null
	var snk := build_chain(pl, sink)
	if snk != null and pl.kind == "treat":
		_treaters.append([pl.reagent, snk])
	return snk

var _treaters: Array = []

## Подкладывать реагент в обработчики и топливо в печь купола, пока идёт ожидание.
func maintain() -> void:
	if not _feed.is_empty() and w.machines.has(_feed[1].id) and _feed[1].items.is_empty():
		var fs: Substance = _feed[0]
		if w.robot.mass_of(fs.id) < 2.0:
			mine_mass(fs, 12.0)
		travel(_feed[1].cell)
		w.robot.selected = fs.id
		w.insert_into(_feed[1].cell, false, min(6.0, w.robot.mass_of(fs.id)))
	for pair in _treaters:
		var rg: Substance = pair[0]
		for m in w.machines_of("treater"):
			if m.reagent == null or m.reagent.mass < 2.0:
				if w.robot.mass_of(rg.id) < 3.0:
					mine_mass(rg, 10.0)
				travel(m.cell)
				w.robot.selected = rg.id
				w.insert_into(m.cell, true, min(5.0, w.robot.mass_of(rg.id)))

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
		var st: Dictionary = goal.stages[i]
		_stage_start = w.time
		var why := do_stage(st)
		var ok: bool = w.goals.stage > i or w.goals.completed
		if not ok and why == "":
			ok = wait_until(func(): return w.goals.stage > i or w.goals.completed, STAGE_LIMIT - (w.time - _stage_start))
			if not ok:
				why = "не успел за %.0f мин (прогресс %d%%)" % [STAGE_LIMIT / 60.0, int(w.goals.progress * 100)]
		stages.append({"desc": st.desc, "ok": ok, "time": w.time - _stage_start, "why": why})
		if not ok:
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
			return "" if build_chain({"kind": "direct", "mat": any[0]}, "launch_silo") != null else "не построить шахту"
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
	_lab()
	var done := func() -> bool: return w.goals.stage > w.planet.goal.stages.find(st) or w.goals.completed
	if done.call():
		return ""
	# Прогон образцов через все доступные машины.
	for pid in Planner.usable_processes(w) + ["treater"]:
		var kind := ""
		for k in Buildings.KINDS:
			if Buildings.KINDS[k].get("process", "") == pid:
				kind = k
		var c := _free_near(w.planet.spawn)
		var m := build(kind, c, 0)
		if m == null:
			continue
		build("container", c + Vector2i(1, 0), 0)
		if Processes.PROCESSES[pid].get("gas_min", 0.0) > 0.0:
			pump_for(m, 10.0 if pid == "compressor" else 3.0, 1)
		var samples: Array = w.robot.inventory.keys()
		for i in samples.size():
			var id: String = samples[i]
			if w.robot.mass_of(id) < 1.0:
				continue
			travel(m.cell)
			w.robot.selected = id
			if pid == "treater":
				for id2 in samples:
					if id2 == id or w.robot.mass_of(id2) < 1.0:
						continue
					w.robot.selected = id2
					w.insert_into(m.cell, true, 1.0)
					w.robot.selected = id
					w.insert_into(m.cell, false, 1.0)
					run(4.0)
					if m.reagent != null:
						w.robot.add_item(m.reagent)
						m.reagent = null
					if done.call():
						return ""
			else:
				w.insert_into(m.cell, false, 1.0)
				run(Processes.PROCESSES[pid].dur + 1.0)
		if done.call():
			return ""
	return "" if done.call() else "кончились идеи для открытий"

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
	if w.planet.atm_pressure > st.p[1]:
		return "атмосфера %.1f атм выше нормы купола, а стравить давление ниже атмосферного нечем" % w.planet.atm_pressure
	var c := _free_near(w.planet.spawn)
	var dome := build("dome", c, 0, func(s): return s.has("insulating")) if not w.planet.materials.filter(func(s): return s.has("insulating")).is_empty() else null
	if dome == null:
		dome = build("dome", c, 0)
	if dome == null:
		return "не построить купол"
	var target_p: float = clamp(1.1, st.p[0] + 0.1, st.p[1] - 0.1)
	if w.planet.atm_pressure < st.p[0]:
		pump_for(dome, target_p, 1)
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
