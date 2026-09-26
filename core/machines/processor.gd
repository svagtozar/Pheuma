class_name Processor
extends Machine
## Обрабатывающая машина. Правила берутся из data/processes.gd.
## Вход — сзади (и слева для реагента/источника), выход 0 — вперёд, выход 1 — вправо.

const GAS_PER_KG := 2.0

var pid := ""
var proc := {}
var busy: Portion = null
var reagent: Portion = null
var progress := 0.0
var need_p := 0.0     # давление, которого ждёт машина, чтобы обработка что-то изменила

func init_config() -> void:
	pid = info.process
	proc = Processes.PROCESSES[pid]
	if pid == "furnace":
		config.target_t = 900.0
	if pid == "filter":
		config.tag = "dense"

func uses_side_input() -> bool:
	return proc.get("reagent", false) or proc.get("source", "") != ""

func accept(p: Portion, from_cell: Vector2i) -> bool:
	var side := side_of(from_cell)
	if side == "front" or side == "right" and proc.outs == 2:
		return false
	if uses_side_input() and side == "left":
		if reagent == null:
			reagent = p
			return true
		if reagent.substance == p.substance and reagent.mass + p.mass <= 20.0:
			reagent.absorb(p)
			return true
		return false
	if p.mass > free_space() + 0.001:
		return false
	store(p)
	return true

func source_ok() -> bool:
	var tag: String = proc.get("source", "")
	if tag == "":
		return true
	return built_from.has(tag) or (reagent != null and reagent.has(tag))

func target_temp(w) -> float:
	var t: float = config.get("target_t", 900.0) + w.robot.passive("furnace_t")
	return min(t, stats.max_t)

func tick(w, dt: float) -> void:
	status = ""
	hot = false
	if not enabled:
		status = "выключено"
		return
	if not out_queue.is_empty():
		status = "выход занят"
		return
	if busy == null:
		if items.is_empty():
			status = "ждёт груз"
			return
		if proc.get("gas_min", 0.0) > 0.0 and w.gas.pressure(id) < proc.gas_min:
			status = "мало давления (нужно %.1f атм)" % proc.gas_min
			return
		if proc.get("reagent", false) and reagent == null:
			status = "нет реагента (вход слева)"
			return
		if not source_ok():
			status = "нужен радиоактивный источник: материал постройки или реагент слева"
			return
		var p: Portion = items[0]
		busy = p.split(min(2.0, p.mass))
		if p.mass <= 0.001:
			items.remove_at(0)
		progress = 0.0
	var lag := 0.2 if busy.has("chrono_lagged") else 1.0
	progress += dt * stats.speed * w.time_factor() * lag
	hot = proc.get("temp", "") in ["heat", "sinter"]
	status = "работает %d%%" % int(100.0 * progress / proc.dur)
	if progress >= proc.dur:
		_finish(w)

func _finish(w) -> void:
	var ctx := context(w)
	var res := run(pid, busy, ctx)
	need_p = 0.0
	if not res.get("wait", false) and res.added.is_empty() and res.gas <= 0.0:
		# При этом давлении ничего не меняется, а при большем — поменялось бы:
		# ждём давления, а не гоним сырьё насквозь.
		var np := pressure_needed(pid, busy, ctx, stats.get("max_p", 0.0))
		if np > 0.0:
			need_p = np
			res.wait = true
			res.note = "мало давления для обработки: нужно %.1f атм" % np
	if res.get("wait", false):
		status = res.note
		progress = proc.dur
		return
	if proc.get("gas_use", 0.0) > 0.0:
		w.gas.take_gas(id, proc.gas_use)
	if res.gas > 0.0 and has_gas():
		w.gas.add_gas(id, res.gas * GAS_PER_KG)
		_relieve(w)
	elif res.gas > 0.0:
		w.gas.add_gas(id, res.gas * GAS_PER_KG)
	if reagent != null and res.reagent_used > 0.0:
		reagent.mass -= res.reagent_used
		if reagent.mass <= 0.001:
			reagent = null
	for o in res.outs:
		out_queue.append(o)
	w.on_processed(self, busy, res)
	busy = null
	progress = 0.0

## Предохранительный клапан: газ, выделенный обработкой, не разрывает машину —
## всё выше 90% предела материала стравливается наружу.
func _relieve(w) -> void:
	var cap: float = stats.get("max_p", 0.0) * 0.9
	var p: float = w.gas.pressure(id)
	if cap <= 0.0 or p <= cap:
		return
	var excess: float = w.gas.amount(id) * (1.0 - cap / p)
	w.gas.vented_total += w.gas.take_gas(id, excess)
	w.add_fx("vapor", cell, Color(0.9, 0.95, 1.0))

func context(w) -> Dictionary:
	return {"db": w.db, "pressure": w.gas.pressure(id) if has_gas() else 0.0,
		"compress_bonus": w.robot.passive("compress_bonus") if pid == "compressor" else 0.0,
		"target_t": target_temp(w), "ambient": w.planet.ambient_temp, "reagent": reagent,
		"filter_tag": config.get("tag", "")}

## Наименьшее давление правила, при котором обработка изменила бы груз (0 — такого нет
## или машина его не выдержит). Для машин, чьи правила зависят от давления.
static func pressure_needed(p_pid: String, p: Portion, ctx: Dictionary, max_p: float) -> float:
	var levels: Array = []
	for rule in Processes.PROCESSES[p_pid].get("rules", []):
		var mp: float = rule.get("min_p", 0.0)
		if mp > ctx.get("pressure", 0.0) + ctx.get("compress_bonus", 0.0) and not mp in levels:
			levels.append(mp)
	levels.sort()
	for mp in levels:
		if mp - ctx.get("compress_bonus", 0.0) > max_p:
			break
		var c2 := ctx.duplicate()
		c2.pressure = mp - ctx.get("compress_bonus", 0.0)
		var r := run(p_pid, p, c2)
		if not r.added.is_empty() or r.gas > 0.0:
			return mp - ctx.get("compress_bonus", 0.0)
	return 0.0

