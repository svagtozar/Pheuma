class_name ProtoPneumaticsView
extends Node3D
## 3D-вид пневмозавода (ProtoPneumatics): корпуса деталей из материала, стеклянные
## трубы с капсулами груза внутри, манометры (зелёный → красный к пределу
## материала), подписи машин, разрывы. Сам шагает симуляцию в _process.
## ghost() — полупрозрачная деталь-призрак для режима стройки.

const PIPE_Y := 0.55
const PIPE_R := 0.16
## Масштаб моделей машин в клетке завода.
const MODEL_SCALE := 0.9

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
var _batch: Array = []    # общие склеенные сетки неподвижных частей всех деталей
var _sig := ""            # отпечаток расстановки: при смене трубы перестраиваются
var _caps: Array = []     # MeshInstance3D капсул (пул)
var _cap_mesh: CapsuleMesh
var _gauges := {}         # id → StandardMaterial3D манометра
var _labels := {}         # id → Label3D
var _ghost: Node3D
var _ghost_key := ""
var _t := 0.0
var _dt := 0.0
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
	_dt = dt
	if running:
		net.step(minf(dt, 0.1))
	sync()

func sync() -> void:
	var sig := ""
	for c in net.parts:
		var p: Dictionary = net.parts[c]
		sig += "%d:%s:%d:%.2f;" % [p.id, str(c), p.dir, float(p.get("lift", 0.0))]
	if sig != _sig:
		_sig = sig
		_rebuild()
	_update_live(_dt)
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
	for n in _nodes.values() + _batch:
		n.queue_free()
	_nodes.clear()
	_batch.clear()
	_gauges.clear()
	_labels.clear()
	for c in net.parts:
		var part: Dictionary = net.parts[c]
		var n := build_part(part.kind, part.sub, part.dir, _links(c), false, _rises(c))
		n.position = net.at(origin, c)
		add_child(n)
		_nodes[part.id] = n
		# Робот не проходит сквозь детали: трубы низкие — на них можно наступить.
		ProtoMachines.add_box_collider(n)
		_foundation(n, float(part.get("foot", 0.0)))
		var g := n.find_child("gauge", true, false) as MeshInstance3D
		if g:
			_gauges[part.id] = g.material_override
		if part.kind != "pipe" and part.kind != "lamp":
			var l := Label3D.new()
			l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			l.pixel_size = 0.006
			l.font_size = 40
			l.outline_size = 10
			l.modulate = Color(0.95, 0.97, 1.0)
			var model := n.get_node_or_null("model")
			var top: float = float(model.get_meta("h", 1.6)) * MODEL_SCALE + 0.7 if model != null else 2.2
			l.position = Vector3(0, top, 0)
			l.no_depth_test = true
			n.add_child(l)
			_labels[part.id] = l
	# Неподвижные части всех деталей — общими сетками по материалу (ProtoBatch):
	# лампы, ролики, поршень, карусель и прочие живые части названы и остаются
	# в своих узлах. Коллайдеры уже посчитаны по полным моделям.
	var kids := get_child_count()
	for n in _nodes.values():
		ProtoBatch.merge_children(n)
	ProtoBatch.merge_static(self, _nodes.values(), ["model"])
	for i in range(kids, get_child_count()):
		_batch.append(get_child(i))

## Фундамент под деталью за площадкой: плита до самого низкого места клетки,
## чтобы деталь на склоне не висела над грунтом. Отдельный коллайдер — плита
## шире детали, на неё можно встать.
static var _concrete: StandardMaterial3D

func _foundation(n: Node3D, foot: float) -> void:
	if foot < 0.12:
		return
	var h := foot + 0.3
	var mi := MeshInstance3D.new()
	mi.name = "foundation"
	var bm := BoxMesh.new()
	bm.size = Vector3(ProtoPneumatics.CELL - 0.1, h, ProtoPneumatics.CELL - 0.1)
	mi.mesh = bm
	if _concrete == null:
		_concrete = StandardMaterial3D.new()
		_concrete.albedo_color = Color(0.4, 0.4, 0.42)   # как плита площадки
		_concrete.roughness = 0.9
	mi.material_override = _concrete
	mi.position = Vector3(0, -h / 2.0 + 0.02, 0)
	n.add_child(mi)
	ProtoMachines.add_box_collider(mi, ProtoMachines.LAYER_GROUND)

## Разница высот к соседям по сторонам (полразницы — трубы встречаются
## посередине): [dy0, dy1, dy2, dy3].
func _rises(c: Vector2i) -> Array:
	var out: Array = [0.0, 0.0, 0.0, 0.0]
	var own := net.lift(c)
	for i in 4:
		var nc: Vector2i = c + ProtoPneumatics.DIRS[i]
		if net.parts.has(nc):
			out[i] = (net.lift(nc) - own) / 2.0
	return out

