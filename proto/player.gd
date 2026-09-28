class_name ProtoPlayer
extends Node
## Управление роботом от третьего лица в предпросмотре (--play) и скриптовый
## маршрут для проверки (--auto=cave).
##   WASD — ходьба относительно камеры, Shift — бег, Пробел — прыжок (в режиме
##   стройки Пробел ставит деталь). Камера — мышью: курсор захвачен, клик —
##   захватить снова, Esc / Start — меню управления (без захвата крутит мышь с правой
##   кнопкой, ещё Q/E), колесо — дистанция. F или правый курок (действие
##   tool_work, держать) — работать инструментом: бур выдвигается из правого
##   предплечья, отпустить — уходит. У друзы бур выбуривает кристаллы (ProtoMining).
##   G — выстрелить кистью туда, куда смотрит камера, и подтянуться (G ещё
##   раз — отпустить).
##   Геймпад: левый стик — ходьба, правый — камера, L3 — бег, A — прыжок, RT — бур,
##   LT — кисть, D-pad вверх/вниз — дистанция (раскладка — ProtoControls).
## Скорость хода, высота уступа и прыжка зависят от гравитации планеты.
## Высота под ногами — по видимой сетке рельефа и верху деталей завода
## (RobotGround: стопы по склону, корпус с лёгким наклоном), в породу, в машины
## и на слишком крутые уступы не заходит. Камера на пружинной штанге. Под сводом сама
## включает фару и сгущает тёмный туман.
## В жидкости (ProtoSwim): всплывает или тонет по отношению плотностей жидкости и
## робота, вязкость тормозит шаг и качку, река сносит по течению. Плывя, Прыжок
## (держать) — грести вверх, Бег — нырнуть; у берега выбирается сам.

var robot: Node3D
var anim: RobotAnim
var ground: RobotGround      # стопы и наклон по сетке рельефа
var cam: Camera3D
var terrain: ProtoTerrain
var env: Environment
var fog_out := Color()
var fog_out_d := 0.0

var cam_yaw := 0.0
var cam_pitch := 0.28          # > 0 — камера над роботом, смотрит вниз
var cam_dist := 4.6
var vel := Vector3.ZERO
var under := 0.0             # 0 — под небом, 1 — под сводом (сглажено)
var vy := 0.0                # вертикальная скорость в прыжке/падении
var air := false             # в воздухе: высоту задаёт vy, а не пол
var swim := false            # в жидкости и не на дне (плывёт; высоту задаёт vy)
var wet := {}                # жидкость под роботом (ProtoHealth.liquid_at): sub, depth, zone
var wet_f := 0.0             # доля робота под поверхностью, 0..1
var buoy := 0.0              # плотность жидкости / плотность робота: > 1 — всплывает
var visc := 0.0              # вязкость жидкости (ProtoSwim.viscosity)
var swim_in := 0.0           # гребок: +1 вверх (Прыжок), −1 вниз (Бег)
var swim_hold := 0.0         # скриптовый гребок (проверки)
var capture := false         # --play: захватывать курсор для камеры мышью
var _captured_once := false
var _resume_capture := false

const SPRINT_MULT := 2.3     # бег — во столько раз быстрее шага
const G := 14.0              # м/с² при 1 g (чуть «игровее» настоящих 9.8)
const JUMP_V := 5.5          # м/с при отрыве: ≈1.1 м на 1 g (выше трубы), на лёгкой планете выше
const JUMP_MAX_H := 2.4      # потолок высоты прыжка на совсем лёгкой планете
const PITCH_MIN := -0.6
const PITCH_MAX := 1.2

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
var digger: ProtoDigger        # бур без кристалла копает грунт, H / D-pad влево — насыпь
var fill_auto := false         # проверки: насыпать без кнопки
var health: ProtoHealth       # прочность корпуса: удар при приземлении, вязкость жидкости

