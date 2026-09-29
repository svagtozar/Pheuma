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
##   G — выстрелить кистью в центр экрана (до HOOK_RANGE м): кисть вцепляется в
##   породу, трос втягивает робота к ней, и вверх тоже; под кромкой уступа —
##   подсаживает наверх (G ещё раз — отпустить, Пробел — отпустить с подскоком).
##   Застрял так, что не шагнуть никуда (яма после бура, засыпало) — сам выбирается.
##   Геймпад: левый стик — ходьба, правый — камера, L3 — бег (щелчок, до остановки), A — прыжок, RT — бур,
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
var sprint_latch := false    # геймпад: L3 щелчком включает бег до остановки
var hook_at := Vector3.INF   # куда вцепилась кисть (мир); INF — не вцепилась
var hook_t := 0.0            # сколько тянет трос
var mantle := Vector3.INF   # подсадка на уступ после троса: точка наверху; INF — нет
# Камера: сглаженная точка у робота и длина штанги (коротится сразу, растёт плавно).
var cam_pivot := Vector3.INF
var boom := -1.0
var boom_v := 0.0
var stuck_t := 0.0           # сколько игрок жмёт ход, а робот стоит на месте
var fov_base := -1.0

const SPRINT_MULT := 3.2     # бег — во столько раз быстрее шага
const SPRINT_ACC := 2.2      # и разгоняется во столько раз резвее
const SPRINT_FOV := 7.0      # на бегу угол камеры шире — скорость видна
const HOOK_RANGE := 20.0     # кисть-крюк достаёт до стены на столько м от робота
const HOOK_SPEED := 8.0      # м/с — трос тянет робота к кисти
const HOOK_TIME := 4.0       # дольше не тянет: застрял — отпускает
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
var aim_ui: ProtoAim           # перекрестье и шар-кисть (есть, когда играет человек)
var aim_hit := Vector3.INF     # точка породы под перекрестьем (мир); INF — не видно
var aim_goal := Vector3.INF    # скрипты (прогон, баланс): навести перекрестье на точку, как игрок
var harvest: ProtoHarvest     # срез растений тем же буром (есть, если на планете жизнь)
var health: ProtoHealth       # прочность корпуса: удар при приземлении, вязкость жидкости

