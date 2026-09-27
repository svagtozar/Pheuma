extends GutTest
## Экран «Управление»: переназначение, сохранение, сброс; направление ходьбы.

var C := ProtoControls
var _path := C.save_path

func before_each():
	C.save_path = "user://test_controls.cfg"
	C.reset_defaults()

func after_each():
	DirAccess.remove_absolute(ProjectSettings.globalize_path(C.save_path))
	C.reset_defaults()
	C.save_path = _path

func _key(code: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.pressed = true
	return e

func test_strafe_right_goes_to_screen_right():
	# Камера смотрит вдоль +z (yaw 0): право на экране — это −x.
	var cam := Camera3D.new()
	add_child_autofree(cam)
	cam.look_at_from_position(Vector3(0, 0, -5), Vector3.ZERO)
	var d := ProtoPlayer.move_dir(0.0, Vector2(1, 0))
	assert_gt(d.dot(cam.global_transform.basis.x), 0.9, "D — вправо по экрану")
	assert_gt(ProtoPlayer.move_dir(0.0, Vector2(0, 1)).z, 0.9, "W — от камеры")

func test_rebind_replaces_only_same_device():
	C.rebind(C.JUMP, _key(KEY_J))
	assert_eq(C.binding(C.JUMP, false).physical_keycode, KEY_J)
	assert_eq(C.binding(C.JUMP, true).button_index, JOY_BUTTON_A, "кнопка геймпада осталась")
	var b := InputEventJoypadButton.new()
	b.button_index = JOY_BUTTON_Y
	b.device = 3
	C.rebind(C.JUMP, b)
	assert_eq(C.binding(C.JUMP, true).button_index, JOY_BUTTON_Y)
	assert_eq(C.binding(C.JUMP, true).device, -1, "любой геймпад")
	assert_eq(InputMap.action_get_events(C.JUMP).size(), 2)

func test_save_and_load_roundtrip():
	C.rebind(C.SPRINT, _key(KEY_CTRL))
	var ax := InputEventJoypadMotion.new()
	ax.axis = JOY_AXIS_RIGHT_Y
	ax.axis_value = -0.8
	C.rebind(C.WORK, ax)
	C.mouse_sens = 1.75
	C.stick_invert_y = true
	C.save_settings()
	C.reset_defaults()
	assert_eq(C.binding(C.SPRINT, false).physical_keycode, KEY_SHIFT)
	C.load_settings()
	assert_eq(C.binding(C.SPRINT, false).physical_keycode, KEY_CTRL)
	var w := C.binding(C.WORK, true) as InputEventJoypadMotion
	assert_eq(w.axis, JOY_AXIS_RIGHT_Y)
	assert_eq(w.axis_value, -1.0)
	assert_almost_eq(C.mouse_sens, 1.75, 0.001)
	assert_true(C.stick_invert_y)

func test_menu_captures_key_and_cancels():
	var m := ProtoControlsMenu.new()
	m.pause_tree = false
	add_child_autofree(m)
	m.open()
	m.start_wait(C.FIST, false)
	m.feed(_key(KEY_H))
	assert_eq(C.binding(C.FIST, false).physical_keycode, KEY_H)
	assert_true(FileAccess.file_exists(C.save_path), "сохранено сразу")
	m.start_wait(C.FIST, false)
	m.feed(_key(KEY_ESCAPE))
	assert_eq(C.binding(C.FIST, false).physical_keycode, KEY_H, "Esc — отмена")
	assert_eq(m._rows[C.FIST][0].text, "H")
	m.close()
	assert_false(m.is_open())
