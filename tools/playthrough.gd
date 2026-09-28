extends SceneTree
## Сквозной прогон 3D-прототипа настоящим вводом (Input.parse_input_event):
## главное меню → выбор планеты → высадка → обучение (камера, ходьба) → бур у друзы
## → карточка материала → выгрузка в приёмник → стройка (насос, труба) → карта →
## пауза → награды за три этапа → итоги → «Новая планета» → высадка на следующей.
## На стыках проверяет, что кнопка делает одно дело: A, закрывшая окно, не прыгает
## и не ставит деталь; в карточке Y не включает стройку; в стройке B и RB не трогают
## карточку и анализатор; M в стройке не открывает карту; Esc карточки не ставит паузу.
##   xvfb-run -a godot --path . --rendering-driver opengl3 --resolution 1280x800 \
##     -s tools/playthrough.gd -- --pad|--keys [--shots=папка]
## Сохранения, настройки и обучение — в user://playthrough_pad (_keys), свои не трогает.
## Код выхода — число найденных проблем (0 — всё прошло).

const WATCHDOG := 540

var pad := true
var shots := ""
var problems: Array = []
var game: Node
var n_shot := 0

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a == "--keys": pad = false
		elif a == "--pad": pad = true
		elif a.begins_with("--shots="): shots = a.substr(8)
	var dir := "user://playthrough_" + ("pad" if pad else "keys")
	_wipe(dir)
	DirAccess.make_dir_recursive_absolute(dir)
	ProtoSave.DIR = dir + "/saves3d"
	ProtoSettings.PATH = dir + "/settings3d.cfg"
	ProtoTutorial.SETTINGS = dir + "/settings.json"
	ProtoControls.save_path = dir + "/controls.cfg"
	if shots != "":
		DirAccess.make_dir_recursive_absolute(shots)
	# Сторож: если прогон где-то встал (ошибка скрипта, окно не закрылось) — выйти.
	create_timer(WATCHDOG, true).timeout.connect(func():
		print("Прогон встал: прошло %d с" % WATCHDOG)
		quit(99))
	_play.call_deferred()

func _wipe(path: String) -> void:
	var d := DirAccess.open(path)
	if d == null:
		return
	for f in d.get_files():
		d.remove(f)
	for sub in d.get_directories():
		_wipe(path + "/" + sub)
		d.remove(sub)

# ---------------------------------------------------------------- проверки

func check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		problems.append(what)

func shot(name: String) -> void:
	if shots == "":
		return
	await frames(2)
	n_shot += 1
	var p := "%s/%02d_%s_%s.png" % [shots, n_shot, "pad" if pad else "keys", name]
	root.get_texture().get_image().save_png(p)
	print("  кадр ", p)

func frames(n: int) -> void:
	for i in n:
		await process_frame

func secs(t: float) -> void:
	var end := Time.get_ticks_msec() + int(t * 1000.0)
	while Time.get_ticks_msec() < end:
		await process_frame

# ---------------------------------------------------------------- ввод

## Событие действия: кнопка геймпада или клавиша — как в InputMap.
func ev(action: StringName, down: bool, strength := 1.0) -> InputEvent:
	var e := ProtoControls.binding(action, pad)
	if e == null:
		return null
	e = e.duplicate()
	if e is InputEventKey:
		e.pressed = down
		e.keycode = e.physical_keycode
	elif e is InputEventJoypadButton:
		e.pressed = down
		e.pressure = 1.0 if down else 0.0
	elif e is InputEventJoypadMotion:
		e.axis_value = signf(e.axis_value) * strength if down else 0.0
	return e

func send(e: InputEvent) -> void:
	if e != null:
		Input.parse_input_event(e)
		Input.flush_buffered_events()

func tap(action: StringName) -> void:
	if game != null and is_instance_valid(game) and game.get("run_ui") != null:
		await settle()
	var e := ev(action, true)
	if e == null:
		check(false, "у действия %s есть %s" % [action, "кнопка" if pad else "клавиша"])
	send(e)
	await frames(3)
	send(ev(action, false))
	await frames(3)

