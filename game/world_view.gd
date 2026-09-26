extends Node2D
## Рисует мир примитивами: тайлы, залежи, машины, трубы, провода, капсулы, робота.

const T := 32.0

var world: World
var main                       # game/main.gd — состояние инструментов для превью
var font: Font
var _t := 0.0

func _ready() -> void:
	font = ThemeDB.fallback_font

func _process(dt: float) -> void:
	_t += dt
	queue_redraw()

static func cell_center(c: Vector2i) -> Vector2:
	return (Vector2(c) + Vector2(0.5, 0.5)) * T

func ground_color() -> Color:
	var p := world.planet
	var c := Color(0.36, 0.31, 0.26)
	if p.has_tag("volcanic"): c = Color(0.30, 0.20, 0.18)
	if p.has_tag("frozen"): c = Color(0.62, 0.68, 0.74)
	if p.has_tag("oceanic"): c = Color(0.25, 0.36, 0.30)
	if p.has_tag("crystalline_crust"): c = c.lerp(Color(0.5, 0.55, 0.65), 0.35)
	if p.has_tag("toxic_atmosphere"): c = c.lerp(Color(0.4, 0.45, 0.2), 0.25)
	if p.has_tag("anomalous_field"): c = c.lerp(Color(0.4, 0.3, 0.5), 0.3)
	return c

func _visible_rect() -> Rect2i:
	var cam := get_viewport().get_camera_2d()
	var size := get_viewport_rect().size
	var zoom := cam.zoom if cam != null else Vector2.ONE
	var center := cam.get_screen_center_position() if cam != null else size / 2.0
	var half := size / zoom / 2.0
	var a := ((center - half) / T).floor()
	var b := ((center + half) / T).ceil()
	var w := world.planet.width
	var h := world.planet.height
	var x0 := clampi(int(a.x), 0, w)
	var y0 := clampi(int(a.y), 0, h)
	var x1 := clampi(int(b.x) + 1, 0, w)
	var y1 := clampi(int(b.y) + 1, 0, h)
	return Rect2i(x0, y0, x1 - x0, y1 - y0)

func _draw() -> void:
	if world == null:
		return
	var vr := _visible_rect()
	_draw_tiles(vr)
	_draw_deposits(vr)
	_draw_ground(vr)
	_draw_pipes()
	_draw_machines(vr)
	_draw_structures()
	_draw_links()
	_draw_wires()
	_draw_drones()
	_draw_fires()
	_draw_robot()
	_draw_projectiles()
	_draw_tool_preview()
	_draw_hover()

func _draw_tiles(vr: Rect2i) -> void:
	var g := ground_color()
	for y in range(vr.position.y, vr.end.y):
		for x in range(vr.position.x, vr.end.x):
			var c := Vector2i(x, y)
			var r := Rect2(Vector2(c) * T, Vector2(T, T))
			var shade := 0.94 + 0.06 * float((x * 7 + y * 13) % 5) / 4.0
			match world.tile(c):
				Planet.Tile.GROUND:
					draw_rect(r, g * shade)
					if world.tile_overrides.has(c):
						draw_rect(r, Color(0.7, 0.9, 1.0, 0.55))
				Planet.Tile.ROCK:
					draw_rect(r, Color(0.16, 0.15, 0.16) * shade)
					draw_rect(r.grow(-6), Color(0.22, 0.21, 0.22))
				Planet.Tile.CHASM:
					draw_rect(r, Color(0.02, 0.02, 0.03))
				Planet.Tile.LAVA:
					var k := 0.5 + 0.5 * sin(_t * 2.0 + x * 0.7 + y * 0.5)
					draw_rect(r, Color(0.85, 0.25 + 0.2 * k, 0.05))
				Planet.Tile.ICE:
					draw_rect(r, Color(0.70, 0.86, 0.95) * shade)
					var st: float = world.ice_stress.get(c, 0.0)
					if st > 0.0:
						draw_line(r.position + Vector2(4, 6), r.end - Vector2(6, 4), Color(0.2, 0.3, 0.4), 1.0 + st)
				Planet.Tile.ACID:
					var k2 := 0.5 + 0.5 * sin(_t * 1.5 + x + y)
					draw_rect(r, Color(0.35, 0.70 + 0.1 * k2, 0.20))
				Planet.Tile.RUIN:
					draw_rect(r, Color(0.32, 0.28, 0.36) * shade)
					draw_rect(r.grow(-9), Color(0.45, 0.40, 0.55), false, 2.0)

