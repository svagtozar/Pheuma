class_name LogicNet
extends RefCounted
## Логическая сеть: провода между выходами и входами машин.
## У провода есть путевые точки, которые игрок добавляет, двигает и удаляет.
## Значения вычисляются с задержкой в один тик (читаются прошлые выходы),
## поэтому петли не зависают.

var outputs := {}   # id машины → bool
var wires := {}     # id провода → {"id", "from", "to", "port", "points": Array[Vector2], "material": id}
var _next_id := 1

func add_wire(from_id: int, to_id: int, port: int = 0, points: Array = [], material: String = "") -> int:
	var id := _next_id
	_next_id += 1
	wires[id] = {"id": id, "from": from_id, "to": to_id, "port": port, "points": points.duplicate(), "material": material}
	return id

func remove_wire(id: int) -> void:
	wires.erase(id)

func remove_machine(mid: int) -> void:
	outputs.erase(mid)
	for id in wires.keys():
		if wires[id].from == mid or wires[id].to == mid:
			wires.erase(id)

func wires_to(mid: int) -> Array:
	return wires.values().filter(func(w): return w.to == mid)

func wires_from(mid: int) -> Array:
	return wires.values().filter(func(w): return w.from == mid)

func has_input(mid: int, port: int = -1) -> bool:
	for w in wires.values():
		if w.to == mid and (port < 0 or w.port == port):
			return true
	return false

func input(mid: int, port: int = 0) -> bool:
	for w in wires.values():
		if w.to == mid and w.port == port and outputs.get(w.from, false):
			return true
	return false

## Полилиния провода от источника к приёмнику через путевые точки.
static func polyline(from_pos: Vector2, points: Array, to_pos: Vector2) -> Array:
	var out: Array = [from_pos]
	out.append_array(points)
	out.append(to_pos)
	return out

static func length_of(poly: Array) -> float:
	var l := 0.0
	for i in range(1, poly.size()):
		l += poly[i - 1].distance_to(poly[i])
	return l

## Вставить путевую точку в ближайший к pos отрезок. Возвращает её индекс.
func insert_waypoint(id: int, pos: Vector2, from_pos: Vector2, to_pos: Vector2) -> int:
	var w: Dictionary = wires[id]
	var poly := polyline(from_pos, w.points, to_pos)
	var best := 0
	var best_d := INF
	for i in range(poly.size() - 1):
		var q := Geometry2D.get_closest_point_to_segment(pos, poly[i], poly[i + 1])
		var d := q.distance_to(pos)
		if d < best_d:
			best_d = d
			best = i
	w.points.insert(best, pos)
	return best

func move_waypoint(id: int, idx: int, pos: Vector2) -> void:
	var pts: Array = wires[id].points
	if idx >= 0 and idx < pts.size():
		pts[idx] = pos

func remove_waypoint(id: int, idx: int) -> void:
	var pts: Array = wires[id].points
	if idx >= 0 and idx < pts.size():
		pts.remove_at(idx)

## Ближайший к pos провод и расстояние до него.
func nearest_wire(pos: Vector2, endpoint: Callable) -> Dictionary:
	var best := {"id": -1, "dist": INF}
	for w in wires.values():
		var ends: Array = endpoint.call(w)
		var poly := polyline(ends[0], w.points, ends[1])
		for i in range(poly.size() - 1):
			var d := Geometry2D.get_closest_point_to_segment(pos, poly[i], poly[i + 1]).distance_to(pos)
			if d < best.dist:
				best = {"id": w.id, "dist": d}
	return best