# Скриптовая добыча (--auto=drill).
var drill_auto := false
var drill_stand := Vector3.INF
var drill_face := Vector3.ZERO
var drill_t := 0.0
var drill_got := 0
var drill_shots := 0
var drill_prefix := ""
var harvest_auto := false    # --auto=harvest: тот же сценарий, но срезать растения
# Скриптовый разбег с прыжком (--auto=jump): кадры бег, взлёт, вершина, приземление.
var jump_auto := false
var jump_t := 0.0
var jump_prefix := ""
var jump_shots := 0
var jump_side := 0.0         # с какой стороны разбега камера (−1.35 или 1.35)
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
		var hit := aim_point()
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
	elif e is InputEventJoypadButton and e.is_action_pressed(ProtoControls.SPRINT):
		sprint_latch = not sprint_latch
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
	var sprint := false
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
		else:
			# Стик отпущен — щелчок L3 больше не держит бег.
			if inp.length() < 0.2:
				sprint_latch = false
			if sprint_latch or Input.is_action_pressed(ProtoControls.SPRINT):
				sprint = true
				top_speed *= SPRINT_MULT
		if Input.is_action_just_pressed(ProtoControls.JUMP):
			if hook_at != Vector3.INF and fist and fist.state == "pull":
				_hook_end(true)     # прыжок с троса — отпустить с подскоком
			elif _can_jump():
				jump()
		if bump_view != null:
			inp = Vector2(0, 1)
			if bump_t > 4.0:
				sprint = true
				top_speed *= SPRINT_MULT
			_auto_bump(dt)
		if jump_auto:
			inp = Vector2(0, 1)
			sprint = true
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
				hook_fire()
			else:
				_hook_end(false)
		if inp != Vector2.ZERO:
			# Вперёд — от камеры: камера смотрит вдоль (sin yaw, cos yaw).
			want = move_dir(cam_yaw, inp)
		if drill_auto:
			want = _auto_harvest_walk() if harvest_auto else _auto_drill_walk()
	else:
		want = _follow_route()
		top_speed *= 1.7
		if finale >= 0.0 and route_i >= route.size():
			_finale(dt)
	# В жидкости вязнет: чем глубже и гуще, тем медленнее.
	if wet_f > 0.0:
		top_speed *= ProtoSwim.speed_mult(visc, wet_f)
	# В воздухе разгон слабее: направление прыжка почти не поменять.
	var acc := 1.2 if air else 3.0 * terrain.style.walk_mult() * (SPRINT_ACC if sprint else 1.0)
	if swim:
		acc = 2.0 / (1.0 + visc * 0.3)
	vel = vel.move_toward(want * top_speed, dt * acc)
	# Кисть-крюк: держит точку в мире, трос тянет робота к ней (и вверх).
	_hook(dt)
	if mantle != Vector3.INF:
		var mf := Vector3(mantle.x - robot.position.x, 0, mantle.z - robot.position.z)
		if not air or mf.length() < 0.2:
			mantle = Vector3.INF
			vel *= 0.3          # встал на уступ — не скользить дальше
		elif robot.position.y > mantle.y - 0.1:
			vel = mf.normalized() * 3.5     # над кромкой — шагнуть на уступ
		else:
			vel = Vector3.ZERO              # ещё под кромкой — вверх вдоль стены
	var was := robot.position
	_move((vel + _drift()) * dt)
	_vertical(dt)
	if route.is_empty() and not busy and not drill_auto and not jump_auto and bump_view == null:
		_unstick(dt, want, was)
	if vel.length() > 0.05:
		robot.rotation.y = lerp_angle(robot.rotation.y, atan2(vel.x, vel.z), minf(1.0, dt * 6.0))
		if not route.is_empty():
			cam_yaw = lerp_angle(cam_yaw, robot.rotation.y, minf(1.0, dt * 2.0))
	if anim:
		anim.speed = Vector2(vel.x, vel.z).length()
		anim.speed_ref = terrain.style.walk_mult()
		anim.airborne = air and wet_f < 0.25    # плывёт — не поза прыжка
		anim.vy = vy
	_aim_goal_step(dt)
	_mine(dt)
	_underground(dt)
	_camera(dt, sprint and vel.length() > top_speed * 0.6 / SPRINT_MULT)
	_route_shots()

## Добыча: цель бура, рука к ней, робот доворачивается к кристаллу.
func _mine(dt: float) -> void:
	if mining == null or anim == null:
		return
	var tip_n := robot.find_child("drill_tip", true, false) as Node3D
	var tip := tip_n.global_position if tip_n and anim.drill_out > 0.5 else Vector3.INF
	_aim_tools()
	mining.step(dt, robot, anim.work, anim.drill_out, tip)
	# Нет кристалла под прицелом — бур срезает растения (ProtoHarvest).
	if harvest:
		harvest.step(dt, robot, anim.work, anim.drill_out, mining.target == null)
	# Ни кристалла, ни растения под прицелом — бур копает грунт (ProtoDigger), H — насыпает.
	if digger != null:
		var building := false
		var b := get_parent().get_node_or_null("builder") if get_parent() else null
		if b != null:
			building = bool(b.get("active"))
		var busy: bool = robot.get_meta("ui_busy", false) or get_tree().paused
		var free: bool = mining.target == null and (harvest == null or harvest.target < 0)
		var digging := free and anim.work > 0.6 and anim.drill_out > 0.95
		var fill := fill_auto or (not busy and not building and Input.is_action_pressed(ProtoDigger.FILL))
		digger.src = tip if tip != Vector3.INF else robot.to_global(Vector3(0.3, 1.2, 0.5))
		var dug := digger.step(dt, digging, fill)
		_aim_show(dt, free, building or busy, fill)
		if free and (anim.work > 0.05 or digger.working):
			var at := digger.dig_point()
			anim.work_target = robot.to_local(at)
			# Доворот плечом к точке прицела (бур в правой руке), пока стоит.
			var to := at - robot.position
			if vel.length() < 0.1 and Vector2(to.x, to.z).length() > 0.5:
				robot.rotation.y = lerp_angle(robot.rotation.y, atan2(to.x, to.z) - 0.25, minf(1.0, dt * 5.0))
			if dug:
				mining.sparks.global_position = at
				mining.crumbs.global_position = at
				mining.crumbs.emitting = true
			return
	var contact := Vector3.INF
	var base := Vector3.INF
	if mining.target:
		contact = mining.contact
		base = ProtoMining.axis(mining.target)[0]
	elif harvest and harvest.target >= 0:
		contact = harvest.contact
		base = contact
	if contact != Vector3.INF and anim.work > 0.05:
		anim.work_target = robot.to_local(contact)
		# Доворот — по основанию кристалла (точка касания сама зависит от позы).
		var to: Vector3 = base.lerp(contact, 0.5) - robot.position
		# Только пока бур выдвигается: во время сверления корпус не крутится.
		if vel.length() < 0.1 and anim.drill_out < 0.95 and Vector2(to.x, to.z).length() > 0.3:
			# Доворот плечом к кристаллу: бур в правой руке.
			var yaw := atan2(to.x, to.z) - 0.25
			robot.rotation.y = lerp_angle(robot.rotation.y, yaw, minf(1.0, dt * 4.0))
		if vel.length() < 0.1 and tip != Vector3.INF and anim.drill_out > 0.95:
			# Налегает на бур: подшагивает, пока острие не упрётся в кристалл.
			var gap := Vector3(contact.x - tip.x, 0, contact.z - tip.z)
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
		if d.node.has_meta("far_id"):
			continue          # россыпи на шаре вдали от участка — не для скриптовой добычи
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
	if harvest_auto:
		return _auto_harvest_use()
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

