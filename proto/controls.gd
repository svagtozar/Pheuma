class_name ProtoControls
extends RefCounted
## Общая раскладка управления роботом: действия InputMap, у каждого — клавиша и
## кнопка/ось геймпада (раскладка Xbox; у PlayStation те же места).
##   Левый стик / WASD — ходьба (наклон стика задаёт скорость)
##   Правый стик / Q,E — камера (стик ещё и вверх-вниз)
##   L3 (нажать левый стик) / Shift — быстрее
##   RT / F (держать) — работать инструментом (бур)
##   LT / G — выстрелить кистью и подтянуться, ещё раз — отпустить
##   D-pad вверх-вниз / колесо мыши — дистанция камеры
##   Start / Esc — меню рана (цель, прокачка, итоги); K — прокачка
## Окна (ensure_ui): A — нажать кнопку, B — назад, D-pad и левый стик — выбор.
## Действия регистрируются кодом (ensure()), если их ещё нет в InputMap, —
## так их видят и прототип, и игра, и тесты без правки project.godot.

const STICK_DEADZONE := 0.2
const TRIGGER_DEADZONE := 0.3

const MOVE_FORWARD := &"move_forward"
const MOVE_BACK := &"move_back"
const MOVE_LEFT := &"move_left"
const MOVE_RIGHT := &"move_right"
const CAM_LEFT := &"cam_left"
const CAM_RIGHT := &"cam_right"
const CAM_UP := &"cam_up"
const CAM_DOWN := &"cam_down"
const CAM_ZOOM_IN := &"cam_zoom_in"
const CAM_ZOOM_OUT := &"cam_zoom_out"
const SPRINT := &"sprint"
const WORK := &"tool_work"
const FIST := &"fist_fire"
const MENU := &"run_menu"
const SKILLS := &"run_skills"

## Действие → [мёртвая зона, события...]. Клавиши — физические (раскладка не важна).
static func _layout() -> Dictionary:
	return {
		MOVE_FORWARD: [STICK_DEADZONE, _key(KEY_W), _axis(JOY_AXIS_LEFT_Y, -1.0)],
		MOVE_BACK: [STICK_DEADZONE, _key(KEY_S), _axis(JOY_AXIS_LEFT_Y, 1.0)],
		MOVE_LEFT: [STICK_DEADZONE, _key(KEY_A), _axis(JOY_AXIS_LEFT_X, -1.0)],
		MOVE_RIGHT: [STICK_DEADZONE, _key(KEY_D), _axis(JOY_AXIS_LEFT_X, 1.0)],
		CAM_LEFT: [STICK_DEADZONE, _key(KEY_Q), _axis(JOY_AXIS_RIGHT_X, -1.0)],
		CAM_RIGHT: [STICK_DEADZONE, _key(KEY_E), _axis(JOY_AXIS_RIGHT_X, 1.0)],
		CAM_UP: [STICK_DEADZONE, _axis(JOY_AXIS_RIGHT_Y, -1.0)],
		CAM_DOWN: [STICK_DEADZONE, _axis(JOY_AXIS_RIGHT_Y, 1.0)],
		CAM_ZOOM_IN: [0.5, _button(JOY_BUTTON_DPAD_UP)],
		CAM_ZOOM_OUT: [0.5, _button(JOY_BUTTON_DPAD_DOWN)],
		SPRINT: [0.5, _key(KEY_SHIFT), _button(JOY_BUTTON_LEFT_STICK)],
		WORK: [TRIGGER_DEADZONE, _key(KEY_F), _axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)],
		FIST: [TRIGGER_DEADZONE, _key(KEY_G), _axis(JOY_AXIS_TRIGGER_LEFT, 1.0)],
		MENU: [0.5, _key(KEY_ESCAPE), _button(JOY_BUTTON_START)],
		SKILLS: [0.5, _key(KEY_K)],
	}

## Добавляет недостающие действия. Уже заданные (в project.godot или раньше) не трогает.
static func ensure() -> void:
	var layout := _layout()
	for action in layout:
		if InputMap.has_action(action):
			continue
		var spec: Array = layout[action]
		InputMap.add_action(action, spec[0])
		for i in range(1, spec.size()):
			InputMap.action_add_event(action, spec[i])

## Окна интерфейса с геймпада: A нажимает кнопку в фокусе, B — назад.
## Встроенные ui_accept и ui_cancel в Godot 4 знают только клавиатуру.
static func ensure_ui() -> void:
	for pair in [[&"ui_accept", JOY_BUTTON_A], [&"ui_cancel", JOY_BUTTON_B]]:
		var has := InputMap.action_get_events(pair[0]).any(func(e): return e is InputEventJoypadButton and e.button_index == pair[1])
		if not has:
			InputMap.action_add_event(pair[0], _button(pair[1]))

## Первая видимая доступная кнопка внутри узла (для фокуса геймпада).
static func first_button(n: Node) -> Control:
	for c in n.get_children():
		if c is CanvasItem and not c.visible:
			continue
		if c is BaseButton and not c.disabled and c.focus_mode != Control.FOCUS_NONE:
			return c
		var b := first_button(c)
		if b != null:
			return b
	return null

## Ходьба: x — вправо, y — вперёд; длина 0..1 (стик наполовину — полшага).
static func move_vector() -> Vector2:
	return Input.get_vector(MOVE_LEFT, MOVE_RIGHT, MOVE_BACK, MOVE_FORWARD)

## Камера: x — вправо, y — вверх; квадратичная кривая — точнее у центра стика.
static func look_vector() -> Vector2:
	var v := Input.get_vector(CAM_LEFT, CAM_RIGHT, CAM_DOWN, CAM_UP)
	return v * v.length()

static func _key(code: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = code
	return e

static func _axis(axis: JoyAxis, dir: float) -> InputEventJoypadMotion:
	var e := InputEventJoypadMotion.new()
	e.device = -1
	e.axis = axis
	e.axis_value = dir
	return e

static func _button(b: JoyButton) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.device = -1
	e.button_index = b
	return e
