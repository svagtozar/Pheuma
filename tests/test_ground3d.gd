extends GutTest
## Толща планеты (ProtoGround): профиль выветривания сверху, пачка пластов из
## материалов планеты, складки и разломы, жилы секут пласты, мерзлота.

func _g(seed_value: int) -> ProtoGround:
	var planet := PlanetGen.generate(seed_value)
	var t := ProtoTerrain.new(seed_value, ProtoWorldStyle.for_planet(planet))
	ProtoSky.palette(planet, t)
	return t.ground_model

func test_weathering_profile_top_down():
	var g := _g(14)
	var p := Vector3(30.0, 10.0, 30.0)
	assert_eq(g.layer_at(p, 0.1), ProtoGround.SOIL, "сверху — почва")
	assert_eq(g.layer_at(p, (g._soil(1.0) + g.sub_d) * 0.5), ProtoGround.SUBSOIL, "под ней — подпочва")
	var deep: int = g.dig_yield(p, 25.0).kind
	assert_true(deep in [ProtoGround.ROCK, ProtoGround.VEIN, ProtoGround.FAULT, ProtoGround.DIKE], "глубоко — коренная порода")
	assert_lt(g._soil(0.5), g._soil(1.0) * 0.3, "на крутом почвы почти нет")

func test_bands_are_planet_solids_and_several():
	var planet := PlanetGen.generate(14)
	var ids: Array = ProtoSky.solid_mats(planet).map(func(m): return m.id)
	var g := _g(14)
	var seen := {}
	for y in range(-20, 20):
		var k := g.layer_at(Vector3(20.0, y * 1.5, 20.0), 30.0)
		if g.layers[k].kind != ProtoGround.ROCK:
			continue
		var s = g.layers[k].sub
		if s != null:
			assert_true(ids.has(s.id), "пласт — твёрдый материал планеты")
		seen[k] = true
	assert_gt(seen.size(), 2, "в стене видно несколько пластов")

func test_fault_offsets_layers():
	var g := _g(14)
	assert_gt(g.faults.size(), 0)
	var f: Dictionary = g.faults[0]
	var n: Vector3 = f.n
	var on: Vector3 = n * float(f.d)                   # точка на плоскости разлома
	var a: Vector3 = on - n * 2.0
	var b: Vector3 = on + n * 2.0
	assert_almost_eq(g._band_y(b) - g._band_y(a), float(f.throw), 3.0, "по разные стороны шва пласты сдвинуты на бросок")
	assert_eq(g.layers[g._cross(on)].kind in [ProtoGround.FAULT, ProtoGround.VEIN, ProtoGround.DIKE], true, "в шве — брекчия или жила")

func test_veins_cut_across_bands_and_pinch_out():
	var g := _g(14)
	assert_gt(g.vein_sets.size(), 0)
	var vl: int = g.vein_sets[0].layer
	var hits := 0
	var bands := {}
	for i in 6000:
		var p := Vector3(fmod(i * 7.31, 80.0), fmod(i * 3.17, 36.0), fmod(i * 5.77, 80.0))
		if g.layer_at(p, 20.0) == vl:
			hits += 1
			bands[int(g._band(g._band_y(p)).x)] = true
	assert_between(hits, 5, 600, "жила — тонкие листы, а не сплошь")
	assert_gt(bands.size(), 1, "жила идёт через несколько пластов")

func test_permafrost_on_cold_planets_only():
	var cold := _g(12)
	var hot := _g(7)
	assert_true(cold.ice_on)
	assert_false(hot.ice_on)
	var p := Vector3(33.0, 12.0, 21.0)
	assert_true(cold.dig_yield(p, 5.0).frozen, "под деятельным слоем — мёрзлое")
	assert_false(cold.dig_yield(p, cold.perm_d + 3.0).frozen, "ниже подошвы — талое")
	assert_false(hot.dig_yield(p, 5.0).frozen)
	var wedges := 0
	for i in 3000:
		var q := Vector3(fmod(i * 1.37, 80.0), 12.0, fmod(i * 2.91, 80.0))
		if cold.layer_at(q, cold._soil(1.0) + 0.3) == ProtoGround.ICE:
			wedges += 1
	assert_between(wedges, 5, 900, "ледяные клинья — сеткой, не сплошь")

func test_same_seed_same_ground():
	var a := _g(21)
	var b := _g(21)
	var p := Vector3(11.0, 7.0, 42.0)
	assert_eq(a.color_at(p, 5.0), b.color_at(p, 5.0))
	assert_eq(a.summary(), b.summary())
