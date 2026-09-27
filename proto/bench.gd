class_name ProtoBench
extends Node
## Бенчмарк 3D-прототипа (--auto=bench): загрузка по этапам и время кадра на
## фиксированном маршруте (от завода к входу и по ходу в пещерный зал, как --auto=cave).
##   godot --path . --fixed-fps 30 res://proto/preview.tscn -- --seed=14 --auto=bench [--bench=отчёт.json] [--deck]
## --fixed-fps делает шаг симуляции постоянным: маршрут проходит за одно и то же
## число кадров при любой скорости машины, а время кадра меряется по часам.
## Отчёт: загрузка (мс по этапам), кадр (среднее, медиана, 95-й и 99-й
## процентиль, максимум — снаружи и в пещере), вызовы отрисовки, объекты и
## треугольники в кадре, самые многочисленные сетки сцены. Без настоящей видеокарты
## (контейнер, Xvfb) FPS меряет программный рендер — смотреть на загрузку, вызовы
## отрисовки и на время кадра с --headless (там это чистое время скриптов).

var load_ms := {}
var out_path := ""
var player: ProtoPlayer
var _prev := 0
var _frames := {"outside": [], "cave": []}
var _draws := []
var _objs := []
var _prims := []
var _tail := -1.0
var _skip := 5          # первые кадры — компиляция шейдеров, не считаем
var _shader_ms := 0.0

func _process(dt: float) -> void:
	var now := Time.get_ticks_usec()
	if _prev == 0:
		_prev = now
		return
	var ms := (now - _prev) / 1000.0
	_prev = now
	if _skip > 0:
		_skip -= 1
		_shader_ms += ms
		return
	var where := "cave" if player != null and player.under > 0.5 else "outside"
	_frames[where].append(ms)
	_draws.append(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
	_objs.append(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME))
	_prims.append(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME))
	if player == null or player.route_i >= player.route.size():
		if _tail < 0.0:
			_tail = 0.0
		_tail += dt
		if _tail > 2.0:
			_finish()

## Что в сцене тяжелее всего: сетки по ближайшему именованному предку —
## число экземпляров и треугольников (тени рисуют их ещё раз).
func _heavy() -> Array:
	var groups := {}
	var stack: Array = [get_parent()]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		var mi := n as MeshInstance3D
		if mi == null or mi.mesh == null or not mi.is_visible_in_tree():
			continue
		var key := _group(mi)
		var tris := 0
		for si in mi.mesh.get_surface_count():
			var a := mi.mesh.surface_get_arrays(si)
			var ix: PackedInt32Array = a[Mesh.ARRAY_INDEX] if a[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			tris += ix.size() / 3 if not ix.is_empty() else (a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
		var g: Array = groups.get(key, [0, 0])
		groups[key] = [g[0] + 1, g[1] + tris]
	var out := []
	for k in groups:
		out.append({"group": k, "meshes": groups[k][0], "tris": groups[k][1]})
	out.sort_custom(func(a, b): return a.meshes > b.meshes)
	return out.slice(0, 10)

func _group(n: Node) -> String:
	var p := n.get_parent()
	while p != null and p != get_parent() and p.get_parent() != get_parent():
		p = p.get_parent()
	if p == null or p == get_parent():
		return "(корень) " + n.get_class()
	return String(p.name)

static func _stats(a: Array) -> Dictionary:
	if a.is_empty():
		return {"n": 0}
	var s := a.duplicate()
	s.sort()
	var sum := 0.0
	for v in s:
		sum += v
	var pick := func(q: float) -> float: return s[mini(s.size() - 1, int(q * s.size()))]
	return {"n": s.size(), "avg": snappedf(sum / s.size(), 0.01), "p50": snappedf(pick.call(0.5), 0.01),
		"p95": snappedf(pick.call(0.95), 0.01), "p99": snappedf(pick.call(0.99), 0.01), "max": snappedf(s[-1], 0.01)}

func _finish() -> void:
	set_process(false)
	var all: Array = _frames.outside + _frames.cave
	var rep := {
		"seed": get_parent().seed_value,
		"deck": ProtoDeck.active,
		"renderer": RenderingServer.get_video_adapter_name(),
		"window": [get_viewport().get_visible_rect().size.x, get_viewport().get_visible_rect().size.y],
		"load_ms": load_ms,
		"first_frames_ms": snappedf(_shader_ms, 0.1),
		"frame_ms": _stats(all),
		"frame_ms_outside": _stats(_frames.outside),
		"frame_ms_cave": _stats(_frames.cave),
		"draw_calls": _stats(_draws),
		"objects": _stats(_objs),
		"primitives": _stats(_prims),
		"nodes": get_tree().get_node_count(),
		"heavy": _heavy(),
	}
	print("БЕНЧМАРК ", JSON.stringify(rep))
	var f: Dictionary = rep.frame_ms
	print("Загрузка %d мс; кадр %.1f мс в среднем (p95 %.1f, p99 %.1f), вызовов отрисовки %d (макс. %d)" % [
		load_ms.get("total", 0), f.get("avg", 0.0), f.get("p95", 0.0), f.get("p99", 0.0),
		int(rep.draw_calls.get("avg", 0)), int(rep.draw_calls.get("max", 0))])
	if out_path != "":
		var fa := FileAccess.open(out_path, FileAccess.WRITE)
		if fa:
			fa.store_string(JSON.stringify(rep, "  "))
	get_tree().quit(0)
