extends GutTest
## Логистика: маршруты по тегу у выхода любой машины, карта потоков, дальность, узкое место.

var H := TestHelpers

## Контейнер со сквозной выдачей в (10,10) с насосом рядом; цели А и Б дальше.
func _sorter(w: World) -> Dictionary:
	var dense := w.db.add(Substance.new("dn", "Плотное", ["dense"]))
	var light := w.db.add(Substance.new("lt", "Лёгкое", ["porous"]))
	var src := w.place("container", Vector2i(10, 10), 0, w.starter, true)
	src.config.pass_through = true
	w.place("pump", Vector2i(10, 11), 0, w.starter, true)
	var a := w.place("container", Vector2i(13, 8), 0, w.starter, true)
	var b := w.place("container", Vector2i(13, 12), 0, w.starter, true)
	src.store(Portion.new(dense, 4.0))
	src.store(Portion.new(light, 4.0))
	return {"src": src, "a": a, "b": b, "dense": dense, "light": light}

func _mass_of(m: Machine, s: Substance) -> float:
	var t := 0.0
	for p in m.items:
		if p.substance == s:
			t += p.mass
	return t

func test_routes_split_cargo_by_tag():
	var w := H.world()
	var d := _sorter(w)
	assert_eq(w.link_output(d.src.cell, d.a.cell, 0, "dense"), "")
	assert_eq(w.link_output(d.src.cell, d.b.cell), "")
	H.run(w, 40.0)
	assert_gt(_mass_of(d.a, d.dense), 3.0, "плотное ушло по маршруту в А")
	assert_almost_eq(_mass_of(d.a, d.light), 0.0, 0.01)
	assert_gt(_mass_of(d.b, d.light), 3.0, "остальное — в цель выстрела Б")

func test_route_without_default_goes_to_neighbour():
	var w := H.world()
	var d := _sorter(w)
	var nb := w.place("container", Vector2i(11, 10), 0, w.starter, true)
	w.link_output(d.src.cell, d.a.cell, 0, "dense")
	H.run(w, 40.0)
	assert_gt(_mass_of(d.a, d.dense), 3.0)
	assert_gt(_mass_of(nb, d.light), 3.0, "без цели выстрела — соседу по стрелке, как раньше")

func test_relink_route_and_target_removal():
	var w := H.world()
	var d := _sorter(w)
	w.link_output(d.src.cell, d.a.cell, 0, "dense")
	assert_eq(d.src.shot_routes(0).size(), 1)
	w.link_output(d.src.cell, d.a.cell, 0, "dense")
	assert_eq(d.src.shot_routes(0).size(), 0, "повтор снимает маршрут")
	w.link_output(d.src.cell, d.a.cell, 0, "dense")
	w.remove_at(d.a.cell, false)
	assert_eq(d.src.shot_routes(0).size(), 0, "снос цели снимает маршрут")

func test_routes_survive_save_and_macro():
	var w := H.world()
	var d := _sorter(w)
	w.link_output(d.src.cell, d.a.cell, 0, "dense")
	var md = JSON.parse_string(JSON.stringify(SaveGame.machine_to(d.src, w.gas)))
	var m2 := w.place("container", Vector2i(30, 30), 0, w.starter, true)
	SaveGame.machine_restore(w, m2, md, w.gas)
	assert_eq(int(m2.shot_routes(0)[0][1]), d.a.id)
	var mb = JSON.parse_string(JSON.stringify(Macroblocks.capture(w, Rect2i(10, 8, 4, 5), "сортировка")))
	w.robot.add_item(Portion.new(w.starter, 300.0))
	assert_eq(Macroblocks.place(w, mb, Vector2i(20, 20), 0, w.starter), "")
	var s2 = w.machine_at(Vector2i(20, 22))
	var a2 = w.machine_at(Vector2i(23, 20))
	assert_eq(int(s2.shot_routes(0)[0][1]), a2.id, "маршрут переехал с блоком")
	var res := Macroblocks.collapse_region(w, Rect2i(20, 20, 4, 5), "сортировка")
	assert_eq(res.err, "")
	var inner_src = res.macro.inner.machine_at(Vector2i(0, 2))
	var inner_a = res.macro.inner.machine_at(Vector2i(3, 0))
	assert_eq(int(inner_src.shot_routes(0)[0][1]), inner_a.id, "внутри блока маршрут сохранён")

func test_flow_counts_push_and_shots_and_decays():
	var w := H.world()
	var c := Vector2i(12, 12)
	w.planet.deposits[c] = {"sub": w.starter.id, "amount": 500.0}
	var dr := w.place("drill", c, 0, w.starter, true)
	var box := w.place("container", c + Vector2i(1, 0), 0, w.starter, true)
	H.run(w, 20.0)
	assert_gt(w.flow.get("%d>%d" % [dr.id, box.id], 0.0), 0.5, "поток бур → контейнер учтён")
	var d := _sorter(w)
	w.link_output(d.src.cell, d.b.cell)
	H.run(w, 10.0)
	assert_gt(w.flow.get("%d>%d" % [d.src.id, d.b.id], 0.0), 0.3, "поток выстрелом учтён")
	w.remove_at(dr.cell, false)
	H.run(w, 60.0)
	assert_false(w.flow.has("%d>%d" % [dr.id, box.id]), "без груза поток затухает")

func test_flow_state():
	var w := H.world()
	var c := Vector2i(12, 12)
	w.planet.deposits[c] = {"sub": w.starter.id, "amount": 500.0}
	var dr := w.place("drill", c, 0, w.starter, true)
	H.run(w, 10.0)
	assert_eq(dr.flow_state(), "blocked", "бур без приёмника — забит")
	var cr := w.place("crusher", Vector2i(20, 20), 0, w.starter, true)
	assert_eq(cr.flow_state(), "idle")

func test_reach_from_neighbour_pipe():
	var w := H.world()
	var cr := w.place("drill", Vector2i(10, 10), 0, w.starter, true)
	assert_almost_eq(Cannon.reach(w, cr), 0.0, 0.01, "у бура своего газа нет — без трубы рядом не дострелит")
	var p := w.place("pipe", Vector2i(10, 11), 0, w.starter, true)
	w.gas.nodes[p.id].n = 4.0 * w.gas.nodes[p.id].v / w.gas.temp_factor()
	assert_almost_eq(Cannon.reach(w, cr), Cannon.range_for(4.0, w.planet) * Machine.SHOT_MULT, 0.01)

func test_bottleneck_points_to_slow_machine():
	var w := H.world()
	var c := Vector2i(12, 12)
	var ore := w.db.add(Substance.new("ore", "Руда", ["brittle"]))
	w.planet.deposits[c] = {"sub": ore.id, "amount": 500.0}
	w.place("drill", c, 0, w.starter, true)
	var cr := w.place("crusher", c + Vector2i(1, 0), 0, w.starter, true)
	w.place("container", c + Vector2i(2, 0), 0, w.starter, true)
	cr.stats.speed = 0.05   # очень медленная дробилка
	H.run(w, 60.0)
	assert_eq(Advisor.bottleneck(w), cr)
	assert_true(Advisor.advise(w, true).text.contains("Узкое место"), Advisor.advise(w, true).text)
