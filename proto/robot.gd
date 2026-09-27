class_name ProtoRobot
extends Node3D
## Робот — гуманоидный каркас из простых тел: таз, торс-клетка из колец и стоек,
## голова-сенсор со светящимся глазом, баллон на спине, конечности-стержни с
## шарнирами. На руках — бур и крюк цвета своих материалов. Лёгкий шаг.

var frame_mat: StandardMaterial3D
var joint_mat: StandardMaterial3D
var hips: Array = []        # [узел бедра, фаза]
var shoulders: Array = []
var walk := true
var _t := 0.0
var eye_light: OmniLight3D

func _init(hull: Color, drill_col: Color, hook_col: Color) -> void:
	frame_mat = StandardMaterial3D.new()
	frame_mat.albedo_color = hull
	frame_mat.metallic = 0.7
	frame_mat.roughness = 0.35
	joint_mat = StandardMaterial3D.new()
	joint_mat.albedo_color = hull.darkened(0.45)
	joint_mat.metallic = 0.6
	joint_mat.roughness = 0.4
	_build(drill_col, hook_col)

func _rod(parent: Node3D, length: float, r: float, pos: Vector3) -> MeshInstance3D:
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = length
	c.radial_segments = 10
	var mi := MeshInstance3D.new()
	mi.mesh = c
	mi.material_override = frame_mat
	mi.position = pos
	parent.add_child(mi)
	return mi

func _ball(parent: Node3D, r: float, pos: Vector3, mat: Material = null) -> MeshInstance3D:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 12
	s.rings = 6
	var mi := MeshInstance3D.new()
	mi.mesh = s
	mi.material_override = mat if mat != null else joint_mat
	mi.position = pos
	parent.add_child(mi)
	return mi

## Конечность: шарнир (узел вращения), верхний стержень, колено/локоть, нижний.
func _limb(parent: Node3D, at: Vector3, upper: float, lower: float, r: float) -> Array:
	var root := Node3D.new()
	root.position = at
	parent.add_child(root)
	_ball(root, r * 1.8, Vector3.ZERO)
	_rod(root, upper, r, Vector3(0, -upper / 2.0, 0))
	var knee := Node3D.new()
	knee.position = Vector3(0, -upper, 0)
	root.add_child(knee)
	_ball(knee, r * 1.5, Vector3.ZERO)
	_rod(knee, lower, r * 0.85, Vector3(0, -lower / 2.0, 0))
	return [root, knee]

func _build(drill_col: Color, hook_col: Color) -> void:
	# Таз.
	var pelvis := MeshInstance3D.new()
	var pb := BoxMesh.new()
	pb.size = Vector3(0.42, 0.14, 0.22)
	pelvis.mesh = pb
	pelvis.material_override = joint_mat
	pelvis.position = Vector3(0, 0.95, 0)
	add_child(pelvis)
	# Позвоночник и торс-клетка: кольца на стойках.
	_rod(self, 0.6, 0.035, Vector3(0, 1.3, -0.05))
	for i in 3:
		var t := TorusMesh.new()
		t.inner_radius = 0.17 - i * 0.01
		t.outer_radius = 0.2 - i * 0.01
		t.rings = 16
		t.ring_segments = 6
		var mi := MeshInstance3D.new()
		mi.mesh = t
		mi.material_override = frame_mat
		mi.position = Vector3(0, 1.2 + i * 0.16, 0)
		mi.scale = Vector3(1.25 - i * 0.1, 1, 0.75)
		add_child(mi)
	for dx in [-0.2, 0.2]:
		_rod(self, 0.4, 0.025, Vector3(dx, 1.36, 0.08))
	# Плечевая перекладина.
	var sb := _rod(self, 0.55, 0.035, Vector3(0, 1.6, 0))
	sb.rotation = Vector3(0, 0, PI / 2.0)
	# Голова-сенсор с глазом.
	_rod(self, 0.12, 0.03, Vector3(0, 1.68, 0))
	var head := MeshInstance3D.new()
	var hb := BoxMesh.new()
	hb.size = Vector3(0.22, 0.16, 0.2)
	head.mesh = hb
	head.material_override = frame_mat
	head.position = Vector3(0, 1.82, 0)
	add_child(head)
	var eye_mat := StandardMaterial3D.new()
	eye_mat.albedo_color = Color(0.3, 0.95, 1.0)
	eye_mat.emission_enabled = true
	eye_mat.emission = Color(0.3, 0.95, 1.0)
	eye_mat.emission_energy_multiplier = 3.0
	_ball(self, 0.045, Vector3(0, 1.83, 0.11), eye_mat)
	eye_light = OmniLight3D.new()
	eye_light.light_color = Color(0.7, 0.95, 1.0)
	eye_light.light_energy = 0.0
	eye_light.omni_range = 9.0
	eye_light.position = Vector3(0, 1.85, 0.3)
	add_child(eye_light)
	# Баллон на спине.
	var tank := MeshInstance3D.new()
	var tc := CylinderMesh.new()
	tc.top_radius = 0.11
	tc.bottom_radius = 0.11
	tc.height = 0.5
	tank.mesh = tc
	var tm := StandardMaterial3D.new()
	tm.albedo_color = Color(0.85, 0.75, 0.3)
	tm.metallic = 0.8
	tm.roughness = 0.3
	tank.material_override = tm
	tank.position = Vector3(0, 1.35, -0.24)
	add_child(tank)
	# Ноги.
	for side in [-1, 1]:
		var leg := _limb(self, Vector3(0.14 * side, 0.92, 0), 0.44, 0.44, 0.035)
		hips.append([leg[0], 0.0 if side < 0 else PI, leg[1]])
		var foot := MeshInstance3D.new()
		var fb := BoxMesh.new()
		fb.size = Vector3(0.1, 0.05, 0.22)
		foot.mesh = fb
		foot.material_override = joint_mat
		foot.position = Vector3(0, -0.46, 0.05)
		leg[1].add_child(foot)
	# Руки: правая с буром, левая с крюком.
	for side in [-1, 1]:
		var arm := _limb(self, Vector3(0.3 * side, 1.6, 0), 0.32, 0.3, 0.03)
		shoulders.append([arm[0], PI if side < 0 else 0.0, arm[1]])
		var tool := MeshInstance3D.new()
		var m := StandardMaterial3D.new()
		m.metallic = 0.6
		m.roughness = 0.35
		if side > 0:
			var cone := CylinderMesh.new()
			cone.top_radius = 0.0
			cone.bottom_radius = 0.07
			cone.height = 0.24
			tool.mesh = cone
			m.albedo_color = drill_col
			tool.rotation = Vector3(PI, 0, 0)
			tool.position = Vector3(0, -0.42, 0)
		else:
			var hook := TorusMesh.new()
			hook.inner_radius = 0.05
			hook.outer_radius = 0.08
			tool.mesh = hook
			m.albedo_color = hook_col
			tool.rotation = Vector3(0, 0, PI / 2.0)
			tool.position = Vector3(0, -0.36, 0)
		tool.material_override = m
		arm[1].add_child(tool)
	pose(0.35)

## Поза шага: фаза 0..1.
func pose(phase: float) -> void:
	for h in hips:
		h[0].rotation.x = sin(phase * TAU + h[1]) * 0.45
		h[2].rotation.x = max(0.0, -sin(phase * TAU + h[1])) * 0.6
	for s in shoulders:
		s[0].rotation.x = sin(phase * TAU + s[1]) * 0.35
		s[2].rotation.x = -0.35

func _process(dt: float) -> void:
	if walk:
		_t += dt * 0.9
		pose(_t)
