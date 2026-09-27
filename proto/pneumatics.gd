class_name ProtoPneumatics
extends RefCounted
## Пневмозавод в 3D: детали на сетке площадки (клетка 2 м), газ и груз.
## Логика — из 2D-игры: давление считает GasNet, прочность детали — ComponentStats
## по её материалу, обработку — Processor.run по правилам data/processes.gd.
##
## Детали: приёмник (сюда робот выгружает добытое), насос, труба, пневмопушка,
## все 16 машин обработки 2D-игры (Buildings, process), бак, лаборатория
## (прогоняет каждую порцию через все полезные пробы — как 2D-машина Lab — и
## пропускает остаток дальше; знания пишет в knowledge). Пушка под давлением
## стреляет капсулой в ближайший приёмник впереди, до CANNON_RANGE клеток. У каждой есть направление: груз выходит вперёд. Труба принимает с любой
## стороны, кроме передней; машина — только сзади; бак — с любой.
## Газ: соседние детали — одна сеть. Насос качает до 90% предела своего материала,
## в разреженной атмосфере медленнее. Деталь выше своего предела лопается.
## Груз едет капсулами: скорость растёт с избытком давления над атмосферой, каждая
## капсула тратит газ. Без давления капсулы стоят.

const CELL := 2.0
const DIRS := [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]

const KINDS := {
	"intake": {"n": "Приёмник", "vol": 1.0, "stat": "intake"},
	"pump": {"n": "Насос", "vol": 0.6, "stat": "pump"},
	"pipe": {"n": "Труба", "vol": 0.4, "stat": "pipe"},
	"cannon": {"n": "Пневмопушка", "vol": 1.2, "stat": "cannon", "min_p": 3.0},
	"crusher": {"n": "Дробилка", "vol": 1.0, "stat": "crusher", "process": "crusher"},
	"furnace": {"n": "Печь", "vol": 1.2, "stat": "furnace", "process": "furnace"},
	"filter": {"n": "Фильтр", "vol": 1.0, "stat": "filter", "process": "filter"},
	"condenser": {"n": "Конденсатор", "vol": 1.0, "stat": "condenser", "process": "condenser"},
	"treater": {"n": "Обработчик", "vol": 1.0, "stat": "treater", "process": "treater"},
	"compressor": {"n": "Компрессор", "vol": 1.2, "stat": "compressor", "process": "compressor"},
	"decompressor": {"n": "Декомпрессор", "vol": 1.2, "stat": "decompressor", "process": "decompressor"},
	"distiller": {"n": "Дистиллятор", "vol": 1.0, "stat": "distiller", "process": "distiller"},
	"centrifuge": {"n": "Центрифуга", "vol": 1.0, "stat": "centrifuge", "process": "centrifuge"},
	"magnet_sep": {"n": "Магн. сепаратор", "vol": 1.0, "stat": "magnet_sep", "process": "magnet_sep"},
	"electrolyzer": {"n": "Электролизёр", "vol": 1.0, "stat": "electrolyzer", "process": "electrolyzer"},
	"sinter": {"n": "Спекатель", "vol": 1.0, "stat": "sinter", "process": "sinter"},
	"irradiator": {"n": "Облучатель", "vol": 1.0, "stat": "irradiator", "process": "irradiator"},
	"cryochamber": {"n": "Криокамера", "vol": 1.2, "stat": "cryochamber", "process": "cryochamber"},
	"resonator": {"n": "Резонатор", "vol": 1.0, "stat": "resonator", "process": "resonator"},
	"loom": {"n": "Ткацкий станок", "vol": 1.0, "stat": "loom", "process": "loom"},
	"tank": {"n": "Бак", "vol": 2.0, "stat": "tank", "cap": 40.0},
	"lab": {"n": "Лаборатория", "vol": 0.8, "stat": "lab"},
}
## Порядок в меню стройки: пневматика, все 16 машин обработки 2D-игры, бак, лаборатория.
const ORDER := ["pipe", "pump", "intake", "cannon", "crusher", "furnace", "filter", "condenser", "treater",
	"compressor", "decompressor", "distiller", "centrifuge", "magnet_sep", "electrolyzer", "sinter",
	"irradiator", "cryochamber", "resonator", "loom", "tank", "lab"]

