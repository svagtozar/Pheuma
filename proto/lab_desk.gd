class_name ProtoLabDesk
extends RefCounted
## Разведка материалов в 3D: касание, пять проб, догадки и анализатор — та же
## логика, что в 2D (World.touch / probe / toggle_hypothesis / check_hypothesis,
## Abilities.reveal_one_each). Знания — в World.robot (sub_known, hypotheses…).
##
## Два режима:
##   игра (F3) — World настоящий: образцы берёт он сам (инвентарь, залежь рядом);
##   прототип — World служит только «памятью» о веществах, а образец на пробу
##     одалживается из груза робота (robot.get_meta("cargo")), из детали завода
##     перед ним или откалывается от друзы в досягаемости; остаток возвращается.
## Газ проб — бортовой баллон World.robot.tank; в прототипе он подкачивается
## сам у детали пневмозавода под давлением.

const TOUCH_R := 2.4          # м: друза или деталь, до которой можно дотянуться
const ANALYZER_R := 6.0       # м: дальность анализатора
const ANALYZER_CD := 8.0
const ANALYZER_GAS := 0.2
const REFILL_R := 3.5         # м до детали завода, от которой подкачивается баллон
const REFILL_RATE := 0.6      # газа в секунду

var world: World
var robot: Node3D = null      # прототип: чей груз; в игре — null
var mining = null             # ProtoMining — друзы (прототип)
var net = null                # ProtoPneumatics (прототип)
var origin := Vector3.ZERO    # начало сетки завода
var analyzer_cd := 0.0
var last := ""                # текст последнего результата (для панели)
var _ev_seen := 0

## Прототип: своя «память» о веществах этой планеты.
static func for_planet(p: Planet) -> World:
	var w := World.new(p)
	w.robot.tank = w.robot.tank_cap()
	return w

func _init(w: World, r: Node3D = null) -> void:
	world = w
	robot = r
	_ev_seen = w.events.size()

func proto() -> bool:
	return robot != null

# ---------------------------------------------------------------- что рядом

func cargo() -> Array:
	if robot == null:
		return []
	if not robot.has_meta("cargo"):
		robot.set_meta("cargo", [])
	return robot.get_meta("cargo")

## Кристалл друзы в досягаемости (или null).
func druse_near() -> Node3D:
	if mining == null or robot == null:
		return null
	var best: Node3D = null
	var bd := TOUCH_R
	for c in mining.crystals():
		var d: float = (c.global_position - robot.global_position).length()
		if d < bd:
			bd = d
			best = c
	return best

## Деталь завода перед роботом, в которой есть груз (или пустой словарь).
func part_near(r: float = TOUCH_R) -> Dictionary:
	if net == null or robot == null:
		return {}
	var best := {}
	var bd := r + ProtoPneumatics.CELL * 0.5
	for c in net.parts:
		var part: Dictionary = net.parts[c]
		if _part_subs(part).is_empty():
			continue
		var d: float = net.at(origin, c).distance_to(robot.global_position)
		if d < bd:
			bd = d
			best = part
	return best

static func _part_subs(part: Dictionary) -> Array:
	var out: Array = []
	var ps: Array = part.items.duplicate()
	if part.get("busy") != null:
		ps.append(part.busy)
	if part.get("cap") != null:
		ps.append(part.cap.p)
	for p in ps:
		if not p.substance in out:
			out.append(p.substance)
	return out

## Что можно изучать сейчас: [{sub, where, kg}], ближнее — первым.
## where: "druse" | "part" | "cargo" | "deposit" | "inventory".
func subjects(focus_cell = null) -> Array:
	var out: Array = []
	var seen := {}
	var add := func(s: Substance, where: String, kg: float):
		if s == null:
			return
		if seen.has(s.id):
			out[seen[s.id]].kg += kg
			return
		seen[s.id] = out.size()
		out.append({"sub": s, "where": where, "kg": kg})
	if proto():
		var dn := druse_near()
		if dn != null:
			add.call(mining.sub, "druse", -1.0)
		var part := part_near()
		if not part.is_empty():
			for s in _part_subs(part):
				add.call(s, "part", -1.0)
		for p in cargo():
			add.call(p.substance, "cargo", p.mass)
	else:
		for c in deposits_near(focus_cell):
			add.call(world.db.get_sub(world.planet.deposits[c].sub), "deposit", float(world.planet.deposits[c].amount))
		for id in world.robot.inventory:
			var p: Portion = world.robot.inventory[id]
			if id != world.starter.id:
				add.call(p.substance, "inventory", p.mass)
	return out

