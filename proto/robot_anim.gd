class_name RobotAnim
extends Node
## Анимация робота на риге из RobotDesigns (сейчас — «Хард-серфейс»): кости
## hips → chest → head, shoulder → elbow, hips → hip → knee → ankle. Руки и ноги
## ставятся двухзвенным IK по целям кисти и лодыжки с полюсом локтя/колена.
##   покой  — контрапост, рука на бедре, дыхание, взгляд по сторонам, уши
##            подёргиваются, диафрагма щурится, шкала давления «дышит»;
##   ходьба — стопы по циклу, таз покачивается, руки в противофазе.
## Позы — словари; между покоем и ходьбой плавный переход по скорости speed
## (м/с): частота шага = скорость / длина цикла, стопы не скользят.
## Поверх — «работа» (рука вперёд, прищур) и прицел левой руки (выстрел кистью).
## Бур в правом предплечье: пока работы нет, спрятан в щитке; с началом работы
## кисть подгибается и сжимается, бур выдвигается мимо запястья и только потом
## крутится; после — останавливается, уходит обратно, кисть разгибается.

## Время для кадров витрины: ≥ 0 — анимация стоит в этом моменте.
static var fixed_t := -1.0
## idle, walk (шаг на месте), demo (покой → ходьба → покой), drill (бур
## выдвигается, работает и уходит, цикл 3 с), fist (выстрел кистью, см. RobotFist) — для витрины.
static var default_mode := "idle"

const CYCLE := 0.88          # м за полный цикл шага (два шага)
const WALK_SPEED := 0.84     # м/с — обычный шаг

var mode := ""
var speed := 0.0             # задаёт игрок; в режимах витрины — сама анимация
var work := 0.0              # 0..1 — работа инструментом (правая рука)
var aim_w := 0.0             # 0..1 — прицел левой рукой
var aim_target := Vector3.ZERO   # в пространстве робота
var work_target := Vector3.INF   # точка работы бура (пространство робота); INF — просто вперёд
var fill_drop := 0.0         # просадка давления после выстрела (затухает)
var ap_kick := 0.0           # «щелчок» диафрагмой (затухает)
var bit: Node3D              # сверло бура, если есть
var drill: Node3D            # бур в предплечье (выдвигается), если есть
var drill_rest := Transform3D()
var drill_out := 0.0         # 0 — спрятан, 1 — выдвинут
var hand_r: Node3D
var hand_r_rest := Basis()
var t := 0.0
var phase := 0.0
var walk_k := 0.0
var root: Node3D
var s: Dictionary
var hips: Node3D
var chest: Node3D
var head: Node3D
var ears: Array = []        # [узел, покойный базис]
var aperture: Node3D
var fill: Node3D
var hips_rest := Transform3D()
var chest_rest := Transform3D()
var _sim_t := 0.0
var _fixed_started := false

func _ready() -> void:
	if mode == "":
		mode = default_mode
	root = get_parent()
	s = root.get_meta("rig")
	hips = root.get_node("hips")
	chest = hips.get_node("chest")
	head = chest.get_node("head")
	hips_rest = hips.transform
	chest_rest = chest.transform
	for e in ["ear_l", "ear_r"]:
		var en: Node3D = head.get_node(e)
		ears.append([en, en.transform.basis])
	aperture = head.get_node_or_null("aperture")
	fill = chest.get_node_or_null("pressure_bar/pressure_fill")
	bit = root.find_child("bit", true, false) as Node3D
	drill = root.find_child("drill", true, false) as Node3D
	if drill:
		drill_rest = drill.transform
	hand_r = root.find_child("hand_r", true, false) as Node3D
	if hand_r:
		hand_r_rest = hand_r.transform.basis
	_apply()

func _process(dt: float) -> void:
	if fixed_t >= 0.0:
		# Кадры витрины: детерминированно прогоняем время до fixed_t.
		if fixed_t < _sim_t or not _fixed_started:
			_reset_sim()
			_fixed_started = true
		while _sim_t < fixed_t - 0.0001:
			var h := minf(1.0 / 60.0, fixed_t - _sim_t)
			_step(h)
			_sim_t += h
	else:
		_step(dt)
	_apply()

func _reset_sim() -> void:
	_sim_t = 0.0
	t = 0.0
	phase = 0.0
	walk_k = 0.0
	fill_drop = 0.0
	ap_kick = 0.0
	drill_out = 0.0
	work = 0.0

## Скорость в режимах витрины.
func _mode_speed(tt: float) -> float:
	match mode:
		"walk": return WALK_SPEED
		"demo": return WALK_SPEED if tt > 1.0 and tt < 3.6 else 0.0
	return speed

