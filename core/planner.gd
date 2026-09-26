class_name Planner
## Планировщик получения тега из материалов планеты: поиск в ширину по
## состояниям вещества (теги + фаза + температура). Шаг — машина обработки
## или обработчик с реагентом из местных материалов. Каждый шаг проверяется
## настоящим Processor.run / Interactions.apply.
##
## План: {"mat": исходный материал, "steps": [шаг…], "locked": [закрытые постройки]}
## Шаг:  {"op": "process", "pid": id, "kind": постройка, "out": 0|1}
##       {"op": "treat", "reagent": Substance, "kind": "treater", "out": 0}
## У процессов с источником (облучатель, резонатор) в шаге есть "source": материал-источник.
##
## Побочный эффект: производные вещества создаются в w.db.

const MAX_DEPTH := 5
const MAX_STATES := 2500
const MAX_P := 9.5

static func kind_of(pid: String) -> String:
	for k in Buildings.KINDS:
		if Buildings.KINDS[k].get("process", "") == pid:
			return k
	return ""

static func ctx_for(w, pid: String, reagent = null) -> Dictionary:
	return {"db": w.db, "pressure": MAX_P if pid == "compressor" else 3.0, "compress_bonus": 0.0,
		"target_t": 900.0, "ambient": w.planet.ambient_temp, "reagent": reagent, "filter_tag": ""}

## Реагенты: твёрдые материалы с залежами, которые можно накопать.
static func reagents(w, mats: Array) -> Array:
	return mats.filter(func(m): return m.phase_at(w.planet.ambient_temp) == Substance.Phase.SOLID and m.hardness <= w.robot.mining_hardness() + 0.5)

## Сначала — из открытых машин, потом с машинами ранних узлов прокачки, в конце — с любыми:
## короткий путь через глубокий узел хуже длинного через открытые машины.
static func plan(w, tag: String, mats: Array) -> Dictionary:
	for tier in [0, 2, 3, ALL_TIERS]:
		var p := _search(w, tag, mats, tier)
		if not p.is_empty():
			return p
	return {}

const ALL_TIERS := 99

## Ступень постройки: номер узла прокачки в своём классе (0 — открыта с начала).
static func tier_of(kind: String) -> int:
	for nd in SkillTree.NODES:
		if kind in nd.get("unlock", []):
			return SkillTree.nodes_of(nd.cls).find(nd) + 1
	return 0

static func _search(w, tag: String, mats: Array, max_tier: int, max_states: int = MAX_STATES) -> Dictionary:
	var rgs := reagents(w, mats)
	# Процессы с источником (облучатель, резонатор): источник — местный реагент с нужным тегом.
	var sources := {}
	var pids: Array = []
	for pid in Processes.PROCESSES:
		if pid in ["filter", "magnet_sep", "treater"]:
			continue
		var stag: String = Processes.PROCESSES[pid].get("source", "")
		if stag != "":
			var cand: Array = rgs.filter(func(m): return m.has(stag))
			if cand.is_empty():
				continue
			sources[pid] = cand[0]
		var k := kind_of(pid)
		if w.robot.unlocked.has(k) or tier_of(k) <= max_tier:
			pids.append(pid)
	pids.sort()
	var queue: Array = []
	var seen := {}
	for m in mats:
		var p := Portion.new(m, 2.0, w.planet.ambient_temp)
		queue.append({"mat": m, "p": p, "steps": []})
		seen[_key(p)] = true
	var head := 0
	while head < queue.size() and seen.size() < max_states:
		var s: Dictionary = queue[head]
		head += 1
		if s.p.has(tag):
			return _finish(w, s)
		if s.steps.size() >= MAX_DEPTH:
			continue
		for pid in pids:
			var ctx := ctx_for(w, pid, Portion.new(sources[pid], 5.0) if sources.has(pid) else null)
			var res := Processor.run(pid, s.p, ctx)
			if res.get("wait", false):
				continue
			for o in res.outs:
				var np: Portion = o[0]
				var k := _key(np)
				if seen.has(k):
					continue
				seen[k] = true
				var st := {"op": "process", "pid": pid, "kind": kind_of(pid), "out": o[1]}
				if sources.has(pid):
					st.source = sources[pid]
				queue.append({"mat": s.mat, "p": np, "steps": s.steps + [st]})
		for rg in rgs:
			if rg == s.p.substance:
				continue
			var ir := Interactions.apply(rg.tags, s.p.substance.tags)
			if ir.keys.is_empty() or ir.tags == s.p.substance.tags:
				continue
			var np := Portion.new(w.db.derive(s.p.substance, ir.tags), s.p.mass, s.p.temp + ir.heat)
			var k := _key(np)
			if seen.has(k):
				continue
			seen[k] = true
			queue.append({"mat": s.mat, "p": np, "steps": s.steps + [{"op": "treat", "reagent": rg, "kind": "treater", "out": 0}]})
	return {}

## Быстрая проверка при генерации планеты: один проход со всеми постройками.
static func feasible(w, tag: String, mats: Array) -> bool:
	return not probe_plan(w, tag, mats).is_empty()

## То же, но возвращает сам план (для проверки, из чего строить его машины).
static func probe_plan(w, tag: String, mats: Array) -> Dictionary:
	return _search(w, tag, mats, ALL_TIERS, 900)

static func _key(p: Portion) -> String:
	return ",".join(p.substance.tags) + "|" + str(p.phase())

static func _finish(w, s: Dictionary) -> Dictionary:
	var locked: Array = []
	for st in s.steps:
		if not w.robot.unlocked.has(st.kind) and not st.kind in locked:
			locked.append(st.kind)
	return {"mat": s.mat, "steps": s.steps, "locked": locked, "final": s.p}

static func describe(pl: Dictionary) -> String:
	if pl.is_empty():
		return "нет плана"
	var parts: Array = [pl.mat.name]
	for st in pl.steps:
		if st.op == "treat":
			parts.append("обработка реагентом %s" % st.reagent.name)
		else:
			parts.append(Processes.PROCESSES[st.pid].n + (" (правый выход)" if st.out == 1 else ""))
	var s := " → ".join(parts)
	if not pl.locked.is_empty():
		s += " [нужно открыть: %s]" % ", ".join(pl.locked.map(func(k): return Buildings.name_of(k)))
	return s
