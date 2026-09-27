class_name RobotFist
extends Node
## Выстреливающаяся левая кисть «Хард-серфейса» (пневматика вместо крюка-кошки).
## Выстрел: облачко пара из ствола, шкала давления проседает; кисть с раскрытыми
## пальцами летит по дуге к цели, за ней провисает трос. У цели пальцы сжимаются;
## дальше трос натягивается и подтягивает робота (pull) либо кисть возвращается.
## На возврате трос сматывается, кисть защёлкивается в гнезде, диафрагма щурится.
## Цели — в пространстве робота. В режиме витрины RobotAnim.default_mode == "fist"
## выстрел повторяется, а кадры берутся по RobotAnim.fixed_t.

const FLY_SPEED := 10.0
const BACK_SPEED := 7.0
const LINKS := 16

var state := "dock"          # dock, fly, grab, pull, back
var st_t := 0.0              # время в текущем состоянии
var target := Vector3.ZERO
var pull_wanted := false
var root: Node3D
var anim: RobotAnim
var elbow: Node3D
var hand: Node3D
var mouth: Node3D
var hand_rest := Transform3D()
var dn_elb := Vector3.DOWN   # «вниз по кисти» в пространстве кости локтя
var links: Array = []
var puff: CPUParticles3D
var fist_pos := Vector3.ZERO # где кисть сейчас (пространство робота)
var _sim_t := 0.0
var _demo_next := 0.4
var _fixed_started := false

func _ready() -> void:
	root = get_parent()
	anim = root.get_node_or_null("anim")
	var s: Dictionary = root.get_meta("rig")
	elbow = root.get_node("hips/chest/shoulder_l/elbow_l")
	hand = elbow.get_node("hand_l")
	mouth = elbow.get_node("fist_mouth")
	hand_rest = hand.transform
	dn_elb = ((s.ha_l - s.el_l) as Vector3).normalized() + Vector3(0, -0.6, 0)
	dn_elb = dn_elb.normalized()
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.1, 0.1, 0.12)
	m.metallic = 0.5
	m.roughness = 0.5
	for i in LINKS:
		var c := CylinderMesh.new()
		c.top_radius = 0.007
		c.bottom_radius = 0.007
		c.height = 1.0
		c.radial_segments = 6
		var mi := MeshInstance3D.new()
		mi.mesh = c
		mi.material_override = m
		mi.visible = false
		root.add_child.call_deferred(mi)
		links.append(mi)
	puff = _make_puff()
	root.add_child.call_deferred(puff)
	RobotDesigns.set_grip(hand, 0.25)

## Выстрелить в точку (пространство робота); pull — подтянуться к ней.
func fire(at: Vector3, pull := false) -> void:
	if state != "dock":
		return
	target = at
	pull_wanted = pull
	_set_state("fly")
	fist_pos = _mouth_pos()
	puff.position = fist_pos
	puff.restart()
	puff.emitting = true
	if anim:
		anim.fill_drop = 0.22

## Отпустить после подтягивания.
func release() -> void:
	if state == "pull" or state == "grab":
		_set_state("back")

func _set_state(s: String) -> void:
	state = s
	st_t = 0.0

func _process(dt: float) -> void:
	if RobotAnim.default_mode == "fist":
		if RobotAnim.fixed_t >= 0.0:
			if RobotAnim.fixed_t < _sim_t or not _fixed_started:
				_reset()
				_fixed_started = true
			while _sim_t < RobotAnim.fixed_t - 0.0001:
				var h := minf(1.0 / 60.0, RobotAnim.fixed_t - _sim_t)
				_demo_step(h)
				_sim_t += h
		else:
			_demo_step(dt)
	else:
		_step(dt)
	_pose()

func _reset() -> void:
	_sim_t = 0.0
	_demo_next = 0.4
	state = "dock"
	st_t = 0.0
	if anim:
		anim.aim_w = 0.0
		anim.fill_drop = 0.0

## Витрина: выстрел вперёд-вправо, повтор каждые 3 с.
func _demo_step(dt: float) -> void:
	if state == "dock" and _sim_t_or_live() >= _demo_next:
		fire(Vector3(0.9, 1.5, 3.2))
		_demo_next += 3.0
	_step(dt)

func _sim_t_or_live() -> float:
	return _sim_t if RobotAnim.fixed_t >= 0.0 else _live_t

var _live_t := 0.0

