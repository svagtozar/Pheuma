extends GutTest
## Макроблоки 2.0: газовые и сигнальные порты, свёртка на месте, разворот, параметры.

var H := TestHelpers

func _ore(w: World) -> Substance:
	return w.db.add(Substance.new("ore", "Руда", ["brittle", "crystalline"]))

## Пушка → приёмник внутри схемы; снаружи насос через трубу к пушке.
func test_gas_port_feeds_inner_cannon_from_outside():
	var w := H.world()
	var inlet := w.place("container", Vector2i(10, 10), 0, w.starter, true)
	inlet.config.pass_through = true
	var cannon := w.place("cannon", Vector2i(11, 10), 0, w.starter, true)
	var recv := w.place("receiver", Vector2i(15, 10), 0, w.starter, true)
	w.link_cannon(cannon.cell, recv.cell)
	var res := Macroblocks.collapse_region(w, Rect2i(10, 10, 6, 1), "пушечный узел")
	assert_eq(res.err, "")
	var macro: MacroMachine = res.macro
	assert_true(macro.has_gas(), "у пушки на краю — газовый порт")
	# Снаружи: насос и труба рядом с блоком.
	w.place("pipe", macro.cell + Vector2i(0, 1), 0, w.starter, true)
	w.place("pump", macro.cell + Vector2i(0, 2), 0, w.starter, true)
	var inner_cannon: Machine = macro.inner.machines_of("cannon")[0]
	inner_cannon.store(Portion.new(w.starter, 3.0))
	var p0: float = macro.inner.gas.pressure(inner_cannon.id)
	H.run(w, 30.0)
	var inner_recv: Machine = macro.inner.machines_of("receiver")[0]
	assert_gt(inner_recv.total_mass() + macro.inner.gas.pressure(inner_cannon.id) - p0, 0.5, "газ дошёл до внутренней пушки")
	assert_gt(inner_recv.total_mass(), 1.0, "пушка выстрелила внутри блока")

func test_gas_exchange_conserves():
	var w := H.world()
	var t := w.place("tank", Vector2i(5, 5), 0, w.starter, true)
	w.gas.add_gas(t.id, 10.0)
	var res := Macroblocks.collapse_region(w, Rect2i(5, 5, 1, 1), "бак")
	var macro: MacroMachine = res.macro
	var pipe := w.place("pipe", Vector2i(6, 5), 0, w.starter, true)
	var total: float = w.gas.total_gas() + macro.inner.gas.total_gas()
	for i in 100:
		w.tick(0.1)
	assert_almost_eq(w.gas.total_gas() + macro.inner.gas.total_gas(), total, 0.01)
	assert_gt(w.gas.pressure(pipe.id), 1.2, "газ вышел из блока в трубу")

func test_signal_out_closes_outer_valve():
	var w := H.world()
	var box := w.place("container", Vector2i(10, 10), 0, w.starter, true)
	var sensor := w.place("sensor", Vector2i(10, 11), 3, w.starter, true)
	sensor.config.threshold = 0.05
	var valve := w.place("valve", Vector2i(20, 20), 0, w.starter, true)
	var inv := w.place("gate_not", Vector2i(19, 20), 0, w.starter, true)
	w.logic.add_wire(sensor.id, inv.id, 0)
	w.logic.add_wire(inv.id, valve.id, 0)
	var res := Macroblocks.collapse_region(w, Rect2i(10, 10, 1, 2), "датчик уровня")
	assert_eq(res.err, "")
	var macro: MacroMachine = res.macro
	assert_eq(macro.mb.sig_out.size(), 1)
	assert_eq(w.logic.wires_from(macro.id).size(), 1, "внешний провод переподключён к блоку")
	H.run(w, 1.0)
	assert_true(valve.enabled)
	macro.inner.machines_of("container")[0].store(Portion.new(w.starter, 10.0))
	H.run(w, 1.0)
	assert_true(macro.signal_out)
	assert_false(valve.enabled, "датчик внутри блока закрыл внешний клапан")

