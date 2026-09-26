class_name World
extends RefCounted
## Мир рана: планета, постройки, газовая и логическая сети, капсулы, дроны,
## порции на земле, робот, цель. Тикается фиксированным шагом из Sim.

const MACHINE_LIMIT := 60
const PICKUP_RADIUS := 0.8

var planet: Planet
var db: SubstanceDB
var gas := GasNet.new()
var logic := LogicNet.new()
var robot := RobotState.new()
var goals: GoalsTracker
var rng: Rng
var machines := {}              # id → Machine
var grid := {}                  # Vector2i → id
var ground := {}                # Vector2i → Array[Portion]
var projectiles: Array = []     # {from, to, t, dur, payload, orbit}
var drones: Array = []          # {src, dst, pos, cargo, speed, cap}
var drone_pending := -1
var revealed := {}              # клетки залежей, найденные сканером
var tile_overrides := {}        # Vector2i → {"tile", "t"}
var ice_stress := {}
var fires := {}                 # Vector2i → оставшееся время
var launched := {"mass": 0.0, "tags": {}, "exotic": 0.0}
var built_kinds := {}
var events: Array = []          # {"cell", "text", "t"} для интерфейса
var time := 0.0
var starter: Substance
var _next_id := 1
var _handling_acc := 0.0
var _hazard_acc := 0.0

static func create(seed_value: int) -> World:
	return World.new(PlanetGen.generate(seed_value))

func _init(p: Planet) -> void:
	planet = p
	db = p.db
	rng = Rng.new(p.seed_value).fork("world")
	gas.atm_pressure = p.atm_pressure
	gas.ambient = p.ambient_temp
	goals = GoalsTracker.new(self)
	starter = db.add(Substance.new("pod", "Сплав капсулы", ["metallic", "dense"], {"hard": 0.5, "melt": 100.0}))
	starter.name = "Сплав капсулы"
	robot.pos = Vector2(p.spawn) + Vector2(0.5, 0.5)
	robot.last_safe = p.spawn
	robot.add_item(Portion.new(starter, 60.0, p.ambient_temp))
	robot.analyzed[starter.id] = true
	for t in starter.tags:
		robot.known_tags[t] = true
	robot.hull = robot.new_module("hull", starter, 0.0)
	robot.drill = robot.new_module("hand_drill", starter, 0.0)
	robot.hp = robot.max_hp()
	robot.tank = robot.tank_cap() * 0.5
	log_event(p.spawn, "Посадка на %s. Цель: %s" % [p.name, p.goal.n])

# ---------------------------------------------------------------- утилиты

func log_event(cell: Vector2i, text: String) -> void:
	events.append({"cell": cell, "text": text, "t": time})
	if events.size() > 200:
		events.remove_at(0)

func time_factor() -> float:
	if planet.has_tag("temporal_drift"):
		return 1.0 + 0.5 * sin(time * 0.2)
	return 1.0

func tile(c: Vector2i) -> int:
	if tile_overrides.has(c):
		return tile_overrides[c].tile
	return planet.tile(c)

func walkable(c: Vector2i) -> bool:
	var t := tile(c)
	return t == Planet.Tile.GROUND or t == Planet.Tile.RUIN or t == Planet.Tile.ICE

func machine_at(c: Vector2i):
	var id = grid.get(c)
	return machines.get(id) if id != null else null

func machines_of(kind: String) -> Array:
	return machines.values().filter(func(m): return m.kind == kind)

func sub_label(s: Substance) -> String:
	if s == null:
		return "—"
	if robot.analyzed.has(s.id):
		return "%s [%s]" % [s.name, s.tag_names()]
	return "%s [?]" % s.name

func is_analyzed(s: Substance) -> bool:
	return robot.analyzed.has(s.id)

func stored_with_tag(tag: String) -> float:
	var s := 0.0
	for m in machines.values():
		if m.is_storage() or m is Cannon:
			for p in m.items:
				if p.has(tag):
					s += p.mass
	return s

func machine_limit() -> int:
	return MACHINE_LIMIT + int(robot.passive("machine_limit"))

func robot_cell() -> Vector2i:
	return robot.cell()

func near_robot(c: Vector2i, dist: float) -> bool:
	return (Vector2(c) + Vector2(0.5, 0.5)).distance_to(robot.pos) <= dist