const PUMP_RATE := 1.6          # газа в секунду при 1 атм снаружи
const PUMP_SAFE := 0.9          # насос не качает выше этой доли своего предела
const MOVE_P := 0.25            # избыток давления над атмосферой, с которого капсулы едут
const SPEED := 1.4              # клеток в секунду на 1 атм избытка
const MAX_SPEED := 3.0
const GAS_PER_CELL := 0.08      # расход газа на капсулу за клетку
const CAPSULE_KG := 2.0
const INTAKE_CD := 0.9
const QUEUE := 3                # сколько порций машина держит в очереди
const FURNACE_T := 900.0
const CANNON_RANGE := 12         # клеток: пушка бьёт в ближайший приёмник по своему направлению
const CANNON_GAS := 0.6          # газа на выстрел
const CANNON_CD := 1.2
const LAB_DUR := 4.0            # с на порцию в лаборатории

var planet: Planet
var gas := GasNet.new()
var parts := {}                 # Vector2i → Dictionary (деталь)
var by_id := {}                 # id → Vector2i
var events: Array = []          # {"kind": "burst"|"done"|"lost", "cell", ...} — для визуала
var produced := {}              # id вещества → кг, пришедших в баки
var flights: Array = []         # капсулы пушек в полёте: {p, from, to, t, dur}
var knowledge: World = null     # чьи знания пополняет лаборатория (ProtoLabDesk.world)
var _next_id := 1

func _init(p: Planet) -> void:
	planet = p
	gas.atm_pressure = p.atm_pressure
	gas.ambient = p.ambient_temp

# ---------------------------------------------------------------- стройка

func can_place(c: Vector2i) -> bool:
	return not parts.has(c)

## Ставит деталь; возвращает её или пустой словарь, если клетка занята.
func place(kind: String, c: Vector2i, dir: int, sub: Substance) -> Dictionary:
	if parts.has(c) or not KINDS.has(kind):
		return {}
	var info: Dictionary = KINDS[kind]
	var stats := ComponentStats.compute(info.stat, sub)
	var part := {"id": _next_id, "kind": kind, "cell": c, "dir": posmod(dir, 4), "sub": sub,
		"stats": stats, "items": [], "busy": null, "progress": 0.0, "status": "",
		"cap": null, "cd": 0.0, "hot": false, "work": false, "out_q": []}
	_next_id += 1
	parts[c] = part
	by_id[part.id] = c
	gas.add_node(part.id, info.vol, stats.max_p)
	for d in DIRS:
		var n: Dictionary = parts.get(c + d, {})
		if not n.is_empty():
			gas.connect_nodes(part.id, n.id, 1.0)
	return part

## Убирает деталь; груз в ней пропадает (кроме того, что вернули роботу).
func remove(c: Vector2i) -> Array:
	var part: Dictionary = parts.get(c, {})
	if part.is_empty():
		return []
	var back: Array = part.items.duplicate()
	if part.busy != null:
		back.append(part.busy)
	if part.cap != null:
		back.append(part.cap.p)
	back.append_array(part.get("out_q", []))
	gas.remove_node(part.id)
	by_id.erase(part.id)
	parts.erase(c)
	return back

func rotate(c: Vector2i) -> void:
	if parts.has(c):
		parts[c].dir = (parts[c].dir + 1) % 4

## Робот выгружает груз в приёмник.
func feed(c: Vector2i, p: Portion) -> bool:
	var part: Dictionary = parts.get(c, {})
	if part.is_empty() or part.kind != "intake":
		return false
	for it in part.items:
		if it.substance == p.substance:
			it.absorb(p)
			return true
	part.items.append(p)
	return true

func pressure(c: Vector2i) -> float:
	return gas.pressure(parts[c].id) if parts.has(c) else 0.0

func max_p(c: Vector2i) -> float:
	return parts[c].stats.max_p if parts.has(c) else 0.0

func mass_in(c: Vector2i) -> float:
	var part: Dictionary = parts.get(c, {})
	var m := 0.0
	for it in part.get("items", []):
		m += it.mass
	if part.get("busy") != null:
		m += part.busy.mass
	return m

## Капсулы в пути: [{p, cell, from, t}] — для визуала.
func capsules() -> Array:
	var out: Array = []
	for part in parts.values():
		if part.cap != null:
			out.append(part.cap)
	return out

# ---------------------------------------------------------------- шаг

