class_name GoalsTracker
extends RefCounted
## Прогресс этапов цели планеты.

var w                       # World (без типа, чтобы не было циклической ссылки)
var stage := 0
var hold := 0.0
var progress := 0.0
var completed := false
var _acc := 0.0

func _init(world) -> void:
	w = world

func goal() -> Dictionary:
	return w.planet.goal

func current() -> Dictionary:
	var st: Array = goal().stages
	return st[min(stage, st.size() - 1)]

func tick(dt: float) -> void:
	if completed:
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
	stage += 1
	hold = 0.0
	progress = 0.0
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
		"beacon_hold":
			var ok := false
			for m in w.machines_of("beacon"):
				if w.gas.pressure(m.id) >= st.pressure:
					ok = true
			return _hold(ok, st.hold, dt)
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
	if completed:
		s = "%s — ВЫПОЛНЕНО. Нажмите N для новой планеты." % goal().n
	return s