func hold(action: StringName, t: float, until := Callable()) -> void:
	send(ev(action, true))
	var end := Time.get_ticks_msec() + int(t * 1000.0)
	while Time.get_ticks_msec() < end:
		await process_frame
		if until.is_valid() and until.call():
			break
	send(ev(action, false))
	await frames(3)

## A на геймпаде / Enter: нажать кнопку под фокусом.
func accept() -> void:
	var e: InputEvent
	if pad:
		e = ProtoControls._button(JOY_BUTTON_A)
	else:
		e = InputEventKey.new()
		e.physical_keycode = KEY_ENTER
		e.keycode = KEY_ENTER
	e.pressed = true
	send(e)
	await frames(3)
	var up := e.duplicate()
	up.pressed = false
	send(up)
	await frames(3)

## B на геймпаде / Esc.
func back() -> void:
	var e: InputEvent
	if pad:
		e = ProtoControls._button(JOY_BUTTON_B)
	else:
		e = InputEventKey.new()
		e.physical_keycode = KEY_ESCAPE
		e.keycode = KEY_ESCAPE
	e.pressed = true
	send(e)
	await frames(3)
	var up := e.duplicate()
	up.pressed = false
	send(up)
	await frames(3)

## Кнопка с текстом в поддереве — в фокус.
func focus_text(n: Node, prefix: String) -> bool:
	for c in n.find_children("*", "Button", true, false):
		if c.is_visible_in_tree() and (c as Button).text.begins_with(prefix):
			(c as Button).grab_focus()
			return true
	return false

func wait_scene(path: String, t := 20.0) -> Node:
	var end := Time.get_ticks_msec() + int(t * 1000.0)
	while Time.get_ticks_msec() < end:
		await process_frame
		if current_scene != null and current_scene.scene_file_path == path:
			await frames(5)
			return current_scene
	return null

# ---------------------------------------------------------------- узлы игры

func pl() -> Node: return game.get_node("player")
func robot() -> Node3D: return game.robot
func builder() -> Node: return game.get_node_or_null("builder")
func run_ui() -> ProtoRunUi: return game.run_ui
func cargo_kg() -> float:
	var m := 0.0
	for p in ProtoMining.cargo_of(robot()):
		m += p.mass
	return m

## Снимок того, что не должна менять «чужая» кнопка.
func state() -> Dictionary:
	return {"air": pl().air, "vy": pl().vy, "parts": game.pneu.parts.size(),
		"build": builder().active, "card": game.lab_panel.open, "map": game.map_view.open,
		"modal": run_ui().modal}

## Стройка вкл/выкл кнопкой. Окно награды может открыться в тот же кадр и забрать
## нажатие себе (игра на паузе) — тогда взять награду и нажать ещё раз.
func set_build(on: bool) -> void:
	for i in 4:
		await settle()
		if builder().active == on:
			return
		await tap(&"build_mode")
		await frames(3)

## Выбрать деталь кнопкой «следующая» (окно рана может открыться посреди выбора).
func _select(kind: String) -> void:
	for i in ProtoPneumatics.ORDER.size() * 2:
		await settle()
		if builder().kind() == kind:
			return
		await tap(&"build_next")

## Где встать, чтобы поставить деталь в свободную клетку рядом с c: [где, куда смотреть].
func _beside(c: Vector2i) -> Array:
	var net: ProtoPneumatics = game.pneu
	var o: Vector3 = game.pneu_view.origin
	for dn: Vector2i in ProtoPneumatics.DIRS:
		var n := c + dn
		if net.parts.has(n):
			continue
		for d: Vector2i in ProtoPneumatics.DIRS:
			if net.parts.has(n - d):
				continue
			var at := ProtoPneumatics.cell_pos(o, n)
			var dw := Vector3(d.x, 0, d.y)
			return [at - dw * ProtoPneumatics.CELL * 1.1, at]
	return []

