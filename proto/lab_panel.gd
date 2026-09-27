class_name ProtoLabPanel
extends CanvasLayer
## Карточка материала в 3D (прототип и F3 в игре): касание, пять проб, догадки
## и их проверка — поверх ProtoLabDesk. Всё делается с геймпада:
##   B / Z        — коснуться того, что рядом, и открыть карточку
##   D-pad / ←→↑↓ — выбрать кнопку, A / Enter — нажать
##   LB RB / PgUp PgDn — другой образец (друза, машина, груз)
##   B / Esc / Z  — закрыть
##   RB / V       — анализатор (при закрытой карточке): по тегу у всего рядом
## Пока карточка открыта, робот стоит (мета "ui_busy" на узле робота).
## Сверху по центру — лента находок: новые теги, верные догадки, опознания.
## Размеры — под Steam Deck 1280×800, как у ProtoHud.

const TOUCH := &"lab_touch"
const ANALYZE := &"lab_analyze"
const PREV := &"lab_prev"
const NEXT := &"lab_next"
const CLOSE := &"lab_close"

const FONT := ProtoHud.FONT
const SMALL := ProtoHud.FONT_SMALL
const WIDTH := 700.0
const MAX_GUESS_TAGS := 10
const FEED_SEC := 5.0
const FEED_W := 520.0

const WHERE := {"druse": "друза рядом", "part": "в машине", "cargo": "в грузе",
	"deposit": "залежь рядом", "inventory": "в инвентаре"}

var desk: ProtoLabDesk
var robot: Node3D = null         # кому ставить "ui_busy"
var builder: Object = null       # ProtoBuilder: в режиме стройки карточка закрыта
var focus_cell = null            # игра: клетка под курсором (залежь — первой)
var pad := false
var enabled := true              # игра: карточка работает только в 3D-виде
var feed_events := true          # находки World в ленту (в игре их пишет свой журнал)
var open := false
var subjects: Array = []
var cur := 0

var _root: Control
var _card: PanelContainer
var _box: VBoxContainer
var _feed: VBoxContainer
var _feed_items: Array = []      # [Label, t]
var _hint: Label                 # что делает кнопка под фокусом
var _sig := ""
var _focus_key := ""

## Раскладка по умолчанию. Коснуться — B: A на геймпаде — прыжок (ProtoControls),
## а B вне карточки свободен и её же закрывает.
static func layout() -> Dictionary:
	return {
		TOUCH: [ProtoControls._key(KEY_Z), ProtoControls._button(JOY_BUTTON_B)],
		ANALYZE: [ProtoControls._key(KEY_V), ProtoControls._button(JOY_BUTTON_RIGHT_SHOULDER)],
		PREV: [ProtoControls._key(KEY_PAGEUP), ProtoControls._button(JOY_BUTTON_LEFT_SHOULDER)],
		NEXT: [ProtoControls._key(KEY_PAGEDOWN), ProtoControls._button(JOY_BUTTON_RIGHT_SHOULDER)],
		CLOSE: [ProtoControls._key(KEY_ESCAPE), ProtoControls._button(JOY_BUTTON_B)],
	}

static func ensure_actions() -> void:
	var lay := layout()
	for a in lay:
		if InputMap.has_action(a):
			continue
		InputMap.add_action(a, 0.5)
		for e in lay[a]:
			InputMap.action_add_event(a, e)

func setup(d: ProtoLabDesk, r: Node3D = null) -> void:
	desk = d
	robot = r
	pad = OS.has_feature("steamdeck") or not Input.get_connected_joypads().is_empty()
	ensure_actions()

func _ready() -> void:
	layer = 6
	_root = Control.new()
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_card = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.06, 0.08, 0.9)
	sb.border_color = Color(0.45, 0.85, 1.0, 0.35)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(14)
	_card.add_theme_stylebox_override("panel", sb)
	_card.position = Vector2(ProtoHud.PAD, 70)
	_card.custom_minimum_size.x = WIDTH
	_card.visible = false
	_root.add_child(_card)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 8)
	_card.add_child(_box)
	# Лента — справа, под панелью завода: слева карточка, по центру робот.
	_feed = VBoxContainer.new()
	_feed.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_feed.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_feed.offset_left = -FEED_W - ProtoHud.PAD
	_feed.offset_right = -ProtoHud.PAD
	_feed.offset_top = 170
	_feed.add_theme_constant_override("separation", 4)
	_feed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_feed)
	get_viewport().size_changed.connect(_fit)
	get_viewport().gui_focus_changed.connect(_on_focus)
	_fit()

func _fit() -> void:
	var vs := get_viewport().get_visible_rect().size
	var s := clampf(minf(vs.x / ProtoHud.BASE.x, vs.y / ProtoHud.BASE.y), 0.75, 2.0)
	_root.scale = Vector2(s, s)
	_root.size = vs / s

