class_name ProtoTutorial
extends CanvasLayer
## Обучение первых минут в 3D (--play и сборки play3d): короткие задания
## по очереди, каждое проверяется по состоянию сцены, как шаги 2D-обучения
## (core/tutorial.gd). Кнопки в тексте — из InputMap ({действие} в тексте шага)
## и сами переключаются между клавиатурой и геймпадом, как в ProtoHud.
## Над целью шага (друза, приёмник) в мире висит метка ▼ с расстоянием.
##   F1 / D-pad влево, удерживать — пропустить шаг; дольше — закрыть обучение.
##   В стройке (там D-pad выбирает деталь) и в окнах рана пропуск не работает.
## Прогресс и «пройдено» — в user://settings.json (общий с игрой файл
## настроек): ключи tutorial3d_step и tutorial3d_done. Пройденное или закрытое
## обучение больше не показывается; --tutorial в предпросмотре начинает заново.
## Корень сцены — «утиный»: robot, pneu, pneu_view, mining, lab_panel, узлы
## player и builder; без завода шаги стройки пропускаются сами.

const SKIP := &"tutorial_skip"
const HOLD_STEP := 0.8           # удерживать, чтобы пропустить шаг
const HOLD_ALL := 2.2            # … чтобы закрыть обучение
const DONE_PAUSE := 1.4          # «Готово» на экране перед следующим шагом
const LOOK_RAD := 1.2            # на сколько повернуть камеру
const WALK_M := 6.0              # сколько пройти
const WIDTH := 440.0
const NEAR_M := 2.5              # ближе — метка цели не нужна

static var SETTINGS := "user://settings.json"   # тесты подменяют на свой файл

## Шаги: id, заголовок, задание. {действие} — кнопка из InputMap,
## {move} и {cam} — группы действий ходьбы и камеры.
const STEPS := [
	{"id": "look", "title": "Осмотритесь",
		"text": "Поверните камеру: {cam}."},
	{"id": "walk", "title": "Пройдитесь",
		"text": "Идите: {move}. С {sprint} — бегом."},
	{"id": "drill", "title": "Добудьте кристалл",
		"text": "Кристаллы растут в пещере — идите к метке ▼. Встаньте вплотную к друзе и держите {tool_work}, пока кристалл не отломится."},
	{"id": "touch", "title": "Изучите материал",
		"text": "У друзы или с грузом нажмите {lab_touch}: касание покажет видимые теги, пробы — скрытые."},
	{"id": "unload", "title": "Сдайте груз",
		"text": "Отнесите груз к приёмнику завода (метка ▼) и нажмите {cargo_unload}. Завод повезёт его по трубам."},
	{"id": "pump", "title": "Поставьте насос",
		"text": "{build_mode} — стройка. {build_prev} {build_next} — выбрать «Насос», {build_place} — поставить перед собой."},
	{"id": "pipe", "title": "Проложите трубу",
		"text": "Выберите «Трубу» и поставьте рядом с деталью завода, {build_rotate} — повернуть. Соседние детали — одна газовая сеть. {build_mode} — выйти из стройки."},
	{"id": "goal", "title": "Цель планеты",
		"text": "Слева вверху — цель планеты из трёх этапов и совет, что делать дальше. {run_menu} — меню: цель, прокачка ({run_skills}), выход. Дальше — сами!"},
]

var root: Node                   # сцена предпросмотра
var hud: ProtoHud                # откуда брать клавиатура/геймпад
var pad := false
var step := 0
var done := false                # пройдено или закрыто
var finished := false            # пройдено до конца (не закрыто)

var _base := {}                  # замеры состояния в начале шага
var _look := 0.0                 # накопленный поворот камеры
var _yaw := INF
var _done_t := -1.0              # пауза «Готово»; <0 — шаг идёт
var _goal_t := 0.0
var _hold := 0.0
var _hold_used := false          # удержание уже сработало, ждём отпускания

