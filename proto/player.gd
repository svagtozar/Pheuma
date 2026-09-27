class_name ProtoPlayer
extends Node
## Управление роботом от третьего лица в предпросмотре (--play) и скриптовый
## маршрут для проверки (--auto=cave).
##   WASD — ходьба относительно камеры, Shift — быстрее, Q/E или мышь с правой
##   кнопкой — поворот камеры, колесо — дистанция. F (держать) — работать
##   инструментом: бур выдвигается из правого предплечья, отпустить — уходит.
##   G — выстрелить кистью туда, куда смотрит камера, и подтянуться (G ещё
##   раз — отпустить).
##   Геймпад: левый стик — ходьба, правый — камера, L3 — быстрее, RT — бур,
##   LT — кисть, D-pad вверх/вниз — дистанция (раскладка — ProtoControls).
## Скорость хода и высота уступа зависят от гравитации планеты.
## Высота под ногами — по полю плотности (снаружи и в пещере), в породу и на
## слишком крутые уступы не заходит. Камера на пружинной штанге. Под сводом сама
## включает фару и сгущает тёмный туман.

var robot: Node3D
var anim: RobotAnim
var cam: Camera3D
var terrain: ProtoTerrain
var env: Environment
var fog_out := Color()
var fog_out_d := 0.0

var cam_yaw := 0.0
var cam_pitch := -0.32
var cam_dist := 4.6
var vel := Vector3.ZERO
var under := 0.0             # 0 — под небом, 1 — под сводом (сглажено)

# Скриптовый маршрут.
var route: Array = []
var route_i := 0
var shots: Array = []        # доли маршрута, на которых снять кадр
var shot_prefix := ""
var shot_n := 0
var route_len := 0.0
var route_done := 0.0
var fist: RobotFist
var finale := -1.0           # --auto=sound: время после конца маршрута (бур, кисть)

func setup(r: Node3D, c: Camera3D, t: ProtoTerrain, e: Environment) -> void:
	robot = r
	cam = c
	terrain = t
	env = e
	fog_out = env.fog_light_color
	fog_out_d = env.fog_density
	anim = robot.get_node_or_null("anim")
	if anim:
		anim.mode = "play"
	cam_yaw = robot.rotation.y
	fist = robot.get_node_or_null("fist")
	ProtoControls.ensure()

## Маршрут: от площадки завода по склону к входу в пещеру и по ходу в зал.
func auto_cave(prefix: String) -> void:
	shot_prefix = prefix
	var pc := terrain.plateau()
	route = [Vector3(pc.x + 5.0, 0, pc.z + 4.0), Vector3(terrain.cave_entry.x, 0, terrain.cave_entry.z + 3.0)]
	var a := terrain.cave_entry
	var b := terrain.cave_c + Vector3(0, 1, 0)
	for i in range(1, 11):
		var tt := i / 10.0
		route.append(a.lerp(b, tt) + Vector3(sin(tt * 6.0) * 2.0, 0, 0))
	# Конец — у края зала, где нет натёков и друз (то же место, что у вида cave).
	route.append(terrain.cave_c + Vector3(-4.0, 0, 3.0))
	var p0: Vector3 = route[0]
	robot.position = Vector3(p0.x, terrain.surface_h(p0.x, p0.z), p0.z)
	for i in range(1, route.size()):
		route_len += Vector2(route[i].x, route[i].z).distance_to(Vector2(route[i - 1].x, route[i - 1].z))
	shots = [0.08, 0.42, 0.72, 1.0]
	route_i = 1

## Маршрут для проверки звука: снаружи в пещеру, в конце бур у стены и выстрел кистью.
func auto_sound() -> void:
	auto_cave("")
	shots = []
	finale = 0.0

