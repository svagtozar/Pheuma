class_name ProtoPlayer
extends Node
## Управление роботом от третьего лица в предпросмотре (--play) и скриптовый
## маршрут для проверки (--auto=cave).
##   WASD — ходьба относительно камеры, Shift — быстрее, Q/E или мышь с правой
##   кнопкой — поворот камеры, колесо — дистанция. F или правый курок (действие
##   tool_work, держать) — работать инструментом: бур выдвигается из правого
##   предплечья, отпустить — уходит. У друзы бур выбуривает кристаллы (ProtoMining).
##   G — выстрелить кистью туда, куда смотрит камера, и подтянуться (G ещё
##   раз — отпустить).
##   Геймпад: левый стик — ходьба, правый — камера, L3 — быстрее, RT — бур,
##   LT — кисть, D-pad вверх/вниз — дистанция (раскладка — ProtoControls).
## Скорость хода и высота уступа зависят от гравитации планеты.
## Высота под ногами — по видимой сетке рельефа (RobotGround: стопы по склону,
## корпус с лёгким наклоном), в породу и на слишком крутые уступы не заходит. Камера на пружинной штанге. Под сводом сама
## включает фару и сгущает тёмный туман.

var robot: Node3D
var anim: RobotAnim
var ground: RobotGround      # стопы и наклон по сетке рельефа
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
var mining: ProtoMining

# Скриптовая добыча (--auto=drill).
var drill_auto := false
var drill_stand := Vector3.INF
var drill_face := Vector3.ZERO
var drill_t := 0.0
var drill_got := 0
var drill_shots := 0
var drill_prefix := ""
var cam_focus := Vector3.INF # точка, на которую смотрит камера (скрипт добычи); INF — на робота
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
	ground = RobotGround.attach(robot)
	cam_yaw = robot.rotation.y
	fist = robot.get_node_or_null("fist")
	ProtoControls.ensure()
	ProtoMining.ensure_action()

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
	# Открыта карточка материала (ProtoLabPanel): стик и D-pad заняты ею.
	var busy: bool = robot.get_meta("ui_busy", false)
	if route.is_empty() and busy:
		pass
	elif route.is_empty():
		var inp := ProtoControls.move_vector()
		var look := ProtoControls.look_vector()
		cam_yaw -= look.x * dt * 2.4
		cam_pitch = clampf(cam_pitch + look.y * dt * 1.6, -1.1, 0.2)
		if Input.is_action_pressed(ProtoControls.CAM_ZOOM_IN): cam_dist = maxf(2.0, cam_dist - dt * 4.0)
		if Input.is_action_pressed(ProtoControls.CAM_ZOOM_OUT): cam_dist = minf(12.0, cam_dist + dt * 4.0)
		if Input.is_action_pressed(ProtoControls.SPRINT): top_speed *= 1.9
		if drill_auto:
			inp = Vector2.ZERO
		if anim:
			var use := Input.get_action_strength(ProtoControls.WORK)
			if drill_auto and _auto_drill_use():
				use = 1.0
			anim.work = move_toward(anim.work, use, dt * 5.0)
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
		if drill_auto:
			want = _auto_drill_walk()
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
	_mine(dt)
	_underground(dt)
	_camera()
	_route_shots()

