class_name ProtoBuildMenu
extends CanvasLayer
## Каталог стройки (по мотивам меню Satisfactory и молота Valheim): вкладки по
## назначению, карточки деталей с картинками, справа — что деталь делает и
## сколько давления выдержит из выбранного материала. Выбранная деталь ложится
## в ячейку быстрой панели ProtoBuilder и сразу — в руки.
##   Геймпад: LB/RB — вкладка, D-pad / L-стик — деталь, A — взять, X — материал,
##            B — назад к стройке, Y — выйти из стройки.
##   Клавиатура: Q/E — вкладка, стрелки / WASD — деталь, Enter / Пробел — взять,
##            M — материал, Esc — назад, B — выйти; мышь — навести и щёлкнуть.
## Пока каталог открыт, робот стоит (мета "ui_busy"), мышь свободна.

const CATS := [
	{"n": "Пневматика", "kinds": ["pipe", "pump", "intake", "relief"]},
	{"n": "Логистика", "kinds": ["splitter", "sorter", "buffer", "cannon"]},
	{"n": "Обработка", "kinds": ["crusher", "furnace", "filter", "condenser", "treater", "compressor",
		"decompressor", "distiller", "centrifuge", "magnet_sep", "electrolyzer", "sinter",
		"irradiator", "cryochamber", "resonator", "loom"]},
	{"n": "Склад и наука", "kinds": ["tank", "lab", "lamp"]},
	{"n": "Цели и климат", "kinds": ["launch_silo", "beacon", "dome", "vent"]},
]
## Что деталь делает — для деталей без процесса (у машин — Processes.desc).
const DESC := {
	"pipe": "Везёт капсулы по направлению стрелки. Принимает с любой стороны, кроме выхода. Соседние детали — одна газовая сеть.",
	"pump": "Качает воздух снаружи в сеть — до 75% предела своего материала. Без давления капсулы стоят.",
	"intake": "Сюда робот выгружает добытое (C / X). Выпускает груз капсулами по 2 кг.",
	"relief": "Стравливает газ выше 80% предела своего материала. Сделайте его из того же, что трубы, и поставьте сразу за насосом — прочный насос не разорвёт слабую линию.",
	"splitter": "Делит поток: капсулы по очереди идут вперёд и в стороны, где стоит деталь. Занятый выход пропускается.",
	"sorter": "Первое пришедшее вещество запоминает и пускает прямо, всё остальное — вбок. Разобрать и поставить заново — сбросить.",
	"buffer": "Копит до 6 капсул, пока линия впереди занята, и отдаёт по одной. В пустоту не сыплет.",
	"cannon": "Копит давление (от 3 атм) и стреляет капсулой в ближайший приёмник впереди — до 12 клеток.",
	"tank": "Хранит продукцию завода — до 40 кг. Полный бак пропускает капсулы дальше, если за ним что-то стоит.",
	"lab": "Изучает вещества, которые через неё идут: знания о тегах — в карточку материала.",
	"lamp": "Светит у линий ночью. К газу сети не подключён.",
	"launch_silo": "Цель «Орбита»: копит груз и отправляет его на орбиту при достаточном давлении.",
	"beacon": "Цель «Маяк»: горит от 2 атм, нужен проводящий или кристаллический материал.",
	"dome": "Цель «Колония»: держит давление и тепло для поселенцев. Печь рядом греет, конденсатор остужает.",
	"vent": "Выпускает газ сети в небо: давление планеты растёт (терраформирование).",
}
const COLS := 5
const CARD := Vector2(116, 118)
const ICON := 128

var builder: ProtoBuilder
var open := false
var closed_frame := -1          # кадр, в котором каталог закрылся: та же кнопка стройку не трогает
var pad := false
var tab := 0
var item := 0

var _root: Control
var _tabs: VBoxContainer
var _grid: GridContainer
var _info: VBoxContainer
var _mat_row: HBoxContainer
var _hints: HBoxContainer
var _cards: Array = []
var _icons := {}               # вид → Texture2D (снимок модели)
var _icon_q: Array = []
var _icon_vp: SubViewport
var _icon_holder: Node3D
var _icon_wait := 0
var _icon_kind := ""
var _stick := Vector2.ZERO
var _mouse_mode := Input.MOUSE_MODE_VISIBLE

func setup(b: ProtoBuilder) -> void:
	builder = b

