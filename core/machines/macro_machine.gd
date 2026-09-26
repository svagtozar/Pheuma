class_name MacroMachine
extends Machine
## Свёрнутый макроблок: одна клетка, внутри — целая схема из примитивов
## со своими проводами и газом. Порты схемы выведены на стороны клетки:
##   груз — входы и выходы по сторонам (порты одной стороны делят её);
##   газ  — внешний газовый узел блока обменивается газом с машинами-портами;
##   сигнал — провод в блок идёт во входы схемы, провод из блока — ИЛИ её выходов.
## Внутри может стоять другой свёрнутый блок (до MAX_DEPTH уровней): он ведёт себя
## как обычная машина схемы, его порты — стороны его клетки.

const SIG_SOURCE := -1        # псевдоисточник внешнего сигнала внутри схемы
const GAS_K := 2.0
const MAX_DEPTH := 3          # блок в блоке в блоке

var mb := {}
var rot := 0
var inner: InnerGrid
var ports: Array = []
var gas_port_ids: Array = []   # id внутренних машин — газовых портов
var sig_out_ids: Array = []    # id внутренних машин — сигнальных выходов
var outer_signal := false
var _rr := {}          # круговой выбор входного порта по стороне

## Можно ли свернуть: внутри не должно быть того, что привязано к месту на карте.
static func collapse_error(p_mb: Dictionary) -> String:
	for p in p_mb.parts:
		if p.kind in ["drill", "warehouse_section", "battery_section", "catch_net", "launch_silo", "fabricator", "dome", "beacon"]:
			return "не сворачивается: «%s» привязан к месту" % Buildings.name_of(p.kind)
		if p.kind == "macro":
			if not p.has("mb"):
				return "не сворачивается: у вложенного блока нет схемы"
			var e := collapse_error(p.mb)
			if e != "":
				return e
	if depth_of(p_mb) > MAX_DEPTH:
		return "не сворачивается: вложенность больше %d уровней" % MAX_DEPTH
	return ""

## Сколько уровней блоков в схеме (схема без вложенных блоков — 1).
static func depth_of(p_mb: Dictionary) -> int:
	var d := 1
	for p in p_mb.parts:
		if p.kind == "macro" and p.has("mb"):
			d = max(d, depth_of(p.mb) + 1)
	return d

## Все примитивы схемы по порядку, с раскрытием вложенных блоков.
## В этом же порядке идут материалы для setup().
static func flat_kinds(p_mb: Dictionary) -> Array:
	var out: Array = []
	for p in p_mb.parts:
		if p.kind == "macro":
			out.append_array(flat_kinds(p.get("mb", {"parts": []})))
		else:
			out.append(p.kind)
	return out

## Все примитивы внутри, включая спрятанные во вложенных блоках.
func all_inner() -> Array:
	var out: Array = []
	for m in inner.machines.values():
		if m is MacroMachine:
			out.append_array(m.all_inner())
		else:
			out.append(m)
	return out

## Весь груз внутри (для разрушения и сноса).
func all_contents() -> Array:
	var all: Array = []
	for m in inner.machines.values():
		all.append_array(m.items)
		for e in m.out_queue:
			all.append(e[0])
		if m is Processor:
			if m.busy != null: all.append(m.busy)
			if m.reagent != null: all.append(m.reagent)
		if m is MacroMachine:
			all.append_array(m.all_contents())
	return all

## Шаблон по текущему состоянию схемы (с настройками, изменёнными внутри).
func template() -> Dictionary:
	var size := Vector2i(int(mb.size[0]), int(mb.size[1]))
	var t := Macroblocks.capture(inner, Rect2i(Vector2i.ZERO, size), display_name())
	t.size = [size.x, size.y]
	t.sig_out = mb.get("sig_out", []).duplicate(true)
	t.ports = Macroblocks.compute_ports(t)
	return t

func _root():
	return inner.world

func display_name() -> String:
	return mb.get("name", "Макроблок")

func has_gas() -> bool:
	return not gas_port_ids.is_empty()

func has_sig_in() -> bool:
	return not mb.get("sig_in", []).is_empty()

func _begin(w, p_mb: Dictionary, p_rot: int) -> void:
	mb = p_mb
	rot = p_rot
	facing = p_rot
	ports = mb.ports
	inner = InnerGrid.new(w, self, Vector2i(int(mb.size[0]), int(mb.size[1])))

