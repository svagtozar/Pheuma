class_name ProtoInventory
extends CanvasLayer
## Инвентарь робота в 3D (как рюкзак в Astroneer): что в грузе, сколько грунта
## в бункере, и ближайший бак или приёмник завода — перекладывать туда и обратно.
##   I / LB           — открыть и закрыть (в стройке LB — материал детали)
##   D-pad / стрелки   — выбрать строку, влево-вправо — груз или бак
##   A / Enter / клик  — переложить порцию целиком на другую сторону
##   X / R             — переложить 1 кг
##   Y / Delete        — выбросить из груза (строка грунта — высыпать бункер)
##   B / Esc / I       — закрыть
## Пока открыт, робот стоит (мета "ui_busy"), как у карты и карточки материала.
## Груз — robot.get_meta("cargo") (Array[Portion]); завод — ProtoPneumatics
## (view.net), клетки — по view.origin; грунт — ProtoDigger.soil.
## Логика перекладывания — статические функции: тесты зовут их без сцены.

const TOGGLE := &"inventory"
const REACH := 3.5                  # м до бака или приёмника — как выгрузка (ProtoBuilder.UNLOAD_R)
const CHUNK_KG := 1.0
const KINDS := ["tank", "intake"]   # откуда можно брать и куда класть
const ROWS_H := 360.0
const COL_W := 400.0

var robot: Node3D
var view: Object = null             # ProtoPneumaticsView: net и origin
var digger: Object = null           # ProtoDigger: soil, SOIL_MAX
var desk: Object = null             # ProtoLabDesk: «?N» у неизвестных веществ
var pad := false
var open := false
var note := ""

var _root: Control
var _dim: ColorRect
var _card: PanelContainer
var _cols: HBoxContainer
var _hint: HBoxContainer
var _note: Label
var _sig := ""
var _focus := ["cargo", 0]          # что было в фокусе: сторона и номер строки
var _mouse_mode := Input.MOUSE_MODE_VISIBLE
var _note_t := 0.0

static func layout() -> Dictionary:
	return {TOGGLE: [ProtoControls._key(KEY_I), ProtoControls._button(JOY_BUTTON_LEFT_SHOULDER)]}

static func ensure_actions() -> void:
	var lay := layout()
	for a in lay:
		if InputMap.has_action(a):
			continue
		InputMap.add_action(a, 0.5)
		for e in lay[a]:
			InputMap.action_add_event(a, e)

# ---------------------------------------------------------------- логика

## Ближайшая к точке деталь, из которой берут (бак, приёмник), в пределах r;
## null — рядом нет.
static func nearest_box(net: Object, origin: Vector3, at: Vector3, r := REACH) -> Variant:
	if net == null:
		return null
	var best = null
	var bd := r
	for c in net.parts:
		if not KINDS.has(net.parts[c].kind):
			continue
		var p := ProtoPneumatics.cell_pos(origin, c)
		var d := Vector2(p.x - at.x, p.z - at.z).length()
		if d <= bd:
			bd = d
			best = c
	return best

## Вместимость детали, кг (INF — без предела).
static func box_cap(net: Object, c: Vector2i) -> float:
	var kind: String = net.parts[c].kind
	return float(ProtoPneumatics.KINDS[kind].get("cap", INF))

## Порции одного вещества — в одну (после разборки деталей их бывает несколько).
static func compact(list: Array) -> void:
	var i := 0
	while i < list.size():
		var p: Portion = list[i]
		var j := i + 1
		while j < list.size():
			if list[j].substance == p.substance:
				p.absorb(list[j])
				list.remove_at(j)
			else:
				j += 1
		i += 1

## Положить порцию p в список: к той же, если есть.
static func add_to(list: Array, p: Portion) -> void:
	for q: Portion in list:
		if q.substance == p.substance:
			q.absorb(p)
			return
	list.append(p)

## Отделить от list[i] kg (не больше, чем там есть); пустая — уходит из списка.
static func take_from(list: Array, i: int, kg: float) -> Portion:
	if i < 0 or i >= list.size() or kg <= 0.0:
		return null
	var p: Portion = list[i]
	if kg >= p.mass - 0.001:
		list.remove_at(i)
		return p
	return p.split(kg)