## Игра: залежи в досягаемости (клетка под курсором — первой).
func deposits_near(focus_cell = null) -> Array:
	var out: Array = []
	if focus_cell != null and world.planet.deposits.has(focus_cell) and world.near_robot(focus_cell, 2.2):
		out.append(focus_cell)
	var rc: Vector2i = world.robot_cell()
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			var c := rc + Vector2i(dx, dy)
			if c in out or not world.planet.deposits.has(c):
				continue
			if world.planet.deposits[c].amount > 0.0 and world.near_robot(c, 2.2):
				out.append(c)
	return out

# ---------------------------------------------------------------- действия

func touch(s: Substance) -> void:
	world.touch(s)

func probe(s: Substance, pid: String) -> String:
	var lent := _lend(s, world.probe_cost())
	var err := world.probe(s.id, pid)
	_settle(s, lent)
	last = err if err != "" else world.robot.last_probe
	return err

func probe_error(s: Substance, pid: String) -> String:
	if proto():
		if sample_kg(s) + 0.001 < world.probe_cost():
			return "нужно %.1f кг образца" % world.probe_cost()
		if world.robot.tank + 0.001 < Probes.PROBES[pid].gas:
			return "мало газа в баллоне"
		return ""
	return world.probe_error(s.id, pid)

func toggle_guess(s: Substance, tag: String) -> String:
	return world.toggle_hypothesis(s, tag)

func check(s: Substance, tag: String) -> String:
	var lent := _lend(s, world.probe_cost() * 0.5)
	var err := world.check_hypothesis(s.id, tag)
	_settle(s, lent)
	last = err if err != "" else world.robot.last_probe
	return err

func check_error(s: Substance, tag: String) -> String:
	if proto():
		var pid := Probes.probe_of(tag)
		if pid == "" and not tag in Probes.VISIBLE:
			return "только наблюдением"
		if sample_kg(s) + 0.001 < world.probe_cost() * 0.5:
			return "нужно %.2f кг образца" % (world.probe_cost() * 0.5)
		if pid != "" and world.robot.tank + 0.001 < Probes.PROBES[pid].gas * 0.5:
			return "мало газа"
		return ""
	return world.check_error(s.id, tag)

## Анализатор прототипа: по одному неизвестному тегу у всего, что рядом.
func analyze_near() -> String:
	if analyzer_cd > 0.0:
		return "анализатор перезаряжается (%.0f с)" % ceilf(analyzer_cd)
	if world.robot.tank + 0.001 < ANALYZER_GAS:
		return "мало газа в баллоне"
	var subs: Array = []
	var dn := druse_near()
	if dn == null and mining != null and robot != null:
		for c in mining.crystals():
			if (c.global_position - robot.global_position).length() < ANALYZER_R:
				dn = c
				break
	if dn != null:
		subs.append(mining.sub)
	var part := part_near(ANALYZER_R)
	if not part.is_empty():
		for s in _part_subs(part):
			if not s in subs:
				subs.append(s)
	if subs.is_empty():
		for p in cargo():
			if not p.substance in subs:
				subs.append(p.substance)
	if subs.is_empty():
		return "анализировать нечего: подойдите к друзе или машине"
	world.robot.tank -= ANALYZER_GAS
	analyzer_cd = ANALYZER_CD
	if Abilities.reveal_one_each(world, subs) == 0:
		last = "Анализатор: здесь всё уже известно"
		return "здесь всё уже известно"
	last = "Анализатор: " + ", ".join(subs.map(func(s): return world.sub_label(s)))
	return ""

## Игра: анализатор — модуль робота (как клавиши 1–6 в 2D); цель — залежь рядом
## или клетка под курсором.
func analyze_game(focus_cell = null) -> String:
	var dn := deposits_near(focus_cell)
	var c: Vector2i = dn[0] if not dn.is_empty() else (focus_cell if focus_cell != null else world.robot_cell())
	var err := Abilities.use(world, "analyzer", Vector2(c) + Vector2(0.5, 0.5))
	if err == "модуль не установлен":
		err = "нужен модуль «Анализатор» (F — фабрикатор)"
	last = err if err != "" else "Анализатор: " + ", ".join(Abilities.substances_at(world, c).map(func(s): return world.sub_label(s)))
	return err

