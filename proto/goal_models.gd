class_name GoalModels
## Варианты облика сооружений целей (пусковая шахта, маяк, купол) — на выбор.
## Стиль по умолчанию ("") — модели MachineModels. Остальные:
##   "landmark" — крупные ориентиры: башня обслуживания с ракетой, большой
##                геодезический купол с садом внутри, решётчатая мачта с лучом;
##   "sleek"    — цельные обтекаемые формы: люк в бетонном кольце, светлая
##                оболочка с поясом окон, обелиск с кристаллом.
## Контракт как у MachineModels.build: выход на +Z, мета "h" — высота, узел
## "spin" крутится, пока деталь работает.

const KINDS := ["launch_silo", "beacon", "dome"]
const STYLES := ["", "landmark", "sleek"]

static func build(kind: String, body: Material, style: String) -> Node3D:
	if style == "" or not kind in KINDS:
		return MachineModels.build(kind, body)
	var n := Node3D.new()
	var h := 1.2
	match style + ":" + kind:
		"landmark:launch_silo": h = _tower(n, body)
		"landmark:dome": h = _geodome(n, body)
		"landmark:beacon": h = _mast(n, body)
		"sleek:launch_silo": h = _hatch(n, body)
		"sleek:dome": h = _shell(n, body)
		"sleek:beacon": h = _obelisk(n, body)
	n.set_meta("h", h)
	return n

static func _m(id: String) -> Material:
	return MachineModels.mat(id)

# ---------------------------------------------------------------- крупные ориентиры

## Пусковая: бетонная площадка, ракета 3.6 м в фермах башни обслуживания.
static func _tower(n: Node3D, body: Material) -> float:
	MachineModels._cyl(n, 0.98, 0.3, _m("dark"), Vector3(0, 0.15, 0), -1.0, Vector3.ZERO, 24)
	MachineModels._ring(n, 0.9, 0.04, _m("stripe"), Vector3(0, 0.31, 0))
	# Ракета: корпус, обтекатель, стабилизаторы.
	var white := MachineModels._flat(Color(0.92, 0.92, 0.9), 0.5)
	MachineModels._cyl(n, 0.3, 2.4, white, Vector3(0, 1.55, 0), -1.0, Vector3.ZERO, 16)
	MachineModels._cyl(n, 0.3, 0.9, _m("magnet"), Vector3(0, 3.2, 0), 0.02)
	MachineModels._ring(n, 0.31, 0.03, body, Vector3(0, 2.2, 0))
	for i in 4:
		var a := i * TAU / 4.0 + PI / 4.0
		MachineModels._box(n, Vector3(0.04, 0.6, 0.35), body, Vector3(cos(a) * 0.33, 0.6, sin(a) * 0.33), Vector3(0, -a, 0))
	# Башня обслуживания сбоку (на -X): четыре стойки, ригели, два рукава к ракете.
	var tx := -0.72
	for dx in [-0.18, 0.18]:
		for dz in [-0.18, 0.18]:
			MachineModels._box(n, Vector3(0.06, 4.0, 0.06), body, Vector3(tx + dx, 2.0, dz))
	for y in [0.8, 1.6, 2.4, 3.2, 4.0]:
		MachineModels._box(n, Vector3(0.42, 0.05, 0.42), body, Vector3(tx, y, 0))
	for y in [1.6, 2.8]:
		MachineModels._box(n, Vector3(0.36, 0.08, 0.1), _m("yellow"), Vector3(tx + 0.36, y, 0))
	var lamp := MachineModels._sph(n, 0.08, _m("lamp_idle"), Vector3(tx, 4.1, 0))
	lamp.name = "lamp"
	return 4.2

