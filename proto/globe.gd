class_name ProtoGlobe
extends RefCounted
## Вся планета-шар для радара (ProtoRadar) и карты (ProtoMapView), когда робот
## ушёл с участка: разведанное по всему шару (равнопромежуточная развёртка,
## туман войны), рельеф вокруг робота для радара (запекается в потоке, пока
## робот идёт) и сетки глобуса для карты (рельеф с преувеличенной высотой и моря).
## Всё — в системе планеты (ProtoPlanetStream: шар повёрнут под роботом).

const W := 512                 # развёртка разведанного: ~10 м на пиксель у экватора
const H := 256
const REVEAL_R := 45.0         # м вокруг робота открываются на глобусе
const PATCH := 44.0            # полуширина рельефа радара, м (радар до обода — 28 м)
const PATCH_PX := 128
const REBAKE := 12.0           # робот отошёл от середины рельефа радара — запечь новый
const GLOBE_R := 50.0          # радиус глобуса на карте, ед.
const EXAG := 2.0              # высоты на глобусе — во столько раз выше
const GLOBE_CELLS := 40        # клеток на грань глобуса

var terrain: ProtoTerrain
var stream: ProtoPlanetStream
var fill: ProtoPlanetFill
var factory := Vector3.ZERO    # завод (система планеты) — метка на глобусе и стрелка радара
var fog: ImageTexture
var patch := {}                # tex, o (середина, система планеты), e1, e3
var globe_mesh: ArrayMesh      # рельеф глобуса (null — ещё строится)
var sea_mesh: ArrayMesh
var _fog_img: Image
var _dirty := false
var _last := Vector3.INF
var _baking := false
var _globe_task := -1
var _globe_arr: Array = []

func _init(s: ProtoPlanetStream, f: ProtoPlanetFill) -> void:
	stream = s
	terrain = s.terrain
	fill = f
	_fog_img = Image.create(W, H, false, Image.FORMAT_L8)
	fog = ImageTexture.create_from_image(_fog_img)

## Далеко ли робот (система планеты) от участка — тогда радар и карта про шар.
func away(q: Vector3) -> bool:
	return terrain.out_dist(q.x, q.z) > 6.0 or q.y < -30.0

# ---------------------------------------------------------------- разведанное

## Пиксель развёртки для направления d.
static func dir_px(d: Vector3) -> Vector2:
	return Vector2((atan2(d.z, d.x) / TAU + 0.5) * W, acos(clampf(d.y, -1.0, 1.0)) / PI * H)

static func px_dir(i: float, j: float) -> Vector3:
	var lon := i / W * TAU - PI
	var co := j / H * PI
	return Vector3(sin(co) * cos(lon), cos(co), sin(co) * sin(lon))

func reveal(q: Vector3) -> void:
	if q.distance_to(_last) < 4.0:
		return
	_last = q
	var d := (q - terrain.center).normalized()
	var ang := REVEAL_R / terrain.radius
	var c := dir_px(d)
	var rj := ang / PI * H + 1.0
	for j in range(maxi(0, int(c.y - rj)), mini(H, int(c.y + rj) + 1)):
		var s := maxf(sin((j + 0.5) / H * PI), 0.02)
		var ri := minf(rj / s, W * 0.5)
		for ii in range(int(c.x - ri), int(c.x + ri) + 1):
			var i := posmod(ii, W)
			var a := acos(clampf(px_dir(i + 0.5, j + 0.5).dot(d), -1.0, 1.0))
			var v := clampf((ang - a) / ang * 3.0, 0.0, 1.0)
			if v > _fog_img.get_pixel(i, j).r:
				_fog_img.set_pixel(i, j, Color(v, v, v))
				_dirty = true
				_share = -1.0

func flush() -> void:
	if _dirty:
		_dirty = false
		fog.update(_fog_img)

## Доля разведанной поверхности шара (по площади), 0..1.
func explored_share() -> float:
	if _share >= 0.0:
		return _share
	var raw := _fog_img.get_data()
	var sum := 0.0
	var tot := 0.0
	for j in H:
		var s := sin((j + 0.5) / H * PI)
		var row := 0
		for i in W:
			row += raw[j * W + i]
		sum += row * s
		tot += 255.0 * W * s
	_share = sum / tot
	return _share

var _share := -1.0             # доля разведанного (сбрасывается, когда открылось новое)

func save_dict() -> Dictionary:
	return {"fog": Marshalls.raw_to_base64(_fog_img.get_data())}

func load_dict(d: Dictionary) -> void:
	var raw := Marshalls.base64_to_raw(str(d.get("fog", "")))
	if raw.size() == W * H:
		_fog_img.set_data(W, H, false, Image.FORMAT_L8, raw)
		_dirty = true
		_share = -1.0
		flush()

func reveal_all() -> void:
	_fog_img.fill(Color.WHITE)
	_dirty = true
	_share = -1.0
	flush()

# ---------------------------------------------------------------- рельеф для радара

## Рельеф вокруг точки q (система планеты); пока новый запекается в потоке —
## прежний. В первый раз — сразу.
func patch_for(q: Vector3) -> Dictionary:
	if patch.is_empty():
		patch = _bake(q)
	elif not _baking and q.distance_to(patch.o) > REBAKE:
		_baking = true
		_bake_task = WorkerThreadPool.add_task(func():
			var p := _bake(q)
			_swap.call_deferred(p), false, "рельеф радара")
	return patch

var _bake_task := -1

## Дождаться потоков (выход из сцены), чтобы они не писали в удалённое.
func finish() -> void:
	if _bake_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_bake_task)
		_bake_task = -1
	if _globe_task >= 0 and globe_mesh == null:
		WorkerThreadPool.wait_for_task_completion(_globe_task)
		_globe_task = -1