## Из бака или приёмника — в груз. Возвращает, сколько кг взято.
static func take(net: Object, c: Vector2i, i: int, cargo: Array, kg := INF) -> float:
	if net == null or not net.parts.has(c):
		return 0.0
	var p := take_from(net.parts[c].items, i, kg)
	if p == null:
		return 0.0
	net.parts[c].status = ""
	add_to(cargo, p)
	return p.mass

## Из груза — в бак или приёмник (в бак — пока влезает). Сколько кг положено.
static func put(net: Object, c: Vector2i, i: int, cargo: Array, kg := INF) -> float:
	if net == null or not net.parts.has(c) or i < 0 or i >= cargo.size():
		return 0.0
	var room: float = box_cap(net, c) - float(net.mass_in(c))
	var m := minf(minf(kg, cargo[i].mass), room)
	if m <= 0.001:
		return 0.0
	var p := take_from(cargo, i, m)
	add_to(net.parts[c].items, p)
	return p.mass

# ---------------------------------------------------------------- сцена

func setup(r: Node3D, v: Object = null, d: Object = null) -> void:
	robot = r
	view = v
	digger = d
	pad = OS.has_feature("steamdeck") or not Input.get_connected_joypads().is_empty()
	ensure_actions()

func _ready() -> void:
	layer = 12                         # над HUD, окном рана и тостами (карта и меню — ещё выше)
	_dim = ColorRect.new()
	_dim.color = Color(0, 0, 0, 0.45)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.visible = false
	add_child(_dim)
	_root = Control.new()
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_card = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.06, 0.08, 0.97)
	sb.border_color = Color(0.45, 0.85, 1.0, 0.35)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(12)
	sb.set_content_margin_all(16)
	_card.add_theme_stylebox_override("panel", sb)
	_card.set_anchors_preset(Control.PRESET_CENTER)
	_card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_card.grow_vertical = Control.GROW_DIRECTION_BOTH
	_card.visible = false
	_root.add_child(_card)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	_card.add_child(box)
	box.add_child(_label("ИНВЕНТАРЬ", ProtoHud.FONT + 4, ProtoHud.TEXT))
	_cols = HBoxContainer.new()
	_cols.add_theme_constant_override("separation", 16)
	box.add_child(_cols)
	_note = _label("", ProtoHud.FONT_SMALL + 2, ProtoHud.WARN)
	_note.custom_minimum_size.y = 24
	box.add_child(_note)
	_hint = HBoxContainer.new()
	_hint.add_theme_constant_override("separation", 18)
	box.add_child(_hint)
	get_viewport().size_changed.connect(_fit)
	_fit()

func _fit() -> void:
	var vs := get_viewport().get_visible_rect().size
	var s := clampf(minf(vs.x / ProtoHud.BASE.x, vs.y / ProtoHud.BASE.y), 0.75, 2.0)
	_root.scale = Vector2(s, s)
	_root.size = vs / s

func cargo() -> Array:
	return ProtoMining.cargo_of(robot)

func net() -> Object:
	return view.net if view != null else null

## Клетка бака или приёмника рядом; null — нет.
func box_cell() -> Variant:
	if view == null or robot == null:
		return null
	return nearest_box(view.net, view.origin, robot.global_position)

func show_inventory() -> void:
	if open:
		return
	open = true
	compact(cargo())
	_mouse_mode = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	robot.set_meta("ui_busy", true)
	_focus = ["cargo", 0]
	_sig = ""
	_card.visible = true
	_dim.visible = true
	_refresh()

func close() -> void:
	if not open:
		return
	open = false
	_card.visible = false
	_dim.visible = false
	Input.mouse_mode = _mouse_mode
	robot.set_meta("ui_busy", false)
	var f := get_viewport().gui_get_focus_owner()
	if f != null and _card.is_ancestor_of(f):
		f.release_focus()

## Открыть можно, когда не открыто другое окно и не идёт стройка (там LB — материал).
func _can_open() -> bool:
	if robot == null or bool(robot.get_meta("ui_busy", false)) or bool(robot.get_meta("wrecked", false)):
		return false
	var pr := get_parent()
	var ru = pr.get("run_ui") if pr != null else null
	if ru != null and str(ru.get("modal")) != "":
		return false
	var b := pr.get_node_or_null("builder") if pr != null else null
	return b == null or not bool(b.get("active"))

