class_name MachineChunk
extends Node2D
## Неизменная часть машин (корпус, подпись, стрелки) на участке 16×16 клеток,
## отрисованная один раз во вьюпорт-текстуру. Каждый кадр — один квадрат вместо
## десятков примитивов и надписей на машину. Перерисовывается, когда машины участка
## меняются (поставили, снесли, повернули).

const SIZE := 16
const T := 32.0

var view                  # game/world_view.gd
var origin := Vector2i.ZERO
var fingerprint := -1
var baked_ids := {}       # id машин, чьи корпуса уже в текстуре
var _vp: SubViewport
var _painter: Node2D
var _pending: Array = []  # машины для следующей отрисовки во вьюпорт
var _runs: Array = []     # Rect2 — полосы клеток с машинами (в координатах участка)

func _init() -> void:
	show_behind_parent = true   # под живой частью машин, которую рисует сам вид

## Вьюпорт заводится только на участке, где есть машины.
func _make_viewport() -> void:
	_vp = SubViewport.new()
	_vp.size = Vector2i(SIZE * int(T), SIZE * int(T))
	_vp.transparent_bg = true
	_vp.disable_3d = true
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_vp)
	_painter = Node2D.new()
	_painter.position = -Vector2(origin) * T
	_painter.draw.connect(_paint)
	_vp.add_child(_painter)

func _machines() -> Array:
	var r := Rect2i(origin, Vector2i(SIZE, SIZE))
	return view.world.machines.values().filter(func(m): return r.has_point(m.cell))

func compute_fingerprint(ms: Array) -> int:
	var h := 23
	for m in ms:
		h = (h * 31 + m.id * 7 + m.facing + m.kind.hash() + m.built_from.color.to_rgba32()) & 0x7fffffff
	return h

func refresh_if_changed() -> bool:
	var ms := _machines()
	var f := compute_fingerprint(ms)
	if f == fingerprint:
		return false
	if _vp == null:
		if ms.is_empty():
			fingerprint = f
			return false
		_make_viewport()
	fingerprint = f
	_pending = ms
	baked_ids.clear()
	_painter.queue_redraw()
	_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	# Корпуса попадут в текстуру к следующему кадру; до тех пор вид рисует их сам.
	await RenderingServer.frame_post_draw
	for m in ms:
		baked_ids[m.id] = true
	_runs = compute_runs(ms, origin)
	queue_redraw()
	return true

## Горизонтальные полосы подряд стоящих машин, с запасом по бокам под широкие подписи.
## Рисуем из текстуры только их: пустая прозрачная часть участка тоже стоит времени
## при программной отрисовке. Полосы не перекрываются — ничего не смешивается дважды.
static func compute_runs(ms: Array, org: Vector2i) -> Array:
	var rows := {}
	for m in ms:
		var l: Vector2i = m.cell - org
		if not rows.has(l.y):
			rows[l.y] = []
		rows[l.y].append(l.x)
	var out: Array = []
	for y in rows:
		var xs: Array = rows[y]
		xs.sort()
		var start: int = xs[0]
		var prev: int = xs[0]
		for i in range(1, xs.size() + 1):
			if i < xs.size() and xs[i] <= prev + 1:
				prev = xs[i]
				continue
			var x0 := maxf(start * T - 6.0, 0.0)
			var x1 := minf((prev + 1) * T + 6.0, SIZE * T)
			out.append(Rect2(x0, y * T, x1 - x0, T))
			if i < xs.size():
				start = xs[i]
				prev = xs[i]
	return out

func _paint() -> void:
	for m in _pending:
		view.draw_body(_painter, m.kind, m.cell, m.facing, m.built_from.color)

func _draw() -> void:
	if _vp != null and not baked_ids.is_empty():
		var tex := _vp.get_texture()
		var o := Vector2(origin) * T
		for r in _runs:
			draw_texture_rect_region(tex, Rect2(o + r.position, r.size), r)