# ---------------------------------------------------------------- знания

func discover_tag(t: String) -> void:
	if robot.known_tags.has(t):
		return
	robot.known_tags[t] = true
	var k := 1
	if MaterialTags.is_exotic(t):
		k = 3 * (2 if robot.passive("exotic_insight") > 0 else 1)
	robot.knowledge += k
	robot.xp.shaman += 5
	log_event(robot_cell(), "Новый тег: «%s» (+%d знаний)" % [MaterialTags.display(t), k])

func discover_interaction(key: String) -> void:
	if robot.known_interactions.has(key):
		return
	robot.known_interactions[key] = true
	robot.knowledge += 1
	robot.xp.shaman += 4
	var parts := key.split(">")
	var a := PlanetTags.display(parts[0]) if PlanetTags.TAGS.has(parts[0]) else MaterialTags.display(parts[0])
	log_event(robot_cell(), "Открыто взаимодействие: «%s» → «%s»" % [a, MaterialTags.display(parts[1])])

func analyze(s: Substance) -> void:
	if s == null:
		return
	if not robot.analyzed.has(s.id):
		robot.analyzed[s.id] = true
		robot.knowledge += 1
		robot.xp.shaman += 2
		log_event(robot_cell(), "Анализ: %s — %s" % [s.name, s.tag_names()])
	for t in s.tags:
		discover_tag(t)

## Вызывается процессором после цикла: теги, добавленные машиной, становятся известны.
func on_processed(m: Machine, input: Portion, res: Dictionary) -> void:
	for k in res.keys:
		discover_interaction(k)
	for o in res.outs:
		var s: Substance = o[0].substance
		if is_analyzed(input.substance) or s != input.substance:
			if is_analyzed(input.substance):
				robot.analyzed[s.id] = true
	for t in res.added:
		discover_tag(t)
	match m.kind:
		"furnace", "compressor", "decompressor", "sinter":
			robot.xp.firekeeper += 1.0
		"treater", "electrolyzer", "irradiator", "distiller":
			robot.xp.shaman += 0.5
		_:
			robot.xp.crafter += 0.5

# ---------------------------------------------------------------- постройки

func build_cost(kind: String) -> float:
	return Buildings.KINDS[kind].cost * (1.0 - robot.passive("build_discount"))

func can_place(kind: String, c: Vector2i, sub: Substance) -> String:
	if not robot.unlocked.has(kind):
		return "постройка не изучена"
	if not planet.buildable(c) or tile_overrides.has(c):
		return "здесь нельзя строить"
	if grid.has(c):
		return "клетка занята"
	if kind == "drill" and not planet.deposits.has(c):
		return "бур ставится на залежь"
	if machines.size() >= machine_limit():
		return "лимит машин (%d)" % machine_limit()
	if sub == null:
		return "не выбран материал"
	var err := Buildings.check_material(kind, sub, planet.ambient_temp)
	if err != "":
		return err
	if robot.mass_of(sub.id) + 0.001 < build_cost(kind):
		return "нужно %.1f кг материала" % build_cost(kind)
	return ""

func place(kind: String, c: Vector2i, facing: int, sub: Substance, free: bool = false) -> Machine:
	if not free:
		if can_place(kind, c, sub) != "":
			return null
		robot.take_item(sub.id, build_cost(kind))
	var m := Machine.create(kind)
	m.id = _next_id
	_next_id += 1
	m.cell = c
	m.facing = facing
	m.built_from = sub
	m.stats = ComponentStats.compute(kind, sub, robot.passive("quality"))
	m.hp = m.max_hp()
	machines[m.id] = m
	grid[c] = m.id
	if m.has_gas():
		gas.add_node(m.id, m.info.gas, m.stats.max_p)
		for d in Machine.DIRS:
			var n = machine_at(c + d)
			if n != null and n.has_gas():
				gas.connect_nodes(m.id, n.id)
		if kind == "decompressor":
			gas.set_vent(m.id, true)
	if m is Dome:
		m.temp = planet.ambient_temp
	robot.xp.crafter += 1.0
	if kind in ["sensor", "gate_and", "gate_or", "gate_not"]:
		robot.xp.chief += 2.0
	if not built_kinds.has(kind):
		built_kinds[kind] = true
		robot.knowledge += 1
	return m