func step(dt: float) -> void:
	for part in parts.values():
		match part.kind:
			"pump": _pump(part, dt)
			"intake": _intake(part, dt)
			"cannon": _cannon(part, dt)
			"lab": _lab(part, dt)
			"tank": part.status = "%.1f / %.0f кг" % [mass_in(part.cell), KINDS.tank.cap] + ("\n" + part.items[-1].substance.name if not part.items.is_empty() else "")
			_:
				if KINDS[part.kind].has("process"):
					_machine(part, dt)
	_move_capsules(dt)
	_fly(dt)
	for id in gas.step(dt):
		_burst(by_id.get(id, Vector2i(-9999, -9999)))

func _pump(part: Dictionary, dt: float) -> void:
	var limit: float = part.stats.max_p * PUMP_SAFE
	var p := gas.pressure(part.id)
	if p >= limit:
		part.status = "держит %.1f атм (предел материала %.1f)" % [p, part.stats.max_p]
		part.hot = false
		return
	# Насос забирает воздух снаружи: чем он реже, тем меньше за такт.
	var want := gas.gas_for_pressure(part.id, limit)
	gas.add_gas(part.id, minf(want, PUMP_RATE * planet.atm_pressure * dt))
	part.status = "качает: %.1f атм" % p
	part.hot = true

func _intake(part: Dictionary, dt: float) -> void:
	part.cd = maxf(0.0, part.cd - dt)
	if part.items.is_empty():
		part.status = "пусто — выгрузите добытое"
		return
	part.status = "%.1f кг в приёмнике" % mass_in(part.cell)
	if part.cap == null and part.cd <= 0.0:
		var it: Portion = part.items[0]
		var p := it.split(minf(CAPSULE_KG, it.mass))
		if it.mass <= 0.001:
			part.items.remove_at(0)
		part.cap = {"p": p, "cell": part.cell, "from": part.cell - DIRS[part.dir], "t": 0.5}
		part.cd = INTAKE_CD

func _machine(part: Dictionary, dt: float) -> void:
	var pid: String = KINDS[part.kind].process
	var proc: Dictionary = Processes.PROCESSES[pid]
	part.hot = false
	part.work = false
	if part.cap != null:
		part.status = "выход занят"
		return
	if not part.out_q.is_empty():
		# Процесс дал несколько порций (два выхода, отходы) — выпускаем по одной.
		part.cap = {"p": part.out_q.pop_front(), "cell": part.cell, "from": part.cell - DIRS[part.dir], "t": 0.5}
		return
	if part.busy == null:
		if part.items.is_empty():
			part.status = "ждёт груз"
			return
		if proc.get("gas_min", 0.0) > 0.0 and gas.pressure(part.id) < proc.gas_min:
			part.status = "мало давления (нужно %.1f атм)" % proc.gas_min
			return
		part.busy = part.items.pop_front()
		part.progress = 0.0
	part.progress += dt * part.stats.speed
	part.hot = proc.get("temp", "") == "heat"
	part.work = true
	part.status = "работает %d%%" % int(100.0 * part.progress / proc.dur)
	if part.progress < proc.dur:
		return
	var ctx := {"db": planet.db, "pressure": gas.pressure(part.id), "target_t": minf(FURNACE_T, part.stats.max_t),
		"ambient": planet.ambient_temp, "reagent": null, "filter_tag": ""}
	var res: Dictionary
	if pid == "treater":
		# Реагент — следующая порция другого вещества в очереди; без неё груз проходит как есть.
		var rg: Portion = null
		for it in part.items:
			if it.substance != part.busy.substance:
				rg = it
				break
		if rg == null:
			res = {"outs": [[part.busy, 0]], "gas": 0.0, "added": [], "reagent_used": 0.0}
		else:
			ctx.reagent = rg
			res = Processor.run(pid, part.busy, ctx)
			if res.get("wait", false):
				part.status = res.note
				return
			rg.mass -= res.reagent_used
			if rg.mass <= 0.001:
				part.items.erase(rg)
	else:
		res = Processor.run(pid, part.busy, ctx)
	if proc.get("gas_use", 0.0) > 0.0:
		gas.take_gas(part.id, proc.gas_use)
	if res.gas > 0.0:
		gas.add_gas(part.id, res.gas * Processor.GAS_PER_KG)
	if knowledge != null:
		# Наблюдение, как в 2D (World.on_processed): сработавшее правило выдаёт тег
		# входа, знание переходит на продукт.
		for t in res.get("matched", []):
			knowledge.reveal(part.busy.substance, t, "%s: сработало" % KINDS[part.kind].n)
		for o in res.outs:
			knowledge.inherit_knowledge(part.busy.substance, o[0].substance, res.added)
	for group in res.outs:
		for o in group:
			if o is Portion and o.mass > 0.001:
				part.out_q.append(o)
	if not part.out_q.is_empty():
		var o: Portion = part.out_q.pop_front()
		part.cap = {"p": o, "cell": part.cell, "from": part.cell - DIRS[part.dir], "t": 0.5}
		events.append({"kind": "done", "cell": part.cell, "added": res.added, "sub": o.substance})
	part.busy = null
	part.progress = 0.0

