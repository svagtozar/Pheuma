extends GutTest
## Вложенные макроблоки: свёрнутый блок внутри другого.

var H := TestHelpers

func _ore(w: World) -> Substance:
	return w.db.add(Substance.new("ore", "Руда", ["brittle", "crystalline"]))

## Дробильня (контейнер → дробилка), свёрнутая на месте в клетке (10,10).
func _inner_block(w: World) -> MacroMachine:
	var box := w.place("container", Vector2i(10, 10), 0, w.starter, true)
	box.config.pass_through = true
	w.place("crusher", Vector2i(11, 10), 0, w.starter, true)
	var res := Macroblocks.collapse_region(w, Rect2i(10, 10, 2, 1), "дробильня")
	assert_eq(res.err, "")
	return res.macro

## Внешний блок в (10,10): дробильня + выходной контейнер справа.
func _outer_block(w: World) -> MacroMachine:
	_inner_block(w)
	var out := w.place("container", Vector2i(11, 10), 0, w.starter, true)
	out.config.pass_through = true
	var res := Macroblocks.collapse_region(w, Rect2i(10, 10, 2, 1), "цех")
	assert_eq(res.err, "")
	return res.macro

func _powder(m: Machine) -> float:
	var s := 0.0
	for p in m.items:
		if p.has("porous"):
			s += p.mass
	return s

func test_collapse_block_with_block_inside_processes():
	var w := H.world()
	var outer := _outer_block(w)
	assert_eq(outer.inner.machines.size(), 2)
	assert_eq(outer.inner.machines_of("macro").size(), 1, "внутри — свёрнутая дробильня")
	assert_eq(outer.all_inner().size(), 3, "всего примитивов три")
	assert_eq(MacroMachine.depth_of(outer.mb), 2)
	var src := w.place("container", Vector2i(9, 10), 0, w.starter, true)
	src.config.pass_through = true
	src.store(Portion.new(_ore(w), 5.0))
	var dst := w.place("container", Vector2i(11, 10), 0, w.starter, true)
	H.run(w, 40.0)
	assert_gt(_powder(dst), 4.0, "руда прошла через блок в блоке")
	assert_eq(w.all_machines().filter(func(m): return m.kind == "crusher").size(), 1, "вложенная дробилка видна целям")

func test_template_with_nested_block_costs_all_primitives():
	var w := H.world()
	var outer := _outer_block(w)
	var mb = JSON.parse_string(JSON.stringify(Macroblocks.capture(w, Rect2i(10, 10, 1, 1), "цех")))
	assert_eq(mb.parts.size(), 1)
	assert_true(mb.parts[0].has("mb"), "часть-блок хранит свою схему")
	assert_eq(MacroMachine.flat_kinds(mb).size(), 3)
	assert_eq(MacroMachine.collapse_error(mb), "")
	assert_almost_eq(Macroblocks.cost(w, mb), 2 * w.build_cost("container") + w.build_cost("crusher"), 0.01)
	w.remove_at(outer.cell, false)
	w.robot.add_item(Portion.new(w.starter, 200.0))
	var before := w.robot.mass_of(w.starter.id)
	assert_eq(Macroblocks.place_collapsed(w, mb, Vector2i(20, 20), 0, w.starter), "")
	assert_almost_eq(w.robot.mass_of(w.starter.id), before - Macroblocks.cost(w, mb), 0.01)
	var m: MacroMachine = w.machine_at(Vector2i(20, 20))
	assert_eq(m.all_inner().size(), 3)

func test_template_keeps_changed_inner_settings():
	var w := H.world()
	var outer := _outer_block(w)
	var nested: MacroMachine = outer.inner.machines_of("macro")[0]
	nested.inner.machines_of("container")[0].config.pass_through = false
	var t := outer.template()
	var np: Dictionary = t.parts.filter(func(p): return p.kind == "macro")[0]
	var box_part: Dictionary = np.mb.parts.filter(func(p): return p.kind == "container")[0]
	assert_false(box_part.config.pass_through, "в шаблон попала настройка, изменённая внутри")

func test_nested_ports_rotate_with_block():
	var w := H.world()
	_inner_block(w)
	var mb := Macroblocks.capture(w, Rect2i(10, 10, 1, 1), "одна дробильня")
	var types: Array = mb.ports.map(func(q): return "%s%d" % [q.type, q.dir])
	assert_true("in2" in types and "out0" in types, "порты вложенного блока выведены наружу")
	var nested: MacroMachine = w.machine_at(Vector2i(10, 10))
	nested.rot = 1
	nested.facing = 1
	var mb2 := Macroblocks.capture(w, Rect2i(10, 10, 1, 1), "повёрнутая")
	var types2: Array = mb2.ports.map(func(q): return "%s%d" % [q.type, q.dir])
	assert_true("in3" in types2 and "out1" in types2, "повёрнутый блок — порты повёрнуты")

