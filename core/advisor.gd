class_name Advisor
## Совет «что дальше»: одна строка с конкретным шагом и клетка, на которую показать.
## Сначала — почему стоит то, что уже построено (давление, некуда отдавать, склад полон,
## пушка без цели), потом — шаг к текущему этапу цели. Совет опирается только на то,
## что игрок уже знает: скрытые теги материалов он не выдаёт, а подсказывает, какой
## пробой или какой машиной их искать.

## {"text": String, "cell": Vector2i или null}
static func advise(w: World) -> Dictionary:
	if w.goals.completed:
		return _r("Цель выполнена. N — новая планета.")
	if w.goals.choice_pending():
		return _r("Выберите путь в окне выбора этапа.")
	if w.robot.hp < w.robot.max_hp() * 0.3:
		var fab: Array = w.machines_of("fabricator")
		return _r("Корпус на исходе — уйдите от опасности%s." % (", у фабрикатора корпус чинится" if not fab.is_empty() else ""),
			fab[0].cell if not fab.is_empty() else null)
	var d := diagnose(w)
	if not d.is_empty():
		return d
	return stage_step(w, w.goals.current())

static func _r(text: String, cell = null) -> Dictionary:
	return {"text": text, "cell": cell}

# ---------------------------------------------------------------- почему стоит

## Первая машина, которая стоит по понятной причине, и что с этим сделать.
static func diagnose(w: World) -> Dictionary:
	var ids: Array = w.machines.keys()
	ids.sort()
	for id in ids:
		var m: Machine = w.machines[id]
		var name := "«%s» %d,%d" % [m.display_name(), m.cell.x, m.cell.y]
		if not m.out_queue.is_empty() and m.status.begins_with("выстрел: мало давления"):
			return _r("%s стреляет выходом, но нет давления — поставьте насос или трубу от насоса вплотную (%.0f атм)." % [name, Machine.SHOT_P], m.cell)
		if not m.out_queue.is_empty() and m.shot_target(int(m.out_queue[0][1])) < 0:
			var oc: Vector2i = m.out_cell(int(m.out_queue[0][1]))
			var t = w.machine_at(oc)
			if t == null:
				return _r("%s: некуда отдавать груз — поставьте контейнер по стрелке выхода (%d,%d)." % [name, oc.x, oc.y], oc)
			if t.is_storage() and t.capacity() > 0.0 and t.free_space() < m.out_queue[0][0].mass:
				return _r("«%s» %d,%d полон — поставьте за ним ещё один или заберите груз (T у хранилища)." % [t.display_name(), oc.x, oc.y], oc)
		if m is Processor and m.status.begins_with("мало давления") and not _has_pump(w, m):
			return _r("%s: %s — поставьте насос вплотную или протяните трубу от насоса." % [name, m.status], m.cell)
		if m is Processor and m.status.begins_with("мало давления"):
			var need: float = m.need_p if m.need_p > 0.0 else m.proc.get("gas_min", 0.0)
			var weak = _weak_link(w, m, need)
			if weak != null:
				return _r("«%s» нужно %.1f атм, а «%s» %d,%d в той же газовой сети держит %.1f. Разнесите: пусть машина перед ней стреляет грузом через пустую клетку (L), а у «%s» будут свои насосы." % [
					m.display_name(), need, weak.display_name(), weak.cell.x, weak.cell.y, weak.stats.get("max_p", 0.0) * 0.95, m.display_name()], weak.cell)
			var pmp = _weak_pump(w, m, need)
			if pmp != null:
				return _r("Насос %d,%d из %s держит только %.1f атм, а «%s» нужно %.1f — поставьте насос из прочного материала (твёрдый, плотный, упругий)." % [
					pmp.cell.x, pmp.cell.y, pmp.built_from.name, pmp.stats.max_p * 0.95, m.display_name(), need], pmp.cell)
		if m is Cannon and not m.is_silo() and m.status.begins_with("нет цели"):
			return _r("Пушке %d,%d некуда стрелять — L: клик по пушке, затем по приёмнику." % [m.cell.x, m.cell.y], m.cell)
		if m is Cannon and not m.items.is_empty() and not _has_pump(w, m):
			return _r("%s: нет насоса — поставьте насос вплотную, выстрел при %.0f атм." % [name, m.fire_pressure(w)], m.cell)
		if m.kind == "drill" and m.status == "залежь пуста":
			return _r("Залежь под буром %d,%d кончилась — снесите бур и поставьте на другую." % [m.cell.x, m.cell.y], m.cell)
	return {}

