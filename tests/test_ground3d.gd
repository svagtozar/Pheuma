extends GutTest
## Толща планеты (ProtoGround): почва сверху, осыпь, пласты пород из
## материалов планеты, мерзлота на холодных; что даёт бур.

func _g(seed_value: int) -> ProtoGround:
	var planet := PlanetGen.generate(seed_value)
	var t := ProtoTerrain.new(seed_value, ProtoWorldStyle.for_planet(planet))
	ProtoSky.palette(planet, t)
	return t.ground_model

func test_layers_follow_depth():
	var g := _g(14)
	var p := Vector3(30.0, 10.0, 30.0)
	assert_eq(g.layer_at(p, 0.1), ProtoGround.SOIL, "сверху — почва")
	assert_eq(g.dig_yield(p, 0.1).kind, ProtoGround.SOIL)
	assert_true(g.dig_yield(p, 12.0).kind in [ProtoGround.ROCK, ProtoGround.VEIN], "глубоко — порода или жила")
	assert_true(g.layer_at(p, g.sub_d - 0.7) in [ProtoGround.SUBSOIL, ProtoGround.ICE], "под почвой — осыпь")

func test_rock_bands_come_from_planet_solids():
	var planet := PlanetGen.generate(14)
	var solids: Array = ProtoSky.solid_mats(planet).map(func(m): return m.id)
	var g := _g(14)
	var seen := {}
	for y in range(-20, 20):
		var k := g.layer_at(Vector3(20.0, y * 1.5, 20.0), 30.0)
		assert_gte(k, ProtoGround.ROCK)
		if g.layers[k].kind != ProtoGround.ROCK:
			continue
		var s = g.layers[k].sub
		if s != null:
			assert_true(solids.has(s.id), "пласт — твёрдый материал планеты")
		seen[k] = true
	assert_gt(seen.size(), 1, "в стене видно несколько пластов")

func test_permafrost_only_on_cold_planets():
	var cold := _g(12)
	var hot := _g(7)
	assert_true(cold.ice_on)
	assert_false(hot.ice_on)
	var ice := 0
	for i in 200:
		var p := Vector3(i * 1.7, 12.0, i * 0.9)
		if cold.layer_at(p, cold.soil_d + 0.5) == ProtoGround.ICE:
			ice += 1
		assert_ne(hot.layer_at(p, hot.soil_d + 0.5), ProtoGround.ICE)
	assert_gt(ice, 5, "на холодной — линзы льда под почвой")

func test_same_seed_same_ground():
	var a := _g(21)
	var b := _g(21)
	var p := Vector3(11.0, 7.0, 42.0)
	assert_eq(a.color_at(p, 5.0), b.color_at(p, 5.0))
	assert_eq(a.summary(), b.summary())

func test_veins_cut_across_bands():
	var g := _g(14)
	assert_gt(g.veins.size(), 0)
	var vein_layer: int = g.veins[0].layer
	var hits := 0
	var bands := {}
	for i in 4000:
		var p := Vector3(fmod(i * 7.31, 80.0), fmod(i * 3.17, 36.0), fmod(i * 5.77, 80.0))
		if g.layer_at(p, 20.0) == vein_layer:
			hits += 1
			bands[g._band(g._band_y(p))] = true
	assert_between(hits, 20, 800, "жила — тонкие листы, а не сплошь")
	assert_gt(bands.size(), 1, "жила идёт через несколько пластов")
	var y := g.dig_yield(Vector3.ZERO, 20.0)
	assert_true(y.has("sub"))
	assert_eq(g.layers[vein_layer].kind, ProtoGround.VEIN)