func _step(dt: float) -> void:
	t += dt
	fill_drop = move_toward(fill_drop, 0.0, dt * 0.12)
	ap_kick = move_toward(ap_kick, 0.0, dt * 4.0)
	if mode == "drill":
		# Витрина: цикл 3 с — бур выдвигается, сверлит, уходит обратно.
		var q := fposmod(t, 3.0)
		work = move_toward(work, 1.0 if q > 0.2 and q < 2.0 else 0.0, dt * 5.0)
	if drill:
		# Выдвигается, когда рука уже пошла вперёд; уходит, когда работа кончилась.
		var want_out := 1.0 if work > 0.6 else 0.0
		drill_out = move_toward(drill_out, want_out, dt / (0.3 if want_out > 0.0 else 0.25))
	var spin := work if drill == null else work * smoothstep(0.85, 1.0, drill_out)
	if bit and spin > 0.01:
		bit.rotate_object_local(Vector3.UP, dt * 28.0 * spin)
	var v := _mode_speed(t) if mode != "play" else speed
	var want := clampf(v / WALK_SPEED, 0.0, 1.0)
	walk_k = move_toward(walk_k, want, dt / 0.3)
	# Пока шаг затухает, стопы доходят цикл до конца — не зависают в воздухе.
	var rate := maxf(v, walk_k * WALK_SPEED * 0.6) / CYCLE
	if walk_k > 0.001:
		phase += dt * rate
	else:
		phase = 0.0

func _apply() -> void:
	var p := _idle(t)
	if walk_k > 0.001:
		p = _blend(p, _walk(phase, clampf(walk_k * 1.2, 0.0, 1.0)), smoothstep(0.0, 1.0, walk_k))
	if work > 0.001:
		p = _blend(p, _work(p), work)
	if aim_w > 0.001:
		var sh := _pose_shoulder(p, "l")
		var d := (aim_target - sh).normalized()
		var pa := p.duplicate()
		pa.arm_l = sh + d * 0.52
		pa.pole_l = Vector3(-0.3, -1, -0.2)
		pa.head_rot = Vector3(-0.05, clampf(atan2(d.x, d.z), -0.8, 0.8) * 0.6, 0.0)
		p = _blend(p, pa, aim_w)
	p.fill -= fill_drop
	p.ap -= 0.3 * sin(ap_kick * PI)
	_apply_pose(p)

# ---------------------------------------------------------------- позы

func _idle(tt: float) -> Dictionary:
	var p := {}
	# Вес на левой ноге: таз сдвинут влево и опущен справа, плечи — встречно.
	p.hips_off = Vector3(-0.025 + 0.01 * sin(tt * 0.5), -0.02 + 0.003 * sin(tt * 1.6), 0)
	p.hips_rot = Vector3(0, 0.05, -0.05)
	p.chest_rot = Vector3(0.015 * sin(tt * 1.6), -0.04, 0.07)
	# Взгляд: медленно по сторонам, голова наклонена — «присматривается».
	var look := 0.3 * sin(tt * 0.23) * sin(tt * 0.11 + 1.0)
	p.head_rot = Vector3(-0.06 + 0.04 * sin(tt * 0.4 + 2.0), 0.14 + look, 0.12)
	p.foot_l = s.an_l
	p.foot_l_rot = Vector3.ZERO
	p.foot_r = Vector3(0.19, s.an_r.y, 0.08)
	p.foot_r_rot = Vector3(0, 0.28, 0)
	# Левая кисть — на бедре (цель привязана к тазу), правая с инструментом наготове.
	p.arm_l = _pose_hips(p) * Vector3(-0.2, 0.075, 0.02)
	p.pole_l = Vector3(-1, 0, -0.7)
	p.arm_r = _pose_shoulder(p, "r") + Vector3(0.06, -0.43, 0.19)
	p.pole_r = Vector3(0.4, -0.3, -1)
	# Уши подёргиваются вразнобой, диафрагма иногда щурится, давление «дышит».
	p.ear_l = 0.45 * _pulse(tt, 3.7, 0.4)
	p.ear_r = -0.4 * _pulse(tt, 5.1, 2.2)
	p.ap = 0.93 + 0.05 * sin(tt * 0.7) - 0.22 * _pulse(tt, 6.3, 3.0, 5.0)
	p.fill = 0.72 + 0.03 * sin(tt * 0.9)
	return p

