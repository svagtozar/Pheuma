extends GutTest

func test_planet_deterministic():
	var a := PlanetGen.generate(123)
	var b := PlanetGen.generate(123)
	assert_eq(a.tags, b.tags)
	assert_eq(a.name, b.name)
	assert_eq(a.tiles, b.tiles)
	assert_eq(a.deposits.size(), b.deposits.size())
	assert_eq(a.goal.id, b.goal.id)

func test_planet_tags_compatible_and_count():
	for s in 40:
		var p := PlanetGen.generate(s)
		assert_between(p.tags.size(), 3, 5)
		for x in p.tags:
			for y in p.tags:
				if x != y:
					assert_true(PlanetTags.compatible(x, y), "%s + %s" % [x, y])

func test_runs_are_varied():
	var tagsets := {}
	var goals := {}
	for s in 40:
		var p := PlanetGen.generate(s)
		tagsets[",".join(p.tags)] = true
		goals[p.goal.id] = true
	assert_gt(tagsets.size(), 30, "планеты должны отличаться тегами")
	assert_gt(goals.size(), 2, "цели должны отличаться")

func test_environment_follows_tags():
	for s in 60:
		var p := PlanetGen.generate(s)
		if p.has_tag("thin_atmosphere"):
			assert_lt(p.atm_pressure, 0.5)
		if p.has_tag("low_gravity"):
			assert_lt(p.gravity, 1.0)
		if p.has_tag("volcanic"):
			assert_gt(p.ambient_temp, 40.0)

func test_atmosphere_is_gas():
	for s in 20:
		var p := PlanetGen.generate(s)
		assert_eq(p.atmosphere.phase_at(p.ambient_temp), Substance.Phase.GAS)

func test_goal_is_feasible():
	for s in 40:
		var p := PlanetGen.generate(s)
		var have := Recipes.reachable(p.material_tags_present(), p.tags)
		for t in Goals.required_tags(p.goal):
			assert_true(have.has(t), "seed %d: цель %s требует %s" % [s, p.goal.id, t])

func test_spawn_is_clear_and_deposits_on_ground():
	var p := PlanetGen.generate(5)
	assert_true(p.walkable(p.spawn))
	assert_gt(p.deposits.size(), 20)
	for c in p.deposits:
		assert_true(p.buildable(c))

func test_soft_materials_near_spawn():
	for s in 10:
		var p := PlanetGen.generate(s)
		var near := 0
		for c in p.deposits:
			if (c - p.spawn).length() < 20:
				near += 1
		assert_gt(near, 0, "seed %d" % s)

func test_anomaly_goal_only_on_anomaly_planets():
	for s in 80:
		var p := PlanetGen.generate(s)
		if p.goal.id == "anomaly":
			assert_true(p.has_anomaly())
