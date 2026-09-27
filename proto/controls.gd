class_name ProtoControls
extends RefCounted
## Общая раскладка управления роботом: действия InputMap, у каждого — клавиша и
## кнопка/ось геймпада (раскладка Xbox; у PlayStation те же места).
##   Левый стик / WASD — ходьба (наклон стика задаёт скорость)
##   Правый стик / Q,E — камера (стик ещё и вверх-вниз)
##   L3 (нажать левый стик) / Shift — бег
##   A / Пробел — прыжок (в режиме стройки эти же кнопки ставят деталь)
##   RT / F (держать) — работать инструментом (бур)
##   LT / G — выстрелить кистью и подтянуться, ещё раз — отпустить
##   D-pad вверх-вниз / колесо мыши — дистанция камеры
##   B / Z — коснуться того, что рядом (карточка материала, ProtoLabPanel)
##   Мышь — камера (курсор захвачен; клик — захватить)
##   Start / Esc — меню рана (цель, прокачка, итоги, «Управление»); K — прокачка
## Окна (ensure_ui): A — нажать кнопку, B — назад, D-pad и левый стик — выбор.
## Действия регистрируются кодом (ensure()), если их ещё нет в InputMap, —
## так их видят и прототип, и игра, и тесты без правки project.godot.
## Переназначенные кнопки и чувствительность хранятся в user://controls.cfg
## (экран ProtoControlsMenu); ensure() подхватывает их при первом вызове.

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
const JUMP := &"jump"
const MENU := &"run_menu"
const SKILLS := &"run_skills"

## Чувствительность мыши и стика (1 — по умолчанию) и инверсия вертикали.
static var mouse_sens := 1.0
static var mouse_invert_y := false
static var stick_sens := 1.0
static var stick_invert_y := false
static var save_path := "user://controls.cfg"
static var _loaded := false

## Что можно переназначить, по порядку в меню: [действие, подпись].
const REBIND := [
	[MOVE_FORWARD, "Вперёд"], [MOVE_BACK, "Назад"], [MOVE_LEFT, "Влево"], [MOVE_RIGHT, "Вправо"],
	[SPRINT, "Бег"], [JUMP, "Прыжок"],
	[CAM_LEFT, "Камера влево"], [CAM_RIGHT, "Камера вправо"], [CAM_UP, "Камера вверх"], [CAM_DOWN, "Камера вниз"],
	[CAM_ZOOM_IN, "Камера ближе"], [CAM_ZOOM_OUT, "Камера дальше"],
	[WORK, "Бур"], [FIST, "Кисть"],
	[&"build_mode", "Стройка вкл/выкл"], [&"build_next", "Следующая деталь"], [&"build_prev", "Предыдущая деталь"],
	[&"build_rotate", "Повернуть деталь"], [&"build_material", "Материал детали"],
	[&"build_place", "Поставить"], [&"build_remove", "Разобрать"], [&"cargo_unload", "Выгрузить груз"],
	[&"lab_touch", "Коснуться (карточка материала)"], [&"lab_analyze", "Анализатор"],
	[&"lab_prev", "Карточка: предыдущий образец"], [&"lab_next", "Карточка: следующий образец"],
	[&"lab_close", "Карточка: закрыть"],
	[MENU, "Меню рана"], [SKILLS, "Прокачка"], [&"map_toggle", "Карта"],
]

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
		JUMP: [0.5, _key(KEY_SPACE), _button(JOY_BUTTON_A)],
		MENU: [0.5, _key(KEY_ESCAPE), _button(JOY_BUTTON_START)],
		SKILLS: [0.5, _key(KEY_K)],
	}

## Добавляет недостающие действия (свои и стройки). Уже заданные (в
## project.godot или раньше) не трогает. Сохранённые настройки — один раз.
static func ensure() -> void:
	var layout := _layout()
	for action in layout:
		if InputMap.has_action(action):
			continue
		var spec: Array = layout[action]
		InputMap.add_action(action, spec[0])
		for i in range(1, spec.size()):
			InputMap.action_add_event(action, spec[i])
	ProtoBuilder.ensure_actions()
	ProtoLabPanel.ensure_actions()
	ProtoMapView.ensure_actions()
	if not _loaded:
		_loaded = true
		load_settings()

# ---------------------------------------------------------------- переназначение

static func is_pad(e: InputEvent) -> bool:
	return e is InputEventJoypadButton or e is InputEventJoypadMotion

## Первое событие действия с клавиатуры (pad = false) или геймпада (pad = true).
static func binding(action: StringName, pad: bool) -> InputEvent:
	if not InputMap.has_action(action):
		return null
	for e in InputMap.action_get_events(action):
		if is_pad(e) == pad:
			return e
	return null