## Конец маршрута --auto=sound: повернуться к стене, сверлить, выстрелить кистью.
func _finale(dt: float) -> void:
	finale += dt
	if finale < 0.1:
		var best := Vector3.FORWARD
		var best_d := 99.0
		for k in 16:
			var dir := Vector3(sin(TAU * k / 16.0), 0, cos(TAU * k / 16.0))
			for d in range(1, 30):
				var q := robot.position + Vector3(0, 1.1, 0) + dir * (d * 0.25)
				if terrain.solid(q.x, q.y, q.z):
					if d < best_d:
						best_d = d
						best = dir
					break
		robot.rotation.y = atan2(best.x, best.z)
		cam_yaw = robot.rotation.y
	if anim:
		anim.work = move_toward(anim.work, 1.0 if finale > 0.5 and finale < 4.5 else 0.0, dt * 5.0)
	if fist and finale > 5.5 and fist.state == "dock" and finale < 6.0:
		var hit := _aim_point()
		fist.fire(robot.to_local(hit) if hit != Vector3.INF else Vector3(0.9, 1.5, 3.2), false)
	if finale > 9.0:
		get_tree().quit(0)

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		cam_yaw -= e.relative.x * 0.006
		cam_pitch = clampf(cam_pitch - e.relative.y * 0.004, -1.1, 0.2)
	elif e is InputEventMouseButton and e.pressed:
		if e.button_index == MOUSE_BUTTON_WHEEL_UP:
			cam_dist = maxf(2.0, cam_dist - 0.4)
		elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			cam_dist = minf(12.0, cam_dist + 0.4)

func _process(dt: float) -> void:
	dt = minf(dt, 0.25)
	var want := Vector3.ZERO
	# Тяжёлая планета — шаг медленнее, лёгкая — быстрее (ProtoWorldStyle).
	var top_speed := RobotAnim.WALK_SPEED * terrain.style.walk_mult()
	if route.is_empty():
		var inp := ProtoControls.move_vector()
		var look := ProtoControls.look_vector()
		cam_yaw -= look.x * dt * 2.4
		cam_pitch = clampf(cam_pitch + look.y * dt * 1.6, -1.1, 0.2)
		if Input.is_action_pressed(ProtoControls.CAM_ZOOM_IN): cam_dist = maxf(2.0, cam_dist - dt * 4.0)
		if Input.is_action_pressed(ProtoControls.CAM_ZOOM_OUT): cam_dist = minf(12.0, cam_dist + dt * 4.0)
		if Input.is_action_pressed(ProtoControls.SPRINT): top_speed *= 1.9
		if anim:
			anim.work = move_toward(anim.work, Input.get_action_strength(ProtoControls.WORK), dt * 5.0)
		if Input.is_action_just_pressed(ProtoControls.FIST) and fist:
			if fist.state == "dock":
				var hit := _aim_point()
				if hit != Vector3.INF:
					fist.fire(robot.to_local(hit), true)
			else:
				fist.release()
		if inp != Vector2.ZERO:
			# Вперёд — от камеры: камера смотрит вдоль (sin yaw, cos yaw).
			var fwd := Vector3(sin(cam_yaw), 0, cos(cam_yaw))
			var right := Vector3(-fwd.z, 0, fwd.x)
			# Длина inp — наклон стика (клавиши дают 1): лёгкий наклон — медленный шаг.
			want = (fwd * inp.y - right * inp.x).normalized() * minf(1.0, inp.length())
	else:
		want = _follow_route()
		top_speed *= 1.7
		if finale >= 0.0 and route_i >= route.size():
			_finale(dt)
	# Подтягивание: трос тянет робота к кисти.
	if fist and fist.state == "pull":
		var tw := robot.to_global(fist.target)
		var to := tw - robot.position
		if Vector2(to.x, to.z).length() > 1.0:
			want = Vector3(to.x, 0, to.z).normalized()
			top_speed = 2.6
		else:
			fist.release()
	vel = vel.move_toward(want * top_speed, dt * 3.0)
	_move(vel * dt)
	if vel.length() > 0.05:
		robot.rotation.y = lerp_angle(robot.rotation.y, atan2(vel.x, vel.z), minf(1.0, dt * 6.0))
		if not route.is_empty():
			cam_yaw = lerp_angle(cam_yaw, robot.rotation.y, minf(1.0, dt * 2.0))
	if anim:
		anim.speed = Vector2(vel.x, vel.z).length()
	_underground(dt)
	_camera()
	_route_shots()

