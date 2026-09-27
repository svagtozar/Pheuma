class_name ProtoPneumaticsView
extends Node3D
## 3D-вид пневмозавода (ProtoPneumatics): корпуса деталей из материала, стеклянные
## трубы с капсулами груза внутри, манометры (зелёный → красный к пределу
## материала), подписи машин, разрывы. Сам шагает симуляцию в _process.
## ghost() — полупрозрачная деталь-призрак для режима стройки.

const PIPE_Y := 0.55
const PIPE_R := 0.16

var net: ProtoPneumatics
## Облик сооружений целей (GoalModels.STYLES): "" — MachineModels.
static var goal_style := ""
var origin := Vector3.ZERO
var running := true
## В игре подпись видна только у ближней к роботу машины (в LABEL_R м): иначе
## у площадки десяток крупных подписей наезжает друг на друга и на HUD.
## null — видны все (кадры завода).
var focus: Node3D = null
const LABEL_R := 4.5
const LABEL_PX := 0.0009      # при fixed_size: ≈24 px строка на 1280×800

var _nodes := {}          # id детали → Node3D
var _sig := ""            # отпечаток расстановки: при смене трубы перестраиваются
var _caps: Array = []     # MeshInstance3D капсул (пул)
var _cap_mesh: CapsuleMesh
var _gauges := {}         # id → StandardMaterial3D манометра
var _labels := {}         # id → Label3D
var _ghost: Node3D
var _ghost_key := ""
var _t := 0.0
var _flights: Array = []  # MeshInstance3D капсул пушек в полёте (пул)

func setup(n: ProtoPneumatics, o: Vector3) -> void:
	net = n
	origin = o
	_cap_mesh = CapsuleMesh.new()
	_cap_mesh.radius = 0.12
	_cap_mesh.height = 0.42
	sync()

## Прогнать симуляцию вперёд (для кадров, чтобы завод уже работал).
func warm(secs: float) -> void:
	var t := 0.0
	while t < secs:
		net.step(0.05)
		t += 0.05
	net.events.clear()
	sync()

func _process(dt: float) -> void:
	_t += dt
	if running:
		net.step(minf(dt, 0.1))
	sync()

func sync() -> void:
	var sig := ""
	for c in net.parts:
		var p: Dictionary = net.parts[c]
		sig += "%d:%s:%d;" % [p.id, str(c), p.dir]
	if sig != _sig:
		_sig = sig
		_rebuild()
	_update_live()
	_update_label_focus()
	_update_caps()
	_update_flights()
	_play_events()

func _update_label_focus() -> void:
	if focus == null:
		return
	var near_id := -1
	var near_d := LABEL_R
	for id in _labels:
		var n: Node3D = _nodes.get(id)
		if n == null:
			continue
		var d := Vector2(n.global_position.x - focus.global_position.x, n.global_position.z - focus.global_position.z).length()
		if d < near_d:
			near_d = d
			near_id = id
	for id in _labels:
		var l: Label3D = _labels[id]
		l.visible = id == near_id
		# Одного размера на экране, как бы близко ни встала камера.
		l.fixed_size = true
		l.pixel_size = LABEL_PX

# ---------------------------------------------------------------- корпуса

func _rebuild() -> void:
	for n in _nodes.values():
		n.queue_free()
	_nodes.clear()
	_gauges.clear()
	_labels.clear()
	for c in net.parts:
		var part: Dictionary = net.parts[c]
		var n := build_part(part.kind, part.sub, part.dir, _links(c))
		n.position = ProtoPneumatics.cell_pos(origin, c)
		add_child(n)
		_nodes[part.id] = n
		# Робот не проходит сквозь детали: трубы низкие — на них можно наступить.
		ProtoMachines.add_box_collider(n)
		var g := n.find_child("gauge", true, false) as MeshInstance3D
		if g:
			_gauges[part.id] = g.material_override
		if part.kind != "pipe":
			var l := Label3D.new()
			l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			l.pixel_size = 0.006
			l.font_size = 40
			l.outline_size = 10
			l.modulate = Color(0.95, 0.97, 1.0)
			var model := n.get_node_or_null("model")
			var top: float = float(model.get_meta("h", 1.6)) * 0.85 + 0.9 if model != null else 2.2
			l.position = Vector3(0, {"tank": 2.7, "intake": 2.5, "pump": 1.9}.get(part.kind, top), 0)
			l.no_depth_test = true
			n.add_child(l)
			_labels[part.id] = l

