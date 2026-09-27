extends Node2D
## Сцена игры: мир, камера, ввод, инструменты строительства, интерфейс.
##
## Аргументы командной строки (после «--»):
##   --seed=N          — планета с заданным seed
##   --autotest        — собрать цепочку, прогнать симуляцию, проверить и выйти
##   --screenshot=путь — сохранить скриншот через пару секунд и выйти
##   --open=окно       — открыть окно (palette, skills, fabricator, codex, help, briefing,
##                       pause, settings, slots, end, event, choice, reward)
##   --tutorial        — начать обучение (при первом запуске оно включается само)
##   --flow            — включить карту потоков (O)
##   --no-music        — без музыки (в headless она и так не сводится)
##   --3d              — объёмный вид (F3); окна те же, геймпад работает и в нём
##   --pad             — как будто играют с геймпада (фокус на кнопках окон)
## Геймпад: левый стик — ход, RT — добыча, Menu — пауза, B — закрыть окно,
## View — прокачка, Y — цель; в окнах D-pad — выбор, A — нажать.

const T := 32.0
const WorldView := preload("res://game/world_view.gd")
const WorldView3D := preload("res://game/world_view_3d.gd")
const Hud := preload("res://game/ui/hud.gd")
const Audio := preload("res://game/audio.gd")
const Menus := preload("res://game/ui/menus.gd")
var autosave_every := 120.0
const SETTINGS := "user://settings.json"

var world: World
var sim: Sim
var view: Node2D
var view3d: Node3D = null      # объёмный вид (F3); создаётся при первом включении
var use_3d := false
var lab_panel: ProtoLabPanel = null   # 3D: карточка материала с геймпада (Z / A)
var cam: Camera2D
var hud: Control
var menus: Control
var ui_layer: CanvasLayer
var ui_scale := 1.0
var in_menu := false
var audio: Node
var seed_value := 0
var macro_lib: Array = []
var macro_idx := -1
var macro_rot := 0
var macro_collapsed := false
var pending_macro := {}        # выделенная рамкой схема, ждёт выбора действия
var route_tag := ""
var _link_idx := 0             # какой выход машины наводится в режиме L (Shift — второй)
var flow_view := false         # O — карта потоков груза
var route_tag_pick := ""
var tutorial: Tutorial = null
var _uitest := false
var _demo := false          # --demo[=N]: у робота строится завод из N машин (для скриншотов и замера кадров)
var _demo_n := 13
var _lab_demo := false      # --lab: 3D-вид, робот у залежи, открыта карточка материала (для кадра)
var _bench := false         # --bench: 5 с кадрового профиля и выход
var _bench_t := 0.0
var _bench_frames := 0
var _bench_us := {"draw": 0, "hud": 0, "sim": 0, "fx": 0}
var sel_start = null
var _autosave_t := 0.0
var pad_used := false          # последний ввод — с геймпада (фокус кнопок в окнах)

var mode := "none"            # none | build | remove | wire | link | macro_select | macro_place
var build_kind := ""
var build_facing := 0
var build_sub_id := ""
var pending_cell = null
var selected_cell = null
var wire_port := 0
var _drag := {}
var message := ""
var message_t := 0.0

var manual_pause := false
var autotest := false
var screenshot_path := ""
var open_window := ""
var _shot_t := 0.0

func _ready() -> void:
	var args := OS.get_cmdline_user_args() + OS.get_cmdline_args()
	var s := -1
	var want_tutorial := false
	var want_menu := false
	for a in args:
		if a.begins_with("--seed="):
			s = int(a.substr(7))
		elif a == "--autotest":
			autotest = true
		elif a == "--tutorial":
			want_tutorial = true
		elif a == "--uitest":
			autotest = true
			_uitest = true
		elif a.begins_with("--screenshot="):
			screenshot_path = a.substr(13)
		elif a.begins_with("--open="):
			open_window = a.substr(7)
		elif a == "--menu":
			want_menu = true
		elif a == "--demo" or a.begins_with("--demo="):
			_demo = true
			if a.begins_with("--demo="):
				_demo_n = int(a.substr(7))
		elif a == "--flow":
			flow_view = true
		elif a == "--3d":
			use_3d = true
		elif a == "--pad":
			pad_used = true
		elif a == "--lab":
			_lab_demo = true
			use_3d = true
		elif a == "--bench":
			_bench = true
			_demo = true
	randomize()
	ProtoControls.ensure()
	ProtoControls.ensure_ui()
	view = WorldView.new()
	view.main = self
	add_child(view)
	cam = Camera2D.new()
	cam.zoom = Vector2(1.5, 1.5)
	add_child(cam)
	cam.make_current()
	ui_layer = CanvasLayer.new()
	add_child(ui_layer)
	hud = Hud.new()
	hud.main = self
	ui_layer.add_child(hud)
	menus = Menus.new()
	menus.main = self
	ui_layer.add_child(menus)
	audio = Audio.new()
	add_child(audio)
	apply_settings()
	macro_lib = Macroblocks.load_library()
	var plain_start: bool = s < 0 and not autotest and screenshot_path == "" and not want_tutorial
	var first_run: bool = plain_start and not settings().get("tutorial_done", false)
	if want_tutorial or first_run:
		start_tutorial()
	elif want_menu or plain_start:
		open_main_menu()
	else:
		new_world(s if s >= 0 else randi() % 1000000)
	if _demo:
		call_deferred("_build_demo")
	if _lab_demo:
		call_deferred("_open_lab_demo")
	if _uitest:
		call_deferred("run_uitest")
	elif autotest:
		call_deferred("run_autotest")
	if open_window in ["pause", "settings"]:
		if open_window == "settings":
			menus.open_settings("pause")
		else:
			menus.show_panel("pause")
	elif open_window == "slots":
		SaveGame.save_file(world, "slot1")
		menus.open_slots("load", "pause")
	elif open_window == "event":
		world.director.enabled = true
		world.director.start("meteors", world.robot_cell() + Vector2i(4, -2))
		world.director.current.t = 0.01
	elif open_window == "choice":
		world.goals.stage = 1
	elif open_window == "reward":
		world.goals.reward_pending = Rewards.offer(world, 0)
	elif open_window == "end":
		menus.show_run_end(world)
	elif open_window == "briefing":
		hud.show_briefing()
	elif open_window != "":
		hud.toggle(open_window)

func settings() -> Dictionary:
	if not FileAccess.file_exists(SETTINGS):
		return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string(SETTINGS))
	return d if typeof(d) == TYPE_DICTIONARY else {}

func set_setting(key: String, value) -> void:
	var d := settings()
	d[key] = value
	var f := FileAccess.open(SETTINGS, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(d))

# ---------------------------------------------------------------- меню

func open_main_menu() -> void:
	new_world(randi() % 1000000)
	in_menu = true
	hud.visible = false
	hud.close_all()
	menus.show_main()

func _leave_menu() -> void:
	in_menu = false
	hud.visible = true
	menus.close_all()

func menu_new_game(s: int) -> void:
	_leave_menu()
	new_world(s if s >= 0 else randi() % 1000000)
	hud.show_briefing()

func menu_continue() -> void:
	var slot := SaveGame.latest_slot()
	if slot != "":
		load_from(slot)