func _deposit_visible(c: Vector2i) -> bool:
	return world.revealed.has(c) or world.near_robot(c, 4.5)

func _draw_deposits(vr: Rect2i) -> void:
	for c in world.planet.deposits:
		if not vr.has_point(c):
			continue
		var dep: Dictionary = world.planet.deposits[c]
		if dep.amount <= 0.0:
			continue
		var s: Substance = world.db.get_sub(dep.sub)
		var ctr := cell_center(c)
		var rad: float = clamp(4.0 + dep.amount * 0.12, 5.0, 12.0)
		if _deposit_visible(c):
			for i in 3:
				var off := Vector2(cos(i * 2.1 + c.x), sin(i * 2.1 + c.y)) * 7.0
				draw_circle(ctr + off, rad * 0.6, s.color.darkened(0.15))
			if s.is_exotic() and world.is_analyzed(s):
				draw_arc(ctr, rad + 4.0, 0, TAU, 16, Color(1, 0.6, 1, 0.5 + 0.4 * sin(_t * 3.0)), 1.5)
		else:
			draw_circle(ctr, 4.0, Color(0.55, 0.5, 0.45, 0.6))

func _draw_ground(vr: Rect2i) -> void:
	for c in world.ground:
		if not vr.has_point(c):
			continue
		var i := 0
		for p in world.ground[c]:
			var pos := Vector2(c) * T + Vector2(8 + (i % 3) * 8, 10 + (i / 3) * 8)
			var sz: float = clamp(3.0 + p.mass * 0.5, 3.0, 8.0)
			var col: Color = p.substance.color
			if p.phase() == Substance.Phase.LIQUID:
				draw_circle(pos, sz, col)
			else:
				draw_rect(Rect2(pos - Vector2(sz, sz) / 2.0, Vector2(sz, sz)), col)
			i += 1

func pressure_color(p: float) -> Color:
	var k: float = clamp((p - 1.0) / 8.0, 0.0, 1.0)
	return Color(0.3, 0.5, 0.9).lerp(Color(0.95, 0.25, 0.2), k)

func _draw_pipes() -> void:
	for e in world.gas.edges.values():
		var a = world.machines.get(e.a)
		var b = world.machines.get(e.b)
		if a == null or b == null:
			continue
		var p := (world.gas.pressure(e.a) + world.gas.pressure(e.b)) / 2.0
		var col := pressure_color(p) if e.open else Color(0.3, 0.3, 0.3)
		draw_line(cell_center(a.cell), cell_center(b.cell), col.darkened(0.3), 9.0)
		draw_line(cell_center(a.cell), cell_center(b.cell), col, 5.0)

const SHORT := {"drill": "Бур", "container": "Конт", "tank": "Бак", "receiver": "Приём", "fabricator": "Фаб",
	"pump": "Насос", "pipe": "", "valve": "Клап", "cannon": "Пушка", "crusher": "Дроб", "furnace": "Печь",
	"condenser": "Хол", "treater": "Обр", "compressor": "Компр", "decompressor": "Деко", "distiller": "Дист",
	"centrifuge": "Центр", "magnet_sep": "Магн", "filter": "Фильтр", "electrolyzer": "Элек", "sinter": "Спек",
	"irradiator": "Облуч", "loom": "Ткач", "sensor": "Дат", "gate_and": "И", "gate_or": "ИЛИ", "gate_not": "НЕ",
	"launch_silo": "Шахта", "dome": "Купол", "beacon": "Маяк", "warehouse_section": "Склад",
	"battery_section": "Батар", "catch_net": "", "macro": "МБ"}

func _draw_machines(vr: Rect2i) -> void:
	for m in world.machines.values():
		if not vr.has_point(m.cell):
			continue
		_draw_machine(m.kind, m.cell, m.facing, m.built_from.color, m)