## Середина стороны d клетки c, где стыкуются трубы (на высоте труб).
func edge(c: Vector2i, d: Vector2i) -> Vector3:
	var half := ProtoPneumatics.CELL / 2.0
	var y := net.lift(c)
	if net.parts.has(c + d):
		y = (y + net.lift(c + d)) / 2.0
	return ProtoPneumatics.cell_pos(origin, c) + Vector3(d.x * half, y + PIPE_Y, d.y * half)

## Стороны клетки (индексы DIRS), к которым подходят трубы: вперёд — если там
## деталь, назад — всегда у трубы и машины, с боков — если соседняя деталь
## смотрит сюда.
func _links(c: Vector2i) -> Array:
	var part: Dictionary = net.parts[c]
	var out: Array = []
	for i in 4:
		var nc: Vector2i = c + ProtoPneumatics.DIRS[i]
		var nb: Dictionary = net.parts.get(nc, {})
		if part.kind == "lamp" or (not nb.is_empty() and nb.kind == "lamp"):
			continue                              # фонарь к линии не подключён
		if part.kind in ["splitter", "sorter"]:
			# Выходы во все стороны, где есть сосед; вход сзади — всегда.
			if not nb.is_empty() or i == (part.dir + 2) % 4:
				out.append(i)
			continue
		if part.kind == "relief" and (i == part.dir or i == (part.dir + 2) % 4):
			out.append(i)
			continue
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

## Общие на все детали материалы корпуса (по веществу) и стекла (null):
## одинаковые части разных машин склеиваются в одну сетку. Их никто не
## перекрашивает — живые части берут свои материалы.
static var _mats := {}

static func _shared(sub: Substance) -> Material:
	if not _mats.has(sub):
		_mats[sub] = ProtoMachines.surface(sub) if sub != null else ProtoMachines.glass()
	return _mats[sub]

## Корпус детали; links — стороны, куда вести патрубки. Работает и для призрака.
## rises — подъём к соседу по сторонам (см. _rises): трубы и патрубки
## наклоняются к стыку.
static func build_part(kind: String, sub: Substance, dir: int, links: Array, holo := false, rises: Array = [0.0, 0.0, 0.0, 0.0]) -> Node3D:
	var body := ProtoMachines.hologram() if holo else _shared(sub)
	var n := Node3D.new()
	n.name = kind
	var core: Node3D
	if kind == "pipe":
		core = Node3D.new()
		for i in links:
			_half_pipe(core, i, body, holo, rises[i])
		var hub := MeshInstance3D.new()
		var s := SphereMesh.new()
		s.radius = PIPE_R * 1.25
		s.height = PIPE_R * 2.5
		hub.mesh = s
		hub.material_override = body if holo else MachineKit.m("frame")
		hub.position = Vector3(0, PIPE_Y, 0)
		core.add_child(hub)
	else:
		# Все машины — общие модели (MachineModels в наборе MachineKit;
		# сооружения целей — в облике goal_style).
		core = GoalModels.build(kind, body, goal_style)
		core.scale = Vector3.ONE * MODEL_SCALE
		core.name = "model"
		if kind == "furnace" and not holo:
			var light := OmniLight3D.new()
			light.light_color = Color(1.0, 0.5, 0.2)
			light.light_energy = 1.5
			light.omni_range = 3.0
			light.position = Vector3(0, 0.9, 1.3)
			core.add_child(light)
			MachineKit.anim(light, "flicker", {"energy": 1.8})
	# Машины смотрят выходом по dir: модель строится выходом на +Z.
	if kind != "pipe":
		core.rotation.y = _yaw(dir)
		for i in links:
			_stub(n, i, body, holo, rises[i])
	n.add_child(core)
	if kind == "pipe" and not holo:
		var g := MeshInstance3D.new()
		g.name = "gauge"
		var gs := SphereMesh.new()
		gs.radius = 0.07
		gs.height = 0.14
		g.mesh = gs
		g.material_override = ProtoMachines.glow(Color(0.3, 1.0, 0.4), 1.5)
		g.position = Vector3(0, PIPE_Y + PIPE_R + 0.08, 0)
		n.add_child(g)
	if holo:
		_holo_all(n, body)
	return n

static func _yaw(dir: int) -> float:
	var d: Vector2i = ProtoPneumatics.DIRS[dir]
	return atan2(float(d.x), float(d.y))

