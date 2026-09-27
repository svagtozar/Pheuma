class_name ProtoUi
extends RefCounted
## Общий вид меню 3D-прототипа (главное меню, пауза, настройки): тема с
## крупными кнопками под Steam Deck (1280×800), рамка фокуса для геймпада,
## масштаб под экран — как у HUD (ProtoHud.BASE).

const FONT := 24
const FONT_BODY := 20
const FONT_SMALL := 17
const ACCENT := Color(0.45, 0.9, 1.0)
const TEXT := ProtoHud.TEXT
const DIM := ProtoHud.DIM
const PANEL := Color(0.06, 0.07, 0.09, 0.9)

static var _theme: Theme

## Тема: кнопки, переключатели, ползунки и подписи в одном стиле.
static func theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	t.default_font_size = FONT_BODY
	var n := _box(Color(0.16, 0.18, 0.22, 0.95))
	var hov := _box(Color(0.21, 0.24, 0.29, 0.97))
	var foc := _box(Color(0.2, 0.36, 0.46, 0.98))
	foc.border_color = ACCENT
	foc.set_border_width_all(3)
	var dis := _box(Color(0.12, 0.12, 0.14, 0.8))
	for cls in ["Button", "CheckButton"]:
		t.set_stylebox("normal", cls, n)
		t.set_stylebox("hover", cls, hov)
		t.set_stylebox("pressed", cls, foc if cls == "Button" else n)
		t.set_stylebox("hover_pressed", cls, hov)
		t.set_stylebox("focus", cls, foc)
		t.set_stylebox("disabled", cls, dis)
		t.set_color("font_color", cls, TEXT)
		t.set_color("font_hover_color", cls, Color.WHITE)
		t.set_color("font_focus_color", cls, Color.WHITE)
		t.set_color("font_pressed_color", cls, Color.WHITE)
		t.set_color("font_hover_pressed_color", cls, Color.WHITE)
		t.set_color("font_disabled_color", cls, Color(0.45, 0.47, 0.5))
		t.set_font_size("font_size", cls, FONT)
	# Вкладка выбрана — подсвечена и без фокуса.
	t.set_stylebox("pressed", "Button", _box(Color(0.2, 0.42, 0.55, 0.95)))
	t.set_color("font_color", "Label", TEXT)
	var slider := StyleBoxFlat.new()
	slider.bg_color = Color(0.25, 0.27, 0.31)
	slider.content_margin_top = 4
	slider.content_margin_bottom = 4
	slider.set_corner_radius_all(4)
	var filled := slider.duplicate()
	filled.bg_color = ACCENT.darkened(0.25)
	var sfoc := StyleBoxFlat.new()
	sfoc.draw_center = false
	sfoc.border_color = ACCENT
	sfoc.set_border_width_all(3)
	sfoc.set_corner_radius_all(6)
	sfoc.expand_margin_top = 8
	sfoc.expand_margin_bottom = 8
	sfoc.expand_margin_left = 6
	sfoc.expand_margin_right = 6
	t.set_stylebox("slider", "HSlider", slider)
	t.set_stylebox("grabber_area", "HSlider", filled)
	t.set_stylebox("grabber_area_highlight", "HSlider", filled)
	t.set_stylebox("focus", "HSlider", sfoc)
	var pc := StyleBoxFlat.new()
	pc.bg_color = PANEL
	pc.border_color = Color(1, 1, 1, 0.08)
	pc.set_border_width_all(1)
	pc.set_corner_radius_all(10)
	pc.set_content_margin_all(24)
	t.set_stylebox("panel", "PanelContainer", pc)
	_theme = t
	return t

static func _box(c: Color) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = c
	b.set_corner_radius_all(8)
	b.content_margin_left = 20
	b.content_margin_right = 20
	b.content_margin_top = 8
	b.content_margin_bottom = 8
	return b

## Корень меню во весь экран, масштаб как у HUD: 1280×800 — один к одному.
static func root(layer: Node) -> Control:
	var r := Control.new()
	r.theme = theme()
	r.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(r)
	var fit := func():
		var vs := r.get_viewport().get_visible_rect().size
		var s := clampf(minf(vs.x / ProtoHud.BASE.x, vs.y / ProtoHud.BASE.y), 0.75, 2.0)
		r.scale = Vector2(s, s)
		r.size = vs / s
	r.get_viewport().size_changed.connect(fit)
	fit.call()
	return r

static func label(t: String, size := FONT_BODY, col := TEXT) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	return l

static func button(t: String, cb: Callable = Callable()) -> Button:
	var b := Button.new()
	b.text = t
	b.custom_minimum_size = Vector2(360, 54)
	b.focus_mode = Control.FOCUS_ALL
	if cb.is_valid():
		b.pressed.connect(cb)
	return b

## Строка настройки: подпись слева, элемент справа.
static func row(caption: String, ctl: Control) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 24)
	var l := label(caption)
	l.custom_minimum_size.x = 300
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(l)
	ctl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(ctl)
	return h

## Переключатель да/нет.
static func toggle(on: bool, cb: Callable) -> CheckButton:
	var c := CheckButton.new()
	c.button_pressed = on
	c.text = "Вкл" if on else "Выкл"
	c.custom_minimum_size.y = 50
	c.focus_mode = Control.FOCUS_ALL
	c.toggled.connect(func(v: bool):
		c.text = "Вкл" if v else "Выкл"
		cb.call(v))
	return c

## Ползунок с числом справа; fmt — как показать значение.
static func slider(v: float, lo: float, hi: float, step: float, fmt: Callable, cb: Callable) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 16)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = v
	s.custom_minimum_size = Vector2(320, 44)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.focus_mode = Control.FOCUS_ALL
	var l := label(fmt.call(v))
	l.custom_minimum_size.x = 90
	s.value_changed.connect(func(x: float):
		l.text = fmt.call(x)
		cb.call(x))
	h.add_child(s)
	h.add_child(l)
	return h

## Первый элемент под n, который может взять фокус.
static func first_focusable(n: Node) -> Control:
	for c in n.find_children("*", "Control", true, false):
		var ctl := c as Control
		if ctl.focus_mode == Control.FOCUS_ALL and ctl.is_visible_in_tree() and not (ctl is BaseButton and ctl.disabled):
			return ctl
	return null
