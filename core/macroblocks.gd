class_name Macroblocks
## Макроблоки: сохранённые группы примитивов с проводами, настройками и
## вычисленными входами/выходами. Ставятся целиком, с поворотом.
## Библиотека общая для всех ранов (user://macroblocks.json).

const LIB_PATH := "user://macroblocks.json"

## Снять макроблок с прямоугольника мира.
static func capture(w: World, rect: Rect2i, name: String) -> Dictionary:
	var parts: Array = []
	var ids := {}
	for m in w.machines.values():
		if rect.has_point(m.cell):
			ids[m.id] = m.cell - rect.position
	if ids.is_empty():
		return {}
	for m in w.machines.values():
		if not ids.has(m.id):
			continue
		var off: Vector2i = ids[m.id]
		var cfg: Dictionary = m.config.duplicate(true)
		if cfg.has("target"):
			cfg.target = [ids[cfg.target].x, ids[cfg.target].y] if ids.has(cfg.target) else null
		if cfg.has("routes"):
			cfg.routes = cfg.routes.filter(func(r): return ids.has(int(r[1]))).map(func(r): return [r[0], [ids[int(r[1])].x, ids[int(r[1])].y]])
		parts.append({"kind": m.kind, "off": [off.x, off.y], "facing": m.facing, "config": cfg})
	var wires: Array = []
	for wr in w.logic.wires.values():
		if ids.has(wr.from) and ids.has(wr.to):
			wires.append({"from": [ids[wr.from].x, ids[wr.from].y], "to": [ids[wr.to].x, ids[wr.to].y], "port": wr.port,
				"points": wr.points.map(func(p): return [p.x - rect.position.x, p.y - rect.position.y])})
	var mb := {"name": name, "size": [rect.size.x, rect.size.y], "parts": parts, "wires": wires}
	mb.ports = compute_ports(mb)
	return mb

## Входы и выходы: стороны машин, смотрящие за пределы блока.
static func compute_ports(mb: Dictionary) -> Array:
	var size := Vector2i(int(mb.size[0]), int(mb.size[1]))
	var rect := Rect2i(Vector2i.ZERO, size)
	var ports: Array = []
	for p in mb.parts:
		var info: Dictionary = Buildings.KINDS[p.kind]
		var off := Vector2i(int(p.off[0]), int(p.off[1]))
		var f := int(p.facing)
		var outs := 0
		if info.has("process"):
			outs = Processes.PROCESSES[info.process].outs
		elif p.kind in ["drill", "container", "tank", "receiver", "warehouse_section"]:
			outs = 1
		for i in outs:
			var c: Vector2i = off + Machine.DIRS[(f + i) % 4]
			if not rect.has_point(c):
				ports.append({"type": "out", "off": [off.x, off.y], "dir": (f + i) % 4, "kind": p.kind})
		var accepts: bool = info.get("cap", 0.0) > 0.0 and p.kind != "drill"
		if accepts:
			var c2: Vector2i = off + Machine.DIRS[(f + 2) % 4]
			if not rect.has_point(c2):
				ports.append({"type": "in", "off": [off.x, off.y], "dir": (f + 2) % 4, "kind": p.kind})
	return ports

static func describe_ports(mb: Dictionary) -> String:
	var ins := 0
	var outs := 0
	for p in mb.ports:
		if p.type == "in": ins += 1
		else: outs += 1
	return "входов %d, выходов %d" % [ins, outs]

static func cost(w: World, mb: Dictionary) -> float:
	var s := 0.0
	for p in mb.parts:
		s += w.build_cost(p.kind)
	return s

static func rotated_size(mb: Dictionary, rot: int) -> Vector2i:
	var s := Vector2i(int(mb.size[0]), int(mb.size[1]))
	return s if rot % 2 == 0 else Vector2i(s.y, s.x)

## Поворот смещения клетки на rot×90° по часовой.
static func rot_off(off: Vector2i, size: Vector2i, rot: int) -> Vector2i:
	var o := off
	var s := size
	for i in rot % 4:
		o = Vector2i(s.y - 1 - o.y, o.x)
		s = Vector2i(s.y, s.x)
	return o

## Поворот непрерывной точки (путевые точки проводов).
static func rot_point(p: Vector2, size: Vector2i, rot: int) -> Vector2:
	var o := p
	var s := Vector2(size)
	for i in rot % 4:
		o = Vector2(s.y - o.y, o.x)
		s = Vector2(s.y, s.x)
	return o

## [клетка, часть, направление] для размещения в origin с поворотом.
static func footprint(mb: Dictionary, origin: Vector2i, rot: int) -> Array:
	var size := Vector2i(int(mb.size[0]), int(mb.size[1]))
	var out: Array = []
	for p in mb.parts:
		var off := rot_off(Vector2i(int(p.off[0]), int(p.off[1])), size, rot)
		out.append([origin + off, p, (int(p.facing) + rot) % 4])
	return out

