class_name ProtoDigger
extends Node
## Правка рельефа роботом: бур без кристалла под прицелом копает грунт перед
## собой, а вынутый грунт можно насыпать обратно (H / D-pad влево). Грунт —
## не груз: робот держит до SOIL_MAX «вёдер» в бункере.
## Рельеф меняет ProtoTerrain.edit, сетки перестраивает ProtoTerrainChunks —
## не чаще раза в REBUILD_EVERY, задетое копится.

const FILL := &"tool_fill"
const DIG_R := 1.2             # радиус лунки за один приём, м (сетка рельефа — 1 м)
const DIG_EVERY := 0.4         # с на приём при скорости бура 1
const FILL_EVERY := 0.3
const SOIL_MAX := 12           # вёдер грунта в бункере
const REBUILD_EVERY := 0.2
const REACH := 1.6             # на сколько впереди робота копает и сыплет

var terrain: ProtoTerrain
var chunks: Array = []         # ProtoTerrainChunks, которые перестраивать
var robot: Node3D
var soil := 0                  # вёдер грунта в бункере
var dug := 0                   # приёмов копания за всё время
var filled := 0
var status := ""               # подсказка для HUD ("" — нечего сказать)
var speed_mult := 1.0
var _t := 0.0
var _dirty := AABB()
var _rebuild_t := 0.0
var on_edit: Callable          # (центр, радиус, насыпь) — сохранение, флора

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

## Куда бьёт бур: земля в REACH впереди, чуть ниже поверхности.
func dig_point() -> Vector3:
	var f := robot.global_transform.basis.z
	var p := robot.global_position + Vector3(f.x, 0, f.z).normalized() * REACH
	var g := terrain.floor_at(Vector3(p.x, robot.global_position.y + 1.5, p.z))
	return Vector3(p.x, g - 0.1, p.z)

func fill_point() -> Vector3:
	var p := dig_point()
	return p - Vector3(0, 0.35, 0)

## Кадр: drilling — бур выдвинут и работает, а кристалла под прицелом нет;
## fill — зажата кнопка насыпи. Возвращает, копал ли.
func step(dt: float, drilling: bool, fill: bool) -> bool:
	_t = maxf(0.0, _t - dt)
	status = ""
	var did := false
	if drilling:
		var at := dig_point()
		if soil >= SOIL_MAX:
			status = "бункер грунта полон — насыпьте (%s)" % "H"
		elif not terrain.can_edit(at):
			status = "площадка завода укреплена — копать нельзя"
		elif _t <= 0.0:
			_edit(at, DIG_R, false)
			soil += 1
			dug += 1
			_t = DIG_EVERY / maxf(0.2, speed_mult)
			did = true
	elif fill:
		var at := fill_point()
		if soil <= 0:
			status = "грунта нет — сначала выкопайте буром"
		elif not terrain.can_edit(at):
			status = "на площадку завода не сыпать"
		elif _t <= 0.0:
			_edit(at, DIG_R, true)
			soil -= 1
			filled += 1
			_t = FILL_EVERY
	_rebuild_t = maxf(0.0, _rebuild_t - dt)
	if _dirty.size != Vector3.ZERO and _rebuild_t <= 0.0:
		flush()
	return did

func _edit(at: Vector3, r: float, add: bool) -> void:
	var box := terrain.edit(at, r, add)
	_dirty = box if _dirty.size == Vector3.ZERO else _dirty.merge(box)
	if on_edit.is_valid():
		on_edit.call(at, r, add)

## Перестроить сетки задетого (сразу).
func flush() -> void:
	if _dirty.size == Vector3.ZERO:
		return
	for c in chunks:
		c.rebuild(_dirty)
	_dirty = AABB()
	_rebuild_t = REBUILD_EVERY
