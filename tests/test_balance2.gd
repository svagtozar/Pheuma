extends GutTest
## Баланс, третий проход: ловушки, на которых застревали и бот, и игрок.

var H := TestHelpers

func _set_p(w: World, m: Machine, p: float) -> void:
	w.gas.nodes[m.id].n = p * w.gas.nodes[m.id].v / w.gas.temp_factor()

func _run_proc(w: World, m: Machine, p: float, sec: float) -> void:
	for i in int(sec / 0.1):
		_set_p(w, m, p)
		m.tick(w, 0.1)

func test_compressor_waits_for_pressure_instead_of_passing_raw():
	var w := H.world()
	var d := w.db.add(Substance.new("d", "Д", ["dense"]))
	var comp: Processor = w.place("compressor", Vector2i(10, 10), 0, w.starter, true)
	comp.store(Portion.new(d, 2.0))
	_run_proc(w, comp, 4.0, 5.0)
	assert_true(comp.out_queue.is_empty(), "при 4 атм сырьё не проходит насквозь")
	assert_true(comp.status.contains("6.0"), "статус подсказывает нужное давление: " + comp.status)
	assert_almost_eq(comp.need_p, 6.0, 0.01)
	_run_proc(w, comp, 7.0, 1.0)
	assert_eq(comp.out_queue.size(), 1)
	assert_true(comp.out_queue[0][0].has("crystalline"), "при 7 атм — кристаллический")

func test_compressor_passes_material_no_pressure_can_change():
	var w := H.world()
	var s := w.db.add(Substance.new("s", "С", ["sticky"]))
	var comp: Processor = w.place("compressor", Vector2i(10, 10), 0, w.starter, true)
	comp.store(Portion.new(s, 2.0))
	_run_proc(w, comp, 4.0, 4.0)
	assert_eq(comp.out_queue.size(), 1, "то, что давлением не изменить, проходит как раньше")

func test_silo_sends_materials_in_turn():
	var w := H.world()
	var a := w.db.add(Substance.new("a", "А", ["dense"]))
	var b := w.db.add(Substance.new("b", "Б", ["porous"]))
	var silo: Cannon = w.place("launch_silo", Vector2i(10, 10), 0, w.starter, true)
	silo.store(Portion.new(a, 30.0))
	silo.store(Portion.new(b, 4.0))
	silo.fire(w, 7.0)
	silo.store(Portion.new(a, 10.0))   # бур подкладывает своё
	silo.fire(w, 7.0)
	assert_eq(w.launched.subs.size(), 2, "второй материал улетел, хотя бур кладёт первый")

func test_relief_valve_keeps_gas_machine_whole():
	var w := H.world()
	var comp: Processor = w.place("compressor", Vector2i(10, 10), 0, w.starter, true)
	var mp: float = comp.stats.max_p
	_set_p(w, comp, mp * 0.99)
	comp._relieve(w)
	assert_lte(w.gas.pressure(comp.id), mp * 0.9 + 0.01, "лишний газ стравлен")
	assert_gt(w.gas.vented_total, 0.0)

func test_planner_needs_buildable_machine():
	var w := H.world()
	var soft := w.db.add(Substance.new("soft", "Мягкий", ["porous"]))
	soft.hardness = 1.0
	w.robot.inventory.clear()
	assert_false(Planner.buildable(w, "compressor", [soft]), "компрессор из мягкого не построить")
	w.robot.add_item(Portion.new(w.starter, 20.0))
	assert_true(Planner.buildable(w, "compressor", [soft]), "из стартового сплава в инвентаре — можно")

func test_burning_reagent_not_used_in_oxidizing_atmosphere():
	var w := H.world(["oxidizing_atmosphere"])
	var f := w.db.add(Substance.new("f", "Горючий", ["flammable", "acidic"]))
	f.hardness = 1.0
	var ok := w.db.add(Substance.new("k", "Спокойный", ["alkaline"]))
	ok.hardness = 1.0
	var r := Planner.reagents(w, [f, ok])
	assert_false(f in r, "горючее в окисляющей атмосфере в руках не донести")
	assert_true(ok in r)

func test_generator_gives_anchoring_walls_for_phasing_stockpile():
	var bad := 0
	for s in range(1, 41):
		var p := PlanetGen.generate(s)
		var pr := PlanetGen._probe(p)
		for t in PlanetGen._stockpile_tags(p.goal):
			var pl := Planner.probe_plan(pr, t, p.materials)
			if pl.is_empty() or not pl.final.substance.has("phasing"):
				continue
			var kind := "tank" if pl.final.substance.has("volatile") else "container"
			if not PlanetGen._buildable_from(p, kind, 0.0, "anchoring"):
				bad += 1
				gut.p("seed %d: «%s» фазирующий, якорных стенок нет" % [s, MaterialTags.display(t)])
	assert_eq(bad, 0, "фазирующий запас есть в чём хранить")