## Ходьба в фазе w (циклы); amp — размах (на разгоне меньше).
func _walk(w: float, amp: float) -> Dictionary:
	var p := {}
	var ph := TAU * w
	var stride := 0.44 * amp
	p.hips_off = Vector3(0.022 * sin(ph) * amp, -0.05 * amp + 0.02 * cos(2.0 * ph) * amp, 0)
	p.hips_rot = Vector3(0.03 * amp, 0.1 * sin(ph) * amp, 0.03 * sin(ph) * amp)
	p.chest_rot = Vector3(0.05 * amp, -0.16 * sin(ph) * amp, -0.04 * sin(ph) * amp)
	p.head_rot = Vector3(-0.05 + 0.015 * cos(2.0 * ph), 0.07 * sin(ph) * amp, 0.0)
	var fl := _foot(w, 0.0, stride)
	var fr := _foot(w, 0.5, stride)
	p.foot_l = s.an_l + Vector3(0, fl.y * amp, fl.z)
	p.foot_l_rot = Vector3(fl.x * amp, 0, 0)
	p.foot_r = s.an_r + Vector3(0, fr.y * amp, fr.z)
	p.foot_r_rot = Vector3(fr.x * amp, 0, 0)
	# Руки — в противофазе ногам своей стороны; правая с инструментом — сдержаннее.
	var l_rest: Vector3 = s.ha_l - s.sh_l
	var r_rest: Vector3 = s.ha_r - s.sh_r
	p.arm_l = _pose_shoulder(p, "l") + Basis(Vector3.RIGHT, fl.z * 1.5) * (l_rest * 0.96)
	p.pole_l = Vector3(-0.3, 0, -1)
	p.arm_r = _pose_shoulder(p, "r") + Basis(Vector3.RIGHT, fr.z * 0.7 - 0.25) * (r_rest * 0.93)
	p.pole_r = Vector3(0.3, -0.2, -1)
	p.ear_l = 0.1 * sin(2.0 * ph) * amp
	p.ear_r = 0.1 * sin(2.0 * ph + 0.6) * amp
	p.ap = 1.0
	p.fill = 0.72
	return p

## Работа инструментом: правая рука вперёд-вниз, корпус подаётся вперёд, прищур.
func _work(base: Dictionary) -> Dictionary:
	var p := base.duplicate()
	p.chest_rot = base.chest_rot + Vector3(0.12, -0.15, 0)
	p.head_rot = Vector3(0.18, -0.1, 0.05)
	p.arm_r = _pose_shoulder(p, "r") + Vector3(-0.08, -0.25, 0.42)
	if work_target != Vector3.INF:
		# Тянется к точке: низко — наклоняется корпусом, кисть — не дальше руки,
		# остальное добирает выдвинутый бур.
		var low := clampf((1.2 - work_target.y) / 1.0, 0.0, 1.0)
		p.chest_rot = base.chest_rot + Vector3(0.12 + 0.3 * low, -0.1, 0)
		p.head_rot = Vector3(0.18 + 0.35 * low, -0.05, 0.05)
		var sh := _pose_shoulder(p, "r")
		var to := work_target - sh
		p.arm_r = sh + to.normalized() * clampf(to.length() - 0.3, 0.2, 0.5)
		p.pole_r = Vector3(0.7, 0.1, -0.5)
	p.pole_r = Vector3(0.6, -0.4, -0.6)
	p.ap = 0.72 + 0.03 * sin(t * 23.0)
	p.fill = base.fill - 0.12 - 0.02 * sin(t * 5.0)
	return p

static func _blend(a: Dictionary, b: Dictionary, k: float) -> Dictionary:
	var r := {}
	for key in a:
		r[key] = lerp(a[key], b[key], k)
	return r

## Трансформы таза и груди для позы (не текущие — чтобы цели не отставали).
func _pose_hips(p: Dictionary) -> Transform3D:
	return Transform3D(Basis.from_euler(p.hips_rot), hips_rest.origin + p.hips_off)

func _pose_shoulder(p: Dictionary, side: String) -> Vector3:
	var cx := _pose_hips(p) * Transform3D(Basis.from_euler(p.chest_rot), chest_rest.origin)
	var sb: Node3D = chest.get_node("shoulder_" + side)
	return cx * sb.position

func _apply_pose(p: Dictionary) -> void:
	hips.transform = _pose_hips(p)
	chest.transform = Transform3D(Basis.from_euler(p.chest_rot), chest_rest.origin)
	head.rotation = p.head_rot
	_legs(p.foot_l, Basis.from_euler(p.foot_l_rot), p.foot_r, Basis.from_euler(p.foot_r_rot))
	_arm("l", p.arm_l, p.pole_l)
	_arm("r", p.arm_r, p.pole_r)
	for i in 2:
		var e: Node3D = ears[i][0]
		var rest: Basis = ears[i][1]
		e.transform.basis = rest * Basis(Vector3.BACK, p.ear_l if i == 0 else p.ear_r)
	if aperture:
		aperture.scale = Vector3(p.ap, p.ap, 1)
		aperture.rotation.z = (1.0 - p.ap) * 1.6
	if fill:
		fill.scale.y = maxf(p.fill, 0.01)
	if drill:
		# Сначала подгибается кисть (первая треть хода), затем бур идёт вперёд.
		var slide := smoothstep(0.25, 1.0, drill_out)
		var stroke: float = drill.get_meta("stroke", 0.2)
		drill.visible = drill_out > 0.001
		drill.transform = Transform3D(drill_rest.basis, drill_rest.origin + drill_rest.basis.y * stroke * slide)
		if hand_r and hand_r.has_meta("flex_axis"):
			var fk := smoothstep(0.0, 0.4, drill_out)
			hand_r.transform.basis = Basis(hand_r.get_meta("flex_axis"), 1.25 * fk) * hand_r_rest

