extends GutTest
## Инвентарь 3D-прототипа (ProtoInventory): бак рядом, взять и положить,
## по 1 кг, вместимость бака; бур копает и при полном бункере грунта.

func _sub(n: String) -> Substance:
	var s := Substance.new()
	s.name = n
	s.id = n
	return s

func _net() -> ProtoPneumatics:
	var p := Planet.new()
	p.atm_pressure = 1.0
	p.ambient_temp = 15.0
	var net := ProtoPneumatics.new(p)
	var body := _sub("Толий")
	net.place("tank", Vector2i(0, 0), 0, body)
	net.place("intake", Vector2i(5, 0), 0, body)
	net.place("pump", Vector2i(2, 0), 0, body)
	return net

func before_all():
	ProtoControls.ensure()

func test_nearest_box_only_tank_or_intake_in_reach():
	var net := _net()
	var o := Vector3.ZERO
	assert_eq(ProtoInventory.nearest_box(net, o, ProtoPneumatics.cell_pos(o, Vector2i(0, 0)) + Vector3(1, 0, 1)), Vector2i(0, 0))
	assert_eq(ProtoInventory.nearest_box(net, o, ProtoPneumatics.cell_pos(o, Vector2i(5, 0)) + Vector3(0, 0, 2)), Vector2i(5, 0))
	# У насоса — ни бака, ни приёмника ближе REACH.
	assert_null(ProtoInventory.nearest_box(net, o, ProtoPneumatics.cell_pos(o, Vector2i(2, 0)) + Vector3(0, 0, 3.4)))
	assert_null(ProtoInventory.nearest_box(null, o, o))

func test_take_from_tank_into_cargo_merges():
	var net := _net()
	var a := _sub("Зенол")
	net.parts[Vector2i(0, 0)].items.append(Portion.new(a, 6.0))
	var cargo: Array = [Portion.new(a, 1.0)]
	assert_almost_eq(ProtoInventory.take(net, Vector2i(0, 0), 0, cargo, 1.0), 1.0, 0.001, "по 1 кг")
	assert_almost_eq(cargo[0].mass, 2.0, 0.001, "к той же порции")
	assert_almost_eq(net.mass_in(Vector2i(0, 0)), 5.0, 0.001)
	assert_almost_eq(ProtoInventory.take(net, Vector2i(0, 0), 0, cargo), 5.0, 0.001, "всё")
	assert_true(net.parts[Vector2i(0, 0)].items.is_empty(), "пустая порция ушла из бака")
	assert_eq(cargo.size(), 1)
	assert_almost_eq(ProtoInventory.take(net, Vector2i(0, 0), 0, cargo), 0.0, 0.001, "брать нечего")

func test_put_respects_tank_cap():
	var net := _net()
	var a := _sub("Зенол")
	var cap: float = ProtoPneumatics.KINDS.tank.cap
	net.parts[Vector2i(0, 0)].items.append(Portion.new(a, cap - 2.0))
	var cargo: Array = [Portion.new(_sub("Руда"), 5.0)]
	assert_almost_eq(ProtoInventory.put(net, Vector2i(0, 0), 0, cargo), 2.0, 0.001, "влезло только 2 кг")
	assert_almost_eq(cargo[0].mass, 3.0, 0.001)
	assert_almost_eq(ProtoInventory.put(net, Vector2i(0, 0), 0, cargo), 0.0, 0.001, "бак полон")
	# В приёмник — без предела; он отправит груз дальше по трубам.
	assert_almost_eq(ProtoInventory.put(net, Vector2i(5, 0), 0, cargo), 3.0, 0.001)
	assert_true(cargo.is_empty())

func test_compact_merges_same_substance():
	var a := _sub("Зенол")
	var b := _sub("Толий")
	var list: Array = [Portion.new(a, 1.0), Portion.new(b, 2.0), Portion.new(a, 3.0)]
	ProtoInventory.compact(list)
	assert_eq(list.size(), 2)
	assert_almost_eq(list[0].mass, 4.0, 0.001)

func test_panel_moves_rows_and_drops_soil():
	var net := _net()
	var a := _sub("Зенол")
	var view := ProtoPneumaticsView.new()
	view.net = net
	add_child_autofree(view)
	var robot := Node3D.new()
	add_child_autofree(robot)
	robot.global_position = ProtoPneumatics.cell_pos(view.origin, Vector2i(0, 0)) + Vector3(0, 0, 2)
	robot.set_meta("cargo", [Portion.new(a, 3.0)])
	var dg := ProtoDigger.new()
	add_child_autofree(dg)
	dg.soil = 5
	var inv := ProtoInventory.new()
	add_child_autofree(inv)
	inv.setup(robot, view, dg)
	inv.show_inventory()
	assert_true(robot.get_meta("ui_busy"), "робот стоит")
	assert_eq(inv.box_cell(), Vector2i(0, 0))
	inv.act(["cargo", 0])
	assert_true((robot.get_meta("cargo") as Array).is_empty(), "груз — в бак")
	assert_almost_eq(net.mass_in(Vector2i(0, 0)), 3.0, 0.001)
	inv.act(["box", 0], ProtoInventory.CHUNK_KG)
	assert_almost_eq((robot.get_meta("cargo") as Array)[0].mass, 1.0, 0.001, "взят 1 кг")
	inv.drop(["soil", 0])
	assert_eq(dg.soil, 0, "бункер высыпан")
	inv.drop(["cargo", 0])
	assert_true((robot.get_meta("cargo") as Array).is_empty(), "выброшено")
	inv.close()
	assert_false(robot.get_meta("ui_busy"))

func test_toggle_action_and_rebind_entry():
	assert_true(InputMap.has_action(ProtoInventory.TOGGLE))
	assert_true(ProtoControls.REBIND.any(func(r): return r[0] == ProtoInventory.TOGGLE))
	assert_eq(ProtoControls.binding(ProtoInventory.TOGGLE, false).physical_keycode, KEY_I)