## Лаборатория: порция ждёт LAB_DUR, получает все пробы, которые ещё что-то
## скажут (Lab.run_probes, по 0,5 кг на пробу), остаток уходит вперёд.
func _lab(part: Dictionary, dt: float) -> void:
	part.hot = false
	if part.cap != null:
		part.status = "выход занят"
		return
	if part.busy == null:
		if part.items.is_empty():
			part.status = "ждёт образцы" if knowledge != null else "нет связи с роботом"
			return
		part.busy = part.items.pop_front()
		part.progress = 0.0
	part.progress += dt * part.stats.speed
	part.hot = true
	part.status = "пробы %d%%" % int(100.0 * minf(1.0, part.progress / LAB_DUR))
	if part.progress < LAB_DUR:
		return
	var p: Portion = part.busy
	var learned := knowledge != null and Lab.run_probes(knowledge, p)
	events.append({"kind": "lab", "cell": part.cell, "sub": p.substance, "learned": learned})
	if p.mass > 0.01:
		part.cap = {"p": p, "cell": part.cell, "from": part.cell - DIRS[part.dir], "t": 0.5}
	part.busy = null
	part.progress = 0.0

## Капсула в клетке едет от входной стороны к выходной; на t=1 — в следующую деталь.
func _move_capsules(dt: float) -> void:
	for part in parts.values().duplicate():
		var cap = part.cap
		if cap == null:
			continue
		var over := gas.pressure(part.id) - gas.atm_pressure
		if over < MOVE_P:
			continue
		var v := minf(MAX_SPEED, SPEED * over)
		var nt: float = cap.t + v * dt
		if cap.t < 1.0:
			gas.take_gas(part.id, GAS_PER_CELL * (minf(nt, 1.0) - cap.t))
		cap.t = minf(nt, 1.0)
		if cap.t < 1.0:
			continue
		var nc: Vector2i = part.cell + DIRS[part.dir]
		var nxt: Dictionary = parts.get(nc, {})
		if nxt.is_empty():
			# Конец трубы в пустоту — капсула выпадает наружу.
			events.append({"kind": "lost", "cell": part.cell, "dir": part.dir, "sub": cap.p.substance})
			part.cap = null
			continue
		if _accept(nxt, cap.p, part.cell):
			part.cap = null

func _accept(part: Dictionary, p: Portion, from: Vector2i) -> bool:
	var back: Vector2i = part.cell - DIRS[part.dir]
	var front: Vector2i = part.cell + DIRS[part.dir]
	match part.kind:
		"pipe":
			if from == front or part.cap != null:
				return false
			part.cap = {"p": p, "cell": part.cell, "from": from, "t": 0.0}
			return true
		"tank":
			if mass_in(part.cell) + p.mass > KINDS.tank.cap + 0.001:
				part.status = "полон"
				return false
			produced[p.substance.id] = produced.get(p.substance.id, 0.0) + p.mass
			for it in part.items:
				if it.substance == p.substance:
					it.absorb(p)
					return true
			part.items.append(p)
			return true
		_:
			# Машины обработки и пушка берут груз только сзади.
			if part.kind == "intake" or from != back or part.items.size() >= QUEUE:
				return false
			part.items.append(p)
			return true
	return false

