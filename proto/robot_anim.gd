class_name RobotAnim
extends Node
## Анимация робота на риге из RobotDesigns (сейчас — «Хард-серфейс»): кости
## hips → chest → head, shoulder → elbow, hips → hip → knee → ankle. Руки и ноги
## ставятся двухзвенным IK по целям кисти и лодыжки с полюсом локтя/колена.
##   idle — контрапост, рука на бедре, дыхание, взгляд по сторонам, уши
##          подёргиваются, диафрагма щурится, шкала давления «дышит»;
##   walk — шаг на месте: стопы по циклу, таз покачивается, руки в противофазе.

## Время для кадров витрины: ≥ 0 — анимация стоит в этом моменте.
static var fixed_t := -1.0
static var default_mode := "idle"

var mode := ""
var t := 0.0
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
	_apply()

func _process(dt: float) -> void:
	t += dt
	_apply()

func _apply() -> void:
	var tt := fixed_t if fixed_t >= 0.0 else t
	if mode == "walk":
		_walk(tt)
	else:
		_idle(tt)

# ---------------------------------------------------------------- позы

func _idle(tt: float) -> void:
	# Вес на левой ноге: таз сдвинут влево и опущен справа, плечи — встречно.
	hips.transform = Transform3D(Basis.from_euler(Vector3(0, 0.05, -0.05)),
		hips_rest.origin + Vector3(-0.025 + 0.01 * sin(tt * 0.5), -0.02 + 0.003 * sin(tt * 1.6), 0))
	chest.transform = Transform3D(Basis.from_euler(Vector3(0.015 * sin(tt * 1.6), -0.04, 0.07)), chest_rest.origin)
	# Взгляд: медленно по сторонам, голова наклонена — «присматривается».
	var look := 0.3 * sin(tt * 0.23) * sin(tt * 0.11 + 1.0)
	head.rotation = Vector3(-0.06 + 0.04 * sin(tt * 0.4 + 2.0), 0.14 + look, 0.12)
	_legs(Vector3(s.an_l.x, s.an_l.y, s.an_l.z), 0.0, Basis(),
		Vector3(0.19, s.an_r.y, 0.08), 0.0, Basis(Vector3.UP, 0.28))
	# Левая кисть — на бедре (цель привязана к тазу), правая с инструментом наготове.
	var hip_pt: Vector3 = hips.transform * Vector3(-0.2, 0.075, 0.02)
	_arm("l", hip_pt, Vector3(-1, 0, -0.7))
	_arm("r", _shoulder("r") + Vector3(0.06, -0.43, 0.19), Vector3(0.4, -0.3, -1))
	# Уши подёргиваются вразнобой, диафрагма иногда щурится, давление «дышит».
	_ears(0.45 * _pulse(tt, 3.7, 0.4), -0.4 * _pulse(tt, 5.1, 2.2))
	if aperture:
		var sq := 0.93 + 0.05 * sin(tt * 0.7) - 0.22 * _pulse(tt, 6.3, 3.0, 5.0)
		aperture.scale = Vector3(sq, sq, 1)
		aperture.rotation.z = (1.0 - sq) * 1.6
	if fill:
		fill.scale.y = 0.72 + 0.03 * sin(tt * 0.9)

func _walk(tt: float) -> void:
	var w := tt * 0.95
	var ph := TAU * w
	var stride := 0.44
	hips.transform = Transform3D(Basis.from_euler(Vector3(0.03, 0.1 * sin(ph), 0.03 * sin(ph))),
		hips_rest.origin + Vector3(0.022 * sin(ph), -0.05 + 0.02 * cos(2.0 * ph), 0))
	chest.transform = Transform3D(Basis.from_euler(Vector3(0.05, -0.16 * sin(ph), -0.04 * sin(ph))), chest_rest.origin)
	head.rotation = Vector3(-0.05 + 0.015 * cos(2.0 * ph), 0.07 * sin(ph), 0.0)
	var fl := _foot(w, 0.0, stride)
	var fr := _foot(w, 0.5, stride)
	_legs(Vector3(s.an_l.x, s.an_l.y + fl.y, s.an_l.z + fl.z), 0.0, Basis(Vector3.RIGHT, fl.x),
		Vector3(s.an_r.x, s.an_r.y + fr.y, s.an_r.z + fr.z), 0.0, Basis(Vector3.RIGHT, fr.x))
	# Руки — в противофазе ногам своей стороны; правая с инструментом — сдержаннее.
	var el_rest: Vector3 = s.ha_l - s.sh_l
	_arm("l", _shoulder("l") + Basis(Vector3.RIGHT, fl.z * 1.5) * (el_rest * 0.96), Vector3(-0.3, 0, -1))
	var er_rest: Vector3 = s.ha_r - s.sh_r
	_arm("r", _shoulder("r") + Basis(Vector3.RIGHT, fr.z * 0.7 - 0.25) * (er_rest * 0.93), Vector3(0.3, -0.2, -1))
	_ears(0.1 * sin(2.0 * ph), 0.1 * sin(2.0 * ph + 0.6))
	if aperture:
		aperture.scale = Vector3.ONE
		aperture.rotation.z = 0.0
	if fill:
		fill.scale.y = 0.72

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

func _ears(a_l: float, a_r: float) -> void:
	for i in 2:
		var e: Node3D = ears[i][0]
		var rest: Basis = ears[i][1]
		e.transform.basis = rest * Basis(Vector3.BACK, a_l if i == 0 else a_r)

# ---------------------------------------------------------------- IK

## Трансформ узла в пространстве робота.
func _xf(nd: Node3D) -> Transform3D:
	var x := Transform3D()
	var c: Node = nd
	while c != root and c is Node3D:
		x = (c as Node3D).transform * x
		c = c.get_parent()
	return x

func _shoulder(side: String) -> Vector3:
	var sb: Node3D = chest.get_node("shoulder_" + side)
	return _xf(chest) * sb.position

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
	var p := (pole - u * u.dot(pole)).normalized()
	var E := A + u * ka + p * h
	var C := A + u * d
	var g1 := _frame(E - A, pole) * _frame(b - a, rest_pole).inverse()
	upper.transform.basis = pxf.basis.inverse() * g1
	var g2 := _frame(C - E, pole) * _frame(c - b, rest_pole).inverse()
	lower.transform.basis = g1.inverse() * g2
	if end != null:
		end.transform.basis = g2.inverse() * end_basis

func _legs(tl: Vector3, _yl: float, fl: Basis, tr: Vector3, _yr: float, fr: Basis) -> void:
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