## Добыча: цель бура, рука к ней, робот доворачивается к кристаллу.
func _mine(dt: float) -> void:
	if mining == null or anim == null:
		return
	var tip_n := robot.find_child("drill_tip", true, false) as Node3D
	var tip := tip_n.global_position if tip_n and anim.drill_out > 0.5 else Vector3.INF
	mining.step(dt, robot, anim.work, anim.drill_out, tip)
	if mining.target and anim.work > 0.05:
		anim.work_target = robot.to_local(mining.contact)
		# Доворот — по основанию кристалла (точка касания сама зависит от позы).
		var to: Vector3 = ProtoMining.axis(mining.target)[0].lerp(mining.contact, 0.5) - robot.position
		# Только пока бур выдвигается: во время сверления корпус не крутится.
		if vel.length() < 0.1 and anim.drill_out < 0.95 and Vector2(to.x, to.z).length() > 0.3:
			# Доворот плечом к кристаллу: бур в правой руке.
			var yaw := atan2(to.x, to.z) - 0.25
			robot.rotation.y = lerp_angle(robot.rotation.y, yaw, minf(1.0, dt * 4.0))
		if vel.length() < 0.1 and tip != Vector3.INF and anim.drill_out > 0.95:
			# Налегает на бур: подшагивает, пока острие не упрётся в кристалл.
			var gap := Vector3(mining.contact.x - tip.x, 0, mining.contact.z - tip.z)
			if gap.length() > 0.05 and Vector2(to.x, to.z).length() > 0.35:
				_move(gap.normalized() * minf(gap.length() - 0.04, dt * 0.5))
	else:
		anim.work_target = Vector3.INF

## Скриптовая добыча: выбрать друзу у пола, подойти, бурить, кадры по событиям.
func auto_drill(prefix: String) -> void:
	drill_prefix = prefix
	drill_auto = true
	cam_dist = 4.8
	cam_pitch = 0.42   # штанга вверх: камера над друзой
	var cands := []
	for d in mining.druses:
		var nrm: Vector3 = d.node.get_meta("normal")
		var c: MeshInstance3D = d.crystals[0]
		var base: Vector3 = c.global_position
		var flat := Vector3(nrm.x, 0, nrm.z)
		if flat.length() < 0.3:
			flat = Vector3(terrain.cave_c.x - base.x, 0, terrain.cave_c.z - base.z)
		flat = flat.normalized()
		# Встать сразу за самым дальним кристаллом друзы, чтобы не стоять внутри неё.
		var ext := 0.0
		for k: MeshInstance3D in d.crystals:
			for q: Vector3 in ProtoMining.axis(k):
				ext = maxf(ext, (q - base).dot(flat))
		for off: float in [ext + 0.35, ext + 0.5, ext + 0.65]:
			var sp: Vector3 = base + flat * off
			sp.y = terrain.floor_at(sp + Vector3(0, 1.0, 0))
			var h := base.y - sp.y
			if h < -0.3 or h > 1.1 or terrain.solid(sp.x, sp.y + 1.2, sp.z):
				continue
			# Хоть один кристалл друзы должен доставать бур с этой стоянки.
			var sh := sp + Vector3(0, 1.4, 0)
			var near := INF
			for k: MeshInstance3D in d.crystals:
				near = minf(near, sh.distance_to(ProtoMining.nearest_on(k, sh)))
			if near > ProtoMining.REACH - 0.1:
				continue
			# Крупная друза смотрится лучше мелкой.
			cands.append([absf(h - 0.3) + off * 0.5 - float(c.get_meta("len")) * 0.8, sp, base])
			break
	cands.sort_custom(func(x, y): return x[0] < y[0])
	# Первая друза, к которой есть чистый ракурс камеры.
	for cd in cands:
		drill_stand = cd[1]
		drill_face = cd[2]
		if _drill_view(cd[1], cd[2]) != INF:
			break
	var f := Vector3(drill_face.x - drill_stand.x, 0, drill_face.z - drill_stand.z).normalized()
	# Старт — в паре метров позади, чтобы видно было подход.
	var st := drill_stand - f * 2.2
	robot.position = Vector3(st.x, terrain.floor_at(st + Vector3(0, 1.0, 0)), st.z)
	robot.rotation.y = atan2(f.x, f.z)
	_auto_drill_camera()
	print("Добыча: стоянка ", drill_stand, " друза ", drill_face)

func _auto_drill_walk() -> Vector3:
	if mining.target != null and drill_shots > 0:
		return Vector3.ZERO
	var to := Vector3(drill_stand.x - robot.position.x, 0, drill_stand.z - robot.position.z)
	if to.length() > 0.12:
		return to.normalized()
	# На месте, цели нет — повернуться к друзе.
	var f := drill_face - robot.position
	robot.rotation.y = lerp_angle(robot.rotation.y, atan2(f.x, f.z), minf(1.0, get_process_delta_time() * 4.0))
	return Vector3.ZERO