func test_signal_in_drives_only_target_machine():
	var w := H.world()
	var src := w.place("container", Vector2i(2, 2), 0, w.starter, true)
	var outer_sensor := w.place("sensor", Vector2i(2, 3), 3, w.starter, true)
	outer_sensor.config.threshold = 0.05
	var a := w.place("crusher", Vector2i(10, 10), 0, w.starter, true)
	var b := w.place("crusher", Vector2i(10, 12), 0, w.starter, true)
	w.logic.add_wire(outer_sensor.id, a.id, 0)
	var res := Macroblocks.collapse_region(w, Rect2i(10, 10, 1, 3), "две дробилки")
	var macro: MacroMachine = res.macro
	assert_true(macro.has_sig_in())
	H.run(w, 1.0)
	var ia = macro.inner.machine_at(Vector2i(0, 0))
	var ib = macro.inner.machine_at(Vector2i(0, 2))
	assert_false(ia.enabled, "нет сигнала — целевая дробилка стоит")
	assert_true(ib.enabled, "вторая дробилка не зависит от сигнала")
	src.store(Portion.new(w.starter, 10.0))
	H.run(w, 1.0)
	assert_true(ia.enabled, "сигнал пришёл — дробилка включилась")

func test_collapse_in_place_keeps_state():
	var w := H.world()
	var f := w.place("filter", Vector2i(5, 5), 0, w.starter, true)
	f.config.tag = "porous"
	var box := w.place("container", Vector2i(6, 5), 0, w.starter, true)
	box.store(Portion.new(w.starter, 7.0))
	var t := w.place("tank", Vector2i(5, 6), 0, w.starter, true)
	w.gas.add_gas(t.id, 5.0)
	var p_tank: float = w.gas.pressure(t.id)
	var n := w.machines.size()
	var res := Macroblocks.collapse_region(w, Rect2i(5, 5, 2, 2), "узел")
	assert_eq(res.err, "")
	var macro: MacroMachine = res.macro
	assert_eq(w.machines.size(), n - 3 + 1)
	assert_eq(macro.cell, Vector2i(5, 5))
	var inner_f = macro.inner.machine_at(Vector2i(0, 0))
	var inner_box = macro.inner.machine_at(Vector2i(1, 0))
	var inner_t = macro.inner.machine_at(Vector2i(0, 1))
	assert_eq(inner_f.config.tag, "porous")
	assert_almost_eq(inner_box.total_mass(), 7.0, 0.01)
	assert_almost_eq(macro.inner.gas.pressure(inner_t.id), p_tank, 0.01)

func test_collapse_remaps_internal_cannon_route():
	var w := H.world()
	var c := w.place("cannon", Vector2i(2, 2), 0, w.starter, true)
	var r1 := w.place("receiver", Vector2i(5, 2), 0, w.starter, true)
	var r2 := w.place("receiver", Vector2i(5, 3), 0, w.starter, true)
	w.link_cannon(c.cell, r1.cell)
	w.link_cannon(c.cell, r2.cell, "dense")
	var res := Macroblocks.collapse_region(w, Rect2i(2, 2, 4, 2), "сортировка")
	var macro: MacroMachine = res.macro
	var ic = macro.inner.machine_at(Vector2i(0, 0))
	var ir1 = macro.inner.machine_at(Vector2i(3, 0))
	var ir2 = macro.inner.machine_at(Vector2i(3, 1))
	assert_eq(ic.config.target, ir1.id)
	assert_eq(ic.config.routes, [["dense", ir2.id]])

