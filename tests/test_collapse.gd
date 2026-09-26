extends GutTest
## Свёрнутые макроблоки.

var H := TestHelpers

## Схема: вход (контейнер со сквозной выдачей) → дробилка → выход наружу.
func _chain_mb(w: World) -> Dictionary:
	var box := w.place("container", Vector2i(2, 2), 0, w.starter, true)
	box.config.pass_through = true
	w.place("crusher", Vector2i(3, 2), 0, w.starter, true)
	var mb = JSON.parse_string(JSON.stringify(Macroblocks.capture(w, Rect2i(2, 2, 2, 1), "дробильня")))
	w.remove_at(Vector2i(2, 2), false)
	w.remove_at(Vector2i(3, 2), false)
	return mb

func test_collapsed_macro_processes_between_neighbors():
	var w := H.world()
	w.robot.add_item(Portion.new(w.starter, 200.0))
	var mb := _chain_mb(w)
	var ore := w.db.add(Substance.new("ore", "Руда", ["brittle", "crystalline"]))
	var src := w.place("container", Vector2i(9, 10), 0, w.starter, true)
	src.config.pass_through = true
	src.store(Portion.new(ore, 6.0))
	assert_eq(Macroblocks.place_collapsed(w, mb, Vector2i(10, 10), 0, w.starter), "")
	var dst := w.place("container", Vector2i(11, 10), 0, w.starter, true)
	var macro = w.machine_at(Vector2i(10, 10))
	assert_true(macro is MacroMachine)
	assert_eq(macro.inner.machines.size(), 2)
	H.run(w, 30.0)
	var powder := 0.0
	for p in dst.items:
		if p.has("porous"):
			powder += p.mass
	assert_gt(powder, 5.0, "руда прошла через свёрнутую дробильню")

func test_collapsed_macro_rotated():
	var w := H.world()
	w.robot.add_item(Portion.new(w.starter, 200.0))
	var mb := _chain_mb(w)
	var ore := w.db.add(Substance.new("ore", "Руда", ["brittle", "crystalline"]))
	var src := w.place("container", Vector2i(10, 9), 1, w.starter, true)
	src.config.pass_through = true
	src.store(Portion.new(ore, 4.0))
	assert_eq(Macroblocks.place_collapsed(w, mb, Vector2i(10, 10), 1, w.starter), "")
	var dst := w.place("container", Vector2i(10, 11), 1, w.starter, true)
	H.run(w, 30.0)
	assert_gt(dst.total_mass(), 3.0)

func test_collapse_costs_all_parts_and_counts_one_machine():
	var w := H.world()
	var mb := _chain_mb(w)
	var before := w.robot.mass_of(w.starter.id)
	var n := w.machines.size()
	assert_eq(Macroblocks.place_collapsed(w, mb, Vector2i(10, 10), 0, w.starter), "")
	assert_almost_eq(w.robot.mass_of(w.starter.id), before - 12.0, 0.01)
	assert_eq(w.machines.size(), n + 1)

func test_drills_cannot_be_collapsed():
	var w := H.world()
	w.planet.deposits[Vector2i(2, 2)] = {"sub": w.starter.id, "amount": 10.0}
	w.place("drill", Vector2i(2, 2), 0, w.starter, true)
	var mb := Macroblocks.capture(w, Rect2i(2, 2, 1, 1), "бур")
	assert_ne(Macroblocks.can_place_collapsed(w, mb, Vector2i(10, 10), w.starter), "")

func test_collapsed_macro_with_internal_cannon_and_logic():
	var w := H.world()
	w.robot.add_item(Portion.new(w.starter, 300.0))
	var inlet := w.place("container", Vector2i(2, 2), 0, w.starter, true)
	inlet.config.pass_through = true
	var c := w.place("cannon", Vector2i(3, 2), 0, w.starter, true)
	w.place("pump", Vector2i(3, 3), 0, w.starter, true)
	var r := w.place("receiver", Vector2i(6, 2), 0, w.starter, true)
	w.link_cannon(c.cell, r.cell)
	var mb = JSON.parse_string(JSON.stringify(Macroblocks.capture(w, Rect2i(2, 2, 5, 2), "пушечный узел")))
	for cell in [Vector2i(2, 2), Vector2i(3, 2), Vector2i(3, 3), Vector2i(6, 2)]:
		w.remove_at(cell, false)
	var src := w.place("container", Vector2i(19, 20), 0, w.starter, true)
	src.config.pass_through = true
	src.store(Portion.new(w.starter, 6.0))
	assert_eq(Macroblocks.place_collapsed(w, mb, Vector2i(20, 20), 0, w.starter), "")
	var dst := w.place("container", Vector2i(21, 20), 0, w.starter, true)
	H.run(w, 60.0)
	assert_gt(dst.total_mass(), 4.0, "груз прошёл через пушку внутри блока")

func test_save_load_collapsed_macro():
	var w := H.world()
	w.robot.add_item(Portion.new(w.starter, 200.0))
	var mb := _chain_mb(w)
	Macroblocks.place_collapsed(w, mb, Vector2i(10, 10), 2, w.starter)
	var m = w.machine_at(Vector2i(10, 10))
	m.inner.machines.values()[0].store(Portion.new(w.starter, 3.0))
	var d = JSON.parse_string(JSON.stringify(SaveGame.to_dict(w)))
	# Тестовый мир не из seed — проверяем только сериализацию машины.
	var md: Dictionary = d.machines.filter(func(x): return x.kind == "macro")[0]
	assert_eq(md.extra.parts.size(), 2)
	var w2 := H.world()
	var m2 = w2.place("macro", Vector2i(10, 10), 2, w2.starter, true)
	SaveGame.machine_restore(w2, m2, md, w2.gas)
	assert_eq(m2.inner.machines.size(), 2)
	assert_almost_eq(m2.total_mass(), 3.0, 0.01)
	assert_eq(m2.rot, 2)

func test_removing_macro_refunds_and_drops_contents():
	var w := H.world()
	var mb := _chain_mb(w)
	Macroblocks.place_collapsed(w, mb, Vector2i(10, 10), 0, w.starter)
	var m = w.machine_at(Vector2i(10, 10))
	m.inner.machines.values()[0].store(Portion.new(w.starter, 3.0))
	var before := w.robot.mass_of(w.starter.id)
	w.remove_at(Vector2i(10, 10))
	assert_almost_eq(w.robot.mass_of(w.starter.id), before + 6.0, 0.01)
	assert_true(w.ground.has(Vector2i(10, 10)))
