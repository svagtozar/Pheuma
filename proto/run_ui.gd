class_name ProtoRunUi
extends CanvasLayer
## Интерфейс рана 3D-прототипа (ProtoRun): панель цели с советом «что дальше»,
## баннер события, всплывающие записи журнала и окна — высадка (брифинг), выбор
## пути, награда, меню, прокачка, итоги. Всё управляется геймпадом: D-pad или
## левый стик — выбор, A — нажать, B — назад, Menu (Start) — меню; мышь и
## клавиатура тоже работают. Пока открыто окно, игра стоит на паузе.
## Размеры — под Steam Deck (1280×800), на большом экране всё крупнее.

const BASE := Vector2(1280, 800)
const PAD := 16.0
const GOAL_W := 460.0

const BG := Color(0.06, 0.07, 0.09, 0.78)
const WIN_BG := Color(0.07, 0.08, 0.11, 0.97)
const EDGE := Color(1, 1, 1, 0.1)
const TEXT := Color(0.93, 0.94, 0.95)
const DIM := Color(0.66, 0.69, 0.73)
const ACCENT := Color(0.55, 0.8, 1.0)
const GOLD := Color(1.0, 0.83, 0.47)
const OK := Color(0.45, 0.82, 0.5)
const WARN := Color(0.98, 0.76, 0.3)
const BAD := Color(0.97, 0.38, 0.33)
const FOCUS := Color(1.0, 0.85, 0.3)

var run: ProtoRun
var robot: Node3D
var hud: ProtoHud                  # подписи кнопок: клавиатура или геймпад
var on_new_planet := Callable()
var on_quit := Callable()
var pause_game := true             # окно ставит игру на паузу (для кадров — нет)

var modal := ""                    # открытое окно или ""
var closable := true
var _root: Control
var _goal_title: Label
var _goal_stage: Label
var _goal_bar: ProgressBar
var _goal_num: Label
var _goal_dots: HBoxContainer
var _hint: Label
var _skill_note: Label
var _banner: PanelContainer
var _banner_title: Label
var _banner_tip: Label
var _toasts: VBoxContainer
var _layer: Control                # затемнение и окно
var _win: PanelContainer
var _body: VBoxContainer
var _refresh_t := 0.0
var _skill_focus := ""
var _skill_footer: Label
var _warm := 0.3                   # сохранение накладывается отложенно — окна чуть позже

func setup(r: ProtoRun, robot_node: Node3D, h: ProtoHud) -> void:
	run = r
	robot = robot_node
	hud = h

func _ready() -> void:
	layer = 8
	process_mode = Node.PROCESS_MODE_ALWAYS
	ProtoControls.ensure()
	ProtoControls.ensure_ui()
	_root = Control.new()
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = _theme()
	add_child(_root)
	_build_goal()
	_build_banner()
	_toasts = VBoxContainer.new()
	_toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toasts.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toasts.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toasts.offset_top = 290
	_toasts.alignment = BoxContainer.ALIGNMENT_BEGIN
	_toasts.add_theme_constant_override("separation", 6)
	_root.add_child(_toasts)
	_build_modal()
	get_viewport().size_changed.connect(_fit)
	_fit()

func _fit() -> void:
	var vs := get_viewport().get_visible_rect().size
	var s := clampf(minf(vs.x / BASE.x, vs.y / BASE.y), 0.75, 2.0)
	_root.scale = Vector2(s, s)
	_root.size = vs / s

func pad() -> bool:
	return hud != null and hud.pad

func glyph(actions: Array) -> String:
	return ProtoHud.glyph(actions, pad())

# ---------------------------------------------------------------- кадр

func _process(dt: float) -> void:
	if run == null:
		return
	if not get_tree().paused:
		if robot != null:
			run.robot_pos = robot.global_position
		run.tick(dt)
	_warm -= dt
	if modal == "" and _warm <= 0.0:
		if not run.briefing_seen:
			open("briefing")
		elif not run.goals.reward_pending.is_empty():
			open("reward")
		elif run.goals.choice_pending():
			open("choice")
		elif run.goals.completed and not run.end_shown:
			run.end_shown = true
			open("end")
	_keep_focus()
	while not run.notes.is_empty():
		_toast(run.notes.pop_front())
	_refresh_t -= dt
	if _refresh_t <= 0.0:
		_refresh_t = 0.25
		refresh()