func remove_at(c: Vector2i, refund: bool = true) -> void:
	var m = machine_at(c)
	if m == null:
		return
	if refund:
		robot.add_item(Portion.new(m.built_from, build_cost(m.kind) * 0.5, planet.ambient_temp))
	_drop_contents(m)
	_erase(m)

func destroy(m: Machine, reason: String) -> void:
	if not machines.has(m.id):
		return
	log_event(m.cell, "%s разрушен: %s" % [m.display_name(), reason])
	_drop_contents(m)
	_erase(m)

func _drop_contents(m: Machine) -> void:
	var all: Array = m.items.duplicate()
	for e in m.out_queue:
		all.append(e[0])
	if m is Processor:
		if m.busy != null: all.append(m.busy)
		if m.reagent != null: all.append(m.reagent)
	drop_portions(m.cell, all)

func _erase(m: Machine) -> void:
	machines.erase(m.id)
	grid.erase(m.cell)
	gas.remove_node(m.id)
	logic.remove_machine(m.id)
	for c in machines.values():
		if c is Cannon and c.config.target == m.id:
			c.config.target = -1
	drones = drones.filter(func(d): return d.src != m.id and d.dst != m.id)

func rotate_at(c: Vector2i) -> void:
	var m = machine_at(c)
	if m != null:
		m.facing = (m.facing + 1) % 4

## Передать порцию машине в клетке (выход машины src).
func push(src: Machine, p: Portion, c: Vector2i) -> bool:
	var t = machine_at(c)
	if t == null:
		return false
	return t.accept(p, src.cell)

func drop_portions(c: Vector2i, arr: Array) -> void:
	for p in arr:
		if p != null and p.mass > 0.001:
			if not ground.has(c):
				ground[c] = []
			var merged := false
			for q in ground[c]:
				if q.substance == p.substance:
					q.absorb(p)
					merged = true
					break
			if not merged:
				ground[c].append(p)

func link_cannon(cannon_cell: Vector2i, target_cell: Vector2i) -> String:
	var c = machine_at(cannon_cell)
	var t = machine_at(target_cell)
	if c == null or not c is Cannon or c.is_silo():
		return "это не пневмопушка"
	if t == null or t.capacity() <= 0.0 or t == c:
		return "цель должна принимать груз (приёмник, контейнер, бак…)"
	c.config.target = t.id
	return ""

## Провод от выхода одной машины ко входу другой.
func add_wire(from_cell: Vector2i, to_cell: Vector2i, port: int, sub: Substance, points: Array = []) -> String:
	var a = machine_at(from_cell)
	var b = machine_at(to_cell)
	if a == null or b == null or a == b:
		return "провод соединяет две машины"
	if sub == null:
		return "нужен материал для провода"
	var st := ComponentStats.compute("wire", sub, robot.passive("quality"))
	var poly := LogicNet.polyline(Vector2(from_cell), points, Vector2(to_cell))
	var length := LogicNet.length_of(poly)
	var max_len: float = st.wire_range * (1.0 + robot.passive("wire_range")) * (2.0 if robot.has_module("relay") else 1.0)
	if not st.wireless and length > max_len:
		return "провод из этого материала дотягивается на %.0f кл." % max_len
	var cost: float = max(0.5, length * 0.1)
	if robot.mass_of(sub.id) < cost:
		return "нужно %.1f кг материала" % cost
	robot.take_item(sub.id, cost)
	logic.add_wire(a.id, b.id, port, points, sub.id)
	robot.xp.chief += 2.0
	return ""

# ---------------------------------------------------------------- робот

func move_robot(delta: Vector2) -> void:
	var steps := int(ceil(delta.length() / 0.25))
	for i in steps:
		var d := delta / steps
		var np := robot.pos + d
		if walkable(Vector2i(floori(np.x), floori(robot.pos.y))):
			robot.pos.x = np.x
		if walkable(Vector2i(floori(robot.pos.x), floori(np.y))):
			robot.pos.y = np.y

func robot_speed() -> float:
	return clamp(5.5 * 80.0 / robot.total_mass(), 2.5, 8.0)

