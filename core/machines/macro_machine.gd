class_name MacroMachine
extends Machine
## Свёрнутый макроблок: одна клетка, внутри — целая схема из примитивов
## со своими проводами и газом. Входы и выходы схемы выведены на стороны клетки
## (все порты с одной стороны делят эту сторону).

var mb := {}
var rot := 0
var inner: InnerGrid
var ports: Array = []
var _rr := {}          # круговой выбор входного порта по стороне

## Можно ли свернуть: внутри не должно быть того, что привязано к месту на карте.
static func collapse_error(p_mb: Dictionary) -> String:
	for p in p_mb.parts:
		if p.kind in ["drill", "warehouse_section", "battery_section", "catch_net", "launch_silo", "fabricator", "dome", "beacon", "macro"]:
			return "не сворачивается: «%s» привязан к месту" % Buildings.name_of(p.kind)
	return ""

func display_name() -> String:
	return mb.get("name", "Макроблок")

func setup(w: World, p_mb: Dictionary, p_rot: int, subs: Array) -> void:
	mb = p_mb
	rot = p_rot
	facing = p_rot
	ports = mb.ports
	inner = InnerGrid.new(w, self, Vector2i(int(mb.size[0]), int(mb.size[1])))
	var by_off := {}
	for i in mb.parts.size():
		var p: Dictionary = mb.parts[i]
		var off := Vector2i(int(p.off[0]), int(p.off[1]))
		var m := inner.place(p.kind, off, int(p.facing), subs[i], quality)
		by_off[off] = m
	for i in mb.parts.size():
		var p: Dictionary = mb.parts[i]
		var m: Machine = by_off[Vector2i(int(p.off[0]), int(p.off[1]))]
		for k in p.config:
			var v = p.config[k]
			if k == "target":
				var t = by_off.get(Vector2i(int(v[0]), int(v[1]))) if v != null else null
				m.config.target = t.id if t != null else -1
			elif k == "routes":
				m.config.routes = []
				for r in v:
					var t = by_off.get(Vector2i(int(r[1][0]), int(r[1][1])))
					if t != null:
						m.config.routes.append([r[0], t.id])
			else:
				m.config[k] = v
	for wr in mb.wires:
		var a = by_off.get(Vector2i(int(wr.from[0]), int(wr.from[1])))
		var b = by_off.get(Vector2i(int(wr.to[0]), int(wr.to[1])))
		if a != null and b != null:
			inner.logic.add_wire(a.id, b.id, int(wr.port), wr.points.map(func(q): return Vector2(q[0], q[1])), a.built_from.id)

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
func push_out(w: World, src: Machine, p: Portion, c: Vector2i) -> bool:
	var ld := Machine.DIRS.find(c - src.cell)
	var ok := false
	for q in ports:
		if q.type == "out" and int(q.dir) == ld and Vector2i(int(q.off[0]), int(q.off[1])) == src.cell:
			ok = true
	if not ok:
		return false
	return w.push(self, p, cell + Machine.DIRS[world_dir(ld)])

func tick(w, dt: float) -> void:
	inner.tick(dt)
	var working := 0
	for m in inner.machines.values():
		if m.status.begins_with("работает") or m.status.begins_with("давление"):
			working += 1
	status = "внутри машин: %d, работают: %d" % [inner.machines.size(), working]
	hot = false
	for m in inner.machines.values():
		if m.hot:
			hot = true

func describe(w) -> Array:
	var l: Array = []
	l.append("%s — свёрнутый макроблок (прочность %.0f/%.0f)" % [display_name(), hp, max_hp()])
	l.append("Размер схемы %d×%d, %s" % [int(mb.size[0]), int(mb.size[1]), Macroblocks.describe_ports(mb)])
	for m in inner.machines.values():
		var extra := ""
		if m.has_gas():
			extra = ", %.1f атм" % inner.gas.pressure(m.id)
		l.append("  · %s: %s%s" % [m.display_name(), m.status if m.status != "" else "—", extra])
	if not enabled:
		l.append("Выключено")
	return l

func save_extra() -> Dictionary:
	var parts: Array = []
	for m in inner.machines.values():
		parts.append(SaveGame.machine_to(m, inner.gas))
	var wires: Array = inner.logic.wires.values().map(func(x): return {"from": x.from, "to": x.to, "port": x.port,
		"points": x.points.map(func(p): return [p.x, p.y]), "material": x.material})
	return {"mb": mb, "rot": rot, "parts": parts, "wires": wires}

func load_extra(w, d: Dictionary) -> void:
	mb = d.mb
	rot = int(d.rot)
	ports = mb.ports
	inner = InnerGrid.new(w, self, Vector2i(int(mb.size[0]), int(mb.size[1])))
	for md in d.parts:
		var sub: Substance = w.db.get_sub(md.sub)
		var m := inner.place(md.kind, SaveGame.v2i(md.cell), int(md.facing), sub, float(md.q), int(md.id))
		SaveGame.machine_restore(w, m, md, inner.gas)
	for x in d.wires:
		inner.logic.add_wire(int(x.from), int(x.to), int(x.port), x.points.map(func(p): return Vector2(p[0], p[1])), x.material)
