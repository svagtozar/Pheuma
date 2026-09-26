class_name Cannon
extends Machine
## Пневмопушка и пусковая шахта. Копят давление в камере и стреляют капсулой.
## Дальность зависит от давления, гравитации и свойств груза.
## Маршруты: груз с тегом летит в свою цель (config.routes = [[тег, id цели], …]),
## остальное — в цель по умолчанию. Так пушки сортируют и развозят грузы.

var _cd := 0.0

func init_config() -> void:
	config.fire_p = 6.0 if kind == "launch_silo" else 3.0
	config.target = -1
	if kind != "launch_silo":
		config.routes = []

func is_silo() -> bool:
	return kind == "launch_silo"

## Камера пушки — под давлением, значит закрытая: летучее в ней не испаряется.
func handling_ctx() -> String:
	return "sealed"

func accept(p: Portion, from_cell: Vector2i) -> bool:
	if p.mass > free_space() + 0.001:
		return false
	if not is_silo() and side_of(from_cell) == "front":
		return false
	store(p)
	return true

func fire_pressure(w) -> float:
	if is_silo():
		return max(3.0, config.fire_p - w.robot.passive("silo_bonus"))
	return config.fire_p

func payload_limit() -> float:
	return 20.0 if is_silo() else 5.0

func range_mult() -> float:
	return 1.0

func consume_gas(w) -> void:
	w.gas.take_gas(id, w.gas.amount(id) * 0.7)

## Куда летит порция: первый подходящий маршрут, иначе цель по умолчанию.
func target_for(w, p: Portion) -> int:
	for r in config.get("routes", []):
		if p.has(r[0]) and w.machines.has(int(r[1])):
			return int(r[1])
	return int(config.target)

func add_route(tag: String, target_id: int) -> void:
	var routes: Array = config.get("routes", [])
	routes = routes.filter(func(r): return r[0] != tag)
	routes.append([tag, target_id])
	config.routes = routes

func tick(w, dt: float) -> void:
	status = ""
	_cd -= dt
	if not enabled:
		return
	if items.is_empty():
		status = "нет груза"
		return
	if not is_silo() and not w.machines.has(target_for(w, items[0])):
		status = "нет цели для «%s» — L или маршрут" % w.sub_label(items[0].substance)
		return
	var p: float = w.gas.pressure(id)
	if p < fire_pressure(w):
		status = "давление %.1f / %.1f атм" % [p, fire_pressure(w)]
		return
	if _cd > 0.0:
		return
	fire(w, p)

func fire(w, p: float) -> void:
	var limit := payload_limit()
	var tid := -1 if is_silo() else target_for(w, items[0])
	var payload: Array = []
	var taken := 0.0
	var keep: Array = []
	for q in items:
		if taken >= limit or (not is_silo() and target_for(w, q) != tid):
			keep.append(q)
			continue
		var part: Portion = q.split(min(q.mass, limit - taken))
		taken += part.mass
		payload.append(part)
		if q.mass > 0.001:
			keep.append(q)
	items = keep
	var extra: Array = []
	for q in payload:
		var s0: Substance = q.substance
		var r: Dictionary = Handling.event(q, "launch", w.handling_env(self, "launch"))
		w.observe(r, s0)
		extra.append_array(r.spawn)
		if r.jammed != null:
			store(r.jammed)
			w.log_event(cell, "%s застрял в стволе" % w.sub_label(q.substance))
		for e in r.events:
			w.log_event(cell, e)
	payload.append_array(extra)
	consume_gas(w)
	w.sound("thump", cell)
	w.stats.shots += 1
	_cd = 1.0
	w.robot.xp.firekeeper += 0.5
	if w.rng.chance(stats.burst_risk * p / stats.max_p):
		w.drop_portions(cell, payload)
		w.destroy(self, "хрупкий ствол лопнул при выстреле")
		return
	if is_silo():
		w.launch_orbit(payload, cell)
		return
	var target = w.machines[tid]
	var from := Vector2(cell) + Vector2(0.5, 0.5)
	var to := Vector2(target.cell) + Vector2(0.5, 0.5)
	var factor := 0.0
	var total := 0.0
	var scatter := 0.0
	for q in payload:
		factor += Handling.cannon_range_factor(q, w.planet) * q.mass
		total += q.mass
		scatter = max(scatter, Handling.cannon_scatter(q, w.planet))
	factor = factor / total if total > 0.0 else 1.0
	var storm: float = w.event_mods.scatter
	scatter = (scatter * storm + (2.0 if storm > 1.0 else 0.0)) * (1.0 - w.robot.passive("aim"))
	var rng_tiles := range_for(p, w.planet) * factor * range_mult()
	var dist := from.distance_to(to)
	var dest := to
	if dist > rng_tiles:
		dest = from + (to - from).normalized() * rng_tiles
	dest += Vector2(w.rng.range_f(-1, 1), w.rng.range_f(-1, 1)) * scatter * 0.5
	w.spawn_projectile(from, dest, payload)

static func range_for(p: float, planet: Planet) -> float:
	var r := 3.0 * p / planet.gravity
	if planet.has_tag("dense_atmosphere"):
		r *= 0.8
	return r

func describe(w) -> Array:
	var l := super.describe(w)
	l.append("Выстрел при %.1f атм, до %.0f кг" % [fire_pressure(w), payload_limit()])
	if not is_silo():
		l.append("Дальность при этом давлении: %.1f кл." % (range_for(fire_pressure(w), w.planet) * range_mult()))
		l.append("Цель по умолчанию: %s" % (w.machines[config.target].display_name() if w.machines.has(config.target) else "нет"))
		for r in config.get("routes", []):
			var t = w.machines.get(int(r[1]))
			l.append("  «%s» → %s" % [MaterialTags.display(r[0]), t.display_name() + " %d,%d" % [t.cell.x, t.cell.y] if t != null else "нет цели"])
	return l
