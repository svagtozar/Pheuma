extends Control
## Меню: главное, пауза, слоты сохранения, настройки, завершение рана.

var main
var panels := {}
var slots_box: VBoxContainer
var slots_title: Label
var slots_mode := "load"        # load | save
var seed_edit: LineEdit
var end_label: RichTextLabel
var continue_btn: Button
var _back := ""                 # куда вернуться из слотов/настроек

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	_layout()
	get_viewport().size_changed.connect(_layout)

func _layout() -> void:
	var vp: Vector2 = get_viewport_rect().size / (main.ui_scale if main != null else 1.0)
	size = vp
	for k in panels:
		var p: Control = panels[k]
		p.position = (vp - p.get_combined_minimum_size()) / 2.0

func any_open() -> bool:
	for k in panels:
		if panels[k].visible:
			return true
	return false

func close_all() -> void:
	for k in panels:
		panels[k].visible = false

func show_panel(name: String) -> void:
	close_all()
	panels[name].visible = true
	_layout()

# ---------------------------------------------------------------- построение

func _panel(name: String, width: float) -> VBoxContainer:
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(width, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.07, 0.1, 0.95)
	sb.border_color = Color(0.3, 0.55, 0.8)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(18)
	p.add_theme_stylebox_override("panel", sb)
	p.visible = false
	add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	p.add_child(v)
	panels[name] = p
	return v

func _title(v: VBoxContainer, text: String, size: int = 22) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	v.add_child(l)
	return l

func _button(v: Container, text: String, f: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 38)
	b.add_theme_font_size_override("font_size", 16)
	b.pressed.connect(f)
	v.add_child(b)
	return b

func _build() -> void:
	# Главное меню.
	var m := _panel("main", 420)
	var t := _title(m, "PNEUMA", 48)
	t.add_theme_color_override("font_color", Color(0.6, 0.85, 1.0))
	var sub := _title(m, "робот, процедурная планета, пневматика и теги", 14)
	sub.add_theme_color_override("font_color", Color(0.6, 0.65, 0.7))
	continue_btn = _button(m, "Продолжить", func(): main.menu_continue())
	_button(m, "Новая планета", func(): main.menu_new_game(-1))
	var sh := HBoxContainer.new()
	m.add_child(sh)
	seed_edit = LineEdit.new()
	seed_edit.placeholder_text = "seed планеты"
	seed_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	seed_edit.add_theme_font_size_override("font_size", 15)
	seed_edit.text_submitted.connect(func(_t): _new_by_seed())
	sh.add_child(seed_edit)
	var sb := Button.new()
	sb.text = "По seed"
	sb.add_theme_font_size_override("font_size", 15)
	sb.pressed.connect(_new_by_seed)
	sh.add_child(sb)
	_button(m, "Обучение", func(): main.menu_tutorial())
	_button(m, "Загрузить", func(): open_slots("load", "main"))
	_button(m, "Настройки", func(): open_settings("main"))
	_button(m, "Выход", func(): main.get_tree().quit())

	# Пауза.
	var p := _panel("pause", 380)
	_title(p, "Пауза")
	_button(p, "Продолжить (Esc)", func(): close_all())
	_button(p, "Сохранить", func(): open_slots("save", "pause"))
	_button(p, "Загрузить", func(): open_slots("load", "pause"))
	_button(p, "Настройки", func(): open_settings("pause"))
	_button(p, "Справка (H)", func():
		close_all()
		main.hud.toggle("help"))
	_button(p, "В главное меню", func(): main.open_main_menu())
	_button(p, "Выход из игры", func(): main.get_tree().quit())

	# Слоты.
	var s := _panel("slots", 640)
	slots_title = _title(s, "Загрузка")
	slots_box = VBoxContainer.new()
	slots_box.add_theme_constant_override("separation", 6)
	s.add_child(slots_box)
	_button(s, "Назад", func(): show_panel(_back))

	# Настройки.
	_build_settings()

	# Завершение рана.
	var e := _panel("end", 560)
	_title(e, "Цель планеты достигнута!", 24)
	end_label = RichTextLabel.new()
	end_label.bbcode_enabled = true
	end_label.fit_content = true
	end_label.custom_minimum_size = Vector2(520, 0)
	end_label.add_theme_font_size_override("normal_font_size", 15)
	e.add_child(end_label)
	_button(e, "Остаться на этой планете", func(): close_all())
	_button(e, "Новая планета", func(): main.menu_new_game(-1))
	_button(e, "В главное меню", func(): main.open_main_menu())

