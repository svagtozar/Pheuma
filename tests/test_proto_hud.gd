extends GutTest
## HUD 3D-прототипа: сводка груза и завода, подсказки кнопок под устройство.

## Завод-заглушка с тем же интерфейсом, что у ProtoPneumatics.
class FakeNet:
	var parts := {}
	var p := {}
	func pressure(c): return p.get(c, 0.0)
	func max_p(c): return parts[c].get("max", 10.0)
	func mass_in(c): return parts[c].get("kg", 0.0)

func _sub(n: String) -> Substance:
	var s := Substance.new()
	s.name = n
	return s

func before_all():
	ProtoControls.ensure()

func test_cargo_groups_by_substance_heaviest_first():
	var a := _sub("Толий")
	var b := _sub("Зенол")
	var s := ProtoHud.cargo_summary([Portion.new(b, 1.0), Portion.new(a, 2.0), Portion.new(a, 1.5)])
	assert_almost_eq(s.kg, 4.5, 0.001)
	assert_eq(s.rows.size(), 2)
	assert_eq(s.rows[0].name, "Толий")
	assert_almost_eq(s.rows[0].kg, 3.5, 0.001)

func test_empty_cargo():
	var s := ProtoHud.cargo_summary([])
	assert_eq(s.kg, 0.0)
	assert_true(s.rows.is_empty())

func test_factory_states():
	assert_false(ProtoHud.factory_summary(null).built, "нет завода")
	var net := FakeNet.new()
	net.parts[Vector2i(0, 0)] = {"kind": "pipe", "status": ""}
	assert_eq(ProtoHud.factory_summary(net).state, "нет насоса")
	net.parts[Vector2i(1, 0)] = {"kind": "pump", "status": ""}
	net.parts[Vector2i(2, 0)] = {"kind": "crusher", "status": "работает 40%"}
	net.parts[Vector2i(3, 0)] = {"kind": "tank", "status": "", "kg": 5.0}
	net.p = {Vector2i(1, 0): 4.0, Vector2i(0, 0): 3.0}
	var s := ProtoHud.factory_summary(net)
	assert_eq(s.state, "работает")
	assert_eq(s.tone, "ok")
	assert_eq(s.pumps, 1)
	assert_almost_eq(s.p, 4.0, 0.001)
	assert_almost_eq(s.stored, 5.0, 0.001)
	net.parts[Vector2i(0, 0)].max = 3.2      # труба почти на пределе
	s = ProtoHud.factory_summary(net)
	assert_eq(s.tone, "bad")
	assert_almost_eq(s.max_p, 3.2, 0.001)

func test_glyphs_switch_between_keyboard_and_pad():
	var move := [ProtoControls.MOVE_FORWARD, ProtoControls.MOVE_LEFT, ProtoControls.MOVE_BACK, ProtoControls.MOVE_RIGHT]
	assert_eq(ProtoHud.glyph(move, false), "WASD")
	assert_eq(ProtoHud.glyph(move, true), "L-стик")
	assert_eq(ProtoHud.glyph([ProtoControls.WORK], false), "F")
	assert_eq(ProtoHud.glyph([ProtoControls.WORK], true), "RT")
	assert_eq(ProtoHud.glyph([&"нет_такого"], true), "")

func test_hint_rows_follow_last_device():
	var hud := ProtoHud.new()
	add_child_autofree(hud)
	var e := InputEventJoypadButton.new()
	e.button_index = JOY_BUTTON_A
	e.pressed = true
	hud._input(e)
	assert_true(hud.pad)
	var rows := hud.hint_rows(false, false)
	assert_true(rows.any(func(r): return r[0] == "Бур" and r[1] == "RT"))
	var k := InputEventKey.new()
	k.physical_keycode = KEY_F
	k.pressed = true
	hud._input(k)
	assert_false(hud.pad)
	rows = hud.hint_rows(false, false)
	assert_true(rows.any(func(r): return r[0] == "Бур" and r[1] == "F"))

func test_hints_show_jump_run_and_mouse_camera():
	ProtoControls.ensure()
	var hud := ProtoHud.new()
	add_child_autofree(hud)
	hud.pad = false
	var rows := hud.hint_rows(false, false)
	assert_true(rows.any(func(r): return r[0] == "Прыжок" and r[1] == "Пробел"))
	assert_true(rows.any(func(r): return r[0] == "Бег" and r[1] == "Shift"))
	assert_true(rows.any(func(r): return r[0] == "Камера" and r[1].begins_with("Мышь")))
	hud.pad = true
	rows = hud.hint_rows(false, false)
	assert_true(rows.any(func(r): return r[0] == "Прыжок" and r[1] == "A"))
