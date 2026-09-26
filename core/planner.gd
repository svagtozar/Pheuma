class_name Planner
## Планировщик получения тега из материалов планеты. Каждый вариант
## проверяется настоящим прогоном Processor.run, а не только таблицами.
## Используется ботом баланса (а в будущем — подсказками Шамана).
##
## План:
##   {"kind": "direct", "mat": Substance}
##   {"kind": "process", "mat": Substance, "procs": [pid, …], "out": [индексы выходов]}
##   {"kind": "treat", "mat": Substance, "reagent": Substance}

const MAX_P := 9.5

## Контекст прогона машины «как у хорошо накачанной установки».
static func ctx_for(w, pid: String, reagent = null) -> Dictionary:
	return {"db": w.db, "pressure": MAX_P if pid == "compressor" else 3.0, "compress_bonus": 0.0,
		"target_t": 900.0, "ambient": w.planet.ambient_temp, "reagent": reagent, "filter_tag": ""}

static func usable_processes(w) -> Array:
	var out: Array = []
	for k in Buildings.KINDS:
		var d: Dictionary = Buildings.KINDS[k]
		if d.has("process") and w.robot.unlocked.has(k) and not d.process in ["filter", "magnet_sep", "treater"]:
			if d.process == "irradiator":
				continue   # нужен радиоактивный источник — отдельный случай
			out.append(d.process)
	out.sort()
	return out

## Прогнать цепочку процессов; вернуть [порция, индексы выходов] или null.
static func run_chain(w, mat: Substance, procs: Array, tag: String) -> Array:
	var p := Portion.new(mat, 2.0, w.planet.ambient_temp)
	var outs: Array = []
	for pid in procs:
		var res := Processor.run(pid, p, ctx_for(w, pid))
		if res.get("wait", false) or res.outs.is_empty():
			return []
		var best = res.outs[0]
		for o in res.outs:
			if o[0].has(tag):
				best = o
		p = best[0]
		outs.append(best[1])
	return [p, outs] if p.has(tag) else []

## Лучший план для тега среди материалов mats (Substance) с залежами на планете.
static func plan(w, tag: String, mats: Array) -> Dictionary:
	var solid := mats.filter(func(m): return m.phase_at(w.planet.ambient_temp) == Substance.Phase.SOLID)
	for m in mats:
		if m.has(tag):
			return {"kind": "direct", "mat": m}
	var procs := usable_processes(w)
	for m in mats:
		for pid in procs:
			var r := run_chain(w, m, [pid], tag)
			if not r.is_empty():
				return {"kind": "process", "mat": m, "procs": [pid], "out": r[1]}
	for m in mats:
		for rg in solid:
			if rg == m:
				continue
			var ir := Interactions.apply(rg.tags, m.tags)
			if tag in ir.tags:
				return {"kind": "treat", "mat": m, "reagent": rg}
	for m in mats:
		for a in procs:
			for b in procs:
				var r := run_chain(w, m, [a, b], tag)
				if not r.is_empty():
					return {"kind": "process", "mat": m, "procs": [a, b], "out": r[1]}
	return {}

static func describe(pl: Dictionary) -> String:
	match pl.get("kind", ""):
		"direct": return "залежь %s" % pl.mat.name
		"process": return "%s → %s" % [pl.mat.name, " → ".join(pl.procs)]
		"treat": return "%s обработать реагентом %s" % [pl.mat.name, pl.reagent.name]
	return "нет плана"