## Стопа в цикле шага: x — наклон носка, y — подъём, z — сдвиг вперёд.
func _foot(w: float, off: float, stride: float) -> Vector3:
	var q := fposmod(w + off, 1.0)
	if q < 0.6:
		var a := q / 0.6
		return Vector3(0.12 * smoothstep(0.75, 1.0, a), 0.0, stride * (0.5 - a))
	var b := (q - 0.6) / 0.4
	return Vector3(-0.3 * sin(PI * b), 0.1 * sin(PI * b), stride * (smoothstep(0.0, 1.0, b) - 0.5))

## Короткий импульс раз в период (для подёргиваний).
func _pulse(tt: float, period: float, off: float, width: float = 14.0) -> float:
	var x := fposmod(tt - off, period) - 0.15
	return exp(-pow(x * width, 2.0))

# ---------------------------------------------------------------- IK

## Трансформ узла в пространстве робота.
func _xf(nd: Node3D) -> Transform3D:
	var x := Transform3D()
	var c: Node = nd
	while c != root and c is Node3D:
		x = (c as Node3D).transform * x
		c = c.get_parent()
	return x

## Базис, у которого Y идёт вдоль y, а Z — к z.
static func _frame(y: Vector3, z: Vector3) -> Basis:
	y = y.normalized()
	z = (z - y * y.dot(z)).normalized()
	return Basis(y.cross(z), y, z)

## Двухзвенный IK: upper — кость в суставе a, lower — в b, конец c (покой);
## target — куда поставить конец, pole — куда смотрит средний сустав;
## rest_pole — куда он смотрит в покое. end/end_basis — поворот концевой кости.
func _two_bone(upper: Node3D, lower: Node3D, a: Vector3, b: Vector3, c: Vector3, target: Vector3, pole: Vector3, rest_pole: Vector3, end: Node3D = null, end_basis := Basis()) -> void:
	var pxf := _xf(upper.get_parent())
	var A := pxf * upper.position
	var l1 := a.distance_to(b)
	var l2 := b.distance_to(c)
	var to := target - A
	var d := clampf(to.length(), 0.02, (l1 + l2) * 0.999)
	var u := to.normalized()
	var ka := (l1 * l1 - l2 * l2 + d * d) / (2.0 * d)
	var h := sqrt(maxf(l1 * l1 - ka * ka, 0.0))
	var pp := (pole - u * u.dot(pole)).normalized()
	var E := A + u * ka + pp * h
	var C := A + u * d
	var g1 := _frame(E - A, pole) * _frame(b - a, rest_pole).inverse()
	upper.transform.basis = pxf.basis.inverse() * g1
	var g2 := _frame(C - E, pole) * _frame(c - b, rest_pole).inverse()
	lower.transform.basis = g1.inverse() * g2
	if end != null:
		end.transform.basis = g2.inverse() * end_basis

func _legs(tl: Vector3, fl: Basis, tr: Vector3, fr: Basis) -> void:
	for side in ["l", "r"]:
		var hb: Node3D = hips.get_node("hip_" + side)
		var kb: Node3D = hb.get_node("knee_" + side)
		var ab: Node3D = kb.get_node("ankle_" + side)
		var tgt := tl if side == "l" else tr
		var fb := fl if side == "l" else fr
		_two_bone(hb, kb, s["hi_" + side], s["kn_" + side], s["an_" + side], tgt,
			fb * Vector3(0, 0, 1) + Vector3(0, 0.1, 0), Vector3(0, 0, 1), ab, fb)

func _arm(side: String, target: Vector3, pole: Vector3) -> void:
	var sb: Node3D = chest.get_node("shoulder_" + side)
	var eb: Node3D = sb.get_node("elbow_" + side)
	_two_bone(sb, eb, s["sh_" + side], s["el_" + side], s["ha_" + side], target, pole, Vector3(0, 0, -1))
	if side == "r":
		var h := eb.get_node_or_null("hand_r") as Node3D
		RobotDesigns.set_grip(h, maxf(0.3 + 0.5 * work, smoothstep(0.0, 0.4, drill_out)))
