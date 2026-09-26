extends Control
## Интерфейс: панели состояния, инвентарь, инспектор, окна (палитра построек,
## прокачка, фабрикатор, справочник, помощь, брифинг планеты).

var main
var world: World

var info_label: Label
var goal_label: Label
var log_label: Label
var status_label: Label
var msg_label: Label
var inv_list: ItemList
var inspector_panel: PanelContainer
var inspector_label: Label
var inspector_buttons: HFlowContainer
var windows := {}
var palette_mat: OptionButton
var palette_box: VBoxContainer
var skills_box: HBoxContainer
var skills_title: Label
var fab_box: VBoxContainer
var fab_bp := ""
var fab_mat: OptionButton
var codex_label: RichTextLabel
var briefing_label: RichTextLabel

var _placed: Array = []       # [Control, anchor, offset]
var _inv_sig := ""
var _insp_sig := ""
var _t := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	_layout()
	get_viewport().size_changed.connect(_layout)

## Раскладка вручную: anchor — угол экрана, offset — смещение от него.
func _layout() -> void:
	var vp := get_viewport_rect().size
	size = vp
	for e in _placed:
		var c: Control = e[0]
		var off: Vector2 = e[2]
		var sz := c.get_combined_minimum_size()
		match e[1]:
			Control.PRESET_TOP_LEFT: c.position = off
			Control.PRESET_TOP_RIGHT: c.position = Vector2(vp.x + off.x, off.y)
			Control.PRESET_BOTTOM_RIGHT: c.position = Vector2(vp.x + off.x, vp.y - sz.y - off.y)
			Control.PRESET_CENTER_BOTTOM: c.position = Vector2(vp.x / 2.0 + off.x, vp.y - sz.y - off.y)
			Control.PRESET_CENTER: c.position = (vp - sz) / 2.0

func set_world(w: World) -> void:
	world = w
	_inv_sig = ""
	_insp_sig = ""
	close_all()

# ---------------------------------------------------------------- построение

func _panel(pos: Vector2, size: Vector2, anchor: int = Control.PRESET_TOP_LEFT) -> PanelContainer:
	var p := PanelContainer.new()
	p.custom_minimum_size = size
	_placed.append([p, anchor, pos])
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.07, 0.09, 0.82)
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(8)
	p.add_theme_stylebox_override("panel", sb)
	add_child(p)
	return p

func _label(parent: Node, size: int = 13) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(l)
	return l

func _window(name: String, size: Vector2, title: String) -> VBoxContainer:
	var p := PanelContainer.new()
	p.custom_minimum_size = size
	_placed.append([p, Control.PRESET_CENTER, Vector2.ZERO])
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.08, 0.11, 0.96)
	sb.border_color = Color(0.3, 0.5, 0.7)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(12)
	p.add_theme_stylebox_override("panel", sb)
	p.visible = false
	add_child(p)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = size - Vector2(24, 24)
	p.add_child(scroll)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	var t := _label(head, 18)
	t.text = title
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var close := Button.new()
	close.text = "✕"
	close.pressed.connect(func(): p.visible = false)
	head.add_child(close)
	windows[name] = p
	return v