## Геймпаду нужна кнопка в фокусе: если фокус потерян — первая кнопка окна.
func _keep_focus() -> void:
	if modal == "":
		return
	var f := get_viewport().gui_get_focus_owner()
	if f != null and _win.is_ancestor_of(f) and f.is_visible_in_tree():
		return
	var b := ProtoControls.first_button(_win)
	if b != null:
		b.grab_focus()

func _unhandled_input(e: InputEvent) -> void:
	if run == null or e.is_echo():
		return
	if e.is_action_pressed(ProtoControls.MENU):
		if modal == "":
			open("menu")
		elif closable:
			close()
		get_viewport().set_input_as_handled()
	elif e.is_action_pressed(ProtoControls.SKILLS):
		if modal == "skills":
			close()
		elif modal == "" or closable:
			open("skills")
		get_viewport().set_input_as_handled()
	elif modal != "" and e.is_action_pressed(&"ui_cancel"):
		if closable:
			close()
		get_viewport().set_input_as_handled()

# ---------------------------------------------------------------- панель цели

func _build_goal() -> void:
	var p := _panel(BG)
	p.custom_minimum_size.x = GOAL_W
	p.position = Vector2(PAD, PAD)
	_root.add_child(p)
	var v: VBoxContainer = p.get_child(0)
	_goal_title = _label("", 15, DIM)
	v.add_child(_goal_title)
	_goal_stage = _label("", 20, TEXT)
	_goal_stage.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_goal_stage.custom_minimum_size.x = GOAL_W - 28
	v.add_child(_goal_stage)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	v.add_child(row)
	_goal_bar = ProgressBar.new()
	_goal_bar.show_percentage = false
	_goal_bar.max_value = 1.0
	_goal_bar.custom_minimum_size = Vector2(250, 14)
	_goal_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(1, 1, 1, 0.12)
	bg.set_corner_radius_all(5)
	var fg := StyleBoxFlat.new()
	fg.bg_color = OK
	fg.set_corner_radius_all(5)
	_goal_bar.add_theme_stylebox_override("background", bg)
	_goal_bar.add_theme_stylebox_override("fill", fg)
	row.add_child(_goal_bar)
	_goal_num = _label("", 17, TEXT)
	row.add_child(_goal_num)
	_goal_dots = HBoxContainer.new()
	_goal_dots.add_theme_constant_override("separation", 6)
	v.add_child(_goal_dots)
	_hint = _label("", 17, GOLD)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.custom_minimum_size.x = GOAL_W - 28
	v.add_child(_hint)
	_skill_note = _label("", 15, DIM)
	v.add_child(_skill_note)

func refresh() -> void:
	var g := run.goals
	var goal: Dictionary = run.planet.goal
	var n: int = goal.stages.size()
	_goal_title.text = "ЦЕЛЬ ПЛАНЕТЫ · " + str(goal.n).to_upper()
	if g.completed:
		_goal_stage.text = "Цель выполнена!"
		_goal_bar.value = 1.0
		_goal_num.text = "✓"
	elif g.choice_pending():
		_goal_stage.text = "Этап %d/%d: выберите путь" % [g.stage + 1, n]
		_goal_bar.value = 0.0
		_goal_num.text = ""
	else:
		_goal_stage.text = "Этап %d/%d: %s" % [g.stage + 1, n, g.current().desc]
		_goal_bar.value = g.progress
		var nums := run.stage_numbers()
		_goal_num.text = "%s / %s %s" % [_num(nums[0]), _num(nums[1]), nums[2]]
	_clear(_goal_dots)
	for i in n:
		var done: bool = g.completed or i < g.stage
		var d := _label("●" if done else ("◉" if i == g.stage else "○"), 16, OK if done else (TEXT if i == g.stage else DIM))
		_goal_dots.add_child(d)
	_hint.text = "▶ " + run.advise(glyph)
	var can := _learnable()
	_skill_note.text = "Знаний %d · %s — меню%s" % [run.robot.knowledge, glyph([ProtoControls.MENU]),
		" · можно изучить: %d" % can if can > 0 else ""]
	_skill_note.add_theme_color_override("font_color", ACCENT if can > 0 else DIM)
	_refresh_banner()

func _num(x: float) -> String:
	return "%d" % int(x) if absf(x - roundf(x)) < 0.05 or x >= 10.0 else "%.1f" % x

func _learnable() -> int:
	var c := 0
	for nd in SkillTree.NODES:
		if Progression.can_learn(run.robot, nd.id) == "":
			c += 1
	return c