## Стороны клетки (индексы DIRS), к которым подходят трубы: вперёд — если там
## деталь, назад — всегда у трубы и машины, с боков — если соседняя деталь
## смотрит сюда.
func _links(c: Vector2i) -> Array:
	var part: Dictionary = net.parts[c]
	var out: Array = []
	for i in 4:
		var nc: Vector2i = c + ProtoPneumatics.DIRS[i]
		var nb: Dictionary = net.parts.get(nc, {})
		if i == part.dir:
			if not nb.is_empty() or part.kind == "pipe":
				out.append(i)
			continue
		if nb.is_empty():
			if part.kind == "pipe" and i == (part.dir + 2) % 4:
				out.append(i)
			continue
		if nb.dir == (i + 2) % 4 and nb.kind != "pump":
			out.append(i)      # соседний выход смотрит в эту клетку
		elif part.kind == "pump" or nb.kind == "pump":
			out.append(i)      # насос подключается к соседям газом
	return out

## Корпус детали; links — стороны, куда вести патрубки. Работает и для призрака.
static func build_part(kind: String, sub: Substance, dir: int, links: Array, holo := false) -> Node3D:
	var body := ProtoMachines.hologram() if holo else ProtoMachines.surface(sub)
	var n := Node3D.new()
	n.name = kind
	var core: Node3D
	match kind:
		"pipe":
			core = Node3D.new()
			for i in links:
				_half_pipe(core, i, body, holo)
			var hub := MeshInstance3D.new()
			var s := SphereMesh.new()
			s.radius = PIPE_R * 1.25
			s.height = PIPE_R * 2.5
			hub.mesh = s
			hub.material_override = body
			hub.position = Vector3(0, PIPE_Y, 0)
			core.add_child(hub)
		"pump":
			core = ProtoMachines.pump(body)
			core.scale = Vector3(0.85, 0.85, 0.85)
		"intake":
			core = _intake_mesh(body)
		"crusher":
			core = _crusher_mesh(body)
		"furnace":
			core = ProtoMachines.furnace(body)
			core.scale = Vector3(0.8, 0.8, 0.8)
		"tank":
			core = ProtoMachines.tank(body, Color(0.2, 0.2, 0.22), 0.001)
			core.name = "tank_body"
		"lab":
			core = _lab_mesh(body)
		_:
			# Пушка и машины обработки 2D-игры — общие модели (MachineModels).
			core = GoalModels.build(kind, body, goal_style)
			core.scale = Vector3(0.85, 0.85, 0.85)
			core.name = "model"
	# Машины смотрят выходом по dir: модель строится выходом на +Z.
	if kind != "pipe":
		core.rotation.y = _yaw(dir)
		for i in links:
			_stub(n, i, body, holo)
	n.add_child(core)
	if kind in ["pipe", "pump"] and not holo:
		var g := MeshInstance3D.new()
		g.name = "gauge"
		var gs := SphereMesh.new()
		gs.radius = 0.07
		gs.height = 0.14
		g.mesh = gs
		g.material_override = ProtoMachines.glow(Color(0.3, 1.0, 0.4), 1.5)
		g.position = Vector3(0, PIPE_Y + PIPE_R + 0.08, 0) if kind == "pipe" else Vector3(0.3, 1.3, 0.3)
		n.add_child(g)
	if holo:
		_holo_all(n, body)
	return n

static func _yaw(dir: int) -> float:
	var d: Vector2i = ProtoPneumatics.DIRS[dir]
	return atan2(float(d.x), float(d.y))

