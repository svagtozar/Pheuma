extends GutTest
## Сборные сооружения и пушечная логистика.

var H := TestHelpers

func _sub(w: World, tags: Array) -> Substance:
	var n := "S" + str(w.db.by_id.size())
	return w.db.add(Substance.new(n, n, tags))

func test_cannon_routes_by_tag():
	var w := H.world()
	var dense := _sub(w, ["dense", "metallic"])
	var light := _sub(w, ["porous", "crystalline"])
	var cannon := w.place("cannon", Vector2i(5, 10), 0, w.starter, true)
	w.place("pump", Vector2i(5, 11), 0, w.starter, true)
	var r_def := w.place("receiver", Vector2i(10, 10), 0, w.starter, true)
	var r_dense := w.place("receiver", Vector2i(5, 5), 0, w.starter, true)
	assert_eq(w.link_cannon(cannon.cell, r_def.cell), "")
	assert_eq(w.link_cannon(cannon.cell, r_dense.cell, "dense"), "")
	cannon.store(Portion.new(dense, 3.0))
	cannon.store(Portion.new(light, 3.0))
	H.run(w, 30.0)
	var got_dense := 0.0
	var got_light := 0.0
	for p in r_dense.items:
		got_dense += p.mass if p.has("dense") else 0.0
	for p in r_def.items:
		got_light += p.mass if p.has("porous") else 0.0
	assert_gt(got_dense, 2.0, "плотное улетело по маршруту")
	assert_gt(got_light, 2.0, "остальное — в цель по умолчанию")

func test_route_removed_with_target():
	var w := H.world()
	var cannon := w.place("cannon", Vector2i(5, 10), 0, w.starter, true)
	var r := w.place("receiver", Vector2i(9, 10), 0, w.starter, true)
	w.link_cannon(cannon.cell, r.cell, "dense")
	assert_eq(cannon.config.routes.size(), 1)
	w.remove_at(r.cell)
	assert_eq(cannon.config.routes.size(), 0)

func _battery(w: World, o: Vector2i) -> Machine:
	var a := w.place("battery_section", o, 0, w.starter, true)
	w.place("battery_section", o + Vector2i(1, 0), 0, w.starter, true)
	w.place("battery_section", o + Vector2i(0, 1), 0, w.starter, true)
	w.place("battery_section", o + Vector2i(1, 1), 0, w.starter, true)
	return a

func test_battery_needs_assembly_and_fires_heavy_and_far():
	var w := H.world()
	var lone := w.place("battery_section", Vector2i(2, 30), 0, w.starter, true)
	assert_false(lone.accept(Portion.new(w.starter, 1.0), Vector2i(1, 30)), "одиночная секция не стреляет")
	var a := _battery(w, Vector2i(2, 5))
	w.place("pump", Vector2i(2, 7), 0, w.starter, true)
	w.place("pump", Vector2i(3, 7), 0, w.starter, true)
	w.place("pump", Vector2i(4, 6), 0, w.starter, true)
	var far := w.place("receiver", Vector2i(25, 5), 0, w.starter, true)
	H.run(w, 1.5)
	assert_eq(a.master_id, a.id)
	assert_eq(w.link_cannon(Vector2i(3, 6), far.cell), "", "наводится с любой секции")
	var cargo := _sub(w, ["crystalline", "conductive"])
	assert_true(a.accept(Portion.new(cargo, 20.0), Vector2i(1, 5)))
	for m in w.machines.values():
		if m.kind == "pump":
			m.config.target_p = 5.0
	H.run(w, 40.0)
	assert_gt(far.total_mass(), 15.0, "20 кг долетели на 22 клетки")

func test_catch_net_funnels_capsule_to_receiver():
	var w := H.world()
	var r := w.place("receiver", Vector2i(10, 10), 0, w.starter, true)
	w.place("catch_net", Vector2i(11, 10), 0, w.starter, true)
	w.place("catch_net", Vector2i(12, 10), 0, w.starter, true)
	assert_eq(w.net_receiver(Vector2i(12, 10)), r)
	w.spawn_projectile(Vector2(3.5, 10.5), Vector2(12.5, 10.5), [Portion.new(w.starter, 2.0)])
	H.run(w, 3.0)
	assert_almost_eq(r.total_mass(), 2.0, 0.01)

func test_net_reach_depends_on_material():
	var w := H.world()
	var el := _sub(w, ["elastic", "fibrous"])
	var plain := _sub(w, ["dense", "metallic"])
	var a := w.place("catch_net", Vector2i(1, 1), 0, el, true)
	var b := w.place("catch_net", Vector2i(3, 3), 0, plain, true)
	assert_gt(a.net_reach(), b.net_reach())

func test_warehouse_assembles_from_four_sections():
	var w := H.world()
	var a := w.place("warehouse_section", Vector2i(5, 5), 0, w.starter, true)
	w.place("warehouse_section", Vector2i(6, 5), 0, w.starter, true)
	w.place("warehouse_section", Vector2i(5, 6), 0, w.starter, true)
	assert_eq(a.capacity(), 20.0)
	var d := w.place("warehouse_section", Vector2i(6, 6), 0, w.starter, true)
	H.run(w, 1.5)
	assert_eq(a.master_id, a.id)
	assert_eq(a.capacity(), 320.0)
	assert_true(d.accept(Portion.new(w.starter, 100.0), Vector2i(6, 7)))
	assert_almost_eq(a.total_mass(), 100.0, 0.01)
	w.remove_at(d.cell)
	H.run(w, 1.5)
	assert_eq(a.master_id, -1)
