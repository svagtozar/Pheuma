class_name MachineModels
extends RefCounted
## Объёмные модели всех машин 2D-игры (Buildings.KINDS) — у каждой свой силуэт,
## чтобы с камеры было понятно, что где стоит. Облик — индустриальный набор
## MachineKit: у машин 3D-завода там же своя модель, остальные силуэты отсюда
## строятся краской назначения и одеваются в набор (MachineKit.dress: основание
## из материала планеты, рама, скосы, панели). Начало координат — центр клетки
## на земле, выход машины смотрит в +Z.
##
## Живые части модель отдаёт по именам детей, их двигает вид:
##   "spin"  — Node3D, крутится вокруг своей оси Y, пока машина работает;
##   "lamp"  — MeshInstance3D, лампа состояния (цвет задаёт вид);
##   "fill"  — MeshInstance3D, груз внутри (масштаб по Y — доля заполнения).
## Высота корпуса — meta "h" (над ней вид ставит порцию и подписи).

const OUT_KINDS_NONE := ["pipe", "catch_net", "fabricator", "launch_silo", "macro", "sensor",
	"gate_and", "gate_or", "gate_not", "dome", "beacon"]
## Без основания-салазок: мелочь, которая стоит прямо на земле.
const NO_BASE := ["pipe", "sensor", "gate_and", "gate_or", "gate_not"]

static var _mats := {}

## Модель машины вида kind. body — материал постройки (основание и панели).
static func build(kind: String, body: Material) -> Node3D:
	var n := Node3D.new()
	if MachineKit.has_model(kind):
		n.set_meta("h", MachineKit.build_into(n, kind, body))
		return n
	var pnt := MachineKit.paint(MachineKit.cat_of(kind))
	var y0 := 0.0 if kind in NO_BASE else MachineKit.base(n, body)
	var first := n.get_child_count()
	var h := 1.2
	match kind:
		"drill": h = _drill(n, pnt)
		"container": h = _container(n, pnt)
		"receiver": h = _receiver(n, pnt)
		"fabricator": h = _fabricator(n, pnt)
		"pipe": h = _pipe_hub(n, pnt)
		"valve": h = _valve(n, pnt)
		"cannon": h = _cannon(n, pnt)
		"filter": h = _filter(n, pnt)
		"condenser": h = _condenser(n, pnt)
		"treater": h = _treater(n, pnt)
		"compressor": h = _compressor(n, pnt, false)
		"decompressor": h = _compressor(n, pnt, true)
		"distiller": h = _distiller(n, pnt)
		"magnet_sep": h = _magnet(n, pnt)
		"electrolyzer": h = _electrolyzer(n, pnt)
		"sinter": h = _sinter(n, pnt)
		"irradiator": h = _irradiator(n, pnt)
		"cryochamber": h = _cryo(n, pnt)
		"resonator": h = _resonator(n, pnt)
		"loom": h = _loom(n, pnt)
		"sensor": h = _sensor(n, pnt)
		"gate_and", "gate_or", "gate_not": h = _gate(n, pnt, kind)
		"battery_section": h = _battery(n, pnt)
		"catch_net": h = _net(n, pnt)
		"warehouse_section": h = _warehouse(n, pnt)
		"macro": h = _macro(n, pnt)
		"launch_silo": h = _silo(n, pnt)
		"dome": h = _dome(n, pnt)
		"beacon": h = _beacon(n, pnt)
		_:
			_box(n, Vector3(1.6, 1.0, 1.6), pnt, Vector3(0, 0.5, 0))
			h = 1.0
	MachineKit.dress(n, first, y0, pnt, body)
	h += y0
	if not kind in OUT_KINDS_NONE:
		MachineKit.outlet(n, Vector3(0, y0 + 0.25, 0.84))
	if kind != "pipe":
		MachineKit.lamp(n, Vector3(-0.62, h + 0.05, -0.62))
	n.set_meta("h", h)
	return n

