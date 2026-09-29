class_name ProtoRapierFluid
extends Node3D
## Опыт: жидкость частицами на Rapier Physics (Fluid3D, SPH из salva) — струи,
## фонтаны, всплески. Нужен аддон addons/godot-rapier3d (tools/get_rapier.sh) и
## движок физики Rapier3D (tools/rapier.sh кладёт override.cfg); без них узел
## ничего не делает. Тип Fluid3D берём через ClassDB, чтобы скрипт собирался
## и без аддона.
## Два режима:
## - pure: жидкость только частицами — летят, падают, растекаются по рельефу,
##   живут lifetime секунд (частица дорогая: ~3 мс на 1000 штук за шаг).
## - hybrid: частица, что упала и почти остановилась (или ушла под гладь), сдаёт
##   свой объём в сетку ProtoFlow: частицы — только то, что летит и плещется,
##   лужи и озёра остаются на дешёвой сетке.
## Частицы живут в своём мире физики (SubViewport с own_world_3d) с одним
## столкновением — сеткой высот рельефа вокруг источника (дно ProtoFlow с
## коркой). В общем мире salva на каждом шаге перебирает все клетки своей
## сетки (0,8 м) в рамке КАЖДОГО коллайдера: плитки рельефа 64 м давали
## ~45 мс на шаг даже при 150 частицах.

const R := 0.2               # радиус частицы (physics/rapier/fluid/fluid_particle_radius_3d)
const SETTLE_V := 0.6        # медленнее — частица осела, м/с
const SETTLE_AGE := 0.8      # и прожила хотя бы столько, с
const PARTICLE_SHADER := """
shader_type spatial;
uniform float glow = 0.0;
uniform float rough = 0.2;
uniform float metal = 0.0;
void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = rough;
	METALLIC = metal;
	float rim = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	EMISSION = COLOR.rgb * glow * COLOR.a * (0.7 + 0.6 * rim);
}
"""

var sub: Substance
var flow: ProtoFlow          # дно (рельеф + корка) — по нему сетка высот
var hybrid := false          # осевшие частицы сдают объём в flow
var cap := 1500              # больше частиц не держим (старые уходят)
var lifetime := 25.0         # pure: столько живёт частица, с
var cool_time := 0.0         # >0: частица остывает за столько секунд (лава темнеет)
var emitters: Array = []     # {pos, vel, spread, rate (частиц/с), on, acc — пройдено с прошлого слоя, м}
var fluid: Node3D            # Fluid3D
var mm: MultiMeshInstance3D
var handed := 0.0            # hybrid: сколько объёма сдано в сетку, м³
var _age := PackedFloat32Array()
var _rng := RandomNumberGenerator.new()
var _t := 0.0
var _glow := 0.0
var _hot := Color.WHITE
var _cold := Color.BLACK
var _world: SubViewport      # свой мир физики для частиц
var _ground_body: StaticBody3D
var _ground: CollisionShape3D
var _ground_sum := INF
var _ground_c := Vector2i.ZERO
var _ground_half := 14
var _ground_t := 0.0

static func available() -> bool:
	return ClassDB.class_exists("Fluid3D") and PhysicsServer3D.get_class() == "RapierPhysicsServer3D"

## Объём одной частицы при плотной укладке (шаг 2R), м³.
static func particle_volume() -> float:
	return pow(2.0 * R, 3.0)

func setup(s: Substance, ambient: float, grid: ProtoFlow, hybrid_ := false) -> void:
	sub = s
	flow = grid
	hybrid = hybrid_
	_rng.seed = 7
	fluid = ClassDB.instantiate("Fluid3D")
	fluid.set("density", s.density * 1000.0 if s.density > 0.0 else 1000.0)
	var v := ProtoSwim.viscosity(s)
	# Искусственная вязкость гасит брызги (с поверхностным натяжением AKINCI
	# струя разлеталась вчетверо шире, DFSPH глушит её совсем).
	var fx: Array = []
	var e: Resource = ClassDB.instantiate("FluidEffect3DViscosityArtificial")
	e.set("fluid_viscosity_coefficient", clampf(0.5 + 0.25 * v, 0.5, 3.0))
	fx.append(e)
	var typed := Array([], TYPE_OBJECT, &"Resource", null)
	typed.assign(fx)
	fluid.set("effects", typed)
	_world = SubViewport.new()
	_world.name = "rapier_world"
	_world.own_world_3d = true
	_world.size = Vector2i(2, 2)
	_world.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_world)
	_ground_body = StaticBody3D.new()
	# Слои по умолчанию: salva сверяет группы в обе стороны (маска тела 0 —
	# частицы проходят насквозь). В своём мире, кроме дна, ничего и нет.
	_ground = CollisionShape3D.new()
	_ground_body.add_child(_ground)
	_world.add_child(_ground_body)
	_world.add_child(fluid)
	mm = MultiMeshInstance3D.new()
	mm.name = "particles"
	var m := MultiMesh.new()
	m.transform_format = MultiMesh.TRANSFORM_3D
	m.use_colors = true
	var sph := SphereMesh.new()
	# Шарики крупнее частицы: соседние (шаг 2R) сливаются в сплошную струю.
	sph.radius = R * 1.35
	sph.height = R * 2.7
	sph.radial_segments = 8
	sph.rings = 4
	m.mesh = sph
	mm.multimesh = m
	# Полосы и рябь шейдера озера на шариках читаются «монетками» — у частиц
	# свой простой шейдер: цвет экземпляра, жар (альфа цвета) светится.
	var d := ProtoLiquids.look(s, ambient)
	_glow = d.glow
	_hot = d.color if d.crust <= 0.0 else d.color.lerp(Color(1.0, 0.55, 0.15), 0.7)
	_cold = d.color.darkened(0.65)
	var sh := Shader.new()
	sh.code = PARTICLE_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("glow", _glow)
	mat.set_shader_parameter("rough", d.rough + 0.1)
	mat.set_shader_parameter("metal", d.metal)
	mm.material_override = mat
	mm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mm)

