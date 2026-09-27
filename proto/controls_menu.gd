class_name ProtoControlsMenu
extends CanvasLayer
## Экран «Управление»: чувствительность и инверсия камеры (мышь и стик),
## переназначение клавиш и кнопок геймпада для всех действий ProtoControls.REBIND.
## Всё сохраняется сразу в user://controls.cfg (ProtoControls.save_settings).
## Управляется и мышью, и геймпадом: фокус по D-pad/стику, A — выбрать,
## B / Esc — назад. Переназначение: выбрать ячейку, нажать клавишу (или кнопку,
## или наклонить стик/курок); Esc или View — отмена.
## Размеры — под Steam Deck (1280×800), на большем экране масштабируется целиком.
## pause_tree — ставить дерево на паузу, пока меню открыто, если оно ещё не на
## паузе (меню рана уже поставило — тогда и снимать не нам). Открытое меню —
## в группе GROUP: окна под ним не забирают фокус.

const GROUP := &"controls_menu_open"

signal closed

const BASE := Vector2(1280, 800)
const FONT := 20
const FONT_SMALL := 16
const BG := Color(0.06, 0.07, 0.09, 0.94)
const TEXT := Color(0.93, 0.94, 0.95)
const DIM := Color(0.66, 0.69, 0.73)
const ACCENT := Color(0.98, 0.76, 0.3)

var pause_tree := true
var _paused_here := false
var _frame: Control
var _rows := {}                  # действие → [кнопка клавиатуры, кнопка геймпада]
var _mouse: HSlider
var _stick: HSlider
var _mouse_inv: CheckButton
var _stick_inv: CheckButton
var _mouse_val: Label
var _stick_val: Label
var _hint: Label
var _first: Control
var _wait_action := &""
var _wait_pad := false

func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	ProtoControls.ensure()
	_build()
	get_viewport().size_changed.connect(_layout)
	_layout()

func is_open() -> bool:
	return visible

func open() -> void:
	if visible:
		return
	visible = true
	_refresh()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	add_to_group(GROUP)
	_paused_here = pause_tree and not get_tree().paused
	if _paused_here:
		get_tree().paused = true
	_first.grab_focus.call_deferred()

func close() -> void:
	if not visible:
		return
	_cancel_wait()
	visible = false
	remove_from_group(GROUP)
	if _paused_here:
		get_tree().paused = false
	_paused_here = false
	closed.emit()

func toggle() -> void:
	if visible:
		close()
	else:
		open()

# ---------------------------------------------------------------- ввод

func _input(e: InputEvent) -> void:
	if not visible:
		return
	if _wait_action != &"":
		_capture(e)
		return
	if e.is_action_pressed(&"ui_cancel") or (e is InputEventJoypadButton and e.pressed and e.button_index == JOY_BUTTON_START):
		close()
		get_viewport().set_input_as_handled()

## Ждём клавишу (или кнопку/ось геймпада) для _wait_action.
func _capture(e: InputEvent) -> void:
	var cancel: bool = (e is InputEventKey and e.pressed and e.physical_keycode == KEY_ESCAPE) \
		or (e is InputEventJoypadButton and e.pressed and e.button_index == JOY_BUTTON_BACK)
	cancel = cancel or (e is InputEventMouseButton and e.pressed)   # клик мимо — отмена
	var got: InputEvent = null
	if not cancel:
		if not _wait_pad and e is InputEventKey and e.pressed and not e.echo:
			got = e
		elif _wait_pad and e is InputEventJoypadButton and e.pressed:
			got = e
		elif _wait_pad and e is InputEventJoypadMotion and absf(e.axis_value) > 0.6:
			got = e
	# Пока ждём, клавиши и кнопки не уходят ни в меню, ни в игру.
	if cancel or got != null or e is InputEventKey or e is InputEventJoypadButton or e is InputEventMouseButton:
		get_viewport().set_input_as_handled()
	if not cancel and got == null:
		return
	var a := _wait_action
	var btn: Button = _rows[a][1 if _wait_pad else 0]
	_cancel_wait()
	if got != null:
		ProtoControls.rebind(a, got)
		ProtoControls.save_settings()
		_refresh()
	btn.grab_focus()

func start_wait(action: StringName, pad: bool) -> void:
	_start_wait(action, pad)

func _start_wait(action: StringName, pad: bool) -> void:
	_cancel_wait()
	_wait_action = action
	_wait_pad = pad
	var b: Button = _rows[action][1 if pad else 0]
	b.text = "…"
	_hint.text = ("Нажмите кнопку геймпада или наклоните стик" if pad else "Нажмите клавишу") \
		+ " для «%s». Отмена — %s." % [_label_of(action), "View" if pad else "Esc"]
	_hint.add_theme_color_override("font_color", ACCENT)

func _cancel_wait() -> void:
	_wait_action = &""
	_hint.text = "Выберите ячейку и нажмите новую клавишу или кнопку. Настройки сохраняются сразу."
	_hint.add_theme_color_override("font_color", DIM)
	_refresh()

# ---------------------------------------------------------------- вид

func _layout() -> void:
	var vs := get_viewport().get_visible_rect().size
	var s := clampf(minf(vs.x / BASE.x, vs.y / BASE.y), 0.6, 2.0)
	_frame.scale = Vector2(s, s)
	_frame.position = (vs - BASE * s) * 0.5