## Пушка: копит давление и стреляет капсулой в ближайший приёмник по направлению.
func _cannon(part: Dictionary, dt: float) -> void:
	part.cd = maxf(0.0, part.cd - dt)
	part.work = part.cd > CANNON_CD * 0.6
	var tgt := cannon_target(part.cell)
	if tgt == Vector2i(-9999, -9999):
		part.status = "некуда стрелять — поставьте приёмник впереди"
		return
	if part.items.is_empty():
		part.status = "ждёт груз"
		return
	var p := gas.pressure(part.id)
	if p < KINDS.cannon.min_p:
		part.status = "копит давление: %.1f / %.1f атм" % [p, KINDS.cannon.min_p]
		return
	if part.cd > 0.0:
		return
	var it: Portion = part.items.pop_front()
	gas.take_gas(part.id, CANNON_GAS)
	part.cd = CANNON_CD
	part.work = true
	var dist := float((tgt - part.cell).length())
	flights.append({"p": it, "from": part.cell, "to": tgt, "t": 0.0, "dur": 0.5 + dist * 0.08})
	part.status = "выстрел → %d клеток" % int(dist)
	events.append({"kind": "shot", "cell": part.cell, "dir": part.dir, "sub": it.substance})

## Клетка приёмника, в который бьёт пушка (или (-9999, -9999)).
func cannon_target(c: Vector2i) -> Vector2i:
	var part: Dictionary = parts.get(c, {})
	if part.is_empty():
		return Vector2i(-9999, -9999)
	for i in range(2, CANNON_RANGE + 1):
		var q: Vector2i = c + DIRS[part.dir] * i
		if parts.has(q) and parts[q].kind == "intake":
			return q
	return Vector2i(-9999, -9999)

func _fly(dt: float) -> void:
	var keep: Array = []
	for f in flights:
		f.t += dt
		if f.t < f.dur:
			keep.append(f)
			continue
		var tgt: Dictionary = parts.get(f.to, {})
		if tgt.is_empty() or tgt.kind != "intake":
			events.append({"kind": "lost", "cell": f.to, "dir": 0, "sub": f.p.substance})
			continue
		feed(f.to, f.p)
		events.append({"kind": "caught", "cell": f.to, "sub": f.p.substance})
	flights = keep

func _burst(c: Vector2i) -> void:
	var part: Dictionary = parts.get(c, {})
	if part.is_empty():
		return
	events.append({"kind": "burst", "cell": c, "part": part.kind, "p": gas.pressure(part.id), "max_p": part.stats.max_p})
	remove(c)

# ---------------------------------------------------------------- удобства

## Клетка сетки под точкой мира (origin — центр клетки (0,0)).
static func cell_at(origin: Vector3, p: Vector3) -> Vector2i:
	return Vector2i(roundi((p.x - origin.x) / CELL), roundi((p.z - origin.z) / CELL))

static func cell_pos(origin: Vector3, c: Vector2i) -> Vector3:
	return origin + Vector3(c.x * CELL, 0, c.y * CELL)

## Направление сетки, ближайшее к вектору в плоскости XZ.
static func dir_of(v: Vector3) -> int:
	if absf(v.x) >= absf(v.z):
		return 0 if v.x >= 0.0 else 2
	return 1 if v.z >= 0.0 else 3

## Готовая цепочка для площадки: приёмник → трубы → дробилка → труба → печь → бак,
## насос сбоку от первой трубы. start — клетка приёмника, линия идёт по +X.
func build_demo(start: Vector2i, body: Substance, pipe_sub: Substance = null) -> void:
	var ps := pipe_sub if pipe_sub != null else body
	var line := ["intake", "pipe", "pipe", "crusher", "pipe", "furnace", "tank"]
	for i in line.size():
		var k: String = line[i]
		place(k, start + Vector2i(i, 0), 0, ps if k == "pipe" else body)
	place("pump", start + Vector2i(1, 1), 3, body)

## Вторая цепочка — логистика и машины обработки 2D: пушка (с насосом) стреляет
## капсулами через площадку в приёмник → центрифуга → спекатель → бак.
## start — клетка пушки, линия идёт по +X. Груз для пушки кладётся в cannon.items.
func build_logistics(start: Vector2i, body: Substance) -> Dictionary:
	var cannon := place("cannon", start, 0, body)
	place("pump", start + Vector2i(0, 1), 3, body)
	var line := ["intake", "centrifuge", "sinter", "tank"]
	for i in line.size():
		place(line[i], start + Vector2i(4 + i, 0), 0, body)
	place("pump", start + Vector2i(4, 1), 3, body)
	return cannon