func menu_tutorial() -> void:
	_leave_menu()
	start_tutorial()

func save_to(slot: String) -> String:
	var err := SaveGame.save_file(world, slot)
	return err if err != "" else "Сохранено: %s" % SaveGame.slot_title(slot)

func load_from(slot: String) -> void:
	var lw := SaveGame.load_file(slot)
	if lw == null:
		say("не удалось загрузить «%s»" % SaveGame.slot_title(slot))
		return
	_leave_menu()
	new_world(0, lw)
	say("Загружено: %s" % SaveGame.slot_title(slot))

func apply_settings() -> void:
	var st := settings()
	var vol: float = float(st.get("volume", 0.8))
	AudioServer.set_bus_volume_db(0, linear_to_db(max(vol, 0.0001)))
	Audio.ensure_buses()
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Music"), linear_to_db(max(float(st.get("music", 0.6)), 0.0001)))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("SFX"), linear_to_db(max(float(st.get("sfx", 0.8)), 0.0001)))
	ui_scale = float(st.get("ui_scale", 1.0))
	ui_layer.scale = Vector2(ui_scale, ui_scale)
	autosave_every = float(st.get("autosave", 120.0))
	if hud != null:
		hud.advice_on = st.get("advice", true)
	if DisplayServer.get_name() != "headless":
		var full: bool = st.get("fullscreen", false)
		var cur := DisplayServer.window_get_mode()
		if full and cur != DisplayServer.WINDOW_MODE_FULLSCREEN:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		elif not full and cur == DisplayServer.WINDOW_MODE_FULLSCREEN:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	hud._layout()
	menus._layout()

func start_tutorial() -> void:
	var w := World.create(Tutorial.SEED, Tutorial.PLANET_TAGS)
	Tutorial.setup_world(w)
	new_world(0, w)
	tutorial = Tutorial.new(world)
	say("Обучение: задания — в панели сверху")

func end_tutorial(completed: bool) -> void:
	tutorial = null
	world.meta.erase("tutorial_step")
	set_setting("tutorial_done", true)
	if completed:
		say("Обучение пройдено! Shift+N — настоящая планета")

func new_world(s: int, loaded: World = null) -> void:
	tutorial = null
	world = loaded if loaded != null else World.create(s)
	if world.meta.has("tutorial_step"):
		tutorial = Tutorial.new(world)
		tutorial.step = int(world.meta.tutorial_step)
	seed_value = world.planet.seed_value
	sim = Sim.new(world)
	audio.set_world(world)
	_autosave_t = 0.0
	view.world = world
	set_3d(use_3d)
	cam.position = world.robot.pos * T
	cam.reset_smoothing()
	mode = "none"
	pending_cell = null
	selected_cell = null
	hud.set_world(world)
	if not autotest and screenshot_path == "" and loaded == null:
		hud.show_briefing()

func say(text: String) -> void:
	if text == "":
		return
	message = text
	message_t = 3.0

func mouse_world() -> Vector2:
	if use_3d and view3d != null and view3d.world != null:
		return view3d.screen_to_world(get_viewport().get_mouse_position())
	return get_global_mouse_position() / T

## Объёмный вид вместо плоского. Мир, управление и интерфейс те же.
func set_3d(on: bool) -> void:
	use_3d = on
	if on and view3d == null and world != null:
		view3d = WorldView3D.new()
		view3d.main = self
		add_child(view3d)
	# Объёмный мир строится при включении: в 2D новый ран его не ждёт.
	if on and view3d != null and view3d.world != world:
		view3d.set_world(world)
	view.visible = not on
	if view3d != null:
		view3d.activate(on)
	if on and world != null and (lab_panel == null or lab_panel.desk.world != world):
		if lab_panel != null:
			lab_panel.queue_free()
		lab_panel = ProtoLabPanel.new()
		lab_panel.setup(ProtoLabDesk.new(world))
		lab_panel.feed_events = false
		add_child(lab_panel)
	if lab_panel != null:
		lab_panel.enabled = on
		if not on and lab_panel.open:
			lab_panel.close()

func mouse_cell() -> Vector2i:
	var m := mouse_world()
	return Vector2i(floori(m.x), floori(m.y))

func build_material() -> Substance:
	var r := world.robot
	var pref: Substance = null
	if build_sub_id != "" and r.inventory.has(build_sub_id):
		pref = world.db.get_sub(build_sub_id)
	elif r.selected != "":
		pref = world.db.get_sub(r.selected)
	if mode == "build" and build_kind != "":
		var s := world.pick_build_material(build_kind, pref)
		if s != null:
			return s
	return pref

func set_mode(m: String) -> void:
	mode = m
	pending_cell = null
	sel_start = null
	if m != "build":
		build_kind = ""

func start_build(kind: String, sub_id: String = "") -> void:
	set_mode("build")
	build_kind = kind
	if sub_id != "":
		build_sub_id = sub_id
	else:
		# Автоматически выбрать подходящий материал из инвентаря.
		build_sub_id = ""
		for id in world.robot.inventory:
			var sub := world.db.get_sub(id)
			if Buildings.check_material(kind, sub, world.planet.ambient_temp) == "" and world.robot.mass_of(id) >= world.build_cost(kind):
				build_sub_id = id
				break

# ---------------------------------------------------------------- цикл

func _process(dt: float) -> void:
	if world == null:
		return
	message_t -= dt
	var paused: bool = hud.blocks_game() or menus.any_open() or in_menu
	if in_menu:
		cam.position += Vector2(18, 6) * dt
	if world.goals.completed and not world.meta.get("end_shown", false) and not autotest and tutorial == null:
		world.meta.end_shown = true
		menus.show_run_end(world)
	sim.paused = paused or manual_pause
	var lab_open: bool = lab_panel != null and lab_panel.open
	if lab_panel != null and use_3d:
		lab_panel.focus_cell = mouse_cell()
	if not paused:
		var dir := Vector2.ZERO
		if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP): dir.y -= 1
		if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN): dir.y += 1
		if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT): dir.x -= 1
		if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT): dir.x += 1
		if dir != Vector2.ZERO:
			dir = dir.normalized()
		else:
			# Левый стик геймпада (раскладка ProtoControls): наклон задаёт скорость.
			var stick := ProtoControls.move_vector()
			dir = Vector2(stick.x, -stick.y)
		if dir != Vector2.ZERO and not lab_open:   # карточке материала нужны стик и стрелки
			world.move_robot(dir * world.robot_speed() * dt)
		# Добыча: E или правый курок (F — тоже клавиша бура в раскладке, но здесь это фабрикатор).
		if Input.is_key_pressed(KEY_E) or (Input.is_action_pressed(ProtoControls.WORK) and not Input.is_physical_key_pressed(KEY_F)):
			say(world.mine(_mine_target(), dt))
		if Input.is_key_pressed(KEY_G):
			world.refill_robot(dt)
		if mode == "build" and build_kind == "pipe" and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			var c := mouse_cell()
			if world.machine_at(c) == null and world.can_place("pipe", c, build_material()) == "":
				world.place("pipe", c, 0, build_material())
		var t_sim := Time.get_ticks_usec()
		sim.advance(dt)
		_bench_us.sim += Time.get_ticks_usec() - t_sim
		if tutorial != null:
			if tutorial.update(world):
				world.sound("fanfare", world.robot_cell())
				say("Шаг выполнен: " + Tutorial.STEPS[tutorial.step - 1].title if not tutorial.done else "Обучение пройдено!")
			world.meta.tutorial_step = tutorial.step
			if tutorial.done:
				end_tutorial(true)
		_autosave_t += dt
		if autosave_every > 0.0 and _autosave_t >= autosave_every and not autotest and not in_menu:
			_autosave_t = 0.0
			SaveGame.save_file(world, "auto")
	if not in_menu:
		cam.position = cam.position.lerp(world.robot.pos * T, min(1.0, dt * 8.0))
	_pad_focus()
	var t_hud := Time.get_ticks_usec()
	hud.refresh()
	_bench_us.hud += Time.get_ticks_usec() - t_hud
	if _bench:
		_bench_step(dt)
	if screenshot_path != "" and not _uitest:
		_shot_t += dt
		if _shot_t > 2.5:
			_save_screenshot()

