extends GutTest
## Карта 3D-прототипа: рельеф, туман войны, метки, радар и кнопка карты.

func _flat_map() -> ProtoMapData:
	var d := ProtoMapData.new(Vector2.ZERO, Vector2(40, 30), 1.0)
	d.bake(func(x, z): return 10.0 + x * 0.1, func(_x, _z, _h, _n): return Color(0.5, 0.4, 0.3))
	return d

func test_bake_heights_and_textures():
	var d := _flat_map()
	assert_not_null(d.relief)
	assert_eq(d.relief.get_width(), 40)
	assert_eq(d.relief.get_height(), 30)
	assert_almost_eq(d.height_at(20.0, 5.0), 12.05, 0.11)

func test_reveal_opens_circle_and_finds_markers():
	var d := _flat_map()
	var near := d.add_marker("druse", Vector3(12, 10, 10))
	var far := d.add_marker("druse", Vector3(38, 10, 28))
	var fac := d.add_marker("factory", Vector3(30, 10, 5))
	assert_true(fac.found, "завод известен с начала")
	assert_false(near.found)
	d.reveal(Vector3(10, 10, 10))
	assert_gt(d.explored(10, 10), 0.9, "вокруг робота разведано")
	assert_eq(d.explored(38, 28), 0.0, "далеко — туман")
	assert_true(near.found)
	assert_false(far.found)
	assert_eq(d.found().size(), 2)
	assert_gt(d.explored_share(), 0.1)

func test_underground_reveal_has_own_mask():
	var d := _flat_map()
	var hall := d.add_marker("hall", Vector3(20, 2, 15), "", true)
	d.reveal(Vector3(20, 2, 15), true)
	assert_eq(d.explored(20, 15), 0.0, "поверхность над залом — в тумане")
	assert_gt(d.explored(20, 15, true), 0.9)
	assert_true(hall.found)

func test_save_roundtrip():
	var d := _flat_map()
	d.add_marker("cave", Vector3(5, 10, 5))
	d.reveal(Vector3(5, 10, 5))
	d.reveal(Vector3(30, 3, 20), true)
	var saved := d.save_dict()
	var e := _flat_map()
	e.add_marker("cave", Vector3(5, 10, 5))
	e.load_dict(JSON.parse_string(JSON.stringify(saved)))
	assert_gt(e.explored(5, 5), 0.9)
	assert_gt(e.explored(30, 20, true), 0.9)
	assert_true(e.markers[0].found)

func test_radar_rotates_with_heading():
	# Камера смотрит на север (−z): точка севернее — вверху радара.
	var s := ProtoRadar.to_screen(Vector2(0, -10), Vector2(0, -1), 100.0, 20.0)
	assert_almost_eq(s.x, 0.0, 0.001)
	assert_almost_eq(s.y, -50.0, 0.001)
	# Камера смотрит на восток (+x): точка восточнее — вверху, севернее — слева.
	s = ProtoRadar.to_screen(Vector2(10, 0), Vector2(1, 0), 100.0, 20.0)
	assert_almost_eq(s.y, -50.0, 0.001)
	s = ProtoRadar.to_screen(Vector2(0, -10), Vector2(1, 0), 100.0, 20.0)
	assert_almost_eq(s.x, -50.0, 0.001)

func test_map_action_and_hint():
	ProtoControls.ensure()
	ProtoMapView.ensure_actions()
	assert_true(InputMap.has_action(ProtoMapView.TOGGLE))
	assert_eq(ProtoHud.glyph([ProtoMapView.TOGGLE], false), "M")
	assert_eq(ProtoHud.glyph([ProtoMapView.TOGGLE], true), "View")
	var hud := ProtoHud.new()
	var rows := hud.hint_rows(false, false)
	assert_true(rows.any(func(r): return r[0] == "Карта"), "подсказка карты в HUD")
	hud.free()

func test_map_view_opens_and_blocks_robot():
	var d := _flat_map()
	var robot := Node3D.new()
	add_child_autofree(robot)
	var mv := ProtoMapView.new()
	add_child_autofree(mv)
	mv.setup(d, robot, [], [], [])
	mv.show_map()
	assert_true(mv.open)
	assert_true(robot.get_meta("ui_busy"), "робот стоит, пока карта открыта")
	assert_true(robot.get_meta("map_open"))
	mv.close()
	assert_false(robot.get_meta("ui_busy"))
	assert_false(robot.get_meta("map_open"))