# Скриптовая добыча (--auto=drill).
var drill_auto := false
var drill_stand := Vector3.INF
var drill_face := Vector3.ZERO
var drill_t := 0.0
var drill_got := 0
var drill_shots := 0
var drill_prefix := ""
# Скриптовый разбег с прыжком (--auto=jump): кадры бег, взлёт, вершина, приземление.
var jump_auto := false
var jump_t := 0.0
var jump_prefix := ""
var jump_shots := 0
var _was_air := false
# Проверка столкновений (--auto=bump): упереться в дробилку, перешагнуть трубу.
var bump_view: ProtoPneumaticsView
var bump_t := 0.0
var bump_prefix := ""
var bump_min := INF
var bump_top := -INF
var bump_shot2 := false
var bump_jumped := false
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
	process_mode = Node.PROCESS_MODE_ALWAYS   # следит за курсором и на паузе

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

## Ввод (x — вправо, y — вперёд) → направление в мире для камеры с рысканием yaw.
## Длина inp — наклон стика (клавиши дают 1): лёгкий наклон — медленный шаг.
static func move_dir(yaw: float, inp: Vector2) -> Vector3:
	var fwd := Vector3(sin(yaw), 0, cos(yaw))
	# Право на экране: камера смотрит вдоль fwd, значит право — fwd × вверх.
	var right := fwd.cross(Vector3.UP)
	return (fwd * inp.y + right * inp.x).normalized() * minf(1.0, inp.length())

## Вернуть захват курсора (после меню).
func recapture() -> void:
	if capture:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

## Камера мышью: при захваченном курсоре — всегда, без захвата — с правой кнопкой.
## Клик — захватить курсор; отпускает его меню управления (Esc, ProtoControlsMenu).
func _unhandled_input(e: InputEvent) -> void:
	if get_tree().paused:
		return
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if e is InputEventMouseMotion and (captured or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)):
		var d := ProtoControls.mouse_look(e.relative)
		cam_yaw += d.x
		cam_pitch = clampf(cam_pitch + d.y, PITCH_MIN, PITCH_MAX)
	elif e is InputEventMouseButton and e.pressed:
		if e.button_index == MOUSE_BUTTON_LEFT and capture and not captured:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			get_viewport().set_input_as_handled()
		elif e.button_index == MOUSE_BUTTON_WHEEL_UP:
			cam_dist = maxf(2.0, cam_dist - 0.4)
		elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			cam_dist = minf(12.0, cam_dist + 0.4)

