class_name GoalsTracker
extends RefCounted
## Прогресс этапов цели планеты.
## Мир — World или «утиная» обёртка с теми же полями (3D-прототип: ProtoRun).

var w:                      # World; слабая ссылка, чтобы мир не держал сам себя
	get: return _wr.get_ref()
var _wr: WeakRef
var stage := 0
var hold := 0.0
var progress := 0.0
var completed := false
var choices := {}           # номер этапа (строкой) → выбранный вариант
var reward_pending: Array = []
var base_hits := 0
var base_vented := 0.0      # выпущенный газ на начало этапа (терраформирование)
var _acc := 0.0

func _init(world) -> void:
	_wr = weakref(world)

func goal() -> Dictionary:
	return w.planet.goal

func raw_stage(i: int) -> Dictionary:
	var st: Array = goal().stages
	return st[min(i, st.size() - 1)]

## Нужно выбрать путь для текущего этапа.
func choice_pending() -> bool:
	return not completed and raw_stage(stage).has("alt") and not choices.has(str(stage))

func current() -> Dictionary:
	var raw := raw_stage(stage)
	if raw.has("alt"):
		if choices.has(str(stage)):
			return raw.alt[int(choices[str(stage)])]
		return {"type": "choice", "desc": "Выберите путь для следующего этапа"}
	return raw

func choose(idx: int) -> void:
	choices[str(stage)] = idx
	base_hits = w.stats.hits
	base_vented = w.gas.vented_total
	hold = 0.0
	w.log_event(w.robot_cell(), "Выбран путь: " + current().desc)

func take_reward(id: String) -> String:
	if not id in reward_pending:
		return ""
	reward_pending = []
	w.sound("fanfare", w.robot_cell())
	var msg := Rewards.apply(w, id)
	w.log_event(w.robot_cell(), "Награда: %s — %s" % [Rewards.CARDS[id].n, msg])
	return msg

func tick(dt: float) -> void:
	if completed or choice_pending():
		return
	_acc += dt
	if _acc < 1.0:
		return
	var step := _acc
	_acc = 0.0
	progress = clamp(evaluate(current(), step), 0.0, 1.0)
	if progress >= 1.0:
		advance()

func advance() -> void:
	w.log_event(w.planet.spawn, "Этап выполнен: " + current().desc)
	w.robot.knowledge += 3
	w.robot.xp.chief += 20
	reward_pending = Rewards.offer(w, stage)
	w.sound("fanfare", w.robot_cell())
	stage += 1
	hold = 0.0
	progress = 0.0
	base_hits = w.stats.hits
	base_vented = w.gas.vented_total
	if stage >= goal().stages.size():
		completed = true
		stage = goal().stages.size() - 1
		progress = 1.0
		w.log_event(w.planet.spawn, "ЦЕЛЬ ПЛАНЕТЫ ДОСТИГНУТА: " + goal().n)

func _hold(ok: bool, need: float, dt: float) -> float:
	if ok:
		hold += dt * (1.0 + w.robot.passive("goal_speed"))
	else:
		hold = max(0.0, hold - dt * 2.0)
	return hold / need

func evaluate(st: Dictionary, dt: float) -> float:
	match st.type:
		"stockpile_tags":
			var p := 1.0
			for t in st.tags:
				p = min(p, w.stored_with_tag(t) / st.tags[t])
			return p
		"dome_env":
			var ok := false
			for m in w.machines_of("dome"):
				var pr: float = w.gas.pressure(m.id)
				if pr >= st.p[0] and pr <= st.p[1] and m.temp >= st.t[0] and m.temp <= st.t[1]:
					ok = true
			return _hold(ok, st.hold, dt)
		"launch_mass":
			return w.launched.mass / st.mass
		"launch_tag":
			return w.launched.tags.get(st.tag, 0.0) / st.mass
		"launch_exotic":
			return w.launched.exotic / st.mass
		"build_count":
			return float(w.machines_of(st.kind).size()) / st.n
		"discover_tags":
			return float(w.robot.known_tags.size()) / st.n
		"discover_exotic":
			var c := 0
			for t in w.robot.known_tags:
				if MaterialTags.is_exotic(t):
					c += 1
			return float(c) / st.n
		"discover_interactions":
			return float(w.robot.known_interactions.size()) / st.n
		"sensor_network":
			var c := 0
			for m in w.machines_of("sensor"):
				if not w.logic.wires_from(m.id).is_empty():
					c += 1
			return float(c) / st.n
		"phasing_contained":
			var s := 0.0
			for m in w.machines_of("tank"):
				if m.built_from.has("anchoring"):
					for p in m.items:
						if p.has("phasing"):
							s += p.mass
			return s / st.mass
		"deliveries":
			return float(w.stats.hits - base_hits) / st.n
		"machines_working":
			var c := 0
			for m in w.all_machines():
				if m is Processor and m.busy != null and m.enabled:
					c += 1
			return float(c) / st.n
		"stockpile_mass":
			var s := 0.0
			for m in w.all_machines():
				if m.is_storage():
					s += m.total_mass()
			return s / st.mass
		"vent_gas":
			return (w.gas.vented_total - base_vented) / st.amount
		"launch_variety":
			return float(w.launched.subs.size()) / st.n
		"excavate":
			return w.excavated / st.mass
		"beacon_hold":
			var ok := false
			for m in w.machines_of("beacon"):
				if w.gas.pressure(m.id) >= st.pressure:
					ok = true
			return _hold(ok, st.hold, dt)
	# Свои типы этапов у мира-обёртки (3D-прототип: ProtoRun.eval_stage).
	if w.has_method("eval_stage"):
		return w.eval_stage(self, st, dt)
	return 0.0

func text() -> String:
	var st := current()
	var s := "%s — этап %d/%d: %s (%d%%)" % [goal().n, stage + 1, goal().stages.size(), st.desc, int(progress * 100)]
	if st.has("tags"):
		var parts: Array = []
		for t in st.tags:
			parts.append("%s %.0f/%.0f кг" % [MaterialTags.display(t), w.stored_with_tag(t), st.tags[t]])
		s += "\n  " + ", ".join(parts)
	if st.has("tag"):
		s += "\n  тег: " + MaterialTags.display(st.tag)
	if choice_pending():
		s = "%s — этап %d/%d: выберите путь (окно выбора)" % [goal().n, stage + 1, goal().stages.size()]
	if st.type == "deliveries":
		s += "\n  доставлено: %d/%d" % [w.stats.hits - base_hits, st.n]
	if st.type == "vent_gas":
		s += "\n  выпущено: %.0f/%.0f (декомпрессор или насос на откачке)" % [w.gas.vented_total - base_vented, st.amount]
	if st.type == "launch_variety":
		s += "\n  разных материалов на орбите: %d/%d" % [w.launched.subs.size(), st.n]
	if st.type == "excavate":
		s += "\n  раскопано: %.1f/%.0f кг (E на клетке руин)" % [w.excavated, st.mass]
	if completed:
		s = "%s — ВЫПОЛНЕНО. Нажмите N для новой планеты." % goal().n
	return s