## Купол: геодезическая полусфера радиусом 1.4 м, сад и свет внутри, шлюз.
static func _geodome(n: Node3D, body: Material) -> float:
	MachineModels._cyl(n, 1.0, 0.2, body, Vector3(0, 0.1, 0), -1.0, Vector3.ZERO, 24)
	var s := SphereMesh.new()
	s.radius = 0.98
	s.height = 0.98
	s.is_hemisphere = true
	s.radial_segments = 10
	s.rings = 4
	var glass := MachineModels._add(n, s, ProtoMachines.glass(), Vector3(0, 0.2, 0))
	glass.scale = Vector3(1, 1.25, 1)
	# Рёбра: меридианы и два пояса.
	for i in 5:
		MachineModels._ring(n, 0.98, 0.022, body, Vector3(0, 0.2, 0), Vector3(PI / 2.0, i * PI / 5.0, 0)).scale = Vector3(1, 1, 1.25)
	for k in [0.45, 0.85]:
		var y := 0.2 + 0.98 * 1.25 * sin(k)
		MachineModels._ring(n, 0.98 * cos(k), 0.02, body, Vector3(0, y, 0))
	# Сад: грядки и деревца, тёплый свет.
	var green := MachineModels._flat(Color(0.3, 0.62, 0.28), 0.9)
	for p in [Vector3(-0.35, 0, -0.2), Vector3(0.3, 0, -0.35), Vector3(0.1, 0, 0.3), Vector3(-0.3, 0, 0.35)]:
		MachineModels._cyl(n, 0.03, 0.4, _m("rubber"), p + Vector3(0, 0.4, 0))
		MachineModels._sph(n, 0.18, green, p + Vector3(0, 0.68, 0))
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.85, 0.6)
	l.light_energy = 0.8
	l.omni_range = 2.2
	l.position = Vector3(0, 0.9, 0)
	n.add_child(l)
	# Шлюз на выходе (+Z).
	MachineModels._box(n, Vector3(0.45, 0.6, 0.35), body, Vector3(0, 0.5, 0.95))
	MachineModels._box(n, Vector3(0.28, 0.42, 0.02), _m("yellow"), Vector3(0, 0.45, 1.13))
	return 1.45

## Маяк: решётчатая мачта 5 м, фонарь с вращающимся лучом.
static func _mast(n: Node3D, body: Material) -> float:
	MachineModels._cyl(n, 0.7, 0.25, _m("dark"), Vector3(0, 0.12, 0), 0.6, Vector3.ZERO, 6)
	var top := 4.8
	for i in 4:
		var a := i * TAU / 4.0 + PI / 4.0
		var b := MachineModels._box(n, Vector3(0.07, top, 0.07), body, Vector3(cos(a) * 0.3, top / 2.0, sin(a) * 0.3))
		b.rotation = Vector3(sin(a) * 0.05, 0, -cos(a) * 0.05)
	for k in 6:
		var y := 0.6 + k * 0.72
		var w := 0.62 - y * 0.075
		MachineModels._box(n, Vector3(w, 0.04, 0.04), body, Vector3(0, y, w / 2.0), Vector3(0, 0, 0.5))
		MachineModels._box(n, Vector3(0.04, 0.04, w), body, Vector3(w / 2.0, y, 0), Vector3(0.5, 0, 0))
	MachineModels._cyl(n, 0.3, 0.1, body, Vector3(0, top, 0))
	MachineModels._cyl(n, 0.2, 0.45, ProtoMachines.glass(), Vector3(0, top + 0.28, 0))
	MachineModels._sph(n, 0.13, _m("cyan"), Vector3(0, top + 0.28, 0))
	MachineModels._cyl(n, 0.24, 0.18, _m("magnet"), Vector3(0, top + 0.6, 0), 0.05)
	var s := MachineModels._spin(n, Vector3(0, top + 0.28, 0))
	# Луч: полупрозрачный конус, лежащий на боку.
	var beam := StandardMaterial3D.new()
	beam.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	beam.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	beam.albedo_color = Color(0.55, 0.9, 1.0, 0.22)
	beam.cull_mode = BaseMaterial3D.CULL_DISABLED
	MachineModels._cyl(s, 0.08, 3.0, beam, Vector3(1.5, 0, 0), 0.45, Vector3(0, 0, PI / 2.0), 12)
	for i in 3:
		var a := i * TAU / 3.0
		MachineModels._sph(n, 0.05, _m("lamp_off"), Vector3(cos(a) * 0.3, top * 0.5, sin(a) * 0.3))
	return top + 0.7

# ---------------------------------------------------------------- обтекаемые