func _process(dt: float) -> void:
	# Идёт и на паузе (process_mode ALWAYS): пока открыто окно или карточка,
	# курсор свободен; закрылись — снова захвачен.
	if get_tree().paused or robot.get_meta("ui_busy", false):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			_resume_capture = true
		if get_tree().paused:
			return
	elif _resume_capture:
		_resume_capture = false
		recapture()
	dt = minf(dt, 0.25)
	if bump_view != null or jump_auto:
		dt = minf(dt, 1.0 / 30.0)   # проверки: шаг не зависит от того, как тянет машина
	if capture and not _captured_once and route.is_empty() and not drill_auto:
		_captured_once = true
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var want := Vector3.ZERO
	_liquid_state()
	swim_in = swim_hold
	# Тяжёлая планета — шаг медленнее, лёгкая — быстрее (ProtoWorldStyle).
	var top_speed := RobotAnim.WALK_SPEED * terrain.style.walk_mult()
	# Открыта карточка материала (ProtoLabPanel): стик и D-pad заняты ею.
	var busy: bool = robot.get_meta("ui_busy", false) or robot.get_meta("wrecked", false)
	if route.is_empty() and busy:
		pass
	elif route.is_empty():
		var inp := ProtoControls.move_vector()
		var look := ProtoControls.look_vector()
		# Стик вверх — смотреть вверх: камера опускается за спину.
		cam_yaw -= look.x * dt * 2.4
		cam_pitch = clampf(cam_pitch - look.y * dt * 1.6, PITCH_MIN, PITCH_MAX)
		if Input.is_action_pressed(ProtoControls.CAM_ZOOM_IN): cam_dist = maxf(2.0, cam_dist - dt * 4.0)
		if Input.is_action_pressed(ProtoControls.CAM_ZOOM_OUT): cam_dist = minf(12.0, cam_dist + dt * 4.0)
		if swim:
			# Плывя: Прыжок — грести вверх, Бег — нырнуть.
			swim_in = clampf(swim_hold + Input.get_action_strength(ProtoControls.JUMP) - Input.get_action_strength(ProtoControls.SPRINT), -1.0, 1.0)
		elif Input.is_action_pressed(ProtoControls.SPRINT):
			top_speed *= SPRINT_MULT
		if Input.is_action_just_pressed(ProtoControls.JUMP) and _can_jump():
			jump()
		if bump_view != null:
			inp = Vector2(0, 1)
			if bump_t > 4.0:
				top_speed *= SPRINT_MULT
			_auto_bump(dt)
		if jump_auto:
			inp = Vector2(0, 1)
			top_speed *= SPRINT_MULT
			_auto_jump(dt)
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
			want = move_dir(cam_yaw, inp)
		if drill_auto:
			want = _auto_drill_walk()
	else:
		want = _follow_route()
		top_speed *= 1.7
		if finale >= 0.0 and route_i >= route.size():
			_finale(dt)
	# В жидкости вязнет: чем глубже и гуще, тем медленнее.
	if wet_f > 0.0:
		top_speed *= ProtoSwim.speed_mult(visc, wet_f)
	# Подтягивание: трос тянет робота к кисти.
	if fist and fist.state == "pull":
		var tw := robot.to_global(fist.target)
		var to := tw - robot.position
		if Vector2(to.x, to.z).length() > 1.0:
			want = Vector3(to.x, 0, to.z).normalized()
			top_speed = 2.6
		else:
			fist.release()
	# В воздухе разгон слабее: направление прыжка почти не поменять.
	var acc := 1.2 if air else 3.0 * terrain.style.walk_mult()
	if swim:
		acc = 2.0 / (1.0 + visc * 0.3)
	vel = vel.move_toward(want * top_speed, dt * acc)
	_move((vel + _drift()) * dt)
	_vertical(dt)
	if vel.length() > 0.05:
		robot.rotation.y = lerp_angle(robot.rotation.y, atan2(vel.x, vel.z), minf(1.0, dt * 6.0))
		if not route.is_empty():
			cam_yaw = lerp_angle(cam_yaw, robot.rotation.y, minf(1.0, dt * 2.0))
	if anim:
		anim.speed = Vector2(vel.x, vel.z).length()
		anim.speed_ref = terrain.style.walk_mult()
		anim.airborne = air and wet_f < 0.25    # плывёт — не поза прыжка
		anim.vy = vy
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
	if digger != null:
		var building := false
		var b := get_parent().get_node_or_null("builder") if get_parent() else null
		if b != null:
			building = bool(b.get("active"))
		var busy: bool = robot.get_meta("ui_busy", false) or get_tree().paused
		var digging := mining.target == null and anim.work > 0.6 and anim.drill_out > 0.95
		var fill := fill_auto or (not busy and not building and Input.is_action_pressed(ProtoDigger.FILL))
		digger.step(dt, digging, fill)
		if mining.target == null and anim.work > 0.05:
			anim.work_target = robot.to_local(digger.dig_point())
			if digging:
				mining.sparks.global_position = digger.dig_point()
				mining.crumbs.global_position = digger.dig_point()
				mining.crumbs.emitting = true
			return
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
				near = minf(near, ProtoMining.reach_dist(k, sh))
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
	var g := ground_at(np + Vector3(0, 0.7, 0))
	# Уступ выше колена за шаг, порода на уровне груди или машина — не пройти
	# (в прыжке — порода на уровне ног или груди там, где робот сейчас).
	var body := maxf(g, robot.position.y)
	# Плывя — выбирается на берег до пояса.
	var step := 1.1 if swim else maxf(terrain.style.step_height(), d.length() * 1.6)
	if (g - robot.position.y) > step or terrain.solid(np.x, body + 1.2, np.z) \
			or (air and terrain.solid(np.x, robot.position.y + 0.3, np.z)) or (_hits_machine(Vector3(np.x, body, np.z)) and not _hits_machine(robot.position)):
		# Скриптовый маршрут упёрся в уступ (не в породу и не в машину) — перескочить,
		# как сделал бы игрок: иначе проверка (--auto=cave, bench) стоит вечно.
		if not route.is_empty() and not air and g - robot.position.y < JUMP_MAX_H \
				and not terrain.solid(np.x, body + 1.2, np.z) and not _hits_machine(Vector3(np.x, body, np.z)):
			jump()
		vel *= 0.3
		return
	robot.position.x = np.x
	robot.position.z = np.z
	if swim and g > robot.position.y - 0.02 and vy <= 0.5:
		_land(g, 0.0)
		return
	_settle()