## Скриптовый сбор органики: подойти к крупному растению у самых густых
## зарослей и срезать его (и что ещё достанет), кадры по событиям.
func auto_harvest(prefix: String) -> void:
	drill_prefix = prefix
	drill_auto = true
	harvest_auto = true
	cam_dist = 4.2
	cam_pitch = 0.36
	var fl := harvest.flora
	var near := fl.best if fl.best != Vector3.INF else robot.position
	var best := -1
	var best_d := INF
	for i in fl.items.size():
		var it: Dictionary = fl.items[i]
		if it.key == "cave" or ProtoHarvest.LOW.has(it.form):
			continue
		var d: float = (it.p as Vector3).distance_to(near) - float(it.h) * 0.5
		if d < best_d:
			best_d = d
			best = i
	if best < 0:
		best = 0
	var p: Vector3 = fl.items[best].p
	var h: float = fl.items[best].h
	# Стоянка: в метре от основания, посуше и поровнее, с чистым ракурсом.
	var off := 0.8 + minf(float(fl.items[best].r) * 0.25, 0.4)
	for i in 12:
		var dd := Vector3(cos(TAU * i / 12.0), 0, sin(TAU * i / 12.0))
		var sp := p + dd * off
		sp.y = terrain.floor_at(Vector3(sp.x, terrain.sy, sp.z))
		if absf(sp.y - p.y) > 0.5 or sp.y < maxf(terrain.lake_level, terrain.river_level_at(sp.x)) + 0.1:
			continue
		if _drill_view(sp, p + Vector3(0, h * 0.3, 0)) == INF:
			continue
		# Не в чужих зарослях: крупное растение рядом со стоянкой закроет кадр.
		var crowded := false
		for j in fl.items.size():
			var o: Dictionary = fl.items[j]
			if j != best and not ProtoHarvest.LOW.has(o.form) and o.key != "cave" \
					and Vector2(o.p.x - sp.x, o.p.z - sp.z).length() < float(o.r) + 0.5:
				crowded = true
				break
		if crowded:
			continue
		drill_stand = sp
		break
	if drill_stand == Vector3.INF:
		drill_stand = p + Vector3(off, 0, 0)
		drill_stand.y = terrain.floor_at(Vector3(drill_stand.x, terrain.sy, drill_stand.z))
	drill_face = p
	var f := Vector3(p.x - drill_stand.x, 0, p.z - drill_stand.z).normalized()
	var st := drill_stand - f * 2.2
	robot.position = fl.node.to_global(Vector3(st.x, terrain.floor_at(Vector3(st.x, terrain.sy, st.z)), st.z))
	robot.rotation.y = atan2(f.x, f.z)
	var yaw := _drill_view(drill_stand, p + Vector3(0, h * 0.3, 0))
	cam_yaw = yaw if yaw != INF else atan2(f.x, f.z) - 2.0
	_harvest_focus = drill_stand.lerp(p, 0.55) + Vector3(0, 0.5 + h * 0.25, 0)
	cam_focus = fl.node.to_global(_harvest_focus)
	print("Сбор: стоянка ", drill_stand, " растение ", fl.items[best].form, " h=%.2f" % h)