## Пусковая: утопленная шахта в толстом бетонном кольце, створки полуоткрыты.
static func _hatch(n: Node3D, body: Material) -> float:
	var conc := MachineModels._flat(Color(0.62, 0.62, 0.6), 0.95)
	MachineModels._cyl(n, 0.98, 0.5, conc, Vector3(0, 0.25, 0), 0.9, Vector3.ZERO, 28)
	MachineModels._cyl(n, 0.62, 0.02, _m("dark"), Vector3(0, 0.51, 0), -1.0, Vector3.ZERO, 24)
	MachineModels._ring(n, 0.66, 0.04, _m("stripe"), Vector3(0, 0.52, 0))
	for sgn in [-1.0, 1.0]:
		var door := MachineModels._box(n, Vector3(0.62, 0.06, 1.2), body, Vector3(sgn * 0.55, 0.75, 0))
		door.rotation.z = sgn * -0.75
	MachineModels._cyl(n, 0.24, 0.5, MachineModels._flat(Color(0.95, 0.95, 0.93), 0.4), Vector3(0, 0.62, 0), 0.02)
	for i in 3:
		var a := i * TAU / 3.0 + PI / 2.0
		var lp := MachineModels._sph(n, 0.06, _m("lamp_idle"), Vector3(cos(a) * 0.88, 0.52, sin(a) * 0.88))
		if i == 0:
			lp.name = "lamp"
	return 1.2

## Купол: светлая приплюснутая оболочка с поясом тёплых окон.
static func _shell(n: Node3D, body: Material) -> float:
	var white := MachineModels._flat(Color(0.9, 0.9, 0.87), 0.6)
	MachineModels._cyl(n, 1.0, 0.18, body, Vector3(0, 0.09, 0), -1.0, Vector3.ZERO, 28)
	var s := SphereMesh.new()
	s.radius = 0.95
	s.height = 0.95
	s.is_hemisphere = true
	s.radial_segments = 28
	s.rings = 10
	MachineModels._add(n, s, white, Vector3(0, 0.18, 0)).scale = Vector3(1, 0.72, 1)
	var win := ProtoMachines.glow(Color(1.0, 0.82, 0.5), 1.6)
	for i in 10:
		var a := i * TAU / 10.0
		var w := MachineModels._box(n, Vector3(0.26, 0.12, 0.04), win, Vector3(sin(a) * 0.93, 0.36, cos(a) * 0.93))
		w.rotation.y = a
	MachineModels._cyl(n, 0.2, 0.08, ProtoMachines.glass(), Vector3(0, 0.88, 0))
	MachineModels._box(n, Vector3(0.4, 0.4, 0.3), white, Vector3(0, 0.3, 0.95))
	MachineModels._box(n, Vector3(0.24, 0.3, 0.02), _m("yellow"), Vector3(0, 0.3, 1.11))
	return 0.95

## Маяк: гранёный обелиск из материала постройки, кристалл-фонарь на вершине.
static func _obelisk(n: Node3D, body: Material) -> float:
	MachineModels._cyl(n, 0.6, 0.2, _m("dark"), Vector3(0, 0.1, 0), 0.55, Vector3.ZERO, 4)
	MachineModels._cyl(n, 0.38, 3.2, body, Vector3(0, 1.8, 0), 0.18, Vector3(0, PI / 4.0, 0), 4)
	for y in [1.0, 2.0, 3.0]:
		MachineModels._box(n, Vector3(0.04, 0.3, 0.04), _m("cyan"), Vector3(0, y, 0.38 - y * 0.065))
	var s := MachineModels._spin(n, Vector3(0, 3.75, 0))
	var c := MachineModels._cyl(s, 0.22, 0.55, _m("cyan"), Vector3(0, 0.28, 0), 0.0, Vector3.ZERO, 6)
	MachineModels._cyl(s, 0.0, 0.3, _m("cyan"), Vector3(0, -0.15, 0), 0.22, Vector3.ZERO, 6)
	c.name = "crystal"
	var l := OmniLight3D.new()
	l.light_color = Color(0.5, 0.85, 1.0)
	l.light_energy = 1.2
	l.omni_range = 4.0
	s.add_child(l)
	return 4.3
