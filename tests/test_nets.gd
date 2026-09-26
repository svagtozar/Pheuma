extends GutTest

func _chain(n: int) -> GasNet:
	var g := GasNet.new()
	for i in n:
		g.add_node(i, 1.0)
	for i in n - 1:
		g.connect_nodes(i, i + 1)
	return g

func test_gas_conserved():
	var g := _chain(6)
	g.add_gas(0, 20.0)
	var total := g.total_gas()
	for i in 500:
		g.step(0.1)
	assert_almost_eq(g.total_gas(), total, 0.0001)

func test_pressure_equalizes():
	var g := _chain(4)
	g.add_gas(0, 12.0)
	for i in 600:
		g.step(0.1)
	assert_almost_eq(g.pressure(0), g.pressure(3), 0.01)
	assert_gt(g.pressure(3), 1.5)

func test_flow_goes_high_to_low():
	var g := _chain(2)
	g.add_gas(0, 5.0)
	var p0 := g.pressure(0)
	g.step(0.1)
	assert_lt(g.pressure(0), p0)
	assert_gt(g.pressure(1), 1.0)

func test_closed_valve_blocks():
	var g := _chain(2)
	g.add_gas(0, 5.0)
	g.set_open(0, 1, false)
	for i in 50:
		g.step(0.1)
	assert_almost_eq(g.pressure(1), 1.0, 0.0001)

func test_vent_returns_to_atmosphere():
	var g := _chain(1)
	g.add_gas(0, 5.0)
	g.set_vent(0, true)
	for i in 100:
		g.step(0.1)
	assert_almost_eq(g.pressure(0), 1.0, 0.01)

func test_burst_reported():
	var g := GasNet.new()
	g.add_node(1, 1.0, 3.0)
	g.add_gas(1, 5.0)
	assert_eq(g.step(0.1), [1])

func test_thin_atmosphere_starts_low():
	var g := GasNet.new()
	g.atm_pressure = 0.25
	g.add_node(1, 2.0)
	assert_almost_eq(g.pressure(1), 0.25, 0.001)

func test_logic_wires_and_inputs():
	var l := LogicNet.new()
	l.add_wire(1, 3, 0)
	l.add_wire(2, 3, 1)
	l.outputs[1] = true
	assert_true(l.input(3, 0))
	assert_false(l.input(3, 1))
	assert_true(l.has_input(3))
	l.remove_machine(1)
	assert_false(l.input(3, 0))
	assert_eq(l.wires.size(), 1)

func test_waypoints_edit():
	var l := LogicNet.new()
	var w := l.add_wire(1, 2, 0)
	var a := Vector2(0, 0)
	var b := Vector2(100, 0)
	var i := l.insert_waypoint(w, Vector2(50, 30), a, b)
	assert_eq(i, 0)
	l.insert_waypoint(w, Vector2(80, 10), a, b)
	assert_eq(l.wires[w].points.size(), 2)
	assert_eq(l.wires[w].points[1], Vector2(80, 10))
	l.move_waypoint(w, 0, Vector2(40, 40))
	assert_eq(l.wires[w].points[0], Vector2(40, 40))
	l.remove_waypoint(w, 0)
	assert_eq(l.wires[w].points, [Vector2(80, 10)])
	var poly := LogicNet.polyline(a, l.wires[w].points, b)
	assert_gt(LogicNet.length_of(poly), 100.0)