func _step(dt: float) -> void:
	_live_t += dt
	st_t += dt
	var m := _mouth_pos()
	match state:
		"fly":
			var d := m.distance_to(target)
			var e := clampf(st_t * FLY_SPEED / maxf(d, 0.1), 0.0, 1.0)
			fist_pos = m.lerp(target, e) + Vector3(0, sin(PI * e) * d * 0.06, 0)
			if e >= 1.0:
				_set_state("grab")
		"grab":
			fist_pos = target
			if st_t > 0.3:
				_set_state("pull" if pull_wanted else "back")
		"pull":
			fist_pos = target
			if st_t > 3.0:
				_set_state("back")
		"back":
			var d2 := fist_pos.distance_to(m)
			var step := BACK_SPEED * dt
			if d2 <= step:
				fist_pos = m
				_set_state("dock")
				if anim:
					anim.ap_kick = 1.0
			else:
				fist_pos += (m - fist_pos) / d2 * step
	if anim:
		anim.aim_w = move_toward(anim.aim_w, 0.0 if state == "dock" else 1.0, dt * 6.0)
		anim.aim_target = target

func _mouth_pos() -> Vector3:
	return _xf(elbow) * mouth.position

func _xf(nd: Node3D) -> Transform3D:
	var x := Transform3D()
	var c: Node = nd
	while c != root and c is Node3D:
		x = (c as Node3D).transform * x
		c = c.get_parent()
	return x

## Кисть, пальцы и трос по состоянию.
func _pose() -> void:
	if state == "dock":
		hand.transform = hand_rest
		RobotDesigns.set_grip(hand, 0.25)
		for l in links:
			(l as MeshInstance3D).visible = false
		return
	var exf := _xf(elbow)
	var m := exf * mouth.position
	var dir := (fist_pos - m)
	if dir.length() < 0.01:
		dir = exf.basis * dn_elb
	dir = dir.normalized()
	if state == "back":
		dir = (m - fist_pos).normalized() * -1.0
	# Поворот кисти: её «вниз» — вдоль полёта; положение — fist_pos.
	var b0 := exf.basis * hand_rest.basis
	var now_dn := (exf.basis * dn_elb).normalized()
	var q := Quaternion(now_dn, dir) if now_dn.dot(dir) > -0.999 else Quaternion(Vector3.UP, PI)
	var gb := Basis(q) * b0
	hand.transform = exf.affine_inverse() * Transform3D(gb, fist_pos)
	var g := -0.25
	match state:
		"grab": g = lerpf(-0.25, 1.0, clampf(st_t / 0.25, 0.0, 1.0))
		"pull", "back": g = 1.0
	RobotDesigns.set_grip(hand, g)
	_cable(m, fist_pos)

## Трос по кривой Безье: провисает, пока кисть в полёте и у цели, натянут при подтягивании.
func _cable(a: Vector3, b: Vector3) -> void:
	var L := a.distance_to(b)
	var sag := 0.0
	match state:
		"fly": sag = L * 0.08
		"grab": sag = L * 0.12
		"back": sag = L * 0.1
	var d := (b - a) / 3.0
	var ca := a + d + Vector3(0, -sag, 0)
	var cb := b - d + Vector3(0, -sag, 0)
	var prev := a
	for i in LINKS:
		var t := float(i + 1) / LINKS
		var u := 1.0 - t
		var p := a * u * u * u + ca * 3.0 * u * u * t + cb * 3.0 * u * t * t + b * t * t * t
		var mi: MeshInstance3D = links[i]
		mi.visible = true
		var y := p - prev
		var len := y.length()
		if len < 0.0001:
			mi.visible = false
			continue
		y /= len
		var ref := Vector3.UP if absf(y.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
		var x := y.cross(ref).normalized()
		mi.transform = Transform3D(Basis(x, y * len, x.cross(y)), (prev + p) / 2.0)
		prev = p

func _make_puff() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.emitting = false
	p.amount = 14
	p.lifetime = 0.9
	p.explosiveness = 0.9
	p.direction = Vector3(0, 0.3, 1)
	p.spread = 35.0
	p.initial_velocity_min = 0.25
	p.initial_velocity_max = 0.6
	p.gravity = Vector3(0, 0.4, 0)
	p.scale_amount_min = 0.03
	p.scale_amount_max = 0.07
	var q := QuadMesh.new()
	var m := StandardMaterial3D.new()
	var gt := GradientTexture2D.new()
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	var gr := Gradient.new()
	gr.set_color(0, Color(1, 1, 1, 0.8))
	gr.set_color(1, Color(1, 1, 1, 0))
	gt.gradient = gr
	m.albedo_texture = gt
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.albedo_color = Color(0.9, 0.95, 1.0, 0.35)
	q.material = m
	p.mesh = q
	return p