# ---------------------------------------------------------------- ввод

func _input(e: InputEvent) -> void:
	if e is InputEventKey or e is InputEventMouseButton:
		pad = false
	elif e is InputEventJoypadButton or (e is InputEventJoypadMotion and absf(e.axis_value) > 0.5):
		pad = true
	if not enabled or not e.is_pressed() or e.is_echo():
		return
	if open:
		# A на геймпаде нажимает кнопку под фокусом; закрывают B, Esc и Z.
		if e.is_action_pressed(CLOSE) or (e is InputEventKey and e.is_action_pressed(TOUCH)):
			close()
			get_viewport().set_input_as_handled()
		elif e.is_action_pressed(PREV):
			select(cur - 1)
			get_viewport().set_input_as_handled()
		elif e.is_action_pressed(NEXT):
			select(cur + 1)
			get_viewport().set_input_as_handled()
		return
	if _building():
		return
	if e.is_action_pressed(TOUCH):
		touch_open()
		get_viewport().set_input_as_handled()
	elif e.is_action_pressed(ANALYZE):
		var err := desk.analyze_near() if desk.proto() else desk.analyze_game(focus_cell)
		if err != "":
			say(err)
		get_viewport().set_input_as_handled()

func _building() -> bool:
	return builder != null and bool(builder.get("active"))

## Коснуться ближнего и открыть карточку. false — рядом нечего изучать.
func touch_open() -> bool:
	subjects = desk.subjects(focus_cell)
	if subjects.is_empty():
		say("Изучать нечего: подойдите к друзе или машине, или добудьте образец" if desk.proto()
			else "Изучать нечего: подойдите к залежи или возьмите образец в инвентарь")
		return false
	open = true
	_set_busy(true)
	_focus_key = ""
	select(0)
	return true

func close() -> void:
	open = false
	_set_busy(false)
	_card.visible = false
	var f := get_viewport().gui_get_focus_owner()
	if f != null and _card.is_ancestor_of(f):
		f.release_focus()

func select(i: int) -> void:
	if subjects.is_empty():
		return
	cur = posmod(i, subjects.size())
	desk.touch(subjects[cur].sub)
	_sig = ""
	_focus_key = ""

func current() -> Substance:
	return subjects[cur].sub if open and cur < subjects.size() else null

func _set_busy(on: bool) -> void:
	if robot != null:
		robot.set_meta("ui_busy", on)

# ---------------------------------------------------------------- кадр

func _process(dt: float) -> void:
	if desk == null:
		return
	desk.tick(dt)
	for t in desk.new_events():
		if feed_events:
			_push_feed(t)
	for it in _feed_items.duplicate():
		it[1] -= dt
		it[0].modulate.a = clampf(it[1], 0.0, 1.0)
		if it[1] <= 0.0:
			_feed_items.erase(it)
			it[0].queue_free()
	if open and _building():
		close()
	if open:
		_refresh()

func _refresh() -> void:
	var s := current()
	if s == null:
		close()
		return
	var w := desk.world
	var sig := str([cur, subjects.size(), s.id, w.known_tags_of(s), w.excluded_of(s).size(), w.hypotheses_of(s),
		int(w.robot.tank * 10.0), desk.last, int(desk.sample_kg(s) * 10.0) if desk.proto() else 0, pad, w.robot.knowledge])
	if sig == _sig:
		return
	_sig = sig
	_build(s)