## Высота и наклон — по видимой сетке рельефа (RobotGround); поле плотности —
## запасной вариант, если сетки под роботом нет.
func _settle() -> void:
	if air:
		return
	var g := ground_at(robot.position + Vector3(0, 0.6, 0))
	# Пол ушёл вниз больше чем на уступ — не «съезжать», а падать.
	if robot.position.y - g > terrain.style.step_height() * 1.5 + 0.2:
		air = true
		vy = 0.0
		return
	if ground:
		ground.place(g)
	else:
		robot.position.y = lerpf(robot.position.y, g, 0.5)

## Разбег по площадке завода боком к камере; прыжок на 2.4 с.
func auto_jump(prefix: String) -> void:
	jump_prefix = prefix
	jump_auto = true
	# Самая ровная 9-метровая дорожка в стороне от завода, и чтобы сбоку (со стороны
	# камеры) рельеф не загораживал.
	var pc := terrain.plateau()
	var best := INF
	var st := pc
	var yaw := 0.0
	for k in 16:
		var ang := TAU * k / 16.0
		var f := Vector3(sin(ang), 0, cos(ang))
		var side := Basis(Vector3.UP, ang - 1.35) * Vector3(0, 0, -1)
		for r: float in [9.0, 11.0, 13.0, 15.0]:
			var p0 := pc + Vector3(sin(ang + 2.0), 0, cos(ang + 2.0)) * r
			var h0 := terrain.surface_h(p0.x, p0.z)
			var cost := 0.0
			for i in 10:
				var q := p0 + f * i
				cost += absf(terrain.surface_h(q.x, q.z) - h0)
				# Не через завод и не в воду.
				cost += 20.0 if Vector2(q.x - pc.x, q.z - pc.z).length() < 8.0 else 0.0
				cost += 20.0 if terrain.solid(q.x, h0 + 1.0, q.z) else 0.0
				var c := q + side * 5.0
				cost += maxf(0.0, terrain.surface_h(c.x, c.z) - h0 - 1.0) * 0.5
			if cost < best:
				best = cost
				st = p0
				yaw = ang
	robot.position = Vector3(st.x, terrain.surface_h(st.x, st.z), st.z)
	robot.rotation.y = yaw
	cam_yaw = yaw
	cam_dist = 5.5
	cam_pitch = 0.3

func _auto_jump(dt: float) -> void:
	jump_t += dt
	# Камера сбоку, идёт вдоль разбега.
	cam_yaw = robot.rotation.y - 1.35
	cam_focus = robot.position + Vector3(0, 1.1, 0)
	if jump_t > 2.4 and jump_t < 2.5 and _can_jump():
		jump()
	var shot := ""
	if jump_shots == 0 and jump_t > 2.2:
		shot = "бег"
	elif jump_shots == 1 and air and vy < 2.6:
		shot = "взлёт"
	elif jump_shots == 2 and air and vy < 0.0:
		shot = "вершина"
	elif jump_shots == 3 and _was_air and not air:
		shot = "приземление"
	_was_air = air
	if shot != "":
		jump_shots += 1
		var path := "%s_%d.png" % [jump_prefix, jump_shots]
		get_viewport().get_texture().get_image().save_png(path)
		print("кадр прыжка (%s): %s" % [shot, path])
		if jump_shots >= 4:
			get_tree().quit(0)
	if jump_t > 8.0:
		print("Прыжок: время вышло")
		get_tree().quit(1)

const BODY_R := 0.3          # радиус корпуса для столкновений с машинами