## Ручная добыча залежи рядом с роботом.
func mine(c: Vector2i, dt: float) -> String:
	if not near_robot(c, 2.2):
		return "слишком далеко"
	var dep = planet.deposits.get(c)
	if dep == null or dep.amount <= 0.0:
		return "здесь нет залежи"
	var sub: Substance = db.get_sub(dep.sub)
	if robot.mining_hardness() + 0.5 < sub.hardness:
		return "бур слишком мягкий: нужна твёрдость %.1f (у вас %.1f)" % [sub.hardness, robot.mining_hardness()]
	robot.mine_progress += dt * (1.0 + robot.passive("mine_speed"))
	if robot.mine_progress >= 1.0:
		robot.mine_progress = 0.0
		var m: float = min(1.0, dep.amount)
		dep.amount -= m
		var p := Portion.new(sub, m, planet.ambient_temp)
		robot.xp.gatherer += 1.0
		if robot.passive("auto_analyze") > 0:
			analyze(sub)
		if not robot.can_carry(p):
			drop_portions(c, [p])
			return "это %s — без газозаборника не унести, ставьте бур и бак" % Substance.PHASE_NAMES[p.phase()]
		robot.add_item(p)
	return ""

## Подкачать бортовой баллон: из газовой машины рядом или вручную из атмосферы.
func refill_robot(dt: float) -> String:
	var cap := robot.tank_cap()
	if robot.tank >= cap:
		return "баллон полон"
	for m in machines.values():
		if m.has_gas() and near_robot(m.cell, 1.8) and gas.pressure(m.id) > 1.05:
			var got := gas.take_gas(m.id, min(3.0 * dt, cap - robot.tank))
			robot.tank += got
			if got > 0.0:
				return ""
	robot.tank = min(cap, robot.tank + 0.4 * planet.atm_pressure * dt)
	return ""

func insert_into(c: Vector2i, as_reagent: bool, amount: float = 1.0) -> String:
	var m = machine_at(c)
	if m == null:
		return "здесь нет машины"
	if not near_robot(c, 2.2):
		return "слишком далеко"
	if robot.selected == "":
		return "не выбран материал"
	var p := robot.take_item(robot.selected, amount)
	if p == null:
		return "нет материала"
	var side: int = (m.facing + 3) % 4 if as_reagent else (m.facing + 2) % 4
	if not m.accept(p, m.cell + Machine.DIRS[side]):
		robot.add_item(p)
		return "машина не принимает"
	return ""

func take_from(c: Vector2i) -> String:
	var m = machine_at(c)
	if m == null:
		return "здесь нет машины"
	if not near_robot(c, 2.2):
		return "слишком далеко"
	var keep: Array = []
	for p in m.items:
		if robot.can_carry(p):
			robot.add_item(p)
		else:
			keep.append(p)
	m.items = keep
	return "" if keep.is_empty() else "жидкости и газы без газозаборника не унести"

func fabricate(kind: String, sub: Substance) -> String:
	var near := false
	for m in machines_of("fabricator"):
		if near_robot(m.cell, 2.5):
			near = true
	if not near:
		return "подойдите к фабрикатору"
	if not robot.blueprints.has(kind):
		return "чертёж не изучен"
	var err := Modules.check_material(kind, sub, planet.ambient_temp)
	if err != "":
		return err
	var cost: float = Modules.MODULES[kind].cost
	if robot.mass_of(sub.id) < cost:
		return "нужно %.1f кг" % cost
	robot.take_item(sub.id, cost)
	robot.modules.append(robot.new_module(kind, sub, robot.passive("quality")))
	robot.xp.crafter += 5.0
	log_event(robot_cell(), "Изготовлен модуль: %s из %s" % [Modules.MODULES[kind].n, sub.name])
	return ""

func robot_die() -> void:
	log_event(robot_cell(), "Робот разрушен! Восстановление в капсуле, половина груза потеряна.")
	var lost: Array = []
	for id in robot.inventory.keys():
		var p: Portion = robot.inventory[id]
		lost.append(p.split(p.mass * 0.5))
	drop_portions(robot_cell(), lost)
	robot.pos = Vector2(planet.spawn) + Vector2(0.5, 0.5)
	robot.hp = robot.max_hp()

# ---------------------------------------------------------------- капсулы

func spawn_projectile(from: Vector2, to: Vector2, payload: Array, orbit: bool = false, kind: String = "capsule") -> void:
	var dist := from.distance_to(to)
	projectiles.append({"from": from, "to": to, "t": 0.0, "dur": 0.4 + dist * 0.07, "payload": payload, "orbit": orbit, "kind": kind})

