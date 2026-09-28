extends GutTest
## Планеты не повторяются пресетами: облик разбросан по сиду поверх тегов
## (ProtoWorldVariety, ProtoSky), а «Новая планета» — случайный непосещённый сид.

func test_looks_vary_by_seed():
	var looks := {}
	var grounds := {}
	var rivers := {}
	for s in 40:
		var p := PlanetGen.generate(s)
		var st := ProtoWorldStyle.for_planet(p)
		looks["%s|%s" % [st.cave, st.habit]] = true
		grounds[ProtoSky.ground_color(p).to_html(false)] = true
		rivers["%.2f" % st.river_z(30.0)] = true
	assert_gt(looks.size(), 12, "пещер × кристаллов разных сочетаний: %d" % looks.size())
	assert_gt(grounds.size(), 35, "цвет грунта у каждой планеты свой")
	assert_gt(rivers.size(), 30, "русло у каждой планеты своё")

func test_same_seed_same_look():
	var a := ProtoWorldStyle.for_planet(PlanetGen.generate(21))
	var b := ProtoWorldStyle.for_planet(PlanetGen.generate(21))
	assert_eq(a.relief_amp, b.relief_amp)
	assert_eq(a.river_z(10.0), b.river_z(10.0))
	assert_eq(a.habit, b.habit)

func test_river_keeps_cave_entry_and_lake_on_map():
	for s in 60:
		var st := ProtoWorldStyle.for_planet(PlanetGen.generate(s))
		assert_lte(st.river_z(40.0), 57.5, "сид %d: река не заливает вход в пещеру" % s)
		assert_gte(st.river_z(16.0), 44.0, "сид %d: озеро не лезет к площадке" % s)

func test_tags_still_rule():
	for s in 60:
		var p := PlanetGen.generate(s)
		var st := ProtoWorldStyle.for_planet(p)
		if p.has_tag("volcanic"):
			assert_true(st.volcano)
		if p.has_tag("crystalline_crust"):
			assert_eq(st.cave, "geode")
		elif p.has_tag("volcanic"):
			assert_eq(st.cave, "tube")
		elif p.has_tag("frozen"):
			assert_eq(st.cave, "ice")
			assert_eq(st.habit, "needle")

func test_new_seed_is_unvisited():
	for i in 5:
		var s := ProtoMainMenu.new_seed()
		assert_true(ProtoSave.read(s).is_empty())
