extends GutTest
## Наполнение шара вне участка (ProtoPlanetFill): флора и россыпи залежей в
## кусках вокруг робота, моря в котловинах, своё время суток на другой стороне
## шара (ProtoDayNight.turn), разведанное всего шара и радар вдали (ProtoGlobe).

func _setup(seed_value := 14) -> Dictionary:
	var p := PlanetGen.generate(seed_value)
	var st := ProtoWorldStyle.for_planet(p)
	var t := ProtoTerrain.new(seed_value, st)
	var fl := ProtoFlora.for_planet(p, st, seed_value)
	fl.attach(t)
	var robot := Node3D.new()
	add_child_autofree(robot)
	robot.position = Vector3(40, 20, 40)
	var s := ProtoPlanetStream.create(t, t.material(), robot, null, 800.0)
	add_child_autofree(s)
	var f := ProtoPlanetFill.create(s, fl, p, seed_value)
	s.add_child(f)
	return {"planet": p, "terrain": t, "stream": s, "fill": f, "robot": robot, "flora": fl}

func test_key_of_inverts_chunk_dirs():
	var e := _setup()
	var s: ProtoPlanetStream = e.stream
	var f: ProtoPlanetFill = e.fill
	for k: Vector3i in [Vector3i(0, 3, 7), Vector3i(1, 0, 19), Vector3i(2, 10, 10), Vector3i(3, 19, 0), Vector3i(4, 5, 12), Vector3i(5, 17, 2)]:
		var d := s._dir(k.x, (k.y + 0.5) / s.n_face, (k.z + 0.5) / s.n_face)
		assert_eq(f.key_of(d), k, "середина куска %s" % k)

func test_chunk_is_deterministic_and_filled():
	var e := _setup(8)       # буйная жизнь
	var f: ProtoPlanetFill = e.fill
	var s: ProtoPlanetStream = e.stream
	# Кусок в ~300 м от завода.
	var a := 300.0 / 800.0
	var k := f.key_of(Vector3(sin(a), cos(a), 0.0))
	var one := f._arrays(k)
	var two := f._arrays(k)
	assert_gt(one.plants, 50, "вдали от завода растёт флора")
	assert_eq(one.plants, two.plants, "тот же кусок — те же растения")
	assert_eq(one.deps.size(), two.deps.size(), "и те же залежи")
	assert_false(one.geos.is_empty())
	# Растения стоят на поверхности шара (система куска: Y — вверх).
	var fr: Transform3D = one.frame
	var g: Array = one.geos[0]
	var v: Vector3 = fr * (g[1] as PackedVector3Array)[0]
	var t: ProtoTerrain = e.terrain
	var h := (v - t.center).length() - t.radius
	var d := (v - t.center).normalized()
	assert_almost_eq(h, t.sphere_h(d), 3.0, "растение у земли")

func test_deposits_are_drillable_and_dropped():
	var e := _setup(14)
	var f: ProtoPlanetFill = e.fill
	var m := ProtoMining.new()
	add_child_autofree(m)
	f.mining = m
	# Ищем кусок с россыпью.
	var got := Vector3i(-1, -1, -1)
	var out := {}
	for i in 60:
		var a := (200.0 + i * 40.0) / 800.0
		var k := f.key_of(Vector3(sin(a) * cos(i * 0.7), cos(a), sin(a) * sin(i * 0.7)).normalized())
		out = f._arrays(k)
		if not out.deps.is_empty():
			got = k
			break
	assert_ne(got, Vector3i(-1, -1, -1), "россыпи на шаре есть")
	f._ready_chunk(got, out)
	assert_eq(m.druses.size(), out.deps.size(), "залежи куска — в добыче")
	assert_false(m.crystals().is_empty(), "их куски можно бурить")
	assert_true(f.finds.has("%d_%d_%d_0" % [got.x, got.y, got.z]), "метка россыпи для радара")
	f._drop(got)
	assert_eq(m.druses.size(), 0, "кусок убран — и залежи из добычи")

func test_seas_fill_basins_not_site():
	var e := _setup(8)       # океаническая
	var f: ProtoPlanetFill = e.fill
	var t: ProtoTerrain = e.terrain
	var liq: Substance = null
	for m in e.planet.materials:
		if m.phase_at(e.planet.ambient_temp) == Substance.Phase.LIQUID:
			liq = m
	if liq == null:
		liq = ProtoHealth.hazard_liquid(e.planet)
	f.setup_seas(liq, e.planet.ambient_temp)
	assert_gt(t.sea_level, -INF, "у океанической планеты есть моря")
	# У завода и в кольце вокруг — суше уровня моря.
	for k in 24:
		var th := k * TAU / 24.0
		var ang := ProtoPlanetFill.SEA_CLEAR / t.radius
		assert_gt(t.sphere_h(Vector3(sin(ang) * cos(th), cos(ang), sin(ang) * sin(th))), t.sea_level, "у участка сухо")
	f.build_sea()
	assert_not_null(f.sea_mi, "оболочка моря построена")
	# Точка в море: зона жидкости видит глубину.
	var r := RandomNumberGenerator.new()
	r.seed = 3
	var found := false
	for i in 4000:
		var d := Vector3(r.randfn(), r.randfn(), r.randfn()).normalized()
		if t.arc_from_site(d) < 300.0 or t.sphere_h(d) > t.sea_level - 2.0:
			continue
		var bottom := t.center + d * (t.radius + t.sphere_h(d) + 0.5)
		assert_gt(f.sea_at(bottom), 1.0, "на дне — под водой")
		assert_lt(f.sea_at(t.center + d * (t.radius + t.sea_level + 2.0)), 0.0, "над водой — сухо")
		found = true
		break
	assert_true(found, "моря на шаре нашлись")

func test_local_time_on_other_side():
	var root := Node3D.new()
	add_child_autofree(root)
	var c: ProtoDayNight = ProtoSky.build(PlanetGen.generate(14), root).cycle
	c.time = 0.5
	c.update_now()
	assert_almost_eq(c.local_time(), 0.5, 0.001, "у завода — время планеты")
	assert_lt(c.night, 0.05, "полдень")
	# Робот на противоположной стороне шара: шар повёрнут на 180° вокруг оси неба.
	c.turn = Basis(c.pole, PI)
	c.update_now()
	assert_almost_eq(c.local_time(), 0.0, 0.01, "там полночь")
	assert_gt(c.night, 0.9, "и темно")
	assert_eq(c.clock(), "00:00")

func test_globe_reveal_and_radar_patch():
	var e := _setup(14)
	var g := ProtoGlobe.new(e.stream, e.fill)
	var t: ProtoTerrain = e.terrain
	assert_almost_eq(g.explored_share(), 0.0, 0.0001)
	var a := 500.0 / t.radius
	var d := Vector3(sin(a), cos(a), 0.0)
	var q := t.center + d * (t.radius + t.sphere_h(d))
	assert_true(g.away(q), "в 500 м от завода — вне участка")
	assert_false(g.away(Vector3(40, 20, 40)), "у завода — участок")
	g.reveal(q)
	assert_gt(g.explored_share(), 0.0, "открылось вокруг робота")
	var px := ProtoGlobe.dir_px(d)
	assert_almost_eq(ProtoGlobe.px_dir(px.x, px.y).dot(d), 1.0, 0.001, "развёртка обратима")
	var pt := g.patch_for(q)
	assert_almost_eq(g.patch_uv(q), Vector2(0.5, 0.5), Vector2(0.01, 0.01), "робот — в середине рельефа радара")
	assert_eq((pt.tex as ImageTexture).get_width(), ProtoGlobe.PATCH_PX)
