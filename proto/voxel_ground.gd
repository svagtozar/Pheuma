class_name ProtoVoxelGround
extends Node3D
## Рельеф участка на Voxel Tools (VoxelLodTerrain + Transvoxel): сетки, LOD и
## коллизия строятся в C++ в потоках модуля. Воксель LOD 0 — 0,5 м (узел
## VoxelLodTerrain уменьшен вдвое), дальше от наблюдателя — 1, 2, 4 м.
## Источник правды — по-прежнему ProtoTerrain: поле плотности отдаёт генератор
## (ProtoVoxelGen), правка рельефа (бур, кисть, сохранение) меняет поле
## ProtoTerrain и вставляется в воксели VoxelTool'ом (paste).
## Цвет породы — не в вершинах (их строит модуль), а в 3D-текстуре по узлам 1 м:
## тот же ProtoTerrain._color_h с нормалью по полю; шейдер берёт его в вершине.

# Без Voxel Tools (нет библиотеки рядом с игрой) этот файл должен собираться:
# типы модуля здесь не упоминаются, генератор грузится по пути.
const VOXEL := 0.5              # м на воксель LOD 0 (ProtoVoxelGen.VOXEL)
const GEN := "res://proto/voxel_gen.gd"
const LOD_COUNT := 4
const LOD_DIST := 16.0          # м: LOD 0 (0,5 м) — ближе стольких метров от наблюдателя
const VIEW := 160.0             # м: видно весь участок с любого его края
const SITE_XF := &"pv_site_from_world"   # глобальный параметр шейдера: мир → участок

var terrain: ProtoTerrain
var vt: Node3D                  # VoxelLodTerrain
var tool: Object                # VoxelToolLodTerrain
var gen: Object                 # ProtoVoxelGen
var material: ShaderMaterial
var rebuilt := 0                # сколько правок вставлено (для тестов и лога)
var chunks: Array = []          # для совместимости с ProtoTerrainChunks (кусков нет)
var _queue: Array = []          # области правок, ждущие вставки
var _col := PackedByteArray()   # RGBA8 по узлам 1 м: цвет породы, a — видимость неба
var _vein := PackedByteArray()  # R8: маска жилы
var _fcol := PackedByteArray()  # то же по узлам 0,5 м в коробке пещеры
var _fvein := PackedByteArray()
var _col_tex: ImageTexture3D
var _vein_tex: ImageTexture3D
var _fcol_tex: ImageTexture3D
var _fvein_tex: ImageTexture3D
var _n := Vector3i.ZERO         # узлов поля
var _last_xf := Transform3D()
static var _site_xf_added := false

static func available() -> bool:
	return ClassDB.class_exists("VoxelLodTerrain")

## Всё сразу: поле → генератор, цвет → текстуры, узел рельефа. Сетки модуль
## строит в следующих кадрах (ready() — готова ли сетка у точки).
func build(t: ProtoTerrain, base: ShaderMaterial = null) -> void:
	terrain = t
	_n = Vector3i(t.sx + 1, t.sy + 1, t.sz + 1)
	gen = load(GEN).new()
	gen.load_field(t)
	gen.load_fine(t, t.cave_box)
	_bake_colors()
	material = voxel_material(t, base)
	material.set_shader_parameter("col3d", _col_tex)
	material.set_shader_parameter("vein3d", _vein_tex)
	material.set_shader_parameter("field_n", Vector3(_n))
	material.set_shader_parameter("fcol3d", _fcol_tex)
	material.set_shader_parameter("fvein3d", _fvein_tex)
	material.set_shader_parameter("fine_o", Vector3(gen.fine_o) * VOXEL)
	material.set_shader_parameter("fine_n", Vector3(gen.fine_n))
	vt = ClassDB.instantiate("VoxelLodTerrain")
	vt.name = "voxels"
	vt.scale = Vector3.ONE * VOXEL
	# SDF во float32: поле копируется в блоки как есть, без квантования.
	var fmt: Resource = ClassDB.instantiate("VoxelFormat")
	fmt.set("sdf_depth", 2)     # VoxelBuffer.DEPTH_32_BIT
	vt.set("format", fmt)
	vt.set("generator", gen)
	vt.set("mesher", ClassDB.instantiate("VoxelMesherTransvoxel"))
	vt.set("voxel_bounds", AABB(Vector3.ZERO, Vector3(t.sx, t.sy, t.sz) / VOXEL))
	vt.set("lod_count", LOD_COUNT)
	vt.set("lod_distance", LOD_DIST / VOXEL)
	vt.set("view_distance", int(VIEW / VOXEL))
	vt.set("mesh_block_size", 32)   # меньше кусков — меньше вызовов отрисовки
	vt.set("generate_collisions", true)
	vt.set("collision_lod_count", 1)
	vt.set("collision_layer", RobotGround.LAYER)
	vt.set("collision_mask", 0)
	vt.set("threaded_update_enabled", true)
	vt.set("material", material)
	add_child(vt)
	tool = vt.call("get_voxel_tool")