func _mine_target() -> Vector2i:
	var mc := mouse_cell()
	if world.planet.deposits.has(mc) and world.near_robot(mc, 2.2):
		return mc
	var rc := world.robot_cell()
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var c := rc + Vector2i(dx, dy)
			var dep = world.planet.deposits.get(c)
			if dep != null and dep.amount > 0.0:
				return c
	return mc

# ---------------------------------------------------------------- ввод

func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton or (event is InputEventJoypadMotion and absf(event.axis_value) > 0.5):
		pad_used = true
	elif event is InputEventKey or event is InputEventMouseButton:
		pad_used = false

func _unhandled_input(event: InputEvent) -> void:
	if world == null:
		return
	if event is InputEventJoypadButton and event.pressed:
		_on_pad(event)
		return
	if (in_menu or menus.any_open()) and not event is InputEventKey:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if menus.any_open() or in_menu:
			if event.keycode == KEY_ESCAPE and not in_menu:
				menus.close_all()
			return
		_on_key(event)
	elif event is InputEventMouseButton:
		_on_mouse_button(event)
	elif event is InputEventMouseMotion and not _drag.is_empty():
		if world.logic.wires.has(_drag.wire):
			world.logic.move_waypoint(_drag.wire, _drag.idx, mouse_world())

# ---------------------------------------------------------------- геймпад

## Открытое окно, где геймпаду нужна кнопка в фокусе: меню, выбор пути,
## награда, высадка, прокачка и остальные окна HUD. null — окон нет.
func pad_window() -> Control:
	for k in menus.panels:
		if menus.panels[k].visible:
			return menus.panels[k]
	for k in ["reward", "choice", "briefing"]:
		if hud.windows[k].visible:
			return hud.windows[k]
	for k in hud.windows:
		if hud.windows[k].visible and k != "help":
			return hud.windows[k]
	return null

## С геймпада окна управляются фокусом: если он не в открытом окне — первая кнопка.
func _pad_focus() -> void:
	if not pad_used:
		return
	var w := pad_window()
	if w == null:
		return
	var f := get_viewport().gui_get_focus_owner()
	if f != null and w.is_ancestor_of(f) and f.is_visible_in_tree():
		return
	var b := ProtoControls.first_button(w)
	if b != null:
		b.grab_focus()

## Кнопки геймпада вне окон (A — нажать кнопку в фокусе — делает сам интерфейс):
##   Menu (Start) — пауза; B — закрыть окно; View (Back) — прокачка; Y — цель (высадка).
func _on_pad(e: InputEventJoypadButton) -> void:
	match e.button_index:
		JOY_BUTTON_START:
			if in_menu:
				return
			if menus.any_open():
				menus.close_all()
			elif pad_window() != null and not hud.windows.choice.visible and not hud.windows.reward.visible:
				_pad_back()
			else:
				menus.show_panel("pause")
		JOY_BUTTON_B:
			_pad_back()
		JOY_BUTTON_BACK:
			if not menus.any_open() and not in_menu:
				hud.toggle("skills")
		JOY_BUTTON_Y:
			if not menus.any_open() and not in_menu and pad_window() == null:
				hud.show_briefing()

## B: шаг назад — из настроек и слотов в меню, иначе закрыть окно.
func _pad_back() -> void:
	if menus.any_open():
		if menus.panels.settings.visible or menus.panels.slots.visible:
			menus.show_panel(menus._back)
		elif not in_menu:
			menus.close_all()
		return
	if hud.windows.briefing.visible:
		hud.windows.briefing.visible = false
		return
	hud.close_all()

func _on_key(e: InputEventKey) -> void:
	if hud.handle_key(e):
		return
	var shift := e.shift_pressed
	match e.keycode:
		KEY_B: hud.toggle("palette")
		KEY_K: hud.toggle("skills")
		KEY_F:
			hud.toggle("fabricator")
			if world.fabricator_distance() > World.FAB_RADIUS and hud.windows.fabricator.visible:
				say("изготовление работает у фабрикатора: подойдите ближе" if world.fabricator_distance() < INF else "сначала поставьте фабрикатор (B)")
		KEY_H, KEY_F1: hud.toggle("help")
		KEY_F3:
			set_3d(not use_3d)
			say("Объёмный вид" if use_3d else "Плоский вид")
		KEY_X: set_mode("remove" if mode != "remove" else "none")
		KEY_V: set_mode("wire" if mode != "wire" else "none")
		KEY_L: set_mode("link" if mode != "link" else "none")
		KEY_O:
			flow_view = not flow_view
			say("Карта потоков: %s" % ("включена — толщина линий = кг/мин, рамка = состояние машины" if flow_view else "выключена"))
		KEY_I:
			hud.toggle_inventory()
		KEY_M:
			set_mode("macro_select" if mode != "macro_select" else "none")
		KEY_F5:
			var err := SaveGame.save_file(world, "quick")
			say(err if err != "" else "Игра сохранена (F9 — загрузить)")
		KEY_F9:
			var slot := "quick" if SaveGame.exists("quick") else "auto"
			var lw := SaveGame.load_file(slot)
			if lw == null:
				say("сохранения нет")
			else:
				new_world(0, lw)
				say("Загружено сохранение «%s»" % slot)
		KEY_C:
			if mode == "macro_place":
				macro_collapsed = not macro_collapsed
				say("макроблок: " + ("свёрнутый в одну клетку" if macro_collapsed else "развёрнутый"))
		KEY_R:
			if mode == "macro_place":
				macro_rot = (macro_rot + 1) % 4
			elif mode == "build":
				build_facing = (build_facing + 1) % 4
			else:
				world.rotate_at(mouse_cell())
		KEY_Q: say(world.insert_into(mouse_cell(), shift, 5.0 if e.ctrl_pressed else 1.0))
		KEY_T: say(world.take_from(mouse_cell()))
		KEY_Z: _touch_analyze()
		KEY_TAB, KEY_BRACKETRIGHT: world.robot.cycle_selected(-1 if shift else 1)
		KEY_BRACKETLEFT: world.robot.cycle_selected(-1)
		KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6:
			use_slot(e.keycode - KEY_1)
		KEY_ESCAPE:
			var busy: bool = mode != "none" or selected_cell != null
			for k in hud.windows:
				if hud.windows[k].visible:
					busy = true
			set_mode("none")
			selected_cell = null
			hud.close_all()
			if not busy:
				menus.show_panel("pause")
		KEY_N:
			if world.goals.completed or shift:
				new_world(randi() % 1000000)
			else:
				say("Shift+N — бросить планету и начать новую")
		KEY_P:
			manual_pause = not manual_pause
			say("пауза" if manual_pause else "продолжаем")

