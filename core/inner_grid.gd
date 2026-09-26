class_name InnerGrid
extends RefCounted
## Внутренность свёрнутого макроблока: своя сетка машин, газовая и логическая
## сети, свои капсулы. Предоставляет машинам тот же интерфейс, что и World.
## Родитель — мир или внутренность другого блока (блоки вкладываются).
## Груз, газ, события и эффекты уходят к родителю от клетки блока-хозяина и так
## всплывают до карты; робот, планета и база веществ — общие, от мира.

var machines := {}
var grid := {}
var gas := GasNet.new()
var logic := LogicNet.new()
var projectiles: Array = []
var size := Vector2i.ONE
var _parent: WeakRef
var _host: WeakRef
var _next_id := 1

var parent:
	get: return _parent.get_ref()
var world: World:
	get:
		var p = _parent.get_ref()
		return p if p is World else p.world
var host:
	get: return _host.get_ref()
var robot: RobotState:
	get: return world.robot
var planet: Planet:
	get: return world.planet
var db: SubstanceDB:
	get: return world.db
var rng: Rng:
	get: return world.rng
var stats: Dictionary:
	get: return world.stats
var event_mods: Dictionary:
	get: return world.event_mods

func _init(p_parent, h, p_size: Vector2i) -> void:
	_parent = weakref(p_parent)
	_host = weakref(h)
	size = p_size
	gas.atm_pressure = p_parent.planet.atm_pressure
	gas.ambient = p_parent.planet.ambient_temp

## Глубина вложенности: 1 — блок стоит на карте.
func depth() -> int:
	var p = parent
	return 1 if p is World else p.depth() + 1

func inside(c: Vector2i) -> bool:
	return Rect2i(Vector2i.ZERO, size).has_point(c)

func machine_at(c: Vector2i):
	var id = grid.get(c)
	return machines.get(id) if id != null else null

func machines_of(kind: String) -> Array:
	return machines.values().filter(func(m): return m.kind == kind)

func place(kind: String, c: Vector2i, facing: int, sub: Substance, quality: float, force_id: int = -1) -> Machine:
	var m := Machine.create(kind)
	m.id = force_id if force_id >= 0 else _next_id
	_next_id = max(_next_id, m.id + 1)
	m.cell = c
	m.facing = facing
	m.built_from = sub
	m.quality = quality
	m.stats = ComponentStats.compute(kind, sub, quality)
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
	return m

# ---- интерфейс, которым пользуются машины

func sub_label(s: Substance) -> String:
	return world.sub_label(s)

func time_factor() -> float:
	return world.time_factor()

func log_event(_c: Vector2i, text: String) -> void:
	parent.log_event(host.cell, "[%s] %s" % [host.display_name(), text])

func sound(name: String, _c: Vector2i) -> void:
	parent.sound(name, host.cell)

func on_processed(m: Machine, input: Portion, res: Dictionary) -> void:
	world.on_processed(m, input, res)

func observe(res: Dictionary, sub: Substance, _c = null) -> void:
	parent.observe(res, sub, host.cell)

func add_fx(kind: String, _c: Vector2i, col: Color = Color.WHITE, text: String = "") -> void:
	parent.add_fx(kind, host.cell, col, text)

func net_receiver(_c: Vector2i):
	return null

func handling_env(m, _ctx: String) -> Dictionary:
	var hot := false
	if m != null:
		for d in Machine.DIRS:
			var n = machine_at(m.cell + d)
			if n != null and n.hot:
				hot = true
	return {"planet": planet, "db": db, "rng": rng, "container": m.built_from if m != null else null,
		"neighbors": m.items if m != null else [], "hot_nearby": hot,
		"shield": robot.shield(), "safe_fire": robot.passive("safe_fire") > 0, "corrosion": world.event_mods.corrosion}

func drop_portions(_c: Vector2i, arr: Array) -> void:
	parent.drop_portions(host.cell, arr)

func destroy(m: Machine, reason: String) -> void:
	if not machines.has(m.id):
		return
	log_event(m.cell, "%s разрушен: %s" % [m.display_name(), reason])
	var all: Array = m.items.duplicate()
	for e in m.out_queue:
		all.append(e[0])
	if m is MacroMachine:
		all.append_array(m.all_contents())
	drop_portions(m.cell, all)
	machines.erase(m.id)
	grid.erase(m.cell)
	gas.remove_node(m.id)
	logic.remove_machine(m.id)
	Machine.drop_shot_links(machines, m.id)

func launch_orbit(payload: Array, _c: Vector2i) -> void:
	parent.launch_orbit(payload, host.cell)

func spawn_projectile(from: Vector2, to: Vector2, payload: Array, _orbit: bool = false, _kind: String = "capsule") -> void:
	projectiles.append({"to": to, "t": 0.0, "dur": 0.3 + from.distance_to(to) * 0.05, "payload": payload})

## Выход машины: внутрь блока — соседней машине, наружу — через порт хоста.
func push(src: Machine, p: Portion, c: Vector2i) -> bool:
	if inside(c):
		var t = machine_at(c)
		return t != null and t.accept(p, src.cell)
	return host.push_out(parent, src, p, c)

func tick(dt: float) -> void:
	# Внешний провод в блок: если у схемы есть сигнальные входы — идёт в них,
	# иначе выключает весь блок целиком.
	World.eval_logic(self, {MacroMachine.SIG_SOURCE: host.outer_signal})
	var off: bool = host.manual_off if host.has_sig_in() else not host.enabled
	if off:
		for m in machines.values():
			m.enabled = false
	World.tick_machines(self, dt)
	var keep: Array = []
	for pr in projectiles:
		pr.t += dt
		if pr.t < pr.dur:
			keep.append(pr)
			continue
		var c := Vector2i(floori(pr.to.x), floori(pr.to.y))
		var m = machine_at(c)
		for q in pr.payload:
			if m == null or not m.accept(q, m.cell + Machine.DIRS[(m.facing + 2) % 4]):
				drop_portions(c, [q])
	projectiles = keep
