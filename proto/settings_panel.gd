class_name ProtoSettingsPanel
extends PanelContainer
## Экран настроек (главное меню и пауза): вкладки Управление, Графика, Звук.
## LB/RB или Q/E — соседняя вкладка, B / Esc — назад (сигнал closed).
## Вкладка «Управление» — список кнопок из InputMap и вход в экран
## ProtoControlsMenu (переназначение, чувствительность, инверсия), если он есть.
## Всё применяется и сохраняется сразу (ProtoSettings).

signal closed

const TABS := ["Управление", "Графика", "Звук"]
const CONTROLS_MENU := &"ProtoControlsMenu"

var tab := 0
var _tabs: Array = []
var _body: VBoxContainer
var _page: Control

func _ready() -> void:
	theme = ProtoUi.theme()
	custom_minimum_size = Vector2(860, 600)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 18)
	add_child(v)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	v.add_child(head)
	head.add_child(_hint_chip("LB"))
	for i in TABS.size():
		var b := ProtoUi.button(TABS[i], show_tab.bind(i))
		b.custom_minimum_size = Vector2(220, 50)
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE     # вкладки — LB/RB, фокус остаётся в странице
		head.add_child(b)
		_tabs.append(b)
	head.add_child(_hint_chip("RB"))
	_body = VBoxContainer.new()
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(_body)
	var foot := HBoxContainer.new()
	foot.alignment = BoxContainer.ALIGNMENT_END
	v.add_child(foot)
	var back := ProtoUi.button("Назад", func(): closed.emit())
	back.custom_minimum_size = Vector2(200, 50)
	back.name = "back"
	foot.add_child(back)
	show_tab(tab)

func _hint_chip(t: String) -> Label:
	var l := ProtoUi.label(t, ProtoUi.FONT_SMALL, ProtoUi.DIM)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return l

func show_tab(i: int) -> void:
	tab = wrapi(i, 0, TABS.size())
	for k in _tabs.size():
		_tabs[k].button_pressed = k == tab
	if _page != null:
		_page.queue_free()
		_body.remove_child(_page)
	match tab:
		0: _page = _controls_page()
		1: _page = _graphics_page()
		_: _page = _audio_page()
	_page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_child(_page)
	focus_first.call_deferred()

func focus_first() -> void:
	if not is_inside_tree():
		return
	var f := ProtoUi.first_focusable(_page)
	if f == null:
		f = get_node_or_null("back") as Control
	if f == null:
		f = find_child("back", true, false) as Control
	if f != null:
		f.grab_focus()

func _input(e: InputEvent) -> void:
	if not is_visible_in_tree() or not e.is_pressed() or e.is_echo():
		return
	var prev: bool = (e is InputEventJoypadButton and e.button_index == JOY_BUTTON_LEFT_SHOULDER) \
		or (e is InputEventKey and e.physical_keycode == KEY_Q)
	var next: bool = (e is InputEventJoypadButton and e.button_index == JOY_BUTTON_RIGHT_SHOULDER) \
		or (e is InputEventKey and e.physical_keycode == KEY_E)
	if is_capturing():
		return                      # поверх открыт экран «Управление»
	if prev or next:
		show_tab(tab + (1 if next else -1))
		get_viewport().set_input_as_handled()
	elif _is_back(e):
		closed.emit()
		get_viewport().set_input_as_handled()

static func _is_back(e: InputEvent) -> bool:
	return (e is InputEventKey and e.physical_keycode == KEY_ESCAPE) \
		or (e is InputEventJoypadButton and e.button_index == JOY_BUTTON_B)

# ---------------------------------------------------------------- страницы