func _input(e: InputEvent) -> void:
	if e is InputEventKey or e is InputEventMouseButton:
		pad = false
	elif e is InputEventJoypadButton or (e is InputEventJoypadMotion and absf(e.axis_value) > 0.5):
		pad = true
	if not e.is_pressed() or e.is_echo():
		return
	if not open:
		if e.is_action_pressed(TOGGLE) and _can_open():
			show_inventory()
			get_viewport().set_input_as_handled()
		return
	var key: Key = e.physical_keycode if e is InputEventKey else KEY_NONE
	var btn: JoyButton = e.button_index if e is InputEventJoypadButton else JOY_BUTTON_INVALID
	if e.is_action_pressed(TOGGLE) or e.is_action_pressed(&"ui_cancel") or btn == JOY_BUTTON_B:
		close()
	elif key == KEY_R or btn == JOY_BUTTON_X:
		act(_focused(), CHUNK_KG)
	elif key == KEY_DELETE or btn == JOY_BUTTON_Y:
		drop(_focused())
	else:
		return                        # стрелки и A — фокусу и кнопкам
	get_viewport().set_input_as_handled()

func _process(dt: float) -> void:
	_note_t = maxf(0.0, _note_t - dt)
	if not open:
		return
	if robot != null and not bool(robot.get_meta("ui_busy", false)):
		robot.set_meta("ui_busy", true)
	_refresh()

## Строка под фокусом: ["cargo" | "box" | "soil", номер] или [].
func _focused() -> Array:
	var f := get_viewport().gui_get_focus_owner()
	if f == null or not _card.is_ancestor_of(f) or not f.has_meta("row"):
		return []
	return f.get_meta("row")

## Переложить строку на другую сторону: kg — сколько (INF — всё).
func act(row: Array, kg := INF) -> void:
	if row.is_empty():
		return
	var c = box_cell()
	match row[0]:
		"soil":
			drop(row)
			return
		"cargo":
			if c == null:
				_say("Рядом нет бака или приёмника: подойдите к заводу")
				return
			var s: Substance = cargo()[row[1]].substance if row[1] < cargo().size() else null
			var m := put(net(), c, row[1], cargo(), kg)
			if m <= 0.0:
				_say("%s полон" % ProtoPneumatics.KINDS[net().parts[c].kind].n)
			elif s != null:
				_say("Положено %.1f кг %s" % [m, s.name])
		"box":
			if c == null:
				return
			var items: Array = net().parts[c].items
			var s: Substance = items[row[1]].substance if row[1] < items.size() else null
			var m := take(net(), c, row[1], cargo(), kg)
			if m > 0.0 and s != null:
				_say("Взято %.1f кг %s" % [m, s.name])
	_focus = row
	_sig = ""

## Выбросить из груза; строка грунта — высыпать весь бункер.
func drop(row: Array) -> void:
	if row.is_empty():
		return
	if row[0] == "soil":
		if digger != null and int(digger.soil) > 0:
			_say("Грунт высыпан: %d вёдер" % int(digger.soil))
			digger.soil = 0
	elif row[0] == "cargo" and row[1] < cargo().size():
		var p: Portion = cargo()[row[1]]
		cargo().remove_at(row[1])
		_say("Выброшено %.1f кг %s" % [p.mass, p.substance.name])
	_focus = row
	_sig = ""

func _say(s: String) -> void:
	note = s
	_note_t = 3.0
	_sig = ""

# ---------------------------------------------------------------- вид

func _refresh() -> void:
	var c = box_cell()
	var sig := [pad, c, int(digger.soil) if digger != null else -1, _note_t > 0.0, note]
	for p: Portion in cargo():
		sig.append([p.substance.id, snappedf(p.mass, 0.1)])
	if c != null:
		sig.append(net().parts[c].kind)
		for p: Portion in net().parts[c].items:
			sig.append([p.substance.id, snappedf(p.mass, 0.1)])
	var s := str(sig)
	if s == _sig:
		return
	_sig = s
	var keep := _focused()
	if not keep.is_empty():
		_focus = keep
	_build(c)

