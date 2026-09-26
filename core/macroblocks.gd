class_name Macroblocks
## Макроблоки: сохранённые группы примитивов с проводами, настройками и
## вычисленными входами/выходами. Ставятся целиком, с поворотом.
## Библиотека общая для всех ранов (user://macroblocks.json).

const LIB_PATH := "user://macroblocks.json"

## Снять макроблок с прямоугольника мира (или внутренности свёрнутого блока).
## Свёрнутый блок в выделении становится частью со своей схемой (поле mb).
static func capture(w, rect: Rect2i, name: String) -> Dictionary:
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
		var part := {"kind": m.kind, "off": [off.x, off.y], "facing": m.facing, "config": cfg}
		if m is MacroMachine:
			part.mb = m.template()
		parts.append(part)
	var wires: Array = []
	var sig_in: Array = []
	var sig_out: Array = []
	for wr in w.logic.wires.values():
		if ids.has(wr.from) and ids.has(wr.to):
			wires.append({"from": [ids[wr.from].x, ids[wr.from].y], "to": [ids[wr.to].x, ids[wr.to].y], "port": wr.port,
				"points": wr.points.map(func(p): return [p.x - rect.position.x, p.y - rect.position.y])})
		elif ids.has(wr.to):
			# Провод снаружи внутрь — сигнальный вход блока.
			var e := {"to": [ids[wr.to].x, ids[wr.to].y], "port": wr.port}
			if not e in sig_in:
				sig_in.append(e)
		elif ids.has(wr.from):
			var o: Array = [ids[wr.from].x, ids[wr.from].y]
			if not o in sig_out:
				sig_out.append(o)
	var mb := {"name": name, "size": [rect.size.x, rect.size.y], "parts": parts, "wires": wires,
		"sig_in": sig_in, "sig_out": sig_out}
	mb.ports = compute_ports(mb)
	return mb

## Переназначить id целей пушек в конфиге (старый id → новый).
static func remap_config(cfg: Dictionary, idmap: Dictionary) -> Dictionary:
	var c := cfg.duplicate(true)
	if c.has("target"):
		c.target = idmap.get(int(c.target), -1)
	if c.has("routes"):
		c.routes = c.routes.filter(func(r): return idmap.has(int(r[1]))).map(func(r): return [r[0], idmap[int(r[1])]])
	return c

## Входы и выходы: стороны машин, смотрящие за пределы блока.
static func compute_ports(mb: Dictionary) -> Array:
	var size := Vector2i(int(mb.size[0]), int(mb.size[1]))
	var rect := Rect2i(Vector2i.ZERO, size)
	var ports: Array = []
	for p in mb.parts:
		var info: Dictionary = Buildings.KINDS[p.kind]
		var off := Vector2i(int(p.off[0]), int(p.off[1]))
		var f := int(p.facing)
		if p.kind == "macro":
			_nested_ports(ports, p, off, f, rect)
			continue
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
		# Газовая машина на краю схемы — газовый порт (сосед снаружи).
		if info.get("gas", 0.0) > 0.0:
			for d in 4:
				if not rect.has_point(off + Machine.DIRS[d]):
					ports.append({"type": "gas", "off": [off.x, off.y], "dir": d, "kind": p.kind})
					break
	return ports

## Порты вложенного блока — его собственные, повёрнутые вместе с ним; наружу
## выходят те, что смотрят за край схемы.
static func _nested_ports(ports: Array, p: Dictionary, off: Vector2i, f: int, rect: Rect2i) -> void:
	var gas_done := false
	for q in p.get("mb", {}).get("ports", []):
		var d := (int(q.dir) + f) % 4
		if q.type == "gas":
			# Как у газовой машины: узел блока связан со всеми соседями.
			if gas_done:
				continue
			gas_done = true
			d = -1
			for k in 4:
				if not rect.has_point(off + Machine.DIRS[k]):
					d = k
					break
			if d < 0:
				continue
		elif rect.has_point(off + Machine.DIRS[d]):
			continue
		var e := {"type": q.type, "off": [off.x, off.y], "dir": d, "kind": "macro"}
		if not e in ports:
			ports.append(e)

static func describe_ports(mb: Dictionary) -> String:
	var n := {"in": 0, "out": 0, "gas": 0}
	for p in mb.ports:
		n[p.type] = n.get(p.type, 0) + 1
	var s := "входов %d, выходов %d" % [n.in, n.out]
	if n.gas > 0:
		s += ", газ"
	var si: int = mb.get("sig_in", []).size()
	var so: int = mb.get("sig_out", []).size()
	if si > 0 or so > 0:
		s += ", сигнал %s" % ("вход и выход" if si > 0 and so > 0 else ("вход" if si > 0 else "выход"))
	return s