## Пол под точкой p: первая видимая поверхность вниз — сетка рельефа, настил,
## деталь завода (тела ProtoMachines); если тел нет — по полю плотности.
func ground_at(p: Vector3) -> float:
	var w := robot.get_world_3d() if robot and robot.is_inside_tree() else null
	if w != null:
		var q := PhysicsRayQueryParameters3D.create(p, p - Vector3(0, 8.0, 0),
			ProtoMachines.LAYER_GROUND | ProtoMachines.LAYER_MACHINES)
		var hit := w.direct_space_state.intersect_ray(q)
		if not hit.is_empty():
			return hit.position.y
	return terrain.floor_at(p)

## Корпус (шары у ног, у пояса и у груди) в машине — не пройти.
func _hits_machine(at: Vector3) -> bool:
	var w := robot.get_world_3d() if robot and robot.is_inside_tree() else null
	if w == null:
		return false
	var sp := SphereShape3D.new()
	sp.radius = BODY_R - 0.02
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = sp
	q.collision_mask = ProtoMachines.LAYER_MACHINES
	for h: float in [0.35, 0.8, 1.35]:
		q.transform = Transform3D(Basis(), at + Vector3(0, h, 0))
		if not w.direct_space_state.intersect_shape(q, 1).is_empty():
			return true
	return false

## Скрипт столкновений: робот идёт на дробилку (клетка 0,0 демо-завода) —
## должен остановиться у корпуса; потом бежит на трубу (1,0): она по пояс,
## перешагнуть нельзя — перепрыгивает. Кадры путь_1/2.png, итог в консоль.
func auto_bump(view: ProtoPneumaticsView, prefix: String) -> void:
	bump_view = view
	bump_prefix = prefix
	_bump_start(Vector2i(0, 0))

func _bump_start(c: Vector2i) -> void:
	var at := ProtoPneumatics.cell_pos(bump_view.origin, c)
	robot.position = Vector3(at.x, at.y + 0.3, at.z + 3.6)
	robot.position.y = ground_at(robot.position + Vector3(0, 1.0, 0))
	robot.rotation.y = PI
	cam_yaw = PI           # вперёд — на −z, к линии завода
	cam_pitch = 0.35
	cam_dist = 4.5
	vel = Vector3.ZERO

func _auto_bump(dt: float) -> void:
	bump_t += dt
	var crusher := ProtoPneumatics.cell_pos(bump_view.origin, Vector2i(0, 0))
	var pipe := ProtoPneumatics.cell_pos(bump_view.origin, Vector2i(1, 0))
	if bump_t < 4.0:
		bump_min = minf(bump_min, Vector2(robot.position.x - crusher.x, robot.position.z - crusher.z).length())
		if bump_t + dt >= 4.0:
			_shot("%s_1.png" % bump_prefix)
			bump_jumped = false
			_bump_start(Vector2i(1, 0))
	elif bump_t < 9.0:
		if robot.position.z - pipe.z < 1.15 and robot.position.z > pipe.z and not bump_jumped and _can_jump():
			bump_jumped = true
			jump()
		if absf(robot.position.z - pipe.z) < 0.3:
			bump_top = maxf(bump_top, robot.position.y - pipe.y)
			if bump_top > 0.05 and not bump_shot2:
				bump_shot2 = true
				_shot("%s_2.png" % bump_prefix)
	else:
		var passed := robot.position.z < pipe.z - 1.0
		if not passed:
			_shot("%s_fail.png" % bump_prefix)   # где застрял
			print("Столкновения: робот на ", robot.position, ", труба ", pipe)
		print("Столкновения: до дробилки %.2f м (упёрся: %s); над трубой +%.2f м, перепрыгнул: %s" % [
			bump_min, "да" if bump_min > 0.9 else "НЕТ", bump_top, "да" if passed else "НЕТ"])
		get_tree().quit(0 if bump_min > 0.9 and passed else 1)

func _shot(path: String) -> void:
	get_viewport().get_texture().get_image().save_png(path)
	print("кадр: ", path)

## Прыгать можно с земли и когда руки свободны: не в стройке, не на тросе, не с буром.
func _can_jump() -> bool:
	if air or not route.is_empty() or drill_auto:
		return false
	var b := get_parent().get_node_or_null("builder")
	if b != null and b.get("active"):
		return false
	if fist and fist.state == "pull":
		return false
	return anim == null or anim.work < 0.3

