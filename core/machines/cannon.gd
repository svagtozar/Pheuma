class_name Cannon
extends Machine
## Пневмопушка и пусковая шахта. Копят давление в камере и стреляют капсулой.
## Дальность зависит от давления, гравитации и свойств груза.

var _cd := 0.0

func init_config() -> void:
	config.fire_p = 8.0 if kind == "launch_silo" else 3.0
	config.target = -1

func is_silo() -> bool:
	return kind == "launch_silo"

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

func tick(w, dt: float) -> void:
	status = ""
	_cd -= dt
	if not enabled:
		return
	if items.is_empty():
		status = "нет груза"
		return
	if not is_silo() and not w.machines.has(config.target):
		status = "нет цели — свяжите с приёмником (L)"
		return
	var p: float = w.gas.pressure(id)
	if p < fire_pressure(w):
		status = "давление %.1f / %.1f атм" % [p, fire_pressure(w)]
		return
	if _cd > 0.0:
		return
	fire(w, p)

func fire(w, p: float) -> void:
	var limit := 20.0 if is_silo() else 5.0
	var payload: Array = []
	var taken := 0.0
	while not items.is_empty() and taken < limit:
		var q: Portion = items[0]
		var part := q.split(min(q.mass, limit - taken))
		if q.mass <= 0.001:
			items.remove_at(0)
		taken += part.mass
		payload.append(part)
	var extra: Array = []
	for q in payload:
		var r: Dictionary = Handling.event(q, "launch", w.handling_env(self, "launch"))
		extra.append_array(r.spawn)
		if r.jammed != null:
			store(r.jammed)
			w.log_event(cell, "%s застрял в стволе" % w.sub_label(q.substance))
		for e in r.events:
			w.log_event(cell, e)
	payload.append_array(extra)
	w.gas.take_gas(id, w.gas.amount(id) * 0.7)
	w.sound("thump", cell)
	_cd = 1.0
	w.robot.xp.firekeeper += 0.5
	if w.rng.chance(stats.burst_risk * p / stats.max_p):
		w.drop_portions(cell, payload)
		w.destroy(self, "хрупкий ствол лопнул при выстреле")
		return
	if is_silo():
		w.launch_orbit(payload, cell)
		return
	var target = w.machines[config.target]
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
	scatter *= (1.0 - w.robot.passive("aim"))
	var rng_tiles := range_for(p, w.planet) * factor
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
	l.append("Выстрел при %.1f атм" % fire_pressure(w))
	if not is_silo():
		l.append("Дальность при этом давлении: %.1f кл." % range_for(fire_pressure(w), w.planet))
		l.append("Цель: %s" % ("есть" if w.machines.has(config.target) else "нет"))
	return l