## Наблюдатель (робот, камера): вокруг него модуль держит LOD 0 и коллизию.
static func add_viewer(who: Node3D) -> Node3D:
	var v: Node3D = ClassDB.instantiate("VoxelViewer")
	v.name = "voxel_viewer"
	v.set("view_distance", int(VIEW / VOXEL))
	who.add_child(v)
	return v

## Готова ли сетка LOD 0 в области box (метры, система участка).
func is_meshed(box: AABB) -> bool:
	var b := AABB(box.position / VOXEL, box.size / VOXEL)
	return vt.call("is_area_meshed", b, 0)

func _process(_dt: float) -> void:
	if global_transform != _last_xf:
		_last_xf = global_transform
		RenderingServer.global_shader_parameter_set(SITE_XF, Projection(global_transform.affine_inverse()))
	if not _queue.is_empty():
		_apply(_queue.pop_front())

# ---------------------------------------------------------------- правки

## Правка рельефа в области box (поле ProtoTerrain уже поправлено): в воксели
## и в цвет — по области за кадр (now — сразу). Возвращает 1 (как число кусков).
func rebuild(box: AABB, now := false) -> int:
	_queue.append(box)
	if now:
		flush()
	return 1

func flush() -> void:
	while not _queue.is_empty():
		_apply(_queue.pop_front())

func pending() -> int:
	return _queue.size()

func _apply(box: AABB) -> void:
	box = box.grow(1.0)
	var lo := Vector3i(box.position.floor())
	var hi := Vector3i(box.end.ceil())
	gen.refresh(lo, hi)
	gen.refresh_fine(terrain, box)
	# LOD 0 в области — как у генератора, и вставить в воксели.
	var vlo := (Vector3i((box.position / VOXEL).floor())).max(Vector3i.ZERO)
	var vhi := Vector3i((box.end / VOXEL).ceil()).min(Vector3i(_n - Vector3i.ONE) * 2)
	var n := vhi - vlo + Vector3i.ONE
	if n.x > 0 and n.y > 0 and n.z > 0:
		tool.call("paste", vlo, gen.lod0_buffer(vlo, n), gen.sdf_mask())
	# Цвет узлов вокруг — заново (обрыв стал полом, пол — стенкой).
	var clo := (lo - Vector3i.ONE).max(Vector3i.ZERO)
	var chi := (hi + Vector3i.ONE).min(_n - Vector3i.ONE)
	for z in range(clo.z, chi.z + 1):
		_bake_slice(z, clo, chi)
	var fo: Vector3i = gen.fine_o
	var flo: Vector3i = (Vector3i(((box.position - Vector3.ONE) / VOXEL).floor()) - fo).max(Vector3i.ZERO)
	var fhi: Vector3i = (Vector3i(((box.end + Vector3.ONE) / VOXEL).ceil()) - fo).min(gen.fine_n - Vector3i.ONE)
	for z in range(flo.z, fhi.z + 1):
		_bake_fine_slice(z, flo, fhi)
	_upload()
	rebuilt += 1

# ---------------------------------------------------------------- цвет

## Цвет по узлам 1 м у поверхности (где рядом по осям меняется знак поля):
## остальные узлы шейдер у поверхности не берёт.
func _bake_colors() -> void:
	_col = PackedByteArray()
	_col.resize(_n.x * _n.y * _n.z * 4)
	_vein = PackedByteArray()
	_vein.resize(_n.x * _n.y * _n.z)
	var fn: Vector3i = gen.fine_n
	_fcol = PackedByteArray()
	_fcol.resize(fn.x * fn.y * fn.z * 4)
	_fvein = PackedByteArray()
	_fvein.resize(fn.x * fn.y * fn.z)
	var id := WorkerThreadPool.add_group_task(_bake_slice.bind(Vector3i.ZERO, _n - Vector3i.ONE), _n.z, -1, true, "цвет рельефа")
	var id2 := WorkerThreadPool.add_group_task(_bake_fine_slice.bind(Vector3i.ZERO, fn - Vector3i.ONE), fn.z, -1, true, "цвет пещеры")
	WorkerThreadPool.wait_for_group_task_completion(id)
	WorkerThreadPool.wait_for_group_task_completion(id2)
	_upload()