var _harvest_last := 0.0      # когда было последнее срезание (для кадра груза)
var _harvest_focus := Vector3.ZERO

## Сбор идёт в системе флоры (участка): на планете-шаре участок поворачивается
## вместе с шаром, и мировые координаты стоянки уплывают.
func _auto_harvest_walk() -> Vector3:
	var n := harvest.flora.node
	var q := n.to_local(robot.global_position)
	var to := Vector3(drill_stand.x - q.x, 0, drill_stand.z - q.z)
	if to.length() > 0.12:
		return (n.global_transform.basis * to.normalized()).normalized()
	var f := n.to_global(drill_face) - robot.global_position
	robot.rotation.y = lerp_angle(robot.rotation.y, atan2(f.x, f.z), minf(1.0, get_process_delta_time() * 4.0))
	return Vector3.ZERO

func _auto_harvest_use() -> bool:
	var q := harvest.flora.node.to_local(robot.global_position)
	var at := Vector2(drill_stand.x - q.x, drill_stand.z - q.z).length() < 0.2
	cam_focus = harvest.flora.node.to_global(_harvest_focus)
	drill_t += get_process_delta_time()
	var shot := ""
	if drill_shots == 0 and at and harvest.target >= 0 and drill_t > 1.5:
		shot = "прицел"
	elif drill_shots == 1 and harvest.progress > 0.5:
		shot = "срез"
	elif drill_shots == 2 and not harvest.falling.is_empty() and harvest.falling[0].t > 0.35:
		shot = "валится"
	elif drill_shots == 3 and harvest.harvested_total > 0.0 and harvest.falling.is_empty() \
			and (harvest.cuts >= 3 or drill_t - _harvest_last > 2.5):
		shot = "груз"
	if harvest.cutting or not harvest.falling.is_empty():
		_harvest_last = drill_t
	if shot != "":
		drill_shots += 1
		var path := "%s_%d.png" % [drill_prefix, drill_shots]
		get_viewport().get_texture().get_image().save_png(path)
		print("кадр сбора (%s): %s; срезано %d, %.1f кг" % [shot, path, harvest.cuts, harvest.harvested_total])
		if drill_shots >= 4:
			get_tree().quit(0)
	if drill_t > 40.0:
		print("Сбор: время вышло, собрано ", _cargo_mass())
		get_tree().quit(1)
	return drill_shots >= 1 and harvest.cuts < 3

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
	if _blocked(np, g, body, step):
		# Скриптовый маршрут упёрся в породу на уровне груди (низкий свод у входа
		# в пещеру) — обойти, взяв чуть в сторону, как сделал бы игрок.
		if not route.is_empty() and not air:
			for ang in [0.6, -0.6, 1.2, -1.2]:
				var d2 := d.rotated(Vector3.UP, ang)
				var np2 := robot.position + d2
				var g2 := ground_at(np2 + Vector3(0, 0.7, 0))
				if not _blocked(np2, g2, maxf(g2, robot.position.y), step):
					d = d2
					np = np2
					g = g2
					body = maxf(g2, robot.position.y)
					break
	if _blocked(np, g, body, step):
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

## Застрял: игрок держит ход больше UNSTICK_T с, робот не сдвинулся и не может
## шагнуть ни в одну сторону (яма глубже прыжка после бура, насыпь вокруг, щель
## под сводом, зажат машиной) — выбраться на ближайшее место, где можно стоять,
## лучше в сторону хода. Просто упёрся в стену — не помогает: отойти можно.
const UNSTICK_T := 1.2

