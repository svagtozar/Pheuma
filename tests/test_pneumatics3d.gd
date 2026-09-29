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

## Полный бак не глушит линию: с баком перед ним груз идёт дальше; без него — стоит.
func test_full_tank_passes_capsules_to_next_tank():
	var n := ProtoPneumatics.new(planet)
	n.build_demo(Vector2i.ZERO, steel)
	var tank := Vector2i(6, 0)
	n.parts[tank].items.append(Portion.new(crystal, ProtoPneumatics.KINDS.tank.cap - 0.5))
	n.feed(Vector2i.ZERO, Portion.new(crystal, 4.0))
	_run(n, 40.0)
	assert_eq(n.delivered, 0, "полный бак без продолжения груз не берёт")
	n.place("tank", tank + Vector2i(1, 0), 0, steel)
	_run(n, 40.0)
	assert_almost_eq(n.mass_in(tank + Vector2i(1, 0)), 4.0, 0.05, "груз прошёл сквозь полный бак во второй")
	assert_eq(n.delivered, 2, "капсулы засчитаны во втором баке")

## Запас насосов переживает событие «сдвиг температуры»: сеть не рвётся целиком.
func test_net_survives_temp_shift():
	var n := ProtoPneumatics.new(planet)
	n.build_demo(Vector2i.ZERO, steel)
	_run(n, 90.0)
	n.gas.ambient += 40.0
	_run(n, 60.0)
	assert_eq(n.burst_log.size(), 0, "ни одна деталь не лопнула")

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

func test_cannon_shoots_capsule_into_intake():
	var n := ProtoPneumatics.new(planet)
	n.place("pump", Vector2i(0, 1), 3, steel)
	var cannon := n.place("cannon", Vector2i(0, 0), 0, steel)
	n.place("intake", Vector2i(7, 0), 0, steel)
	assert_eq(n.cannon_target(Vector2i.ZERO), Vector2i(7, 0), "пушка видит приёмник впереди")
	cannon.items.append(Portion.new(crystal, 2.0))
	_run(n, 20.0)
	assert_true(n.events.any(func(e): return e.kind == "shot"), "выстрел был")
	assert_true(n.events.any(func(e): return e.kind == "caught"), "приёмник поймал капсулу")
	var got: float = n.mass_in(Vector2i(7, 0))
	if n.parts[Vector2i(7, 0)].cap != null:
		got += n.parts[Vector2i(7, 0)].cap.p.mass
	assert_almost_eq(got, 2.0, 0.05, "груз перелетел в приёмник")

func test_cannon_without_target_keeps_cargo():
	var n := ProtoPneumatics.new(planet)
	n.place("pump", Vector2i(0, 1), 3, steel)
	var cannon := n.place("cannon", Vector2i(0, 0), 0, steel)
	cannon.items.append(Portion.new(crystal, 2.0))
	_run(n, 10.0)
	assert_eq(cannon.items.size(), 1, "некуда стрелять — капсула ждёт")
	assert_true(n.flights.is_empty())

func test_every_processing_machine_of_2d_game_is_buildable_and_runs():
	var kinds := []
	for k in Buildings.KINDS:
		if Buildings.KINDS[k].has("process"):
			kinds.append(k)
	assert_eq(kinds.size(), 16, "в 2D шестнадцать машин обработки")
	for k in kinds:
		assert_true(k in ProtoPneumatics.ORDER, "%s есть в меню стройки 3D" % k)
		var n := ProtoPneumatics.new(planet)
		n.place("intake", Vector2i(0, 0), 0, steel)
		n.place("pump", Vector2i(0, 1), 3, steel)
		assert_false(n.place(k, Vector2i(1, 0), 0, steel).is_empty(), "%s ставится" % k)
		n.place("tank", Vector2i(2, 0), 0, steel)
		n.feed(Vector2i.ZERO, Portion.new(crystal, 2.0))
		_run(n, 40.0)
		assert_eq(n.mass_in(Vector2i.ZERO), 0.0, "%s забрал груз из приёмника" % k)
		assert_true(n.events.any(func(e): return e.kind == "done" and e.cell == Vector2i(1, 0)) or n.parts[Vector2i(1, 0)].busy != null,
			"%s взялся за обработку (%s)" % [k, n.parts[Vector2i(1, 0)].status])

