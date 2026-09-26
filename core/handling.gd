class_name Handling
## Применяет HandlingRules к порции в любом месте мира: в контейнере, на земле,
## в капсуле, в руках робота. Мутирует порцию и возвращает побочные эффекты.
##
## env:
##   planet: Planet, db: SubstanceDB, rng: Rng
##   container: Substance | null — материал стенок контейнера
##   neighbors: Array[Portion] — другие порции в том же контейнере
##   hot_nearby: bool — рядом работает горячая машина
##   shield: {toxic, radiation, heat} — защита робота 0..1
##   safe_fire: bool — навык Хранителя огня

const EVENT_CTX := ["launch", "impact"]
const CORROSION_PROOF := ["insulating", "crystalline", "anchoring"]

static func new_result() -> Dictionary:
	return {"lost": 0.0, "spawn": [], "jammed": null, "robot_damage": 0.0, "container_damage": 0.0,
		"fire": false, "signal": false, "absorb_gas": 0.0, "crawl": false, "events": [], "discovered": []}

## Непрерывные эффекты за dt секунд.
static func tick(p: Portion, ctx: String, env: Dictionary, dt: float) -> Dictionary:
	var res := new_result()
	if p.mass <= 0.0:
		return res
	var planet: Planet = env.planet
	var rng: Rng = env.rng
	var lag := 0.2 if p.has("chrono_lagged") else 1.0
	dt *= lag

	_relax_temperature(p, ctx, env, dt)
	var phase := p.phase()
	var mass0 := p.mass

	# Газ на открытом воздухе улетает, жидкость на земле впитывается.
	if ctx == "open" or ctx == "ground":
		if phase == Substance.Phase.GAS:
			res.lost += mass0 * 0.5 * dt
		elif phase == Substance.Phase.LIQUID and ctx == "ground":
			res.lost += mass0 * 0.05 * dt
	if ctx == "carried" and p.temp > 200.0:
		res.robot_damage += 0.5 * dt * (1.0 - env.get("shield", {}).get("heat", 0.0))

	for tag in p.substance.tags:
		for r in HandlingRules.rules_for(tag):
			if not ctx in r.ctx:
				continue
			if r.has("planet"):
				var ok := false
				for pt in r.planet:
					if planet.has_tag(pt):
						ok = true
				if not ok:
					continue
			_apply(r, p, mass0, phase, ctx, env, dt, res)

	# Среда планеты действует на открыто лежащие порции через таблицу взаимодействий.
	if (ctx == "open" or ctx == "ground") and rng.chance(0.03 * dt):
		var ir := Interactions.apply(planet.tags, p.substance.tags, true)
		if ir.tags != p.substance.tags:
			p.substance = env.db.derive(p.substance, ir.tags)
			for k in ir.keys:
				res.discovered.append(k)
			res.events.append("среда изменила %s" % p.substance.name)

	p.mass = max(0.0, p.mass - res.lost)
	return res

## Разовые эффекты: выстрел, удар.
static func event(p: Portion, ctx: String, env: Dictionary) -> Dictionary:
	var res := new_result()
	if p.mass <= 0.0:
		return res
	var mass0 := p.mass
	for tag in p.substance.tags:
		for r in HandlingRules.rules_for(tag):
			if ctx in r.ctx:
				_apply(r, p, mass0, p.phase(), ctx, env, 1.0, res)
	return res

static func _relax_temperature(p: Portion, ctx: String, env: Dictionary, dt: float) -> void:
	var k := 0.05
	var cont = env.get("container")
	if ctx == "sealed" or ctx == "open":
		k = 0.03
		if cont != null and cont.has("insulating"):
			k = 0.006
	var target: float = env.planet.ambient_temp
	p.temp += (target - p.temp) * min(1.0, k * dt)