func _controls_page() -> Control:
	var v := _page_box()
	var menu := _controls_menu_class()
	if menu != null:
		var b := ProtoUi.button("Кнопки, чувствительность, инверсия…", _open_controls_menu.bind(menu))
		b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		b.custom_minimum_size.x = 520
		v.add_child(b)
	v.add_child(ProtoUi.label("Кнопки", ProtoUi.FONT, ProtoUi.DIM))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 36)
	grid.add_theme_constant_override("v_separation", 4)
	for h in binding_rows():
		grid.add_child(ProtoUi.label(h[0]))
		grid.add_child(ProtoUi.label(h[1], ProtoUi.FONT_BODY, ProtoUi.ACCENT))
		grid.add_child(ProtoUi.label(h[2], ProtoUi.FONT_BODY, ProtoUi.ACCENT))
	v.add_child(grid)
	return _scroll(v)

## Экран «Управление» (переназначение, чувствительность, инверсия), если он уже
## есть в проекте: открывается поверх настроек, по закрытии фокус возвращается.
func _controls_menu_class() -> Script:
	for c in ProjectSettings.get_global_class_list():
		if c["class"] == CONTROLS_MENU:
			return load(c.path)
	return null

var _controls_overlay: Node

func _open_controls_menu(s: Script) -> void:
	if _controls_overlay == null:
		_controls_overlay = s.new()
		_controls_overlay.set("pause_tree", false)     # пауза уже своя (меню или пауза игры)
		add_child(_controls_overlay)
		_controls_overlay.connect("closed", func():
			show_tab(0))
	_controls_overlay.call("open")

func is_capturing() -> bool:
	return _controls_overlay != null and bool(_controls_overlay.call("is_open"))

## Строки таблицы кнопок: [подпись, клавиша, кнопка геймпада].
static func binding_rows() -> Array:
	var rows: Array = []
	for h in ProtoHud.HINTS_WALK + ProtoHud.HINTS_BUILD.slice(0, 5):
		var acts: Array = h.slice(1)
		var k := ProtoHud.glyph(acts, false)
		var p := ProtoHud.glyph(acts, true)
		if k != "" or p != "":
			rows.append([h[0], k, p])
	rows.append(["Пауза", "Esc", "Menu"])
	return rows

func _graphics_page() -> Control:
	var v := _page_box()
	var g := func(key): return ProtoSettings.get_value("graphics", key)
	var s := func(key): return func(x): ProtoSettings.set_value("graphics", key, x)
	v.add_child(ProtoUi.row("Во весь экран", ProtoUi.toggle(g.call("fullscreen"), s.call("fullscreen"))))
	v.add_child(ProtoUi.row("Вертикальная синхронизация", ProtoUi.toggle(g.call("vsync"), s.call("vsync"))))
	v.add_child(ProtoUi.row("Разрешение 3D", ProtoUi.slider(g.call("render_scale"), 0.5, 1.0, 0.05,
		func(x): return "%d%%" % roundi(x * 100.0), s.call("render_scale"))))
	v.add_child(ProtoUi.row("Тени", ProtoUi.toggle(g.call("shadows"), s.call("shadows"))))
	v.add_child(ProtoUi.row("Счётчик кадров", ProtoUi.toggle(g.call("show_fps"), s.call("show_fps"))))
	v.add_child(ProtoUi.label("Меньше разрешение 3D и без теней — выше FPS на Steam Deck.", ProtoUi.FONT_SMALL, ProtoUi.DIM))
	return v

func _audio_page() -> Control:
	var v := _page_box()
	var pct := func(x): return "%d%%" % roundi(x * 100.0)
	v.add_child(ProtoUi.row("Общая громкость", ProtoUi.slider(ProtoSettings.get_value("audio", "master"), 0.0, 1.0, 0.05,
		pct, func(x): ProtoSettings.set_value("audio", "master", x))))
	v.add_child(ProtoUi.row("Звуки мира", ProtoUi.slider(ProtoSettings.get_value("audio", "world"), 0.0, 1.0, 0.05,
		pct, func(x): ProtoSettings.set_value("audio", "world", x))))
	v.add_child(ProtoUi.row("Без звука", ProtoUi.toggle(ProtoSettings.get_value("audio", "mute"),
		func(on): ProtoSettings.set_value("audio", "mute", on))))
	return v

func _page_box() -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	return v

func _scroll(c: Control) -> ScrollContainer:
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.follow_focus = true
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(c)
	return sc