func test_builder_ignores_buttons_under_card_or_map():
	var n := ProtoPneumatics.new(planet)
	var view := ProtoPneumaticsView.new()
	add_child_autofree(view)
	view.setup(n, Vector3.ZERO)
	var robot := Node3D.new()
	add_child_autofree(robot)
	var b := ProtoBuilder.new()
	add_child_autofree(b)
	b.setup(view, robot, [steel])
	robot.set_meta("ui_busy", true)            # открыта карточка материала или карта
	Input.action_press(ProtoBuilder.BUILD_MODE)
	assert_true(Input.is_action_just_pressed(ProtoBuilder.BUILD_MODE), "кнопка стройки нажата в этом кадре")
	b._process(0.016)
	Input.action_release(ProtoBuilder.BUILD_MODE)
	assert_false(b.active, "Y / B в карточке не включает стройку")

func test_in_game_only_nearest_machine_is_labeled():
	var n := ProtoPneumatics.new(planet)
	n.place("pump", Vector2i(0, 0), 0, steel)
	n.place("tank", Vector2i(2, 0), 0, steel)
	var view := ProtoPneumaticsView.new()
	add_child_autofree(view)
	view.setup(n, Vector3.ZERO)
	var shown := func(): return view._labels.values().filter(func(l): return l.visible).size()
	assert_eq(shown.call(), 2, "для кадров завода подписаны все машины")
	var robot := Node3D.new()
	add_child_autofree(robot)
	robot.position = ProtoPneumatics.cell_pos(Vector3.ZERO, Vector2i(2, 0)) + Vector3(0, 0, 1.5)
	view.focus = robot
	view.sync()
	assert_eq(shown.call(), 1, "в игре — одна, ближняя")
	assert_true(view._labels.values().filter(func(l): return l.visible)[0].text.begins_with(ProtoPneumatics.KINDS.tank.n))
	robot.position += Vector3(0, 0, 20)
	view.sync()
	assert_eq(shown.call(), 0, "далеко от завода подписей нет")

## За площадкой деталь стоит на своём грунте: at() учитывает подъём, лопнувшая
## деталь оставляет его в событии (клуб газа — там, где она стояла).
func test_part_lift_off_pad():
	var n := ProtoPneumatics.new(planet)
	var o := Vector3(10, 5, 10)
	var part := n.place("pipe", Vector2i(2, 1), 0, steel)
	assert_eq(n.at(o, Vector2i(2, 1)), ProtoPneumatics.cell_pos(o, Vector2i(2, 1)), "на площадке подъёма нет")
	part.lift = -1.5
	assert_almost_eq(n.at(o, Vector2i(2, 1)).y, 3.5, 0.001)
	n._burst(Vector2i(2, 1))
	assert_false(n.parts.has(Vector2i(2, 1)))
	var e: Dictionary = n.events.filter(func(x): return x.kind == "burst")[0]
	assert_almost_eq(float(e.lift), -1.5, 0.001)

## Приёмник → труба → X → … : линия с насосом, X ставит тест.
func _line_with(kind: String) -> ProtoPneumatics:
	var n := ProtoPneumatics.new(planet)
	n.place("intake", Vector2i(0, 0), 0, steel)
	n.place("pipe", Vector2i(1, 0), 0, steel)
	n.place("pump", Vector2i(1, 1), 3, steel)
	n.place(kind, Vector2i(2, 0), 0, steel)
	return n