## Полтрубы от центра клетки к стороне i: стекло с металлическими кольцами.
static func _half_pipe(parent: Node3D, i: int, body: Material, holo: bool, rise := 0.0) -> void:
	var d: Vector2i = ProtoPneumatics.DIRS[i]
	var dv := Vector3(d.x, 0, d.y)
	var half := ProtoPneumatics.CELL / 2.0
	var a := Vector3(0, PIPE_Y, 0)
	var b := a + dv * half + Vector3(0, rise, 0)
	var tube := _segment(a, b, PIPE_R, body if holo else _shared(null))
	parent.add_child(tube)
	for k in [0.35, 0.95]:
		var ring := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = PIPE_R * 0.95
		tm.outer_radius = PIPE_R * 1.3
		tm.rings = 12
		ring.mesh = tm
		ring.material_override = body if holo else MachineKit.m("frame")
		ring.transform = Transform3D(tube.transform.basis, a.lerp(b, k))
		parent.add_child(ring)
	# Опора под трубой у края клетки.
	var leg := MeshInstance3D.new()
	var lb := BoxMesh.new()
	lb.size = Vector3(0.08, PIPE_Y, 0.08)
	leg.mesh = lb
	leg.material_override = body if holo else MachineKit.m("frame")
	leg.position = Vector3(0, PIPE_Y / 2.0, 0) + dv * half * 0.6
	parent.add_child(leg)

## Короткий патрубок машины к стороне i (металл, от корпуса до края клетки).
static func _stub(parent: Node3D, i: int, body: Material, holo: bool, rise := 0.0) -> void:
	var d: Vector2i = ProtoPneumatics.DIRS[i]
	var dv := Vector3(d.x, 0, d.y)
	var edge := Vector3(0, PIPE_Y, 0) + dv * (ProtoPneumatics.CELL / 2.0)
	parent.add_child(_segment(edge - dv * 0.45, edge + Vector3(0, rise, 0), PIPE_R * 1.05, body if holo else MachineKit.m("metal")))

