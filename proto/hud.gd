class_name ProtoHud
extends CanvasLayer
## HUD 3D-прототипа: груз робота, состояние пневмозавода, деталь в режиме
## стройки и подсказки кнопок. Подсказки берутся из InputMap и сами
## переключаются между клавиатурой и геймпадом по последнему нажатию.
## Размеры рассчитаны на Steam Deck (1280×800); на большем экране всё
## масштабируется целиком.
## Источники данных «утиные», чтобы HUD жил и без пневматики, и без бура:
##   robot.get_meta("cargo")        — Array[Portion], груз робота
##   factory: pressure/max_p/parts  — ProtoPneumatics (если есть)
##   builder: active/kind()/material()/note — ProtoBuilder (если есть)

const BASE := Vector2(1280, 800)
const PAD := 16.0
const FONT := 20
const FONT_SMALL := 16
const CARGO_ROWS := 4
const DANGER := 0.85             # доля предела давления, с которой завод «у предела»

const BG := Color(0.06, 0.07, 0.09, 0.72)
const EDGE := Color(1, 1, 1, 0.08)
const TEXT := Color(0.93, 0.94, 0.95)
const DIM := Color(0.66, 0.69, 0.73)
const OK := Color(0.45, 0.82, 0.5)
const WARN := Color(0.98, 0.76, 0.3)
const BAD := Color(0.97, 0.38, 0.33)

## Цвета кнопок геймпада (Xbox, как и раскладка в ProtoControls).
const PAD_COLORS := {"A": Color(0.33, 0.66, 0.2), "B": Color(0.78, 0.2, 0.18),
	"X": Color(0.16, 0.42, 0.8), "Y": Color(0.8, 0.62, 0.1)}

## Подсказки: [подпись, действия...]. Несуществующие действия пропускаются.
const HINTS_WALK := [
	["Ходьба", &"move_forward", &"move_left", &"move_back", &"move_right"],
	["Камера", &"cam_left", &"cam_right", &"cam_up", &"cam_down"],
	["Бур", &"tool_work"],
	["Кисть", &"fist_fire"],
	["Стройка", &"build_mode"],
	["Меню", &"run_menu"],
]
const HINTS_BUILD := [
	["Деталь", &"build_prev", &"build_next"],
	["Повернуть", &"build_rotate"],
	["Материал", &"build_material"],
	["Поставить", &"build_place"],
	["Разобрать", &"build_remove"],
	["Выйти из стройки", &"build_mode"],
]
const UNLOAD := &"cargo_unload"

var robot: Node3D
var factory: Object              # ProtoPneumatics или null
var builder: Object              # ProtoBuilder или null
var pad := false                 # подсказки для геймпада
var extra_hints: Array = []      # [[подпись, клавиша, кнопка]] — вне InputMap (сборка для проверки)

var _root: Control
var _cargo_box: VBoxContainer
var _cargo_title: Label
var _factory_panel: PanelContainer
var _factory_box: VBoxContainer
var _build_panel: PanelContainer
var _build_box: VBoxContainer
var _hints_box: VBoxContainer
var _toast: Label
var _key := ""                   # что сейчас нарисовано — перестраиваем только при изменении

func setup(r: Node3D) -> void:
	robot = r
	pad = OS.has_feature("steamdeck") or not Input.get_connected_joypads().is_empty()

func _ready() -> void:
	layer = 5
	_root = Control.new()
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	var cargo := _panel()
	_cargo_box = cargo.get_child(0)
	_cargo_title = _label("", FONT, TEXT)
	_root.add_child(cargo)
	cargo.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	cargo.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_factory_panel = _panel()
	_factory_box = _factory_panel.get_child(0)
	_root.add_child(_factory_panel)
	_factory_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_factory_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_factory_panel.custom_minimum_size.x = 300
	_build_panel = _panel()
	_build_box = _build_panel.get_child(0)
	_root.add_child(_build_panel)
	_build_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_build_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_build_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	var hints := _panel()
	_hints_box = hints.get_child(0)
	_root.add_child(hints)
	hints.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	hints.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	hints.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_toast = _label("", FONT + 2, TEXT)
	_toast.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root.add_child(_toast)
	for p in [cargo, _factory_panel, hints]:
		_margins(p)
	get_viewport().size_changed.connect(_fit)
	_fit()

## Масштаб под экран: 1280×800 — один к одному, больше — крупнее, меньше — мельче.
func _fit() -> void:
	var vs := get_viewport().get_visible_rect().size
	var s := clampf(minf(vs.x / BASE.x, vs.y / BASE.y), 0.75, 2.0)
	_root.scale = Vector2(s, s)
	_root.size = vs / s