## Назначить событие: заменяет прежнюю клавишу (или кнопку геймпада) действия.
## Событие приводится к виду раскладки: физическая клавиша, любой геймпад,
## ось — только направление.
static func rebind(action: StringName, e: InputEvent) -> void:
	var clean := _normalize(e)
	if clean == null or not InputMap.has_action(action):
		return
	for old in InputMap.action_get_events(action):
		if is_pad(old) == is_pad(clean):
			InputMap.action_erase_event(action, old)
	InputMap.action_add_event(action, clean)

static func _normalize(e: InputEvent) -> InputEvent:
	if e is InputEventKey:
		var code: Key = e.physical_keycode if e.physical_keycode != KEY_NONE else e.keycode
		return _key(code) if code != KEY_NONE else null
	if e is InputEventJoypadButton:
		return _button(e.button_index)
	if e is InputEventJoypadMotion:
		return _axis(e.axis, signf(e.axis_value) if e.axis_value != 0.0 else 1.0)
	return null

## Всё как по умолчанию: раскладка, чувствительность, инверсия.
static func reset_defaults() -> void:
	for lay: Dictionary in [_layout(), ProtoBuilder.layout(), ProtoLabPanel.layout(), ProtoMapView.layout()]:
		for a in lay:
			if InputMap.has_action(a):
				InputMap.erase_action(a)
	mouse_sens = 1.0
	stick_sens = 1.0
	mouse_invert_y = false
	stick_invert_y = false
	ensure()

## Событие → строка для файла: key:код, btn:кнопка, axis:ось:знак.
static func event_to_str(e: InputEvent) -> String:
	if e is InputEventKey:
		return "key:%d" % (e.physical_keycode if e.physical_keycode != KEY_NONE else e.keycode)
	if e is InputEventJoypadButton:
		return "btn:%d" % e.button_index
	if e is InputEventJoypadMotion:
		return "axis:%d:%d" % [e.axis, 1 if e.axis_value >= 0.0 else -1]
	return ""

static func str_to_event(s: String) -> InputEvent:
	var p := s.split(":")
	match p[0]:
		"key": return _key(int(p[1]) as Key) if p.size() == 2 else null
		"btn": return _button(int(p[1]) as JoyButton) if p.size() == 2 else null
		"axis": return _axis(int(p[1]) as JoyAxis, float(p[2])) if p.size() == 3 else null
	return null

static func save_settings() -> void:
	var cf := ConfigFile.new()
	cf.set_value("camera", "mouse_sens", mouse_sens)
	cf.set_value("camera", "mouse_invert_y", mouse_invert_y)
	cf.set_value("camera", "stick_sens", stick_sens)
	cf.set_value("camera", "stick_invert_y", stick_invert_y)
	for r in REBIND:
		if not InputMap.has_action(r[0]):
			continue
		var evs := PackedStringArray()
		for e in InputMap.action_get_events(r[0]):
			var t := event_to_str(e)
			if t != "":
				evs.append(t)
		cf.set_value("bind", String(r[0]), evs)
	cf.save(save_path)

## Подхватить сохранённое; нет файла — всё остаётся по умолчанию.
static func load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load(save_path) != OK:
		return
	mouse_sens = clampf(float(cf.get_value("camera", "mouse_sens", 1.0)), 0.1, 5.0)
	mouse_invert_y = bool(cf.get_value("camera", "mouse_invert_y", false))
	stick_sens = clampf(float(cf.get_value("camera", "stick_sens", 1.0)), 0.1, 5.0)
	stick_invert_y = bool(cf.get_value("camera", "stick_invert_y", false))
	if not cf.has_section("bind"):
		return
	for a in cf.get_section_keys("bind"):
		if not InputMap.has_action(a):
			continue
		var evs := []
		for t in cf.get_value("bind", a, PackedStringArray()):
			var e := str_to_event(String(t))
			if e != null:
				evs.append(e)
		if evs.is_empty():
			continue
		InputMap.action_erase_events(a)
		for e in evs:
			InputMap.action_add_event(a, e)

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
	if stick_invert_y:
		v.y = -v.y
	return v * v.length() * stick_sens

## Поворот камеры от движения мыши (пиксели) → [рыскание, тангаж], радианы.
static func mouse_look(rel: Vector2) -> Vector2:
	var k := 0.0032 * mouse_sens
	# Мышь вверх — смотреть вверх: тангаж (высота камеры над роботом) убывает.
	return Vector2(-rel.x * k, rel.y * k * (-1.0 if mouse_invert_y else 1.0))

## Только правый стик (без клавиш): там, где Q/E заняты другим (игра, F3).
static func stick_look() -> Vector2:
	var v := Vector2.ZERO
	for d in Input.get_connected_joypads():
		var s := Vector2(Input.get_joy_axis(d, JOY_AXIS_RIGHT_X), -Input.get_joy_axis(d, JOY_AXIS_RIGHT_Y))
		if s.length() > STICK_DEADZONE and s.length() > v.length():
			v = s
	if stick_invert_y:
		v.y = -v.y
	return v * minf(v.length(), 1.0) * stick_sens

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