func _touch_analyze() -> void:
	var r := world.robot
	if r.cooldowns.has("touch"):
		say("касание перезаряжается")
		return
	var c := mouse_cell()
	var subs: Array = []
	if world.near_robot(c, 1.8):
		subs = Abilities.substances_at(world, c)
	if subs.is_empty() and r.selected != "":
		subs = [world.db.get_sub(r.selected)]
	if subs.is_empty():
		say("нечего ощупать: подойдите вплотную к залежи или выберите материал в инвентаре")
		return
	for s in subs:
		world.touch(s)
	# Залежь под курсором — её карточка с пробами появится в инвентаре.
	var dep = world.planet.deposits.get(c)
	if dep != null and world.near_robot(c, 1.8):
		r.focus_sub = dep.sub
		hud._inv_sig = ""
		if hud.inv_collapsed:
			hud.toggle_inventory()
	r.cooldowns["touch"] = 3.0

func use_slot(i: int) -> void:
	var active: Array = world.robot.equipped.filter(func(m): return Modules.MODULES[m.kind].get("active", false))
	if i >= active.size():
		say("в слоте %d нет активного модуля (F — фабрикатор)" % (i + 1))
		return
	say(Abilities.use(world, active[i].kind, mouse_world()))

func _on_mouse_button(e: InputEventMouseButton) -> void:
	if e.button_index == MOUSE_BUTTON_WHEEL_UP and e.pressed:
		cam.zoom = (cam.zoom * 1.1).clamp(Vector2(0.4, 0.4), Vector2(3, 3))
		return
	if e.button_index == MOUSE_BUTTON_WHEEL_DOWN and e.pressed:
		cam.zoom = (cam.zoom / 1.1).clamp(Vector2(0.4, 0.4), Vector2(3, 3))
		return
	if e.button_index == MOUSE_BUTTON_LEFT:
		if e.pressed:
			_click(e.shift_pressed)
		else:
			_drag = {}
			if mode == "macro_select" and sel_start != null:
				_finish_macro_select()
	elif e.button_index == MOUSE_BUTTON_RIGHT and e.pressed:
		if mode != "none":
			set_mode("none")
		else:
			var hit := _waypoint_at(get_global_mouse_position())
			if not hit.is_empty():
				world.logic.remove_waypoint(hit.wire, hit.idx)

func selection_rect() -> Rect2i:
	if sel_start == null:
		return Rect2i(mouse_cell(), Vector2i.ONE)
	var a: Vector2i = sel_start
	var b := mouse_cell()
	var p := Vector2i(min(a.x, b.x), min(a.y, b.y))
	return Rect2i(p, (Vector2i(max(a.x, b.x), max(a.y, b.y)) - p) + Vector2i.ONE)

func _finish_macro_select() -> void:
	var r := selection_rect()
	sel_start = null
	var mb := Macroblocks.capture(world, r, "Макроблок %d" % (macro_lib.size() + 1))
	set_mode("none")
	if mb.is_empty():
		say("в выделении нет машин")
		return
	pending_macro = {"rect": r, "mb": mb}
	hud.show_macro_actions(mb, MacroMachine.collapse_error(mb))

## Действие над выделенной схемой: сохранить в библиотеку и/или свернуть на месте.
func macro_action(save: bool, collapse: bool) -> void:
	if pending_macro.is_empty():
		return
	var mb: Dictionary = pending_macro.mb
	var r: Rect2i = pending_macro.rect
	pending_macro = {}
	var msg := ""
	if save:
		macro_lib.append(JSON.parse_string(JSON.stringify(mb)))
		if tutorial != null:
			tutorial.macros_made += 1
		Macroblocks.save_library(macro_lib)
		msg = "Сохранён «%s»: %d машин, %s. B — поставить" % [mb.name, mb.parts.size(), Macroblocks.describe_ports(mb)]
	if collapse:
		var res := Macroblocks.collapse_region(world, r, mb.name)
		if res.err != "":
			msg = (msg + ". " if msg != "" else "") + "Не свернуть: " + res.err
		else:
			if tutorial != null and not save:
				tutorial.macros_made += 1
			selected_cell = res.macro.cell
			hud.insp_inner = -1
			msg = "«%s» свёрнут на месте (%d машин). Инспектор — настройки внутри, «Развернуть»" % [mb.name, mb.parts.size()]
	if msg != "":
		say(msg)

func unfold_macro(m: MacroMachine) -> void:
	var err := Macroblocks.unfold(world, m)
	if err != "":
		say("Не развернуть: " + err)
		return
	selected_cell = null
	say("Макроблок развёрнут")

func start_macro(idx: int, collapsed: bool = false) -> void:
	set_mode("macro_place")
	macro_idx = idx
	macro_rot = 0
	macro_collapsed = collapsed

func delete_macro(idx: int) -> void:
	macro_lib.remove_at(idx)
	Macroblocks.save_library(macro_lib)

func _waypoint_at(pos: Vector2) -> Dictionary:
	for w in world.logic.wires.values():
		for i in w.points.size():
			if (w.points[i] * T).distance_to(pos) < 8.0:
				return {"wire": w.id, "idx": i}
	return {}