## Материал для части: выбранный, а если не подходит — любой подходящий из инвентаря.
static func material_for(w: World, kind: String, preferred: Substance, reserved: Dictionary) -> Substance:
	var need := w.build_cost(kind)
	var cands: Array = []
	if preferred != null:
		cands.append(preferred)
	var keys: Array = w.robot.inventory.keys()
	keys.sort()
	for id in keys:
		cands.append(w.db.get_sub(id))
	for s in cands:
		if Buildings.check_material(kind, s, w.planet.ambient_temp) != "":
			continue
		if w.robot.mass_of(s.id) - reserved.get(s.id, 0.0) + 0.001 >= need:
			return s
	return null

static func can_place(w: World, mb: Dictionary, origin: Vector2i, rot: int, preferred: Substance) -> String:
	var reserved := {}
	for e in footprint(mb, origin, rot):
		var c: Vector2i = e[0]
		var kind: String = e[1].kind
		if not w.robot.unlocked.has(kind):
			return "не изучено: " + Buildings.name_of(kind)
		if not w.planet.buildable(c) or w.grid.has(c) or w.tile_overrides.has(c):
			return "мешает клетка %d,%d" % [c.x, c.y]
		if kind == "drill" and not w.planet.deposits.has(c):
			return "бур из блока не на залежи"
		var s := material_for(w, kind, preferred, reserved)
		if s == null:
			return "не хватает подходящего материала для «%s»" % Buildings.name_of(kind)
		reserved[s.id] = reserved.get(s.id, 0.0) + w.build_cost(kind)
	if w.machines.size() + mb.parts.size() > w.machine_limit():
		return "лимит машин"
	return ""

static func place(w: World, mb: Dictionary, origin: Vector2i, rot: int, preferred: Substance) -> String:
	var err := can_place(w, mb, origin, rot, preferred)
	if err != "":
		return err
	var size := Vector2i(int(mb.size[0]), int(mb.size[1]))
	var by_off := {}
	var placed: Array = []
	for e in footprint(mb, origin, rot):
		var s := material_for(w, e[1].kind, preferred, {})
		var m := w.place(e[1].kind, e[0], e[2], s)
		by_off[Vector2i(int(e[1].off[0]), int(e[1].off[1]))] = m
		placed.append([m, e[1]])
	for pair in placed:
		var m: Machine = pair[0]
		for k in pair[1].config:
			var v = pair[1].config[k]
			if k == "target":
				var t = by_off.get(Vector2i(int(v[0]), int(v[1]))) if v != null else null
				m.config.target = t.id if t != null else -1
			elif k == "routes":
				var routes: Array = []
				for r in v:
					var t = by_off.get(Vector2i(int(r[1][0]), int(r[1][1])))
					if t != null:
						routes.append([r[0], t.id])
				m.config.routes = routes
			else:
				m.config[k] = v
	for wr in mb.wires:
		var a = by_off.get(Vector2i(int(wr.from[0]), int(wr.from[1])))
		var b = by_off.get(Vector2i(int(wr.to[0]), int(wr.to[1])))
		if a == null or b == null:
			continue
		var pts: Array = wr.points.map(func(p): return Vector2(origin) + rot_point(Vector2(p[0], p[1]), size, rot))
		w.logic.add_wire(a.id, b.id, int(wr.port), pts, a.built_from.id)
	w.robot.xp.chief += 3.0
	return ""

## Поставить макроблок свёрнутым в одну клетку. Материалы тратятся как на все части.
static func can_place_collapsed(w: World, mb: Dictionary, c: Vector2i, preferred: Substance) -> String:
	var err := MacroMachine.collapse_error(mb)
	if err != "":
		return err
	if not w.planet.buildable(c) or w.grid.has(c) or w.tile_overrides.has(c):
		return "здесь нельзя строить"
	if w.machines.size() >= w.machine_limit():
		return "лимит машин"
	var reserved := {}
	for p in mb.parts:
		if not w.robot.unlocked.has(p.kind):
			return "не изучено: " + Buildings.name_of(p.kind)
		var s := material_for(w, p.kind, preferred, reserved)
		if s == null:
			return "не хватает подходящего материала для «%s»" % Buildings.name_of(p.kind)
		reserved[s.id] = reserved.get(s.id, 0.0) + w.build_cost(p.kind)
	return ""

static func place_collapsed(w: World, mb: Dictionary, c: Vector2i, rot: int, preferred: Substance) -> String:
	var err := can_place_collapsed(w, mb, c, preferred)
	if err != "":
		return err
	var subs: Array = []
	for p in mb.parts:
		var s := material_for(w, p.kind, preferred, {})
		w.robot.take_item(s.id, w.build_cost(p.kind))
		subs.append(s)
	var housing: Substance = preferred if preferred != null else subs[0]
	var m: MacroMachine = w.place("macro", c, rot, housing, true)
	m.setup(w, mb, rot, subs)
	w.robot.xp.chief += 5.0
	return ""

# ---------------------------------------------------------------- библиотека

static func load_library() -> Array:
	if not FileAccess.file_exists(LIB_PATH):
		return []
	var data = JSON.parse_string(FileAccess.get_file_as_string(LIB_PATH))
	return data if typeof(data) == TYPE_ARRAY else []

static func save_library(lib: Array) -> void:
	var f := FileAccess.open(LIB_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(lib, "  "))