func _unstick(dt: float, want: Vector3, was: Vector3) -> void:
	var moved := Vector2(robot.position.x - was.x, robot.position.z - was.z).length()
	if want.length() < 0.1 or air or swim or moved > 0.25 * dt:
		stuck_t = 0.0
		return
	stuck_t += dt
	if stuck_t < UNSTICK_T:
		return
	stuck_t = 0.0
	if not trapped():
		return
	var spot := free_spot(robot.position, want)
	if spot == Vector3.INF:
		return
	robot.position = spot
	vel = Vector3.ZERO
	# Небольшой подскок — видно, что выбрался, а не телепортировался молча.
	air = true
	vy = 2.0
	if ground:
		ground.snap(spot.y)

## Ни в одну из 8 сторон не шагнуть (и прыжком — яма глубже прыжка).
func trapped() -> bool:
	var p := robot.position
	var gg := G * terrain.style.gravity
	var jump_h := minf(JUMP_V, sqrt(2.0 * gg * JUMP_MAX_H))
	jump_h = jump_h * jump_h / (2.0 * gg)
	var step := terrain.style.step_height()
	for k in 8:
		var a := TAU * k / 8.0
		var np := p + Vector3(sin(a), 0, cos(a)) * 0.3
		var g := ground_at(np + Vector3(0, 0.7, 0))
		var body := maxf(g, p.y)
		if not _blocked(np, g, body, maxf(step, jump_h * 0.9)):
			return false
	return true

## Ближайшее к p место, где робот может стоять: пол не выше 2.6 м, корпус не в
## породе и не в машине. Сначала — в сторону dir. INF — ничего в 3.5 м.
func free_spot(p: Vector3, dir: Vector3) -> Vector3:
	var f := Vector3(dir.x, 0, dir.z)
	f = f.normalized() if f.length() > 0.01 else Vector3(0, 0, 1)
	for r: float in [0.6, 1.0, 1.5, 2.0, 2.6, 3.5]:
		for a: float in [0.0, 0.5, -0.5, 1.0, -1.0, 1.6, -1.6, 2.3, -2.3, PI]:
			var q := p + f.rotated(Vector3.UP, a) * r
			var g := ground_at(Vector3(q.x, p.y + 3.0, q.z))
			if g - p.y > 2.6 or g < p.y - 4.0:
				continue
			var ok := true
			for h: float in [0.3, 0.9, 1.5]:
				if terrain.solid(q.x, g + h, q.z):
					ok = false
					break
			if ok and not _hits_machine(Vector3(q.x, g, q.z)):
				return Vector3(q.x, g, q.z)
	return Vector3.INF

## Шаг в np не пройти: уступ выше step, порода на уровне груди (в прыжке — и ног)
## или машина.
func _blocked(np: Vector3, g: float, body: float, step: float) -> bool:
	return (g - robot.position.y) > step or terrain.solid(np.x, body + 1.2, np.z) \
			or (air and (terrain.solid(np.x, robot.position.y + 0.3, np.z) or terrain.solid(np.x, robot.position.y + 0.9, np.z))) \
			or (_hits_machine(Vector3(np.x, body, np.z)) and not _hits_machine(robot.position))

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
	# Камера сбоку, идёт вдоль разбега — с той стороны, где склон не заслоняет.
	cam_focus = robot.position + Vector3(0, 1.1, 0)
	if jump_side == 0.0:
		var room := func(sd: float) -> float:
			var y := robot.rotation.y + sd
			var d := Basis(Vector3.UP, y) * Basis(Vector3.RIGHT, cam_pitch) * Vector3(0, 0, -cam_dist)
			return boom_hard(cam_focus, d)
		jump_side = -1.35 if room.call(-1.35) >= room.call(1.35) else 1.35
	cam_yaw = robot.rotation.y + jump_side
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

## Точка прицела (центр экрана): луч из камеры до породы, не дальше HOOK_RANGE
## от робота. Порода между камерой и роботом не в счёт.
func aim_point() -> Vector3:
	var from := cam.global_position
	var dir := _aim_dir()
	var eye := robot.position + Vector3(0, 1.5, 0)
	# Начать с точки луча, ближайшей к роботу — не цепляться за камеру.
	var t := maxf(0.5, (eye - from).dot(dir))
	var far := t + HOOK_RANGE
	var last := from + dir * t
	while t < far:
		var q := from + dir * t
		if terrain.solid(q.x, q.y, q.z):
			# Уточнить поверхность делением отрезка.
			var a := last
			var b := q
			for k in 5:
				var m := (a + b) * 0.5
				if terrain.solid(m.x, m.y, m.z): b = m
				else: a = m
			return a - dir * 0.1 if a.distance_to(eye) <= HOOK_RANGE else Vector3.INF
		last = q
		t += 0.25
	return Vector3.INF