## Полтрубы от центра клетки к стороне i: стекло с металлическими кольцами.
static func _half_pipe(parent: Node3D, i: int, body: Material, holo: bool) -> void:
	var d: Vector2i = ProtoPneumatics.DIRS[i]
	var dv := Vector3(d.x, 0, d.y)
	var half := ProtoPneumatics.CELL / 2.0
	var tube := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = PIPE_R
	cm.bottom_radius = PIPE_R
	cm.height = half
	cm.radial_segments = 14
	tube.mesh = cm
	tube.material_override = body if holo else ProtoMachines.glass()
	tube.position = Vector3(0, PIPE_Y, 0) + dv * half / 2.0
	tube.rotation = Vector3(PI / 2.0, _yaw(i), 0)
	parent.add_child(tube)
	for k in [0.35, 0.95]:
		var ring := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = PIPE_R * 0.95
		tm.outer_radius = PIPE_R * 1.3
		tm.rings = 12
		ring.mesh = tm
		ring.material_override = body
		ring.position = Vector3(0, PIPE_Y, 0) + dv * half * k
		ring.rotation = Vector3(PI / 2.0, _yaw(i), 0)
		parent.add_child(ring)
	# Опора под трубой у края клетки.
	var leg := MeshInstance3D.new()
	var lb := BoxMesh.new()
	lb.size = Vector3(0.08, PIPE_Y, 0.08)
	leg.mesh = lb
	leg.material_override = body
	leg.position = Vector3(0, PIPE_Y / 2.0, 0) + dv * half * 0.6
	parent.add_child(leg)

## Короткий патрубок машины к стороне i (металл, от корпуса до края клетки).
static func _stub(parent: Node3D, i: int, body: Material, _holo: bool) -> void:
	var d: Vector2i = ProtoPneumatics.DIRS[i]
	var dv := Vector3(d.x, 0, d.y)
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = PIPE_R * 1.05
	cm.bottom_radius = PIPE_R * 1.05
	cm.height = 0.45
	cm.radial_segments = 14
	mi.mesh = cm
	mi.material_override = body
	mi.position = Vector3(0, PIPE_Y, 0) + dv * (ProtoPneumatics.CELL / 2.0 - 0.22)
	mi.rotation = Vector3(PI / 2.0, _yaw(i), 0)
	parent.add_child(mi)

## Приёмник: воронка на ножках, внизу — патрубок.
static func _intake_mesh(body: Material) -> Node3D:
	var n := Node3D.new()
	var f := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.85
	cm.bottom_radius = 0.25
	cm.height = 0.8
	cm.radial_segments = 8
	f.mesh = cm
	f.material_override = body
	f.position = Vector3(0, 1.35, 0)
	n.add_child(f)
	var rim := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.8
	tm.outer_radius = 0.92
	tm.ring_segments = 8
	rim.mesh = tm
	rim.material_override = body
	rim.position = Vector3(0, 1.76, 0)
	n.add_child(rim)
	for a in 4:
		var ang := a * TAU / 4.0 + PI / 4.0
		var leg := MeshInstance3D.new()
		var lb := BoxMesh.new()
		lb.size = Vector3(0.1, 1.1, 0.1)
		leg.mesh = lb
		leg.material_override = body
		leg.position = Vector3(cos(ang) * 0.55, 0.55, sin(ang) * 0.55)
		n.add_child(leg)
	var neck := MeshInstance3D.new()
	var nm := CylinderMesh.new()
	nm.top_radius = 0.25
	nm.bottom_radius = 0.25
	nm.height = 0.45
	neck.mesh = nm
	neck.material_override = body
	neck.position = Vector3(0, 0.75, 0)
	n.add_child(neck)
	# Внутри воронки — горка груза (цвет задаётся на ходу).
	var heap := MeshInstance3D.new()
	heap.name = "heap"
	var hm := SphereMesh.new()
	hm.radius = 0.6
	hm.height = 0.5
	heap.mesh = hm
	heap.position = Vector3(0, 1.55, 0)
	heap.visible = false
	n.add_child(heap)
	return n