func _build() -> void:
	var tl := _panel(Vector2(8, 8), Vector2(330, 0))
	info_label = _label(tl, 12)
	var tr := _panel(Vector2(-488, 8), Vector2(480, 0), Control.PRESET_TOP_RIGHT)
	goal_label = _label(tr, 13)

	var invp := _panel(Vector2(8, 190), Vector2(330, 0))
	var iv := VBoxContainer.new()
	invp.add_child(iv)
	var it := _label(iv, 13)
	it.text = "Инвентарь (Tab — выбор, клик — выбрать)"
	inv_list = ItemList.new()
	inv_list.custom_minimum_size = Vector2(314, 180)
	inv_list.add_theme_font_size_override("font_size", 12)
	inv_list.item_selected.connect(_on_inv_selected)
	iv.add_child(inv_list)

	inspector_panel = _panel(Vector2(-398, 140), Vector2(390, 0), Control.PRESET_TOP_RIGHT)
	var insp := VBoxContainer.new()
	inspector_panel.add_child(insp)
	inspector_label = _label(insp, 12)
	inspector_label.custom_minimum_size = Vector2(374, 0)
	inspector_buttons = HFlowContainer.new()
	insp.add_child(inspector_buttons)
	inspector_panel.visible = false

	var bp := _panel(Vector2(-420, 8), Vector2(840, 0), Control.PRESET_CENTER_BOTTOM)
	status_label = _label(bp, 13)
	var lp := _panel(Vector2(-488, 110), Vector2(480, 0), Control.PRESET_BOTTOM_RIGHT)
	log_label = _label(lp, 11)
	msg_label = Label.new()
	_placed.append([msg_label, Control.PRESET_CENTER_BOTTOM, Vector2(-400, 120)])
	msg_label.custom_minimum_size = Vector2(800, 30)
	msg_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg_label.add_theme_font_size_override("font_size", 16)
	msg_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	msg_label.add_theme_color_override("font_outline_color", Color.BLACK)
	msg_label.add_theme_constant_override("outline_size", 4)
	add_child(msg_label)

	# Палитра построек.
	var pv := _window("palette", Vector2(820, 600), "Постройки (B)")
	var mh := HBoxContainer.new()
	pv.add_child(mh)
	var ml := _label(mh, 13)
	ml.autowrap_mode = TextServer.AUTOWRAP_OFF
	ml.text = "Материал:"
	palette_mat = OptionButton.new()
	palette_mat.custom_minimum_size = Vector2(500, 0)
	mh.add_child(palette_mat)
	palette_mat.item_selected.connect(func(_i): _rebuild_palette())
	palette_box = VBoxContainer.new()
	pv.add_child(palette_box)

	# Прокачка.
	var sv := _window("skills", Vector2(1180, 600), "Прокачка (K)")
	skills_title = _label(sv, 14)
	skills_box = HBoxContainer.new()
	skills_box.add_theme_constant_override("separation", 10)
	sv.add_child(skills_box)

	# Фабрикатор.
	fab_box = _window("fabricator", Vector2(900, 580), "Фабрикатор и модули (F)")

	# Справочник.
	var cv := _window("codex", Vector2(900, 620), "Справочник тегов (J)")
	codex_label = RichTextLabel.new()
	codex_label.bbcode_enabled = true
	codex_label.fit_content = true
	codex_label.custom_minimum_size = Vector2(860, 0)
	codex_label.add_theme_font_size_override("normal_font_size", 13)
	cv.add_child(codex_label)

	# Помощь.
	var hv := _window("help", Vector2(760, 620), "Управление (H)")
	var help := _label(hv, 13)
	help.text = HELP

	# Брифинг.
	var brv := _window("briefing", Vector2(820, 600), "Высадка")
	briefing_label = RichTextLabel.new()
	briefing_label.bbcode_enabled = true
	briefing_label.fit_content = true
	briefing_label.custom_minimum_size = Vector2(780, 0)
	briefing_label.add_theme_font_size_override("normal_font_size", 14)
	brv.add_child(briefing_label)
	var go := Button.new()
	go.text = "Начать (Enter)"
	go.pressed.connect(func(): windows.briefing.visible = false)
	brv.add_child(go)

