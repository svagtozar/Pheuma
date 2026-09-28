class_name ProtoTerraFlora
extends Node3D
## Флора терраформирования (ProtoTerraFlora; органика планеты по тегам — ProtoFlora): трава, кусты и цветы. Места заданы заранее (по
## зерну планеты), видно — то, что разрешает климат:
##   по всей планете — доля мест растёт с пригодностью (ProtoTerraform) выше GLOBAL_FROM,
##   но только когда жизнь занесена (газ из газоотводов несёт споры, см. seeded);
##   вокруг купола с жилыми условиями — всё в радиусе его зелёной зоны.
## Три MultiMesh (трава, кусты, цветы); спрятанное — нулевой масштаб.

const COUNT := 2600
const GLOBAL_FROM := 0.35       # с какой пригодности зеленеет вся планета
const GLOBAL_MAX := 0.75        # доля мест при полной пригодности
const KINDS := ["grass", "shrub", "flower"]

var terrain: ProtoTerrain
var spots: Array = []           # [{p: Vector3, u, kind, s, yaw}]
var mm := {}                    # вид → MultiMeshInstance3D
var shown := 0                  # сколько видно (для тестов и лога)
var _key := ""
var _blocked: Callable          # (x, z, y) -> 0 растёт, 1 нет (вода), 2 площадка завода
var occupied: Callable          # (Vector3) -> bool — место занято деталью завода

## blocked — где не растёт (вода) и где площадка завода: там — только в зоне
## купола и не под деталями.
func setup(t: ProtoTerrain, planet: Planet, blocked: Callable) -> void:
	terrain = t
	_blocked = blocked
	var rng := RandomNumberGenerator.new()
	rng.seed = planet.seed_value * 31 + 5
	var tries := 0
	while spots.size() < COUNT and tries < COUNT * 4:
		tries += 1
		var x := rng.randf_range(3.0, t.sx - 3.0)
		var z := rng.randf_range(3.0, t.sz - 3.0)
		var h := t.surface_h(x, z)
		# Крутые склоны голые.
		var slope := maxf(absf(t.surface_h(x + 1.0, z) - h), absf(t.surface_h(x, z + 1.0) - h))
		if slope > 0.9:
			continue
		var y := t.floor_at(Vector3(x, h + 1.0, z))
		var b: int = _blocked.call(x, z, y) if _blocked.is_valid() else 0
		if b == 1:
			continue
		if b == 2:
			y = maxf(y, t.plateau().y + 0.1)     # на настил площадки
		var r := rng.randf()
		var kind := "grass" if r < 0.78 else ("shrub" if r < 0.94 else "flower")
		spots.append({"p": Vector3(x, y, z), "u": rng.randf(), "kind": kind, "pad": b == 2,
			"s": rng.randf_range(0.7, 1.3), "yaw": rng.randf() * TAU})
	var cols := palette(planet)
	for k in KINDS:
		var inst := MultiMeshInstance3D.new()
		inst.name = "flora_" + k
		var m := MultiMesh.new()
		m.transform_format = MultiMesh.TRANSFORM_3D
		m.mesh = _mesh(k, cols)
		var n := spots.filter(func(sp): return sp.kind == k).size()
		m.instance_count = n
		inst.multimesh = m
		inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(inst)
		mm[k] = inst
	_hide_all()

## Цвета по планете: грибная — бирюза и лиловый, иначе — зелень.
static func palette(planet: Planet) -> Dictionary:
	if planet.has_tag("fungal_biosphere"):
		return {"low": Color(0.12, 0.35, 0.36), "high": Color(0.45, 0.8, 0.7), "bloom": Color(0.8, 0.45, 0.95)}
	if planet.has_tag("volcanic"):
		return {"low": Color(0.28, 0.32, 0.12), "high": Color(0.65, 0.7, 0.25), "bloom": Color(1.0, 0.55, 0.2)}
	return {"low": Color(0.13, 0.3, 0.1), "high": Color(0.45, 0.72, 0.28), "bloom": Color(1.0, 0.85, 0.3)}