## Лаборатория: стол с пятью щупами (по одному на пробу) под стеклянным колпаком,
## в центре — вращающаяся чашка с образцом, сбоку табло.
static func _lab_mesh(body: Material) -> Node3D:
	var n := Node3D.new()
	var base := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.3, 0.7, 1.3)
	base.mesh = bm
	base.material_override = body
	base.position = Vector3(0, 0.35, 0)
	n.add_child(base)
	var dome := MeshInstance3D.new()
	var dm := SphereMesh.new()
	dm.radius = 0.55
	dm.height = 0.8
	dm.is_hemisphere = true
	dome.mesh = dm
	dome.material_override = ProtoMachines.glass()
	dome.position = Vector3(0, 0.7, 0)
	n.add_child(dome)
	var cup := Node3D.new()
	cup.name = "carousel"
	cup.position = Vector3(0, 0.78, 0)
	n.add_child(cup)
	var dish := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.22
	cm.bottom_radius = 0.14
	cm.height = 0.08
	dish.mesh = cm
	dish.material_override = body
	cup.add_child(dish)
	var sample := MeshInstance3D.new()
	sample.name = "sample"
	var sm := SphereMesh.new()
	sm.radius = 0.12
	sm.height = 0.16
	sm.radial_segments = 6
	sm.rings = 3
	sample.mesh = sm
	sample.position = Vector3(0, 0.08, 0)
	sample.visible = false
	cup.add_child(sample)
	# Пять щупов по кругу — цвета проб (нагрев, капля, магнит, ток, счётчик).
	var cols := [Color(1.0, 0.45, 0.15), Color(0.5, 0.95, 0.4), Color(0.45, 0.55, 1.0), Color(1.0, 0.95, 0.4), Color(0.4, 1.0, 0.8)]
	for i in 5:
		var a := i * TAU / 5.0
		var arm := MeshInstance3D.new()
		var am := CylinderMesh.new()
		am.top_radius = 0.025
		am.bottom_radius = 0.035
		am.height = 0.42
		arm.mesh = am
		arm.material_override = body
		arm.position = Vector3(cos(a) * 0.32, 0.9, sin(a) * 0.32)
		arm.rotation = Vector3(sin(a) * 0.6, 0, -cos(a) * 0.6)
		n.add_child(arm)
		var tip := MeshInstance3D.new()
		var tm := SphereMesh.new()
		tm.radius = 0.04
		tm.height = 0.08
		tip.mesh = tm
		tip.material_override = ProtoMachines.glow(cols[i], 1.2)
		tip.position = Vector3(cos(a) * 0.2, 0.74, sin(a) * 0.2)
		n.add_child(tip)
	var board := MeshInstance3D.new()
	board.name = "lamp"
	var pm := BoxMesh.new()
	pm.size = Vector3(0.5, 0.22, 0.04)
	board.mesh = pm
	board.material_override = ProtoMachines.glow(Color(0.3, 0.3, 0.3), 0.2)
	board.position = Vector3(0, 0.45, 0.67)
	n.add_child(board)
	return n

## Дробилка: корпус, приёмный бункер сверху, два вала с зубьями по бокам.
static func _crusher_mesh(body: Material) -> Node3D:
	var n := Node3D.new()
	var b := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.3, 1.0, 1.3)
	b.mesh = bm
	b.material_override = body
	b.position = Vector3(0, 0.5, 0)
	n.add_child(b)
	var hop := MeshInstance3D.new()
	var hm := CylinderMesh.new()
	hm.top_radius = 0.6
	hm.bottom_radius = 0.35
	hm.height = 0.45
	hm.radial_segments = 4
	hop.mesh = hm
	hop.material_override = body
	hop.position = Vector3(0, 1.22, 0)
	hop.rotation.y = PI / 4.0
	n.add_child(hop)
	for side in [-1.0, 1.0]:
		var rot := Node3D.new()
		rot.name = "roller"
		rot.position = Vector3(side * 0.72, 0.62, 0)
		n.add_child(rot)
		var r := MeshInstance3D.new()
		var rm := CylinderMesh.new()
		rm.top_radius = 0.28
		rm.bottom_radius = 0.28
		rm.height = 0.14
		rm.radial_segments = 10
		r.mesh = rm
		r.material_override = body
		r.rotation.z = PI / 2.0
		rot.add_child(r)
		for k in 6:
			var tooth := MeshInstance3D.new()
			var tb := BoxMesh.new()
			tb.size = Vector3(0.16, 0.12, 0.12)
			tooth.mesh = tb
			tooth.material_override = body
			var a := k * TAU / 6.0
			tooth.position = Vector3(0, cos(a) * 0.32, sin(a) * 0.32)
			tooth.rotation.x = -a
			rot.add_child(tooth)
	var lamp := MeshInstance3D.new()
	lamp.name = "lamp"
	var lm := SphereMesh.new()
	lm.radius = 0.07
	lm.height = 0.14
	lamp.mesh = lm
	lamp.material_override = ProtoMachines.glow(Color(0.3, 0.3, 0.3), 0.2)
	lamp.position = Vector3(0.45, 1.02, 0.45)
	n.add_child(lamp)
	return n