func _swap(p: Dictionary) -> void:
	_baking = false
	patch = p

## Цвет рельефа сверху: как у шара (ProtoTerrain._color_h), отмывка с
## северо-запада; море — цветом жидкости, глубже — темнее.
func _bake(q: Vector3) -> Dictionary:
	var t := terrain
	var R := t.radius
	var d0 := (q - t.center).normalized()
	var e1 := d0.cross(Vector3.FORWARD if absf(d0.z) < 0.9 else Vector3.RIGHT).normalized()
	var e3 := e1.cross(d0)
	var n := PATCH_PX
	var cell := PATCH * 2.0 / n
	var hs := PackedFloat32Array()
	var ps := PackedVector3Array()
	hs.resize(n * n)
	ps.resize(n * n)
	for j in n:
		for i in n:
			var u := -PATCH + (i + 0.5) * cell
			var v := -PATCH + (j + 0.5) * cell
			var d := (d0 * R + e1 * u + e3 * v).normalized()
			var h := t.sphere_h(d)
			hs[j * n + i] = h
			ps[j * n + i] = t.center + d * (R + h)
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	var sea := t.sea_level
	var sea_c: Color = fill.sea_sub.color if fill != null and fill.sea_sub != null else Color.BLACK
	for j in n:
		for i in n:
			var h := hs[j * n + i]
			var hx := hs[j * n + mini(i + 1, n - 1)] - hs[j * n + maxi(i - 1, 0)]
			var hz := hs[mini(j + 1, n - 1) * n + i] - hs[maxi(j - 1, 0) * n + i]
			var nrm := Vector3(-hx / (cell * 2.0), 1.0, -hz / (cell * 2.0)).normalized()
			var c: Color
			if h < sea:
				c = sea_c.darkened(0.15 + clampf((sea - h) / 12.0, 0.0, 0.5))
			else:
				var fk := ProtoTerrain.far_key(ps[j * n + i])
				c = t._color_h(Vector3(fk.x, h, fk.y), Vector3(sqrt(maxf(0.0, 1.0 - nrm.y * nrm.y)), nrm.y, 0.0), 0.0, h)
				var shade := clampf(0.75 + nrm.dot(Vector3(-0.6, 0.7, -0.6).normalized()) * 0.45, 0.45, 1.25)
				c = c * shade
			img.set_pixel(i, j, Color(c.r, c.g, c.b))
	return {"tex": ImageTexture.create_from_image(img), "o": q, "d0": d0, "e1": e1, "e3": e3}

## Точка p (система планеты) → uv рельефа радара.
func patch_uv(p: Vector3) -> Vector2:
	var v: Vector3 = p - (patch.o as Vector3)
	return Vector2(v.dot(patch.e1), v.dot(patch.e3)) / (PATCH * 2.0) + Vector2(0.5, 0.5)

# ---------------------------------------------------------------- глобус для карты

## Сетки глобуса: строятся в потоке при первом вызове; готовы — ready() true.
func prepare() -> void:
	if _globe_task >= 0 or globe_mesh != null:
		return
	var sea: Array = fill.sea_mi.mesh.surface_get_arrays(0) if fill != null and fill.sea_mi != null else []
	_globe_task = WorkerThreadPool.add_task(func(): _globe_arr = _globe_arrays(sea), false, "глобус")

func ready() -> bool:
	if globe_mesh != null:
		return true
	if _globe_task < 0 or not WorkerThreadPool.is_task_completed(_globe_task):
		return false
	WorkerThreadPool.wait_for_task_completion(_globe_task)
	globe_mesh = ArrayMesh.new()
	globe_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _globe_arr[0])
	if not _globe_arr[1].is_empty():
		sea_mesh = ArrayMesh.new()
		sea_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _globe_arr[1])
	_globe_arr = []
	return true

## Точка шара (система планеты) → точка глобуса (от его середины).
func to_globe(p: Vector3, lift := 0.0) -> Vector3:
	var v := p - terrain.center
	var r := v.length()
	return v / r * (GLOBE_R + ((r - terrain.radius) * EXAG + lift) * GLOBE_R / terrain.radius)

func _globe_arrays(sa: Array) -> Array:
	var parts: Array = []
	for f in 6:
		parts.append(stream._grid(f, 0.0, 0.0, 1.0 / GLOBE_CELLS, GLOBE_CELLS, false, true))
	var arr := stream._merge(parts)
	var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	for i in vs.size():
		vs[i] = to_globe(vs[i])
	arr[Mesh.ARRAY_VERTEX] = vs
	# Нормали — по новой (преувеличенной) форме.
	var ns := PackedVector3Array()
	ns.resize(vs.size())
	var ix: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	for k in range(0, ix.size(), 3):
		var fn := (vs[ix[k + 2]] - vs[ix[k]]).cross(vs[ix[k + 1]] - vs[ix[k]])
		if fn.dot(vs[ix[k]]) < 0.0:
			fn = -fn
		for m in 3:
			ns[ix[k + m]] += fn
	for i in ns.size():
		ns[i] = ns[i].normalized()
	arr[Mesh.ARRAY_NORMAL] = ns
	var sea: Array = []
	if not sa.is_empty():
		var sv: PackedVector3Array = sa[Mesh.ARRAY_VERTEX]
		var sn := PackedVector3Array()
		sn.resize(sv.size())
		for i in sv.size():
			sv[i] = to_globe(sv[i], 0.5)
			sn[i] = sv[i].normalized()
		sea.resize(Mesh.ARRAY_MAX)
		sea[Mesh.ARRAY_VERTEX] = sv
		sea[Mesh.ARRAY_NORMAL] = sn
	return [arr, sea]