static func _mesh(kind: String, cols: Dictionary) -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	match kind:
		"grass":
			for i in 6:
				var a := i * TAU / 6.0 + 0.3
				var d := Vector3(cos(a), 0, sin(a))
				var side := Vector3(-d.z, 0, d.x) * 0.05
				var tip := d * 0.22 + Vector3(0, 0.45 + 0.1 * (i % 2), 0)
				_tri(st, -side, side, tip, cols.low, cols.low, cols.high)
		"shrub":
			var sm := SphereMesh.new()
			sm.radius = 0.35
			sm.height = 0.5
			sm.radial_segments = 7
			sm.rings = 4
			var arr := sm.get_mesh_arrays()
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
			for i in range(0, idx.size(), 3):
				var p: Array = []
				var c: Array = []
				for j in 3:
					var q: Vector3 = v[idx[i + j]] + Vector3(0, 0.22, 0)
					p.append(q)
					c.append(cols.low.lerp(cols.high, clampf(q.y / 0.45, 0.0, 1.0)))
				_tri(st, p[0], p[1], p[2], c[0], c[1], c[2])
		"flower":
			var s := Vector3(0.02, 0, 0)
			_tri(st, -s, s, Vector3(0, 0.4, 0), cols.low, cols.low, cols.high)
			for i in 5:
				var a := i * TAU / 5.0
				var c := Vector3(0, 0.42, 0)
				var e := c + Vector3(cos(a), 0.05, sin(a)) * 0.12
				var e2 := c + Vector3(cos(a + 0.6), 0.05, sin(a + 0.6)) * 0.12
				_tri(st, c, e, e2, cols.bloom.lightened(0.3), cols.bloom, cols.bloom)
	st.generate_normals()
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.roughness = 0.85
	st.set_material(m)
	return st.commit()

static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, ca: Color, cb: Color, cc: Color) -> void:
	st.set_color(ca)
	st.add_vertex(a)
	st.set_color(cb)
	st.add_vertex(b)
	st.set_color(cc)
	st.add_vertex(c)

func _hide_all() -> void:
	var i := {}
	for sp in spots:
		var k: String = sp.kind
		var n: int = i.get(k, 0)
		(mm[k] as MultiMeshInstance3D).multimesh.set_instance_transform(n, Transform3D(Basis().scaled(Vector3.ZERO), sp.p))
		i[k] = n + 1
	shown = 0

## Сколько мест зеленеет на пригодности hab по всей планете (доля 0..GLOBAL_MAX).
static func global_share(hab: float) -> float:
	return clampf((hab - GLOBAL_FROM) / (1.0 - GLOBAL_FROM), 0.0, 1.0) * GLOBAL_MAX

## Обновить по климату: hab — пригодность, seeded — 0..1, сколько жизни занесено
## терраформированием (ProtoTerraform.seeded), zones — [[центр мира, радиус]].
func update(hab: float, seeded: float, zones: Array) -> void:
	hab *= clampf(seeded, 0.0, 1.0)
	var key := "%.2f|%s" % [hab, str(zones.map(func(z): return [snappedf(z[0].x, 0.5), snappedf(z[0].z, 0.5), snappedf(z[1], 0.25)]))]
	if key == _key:
		return
	_key = key
	var share := global_share(hab)
	var i := {}
	shown = 0
	for sp in spots:
		var k: String = sp.kind
		var n: int = i.get(k, 0)
		i[k] = n + 1
		var g := 0.0
		if sp.u < share and not sp.pad:
			# У порога — мельче: растёт, а не появляется сразу.
			g = clampf((share - sp.u) / 0.08, 0.3, 1.0)
		for z in zones:
			var d := Vector2(sp.p.x - z[0].x, sp.p.z - z[0].z).length()
			if d < z[1] and d > 1.6 and not (sp.pad and occupied.is_valid() and occupied.call(sp.p)):
				g = maxf(g, clampf((z[1] - d) / 1.5, 0.3, 1.0))
		if g > 0.0:
			shown += 1
		var b := Basis(Vector3.UP, sp.yaw).scaled(Vector3.ONE * sp.s * g)
		(mm[k] as MultiMeshInstance3D).multimesh.set_instance_transform(n, Transform3D(b, sp.p))

## Рельеф поменялся (копали/насыпали): места рядом — на новую поверхность;
## заваленные и затопленные не растут, пока снова не станут землёй.
func terrain_changed(c: Vector3, r: float) -> void:
	for sp in spots:
		var p: Vector3 = sp.p
		if Vector2(p.x - c.x, p.z - c.z).length() < r + 1.0:
			sp.p = Vector3(p.x, terrain.floor_at(Vector3(p.x, maxf(p.y, c.y + r) + 1.0, p.z)), p.z)
	_key = ""
