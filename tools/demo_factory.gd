class_name DemoFactory
## Демонстрационный завод для скриншотов и замеров производительности.
## Блок 8×6 клеток, 13 машин: подача → печь с насосом → контейнер, трубы к баку,
## подача → дробилка → контейнер, открытый контейнер с летучим. Блоки — сеткой.

const BLOCK := 13
const BW := 8
const BH := 6

## Строит завод из n машин (кратно блоку, последний блок — сколько влезет).
## Возвращает центр завода в клетках.
static func build(w: World, origin: Vector2i, n: int = BLOCK) -> Vector2:
	var blocks := int(ceil(float(n) / BLOCK))
	var cols := int(ceil(sqrt(float(blocks))))
	var rows := int(ceil(float(blocks) / cols))
	for dy in range(-1, rows * BH + 1):
		for dx in range(-1, cols * BW + 1):
			var q := origin + Vector2i(dx, dy)
			if q.x <= 0 or q.y <= 0 or q.x >= w.planet.width - 1 or q.y >= w.planet.height - 1:
				continue
			w.planet.set_tile(q, Planet.Tile.GROUND)
			w.planet.deposits.erase(q)
	var ore := w.db.get_sub("demo_ore")
	if ore == null:
		ore = w.db.add(Substance.new("demo_ore", "Демит", ["brittle", "flammable"]))
	var vol := w.db.get_sub("demo_gas")
	if vol == null:
		vol = w.db.add(Substance.new("demo_gas", "Летан", ["volatile", "organic"]))
	var left := n
	for b in blocks:
		var o := origin + Vector2i((b % cols) * BW, (b / cols) * BH)
		left -= _block(w, o, ore, vol, left)
	return Vector2(origin) + Vector2(cols * BW, rows * BH) / 2.0

static func _block(w: World, o: Vector2i, ore: Substance, vol: Substance, budget: int) -> int:
	var plan: Array = [
		["container", Vector2i(0, 0)], ["furnace", Vector2i(1, 0)], ["container", Vector2i(2, 0)],
		["pump", Vector2i(1, 1)], ["pipe", Vector2i(1, 2)], ["pipe", Vector2i(2, 2)], ["pipe", Vector2i(3, 2)],
		["pipe", Vector2i(4, 2)], ["tank", Vector2i(5, 2)], ["container", Vector2i(4, 0)],
		["crusher", Vector2i(5, 0)], ["container", Vector2i(6, 0)], ["container", Vector2i(3, 4)],
	]
	var made := 0
	for i in plan.size():
		if made >= budget:
			break
		var m := w.place(plan[i][0], o + plan[i][1], 0, w.starter, true)
		if m == null:
			continue
		made += 1
		match i:
			0, 9:
				m.config.pass_through = true
				m.store(Portion.new(ore, 40.0))
			3:
				m.config.target_p = 6.0
			12:
				m.store(Portion.new(vol, 20.0))
	return made

# ---------------------------------------------------------------- витрина для 3D-вида