func _margins(c: Control) -> void:
	# Отступ от края экрана: у якорных панелей смещения задаются вручную.
	var right := c.anchor_left >= 1.0
	var bottom := c.anchor_top >= 1.0
	c.offset_left = -PAD if right else PAD
	c.offset_right = -PAD if right else PAD
	c.offset_top = -PAD if bottom else PAD
	c.offset_bottom = -PAD if bottom else PAD

func _input(e: InputEvent) -> void:
	if e is InputEventKey or e is InputEventMouseButton:
		pad = false
	elif e is InputEventJoypadButton or (e is InputEventJoypadMotion and absf(e.axis_value) > 0.5):
		pad = true

func _process(_dt: float) -> void:
	if builder == null:
		builder = get_parent().get_node_or_null("builder") if get_parent() else null
		if builder != null and builder.get("hud") is Control:
			builder.hud.visible = false       # у стройки своя строка-подсказка; её заменяет HUD
	if factory == null and get_parent() != null:
		factory = get_parent().get("pneu")
	refresh()

## Перерисовывает панели, если что-то поменялось.
func refresh() -> void:
	var cg := cargo_summary(_cargo())
	var fs := factory_summary(factory)
	var building: bool = builder != null and bool(builder.get("active"))
	var part := _part_info() if building else {}
	var note: String = builder.note if builder != null and float(builder.get("_note_t")) > 0.0 else ""
	var key := str([cg, fs, part, note, pad, building])
	if key == _key:
		return
	_key = key
	_fill_cargo(cg)
	_fill_factory(fs)
	_fill_build(part)
	_fill_hints(building, cg.kg > 0.0)
	_toast.text = note
	_toast.offset_bottom = -PAD - (_build_panel.size.y + 12.0 if building else 12.0)

func _cargo() -> Array:
	if robot == null or not robot.has_meta("cargo"):
		return []
	return robot.get_meta("cargo")

# ---------------------------------------------------------------- данные

## Груз по веществам: {kg, rows: [{name, kg, color}]}, самые тяжёлые — первыми.
static func cargo_summary(cargo: Array) -> Dictionary:
	var by := {}
	var total := 0.0
	for p in cargo:
		if p == null or p.substance == null:
			continue
		total += p.mass
		var n: String = p.substance.name
		if not by.has(n):
			by[n] = {"name": n, "kg": 0.0, "color": p.substance.color}
		by[n].kg += p.mass
	var rows: Array = by.values()
	rows.sort_custom(func(a, b): return a.kg > b.kg)
	return {"kg": total, "rows": rows}

## Состояние завода: {built, parts, pumps, p, max_p, load, state, tone, stored}.
## load — самая нагруженная деталь (давление / предел её материала);
## tone — "ok" | "warn" | "bad" | "idle".
static func factory_summary(net: Object) -> Dictionary:
	var out := {"built": false, "parts": 0, "pumps": 0, "p": 0.0, "max_p": 0.0, "load": 0.0,
		"state": "не построен", "tone": "idle", "stored": 0.0}
	if net == null or not ("parts" in net):
		return out
	var parts: Dictionary = net.parts
	out.parts = parts.size()
	if parts.is_empty():
		return out
	out.built = true
	var working := false
	var starved := false
	for c in parts:
		var part: Dictionary = parts[c]
		if part.kind == "pump":
			out.pumps += 1
		if part.kind == "tank":
			out.stored += net.mass_in(c)
		var mp: float = net.max_p(c)
		var pr: float = net.pressure(c)
		if mp > 0.0 and pr / mp >= out.load:
			out.load = pr / mp
			out.p = pr
			out.max_p = mp
		var st: String = part.get("status", "")
		if st.begins_with("работает"):
			working = true
		elif st.begins_with("мало давления"):
			starved = true
	if out.load >= DANGER:
		out.state = "давление у предела"
		out.tone = "bad"
	elif out.pumps == 0:
		out.state = "нет насоса"
		out.tone = "warn"
	elif starved:
		out.state = "мало давления"
		out.tone = "warn"
	elif working:
		out.state = "работает"
		out.tone = "ok"
	else:
		out.state = "ждёт груз"
		out.tone = "idle"
	return out

func _part_info() -> Dictionary:
	var kind: String = builder.kind()
	var sub = builder.material()
	var consts := _net_consts()
	var info: Dictionary = consts.get("KINDS", {}).get(kind, {})
	var order: Array = consts.get("ORDER", [])
	var limit := 0.0
	if info.has("stat") and sub != null:
		limit = ComponentStats.compute(info.stat, sub).max_p
	return {"name": info.get("n", kind), "mat": sub.name if sub != null else "",
		"mat_color": sub.color if sub != null else Color.GRAY, "limit": limit,
		"i": order.find(kind) + 1, "n": order.size()}