func _draw_machine(kind: String, c: Vector2i, facing: int, col: Color, m = null, ghost: bool = false) -> void:
	var r := Rect2(Vector2(c) * T, Vector2(T, T))
	var ctr := cell_center(c)
	var a := 0.45 if ghost else 1.0
	var body := Color(col.darkened(0.25), a)
	var info: Dictionary = Buildings.KINDS[kind]
	if kind == "catch_net":
		for i in range(1, 4):
			var k := T * i / 4.0
			draw_line(r.position + Vector2(k, 2), r.position + Vector2(k, T - 2), Color(body.lightened(0.3), 0.8 * a), 1.0)
			draw_line(r.position + Vector2(2, k), r.position + Vector2(T - 2, k), Color(body.lightened(0.3), 0.8 * a), 1.0)
	elif kind == "macro":
		draw_rect(r.grow(-1), body)
		draw_rect(r.grow(-1), Color(0.5, 0.85, 1.0, a), false, 2.0)
		draw_rect(r.grow(-5), Color(0.5, 0.85, 1.0, 0.6 * a), false, 1.0)
	elif kind == "pipe":
		draw_circle(ctr, 7.0, Color(body, a))
		draw_arc(ctr, 7.0, 0, TAU, 12, Color(0, 0, 0, 0.5 * a), 1.5)
	elif kind in ["sensor", "gate_and", "gate_or", "gate_not"]:
		draw_rect(r.grow(-7), body)
		draw_rect(r.grow(-7), Color(0.9, 0.85, 0.3, a), false, 1.5)
	elif kind == "dome" or kind == "tank":
		draw_circle(ctr, T * 0.46, body)
		draw_arc(ctr, T * 0.46, 0, TAU, 20, Color(0.1, 0.1, 0.1, a), 2.0)
	else:
		draw_rect(r.grow(-2), body)
		draw_rect(r.grow(-2), Color(0.08, 0.08, 0.1, a), false, 2.0)
	if info.get("cat", 0) == 2:
		draw_rect(Rect2(r.position + Vector2(2, 2), Vector2(T - 4, 5)), Color(0.9, 0.6, 0.2, a))
	var label: String = SHORT.get(kind, "")
	if label != "":
		_plate(ctr + Vector2(0, T * 0.5 - 2), label, 9, a)
	# Направление выхода.
	if not kind in ["pipe", "catch_net", "fabricator", "launch_silo", "macro"]:
		var d := Vector2(Machine.DIRS[facing])
		var tip := ctr + d * (T * 0.5 - 2.0)
		var side := Vector2(-d.y, d.x) * 5.0
		draw_colored_polygon(PackedVector2Array([tip, tip - d * 7.0 + side, tip - d * 7.0 - side]), Color(1, 1, 1, 0.85 * a))
		var info_outs: int = Processes.PROCESSES[info.process].outs if info.has("process") else 1
		if info_outs == 2:
			var d2 := Vector2(Machine.DIRS[(facing + 1) % 4])
			var tip2 := ctr + d2 * (T * 0.5 - 2.0)
			var s2 := Vector2(-d2.y, d2.x) * 4.0
			draw_colored_polygon(PackedVector2Array([tip2, tip2 - d2 * 6.0 + s2, tip2 - d2 * 6.0 - s2]), Color(0.7, 0.9, 1.0, 0.85 * a))
	if m == null:
		return
	if m.hot:
		draw_rect(r.grow(-1), Color(1.0, 0.45, 0.1, 0.25 + 0.15 * sin(_t * 6.0)), false, 3.0)
	if not m.enabled:
		draw_line(r.position + Vector2(4, 4), r.end - Vector2(4, 4), Color(0.9, 0.2, 0.2, 0.8), 2.0)
	if m.capacity() > 0.0:
		var f: float = clamp(m.total_mass() / m.capacity(), 0.0, 1.0)
		draw_rect(Rect2(r.position + Vector2(3, T - 6), Vector2((T - 6) * f, 3)), Color(0.4, 0.9, 0.4))
		if not m.items.is_empty():
			draw_circle(r.position + Vector2(T - 7, 11), 4.0, m.items[0].substance.color)
	if m is Processor and m.busy != null:
		draw_circle(ctr + Vector2(0, 6), 4.0 + 1.5 * sin(_t * 8.0), m.busy.substance.color)
	if m.hp < m.max_hp() * 0.99:
		var hf: float = clamp(m.hp / m.max_hp(), 0.0, 1.0)
		draw_rect(Rect2(r.position + Vector2(3, -4), Vector2((T - 6) * hf, 3)), Color(0.9, 0.3, 0.2))
	if m is MacroMachine:
		for p in m.ports:
			var d := Vector2(Machine.DIRS[m.world_dir(int(p.dir))])
			var base := ctr + d * (T * 0.5 - 3.0)
			var pcol := Color(0.4, 1.0, 0.5) if p.type == "out" else Color(1.0, 0.6, 0.3)
			draw_circle(base, 3.0, pcol)
	if m.has_gas() and kind != "pipe":
		draw_arc(ctr, T * 0.3, -PI / 2, -PI / 2 + TAU * clamp(world.gas.pressure(m.id) / 10.0, 0.0, 1.0), 16, pressure_color(world.gas.pressure(m.id)), 2.0)
	if world.logic.outputs.get(m.id, false):
		draw_circle(r.position + Vector2(6, 6), 3.0, Color(1, 0.9, 0.2))
	if m.stats.get("light", false):
		draw_circle(ctr, T * 0.8, Color(1, 1, 0.7, 0.07))