## Второй выход (у процессов на два выхода) — в сторону dir_local.
static func add_outlet(n: Node3D, dir_local: Vector3) -> void:
	var d := dir_local.normalized()
	var o := MachineKit.outlet(n, Vector3(d.x * 0.84, MachineKit.BASE_H + 0.25, d.z * 0.84), mat("out2"))
	o.rotation.y = atan2(d.x, d.z)

## Общие материалы видов (лампы, стекло, свечение) — по одному на всё.
static func mat(id: String) -> Material:
	if _mats.has(id):
		return _mats[id]
	var m: Material
	match id:
		"lamp_idle": m = _flat(Color(0.35, 0.35, 0.38))
		"lamp_work": m = ProtoMachines.glow(Color(0.35, 1.0, 0.45), 3.0)
		"lamp_off": m = ProtoMachines.glow(Color(1.0, 0.2, 0.15), 3.0)
		"lamp_sig": m = ProtoMachines.glow(Color(1.0, 0.85, 0.2), 3.0)
		"lamp_starved": m = ProtoMachines.glow(Color(1.0, 0.7, 0.2), 1.5)
		"stripe": m = ProtoMachines.glow(Color(0.9, 0.42, 0.1), 0.25)
		"out": m = ProtoMachines.glow(Color(0.9, 0.95, 1.0), 0.8)
		"out2": m = ProtoMachines.glow(Color(0.55, 0.8, 1.0), 0.8)
		"glass": m = ProtoMachines.glass()
		"dark": m = _flat(Color(0.12, 0.12, 0.14))
		"rubber": m = _flat(Color(0.18, 0.17, 0.16))
		"hot": m = ProtoMachines.glow(Color(1.0, 0.45, 0.1), 4.0)
		"cold": m = ProtoMachines.glow(Color(0.55, 0.85, 1.0), 1.6)
		"blue": m = ProtoMachines.glow(Color(0.3, 0.6, 1.0), 2.0)
		"violet": m = ProtoMachines.glow(Color(0.8, 0.4, 1.0), 2.5)
		"green": m = ProtoMachines.glow(Color(0.5, 1.0, 0.3), 2.2)
		"cyan": m = ProtoMachines.glow(Color(0.5, 0.85, 1.0), 2.0)
		"yellow": m = ProtoMachines.glow(Color(1.0, 0.85, 0.25), 1.2)
		"magnet": m = _flat(Color(0.75, 0.15, 0.12), 0.4, 0.6)
		"thread": m = _flat(Color(0.9, 0.85, 0.7))
		"net": m = _flat(Color(0.8, 0.78, 0.7))
		_: m = _flat(Color.MAGENTA)
	_mats[id] = m
	return m