# ---------------------------------------------------------------- событие и журнал

func _build_banner() -> void:
	_banner = _panel(Color(0.35, 0.08, 0.05, 0.85))
	_banner.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_banner.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_banner.offset_right = -PAD
	_banner.offset_left = -PAD
	_banner.offset_top = 150
	_banner.custom_minimum_size.x = 360
	_banner.visible = false
	_root.add_child(_banner)
	var v: VBoxContainer = _banner.get_child(0)
	_banner_title = _label("", 19, TEXT)
	v.add_child(_banner_title)
	_banner_tip = _label("", 15, Color(1, 0.9, 0.85))
	_banner_tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_banner_tip.custom_minimum_size.x = 332
	v.add_child(_banner_tip)

func _refresh_banner() -> void:
	var line := run.event_line()
	_banner.visible = line != ""
	if line == "":
		return
	var warn: bool = run.ev.phase == "warn"
	_banner_title.text = ("⚠ " if warn else "● ") + line
	_banner_tip.text = run.event_tip()
	var sb: StyleBoxFlat = _banner.get_theme_stylebox("panel")
	sb.bg_color = Color(0.4, 0.26, 0.04, 0.88) if warn else Color(0.42, 0.08, 0.06, 0.88)

func _toast(text: String) -> void:
	var l := _panel(Color(0.05, 0.06, 0.08, 0.7))
	var t := _label(text, 18, TEXT)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t.custom_minimum_size.x = 560
	l.get_child(0).add_child(t)
	_toasts.add_child(l)
	while _toasts.get_child_count() > 3:
		_toasts.get_child(0).queue_free()
		_toasts.remove_child(_toasts.get_child(0))
	var tw := l.create_tween()
	tw.tween_interval(3.5)
	tw.tween_property(l, "modulate:a", 0.0, 0.8)
	tw.tween_callback(l.queue_free)

# ---------------------------------------------------------------- окна

func _build_modal() -> void:
	_layer = Control.new()
	_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_layer.visible = false
	_root.add_child(_layer)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_layer.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_layer.add_child(center)
	_win = _panel(WIN_BG)
	(_win.get_theme_stylebox("panel") as StyleBoxFlat).set_content_margin_all(22)
	center.add_child(_win)
	_body = _win.get_child(0)
	_body.add_theme_constant_override("separation", 12)

func open(name: String) -> void:
	_clear(_body)
	modal = name
	closable = not name in ["choice", "reward"]
	match name:
		"briefing": _fill_briefing()
		"choice": _fill_choice()
		"reward": _fill_reward()
		"menu": _fill_menu()
		"skills": _fill_skills()
		"end": _fill_end()
	_layer.visible = true
	if pause_game:
		get_tree().paused = true
	_keep_focus.call_deferred()

func close() -> void:
	if modal == "briefing":
		run.briefing_seen = true
	modal = ""
	_layer.visible = false
	_clear(_body)
	# Снять паузу чуть позже: нажатие A, закрывшее окно, не должно поставить деталь.
	get_tree().create_timer(0.12, true).timeout.connect(func():
		if modal == "" and is_inside_tree():
			get_tree().paused = false)