func _new_by_seed() -> void:
	var txt := seed_edit.text.strip_edges()
	if txt.is_valid_int():
		main.menu_new_game(int(txt))
	else:
		main.menu_new_game(abs(hash(txt)) % 1000000 if txt != "" else -1)

# ---------------------------------------------------------------- главное меню

func show_main() -> void:
	var latest := SaveGame.latest_slot()
	continue_btn.visible = latest != ""
	if latest != "":
		var md := SaveGame.slot_meta(latest)
		continue_btn.text = "Продолжить — %s, %s" % [md.get("planet", "?"), SaveGame.slot_title(latest)]
	show_panel("main")

# ---------------------------------------------------------------- слоты

func open_slots(mode: String, back: String) -> void:
	slots_mode = mode
	_back = back
	_rebuild_slots()
	show_panel("slots")

func _rebuild_slots() -> void:
	slots_title.text = "Сохранить в слот" if slots_mode == "save" else "Загрузить"
	for c in slots_box.get_children():
		c.queue_free()
	var slots: Array = SaveGame.SLOTS if slots_mode == "save" else SaveGame.all_slots()
	for slot in slots:
		var md := SaveGame.slot_meta(slot)
		var row := PanelContainer.new()
		var st := StyleBoxFlat.new()
		st.bg_color = Color(0.11, 0.12, 0.16)
		st.set_corner_radius_all(4)
		st.set_content_margin_all(8)
		row.add_theme_stylebox_override("panel", st)
		slots_box.add_child(row)
		var h := HBoxContainer.new()
		row.add_child(h)
		var info := Label.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_theme_font_size_override("font_size", 14)
		if md.is_empty():
			info.text = "%s — пусто" % SaveGame.slot_title(slot)
			info.add_theme_color_override("font_color", Color(0.5, 0.5, 0.55))
		else:
			var stage := "выполнена" if md.get("completed", false) else "этап %d/%d" % [int(md.get("stage", 0)), int(md.get("stages", 0))]
			info.text = "%s — %s%s\n%s, %s · %s · %s" % [SaveGame.slot_title(slot), md.get("planet", "?"),
				" (обучение)" if md.get("tutorial", false) else "", md.get("goal", ""), stage,
				SaveGame.format_time(float(md.get("time", 0.0))), str(md.get("date", "")).replace("T", " ")]
		h.add_child(info)
		var sl: String = slot
		if slots_mode == "save":
			var b := Button.new()
			b.text = "Перезаписать" if not md.is_empty() else "Сохранить"
			b.pressed.connect(func():
				main.say(main.save_to(sl))
				_rebuild_slots())
			h.add_child(b)
		elif not md.is_empty():
			var b := Button.new()
			b.text = "Загрузить"
			b.pressed.connect(func(): main.load_from(sl))
			h.add_child(b)
		if not md.is_empty() and slot != "auto":
			var d := Button.new()
			d.text = "Удалить"
			d.pressed.connect(func():
				SaveGame.delete_slot(sl)
				_rebuild_slots())
			h.add_child(d)

# ---------------------------------------------------------------- настройки

var vol_slider: HSlider
var scale_slider: HSlider
var scale_label: Label
var full_check: CheckBox
var advice_check: CheckBox
var autosave_opt: OptionButton
const AUTOSAVE := [0.0, 60.0, 120.0, 300.0]
const AUTOSAVE_NAMES := ["выключено", "каждую минуту", "каждые 2 минуты", "каждые 5 минут"]