func test_unfold_restores_machines_rotated_with_state():
	var w := H.world()
	w.robot.add_item(Portion.new(w.starter, 200.0))
	var box := w.place("container", Vector2i(2, 2), 0, w.starter, true)
	box.config.pass_through = true
	var cr := w.place("crusher", Vector2i(3, 2), 0, w.starter, true)
	var s := w.place("sensor", Vector2i(3, 3), 3, w.starter, true)
	w.logic.add_wire(s.id, cr.id, 0, [Vector2(3.5, 2.8)])
	var mb = JSON.parse_string(JSON.stringify(Macroblocks.capture(w, Rect2i(2, 2, 2, 2), "дробильня")))
	for c in [Vector2i(2, 2), Vector2i(3, 2), Vector2i(3, 3)]:
		w.remove_at(c, false)
	assert_eq(Macroblocks.place_collapsed(w, mb, Vector2i(10, 10), 1, w.starter), "")
	var macro: MacroMachine = w.machine_at(Vector2i(10, 10))
	macro.inner.machine_at(Vector2i(0, 0)).store(Portion.new(_ore(w), 4.0))
	assert_eq(Macroblocks.unfold(w, macro), "")
	assert_false(w.machines.has(macro.id))
	# Поворот на 90°: (0,0)→(1,0), (1,0)→(1,1), (1,1)→(0,1)
	var b2 = w.machine_at(Vector2i(11, 10))
	var c2 = w.machine_at(Vector2i(11, 11))
	var s2 = w.machine_at(Vector2i(10, 11))
	assert_eq(b2.kind, "container")
	assert_eq(c2.kind, "crusher")
	assert_eq(c2.facing, 1)
	assert_eq(s2.kind, "sensor")
	assert_almost_eq(b2.total_mass() + c2.total_mass(), 4.0, 0.01)
	assert_eq(w.logic.wires_to(c2.id).size(), 1)
	assert_eq(w.logic.wires_to(c2.id)[0].from, s2.id)

func test_unfold_blocked_by_occupied_cell():
	var w := H.world()
	w.place("container", Vector2i(2, 2), 0, w.starter, true)
	w.place("container", Vector2i(3, 2), 0, w.starter, true)
	var res := Macroblocks.collapse_region(w, Rect2i(2, 2, 2, 1), "пара")
	var macro: MacroMachine = res.macro
	w.place("pipe", Vector2i(3, 2), 0, w.starter, true)
	assert_string_contains(Macroblocks.unfold(w, macro), "3,2")
	assert_true(w.machines.has(macro.id), "блок на месте")

func test_inner_parameter_change_affects_behaviour():
	var w := H.world()
	var inlet := w.place("container", Vector2i(10, 10), 0, w.starter, true)
	inlet.config.pass_through = true
	var f := w.place("filter", Vector2i(11, 10), 0, w.starter, true)
	f.config.tag = "porous"
	var res := Macroblocks.collapse_region(w, Rect2i(10, 10, 2, 1), "фильтр")
	var macro: MacroMachine = res.macro
	var src := w.place("container", Vector2i(9, 10), 0, w.starter, true)
	src.config.pass_through = true
	var straight := w.place("container", Vector2i(11, 10), 0, w.starter, true)
	var side := w.place("container", Vector2i(10, 11), 0, w.starter, true)
	var dense := w.db.add(Substance.new("d", "D", ["dense", "metallic"]))
	# Фильтр пропускает прямо только «пористое» — плотное уходит в правый выход блока.
	src.store(Portion.new(dense, 3.0))
	H.run(w, 10.0)
	assert_almost_eq(straight.total_mass(), 0.0, 0.01)
	assert_gt(side.total_mass(), 2.0)
	macro.inner.machine_at(Vector2i(1, 0)).config.tag = "dense"
	src.store(Portion.new(dense, 3.0))
	H.run(w, 10.0)
	assert_gt(straight.total_mass(), 2.0, "после смены тега плотное пошло прямо")

func test_save_load_macro_with_ports():
	var w := World.create(14)
	var c := w.planet.spawn + Vector2i(3, 0)
	var t := w.place("tank", c, 0, w.starter, true)
	var s := w.place("sensor", c + Vector2i(0, 1), 3, w.starter, true)
	var v := w.place("valve", c + Vector2i(5, 3), 0, w.starter, true)
	w.logic.add_wire(s.id, v.id, 0)
	w.gas.add_gas(t.id, 6.0)
	var res := Macroblocks.collapse_region(w, Rect2i(c, Vector2i(1, 2)), "бак с датчиком")
	var macro: MacroMachine = res.macro
	var outer_gas: float = w.gas.amount(macro.id)
	var w2 := SaveGame.from_dict(JSON.parse_string(JSON.stringify(SaveGame.to_dict(w))))
	var m2 = w2.machine_at(macro.cell)
	assert_true(m2 is MacroMachine)
	assert_true(m2.has_gas())
	assert_eq(m2.sig_out_ids.size(), 1)
	assert_almost_eq(w2.gas.amount(m2.id), outer_gas, 0.01)
	assert_eq(w2.logic.wires_from(m2.id).size(), 1)