func launch_orbit(payload: Array, c: Vector2i) -> void:
	var total := 0.0
	for p in payload:
		total += p.mass
		launched.mass += p.mass
		for t in p.substance.tags:
			launched.tags[t] = launched.tags.get(t, 0.0) + p.mass
		if p.substance.is_exotic():
			launched.exotic += p.mass
	var from := Vector2(c) + Vector2(0.5, 0.5)
	projectiles.append({"from": from, "to": from + Vector2(0, -30), "t": 0.0, "dur": 2.0, "payload": [], "orbit": true, "kind": "rocket"})
	robot.xp.chief += 2.0
	log_event(c, "На орбиту отправлено %.1f кг" % total)

func _land(pr: Dictionary) -> void:
	if pr.orbit:
		return
	var c := Vector2i(floori(pr.to.x), floori(pr.to.y))
	var payload: Array = pr.payload
	if robot.has_module("magnet") and robot.pos.distance_to(pr.to) < 3.0:
		for p in payload:
			if robot.can_carry(p):
				robot.add_item(p)
		log_event(c, "Магнитный захват поймал капсулу")
		return
	if pr.kind == "shot":
		var dep = planet.deposits.get(c)
		if dep != null:
			var s: Substance = db.get_sub(dep.sub)
			if s.has("brittle") or s.has("crystalline"):
				var m: float = min(3.0, dep.amount)
				dep.amount -= m
				drop_portions(c, [Portion.new(s, m, planet.ambient_temp)])
				log_event(c, "Выстрел расколол залежь %s" % s.name)
		for p in payload:
			if p.has("flammable") or p.has("pyrophoric"):
				fires[c] = 6.0
	var extra: Array = []
	for p in payload:
		var r := Handling.event(p, "impact", handling_env(null, "impact"))
		extra.append_array(r.spawn)
	payload.append_array(extra)
	var m = machine_at(c)
	var rest: Array = []
	for p in payload:
		if m == null or not m.accept(p, m.cell + Machine.DIRS[(m.facing + 2) % 4]):
			rest.append(p)
	if not rest.is_empty():
		drop_portions(c, rest)
		if m == null:
			log_event(c, "Капсула упала мимо цели")

# ---------------------------------------------------------------- тик

func tick(dt: float) -> void:
	time += dt
	_tick_logic()
	for m in machines.values().duplicate():
		if machines.has(m.id):
			m.tick(self, dt)
			if machines.has(m.id):
				m.flush_outputs(self)
	for id in gas.step(dt):
		if machines.has(id):
			destroy(machines[id], "не выдержал давления %.1f атм" % gas.pressure(id))
	_tick_projectiles(dt)
	_tick_drones(dt)
	_handling_acc += dt
	if _handling_acc >= 0.5:
		_tick_handling(_handling_acc)
		_handling_acc = 0.0
	_tick_robot(dt)
	_tick_world_hazards(dt)
	goals.tick(dt)

func _tick_logic() -> void:
	var out := {}
	for m in machines.values():
		if m is LogicGate:
			out[m.id] = m.compute(self)
		elif m.signal_out:
			out[m.id] = true
	logic.outputs = out
	for m in machines.values():
		if m is LogicGate:
			continue
		var wired := logic.has_input(m.id, 0)
		m.enabled = (logic.input(m.id, 0) if wired else true) and not m.manual_off

func _tick_projectiles(dt: float) -> void:
	var keep: Array = []
	for pr in projectiles:
		pr.t += dt
		if pr.t >= pr.dur:
			_land(pr)
		else:
			keep.append(pr)
	projectiles = keep

func _tick_drones(dt: float) -> void:
	for d in drones:
		var src = machines.get(d.src)
		var dst = machines.get(d.dst)
		if src == null or dst == null:
			continue
		var target: Vector2 = (Vector2(dst.cell) if d.cargo != null else Vector2(src.cell)) + Vector2(0.5, 0.5)
		var to: Vector2 = target - d.pos
		var step: float = d.speed * dt
		if to.length() > step:
			d.pos += to.normalized() * step
			continue
		d.pos = target
		if d.cargo == null:
			if not src.items.is_empty():
				var p: Portion = src.items[0]
				d.cargo = p.split(min(d.cap, p.mass))
				if p.mass <= 0.001:
					src.items.remove_at(0)
		else:
			if dst.accept(d.cargo, dst.cell + Machine.DIRS[(dst.facing + 2) % 4]):
				d.cargo = null