## Окно рана (награда, выбор пути) может открыться само, когда этап выполнен:
## взять первую карточку кнопкой и проверить, что больше ничего не случилось.
func settle() -> void:
	while run_ui().modal in ["reward", "choice"]:
		var m := run_ui().modal
		var s0 := state()
		await shot(m)
		await accept()
		var s1 := state()
		check(s1.modal != m, "окно «%s» закрылось кнопкой" % m)
		check(not s1.air and s1.parts == s0.parts and s1.build == s0.build, "кнопка, закрывшая «%s», больше ничего не сделала" % m)
		await frames(10)

func stand(p: Vector3, face: Vector3) -> void:
	var t: ProtoTerrain = game.terrain
	robot().position = Vector3(p.x, t.floor_at(p + Vector3(0, 1.0, 0)), p.z)
	var f := face - p
	robot().rotation.y = atan2(f.x, f.z)
	pl().cam_yaw = robot().rotation.y
	pl().vel = Vector3.ZERO
	pl().air = false
	await frames(4)

# ---------------------------------------------------------------- прогон

func _play() -> void:
	print("Сквозной прогон: ", "геймпад" if pad else "клавиатура и мышь")
	change_scene_to_file(ProtoMainMenu.SCENE)
	var menu: Node = await wait_scene(ProtoMainMenu.SCENE)
	check(menu != null, "главное меню открылось")
	await secs(0.5)
	await shot("menu")
	# Сохранений нет: в фокусе «Новая планета».
	await accept()
	await frames(5)
	check(menu.page == "picker", "A / Enter в меню → выбор планеты")
	await shot("picker")
	var first_seed: int = menu.seed_value
	await accept()
	game = await wait_scene(ProtoMainMenu.GAME)
	check(game != null, "высадка: сцена игры загрузилась")
	if game == null:
		return _end()
	await _planet(first_seed, true)
	_end()