static func _holo_all(n: Node, mat: Material) -> void:
	for ch in n.get_children():
		if ch is MeshInstance3D:
			ch.material_override = mat
			ch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if ch is Light3D:
			ch.visible = false
		_holo_all(ch, mat)

# ---------------------------------------------------------------- живое

func _update_live() -> void:
	for c in net.parts:
		var part: Dictionary = net.parts[c]
		var n: Node3D = _nodes.get(part.id)
		if n == null:
			continue
		var p := net.pressure(c)
		if _gauges.has(part.id):
			var k := clampf((p - net.gas.atm_pressure) / maxf(0.1, part.stats.max_p - net.gas.atm_pressure), 0.0, 1.0)
			var col := Color(0.3, 1.0, 0.4).lerp(Color(1.0, 0.85, 0.2), minf(1.0, k * 1.6))
			if k > 0.8:
				col = col.lerp(Color(1.0, 0.15, 0.1), (k - 0.8) / 0.2)
			var gm: StandardMaterial3D = _gauges[part.id]
			gm.albedo_color = col
			gm.emission = col
		if _labels.has(part.id):
			_labels[part.id].text = "%s · %.1f атм\n%s" % [ProtoPneumatics.KINDS[part.kind].n, p, part.status]
		match part.kind:
			"crusher":
				var on: bool = part.busy != null
				for r in n.find_children("roller", "", true, false):
					if on:
						r.rotation.x += 0.12 * (1.0 if r.position.x < 0 else -1.0)
				var lamp := n.find_child("lamp", true, false) as MeshInstance3D
				var lc := Color(0.3, 1.0, 0.4) if on else Color(0.3, 0.3, 0.3)
				lamp.material_override.albedo_color = lc
				lamp.material_override.emission = lc
				lamp.material_override.emission_energy_multiplier = 2.5 if on else 0.2
			"pump":
				var piston := _find_mesh_at(n, 1.6)
				if piston:
					piston.position.y = 1.6 + (sin(_t * 9.0) * 0.12 if part.hot else 0.0)
			"furnace":
				for l in n.find_children("*", "OmniLight3D", true, false):
					l.light_energy = (1.8 + sin(_t * 13.0) * 0.3) if part.hot else 0.4
			"intake":
				var heap := n.find_child("heap", true, false) as MeshInstance3D
				var m := net.mass_in(c)
				heap.visible = m > 0.01
				if heap.visible:
					var it: Portion = part.items[0]
					heap.material_override = ProtoMachines.surface(it.substance) if heap.material_override == null or heap.get_meta("sub", "") != it.substance.id else heap.material_override
					heap.set_meta("sub", it.substance.id)
					heap.scale = Vector3.ONE * clampf(0.4 + m / 20.0, 0.4, 1.1)
			"tank":
				_tank_fill(n, part)
			"lab":
				var busy: bool = part.busy != null
				var car := n.find_child("carousel", true, false) as Node3D
				if car and busy:
					car.rotation.y += 0.05
				var smp := n.find_child("sample", true, false) as MeshInstance3D
				if smp:
					smp.visible = busy
					if busy and smp.get_meta("sub", "") != part.busy.substance.id:
						smp.material_override = ProtoMachines.surface(part.busy.substance)
						smp.set_meta("sub", part.busy.substance.id)
				var board := n.find_child("lamp", true, false) as MeshInstance3D
				if board:
					var flash: float = n.get_meta("flash", 0.0)
					var bc := Color(0.35, 0.9, 1.0) if flash > 0.0 else (Color(0.3, 1.0, 0.4) if busy else Color(0.3, 0.3, 0.3))
					board.material_override.albedo_color = bc
					board.material_override.emission = bc
					board.material_override.emission_energy_multiplier = 3.0 if flash > 0.0 else (1.5 if busy else 0.2)
					n.set_meta("flash", maxf(0.0, flash - 0.03))
			_:
				var model := n.get_node_or_null("model")
				if model == null:
					continue
				var on: bool = part.get("work", false)
				var lamp := model.get_node_or_null("lamp") as MeshInstance3D
				if lamp:
					lamp.material_override = MachineModels.mat("lamp_work" if on else ("lamp_starved" if part.items.is_empty() and part.kind != "cannon" else "lamp_idle"))
				var spin := model.find_child("spin", true, false) as Node3D
				if spin and on:
					spin.rotation.y += 0.15