## Сколько образца доступно прототипу: груз + деталь рядом; друза — сколько угодно.
func sample_kg(s: Substance) -> float:
	var dn := druse_near()
	if dn != null and mining.sub == s:
		return INF
	var kg := 0.0
	for p in cargo():
		if p.substance == s:
			kg += p.mass
	var part := part_near()
	if not part.is_empty():
		for p in part.items:
			if p.substance == s:
				kg += p.mass
	return kg

## Прототип: на время пробы кладём образец в инвентарь World (пробы берут оттуда).
func _lend(s: Substance, kg: float) -> String:
	if not proto() or world.robot.mass_of(s.id) + 0.001 >= kg:
		return ""
	for p in cargo():
		if p.substance == s and p.mass + 0.001 >= kg:
			world.robot.add_item(p.split(kg))
			if p.mass <= 0.001:
				cargo().erase(p)
			return "cargo"
	var part := part_near()
	if not part.is_empty():
		for p in part.items:
			if p.substance == s and p.mass + 0.001 >= kg:
				world.robot.add_item(p.split(kg))
				if p.mass <= 0.001:
					part.items.erase(p)
				return "part"
	if druse_near() != null and mining.sub == s:
		world.robot.add_item(Portion.new(s, kg, mining.temp))
		return "druse"
	return ""

## Остаток образца (проба не состоялась) — обратно в груз; откол от друзы — тоже в груз.
func _settle(s: Substance, lent: String) -> void:
	if lent == "" or not world.robot.inventory.has(s.id):
		return
	var left: Portion = world.robot.take_item(s.id, world.robot.mass_of(s.id))
	if left == null or left.mass <= 0.001:
		return
	for p in cargo():
		if p.substance == s:
			p.absorb(left)
			return
	cargo().append(left)

# ---------------------------------------------------------------- время

## Перезарядка анализатора и подкачка баллона у завода (прототип).
func tick(dt: float) -> void:
	analyzer_cd = maxf(0.0, analyzer_cd - dt)
	if net == null or robot == null:
		return
	var cap := world.robot.tank_cap()
	if world.robot.tank >= cap - 0.001:
		return
	for c in net.parts:
		var part: Dictionary = net.parts[c]
		if net.at(origin, c).distance_to(robot.global_position) > REFILL_R:
			continue
		var extra: float = net.gas.pressure(part.id) - net.gas.atm_pressure
		if extra < 0.3:
			continue
		var got: float = net.gas.take_gas(part.id, minf(REFILL_RATE * dt, cap - world.robot.tank))
		world.robot.tank += got
		return

## Новые записи журнала World (новый тег, догадка верна, опознан…) с прошлого раза.
func new_events() -> Array:
	var ev := world.events
	if _ev_seen > ev.size():
		_ev_seen = 0
	var out: Array = []
	for i in range(_ev_seen, ev.size()):
		out.append(ev[i].text)
	_ev_seen = ev.size()
	return out

## Короткая метка для списков: «Имя ✓» опознан, «Имя ?2» — два тега неизвестны.
func short_label(s: Substance) -> String:
	if world.is_identified(s):
		return "%s ✓" % s.name
	return "%s ?%d" % [s.name, world.unknown_count(s)]

# ---------------------------------------------------------------- сохранение

func save_dict() -> Dictionary:
	var r := world.robot
	return {"knowledge": r.knowledge, "known_tags": r.known_tags.keys(), "analyzed": r.analyzed.keys(),
		"sub_known": r.sub_known.duplicate(true), "hypotheses": r.hypotheses.duplicate(true), "tank": r.tank}

func load_dict(d: Dictionary) -> void:
	var r := world.robot
	r.knowledge = int(d.get("knowledge", r.knowledge))
	for t in d.get("known_tags", []):
		r.known_tags[str(t)] = true
	for id in d.get("analyzed", []):
		r.analyzed[str(id)] = true
	var sk: Dictionary = d.get("sub_known", {})
	for id in sk:
		r.sub_known[id] = sk[id]
	var hy: Dictionary = d.get("hypotheses", {})
	for id in hy:
		r.hypotheses[id] = hy[id]
	r.tank = float(d.get("tank", r.tank))
	_ev_seen = world.events.size()
