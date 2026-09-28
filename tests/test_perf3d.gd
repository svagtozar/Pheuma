extends GutTest
## Производительность 3D-прототипа: поле рельефа в потоках совпадает с density(),
## склейка сеток (ProtoBatch) не теряет треугольников и держит анимацию шарниров.

func test_field_matches_density():
	var t := ProtoTerrain.new(14, ProtoWorldStyle.new())
	t.build_field()
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for i in 300:
		var x := rng.randi_range(0, t.sx)
		var y := rng.randi_range(0, t.sy)
		var z := rng.randi_range(0, t.sz)
		var d := t.density(x, y, z)
		var f: float = t.dens[t._i(x, y, z)]
		assert_eq(f > 0.0, d > 0.0, "знак поля в %d,%d,%d" % [x, y, z])
		if absf(d) < 2.0:
			assert_almost_eq(f, d, 0.001, "поле у поверхности в %d,%d,%d" % [x, y, z])

func test_field_at_is_trilinear():
	var t := ProtoTerrain.new(7, ProtoWorldStyle.new())
	t.build_field()
	assert_almost_eq(t.field_at(Vector3(10, 12, 20)), t.dens[t._i(10, 12, 20)], 0.0001)
	var mid := (t.dens[t._i(10, 12, 20)] + t.dens[t._i(11, 12, 20)]) * 0.5
	assert_almost_eq(t.field_at(Vector3(10.5, 12, 20)), mid, 0.0001)