func _title(t: String, sub: String = "") -> void:
	var l := _label(t, 28, TEXT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_body.add_child(l)
	if sub != "":
		var s := _label(sub, 17, DIM)
		s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		s.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		s.custom_minimum_size.x = 760
		_body.add_child(s)

func _text(t: String, size: int = 18, col: Color = TEXT, width: float = 760.0) -> Label:
	var l := _label(t, size, col)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = width
	_body.add_child(l)
	return l

func _button(parent: Container, t: String, f: Callable, min_size := Vector2(0, 48)) -> Button:
	var b := Button.new()
	b.text = t
	b.custom_minimum_size = min_size
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.pressed.connect(f)
	parent.add_child(b)
	return b

func _buttons_row() -> HBoxContainer:
	var h := HBoxContainer.new()
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_theme_constant_override("separation", 14)
	_body.add_child(h)
	return h

func _controls_line() -> String:
	if not closable:
		return "D-pad — выбор, A — взять" if pad() else "Мышь или стрелки и Enter"
	return "A — выбрать, B — назад" if pad() else "Мышь или стрелки и Enter, Esc — назад"

func _fill_briefing() -> void:
	var p := run.planet
	var goal: Dictionary = p.goal
	_title("Высадка: " + p.name, ", ".join(PackedStringArray(p.tags.map(func(t): return PlanetTags.display(t)))) +
		" · %.0f °C, %.2f атм, %.1f g" % [p.ambient_temp, p.atm_pressure, p.gravity])
	_text("Цель: %s" % goal.n, 22, GOLD)
	if str(goal.desc) != "":
		_text(goal.desc, 18, DIM)
	for i in goal.stages.size():
		var st: Dictionary = goal.stages[i]
		if st.has("alt"):
			_text("%d. На выбор: %s — или — %s" % [i + 1, st.alt[0].desc, st.alt[1].desc], 18)
		else:
			_text("%d. %s" % [i + 1, st.desc], 18)
	_text("За каждый этап — награда на выбор, за добычу и стройку — опыт классов и знания для прокачки. " +
		"Планета живёт: события предупреждают заранее.", 17, DIM)
	var keys: Array = []
	for k in [["Бур", ProtoControls.WORK], ["Выгрузить в приёмник", &"cargo_unload"], ["Стройка", &"build_mode"],
			["Меню, прокачка и итоги", ProtoControls.MENU]]:
		var g := glyph([k[1]])
		if g != "":
			keys.append("%s — %s" % [k[0], g])
	_text(" · ".join(PackedStringArray(keys)), 17, ACCENT)
	var h := _buttons_row()
	_button(h, "Начать", close, Vector2(260, 52))

func _fill_choice() -> void:
	var g := run.goals
	var raw := g.raw_stage(g.stage)
	_title("Этап %d: выберите путь" % (g.stage + 1), "Выбор нельзя отменить до конца этапа.")
	var h := _buttons_row()
	for i in raw.alt.size():
		var alt: Dictionary = raw.alt[i]
		var idx: int = i
		_button(h, "%s\n\n%s" % [alt.desc, alt.get("pitch", "")], func():
			g.choose(idx)
			close(), Vector2(400, 150))
	_text(_controls_line(), 15, DIM).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

func _fill_reward() -> void:
	var g := run.goals
	_title("Этап выполнен — выберите награду", "+3 знания и опыт вождя уже получены.")
	var h := _buttons_row()
	for id in g.reward_pending:
		var cid: String = id
		var c := run.card(cid)
		_button(h, "%s\n\n%s" % [c.n, c.desc], func():
			run.take_reward(cid)
			close(), Vector2(340, 160))
	_text(_controls_line(), 15, DIM).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

func _fill_menu() -> void:
	var g := run.goals
	var goal: Dictionary = run.planet.goal
	var st := "выполнена" if g.completed else "этап %d из %d" % [g.stage + 1, goal.stages.size()]
	_title("Пауза", "%s · %s · %s" % [run.planet.name, goal.n, st])
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	v.custom_minimum_size.x = 420
	var c := CenterContainer.new()
	c.add_child(v)
	_body.add_child(c)
	_button(v, "Продолжить", close)
	_button(v, "Цель и высадка", func(): open("briefing"))
	var can := _learnable()
	_button(v, "Прокачка · знаний %d%s" % [run.robot.knowledge, " · можно изучить %d" % can if can > 0 else ""], func(): open("skills"))
	_button(v, "Итоги рана", func(): open("end"))
	if on_new_planet.is_valid():
		_button(v, "Новая планета", on_new_planet)
	if on_quit.is_valid():
		_button(v, "Сохранить и выйти", on_quit)
	_text(_controls_line(), 15, DIM, 420).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

func _fill_skills() -> void:
	var r := run.robot
	_title("Прокачка · знаний: %d" % r.knowledge,
		"Опыт классов растёт от дела: бур — собиратель, стройка — ремесленник, машины — хранитель огня, теги — шаман, доставка и этапы — вождь, события — охотник.")
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	_body.add_child(grid)
	var focus_btn: Button = null
	for cls in SkillTree.CLASS_ORDER:
		var info: Dictionary = SkillTree.CLASSES[cls]
		var box := VBoxContainer.new()
		box.custom_minimum_size.x = 370
		box.add_theme_constant_override("separation", 5)
		grid.add_child(box)
		var head := _label("%s · опыт %d" % [info.n, int(r.xp[cls])], 18, info.col)
		box.add_child(head)
		for nd in SkillTree.nodes_of(cls):
			var id: String = nd.id
			var err := Progression.can_learn(r, id)
			var learned: bool = r.learned.has(id)
			var t: String = ("✓ " if learned else "") + nd.n + ("" if learned else " · %d зн." % nd.cost)
			var b := _button(box, t, func():
				var e := run.learn(id)
				if e != "":
					_skill_footer.text = "Нельзя: " + e
				else:
					_skill_focus = id
					open("skills"), Vector2(0, 38))
			b.add_theme_font_size_override("font_size", 17)
			if learned:
				b.add_theme_color_override("font_color", OK)
				b.add_theme_color_override("font_focus_color", OK)
			elif err != "":
				b.add_theme_color_override("font_color", DIM)
			b.focus_entered.connect(func(): _skill_hint(id))
			b.mouse_entered.connect(func(): _skill_hint(id))
			if id == _skill_focus:
				focus_btn = b
	_skill_footer = _text("", 17, GOLD, 1130)
	_skill_footer.custom_minimum_size.y = 44
	var bp := r.blueprints.keys().filter(func(k): return Modules.MODULES.has(k)).map(func(k): return Modules.MODULES[k].n)
	_text("Чертежи модулей: %d из %d — %s. Модули изготавливают в игре, у фабрикатора." % [bp.size(), Modules.MODULES.size(),
		", ".join(PackedStringArray(bp)) if not bp.is_empty() else "нет"], 15, DIM, 1130)
	var h := _buttons_row()
	_button(h, "Назад", close, Vector2(220, 46))
	if focus_btn != null:
		focus_btn.grab_focus.call_deferred()

func _skill_hint(id: String) -> void:
	_skill_focus = id
	var nd := SkillTree.node(id)
	var err := Progression.can_learn(run.robot, id)
	var st := "изучено" if err == "уже изучено" else ("можно изучить — A" if pad() else "можно изучить — Enter или щелчок") if err == "" else err
	_skill_footer.text = "%s: %s (%s)" % [nd.n, nd.desc, st]

func _fill_end() -> void:
	_title("Цель планеты достигнута!" if run.goals.completed else "Итоги рана")
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 28)
	grid.add_theme_constant_override("v_separation", 6)
	var c := CenterContainer.new()
	c.add_child(grid)
	_body.add_child(c)
	for row in run.summary():
		grid.add_child(_label(row[0], 18, DIM))
		grid.add_child(_label(row[1], 18, GOLD if row[0] == "Главная роль робота" else TEXT))
	var h := _buttons_row()
	_button(h, "Остаться на планете" if run.goals.completed else "Продолжить", close, Vector2(250, 50))
	if on_new_planet.is_valid():
		_button(h, "Новая планета", on_new_planet, Vector2(220, 50))
	if on_quit.is_valid():
		_button(h, "Выход", on_quit, Vector2(160, 50))