## Все виды машин рядами (включая склад и пневмобатарею 2×2), а ближе к роботу —
## подвижное: пушка стреляет капсулами в приёмник, дроны возят груз между
## контейнерами, горит огонь, на земле лежат порции, датчик с проводом к «И»,
## шахта пускает ракеты, рядом идёт зона метеоров. Возвращает точку для робота.
static func showcase(w: World, origin: Vector2i) -> Vector2:
	var kinds: Array = []
	for k in Buildings.KINDS:
		if not k in ["macro", "warehouse_section", "battery_section"]:
			kinds.append(k)
	const PER_ROW := 9
	var rows := int(ceil(float(kinds.size()) / PER_ROW))
	var area := Rect2i(origin - Vector2i(2, 2), Vector2i(PER_ROW * 2 + 12, rows * 2 + 18))
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			var q := Vector2i(x, y)
			if q.x <= 0 or q.y <= 0 or q.x >= w.planet.width - 1 or q.y >= w.planet.height - 1:
				continue
			w.planet.set_tile(q, Planet.Tile.GROUND)
			w.planet.deposits.erase(q)
	var ore := _sub(w, "demo_ore", "Демит", ["brittle", "flammable"])
	var liq := _sub(w, "demo_liq", "Текучка", ["organic"])
	liq.melt = -40.0
	liq.boil = 300.0
	var metal := _sub(w, "demo_metal", "Сплавит", ["metallic", "conductive"])
	var rock := _sub(w, "demo_rock", "Пемзит", ["porous"])
	for i in kinds.size():
		var c := origin + Vector2i((i % PER_ROW) * 2, (i / PER_ROW) * 2)
		var m := w.place(kinds[i], c, 1, metal if kinds[i] in ["electrolyzer", "beacon"] else w.starter, true)
		if m != null and m.capacity() > 0.0 and not kinds[i] in ["launch_silo"]:
			m.store(Portion.new(metal, m.capacity() * 0.5))
	# Склад и батарея: по четыре секции квадратом.
	var y0 := origin.y + rows * 2
	for kd in [["warehouse_section", 0], ["battery_section", 3]]:
		for d in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]:
			w.place(kd[0], Vector2i(origin.x + 20, origin.y + kd[1]) + d, 1, w.starter, true)
	# Подвижное — южнее рядов, ближе к камере.
	var s := Vector2i(origin.x, y0 + 2)
	var cannon := w.place("cannon", s, 0, w.starter, true)
	var recv := w.place("receiver", s + Vector2i(9, 0), 0, w.starter, true)
	var src := w.place("container", s + Vector2i(0, 4), 0, w.starter, true)
	var dst := w.place("container", s + Vector2i(8, 6), 0, w.starter, true)
	var silo := w.place("launch_silo", s + Vector2i(14, 3), 0, w.starter, true)
	var sensor := w.place("sensor", s + Vector2i(3, 8), 0, w.starter, true)
	var gate := w.place("gate_and", s + Vector2i(6, 8), 0, w.starter, true)
	if sensor != null and gate != null:
		w.logic.add_wire(sensor.id, gate.id, 0, [Vector2(s.x + 4.5, s.y + 9.5)])
		w.logic.outputs[sensor.id] = true
	for i in 3:
		w.ground[s + Vector2i(11 + i, 7)] = [Portion.new(rock, 3.0 + i * 3.0), Portion.new(liq, 4.0), Portion.new(metal, 2.0 + i)]
	w.meta["showcase"] = {"cannon": cannon.id if cannon else -1, "recv": recv.id if recv else -1,
		"src": src.id if src else -1, "dst": dst.id if dst else -1, "silo": silo.id if silo else -1,
		"fires": [s + Vector2i(2, 6), s + Vector2i(3, 6)], "meteor": s + Vector2i(18, 8), "t": 0.0, "shot": 0.0}
	for i in 3:
		w.drones.append({"src": src.id, "dst": dst.id, "pos": Vector2(s + Vector2i(i * 3, 5)) + Vector2(0.5, 0.5),
			"cargo": Portion.new(metal, 2.0) if i != 1 else null, "speed": 1.5, "cap": 2.0})
	w.director.enabled = false
	w.director.current = {"id": "meteors", "phase": "warn", "t": 999.0, "center": [s.x + 18, s.y + 8], "radius": 3,
		"shift": 0.0, "acc": 0.0}
	return Vector2(s) + Vector2(8.5, 5.0)

## Держит витрину живой: капсулы, ракеты, метеоры, огонь, груз для дронов.
static func showcase_tick(w: World, dt: float) -> void:
	var sc: Dictionary = w.meta.get("showcase", {})
	if sc.is_empty():
		return
	sc.t += dt
	sc.shot -= dt
	for c in sc.fires:
		w.fires[c] = 6.0
	var src = w.machines.get(sc.src)
	if src != null and src.items.is_empty():
		src.store(Portion.new(w.db.get_sub("demo_metal"), 20.0))
	if sc.shot > 0.0:
		return
	sc.shot = 0.3
	var c = w.machines.get(sc.cannon)
	var r = w.machines.get(sc.recv)
	if c != null and r != null:
		w.spawn_projectile(Vector2(c.cell) + Vector2(0.5, 0.5), Vector2(r.cell) + Vector2(0.5, 0.5),
			[Portion.new(w.db.get_sub("demo_metal"), 2.0)])
	var m: Vector2i = sc.meteor
	w.spawn_projectile(Vector2(m) + Vector2(randf_range(-2, 2), randf_range(-2, 2)), Vector2(m) + Vector2(randf_range(-2, 2), randf_range(-2, 2)), [], false, "meteor" if randf() < 0.6 else "debris")
	var s = w.machines.get(sc.silo)
	if s != null and fmod(sc.t, 2.0) < 0.3:
		w.projectiles.append({"from": Vector2(s.cell) + Vector2(0.5, 0.5), "to": Vector2(s.cell) + Vector2(0.5, -29.5),
			"t": 0.0, "dur": 2.0, "payload": [], "orbit": true, "kind": "rocket"})

static func _sub(w: World, id: String, name: String, tags: Array) -> Substance:
	var s := w.db.get_sub(id)
	if s == null:
		s = w.db.add(Substance.new(id, name, tags))
	return s
