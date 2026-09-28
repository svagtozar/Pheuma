extends GutTest
## Живые жидкости (ProtoFlow, ProtoLiquidLife): растекание, паводок, лава и корка.

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

func _in_lake(t: ProtoTerrain) -> Callable:
	return func(x, z): return Vector2(x, z).distance_to(t.lake_c) < t.lake_r + 4.5

func test_volume_is_kept_while_it_spreads():
	var t := _terrain(32)
	var f := ProtoFlow.new(t, _water())
	f.fill(t.lake_level, _in_lake(t))
	# Горб воды посреди озера растекается, объём тот же.
	var i := f.cell_of(t.lake_c.x, t.lake_c.y)
	f.d[i] += 3.0
	var v0 := f.volume()
	for k in 200:
		f.step(0.1)
	assert_almost_eq(f.volume(), v0, v0 * 0.01, "без источников и испарения объём почти не меняется (плёнки тоньше WET сохнут)")
	var a := f.level_at(t.lake_c.x, t.lake_c.y)
	var b := f.level_at(t.lake_c.x - 2.0, t.lake_c.y + 1.0)
	assert_almost_eq(a, b, 0.05, "гладь выровнялась")

func test_source_raises_level_and_floods_shore():
	var t := _terrain(32)
	var f := ProtoFlow.new(t, _water())
	f.fill(t.lake_level, _in_lake(t))
	var wet0 := _wet_cells(f)
	var l0 := f.level_at(t.lake_c.x, t.lake_c.y)
	f.add_source(t.lake_c.x + t.lake_r * 0.7, t.lake_c.y, 8.0)
	for k in 600:
		f.step(0.1)
	assert_gt(f.level_at(t.lake_c.x, t.lake_c.y), l0 + 0.5, "озеро поднялось")
	assert_gt(_wet_cells(f), wet0 + 20, "вода вышла на берег")
	assert_true(f.wet_at(t.lake_c.x, t.lake_c.y))

func test_flood_cycle_rises_and_falls():
	var t := _terrain(32)
	var ll := ProtoLiquidLife.new()
	add_child_autofree(ll)
	ll.setup_lake(t, _water(), t.lake_level, _in_lake(t), 32)
	var peak := -ll.flood_phase + ProtoLiquidLife.FLOOD_PERIOD * 0.6
	if peak < 0.0:
		peak += ProtoLiquidLife.FLOOD_PERIOD
	ll.advance(peak)
	assert_gt(ll.lake_level(), t.lake_level + 0.8, "в паводок озеро выше")
	ll.advance(ProtoLiquidLife.FLOOD_PERIOD * 0.38)
	assert_lt(ll.lake_level(), t.lake_level + 0.35, "после спада — почти прежнее")

func test_lava_flows_down_and_hardens():
	var t := _terrain(7)
	assert_true(t.style.volcano)
	var lava := ProtoHealth.hazard_liquid(PlanetGen.generate(7))
	var ll := ProtoLiquidLife.new()
	add_child_autofree(ll)
	ll.setup_lake(t, lava, t.lake_level, _in_lake(t), 7)
	var f := ll.setup_volcano(lava)
	ll.erupt_next = 0.0
	ll.advance(ProtoLiquidLife.ERUPT_DUR + 5.0)
	assert_true(ll.erupt_left <= 0.0, "извержение кончилось")
	# Лава вышла за кратер и ниже него.
	var below := 0
	for z in f.nz:
		for x in f.nx:
			var i := f.idx(x, z)
			if f.d[i] > 0.05 and Vector2(x, z).distance_to(ProtoTerrain.VOLC_C) > 6.0 and f.hot[i] == 0:
				below += 1
	assert_gt(below, 10, "лава стекла по склону")
	ll.advance(120.0)
	assert_gt(ll.crust_cells(), 10, "остыла коркой")
	var i0 := -1
	for i in f.crust.size():
		if f.crust[i] > 0.05 and f.d[i] <= ProtoFlow.SHOW:
			i0 = i
			break
	assert_gt(i0, -1)
	assert_false(f.wet_at(i0 % f.nx + 0.5, i0 / f.nx + 0.5), "по корке не жжёт")
	assert_false(f.crust_shape().is_empty(), "по корке можно ходить")

func _wet_cells(f: ProtoFlow) -> int:
	var n := 0
	for v in f.d:
		if v > ProtoFlow.SHOW:
			n += 1
	return n