static func _flat(c: Color, rough := 0.8, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m

# ---------------------------------------------------------------- примитивы

static func _add(parent: Node3D, mesh: Mesh, m: Material, pos: Vector3, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi

static func _box(parent: Node3D, size: Vector3, m: Material, pos: Vector3, rot := Vector3.ZERO) -> MeshInstance3D:
	var b := BoxMesh.new()
	b.size = size
	return _add(parent, b, m, pos, rot)

static func _cyl(parent: Node3D, r: float, h: float, m: Material, pos: Vector3, top := -1.0, rot := Vector3.ZERO, seg := 16) -> MeshInstance3D:
	var c := CylinderMesh.new()
	c.top_radius = r if top < 0.0 else top
	c.bottom_radius = r
	c.height = h
	c.radial_segments = seg
	c.rings = 1
	return _add(parent, c, m, pos, rot)

static func _sph(parent: Node3D, r: float, m: Material, pos: Vector3, hemi := false) -> MeshInstance3D:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r if hemi else r * 2.0
	s.is_hemisphere = hemi
	s.radial_segments = 16
	s.rings = 8
	return _add(parent, s, m, pos)

static func _ring(parent: Node3D, r: float, w: float, m: Material, pos: Vector3, rot := Vector3.ZERO) -> MeshInstance3D:
	var t := TorusMesh.new()
	t.inner_radius = r - w
	t.outer_radius = r + w
	t.rings = 24
	t.ring_segments = 8
	return _add(parent, t, m, pos, rot)

static func _spin(parent: Node3D, pos: Vector3) -> Node3D:
	var s := Node3D.new()
	s.name = "spin"
	s.position = pos
	parent.add_child(s)
	return s

static func _fill(parent: Node3D, r: float, h: float, y0: float) -> MeshInstance3D:
	# Цилиндр высотой 1 с низом в y0: вид масштабирует его по Y до доли груза.
	var holder := Node3D.new()
	holder.position = Vector3(0, y0, 0)
	parent.add_child(holder)
	var mi := _cyl(holder, r, 1.0, _flat(Color(0.3, 0.3, 0.35)), Vector3(0, 0.5, 0))
	holder.name = "fill"
	holder.scale = Vector3(1, 0.001, 1)
	holder.set_meta("h", h)
	mi.name = "fill_mesh"
	return mi

# ---------------------------------------------------------------- добыча и склад

static func _drill(n: Node3D, body: Material) -> float:
	for dx in [-0.75, 0.75]:
		for dz in [-0.75, 0.75]:
			_box(n, Vector3(0.12, 1.8, 0.12), body, Vector3(dx, 0.9, dz), Vector3(-dz * 0.06, 0, dx * 0.06))
	_box(n, Vector3(1.7, 0.14, 1.7), body, Vector3(0, 1.8, 0))
	_box(n, Vector3(0.7, 0.55, 0.7), body, Vector3(0, 2.15, 0))
	var s := _spin(n, Vector3(0, 0, 0))
	_cyl(s, 0.08, 1.8, mat("dark"), Vector3(0, 1.0, 0))
	_cyl(s, 0.26, 0.6, body, Vector3(0, 0.3, 0), 0.02, Vector3.ZERO, 8)
	_ring(s, 0.2, 0.04, body, Vector3(0, 0.7, 0))
	_ring(s, 0.17, 0.04, body, Vector3(0, 0.95, 0))
	return 2.45

static func _container(n: Node3D, body: Material) -> float:
	_box(n, Vector3(1.7, 0.12, 1.7), body, Vector3(0, 0.06, 0))
	for i in 4:
		var a := i * PI / 2.0
		var w := _box(n, Vector3(1.7, 0.85, 0.1), body, Vector3(sin(a) * 0.8, 0.48, cos(a) * 0.8))
		w.rotation.y = a
	for x in [-0.8, 0.8]:
		for z in [-0.8, 0.8]:
			_box(n, Vector3(0.16, 0.95, 0.16), mat("dark"), Vector3(x, 0.48, z))
	_fill(n, 0.7, 0.8, 0.1)
	return 0.95

static func _receiver(n: Node3D, body: Material) -> float:
	_box(n, Vector3(1.6, 0.6, 1.6), body, Vector3(0, 0.3, 0))
	_cyl(n, 0.35, 0.9, body, Vector3(0, 1.05, 0), 0.85)
	_ring(n, 0.85, 0.05, mat("yellow"), Vector3(0, 1.5, 0))
	_cyl(n, 0.3, 0.05, mat("dark"), Vector3(0, 1.49, 0), 0.8)
	return 1.55

static func _fabricator(n: Node3D, body: Material) -> float:
	_box(n, Vector3(1.8, 0.5, 1.6), body, Vector3(0, 0.25, 0))
	_box(n, Vector3(1.2, 0.05, 1.0), mat("blue"), Vector3(0, 0.52, 0))
	for x in [-0.8, 0.8]:
		_box(n, Vector3(0.14, 1.5, 0.14), body, Vector3(x, 1.25, -0.6))
	_box(n, Vector3(1.8, 0.16, 0.2), body, Vector3(0, 2.0, -0.6))
	var s := _spin(n, Vector3(0, 2.0, -0.6))
	_box(s, Vector3(0.12, 0.12, 0.9), body, Vector3(0.3, -0.1, 0.45))
	_cyl(s, 0.05, 0.8, mat("dark"), Vector3(0.3, -0.5, 0.85))
	_sph(s, 0.07, mat("cyan"), Vector3(0.3, -0.92, 0.85))
	_box(n, Vector3(0.5, 0.35, 0.05), mat("cyan"), Vector3(-0.55, 1.3, -0.52))
	return 2.1

# ---------------------------------------------------------------- пневматика

static func _pipe_hub(n: Node3D, body: Material) -> float:
	_sph(n, 0.2, body, Vector3(0, 0.4, 0))
	_cyl(n, 0.05, 0.4, body, Vector3(0, 0.2, 0))
	return 0.6

static func _valve(n: Node3D, body: Material) -> float:
	_cyl(n, 0.16, 1.9, body, Vector3(0, 0.4, 0), -1.0, Vector3(PI / 2.0, 0, 0))
	_cyl(n, 0.28, 0.5, body, Vector3(0, 0.4, 0), 0.24)
	_cyl(n, 0.05, 0.55, mat("dark"), Vector3(0, 0.9, 0))
	var s := _spin(n, Vector3(0, 1.18, 0))
	_ring(s, 0.3, 0.04, mat("magnet"), Vector3.ZERO)
	for i in 3:
		_box(s, Vector3(0.58, 0.04, 0.04), mat("magnet"), Vector3.ZERO, Vector3(0, i * PI / 3.0, 0))
	_cyl(n, 0.12, 0.1, body, Vector3(0, 0.05, 0))
	return 1.2

static func _cannon(n: Node3D, body: Material) -> float:
	_box(n, Vector3(1.3, 0.45, 1.3), body, Vector3(0, 0.22, 0))
	_cyl(n, 0.4, 0.4, body, Vector3(0, 0.65, 0))
	_cyl(n, 0.3, 0.9, body, Vector3(0, 1.0, -0.45), -1.0, Vector3(PI / 2.0, 0, 0))   # баллон
	_ring(n, 0.3, 0.04, mat("yellow"), Vector3(0, 1.0, -0.2), Vector3(PI / 2.0, 0, 0))
	_cyl(n, 0.18, 1.9, body, Vector3(0, 1.35, 0.55), 0.14, Vector3(PI / 2.0 - 0.6, 0, 0))
	_ring(n, 0.19, 0.04, mat("dark"), Vector3(0, 1.85, 1.27), Vector3(PI / 2.0 - 0.6, 0, 0))
	return 1.3

# ---------------------------------------------------------------- обработка

static func _filter(n: Node3D, body: Material) -> float:
	_box(n, Vector3(1.4, 0.3, 1.4), body, Vector3(0, 0.15, 0))
	_cyl(n, 0.5, 1.2, body, Vector3(0, 0.9, 0))
	for y in [0.55, 0.85, 1.15, 1.45]:
		_ring(n, 0.52, 0.03, mat("dark"), Vector3(0, y, 0))
	_cyl(n, 0.12, 0.4, body, Vector3(0, 1.95, 0), 0.55)
	_cyl(n, 0.5, 0.04, mat("net"), Vector3(0, 2.14, 0))
	return 2.15

static func _condenser(n: Node3D, body: Material) -> float:
	_box(n, Vector3(1.5, 1.0, 1.2), body, Vector3(0, 0.5, 0))
	for i in 7:
		_box(n, Vector3(0.04, 0.9, 1.3), mat("cold"), Vector3(-0.6 + i * 0.2, 0.55, 0))
	_cyl(n, 0.6, 0.15, body, Vector3(0, 1.1, 0))
	var s := _spin(n, Vector3(0, 1.2, 0))
	for i in 4:
		_box(s, Vector3(1.0, 0.03, 0.18), mat("dark"), Vector3.ZERO, Vector3(0.3, i * PI / 4.0, 0))
	return 1.25

static func _treater(n: Node3D, body: Material) -> float:
	_cyl(n, 0.75, 1.0, body, Vector3(0, 0.5, 0))
	_cyl(n, 0.65, 0.05, mat("green"), Vector3(0, 0.95, 0))
	_box(n, Vector3(1.6, 0.1, 0.12), body, Vector3(0, 1.4, 0))
	for x in [-0.78, 0.78]:
		_box(n, Vector3(0.1, 1.4, 0.1), body, Vector3(x, 0.7, 0))
	var s := _spin(n, Vector3(0, 1.35, 0))
	_cyl(s, 0.04, 0.8, mat("dark"), Vector3(0, -0.4, 0))
	_box(s, Vector3(0.7, 0.2, 0.04), mat("dark"), Vector3(0, -0.75, 0))
	return 1.45

static func _compressor(n: Node3D, body: Material, de: bool) -> float:
	_box(n, Vector3(1.6, 0.3, 1.0), body, Vector3(0, 0.15, 0))
	_cyl(n, 0.42, 1.3, body, Vector3(0, 0.75, -0.05), -1.0, Vector3(PI / 2.0, 0, 0))
	for z in [-0.45, 0.0, 0.45]:
		_ring(n, 0.44, 0.04, mat("dark"), Vector3(0, 0.75, z - 0.05), Vector3(PI / 2.0, 0, 0))
	if de:
		_cyl(n, 0.4, 0.4, body, Vector3(0, 0.75, 0.75), 0.12, Vector3(-PI / 2.0, 0, 0))
		_ring(n, 0.45, 0.04, mat("cold"), Vector3(0, 0.75, 0.9), Vector3(PI / 2.0, 0, 0))
	else:
		_cyl(n, 0.18, 0.5, body, Vector3(0, 0.75, -0.9), 0.35, Vector3(PI / 2.0, 0, 0))
	_cyl(n, 0.13, 0.06, mat("yellow"), Vector3(0.35, 1.2, 0.1))
	_cyl(n, 0.03, 0.25, mat("dark"), Vector3(0.35, 1.07, 0.1))
	var s := _spin(n, Vector3(-0.55, 0.75, -0.05))
	_ring(s, 0.25, 0.05, body, Vector3.ZERO, Vector3(0, 0, PI / 2.0))
	return 1.25

static func _distiller(n: Node3D, body: Material) -> float:
	_box(n, Vector3(1.4, 0.3, 1.4), body, Vector3(0, 0.15, 0))
	_sph(n, 0.5, body, Vector3(-0.2, 0.75, 0))
	_box(n, Vector3(0.4, 0.2, 0.05), mat("hot"), Vector3(-0.2, 0.55, 0.46))
	_cyl(n, 0.16, 1.7, body, Vector3(-0.2, 2.0, 0))
	for y in [1.4, 1.9, 2.4]:
		_ring(n, 0.18, 0.03, mat("dark"), Vector3(-0.2, y, 0))
	_cyl(n, 0.05, 0.9, body, Vector3(0.2, 2.55, 0), -1.0, Vector3(0, 0, 1.25))
	for i in 5:
		_ring(n, 0.2, 0.035, mat("cold"), Vector3(0.55, 2.0 - i * 0.22, 0))
	_cyl(n, 0.2, 0.4, body, Vector3(0.55, 0.5, 0))
	return 2.9

static func _magnet(n: Node3D, body: Material) -> float:
	_box(n, Vector3(1.7, 0.4, 0.8), body, Vector3(0, 0.2, 0))
	_box(n, Vector3(1.8, 0.06, 0.6), mat("rubber"), Vector3(0, 0.43, 0))
	# Подкова над лентой.
	_ring(n, 0.55, 0.13, mat("magnet"), Vector3(0, 0.95, 0), Vector3(PI / 2.0, 0, 0))
	for x in [-0.55, 0.55]:
		_box(n, Vector3(0.28, 0.18, 0.3), body, Vector3(x, 0.5, 0))
	var s := _spin(n, Vector3(0.85, 0.3, 0))
	_cyl(s, 0.15, 0.7, mat("dark"), Vector3.ZERO, -1.0, Vector3(PI / 2.0, 0, 0), 8)
	_box(n, Vector3(0.9, 0.5, 0.5), body, Vector3(0, 0.25, -0.65))
	return 1.6

static func _electrolyzer(n: Node3D, body: Material) -> float:
	_box(n, Vector3(1.6, 0.3, 1.2), body, Vector3(0, 0.15, 0))
	_box(n, Vector3(1.4, 0.7, 1.0), mat("glass"), Vector3(0, 0.65, 0))
	_box(n, Vector3(1.3, 0.45, 0.9), mat("blue"), Vector3(0, 0.55, 0))
	for x in [-0.35, 0.35]:
		_box(n, Vector3(0.1, 1.0, 0.6), mat("dark"), Vector3(x, 0.8, 0))
		_cyl(n, 0.05, 0.4, mat("magnet") if x < 0 else mat("dark"), Vector3(x, 1.45, 0))
	_cyl(n, 0.03, 0.7, mat("yellow"), Vector3(0, 1.62, 0), -1.0, Vector3(0, 0, PI / 2.0))
	return 1.65

static func _sinter(n: Node3D, body: Material) -> float:
	_box(n, Vector3(1.6, 0.45, 1.4), body, Vector3(0, 0.22, 0))
	_box(n, Vector3(0.9, 0.08, 0.9), mat("hot"), Vector3(0, 0.49, 0))
	for x in [-0.65, 0.65]:
		_cyl(n, 0.1, 1.7, body, Vector3(x, 1.2, 0))
	_box(n, Vector3(1.6, 0.3, 0.6), body, Vector3(0, 2.0, 0))
	var s := _spin(n, Vector3(0, 1.3, 0))
	_box(s, Vector3(1.0, 0.25, 1.0), body, Vector3.ZERO)
	_cyl(s, 0.14, 0.6, mat("dark"), Vector3(0, 0.4, 0))
	return 2.15

static func _irradiator(n: Node3D, body: Material) -> float:
	_box(n, Vector3(1.6, 0.9, 1.6), body, Vector3(0, 0.45, 0))
	_sph(n, 0.6, mat("green"), Vector3(0, 0.9, 0), true)
	_sph(n, 0.66, mat("glass"), Vector3(0, 0.9, 0), true)
	for i in 3:
		var a := i * TAU / 3.0
		_box(n, Vector3(0.45, 0.06, 0.12), mat("yellow"), Vector3(cos(a) * 0.72, 0.92, sin(a) * 0.72), Vector3(0, -a, 0))
	return 1.55

static func _cryo(n: Node3D, body: Material) -> float:
	_box(n, Vector3(1.6, 0.35, 1.2), body, Vector3(0, 0.17, 0))
	_cyl(n, 0.45, 1.5, body, Vector3(0, 0.8, 0), -1.0, Vector3(0, 0, PI / 2.0))
	_sph(n, 0.45, body, Vector3(-0.75, 0.8, 0))
	_sph(n, 0.45, body, Vector3(0.75, 0.8, 0))
	_box(n, Vector3(0.9, 0.3, 0.05), mat("cold"), Vector3(0, 0.9, 0.44))
	for x in [-0.4, 0.0, 0.4]:
		_ring(n, 0.47, 0.03, mat("cold"), Vector3(x, 0.8, 0), Vector3(0, 0, PI / 2.0))
	return 1.3

static func _resonator(n: Node3D, body: Material) -> float:
	_cyl(n, 0.7, 0.35, body, Vector3(0, 0.17, 0), 0.55)
	for x in [-0.2, 0.2]:
		_box(n, Vector3(0.1, 1.6, 0.22), body, Vector3(x, 1.1, 0))
	_sph(n, 0.16, mat("violet"), Vector3(0, 1.3, 0))
	var s := _spin(n, Vector3(0, 1.3, 0))
	_ring(s, 0.5, 0.025, mat("violet"), Vector3.ZERO, Vector3(0.5, 0, 0))
	_ring(s, 0.65, 0.02, mat("violet"), Vector3.ZERO, Vector3(-0.4, 0, 0.3))
	return 1.9

static func _loom(n: Node3D, body: Material) -> float:
	for x in [-0.75, 0.75]:
		_box(n, Vector3(0.12, 1.5, 1.2), body, Vector3(x, 0.75, 0))
	_cyl(n, 0.12, 1.5, body, Vector3(0, 1.35, -0.4), -1.0, Vector3(0, 0, PI / 2.0))
	_cyl(n, 0.14, 1.5, body, Vector3(0, 0.4, 0.45), -1.0, Vector3(0, 0, PI / 2.0))
	for i in 12:
		var x := -0.6 + i * 0.11
		var t := _box(n, Vector3(0.015, 1.05, 0.015), mat("thread"), Vector3(x, 0.88, 0.02))
		t.rotation.x = -0.75
	var s := _spin(n, Vector3(0, 0.9, 0.05))
	_box(s, Vector3(1.4, 0.06, 0.1), mat("dark"), Vector3.ZERO)
	return 1.5

# ---------------------------------------------------------------- логика

static func _sensor(n: Node3D, body: Material) -> float:
	_cyl(n, 0.3, 0.15, body, Vector3(0, 0.07, 0))
	_cyl(n, 0.06, 0.7, body, Vector3(0, 0.45, 0))
	_box(n, Vector3(0.36, 0.26, 0.3), body, Vector3(0, 0.9, 0))
	_sph(n, 0.1, mat("yellow"), Vector3(0, 0.9, 0.16))
	return 1.05

static func _gate(n: Node3D, body: Material, kind: String) -> float:
	_box(n, Vector3(0.8, 0.3, 0.8), body, Vector3(0, 0.15, 0))
	_box(n, Vector3(0.84, 0.04, 0.84), mat("yellow"), Vector3(0, 0.3, 0))
	var l := Label3D.new()
	l.text = {"gate_and": "И", "gate_or": "ИЛИ", "gate_not": "НЕ"}[kind]
	l.font_size = 64
	l.pixel_size = 0.004
	l.modulate = Color(1.0, 0.9, 0.3)
	l.outline_size = 10
	l.rotation.x = -PI / 2.0
	l.position = Vector3(0, 0.33, 0)
	n.add_child(l)
	return 0.35

# ---------------------------------------------------------------- составные и прочее

static func _battery(n: Node3D, body: Material) -> float:
	_box(n, Vector3(1.9, 0.3, 1.9), body, Vector3(0, 0.15, 0))
	_cyl(n, 0.6, 1.1, body, Vector3(0, 0.85, 0))
	_sph(n, 0.6, body, Vector3(0, 1.4, 0), true)
	_ring(n, 0.62, 0.05, mat("stripe"), Vector3(0, 0.75, 0))
	return 1.95

static func _net(n: Node3D, body: Material) -> float:
	for x in [-0.85, 0.85]:
		for z in [-0.85, 0.85]:
			_cyl(n, 0.05, 0.9, body, Vector3(x, 0.45, z))
	for i in 5:
		var k := -0.8 + i * 0.4
		var sag := 0.62 - 0.12 * (1.0 - absf(k) / 0.8)
		_box(n, Vector3(1.7, 0.02, 0.02), mat("net"), Vector3(0, sag, k))
		_box(n, Vector3(0.02, 0.02, 1.7), mat("net"), Vector3(k, sag, 0))
	return 0.9

static func _warehouse(n: Node3D, body: Material) -> float:
	_box(n, Vector3(1.9, 1.3, 1.9), body, Vector3(0, 0.65, 0))
	for i in 5:
		_box(n, Vector3(0.05, 1.2, 1.92), mat("dark"), Vector3(-0.8 + i * 0.4, 0.65, 0))
	_box(n, Vector3(0.9, 0.9, 0.04), mat("yellow"), Vector3(0, 0.5, 0.96))
	return 1.3

static func _macro(n: Node3D, body: Material) -> float:
	_box(n, Vector3(1.8, 1.2, 1.8), body, Vector3(0, 0.6, 0))
	var c := mat("cyan")
	for y in [0.02, 1.2]:
		for i in 4:
			var a := i * PI / 2.0
			_box(n, Vector3(1.84, 0.05, 0.05), c, Vector3(sin(a) * 0.9, y, cos(a) * 0.9), Vector3(0, a, 0))
	for x in [-0.9, 0.9]:
		for z in [-0.9, 0.9]:
			_box(n, Vector3(0.05, 1.2, 0.05), c, Vector3(x, 0.6, z))
	var l := Label3D.new()
	l.text = "МБ"
	l.font_size = 72
	l.pixel_size = 0.006
	l.modulate = Color(0.5, 0.85, 1.0)
	l.rotation.x = -PI / 2.0
	l.position = Vector3(0, 1.22, 0)
	n.add_child(l)
	return 1.2

static func _silo(n: Node3D, body: Material) -> float:
	_cyl(n, 0.95, 0.8, body, Vector3(0, 0.4, 0), 0.9, Vector3.ZERO, 24)
	_cyl(n, 0.72, 0.05, mat("dark"), Vector3(0, 0.81, 0))
	_ring(n, 0.82, 0.05, mat("yellow"), Vector3(0, 0.82, 0))
	_cyl(n, 0.25, 0.9, mat("net"), Vector3(0, 1.1, 0))
	_cyl(n, 0.25, 0.45, mat("magnet"), Vector3(0, 1.77, 0), 0.0)
	for i in 3:
		var a := i * TAU / 3.0
		_box(n, Vector3(0.08, 1.8, 0.08), body, Vector3(cos(a) * 0.8, 1.3, sin(a) * 0.8))
	return 2.0

static func _dome(n: Node3D, body: Material) -> float:
	_cyl(n, 0.95, 0.25, body, Vector3(0, 0.12, 0), -1.0, Vector3.ZERO, 24)
	_sph(n, 0.9, mat("glass"), Vector3(0, 0.25, 0), true)
	for i in 3:
		_ring(n, 0.9, 0.025, body, Vector3(0, 0.25, 0), Vector3(PI / 2.0, i * PI / 3.0, 0))
	_box(n, Vector3(0.4, 0.5, 0.3), body, Vector3(0, 0.45, 0.85))
	_fill(n, 0.45, 0.6, 0.25)
	return 1.15

static func _beacon(n: Node3D, body: Material) -> float:
	_cyl(n, 0.6, 0.3, body, Vector3(0, 0.15, 0), 0.5)
	for i in 3:
		var a := i * TAU / 3.0
		var leg := _box(n, Vector3(0.07, 2.6, 0.07), body, Vector3(cos(a) * 0.25, 1.5, sin(a) * 0.25))
		leg.rotation = Vector3(sin(a) * 0.12, 0, -cos(a) * 0.12)
	for y in [0.9, 1.6, 2.3]:
		_ring(n, 0.3 - (y - 0.9) * 0.07, 0.03, body, Vector3(0, y, 0))
	_sph(n, 0.2, mat("cyan"), Vector3(0, 2.9, 0))
	var s := _spin(n, Vector3(0, 2.9, 0))
	_box(s, Vector3(0.9, 0.04, 0.04), mat("cyan"), Vector3.ZERO)
	return 3.1
