extends GutTest
## Раскладка управления: геймпад и клавиатура ведут к одним действиям.

var C := ProtoControls

func before_all():
	C.ensure()

func after_each():
	Input.action_release(C.MOVE_FORWARD)
	for a in [JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y, JOY_AXIS_RIGHT_X, JOY_AXIS_TRIGGER_RIGHT, JOY_AXIS_TRIGGER_LEFT]:
		_stick(a, 0.0)

func _stick(axis: JoyAxis, v: float) -> void:
	var e := InputEventJoypadMotion.new()
	e.device = 0
	e.axis = axis
	e.axis_value = v
	Input.parse_input_event(e)
	Input.flush_buffered_events()

func test_actions_have_key_and_pad():
	for a in [C.MOVE_FORWARD, C.CAM_LEFT, C.SPRINT, C.WORK, C.FIST, C.JUMP]:
		var ev := InputMap.action_get_events(a)
		assert_true(ev.any(func(e): return e is InputEventKey), "%s: клавиша" % a)
		assert_true(ev.any(func(e): return e is InputEventJoypadMotion or e is InputEventJoypadButton), "%s: геймпад" % a)

func test_ensure_keeps_existing_action():
	InputMap.action_set_deadzone(C.SPRINT, 0.42)
	C.ensure()
	assert_almost_eq(InputMap.action_get_deadzone(C.SPRINT), 0.42, 0.001)
	InputMap.action_set_deadzone(C.SPRINT, 0.5)

func test_left_stick_moves_forward_and_scales():
	_stick(JOY_AXIS_LEFT_Y, -1.0)
	assert_almost_eq(C.move_vector().y, 1.0, 0.01)
	_stick(JOY_AXIS_LEFT_Y, -0.6)
	var half := C.move_vector().y
	assert_between(half, 0.3, 0.6, "частичный наклон — медленнее")

func test_stick_drift_inside_deadzone_ignored():
	_stick(JOY_AXIS_LEFT_X, 0.15)
	_stick(JOY_AXIS_RIGHT_X, 0.15)
	assert_eq(C.move_vector(), Vector2.ZERO)
	assert_eq(C.look_vector(), Vector2.ZERO)

func test_right_trigger_drives_drill():
	_stick(JOY_AXIS_TRIGGER_RIGHT, 1.0)
	assert_true(Input.is_action_pressed(C.WORK))
	assert_almost_eq(Input.get_action_strength(C.WORK), 1.0, 0.01)

func test_keyboard_action_still_moves():
	Input.action_press(C.MOVE_FORWARD)
	assert_almost_eq(C.move_vector().y, 1.0, 0.01)

func test_mouse_look_direction_and_sensitivity():
	# Мышь вправо — камера вправо (рыскание убывает), мышь вверх — взгляд вверх
	# (камера опускается: тангаж убывает).
	var d := C.mouse_look(Vector2(10, -10))
	assert_lt(d.x, 0.0)
	assert_lt(d.y, 0.0)
	C.mouse_sens = 2.0
	assert_almost_eq(C.mouse_look(Vector2(10, 0)).x, d.x * 2.0, 0.0001)
	C.mouse_sens = 1.0
	C.mouse_invert_y = true
	assert_gt(C.mouse_look(Vector2(0, -10)).y, 0.0)
	C.mouse_invert_y = false