func _build(c: Variant) -> void:
	for ch in _cols.get_children():
		_cols.remove_child(ch)
		ch.queue_free()
	var buttons := {}                 # сторона → [Button]
	# Слева — груз робота и бункер грунта.
	var left := _column()
	var cg := cargo()
	var kg := 0.0
	for p: Portion in cg:
		kg += p.mass
	left.add_child(_head("Груз робота", "%.1f кг" % kg))
	var rows := _rows()
	left.add_child(rows.get_parent())
	buttons.cargo = []
	for i in cg.size():
		var b := _row(cg[i], ["cargo", i])
		rows.add_child(b)
		buttons.cargo.append(b)
	if cg.is_empty():
		rows.add_child(_label("Пусто: добудьте буром или возьмите из бака", ProtoHud.FONT_SMALL, ProtoHud.DIM))
	if digger != null:
		var sb := _soil_row()
		left.add_child(sb)
		buttons.soil = [sb]
	_cols.add_child(left)
	# Справа — бак или приёмник рядом.
	var right := _column()
	if c == null:
		right.add_child(_head("Контейнер", ""))
		var l := _label("Рядом нет бака или приёмника.\nПодойдите к заводу ближе чем на %.0f м." % REACH,
			ProtoHud.FONT_SMALL + 2, ProtoHud.DIM)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD
		right.add_child(l)
	else:
		var part: Dictionary = net().parts[c]
		var cap := box_cap(net(), c)
		var in_kg: float = net().mass_in(c)
		var sub := "%.1f кг" % in_kg if cap == INF else "%.1f / %.0f кг" % [in_kg, cap]
		right.add_child(_head("%s · %s" % [ProtoPneumatics.KINDS[part.kind].n, part.sub.name], sub))
		if cap != INF:
			right.add_child(_bar(in_kg / cap, ProtoHud.OK if in_kg < cap * 0.95 else ProtoHud.WARN))
		var rr := _rows()
		right.add_child(rr.get_parent())
		buttons.box = []
		for i in part.items.size():
			var b := _row(part.items[i], ["box", i])
			rr.add_child(b)
			buttons.box.append(b)
		if part.items.is_empty():
			rr.add_child(_label("Пусто", ProtoHud.FONT_SMALL, ProtoHud.DIM))
	_cols.add_child(right)
	_links(buttons)
	_hints(c != null)
	_note.text = note if _note_t > 0.0 else ""
	# Фокус — туда же, где был (строк могло стать меньше).
	var side: String = _focus[0]
	var list: Array = buttons.get(side, [])
	if list.is_empty():
		for k in ["cargo", "box", "soil"]:
			if not buttons.get(k, []).is_empty():
				list = buttons[k]
				break
	if not list.is_empty():
		list[clampi(int(_focus[1]), 0, list.size() - 1)].grab_focus.call_deferred()

## Соседи для D-pad: влево-вправо — на другую колонку, вниз из груза — в грунт.
func _links(buttons: Dictionary) -> void:
	var cargo_b: Array = buttons.get("cargo", [])
	var box_b: Array = buttons.get("box", [])
	var soil_b: Array = buttons.get("soil", [])
	var left_all: Array = cargo_b + soil_b
	for i in left_all.size():
		var b: Button = left_all[i]
		if not box_b.is_empty():
			b.focus_neighbor_right = box_b[mini(i, box_b.size() - 1)].get_path()
		b.focus_neighbor_left = b.get_path()
	for i in box_b.size():
		var b: Button = box_b[i]
		if not left_all.is_empty():
			b.focus_neighbor_left = left_all[mini(i, left_all.size() - 1)].get_path()
		b.focus_neighbor_right = b.get_path()
		if i == box_b.size() - 1:
			b.focus_neighbor_bottom = b.get_path()

func _hints(has_box: bool) -> void:
	for ch in _hint.get_children():
		_hint.remove_child(ch)
		ch.queue_free()
	var pairs := [["A" if pad else "Enter", "переложить всё" if has_box else "выбрать"],
		["X" if pad else "R", "по 1 кг"], ["Y" if pad else "Del", "выбросить"],
		["B" if pad else "Esc", "закрыть"]]
	if not has_box:
		pairs.remove_at(1)
	for p in pairs:
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 6)
		h.add_child(_chip(p[0]))
		h.add_child(_label(p[1], ProtoHud.FONT_SMALL, ProtoHud.DIM))
		_hint.add_child(h)