const HELP := """Движение — WASD / стрелки. Колесо мыши — масштаб.
E (удерживать) — копать залежь под курсором или рядом.
Z — анализ касанием: материал в соседней клетке или выбранный в инвентаре.
Tab / [ ] — выбрать материал в инвентаре.
G (удерживать) — подкачать бортовой баллон (от бака/трубы рядом или вручную из атмосферы).

B — постройки. ЛКМ — поставить, R — повернуть, ПКМ/Esc — отмена. Трубы можно тянуть.
X — снос (возврат половины материала). ЛКМ по машине — инспектор и настройки.
Q — положить 1 кг выбранного в машину под курсором (Ctrl — 5 кг, Shift — в боковой вход: реагент/источник).
T — забрать груз из машины под курсором.
L — навести пневмопушку: клик по пушке, затем по приёмнику.
V — провод: клик по источнику сигнала, затем по приёмнику (Shift — во второй вход гейта).
   Провод делается из выбранного материала; проводящий дотягивается дальше.
   ЛКМ по проводу — добавить путевую точку, тянуть — двигать, ПКМ по точке — удалить.

1–6 — абилки установленных модулей (цель — курсор).
F — фабрикатор (рядом с ним): модули и детали робота из любого подходящего материала.
K — прокачка: шесть классов. Знания дают открытия, опыт — действия класса.
J — справочник тегов: как теги меняют обращение с материалом и как их получить.
P — пауза. Shift+N — новая планета. H — эта справка.

Выход машин — по стрелке, второй выход (у разделителей) — голубая стрелка справа.
Вход — сзади и сбоку; у обработчика и облучателя левый бок — вход реагента/источника.
Каждая постройка сделана из материала и наследует его свойства: предельное давление,
жаростойкость, стойкость к кислоте, проводимость — смотрите инспектор."""

# ---------------------------------------------------------------- окна

func toggle(name: String) -> void:
	var w: Control = windows[name]
	var show := not w.visible
	for k in windows:
		if k != "briefing":
			windows[k].visible = false
	w.visible = show
	_layout()
	if show:
		match name:
			"palette": _open_palette()
			"skills": _rebuild_skills()
			"fabricator": _rebuild_fab()
			"codex": _rebuild_codex()

func close_all() -> void:
	for k in windows:
		if k != "briefing":
			windows[k].visible = false

func blocks_game() -> bool:
	return windows.briefing.visible or windows.help.visible

func handle_key(e: InputEventKey) -> bool:
	if windows.briefing.visible:
		if e.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE, KEY_ESCAPE]:
			windows.briefing.visible = false
		return true
	if e.keycode == KEY_J:
		toggle("codex")
		return true
	return false

func show_briefing() -> void:
	var p := world.planet
	var s := "[font_size=22][b]%s[/b][/font_size]   seed %d\n\n" % [p.name, p.seed_value]
	s += "[b]Теги планеты[/b]\n"
	for t in p.tags:
		var d: Dictionary = PlanetTags.TAGS[t]
		var col := "#d9a0ff" if d.get("anomaly", false) else "#9fd4ff"
		s += "  [color=%s]%s[/color] — %s\n" % [col, d.n, d.desc]
	s += "\n[b]Среда[/b]: %.0f °C, атмосфера %.2f атм, гравитация %.2f g\n" % [p.ambient_temp, p.atm_pressure, p.gravity]
	s += "Материалов на планете: %d (теги неизвестны до анализа)\n\n" % p.materials.size()
	s += "[b]Цель: %s[/b]\n%s\n" % [p.goal.n, p.goal.desc]
	var i := 1
	for st in p.goal.stages:
		s += "  %d. %s\n" % [i, st.desc]
		i += 1
	if p.goal.has("rare") and p.goal.id == "mining":
		s += "  Редкий тег: [color=#ffd479]%s[/color]\n" % MaterialTags.display(p.goal.rare)
	s += "\nУ вас 60 кг сплава посадочной капсулы. Для начала: фабрикатор (B), бур на залежь, контейнер.\nH — управление."
	briefing_label.text = s
	windows.briefing.visible = true
	_layout()

func _eligible(check: Callable) -> Array:
	var out: Array = []
	var keys: Array = world.robot.inventory.keys()
	keys.sort()
	for id in keys:
		var sub := world.db.get_sub(id)
		if check.call(sub) == "":
			out.append(id)
	return out

func _fill_material_option(opt: OptionButton, ids: Array, keep: String) -> void:
	opt.clear()
	var sel := 0
	for i in ids.size():
		var sub := world.db.get_sub(ids[i])
		opt.add_item("%s — %.1f кг (тв. %.1f)" % [world.sub_label(sub), world.robot.mass_of(ids[i]), sub.hardness], i)
		opt.set_item_metadata(i, ids[i])
		if ids[i] == keep:
			sel = i
	if not ids.is_empty():
		opt.select(sel)