func _draw_structures() -> void:
	for m in world.machines.values():
		if m.kind == "warehouse_section" and m.master_id == m.id:
			var r := Rect2(Vector2(m.cell) * T, Vector2(T * 2, T * 2)).grow(-1)
			draw_rect(r, Color(0.9, 0.8, 0.4, 0.9), false, 3.0)
			var f: float = clamp(m.total_mass() / m.capacity(), 0.0, 1.0)
			draw_rect(Rect2(r.position + Vector2(4, r.size.y - 8), Vector2((r.size.x - 8) * f, 4)), Color(0.4, 0.9, 0.4))
		elif m.kind == "battery_section" and m.master_id == m.id:
			var r := Rect2(Vector2(m.cell) * T, Vector2(T * 2, T * 2)).grow(-1)
			draw_rect(r, Color(1.0, 0.5, 0.3, 0.9), false, 3.0)
			draw_circle(r.get_center(), T * 0.45, Color(0.15, 0.15, 0.18))
			draw_arc(r.get_center(), T * 0.45, 0, TAU, 20, Color(1.0, 0.5, 0.3), 2.0)

func _draw_links() -> void:
	for m in world.machines.values():
		if not m is Cannon:
			continue
		var links: Array = []
		if world.machines.has(m.config.target):
			links.append([m.config.target, Color(1, 1, 1, 0.25)])
		for r in m.config.get("routes", []):
			if world.machines.has(int(r[1])):
				var col: Color = MaterialTags.TAGS[r[0]].col
				links.append([int(r[1]), Color(col, 0.6)])
		for l in links:
			var t = world.machines[l[0]]
			var a := cell_center(m.cell)
			var b := cell_center(t.cell)
			var n := int(a.distance_to(b) / 12.0)
			for i in range(0, n, 2):
				draw_line(a.lerp(b, float(i) / n), a.lerp(b, float(i + 1) / n), l[1], 1.5)

func wire_poly(w: Dictionary) -> Array:
	var a = world.machines.get(w.from)
	var b = world.machines.get(w.to)
	if a == null or b == null:
		return []
	var pts: Array = [cell_center(a.cell)]
	for p in w.points:
		pts.append(p * T)
	pts.append(cell_center(b.cell) + Vector2(0, 6 if w.port == 1 else -6))
	return pts

func _draw_wires() -> void:
	for w in world.logic.wires.values():
		var poly := wire_poly(w)
		if poly.is_empty():
			continue
		var on: bool = world.logic.outputs.get(w.from, false)
		var col := Color(1.0, 0.85, 0.2) if on else Color(0.55, 0.55, 0.5)
		for i in range(poly.size() - 1):
			draw_line(poly[i], poly[i + 1], col, 2.0)
		for p in w.points:
			draw_circle(p * T, 4.0, col)
		draw_circle(poly[-1], 3.0, Color(0.9, 0.4, 0.4) if w.port == 1 else Color(0.4, 0.8, 0.9))