func _click(shift: bool) -> void:
	var c := mouse_cell()
	match mode:
		"macro_select":
			sel_start = c
		"macro_place":
			if macro_idx >= 0 and macro_idx < macro_lib.size():
				var sub: Substance = world.db.get_sub(world.robot.selected) if world.robot.selected != "" else null
				var err := Macroblocks.place_collapsed(world, macro_lib[macro_idx], c, macro_rot, sub) if macro_collapsed else Macroblocks.place(world, macro_lib[macro_idx], c, macro_rot, sub)
				say(err if err != "" else "Макроблок «%s» построен" % macro_lib[macro_idx].name)
				if err == "" and macro_collapsed:
					selected_cell = c
					hud.insp_inner = -1
		"build":
			var sub := build_material()
			var err := world.can_place(build_kind, c, sub)
			if err != "":
				say(err)
			else:
				world.place(build_kind, c, build_facing, sub)
		"remove":
			world.remove_at(c)
		"wire":
			if pending_cell == null:
				if world.machine_at(c) != null:
					pending_cell = c
				else:
					say("выберите машину-источник сигнала")
			else:
				var sub: Substance = world.db.get_sub(world.robot.selected) if world.robot.selected != "" else null
				say(world.add_wire(pending_cell, c, 1 if shift else 0, sub))
				pending_cell = null
		"link":
			if pending_cell == null:
				var m = world.machine_at(c)
				if m != null and ((m is Cannon and not m.is_silo()) or m.outputs() > 0):
					pending_cell = c
					_link_idx = 1 if shift else 0
				else:
					say("выберите пневмопушку или машину с выходом")
			elif not world.machine_at(pending_cell) is Cannon:
				var src = world.machine_at(pending_cell)
				var dst = world.machine_at(c)
				var far := ""
				if src != null and dst != null:
					var dist: float = Vector2(dst.cell - src.cell).length()
					var reach: float = Cannon.reach(world, src)
					if dist > reach:
						far = " (далеко: %.0f кл., дальность сейчас %.1f — нужно больше давления)" % [dist, reach]
				var err := world.link_output(pending_cell, c, _link_idx, route_tag)
				if err != "":
					say(err)
				elif route_tag != "":
					var on: bool = src.shot_routes(_link_idx).any(func(r): return r[0] == route_tag)
					say(("маршрут «%s» задан" if on else "маршрут «%s» снят") % MaterialTags.display(route_tag) + far)
				else:
					say(("выход наведён — груз полетит выстрелом" if src.shot_target(_link_idx) >= 0 else "выстрел снят — выход снова отдаёт соседу") + far)
				route_tag = ""
				set_mode("none")
			else:
				var err := world.link_cannon(pending_cell, c, route_tag)
				say(err if err != "" else ("маршрут «%s» задан" % MaterialTags.display(route_tag) if route_tag != "" else "пушка наведена"))
				route_tag = ""
				set_mode("none")
		_:
			var pos := get_global_mouse_position()
			var hit := _waypoint_at(pos)
			if not hit.is_empty():
				_drag = hit
				return
			var nw := world.logic.nearest_wire(pos, func(w): return _wire_ends(w))
			if nw.id >= 0 and nw.dist < 6.0:
				var ends := _wire_ends(world.logic.wires[nw.id])
				var idx := world.logic.insert_waypoint(nw.id, mouse_world(), ends[0] / T, ends[1] / T)
				_drag = {"wire": nw.id, "idx": idx}
				return
			if c != selected_cell:
				hud.insp_inner = -1
			selected_cell = c if world.machine_at(c) != null else null

func _wire_ends(w: Dictionary) -> Array:
	var poly: Array = view.wire_poly(w)
	if poly.is_empty():
		return [Vector2.ZERO, Vector2.ZERO]
	return [poly[0], poly[-1]]

# ---------------------------------------------------------------- автотест и скриншот

## Демо-завод у робота (--demo=N): для скриншотов и замеров.
func _build_demo() -> void:
	var w := world
	var c := DemoFactory.build(w, w.planet.spawn + Vector2i(2, -3), _demo_n)
	w.robot.pos = c + Vector2(0.5, 0.5)
	cam.position = w.robot.pos * T
	cam.reset_smoothing()

## Кадр карточки материала в 3D: робот у ближайшей твёрдой залежи, касание,
## одна проба и одна догадка.
func _open_lab_demo() -> void:
	var w := world
	var best = null
	for c in w.planet.deposits:
		var sub: Substance = w.db.get_sub(w.planet.deposits[c].sub)
		if sub == null or sub.phase_at(w.planet.ambient_temp) != Substance.Phase.SOLID or sub.tags.size() < 3:
			continue
		if best == null or Vector2(c).distance_to(w.robot.pos) < Vector2(best).distance_to(w.robot.pos):
			best = c
	if best == null or lab_panel == null:
		return
	w.robot.pos = Vector2(best) + Vector2(0.5, 1.6)
	w.robot.tank = w.robot.tank_cap()
	cam.position = w.robot.pos * T
	lab_panel.focus_cell = best
	if not lab_panel.touch_open():
		return
	var s: Substance = lab_panel.current()
	for pid in Probes.ORDER:
		if w.unknown_count(s) > 1 and lab_panel.desk.probe_error(s, pid) == "" and Probes.PROBES[pid].tags.any(func(t): return t in s.tags):
			lab_panel.desk.probe(s, pid)
			break
	var pos: Array = w.possible_of(s)
	if not pos.is_empty():
		lab_panel.desk.toggle_guess(s, pos[0])

## Кадровый профиль: 1 с разогрева, 5 с замера, затем средние мс на кадр по частям.
func _bench_step(dt: float) -> void:
	_bench_t += dt
	if _bench_t < 1.0:
		for k in _bench_us:
			_bench_us[k] = 0
		view.prof_draw_us = 0
		view.prof_fx_us = 0
		_bench_frames = 0
		return
	_bench_frames += 1
	if _bench_t < 6.0:
		return
	var f := float(max(1, _bench_frames))
	print("BENCH машин=%d кадров/с=%.1f кадр=%.2f мс | отрисовка %.2f, частицы %.2f, интерфейс %.2f, симуляция %.2f мс" % [
		world.machines.size(), f / 5.0, 5000.0 / f, view.prof_draw_us / f / 1000.0, view.prof_fx_us / f / 1000.0,
		_bench_us.hud / f / 1000.0, _bench_us.sim / f / 1000.0])
	audio.stop_all()
	get_tree().quit(0)

func _save_screenshot() -> void:
	print("Кадров в секунду: ", Engine.get_frames_per_second(), ", частиц: ", view.fx.parts.size())
	var img := get_viewport().get_texture().get_image()
	img.save_png(screenshot_path)
	print("Скриншот сохранён: ", screenshot_path)
	audio.stop_all()
	get_tree().quit(0)

## Ищет место под цепочку «бур → пушка ~~> приёмник → бак» и прогоняет симуляцию.
func run_autotest() -> void:
	var w := world
	var out := func(s): print("[autotest] ", s)
	out.call("планета %s, теги: %s, цель: %s" % [w.planet.name, ", ".join(w.planet.tags), w.planet.goal.n])
	var plan := _find_chain_site(w)
	if plan.is_empty():
		out.call("не нашлось места для цепочки")
		_finish_autotest(false)
		return
	var dep: Vector2i = plan.dep
	var f: int = plan.facing
	var d: Vector2i = Machine.DIRS[f]
	var sub := w.starter
	w.robot.add_item(Portion.new(sub, 200.0))
	var drill := w.place("drill", dep, f, sub)
	var cannon := w.place("cannon", dep + d, f, sub)
	var pump_cell: Vector2i = dep + d + Machine.DIRS[(f + 1) % 4]
	var pump := w.place("pump", pump_cell, 0, sub)
	var recv := w.place("receiver", dep + d * 6, f, sub)
	var tank := w.place("tank", dep + d * 7, f, sub)
	for m in [drill, cannon, pump, recv, tank]:
		if m == null:
			out.call("не удалось поставить машину")
			_finish_autotest(false)
			return
	out.call("связь пушки: " + w.link_cannon(cannon.cell, recv.cell))
	var fab := w.place("fabricator", w.planet.spawn + Vector2i(1, 1), 0, sub)
	w.robot.pos = Vector2(fab.cell) + Vector2(0.5, -0.5)
	w.robot.knowledge += 5
	out.call("изучение h1: " + Progression.learn(w.robot, "h1"))
	out.call("изготовление крюка: " + w.fabricate("hook", sub))
	if not w.robot.modules.is_empty():
		out.call("установка: " + w.robot.equip(w.robot.modules[0].uid))
	var logi := _build_logistics(w)
	for i in 1200:
		w.tick(0.1)
	var delivered := tank.total_mass() + recv.total_mass()
	out.call("бур: %s | пушка: %s (%.1f атм) | приёмник: %s" % [drill.status, cannon.status, w.gas.pressure(cannon.id), recv.status])
	var logi_ok := true
	if not logi.is_empty():
		var wh = logi.warehouse
		logi_ok = wh.master_id == wh.id and wh.total_mass() > 1.0
		out.call("батарея → сети → склад: батарея собрана=%s, склад собран=%s, на складе %.1f кг" % [logi.battery.master_id == logi.battery.id, wh.master_id == wh.id, wh.total_mass()])
	else:
		out.call("нет места под батарею — пропуск")
	var w2 := SaveGame.from_dict(JSON.parse_string(JSON.stringify(SaveGame.to_dict(w))))
	var save_ok := w2.machines.size() == w.machines.size() and absf(w2.robot.carried_mass() - w.robot.carried_mass()) < 0.01
	out.call("сохранение/загрузка: %s" % ("ок" if save_ok else "РАСХОЖДЕНИЕ"))
	out.call("доставлено: %.1f кг; знаний: %d; известно тегов: %d" % [delivered, w.robot.knowledge, w.robot.known_tags.size()])
	out.call("цель: " + w.goals.text())
	var ok := delivered > 1.0 and w.robot.has_module("hook") and logi_ok and save_ok
	if screenshot_path != "":
		selected_cell = cannon.cell
		w.robot.pos = Vector2(cannon.cell) + Vector2(0.5, 1.5)
		if not logi.is_empty():
			logi.battery.accept(Portion.new(w.starter, 20.0), logi.battery.cell + Vector2i(-1, 0))
			selected_cell = logi.battery.cell
			w.robot.pos = Vector2(logi.battery.cell) + Vector2(7.5, 3.5)
		cam.position = w.robot.pos * T
		return
	_finish_autotest(ok)

