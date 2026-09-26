extends GutTest
## Баланс целей: осуществимость тегов цели, бур с соседними клетками, предел насоса.

var H := TestHelpers

func test_goal_tags_obtainable_by_real_processing():
	for s in range(1, 31):
		var p := PlanetGen.generate(s)
		var pr := PlanetGen._probe(p)
		for t in Goals.required_tags(p.goal):
			assert_true(PlanetGen._obtainable(pr, t, p.materials),
				"seed %d, цель %s: тег «%s» получается настоящей обработкой" % [s, p.goal.id, t])

func test_generation_stays_deterministic():
	var a := PlanetGen.generate(12)
	var b := PlanetGen.generate(12)
	assert_eq(a.goal.rare, b.goal.rare)
	assert_eq(a.materials.map(func(m): return m.id), b.materials.map(func(m): return m.id))

func test_drill_reaches_neighbour_cell_of_same_material():
	var w := H.world()
	var ore := w.db.add(Substance.new("ore", "Руда", ["brittle"]))
	var other := w.db.add(Substance.new("oth", "Другое", ["dense"]))
	w.planet.deposits[Vector2i(10, 10)] = {"sub": ore.id, "amount": 0.0}
	w.planet.deposits[Vector2i(11, 11)] = {"sub": ore.id, "amount": 5.0}
	w.planet.deposits[Vector2i(9, 10)] = {"sub": other.id, "amount": 50.0}
	var d := w.place("drill", Vector2i(10, 10), 0, w.starter, true)
	w.place("container", Vector2i(11, 10), 0, w.starter, true)
	H.run(w, 10.0)
	assert_eq(d.status, "добывает соседнюю клетку")
	assert_lt(w.planet.deposits[Vector2i(11, 11)].amount, 5.0, "соседняя клетка того же материала убывает")
	assert_eq(w.planet.deposits[Vector2i(9, 10)].amount, 50.0, "чужой материал не трогается")

func test_drill_skips_cell_under_another_machine():
	var w := H.world()
	var ore := w.db.add(Substance.new("ore", "Руда", ["brittle"]))
	w.planet.deposits[Vector2i(10, 10)] = {"sub": ore.id, "amount": 0.0}
	w.planet.deposits[Vector2i(10, 11)] = {"sub": ore.id, "amount": 20.0}
	var d := w.place("drill", Vector2i(10, 10), 0, w.starter, true)
	w.place("drill", Vector2i(10, 11), 0, w.starter, true)
	H.run(w, 1.0)
	assert_eq(d.status, "залежь пуста")

func test_pump_stops_at_its_material_limit():
	var w := H.world()
	var weak := w.db.add(Substance.new("weak", "Слабый", ["brittle"]))
	var pump := w.place("pump", Vector2i(10, 10), 0, weak, true)
	pump.config.target_p = 50.0
	H.run(w, 120.0)
	var limit: float = pump.stats.max_p * 0.95
	assert_lt(w.gas.pressure(pump.id), limit + 0.2, "насос не качает выше предела материала")
	assert_true(pump.status.begins_with("упёрся в предел"), pump.status)

func test_bot_pump_prefers_strong_material():
	var w := World.create(31)
	var bot := BalanceBot.new(w)
	var c := bot._free_near(w.planet.spawn)
	var silo := w.place("launch_silo", c, 0, w.starter, true)
	w.robot.add_item(Portion.new(w.starter, 30.0))
	var n := bot.pump_for(silo, 9.5, 1, 6.5)
	assert_eq(n, 1)
	var best := 0.0
	for m in w.machines_of("pump"):
		best = max(best, m.stats.max_p * 0.95)
	assert_gte(best, 6.5, "насос шахты держит 6.5 атм")