var _panel: PanelContainer
var _root_c: Control
var _head: Label
var _count: Label
var _body: RichTextLabel
var _foot: RichTextLabel
var _bar: ColorRect
var _where: Label
var _marker: Label3D
var _sig := ""

# ---------------------------------------------------------------- настройки

static func settings() -> Dictionary:
	if not FileAccess.file_exists(SETTINGS):
		return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string(SETTINGS))
	return d if typeof(d) == TYPE_DICTIONARY else {}

## Пишет ключи поверх файла, не трогая чужие (настройки игры).
static func save_settings(kv: Dictionary) -> void:
	var d := settings()
	d.merge(kv, true)
	var f := FileAccess.open(SETTINGS, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(d))

static func is_done() -> bool:
	return bool(settings().get("tutorial3d_done", false))

static func saved_step() -> int:
	return clampi(int(settings().get("tutorial3d_step", 0)), 0, STEPS.size() - 1)

static func reset() -> void:
	save_settings({"tutorial3d_done": false, "tutorial3d_step": 0})

static func ensure_actions() -> void:
	if InputMap.has_action(SKIP):
		return
	InputMap.add_action(SKIP, 0.5)
	InputMap.action_add_event(SKIP, ProtoControls._key(KEY_F1))
	InputMap.action_add_event(SKIP, ProtoControls._button(JOY_BUTTON_DPAD_LEFT))

# ---------------------------------------------------------------- текст

## Текст шага с подписями кнопок. rich — плашки BBCode, иначе [F].
static func step_text(i: int, for_pad: bool, rich := true) -> String:
	var t: String = STEPS[i].text
	var groups := {
		"move": [&"move_forward", &"move_left", &"move_back", &"move_right"],
		"cam": [&"cam_left", &"cam_right", &"cam_up", &"cam_down"],
	}
	var re := RegEx.create_from_string("\\{(\\w+)\\}")
	var out := ""
	var at := 0
	for m in re.search_all(t):
		out += t.substr(at, m.get_start() - at)
		var name := m.get_string(1)
		var acts: Array = groups.get(name, [StringName(name)])
		var g := ProtoHud.glyph(acts, for_pad)
		if name == "cam" and not for_pad:
			g = (g + " или мышь") if g != "" else "мышь"
		if g != "":                  # нет такой кнопки (действие без клавиши) — пропускаем
			out += chips(g, for_pad) if rich else "[%s]" % g
		at = m.get_end()
	out += t.substr(at)
	while out.contains("  "):
		out = out.replace("  ", " ")
	return out.strip_edges()

## Подписи кнопок плашками: «Q E» → две плашки; A/B/X/Y геймпада — в цветах Xbox.
static func chips(g: String, for_pad: bool) -> String:
	if g == "":
		return "[color=#8a8f98](нет кнопки)[/color]"
	var parts: Array = []
	for w in g.split(" "):
		if w == "или":
			parts.append("или")
			continue
		var bg := "#3a3e47"
		if for_pad and ProtoHud.PAD_COLORS.has(w):
			bg = "#" + (ProtoHud.PAD_COLORS[w] as Color).to_html(false)
		parts.append("[bgcolor=%s][color=#ffffff][b] %s [/b][/color][/bgcolor]" % [bg, w])
	return " ".join(PackedStringArray(parts))

# ---------------------------------------------------------------- узел

func setup(r: Node, h: ProtoHud = null, from_step := -1) -> void:
	root = r
	hud = h
	ensure_actions()
	step = from_step if from_step >= 0 else saved_step()
	pad = h.pad if h != null else (OS.has_feature("steamdeck") or not Input.get_connected_joypads().is_empty())