## Точка прицела: луч из камеры до породы (не дальше 14 м), край уточнён
## делением пополам — точка не скачет шагами луча.
func _aim_point() -> Vector3:
	var from := cam.global_position
	var dir := -cam.global_transform.basis.z
	var t := 1.0
	while t < 14.0:
		var q := from + dir * t
		if terrain.solid(q.x, q.y, q.z):
			var a := t - 0.2
			var b := t
			for i in 5:
				var m := (a + b) * 0.5
				var qm := from + dir * m
				if terrain.solid(qm.x, qm.y, qm.z):
					b = m
				else:
					a = m
			return from + dir * (a - 0.05)
		t += 0.2
	return Vector3.INF

## Прицел для инструментов: играет человек — бур, срез и кисть берут цель под
## перекрестьем; скрипты (маршрут, --auto=drill) — как раньше, перед роботом.
func _aim_tools() -> void:
	var on := route.is_empty() and not drill_auto and cam != null
	aim_hit = _aim_point() if on else Vector3.INF
	var from := cam.global_position if on else Vector3.INF
	var dir := -cam.global_transform.basis.z if on else Vector3.ZERO
	mining.aim_from = from
	mining.aim_dir = dir
	mining.aim_hit = aim_hit
	if harvest:
		harvest.aim_from = from
		harvest.aim_dir = dir
		harvest.aim_hit = aim_hit
	if digger != null:
		digger.aim = aim_hit
		digger.aim_dir = dir

## Скрипт навёл прицел на aim_goal: камера плавно доворачивает туда перекрестье.
func _aim_goal_step(dt: float) -> void:
	if aim_goal == Vector3.INF or cam == null:
		return
	var d := (aim_goal - cam.global_position).normalized()
	var f := -cam.global_transform.basis.z
	var k := minf(1.0, dt * 8.0)
	cam_yaw += wrapf(atan2(d.x, d.z) - atan2(f.x, f.z), -PI, PI) * k
	cam_pitch = clampf(cam_pitch + (f.y - d.y) * k, PITCH_MIN, PITCH_MAX)

## Перекрестье и шар-кисть: что будет, если нажать бур или кисть.
func _aim_show(dt: float, free: bool, hide: bool, fill: bool) -> void:
	var on := route.is_empty() and not drill_auto
	if not on:
		if aim_ui != null:
			aim_ui.set_hidden(true)
		return
	if aim_ui == null:
		aim_ui = ProtoAim.new()
		aim_ui.name = "aim"
		add_child(aim_ui)
		aim_ui.make_marker(robot.get_parent())
	aim_ui.set_hidden(hide)
	if hide:
		return
	var st := ProtoAim.IDLE
	var brush := Vector3.INF
	var r := ProtoDigger.BITE_R
	if not free:
		st = ProtoAim.TARGET
	elif aim_hit != Vector3.INF:
		st = ProtoAim.READY if digger.in_reach() else ProtoAim.FAR
		if st == ProtoAim.READY and (anim.drill_out > 0.3 or fill or digger.working):
			brush = aim_hit
			if digger.working and digger._bite >= 0:
				brush = digger._bite_c
				r = maxf(digger._bite_r, 0.4)
	aim_ui.show_state(st, brush, r, fill, dt)