func _planet(seed_v: int, full: bool) -> void:
	check(game.seed_value == seed_v, "планета с сидом %d (выбран в меню)" % seed_v)
	await secs(1.0)
	check(run_ui().modal == "briefing", "брифинг высадки открыт")
	check(game.tutorial != null, "обучение идёт")
	await shot("briefing")
	var s0 := state()
	await accept()
	var s1 := state()
	check(s1.modal == "", "A / Enter закрыл брифинг")
	check(not s1.air and s1.vy == 0.0, "кнопка, закрывшая брифинг, не прыгнула")
	check(s1.parts == s0.parts, "кнопка, закрывшая брифинг, не поставила деталь")
	if not full:
		await shot("planet2")
		return
	# ---- обучение: осмотреться и пройтись
	var tut: ProtoTutorial = game.tutorial
	await hold(ProtoControls.CAM_RIGHT, 3.0, func(): return tut.step >= 1)
	await secs(1.6)
	# Идём прочь от завода: камера (а с ней «вперёд») — от его середины.
	var off: Vector3 = robot().global_position - game.pneu_view.origin
	pl().cam_yaw = atan2(off.x, off.z)
	await hold(ProtoControls.MOVE_FORWARD, 20.0, func(): return tut.step >= 2)
	await secs(1.6)
	check(tut.step >= 2, "обучение: осмотрелся и прошёлся (шаг %d)" % tut.step)
	await shot("tutorial_walk")
	# ---- бур
	await settle()
	pl().auto_drill("")
	pl().drill_auto = false
	pl().cam_focus = Vector3.INF
	await stand(pl().drill_stand, pl().drill_face)
	await hold(ProtoControls.WORK, 20.0, func(): return cargo_kg() > 0.0 and game.mining.falling.is_empty())
	check(cargo_kg() > 0.0, "бур: в грузе %.1f кг" % cargo_kg())
	await shot("drilled")
	await secs(1.6)
	# ---- карточка материала
	await settle()
	await tap(&"lab_touch")
	check(game.lab_panel.open, "касание открыло карточку материала")
	await shot("card")
	await tap(&"build_mode")
	check(not builder().active, "в карточке кнопка стройки не включает стройку")
	var hp0: float = game.health.hp
	game.health.hp = 60.0
	await hold(ProtoHealth.REPAIR, 1.0)
	check(game.health.hp <= 60.5, "в карточке D-pad → / H не чинит корпус (прочность %.1f)" % game.health.hp)
	game.health.hp = hp0
	await tap(&"cargo_unload")
	check(cargo_kg() > 0.0, "в карточке кнопка выгрузки не выгружает")
	await back()
	check(not game.lab_panel.open, "B / Esc закрыл карточку")
	check(run_ui().modal == "", "B / Esc, закрывший карточку, не открыл паузу")
	await secs(1.6)
	check(tut.step >= 4, "обучение: дошёл до «Сдайте груз» (шаг %d)" % tut.step)
	# ---- выгрузка
	await settle()
	var intake := Vector3.INF
	for c in game.pneu.parts:
		if game.pneu.parts[c].kind == "intake":
			intake = ProtoPneumatics.cell_pos(game.pneu_view.origin, c)
			break
	var away: Vector3 = (intake - game.pneu_view.origin) * Vector3(1, 0, 1)
	away = away.normalized() if away.length() > 0.1 else Vector3.FORWARD
	await stand(intake + away * 1.6, intake + away * 6.0)
	await shot("at_intake")
	await settle()
	var kg := cargo_kg()
	await tap(&"cargo_unload")
	check(cargo_kg() == 0.0 and builder().unloaded_kg >= kg - 0.01, "выгрузка в приёмник (%.1f кг)" % kg)
	await secs(1.6)
	await settle()
	await secs(1.6)
	check(tut.step >= 5, "обучение: дошёл до «Поставьте насос» (шаг %d)" % tut.step)
	# ---- стройка
	await set_build(true)
	check(builder().active, "стройка включилась")
	await _select("pump")
	check(builder().kind() == "pump", "выбран насос")
	await settle()
	var s2 := state()
	await tap(&"build_place")
	var s3 := state()
	check(s3.parts == s2.parts + 1, "насос поставлен")
	check(not s3.air, "в стройке кнопка «поставить» не прыгает")
	await shot("build_pump")
	await secs(1.6)
	await _select("pipe")
	await tap(&"build_rotate")
	check(not game.lab_panel.open, "в стройке «повернуть» не открывает карточку")
	await tap(&"build_material")
	check(not game.map_view.open, "в стройке «материал» не открывает карту")
	# Труба — в свободную клетку рядом с насосом; робот встаёт к ней со свободной стороны.
	var pump_c: Vector2i = builder().target()[0]
	var spot := _beside(pump_c)
	check(not spot.is_empty(), "рядом с насосом есть место для трубы")
	if not spot.is_empty():
		await stand(spot[0], spot[1])
	var s4 := state()
	await tap(&"build_place")
	check(state().parts == s4.parts + 1, "труба поставлена")
	await tap(&"build_remove")
	check(state().parts == s4.parts, "«разобрать» убрал трубу")
	check(not game.lab_panel.open, "в стройке «разобрать» не открывает карточку")
	await tap(&"build_place")
	await secs(1.6)
	await set_build(false)
	check(not builder().active, "стройка выключилась")
	await secs(1.6)
	check(tut.step >= 7, "обучение: дошёл до «Цель планеты» (шаг %d)" % tut.step)
	await shot("tutorial_goal")
	# ---- карта
	await settle()
	await tap(&"map_toggle")
	check(game.map_view.open, "карта открылась")
	await secs(0.8)
	await shot("map")
	var b0: bool = builder().active
	await back()
	check(not game.map_view.open, "B / Esc закрыл карту")
	check(builder().active == b0 and not game.lab_panel.open and run_ui().modal != "menu", "кнопка, закрывшая карту, больше ничего не сделала")
	# ---- пауза
	await settle()
	await tap(ProtoControls.MENU)
	check(run_ui().modal == "menu", "пауза открылась")
	check(paused, "игра на паузе")
	await shot("pause")
	await tap(ProtoControls.MENU)
	check(run_ui().modal != "menu", "пауза закрылась (могла сразу открыться отложенная награда)")
	# ---- этапы: награда приходит, пока идёт стройка
	await set_build(true)
	for i in 4:
		if game.run.goals.completed:
			break
		await _complete_stage(i)
	check(game.run.goals.completed, "цель планеты выполнена")
	# ---- итоги и перелёт
	var end := Time.get_ticks_msec() + 5000
	while run_ui().modal != "end" and Time.get_ticks_msec() < end:
		await process_frame
	check(run_ui().modal == "end", "итоги рана открылись")
	await shot("end")
	check(focus_text(run_ui()._win, "Новая планета"), "в итогах есть «Новая планета»")
	await accept()
	var menu: Node = await wait_scene(ProtoMainMenu.SCENE)
	check(menu != null and menu.page == "picker", "«Новая планета» → выбор планеты")
	if menu == null:
		return
	check(menu.seed_value != seed_v and ProtoSave.read(menu.seed_value).is_empty(),
		"в выборе — новая, ещё не посещённая планета (%d)" % menu.seed_value)
	await shot("picker2")
	var next: int = menu.seed_value
	await accept()
	game = await wait_scene(ProtoMainMenu.GAME)
	check(game != null, "перелёт: новая планета загрузилась")
	if game != null:
		await _planet(next, false)
	# ---- сохранение первой планеты
	check(ProtoSave.read(seed_v).size() > 0, "первая планета сохранилась при перелёте")