func _column() -> VBoxContainer:
	var v := VBoxContainer.new()
	v.custom_minimum_size.x = COL_W
	v.add_theme_constant_override("separation", 8)
	return v

func _rows() -> VBoxContainer:
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(COL_W, ROWS_H)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.follow_focus = true
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 4)
	sc.add_child(v)
	return v

func _head(t: String, sub: String) -> HBoxContainer:
	var h := HBoxContainer.new()
	var l := _label(t, ProtoHud.FONT + 2, ProtoHud.TEXT)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(l)
	h.add_child(_label(sub, ProtoHud.FONT, ProtoHud.DIM))
	return h

## Строка вещества: цвет, имя (с «?N», если не изучено), масса.
func _row(p: Portion, row: Array) -> Button:
	var name: String = desk.short_label(p.substance) if desk != null else p.substance.name
	var b := _button(row)
	var h := b.get_child(0) as HBoxContainer
	var sw := ColorRect.new()
	sw.color = p.substance.color
	sw.custom_minimum_size = Vector2(22, 22)
	sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sw.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(sw)
	var l := _label(name, ProtoHud.FONT, ProtoHud.TEXT)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.clip_text = true
	h.add_child(l)
	h.add_child(_label("%.1f кг" % p.mass, ProtoHud.FONT, ProtoHud.DIM))
	return b

## Бункер грунта: вёдра из SOIL_MAX; A или Y — высыпать.
func _soil_row() -> Button:
	var n := int(digger.soil)
	var mx := int(digger.SOIL_MAX)
	var b := _button(["soil", 0])
	b.custom_minimum_size.y = 64
	var h := b.get_child(0) as HBoxContainer
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", 4)
	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := _label("Бункер грунта", ProtoHud.FONT, ProtoHud.TEXT)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(l)
	var full := n >= mx
	top.add_child(_label("%d / %d вёдер%s" % [n, mx, " · полон" if full else ""], ProtoHud.FONT_SMALL + 2,
		ProtoHud.WARN if full else ProtoHud.DIM))
	v.add_child(top)
	v.add_child(_bar(float(n) / maxf(1.0, mx), ProtoHud.WARN if full else Color(0.72, 0.56, 0.38)))
	h.add_child(v)
	return b

func _button(row: Array) -> Button:
	var b := Button.new()
	b.set_meta("row", row)
	b.custom_minimum_size = Vector2(COL_W - 8, 44)
	b.focus_mode = Control.FOCUS_ALL
	for st in ["normal", "hover", "pressed", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(1, 1, 1, 0.04) if st == "normal" else Color(0.45, 0.85, 1.0, 0.16)
		if st == "focus":
			sb.bg_color = Color(0.45, 0.85, 1.0, 0.22)
			sb.border_color = Color(0.45, 0.85, 1.0, 0.9)
			sb.set_border_width_all(2)
		sb.set_corner_radius_all(8)
		sb.content_margin_left = 10
		sb.content_margin_right = 10
		b.add_theme_stylebox_override(st, sb)
	var h := HBoxContainer.new()
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_theme_constant_override("separation", 10)
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 10
	h.offset_right = -10
	b.add_child(h)
	b.pressed.connect(func(): act(row))
	return b

func _bar(frac: float, col: Color) -> Control:
	var bg := ColorRect.new()
	bg.color = Color(1, 1, 1, 0.1)
	bg.custom_minimum_size = Vector2(0, 8)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fg := ColorRect.new()
	fg.color = col
	fg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fg.anchor_bottom = 1.0
	fg.anchor_right = clampf(frac, 0.0, 1.0)
	bg.add_child(fg)
	return bg

func _label(t: String, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = t
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l

func _chip(t: String) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	var round := pad and ProtoHud.PAD_COLORS.has(t)
	sb.bg_color = ProtoHud.PAD_COLORS[t] if round else Color(0.22, 0.24, 0.28)
	sb.set_corner_radius_all(12 if round else 5)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 1
	sb.content_margin_bottom = 1
	p.add_theme_stylebox_override("panel", sb)
	p.add_child(_label(t, ProtoHud.FONT_SMALL, Color.WHITE))
	return p