## Машины той же газовой сети.
static func _net(w: World, m: Machine) -> Array:
	var out: Array = []
	if not w.gas.has_node(m.id):
		return out
	var seen := {m.id: true}
	var queue: Array = [m.id]
	while not queue.is_empty():
		var id: int = queue.pop_back()
		var x = w.machines.get(id)
		if x != null:
			out.append(x)
		for n in w.gas.neighbors(id):
			if not seen.has(n):
				seen[n] = true
				queue.append(n)
	return out

## Есть ли насос в той же газовой сети.
static func _has_pump(w: World, m: Machine) -> bool:
	return _net(w, m).any(func(x): return x.kind == "pump")

## Машина сети (не насос), чей материал не держит нужное давление.
static func _weak_link(w: World, m: Machine, need: float):
	for x in _net(w, m):
		if x != m and x.kind != "pump" and x.stats.get("max_p", INF) * 0.95 < need:
			return x
	return null

## Насос сети, упёршийся в предел своего материала ниже нужного.
static func _weak_pump(w: World, m: Machine, need: float):
	var strong := false
	var weak = null
	for x in _net(w, m):
		if x.kind == "pump":
			if x.stats.max_p * 0.95 >= need:
				strong = true
			elif weak == null:
				weak = x
	return null if strong else weak

# ---------------------------------------------------------------- шаг к этапу

static func stage_step(w: World, st: Dictionary) -> Dictionary:
	match st.type:
		"build_count":
			var have: int = w.machines_of(st.kind).size()
			if st.kind == "drill":
				var dep = nearest_deposit(w, null, w.starter.hardness + 0.5)
				var where := " Ближайшая залежь — %d,%d." % [dep.x, dep.y] if dep != null else " Ищите залежи: цветные пятна, серые крестики — ещё не разглядели."
				return _r("Поставьте бур на залежь (B → Бур), перед ним по стрелке — контейнер. Ещё %d.%s" % [st.n - have, where], dep)
			return _r("Поставьте «%s» (B). Ещё %d." % [Buildings.name_of(st.kind), st.n - have])
		"stockpile_tags":
			for t in st.tags:
				var have: float = w.stored_with_tag(t)
				if have + 0.01 < st.tags[t]:
					return tag_step(w, t, "в контейнер или бак (%.0f/%.0f кг)" % [have, st.tags[t]], "container")
			return _r(st.desc)
		"stockpile_mass":
			return _r("Запасите больше: любой бур → контейнер. Хранилища считаются все, и в свёрнутых блоках тоже.")
		"launch_mass", "launch_variety", "launch_tag", "launch_exotic":
			return launch_step(w, st)
		"deliveries":
			if w.machines_of("cannon").is_empty():
				return _r("Пушка (B → Пневматика) с насосом вплотную, приёмник в нескольких клетках, L — связать. Бур или Q кладёт груз в пушку.")
			return _r("Капсулы, попавшие в приёмник, засчитываются: держите пушку заряженной (бур за ней) и под давлением.")
		"discover_tags":
			return _r("Узнайте ещё %d тегов: касание (Z) у залежей, пробы материалов из инвентаря, обработка в машинах." % max(0, st.n - w.robot.known_tags.size()))
		"discover_interactions":
			return _r("Взаимодействия открываются в обработчике: груз сзади, реагент слева. Пробуйте разные пары материалов.")
		"discover_exotic":
			return _r("Невозможные теги находят пробами и обработкой: облучатель, резонатор, сверхдавление в компрессоре.")
		"machines_working":
			var c := 0
			for m in w.all_machines():
				if m is Processor and m.busy != null and m.enabled:
					c += 1
			return _r("Машин обработки в работе: %d из %d. Каждой нужен свой поток груза — бур за ней." % [c, st.n])
		"sensor_network":
			var c := 0
			for m in w.machines_of("sensor"):
				if not w.logic.wires_from(m.id).is_empty():
					c += 1
			return _r("Датчики с проводом: %d из %d. Поставьте датчик у контейнера и проведите провод (V) к машине." % [c, st.n])
		"vent_gas":
			return _r("Выпускайте газ: декомпрессор или насос в режиме откачки (в инспекторе насоса).")
		"excavate":
			return _r("Раскопки: встаньте на клетку руин (сиреневые с рамкой) и удерживайте E.")
		"dome_env", "beacon_hold":
			var kind := "dome" if st.type == "dome_env" else "beacon"
			var ms: Array = w.machines_of(kind)
			if ms.is_empty():
				return _r("Поставьте «%s» (B → Цели) и насосы рядом." % Buildings.name_of(kind))
			return _r("Держите условия у «%s»: смотрите давление и температуру в инспекторе (клик по нему)." % Buildings.name_of(kind), ms[0].cell)
	return _r(st.desc)