func _build_settings() -> void:
	var v := _panel("settings", 480)
	_title(v, "Настройки")
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 16)
	v.add_child(g)
	var add_label := func(text: String):
		var l := Label.new()
		l.text = text
		l.add_theme_font_size_override("font_size", 15)
		g.add_child(l)
	add_label.call("Громкость")
	vol_slider = HSlider.new()
	vol_slider.min_value = 0.0
	vol_slider.max_value = 1.0
	vol_slider.step = 0.05
	vol_slider.custom_minimum_size = Vector2(240, 24)
	vol_slider.value_changed.connect(func(x): main.set_setting("volume", x); main.apply_settings())
	g.add_child(vol_slider)
	scale_label = Label.new()
	scale_label.add_theme_font_size_override("font_size", 15)
	g.add_child(scale_label)
	scale_slider = HSlider.new()
	scale_slider.min_value = 0.75
	scale_slider.max_value = 1.75
	scale_slider.step = 0.05
	scale_slider.custom_minimum_size = Vector2(240, 24)
	scale_slider.drag_ended.connect(func(_c): main.set_setting("ui_scale", scale_slider.value); main.apply_settings())
	scale_slider.value_changed.connect(func(x): scale_label.text = "Масштаб интерфейса ×%.2f" % x)
	g.add_child(scale_slider)
	add_label.call("Полный экран")
	full_check = CheckBox.new()
	full_check.text = "включить"
	full_check.toggled.connect(func(on): main.set_setting("fullscreen", on); main.apply_settings())
	g.add_child(full_check)
	add_label.call("Советы «что дальше»")
	advice_check = CheckBox.new()
	advice_check.text = "показывать"
	advice_check.toggled.connect(func(on): main.set_setting("advice", on); main.apply_settings())
	g.add_child(advice_check)
	add_label.call("Автосохранение")
	autosave_opt = OptionButton.new()
	for i in AUTOSAVE_NAMES.size():
		autosave_opt.add_item(AUTOSAVE_NAMES[i], i)
	autosave_opt.item_selected.connect(func(i): main.set_setting("autosave", AUTOSAVE[i]); main.apply_settings())
	g.add_child(autosave_opt)
	_button(v, "Назад", func(): show_panel(_back))

func open_settings(back: String) -> void:
	_back = back
	var st: Dictionary = main.settings()
	vol_slider.set_value_no_signal(float(st.get("volume", 0.8)))
	scale_slider.value = float(st.get("ui_scale", 1.0))
	full_check.set_pressed_no_signal(st.get("fullscreen", false))
	advice_check.set_pressed_no_signal(st.get("advice", true))
	autosave_opt.select(max(0, AUTOSAVE.find(float(st.get("autosave", 120.0)))))
	show_panel("settings")

# ---------------------------------------------------------------- завершение рана

func show_run_end(w: World) -> void:
	var r := w.robot
	var s := "[b]%s[/b] — %s\n\n" % [w.planet.name, w.planet.goal.n]
	s += "Время: %s\n" % SaveGame.format_time(w.time)
	s += "Машин построено: %d, выстрелов пушек: %d, попаданий: %d\n" % [w.machines.size(), w.stats.shots, w.stats.hits]
	s += "Отправлено на орбиту: %.0f кг\n" % w.launched.mass
	s += "Известно тегов: %d из %d, взаимодействий: %d\n" % [r.known_tags.size(), MaterialTags.TAGS.size(), r.known_interactions.size()]
	s += "Изучено узлов прокачки: %d, знаний осталось: %d\n" % [r.learned.size(), r.knowledge]
	var best := ""
	var bx := -1.0
	for c in r.xp:
		if r.xp[c] > bx:
			bx = r.xp[c]
			best = c
	s += "Главная роль робота: [color=#ffd479]%s[/color]" % SkillTree.CLASSES[best].n
	end_label.text = s
	show_panel("end")
