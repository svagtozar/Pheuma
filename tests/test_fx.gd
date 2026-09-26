extends GutTest
## Видимые эффекты: ядро копит события в world.fx, game/fx.gd рисует.

var H := TestHelpers

func _kinds(w: World) -> Array:
	return w.fx.map(func(e): return e.kind)

func test_processing_emits_process_fx():
	var w := H.world()
	var f := w.place("crusher", Vector2i(10, 10), 0, w.starter, true)
	w.place("container", Vector2i(11, 10), 0, w.starter, true)
	f.store(Portion.new(w.db.add(Substance.new("br", "Хруп", ["brittle"])), 2.0))
	H.run(w, 5.0)
	assert_true("process_crusher" in _kinds(w))

func test_probe_emits_probe_and_reveal_fx():
	var w := H.world()
	w.robot.tank = w.robot.tank_cap()
	var s := w.db.add(Substance.new("mg", "Магн", ["magnetic", "dense"]))
	w.robot.add_item(Portion.new(s, 3.0))
	w.fx.clear()
	w.probe(s.id, "magnet")
	assert_true("probe_magnet" in _kinds(w))
	assert_true("reveal" in _kinds(w))
	var rv: Array = w.fx.filter(func(e): return e.kind == "reveal")
	assert_true(rv.any(func(e): return e.text.contains("магнитный")))

func test_evaporation_emits_vapor_at_container():
	var w := H.world()
	var box := w.place("container", Vector2i(12, 12), 0, w.starter, true)
	box.store(Portion.new(w.db.add(Substance.new("vl", "Лет", ["volatile", "organic"])), 5.0))
	H.run(w, 3.0)
	var v: Array = w.fx.filter(func(e): return e.kind == "vapor")
	assert_false(v.is_empty(), "пар над контейнером")
	assert_eq(v[0].cell, Vector2i(12, 12))

func test_macro_fx_use_block_cell():
	var w := H.world()
	var cr := w.place("crusher", Vector2i(10, 10), 0, w.starter, true)
	w.place("container", Vector2i(11, 10), 0, w.starter, true)
	var res := Macroblocks.collapse_region(w, Rect2i(10, 10, 2, 1), "дробь")
	var macro: MacroMachine = res.macro
	var inner_cr: Machine = macro.inner.machines_of("crusher")[0]
	inner_cr.store(Portion.new(w.db.add(Substance.new("br", "Хруп", ["brittle"])), 2.0))
	w.fx.clear()
	H.run(w, 5.0)
	var ev: Array = w.fx.filter(func(e): return e.kind == "process_crusher")
	assert_false(ev.is_empty())
	assert_eq(ev[0].cell, macro.cell, "эффект — на клетке блока")
	assert_eq(cr.kind, "crusher")

func test_fx_queue_bounded():
	var w := H.world()
	for i in 500:
		w.add_fx("ring", Vector2i(1, 1))
	assert_lte(w.fx.size(), 200)

func test_fx_layer_updates_and_caps():
	var l := FxLayer.new()
	for i in 1000:
		l.smoke(Vector2(10, 10))
	assert_lte(l.parts.size(), FxLayer.MAX)
	for i in 30:
		l.update(0.1)
	assert_eq(l.parts.size(), 0, "частицы гаснут")
	l.event({"kind": "reveal", "cell": Vector2i(2, 2), "col": Color.RED, "text": "«x»"})
	assert_true(l.parts.any(func(p): return p.kind == "text"))