## Константы скрипта завода (KINDS, ORDER) — без прямой ссылки на класс.
func _net_consts() -> Dictionary:
	var net = factory
	if net == null and builder.get("view") != null:
		net = builder.view.get("net")
	if net == null or net.get_script() == null:
		return {}
	return net.get_script().get_script_constant_map()

# ---------------------------------------------------------------- кнопки

## Подпись клавиши или кнопки для действия (или группы действий, как ходьба).
static func glyph(actions: Array, for_pad: bool) -> String:
	var parts: Array = []
	for a in actions:
		if not InputMap.has_action(a):
			continue
		for e in InputMap.action_get_events(a):
			var g := _event_glyph(e, for_pad)
			if g != "" and not parts.has(g):
				parts.append(g)
			if g != "":
				break
	if parts.is_empty():
		return ""
	if parts.size() >= 3 and parts.all(func(g): return g.length() == 1):
		return "".join(PackedStringArray(parts))       # W A S D → WASD
	return " ".join(PackedStringArray(parts))

static func _event_glyph(e: InputEvent, for_pad: bool) -> String:
	if not for_pad and e is InputEventKey:
		var code: Key = e.physical_keycode if e.physical_keycode != KEY_NONE else e.keycode
		match code:
			KEY_SPACE: return "Пробел"
			KEY_SHIFT: return "Shift"
			KEY_TAB: return "Tab"
			KEY_ESCAPE: return "Esc"
		return OS.get_keycode_string(code)
	if for_pad and e is InputEventJoypadButton:
		match e.button_index:
			JOY_BUTTON_A: return "A"
			JOY_BUTTON_B: return "B"
			JOY_BUTTON_X: return "X"
			JOY_BUTTON_Y: return "Y"
			JOY_BUTTON_LEFT_SHOULDER: return "LB"
			JOY_BUTTON_RIGHT_SHOULDER: return "RB"
			JOY_BUTTON_LEFT_STICK: return "L3"
			JOY_BUTTON_RIGHT_STICK: return "R3"
			JOY_BUTTON_BACK: return "View"
			JOY_BUTTON_START: return "Menu"
			JOY_BUTTON_DPAD_UP: return "↑"
			JOY_BUTTON_DPAD_DOWN: return "↓"
			JOY_BUTTON_DPAD_LEFT: return "←"
			JOY_BUTTON_DPAD_RIGHT: return "→"
	if for_pad and e is InputEventJoypadMotion:
		match e.axis:
			JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y: return "L-стик"
			JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y: return "R-стик"
			JOY_AXIS_TRIGGER_LEFT: return "LT"
			JOY_AXIS_TRIGGER_RIGHT: return "RT"
	return ""

## Строки подсказок для текущего режима: [[подпись, клавиша]].
func hint_rows(building: bool, has_cargo: bool) -> Array:
	var rows: Array = []
	for h in (HINTS_BUILD if building else HINTS_WALK):
		var g := glyph(h.slice(1), pad)
		if g != "":
			rows.append([h[0], g])
	if has_cargo and not building:
		var g := glyph([UNLOAD], pad)
		if g != "":
			rows.append(["Выгрузить в приёмник", g])
	for h in extra_hints:
		rows.append([h[0], h[2] if pad else h[1]])
	return rows

# ---------------------------------------------------------------- панели

func _fill_cargo(cg: Dictionary) -> void:
	_clear(_cargo_box)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	head.add_child(_label("ГРУЗ", FONT_SMALL, DIM))
	head.add_child(_label("%.1f кг" % cg.kg if cg.kg > 0.0 else "пусто", FONT, TEXT))
	_cargo_box.add_child(head)
	var rows: Array = cg.rows
	for i in mini(rows.size(), CARGO_ROWS):
		var r: Dictionary = rows[i]
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 8)
		var sw := ColorRect.new()
		sw.color = r.color
		sw.custom_minimum_size = Vector2(14, 14)
		sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		line.add_child(sw)
		var nm := _label(r.name, FONT_SMALL, TEXT)
		nm.custom_minimum_size.x = 150
		line.add_child(nm)
		line.add_child(_label("%.1f кг" % r.kg, FONT_SMALL, DIM))
		_cargo_box.add_child(line)
	if rows.size() > CARGO_ROWS:
		_cargo_box.add_child(_label("и ещё %d" % (rows.size() - CARGO_ROWS), FONT_SMALL, DIM))