func _ready() -> void:
	layer = 11
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS      # картинки снимаются и на паузе
	_root = Control.new()
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.05, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(dim)
	var win := PanelContainer.new()
	win.add_theme_stylebox_override("panel", _box(Color(0.07, 0.08, 0.1, 0.96), Color(1, 1, 1, 0.1), 14, 18))
	win.position = Vector2(56, 40)
	win.size = Vector2(1168, 610)
	_root.add_child(win)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	win.add_child(col)
	# Шапка: заголовок и материал.
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	col.add_child(head)
	var title := _label("СТРОЙКА", 26, ProtoHud.TEXT)
	head.add_child(title)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	_mat_row = HBoxContainer.new()
	_mat_row.add_theme_constant_override("separation", 8)
	head.add_child(_mat_row)
	# Тело: вкладки | сетка | описание.
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 16)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(body)
	_tabs = VBoxContainer.new()
	_tabs.custom_minimum_size.x = 196
	_tabs.add_theme_constant_override("separation", 6)
	body.add_child(_tabs)
	_grid = GridContainer.new()
	_grid.columns = COLS
	_grid.add_theme_constant_override("h_separation", 8)
	_grid.add_theme_constant_override("v_separation", 8)
	_grid.custom_minimum_size.x = COLS * CARD.x + (COLS - 1) * 8
	body.add_child(_grid)
	var info_panel := PanelContainer.new()
	info_panel.add_theme_stylebox_override("panel", _box(Color(1, 1, 1, 0.04), Color(1, 1, 1, 0.06), 10, 14))
	info_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(info_panel)
	_info = VBoxContainer.new()
	_info.add_theme_constant_override("separation", 8)
	info_panel.add_child(_info)
	_hints = HBoxContainer.new()
	_hints.add_theme_constant_override("separation", 18)
	_hints.alignment = BoxContainer.ALIGNMENT_END
	col.add_child(_hints)
	get_viewport().size_changed.connect(_fit)
	_fit()
	_icon_setup()

func _fit() -> void:
	var vs := get_viewport().get_visible_rect().size
	var s := clampf(minf(vs.x / ProtoHud.BASE.x, vs.y / ProtoHud.BASE.y), 0.75, 2.0)
	_root.scale = Vector2(s, s)
	_root.size = vs / s

# ---------------------------------------------------------------- открыть / закрыть

func show_menu() -> void:
	if open:
		return
	open = true
	visible = true
	# Открыть на вкладке и детали, что сейчас в руках.
	var k := builder.kind()
	for i in CATS.size():
		var j: int = CATS[i].kinds.find(k)
		if j >= 0:
			tab = i
			item = j
	_mouse_mode = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_busy(true)
	_rebuild()

func hide_menu() -> void:
	if not open:
		return
	open = false
	visible = false
	closed_frame = Engine.get_process_frames()
	_busy(false)
	Input.mouse_mode = _mouse_mode

func _busy(on: bool) -> void:
	if builder != null and builder.robot != null:
		builder.robot.set_meta("ui_busy", on)

## Взять выбранную деталь в руки и вернуться к стройке.
func pick() -> void:
	builder.choose(kinds()[item])
	hide_menu()

func kinds() -> Array:
	return CATS[tab].kinds

func set_tab(i: int) -> void:
	tab = posmod(i, CATS.size())
	item = mini(item, kinds().size() - 1)
	_rebuild()

func move(d: Vector2i) -> void:
	var n := kinds().size()
	var i := item + d.x + d.y * COLS
	if d.y != 0 and (i < 0 or i >= n):
		return
	item = clampi(i, 0, n - 1)
	_rebuild()

# ---------------------------------------------------------------- ввод

