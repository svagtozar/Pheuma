class_name RobotGround
extends Node
## Контакт робота с рельефом: высота и наклон корпуса по сетке рельефа, стопы —
## на поверхность под ними.
##   Рельеф получает коллизию по своей видимой сетке (add_collision), и все
##   замеры — лучами в неё: робот стоит ровно на том, что видно, а не на поле
##   плотности (сетка от него отличается на десятки сантиметров).
##   place — высота корпуса по лучу под центром и частичный наклон к склону
##   (сглаженный, чтобы робот не качался на каждой кочке).
##   fit — поправка позы RobotAnim: каждая стопа опускается или поднимается до
##   поверхности под ней и поворачивается по её нормали; корпус садится так,
##   чтобы дотянулась нижняя нога.

## Слой коллизии рельефа (только для лучей робота).
const LAYER := 1 << 19
## Доля наклона склона, которую повторяет корпус, и предел наклона.
const TILT := 0.45
const TILT_MAX := 0.3
## Грудь частично отыгрывает наклон назад — голова ближе к вертикали.
const CHEST_BACK := 0.35
## Стопа поворачивается по нормали не больше чем на этот угол.
const FOOT_MAX := 0.5
## Насколько далеко стопа может уйти вверх/вниз от плоскости корпуса.
const FOOT_REACH := 0.4

var root: Node3D
var anim: RobotAnim
var normal := Vector3.UP     # сглаженная нормаль склона под роботом
var _y := NAN                # сглаженная высота корпуса
var _hips := 0.0             # посадка корпуса к нижней стопе (м)

## Коллизия по сетке рельефа: статическое тело на слое LAYER.
static func add_collision(mi: MeshInstance3D) -> void:
	if mi.mesh == null or mi.mesh.get_surface_count() == 0:
		return
	var body := StaticBody3D.new()
	body.name = "ground_collision"
	body.collision_layer = LAYER
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	cs.shape = mi.mesh.create_trimesh_shape()
	body.add_child(cs)
	mi.add_child(body)

## Подключить к роботу из RobotDesigns.build.
static func attach(robot: Node3D) -> RobotGround:
	var g := RobotGround.new()
	g.name = "ground"
	robot.add_child(g)
	g.root = robot
	g.anim = robot.get_node_or_null("anim")
	if g.anim:
		g.anim.ground = g
	return g

## Луч вниз по вертикали мира: {position, normal} или пусто.
func probe(from: Vector3, depth := 1.8) -> Dictionary:
	return ray(from, from - Vector3(0, depth, 0))

## Луч в сетку рельефа: {position, normal} или пусто.
func ray(from: Vector3, to: Vector3) -> Dictionary:
	if root == null or not root.is_inside_tree():
		return {}
	var q := PhysicsRayQueryParameters3D.create(from, to, LAYER)
	return root.get_world_3d().direct_space_state.intersect_ray(q)

## Сразу поставить корпус на высоту y (приземление после прыжка — без сглаживания).
func snap(y: float) -> void:
	_y = y
	_hips = 0.0

## Высота корпуса (fallback — если сетки под роботом нет) и наклон к склону.
func place(fallback: float) -> void:
	var dt := clampf(get_process_delta_time(), 0.001, 0.1)
	var p := root.position
	var top := p + Vector3(0, 0.8, 0)
	var c := probe(top)
	var y := fallback if c.is_empty() else float(c.position.y)
	if is_nan(_y) or absf(y - _y) > 1.5:
		_y = y
	_y = lerpf(_y, y, 1.0 - exp(-dt * 25.0))
	root.position.y = _y + _hips
	# Склон — по четырём точкам вокруг: ровнее, чем нормаль одного треугольника.
	var n := Vector3.UP if c.is_empty() else (c.normal as Vector3)
	var r := 0.3
	var hx0 := probe(top + Vector3(-r, 0, 0))
	var hx1 := probe(top + Vector3(r, 0, 0))
	var hz0 := probe(top + Vector3(0, 0, -r))
	var hz1 := probe(top + Vector3(0, 0, r))
	if not (hx0.is_empty() or hx1.is_empty() or hz0.is_empty() or hz1.is_empty()):
		n = Vector3(hx0.position.y - hx1.position.y, 2.0 * r, hz0.position.y - hz1.position.y).normalized()
	normal = normal.lerp(n, 1.0 - exp(-dt * 5.0)).normalized()
	# Наклон в осях робота (поворот — YXZ: курс, затем тангаж и крен).
	var yaw := root.rotation.y
	var nl := Basis(Vector3.UP, yaw).inverse() * normal
	root.rotation = Vector3(
		clampf(atan2(nl.z, nl.y) * TILT, -TILT_MAX, TILT_MAX),
		yaw,
		clampf(atan2(-nl.x, nl.y) * TILT, -TILT_MAX, TILT_MAX))

## Поправка позы перед применением: стопы на поверхность, таз, грудь.
func fit(p: Dictionary) -> void:
	if root == null or not root.is_inside_tree():
		return
	var dt := clampf(get_process_delta_time(), 0.001, 0.1)
	var s: Dictionary = anim.s
	var gx := root.global_transform
	var inv := gx.basis.inverse()
	var dy := {}
	for side in ["l", "r"]:
		var ft: Vector3 = p["foot_" + side]
		var lift: float = ft.y - (s["an_" + side] as Vector3).y
		# Середина подошвы — чуть впереди лодыжки; луч — по вертикали корпуса.
		var hit := ray(gx * Vector3(ft.x, 0.7, ft.z + 0.05), gx * Vector3(ft.x, -FOOT_REACH - 0.3, ft.z + 0.05))
		if hit.is_empty():
			dy[side] = 0.0
			continue
		var hl: Vector3 = gx.affine_inverse() * (hit.position as Vector3)
		var d := clampf(hl.y, -FOOT_REACH, FOOT_REACH)
		dy[side] = d
		p["foot_" + side] = ft + Vector3(0, d, 0)
		# Опорная стопа ложится на поверхность, в махе — как в анимации.
		var w := 1.0 - clampf(lift / 0.05, 0.0, 1.0)
		var nl: Vector3 = (inv * (hit.normal as Vector3)).normalized()
		var ang := minf(Vector3.UP.angle_to(nl), FOOT_MAX) * w
		if ang > 0.001:
			var ax := Vector3.UP.cross(nl)
			if ax.length() > 0.0001:
				p["foot_" + side + "_rot"] = (Basis(ax.normalized(), ang) * Basis.from_euler(p["foot_" + side + "_rot"])).get_euler()
	# Корпус садится к нижней стопе (place добавляет _hips к высоте), чтобы нога
	# дотягивалась, а верхняя сгибалась: копим, пока нижняя стопа не на уровне корпуса.
	var low := minf(dy.get("l", 0.0), dy.get("r", 0.0))
	_hips = clampf(_hips + low * (1.0 - exp(-dt * 12.0)), -FOOT_REACH, FOOT_REACH)
	p.chest_rot = p.chest_rot - Vector3(root.rotation.x, 0, root.rotation.z) * CHEST_BACK