## Пневмобатарея 2×2 с насосами → приёмник с ловчими сетями → склад 2×2.
func _build_logistics(w: World) -> Dictionary:
	var sub := w.starter
	for r in range(3, 25):
		for oy in range(-r, r + 1):
			var o: Vector2i = w.planet.spawn + Vector2i(-r, oy)
			var free := true
			for dy in range(-1, 3):
				for dx in range(0, 17):
					var c := o + Vector2i(dx, dy)
					if not w.planet.buildable(c) or w.grid.has(c) or w.planet.deposits.has(c):
						free = false
			if not free:
				continue
			var bat := w.place("battery_section", o, 0, sub, true)
			w.place("battery_section", o + Vector2i(1, 0), 0, sub, true)
			w.place("battery_section", o + Vector2i(0, 1), 0, sub, true)
			w.place("battery_section", o + Vector2i(1, 1), 0, sub, true)
			var pumps: Array = [w.place("pump", o + Vector2i(0, 2), 0, sub, true),
				w.place("pump", o + Vector2i(1, 2), 0, sub, true),
				w.place("pump", o + Vector2i(2, 1), 0, sub, true)]
			var recv := w.place("receiver", o + Vector2i(13, 0), 0, sub, true)
			w.place("catch_net", o + Vector2i(12, 0), 0, sub, true)
			w.place("catch_net", o + Vector2i(13, 1), 0, sub, true)
			w.place("catch_net", o + Vector2i(13, -1), 0, sub, true)
			var wh := w.place("warehouse_section", o + Vector2i(14, 0), 0, sub, true)
			w.place("warehouse_section", o + Vector2i(15, 0), 0, sub, true)
			w.place("warehouse_section", o + Vector2i(14, 1), 0, sub, true)
			w.place("warehouse_section", o + Vector2i(15, 1), 0, sub, true)
			w.check_groups()
			w.link_cannon(bat.cell, recv.cell)
			# Давление под гравитацию планеты: плотный сплав летит на 35% короче.
			var need: float = 13.0 / (Cannon.range_for(1.0, w.planet) * 0.65 * bat.range_mult()) * 1.15
			bat.config.fire_p = clampf(need, 2.0, 10.0)
			for m in pumps:
				m.config.target_p = max(5.0, bat.config.fire_p + 0.5)
			bat.accept(Portion.new(sub, 20.0), o + Vector2i(-1, 0))
			return {"battery": bat, "warehouse": wh}
	return {}

## Проверка интерфейса: изготовить и установить модуль через кнопки окна фабрикатора.
func run_uitest() -> void:
	var w := world
	var fc := w.planet.spawn + Vector2i(1, 0)
	w.place("fabricator", fc, 0, w.starter)
	w.robot.pos = Vector2(fc) + Vector2(0.5, 1.5)
	await get_tree().process_frame
	# Изучаем узел через окно прокачки.
	hud.toggle("skills")
	await get_tree().process_frame
	var learn_btn := _find_button(hud.skills_box, "Пневмокрюк")
	print("[uitest] кнопка узла: ", learn_btn != null, " disabled=", learn_btn.disabled if learn_btn else "-")
	if learn_btn: learn_btn.pressed.emit()
	await get_tree().process_frame
	print("[uitest] чертёж крюка: ", w.robot.blueprints.has("hook"))
	hud.toggle("fabricator")
	await get_tree().process_frame
	var bp := _find_button(hud.fab_box, "Пневмокрюк")
	print("[uitest] кнопка чертежа: ", bp != null)
	if bp: bp.pressed.emit()
	await get_tree().process_frame
	var go := _find_button(hud.fab_box, "Изготовить")
	print("[uitest] кнопка «Изготовить»: ", go != null, " disabled=", go.disabled if go else "-", " материалов в списке=", hud.fab_mat.item_count if hud.fab_mat else -1)
	if go: go.pressed.emit()
	await get_tree().process_frame
	print("[uitest] модулей в запасе: ", w.robot.modules.size(), " сообщение: ", message)
	var eq := _find_button(hud.fab_box, "Установить")
	if eq: eq.pressed.emit()
	await get_tree().process_frame
	print("[uitest] установлено: ", w.robot.equipped.map(func(m): return m.kind))
	hud.close_all()
	# Бур настоящим кликом мыши по ближайшей залежи.
	var dep := Vector2i(-1, -1)
	for c in w.planet.deposits:
		if not w.grid.has(c) and (dep == Vector2i(-1, -1) or (Vector2(c) - w.robot.pos).length() < (Vector2(dep) - w.robot.pos).length()):
			dep = c
	w.robot.pos = Vector2(dep) + Vector2(0.5, 1.5)
	cam.position = w.robot.pos * T
	cam.reset_smoothing()
	await get_tree().process_frame
	await get_tree().process_frame
	start_build("drill")
	var screen := get_viewport().get_canvas_transform() * ((Vector2(dep) + Vector2(0.5, 0.5)) * T)
	get_viewport().warp_mouse(screen)
	await get_tree().process_frame
	print("[uitest] мышь над клеткой ", mouse_cell(), ", залежь ", dep, ", проверка: «", w.can_place("drill", dep, build_material()), "»")
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		ev.position = screen
		ev.global_position = screen
		Input.parse_input_event(ev)
		await get_tree().process_frame
	var placed = w.machine_at(dep)
	print("[uitest] бур поставлен: ", placed != null and placed.kind == "drill", " сообщение: ", message)
	# Награда за этап и выбор пути — через карточки окна.
	w.goals.reward_pending = Rewards.offer(w, 0)
	await get_tree().process_frame
	await get_tree().process_frame
	var card := _find_button(hud.reward_box, "")
	for c in hud.reward_box.find_children("*", "Button", true, false):
		if c.text.contains(Rewards.CARDS[w.goals.reward_pending[0]].n):
			card = c
	var reward_ok := false
	if card:
		card.pressed.emit()
		reward_ok = w.goals.reward_pending.is_empty()
	w.goals.stage = 1
	await get_tree().process_frame
	await get_tree().process_frame
	var alt0: String = w.goals.raw_stage(1).alt[0].desc
	var choice_btn := _find_button(hud.choice_box, alt0)
	if choice_btn:
		choice_btn.pressed.emit()
	var choice_ok: bool = w.goals.choices.has("1") and not w.goals.choice_pending()
	print("[uitest] награда выбрана: ", reward_ok, ", путь выбран: ", choice_ok)
	var macro_ok := await _uitest_macro(w)
	var probe_ok := await _uitest_probe(w)
	# Сохранение в слот через меню паузы и загрузка обратно.
	var old_dir := SaveGame.DIR
	SaveGame.DIR = "user://uitest_saves"
	for sl in SaveGame.all_slots():
		SaveGame.delete_slot(sl)
	menus.open_slots("save", "pause")
	await get_tree().process_frame
	var save_btn := _find_button(menus.slots_box, "Сохранить")
	var saved := save_btn != null
	if save_btn: save_btn.pressed.emit()
	await get_tree().process_frame
	var n_before := w.machines.size()
	menus.open_slots("load", "pause")
	await get_tree().process_frame
	var load_btn := _find_button(menus.slots_box, "Загрузить")
	if load_btn: load_btn.pressed.emit()
	await get_tree().process_frame
	var loaded_ok: bool = world != w and world.machines.size() == n_before and not menus.any_open()
	print("[uitest] слот: сохранён=", saved, " загружен=", loaded_ok, " машин ", world.machines.size(), "/", n_before)
	SaveGame.delete_slot("slot1")
	SaveGame.DIR = old_dir
	_finish_autotest(w.robot.has_module("hook") and placed != null and saved and loaded_ok and reward_ok and choice_ok and macro_ok and probe_ok)