## Выполнить этап (как в test_proto_run) и взять награду кнопкой.
func _complete_stage(i: int) -> void:
	var run: ProtoRun = game.run
	var g := run.goals
	var end := Time.get_ticks_msec() + 3000
	while run_ui().modal == "" and g.choice_pending() and Time.get_ticks_msec() < end:
		await process_frame
	if run_ui().modal == "choice":
		if i == 1:
			await shot("choice")
		await accept()
		check(run_ui().modal != "choice", "этап %d: путь выбран" % (i + 1))
	var st := g.current()
	var stage := g.stage
	print("  этап %d: %s, модал «%s», выполнено %s" % [g.stage, st.type, run_ui().modal, g.completed])
	match st.type:
		"p_mine": game.mining.mined_total += float(st.kg) + 1.0
		"p_store":
			for c in game.pneu.parts:
				if game.pneu.parts[c].kind == "tank":
					game.pneu.parts[c].items.append(Portion.new(run.crystal, float(st.kg) + 1.0))
					break
		"deliveries": game.pneu.delivered += int(st.n)
		"p_parts": game.pneu.placed += int(st.n)
		"p_process": game.pneu.processed += int(st.n)
		"p_launch": game.pneu.launched_kg += float(st.kg) + 1.0
		"p_pressure", "p_beacon", "p_dome": g.hold = float(st.hold)
	await secs(0.6)
	if st.type in ["p_pressure", "p_beacon", "p_dome"] and g.stage == stage:
		g.progress = 1.0
		g.advance()
	end = Time.get_ticks_msec() + 4000
	while run_ui().modal not in ["reward", "end"] and Time.get_ticks_msec() < end:
		await process_frame
	check(run_ui().modal == "reward", "этап %d выполнен: окно награды" % (i + 1))
	if i == 0:
		await shot("reward")
	var s0 := state()
	await accept()
	var s1 := state()
	check(s1.modal != "reward", "этап %d: награда взята" % (i + 1))
	check(s1.parts == s0.parts, "этап %d: A / Enter, взявшая награду, не поставила деталь в стройке" % (i + 1))
	check(not s1.air, "этап %d: A / Enter, взявшая награду, не прыгнула" % (i + 1))

func _end() -> void:
	print("Итог: ", "всё прошло" if problems.is_empty() else "проблем %d" % problems.size())
	for p in problems:
		print("  - ", p)
	quit(problems.size())