## Цилиндр от a до b (ось Y цилиндра — вдоль отрезка).
static func _segment(a: Vector3, b: Vector3, r: float, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = a.distance_to(b)
	cm.radial_segments = 14
	mi.mesh = cm
	mi.material_override = mat
	var up := (b - a).normalized()
	var side := up.cross(Vector3.UP)
	if side.length() < 0.01:
		side = Vector3.RIGHT
	side = side.normalized()
	mi.transform = Transform3D(Basis(side, up, side.cross(up)), (a + b) / 2.0)
	return mi

static func _holo_all(n: Node, mat: Material) -> void:
	for ch in n.get_children():
		if ch is MeshInstance3D:
			ch.material_override = mat
			ch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if ch is Light3D:
			ch.visible = false
		_holo_all(ch, mat)

# ---------------------------------------------------------------- живое

func _update_live(dt: float) -> void:
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
		# Движения за работой (MachineKit.anim): валы, поршень, маховик, дым, пламя.
		var model := n.get_node_or_null("model") as Node3D
		if model != null:
			MachineKit.animate(model, _working(part), _t, dt)
		match part.kind:
			"crusher":
				var lamp := n.find_child("lamp", true, false) as MeshInstance3D
				lamp.material_override = MachineModels.mat("lamp_work" if part.busy != null else "lamp_idle")
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
			"buffer":
				var fill := n.find_child("fill", true, false) as Node3D
				var k := float(part.items.size()) / ProtoPneumatics.BUFFER_N
				fill.visible = k > 0.0
				if fill.visible:
					var fm := fill.get_node("fill_mesh") as MeshInstance3D
					var sub: Substance = part.items[-1].substance
					if fm.get_meta("sub", "") != sub.id:
						fm.material_override = ProtoMachines.surface(sub)
						fm.set_meta("sub", sub.id)
					fill.scale = Vector3(1, maxf(0.001, k * float(fill.get_meta("h", 1.0))), 1)
			"sorter":
				var f := n.find_child("filter", true, false) as MeshInstance3D
				var fs = part.get("filter")
				var fid: String = fs.id if fs != null else ""
				if f and f.get_meta("sub", "?") != fid:
					f.material_override = ProtoMachines.glow(fs.color, 2.0) if fs != null else MachineModels.mat("lamp_idle")
					f.set_meta("sub", fid)
			"lab":
				var busy: bool = part.busy != null
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
				if model == null:
					continue
				var on: bool = part.get("work", false)
				var lamp := model.get_node_or_null("lamp") as MeshInstance3D
				if lamp:
					lamp.material_override = MachineModels.mat("lamp_work" if on else ("lamp_starved" if part.items.is_empty() and part.kind != "cannon" else "lamp_idle"))
				var plume := model.find_child("plume", true, false) as CPUParticles3D
				if plume:
					plume.emitting = on

## Деталь сейчас работает (для движений MachineKit.animate).
func _working(part: Dictionary) -> bool:
	match part.kind:
		"pump", "furnace": return part.hot
		"crusher", "lab": return part.busy != null
		"intake": return not part.items.is_empty()
	return part.get("work", false)

## Уровень груза в баке: узел "fill" модели (MachineModels._fill) — масштаб
## по Y до доли груза, цвет — материал.
func _tank_fill(n: Node3D, part: Dictionary) -> void:
	var fill := n.find_child("fill", true, false) as Node3D
	if fill == null:
		return
	var lv := clampf(net.mass_in(part.cell) / ProtoPneumatics.KINDS.tank.cap, 0.0, 1.0)
	fill.visible = lv > 0.005
	if fill.visible:
		var it: Portion = part.items[-1]
		var fm := fill.get_node("fill_mesh") as MeshInstance3D
		if fm.get_meta("sub", "") != it.substance.id:
			fm.material_override = ProtoMachines.surface(it.substance)
			fm.set_meta("sub", it.substance.id)
		fill.scale = Vector3(1, maxf(0.001, lv * float(fill.get_meta("h", 1.0))), 1)

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
		var ctr := net.at(origin, cap.cell) + Vector3(0, PIPE_Y, 0)
		var a := edge(cap.cell, cap.from - cap.cell)
		var b := edge(cap.cell, ProtoPneumatics.DIRS[int(cap.get("out", part.dir))])
		var t: float = cap.t
		var pos: Vector3 = a.lerp(ctr, t * 2.0) if t < 0.5 else ctr.lerp(b, (t - 0.5) * 2.0)
		mi.position = pos
		var dirv: Vector3 = (ctr - a) if t < 0.5 else (b - ctr)
		if dirv.length() > 0.01:
			mi.rotation = Vector3(PI / 2.0 - atan2(dirv.y, Vector2(dirv.x, dirv.z).length()), atan2(dirv.x, dirv.z), 0)
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
		var a := net.at(origin, f.from) + Vector3(0, 1.6, 0)
		var b := net.at(origin, f.to) + Vector3(0, 1.3, 0)
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
				_puff(_ev_at(e) + Vector3(0, PIPE_Y, 0), Color(0.9, 0.95, 1.0), 60)
			"lost":
				var d: Vector2i = ProtoPneumatics.DIRS[e.dir]
				_puff(_ev_at(e) + Vector3(d.x, PIPE_Y, d.y), e.sub.color, 14)
			"done", "caught":
				_puff(_ev_at(e) + Vector3(0, 1.2, 0), e.sub.color, 10)
			"lab":
				if e.learned:
					_puff(_ev_at(e) + Vector3(0, 1.3, 0), Color(0.35, 0.9, 1.0), 24)
					var ln: Node3D = _nodes.get(net.parts.get(e.cell, {}).get("id", -1))
					if ln:
						ln.set_meta("flash", 1.0)
			"launch":
				_launch(net.at(origin, e.cell), e.sub.color)
			"shot":
				var sd: Vector2i = ProtoPneumatics.DIRS[e.dir]
				_puff(_ev_at(e) + Vector3(sd.x * 1.1, 1.8, sd.y * 1.1), Color(0.9, 0.95, 1.0), 24)
	net.events.clear()

## Стрелка выхода под призраком: куда деталь отдаёт капсулы.
static func _arrow(dir: int, mat: Material) -> Node3D:
	var a := Node3D.new()
	a.name = "arrow"
	a.rotation.y = _yaw(dir)
	var shaft := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.12, 0.04, 0.6)
	shaft.mesh = bm
	shaft.material_override = mat
	shaft.position = Vector3(0, 0.06, 0.55)
	a.add_child(shaft)
	var head := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.0
	cm.bottom_radius = 0.26
	cm.height = 0.36
	cm.radial_segments = 3
	head.mesh = cm
	head.material_override = mat
	head.position = Vector3(0, 0.06, 1.0)
	head.rotation = Vector3(PI / 2.0, 0, 0)
	a.add_child(head)
	return a

## Где случилось событие: лопнувшей детали уже нет — её подъём в событии.
func _ev_at(e: Dictionary) -> Vector3:
	return ProtoPneumatics.cell_pos(origin, e.cell) + Vector3(0, float(e.get("lift", net.lift(e.cell))), 0)

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
## lift — подъём над площадкой (грунт клетки за ней, см. ProtoBuilder.ground).
func ghost(kind: String, c: Vector2i, dir: int, sub: Substance, ok: bool, lift := 0.0) -> void:
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
			_ghost.add_child(_arrow(dir, gm))
			add_child(_ghost)
	if _ghost:
		_ghost.position = ProtoPneumatics.cell_pos(origin, c) + Vector3(0, lift, 0)