## Шаг с учётом рельефа: не в породу, не на крутой уступ; высота — пол под ногами.
func _move(d: Vector3) -> void:
	if d.length() < 0.0001:
		_settle()
		return
	var np := robot.position + d
	var g := terrain.floor_at(np + Vector3(0, 0.7, 0))
	# Уступ выше колена за шаг или порода на уровне груди — не пройти.
	if (g - robot.position.y) > maxf(terrain.style.step_height(), d.length() * 1.6) or terrain.solid(np.x, g + 1.2, np.z):
		vel *= 0.3
		return
	robot.position.x = np.x
	robot.position.z = np.z
	_settle()

func _settle() -> void:
	var g := terrain.floor_at(robot.position + Vector3(0, 0.6, 0))
	robot.position.y = lerpf(robot.position.y, g, 0.5)

func _follow_route() -> Vector3:
	if route_i >= route.size():
		return Vector3.ZERO
	var tgt: Vector3 = route[route_i]
	var to := Vector3(tgt.x - robot.position.x, 0, tgt.z - robot.position.z)
	if to.length() < 0.8:
		route_done += Vector2(route[route_i].x, route[route_i].z).distance_to(Vector2(route[route_i - 1].x, route[route_i - 1].z))
		route_i += 1
		return _follow_route()
	return to.normalized()

## Под сводом: фара, тёмный плотный туман; под небом — как было.
func _underground(dt: float) -> void:
	var p := robot.position + Vector3(0, 1.5, 0)
	var u := 1.0 - terrain.sky_vis(p)
	under = move_toward(under, u, dt * 1.5)
	var lamp := robot.find_child("head_lamp", true, false) as SpotLight3D
	if lamp:
		lamp.light_energy = 4.0 * under
	var eye := robot.find_child("eye_light", true, false) as OmniLight3D
	if eye:
		eye.light_energy = 1.0 * under
		eye.omni_range = 5.0
	env.fog_light_color = fog_out.lerp(Color(0.04, 0.045, 0.055), under)
	env.fog_density = lerpf(fog_out_d, 0.06, under)

## Точка прицела: луч из камеры до породы (не дальше 14 м).
func _aim_point() -> Vector3:
	var from := cam.global_position
	var dir := -cam.global_transform.basis.z
	var t := 1.0
	while t < 14.0:
		var q := from + dir * t
		if terrain.solid(q.x, q.y, q.z):
			return q - dir * 0.15
		t += 0.2
	return Vector3.INF

## Камера на пружинной штанге: не заходит в породу.
func _camera() -> void:
	var pivot := robot.position + Vector3(0, 1.6, 0)
	var dir := Basis(Vector3.UP, cam_yaw) * Basis(Vector3.RIGHT, cam_pitch) * Vector3(0, 0, -1)
	var dist := cam_dist * lerpf(1.0, 0.8, under)
	var want := pivot + dir * dist + Basis(Vector3.UP, cam_yaw) * Vector3(-0.7, 0, 0)
	var d := want - pivot
	var steps := int(d.length() / 0.15) + 1
	var last := pivot
	for i in range(1, steps + 1):
		var q := pivot + d * (float(i) / steps)
		if terrain.solid(q.x, q.y, q.z) or terrain.solid(q.x, q.y + 0.3, q.z):
			last -= d.normalized() * 0.15
			break
		last = q
	cam.position = cam.position.lerp(last, 0.35) if cam.position.distance_to(last) < 3.0 else last
	cam.look_at(pivot + Basis(Vector3.UP, cam_yaw) * Vector3(0, -0.2, 1.5))

func _route_shots() -> void:
	if shot_prefix == "" or shot_n >= shots.size():
		return
	var done := route_done
	if route_i < route.size():
		var a: Vector3 = route[route_i - 1]
		var b: Vector3 = route[route_i]
		var leg := Vector2(b.x, b.z).distance_to(Vector2(a.x, a.z))
		done += clampf(leg - Vector2(b.x, b.z).distance_to(Vector2(robot.position.x, robot.position.z)), 0.0, leg)
	var frac := done / maxf(route_len, 0.01)
	if route_i >= route.size():
		frac = 1.0
	if frac >= shots[shot_n]:
		var path := "%s_%d.png" % [shot_prefix, shot_n + 1]
		get_viewport().get_texture().get_image().save_png(path)
		print("кадр маршрута: ", path)
		shot_n += 1
		if shot_n >= shots.size():
			get_tree().quit(0)