const NEAR := [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1),
	Vector3i(2, 0, 0), Vector3i(-2, 0, 0), Vector3i(0, 2, 0), Vector3i(0, -2, 0), Vector3i(0, 0, 2), Vector3i(0, 0, -2)]

func _bake_slice(z: int, lo: Vector3i, hi: Vector3i) -> void:
	var t := terrain
	var dens := t.dens
	var sxn := _n.x
	var sxy := _n.x * _n.y
	for x in range(lo.x, hi.x + 1):
		var h := t.surface_h(x, z)
		for y in range(lo.y, hi.y + 1):
			var i := x + sxn * y + sxy * z
			var d := dens[i]
			var near := false
			if absf(d) < 6.0:
				for o: Vector3i in NEAR:
					var q := Vector3i(x, y, z) + o
					if q.x < 0 or q.y < 0 or q.z < 0 or q.x >= _n.x or q.y >= _n.y or q.z >= _n.z:
						continue
					if (dens[q.x + sxn * q.y + sxy * q.z] > 0.0) != (d > 0.0):
						near = true
						break
			if not near:
				continue
			# Нормаль — по полю (из породы в воздух).
			var g := Vector3(
				dens[i - 1 if x > 0 else i] - dens[i + 1 if x < _n.x - 1 else i],
				dens[i - sxn if y > 0 else i] - dens[i + sxn if y < _n.y - 1 else i],
				dens[i - sxy if z > 0 else i] - dens[i + sxy if z < _n.z - 1 else i])
			var nrm := g.normalized() if g.length_squared() > 1e-8 else Vector3.UP
			var p := Vector3(x, y, z)
			var vm := t._vein_h(p, h)
			var c := t._color_h(p, nrm, vm, h)
			var sky := t._sky_vis_h(p, h)
			var k := i * 4
			_col[k] = clampi(roundi(c.r * 255.0), 0, 255)
			_col[k + 1] = clampi(roundi(c.g * 255.0), 0, 255)
			_col[k + 2] = clampi(roundi(c.b * 255.0), 0, 255)
			_col[k + 3] = clampi(roundi(sky * 255.0), 0, 255)
			_vein[i] = clampi(roundi(vm * 255.0), 0, 255)

## То же для узлов 0,5 м в коробке пещеры (точное поле ProtoVoxelGen.fine).
func _bake_fine_slice(z: int, lo: Vector3i, hi: Vector3i) -> void:
	var t := terrain
	var f: PackedFloat32Array = gen.fine
	var n: Vector3i = gen.fine_n
	var sxn := n.x
	var sxy := n.x * n.y
	for x in range(lo.x, hi.x + 1):
		var p0: Vector3 = Vector3(gen.fine_o + Vector3i(x, 0, z)) * VOXEL
		var h := t.surface_h(p0.x, p0.z)
		for y in range(lo.y, hi.y + 1):
			var i := x + sxn * y + sxy * z
			var d := f[i]
			var near := false
			if absf(d) < 3.0:
				for o: Vector3i in NEAR:
					var q := Vector3i(x, y, z) + o
					if q.x < 0 or q.y < 0 or q.z < 0 or q.x >= n.x or q.y >= n.y or q.z >= n.z:
						continue
					if (f[q.x + sxn * q.y + sxy * q.z] > 0.0) != (d > 0.0):
						near = true
						break
			if not near:
				continue
			var g := Vector3(
				f[i - 1 if x > 0 else i] - f[i + 1 if x < n.x - 1 else i],
				f[i - sxn if y > 0 else i] - f[i + sxn if y < n.y - 1 else i],
				f[i - sxy if z > 0 else i] - f[i + sxy if z < n.z - 1 else i])
			var nrm := g.normalized() if g.length_squared() > 1e-8 else Vector3.UP
			var p: Vector3 = p0 + Vector3(0, (gen.fine_o.y + y) * VOXEL, 0)
			var vm := t._vein_h(p, h)
			var c := t._color_h(p, nrm, vm, h)
			var sky := t._sky_vis_h(p, h)
			var k := i * 4
			_fcol[k] = clampi(roundi(c.r * 255.0), 0, 255)
			_fcol[k + 1] = clampi(roundi(c.g * 255.0), 0, 255)
			_fcol[k + 2] = clampi(roundi(c.b * 255.0), 0, 255)
			_fcol[k + 3] = clampi(roundi(sky * 255.0), 0, 255)
			_fvein[i] = clampi(roundi(vm * 255.0), 0, 255)