func _selected_meta(opt: OptionButton) -> String:
	if opt.item_count == 0 or opt.selected < 0:
		return ""
	return opt.get_item_metadata(opt.selected)

func _open_palette() -> void:
	var ids := _eligible(func(s): return "" if s.phase_at(world.planet.ambient_temp) == Substance.Phase.SOLID else "x")
	_fill_material_option(palette_mat, ids, main.build_sub_id if main.build_sub_id != "" else world.robot.selected)
	_rebuild_palette()

func _rebuild_palette() -> void:
	for c in palette_box.get_children():
		c.queue_free()
	var sub_id := _selected_meta(palette_mat)
	var sub: Substance = world.db.get_sub(sub_id) if sub_id != "" else null
	for ci in Buildings.CATS.size():
		var l := _label(palette_box, 14)
		l.text = Buildings.CATS[ci]
		var flow := HFlowContainer.new()
		palette_box.add_child(flow)
		for k in Buildings.KINDS:
			if Buildings.KINDS[k].cat != ci:
				continue
			var b := Button.new()
			b.text = "%s (%.0f кг)" % [Buildings.name_of(k), world.build_cost(k)]
			var reason := ""
			if not world.robot.unlocked.has(k):
				reason = "не изучено"
			elif sub != null:
				reason = Buildings.check_material(k, sub, world.planet.ambient_temp)
			b.tooltip_text = Buildings.desc_of(k) + ("\n\nНельзя: " + reason if reason != "" else "")
			if sub != null and reason == "":
				b.tooltip_text += "\n\nИз этого материала:\n" + "\n".join(ComponentStats.describe(k, sub, world.robot.passive("quality")))
			b.disabled = reason != ""
			b.pressed.connect(func():
				main.start_build(k, sub_id)
				windows.palette.visible = false)
			flow.add_child(b)

func _rebuild_skills() -> void:
	for c in skills_box.get_children():
		c.queue_free()
	var r := world.robot
	skills_title.text = "Знания: %d. Узлы требуют знаний и опыта класса; опыт растёт от действий этого класса." % r.knowledge
	for cls in SkillTree.CLASS_ORDER:
		var cd: Dictionary = SkillTree.CLASSES[cls]
		var col := VBoxContainer.new()
		col.custom_minimum_size = Vector2(180, 0)
		skills_box.add_child(col)
		var h := _label(col, 16)
		h.text = cd.n
		h.add_theme_color_override("font_color", cd.col)
		var d := _label(col, 11)
		d.text = "%s\nопыт: %d" % [cd.desc, int(r.xp[cls])]
		for n in SkillTree.nodes_of(cls):
			var b := Button.new()
			b.custom_minimum_size = Vector2(176, 44)
			b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			b.add_theme_font_size_override("font_size", 12)
			var learned: bool = r.learned.has(n.id)
			var why := Progression.can_learn(r, n.id)
			b.text = ("✓ " if learned else "") + "%s\n%d зн., опыт %d" % [n.n, n.cost, n.xp]
			b.tooltip_text = n.desc + ("" if learned or why == "" else "\n\n" + why)
			b.disabled = learned or why != ""
			var nid: String = n.id
			b.pressed.connect(func():
				main.say(Progression.learn(r, nid))
				_rebuild_skills())
			col.add_child(b)

