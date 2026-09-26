extends GutTest

var H := TestHelpers

func _sub(w: World, tags: Array, name: String = "") -> Substance:
	if name == "":
		name = "M" + str(w.db.by_id.size())
	return w.db.add(Substance.new(name, name, tags))

func test_drill_fills_container():
	var w := H.world()
	var ore := _sub(w, ["porous", "organic"])
	w.planet.deposits[Vector2i(5, 5)] = {"sub": ore.id, "amount": 50.0}
	w.place("drill", Vector2i(5, 5), 0, w.starter, true)
	var box := w.place("container", Vector2i(6, 5), 0, w.starter, true)
	H.run(w, 20.0)
	assert_gt(box.total_mass(), 5.0)
	assert_eq(box.items[0].substance, ore)

func test_soft_drill_cannot_mine_hard_ore():
	var w := H.world()
	var ore := _sub(w, ["crystalline", "dense", "anchoring"])
	var soft := _sub(w, ["organic", "porous"])
	w.planet.deposits[Vector2i(5, 5)] = {"sub": ore.id, "amount": 50.0}
	var d := w.place("drill", Vector2i(5, 5), 0, soft, true)
	var box := w.place("container", Vector2i(6, 5), 0, w.starter, true)
	H.run(w, 10.0)
	assert_eq(box.total_mass(), 0.0)
	assert_string_contains(d.status, "мягкий")

func test_full_chain_drill_crusher_cannon_receiver_tank():
	var w := H.world()
	var ore := _sub(w, ["brittle", "crystalline"])
	w.planet.deposits[Vector2i(5, 5)] = {"sub": ore.id, "amount": 100.0}
	w.place("drill", Vector2i(5, 5), 0, w.starter, true)
	w.place("crusher", Vector2i(6, 5), 0, w.starter, true)
	var filt := w.place("filter", Vector2i(7, 5), 0, w.starter, true)
	filt.config.tag = "porous"
	var cannon := w.place("cannon", Vector2i(8, 5), 0, w.starter, true)
	w.place("pipe", Vector2i(8, 6), 0, w.starter, true)
	w.place("pump", Vector2i(8, 7), 0, w.starter, true)
	var recv := w.place("receiver", Vector2i(14, 5), 0, w.starter, true)
	var tank := w.place("tank", Vector2i(15, 5), 0, w.starter, true)
	assert_eq(w.link_cannon(cannon.cell, recv.cell), "")
	H.run(w, 90.0)
	assert_gt(tank.total_mass(), 3.0, "груз доехал до бака")
	var ok := false
	for p in tank.items:
		if p.has("porous"):
			ok = true
	assert_true(ok, "в баке порошок")
	assert_true(w.robot.known_tags.has("porous"), "тег, добавленный машиной, узнан")

func test_pipe_bursts_over_limit():
	var w := H.world()
	var weak := _sub(w, ["brittle", "porous"])
	weak.noise.hard = -1.0
	weak.recompute()
	var pump := w.place("pump", Vector2i(3, 3), 0, w.starter, true)
	pump.config.target_p = 20.0
	var pipe := w.place("pipe", Vector2i(4, 3), 0, weak, true)
	H.run(w, 60.0)
	assert_false(w.machines.has(pipe.id), "слабая труба лопнула")

func test_furnace_needs_pressure_and_burning_makes_gas():
	var w := H.world()
	var fuel := _sub(w, ["flammable", "dense"])
	var f := w.place("furnace", Vector2i(3, 3), 0, w.starter, true)
	f.accept(Portion.new(fuel, 4.0), Vector2i(2, 3))
	H.run(w, 5.0)
	assert_string_contains(f.status, "давления")
	w.gas.add_gas(f.id, 3.0)
	var before := w.gas.amount(f.id)
	H.run(w, 4.0)
	assert_gt(w.gas.amount(f.id), before - 0.5, "горение вернуло газ в узел")

func test_sensor_not_gate_stops_drill_when_full():
	var w := H.world()
	var ore := _sub(w, ["porous", "organic"])
	w.planet.deposits[Vector2i(5, 5)] = {"sub": ore.id, "amount": 500.0}
	var drill := w.place("drill", Vector2i(5, 5), 0, w.starter, true)
	var box := w.place("container", Vector2i(6, 5), 0, w.starter, true)
	var sensor := w.place("sensor", Vector2i(6, 6), 3, w.starter, true)
	sensor.config.threshold = 0.05
	var inv := w.place("gate_not", Vector2i(5, 7), 0, w.starter, true)
	w.logic.add_wire(sensor.id, inv.id, 0)
	w.logic.add_wire(inv.id, drill.id, 0)
	H.run(w, 30.0)
	assert_false(drill.enabled, "бур выключен сигналом")
	assert_lt(box.total_mass(), 6.0)

func test_resonant_container_emits_signal():
	var w := H.world()
	var res := _sub(w, ["resonant", "dense"])
	var box := w.place("container", Vector2i(3, 3), 0, w.starter, true)
	var valve := w.place("valve", Vector2i(8, 8), 0, w.starter, true)
	w.logic.add_wire(box.id, valve.id, 0)
	H.run(w, 1.0)
	assert_false(valve.enabled)
	box.store(Portion.new(res, 3.0))
	H.run(w, 1.5)
	assert_true(valve.enabled)