## Байты цвета → ImageTexture3D (слой — z, в слое x по ширине, y по высоте).
func _upload() -> void:
	_col_tex = _tex3d(_col_tex, _col, _n, Image.FORMAT_RGBA8, 4)
	_vein_tex = _tex3d(_vein_tex, _vein, _n, Image.FORMAT_R8, 1)
	_fcol_tex = _tex3d(_fcol_tex, _fcol, gen.fine_n, Image.FORMAT_RGBA8, 4)
	_fvein_tex = _tex3d(_fvein_tex, _fvein, gen.fine_n, Image.FORMAT_R8, 1)

static func _tex3d(tex: ImageTexture3D, bytes: PackedByteArray, n: Vector3i, fmt: Image.Format, bpp: int) -> ImageTexture3D:
	var imgs: Array[Image] = []
	var k := n.x * n.y * bpp
	for z in n.z:
		imgs.append(Image.create_from_data(n.x, n.y, false, fmt, bytes.slice(z * k, (z + 1) * k)))
	if tex == null:
		tex = ImageTexture3D.new()
		tex.create(fmt, n.x, n.y, n.z, false, imgs)
	else:
		tex.update(imgs)
	return tex

## Цвет породы в точке (узлы 1 м, трилинейно) — для сеток карты.
func color_at(p: Vector3) -> Color:
	var q := p.clamp(Vector3.ZERO, Vector3(_n - Vector3i.ONE) - Vector3.ONE * 0.001)
	var i0 := Vector3i(q.floor())
	var f := q - Vector3(i0)
	var c := Color(0, 0, 0, 0)
	var w_sum := 0.0
	for dz in 2:
		for dy in 2:
			for dx in 2:
				var w := (f.x if dx else 1.0 - f.x) * (f.y if dy else 1.0 - f.y) * (f.z if dz else 1.0 - f.z)
				var k := ((i0.x + dx) + _n.x * (i0.y + dy) + _n.x * _n.y * (i0.z + dz)) * 4
				c += Color(_col[k] / 255.0, _col[k + 1] / 255.0, _col[k + 2] / 255.0, _col[k + 3] / 255.0) * w
				w_sum += w
	return c / maxf(w_sum, 1e-6)

# ---------------------------------------------------------------- карта

## Сетки для карты (ProtoMapView): весь участок с шагом 1 м и, отдельно, пещера
## (0,5 м, глубже 1 м под поверхностью — для рентгена). Цвет — в вершинах.
func map_meshes() -> Array:
	var mesher: Object = ClassDB.instantiate("VoxelMesherTransvoxel")
	var site := _mesh_from(mesher, gen.levels[0], Vector3.ONE * -gen.PAD, 1.0, -INF)
	var cm := _mesh_from(mesher, gen.fine_buffer(), Vector3(gen.fine_o) * VOXEL, VOXEL, 1.0)
	return [site, cm]

## Сетка Transvoxel из буфера (угол origin в метрах, шаг cell) с цветом вершин;
## shallow — выбросить треугольники мельче этой глубины под поверхностью.
func _mesh_from(mesher: Object, b: Object, origin: Vector3, cell: float, shallow: float) -> ArrayMesh:
	var m: Mesh = mesher.call("build_mesh", b, [])
	var out := ArrayMesh.new()
	if m == null or m.get_surface_count() == 0:
		return out
	var a := m.surface_get_arrays(0)
	var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var nr: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
	var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
	# Transvoxel кладёт вершины от угла буфера без запаса в 1 воксель.
	var cols := PackedColorArray()
	cols.resize(v.size())
	var uv := PackedVector2Array()
	uv.resize(v.size())
	for i in v.size():
		var p := origin + (v[i] + Vector3.ONE) * cell
		v[i] = p
		cols[i] = color_at(p)
		uv[i] = Vector2(0, 0)
	if shallow > -INF:
		var keep := PackedInt32Array()
		for i in range(0, idx.size(), 3):
			var c: Vector3 = (v[idx[i]] + v[idx[i + 1]] + v[idx[i + 2]]) / 3.0
			if terrain.surface_h(c.x, c.z) - c.y >= shallow:
				keep.append_array([idx[i], idx[i + 1], idx[i + 2]])
		idx = keep
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_NORMAL] = nr
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_TEX_UV] = uv
	arr[Mesh.ARRAY_INDEX] = idx
	if idx.size() > 0:
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return out