func _rebuild_fab() -> void:
	for c in fab_box.get_children():
		if c.get_index() > 0:
			c.queue_free()
	var r := world.robot
	var near := false
	for m in world.machines_of("fabricator"):
		if world.near_robot(m.cell, 2.5):
			near = true
	var l := _label(fab_box, 13)
	l.text = "Изготовление доступно рядом с фабрикатором." if not near else "Выберите чертёж и материал. Свойства модуля зависят от материала."
	var bps := HFlowContainer.new()
	fab_box.add_child(bps)
	for k in Modules.MODULES:
		if not r.blueprints.has(k):
			continue
		var b := Button.new()
		b.text = Modules.MODULES[k].n
		b.toggle_mode = true
		b.button_pressed = k == fab_bp
		b.tooltip_text = Modules.MODULES[k].desc
		var kk: String = k
		b.pressed.connect(func():
			fab_bp = kk
			_rebuild_fab())
		bps.add_child(b)
	if fab_bp != "" and r.blueprints.has(fab_bp):
		var d: Dictionary = Modules.MODULES[fab_bp]
		var dl := _label(fab_box, 12)
		dl.text = "%s: %s\nСтоимость %.0f кг, твёрдость ≥ %.1f" % [d.n, d.desc, d.cost, d.get("hard", 0.0)]
		var h := HBoxContainer.new()
		fab_box.add_child(h)
		fab_mat = OptionButton.new()
		fab_mat.custom_minimum_size = Vector2(520, 0)
		h.add_child(fab_mat)
		var ids := _eligible(func(s): return Modules.check_material(fab_bp, s, world.planet.ambient_temp))
		_fill_material_option(fab_mat, ids, r.selected)
		var preview := _label(fab_box, 12)
		var upd := func():
			var sid := _selected_meta(fab_mat)
			if sid == "":
				preview.text = "Нет подходящего материала."
				return
			var sk: String = fab_bp if fab_bp in ["hull", "hand_drill"] else "module"
			var st := ComponentStats.compute(sk, world.db.get_sub(sid), r.passive("quality"))
			preview.text = "Прочность %.0f, твёрдость %.1f, масса %.1f, гибкость ×%.2f\nзащита: жар %d%%, радиация %d%%, яд %d%%, кислота %d%%" % [
				st.max_hp, st.hardness, st.mass, st.flex, st.shield_heat * 100, st.shield_radiation * 100, st.shield_toxic * 100, st.shield_acid * 100]
		upd.call()
		fab_mat.item_selected.connect(func(_i): upd.call())
		var go := Button.new()
		go.text = "Изготовить"
		go.disabled = not near or ids.is_empty()
		go.pressed.connect(func():
			main.say(world.fabricate(fab_bp, world.db.get_sub(_selected_meta(fab_mat))))
			_rebuild_fab())
		h.add_child(go)
	var sep := HSeparator.new()
	fab_box.add_child(sep)
	var ml := _label(fab_box, 13)
	ml.text = "Корпус: %s | Бур: %s | Слоты абилок: %d/%d" % [
		r.hull.sub.name if r.hull != null else "—", "%s (тв. %.1f)" % [r.drill.sub.name, r.drill.stats.hardness] if r.drill != null else "—",
		r.equipped.size(), r.slots()]
	for m in r.equipped:
		var hb := HBoxContainer.new()
		fab_box.add_child(hb)
		var t := _label(hb, 12)
		t.text = "● %s из %s" % [Modules.MODULES[m.kind].n, m.sub.name]
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var ub := Button.new()
		ub.text = "Снять"
		var uid: int = m.uid
		ub.pressed.connect(func():
			r.unequip(uid)
			_rebuild_fab())
		hb.add_child(ub)
	for m in r.modules:
		var hb := HBoxContainer.new()
		fab_box.add_child(hb)
		var t := _label(hb, 12)
		t.text = "○ %s из %s" % [Modules.MODULES[m.kind].n, m.sub.name]
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var eb := Button.new()
		eb.text = "Установить"
		var uid: int = m.uid
		eb.pressed.connect(func():
			main.say(r.equip(uid))
			_rebuild_fab())
		hb.add_child(eb)