## Собрать схему из шаблона. subs — материалы примитивов в порядке flat_kinds(),
## w — мир или внутренность блока, где стоит этот.
func setup(w, p_mb: Dictionary, p_rot: int, subs: Array) -> void:
	_begin(w, p_mb, p_rot)
	var by_off := {}
	var k := 0
	for i in mb.parts.size():
		var p: Dictionary = mb.parts[i]
		var off := Vector2i(int(p.off[0]), int(p.off[1]))
		if p.kind == "macro":
			var n: int = flat_kinds(p.mb).size()
			var sub_subs: Array = subs.slice(k, k + n)
			k += n
			var nm: MacroMachine = inner.place("macro", off, int(p.facing), sub_subs[0], quality)
			nm.setup(inner, p.mb, int(p.facing), sub_subs)
			by_off[off] = nm
			continue
		by_off[off] = inner.place(p.kind, off, int(p.facing), subs[k], quality)
		k += 1
	for i in mb.parts.size():
		var p: Dictionary = mb.parts[i]
		var m: Machine = by_off[Vector2i(int(p.off[0]), int(p.off[1]))]
		for key in p.config:
			var v = p.config[key]
			if key == "target":
				var t = by_off.get(Vector2i(int(v[0]), int(v[1]))) if v != null else null
				m.config.target = t.id if t != null else -1
			elif key == "routes":
				m.config.routes = []
				for r in v:
					var t = by_off.get(Vector2i(int(r[1][0]), int(r[1][1])))
					if t != null:
						m.config.routes.append([r[0], t.id])
			else:
				m.config[key] = v
	for wr in mb.wires:
		var a = by_off.get(Vector2i(int(wr.from[0]), int(wr.from[1])))
		var b = by_off.get(Vector2i(int(wr.to[0]), int(wr.to[1])))
		if a != null and b != null:
			inner.logic.add_wire(a.id, b.id, int(wr.port), wr.points.map(func(q): return Vector2(q[0], q[1])), a.built_from.id)
	_bind_ports(w)

## Собрать схему из живых машин мира со всем их состоянием (свёртка на месте).
## parts — [SaveGame.machine_to(m) + "loc" (смещение в схеме)], wires — провода между ними (id мира).
func setup_live(w, p_mb: Dictionary, parts: Array, wires: Array) -> Dictionary:
	_begin(w, p_mb, 0)
	var idmap := {}
	for d in parts:
		var sub: Substance = w.db.get_sub(d.sub)
		var m := inner.place(d.kind, SaveGame.v2i(d.loc), int(d.facing), sub, float(d.q))
		idmap[int(d.id)] = m.id
		SaveGame.machine_restore(_root(), m, d, inner.gas, inner)
	for m in inner.machines.values():
		m.config = Macroblocks.remap_config(m.config, idmap)
	for wr in wires:
		inner.logic.add_wire(idmap[wr.from], idmap[wr.to], wr.port, wr.points, wr.material)
	_bind_ports(w)
	return idmap

## Привязать газовые и сигнальные порты к внутренним машинам; завести внешний газовый узел.
func _bind_ports(w) -> void:
	gas_port_ids = []
	for q in ports:
		if q.type == "gas":
			var m = inner.machine_at(Vector2i(int(q.off[0]), int(q.off[1])))
			if m != null and m.has_gas() and not m.id in gas_port_ids:
				gas_port_ids.append(m.id)
	sig_out_ids = []
	for o in mb.get("sig_out", []):
		var m = inner.machine_at(Vector2i(int(o[0]), int(o[1])))
		if m != null:
			sig_out_ids.append(m.id)
	for s in mb.get("sig_in", []):
		var m = inner.machine_at(Vector2i(int(s.to[0]), int(s.to[1])))
		if m != null:
			var exists := false
			for x in inner.logic.wires_to(m.id):
				if x.from == SIG_SOURCE and x.port == int(s.port):
					exists = true
			if not exists:
				inner.logic.add_wire(SIG_SOURCE, m.id, int(s.port))
	if has_gas() and not w.gas.has_node(id):
		w.gas.add_node(id, 1.0, stats.get("max_p", 10.0))
		for d in Machine.DIRS:
			var n = w.machine_at(cell + d)
			if n != null and n.has_gas():
				w.gas.connect_nodes(id, n.id)

func world_dir(local_dir: int) -> int:
	return (local_dir + rot) % 4

func local_dir(wdir: int) -> int:
	return (wdir - rot + 4) % 4

func capacity() -> float:
	return 1.0   # принимает груз через входные порты

func total_mass() -> float:
	var s := 0.0
	for m in inner.machines.values():
		s += m.total_mass()
	return s

