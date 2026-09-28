class_name ProtoPlanetStream
extends Node3D
## Планета-шар вокруг участка. Участок (завод, пещера, озеро) — площадка на
## «макушке» шара; по шару можно обойти всю планету.
## Шар поворачивается под роботом: робот всегда на макушке, мировая ось Y у него
## смотрит от центра планеты, поэтому ходьба, прыжки, камера и стройка остаются
## прежними (Y вверх). У завода (ближе CORE м) шар не повёрнут вовсе — система
## планеты совпадает с миром, всё про участок работает как раньше.
## Сетки: весь шар грубо (кубосфера), а у робота — подробные куски (1 м рядом,
## 4 м дальше) с телом для ног; грубый шар под ними опущен в шейдере (sink).

const CH := 64.0              # примерная сторона куска по поверхности, м
const DETAIL := 200.0         # подробные куски — до стольких м от робота
const FINE := 100.0           # ближе — шаг 1 м и тело для ног
const SKIRT := 3.0            # «юбка» под краем куска: прячет щели между шагами
const CORE := 30.0            # у завода шар не поворачивается
const CORE_OUT := 60.0        # к этому расстоянию робот уже ровно на макушке
const COARSE := 64            # клеток на грань грубого шара
const SITE_HIDE := 450.0      # дальше (по дуге) участок за горизонтом — прячем

var terrain: ProtoTerrain
var mat: ShaderMaterial       # подробные куски (тот же, что у участка)
var coarse_mat: ShaderMaterial
var target: Node3D            # робот
var cam: Camera3D
var n_face := 20              # кусков на ребро грани
var chunks := {}              # Vector3i(грань, i, j) → {"mi", "step", "want"}
var coarse_mi: MeshInstance3D
var frame := Transform3D.IDENTITY   # планета → мир
## Предметы участка (машины, грибы, жидкости…): вместе с шаром.
var site_nodes: Array = []
var _site_base := {}          # узел → исходный transform (в системе планеты)
var _site_hidden := false
var _last_pick := Vector3.INF
var _centers := PackedVector3Array()   # направления на середины всех кусков
var _keys: Array = []

static func create(t: ProtoTerrain, m: ShaderMaterial, who: Node3D, camera: Camera3D, r := 800.0) -> ProtoPlanetStream:
	var s := ProtoPlanetStream.new()
	s.name = "planet"
	s.process_priority = 100    # после игрока: сначала шаг робота, потом поворот шара
	t.make_sphere(r)
	s.terrain = t
	s.mat = m
	s.coarse_mat = t.material()
	s.coarse_mat.set_shader_parameter("sink", 6.0)
	s.coarse_mat.set_shader_parameter("sink_center", t.center)
	s.target = who
	s.cam = camera
	s.n_face = maxi(4, int(round(r * PI * 0.5 / CH)))
	for f in 6:
		for j in s.n_face:
			for i in s.n_face:
				s._keys.append(Vector3i(f, i, j))
				s._centers.append(s._dir(f, (i + 0.5) / s.n_face, (j + 0.5) / s.n_face))
	return s

## Сразу весь шар и куски вокруг робота (при загрузке): в потоках разом.
func build_now() -> void:
	for n: Node3D in site_nodes:
		_site_base[n] = n.transform
	_jobs = []
	for f in 6:
		_jobs.append([Vector3i(f, 0, 0), -1.0])
	for k: Vector3i in _pick():
		_jobs.append([k, _step_for(k)])
	_out = []
	_out.resize(_jobs.size())
	var id := WorkerThreadPool.add_group_task(_job, _jobs.size(), -1, true, "планета")
	WorkerThreadPool.wait_for_group_task_completion(id)
	_coarse_ready(_merge(_out.slice(0, 6)))
	for i in range(6, _jobs.size()):
		var k: Vector3i = _jobs[i][0]
		var st: float = _jobs[i][1]
		chunks[k] = {"want": st}
		_chunk_ready(k, st, _out[i])
	_last_pick = local_pos()
	_jobs = []
	_out = []