func _at_stand() -> bool:
	return Vector2(drill_stand.x - robot.position.x, drill_stand.z - robot.position.z).length() < 0.2

## Камера для кадров добычи: смотрит между роботом и друзой, сбоку со стороны
## бура; из нескольких ракурсов — первый, где штанга не упирается в породу.
func _auto_drill_camera() -> void:
	var yaw := _drill_view(drill_stand, drill_face)
	var rd := drill_face - drill_stand
	cam_yaw = yaw if yaw != INF else atan2(rd.x, rd.z) - 2.0
	cam_focus = drill_stand.lerp(drill_face, 0.6) + Vector3(0, 0.6, 0)

## Ракурс (yaw камеры) для стоянки sp у друзы at; INF — чистого нет.
func _drill_view(sp: Vector3, at: Vector3) -> float:
	var rd := at - sp
	var base := atan2(rd.x, rd.z)
	var focus := sp.lerp(at, 0.45) + Vector3(0, 0.7, 0)
	for off: float in [-2.0, -1.7, -2.3, -1.4, -1.1, 2.0, 1.4, 0.0]:
		var b := Basis(Vector3.UP, base + off)
		var dir := b * Basis(Vector3.RIGHT, cam_pitch) * Vector3(0, 0, -1)
		var ok := true
		for i in range(4, 21):
			var q := focus + (dir * cam_dist + b * Vector3(-0.7, 0, 0)) * (i / 20.0)
			if terrain.solid(q.x, q.y, q.z) or terrain.solid(q.x, q.y + 0.3, q.z) or terrain.solid(q.x, q.y - 0.4, q.z):
				ok = false
				break
		if ok:
			return base + off
	return INF

func _auto_drill_use() -> bool:
	var at := _at_stand()
	drill_t += get_process_delta_time()
	var shot := ""
	if drill_shots == 0 and at and mining.target and cam_focus != Vector3.INF and drill_t > 1.5:
		shot = "прицел"
	elif drill_shots == 1 and mining.progress > 0.55:
		shot = "бурение"
	elif drill_shots == 2 and not mining.falling.is_empty() and mining.falling[0].t > 0.2:
		shot = "откол"
	elif drill_shots == 3 and _cargo_mass() > 0.0 and drill_got >= 3 and mining.falling.is_empty():
		shot = "груз"
	if shot != "":
		drill_shots += 1
		var path := "%s_%d.png" % [drill_prefix, drill_shots]
		get_viewport().get_texture().get_image().save_png(path)
		print("кадр добычи (%s): %s" % [shot, path])
		if drill_shots >= 4:
			get_tree().quit(0)
	if drill_t > 40.0:
		print("Добыча: время вышло, собрано ", _cargo_mass())
		get_tree().quit(1)
	# Первый кадр — прицел без бура; дальше бурим, пока не отколется три кристалла.
	if drill_shots == 0:
		return false
	drill_got = 0
	for d in mining.druses:
		for c in d.crystals:
			if c == null or not is_instance_valid(c) or c.has_meta("broken"):
				drill_got += 1
	return drill_got < 3

func _cargo_mass() -> float:
	var m := 0.0
	for p: Portion in ProtoMining.cargo_of(robot):
		m += p.mass
	return m

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

## Высота и наклон — по видимой сетке рельефа (RobotGround); поле плотности —
## запасной вариант, если сетки под роботом нет.
func _settle() -> void:
	var g := terrain.floor_at(robot.position + Vector3(0, 0.6, 0))
	if ground:
		ground.place(g)
	else:
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
	var pivot := robot.position + Vector3(0, 1.6, 0) if cam_focus == Vector3.INF else cam_focus
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
	cam.look_at(pivot + Basis(Vector3.UP, cam_yaw) * Vector3(0, -0.2, 1.5) if cam_focus == Vector3.INF else pivot)

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