static func cost(w: World, mb: Dictionary) -> float:
	var s := 0.0
	for k in MacroMachine.flat_kinds(mb):
		s += w.build_cost(k)
	return s

## Проверить изучение и подобрать материалы для примитивов (с учётом уже отложенного).
## Возвращает текст ошибки или "" и дописывает материалы в out_subs.
static func _pick_subs(w: World, kinds: Array, preferred: Substance, reserved: Dictionary, out_subs: Array) -> String:
	for kind in kinds:
		if not w.robot.unlocked.has(kind):
			return "не изучено: " + Buildings.name_of(kind)
		var s := material_for(w, kind, preferred, reserved)
		if s == null:
			return "не хватает подходящего материала для «%s»" % Buildings.name_of(kind)
		reserved[s.id] = reserved.get(s.id, 0.0) + w.build_cost(kind)
		out_subs.append(s)
	return ""

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
		if not w.planet.buildable(c) or w.grid.has(c) or w.tile_overrides.has(c):
			return "мешает клетка %d,%d" % [c.x, c.y]
		if kind == "drill" and not w.planet.deposits.has(c):
			return "бур из блока не на залежи"
		if kind == "macro":
			var ce := MacroMachine.collapse_error(e[1].get("mb", {"parts": [{"kind": "macro"}]}))
			if ce != "":
				return ce
		var kinds: Array = MacroMachine.flat_kinds(e[1].mb) if kind == "macro" else [kind]
		var err := _pick_subs(w, kinds, preferred, reserved, [])
		if err != "":
			return err
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
		var m: Machine
		if e[1].kind == "macro":
			m = _place_nested(w, e[1].mb, e[0], e[2], preferred)
		else:
			m = w.place(e[1].kind, e[0], e[2], material_for(w, e[1].kind, preferred, {}))
		by_off[Vector2i(int(e[1].off[0]), int(e[1].off[1]))] = m
		placed.append([m, e[1]])
	for pair in placed:
		var m: Machine = pair[0]
		for k in pair[1].config:
			var v = pair[1].config[k]
			if m is MacroMachine:
				m.config[k] = v
			elif k == "target":
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

## Свёрнутый блок как часть разворачиваемого: материалы списываются за все его примитивы.
static func _place_nested(w: World, sub_mb: Dictionary, c: Vector2i, facing: int, preferred: Substance) -> MacroMachine:
	var subs: Array = []
	_pick_subs(w, MacroMachine.flat_kinds(sub_mb), preferred, {}, subs)
	for i in subs.size():
		w.robot.take_item(subs[i].id, w.build_cost(MacroMachine.flat_kinds(sub_mb)[i]))
	var m: MacroMachine = w.place("macro", c, facing, preferred if preferred != null else subs[0], true)
	m.setup(w, sub_mb, facing, subs)
	return m

## Поставить макроблок свёрнутым в одну клетку. Материалы тратятся как на все части.
static func can_place_collapsed(w: World, mb: Dictionary, c: Vector2i, preferred: Substance) -> String:
	var err := MacroMachine.collapse_error(mb)
	if err != "":
		return err
	if not w.planet.buildable(c) or w.grid.has(c) or w.tile_overrides.has(c):
		return "здесь нельзя строить"
	if w.machines.size() >= w.machine_limit():
		return "лимит машин"
	return _pick_subs(w, MacroMachine.flat_kinds(mb), preferred, {}, [])

static func place_collapsed(w: World, mb: Dictionary, c: Vector2i, rot: int, preferred: Substance) -> String:
	var err := can_place_collapsed(w, mb, c, preferred)
	if err != "":
		return err
	var subs: Array = []
	var kinds := MacroMachine.flat_kinds(mb)
	_pick_subs(w, kinds, preferred, {}, subs)
	for i in subs.size():
		w.robot.take_item(subs[i].id, w.build_cost(kinds[i]))
	var housing: Substance = preferred if preferred != null else subs[0]
	var m: MacroMachine = w.place("macro", c, rot, housing, true)
	m.setup(w, mb, rot, subs)
	w.robot.xp.chief += 5.0
	return ""

# ---------------------------------------------------------------- свёртка на месте и разворот