## Уровень груза в баке: цилиндр внутри стекла, цвет — материал.
func _tank_fill(n: Node3D, part: Dictionary) -> void:
	var fill := n.find_child("fill", true, false) as MeshInstance3D
	if fill == null:
		fill = MeshInstance3D.new()
		fill.name = "fill"
		var cm := CylinderMesh.new()
		cm.top_radius = 0.64
		cm.bottom_radius = 0.64
		cm.height = 1.0
		fill.mesh = cm
		n.add_child(fill)
	var m := net.mass_in(part.cell)
	var lv := clampf(m / ProtoPneumatics.KINDS.tank.cap, 0.0, 1.0)
	fill.visible = lv > 0.005
	if fill.visible:
		var it: Portion = part.items[-1]
		if fill.get_meta("sub", "") != it.substance.id:
			fill.material_override = ProtoMachines.surface(it.substance)
			fill.set_meta("sub", it.substance.id)
		fill.scale = Vector3(1, 1.1 * lv, 1)
		fill.position = Vector3(0, 0.45 + 1.1 * lv / 2.0, 0)

static func _find_mesh_at(n: Node, y: float) -> MeshInstance3D:
	for ch in n.get_children():
		if ch is MeshInstance3D and absf(ch.position.y - y) < 0.2 and ch.mesh is CylinderMesh and ch.mesh.height < 0.7:
			return ch
		var r := _find_mesh_at(ch, y)
		if r:
			return r
	return null

## Капсулы: от входной стороны клетки к центру и дальше к выходной.
func _update_caps() -> void:
	var caps := net.capsules()
	while _caps.size() < caps.size():
		var mi := MeshInstance3D.new()
		mi.mesh = _cap_mesh
		add_child(mi)
		_caps.append(mi)
	for i in _caps.size():
		var mi: MeshInstance3D = _caps[i]
		mi.visible = i < caps.size()
		if not mi.visible:
			continue
		var cap: Dictionary = caps[i]
		var part: Dictionary = net.parts[cap.cell]
		var ctr := ProtoPneumatics.cell_pos(origin, cap.cell) + Vector3(0, PIPE_Y, 0)
		var half := ProtoPneumatics.CELL / 2.0
		var fd: Vector2i = cap.from - cap.cell
		var od: Vector2i = ProtoPneumatics.DIRS[part.dir]
		var a := ctr + Vector3(fd.x, 0, fd.y) * half
		var b := ctr + Vector3(od.x, 0, od.y) * half
		var t: float = cap.t
		var pos: Vector3 = a.lerp(ctr, t * 2.0) if t < 0.5 else ctr.lerp(b, (t - 0.5) * 2.0)
		mi.position = pos
		var dirv: Vector3 = (ctr - a) if t < 0.5 else (b - ctr)
		if dirv.length() > 0.01:
			mi.rotation = Vector3(PI / 2.0, atan2(dirv.x, dirv.z), 0)
		var sid: String = cap.p.substance.id
		if mi.get_meta("sub", "") != sid:
			mi.material_override = ProtoMachines.glow(cap.p.substance.color, 1.4)
			mi.set_meta("sub", sid)

## Капсулы пушек: дуга от пушки к приёмнику (высота — треть дальности).
func _update_flights() -> void:
	var fl: Array = net.flights
	while _flights.size() < fl.size():
		var mi := MeshInstance3D.new()
		mi.mesh = _cap_mesh
		mi.scale = Vector3.ONE * 1.4
		add_child(mi)
		_flights.append(mi)
	for i in _flights.size():
		var mi: MeshInstance3D = _flights[i]
		mi.visible = i < fl.size()
		if not mi.visible:
			continue
		var f: Dictionary = fl[i]
		var k: float = clampf(f.t / f.dur, 0.0, 1.0)
		var a := ProtoPneumatics.cell_pos(origin, f.from) + Vector3(0, 1.6, 0)
		var b := ProtoPneumatics.cell_pos(origin, f.to) + Vector3(0, 1.3, 0)
		var h := a.distance_to(b) * 0.35
		mi.position = a.lerp(b, k) + Vector3(0, sin(PI * k) * h, 0)
		var v := (b - a) + Vector3(0, cos(PI * k) * PI * h, 0)
		mi.rotation = Vector3(PI / 2.0 - atan2(v.y, Vector2(v.x, v.z).length()), atan2(v.x, v.z), 0)
		var sid: String = f.p.substance.id
		if mi.get_meta("sub", "") != sid:
			mi.material_override = ProtoMachines.glow(f.p.substance.color, 1.4)
			mi.set_meta("sub", sid)