func test_volatile_lost_in_container_kept_in_tank():
	var w := H.world()
	var vol := _sub(w, ["volatile", "organic"])
	var box := w.place("container", Vector2i(3, 3), 0, w.starter, true)
	var tank := w.place("tank", Vector2i(6, 3), 0, w.starter, true)
	box.store(Portion.new(vol, 10.0))
	tank.store(Portion.new(vol, 10.0))
	H.run(w, 20.0)
	assert_lt(box.total_mass(), 6.0)
	assert_almost_eq(tank.total_mass(), 10.0, 0.1)

func test_acid_eats_metal_container():
	var w := H.world()
	var acid := _sub(w, ["acidic", "porous"])
	var box := w.place("container", Vector2i(3, 3), 0, w.starter, true)
	box.store(Portion.new(acid, 20.0))
	H.run(w, 200.0)
	assert_false(w.machines.has(box.id), "металлический контейнер разъеден")

func test_silo_launches_to_orbit_and_goal_counts():
	var w := H.world()
	var g: Dictionary = Goals.TEMPLATES.colony.duplicate(true)
	g.id = "colony"
	w.planet.goal = g
	w.goals.stage = 2
	var ore := _sub(w, ["dense", "metallic"])
	var silo := w.place("launch_silo", Vector2i(3, 3), 0, w.starter, true)
	silo.store(Portion.new(ore, 30.0))
	w.gas.add_gas(silo.id, w.gas.gas_for_pressure(silo.id, 9.0))
	H.run(w, 3.0)
	assert_gt(w.launched.mass, 15.0)
	assert_gt(w.launched.tags.get("dense", 0.0), 15.0)

func test_goal_stage_advances():
	var w := H.world()
	var g: Dictionary = Goals.TEMPLATES.mining.duplicate(true)
	g.id = "mining"
	g.stages[1].tags = {"dense": 1.0}
	w.planet.goal = g
	for i in 4:
		w.planet.deposits[Vector2i(3 + i, 3)] = {"sub": w.starter.id, "amount": 1.0}
		w.place("drill", Vector2i(3 + i, 3), 1, w.starter, true)
	var k := w.robot.knowledge
	H.run(w, 2.0)
	assert_eq(w.goals.stage, 1)
	assert_gt(w.robot.knowledge, k)

func test_material_changes_building_stats():
	var w := H.world()
	var brittle := _sub(w, ["brittle", "crystalline"])
	var elastic := _sub(w, ["elastic", "dense"])
	var insul := _sub(w, ["insulating", "crystalline"])
	var cond := _sub(w, ["conductive", "metallic"])
	assert_lt(ComponentStats.compute("pipe", brittle).max_p, ComponentStats.compute("pipe", elastic).max_p)
	assert_lt(ComponentStats.compute("dome", insul).heat_loss, 1.0)
	assert_gt(ComponentStats.compute("wire", cond).wire_range, ComponentStats.compute("wire", brittle).wire_range)
	assert_true(ComponentStats.compute("tank", insul).corrosion_proof)
	var hot := _sub(w, ["organic"])
	var furnace := w.place("furnace", Vector2i(3, 3), 0, hot, true)
	assert_lt(furnace.target_temp(w), 900.0, "печь из легкоплавкого материала не греет до 900")

func test_building_needs_material_properties():
	var w := H.world()
	var soft := _sub(w, ["organic", "porous"])
	w.robot.add_item(Portion.new(soft, 50.0))
	assert_string_contains(w.can_place("cannon", Vector2i(3, 3), soft), "твёрдость")
	assert_eq(w.can_place("container", Vector2i(3, 3), w.starter), "")
	var before := w.robot.mass_of(w.starter.id)
	w.place("container", Vector2i(3, 3), 0, w.starter)
	assert_almost_eq(w.robot.mass_of(w.starter.id), before - 4.0, 0.01)

func test_wire_range_depends_on_material():
	var w := H.world()
	var plain := _sub(w, ["organic", "porous"])
	var cond := _sub(w, ["conductive", "crystalline"])
	w.robot.add_item(Portion.new(plain, 20.0))
	w.robot.add_item(Portion.new(cond, 20.0))
	w.place("sensor", Vector2i(2, 2), 0, w.starter, true)
	w.place("valve", Vector2i(22, 2), 0, w.starter, true)
	assert_ne(w.add_wire(Vector2i(2, 2), Vector2i(22, 2), 0, plain), "")
	assert_eq(w.add_wire(Vector2i(2, 2), Vector2i(22, 2), 0, cond), "")

func test_dome_temperature_and_insulation():
	var w := H.world([], -60.0)
	var insul := _sub(w, ["insulating", "crystalline"])
	var dome := w.place("dome", Vector2i(5, 5), 0, insul, true)
	dome.temp = 20.0
	var plain := w.place("dome", Vector2i(15, 5), 0, w.starter, true)
	plain.temp = 20.0
	H.run(w, 30.0)
	assert_gt(dome.temp, plain.temp)

func test_starter_kit():
	var w := World.create(3)
	assert_gt(w.robot.mass_of(w.starter.id), 10.0)
	assert_not_null(w.robot.hull)
	assert_not_null(w.robot.drill)
	assert_true(w.robot.unlocked.has("drill"))
	assert_false(w.robot.unlocked.has("compressor"))