static func _apply(r: Dictionary, p: Portion, mass0: float, phase: int, ctx: String, env: Dictionary, dt: float, res: Dictionary) -> void:
	var planet: Planet = env.planet
	var db: SubstanceDB = env.db
	var rng: Rng = env.rng
	var cont = env.get("container")
	var shield: Dictionary = env.get("shield", {})
	var rate: float = r.rate
	match r.effect:
		"evaporate":
			var f := 0.1 if phase == Substance.Phase.SOLID else 1.0
			res.lost += mass0 * rate * f * dt
		"ignite":
			var lit := false
			if r.get("oxidizing", false) and planet.oxidizing():
				lit = true
			if not r.get("always", false) and env.get("hot_nearby", false):
				lit = true
			if ctx == "carried" and env.get("safe_fire", false):
				lit = false
			if lit:
				res.lost += mass0 * rate * dt
				p.temp += 40.0 * dt
				res.fire = true
				if ctx == "carried":
					res.robot_damage += 1.5 * dt * (1.0 - shield.get("heat", 0.0))
		"shatter":
			var dust := p.split(mass0 * rate)
			var tags := dust.substance.tags.duplicate()
			tags.erase("crystalline")
			tags = MaterialTags.add_tag(tags, "porous")
			dust.substance = db.derive(dust.substance, tags)
			res.spawn.append(dust)
			res.events.append("%s раскололся" % p.substance.name)
		"corrode":
			if cont == null:
				return
			for t in CORROSION_PROOF:
				if cont.has(t):
					return
			res.container_damage += rate * env.get("corrosion", 1.0) * dt * min(1.0, mass0 / 5.0)
		"phase_leak":
			if cont != null and cont.has("anchoring"):
				return
			res.lost += mass0 * rate * dt
		"float_away":
			res.lost += mass0 * rate * dt
		"irradiate":
			res.robot_damage += rate * dt * min(2.0, mass0 / 5.0) * (1.0 - shield.get("radiation", 0.0))
		"warm":
			p.temp += rate * dt
		"absorb_water":
			p.mass += mass0 * rate * dt
			if rng.chance(rate * 2.0 * dt):
				var tags := p.substance.tags.duplicate()
				tags.erase("hygroscopic")
				p.substance = db.derive(p.substance, tags)
				res.events.append("%s насытился водой" % p.substance.name)
		"poison":
			res.robot_damage += rate * dt * (1.0 - shield.get("toxic", 0.0))
		"jam":
			res.jammed = p.split(mass0 * rate)
		"replicate":
			for n in env.get("neighbors", []):
				if n == p or n.substance == p.substance or n.mass <= 0.0:
					continue
				var take := minf(n.mass, mass0 * rate * dt)
				n.mass -= take
				p.mass += take
		"mimic":
			if rng.chance(rate * dt):
				var pool: Array = []
				for n in env.get("neighbors", []):
					if n == p:
						continue
					for t in n.substance.tags:
						if not t in p.substance.tags and t != "mimetic":
							pool.append(t)
				if not pool.is_empty():
					pool.sort()
					var t: String = rng.pick(pool)
					p.substance = db.derive(p.substance, MaterialTags.add_tag(p.substance.tags, t))
					res.events.append("%s перенял «%s»" % [p.substance.name, MaterialTags.display(t)])
		"echo":
			var copy := Portion.new(p.substance, mass0 * rate, p.temp)
			var tags := p.substance.tags.duplicate()
			tags.erase("echoing")
			copy.substance = db.derive(p.substance, tags)
			res.spawn.append(copy)
			res.events.append("%s отозвался эхом" % p.substance.name)
		"crawl":
			res.crawl = true
		"emit_signal":
			res.signal = true
		"absorb_gas":
			res.absorb_gas += rate * dt * min(3.0, mass0 / 5.0)
		"lag":
			pass

## Множитель дальности пушки для груза.
static func cannon_range_factor(p: Portion, planet: Planet) -> float:
	var f := 1.0
	for t in HandlingRules.CANNON:
		var d: Dictionary = HandlingRules.CANNON[t]
		if p.has(t) and d.has("range"):
			f *= d.range
	return f

## Разброс попадания в клетках.
static func cannon_scatter(p: Portion, planet: Planet) -> float:
	var s := 0.0
	for t in HandlingRules.CANNON:
		var d: Dictionary = HandlingRules.CANNON[t]
		if p.has(t) and d.has("scatter") and planet.has_tag(d.get("planet", "")):
			s += d.scatter
	if planet.has_tag("storms"):
		s += 1.5
	return s