# Общие для потоков build_now: пишем в члены, не в захваченные локальные.
var _jobs: Array = []
var _out: Array = []

func _job(i: int) -> void:
	var k: Vector3i = _jobs[i][0]
	var st: float = _jobs[i][1]
	_out[i] = _grid(k.x, 0.0, 0.0, 1.0 / COARSE, COARSE, false) if st < 0.0 else _chunk_arrays(k, st)

func _process(dt: float) -> void:
	if target == null:
		return
	if _around >= 0.0:
		_around_step(dt)
	_turn()
	# Для радара и карты: где робот на участке (система планеты) и поворот шара.
	target.set_meta("planet_pos", local_pos())
	target.set_meta("planet_turn", frame.basis)
	if cam:
		var e := cam.global_position
		mat.set_shader_parameter("eye", e)
		coarse_mat.set_shader_parameter("eye", e)
	_feed()
	var q := local_pos()
	if q.distance_to(_last_pick) < 8.0:
		return
	_last_pick = q
	var want := {}
	_queue.clear()
	for k: Vector3i in _pick():
		var st := _step_for(k)
		want[k] = true
		var ch: Dictionary = chunks.get(k, {})
		if ch.is_empty() or (ch.want != st and ch.step != st):
			chunks[k] = {"mi": ch.get("mi"), "step": ch.get("step", 0.0), "want": st}
		if chunks[k].want != chunks[k].step:
			_queue.append(k)
	# Ближние — первыми.
	var d := (q - terrain.center).normalized()
	_queue.sort_custom(func(a: Vector3i, b: Vector3i) -> bool:
		return _dir(a.x, (a.y + 0.5) / n_face, (a.z + 0.5) / n_face).distance_to(d) \
			< _dir(b.x, (b.y + 0.5) / n_face, (b.z + 0.5) / n_face).distance_to(d))
	for k: Vector3i in chunks.keys():
		if not want.has(k):
			var mi: MeshInstance3D = chunks[k].get("mi")
			if mi:
				mi.queue_free()
			chunks.erase(k)

## Робот в системе планеты.
func local_pos() -> Vector3:
	return frame.affine_inverse() * target.position

## Поворот шара под роботом: робот (и камера) остаются на месте относительно
## рельефа, а шар поворачивается так, чтобы робот был на макушке. У завода —
## без поворота, в переходе — частично.
func _turn() -> void:
	var q := local_pos()
	var f := frame_for(q)
	if f.is_equal_approx(frame):
		return
	var delta := f * frame.affine_inverse()
	target.position = f * q
	if cam:
		cam.global_transform = delta * cam.global_transform
	frame = f
	transform = f
	terrain.set_frame(f)
	# Участок за горизонтом не виден: прячем и не двигаем (там сотни узлов).
	var far := _arc(q) > SITE_HIDE
	if far and _site_hidden:
		return
	for n: Node3D in site_nodes:
		if is_instance_valid(n) and _site_base.has(n):
			n.visible = not far
			if not far:
				n.transform = f * _site_base[n]
	_site_hidden = far

## Расстояние по дуге от середины участка до точки q (система планеты).
func _arc(q: Vector3) -> float:
	var d := (q - terrain.center).normalized()
	return acos(clampf(d.y, -1.0, 1.0)) * terrain.radius

## Поворот шара для робота в точке q (система планеты).
func frame_for(q: Vector3) -> Transform3D:
	var c := terrain.center
	var d := (q - c).normalized()
	var s := smoothstep(CORE, CORE_OUT, _arc(q))
	if s <= 0.0:
		return Transform3D.IDENTITY
	var rot := Quaternion.IDENTITY.slerp(arc(d, Vector3.UP), s)
	var b := Basis(rot)
	return Transform3D(b, c - b * c)