## Сетка высот дна вокруг c (±half клеток по 1 м): только она и сталкивается с частицами.
func set_ground(c: Vector2, half := 14) -> void:
	_ground_c = Vector2i(int(floor(c.x)), int(floor(c.y)))
	_ground_half = half
	_rebuild_ground()

## Дно — одна треугольная сетка по центрам клеток ProtoFlow (рельеф + корка).
## Замер 500 частиц в покое, мс на шаг: коробка 1,3, треугольники 1,6, сетка
## высот 31 (проекция точки на HeightMapShape в parry медленная), призмы по
## 1 м 32 (salva перебирает клетки в рамке каждого коллайдера).
func _rebuild_ground() -> void:
	var w := _ground_half * 2 + 1
	var x0 := _ground_c.x - _ground_half
	var z0 := _ground_c.y - _ground_half
	var data := PackedFloat32Array()
	data.resize(w * w)
	var sum := 0.0
	for k in w:
		for j in w:
			var i := flow.idx(clampi(x0 + j, 0, flow.nx - 1), clampi(z0 + k, 0, flow.nz - 1))
			data[k * w + j] = flow.g(i)
			sum += data[k * w + j] * (1 + j + k * w)
	if absf(sum - _ground_sum) < 0.01:
		return
	_ground_sum = sum
	var faces := PackedVector3Array()
	faces.resize((w - 1) * (w - 1) * 6)
	var f := 0
	for k in w - 1:
		for j in w - 1:
			# Узлы — центры клеток ProtoFlow (x + 0,5).
			var a := Vector3(x0 + j + 0.5, data[k * w + j], z0 + k + 0.5)
			var b := Vector3(a.x + 1, data[k * w + j + 1], a.z)
			var c := Vector3(a.x, data[(k + 1) * w + j], a.z + 1)
			var d := Vector3(a.x + 1, data[(k + 1) * w + j + 1], a.z + 1)
			faces[f] = a; faces[f + 1] = b; faces[f + 2] = c
			faces[f + 3] = b; faces[f + 4] = d; faces[f + 5] = c
			f += 6
	var sh := ConcavePolygonShape3D.new()
	sh.backface_collision = true
	sh.set_faces(faces)
	_ground.shape = sh

## Источник: частицы летят из pos со скоростью vel (разброс spread, м/с).
func add_emitter(pos: Vector3, vel: Vector3, rate: float, spread := 1.0) -> Dictionary:
	var e := {"pos": pos, "vel": vel, "spread": spread, "rate": rate, "on": true, "acc": 0.0}
	emitters.append(e)
	return e

## Объёмный расход (м³/с) → частиц в секунду.
static func rate_for(q: float) -> float:
	return q / particle_volume()

func count() -> int:
	return _age.size()

func _physics_process(dt: float) -> void:
	if fluid == null:
		return
	var us := Time.get_ticks_usec()
	_physics_body(dt)
	script_us += Time.get_ticks_usec() - us
	script_n += 1

var lost_fall := 0
var lost_engine := 0
var fell_through := 0         # провалились под дно (замер)
var lost_cap := 0
var lost_age := 0
var script_us := 0     # время скрипта в шагах физики (для замера)
var script_n := 0

