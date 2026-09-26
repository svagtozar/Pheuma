class_name EventDirector
extends RefCounted
## Запускает события планеты: пауза → предупреждение → активная фаза → конец.
## Всё детерминировано от seed. На учебной планете выключен.

const FIRST := [240.0, 360.0]
const GAP := [180.0, 360.0]

var w:
	get: return _wr.get_ref()
var _wr: WeakRef
var rng: Rng
var enabled := true
var next_in := 0.0
var current := {}        # {id, phase, t, center:[x,y], radius, shift, acc}
var count := 0

func _init(world) -> void:
	_wr = weakref(world)
	rng = world.rng.fork("events")
	next_in = rng.range_f(FIRST[0], FIRST[1])
	enabled = not world.planet.forced

func active_id() -> String:
	return current.get("id", "") if current.get("phase", "") == "active" else ""

func center() -> Vector2i:
	var c: Array = current.get("center", [0, 0])
	return Vector2i(int(c[0]), int(c[1]))

func tick(dt: float) -> void:
	if not enabled:
		return
	if current.is_empty():
		next_in -= dt
		if next_in <= 0.0:
			start(pick())
		return
	current.t -= dt
	if current.phase == "warn":
		if current.t <= 0.0:
			_begin()
	else:
		_active_tick(dt)
		if current.t <= 0.0:
			finish()

func pick() -> String:
	var ids: Array = Events.EVENTS.keys()
	ids.sort()
	var weights := {}
	for id in ids:
		weights[id] = Events.weight(id, w.planet)
	return rng.weighted_pick(ids, weights)

## Начать событие (с предупреждением). center можно задать явно — для тестов.
func start(id: String, at = null) -> void:
	var d: Dictionary = Events.EVENTS[id]
	var c: Vector2i = at if at != null else _choose_center(id)
	current = {"id": id, "phase": "warn", "t": rng.range_f(d.warn[0], d.warn[1]), "center": [c.x, c.y],
		"radius": d.radius, "shift": 0.0, "acc": 0.0}
	w.sound("alarm", w.robot_cell())
	w.log_event(c, "Надвигается: %s. %s" % [d.n, d.tip])

func _choose_center(id: String) -> Vector2i:
	var p: Planet = w.planet
	var base: Vector2i = p.spawn
	var ms: Array = w.machines.values()
	match id:
		"meteors":
			if not ms.is_empty() and rng.chance(0.6):
				return rng.pick(ms).cell + Vector2i(rng.range_i(-4, 4), rng.range_i(-4, 4))
			return base + Vector2i(rng.range_i(-15, 15), rng.range_i(-12, 12))
		"geyser":
			for _i in 200:
				var c := base + Vector2i(rng.range_i(-12, 12), rng.range_i(-10, 10))
				if p.buildable(c) and not w.grid.has(c) and not p.deposits.has(c):
					return c
			return base
		"flare", "spore_bloom":
			var boxes: Array = ms.filter(func(m): return m.kind == "container" or m.kind == "receiver" or m.kind == "pump")
			if not boxes.is_empty():
				return rng.pick(boxes).cell
			return base
		"ring_debris":
			if not ms.is_empty() and rng.chance(0.5):
				return rng.pick(ms).cell + Vector2i(rng.range_i(-3, 3), rng.range_i(-3, 3))
			return base + Vector2i(rng.range_i(-15, 15), rng.range_i(-12, 12))
	return base

func _begin() -> void:
	var d: Dictionary = Events.EVENTS[current.id]
	current.phase = "active"
	current.t = rng.range_f(d.dur[0], d.dur[1])
	w.log_event(center(), "Началось: %s" % d.n)
	match current.id:
		"storm":
			w.event_mods.scatter = 3.0
		"acid":
			w.event_mods.corrosion = 3.0
		"temp_shift":
			var sign := 1.0
			if w.planet.has_tag("frozen"):
				sign = 1.0 if rng.chance(0.7) else -1.0
			elif w.planet.has_tag("volcanic"):
				sign = -1.0 if rng.chance(0.7) else 1.0
			else:
				sign = 1.0 if rng.chance(0.5) else -1.0
			current.shift = 40.0 * sign
			_apply_shift(current.shift)
		"quake":
			_quake()
		"geyser":
			w.tile_overrides.erase(center())
		"time_loop":
			w.event_mods.time_boost = 1.5

func _apply_shift(delta: float) -> void:
	w.planet.ambient_temp += delta
	w.gas.ambient = w.planet.ambient_temp

