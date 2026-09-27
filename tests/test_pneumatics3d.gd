extends GutTest
## Пневмозавод 3D-прототипа: газ, капсулы, обработка, разрывы.

var planet: Planet
var steel: Substance
var crystal: Substance

func before_each():
	planet = TestHelpers.planet()
	steel = TestHelpers.sub(planet, ["metallic", "dense"], "Сталь")
	crystal = TestHelpers.sub(planet, ["crystalline", "luminous"], "Кварц")

func _run(n: ProtoPneumatics, secs: float) -> void:
	var t := 0.0
	while t < secs:
		n.step(0.05)
		t += 0.05

func test_demo_line_crushes_and_fills_tank():
	var n := ProtoPneumatics.new(planet)
	n.build_demo(Vector2i.ZERO, steel)
	n.feed(Vector2i.ZERO, Portion.new(crystal, 6.0))
	_run(n, 60.0)
	var tank := Vector2i(6, 0)
	assert_almost_eq(n.mass_in(tank), 6.0, 0.05, "весь груз дошёл до бака")
	var got: Portion = n.parts[tank].items[0]
	assert_true(got.has("porous"), "дробилка сделала порошок")
	assert_false(got.has("crystalline"), "кристалличность ушла при дроблении")
	assert_true(n.events.any(func(e): return e.kind == "done" and e.cell == Vector2i(3, 0)))

func test_no_pump_no_movement():
	var n := ProtoPneumatics.new(planet)
	n.build_demo(Vector2i.ZERO, steel)
	n.remove(Vector2i(1, 1))   # насос
	n.feed(Vector2i.ZERO, Portion.new(crystal, 4.0))
	_run(n, 20.0)
	assert_eq(n.mass_in(Vector2i(6, 0)), 0.0, "без давления капсулы стоят")
	assert_eq(n.parts[Vector2i.ZERO].cap.t, 0.5, "капсула так и ждёт в приёмнике")

func test_pump_stops_below_own_limit():
	var n := ProtoPneumatics.new(planet)
	var pump := n.place("pump", Vector2i.ZERO, 0, steel)
	n.place("pipe", Vector2i(1, 0), 0, steel)
	_run(n, 30.0)
	assert_true(n.parts.has(Vector2i.ZERO), "насос цел")
	assert_almost_eq(n.pressure(Vector2i.ZERO), pump.stats.max_p * ProtoPneumatics.PUMP_SAFE, 0.2)

func test_weak_pipe_bursts():
	var weak := TestHelpers.sub(planet, ["brittle", "porous"], "Хрупкое")
	var n := ProtoPneumatics.new(planet)
	n.place("pump", Vector2i.ZERO, 0, steel)
	n.place("pipe", Vector2i(1, 0), 0, weak)
	assert_lt(n.max_p(Vector2i(1, 0)), n.max_p(Vector2i.ZERO) * ProtoPneumatics.PUMP_SAFE, "условие теста")
	_run(n, 30.0)
	assert_false(n.parts.has(Vector2i(1, 0)), "труба из хрупкого лопнула")
	assert_true(n.events.any(func(e): return e.kind == "burst"))

func test_thin_atmosphere_pumps_slower():
	var thin := TestHelpers.planet(["thin_atmosphere"])
	thin.atm_pressure = 0.3
	var s2 := TestHelpers.sub(thin, ["metallic", "dense"], "Сталь")
	var a := ProtoPneumatics.new(planet)
	var b := ProtoPneumatics.new(thin)
	for n in [a, b]:
		n.place("pump", Vector2i.ZERO, 0, steel if n == a else s2)
		n.place("pipe", Vector2i(1, 0), 0, steel if n == a else s2)
	_run(a, 1.0)
	_run(b, 1.0)
	var ra := a.pressure(Vector2i.ZERO) - planet.atm_pressure
	var rb := b.pressure(Vector2i.ZERO) - thin.atm_pressure
	assert_lt(rb, ra, "в разреженной атмосфере давление растёт медленнее")

func test_machine_accepts_only_from_back():
	var n := ProtoPneumatics.new(planet)
	n.place("pump", Vector2i(0, 1), 0, steel)
	n.place("pipe", Vector2i(0, 0), 0, steel)          # труба смотрит в бок дробилки
	n.place("crusher", Vector2i(1, 0), 1, steel)       # дробилка повёрнута на +Z
	n.parts[Vector2i(0, 0)].cap = {"p": Portion.new(crystal, 2.0), "cell": Vector2i(0, 0), "from": Vector2i(-1, 0), "t": 0.0}
	_run(n, 10.0)
	assert_eq(n.parts[Vector2i(1, 0)].items.size(), 0, "сбоку в машину не входит")
	assert_not_null(n.parts[Vector2i(0, 0)].cap, "капсула ждёт у входа")

func test_open_pipe_end_drops_capsule():
	var n := ProtoPneumatics.new(planet)
	n.place("pump", Vector2i(0, 1), 0, steel)
	n.place("intake", Vector2i(0, 0), 0, steel)
	n.place("pipe", Vector2i(1, 0), 0, steel)
	n.feed(Vector2i(0, 0), Portion.new(crystal, 2.0))
	_run(n, 10.0)
	assert_true(n.events.any(func(e): return e.kind == "lost"), "из открытой трубы груз выпадает")

func test_remove_returns_cargo():
	var n := ProtoPneumatics.new(planet)
	n.place("intake", Vector2i.ZERO, 0, steel)
	n.feed(Vector2i.ZERO, Portion.new(crystal, 3.0))
	var back := n.remove(Vector2i.ZERO)
	assert_eq(back.size(), 1)
	assert_false(n.parts.has(Vector2i.ZERO))

func test_builder_places_in_front_and_unloads_cargo():
	var n := ProtoPneumatics.new(planet)
	var view := ProtoPneumaticsView.new()
	add_child_autofree(view)
	view.setup(n, Vector3.ZERO)
	var robot := Node3D.new()
	add_child_autofree(robot)
	robot.position = Vector3(0, 0, 0)     # смотрит по +Z
	var b := ProtoBuilder.new()
	add_child_autofree(b)
	b.setup(view, robot, [steel])
	b.kind_i = ProtoPneumatics.ORDER.find("intake")
	assert_true(b.place())
	assert_eq(n.parts[Vector2i(0, 1)].kind, "intake", "деталь — в клетке перед роботом")
	assert_eq(n.parts[Vector2i(0, 1)].dir, 1, "выходом туда, куда смотрит робот")
	assert_false(b.place(), "занятая клетка")
	b.cargo().append(Portion.new(crystal, 5.0))
	assert_true(b.unload())
	assert_almost_eq(n.mass_in(Vector2i(0, 1)), 5.0, 0.01)
	assert_true(b.cargo().is_empty())