func _input(e: InputEvent) -> void:
	if e is InputEventKey or e is InputEventMouseButton:
		pad = false
	elif e is InputEventJoypadButton or (e is InputEventJoypadMotion and absf(e.axis_value) > 0.5):
		pad = true
	if not open:
		return
	if e is InputEventMouse:
		return                                  # мышь — карточкам (gui_input)
	get_viewport().set_input_as_handled()
	if e is InputEventJoypadMotion:
		_stick_nav(e)
		return
	if not e.is_pressed():
		return
	var key: int = e.physical_keycode if e is InputEventKey else KEY_NONE
	var btn: int = e.button_index if e is InputEventJoypadButton else -1
	if e.is_echo() and not key in [KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN]:
		return                                  # повтор — только у стрелок
	if key == KEY_B or btn == JOY_BUTTON_Y:
		builder.exit_build()
	elif key == KEY_ESCAPE or btn == JOY_BUTTON_B:
		hide_menu()
	elif key in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE] or btn == JOY_BUTTON_A:
		pick()
	elif key == KEY_M or btn == JOY_BUTTON_X:
		builder.next_material()
		_rebuild()
	elif key == KEY_Q or btn == JOY_BUTTON_LEFT_SHOULDER:
		set_tab(tab - 1)
	elif key == KEY_E or btn == JOY_BUTTON_RIGHT_SHOULDER:
		set_tab(tab + 1)
	elif key in [KEY_LEFT, KEY_A] or btn == JOY_BUTTON_DPAD_LEFT:
		move(Vector2i(-1, 0))
	elif key in [KEY_RIGHT, KEY_D] or btn == JOY_BUTTON_DPAD_RIGHT:
		move(Vector2i(1, 0))
	elif key in [KEY_UP, KEY_W] or btn == JOY_BUTTON_DPAD_UP:
		move(Vector2i(0, -1))
	elif key in [KEY_DOWN, KEY_S] or btn == JOY_BUTTON_DPAD_DOWN:
		move(Vector2i(0, 1))
	elif key >= KEY_1 and key <= KEY_5:
		set_tab(key - KEY_1)

## Левый стик: шаг по сетке на выходе из мёртвой зоны.
func _stick_nav(e: InputEventJoypadMotion) -> void:
	if e.axis != JOY_AXIS_LEFT_X and e.axis != JOY_AXIS_LEFT_Y:
		return
	var prev := _stick
	if e.axis == JOY_AXIS_LEFT_X:
		_stick.x = e.axis_value
	else:
		_stick.y = e.axis_value
	var d := Vector2i.ZERO
	if absf(_stick.x) > 0.6 and absf(prev.x) <= 0.6:
		d.x = signi(int(signf(_stick.x)))
	if absf(_stick.y) > 0.6 and absf(prev.y) <= 0.6:
		d.y = signi(int(signf(_stick.y)))
	if d != Vector2i.ZERO:
		move(d)

# ---------------------------------------------------------------- отрисовка

func _rebuild() -> void:
	_clear(_tabs)
	for i in CATS.size():
		var t := PanelContainer.new()
		var on := i == tab
		t.add_theme_stylebox_override("panel", _box(Color(0.98, 0.76, 0.3, 0.16) if on else Color(1, 1, 1, 0.03),
			Color(0.98, 0.76, 0.3, 0.8) if on else Color(1, 1, 1, 0.06), 8, 10))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		t.add_child(row)
		var name_l := _label(CATS[i].n, 18, ProtoHud.TEXT if on else ProtoHud.DIM)
		name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_l)
		row.add_child(_label(str(CATS[i].kinds.size()), 15, ProtoHud.DIM))
		t.mouse_filter = Control.MOUSE_FILTER_STOP
		t.gui_input.connect(func(ev): if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT: set_tab(i))
		_tabs.add_child(t)
	var tab_keys := HBoxContainer.new()
	tab_keys.add_theme_constant_override("separation", 6)
	tab_keys.add_child(_chip("LB" if pad else "Q"))
	tab_keys.add_child(_chip("RB" if pad else "E"))
	tab_keys.add_child(_label("вкладка", 15, ProtoHud.DIM))
	_tabs.add_child(tab_keys)
	_clear(_grid)
	_cards.clear()
	var ks := kinds()
	for j in ks.size():
		var c := _card(ks[j], j == item)
		c.mouse_filter = Control.MOUSE_FILTER_STOP
		c.gui_input.connect(func(ev):
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
				item = j
				pick()
		)
		c.mouse_entered.connect(func():
			if item != j:
				item = j
				_fill_info()
				_restyle_cards()
		)
		_grid.add_child(c)
		_cards.append(c)
	_fill_mat()
	_fill_info()
	_fill_hints()