func _active_tick(dt: float) -> void:
	current.acc += dt
	match current.id:
		"meteors":
			if current.acc >= 0.8:
				current.acc = 0.0
				var r: int = current.radius
				var c := center() + Vector2i(rng.range_i(-r, r), rng.range_i(-r, r))
				var to := Vector2(c) + Vector2(0.5, 0.5)
				w.projectiles.append({"from": to + Vector2(-5, -14), "to": to, "t": 0.0, "dur": 1.2, "payload": [], "orbit": false, "kind": "meteor"})
		"geyser":
			var c := center()
			for d in Machine.DIRS:
				var m = w.machine_at(c + d)
				if m != null and m.has_gas():
					w.gas.add_gas(m.id, 1.5 * dt)
			if current.acc >= 1.5:
				current.acc = 0.0
				w.sound("hiss", c)
		"storm":
			if current.acc >= 4.0:
				current.acc = 0.0
				var weak: Array = w.machines.values().filter(func(m): return not m.stats.storm_proof)
				if not weak.is_empty():
					var m: Machine = rng.pick(weak)
					m.hp -= 12.0 * m.stats.wear
					if m.hp <= 0.0:
						w.destroy(m, "сильная буря")
		"flare":
			if current.acc >= 2.0:
				current.acc = 0.0
				_flare()
		"spore_bloom":
			# Насосы в зоне забиты спорами — их список проверяет сам насос.
			var clogged := {}
			for m in _in_zone():
				if m.kind == "pump":
					clogged[m.id] = true
			w.event_mods.spores = clogged
			if current.acc >= 3.0:
				current.acc = 0.0
				_spores()
		"ring_debris":
			if current.acc >= 1.0:
				current.acc = 0.0
				var r: int = current.radius
				var c := center() + Vector2i(rng.range_i(-r, r), rng.range_i(-r, r))
				var to := Vector2(c) + Vector2(0.5, 0.5)
				w.projectiles.append({"from": to + Vector2(8, -14), "to": to, "t": 0.0, "dur": 1.0, "payload": [], "orbit": false, "kind": "debris"})
		"time_loop":
			w.robot.tank = max(0.0, w.robot.tank - 0.15 * dt)

func _in_zone() -> Array:
	var c := center()
	var r: float = current.radius
	return w.machines.values().filter(func(m): return Vector2(m.cell - c).length() <= r)

## Споры: органика в открытых контейнерах зоны прорастает волокном.
func _spores() -> void:
	for m in _in_zone():
		if m.sealed():
			continue
		for i in m.items.size():
			var p: Portion = m.items[i]
			if p.has("organic") and not p.has("fibrous"):
				p.substance = w.db.derive(p.substance, MaterialTags.add_tag(p.substance.tags, "fibrous"))
				w.log_event(m.cell, "Споры проросли в %s" % p.substance.name)

func finish() -> void:
	var d: Dictionary = Events.EVENTS[current.id]
	match current.id:
		"storm":
			w.event_mods.scatter = 1.0
		"acid":
			w.event_mods.corrosion = 1.0
		"temp_shift":
			_apply_shift(-current.shift)
		"time_loop":
			w.event_mods.time_boost = 1.0
		"spore_bloom":
			w.event_mods.erase("spores")
			_sprout()
	w.log_event(center(), "Закончилось: %s" % d.n)
	current = {}
	count += 1
	next_in = rng.range_f(GAP[0], GAP[1])

## Удар метеорита в клетку (вызывается при падении снаряда).
func meteor_hit(c: Vector2i) -> void:
	w.sound("boom", c)
	w.fires[c] = 3.0
	var m = w.machine_at(c)
	if m != null:
		m.hp -= 45.0 * m.stats.wear
		if m.hp <= 0.0:
			w.destroy(m, "метеорит")
	if w.robot.pos.distance_to(Vector2(c) + Vector2(0.5, 0.5)) < 1.5:
		w.robot.damage(20.0 * (1.0 - w.robot.shield().heat))
	if w.machine_at(c) == null and w.planet.buildable(c) and not w.planet.deposits.has(c) and rng.chance(0.35):
		var sub := _meteor_material()
		w.planet.deposits[c] = {"sub": sub.id, "amount": rng.range_f(30.0, 80.0)}
		w.revealed[c] = true
		w.log_event(c, "Метеорит оставил залежь: %s" % w.sub_label(sub))

## После спорового выброса в зоне прорастают залежи органики.
func _sprout() -> void:
	var org: Array = w.planet.materials.filter(func(s): return s.has("organic") and s.phase_at(w.planet.ambient_temp) == Substance.Phase.SOLID)
	if org.is_empty():
		org = w.planet.materials.filter(func(s): return s.has("fibrous") or s.has("organic"))
	if org.is_empty():
		return
	var sub: Substance = rng.pick(org)
	var n := 0
	for _try in 40:
		if n >= 3:
			break
		var c := center() + Vector2i(rng.range_i(-4, 4), rng.range_i(-4, 4))
		if w.planet.buildable(c) and not w.planet.deposits.has(c) and not w.grid.has(c) and not w.tile_overrides.has(c):
			w.planet.deposits[c] = {"sub": sub.id, "amount": rng.range_f(40.0, 90.0)}
			w.revealed[c] = true
			n += 1
	if n > 0:
		w.log_event(center(), "Проросли грибницы: залежи «%s» — %d" % [sub.name, n])