## Проба из карточки материала в инвентаре: кнопка «Нагрев» меняет известное или исключённое.
func _uitest_probe(w: World) -> bool:
	var s: Substance = null
	for m in w.planet.materials:
		if s == null and not w.is_identified(m) and m.phase_at(w.planet.ambient_temp) == Substance.Phase.SOLID:
			s = m
	if s == null:
		print("[uitest] проба: нет неопознанного материала")
		return true
	w.robot.add_item(Portion.new(s, 3.0, w.planet.ambient_temp))
	w.robot.selected = s.id
	w.robot.tank = w.robot.tank_cap()
	hud.inv_collapsed = false
	hud._inv_sig = ""
	await get_tree().process_frame
	await get_tree().process_frame
	hud._inv_sig = ""
	hud._refresh_inventory()
	var k0: int = w.known_tags_of(s).size() + w.excluded_of(s).size()
	var btn := _find_button(hud.inv_box, "Нагрев")
	var found := btn != null
	if btn: btn.pressed.emit()
	await get_tree().process_frame
	var k1: int = w.known_tags_of(s).size() + w.excluded_of(s).size()
	print("[uitest] проба «Нагрев»: кнопка ", found, ", известно+исключено ", k0, " → ", k1, " (", w.sub_label(s), ")")
	# Догадка: клик по возможному тегу, затем «Проверить».
	var hyp_ok := true
	var pos: Array = w.possible_of(s).filter(func(t): return w.check_error(s.id, t) == "")
	if w.unknown_count(s) > 0 and not pos.is_empty():
		hud._inv_sig = ""
		hud._refresh_inventory()
		var tb := _find_button(hud.inv_box, MaterialTags.display(pos[0]))
		if tb: tb.pressed.emit()
		var marked: bool = pos[0] in w.hypotheses_of(s)
		if screenshot_path != "":
			hud._inv_sig = ""
			await get_tree().process_frame
			await get_tree().process_frame
			_save_screenshot()
		hud._inv_sig = ""
		hud._refresh_inventory()
		var cb := _find_button(hud.inv_box, "Проверить")
		var has_check := cb != null
		if cb: cb.pressed.emit()
		var settled: bool = pos[0] in w.known_tags_of(s) or pos[0] in w.excluded_of(s)
		hyp_ok = marked and has_check and settled
		print("[uitest] догадка «", MaterialTags.display(pos[0]), "»: поставлена ", marked, ", проверена ", settled)
	return found and k1 > k0 and hyp_ok

## Схема «контейнер → фильтр → контейнер»: выделить рамкой, «Свернуть на месте»,
## в инспекторе блока сменить тег внутреннего фильтра, «Развернуть».
func _uitest_macro(w: World) -> bool:
	var base := Vector2i(-1, -1)
	var rc := Vector2i(floori(w.robot.pos.x), floori(w.robot.pos.y))
	for r in range(2, 20):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if base != Vector2i(-1, -1):
					continue
				var c := rc + Vector2i(dx, dy)
				var ok := true
				for i in 3:
					var q := c + Vector2i(i, 0)
					if not w.planet.buildable(q) or w.grid.has(q) or w.tile_overrides.has(q):
						ok = false
				if ok:
					base = c
	if base == Vector2i(-1, -1):
		print("[uitest] макроблок: нет места")
		return false
	w.place("container", base, 0, w.starter, true)
	var flt := w.place("filter", base + Vector2i(1, 0), 0, w.starter, true)
	w.place("container", base + Vector2i(2, 0), 0, w.starter, true)
	var tag0: String = flt.config.tag
	for t in ["dense", "brittle", "volatile"]:
		w.robot.known_tags[t] = true
	cam.position = (Vector2(base) + Vector2(1.5, 0.5)) * T
	cam.reset_smoothing()
	await get_tree().process_frame
	await get_tree().process_frame
	set_mode("macro_select")
	sel_start = base
	get_viewport().warp_mouse(get_viewport().get_canvas_transform() * ((Vector2(base) + Vector2(2.5, 0.5)) * T))
	await get_tree().process_frame
	_finish_macro_select()
	await get_tree().process_frame
	var col := _find_button(hud.macro_box, "Свернуть на месте")
	print("[uitest] окно схемы: ", hud.windows.macro_actions.visible, ", кнопка свёртки: ", col != null)
	if col: col.pressed.emit()
	await get_tree().process_frame
	var macro = world.machine_at(selected_cell) if selected_cell != null else null
	var collapsed: bool = macro is MacroMachine and macro.inner.machines.size() == 3
	print("[uitest] свёрнуто: ", collapsed, " сообщение: ", message)
	if not collapsed:
		return false
	hud._refresh_inspector()
	await get_tree().process_frame
	var inner_btn := _find_button(hud.inspector_buttons, "Фильтр")
	if inner_btn: inner_btn.pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	var tag_btn := _find_button(hud.inspector_buttons, "Тег:")
	if tag_btn: tag_btn.pressed.emit()
	await get_tree().process_frame
	var ifl: Machine = macro.inner.machines_of("filter")[0]
	var tag1: String = ifl.config.tag
	print("[uitest] тег внутреннего фильтра: ", tag0, " → ", tag1)
	await get_tree().process_frame
	if not await _uitest_nested(base):
		return false
	var unf := _find_button(hud.inspector_buttons, "Развернуть")
	if unf: unf.pressed.emit()
	await get_tree().process_frame
	var back = world.machine_at(base + Vector2i(1, 0))
	var unfolded: bool = back != null and back.kind == "filter" and back.config.tag == tag1
	print("[uitest] развёрнуто: ", unfolded, " сообщение: ", message)
	var shot_ok := await _uitest_shot(base)
	return tag1 != tag0 and unfolded and shot_ok