## Прыжок: скорость отрыва одна, высота — от гравитации (на лёгкой выше).
func jump() -> void:
	var g := G * terrain.style.gravity
	vy = minf(JUMP_V, sqrt(2.0 * g * JUMP_MAX_H))
	air = true
	robot.position.y += 0.02

## Полёт и плавание: тяжесть, выталкивание и вязкость жидкости (ProtoSwim),
## гребок, удар головой о свод, приземление на пол (или на дно).
func _vertical(dt: float) -> void:
	if not air:
		return
	var g0 := G * terrain.style.gravity
	if wet_f > 0.0:
		var a := ProtoSwim.accel(g0, buoy, wet_f, 0.0, 0.0)
		if swim_in != 0.0:
			a += g0 * (ProtoSwim.SWIM_UP if swim_in > 0.0 else ProtoSwim.SWIM_DOWN) * swim_in * clampf(wet_f * 2.0, 0.0, 1.0)
		# Вязкость — неявно: устойчиво и при густой лаве и большом шаге.
		vy = (vy + a * dt) / (1.0 + visc * wet_f * dt)
	else:
		vy -= g0 * dt
	var p := robot.position
	if vy > 0.0 and terrain.solid(p.x, p.y + 2.0 + vy * dt, p.z):
		vy = 0.0
	robot.position.y += vy * dt
	var g := ground_at(robot.position + Vector3(0, 0.6, 0))
	if vy <= 0.0 and robot.position.y <= g:
		_land(g, -vy)

## Встал на пол (или на дно, или выбрался на берег): v — скорость удара вниз.
func _land(g: float, v: float) -> void:
	robot.position.y = g
	air = false
	swim = false
	if ground:
		ground.snap(g)
	if anim:
		anim.land = clampf(v / 6.0, 0.25, 1.0)
	if health != null:
		health.landed(v)
	vy = 0.0

## Жидкость под роботом: погружение, плотность, вязкость. На дне в жидкости
## плотнее робота — отрывается и всплывает.
func _liquid_state() -> void:
	wet = health.liquid_at(robot.position) if health != null else {}
	var s: Substance = wet.get("sub")
	wet_f = ProtoSwim.submerged(wet.get("depth", 0.0))
	visc = ProtoSwim.viscosity(s)
	buoy = ProtoSwim.ratio(s, ProtoSwim.robot_density(health.hull if health != null else null, _cargo_mass())) if s != null else 0.0
	if not air and wet_f > 0.0 and buoy * wet_f > 1.0:
		air = true
		vy = 0.0
	swim = air and wet_f > 0.05
	robot.set_meta("swim", swim)

## Снос течением (зона жидкости с flow — река): на плаву сильнее, на дне слабее.
func _drift() -> Vector3:
	if wet_f <= 0.0 or not wet.has("zone"):
		return Vector3.ZERO
	var fl = wet.zone.get("flow")
	if not (fl is Callable):
		return Vector3.ZERO
	var d: Vector3 = fl.call(robot.position.x, robot.position.z)
	return d * ProtoSwim.flow_speed(visc) * wet_f * (1.0 if swim else 0.35)

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

## Под сводом: фара, тёмный плотный туман; под небом — как было (ночью — с фарой).
func _underground(dt: float) -> void:
	var p := robot.position + Vector3(0, 1.5, 0)
	var u := 1.0 - terrain.sky_vis(p)
	under = move_toward(under, u, dt * 1.5)
	# Ночью фара горит и под открытым небом (ProtoDayNight).
	var dn := ProtoDayNight.of(robot)
	var dark := maxf(under, dn.night * 0.8 if dn != null else 0.0)
	if dn != null:
		fog_out = dn.fog_color
	var lamp := robot.find_child("head_lamp", true, false) as SpotLight3D
	if lamp:
		lamp.light_energy = 4.0 * dark
	var eye := robot.find_child("eye_light", true, false) as OmniLight3D
	if eye:
		eye.light_energy = 1.0 * dark
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