## Поворот от a к b (единичные), и когда они почти противоположны.
static func arc(a: Vector3, b: Vector3) -> Quaternion:
	var cr := a.cross(b)
	var w := 1.0 + a.dot(b)
	if w < 1.0e-4:
		var ax := a.cross(Vector3.RIGHT if absf(a.x) < 0.9 else Vector3.FORWARD).normalized()
		return Quaternion(ax, PI)
	return Quaternion(cr.x, cr.y, cr.z, w).normalized()

## Направление на точку грани f с долями (u, v) ∈ [0, 1] — равноугольная кубосфера.
func _dir(f: int, u: float, v: float) -> Vector3:
	var a := tan((u - 0.5) * PI * 0.5)
	var b := tan((v - 0.5) * PI * 0.5)
	var p: Vector3
	match f:
		0: p = Vector3(a, 1.0, b)       # верх: здесь участок, a и b — вдоль x и z
		1: p = Vector3(a, -1.0, -b)
		2: p = Vector3(1.0, -a, b)
		3: p = Vector3(-1.0, a, b)
		4: p = Vector3(a, b, 1.0)
		_: p = Vector3(-a, b, -1.0)
	return p.normalized()

## Какие куски нужны у робота.
func _pick() -> Array:
	var d := (local_pos() - terrain.center).normalized()
	var lim := 2.0 * sin(DETAIL / terrain.radius * 0.5)
	var out: Array = []
	for i in _centers.size():
		if _centers[i].distance_to(d) < lim:
			out.append(_keys[i])
	return out

func _step_for(k: Vector3i) -> float:
	var d := (local_pos() - terrain.center).normalized()
	var c := _dir(k.x, (k.y + 0.5) / n_face, (k.z + 0.5) / n_face)
	return 1.0 if acos(clampf(c.dot(d), -1.0, 1.0)) * terrain.radius < FINE else 4.0

## Куски строятся по очереди, не больше _max_busy сразу: на слабом процессоре
## пачка кусков в потоках иначе отнимает ядра у самой игры.
var _queue: Array = []
var _busy := 0
var _building := {}           # кусок → шаг, который сейчас строится
var _max_busy := maxi(1, OS.get_processor_count() / 4)

func _feed() -> void:
	while _busy < _max_busy and not _queue.is_empty():
		var k: Vector3i = _queue.pop_front()
		var ch: Dictionary = chunks.get(k, {})
		if ch.is_empty() or ch.want == ch.step or _building.get(k, -1.0) == ch.want:
			continue
		_busy += 1
		_building[k] = ch.want
		WorkerThreadPool.add_task(_build_chunk.bind(k, ch.want), false, "кусок рельефа")

func _build_chunk(k: Vector3i, st: float) -> void:
	var arr := _chunk_arrays(k, st)
	call_deferred("_chunk_built", k, st, arr)

func _chunk_built(k: Vector3i, st: float, arr: Array) -> void:
	_busy -= 1
	_building.erase(k)
	_chunk_ready(k, st, arr)

func _chunk_ready(k: Vector3i, st: float, arr: Array) -> void:
	var ch: Dictionary = chunks.get(k, {})
	if ch.is_empty() or ch.want != st:
		return          # кусок уже не нужен или нужен с другим шагом
	var old: MeshInstance3D = ch.get("mi")
	if old:
		old.queue_free()
	var mi: MeshInstance3D = null
	if not arr.is_empty():
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr.slice(0, Mesh.ARRAY_MAX))
		mi = MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = mat
		if st > 1.0:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		if arr.size() > Mesh.ARRAY_MAX:
			# Тело для ног робота: форма собрана в потоке вместе с сеткой.
			var body := StaticBody3D.new()
			body.name = "ground_collision"
			body.collision_layer = RobotGround.LAYER
			body.collision_mask = 0
			var cs := CollisionShape3D.new()
			cs.shape = arr[Mesh.ARRAY_MAX]
			body.add_child(cs)
			mi.add_child(body)
	chunks[k] = {"mi": mi, "step": st, "want": st}