func _fill_factory(fs: Dictionary) -> void:
	_factory_panel.visible = fs.built
	if not fs.built:
		return
	_clear(_factory_box)
	var tone: Color = {"ok": OK, "warn": WARN, "bad": BAD}.get(fs.tone, DIM)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	head.add_child(_label("ЗАВОД", FONT_SMALL, DIM))
	var st := _label(fs.state, FONT, tone)
	st.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	st.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	head.add_child(st)
	_factory_box.add_child(head)
	_factory_box.add_child(_gauge(fs.load, tone))
	_factory_box.add_child(_label("%.1f атм из %.1f" % [fs.p, fs.max_p], FONT, TEXT))
	var info := "деталей %d · насосов %d" % [fs.parts, fs.pumps]
	if fs.stored > 0.0:
		info += " · в баках %.0f кг" % fs.stored
	_factory_box.add_child(_label(info, FONT_SMALL, DIM))

## Полоса давления: заливка — доля предела, риска — порог опасности.
func _gauge(v: float, tone: Color) -> Control:
	var bar := Control.new()
	bar.custom_minimum_size = Vector2(268, 12)
	bar.draw.connect(func():
		var r := Rect2(Vector2.ZERO, bar.size)
		bar.draw_rect(r, Color(1, 1, 1, 0.12))
		bar.draw_rect(Rect2(r.position, Vector2(r.size.x * clampf(v, 0.0, 1.0), r.size.y)), tone)
		var x := r.size.x * DANGER
		bar.draw_line(Vector2(x, -3), Vector2(x, r.size.y + 3), BAD, 2.0))
	return bar

func _fill_build(part: Dictionary) -> void:
	_build_panel.visible = not part.is_empty()
	if part.is_empty():
		return
	_clear(_build_box)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	head.alignment = BoxContainer.ALIGNMENT_CENTER
	var prev := glyph([&"build_prev"], pad)
	var next := glyph([&"build_next"], pad)
	if prev != "":
		head.add_child(_chip(prev))
	var nm := _label(part.name, FONT + 6, TEXT)
	head.add_child(nm)
	if next != "":
		head.add_child(_chip(next))
	_build_box.add_child(head)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 8)
	line.alignment = BoxContainer.ALIGNMENT_CENTER
	var sw := ColorRect.new()
	sw.color = part.mat_color
	sw.custom_minimum_size = Vector2(14, 14)
	sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(sw)
	var txt: String = part.mat
	if part.limit > 0.0:
		txt += " · держит %.1f атм" % part.limit
	line.add_child(_label(txt, FONT_SMALL, DIM))
	_build_box.add_child(line)
	if part.n > 0:
		var pos := _label("СТРОЙКА · деталь %d из %d" % [part.i, part.n], FONT_SMALL, DIM)
		pos.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_build_box.add_child(pos)
	_build_panel.reset_size()
	_build_panel.offset_top = -PAD - _build_panel.get_combined_minimum_size().y
	_build_panel.offset_bottom = -PAD

func _fill_hints(building: bool, has_cargo: bool) -> void:
	_clear(_hints_box)
	for r in hint_rows(building, has_cargo):
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 10)
		var chips := HBoxContainer.new()
		chips.add_theme_constant_override("separation", 4)
		chips.custom_minimum_size.x = 96
		chips.alignment = BoxContainer.ALIGNMENT_END
		for g in r[1].split(" "):
			chips.add_child(_chip(g))
		line.add_child(chips)
		line.add_child(_label(r[0], FONT_SMALL + 2, TEXT))
		_hints_box.add_child(line)

# ---------------------------------------------------------------- виджеты

func _panel() -> PanelContainer:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = BG
	sb.border_color = EDGE
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	p.add_theme_stylebox_override("panel", sb)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	p.add_child(box)
	return p

func _label(t: String, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("outline_size", 4)
	return l

## Клавиша или кнопка: скруглённая плашка; A/B/X/Y — круглые в цветах Xbox.
func _chip(t: String) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	var round := pad and PAD_COLORS.has(t)       # на клавиатуре X и B — просто клавиши
	sb.bg_color = PAD_COLORS[t] if round else Color(0.22, 0.24, 0.28)
	sb.border_color = Color(1, 1, 1, 0.35)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(14 if round else 6)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 1
	sb.content_margin_bottom = 1
	p.add_theme_stylebox_override("panel", sb)
	p.custom_minimum_size = Vector2(28, 28)
	var l := _label(t, FONT_SMALL, Color.WHITE)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	p.add_child(l)
	return p

func _clear(c: Node) -> void:
	for ch in c.get_children():
		c.remove_child(ch)
		ch.queue_free()