# ---------------------------------------------------------------- шейдер

## Шейдер рельефа ProtoTerrain, но цвет, небо и жила — из 3D-текстур по узлам
## поля, позиция — в системе участка; плюс сшивка LOD Transvoxel (обязательна:
## переходные треугольники модуль прячет только в шейдере).
static func voxel_material(t: ProtoTerrain, base: ShaderMaterial = null) -> ShaderMaterial:
	# Система участка — глобальным параметром шейдера: VoxelLodTerrain рисует
	# каждый кусок своей копией материала, и параметр, поменянный у главного,
	# до старых кусков не доходит. Робот ушёл от завода (шар повернулся) — у старых
	# кусков цвет брался не оттуда, а перестроенный бурами кусок — уже верно:
	# вокруг лунки — заплатки другого цвета.
	if not _site_xf_added:
		_site_xf_added = true
		RenderingServer.global_shader_parameter_add(SITE_XF, RenderingServer.GLOBAL_VAR_TYPE_MAT4, Projection(Transform3D.IDENTITY))
	else:
		RenderingServer.global_shader_parameter_set(SITE_XF, Projection(Transform3D.IDENTITY))
	var code := ProtoTerrain.SHADER
	code = code.replace("varying float sky;", """varying float sky;
uniform int u_transition_mask;
uniform sampler3D col3d : filter_linear, repeat_disable;
uniform sampler3D vein3d : filter_linear, repeat_disable;
uniform vec3 field_n = vec3(81.0, 37.0, 81.0);
global uniform mat4 pv_site_from_world;
uniform sampler3D fcol3d : filter_linear, repeat_disable;
uniform sampler3D fvein3d : filter_linear, repeat_disable;
uniform vec3 fine_o;
uniform vec3 fine_n = vec3(1.0);
varying vec3 vcol;
varying float vvein;
float get_transvoxel_secondary_factor(int idata) {
	int transition_mask = u_transition_mask & 0xff;
	int cell_border_mask = (idata >> 0) & 63;
	int vertex_border_mask = (idata >> 8) & 63;
	int m = transition_mask & cell_border_mask;
	float t = float(m != 0);
	t *= float((vertex_border_mask & ~transition_mask) == 0);
	return t;
}
vec3 get_transvoxel_position(vec3 vertex_pos, vec4 fdata) {
	int idata = floatBitsToInt(fdata.a);
	float secondary_factor = get_transvoxel_secondary_factor(idata);
	vec3 pos = mix(vertex_pos, fdata.xyz, secondary_factor);
	int itransition = (idata >> 16) & 0xff;
	float transition_cull = float(itransition == 0 || (itransition & u_transition_mask) != 0);
	return pos * transition_cull;
}""")
	code = code.replace("""	sky = COLOR.a;
	pl_pos = VERTEX;
	pl_n = NORMAL;""", """	VERTEX = get_transvoxel_position(VERTEX, CUSTOM0);
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	pl_pos = (pv_site_from_world * vec4(wp, 1.0)).xyz;
	pl_n = normalize(mat3(pv_site_from_world) * (mat3(MODEL_MATRIX) * NORMAL));
	// В коробке пещеры — узлы 0,5 м (жилы и натёки чётче), иначе — 1 м.
	vec3 fq = (pl_pos - fine_o) / 0.5;
	vec4 c;
	if (all(greaterThanEqual(fq, vec3(0.5))) && all(lessThanEqual(fq, fine_n - 1.5))) {
		vec3 fuvw = (fq + 0.5) / fine_n;
		c = textureLod(fcol3d, fuvw, 0.0);
		vvein = textureLod(fvein3d, fuvw, 0.0).r;
	} else {
		vec3 uvw = (pl_pos + 0.5) / field_n;
		c = textureLod(col3d, uvw, 0.0);
		vvein = textureLod(vein3d, uvw, 0.0).r;
	}
	vcol = c.rgb;
	sky = c.a;""")
	code = code.replace("vec3 col = COLOR.rgb;", "vec3 col = vcol;")
	code = code.replace("EMISSION = vein_glow * UV.x * 0.35;", "EMISSION = vein_glow * vvein * 0.35;")
	var m := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = code
	m.shader = sh
	m.set_shader_parameter("vein_glow", t.vein)
	if base != null:
		for p in ["sink", "surf_on", "surf", "surf_center", "veg_col", "veg_col2", "ice_col", "soil_col"]:
			var v: Variant = base.get_shader_parameter(p)
			if v != null:
				m.set_shader_parameter(p, v)
	return m
