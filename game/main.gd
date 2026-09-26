extends Node2D
## Сцена игры: мир, камера, ввод, инструменты строительства, интерфейс.
##
## Аргументы командной строки (после «--»):
##   --seed=N          — планета с заданным seed
##   --autotest        — собрать цепочку, прогнать симуляцию, проверить и выйти
##   --screenshot=путь — сохранить скриншот через пару секунд и выйти
##   --open=окно       — открыть окно (palette, skills, fabricator, codex, help, briefing)
##   --tutorial        — начать обучение (при первом запуске оно включается само)

const T := 32.0
const WorldView := preload("res://game/world_view.gd")
const Hud := preload("res://game/ui/hud.gd")
const Audio := preload("res://game/audio.gd")
const Menus := preload("res://game/ui/menus.gd")
var autosave_every := 120.0
const SETTINGS := "user://settings.json"

var world: World
var sim: Sim
var view: Node2D
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
var route_tag := ""
var route_tag_pick := ""
var tutorial: Tutorial = null
var _uitest := false
var sel_start = null
var _autosave_t := 0.0

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
	randomize()
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
	ui_scale = float(st.get("ui_scale", 1.0))
	ui_layer.scale = Vector2(ui_scale, ui_scale)
	autosave_every = float(st.get("autosave", 120.0))
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
	return get_global_mouse_position() / T

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
	if not paused:
		var dir := Vector2.ZERO
		if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP): dir.y -= 1
		if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN): dir.y += 1
		if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT): dir.x -= 1
		if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT): dir.x += 1
		if dir != Vector2.ZERO:
			world.move_robot(dir.normalized() * world.robot_speed() * dt)
		if Input.is_key_pressed(KEY_E):
			say(world.mine(_mine_target(), dt))
		if Input.is_key_pressed(KEY_G):
			world.refill_robot(dt)
		if mode == "build" and build_kind == "pipe" and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			var c := mouse_cell()
			if world.machine_at(c) == null and world.can_place("pipe", c, build_material()) == "":
				world.place("pipe", c, 0, build_material())
		sim.advance(dt)
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
	hud.refresh()
	if screenshot_path != "":
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

func _unhandled_input(event: InputEvent) -> void:
	if world == null:
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
		KEY_X: set_mode("remove" if mode != "remove" else "none")
		KEY_V: set_mode("wire" if mode != "wire" else "none")
		KEY_L: set_mode("link" if mode != "link" else "none")
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
		say("анализ касанием перезаряжается")
		return
	var c := mouse_cell()
	var subs: Array = []
	if world.near_robot(c, 1.8):
		subs = Abilities.substances_at(world, c)
	if subs.is_empty() and r.selected != "":
		subs = [world.db.get_sub(r.selected)]
	if subs.is_empty():
		say("нечего анализировать: подойдите вплотную или выберите материал в инвентаре")
		return
	for s in subs:
		world.analyze(s)
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
	if mb.is_empty():
		say("в выделении нет машин")
		return
	macro_lib.append(JSON.parse_string(JSON.stringify(mb)))
	if tutorial != null:
		tutorial.macros_made += 1
	Macroblocks.save_library(macro_lib)
	say("Сохранён «%s»: %d машин, %s. B — поставить" % [mb.name, mb.parts.size(), Macroblocks.describe_ports(mb)])
	set_mode("none")

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
				if m != null and m is Cannon and not m.is_silo():
					pending_cell = c
				else:
					say("выберите пневмопушку")
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
			selected_cell = c if world.machine_at(c) != null else null

func _wire_ends(w: Dictionary) -> Array:
	var poly: Array = view.wire_poly(w)
	if poly.is_empty():
		return [Vector2.ZERO, Vector2.ZERO]
	return [poly[0], poly[-1]]

# ---------------------------------------------------------------- автотест и скриншот

func _save_screenshot() -> void:
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
	# Сохранение в слот через меню паузы и загрузка обратно.
	var old_dir := SaveGame.DIR
	SaveGame.DIR = "user://uitest_saves"
	for sl in SaveGame.all_slots():
		SaveGame.delete_slot(sl)
	menus.open_slots("save", "pause")
	await get_tree().process_frame
	var save_btn := _find_button(menus.slots_box, "Сохранить")
	if save_btn: save_btn.pressed.emit()
	await get_tree().process_frame
	var n_before := w.machines.size()
	menus.open_slots("load", "pause")
	await get_tree().process_frame
	var load_btn := _find_button(menus.slots_box, "Загрузить")
	if load_btn: load_btn.pressed.emit()
	await get_tree().process_frame
	var loaded_ok: bool = world != w and world.machines.size() == n_before and not menus.any_open()
	print("[uitest] слот: сохранён=", save_btn != null, " загружен=", loaded_ok, " машин ", world.machines.size(), "/", n_before)
	SaveGame.delete_slot("slot1")
	SaveGame.DIR = old_dir
	_finish_autotest(w.robot.has_module("hook") and placed != null and loaded_ok)

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