## Свернуть работающую схему в прямоугольнике в одну клетку, сохранив состояние машин.
## Возвращает {"err": текст, "macro": блок, "mb": шаблон}.
static func collapse_region(w: World, rect: Rect2i, name: String) -> Dictionary:
	var mb := capture(w, rect, name)
	if mb.is_empty():
		return {"err": "в выделении нет машин"}
	var err := MacroMachine.collapse_error(mb)
	if err != "":
		return {"err": err}
	var ms: Array = w.machines.values().filter(func(m): return rect.has_point(m.cell))
	ms.sort_custom(func(a, b): return a.cell.y < b.cell.y or (a.cell.y == b.cell.y and a.cell.x < b.cell.x))
	var ids := {}
	for m in ms:
		ids[m.id] = true
	var parts: Array = []
	for m in ms:
		var d := SaveGame.machine_to(m, w.gas)
		d.loc = [m.cell.x - rect.position.x, m.cell.y - rect.position.y]
		parts.append(d)
	var inner_wires: Array = []
	var ext_in: Array = []
	var ext_out: Array = []
	for wr in w.logic.wires.values():
		if ids.has(wr.from) and ids.has(wr.to):
			inner_wires.append({"from": wr.from, "to": wr.to, "port": wr.port, "material": wr.material,
				"points": wr.points.map(func(p): return p - Vector2(rect.position))})
		elif ids.has(wr.to):
			ext_in.append(wr.duplicate(true))
		elif ids.has(wr.from):
			ext_out.append(wr.duplicate(true))
	var host_cell: Vector2i = rect.position if w.planet.buildable(rect.position) and (not w.grid.has(rect.position) or ids.has(w.grid[rect.position])) else ms[0].cell
	var housing: Substance = ms[0].built_from
	for m in ms:
		w._erase(m)
	var macro: MacroMachine = w.place("macro", host_cell, 0, housing, true)
	macro.setup_live(w, mb, parts, inner_wires)
	# Внешние провода — теперь к блоку.
	var seen := {}
	for wr in ext_in:
		if not seen.has(wr.from):
			seen[wr.from] = true
			w.logic.add_wire(wr.from, macro.id, 0, [], wr.material)
	for wr in ext_out:
		w.logic.add_wire(macro.id, wr.to, wr.port, [], wr.material)
	w.robot.xp.chief += 5.0
	w.log_event(host_cell, "Схема «%s» свёрнута в одну клетку" % name)
	return {"err": "", "macro": macro, "mb": mb}

## Какая клетка мешает развернуть блок ("" — места хватает).
static func unfold_blocker(w: World, macro: MacroMachine) -> String:
	var size := Vector2i(int(macro.mb.size[0]), int(macro.mb.size[1]))
	for m in macro.inner.machines.values():
		var c: Vector2i = macro.cell + rot_off(m.cell, size, macro.rot)
		if c == macro.cell:
			continue
		if not w.planet.buildable(c) or w.grid.has(c) or w.tile_overrides.has(c):
			return "мешает клетка %d,%d" % [c.x, c.y]
		if m.kind == "drill" and not w.planet.deposits.has(c):
			return "бур не на залежи"
	if w.machines.size() - 1 + macro.inner.machines.size() > w.machine_limit():
		return "лимит машин"
	return ""

## Развернуть свёрнутый блок обратно в машины на карте (левый верхний угол — клетка блока).
static func unfold(w: World, macro: MacroMachine) -> String:
	var err := unfold_blocker(w, macro)
	if err != "":
		return err
	var size := Vector2i(int(macro.mb.size[0]), int(macro.mb.size[1]))
	var origin: Vector2i = macro.cell
	var rot: int = macro.rot
	var dicts: Array = []
	for m in macro.inner.machines.values():
		var d := SaveGame.machine_to(m, macro.inner.gas)
		d.dst = origin + rot_off(m.cell, size, rot)
		d.fac = (m.facing + rot) % 4
		if m is MacroMachine:
			d.extra.rot = (int(d.extra.rot) + rot) % 4   # вложенный блок поворачивается с внешним
		dicts.append(d)
	var wires: Array = macro.inner.logic.wires.values().filter(func(x): return x.from != MacroMachine.SIG_SOURCE)
	w.logic.remove_machine(macro.id)
	w._erase(macro)
	var idmap := {}
	var placed: Array = []
	for d in dicts:
		var m := w.place(d.kind, d.dst, d.fac, w.db.get_sub(d.sub), true)
		idmap[int(d.id)] = m.id
		SaveGame.machine_restore(w, m, d, w.gas)
		placed.append(m)
	for m in placed:
		m.config = remap_config(m.config, idmap)
	for wr in wires:
		var pts: Array = wr.points.map(func(p): return Vector2(origin) + rot_point(p, size, rot))
		w.logic.add_wire(idmap[wr.from], idmap[wr.to], wr.port, pts, wr.material)
	w.log_event(origin, "Макроблок «%s» развёрнут" % macro.display_name())
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