func _draw_drones() -> void:
	for d in world.drones:
		var p: Vector2 = d.pos * T
		draw_colored_polygon(PackedVector2Array([p + Vector2(0, -7), p + Vector2(6, 5), p + Vector2(-6, 5)]), Color(0.8, 0.9, 1.0))
		if d.cargo != null:
			draw_circle(p + Vector2(0, 8), 3.0, d.cargo.substance.color)

func _draw_fires() -> void:
	for c in world.fires:
		var ctr := cell_center(c)
		for i in 3:
			var k := sin(_t * 9.0 + i * 2.0)
			draw_circle(ctr + Vector2(i * 6 - 6, k * 3.0), 6.0 + k * 2.0, Color(1.0, 0.5 + 0.2 * k, 0.1, 0.7))

func _draw_robot() -> void:
	var r := world.robot
	var p := r.pos * T
	var hull_col: Color = r.hull.sub.color if r.hull != null else Color(0.8, 0.8, 0.8)
	draw_circle(p + Vector2(0, 3), 13.0, Color(0, 0, 0, 0.3))
	draw_circle(p, 12.0, hull_col.lightened(0.2))
	draw_arc(p, 12.0, 0, TAU, 20, Color(0.1, 0.1, 0.12), 2.0)
	var aim: Vector2 = (get_global_mouse_position() - p).normalized()
	draw_line(p, p + aim * 16.0, Color(0.1, 0.1, 0.12), 3.0)
	draw_circle(p + aim * 5.0, 4.0, Color(0.3, 0.9, 1.0))
	# Бортовой баллон.
	var f: float = clamp(r.tank / r.tank_cap(), 0.0, 1.0)
	draw_rect(Rect2(p + Vector2(-12, 16), Vector2(24, 3)), Color(0.1, 0.1, 0.1))
	draw_rect(Rect2(p + Vector2(-12, 16), Vector2(24 * f, 3)), Color(0.4, 0.7, 1.0))

func _draw_projectiles() -> void:
	for pr in world.projectiles:
		var k: float = pr.t / pr.dur
		var a: Vector2 = pr.from * T
		var b: Vector2 = pr.to * T
		var h := a.distance_to(b) * 0.35
		var pos := a.lerp(b, k) - Vector2(0, sin(PI * k) * h)
		if pr.kind == "rocket":
			pos = a.lerp(b, k * k)
			draw_circle(pos + Vector2(0, 10), 6.0, Color(1, 0.7, 0.2, 0.7))
		var col := Color(0.85, 0.85, 0.9)
		if not pr.payload.is_empty():
			col = pr.payload[0].substance.color
		draw_circle(pos + Vector2(0, sin(PI * k) * h * 0.0), 6.0, Color(0.15, 0.15, 0.18))
		draw_circle(pos, 4.0, col)

