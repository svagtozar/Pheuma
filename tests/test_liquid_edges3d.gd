extends GutTest
## Жидкости не висят в воздухе: пещерная лужа ниже пола зала, река не рисуется
## над дырой (ход в пещеру) и опускает завесу, озеро стекает в выкопанную яму.

var _t := {}

func _terrain(seed_value: int) -> ProtoTerrain:
	if not _t.has(seed_value):
		var p := PlanetGen.generate(seed_value)
		var t := ProtoTerrain.new(seed_value, ProtoWorldStyle.for_planet(p))
		t.build_field()
		_t[seed_value] = t
	return _t[seed_value]

func _water() -> Substance:
	var s := Substance.new("water_t", "Вода")
	s.melt = 0.0
	s.boil = 100.0
	s.density = 1.0
	return s

func test_cave_pool_sits_below_hall_floor():
	for sv in [1, 3, 7, 32]:
		var t := _terrain(sv)
		var pc := t.pool_c()
		var lv := t.pool_level()
		# Вокруг чаши на уровне воды — порода (край держит воду).
		for k in 12:
			var a := TAU * k / 12.0
			var q := Vector2(pc.x, pc.z) + Vector2(cos(a), sin(a)) * (t.pool_r + 0.6)
			if t.cave_dist(Vector3(q.x, t.cave_c.y, q.y)) > 0.0:
				continue
			assert_true(t.solid(q.x, lv - 0.05, q.y), "seed %d: край чаши не ниже воды (%.1f, %.1f)" % [sv, q.x, q.y])
		# В середине чаши — вода над дном.
		assert_false(t.solid(pc.x, lv - 0.1, pc.z), "seed %d: в чаше есть вода" % sv)
		var mesh := ProtoLiquids.surface_mesh(t, lv, func(x, z): return Vector2(x, z).distance_to(Vector2(pc.x, pc.z)) < t.pool_r + 1.0)
		assert_gt(mesh.get_surface_count(), 0, "seed %d: гладь лужи есть" % sv)

func test_river_skips_hole_and_hangs_curtain():
	var t := _terrain(1)
	var level := func(x, z): return t.river_level_at(x, z)
	var area := func(x, z): return absf(z - t.river_z(x)) < 6.0 and x > t.lake_c.x + 2.0
	var r := ProtoLiquids.sloped(t, level, area)
	var wet: PackedByteArray = r[1]
	var mesh: ArrayMesh = r[0]
	var holes := 0
	for z in t.sz:
		for x in t.sx:
			if wet[x + z * t.sx] == 1:
				var y0: float = t.river_level_at(x + 0.5)
				assert_true(y0 - t.floor_at(Vector3(x + 0.5, y0 + 0.2, z + 0.5)) <= ProtoLiquids.VOID + 0.01,
					"мокрая клетка (%d, %d) лежит на дне" % [x, z])
			elif area.call(x + 0.5, z + 0.5) and not t.solid(x + 0.5, t.river_level_at(x + 0.5) + 0.2, z + 0.5):
				holes += 1
	assert_gt(holes, 0, "на seed 1 ход в пещеру проходит под руслом — там дыра без глади")
	var vertical := 0
	var f := mesh.get_faces()
	for i in range(0, f.size(), 3):
		if absf((f[i + 1] - f[i]).cross(f[i + 2] - f[i]).normalized().y) < 0.5:
			vertical += 1
	assert_gt(vertical, 0, "с края над дырой опущена завеса")

func test_lake_flows_into_dug_pit():
	var t := ProtoTerrain.new(32, ProtoWorldStyle.for_planet(PlanetGen.generate(32)))
	t.build_field()
	var f := ProtoFlow.new(t, _water())
	f.fill(t.lake_level, func(x, z): return Vector2(x, z).distance_to(t.lake_c) < t.lake_r + 4.5)
	# Сухая клетка у самой воды: берег чуть выше глади.
	var pit := Vector2i(-1, -1)
	var wet_n := Vector2(0, 0)
	for z in range(int(t.lake_c.y) - 20, int(t.lake_c.y) + 20):
		for x in range(int(t.lake_c.x) - 20, int(t.lake_c.x) + 20):
			var i := f.cell_of(x + 0.5, z + 0.5)
			if i < 0 or f.d[i] > 0.0:
				continue
			var gi := f.g(i)
			if gi < t.lake_level or gi > t.lake_level + 0.6:
				continue
			for n in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var j := f.cell_of(x + n.x + 0.5, z + n.y + 0.5)
				if j >= 0 and f.d[j] > 0.3 and t.can_edit(Vector3(x + 0.5, gi - 0.5, z + 0.5)):
					pit = Vector2i(x, z)
					wet_n = Vector2(x + n.x + 0.5, z + n.y + 0.5)
		if pit.x >= 0:
			break
	assert_true(pit.x >= 0, "нашлась сухая клетка у берега")
	if pit.x < 0:
		return
	var c := Vector3(pit.x + 0.5, f.g(f.cell_of(pit.x + 0.5, pit.y + 0.5)) - 0.4, pit.y + 0.5)
	var box := t.edit(c, 1.2, false)
	box = box.merge(t.edit(c - Vector3(0, 0.8, 0), 1.2, false))
	f.reground(box)
	var i := f.cell_of(c.x, c.z)
	assert_lt(f.g(i), t.lake_level - 0.3, "дно ямы ниже глади")
	for k in 600:
		f.step(0.1)
	assert_gt(f.d[i], 0.3, "вода стекла в яму, а не висит над ней")
	assert_almost_eq(f.level_at(c.x, c.z), f.level_at(wet_n.x, wet_n.y), 0.1, "в яме — уровень соседней воды")