## Запуски на орбиту: шахта, давление, груз.
static func launch_step(w: World, st: Dictionary) -> Dictionary:
	var silos: Array = w.machines_of("launch_silo")
	if silos.is_empty():
		return _r("Поставьте пусковую шахту (B → Цели) и 2–3 насоса вплотную: запуск при 6 атм.")
	var s: Cannon = silos[0]
	if s.items.is_empty():
		if st.type == "launch_tag":
			return tag_step(w, st.tag, "в пусковую шахту", "launch_silo")
		return _r("Шахта пуста: подведите к ней бур или положите груз (Q рядом с шахтой).", s.cell)
	var p: float = w.gas.pressure(s.id)
	if p < s.fire_pressure(w):
		return _r("Шахте нужно %.0f атм, сейчас %.1f — ещё насос вплотную или ждите." % [s.fire_pressure(w), p], s.cell)
	if st.type == "launch_variety":
		return _r("Нужно ещё %d разных материалов на орбите — подкладывайте в шахту разные." % max(0, st.n - w.launched.subs.size()), s.cell)
	return _r("Шахта под давлением — груз уходит на орбиту.", s.cell)

## Как получить материал с тегом — только из того, что игрок знает.
static func tag_step(w: World, tag: String, dest: String, sink: String) -> Dictionary:
	var tn := MaterialTags.display(tag)
	# Известный материал с тегом, который можно накопать.
	for s in w.planet.materials:
		if tag in w.known_tags_of(s):
			var dep = nearest_deposit(w, s)
			if dep != null:
				return _r("«%s» есть у %s: бур на залежь %d,%d → %s %s." % [tn, s.name, dep.x, dep.y, Buildings.name_of(sink).to_lower(), dest], dep)
	# Уже в руках (например, после обработки).
	for id in w.robot.inventory:
		var s: Substance = w.db.get_sub(id)
		if tag in w.known_tags_of(s):
			return _r("У вас есть %s с «%s» — положите %s (Q у постройки)." % [s.name, tn, dest])
	# Не проверенные на этот тег материалы: какой пробой проверить.
	var how := _how_to_check(tag)
	var unchecked: Array = []
	var unseen := 0
	for s in w.planet.materials:
		if tag in w.known_tags_of(s) or tag in w.excluded_of(s) or nearest_deposit(w, s) == null:
			continue
		if seen(w, s):
			unchecked.append(s)
		else:
			unseen += 1
	var makers := makers_of(w, tag)
	var tail := (" Или обработкой: %s." % makers) if makers != "" else ""
	if unchecked.is_empty() and unseen > 0:
		var dep = nearest_deposit(w)
		return _r("«%s» ещё не нашли. Накопайте образцы (E у залежи) и %s.%s" % [tn, _lc(_how_to_check(tag)), tail], dep)
	if not unchecked.is_empty():
		var names: Array = unchecked.slice(0, 3).map(func(s): return s.name)
		var dep = nearest_deposit(w, unchecked[0])
		return _r("«%s» ещё не нашли. %s: %s%s.%s" % [tn, how, ", ".join(names), "…" if unchecked.size() > 3 else "", tail], dep)
	if makers != "":
		return _r("«%s» нет в сырье — получите обработкой: %s." % [tn, makers])
	return _r("«%s»: ищите новые залежи — сканер и прокачка «Собирателя» показывают дальние." % tn)