func _physics_body(dt: float) -> void:
	_t += dt
	var pts := PackedVector3Array()
	var vels := PackedVector3Array()
	for e in emitters:
		if not e.on:
			continue
		# Слоями: как только прошлый слой отлетел на шаг решётки (2R), выпускаем
		# следующий — диск частиц поперёк струи. Частицы, рождённые внахлёст,
		# SPH расталкивает взрывом (капли улетали за сотни метров).
		var sp: float = e.vel.length()
		e.acc += sp * dt
		if e.acc < 2.0 * R or e.rate <= 0.0:
			continue
		e.acc = fmod(e.acc, 2.0 * R)
		var n := maxi(int(round(e.rate * 2.0 * R / sp)), 1)
		var fwd: Vector3 = e.vel / sp
		var a := fwd.cross(Vector3.UP if absf(fwd.y) < 0.95 else Vector3.RIGHT).normalized()
		var b := fwd.cross(a)
		var rot := _rng.randf() * TAU
		var k := 0
		var ring := 0
		while k < n and _age.size() + pts.size() < cap:
			var in_ring := 1 if ring == 0 else ring * 6
			for m in in_ring:
				if k >= n:
					break
				var ang := rot + TAU * m / in_ring
				var off: Vector3 = (a * cos(ang) + b * sin(ang)) * ring * 2.0 * R
				pts.append(e.pos + off)
				vels.append(e.vel + off.normalized() * e.spread * 0.3 * ring)
				k += 1
			ring += 1
	if not pts.is_empty():
		fluid.call("add_points_and_velocities", pts, vels)
		var n0 := _age.size()
		_age.resize(n0 + pts.size())
		for i in range(n0, _age.size()):
			_age[i] = 0.0
	for i in _age.size():
		_age[i] += dt
	_retire()
	_ground_t -= dt
	if _ground_t <= 0.0:
		_ground_t = 1.5
		_rebuild_ground()            # корка наросла — дно выше (без перемен — выходит сразу)

## Убрать старые (pure) и осевшие (hybrid) частицы; осевшие сдают объём сетке.
func _retire() -> void:
	var p: PackedVector3Array = fluid.get("points")
	if p.size() != _age.size():
		lost_engine += _age.size() - p.size()
		_age.resize(p.size())     # движок сам убрал частицы
	var gone := PackedInt32Array()
	var v: PackedVector3Array = fluid.call("get_velocities")
	var over := _age.size() - cap
	# Провалилась под дно (у треугольной сетки нет «внутри») — убираем, а не ставим на
	# место: частица, втиснутая к соседям, взрывает SPH.
	var sunk := PackedByteArray()
	sunk.resize(p.size())
	for i in p.size():
		var c := flow.cell_of(p[i].x, p[i].z)
		if c >= 0 and p[i].y < flow.g(c) - 1.0:
			sunk[i] = 1
			fell_through += 1
	for i in _age.size():
		var q := p[i]
		if q.y < -20.0 or (sunk[i] == 1 and not hybrid) or (not hybrid and _age[i] > lifetime) or i < over:
			if q.y < -20.0: lost_fall += 1
			elif sunk[i] == 1: pass
			elif i < over: lost_cap += 1
			else: lost_age += 1
			gone.append(i)
			continue
		if not hybrid or (_age[i] < SETTLE_AGE and sunk[i] == 0):
			continue
		var c := flow.cell_of(q.x, q.z)
		if c < 0:
			continue
		var under := q.y < flow.level_i(c) - R
		if under or v[i].length() < SETTLE_V:
			gone.append(i)
			var heat := 1.0 if cool_time <= 0.0 else clampf(1.0 - _age[i] / cool_time, 0.0, 1.0)
			flow.pour(c, particle_volume(), heat)
			handed += particle_volume()
	if gone.is_empty():
		return
	fluid.call("delete_points", gone)
	var keep := PackedFloat32Array()
	keep.resize(_age.size() - gone.size())
	var k := 0
	var g := 0
	for i in _age.size():
		if g < gone.size() and gone[g] == i:
			g += 1
			continue
		keep[k] = _age[i]
		k += 1
	_age = keep

func _process(_dt: float) -> void:
	if fluid == null:
		return
	var p: PackedVector3Array = fluid.get("points")
	var m := mm.multimesh
	m.instance_count = p.size()
	var v: PackedVector3Array = fluid.call("get_velocities")
	for i in p.size():
		# В полёте капля вытянута по скорости, на земле — круглая.
		var vel := v[i] if i < v.size() else Vector3.ZERO
		var b := Basis.IDENTITY
		var sp := vel.length()
		if sp > 1.0:
			var fwd := vel / sp
			var side := fwd.cross(Vector3.UP if absf(fwd.y) < 0.95 else Vector3.RIGHT).normalized()
			b = Basis(side, fwd * (1.0 + minf((sp - 1.0) * 0.08, 0.8)), side.cross(fwd))
		m.set_instance_transform(i, Transform3D(b, p[i] - global_position))
		var heat := 1.0
		if cool_time > 0.0 and i < _age.size():
			heat = clampf(1.0 - _age[i] / cool_time, 0.0, 1.0)
		var col := _cold.lerp(_hot, heat) if cool_time > 0.0 else _hot
		col.a = heat
		m.set_instance_color(i, col)