## Чистая функция обработки — удобно тестировать и показывать предсказание.
static func run(p_pid: String, p: Portion, ctx: Dictionary) -> Dictionary:
	var pr: Dictionary = Processes.PROCESSES[p_pid]
	var db: SubstanceDB = ctx.db
	var res := {"outs": [], "gas": 0.0, "keys": [], "reagent_used": 0.0, "added": [], "note": "", "matched": []}
	var sub := p.substance
	var phase_in := p.phase()
	var temp := p.temp
	match pr.get("temp", ""):
		"heat":
			if sub.has("thermo_inverted"):
				temp -= (ctx.target_t - temp) * 0.5
			else:
				temp = ctx.target_t
		"cool":
			var target: float = min(ctx.ambient, sub.melt - 40.0)
			if sub.has("thermo_inverted"):
				temp += abs(temp - target) * 0.5
			else:
				temp = target
		"sinter":
			temp = sub.melt - 30.0
		"cryo":
			# Глубокая заморозка: намного холоднее среды и ниже T плавления.
			var deep: float = min(ctx.ambient - 150.0, sub.melt - 60.0)
			if sub.has("thermo_inverted"):
				temp += abs(temp - deep) * 0.5
			else:
				temp = deep
	var phase_out := sub.phase_at(temp)
	var was_hot := phase_in != Substance.Phase.SOLID and phase_out == Substance.Phase.SOLID
	var pressure: float = ctx.get("pressure", 0.0) + ctx.get("compress_bonus", 0.0)

	if pr.has("needs_phase") and Processes.PHASE_BY_NAME[pr.needs_phase] != phase_out:
		res.outs.append([Portion.new(sub, p.mass, temp), 0])
		res.note = "не подходит: нужна фаза «%s»" % Substance.PHASE_NAMES[Processes.PHASE_BY_NAME[pr.needs_phase]]
		return res
	if pr.has("needs_any"):
		var ok := false
		for t in pr.needs_any:
			if sub.has(t):
				ok = true
		if not ok:
			res.outs.append([Portion.new(sub, p.mass, temp), 0])
			res.note = "не подходит по тегам"
			return res

	if p_pid == "treater":
		var rg: Portion = ctx.get("reagent")
		var ir := Interactions.apply(rg.substance.tags, sub.tags)
		if ir.keys.is_empty():
			res.outs.append([Portion.new(sub, p.mass, temp), 0])
			res.note = "реагент не действует на этот материал"
			return res
		var need: float = p.mass * 0.5 * ir.consume
		if rg.mass + 0.001 < need:
			res.wait = true
			res.note = "мало реагента (нужно %.1f кг)" % need
			return res
		res.reagent_used = need
		for k in ir.keys:
			var b: String = k.split(">")[1]
			if b in sub.tags and not b in res.matched:
				res.matched.append(b)
		var gas_m: float = p.mass * ir.gas
		res.gas = gas_m
		res.keys = ir.keys
		var ns := db.derive(sub, ir.tags)
		res.added = ir.tags.filter(func(t): return not t in sub.tags)
		res.outs.append([Portion.new(ns, p.mass - gas_m, temp + ir.heat), 0])
		return res

	if pr.get("route", "") == "magnetic":
		res.outs.append([Portion.new(sub, p.mass, temp), 0 if sub.has("magnetic") else 1])
		return res
	if pr.get("route", "") == "tag":
		res.outs.append([Portion.new(sub, p.mass, temp), 0 if sub.has(ctx.get("filter_tag", "")) else 1])
		return res

	var masses: Array = [p.mass]
	if pr.outs == 2 and pr.has("split"):
		masses = [p.mass * (1.0 - pr.split), p.mass * pr.split]
	for idx in masses.size():
		var tags: Array = sub.tags.duplicate()
		var gas_frac := 0.0
		for rule in pr.rules:
			if rule.has("out") and rule.out != idx:
				continue
			if not Processes.rule_matches(rule, sub.tags, phase_out, pressure, temp, was_hot):
				continue
			# Наблюдение: теги из условия сработавшего правила выдают себя.
			for t in rule.get("all", []) + rule.get("any", []):
				if t in sub.tags and not t in res.matched:
					res.matched.append(t)
			for t in rule.get("remove", []):
				tags.erase(t)
			for t in rule.get("add", []):
				tags = MaterialTags.add_tag(tags, t)
			gas_frac += rule.get("gas", 0.0)
		var m: float = masses[idx]
		var gm: float = m * min(gas_frac, 0.9)
		res.gas += gm
		if m - gm <= 0.001:
			continue
		for t in tags:
			if not t in sub.tags and not t in res.added:
				res.added.append(t)
		res.outs.append([Portion.new(db.derive(sub, tags), m - gm, temp), idx])
	return res

func describe(w) -> Array:
	var l := super.describe(w)
	if pid == "filter":
		l.append("Пропускает прямо: «%s»" % MaterialTags.display(config.tag))
	if pid == "furnace":
		l.append("Температура нагрева: %.0f °C (предел материала %.0f °C)" % [target_temp(w), stats.max_t])
	if uses_side_input():
		l.append("Слева: %s" % ("%s %.1f кг" % [w.sub_label(reagent.substance), reagent.mass] if reagent != null else "пусто"))
	if busy != null:
		l.append("В работе: %s %.1f кг" % [w.sub_label(busy.substance), busy.mass])
	return l
