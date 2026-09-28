class_name ProtoTerrainChunks
extends Node3D
## Сетка рельефа кусками: область делится по X и Z на куски по CHUNK клеток (по
## высоте — целиком). Правка рельефа (ProtoTerrain.edit) перестраивает только
## задетые куски вместе с их коллизией — не весь рельеф (он строится ~1 с), и по
## куску за кадр.
## Соседние куски перекрываются на клетку: surface nets строит грани только на
## внутренних узлах куска, так грани делятся между кусками без щелей и дублей.

var terrain: ProtoTerrain
var region := AABB()
var cell := 1.0
var skip := AABB()
var skip_depth := 2.0
var shallow := -INF
var material: Material
var chunks: Array = []          # [{box: AABB, origin: Vector3, n: Vector3i, mi: MeshInstance3D}]
var rebuilt := 0                # сколько кусков перестроено правками (для тестов и лога)
var _queue: Array = []          # куски, ждущие перестройки

## Строит все куски. chunk — клеток в куске по X и Z.
func build(t: ProtoTerrain, area: AABB, step: float, chunk: int, mat: Material,
		skip_box := AABB(), depth := 2.0, min_depth := -INF) -> void:
	terrain = t
	region = area
	cell = step
	skip = skip_box
	skip_depth = depth
	shallow = min_depth
	material = mat
	var total := Vector3i(ceili(area.size.x / step), ceili(area.size.y / step), ceili(area.size.z / step))
	var xs := _spans(total.x, chunk)
	var zs := _spans(total.z, chunk)
	for zi in zs:
		for xi in xs:
			var o := area.position + Vector3(xi[0], 0, zi[0]) * step
			var n := Vector3i(xi[1], total.y, zi[1])
			var mi := MeshInstance3D.new()
			mi.name = "chunk_%d_%d" % [xi[0], zi[0]]
			mi.material_override = mat
			add_child(mi)
			var c := {"origin": o, "n": n, "mi": mi,
				"box": AABB(o, Vector3(n.x, n.y, n.z) * step)}
			chunks.append(c)
			_mesh(c)

## Отрезки [начало, клеток] вдоль оси: каждый следующий начинается на клетку
## раньше конца предыдущего.
static func _spans(total: int, chunk: int) -> Array:
	var out: Array = []
	var o := 0
	while true:
		var n := mini(chunk, total - o)
		out.append([o, n])
		if o + n >= total:
			break
		o += n - 1
	return out

func _mesh(c: Dictionary) -> void:
	var mi: MeshInstance3D = c.mi
	mi.mesh = terrain.build_mesh(c.origin, c.n, cell, skip, skip_depth, shallow)
	var old := mi.get_node_or_null("ground_collision")
	if old != null:
		mi.remove_child(old)
		old.queue_free()
	RobotGround.add_collision(mi)

## Перестроить куски, задетые областью box: в очередь, по куску за кадр
## (кусок строится 10–20 мс — так правка не даёт рывка). now — сразу все.
## Возвращает число задетых кусков.
func rebuild(box: AABB, now := false) -> int:
	var n := 0
	var grown := box.grow(cell * 0.5)
	for c in chunks:
		if (c.box as AABB).intersects(grown):
			if not _queue.has(c):
				_queue.append(c)
			n += 1
	if now:
		flush()
	return n

## Достроить всю очередь сейчас.
func flush() -> void:
	while not _queue.is_empty():
		_mesh(_queue.pop_front())
		rebuilt += 1

func pending() -> int:
	return _queue.size()

func _process(_dt: float) -> void:
	if not _queue.is_empty():
		_mesh(_queue.pop_front())
		rebuilt += 1

## Сетки кусков (для карты).
func meshes() -> Array:
	return chunks.map(func(c): return c.mi.mesh)
