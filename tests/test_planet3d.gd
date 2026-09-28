extends GutTest
## Планета-шар вокруг участка: у завода рельеф прежний, шар проходит через край
## участка без ступеньки, шар поворачивается под роботом (робот на макушке,
## рельеф под ним тот же), куски рельефа подгружаются вокруг робота.

func _terrain(seed_value := 14) -> ProtoTerrain:
	return ProtoTerrain.new(seed_value, ProtoWorldStyle.for_planet(PlanetGen.generate(seed_value)))

func _stream(t: ProtoTerrain, at: Vector3) -> Array:
	var robot := Node3D.new()
	add_child_autofree(robot)
	robot.position = at
	var st := ProtoPlanetStream.create(t, t.material(), robot, null, 800.0)
	add_child_autofree(st)
	return [st, robot]

func test_site_unchanged_on_sphere():
	var t := _terrain()
	var before: Array = []
	for p: Vector2 in [Vector2(5, 5), Vector2(40, 40), Vector2(79, 12)]:
		before.append(t.surface_h(p.x, p.y))
	t.make_sphere(800.0)
	var i := 0
	for p: Vector2 in [Vector2(5, 5), Vector2(40, 40), Vector2(79, 12)]:
		assert_eq(t.surface_h(p.x, p.y), before[i], "участок в %s" % p)
		assert_eq(t.density(p.x, 10.0, p.y), t._site_density(p.x, 10.0, p.y), "порода участка в %s" % p)
		i += 1

func test_sphere_meets_site_edge():
	var t := _terrain()
	t.make_sphere(800.0)
	for z in range(0, t.sz + 1, 8):
		for x: float in [-0.4, t.sx + 0.4]:
			assert_almost_eq(t.surface_h(x, z), t._site_h(x, z), 0.35, "край участка x=%s, z=%d" % [x, z])

func test_whole_sphere_has_ground():
	var t := _terrain()
	t.make_sphere(800.0)
	for d: Vector3 in [Vector3.DOWN, Vector3.RIGHT, Vector3(0.3, -0.5, 0.8).normalized()]:
		var h := t.sphere_h(d)
		assert_between(h, 3.0, 90.0, "высота шара по %s" % d)
		var q := t.center + d * (t.radius + h)
		assert_gt(t.sphere_density(q - d * 1.0), 0.0, "под поверхностью — порода")
		assert_lt(t.sphere_density(q + d * 1.0), 0.0, "над поверхностью — воздух")

func test_turn_keeps_robot_on_top():
	var t := _terrain()
	var st: ProtoPlanetStream = _stream(t, Vector3(40, 20, 40))[0]
	assert_eq(st.frame_for(Vector3(40, 20, 40)), Transform3D.IDENTITY, "у завода шар не повёрнут")
	# Робот в 300 м по дуге от завода: после поворота он на макушке, мировая Y — от центра.
	var a := 300.0 / t.radius
	var d := Vector3(sin(a), cos(a), 0.0)
	var q := t.center + d * (t.radius + t.sphere_h(d))
	st.target.position = q
	st._turn()
	var w := st.target.position
	assert_almost_eq(w.x, t.center.x, 0.01)
	assert_almost_eq(w.z, t.center.z, 0.01)
	assert_almost_eq(st.local_pos().distance_to(q), 0.0, 0.01, "относительно рельефа робот не сдвинулся")
	# Мировые запросы рельефа видят повёрнутый шар.
	assert_almost_eq(t.surface_h(w.x, w.z), w.y, 0.05, "робот стоит на поверхности")
	assert_true(t.solid(w.x, w.y - 1.0, w.z))
	assert_false(t.solid(w.x, w.y + 1.0, w.z))

func test_stream_builds_around_robot():
	var t := _terrain()
	var r := _stream(t, Vector3(t.sx + 120.0, 20.0, 40.0))
	var st: ProtoPlanetStream = r[0]
	st.build_now()
	assert_not_null(st.coarse_mi)
	assert_gt(st.chunks.size(), 6)
	var fine := 0
	for k: Vector3i in st.chunks:
		var mi: MeshInstance3D = st.chunks[k].mi
		if mi and st.chunks[k].step == 1.0:
			fine += 1
			assert_not_null(mi.get_node_or_null("ground_collision"), "у ближнего куска есть тело для ног")
	assert_gt(fine, 2)