func _card(k: String, on: bool) -> PanelContainer:
	var c := PanelContainer.new()
	c.custom_minimum_size = CARD
	c.add_theme_stylebox_override("panel", _card_box(on))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	c.add_child(v)
	var tr := TextureRect.new()
	tr.name = "icon"
	tr.custom_minimum_size = Vector2(84, 76)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.texture = _icons.get(k)
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(tr)
	var l := _label(ProtoPneumatics.KINDS[k].n, 13, ProtoHud.TEXT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = CARD.x - 12
	v.add_child(l)
	return c

func _card_box(on: bool) -> StyleBoxFlat:
	return _box(Color(0.3, 0.6, 1.0, 0.2) if on else Color(1, 1, 1, 0.04),
		Color(0.45, 0.75, 1.0, 0.95) if on else Color(1, 1, 1, 0.08), 8, 6, 2 if on else 1)

func _restyle_cards() -> void:
	for j in _cards.size():
		_cards[j].add_theme_stylebox_override("panel", _card_box(j == item))

func _fill_mat() -> void:
	_clear(_mat_row)
	var sub := builder.material()
	_mat_row.add_child(_label("Материал", 16, ProtoHud.DIM))
	var sw := ColorRect.new()
	sw.color = sub.color
	sw.custom_minimum_size = Vector2(18, 18)
	sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_mat_row.add_child(sw)
	_mat_row.add_child(_label(sub.name, 18, ProtoHud.TEXT))
	if builder.mats.size() > 1:
		_mat_row.add_child(_label("%d из %d" % [builder.mat_i + 1, builder.mats.size()], 15, ProtoHud.DIM))
		_mat_row.add_child(_chip("X" if pad else "M"))

func _fill_info() -> void:
	_clear(_info)
	var k: String = kinds()[item]
	var info: Dictionary = ProtoPneumatics.KINDS[k]
	var sub := builder.material()
	var big := TextureRect.new()
	big.name = "big_icon"
	big.custom_minimum_size = Vector2(0, 150)
	big.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	big.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	big.texture = _icons.get(k)
	_info.add_child(big)
	_info.add_child(_label(info.n, 24, ProtoHud.TEXT))
	_info.add_child(_label(CATS[tab].n, 14, ProtoHud.DIM))
	var d := _label(describe(k), 15, ProtoHud.TEXT)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.custom_minimum_size.x = 260
	_info.add_child(d)
	for line in facts(k, sub):
		var l := _label(line[0], 15, ProtoHud.OK if line[1] == "ok" else (ProtoHud.WARN if line[1] == "warn" else ProtoHud.DIM))
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = 260
		_info.add_child(l)
	var h := builder.hotbar.find(k)
	_info.add_child(_label("На быстрой панели: ячейка %d" % (h + 1) if h >= 0 else "Возьмёте — встанет в ячейку %d панели" % (builder.slot + 1), 14, ProtoHud.DIM))

## Что деталь делает: своё описание или описание процесса машины.
static func describe(k: String) -> String:
	if DESC.has(k):
		return DESC[k]
	var pid: String = ProtoPneumatics.KINDS[k].get("process", "")
	if pid != "" and Processes.PROCESSES.has(pid):
		return Processes.PROCESSES[pid].desc
	return ""

## Цифры детали: [[строка, тон]] — предел давления из материала, давление для работы, выходы.
static func facts(k: String, sub: Substance) -> Array:
	var info: Dictionary = ProtoPneumatics.KINDS[k]
	var out: Array = []
	var st := ComponentStats.compute(info.stat, sub)
	if not info.get("nogas", false):
		out.append(["Держит %.1f атм из «%s»" % [st.max_p, sub.name], "ok"])
	var pid: String = info.get("process", "")
	if pid != "" and Processes.PROCESSES.has(pid):
		var pr: Dictionary = Processes.PROCESSES[pid]
		if pr.get("gas_min", 0.0) > 0.0:
			out.append(["Работает от %.1f атм" % pr.gas_min, "warn" if pr.gas_min > st.max_p * ProtoPneumatics.PUMP_SAFE else "dim"])
		out.append(["Вход сзади · %s" % ("два выхода: вперёд и вправо" if int(pr.get("outs", 1)) > 1 else "выход вперёд"), "dim"])
	if k == "relief":
		out.append(["Открывается с %.1f атм" % (st.max_p * ProtoPneumatics.RELIEF_K), "dim"])
	if info.has("cap"):
		out.append(["Вмещает %.0f кг" % info.cap, "dim"])
	if k == "buffer":
		out.append(["Вмещает %d капсул" % ProtoPneumatics.BUFFER_N, "dim"])
	return out

func _fill_hints() -> void:
	_clear(_hints)
	for h in [["A" if pad else "Enter", "Взять в руки"], ["LB RB" if pad else "Q E", "Вкладка"],
			["X" if pad else "M", "Материал"], ["B" if pad else "Esc", "Назад"], ["Y" if pad else "B", "Выйти из стройки"]]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		for g in h[0].split(" "):
			row.add_child(_chip(g))
		row.add_child(_label(h[1], 16, ProtoHud.TEXT))
		_hints.add_child(row)

# ---------------------------------------------------------------- картинки деталей

## Снимки моделей деталей: по одной за пару кадров в своём мире (SubViewport),
## чтобы открытие каталога не встало на Deck. Готовые — в _icons.
func _icon_setup() -> void:
	_icon_vp = SubViewport.new()
	_icon_vp.size = Vector2i(ICON, ICON)
	_icon_vp.transparent_bg = true
	_icon_vp.own_world_3d = true
	_icon_vp.msaa_3d = Viewport.MSAA_4X
	_icon_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_icon_vp)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_CLEAR_COLOR
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.75, 0.78, 0.85)
	e.ambient_light_energy = 0.9
	env.environment = e
	_icon_vp.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.9, 0.6, 0)
	sun.light_energy = 1.4
	_icon_vp.add_child(sun)
	var cam := Camera3D.new()
	cam.name = "cam"
	cam.fov = 30.0
	_icon_vp.add_child(cam)
	_icon_holder = Node3D.new()
	_icon_vp.add_child(_icon_holder)
	for c in CATS:
		_icon_q.append_array(c.kinds)

