class_name ProtoDigger
extends Node
## Правка рельефа роботом, как в Astroneer: бур без кристалла под прицелом
## вгрызается в породу там, куда смотрит прицел (вниз, в стену, в свод), а
## вынутый грунт кисть насыпает туда же (H / D-pad влево). Грунт — не груз:
## робот держит до SOIL_MAX «вёдер» в бункере.
## Работает плавно: лунка (или насыпь) растёт от малого шара до BITE_R, пока
## держите кнопку; выросла — следующая начинается глубже по лучу прицела.
## Рельеф меняет ProtoTerrain.edit / edit_grow, сетки перестраивает
## ProtoTerrainChunks — не чаще раза в REBUILD_EVERY, задетое копится.

const FILL := &"tool_fill"
const BITE_R := 1.05           # радиус выросшей лунки, м (сетка рельефа — 1 м)
const BITE_R0 := 0.3           # с этого радиуса лунка начинает расти
const DIG_RATE := 1.7          # м радиуса в секунду при скорости бура 1
const FILL_RATE := 1.9
const BUCKET := 7.24           # м³ в «ведре» бункера (шар радиуса 1.2)
const SOIL_MAX := 12           # вёдер грунта в бункере
const REBUILD_EVERY := 0.1
const REACH := 1.6             # без прицела: на сколько впереди робота копает и сыплет
const AIM_REACH := 4.5         # с прицелом: дальше от плеча бур и кисть не достают
const BODY_GAP := 0.45         # насыпь не заходит на корпус робота ближе этого

var terrain: ProtoTerrain
var chunks: Array = []         # ProtoTerrainChunks, которые перестраивать
var robot: Node3D
var soil := 0.0                # вёдер грунта в бункере (дробное: лунка растёт плавно)
var dug := 0                   # лунок начато за всё время
var filled := 0                # насыпей начато
var status := ""               # подсказка для HUD ("" — нечего сказать)
var speed_mult := 1.0
## Прицел (мир): точка на породе под перекрестьем и направление луча. INF —
## прицела нет (скрипты, проверки): как раньше, земля в REACH впереди.
var aim := Vector3.INF
var aim_dir := Vector3.ZERO
var src := Vector3.INF         # откуда летит грунт кисти (острие/кисть руки); INF — плечо
var working := false           # в этом кадре бур копал или кисть сыпала
var _bite := -1                # правка рельефа, которая сейчас растёт
var _bite_add := false
var _bite_c := Vector3.ZERO
var _bite_r := 0.0
var _dirty := AABB()
var _rebuild_t := 0.0
var _stream: CPUParticles3D    # струя грунта от руки к насыпи
var on_edit: Callable          # (центр, радиус, насыпь) — флора; зовётся при перестройке сеток

static func ensure_actions() -> void:
	if InputMap.has_action(FILL):
		return
	InputMap.add_action(FILL, 0.5)
	InputMap.action_add_event(FILL, ProtoControls._key(KEY_H))
	InputMap.action_add_event(FILL, ProtoControls._button(JOY_BUTTON_DPAD_LEFT))

func setup(t: ProtoTerrain, ground_chunks: Array, r: Node3D) -> void:
	terrain = t
	chunks = ground_chunks
	robot = r
	ensure_actions()

func shoulder() -> Vector3:
	return robot.to_global(Vector3(0.23, 1.4, 0.1))

## Куда бьёт бур: точка прицела; без прицела — земля в REACH впереди.
func dig_point() -> Vector3:
	if aim != Vector3.INF:
		return aim
	var f := robot.global_transform.basis.z
	var p := robot.global_position + Vector3(f.x, 0, f.z).normalized() * REACH
	var g := terrain.floor_at(Vector3(p.x, robot.global_position.y + 1.5, p.z))
	return Vector3(p.x, g - 0.1, p.z)

func fill_point() -> Vector3:
	if aim != Vector3.INF:
		return aim
	return dig_point() - Vector3(0, 0.35, 0)

## Достаёт ли бур / кисть до точки прицела.
func in_reach() -> bool:
	return aim == Vector3.INF or shoulder().distance_to(aim) <= AIM_REACH