## Камера на пружинной штанге: не заходит в породу. Точка у робота сглажена
## (стопы на неровном полу пещеры качают корпус), штанга при упоре в свод
## укорачивается сразу, а отрастает плавно — не щёлкает туда-сюда у стены.
func _camera(dt := 1.0 / 60.0, running := false) -> void:
	var raw := robot.position + Vector3(0, 1.6, 0) if cam_focus == Vector3.INF else cam_focus
	if cam_pivot == Vector3.INF or cam_pivot.distance_to(raw) > 4.0 or cam_focus != Vector3.INF:
		cam_pivot = raw
	else:
		# По горизонтали — почти вплотную, по высоте — мягче (шаги, уступы).
		var kx := 1.0 - exp(-dt * 25.0)
		var ky := 1.0 - exp(-dt * 9.0)
		cam_pivot = Vector3(lerpf(cam_pivot.x, raw.x, kx), lerpf(cam_pivot.y, raw.y, ky), lerpf(cam_pivot.z, raw.z, kx))
	var pivot := cam_pivot
	var dir := Basis(Vector3.UP, cam_yaw) * Basis(Vector3.RIGHT, cam_pitch) * Vector3(0, 0, -1)
	var dist := cam_dist * lerpf(1.0, 0.8, under)
	var d := dir * dist + Basis(Vector3.UP, cam_yaw) * Vector3(-0.7, 0, 0)
	var hard := boom_hard(pivot, d)
	var free := minf(boom_free(pivot, d), hard)
	if boom < 0.0:
		boom = free
		boom_v = 0.0
	else:
		# Пружина с критическим затуханием: к стене — за ~0.15 с, от стены — за ~0.6 с.
		# Без рывка: выступ свода, вдруг вставший между камерой и роботом, «наезжает»;
		# пару кадров камера может быть в породе — изнутри её грани не рисуются.
		boom = _smooth(boom, free, 0.15 if free < boom else 0.6, dt)
	# Жёсткий упор: видимая сетка рельефа и машины прямо на штанге — камера не
	# уходит за них (изнутри порода чёрная), тут без сглаживания.
	boom = minf(boom, hard)
	cam.position = pivot + d.normalized() * boom
	# Взгляд — мимо правого плеча (как в Astroneer): робот левее центра и не
	# заслоняет перекрестье, прицел смотрит туда, куда робот повернётся.
	cam.look_at(pivot + Basis(Vector3.UP, cam_yaw) * Vector3(-0.6, -0.1, 1.5) if cam_focus == Vector3.INF else pivot)
	# Бег — угол чуть шире.
	if fov_base < 0.0:
		fov_base = cam.fov
	cam.fov = lerpf(cam.fov, fov_base + (SPRINT_FOV if running else 0.0), 1.0 - exp(-dt * 4.0))

## Плавное приближение cur к to за время ~smooth (скорость — в boom_v).
func _smooth(cur: float, to: float, smooth: float, dt: float) -> float:
	var w := 2.0 / smooth
	var x := w * dt
	var e := 1.0 / (1.0 + x + 0.48 * x * x + 0.235 * x * x * x)
	var ch := cur - to
	var tmp := (boom_v + w * ch) * dt
	boom_v = (boom_v - w * tmp) * e
	return to + (ch + tmp) * e

## До чего штанга упирается по-настоящему: шар 0.2 м по сетке рельефа и телам
## машин (то, что видно), и центр штанги по полю плотности.
func boom_hard(pivot: Vector3, d: Vector3) -> float:
	var len := d.length()
	var n := d / maxf(len, 0.001)
	var hard := len
	var w := robot.get_world_3d() if robot != null and robot.is_inside_tree() else null
	if w != null:
		var sp := SphereShape3D.new()
		sp.radius = 0.2
		var q := PhysicsShapeQueryParameters3D.new()
		q.shape = sp
		q.transform = Transform3D(Basis(), pivot)
		q.motion = d
		q.collision_mask = ProtoMachines.LAYER_GROUND | ProtoMachines.LAYER_MACHINES
		var r := w.direct_space_state.cast_motion(q)
		if r.size() == 2 and r[0] < 1.0:
			hard = r[0] * len
	var t := 0.2
	while t < hard:
		var p := pivot + n * t
		if terrain.solid(p.x, p.y, p.z):
			hard = t - 0.1
			break
		t += 0.1
	return maxf(0.3, hard)

