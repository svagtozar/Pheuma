extends GutTest
## Ран 3D-прототипа (ProtoRun): цель из 2D, этапы, награды, прокачка, события, сохранение.

var planet: Planet
var steel: Substance
var crystal: Substance
var net: ProtoPneumatics
var drill: ProtoMining
var body: Node3D
var run: ProtoRun

func before_each():
	planet = PlanetGen.generate(14)
	steel = TestHelpers.sub(planet, ["metallic", "dense"], "Сталь")
	crystal = TestHelpers.sub(planet, ["crystalline", "luminous"], "Кварц")
	net = ProtoPneumatics.new(planet)
	net.build_demo(Vector2i.ZERO, steel)
	drill = autofree(ProtoMining.new())
	body = autofree(Node3D.new())
	run = ProtoRun.new(planet, [steel])
	run.attach(net, drill, body, crystal, Vector3.ZERO)
	run.ev_next = 1e9                      # события — только в своих тестах

func _tick(secs: float) -> void:
	var t := 0.0
	while t < secs:
		net.step(0.1)
		run.tick(0.1)
		t += 0.1

## Выполнить текущий этап, что бы он ни требовал.
func _complete_stage() -> void:
	var st := run.goals.current()
	var stage := run.goals.stage
	match st.type:
		"p_mine": drill.mined_total += float(st.kg) + 1.0
		"p_store":
			for c in net.parts:
				if net.parts[c].kind == "tank":
					net.parts[c].items.append(Portion.new(crystal, float(st.kg) + 1.0))
		"deliveries": net.delivered += int(st.n)
		"p_parts": net.placed += int(st.n)
		"p_process": net.processed += int(st.n)
		"p_launch": net.launched_kg += float(st.kg) + 1.0
		"p_pressure", "p_beacon", "p_dome": run.goals.hold = float(st.hold)
	_tick(1.2)
	if st.type in ["p_pressure", "p_beacon", "p_dome"] and run.goals.stage == stage:
		run.goals.progress = 1.0
		run.goals.advance()

func test_every_goal_template_adapts_to_3d_stages():
	var known := ProtoRun.STAGE_TYPES
	for id in Goals.TEMPLATES:
		var g := ProtoRun.adapt_goal(Goals.TEMPLATES[id])
		assert_eq(g.stages.size(), 3, id)
		for st in g.stages:
			if st.has("alt"):
				assert_ne(st.alt[0].type, st.alt[1].type, "%s: развилка из разных путей" % id)
				for a in st.alt:
					assert_has(known, a.type, id)
					assert_ne(str(a.get("pitch", "")), "", "у пути есть пояснение")
			else:
				assert_has(known, st.type, id)

func test_mining_advances_first_stage_and_offers_rewards():
	run.planet.goal.stages[0] = ProtoRun.make_stage("p_mine", 0, 4.0)
	_tick(1.2)
	drill.mined_total += 8.0
	_tick(1.2)
	assert_almost_eq(run.goals.progress, 8.0 / 15.0, 0.01)
	assert_gt(run.robot.xp.gatherer, 0.0, "бур — опыт собирателя")
	assert_true(run.robot.known_tags.has("luminous"), "теги добытого — в знания")
	drill.mined_total += 8.0
	_tick(1.2)
	assert_eq(run.goals.stage, 1)
	assert_eq(run.goals.reward_pending.size(), 3, "три карточки")
	assert_true(run.goals.choice_pending(), "второй этап — развилка")

func test_rewards_apply_in_3d():
	var k := run.robot.knowledge
	run.goals.reward_pending = ["knowledge", "supply", "repair"]
	run.take_reward("knowledge")
	assert_eq(run.robot.knowledge, k + 4, "общая карточка — как в 2D")
	assert_true(run.goals.reward_pending.is_empty())
	run.goals.reward_pending = ["supply"]
	run.take_reward("supply")
	assert_almost_eq(run.cargo_mass(), 15.0, 0.01, "припасы — в груз робота")
	net._burst(Vector2i(2, 0))
	assert_false(net.parts.has(Vector2i(2, 0)))
	run.goals.reward_pending = ["repair"]
	run.take_reward("repair")
	assert_true(net.parts.has(Vector2i(2, 0)), "ремонт ставит лопнувшую деталь обратно")
	_tick(1.2)
	assert_eq(run.built, 0, "починка — не новая постройка")
	run.goals.reward_pending = ["survey"]
	run.take_reward("survey")
	for m in planet.materials:
		for t in m.tags:
			assert_true(run.robot.known_tags.has(t))

func test_full_run_completes_and_summarizes():
	for i in 3:
		if run.goals.choice_pending():
			run.goals.choose(1)
		_complete_stage()
		if not run.goals.reward_pending.is_empty():
			run.take_reward(run.goals.reward_pending[0])
	assert_true(run.goals.completed, "все три этапа")
	var rows := run.summary()
	assert_eq(rows[2][1], "выполнены все")
	assert_true(run.advise(func(_a): return "X").begins_with("Цель выполнена"))

func test_progression_learns_with_shared_rules():
	assert_ne(run.learn("g2"), "", "без опыта и предыдущего узла нельзя")
	assert_eq(run.learn("g1"), "")
	assert_true(run.robot.learned.has("g1"))
	_tick(0.2)
	assert_almost_eq(drill.speed_mult, 1.5, 0.001, "Чутьё залежей ускоряет бур")
	run.robot.knowledge = 5
	assert_eq(run.learn("f1"), "")
	_tick(0.2)
	assert_almost_eq(net.pump_mult, 1.5, 0.001, "Раздувание ускоряет насосы")