func _rebuild_codex() -> void:
	var r := world.robot
	var recipes_ok: bool = r.has_module("predictor") or r.learned.has("s3")
	var prod := Recipes.producers()
	var s := "Известно тегов: %d из %d. Рецепты видны с предсказателем реакций или узлом Шамана «Предвидение».\n\n" % [r.known_tags.size(), MaterialTags.TAGS.size()]
	var tags: Array = MaterialTags.TAGS.keys()
	tags.sort_custom(func(a, b): return int(r.known_tags.has(a)) > int(r.known_tags.has(b)))
	for t in tags:
		if not r.known_tags.has(t):
			s += "[color=#666]??? — неизвестный тег[/color]\n"
			continue
		var col := "#e0a8ff" if MaterialTags.is_exotic(t) else "#a8d8ff"
		s += "[b][color=%s]%s[/color][/b]\n" % [col, MaterialTags.display(t)]
		for rule in HandlingRules.rules_for(t):
			s += "  · %s\n" % rule.desc
		if recipes_ok:
			for e in prod[t]:
				s += "  [color=#ffd479]рецепт:[/color] %s\n" % Recipes.describe(e)
	codex_label.text = s

# ---------------------------------------------------------------- обновление

func _on_inv_selected(i: int) -> void:
	world.robot.selected = inv_list.get_item_metadata(i)

func refresh() -> void:
	if world == null:
		return
	_t += get_process_delta_time()
	var r := world.robot
	var p := world.planet
	info_label.text = "%s  (seed %d)\n%s\n%.0f °C · %.2f атм · %.2f g\nЗнания: %d · Тегов известно: %d · Машин: %d/%d" % [
		p.name, p.seed_value, ", ".join(p.tags.map(func(t): return PlanetTags.display(t))),
		p.ambient_temp, p.atm_pressure, p.gravity, r.knowledge, r.known_tags.size(), world.machines.size(), world.machine_limit()]
	goal_label.text = world.goals.text()
	var ev: Array = world.events.slice(max(0, world.events.size() - 9))
	log_label.text = "\n".join(ev.map(func(e): return e.text))
	var abil: Array = []
	var i := 1
	for m in r.equipped:
		var d: Dictionary = Modules.MODULES[m.kind]
		if d.get("active", false):
			var cd := " %.1fс" % r.cooldowns[m.kind] if r.cooldowns.has(m.kind) else ""
			abil.append("[%d] %s%s" % [i, d.n, cd])
			i += 1
		else:
			abil.append("(%s)" % d.n)
	var mode_text := {"none": "", "build": "Строительство: %s — ЛКМ поставить, R повернуть, ПКМ отмена" % (Buildings.name_of(main.build_kind) if main.build_kind != "" else ""),
		"remove": "Снос — ЛКМ по машине", "wire": "Провод — источник, затем приёмник (Shift — вход 2)", "link": "Наведение пушки — пушка, затем приёмник"}
	var sel := world.db.get_sub(r.selected) if r.selected != "" else null
	status_label.text = "Корпус %.0f/%.0f   Баллон %.1f/%.1f   Масса %.0f   Бур тв. %.1f   Выбрано: %s\n%s\n%s" % [
		r.hp, r.max_hp(), r.tank, r.tank_cap(), r.total_mass(), r.mining_hardness(),
		world.sub_label(sel) if sel != null else "—",
		"  ".join(abil) if not abil.is_empty() else "Модулей нет — изготовьте на фабрикаторе (F), чертежи открываются в прокачке (K)",
		mode_text.get(main.mode, "")]
	if main.sim.paused and not blocks_game():
		status_label.text += "   ПАУЗА"
	msg_label.text = main.message if main.message_t > 0.0 else ""
	msg_label.visible = main.message_t > 0.0
	_refresh_inventory()
	_layout()
	if _t > 0.2:
		_t = 0.0
		_refresh_inspector()

func _refresh_inventory() -> void:
	var r := world.robot
	var keys: Array = r.inventory.keys()
	keys.sort()
	var sig := ""
	for k in keys:
		sig += "%s:%.1f:%s;" % [k, r.inventory[k].mass, world.is_analyzed(world.db.get_sub(k))]
	sig += r.selected
	if sig == _inv_sig:
		return
	_inv_sig = sig
	inv_list.clear()
	for k in keys:
		var pt: Portion = r.inventory[k]
		var idx := inv_list.add_item("%s — %.1f кг" % [world.sub_label(pt.substance), pt.mass])
		inv_list.set_item_metadata(idx, k)
		inv_list.set_item_icon_modulate(idx, pt.substance.color)
		inv_list.set_item_custom_fg_color(idx, pt.substance.color.lightened(0.4))
		var tip := "T плавл. %.0f °C, T кип. %.0f °C, плотность %.1f, твёрдость %.1f\nСейчас: %s, %.0f °C" % [
			pt.substance.melt, pt.substance.boil, pt.substance.density, pt.substance.hardness, Substance.PHASE_NAMES[pt.phase()], pt.temp]
		inv_list.set_item_tooltip(idx, tip)
		if k == r.selected:
			inv_list.select(idx)