func _coarse_ready(arr: Array) -> void:
	coarse_mi = MeshInstance3D.new()
	coarse_mi.name = "coarse"
	coarse_mi.material_override = coarse_mat
	coarse_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	coarse_mi.mesh = mesh
	add_child(coarse_mi)

func _chunk_arrays(k: Vector3i, st: float) -> Array:
	var n := maxi(1, int(round(terrain.radius * PI * 0.5 / n_face / st)))
	var u0 := float(k.y) / n_face
	var v0 := float(k.z) / n_face
	var du := 1.0 / n_face / n
	var arr := _grid(k.x, u0, v0, du, n, true)
	if st <= 1.0 and not arr.is_empty():
		var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var faces := PackedVector3Array()
		for i: int in arr[Mesh.ARRAY_INDEX]:
			faces.append(vs[i])
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(faces)
		arr.append(shape)
	return arr

## Весь шар: шесть граней (сетки _grid с шагом COARSE) в одну.
func _merge(parts: Array) -> Array:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	for a: Array in parts:
		if a.is_empty():
			continue
		var base := verts.size()
		verts.append_array(a[Mesh.ARRAY_VERTEX])
		norms.append_array(a[Mesh.ARRAY_NORMAL])
		cols.append_array(a[Mesh.ARRAY_COLOR])
		var ix: PackedInt32Array = a[Mesh.ARRAY_INDEX]
		for i in ix.size():
			ix[i] += base
		idx.append_array(ix)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_INDEX] = idx
	return arr

## Сетка (n + 1)² узлов на грани f от (u0, v0) с шагом du. Клетки внутри участка
## (у него свой объёмный рельеф) пропускаются; skirt — полоса вниз по краю.
func _grid(f: int, u0: float, v0: float, du: float, n: int, skirt: bool) -> Array:
	var t := terrain
	var c := t.center
	var m := n + 1
	var dirs := PackedVector3Array()
	var ps := PackedVector3Array()
	dirs.resize(m * m)
	ps.resize(m * m)
	for j in m:
		for i in m:
			var d := _dir(f, u0 + i * du, v0 + j * du)
			dirs[j * m + i] = d
			ps[j * m + i] = c + d * (t.radius + t.sphere_h(d))
	var eps := clampf(du * PI * 0.5, 0.5 / t.radius, 4.0 / t.radius)
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	verts.resize(m * m)
	norms.resize(m * m)
	cols.resize(m * m)
	for j in m:
		for i in m:
			var id := j * m + i
			var d := dirs[id]
			var nrm: Vector3
			if i > 0 and j > 0 and i < n and j < n:
				nrm = (ps[id + m] - ps[id - m]).cross(ps[id + 1] - ps[id - 1]).normalized()
			else:
				# По краю — по рельефу в двух соседних направлениях: у соседнего
				# куска или грани та же нормаль, без полос освещения по швам.
				var e1 := d.cross(Vector3.UP if absf(d.y) < 0.9 else Vector3.RIGHT).normalized()
				var e2 := d.cross(e1)
				var d1 := (d + e1 * eps).normalized()
				var d2 := (d + e2 * eps).normalized()
				var ta := c + d1 * (t.radius + t.sphere_h(d1)) - ps[id]
				var tb := c + d2 * (t.radius + t.sphere_h(d2)) - ps[id]
				nrm = ta.cross(tb).normalized()
			if nrm.dot(d) < 0.0:
				nrm = -nrm
			verts[id] = ps[id]
			norms[id] = nrm
			# Цвет — как у участка, в местной системе «вверх = от центра».
			var ny := nrm.dot(d)
			var hgt := (ps[id] - c).length() - t.radius
			var lp := Vector3(ps[id].x + ps[id].y * 0.37, hgt, ps[id].z - ps[id].y * 0.61)
			var col := t._color_h(lp, Vector3(sqrt(maxf(0.0, 1.0 - ny * ny)), ny, 0.0), 0.0, hgt)
			col.a = 1.0
			cols[id] = col
	var idx := PackedInt32Array()
	var site := Rect2(1.0, 1.0, t.sx - 2.0, t.sz - 2.0)
	# Обход вершин — как у верхней грани (у граней разная ориентация осей u, v).
	var flip := (dirs[1] - dirs[0]).cross(dirs[m] - dirs[0]).dot(dirs[0]) > 0.0
	for j in n:
		for i in n:
			var a := j * m + i
			if f == 0:
				var r := Rect2(_on_top(dirs[a]), Vector2.ZERO).expand(_on_top(dirs[a + m + 1]))
				if site.encloses(r):
					continue
			if flip:
				idx.append_array([a, a + m, a + 1, a + 1, a + m, a + m + 1])
			else:
				idx.append_array([a, a + 1, a + m, a + 1, a + m + 1, a + m])
	if skirt:
		var edge: Array = []
		for i in m:
			edge.append(i)
		for j in range(1, m):
			edge.append(j * m + n)
		for i in range(n - 1, -1, -1):
			edge.append(n * m + i)
		for j in range(n - 1, -1, -1):
			edge.append(j * m)
		var base := verts.size()
		for e: int in edge:
			verts.append(verts[e] - dirs[e] * SKIRT)
			norms.append(norms[e])
			cols.append(cols[e].darkened(0.2))
		for j in edge.size() - 1:
			var a: int = edge[j]
			var b: int = edge[j + 1]
			idx.append_array([a, b, base + j, b, base + j + 1, base + j])
	if idx.is_empty():
		return []
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_INDEX] = idx
	return arr