## Разветвитель по очереди шлёт капсулы вперёд и в стороны, где стоят баки.
func test_splitter_shares_between_outputs():
	var n := _line_with("splitter")
	n.place("tank", Vector2i(3, 0), 0, steel)
	n.place("tank", Vector2i(2, 1), 1, steel)
	n.place("tank", Vector2i(2, -1), 3, steel)
	n.feed(Vector2i.ZERO, Portion.new(crystal, 12.0))
	_run(n, 60.0)
	for c in [Vector2i(3, 0), Vector2i(2, 1), Vector2i(2, -1)]:
		assert_gt(n.mass_in(c), 1.5, "бак %s получил свою долю" % str(c))
	assert_almost_eq(n.mass_in(Vector2i(3, 0)) + n.mass_in(Vector2i(2, 1)) + n.mass_in(Vector2i(2, -1)), 12.0, 0.05)

## Сортировщик: первое вещество — прямо, остальное — вбок.
func test_sorter_sends_other_substances_aside():
	var n := _line_with("sorter")
	n.place("tank", Vector2i(3, 0), 0, steel)
	n.place("tank", Vector2i(2, 1), 1, steel)
	n.feed(Vector2i.ZERO, Portion.new(crystal, 4.0))
	n.feed(Vector2i.ZERO, Portion.new(steel, 4.0))
	_run(n, 60.0)
	assert_eq(n.parts[Vector2i(2, 0)].filter, crystal)
	assert_almost_eq(n.mass_in(Vector2i(3, 0)), 4.0, 0.05, "кварц прямо")
	assert_almost_eq(n.mass_in(Vector2i(2, 1)), 4.0, 0.05, "сталь вбок")
	assert_eq(n.parts[Vector2i(3, 0)].items[0].substance, crystal)

## Клапан из слабого материала не даёт прочному насосу разорвать слабые трубы.
func test_relief_valve_saves_weak_pipes():
	var weak := TestHelpers.sub(planet, ["brittle"], "Стекло")
	var strong := TestHelpers.sub(planet, ["metallic", "dense", "elastic"], "Упругая сталь")
	assert_lt(ComponentStats.compute("pipe", weak).max_p, ComponentStats.compute("pump", strong).max_p * ProtoPneumatics.PUMP_SAFE)
	for with_relief in [false, true]:
		var n := ProtoPneumatics.new(planet)
		n.place("pump", Vector2i(0, 0), 0, strong)
		# Клапан — сразу за насосом (без него там просто труба).
		n.place("relief" if with_relief else "pipe", Vector2i(1, 0), 0, weak)
		n.place("pipe", Vector2i(2, 0), 0, weak)
		n.place("pipe", Vector2i(3, 0), 0, weak)
		_run(n, 30.0)
		var whole: bool = n.parts.size() == 4
		assert_eq(whole, with_relief, "с клапаном линия цела, без него лопается")

## Буфер копит капсулы, пока выход занят, и отдаёт их потом.
func test_buffer_holds_and_releases():
	var n := _line_with("buffer")
	n.feed(Vector2i.ZERO, Portion.new(crystal, 8.0))
	_run(n, 30.0)
	assert_eq(n.parts[Vector2i(2, 0)].items.size() + (1 if n.parts[Vector2i(2, 0)].cap != null else 0), 4, "без выхода — всё в буфере")
	n.place("tank", Vector2i(3, 0), 0, steel)
	_run(n, 30.0)
	assert_almost_eq(n.mass_in(Vector2i(3, 0)), 8.0, 0.05, "буфер отдал всё в бак")

## Фонарь к газу сети не подключён и капсул не берёт.
func test_lamp_is_off_the_gas_net():
	var n := ProtoPneumatics.new(planet)
	n.place("pump", Vector2i(0, 0), 0, steel)
	n.place("lamp", Vector2i(1, 0), 0, steel)
	_run(n, 10.0)
	assert_almost_eq(n.pressure(Vector2i(1, 0)), planet.atm_pressure, 0.01)