func test_meteors_knock_cargo_unless_robot_leaves():
	ProtoMining.cargo_of(body).append(Portion.new(crystal, 10.0))
	run.robot_pos = Vector3(3, 0, 3)
	run.start_event("meteors", Vector3(3, 0, 3))
	assert_eq(run.ev.phase, "warn")
	assert_true(run.advise(func(_a): return "X").contains("красного круга"))
	run.ev.t = 0.0
	_tick(0.2)
	assert_eq(run.ev.phase, "active")
	_tick(8.0)
	assert_lt(run.cargo_mass(), 10.0, "удары рядом выбивают груз")
	run.robot_pos = Vector3(60, 0, 60)
	var hunter: float = run.robot.xp.hunter
	run.ev.t = 0.0
	_tick(0.2)
	assert_true(run.ev.is_empty(), "событие закончилось")
	assert_gt(run.robot.xp.hunter, hunter)
	assert_eq(run.ev_count, 1)

## Разбитая событием деталь: подсказка просит поставить её на место, пока пусто.
func test_advise_asks_to_rebuild_broken_part():
	assert_eq(run.goals.current().type, "p_store", "первый этап сида 14 — завод")
	net.feed(Vector2i.ZERO, Portion.new(crystal, 4.0))
	net._burst(Vector2i(1, 0))
	assert_eq(run.broken_parts().size(), 1)
	var tip := run.advise(func(_a): return "X")
	assert_true(tip.contains("Разбита") and tip.contains("Труба"), tip)
	net.place("pipe", Vector2i(1, 0), 0, steel)
	assert_true(run.broken_parts().is_empty(), "деталь на месте")
	assert_false(run.advise(func(_a): return "X").contains("Разбита"))

## Полный бак линии: подсказка просит бак перед ним, даже если другой бак пуст.
func test_advise_asks_for_tank_in_front_of_full_one():
	net.place("tank", Vector2i(0, 5), 0, steel)                # пустой бак в стороне
	net.parts[Vector2i(6, 0)].items.append(Portion.new(crystal, ProtoPneumatics.KINDS.tank.cap))
	net.feed(Vector2i.ZERO, Portion.new(crystal, 4.0))
	assert_eq(run.full_tanks(), [Vector2i(6, 0)])
	assert_true(run.advise(func(_a): return "X").contains("Бак полон"))
	net.place("tank", Vector2i(7, 0), 0, steel)
	assert_true(run.full_tanks().is_empty(), "за полным баком есть куда")

func test_storm_slows_pumps_and_events_come_by_themselves():
	run.start_event("storm", Vector3.ZERO)
	run.ev.t = 0.0
	_tick(0.2)
	assert_almost_eq(net.pump_mult, 0.5, 0.001)
	run.ev = {}
	run.ev_next = 0.05
	_tick(0.2)
	assert_false(run.ev.is_empty(), "следующее событие начинается само")
	assert_gt(Events.weight(run.ev.id, planet), 0.0, "только подходящие планете")

func test_save_roundtrip():
	drill.mined_total += 5.0
	_tick(1.2)
	run.learn("g1")
	run.goals.stage = 1
	run.goals.choices = {"1": 0}
	var d := JSON.parse_string(JSON.stringify(run.to_dict()))
	var fresh := ProtoRun.new(PlanetGen.generate(14), [steel])
	fresh.attach(net, drill, body, crystal, Vector3.ZERO)
	fresh.from_dict(d)
	assert_eq(fresh.goals.stage, 1)
	assert_false(fresh.goals.choice_pending())
	assert_true(fresh.robot.learned.has("g1"))
	assert_almost_eq(fresh.mined, 5.0, 0.01)
	fresh.tick(0.1)
	assert_almost_eq(fresh.mined, 5.0, 0.01, "добытое до загрузки не считается второй раз")

func test_pad_buttons_drive_windows():
	ProtoControls.ensure_ui()
	assert_true(InputMap.action_get_events(&"ui_accept").any(func(e): return e is InputEventJoypadButton and e.button_index == JOY_BUTTON_A))
	assert_true(InputMap.action_get_events(&"ui_cancel").any(func(e): return e is InputEventJoypadButton and e.button_index == JOY_BUTTON_B))
	ProtoControls.ensure()
	assert_true(InputMap.action_get_events(ProtoControls.MENU).any(func(e): return e is InputEventJoypadButton and e.button_index == JOY_BUTTON_START))
	var box: VBoxContainer = autofree(VBoxContainer.new())
	var hidden := Button.new()
	hidden.visible = false
	box.add_child(hidden)
	var off := Button.new()
	off.disabled = true
	box.add_child(off)
	var ok := Button.new()
	box.add_child(ok)
	assert_eq(ProtoControls.first_button(box), ok, "фокус — на первой доступной кнопке")

func test_run_window_waits_while_map_or_card_is_open():
	var ui := ProtoRunUi.new()
	ui.pause_game = false
	ui.setup(run, body, null)
	add_child_autofree(ui)
	ui._warm = 0.0
	body.set_meta("ui_busy", true)
	ui._process(0.1)
	assert_eq(ui.modal, "", "брифинг не встаёт под карту")
	body.set_meta("ui_busy", false)
	ui._process(0.1)
	assert_eq(ui.modal, "briefing")
	ui.close()