func handling_env(m, ctx: String) -> Dictionary:
	var hot := false
	if m != null:
		for d in Machine.DIRS:
			var n = machine_at(m.cell + d)
			if n != null and n.hot:
				hot = true
	return {"planet": planet, "db": db, "rng": rng, "container": m.built_from if m != null else null,
		"neighbors": m.items if m != null else [], "hot_nearby": hot,
		"shield": robot.shield(), "safe_fire": robot.passive("safe_fire") > 0}

func _apply_handling_result(res: Dictionary, c: Vector2i) -> void:
	for k in res.discovered:
		discover_interaction(k)
	if res.fire:
		fires[c] = max(fires.get(c, 0.0), 1.5)
	for e in res.events:
		log_event(c, e)

func _tick_handling(dt: float) -> void:
	for m in machines.values().duplicate():
		if not machines.has(m.id):
			continue
		m.signal_out = false
		if m.stats.self_repair > 0.0:
			m.hp = min(m.max_hp(), m.hp + m.stats.self_repair * dt)
		if m.items.is_empty():
			continue
		var env := handling_env(m, m.handling_ctx())
		var spawn: Array = []
		for p in m.items:
			var res := Handling.tick(p, m.handling_ctx(), env, dt)
			m.hp -= res.container_damage * m.stats.wear
			spawn.append_array(res.spawn)
			if res.signal:
				m.signal_out = true
			if res.absorb_gas > 0.0 and m.has_gas():
				gas.take_gas(m.id, res.absorb_gas)
			if m.stats.leaky:
				p.mass *= 1.0 - min(1.0, 0.05 * dt)
			_apply_handling_result(res, m.cell)
		m.items = m.items.filter(func(p): return p.mass > 0.01)
		for p in spawn:
			if not m.accept(p, m.cell):
				drop_portions(m.cell, [p])
		if m.hp <= 0.0:
			destroy(m, "разъеден грузом")
	# Порции на земле.
	for c in ground.keys():
		var arr: Array = ground[c]
		var env := {"planet": planet, "db": db, "rng": rng, "container": null, "neighbors": arr,
			"hot_nearby": fires.has(c) or _hot_near(c), "shield": {}}
		var crawl := false
		for p in arr:
			var res := Handling.tick(p, "ground", env, dt)
			_apply_handling_result(res, c)
			if res.crawl:
				crawl = true
			if fires.has(c) and (p.has("flammable") or p.has("pyrophoric")):
				p.mass -= 0.1 * dt * p.mass
				fires[c] = 2.0
		arr = arr.filter(func(p): return p.mass > 0.01)
		if arr.is_empty():
			ground.erase(c)
		else:
			ground[c] = arr
			if crawl:
				_crawl(c)
	# Груз робота.
	var renv := {"planet": planet, "db": db, "rng": rng, "container": null, "neighbors": [],
		"hot_nearby": false, "shield": robot.shield(), "safe_fire": robot.passive("safe_fire") > 0}
	for id in robot.inventory.keys():
		var p: Portion = robot.inventory[id]
		var res := Handling.tick(p, "carried", renv, dt)
		robot.damage(res.robot_damage)
		robot.xp.hunter += res.robot_damage * 0.2
		_apply_handling_result(res, robot_cell())
		if p.substance.id != id:
			robot.inventory.erase(id)
			robot.add_item(p)
		elif p.mass <= 0.01:
			robot.inventory.erase(id)
	if robot.selected != "" and not robot.inventory.has(robot.selected):
		robot.cycle_selected(0)

func _hot_near(c: Vector2i) -> bool:
	for d in Machine.DIRS:
		var n = machine_at(c + d)
		if n != null and n.hot:
			return true
	return false

