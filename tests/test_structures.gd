extends GutTest

var H := TestHelpers

func _tube_line(w: World, y: int, length: int) -> Array:
	var inlet := w.place("tube_inlet", Vector2i(2, y), 0, w.starter, true)
	for x in range(3, 3 + length):
		w.place("tube", Vector2i(x, y), 0, w.starter, true)
	var outlet := w.place("tube_outlet", Vector2i(3 + length, y), 0, w.starter, true)
	var box := w.place("container", Vector2i(4 + length, y), 0, w.starter, true)
	return [inlet, outlet, box]

func test_tube_needs_assembly_and_pressure():
	var w := H.world()
	var inlet := w.place("tube_inlet", Vector2i(2, 2), 0, w.starter, true)
	inlet.store(Portion.new(w.starter, 3.0))
	H.run(w, 2.0)
	assert_string_contains(inlet.status, "не собрано")
	for x in range(3, 8):
		w.place("tube", Vector2i(x, 2), 0, w.starter, true)
	w.place("tube_outlet", Vector2i(8, 2), 0, w.starter, true)
	H.run(w, 2.0)
	assert_string_contains(inlet.status, "давления")

func test_tube_delivers_capsules():
	var w := H.world()
	var parts := _tube_line(w, 3, 8)
	var inlet: Machine = parts[0]
	var box: Machine = parts[2]
	w.place("pump", Vector2i(2, 4), 0, w.starter, true)
	inlet.store(Portion.new(w.starter, 6.0))
	H.run(w, 40.0)
	assert_almost_eq(box.total_mass(), 6.0, 0.1)

func test_capsules_are_visible_in_transit():
	var w := H.world()
	var parts := _tube_line(w, 3, 12)
	w.gas.add_gas(parts[0].id, 6.0)
	parts[0].store(Portion.new(w.starter, 3.0))
	H.run(w, 0.8)
	assert_gt(w.tube_capsules.size(), 0)

func test_broken_tube_drops_capsule():
	var w := H.world()
	var parts := _tube_line(w, 3, 14)
	w.gas.add_gas(parts[0].id, 6.0)
	parts[0].store(Portion.new(w.starter, 3.0))
	H.run(w, 1.3)
	w.remove_at(Vector2i(14, 3), false)
	H.run(w, 5.0)
	var dropped := 0.0
	for c in w.ground:
		for p in w.ground[c]:
			dropped += p.mass
	assert_gt(dropped, 0.5)

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
	assert_true(d.accept(Portion.new(w.starter, 100.0), Vector2i(6, 7)), "любая секция принимает в общий склад")
	assert_almost_eq(a.total_mass(), 100.0, 0.01)
	w.remove_at(d.cell)
	H.run(w, 1.5)
	assert_eq(a.master_id, -1, "склад разобран")