## Сколько штанги от pivot вдоль d свободно от породы: проба «толстая» —
## центр и четыре точки вокруг (0.3 м), с запасом 0.35 м до стены.
func boom_free(pivot: Vector3, d: Vector3) -> float:
	var n := d.normalized()
	var side := n.cross(Vector3.UP)
	if side.length() < 0.1:
		side = Vector3.RIGHT
	side = side.normalized()
	var up := side.cross(n).normalized()
	var offs := [Vector3.ZERO, side * 0.3, -side * 0.3, up * 0.3, -up * 0.3]
	var len := d.length()
	var t := 0.3
	while t < len:
		var q := pivot + n * t
		for o: Vector3 in offs:
			var p: Vector3 = q + o * clampf(t / 1.2, 0.0, 1.0)
			if terrain.solid(p.x, p.y, p.z):
				return maxf(0.4, t - 0.35)
		t += 0.12
	return len

## Выстрел кистью: вцепиться в породу, куда смотрит камера (центр экрана),
## не дальше HOOK_RANGE от робота. Мимо — кисть долетает и возвращается.
func hook_fire() -> void:
	if fist == null or fist.state != "dock":
		return
	var hit := aim_point()
	if hit != Vector3.INF:
		hook_to(hit)
	else:
		hook_at = Vector3.INF
		var from := robot.position + Vector3(0, 1.5, 0)
		fist.fire(robot.to_local(from + _aim_dir() * 6.0), false)

## Вцепиться кистью в точку мира и подтянуться к ней.
func hook_to(at: Vector3) -> void:
	hook_at = at
	hook_t = 0.0
	fist.fire(robot.to_local(at), true)

## Трос: кисть держит точку в мире (цель пересчитывается в пространство робота,
## иначе она «едет» вместе с ним); натянут — тянет робота по прямой к ней, и
## вверх тоже; у стены под уступом — подсаживает наверх.
func _hook(dt: float) -> void:
	if fist == null:
		return
	if hook_at == Vector3.INF:
		return
	if fist.state == "dock" or fist.state == "back":
		hook_at = Vector3.INF
		return
	fist.target = robot.to_local(hook_at)
	if fist.state != "pull":
		return
	hook_t += dt
	# Ноги — на 1.2 м ниже кисти и чуть перед стеной: робот повисает, держась за неё.
	var flat := Vector3(hook_at.x - robot.position.x, 0, hook_at.z - robot.position.z)
	var back := flat.normalized() * 0.45 if flat.length() > 0.45 else flat
	var to := hook_at - back - Vector3(0, 1.2, 0) - robot.position
	if to.length() < 0.7 or hook_t > HOOK_TIME:
		_hook_end(false)
		return
	var v := to.normalized() * minf(HOOK_SPEED, 2.0 + hook_t * 16.0)
	v *= clampf(to.length() / 1.2, 0.4, 1.0)
	vel = Vector3(v.x, 0, v.z)
	if v.y > 0.3 or air:
		air = true
		vy = v.y
	# Упёрся в стену и почти не движется — долез: отпустить (с подсадкой).
	if hook_t > 0.4 and Vector2(to.x, to.z).length() < 1.1 and absf(to.y) < 0.9:
		_hook_end(false)

## Отпустить трос. Над кистью уступ, на который можно встать, — подскочить на
## него; hop — отпустили Прыжком: подскок и вперёд.
func _hook_end(hop: bool) -> void:
	var at := hook_at
	hook_at = Vector3.INF
	if fist:
		fist.release()
	if at == Vector3.INF:
		return
	var gg := G * terrain.style.gravity
	var flat := Vector3(at.x - robot.position.x, 0, at.z - robot.position.z)
	var fwd := flat.normalized() if flat.length() > 0.05 else Basis(Vector3.UP, robot.rotation.y) * Vector3(0, 0, 1)
	# Верх уступа — и по сетке, и по полю плотности (сетка сглаживает кромку).
	var q := at + fwd * 0.6 + Vector3(0, 2.5, 0)
	var top := maxf(ground_at(q), terrain.floor_at(q))
	var rise := top - robot.position.y
	if rise > 0.2 and rise < 3.2 and not terrain.solid(q.x, top + 1.2, q.z):
		air = true
		vy = sqrt(2.0 * gg * (rise + 0.4))
		vel = Vector3.ZERO
		mantle = Vector3(q.x, top, q.z)
	elif hop:
		air = true
		vy = maxf(vy, minf(JUMP_V, sqrt(2.0 * gg * JUMP_MAX_H)))

func _aim_dir() -> Vector3:
	return -cam.global_transform.basis.z

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