# ---------------------------------------------------------------- виджеты

func _theme() -> Theme:
	var th := Theme.new()
	th.default_font_size = 18
	th.set_font_size("font_size", "Button", 19)
	var mk := func(bg: Color, border: Color, w: int) -> StyleBoxFlat:
		var sb := StyleBoxFlat.new()
		sb.bg_color = bg
		sb.border_color = border
		sb.set_border_width_all(w)
		sb.set_corner_radius_all(10)
		sb.content_margin_left = 16
		sb.content_margin_right = 16
		sb.content_margin_top = 8
		sb.content_margin_bottom = 8
		return sb
	th.set_stylebox("normal", "Button", mk.call(Color(0.14, 0.16, 0.21), Color(1, 1, 1, 0.12), 1))
	th.set_stylebox("hover", "Button", mk.call(Color(0.19, 0.22, 0.29), Color(1, 1, 1, 0.3), 1))
	th.set_stylebox("pressed", "Button", mk.call(Color(0.24, 0.3, 0.4), ACCENT, 2))
	th.set_stylebox("focus", "Button", mk.call(Color(0, 0, 0, 0), FOCUS, 3))
	th.set_stylebox("disabled", "Button", mk.call(Color(0.1, 0.1, 0.12), Color(1, 1, 1, 0.05), 1))
	th.set_color("font_color", "Button", TEXT)
	th.set_color("font_focus_color", "Button", Color.WHITE)
	th.set_color("font_hover_color", "Button", Color.WHITE)
	return th

func _panel(bg: Color) -> PanelContainer:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
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
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("outline_size", 4)
	return l

func _clear(c: Node) -> void:
	for ch in c.get_children():
		c.remove_child(ch)
		ch.queue_free()