## Надпись целиком на тёмной подложке, по центру над точкой (нижний край — в pos).
func _plate(pos: Vector2, text: String, size: int, alpha: float = 1.0, col: Color = Color.WHITE) -> void:
	var lines := text.split("\n")
	var wmax := 0.0
	for l in lines:
		wmax = max(wmax, font.get_string_size(l, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x)
	var lh := font.get_height(size)
	var h := lh * lines.size()
	var rect := Rect2(pos - Vector2(wmax / 2.0 + 3, h + 1), Vector2(wmax + 6, h + 2))
	draw_rect(rect, Color(0.04, 0.05, 0.07, 0.72 * alpha))
	for i in lines.size():
		draw_string(font, Vector2(rect.position.x + 3, rect.position.y + font.get_ascent(size) + 1 + lh * i), lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(col, 0.95 * alpha))

func _draw_hover() -> void:
	if main == null or main.mode != "none":
		return
	var m = world.machine_at(main.mouse_cell())
	if m == null:
		return
	var text: String = m.display_name()
	if m.status != "":
		text += "\n" + m.status
	_plate(cell_center(m.cell) + Vector2(0, -T * 0.5 - 16), text, 12)

func _draw_tool_preview() -> void:
	if main == null:
		return
	var mc: Vector2i = main.mouse_cell()
	var r := Rect2(Vector2(mc) * T, Vector2(T, T))
	match main.mode:
		"build":
			var sub: Substance = main.build_material()
			var err: String = world.can_place(main.build_kind, mc, sub)
			if main.build_kind == "drill":
				for c in world.planet.deposits:
					if not world.grid.has(c) and world.planet.deposits[c].amount > 0.0:
						draw_rect(Rect2(Vector2(c) * T, Vector2(T, T)).grow(-2), Color(0.4, 1.0, 0.5, 0.55), false, 1.5)
			if err != "":
				draw_string(font, Vector2(mc) * T + Vector2(T + 4, T * 0.6), err, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1.0, 0.45, 0.4))
			_draw_machine(main.build_kind, mc, main.build_facing, sub.color if sub != null else Color.GRAY, null, true)
			draw_rect(r, Color(0.3, 1.0, 0.4, 0.8) if err == "" else Color(1.0, 0.3, 0.3, 0.8), false, 2.0)
		"remove":
			draw_rect(r, Color(1, 0.3, 0.3, 0.8), false, 2.0)
		"macro_select":
			var sr: Rect2i = main.selection_rect()
			draw_rect(Rect2(Vector2(sr.position) * T, Vector2(sr.size) * T), Color(0.4, 0.8, 1.0, 0.15))
			draw_rect(Rect2(Vector2(sr.position) * T, Vector2(sr.size) * T), Color(0.4, 0.8, 1.0, 0.9), false, 2.0)
		"macro_place":
			if main.macro_idx >= 0 and main.macro_idx < main.macro_lib.size():
				var mb: Dictionary = main.macro_lib[main.macro_idx]
				var sub: Substance = world.db.get_sub(world.robot.selected) if world.robot.selected != "" else null
				if main.macro_collapsed:
					var cerr := Macroblocks.can_place_collapsed(world, mb, mc, sub)
					_draw_machine("macro", mc, main.macro_rot, sub.color if sub != null else Color.GRAY, null, true)
					draw_rect(r, Color(0.3, 1.0, 0.4, 0.9) if cerr == "" else Color(1.0, 0.3, 0.3, 0.9), false, 2.0)
					return
				var err := Macroblocks.can_place(world, mb, mc, main.macro_rot, sub)
				for e in Macroblocks.footprint(mb, mc, main.macro_rot):
					_draw_machine(e[1].kind, e[0], e[2], sub.color if sub != null else Color.GRAY, null, true)
				var sz := Macroblocks.rotated_size(mb, main.macro_rot)
				draw_rect(Rect2(Vector2(mc) * T, Vector2(sz) * T), Color(0.3, 1.0, 0.4, 0.9) if err == "" else Color(1.0, 0.3, 0.3, 0.9), false, 2.0)
				var size := Vector2i(int(mb.size[0]), int(mb.size[1]))
				for p in mb.ports:
					var c: Vector2i = mc + Macroblocks.rot_off(Vector2i(int(p.off[0]), int(p.off[1])), size, main.macro_rot)
					var d := Vector2(Machine.DIRS[(int(p.dir) + main.macro_rot) % 4])
					var base := cell_center(c) + d * T * 0.5
					var col := Color(0.4, 1.0, 0.5) if p.type == "out" else Color(1.0, 0.6, 0.3)
					var tip := base + d * (10.0 if p.type == "out" else -10.0)
					draw_line(base, tip, col, 3.0)
		"wire", "link":
			draw_rect(r, Color(1, 0.9, 0.3, 0.8), false, 2.0)
			if main.pending_cell != null:
				draw_line(cell_center(main.pending_cell), get_global_mouse_position(), Color(1, 0.9, 0.3, 0.7), 2.0)
		_:
			draw_rect(r, Color(1, 1, 1, 0.25), false, 1.0)
	if main.selected_cell != null and world.machine_at(main.selected_cell) != null:
		draw_rect(Rect2(Vector2(main.selected_cell) * T, Vector2(T, T)).grow(2), Color(0.3, 0.9, 1.0), false, 2.0)