func accept(p: Portion, from_cell: Vector2i) -> bool:
	var wd := Machine.DIRS.find(from_cell - cell)
	if wd < 0:
		return false
	var ld := local_dir(wd)
	var cands: Array = ports.filter(func(q): return q.type == "in" and int(q.dir) == ld)
	if cands.is_empty():
		return false
	var start: int = _rr.get(ld, 0)
	for i in cands.size():
		var q: Dictionary = cands[(start + i) % cands.size()]
		var off := Vector2i(int(q.off[0]), int(q.off[1]))
		var m = inner.machine_at(off)
		if m != null and m.accept(p, off + Machine.DIRS[int(q.dir)]):
			_rr[ld] = (start + i + 1) % cands.size()
			return true
	return false

## Выход внутренней машины за границу блока — наружу через сторону хоста.
func push_out(w, src: Machine, p: Portion, c: Vector2i) -> bool:
	var ld := Machine.DIRS.find(c - src.cell)
	var ok := false
	for q in ports:
		if q.type == "out" and int(q.dir) == ld and Vector2i(int(q.off[0]), int(q.off[1])) == src.cell:
			ok = true
	if not ok:
		return false
	return w.push(self, p, cell + Machine.DIRS[world_dir(ld)])

func tick(w, dt: float) -> void:
	outer_signal = w.logic.input(id, 0)
	_exchange_gas(w, dt)
	inner.tick(dt)
	signal_out = false
	for sid in sig_out_ids:
		if inner.logic.outputs.get(sid, false):
			signal_out = true
	var working := 0
	for m in inner.machines.values():
		if m.status.begins_with("работает") or m.status.begins_with("давление"):
			working += 1
	status = "внутри машин: %d, работают: %d" % [inner.machines.size(), working]
	hot = false
	for m in inner.machines.values():
		if m.hot:
			hot = true

## Выравнивание давления между внешним узлом блока и внутренними газовыми портами.
func _exchange_gas(w, dt: float) -> void:
	if not w.gas.has_node(id):
		return
	for gid in gas_port_ids:
		if not inner.gas.has_node(gid):
			continue
		var no: float = w.gas.amount(id)
		var vo: float = w.gas.nodes[id].v
		var ni: float = inner.gas.amount(gid)
		var vi: float = inner.gas.nodes[gid].v
		var q_eq: float = (no * vi - ni * vo) / (vo + vi)
		var flow: float = GAS_K * (w.gas.pressure(id) - inner.gas.pressure(gid)) * dt
		if abs(flow) > abs(q_eq) * 0.5:
			flow = q_eq * 0.5
		if flow > 0.0:
			inner.gas.add_gas(gid, w.gas.take_gas(id, flow))
		elif flow < 0.0:
			w.gas.add_gas(id, inner.gas.take_gas(gid, -flow))

func describe(w) -> Array:
	var l: Array = []
	l.append("%s — свёрнутый макроблок (прочность %.0f/%.0f)" % [display_name(), hp, max_hp()])
	l.append("Размер схемы %d×%d, %s" % [int(mb.size[0]), int(mb.size[1]), Macroblocks.describe_ports(mb)])
	if has_gas():
		l.append("Газовый порт: %.2f атм снаружи" % w.gas.pressure(id))
	if has_sig_in():
		l.append("Сигнал на входе: %s" % ("есть" if outer_signal else "нет"))
	if not sig_out_ids.is_empty():
		l.append("Сигнал на выходе: %s" % ("есть" if signal_out else "нет"))
	if not enabled and not has_sig_in():
		l.append("Выключено")
	return l

func save_extra() -> Dictionary:
	var parts: Array = []
	for m in inner.machines.values():
		parts.append(SaveGame.machine_to(m, inner.gas))
	var wires: Array = inner.logic.wires.values().filter(func(x): return x.from != SIG_SOURCE).map(func(x): return {"from": x.from, "to": x.to, "port": x.port,
		"points": x.points.map(func(p): return [p.x, p.y]), "material": x.material})
	return {"mb": mb, "rot": rot, "parts": parts, "wires": wires}

## Внешний газ блока сохраняется и восстанавливается общим кодом SaveGame (поле gas).
func load_extra(w, d: Dictionary) -> void:
	_begin(w, d.mb, int(d.rot))
	for md in d.parts:
		var sub: Substance = w.db.get_sub(md.sub)
		var m := inner.place(md.kind, SaveGame.v2i(md.cell), int(md.facing), sub, float(md.q), int(md.id))
		SaveGame.machine_restore(_root(), m, md, inner.gas, inner)
	for x in d.wires:
		inner.logic.add_wire(int(x.from), int(x.to), int(x.port), x.points.map(func(p): return Vector2(p[0], p[1])), x.material)
	_bind_ports(w)