## Навести мышь на клетку и дождаться, пока курсор действительно окажется
## над ней: под Xvfb warp_mouse и сдвиг камеры доходят не за один кадр.
func _uitest_aim(cell: Vector2i) -> void:
	for i in 30:
		get_viewport().warp_mouse(get_viewport().get_canvas_transform() * ((Vector2(cell) + Vector2(0.5, 0.5)) * T))
		await get_tree().process_frame
		if mouse_cell() == cell:
			return

## Выстрел выхода: дробилка с насосом, в инспекторе «выстрелом в цель (L)», клик по
## контейнеру в четырёх клетках — груз долетает.
func _uitest_shot(base: Vector2i) -> bool:
	var w := world
	var row := Vector2i(-1, -1)
	for dy in range(2, 12):
		for dx in range(-6, 7):
			var c := base + Vector2i(dx, dy)
			var ok := true
			for i in 5:
				for j in 2:
					var q := c + Vector2i(i, j)
					if not w.planet.buildable(q) or w.grid.has(q) or w.tile_overrides.has(q):
						ok = false
			if ok and row == Vector2i(-1, -1):
				row = c
	if row == Vector2i(-1, -1):
		print("[uitest] выстрел: нет места")
		return false
	var ore := w.db.add(Substance.new("uit_ore", "Руда пробы", ["brittle", "crystalline"]))
	var cr := w.place("crusher", row, 0, w.starter, true)
	w.place("pump", row + Vector2i(0, 1), 0, w.starter, true)
	var box := w.place("container", row + Vector2i(4, 0), 0, w.starter, true)
	cr.store(Portion.new(ore, 2.0))
	selected_cell = cr.cell
	hud.insp_inner = -1
	hud._refresh_inspector()
	await get_tree().process_frame
	var b := _find_button(hud.inspector_buttons, "выстрелом в цель")
	var found := b != null
	if b: b.pressed.emit()
	await get_tree().process_frame
	cam.position = (Vector2(row) + Vector2(2.5, 0.5)) * T
	cam.reset_smoothing()
	await get_tree().process_frame
	await _uitest_aim(box.cell)
	_click(false)
	var linked := cr.shot_target(0) == box.id
	var t0 := w.time
	while w.time - t0 < 20.0 and box.items.is_empty():
		await get_tree().process_frame
		sim.advance(0.5)
	print("[uitest] выстрел выхода: кнопка=", found, " наведён=", linked, " груз в контейнере=", not box.items.is_empty(), " сообщение: ", message)
	# Маршрут по тегу через инспектор и карта потоков.
	var box2 := w.place("container", row + Vector2i(4, 1), 0, w.starter, true)
	selected_cell = cr.cell
	hud._insp_sig = ""
	hud._refresh_inspector()
	await get_tree().process_frame
	var rb := _find_button(hud.inspector_buttons, "маршрут «")
	if rb: rb.pressed.emit()
	await get_tree().process_frame
	await _uitest_aim(box2.cell)
	_click(false)
	var routed := not cr.shot_routes(0).is_empty() and int(cr.shot_routes(0)[0][1]) == box2.id
	var ev := InputEventKey.new()
	ev.keycode = KEY_O
	ev.pressed = true
	_unhandled_input(ev)
	await get_tree().process_frame
	await get_tree().process_frame
	print("[uitest] маршрут по тегу: ", routed, ", карта потоков: ", flow_view, ", поток дробилка → контейнер: ", w.flow.has("%d>%d" % [cr.id, box.id]))
	flow_view = false
	return found and linked and not box.items.is_empty() and routed

## Свёрнутый блок в (base) сворачивается вместе с соседом во внешний блок; в инспекторе
## заходим во вложенный, видим его фильтр, выходим наверх и разворачиваем внешний.
func _uitest_nested(base: Vector2i) -> bool:
	world.place("container", base + Vector2i(1, 0), 0, world.starter, true)
	var res := Macroblocks.collapse_region(world, Rect2i(base, Vector2i(2, 1)), "цех")
	if res.err != "":
		print("[uitest] вложенный блок: ", res.err)
		return false
	selected_cell = res.macro.cell
	hud.insp_inner = -1
	hud._refresh_inspector()
	await get_tree().process_frame
	var nb := _find_button(hud.inspector_buttons, " 0,0")
	if nb: nb.pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	var ob := _find_button(hud.inspector_buttons, "Открыть «")
	var open_found := ob != null
	if ob: ob.pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	var inner_filter := _find_button(hud.inspector_buttons, "Фильтр") != null
	var up := _find_button(hud.inspector_buttons, "← Наверх")
	var up_found := up != null
	if up: up.pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	var ub := _find_button(hud.inspector_buttons, "Развернуть")
	if ub: ub.pressed.emit()
	await get_tree().process_frame
	world.remove_at(base + Vector2i(1, 0), false)
	var nested = world.machine_at(base)
	selected_cell = base
	hud.insp_inner = -1
	hud._refresh_inspector()
	await get_tree().process_frame
	print("[uitest] вложенный блок: открыть=", open_found, " фильтр внутри=", inner_filter, " наверх=", up_found,
		" после разворота снова блок=", nested is MacroMachine)
	return open_found and inner_filter and up_found and nested is MacroMachine

func _find_button(root: Node, text_part: String) -> Button:
	for c in root.find_children("*", "Button", true, false):
		if not c.is_queued_for_deletion() and text_part in c.text:
			return c
	return null

func _finish_autotest(ok: bool) -> void:
	print("AUTOTEST ", "OK" if ok else "FAILED")
	audio.stop_all()
	get_tree().quit(0 if ok else 1)

func _find_chain_site(w: World) -> Dictionary:
	var cells: Array = w.planet.deposits.keys()
	cells.sort_custom(func(a, b): return (a - w.planet.spawn).length() < (b - w.planet.spawn).length())
	for dep in cells:
		var s: Substance = w.db.get_sub(w.planet.deposits[dep].sub)
		if s.hardness > w.starter.hardness:
			continue
		for f in 4:
			var d: Vector2i = Machine.DIRS[f]
			var ok := true
			for k in [1, 6, 7]:
				var c: Vector2i = dep + d * k
				if not w.planet.buildable(c) or w.planet.deposits.has(c):
					ok = false
			var pc: Vector2i = dep + d + Machine.DIRS[(f + 1) % 4]
			if not w.planet.buildable(pc) or w.planet.deposits.has(pc):
				ok = false
			if ok:
				return {"dep": dep, "facing": f}
	return {}