## Кадр: drilling — бур выдвинут и работает, а кристалла под прицелом нет;
## fill — зажата кнопка насыпи. Возвращает, копал ли.
func step(dt: float, drilling: bool, fill: bool) -> bool:
	status = ""
	working = false
	var did := false
	if drilling:
		var at := dig_point()
		if soil >= SOIL_MAX:
			status = "бункер грунта полон — насыпьте (%s)" % "H"
		elif not in_reach():
			status = "далеко — подойдите ближе"
		elif not terrain.can_edit(at):
			status = "площадка завода укреплена — копать нельзя"
		else:
			var dv := _grow(at, false, DIG_RATE * clampf(speed_mult, 0.2, 3.0) * dt, INF)
			soil = minf(float(SOIL_MAX), soil + dv / BUCKET)
			did = true
	elif fill:
		var at := fill_point()
		if soil <= 0.001:
			status = "грунта нет — сначала выкопайте буром"
		elif not in_reach():
			status = "далеко — подойдите ближе"
		elif not terrain.can_edit(at):
			status = "на площадку завода не сыпать"
		elif aim != Vector3.INF and (at - robot.global_position).dot(aim_dir) < 0.3:
			# Между камерой и роботом не сыпать: насыпь закрыла бы вид.
			status = "насыпать можно перед роботом"
		else:
			var dv := _grow(at, true, FILL_RATE * dt, _body_room(at))
			if dv < 0.0:
				status = "здесь насыпь накроет робота — отойдите"
			else:
				soil = maxf(0.0, soil - dv / BUCKET)
				working = true
	if not drilling and not fill:
		_bite = -1
	_stream_update(fill and working)
	_rebuild_t = maxf(0.0, _rebuild_t - dt)
	if _dirty.size != Vector3.ZERO and _rebuild_t <= 0.0:
		flush()
	return did

## Растить лунку (add = false) или насыпь у точки at на dr метров радиуса.
## room — насыпь не больше этого радиуса (не накрыть робота). Возвращает
## добавленный объём, м³; -1 — расти некуда.
func _grow(at: Vector3, add: bool, dr: float, room: float) -> float:
	var same := _bite >= 0 and _bite < terrain.edits.size() and _bite_add == add \
		and _bite_r < minf(BITE_R, room) - 0.01 and at.distance_to(_bite_c) < _bite_r + 0.45
	if not same:
		# Новая лунка — чуть глубже точки прицела (вгрызается по лучу);
		# насыпь — у самой поверхности, чтобы росла наружу.
		var d := aim_dir if aim != Vector3.INF else Vector3.DOWN
		var c := at + d * (0.25 if not add else 0.1)
		var r0 := minf(BITE_R0, room)
		if r0 < 0.15:
			return -1.0
		_bite_c = c
		_bite_r = r0
		_bite_add = add
		_bite = terrain.edits.size()
		_mark(terrain.edit(c, r0, add))
		if add:
			filled += 1
		else:
			dug += 1
		working = true
		return _vol(r0) * 0.5
	var r := minf(minf(_bite_r + dr, BITE_R), room)
	if r <= _bite_r + 0.0001:
		return -1.0 if add else 0.0
	var dv := _vol(r) - _vol(_bite_r)
	_bite_r = r
	_mark(terrain.edit_grow(_bite, r))
	working = true
	return dv

static func _vol(r: float) -> float:
	return 4.18879 * r * r * r

## Насколько может вырасти насыпь у точки, не накрыв корпус робота.
func _body_room(at: Vector3) -> float:
	var room := INF
	for h in [0.3, 0.9, 1.5]:
		var p := robot.global_position + Vector3(0, h, 0)
		room = minf(room, at.distance_to(p) - BODY_GAP)
	return room

func _mark(box: AABB) -> void:
	_dirty = box if _dirty.size == Vector3.ZERO else _dirty.merge(box)

## Перестроить сетки задетого (сразу).
func flush() -> void:
	if _dirty.size == Vector3.ZERO:
		return
	for c in chunks:
		c.rebuild(_dirty)
	if on_edit.is_valid():
		on_edit.call(_dirty.get_center(), _dirty.size.x * 0.5 - 1.0, _bite_add)
	_dirty = AABB()
	_rebuild_t = REBUILD_EVERY

## Кисть: струя комьев грунта от руки дугой к насыпи.
func _stream_update(on: bool) -> void:
	if _stream == null:
		if not on:
			return
		_stream = CPUParticles3D.new()
		_stream.name = "soil_stream"
		_stream.local_coords = false
		_stream.amount = 48
		_stream.lifetime = 0.35
		var m := BoxMesh.new()
		m.size = Vector3.ONE * 0.07
		var mat := StandardMaterial3D.new()
		mat.albedo_color = terrain.ground.darkened(0.15) if terrain != null else Color(0.45, 0.36, 0.27)
		mat.roughness = 1.0
		m.material = mat
		_stream.mesh = m
		_stream.spread = 6.0
		_stream.gravity = Vector3(0, -6.0, 0)
		_stream.scale_amount_min = 0.6
		_stream.scale_amount_max = 1.4
		_stream.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		_stream.emission_sphere_radius = 0.05
		add_child(_stream)
	_stream.emitting = on
	if not on:
		return
	var a := src if src != Vector3.INF else shoulder()
	var b := _bite_c + (a - _bite_c).normalized() * _bite_r * 0.7
	var to := b - a
	if to.length() < 0.05:
		return
	# Долёт за lifetime с учётом тяжести: v = d/t + g·t/2 вверх.
	var t := _stream.lifetime * 0.9
	var v := to / t + Vector3(0, 3.0 * t, 0)
	_stream.global_position = a
	_stream.direction = v.normalized()
	_stream.initial_velocity_min = v.length() * 0.95
	_stream.initial_velocity_max = v.length() * 1.05