## Все ли картинки готовы (для кадров и тестов).
func icons_ready() -> bool:
	return _icon_q.is_empty() and _icon_kind == ""

func _process(_dt: float) -> void:
	if _icon_vp == null or (not open and _icons.is_empty() and builder != null and not builder.active):
		return                                 # снимаем, когда стройка впервые понадобилась
	if _icon_kind != "":
		_icon_wait -= 1
		if _icon_wait > 0:
			return
		var img := _icon_vp.get_texture().get_image()
		_icons[_icon_kind] = ImageTexture.create_from_image(img)
		_icon_kind = ""
		_icon_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		if open:
			_refresh_icons()
	if _icon_q.is_empty():
		return
	_icon_kind = _icon_q.pop_front()
	for ch in _icon_holder.get_children():
		ch.queue_free()
	var links: Array = [1, 3] if _icon_kind == "pipe" else ([1] if _icon_kind in ["relief"] else [])
	var n := ProtoPneumaticsView.build_part(_icon_kind, builder.material(), 1, links)
	_icon_holder.add_child(n)
	var model := n.get_node_or_null("model")
	var h: float = float(model.get_meta("h", 1.2)) * ProtoPneumaticsView.MODEL_SCALE if model != null else 0.8
	var size := maxf(h, 1.15)
	var cam := _icon_vp.get_node("cam") as Camera3D
	var look := Vector3(0, h * 0.45, 0)
	cam.position = look + Vector3(1.0, 0.75, 1.25).normalized() * size * 2.3
	cam.look_at(look, Vector3.UP)
	_icon_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	_icon_wait = 2

func _refresh_icons() -> void:
	var ks := kinds()
	for j in _cards.size():
		var tr := _cards[j].find_child("icon", true, false) as TextureRect
		if tr != null and tr.texture == null:
			tr.texture = _icons.get(ks[j])
	var big := _info.find_child("big_icon", true, false) as TextureRect
	if big != null and big.texture == null:
		big.texture = _icons.get(ks[item])

func icon(k: String) -> Texture2D:
	return _icons.get(k)

# ---------------------------------------------------------------- виджеты

static func _box(bg: Color, edge: Color, r: int, m: int, w := 1) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = edge
	sb.set_border_width_all(w)
	sb.set_corner_radius_all(r)
	sb.set_content_margin_all(m)
	return sb

func _label(t: String, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _chip(t: String) -> PanelContainer:
	var p := PanelContainer.new()
	var round := pad and ProtoHud.PAD_COLORS.has(t)
	var sb := _box(ProtoHud.PAD_COLORS[t] if round else Color(0.22, 0.24, 0.28), Color(1, 1, 1, 0.35), 14 if round else 6, 0)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	p.add_theme_stylebox_override("panel", sb)
	p.custom_minimum_size = Vector2(28, 26)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := _label(t, 15, Color.WHITE)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	p.add_child(l)
	return p

func _clear(c: Node) -> void:
	for ch in c.get_children():
		c.remove_child(ch)
		ch.queue_free()