## Игрок уже встречал материал: касался его или держал образец.
static func seen(w: World, s: Substance) -> bool:
	return w.is_analyzed(s) or w.robot.mass_of(s.id) > 0.0 or not w.known_tags_of(s).is_empty() or not w.excluded_of(s).is_empty()

static func _lc(t: String) -> String:
	return t.substr(0, 1).to_lower() + t.substr(1)

static func _how_to_check(tag: String) -> String:
	if tag in Probes.VISIBLE:
		return "Коснитесь залежи (Z рядом)"
	for pid in Probes.ORDER:
		if tag in Probes.PROBES[pid].tags:
			return "Проверьте пробой «%s»" % Probes.PROBES[pid].n
	return "Следите за материалами в машинах — тег выдаст себя поведением"

## Машины, которые добавляют тег, с условием: «Компрессор (из «плотный», от 6 атм)».
## Сначала открытые, потом закрытые с пометкой.
static func makers_of(w: World, tag: String) -> String:
	var open: Array = []
	var locked: Array = []
	for pid in Processes.PROCESSES:
		var k := Planner.kind_of(pid)
		if k == "":
			continue
		for rule in Processes.PROCESSES[pid].get("rules", []):
			if not tag in rule.get("add", []):
				continue
			var cond: Array = []
			if not rule.get("all", []).is_empty():
				cond.append("из " + ", ".join(rule.all.map(func(t): return "«%s»" % MaterialTags.display(t))))
			elif not rule.get("any", []).is_empty():
				cond.append("из " + " или ".join(rule.any.map(func(t): return "«%s»" % MaterialTags.display(t))))
			if rule.has("min_p"):
				cond.append("от %.0f атм" % rule.min_p)
			var txt := Buildings.name_of(k) + (" (%s)" % ", ".join(cond) if not cond.is_empty() else "")
			if w.robot.unlocked.has(k):
				open.append(txt)
			else:
				locked.append(txt.trim_suffix(")") + (", " if txt.ends_with(")") else " (") + "открыть в прокачке)")
			break
	return "; ".join(open.slice(0, 2)) if not open.is_empty() else ("" if locked.is_empty() else locked[0])

## Ближайшая к роботу свободная залежь (материала s, если задан).
static func nearest_deposit(w: World, s: Substance = null, max_hard: float = INF):
	var best = null
	var bd := INF
	var rc := w.robot_cell()
	for c in w.planet.deposits:
		var dep = w.planet.deposits[c]
		if dep.amount <= 0.0 or w.grid.has(c):
			continue
		if s != null and dep.sub != s.id:
			continue
		if max_hard < INF and w.db.get_sub(dep.sub) != null and w.db.get_sub(dep.sub).hardness > max_hard:
			continue
		var dd := Vector2(c - rc).length()
		if dd < bd:
			bd = dd
			best = c
	return best