## Удар обломка колец: урон как у метеорита, залежь — металл, кристалл или тугоплавкое.
func debris_hit(c: Vector2i) -> void:
	w.sound("boom", c)
	var m = w.machine_at(c)
	if m != null:
		m.hp -= 35.0 * m.stats.wear
		if m.hp <= 0.0:
			w.destroy(m, "обломок колец")
	if w.robot.pos.distance_to(Vector2(c) + Vector2(0.5, 0.5)) < 1.5:
		w.robot.damage(15.0 * (1.0 - w.robot.shield().heat))
	if w.machine_at(c) == null and w.planet.buildable(c) and not w.planet.deposits.has(c) and rng.chance(0.5):
		var pool: Array = w.planet.materials.filter(func(s): return s.has("refractory"))
		if pool.is_empty():
			pool = w.planet.materials.filter(func(s): return s.has("metallic") or s.has("crystalline"))
		if pool.is_empty():
			pool = w.planet.materials
		var sub: Substance = rng.pick(pool)
		w.planet.deposits[c] = {"sub": sub.id, "amount": rng.range_f(40.0, 90.0)}
		w.revealed[c] = true
		w.log_event(c, "Обломок оставил залежь: %s" % w.sub_label(sub))

func _meteor_material() -> Substance:
	if rng.chance(0.25):
		var used := {}
		for s in w.planet.materials:
			used[s.root] = true
		var ex: String = rng.pick(MaterialTags.exotic_tags())
		var s := MaterialGen.generate_one(rng, MaterialGen.tag_weights(w.planet.tags, 1.0), used, [ex])
		w.planet.materials.append(s)
		w.db.add(s)
		return s
	return rng.pick(w.planet.materials)

func _quake() -> void:
	w.sound("boom", w.robot_cell())
	var pipes: Array = w.machines.values().filter(func(m): return m.kind == "pipe" and not m.stats.storm_proof)
	for i in min(3, pipes.size()):
		var m: Machine = pipes[rng.range_i(0, pipes.size() - 1)]
		if w.machines.has(m.id):
			w.destroy(m, "землетрясение")
	var p: Planet = w.planet
	for _try in 60:
		var c := p.spawn + Vector2i(rng.range_i(-20, 20), rng.range_i(-16, 16))
		if (c - p.spawn).length() < 6:
			continue
		var d: Vector2i = Machine.DIRS[rng.range_i(0, 3)]
		var cells: Array = []
		for k in rng.range_i(3, 5):
			cells.append(c + d * k)
		var ok := true
		for q in cells:
			if not p.buildable(q) or w.grid.has(q) or w.robot_cell() == q:
				ok = false
		if not ok:
			continue
		for q in cells:
			p.set_tile(q, Planet.Tile.CHASM)
			p.deposits.erase(q)
		var side: Vector2i = Vector2i(d.y, d.x)
		for q in cells:
			var dc: Vector2i = q + side
			if p.buildable(dc) and not w.grid.has(dc) and not p.deposits.has(dc) and rng.chance(0.6):
				p.deposits[dc] = {"sub": rng.pick(p.materials).id, "amount": rng.range_f(40.0, 90.0)}
				w.revealed[dc] = true
		w.log_event(c, "Земля раскололась — у расщелины открылись залежи")
		return

func _flare() -> void:
	var r: int = current.radius
	var c := center()
	var boxes: Array = w.machines.values().filter(func(m): return not m.sealed() and not m.items.is_empty() and (m.cell - c).length() <= r)
	if boxes.is_empty():
		return
	var m: Machine = rng.pick(boxes)
	var p: Portion = rng.pick(m.items)
	var pool: Array = MaterialTags.exotic_tags() if rng.chance(0.3) else MaterialTags.normal_tags()
	pool.sort()
	var t: String = rng.pick(pool)
	var tags := MaterialTags.add_tag(p.substance.tags, t)
	if tags == p.substance.tags:
		return
	p.substance = w.db.derive(p.substance, tags)
	w.robot.xp.shaman += 1.0
	w.log_event(m.cell, "Вспышка изменила груз: теперь %s" % w.sub_label(p.substance))

func to_dict() -> Dictionary:
	return {"next_in": next_in, "current": current, "count": count, "enabled": enabled}

func from_dict(d: Dictionary) -> void:
	next_in = float(d.get("next_in", next_in))
	current = d.get("current", {})
	count = int(d.get("count", 0))
	enabled = d.get("enabled", enabled)
	for k in ["t", "shift", "acc", "radius"]:
		if current.has(k):
			current[k] = float(current[k]) if k != "radius" else int(current[k])
	# Эффекты активного события не хранятся в мире — восстанавливаем.
	if current.get("phase", "") == "active":
		match current.id:
			"storm": w.event_mods.scatter = 3.0
			"acid": w.event_mods.corrosion = 3.0
			"temp_shift": _apply_shift(current.shift)
			"time_loop": w.event_mods.time_boost = 1.5
			# spore_bloom пересчитывает забитые насосы каждый тик сам.

func status_text() -> String:
	if current.is_empty():
		return ""
	var d: Dictionary = Events.EVENTS[current.id]
	if current.phase == "warn":
		return "⚠ %s — через %d с. %s" % [d.n, int(current.t), d.tip]
	return "● %s — ещё %d с" % [d.n, int(current.t)]