func _build(s: Substance) -> void:
	var w := desk.world
	for ch in _box.get_children():
		_box.remove_child(ch)
		ch.queue_free()
	_card.visible = true
	# Образцы рядом: вкладки.
	if subjects.size() > 1:
		var tabs := HFlowContainer.new()
		tabs.add_theme_constant_override("h_separation", 6)
		for i in subjects.size():
			var sj: Dictionary = subjects[i]
			var b := _button(desk.short_label(sj.sub), "tab:%d" % i, i == cur)
			var idx := i
			b.pressed.connect(func(): select(idx))
			tabs.add_child(b)
		var nav := ProtoHud.glyph([PREV], pad) + " " + ProtoHud.glyph([NEXT], pad)
		tabs.add_child(_label(nav, SMALL, ProtoHud.DIM))
		_box.add_child(tabs)
	# Заголовок: имя, откуда образец, известные теги и «?».
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	var sw := ColorRect.new()
	sw.color = s.color
	sw.custom_minimum_size = Vector2(22, 22)
	head.add_child(sw)
	head.add_child(_label(s.name, FONT + 6, ProtoHud.TEXT))
	var sj2: Dictionary = subjects[cur]
	var where: String = WHERE.get(sj2.where, "")
	if sj2.kg > 0.0:
		where += " · %.1f кг" % sj2.kg
	head.add_child(_label(where, SMALL, ProtoHud.DIM))
	if w.is_identified(s):
		head.add_child(_label("опознан", SMALL, ProtoHud.OK))
	_box.add_child(head)
	var tags := HFlowContainer.new()
	tags.add_theme_constant_override("h_separation", 6)
	tags.add_theme_constant_override("v_separation", 4)
	for t in w.known_tags_of(s):
		tags.add_child(_tag_chip(MaterialTags.display(t), MaterialTags.TAGS[t].col, true))
	for i in w.unknown_count(s):
		tags.add_child(_tag_chip("?", Color(0.5, 0.5, 0.55), false))
	_box.add_child(tags)
	var lines: Array = []
	if w.is_analyzed(s):
		lines.append("тв. %.1f · плотн. %.1f · плавится %.0f °C · кипит %.0f °C" % [s.hardness, s.density, s.melt, s.boil])
	var ex: Array = w.excluded_of(s).map(func(t): return MaterialTags.display(t))
	if not ex.is_empty():
		var shown := ex.slice(0, 8)
		lines.append("Нет: " + ", ".join(PackedStringArray(shown)) + (" и ещё %d" % (ex.size() - 8) if ex.size() > 8 else ""))
	if not lines.is_empty():
		var info := _label("\n".join(PackedStringArray(lines)), SMALL, Color(0.75, 0.8, 0.88))
		info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.custom_minimum_size.x = WIDTH - 28
		_box.add_child(info)
	if w.unknown_count(s) > 0:
		# Пробы.
		_box.add_child(_label("ПРОБЫ · образец %.1f кг · газ из баллона %.1f / %.1f" % [w.probe_cost(), w.robot.tank, w.robot.tank_cap()], SMALL, ProtoHud.DIM))
		var pr := HFlowContainer.new()
		pr.add_theme_constant_override("h_separation", 6)
		pr.add_theme_constant_override("v_separation", 6)
		for pid in Probes.ORDER:
			var d: Dictionary = Probes.PROBES[pid]
			var err := desk.probe_error(s, pid)
			var b := _button(d.n + ((" · %.1f" % d.gas) if d.gas > 0.0 else ""), "probe:" + pid)
			b.disabled = err != ""
			var names: Array = d.tags.filter(func(t): return not MaterialTags.is_exotic(t) or w.robot.known_tags.has(t)).map(func(t): return MaterialTags.display(t))
			b.set_meta("hint", "%s Различает: %s.%s" % [d.desc, ", ".join(PackedStringArray(names)), ("  Нельзя: " + err) if err != "" else ""])
			var p2: String = pid
			b.pressed.connect(func():
				var e2 := desk.probe(current(), p2)
				if e2 != "":
					say(e2))
			pr.add_child(b)
		_box.add_child(pr)
		# Догадки.
		var hyp: Array = w.hypotheses_of(s)
		_box.add_child(_label("ДОГАДКИ · до %d, верная даёт знание" % World.MAX_HYPOTHESES, SMALL, ProtoHud.DIM))
		var gf := HFlowContainer.new()
		gf.add_theme_constant_override("h_separation", 6)
		gf.add_theme_constant_override("v_separation", 6)
		var pos: Array = w.possible_of(s)
		for t in hyp:
			if not t in pos:
				pos.push_front(t)
		for t in pos.slice(0, MAX_GUESS_TAGS):
			var on: bool = t in hyp
			var b := _button(("✦ " if on else "") + MaterialTags.display(t), "tag:" + t, on)
			b.set_meta("hint", "Распознать: " + Probes.how(t) + (".  Нажмите ещё раз — снять догадку" if on else ".  Нажмите — отметить догадку"))
			var tag: String = t
			b.pressed.connect(func():
				var e3 := desk.toggle_guess(current(), tag)
				if e3 != "":
					say(e3))
			gf.add_child(b)
		if pos.size() > MAX_GUESS_TAGS:
			gf.add_child(_label("…ещё %d" % (pos.size() - MAX_GUESS_TAGS), SMALL, ProtoHud.DIM))
		_box.add_child(gf)
		if not hyp.is_empty():
			var cf := HFlowContainer.new()
			cf.add_theme_constant_override("h_separation", 6)
			for t in hyp:
				var cerr := desk.check_error(s, t)
				var cb := _button("Проверить «%s»" % MaterialTags.display(t), "check:" + t)
				cb.disabled = cerr != ""
				cb.set_meta("hint", "Вдвое дешевле пробы (%.2f кг), но только про один тег.%s" % [w.probe_cost() * 0.5, ("  Нельзя: " + cerr) if cerr != "" else ""])
				var tag2: String = t
				cb.pressed.connect(func():
					var e4 := desk.check(current(), tag2)
					if e4 != "":
						say(e4))
				cf.add_child(cb)
			_box.add_child(cf)
	if desk.last != "" and desk.last.contains(s.name):
		var lp := _label("▸ " + desk.last, SMALL + 1, Color(0.6, 0.95, 0.7))
		lp.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lp.custom_minimum_size.x = WIDTH - 28
		_box.add_child(lp)
	_hint = _label("", SMALL, Color(0.85, 0.88, 0.95))
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.custom_minimum_size.x = WIDTH - 28
	_box.add_child(_hint)
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 8)
	for h in [["Выбрать", "A", "Enter"], ["Закрыть", "B", "Esc"]]:
		foot.add_child(_chip(h[1] if pad else h[2]))
		foot.add_child(_label(h[0], SMALL, ProtoHud.TEXT))
	foot.add_child(_label("   Знания: %d" % w.robot.knowledge, SMALL, ProtoHud.WARN))
	_box.add_child(foot)
	_restore_focus.call_deferred()