func _ready() -> void:
	layer = 5
	_root_c = Control.new()
	_root_c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root_c)
	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.08, 0.1, 0.82)
	sb.border_color = Color(0.45, 0.85, 1.0, 0.45)
	sb.set_border_width_all(1)
	sb.border_width_left = 4
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(14)
	_panel.add_theme_stylebox_override("panel", sb)
	_panel.custom_minimum_size.x = WIDTH
	# Слева под подписью планеты: справа — завод, снизу — груз и кнопки.
	_panel.position = Vector2(ProtoHud.PAD, 150)
	_root_c.add_child(_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	_panel.add_child(box)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	box.add_child(top)
	var tag := _label("ОБУЧЕНИЕ", ProtoHud.FONT_SMALL, Color(0.45, 0.85, 1.0))
	top.add_child(tag)
	_count = _label("", ProtoHud.FONT_SMALL, ProtoHud.DIM)
	_count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	top.add_child(_count)
	_head = _label("", ProtoHud.FONT + 4, ProtoHud.TEXT)
	box.add_child(_head)
	_body = _rich(ProtoHud.FONT_SMALL + 2)
	box.add_child(_body)
	_where = _label("", ProtoHud.FONT_SMALL, Color(0.55, 0.9, 1.0))
	box.add_child(_where)
	_bar = ColorRect.new()
	_bar.color = Color(0.45, 0.85, 1.0, 0.8)
	_bar.custom_minimum_size = Vector2(0, 3)
	_bar.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	box.add_child(_bar)
	_foot = _rich(ProtoHud.FONT_SMALL - 2)
	box.add_child(_foot)
	get_viewport().size_changed.connect(_fit)
	_fit()
	_marker = Label3D.new()
	_marker.text = "▼"
	_marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_marker.no_depth_test = true
	_marker.fixed_size = true
	_marker.pixel_size = 0.0016
	_marker.font_size = 40
	_marker.outline_size = 10
	_marker.modulate = Color(0.55, 0.9, 1.0)
	_marker.visible = false
	if root != null:
		root.add_child.call_deferred(_marker)
	_begin()

func _fit() -> void:
	var vs := get_viewport().get_visible_rect().size
	var s := clampf(minf(vs.x / ProtoHud.BASE.x, vs.y / ProtoHud.BASE.y), 0.75, 2.0)
	_root_c.scale = Vector2(s, s)
	_root_c.size = vs / s

func _input(e: InputEvent) -> void:
	if e is InputEventKey or e is InputEventMouseButton:
		pad = false
	elif e is InputEventJoypadButton or (e is InputEventJoypadMotion and absf(e.axis_value) > 0.5):
		pad = true

func _process(dt: float) -> void:
	if done:
		return
	if hud != null:
		pad = hud.pad
	var busy := _robot() != null and bool(_robot().get_meta("ui_busy", false))
	busy = busy or _modal()
	var b := _builder()
	_hold_input(dt, busy or (b != null and bool(b.get("active"))))
	if done:
		return
	advance(dt)
	_panel.visible = not busy          # карточка материала занимает то же место
	_update_marker(dt)
	_redraw()
	_place()

## Удержание пропуска: коротко — шаг, долго — всё обучение.
func _hold_input(dt: float, busy: bool) -> void:
	if not busy and Input.is_action_pressed(SKIP):
		_hold += dt
	else:
		_hold = 0.0
		_hold_used = false
	if _hold >= HOLD_ALL:
		close()
	elif _hold >= HOLD_STEP and not _hold_used:
		_hold_used = true
		skip_step()

## Шаг кадра: проверка задания, пауза «Готово», переход. Возвращает true на переходе.
func advance(dt: float) -> bool:
	if done:
		return false
	if _done_t >= 0.0:
		_done_t -= dt
		if _done_t < 0.0:
			_next()
			return true
		return false
	_track(dt)
	if check(STEPS[step].id):
		_done_t = DONE_PAUSE
	return false

func skip_step() -> void:
	_done_t = -1.0
	_next()

## Закрыть обучение насовсем (и не показывать при следующем запуске).
func close() -> void:
	done = true
	save_settings({"tutorial3d_done": true})
	if _marker != null:
		_marker.visible = false
	if _panel != null:
		_panel.visible = false

func _next() -> void:
	step += 1
	while step < STEPS.size() and not available(STEPS[step].id):
		step += 1
	if step >= STEPS.size():
		step = STEPS.size() - 1
		finished = true
		close()
		return
	save_settings({"tutorial3d_step": step})
	_begin()

func _begin() -> void:
	if not available(STEPS[step].id):
		_next()
		return
	_look = 0.0
	_yaw = INF
	_goal_t = 0.0
	_base = {"pos": _robot().global_position if _robot() != null else Vector3.ZERO,
		"cargo": _cargo_kg(), "unloaded": _unloaded(),
		"pump": _count_parts("pump"), "pipe": _count_parts("pipe")}
	_sig = ""

## Шаг возможен в этой сцене (без завода нет стройки и выгрузки, без пещеры — бура).
func available(id: String) -> bool:
	match id:
		"drill":
			return _field("mining") != null
		"touch":
			return _field("lab_panel") != null
		"unload", "pump", "pipe":
			return _field("pneu") != null and _builder() != null
	return true

func _track(dt: float) -> void:
	var pl := _player()
	if pl != null:
		var y: float = pl.get("cam_yaw")
		if _yaw != INF:
			_look += absf(angle_difference(_yaw, y))
		_yaw = y
	_goal_t += dt

func check(id: String) -> bool:
	match id:
		"look":
			return _look >= LOOK_RAD
		"walk":
			var r := _robot()
			if r == null:
				return false
			var d: Vector3 = r.global_position - _base.pos
			return Vector2(d.x, d.z).length() >= WALK_M
		"drill":
			return _cargo_kg() > float(_base.cargo) + 0.01
		"touch":
			var lp = _field("lab_panel")
			return lp != null and bool(lp.get("open"))
		"unload":
			return _unloaded() > float(_base.unloaded) + 0.01
		"pump":
			return _count_parts("pump") > int(_base.pump)
		"pipe":
			return _count_parts("pipe") > int(_base.pipe)
		"goal":
			return _goal_t >= 9.0
	return false

# ---------------------------------------------------------------- состояние сцены

func _field(n: String):
	if root == null:
		return null
	return root.get(n)

func _robot() -> Node3D:
	return _field("robot")

func _player() -> Node:
	return root.get_node_or_null("player") if root != null else null

func _builder() -> Node:
	return root.get_node_or_null("builder") if root != null else null

## Открыто окно рана (ProtoRunUi: высадка, меню, награда…).
func _modal() -> bool:
	var ui = _field("run_ui")
	return ui != null and str(ui.get("modal")) != ""

func _cargo_kg() -> float:
	var r := _robot()
	if r == null or not r.has_meta("cargo"):
		return 0.0
	var m := 0.0
	for p in r.get_meta("cargo"):
		m += p.mass
	return m

func _unloaded() -> float:
	var b := _builder()
	return float(b.get("unloaded_kg")) if b != null and b.get("unloaded_kg") != null else 0.0

func _count_parts(kind: String) -> int:
	var net = _field("pneu")
	if net == null:
		return 0
	var n := 0
	for c in net.parts:
		if net.parts[c].kind == kind:
			n += 1
	return n

## Куда смотреть на этом шаге (или INF).
func target() -> Vector3:
	var r := _robot()
	if r == null:
		return Vector3.INF
	match STEPS[step].id:
		"drill", "touch":
			if STEPS[step].id == "touch" and _cargo_kg() > 0.0:
				return Vector3.INF       # касаться можно и груза — идти никуда не нужно
			var m = _field("mining")
			var best := Vector3.INF
			if m != null:
				for c in m.crystals():
					var p: Vector3 = c.global_position
					if best == Vector3.INF or p.distance_to(r.global_position) < best.distance_to(r.global_position):
						best = p
			# Друзы далеко и под землёй: сначала — ко входу в пещеру.
			var t = _field("terrain")
			if best != Vector3.INF and t != null and best.distance_to(r.global_position) > 18.0:
				var entry: Vector3 = t.cave_entry
				if entry.distance_to(r.global_position) > 4.0:
					return entry + Vector3(0, 1.0, 0)
			return best
		"unload":
			var net = _field("pneu")
			var view = _field("pneu_view")
			if net == null or view == null:
				return Vector3.INF
			var best := Vector3.INF
			for c in net.parts:
				if net.parts[c].kind != "intake":
					continue
				var p: Vector3 = ProtoPneumatics.cell_pos(view.origin, c)
				if best == Vector3.INF or p.distance_to(r.global_position) < best.distance_to(r.global_position):
					best = p
			return best
	return Vector3.INF

# ---------------------------------------------------------------- вид

func _update_marker(_dt: float) -> void:
	if _marker == null or not _marker.is_inside_tree():
		return
	var t := target() if _done_t < 0.0 else Vector3.INF
	var r := _robot()
	var far := t != Vector3.INF and r != null and t.distance_to(r.global_position) > NEAR_M
	_marker.visible = far
	if far:
		var bob := sin(Time.get_ticks_msec() * 0.004) * 0.15
		_marker.global_position = t + Vector3(0, 1.4 + bob, 0)
		_marker.text = "▼\n%d м" % roundi(t.distance_to(r.global_position))
	var cam := get_viewport().get_camera_3d()
	var w := ""
	if far and cam != null:
		w = "▼ %d м, %s" % [roundi(t.distance_to(r.global_position)),
			direction_word(-cam.global_transform.basis.z, t - r.global_position)]
	if _where.text != w:
		_where.text = w
	_where.visible = w != ""

## Панель — под подписью планеты (её высота зависит от длины текста).
func _place() -> void:
	var cap := root.get_node_or_null("caption") if root != null else null
	var y := 150.0
	if cap != null and cap.visible and cap.get_child_count() > 0:
		var l := cap.get_child(0) as Control
		if l != null:
			y = maxf(y, (l.position.y + l.size.y) / maxf(_root_c.scale.y, 0.01) + 12.0)
	# В ране слева сверху — панель цели (ProtoRunUi): встаём под неё.
	var ui = _field("run_ui")
	var gp = ui.get("_goal_panel") if ui != null else null
	if gp is Control and gp.visible:
		y = maxf(y, gp.position.y + gp.size.y + 12.0)
	_panel.position.y = y

## Куда идти относительно камеры: «впереди», «сзади справа»…
static func direction_word(cam_fwd: Vector3, to: Vector3) -> String:
	var f := Vector2(cam_fwd.x, cam_fwd.z).normalized()
	var d := Vector2(to.x, to.z).normalized()
	var a := rad_to_deg(f.angle_to(d))          # >0 — по часовой в плоскости XZ, то есть вправо
	var words := ["впереди", "впереди справа", "справа", "сзади справа", "сзади",
		"сзади слева", "слева", "впереди слева"]
	return words[posmod(roundi(a / 45.0), 8)]

func _redraw() -> void:
	var sig := str([step, pad, _done_t >= 0.0, snappedf(_hold, 0.05)])
	if sig == _sig:
		return
	_sig = sig
	var s: Dictionary = STEPS[step]
	_count.text = "%d из %d" % [step + 1, STEPS.size()]
	if _done_t >= 0.0:
		_head.text = "✓ " + s.title
		_head.add_theme_color_override("font_color", ProtoHud.OK)
	else:
		_head.text = s.title
		_head.add_theme_color_override("font_color", ProtoHud.TEXT)
	_body.text = step_text(step, pad)
	var g := chips(ProtoHud.glyph([SKIP], pad), pad)
	_foot.text = "[color=#a8afb8]Держать %s — пропустить шаг, дольше — закрыть обучение[/color]" % g
	_bar.custom_minimum_size.x = (WIDTH - 28.0) * clampf(_hold / HOLD_ALL, 0.0, 1.0)
	_bar.visible = _hold > 0.0

func _label(t: String, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("outline_size", 4)
	return l

func _rich(size: int) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.custom_minimum_size.x = WIDTH - 28.0
	r.add_theme_font_size_override("normal_font_size", size)
	r.add_theme_font_size_override("bold_font_size", size)
	r.add_theme_color_override("default_color", ProtoHud.TEXT)
	r.add_theme_constant_override("line_separation", 4)
	return r