func _refresh_inspector() -> void:
	var c = main.selected_cell
	var m = world.machine_at(c) if c != null else null
	inspector_panel.visible = m != null
	if m == null:
		_insp_sig = ""
		return
	var lines: Array = m.describe(world)
	if m is Processor and not m.items.is_empty() and (world.robot.has_module("predictor")):
		var res := Processor.run(m.pid, m.items[0].copy(), m.context(world))
		lines.append("Предсказание:")
		for o in res.outs:
			lines.append("  → %s: %s" % ["прямо" if o[1] == 0 else "вправо", world.sub_label(o[0].substance)])
		if res.note != "":
			lines.append("  " + res.note)
	inspector_label.text = "\n".join(lines)
	var sig := "%d:%s:%s" % [m.id, str(m.config), m.manual_off]
	if sig == _insp_sig:
		return
	_insp_sig = sig
	for b in inspector_buttons.get_children():
		b.queue_free()
	_btn("Повернуть", func(): m.facing = (m.facing + 1) % 4)
	_btn("Выключить" if not m.manual_off else "Включить", func(): m.manual_off = not m.manual_off)
	_btn("Снести", func():
		world.remove_at(m.cell)
		main.selected_cell = null)
	if m.config.has("pass_through"):
		_btn("Выдача: %s" % ("да" if m.config.pass_through else "нет"), func(): m.config.pass_through = not m.config.pass_through)
	if m.config.has("tag"):
		_btn("Тег: %s ▶" % MaterialTags.display(m.config.tag), func(): m.config.tag = _next_tag(m.config.tag))
	if m.config.has("target_t"):
		_btn("T −100", func(): m.config.target_t = max(100.0, m.config.target_t - 100.0))
		_btn("T +100", func(): m.config.target_t += 100.0)
	if m.config.has("target_p"):
		_btn("P −1", func(): m.config.target_p = max(1.0, m.config.target_p - 1.0))
		_btn("P +1", func(): m.config.target_p += 1.0)
	if m.config.has("fire_p"):
		_btn("Выстрел −0.5", func(): m.config.fire_p = max(1.2, m.config.fire_p - 0.5))
		_btn("Выстрел +0.5", func(): m.config.fire_p += 0.5)
		if not m.is_silo():
			_btn("Навести (L)", func():
				main.set_mode("link")
				main.pending_cell = m.cell)
	if m.config.has("mode"):
		_btn("Режим ▶", func():
			var i := LogicGate.MODES.find(m.config.mode)
			m.config.mode = LogicGate.MODES[(i + 1) % LogicGate.MODES.size()]
			m.config.threshold = {"level": 0.8, "tag": 0.0, "pressure": 3.0, "temp": 100.0}[m.config.mode])
		_btn("Порог −", func(): m.config.threshold -= _step(m.config.mode))
		_btn("Порог +", func(): m.config.threshold += _step(m.config.mode))

func _step(mode: String) -> float:
	return {"level": 0.1, "tag": 0.0, "pressure": 0.5, "temp": 50.0}[mode]

func _next_tag(cur: String) -> String:
	var pool: Array = world.robot.known_tags.keys()
	if pool.is_empty():
		pool = MaterialTags.TAGS.keys()
	pool.sort()
	var i := pool.find(cur)
	return pool[(i + 1) % pool.size()]

func _btn(text: String, f: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 12)
	b.pressed.connect(func():
		f.call()
		_insp_sig = "")
	inspector_buttons.add_child(b)