## Привязанный материал сам ползёт к ближайшей машине, где лежит такой же.
func _crawl(c: Vector2i) -> void:
	var arr: Array = ground[c]
	var p: Portion = arr[0]
	var best = null
	var best_d := 12.0
	for m in machines.values():
		for q in m.items:
			if q.substance == p.substance:
				var d := Vector2(m.cell - c).length()
				if d < best_d:
					best_d = d
					best = m
	if best == null:
		return
	var step := Vector2i(signi(best.cell.x - c.x), signi(best.cell.y - c.y))
	var nc := c + step
	if nc == best.cell:
		if best.accept(p, c):
			arr.erase(p)
			if arr.is_empty():
				ground.erase(c)
		return
	arr.erase(p)
	if arr.is_empty():
		ground.erase(c)
	drop_portions(nc, [p])

func _tick_robot(dt: float) -> void:
	for k in robot.cooldowns.keys():
		robot.cooldowns[k] -= dt
		if robot.cooldowns[k] <= 0.0:
			robot.cooldowns.erase(k)
	var c := robot_cell()
	var t := tile(c)
	var sh := robot.shield()
	if t == Planet.Tile.ICE and not tile_overrides.has(c):
		ice_stress[c] = ice_stress.get(c, 0.0) + dt * robot.total_mass() / 60.0
		if ice_stress[c] > 2.5:
			planet.set_tile(c, Planet.Tile.CHASM)
			ice_stress.erase(c)
			log_event(c, "Лёд проломился!")
			robot.damage(10.0)
			robot.pos = Vector2(robot.last_safe) + Vector2(0.5, 0.5)
	elif walkable(c):
		robot.last_safe = c
	if not walkable(c):
		# Робот оказался на лаве/кислоте (растаял мост) — выталкиваем.
		robot.damage(15.0)
		robot.pos = Vector2(robot.last_safe) + Vector2(0.5, 0.5)
	if fires.has(c):
		robot.damage(3.0 * dt * (1.0 - sh.heat))
	# Подбор порций с земли.
	if ground.has(c):
		var keep: Array = []
		for p in ground[c]:
			if robot.can_carry(p):
				robot.add_item(p)
				if robot.passive("auto_analyze") > 0:
					analyze(p.substance)
			else:
				keep.append(p)
		if keep.is_empty():
			ground.erase(c)
		else:
			ground[c] = keep
	# Отдых у фабрикатора.
	for m in machines_of("fabricator"):
		if near_robot(m.cell, 3.0):
			robot.hp = min(robot.max_hp(), robot.hp + 2.0 * dt)
	# Радиоактивные постройки облучают рядом.
	for m in machines.values():
		if m.stats.radiation > 0.0 and near_robot(m.cell, 2.5):
			robot.damage(m.stats.radiation * dt * (1.0 - sh.radiation))
	if robot.hp <= 0.0:
		robot_die()

func _tick_world_hazards(dt: float) -> void:
	for c in tile_overrides.keys():
		tile_overrides[c].t -= dt
		if tile_overrides[c].t <= 0.0:
			tile_overrides.erase(c)
	for c in fires.keys():
		fires[c] -= dt
		if fires[c] <= 0.0:
			fires.erase(c)
	var sh := robot.shield()
	var hz := 0.0
	if planet.has_tag("radiation"):
		hz += 0.25 * (1.0 - sh.radiation)
	if planet.has_tag("toxic_atmosphere"):
		hz += 0.15 * (1.0 - sh.toxic)
	if planet.has_tag("acid_rain"):
		hz += 0.1 * (1.0 - sh.acid)
	if planet.ambient_temp > 60.0 or planet.ambient_temp < -60.0:
		hz += 0.15 * (1.0 - sh.heat)
	robot.damage(hz * dt)
	robot.xp.hunter += hz * dt * 0.2
	_hazard_acc += dt
	if _hazard_acc < 10.0:
		return
	_hazard_acc = 0.0
	var list: Array = machines.values()
	if list.is_empty():
		return
	if planet.has_tag("storms") and rng.chance(0.5):
		var m: Machine = rng.pick(list)
		if not m.stats.storm_proof:
			m.hp -= 15.0 * m.stats.wear
			log_event(m.cell, "Буря повредила %s" % m.display_name())
			if m.hp <= 0.0:
				destroy(m, "буря")
	if planet.has_tag("seismic") and rng.chance(0.35):
		var pipes: Array = list.filter(func(x): return x.kind == "pipe" and not x.stats.storm_proof)
		if not pipes.is_empty():
			destroy(rng.pick(pipes), "землетрясение")