func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	_frame = Control.new()
	_frame.size = BASE
	add_child(_frame)
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = BG
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(24)
	panel.add_theme_stylebox_override("panel", sb)
	panel.position = Vector2(110, 40)
	panel.size = Vector2(1060, 720)
	_frame.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)
	v.add_child(_label("Управление", 28, TEXT))

	# Камера: две строки — мышь и стик.
	var cam := GridContainer.new()
	cam.columns = 4
	cam.add_theme_constant_override("h_separation", 18)
	v.add_child(cam)
	_mouse = _slider(func(x): ProtoControls.mouse_sens = x; _save())
	_mouse_inv = _check(func(on): ProtoControls.mouse_invert_y = on; _save())
	_stick = _slider(func(x): ProtoControls.stick_sens = x; _save())
	_stick_inv = _check(func(on): ProtoControls.stick_invert_y = on; _save())
	cam.add_child(_label("Мышь: чувствительность", FONT, TEXT))
	cam.add_child(_mouse)
	_mouse_val = _value_label(_mouse)
	cam.add_child(_mouse_val)
	cam.add_child(_mouse_inv)
	cam.add_child(_label("Стик камеры: чувствительность", FONT, TEXT))
	cam.add_child(_stick)
	_stick_val = _value_label(_stick)
	cam.add_child(_stick_val)
	cam.add_child(_stick_inv)
	_first = _mouse

	# Кнопки: таблица в прокрутке.
	var head := HBoxContainer.new()
	head.add_child(_cell(_label("Действие", FONT_SMALL, DIM), 380))
	head.add_child(_cell(_label("Клавиатура", FONT_SMALL, DIM), 290))
	head.add_child(_cell(_label("Геймпад", FONT_SMALL, DIM), 290))
	v.add_child(head)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	v.add_child(scroll)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 4)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	for r in ProtoControls.REBIND:
		var a: StringName = r[0]
		var row := HBoxContainer.new()
		row.add_child(_cell(_label(r[1], FONT, TEXT), 380))
		var kb := _bind_button(func(): _start_wait(a, false))
		var pb := _bind_button(func(): _start_wait(a, true))
		row.add_child(kb)
		row.add_child(pb)
		list.add_child(row)
		_rows[a] = [kb, pb]

	_hint = _label("", FONT_SMALL, DIM)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_hint)
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 14)
	v.add_child(bottom)
	bottom.add_child(_button("Готово", close))
	bottom.add_child(_button("Сбросить всё", func(): ProtoControls.reset_defaults(); _save(); _refresh()))
	_cancel_wait()

func _refresh() -> void:
	if _mouse == null:
		return
	_mouse.set_value_no_signal(ProtoControls.mouse_sens)
	_stick.set_value_no_signal(ProtoControls.stick_sens)
	_mouse_val.text = "×%.2f" % _mouse.value
	_stick_val.text = "×%.2f" % _stick.value
	_mouse_inv.set_pressed_no_signal(ProtoControls.mouse_invert_y)
	_stick_inv.set_pressed_no_signal(ProtoControls.stick_invert_y)
	for a in _rows:
		if a == _wait_action:
			continue
		_rows[a][0].text = glyph(ProtoControls.binding(a, false))
		_rows[a][1].text = glyph(ProtoControls.binding(a, true))

func _save() -> void:
	ProtoControls.save_settings()

func _label_of(a: StringName) -> String:
	for r in ProtoControls.REBIND:
		if r[0] == a:
			return r[1]
	return String(a)

## Событие для кнопки ожидания (для тестов и скриптов): как нажатие.
func feed(e: InputEvent) -> void:
	if _wait_action != &"":
		_capture(e)

## Подпись события в ячейке: клавиша, кнопка или стик со стрелкой направления.
static func glyph(e: InputEvent) -> String:
	if e == null:
		return "—"
	if e is InputEventJoypadMotion:
		var arrow := ""
		match e.axis:
			JOY_AXIS_LEFT_X, JOY_AXIS_RIGHT_X: arrow = " →" if e.axis_value > 0.0 else " ←"
			JOY_AXIS_LEFT_Y, JOY_AXIS_RIGHT_Y: arrow = " ↓" if e.axis_value > 0.0 else " ↑"
		return ProtoHud._event_glyph(e, true) + arrow
	var g := ProtoHud._event_glyph(e, ProtoControls.is_pad(e))
	return g if g != "" else "?"

# ---------------------------------------------------------------- элементы

func _label(text: String, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	return l

func _cell(c: Control, w: float) -> Control:
	c.custom_minimum_size = Vector2(w, 0)
	return c

func _slider(f: Callable) -> HSlider:
	var s := HSlider.new()
	s.min_value = 0.2
	s.max_value = 3.0
	s.step = 0.05
	s.custom_minimum_size = Vector2(260, 32)
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.value_changed.connect(f)
	return s

func _value_label(s: HSlider) -> Label:
	var l := _label("", FONT, TEXT)
	l.custom_minimum_size = Vector2(70, 0)
	s.value_changed.connect(func(x): l.text = "×%.2f" % x)
	return l

func _check(f: Callable) -> CheckButton:
	var c := CheckButton.new()
	c.text = "Инверсия по вертикали"
	c.add_theme_font_size_override("font_size", FONT_SMALL)
	c.toggled.connect(f)
	return c

func _bind_button(f: Callable) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(280, 38)
	b.add_theme_font_size_override("font_size", FONT)
	b.pressed.connect(f)
	return b

func _button(text: String, f: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(200, 44)
	b.add_theme_font_size_override("font_size", FONT)
	b.pressed.connect(f)
	return b