## Фокус остаётся на той же кнопке после перестройки (или на первой пробе).
func _restore_focus() -> void:
	if not open:
		return
	var buttons := _card.find_children("*", "Button", true, false).filter(func(b): return not b.is_queued_for_deletion())
	if buttons.is_empty():
		return
	var pick: Button = null
	for b in buttons:
		if b.get_meta("key", "") == _focus_key and not b.disabled:
			pick = b
	if pick == null:
		for b in buttons:
			if pick == null and not b.disabled and not str(b.get_meta("key", "")).begins_with("tab:"):
				pick = b
	if pick == null:
		pick = buttons[0]
	pick.grab_focus()

func _on_focus(c: Control) -> void:
	if c == null or not open or not _card.is_ancestor_of(c):
		return
	_focus_key = str(c.get_meta("key", ""))
	if _hint != null and is_instance_valid(_hint):
		_hint.text = str(c.get_meta("hint", ""))

# ---------------------------------------------------------------- лента находок

func say(t: String) -> void:
	_push_feed(t, ProtoHud.WARN)

func _push_feed(t: String, col: Color = Color(0.7, 0.95, 1.0)) -> void:
	var l := _label(t, SMALL + 2, col)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = FEED_W
	_feed.add_child(l)
	_feed_items.append([l, FEED_SEC])
	while _feed_items.size() > 3:
		var old: Array = _feed_items.pop_front()
		old[0].queue_free()

# ---------------------------------------------------------------- виджеты

func _label(t: String, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("outline_size", 4)
	return l

func _button(t: String, key: String, on := false) -> Button:
	var b := Button.new()
	b.text = t
	b.set_meta("key", key)
	b.custom_minimum_size.y = 38
	b.add_theme_font_size_override("font_size", SMALL + 1)
	var n := StyleBoxFlat.new()
	n.bg_color = Color(0.2, 0.42, 0.55, 0.95) if on else Color(0.16, 0.18, 0.22, 0.95)
	n.set_corner_radius_all(6)
	n.content_margin_left = 12
	n.content_margin_right = 12
	var hov := n.duplicate()
	hov.bg_color = n.bg_color.lightened(0.12)
	var foc := n.duplicate()
	foc.bg_color = n.bg_color.lightened(0.18)
	foc.border_color = Color(0.45, 0.9, 1.0)
	foc.set_border_width_all(3)
	var dis := n.duplicate()
	dis.bg_color = Color(0.12, 0.12, 0.14, 0.8)
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("hover", hov)
	b.add_theme_stylebox_override("pressed", foc)
	b.add_theme_stylebox_override("focus", foc)
	b.add_theme_stylebox_override("disabled", dis)
	b.add_theme_color_override("font_color", Color.WHITE)
	b.add_theme_color_override("font_disabled_color", Color(0.5, 0.52, 0.56))
	return b

func _tag_chip(t: String, col: Color, known: bool) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = col.darkened(0.55) if known else Color(0.14, 0.14, 0.16)
	sb.border_color = col if known else Color(0.5, 0.5, 0.55, 0.6)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(12)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	p.add_theme_stylebox_override("panel", sb)
	p.add_child(_label(t, SMALL + 1, Color.WHITE if known else Color(0.7, 0.7, 0.75)))
	return p

func _chip(t: String) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	var round := pad and ProtoHud.PAD_COLORS.has(t)
	sb.bg_color = ProtoHud.PAD_COLORS[t] if round else Color(0.22, 0.24, 0.28)
	sb.set_corner_radius_all(14 if round else 6)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	p.add_theme_stylebox_override("panel", sb)
	p.custom_minimum_size = Vector2(28, 26)
	var l := _label(t, SMALL, Color.WHITE)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	p.add_child(l)
	return p