func test_expanded_place_puts_nested_block_collapsed():
	var w := H.world()
	_inner_block(w)
	var out := w.place("container", Vector2i(11, 10), 0, w.starter, true)
	out.config.pass_through = true
	var mb = JSON.parse_string(JSON.stringify(Macroblocks.capture(w, Rect2i(10, 10, 2, 1), "цех")))
	w.robot.add_item(Portion.new(w.starter, 200.0))
	assert_eq(Macroblocks.place(w, mb, Vector2i(20, 20), 0, w.starter), "")
	var m = w.machine_at(Vector2i(20, 20))
	assert_true(m is MacroMachine, "вложенный блок встал свёрнутым")
	assert_eq(m.all_inner().size(), 2)
	var src := w.place("container", Vector2i(19, 20), 0, w.starter, true)
	src.config.pass_through = true
	src.store(Portion.new(_ore(w), 4.0))
	var dst := w.place("container", Vector2i(22, 20), 0, w.starter, true)
	H.run(w, 40.0)
	assert_gt(_powder(dst), 3.0)

func test_save_load_nested():
	var w := H.world()
	var outer := _outer_block(w)
	var nested: MacroMachine = outer.inner.machines_of("macro")[0]
	nested.inner.machines_of("container")[0].store(Portion.new(w.starter, 3.0))
	var md = JSON.parse_string(JSON.stringify(SaveGame.machine_to(outer, w.gas)))
	var w2 := H.world()
	var m2 = w2.place("macro", Vector2i(10, 10), 0, w2.starter, true)
	SaveGame.machine_restore(w2, m2, md, w2.gas)
	assert_eq(m2.inner.machines_of("macro").size(), 1)
	assert_eq(m2.all_inner().size(), 3)
	assert_almost_eq(m2.total_mass(), 3.0, 0.01)
	assert_eq(m2.inner.machines_of("macro")[0].inner.depth(), 2)

func test_unfold_rotates_nested_block():
	var w := H.world()
	var outer := _outer_block(w)
	var mb := outer.template()
	w.remove_at(outer.cell, false)
	w.robot.add_item(Portion.new(w.starter, 200.0))
	assert_eq(Macroblocks.place_collapsed(w, mb, Vector2i(20, 20), 1, w.starter), "")
	var m: MacroMachine = w.machine_at(Vector2i(20, 20))
	assert_eq(Macroblocks.unfold(w, m), "")
	var nested = w.machine_at(Vector2i(20, 20))
	assert_true(nested is MacroMachine, "после разворота вложенный блок на карте")
	assert_eq(nested.rot, 1, "и повёрнут вместе с внешним")
	assert_eq(w.machine_at(Vector2i(20, 21)).kind, "container")

func test_depth_limit():
	var mb := {"name": "a", "size": [1, 1], "parts": [{"kind": "crusher", "off": [0, 0], "facing": 0, "config": {}}], "wires": []}
	for i in MacroMachine.MAX_DEPTH - 1:
		mb = {"name": "n", "size": [1, 1], "parts": [{"kind": "macro", "off": [0, 0], "facing": 0, "config": {}, "mb": mb}], "wires": []}
	assert_eq(MacroMachine.collapse_error(mb), "", "предельная глубина — можно")
	mb = {"name": "n", "size": [1, 1], "parts": [{"kind": "macro", "off": [0, 0], "facing": 0, "config": {}, "mb": mb}], "wires": []}
	assert_ne(MacroMachine.collapse_error(mb), "", "глубже — нельзя")

func test_remove_refunds_all_levels():
	var w := H.world()
	var outer := _outer_block(w)
	var before := w.robot.mass_of(w.starter.id)
	w.remove_at(outer.cell)
	var full := 2 * w.build_cost("container") + w.build_cost("crusher")
	assert_almost_eq(w.robot.mass_of(w.starter.id) - before, full * 0.5, 0.01)

func test_gas_through_nested_block_conserves():
	var w := H.world()
	var t := w.place("tank", Vector2i(10, 10), 0, w.starter, true)
	w.gas.add_gas(t.id, 10.0)
	Macroblocks.collapse_region(w, Rect2i(10, 10, 1, 1), "бак")
	w.place("pipe", Vector2i(11, 10), 0, w.starter, true)
	var res := Macroblocks.collapse_region(w, Rect2i(10, 10, 2, 1), "бак с трубой")
	assert_eq(res.err, "")
	var b: MacroMachine = res.macro
	assert_true(b.has_gas())
	var pipe := w.place("pipe", Vector2i(10, 11), 0, w.starter, true)
	var inner_a: MacroMachine = b.inner.machines_of("macro")[0]
	var total: float = w.gas.total_gas() + b.inner.gas.total_gas() + inner_a.inner.gas.total_gas()
	for i in 200:
		w.tick(0.1)
	assert_almost_eq(w.gas.total_gas() + b.inner.gas.total_gas() + inner_a.inner.gas.total_gas(), total, 0.02)
	assert_gt(w.gas.pressure(pipe.id), 1.1, "газ из бака в блоке в блоке вышел наружу")