## Точка на касательной плоскости макушки (x, z участка) для направления d.
func _on_top(d: Vector3) -> Vector2:
	var t := terrain
	var k := (t.radius + 16.0) / maxf(d.y, 0.01)
	return Vector2(t.center.x + d.x * k, t.center.z + d.z * k)

# --- --auto=around: робот бегом обходит планету, кадры в пути ---
var _around := -1.0           # пройдено, м (−1 — выкл.)
var _around_ms: Array = []
var _around_shots: Array = []
var _around_prefix := ""
var _around_t := 0

func auto_around(prefix: String) -> void:
	_around = 0.0
	_around_prefix = prefix
	_around_shots = [0.25, 0.5, 0.75, 0.999]
	_around_t = Time.get_ticks_usec()

func _around_step(dt: float) -> void:
	var now := Time.get_ticks_usec()
	_around_ms.append((now - _around_t) / 1000.0)
	_around_t = now
	var v := 45.0
	_around += v * dt
	target.position.x += v * dt
	target.position.y = terrain.surface_h(target.position.x, target.position.z)
	target.rotation.y = PI * 0.5
	var f := _around / (TAU * terrain.radius)
	if not _around_shots.is_empty() and f >= _around_shots[0]:
		_around_shots.pop_front()
		if _around_prefix != "" and DisplayServer.get_name() != "headless":
			get_viewport().get_texture().get_image().save_png("%s_%d.png" % [_around_prefix, int(f * 100)])
	if f >= 1.0:
		var ms := _around_ms.duplicate()
		ms.sort()
		var avg := 0.0
		for x: float in ms:
			avg += x
		avg /= maxf(ms.size(), 1)
		var q := local_pos()
		print("Обход планеты: %d м, кадр %.1f мс в среднем (p95 %.1f, макс %.1f), вернулся к заводу: %.1f м от середины участка" % [
			int(TAU * terrain.radius), avg, ms[int(ms.size() * 0.95)], ms[-1],
			Vector2(q.x - terrain.sx * 0.5, q.z - terrain.sz * 0.5).length()])
		_around = -1.0
		get_tree().quit()