func _play_events() -> void:
	for e in net.events:
		match e.kind:
			"burst":
				_puff(ProtoPneumatics.cell_pos(origin, e.cell) + Vector3(0, PIPE_Y, 0), Color(0.9, 0.95, 1.0), 60)
			"lost":
				var d: Vector2i = ProtoPneumatics.DIRS[e.dir]
				_puff(ProtoPneumatics.cell_pos(origin, e.cell) + Vector3(d.x, PIPE_Y, d.y), e.sub.color, 14)
			"done", "caught":
				_puff(ProtoPneumatics.cell_pos(origin, e.cell) + Vector3(0, 1.2, 0), e.sub.color, 10)
			"lab":
				if e.learned:
					_puff(ProtoPneumatics.cell_pos(origin, e.cell) + Vector3(0, 1.3, 0), Color(0.35, 0.9, 1.0), 24)
					var ln: Node3D = _nodes.get(net.parts.get(e.cell, {}).get("id", -1))
					if ln:
						ln.set_meta("flash", 1.0)
			"launch":
				_launch(ProtoPneumatics.cell_pos(origin, e.cell), e.sub.color)
			"shot":
				var sd: Vector2i = ProtoPneumatics.DIRS[e.dir]
				_puff(ProtoPneumatics.cell_pos(origin, e.cell) + Vector3(sd.x * 1.1, 1.8, sd.y * 1.1), Color(0.9, 0.95, 1.0), 24)
	net.events.clear()

## Старт пусковой шахты: клуб газа и капсула, уходящая в небо.
func _launch(at: Vector3, col: Color) -> void:
	_puff(at + Vector3(0, 0.9, 0), Color(0.9, 0.95, 1.0), 80)
	var mi := MeshInstance3D.new()
	mi.mesh = _cap_mesh
	mi.scale = Vector3.ONE * 2.2
	mi.material_override = ProtoMachines.glow(col, 2.0)
	mi.position = at + Vector3(0, 1.6, 0)
	add_child(mi)
	var tw := mi.create_tween()
	tw.tween_property(mi, "position:y", at.y + 60.0, 2.5).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tw.tween_callback(mi.queue_free)

func _puff(at: Vector3, col: Color, amount: int) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.emitting = true
	p.amount = amount
	p.lifetime = 0.9
	p.explosiveness = 0.9
	p.direction = Vector3.UP
	p.spread = 70.0
	p.initial_velocity_min = 1.0
	p.initial_velocity_max = 3.0
	p.gravity = Vector3(0, -2.0, 0)
	var s := SphereMesh.new()
	s.radius = 0.05
	s.height = 0.1
	p.mesh = s
	p.material_override = ProtoMachines.glow(col, 1.0)
	p.position = at
	add_child(p)
	get_tree().create_timer(1.5).timeout.connect(p.queue_free)

# ---------------------------------------------------------------- призрак

## Показать призрак детали в клетке (kind == "" — спрятать). ok — можно ставить.
func ghost(kind: String, c: Vector2i, dir: int, sub: Substance, ok: bool) -> void:
	var key := "%s:%d:%s:%s" % [kind, dir, sub.id if sub else "", ok]
	if key != _ghost_key:
		_ghost_key = key
		if _ghost:
			_ghost.queue_free()
			_ghost = null
		if kind != "":
			var links: Array = [dir, (dir + 2) % 4] if kind == "pipe" else [dir]
			_ghost = build_part(kind, sub, dir, links, true)
			var gm := StandardMaterial3D.new()
			gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			gm.albedo_color = Color(0.35, 0.9, 1.0, 0.4) if ok else Color(1.0, 0.25, 0.15, 0.45)
			_holo_all(_ghost, gm)
			add_child(_ghost)
	if _ghost:
		_ghost.position = ProtoPneumatics.cell_pos(origin, c)
