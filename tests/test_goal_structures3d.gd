extends GutTest
## Сооружения целей планеты в 3D (ProtoPneumatics): пусковая шахта, маяк, купол —
## и этапы рана, которые на них опираются (ProtoRun: p_launch, p_beacon, p_dome).

var planet: Planet
var steel: Substance
var crystal: Substance
var felt: Substance
var net: ProtoPneumatics

func before_each():
	planet = PlanetGen.generate(14)
	steel = TestHelpers.sub(planet, ["metallic", "dense"], "Сталь")
	crystal = TestHelpers.sub(planet, ["crystalline", "luminous"], "Кварц")
	felt = TestHelpers.sub(planet, ["fibrous"], "Войлок")
	net = ProtoPneumatics.new(planet)

func _step(secs: float) -> void:
	var t := 0.0
	while t < secs:
		net.step(0.1)
		t += 0.1

func _pressurize(c: Vector2i, p: float) -> void:
	var id: int = net.parts[c].id
	net.gas.add_gas(id, net.gas.gas_for_pressure(id, p))

func test_goal_structures_are_in_build_menu():
	for k in ["launch_silo", "beacon", "dome"]:
		assert_has(ProtoPneumatics.ORDER, k)
		assert_true(ProtoPneumatics.KINDS.has(k))

func test_silo_waits_for_cargo_and_pressure_then_launches():
	var silo := net.place("launch_silo", Vector2i.ZERO, 0, steel)
	silo.items.append(Portion.new(crystal, 2.0))
	_pressurize(Vector2i.ZERO, net.launch_p + 0.5)
	net.step(0.1)
	assert_eq(net.launched_kg, 0.0, "мало груза — не стартует")
	silo.items.append(Portion.new(crystal, 2.0))
	net.gas.take_gas(silo.id, net.gas.amount(silo.id))
	net.step(0.1)
	assert_eq(net.launched_kg, 0.0, "нет давления — не стартует")
	_pressurize(Vector2i.ZERO, net.launch_p + 0.5)
	net.step(0.1)
	assert_almost_eq(net.launched_kg, 4.0, 0.01)
	assert_true(net.mass_in(Vector2i.ZERO) < 0.01, "шахта опустела")
	assert_true(net.events.any(func(e): return e.kind == "launch"))

func test_silo_takes_capsules_from_any_side():
	net.place("pipe", Vector2i(0, 1), 3, steel)          # труба смотрит в шахту сбоку
	net.place("launch_silo", Vector2i(0, 0), 0, steel)
	net.parts[Vector2i(0, 1)].cap = {"p": Portion.new(crystal, 2.0), "cell": Vector2i(0, 1), "from": Vector2i(0, 2), "t": 0.9}
	_pressurize(Vector2i(0, 1), 2.5)
	_step(0.5)
	assert_almost_eq(net.mass_in(Vector2i.ZERO), 2.0, 0.01)

func test_beacon_needs_material_and_pressure():
	var good := net.place("beacon", Vector2i(0, 0), 0, crystal)
	var bad := net.place("beacon", Vector2i(5, 0), 0, felt)
	net.step(0.1)
	assert_false(good.work, "без давления не светит")
	_pressurize(Vector2i(0, 0), ProtoPneumatics.BEACON_P + 0.5)
	_pressurize(Vector2i(5, 0), ProtoPneumatics.BEACON_P + 0.5)
	net.step(0.1)
	assert_true(good.work, "кристаллический маяк под давлением светит")
	assert_false(bad.work, "войлочный маяк не светит")

func test_dome_is_heated_by_furnace_next_to_it():
	net.gas.ambient = -90.0
	var cold := net.place("dome", Vector2i(0, 0), 0, steel)
	var warm := net.place("dome", Vector2i(10, 0), 0, steel)
	net.place("furnace", Vector2i(11, 0), 0, steel)
	net.place("furnace", Vector2i(10, 1), 0, steel)
	net.place("furnace", Vector2i(10, -1), 0, steel)
	net.place("furnace", Vector2i(11, 1), 0, steel)     # по диагонали тоже греет
	_step(120.0)
	assert_lt(float(cold.temp), -60.0, "без печи купол стынет до среды")
	assert_between(float(warm.temp), 5.0, 35.0, "четыре печи рядом греют купол")

func test_goal_stages_map_to_structures():
	var colony := ProtoRun.adapt_goal(Goals.TEMPLATES.colony)
	var types: Array = []
	for st in colony.stages:
		for a in (st.alt if st.has("alt") else [st]):
			types.append(a.type)
	assert_has(types, "p_dome", "колония — купол")
	assert_has(types, "p_launch", "колония — запуск на орбиту")
	var beacon := ProtoRun.adapt_goal(Goals.TEMPLATES.beacon)
	types = []
	for st in beacon.stages:
		for a in (st.alt if st.has("alt") else [st]):
			types.append(a.type)
	assert_has(types, "p_beacon")

func test_run_counts_launched_mass_and_saves_it():
	var run := ProtoRun.new(planet, [steel])
	run.attach(net, null, autofree(Node3D.new()), crystal, Vector3.ZERO)
	run.ev_next = 1e9
	net.launched_kg += 5.0
	run.tick(0.1)
	assert_almost_eq(float(run.launched.mass), 5.0, 0.01)
	var d := run.to_dict()
	var run2 := ProtoRun.new(planet, [steel])
	run2.attach(net, null, autofree(Node3D.new()), crystal, Vector3.ZERO)
	run2.from_dict(d)
	assert_almost_eq(float(run2.launched.mass), 5.0, 0.01)

func test_dome_stage_holds_only_when_dome_is_livable():
	var run := ProtoRun.new(planet, [steel])
	run.attach(net, null, autofree(Node3D.new()), crystal, Vector3.ZERO)
	var st := ProtoRun.make_stage("p_dome", 0, 4.0)
	assert_false(run.dome_ok(st), "купола нет")
	var dome := net.place("dome", Vector2i.ZERO, 0, steel)
	dome.temp = 20.0
	net.gas.take_gas(dome.id, net.gas.amount(dome.id))
	assert_false(run.dome_ok(st), "нет воздуха")
	_pressurize(Vector2i.ZERO, 1.2)
	assert_true(run.dome_ok(st))
	dome.temp = -40.0
	assert_false(run.dome_ok(st), "холодно")
	run.planet.goal = {"n": "Тест", "desc": "", "stages": [st, st, st]}
	run.goals.stage = 0
	assert_string_contains(run.advise(func(_a): return "?"), "печь")