func test_mesh_has_surface():
	var t := ProtoTerrain.new(3, ProtoWorldStyle.new())
	t.build_field()
	var m := t.build_mesh(Vector3.ZERO, Vector3i(-1, -1, -1), 1.0, t.coarse_skip())
	var a := m.surface_get_arrays(0)
	assert_gt((a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size(), 1000)
	assert_eq((a[Mesh.ARRAY_COLOR] as PackedColorArray).size(), (a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size())

func _tris(m: Mesh) -> int:
	var n := 0
	for si in m.get_surface_count():
		var a := m.surface_get_arrays(si)
		var ix = a[Mesh.ARRAY_INDEX]
		n += (ix.size() if ix != null and not ix.is_empty() else (a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
	return n

func test_merged_keeps_triangles_and_flips_mirrored():
	var box := BoxMesh.new()
	var m := ProtoBatch.merged([[box, Transform3D()], [box, Transform3D(Basis.from_scale(Vector3(-1, 1, 1)), Vector3(2, 0, 0))]])
	assert_eq(_tris(m), _tris(box) * 2)
	# Зеркальная копия: нормали наружу, треугольники развёрнуты (лицо — снаружи).
	var a := m.surface_get_arrays(0)
	var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var ix: PackedInt32Array = a[Mesh.ARRAY_INDEX]
	var half := ix.size() / 2
	for t in range(0, ix.size(), 3):
		var p0 := v[ix[t]]
		var fn := (v[ix[t + 2]] - p0).cross(v[ix[t + 1]] - p0)
		var c := (p0 + v[ix[t + 1]] + v[ix[t + 2]]) / 3.0 - (Vector3(2, 0, 0) if t >= half else Vector3.ZERO)
		assert_gt(fn.dot(c), 0.0, "грань %s копии смотрит наружу" % ("зеркальной" if t >= half else "обычной"))

func test_robot_batching_keeps_joints():
	var r := RobotDesigns.build("clean")
	add_child_autofree(r)
	var before := r.find_children("*", "MeshInstance3D", true, false).size()
	var saved := ProtoBatch.merge_children(r)
	var after := r.find_children("*", "MeshInstance3D", true, false).size()
	assert_gt(saved, 50)
	assert_eq(after, before - saved)
	# Шарниры и именованные узлы, которые ищет анимация, на месте.
	for path in ["hips/chest/head", "hips/chest/shoulder_l/elbow_l/hand_l", "hips/hip_r/knee_r/ankle_r"]:
		assert_not_null(r.get_node_or_null(path), path)

const LIVE := ["lamp", "fill", "fill_mesh", "heap", "sample", "gauge", "model"]

## Живые части и треугольники модели: [имена живых узлов по порядку, треугольники].
func _live_and_tris(n: Node) -> Array:
	var names := []
	var tris := 0
	for c in n.find_children("*", "", true, false):
		if String(c.name) in LIVE or c.has_meta("anim"):
			names.append(String(n.get_path_to(c)))
		var mi := c as MeshInstance3D
		if mi != null and mi.mesh != null and mi.visible:
			tris += _tris(mi.mesh)
	return [names, tris]

func _check_batched(label: String, n: Node3D) -> Vector2i:
	add_child_autofree(n)
	var before := n.find_children("*", "MeshInstance3D", true, false).size()
	var was := _live_and_tris(n)
	ProtoBatch.merge_children(n)
	var now := _live_and_tris(n)
	assert_eq(now[0], was[0], "%s: живые части на месте" % label)
	assert_eq(now[1], was[1], "%s: треугольники те же" % label)
	return Vector2i(before, n.find_children("*", "MeshInstance3D", true, false).size())

func test_machine_models_batching_keeps_live_parts():
	var body := ProtoMachines.surface(Substance.new())
	var total := Vector2i.ZERO
	for kind in Buildings.KINDS:
		var n := MachineModels.build(kind, body)
		MachineModels.add_outlet(n, Vector3.RIGHT)
		total += _check_batched(kind, n)
	gut.p("MachineModels: сеток %d → %d" % [total.x, total.y])
	assert_lt(total.y, total.x)

func test_factory_parts_batching_keeps_live_parts():
	var total := Vector2i.ZERO
	for kind in ProtoPneumatics.KINDS:
		var n := ProtoPneumaticsView.build_part(kind, Substance.new(), 0, [0, 1, 2, 3])
		total += _check_batched(kind, n)
	gut.p("Детали завода: сеток %d → %d" % [total.x, total.y])
	assert_lt(total.y, total.x)

func test_merge_static_joins_machines_keeps_live_parts():
	# Десять машин из одного вещества: неподвижные части — общими сетками.
	var body := ProtoMachines.surface(Substance.new())
	var into := Node3D.new()
	add_child_autofree(into)
	var roots := []
	for i in 10:
		var n := MachineModels.build(["centrifuge", "drill", "container", "crusher", "pipe"][i % 5], body)
		n.position = Vector3(i * 2.0, 0, 0)
		n.rotation.y = i * 0.7
		into.add_child(n)
		roots.append(n)
	var before := into.find_children("*", "MeshInstance3D", true, false).size()
	var was := _live_and_tris(into)
	for n in roots:
		ProtoBatch.merge_children(n)
	ProtoBatch.merge_static(into, roots)
	var now := _live_and_tris(into)
	var after := into.find_children("*", "MeshInstance3D", true, false).size()
	gut.p("10 машин: сеток %d → %d" % [before, after])
	assert_eq(now[0], was[0], "лампы, spin, fill на месте")
	assert_eq(now[1], was[1], "треугольники те же")
	assert_lt(after * 3, before, "сеток хотя бы втрое меньше")
	# Склеенная сетка стоит там же, где стояли детали: общий габарит тот же.
	# Габарит по вершинам: AABB повёрнутой сетки шире, чем она сама.
	var aabb := func(root: Node3D) -> AABB:
		var box := AABB()
		var first := true
		for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
			for si in mi.mesh.get_surface_count():
				for v: Vector3 in mi.mesh.surface_get_arrays(si)[Mesh.ARRAY_VERTEX]:
					var p: Vector3 = mi.global_transform * v
					box = AABB(p, Vector3.ZERO) if first else box.expand(p)
					first = false
		return box
	var ref := Node3D.new()
	add_child_autofree(ref)
	for i in 10:
		var n := MachineModels.build(["centrifuge", "drill", "container", "crusher", "pipe"][i % 5], body)
		n.position = Vector3(i * 2.0, 0, 0)
		n.rotation.y = i * 0.7
		ref.add_child(n)
	var a: AABB = aabb.call(into)
	var r: AABB = aabb.call(ref)
	assert_almost_eq(a.position, r.position, Vector3.ONE * 0.01)
	assert_almost_eq(a.size, r.size, Vector3.ONE * 0.01)
