extends Node3D
## Предпросмотр объёмного 3D-визуала (к игре не подключён).
##   godot --path . res://proto/preview.tscn -- --seed=14 --view=third|plan|cave|overview|vista|flora|sky --screenshot=путь.png
##   --play — ходить самому (WASD, Shift — бег, Пробел — прыжок, камера мышью —
##   курсор захвачен, клик захватывает; Esc / Start — пауза, в ней Настройки →
##   Управление: переназначение, чувствительность, инверсия
##   (user://controls.cfg; --menu — открыть сразу, для кадра);
##   колесо — дистанция; F — бур,
##   G — выстрел кистью и подтягивание; геймпад — см. ProtoControls); --tool=drill — бур в правом предплечье
##   --auto=cave --screenshot=путь.png — маршрут в пещеру, кадры путь_1..4.png
##   --auto=drill --screenshot=путь.png — подойти к друзе и выбурить её (ProtoMining),
##   кадры путь_1..4.png; в --play бур по действию tool_work (F / правый курок);
##   --form=vein — бурить залежь этой формы (ProtoDeposit: vein, nodules, strata…)
##   --view=factory — пневмозавод крупно; --build — режим стройки (призрак детали)
##   --view=goals — ряд сооружений целей планеты: маяк, купол с печью, пусковая шахта;
##   --goal-style=landmark|sleek — другой облик этих сооружений (GoalModels)
##   В --play: B — стройка, T — деталь, R — повернуть, Пробел — поставить,
##   X — разобрать, C — выгрузить груз в приёмник (подробно — ProtoBuilder)
##   --auto=bump --screenshot=путь.png — упереться в дробилку и перешагнуть трубу
##   (проверка столкновений), кадры путь_1..2.png
##   --auto=jump --screenshot=путь.png — разбег и прыжок, кадры путь_1..4.png
##   --auto=hurt --screenshot=путь.png — прочность корпуса (ProtoHealth): падение с
##   высоты, шаг в лаву или кислоту, поломка, сборка на базе; кадры путь_1..4.png.
##   В --play: H / D-pad → (держать) — починить корпус материалом из груза, у завода
##   корпус чинится сам
##   --auto=swim --screenshot=путь.png — жидкости (ProtoSwim, ProtoWater): вброд по
##   реке, прыжок в озеро, на дне или на плаву, вид из-под воды; кадры путь_1..4.png.
##   В --play в жидкости: Прыжок (держать) — грести вверх, Бег — нырнуть
##   --auto=sound — тот же маршрут без кадров, в конце бур у стены и выстрел кистью
##   (для проверки звука); --record=путь.wav — записать звук, --mute — без звука
##   --auto=bench [--bench=отчёт.json] — бенчмарк: загрузка и время кадра на том же
##   маршруте (ProtoBench; запускать с --fixed-fps 30); --deck — графика как на Steam Deck
##   --hud — HUD (груз, завод, стройка, кнопки; в --play он есть всегда), --pad —
##   подсказки для геймпада, --cargo — положить роботу образцы груза (для кадра)
##   В --play игра сохраняется (ProtoSave): сама раз в минуту и при выходе, F5 / R3 —
##   сейчас, F9 — вернуться к сохранённому; --fresh — начать планету заново
##   Ран (ProtoRun, в --play всегда; --run — и без него): цель планеты из трёх
##   этапов, награды, прокачка, события, советы и итоги; Esc / Menu — меню,
##   K — прокачка; --open=briefing|choice|reward|menu|settings|skills|end|event — открыть
##   окно или начать событие (для кадра)
##   Разведка материалов (ProtoLabDesk, ProtoLabPanel): Z / B — коснуться друзы, машины
##   или груза и открыть карточку (пробы, догадки), V / RB — анализатор; в линии
##   завода — лаборатория. --lab — открыть карточку сразу (для кадра)
##   Карта (ProtoMapData): радар в углу HUD и полноэкранная 3D-карта (ProtoMapView) —
##   M / View; туман над неразведанным, пещеры рентгеном. --map — открыть карту
##   сразу (для кадра; разведан путь от завода к пещере), --map=all — всё разведано
##   Обучение первых минут (ProtoTutorial) — в --play, пока не пройдено; --tutorial —
##   заново, --tutorial=N — с шага N (для кадра), --no-tutorial — без него
##   Смена дня и ночи и небо — ProtoDayNight (по тегам и сиду планеты);
##   --time=0..1 — время суток для кадра (0 — полночь, 0,25 — рассвет, 0,5 — полдень)
##   --robot=clean (по умолчанию; другой вариант из RobotDesigns или old — прежний
##   каркас; корпус — металл планеты)
## Сборка для проверки (фича play3d в export_presets.cfg) стартует с главного
## меню (ProtoMainMenu, proto/menu.tscn): продолжить, новая планета, настройки;
## оттуда — сюда, сразу с управлением. Start или Esc — пауза (меню рана: настройки,
## сохранить, новая планета, в главное меню, выход). С --screenshot меню пропускается.
## M / View — карта; в ней Y — новая планета (тот же выбор планеты, что в меню).
## Планета — настоящий генератор: теги задают небо, свет и дымку, жидкие при её
## температуре материалы — реки и озёра, твёрдые — корпуса машин. Форма рельефа,
## тип пещеры, облик кристаллов и гравитация — по тегам (ProtoWorldStyle).

var seed_value := 14
var view := "third"
var planet_on := true         # вся планета вокруг участка (ProtoPlanetStream); --no-planet — только участок
var planet_stream: ProtoPlanetStream
var planet_fill: ProtoPlanetFill   # флора, залежи и моря на шаре вне участка
var _sea_sub: Substance            # жидкость морей шара (из _liquids)
var wild_far := -1.0               # --far=м: для --view=wild/shore — так далеко от завода по дуге
const PLANET_R := 800.0       # радиус планеты-шара, м
var shot_path := ""
var planet: Planet
var terrain: ProtoTerrain
var style: ProtoWorldStyle
var flora: ProtoFlora          # органика планеты (ProtoFlora)
var robot: Node3D
var robot_design := "clean"
var cam: Camera3D
var _t := 0.0
var play := false            # --play: управление от третьего лица
var controls_menu: ProtoControlsMenu   # --menu: экран «Управление» для кадра
var show_menu := false       # --menu: открыть меню управления сразу (для кадра)
var auto := ""               # --auto=cave: скриптовый маршрут с кадрами
var record := ""             # --record=путь.wav: записать звук (с --play или --auto)
var mute := false            # --mute: без звука
var env: Environment
var mining: ProtoMining
var drill_hard := -1.0       # --drill-hard=N — твёрдость бура (иначе — по материалам планеты)
var hud: ProtoHud
var show_hud := false        # --hud: HUD и без --play (для кадра)
var hud_pad := false         # --pad: подсказки для геймпада
var demo_cargo := false      # --cargo: образцы груза у робота
var pneu: ProtoPneumatics
var pneu_view: ProtoPneumaticsView
var factory_mat: Substance    # из чего стоит завод (стройка начинает с него)
var build := false           # --build: режим стройки (с --play или для кадра)
var fresh := false           # --fresh: не загружать сохранение
var saves: ProtoSave
var drill_form := ""         # --form=vein: --auto=drill бурит залежь этой формы
var run: ProtoRun            # цель, награды, прокачка, события (ProtoRun)
var run_ui: ProtoRunUi
var want_run := false        # --run: ран и без --play (для кадра)
var open_win := ""           # --open=окно
var pneu_origin := Vector3.ZERO
var _caption_layer: CanvasLayer
var _zone: MeshInstance3D    # круг зоны события на земле
var _fog_base := -1.0
var _strike_seen = null
var lab_desk: ProtoLabDesk   # знания о веществах (касание, пробы, догадки, лаборатория)
var lab_panel: ProtoLabPanel
var lab_demo := false        # --lab: карточка материала открыта с самого начала
var map_data: ProtoMapData   # рельеф сверху, разведанное, метки — для радара и карты
var map_view: ProtoMapView
var map_demo := ""           # --map / --map=all: карта открыта с самого начала
var _map_meshes: Array = []  # сетки рельефа: карта рисует их же
var _map_caves: Array = []
var _map_water: Array = []   # [[сетка, цвет]]
var _map_t := 0.0
var bench_out := ""          # --bench=путь.json: куда записать отчёт --auto=bench
var load_ms := {}            # время загрузки по этапам (для --auto=bench и лога)
var _lap_t := 0
var sun: DirectionalLight3D
var daynight: ProtoDayNight   # смена дня и ночи, небо (ProtoSky)
var day_time := -1.0          # --time=0..1: время суток (0,5 — полдень, 0 — полночь)
var yard_light: OmniLight3D   # прожектор над заводом — горит ночью
var deck: ProtoDeck           # облегчённая графика (Steam Deck или --deck)
var health: ProtoHealth      # прочность корпуса робота: урон, починка, поломка
var liquid_zones: Array = [] # жидкости для урона: {sub, temp, level, area}
var hazard: Substance        # лава или кислота планеты (как клетки 2D), иначе null
var hurt_prefix := ""        # --auto=hurt: кадры прочности
var hurt_t := 0.0
var hurt_step := 0
var hurt_mark := -1.0
var tutorial: ProtoTutorial
var tutorial_mode := ""      # --tutorial — начать обучение заново; --tutorial=N — с шага N (для кадра); --no-tutorial

## Сид следующей планеты в сборке для проверки (переживает перезагрузку сцены).
static var build_seed := 14
static var _booted := false
## Главное меню: «Начать заново» — не загружать сохранение этой планеты.
static var start_fresh := false
## Запуск из главного меню (ProtoMainMenu.launch): играть на build_seed, как в сборке.
static var from_menu := false

func _ready() -> void:
	if OS.has_feature("play3d") or from_menu:
		play = true
		if not _booted:
			# Первый запуск сборки — с планеты, где играли в прошлый раз.
			_booted = true
			var last := ProtoSave.last_seed()
			if last >= 0:
				build_seed = last
		seed_value = build_seed
	if start_fresh:
		fresh = true
		start_fresh = false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seed="): seed_value = int(a.substr(7))
		elif a.begins_with("--view="): view = a.substr(7)
		elif a.begins_with("--goal-style="): ProtoPneumaticsView.goal_style = a.substr(13)
		elif a.begins_with("--screenshot="): shot_path = a.substr(13)
		elif a.begins_with("--robot="): robot_design = a.substr(8)
		elif a == "--play": play = true
		elif a.begins_with("--tool="): RobotDesigns.tool_r = a.substr(7)
		elif a.begins_with("--auto="): auto = a.substr(7)
		elif a.begins_with("--drill-hard="): drill_hard = float(a.substr(13))
		elif a.begins_with("--record="): record = a.substr(9)
		elif a == "--mute": mute = true
		elif a == "--no-planet": planet_on = false
		elif a == "--hud": show_hud = true
		elif a == "--pad": hud_pad = true
		elif a == "--cargo": demo_cargo = true
		elif a == "--build": build = true
		elif a == "--fresh": fresh = true
		elif a.begins_with("--form="): drill_form = a.substr(7)
		elif a == "--run": want_run = true
		elif a.begins_with("--open="):
			open_win = a.substr(7)
			want_run = true
		elif a == "--lab": lab_demo = true
		elif a == "--map": map_demo = "route"
		elif a.begins_with("--map="): map_demo = a.substr(6)
		elif a.begins_with("--bench="): bench_out = a.substr(8)
		elif a == "--deck": ProtoDeck.active = true
		elif a.begins_with("--time="): day_time = float(a.substr(7))
		elif a.begins_with("--far="): wild_far = float(a.substr(6))
		elif a == "--tutorial": tutorial_mode = "0"
		elif a.begins_with("--tutorial="): tutorial_mode = a.substr(11)
		elif a == "--no-tutorial": tutorial_mode = "off"
	if auto == "drill":
		RobotDesigns.tool_r = "drill"
		view = "cave"
	if (auto == "sound" or play) and RobotDesigns.tool_r == "":
		RobotDesigns.tool_r = "drill"          # играя, робот добывает: бур в предплечье
	if OS.has_feature("steamdeck"):
		ProtoDeck.active = true
	_lap_t = Time.get_ticks_usec()
	planet = PlanetGen.generate(seed_value)
	lab_desk = ProtoLabDesk.new(ProtoLabDesk.for_planet(planet))
	var t0 := Time.get_ticks_msec()
	style = ProtoWorldStyle.for_planet(planet)
	terrain = ProtoTerrain.new(seed_value, style)
	print("Облик планеты: ", style.summary())
	_palette()
	flora = ProtoFlora.for_planet(planet, style, seed_value)
	flora.attach(terrain)
	_lap("planet")
	terrain.build_field()
	_lap("terrain_field")
	# Основная сетка (1 м) без пещерной коробки и детальная сетка пещеры (0,5 м).
	var mesh := terrain.build_mesh(Vector3.ZERO, Vector3i(-1, -1, -1), 1.0, terrain.coarse_skip())
	_lap("terrain_mesh")
	var cmesh := terrain.build_cave_mesh()
	_lap("cave_mesh")
	print("Рельеф %d×%d×%d: %d мс, вершин %d + пещера %d" % [terrain.sx, terrain.sy, terrain.sz, Time.get_ticks_msec() - t0,
		mesh.surface_get_array_len(0), cmesh.surface_get_array_len(0)])
	var tm := terrain.material()
	_map_meshes = [mesh, cmesh]
	_map_caves = [cmesh]
	for m in [mesh, cmesh]:
		var ground := MeshInstance3D.new()
		ground.name = "ground" if m == mesh else "ground_cave"
		ground.mesh = m
		ground.material_override = tm
		add_child(ground)
		RobotGround.add_collision(ground)
	_environment()
	_lap("environment")
	_liquids()
	_lap("liquids")
	_cave_crystals()
	_lap("cave_crystals")
	_surface_features()
	_lap("surface_features")
	_flora()
	_lap("flora")
	_factory()
	_lap("factory")
	_robot_and_camera()
	if view == "flora" and flora.best != Vector3.INF:
		_flora_shot()
	if planet_on:
		planet_stream = ProtoPlanetStream.create(terrain, tm, robot, cam, PLANET_R)
		add_child(planet_stream)
		for c in get_children():
			# Всё про участок — вместе с шаром; погода (частицы) — у робота.
			if c is Node3D and not (c is Light3D or c is Camera3D or c is CPUParticles3D or c is GPUParticles3D) \
					and c != robot and c != planet_stream:
				planet_stream.site_nodes.append(c)
		planet_stream.daynight = daynight
		planet_fill = ProtoPlanetFill.create(planet_stream, flora, planet, seed_value)
		planet_fill.mining = mining
		planet_fill.setup_seas(_sea_sub, planet.ambient_temp)   # котловины — до постройки шара
		planet_stream.add_child(planet_fill)
		if view in ["wild", "shore"]:
			_wild_shot(view == "shore")
		planet_stream.build_now()
		planet_fill.build_sea()
		if not play and auto == "":
			planet_fill.build_now()     # кадр: сразу всё; в игре — в потоках за первые секунды
		if planet_fill.sea_sub != null:
			liquid_zones.append(planet_fill.sea_zone(planet.ambient_temp))
		_lap("planet_around")
	_caption()
	_map_data()
	_lap("robot")
	if play or auto != "":
		var pl := ProtoPlayer.new()
		pl.name = "player"
		add_child(pl)
		pl.setup(robot, cam, terrain, env)
		pl.capture = play and auto == "" and DisplayServer.get_name() != "headless"
		pl.mining = mining
		if auto == "drill":
			# --form: на время выбора цели бур видит только залежи этой формы.
			var all := mining.druses
			if drill_form != "":
				mining.druses = all.filter(func(d): return String(d.node.get_meta("form", "druse")) == drill_form)
				if mining.druses.is_empty():
					print("Залежей формы %s на этой планете нет" % drill_form)
					mining.druses = all
			pl.auto_drill(shot_path.get_basename() if shot_path != "" else "user://drill")
			mining.druses = all
			shot_path = ""
		elif auto == "cave":
			pl.auto_cave(shot_path.get_basename() if shot_path != "" else "user://route")
			shot_path = ""
		elif auto == "sound":
			pl.auto_sound()
		elif auto == "bench":
			pl.auto_cave("")
			pl.shots = []
		elif auto == "around" and planet_stream:
			planet_stream.auto_around(shot_path.get_basename() if shot_path != "" else "")
			shot_path = ""
		elif auto == "bump":
			pl.auto_bump(pneu_view, shot_path.get_basename() if shot_path != "" else "user://bump")
			shot_path = ""
		elif auto == "jump":
			pl.auto_jump(shot_path.get_basename() if shot_path != "" else "user://jump")
			shot_path = ""
		elif auto == "hurt":
			hurt_prefix = shot_path.get_basename() if shot_path != "" else "user://hurt"
			shot_path = ""
		_health(pl)
		if auto == "swim":
			var sd := ProtoSwimDemo.new()
			sd.name = "swim_demo"
			sd.setup(pl, health, shot_path.get_basename() if shot_path != "" else "user://swim")
			add_child(sd)
			shot_path = ""
		if not mute:
			var snd := ProtoSound.new()
			snd.name = "sound"
			snd.record_path = record
			snd.setup(robot, terrain, pl, planet)
			add_child(snd)
		_lap("player_sound")
		if auto == "bench":
			var b := ProtoBench.new()
			b.name = "bench"
			b.player = pl
			b.out_path = bench_out
			b.load_ms = load_ms
			add_child(b)
	if play and pneu_view != null:
		pneu_view.focus = robot
	if play or build:
		_builder()
	if play or auto != "" or show_hud:
		_hud()
	_lab()
	_tutorial()
	if play and auto == "" and show_menu:
		_controls_menu()
	_map_view()
	if play and auto == "":
		saves = ProtoSave.new()
		saves.name = "saves"
		add_child(saves)
		saves.setup(self, fresh)
	if play or want_run:
		_run()
	# Настройки графики и звука (ProtoSettings): тени солнца, громкость шины мира.
	ProtoSettings.apply()
	_lap("hud_lab_save")
	var total := 0
	for k in load_ms:
		total += load_ms[k]
	load_ms["total"] = total
	print("Загрузка: ", load_ms)
	if ProtoDeck.active:
		# Рельеф и робота не трогаем: сетка пещеры видна снаружи через вход.
		deck = ProtoDeck.apply(self, terrain, cam, sun, [get_node("ground"), get_node("ground_cave"), robot])
		print("Графика Steam Deck: слой пещеры — %d сеток" % deck.hidden)

## Уход со сцены (новая планета, выход): дождаться потоков глобуса.
func _exit_tree() -> void:
	if map_data != null and map_data.globe != null:
		map_data.globe.finish()

## Время этапа загрузки с прошлого вызова, мс.
func _lap(what: String) -> void:
	var now := Time.get_ticks_usec()
	load_ms[what] = int(load_ms.get(what, 0) + (now - _lap_t) / 1000)
	_lap_t = now

## Сохранение (ProtoSave) зовёт после постройки сцены: убрать выбуренные друзы.
func restore_mined(ids: Array) -> void:
	if mining:
		mining.restore_mined(ids)

# ---------------------------------------------------------------- палитра и свет

func _palette() -> void:
	ProtoSky.palette(planet, terrain)
	if style.vein_tint.a > 0.0:
		terrain.vein = terrain.vein.lerp(Color(style.vein_tint, 1.0), style.vein_tint.a)

func _environment() -> void:
	var sky := ProtoSky.build(planet, self, view == "cave")
	env = sky.env
	sun = sky.sun
	daynight = sky.cycle
	if day_time >= 0.0:
		# Кадр в заданное время суток: и у захваченных планет (там солнце стоит).
		daynight.time = day_time
		daynight.running = play and auto == ""
		daynight.update_now()
	# Плотность дымки и ветер — по тегам (ProtoWorldStyle); под землёй не трогаем.
	if view != "cave":
		env.fog_density *= style.fog_mult
	if view == "orbit":
		env.fog_enabled = false
	if sky.particles != null:
		sky.particles.position = Vector3(46, 26, 36)
		var g: Vector3 = sky.particles.gravity
		sky.particles.gravity = Vector3(g.x + style.wind * 3.0, g.y * style.gravity, g.z + style.wind)

# ---------------------------------------------------------------- жидкости

func _liquid_mats() -> Array:
	return planet.materials.filter(func(m): return m.phase_at(planet.ambient_temp) == Substance.Phase.LIQUID)

func _liquids() -> void:
	var liq := _liquid_mats()
	# Лава вулканических и кислота кислотных планет (как клетки 2D) — в озере;
	# если своих жидкостей нет, то и в русле, и в пещерной луже.
	hazard = ProtoHealth.hazard_liquid(planet)
	if liq.is_empty() and hazard == null:
		print("Жидких материалов нет — русла сухие")
		return
	var river_mat: Substance = liq[0] if not liq.is_empty() else hazard
	_sea_sub = river_mat
	var lake_mat: Substance = hazard if hazard != null else (liq[1] if liq.size() > 1 else liq[0])
	var cave_mat: Substance = liq[-1] if not liq.is_empty() else hazard
	var rv := MeshInstance3D.new()
	rv.mesh = ProtoLiquids.sloped_mesh(terrain, func(x, z): return terrain.river_level_at(x, z),
		func(x, z): return abs(z - terrain.river_z(x)) < 6.0 and x > terrain.lake_c.x + 2.0)
	var river_sm := ProtoLiquids.material(river_mat, planet.ambient_temp)
	# Течение к озеру (дно русла понижается к нему): полосы пены сносятся, робота сносит.
	river_sm.set_shader_parameter("flow", Vector2(-1, 0) * ProtoSwim.flow_speed(ProtoSwim.viscosity(river_mat)))
	rv.material_override = river_sm
	add_child(rv)
	_map_water.append([rv.mesh, river_mat.color])
	var rl := ProtoLiquids.look(river_mat, planet.ambient_temp)
	if rl.vapor or rl.haze:
		add_child(ProtoLiquids.vapor(Vector3(40, terrain.river_level_at(40) + 0.8, 58), Vector3(38, 0.5, 5), river_mat.color, rl.haze))
	var in_lake := func(x, z): return Vector2(x, z).distance_to(terrain.lake_c) < terrain.lake_r + 4.5
	var lake_sm := _liquid_surface(lake_mat, terrain.lake_level, in_lake,
		Vector3(terrain.lake_c.x, terrain.lake_level + 0.8, terrain.lake_c.y), Vector3(10, 0.5, 10))
	var ll: float = terrain.lake_level
	_liquid_zone(lake_mat, func(_x, _z): return ll, in_lake, lake_sm)
	var pc: Vector3 = terrain.pool_c()
	var lv: float = terrain.pool_level()
	var in_pool := func(x, z): return Vector2(x, z).distance_to(Vector2(pc.x, pc.z)) < terrain.pool_r + 1.0
	var pool_sm := _liquid_surface(cave_mat, lv, in_pool, Vector3(pc.x, lv + 0.6, pc.z), Vector3(2.5, 0.3, 2.5))
	_liquid_zone(cave_mat, func(_x, _z): return lv, in_pool, pool_sm)
	# Русло — последним: у устья озеро важнее.
	var in_river := func(x, z): return abs(z - terrain.river_z(x)) < 6.0 and x > terrain.lake_c.x + 2.0
	_liquid_zone(river_mat, func(x, z): return terrain.river_level_at(x, z), in_river, river_sm, river_flow)

## Направление течения реки в точке (вниз по руслу, к озеру).
func river_flow(x: float, _z: float) -> Vector3:
	var dz := 0.63 * cos(x * 0.09)     # производная ProtoTerrain.river_z
	return -Vector3(1, 0, dz).normalized()

## Зона жидкости для урона (ProtoHealth) и плавания (ProtoPlayer, ProtoWater):
## mat — её шейдер (круги на поверхности), flow — Callable(x, z) -> направление течения.
func _liquid_zone(s: Substance, level: Callable, area: Callable, mat: Material = null, flow = null) -> void:
	liquid_zones.append({"sub": s, "temp": ProtoHealth.liquid_temp(s, planet.ambient_temp), "level": level, "area": area,
		"mat": mat, "flow": flow})

func _liquid_surface(s: Substance, level: float, area: Callable, vpos: Vector3, vext: Vector3) -> ShaderMaterial:
	var mi := MeshInstance3D.new()
	mi.mesh = ProtoLiquids.surface_mesh(terrain, level, area)
	var sm := ProtoLiquids.material(s, planet.ambient_temp)
	mi.material_override = sm
	add_child(mi)
	_map_water.append([mi.mesh, s.color])
	var look := ProtoLiquids.look(s, planet.ambient_temp)
	if look.vapor or look.haze:
		add_child(ProtoLiquids.vapor(vpos, vext, s.color, look.haze))
	if look.glow > 0.0:
		var l := OmniLight3D.new()
		l.light_color = s.color
		l.light_energy = 1.5
		l.omni_range = 8.0
		l.position = vpos + Vector3(0, 1, 0)
		add_child(l)
	return sm

# ---------------------------------------------------------------- пещера

func _cave_crystals() -> void:
	var col: Color = terrain.vein.lerp(Color(0.45, 0.8, 1.0), 0.25)
	if style.crystal_tint.a > 0.0:
		col = col.lerp(Color(style.crystal_tint, 1.0), style.crystal_tint.a)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var rock := StandardMaterial3D.new()
	rock.albedo_color = terrain.cliff.lerp(terrain.ground, 0.3).darkened(0.1)
	rock.roughness = 0.95
	var glow := ProtoMachines.glow(col, 0.75)
	var cmat := ProtoCrystal.material(col, style.crystal_glow, style.crystal_alpha)
	if style.icicles:
		# Сосульки: прозрачный голубой лёд вместо каменных натёков.
		rock = ProtoCrystal.material(Color(0.75, 0.88, 1.0), 0.15, 0.55)
	var cc: Vector3 = terrain.cave_c
	mining = ProtoMining.new()
	mining.name = "mining"
	add_child(mining)
	var cs = _mat_with("crystalline")
	var metal = _mat_with("metallic")
	var cs_sub: Substance = cs if cs != null else (_solid_mats()[0] if not _solid_mats().is_empty() else World.starter_substance())
	# Сверло — из самого твёрдого материала планеты (как собранный из него бур
	# в игре); --drill-hard=N — задать твёрдость, чтобы проверить «слишком мягкий».
	var hard: float = metal.hardness if metal != null else 2.5
	for m in _solid_mats():
		hard = maxf(hard, m.hardness)
	if drill_hard >= 0.0:
		hard = drill_hard
	mining.setup(cs_sub, hard, planet.ambient_temp, terrain, cmat)
	print("Друзы: %s, твёрдость %.1f; бур %.1f" % [_label(cs_sub), cs_sub.hardness, hard])
	# Натёки: сталактиты со свода, сталагмиты с пола — все одной сеткой.
	var drips := []
	var made := 0
	for i in 300:
		if made >= style.drips * (2 if style.icicles else 1):
			break
		var q := cc + Vector3(rng.randf_range(-1, 1) * terrain.cave_r, 0, rng.randf_range(-1, 1) * terrain.cave_r)
		if terrain.solid(q.x, q.y, q.z):
			continue
		var pcq: Vector3 = terrain.pool_c()
		if Vector2(q.x, q.z).distance_to(Vector2(pcq.x, pcq.z)) < terrain.pool_r + 0.6 and rng.randf() < 0.8:
			continue
		var down := rng.randf() < 0.55
		var p := q
		var hit := false
		for k in 40:
			p.y += 0.2 if down else -0.2
			if terrain.solid(p.x, p.y, p.z):
				hit = true
				break
		if not hit:
			continue
		if not _clear_of_view(p):
			continue
		var len := rng.randf_range(0.3, 1.1) * (1.6 if rng.randf() < 0.2 else 1.0)
		if style.icicles and down:
			len *= 1.8
		var c := CylinderMesh.new()
		c.top_radius = rng.randf_range(0.08, 0.22) if down else 0.02
		c.bottom_radius = 0.02 if down else rng.randf_range(0.1, 0.26)
		c.height = len
		c.radial_segments = 7
		drips.append([c, Transform3D(Basis(), p + Vector3(0, -len / 2.0 + 0.1 if down else len / 2.0 - 0.1, 0))])
		made += 1
	if not drips.is_empty():
		var di := MeshInstance3D.new()
		di.name = "drips"
		di.mesh = ProtoBatch.merged(drips)
		di.material_override = rock
		add_child(di)
	# Друзы кристаллов на стенах там, где выходит жила; у крупных — свой свет.
	var lights := 0
	made = 0
	for i in 600:
		if made >= style.druzes:
			break
		# Друзы ниже середины стен и на полу — их видно в луче фары, они «стоят», а не висят.
		# В жеоде — по всему своду.
		var up := 0.9 if style.cave == "geode" else 0.15
		var dir := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.9, up), rng.randf_range(-1, 1)).normalized()
		var p := cc
		var hit := false
		for k in 60:
			p += dir * 0.2
			if terrain.solid(p.x, p.y, p.z):
				hit = true
				break
		if not hit:
			continue
		if not _clear_of_view(p):
			continue
		var nrm := _normal_at(p)
		var base := p - dir * 0.05
		# Друза: главный кристалл и поросль вокруг, все растут веером от стены,
		# основания утоплены в породу, у подножия — мелкие «щётки».
		var druse := Node3D.new()
		druse.name = "druse_%d" % made
		druse.set_meta("normal", nrm)
		add_child(druse)
		var cnt := rng.randi_range(5, 9)
		var main_len := rng.randf_range(0.7, 1.3) * style.druze_size
		for m in cnt:
			var spread := 0.15 if m == 0 else rng.randf_range(0.25, 0.7)
			var tilt := (nrm + Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * spread).normalized()
			var len := main_len if m == 0 else main_len * rng.randf_range(0.25, 0.7)
			var r := len * rng.randf_range(0.11, 0.16)
			var ci := MeshInstance3D.new()
			ci.mesh = ProtoCrystal.mesh(len, r, rng, style.habit)
			ci.material_override = cmat
			var y := tilt
			var ref := Vector3.UP if absf(y.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
			var x := y.cross(ref).normalized()
			var off := Vector3.ZERO if m == 0 else (x * cos(m * 2.4) + x.cross(y) * sin(m * 2.4)) * rng.randf_range(0.08, 0.28)
			ci.transform = Transform3D(Basis(x, y, x.cross(y)).rotated(y, rng.randf() * TAU), base + off - tilt * len * 0.12)
			ci.name = "crystal_%d" % m
			ci.set_meta("len", len)
			ci.set_meta("r", r)
			druse.add_child(ci)
		# Щётка: мелкие кристаллики вокруг подножия, почти вровень с породой.
		var fx := nrm.cross(Vector3.UP if absf(nrm.y) < 0.9 else Vector3.RIGHT).normalized()
		var fz := nrm.cross(fx)
		var brush := []
		for m in rng.randi_range(8, 14):
			var a := rng.randf() * TAU
			var len := rng.randf_range(0.06, 0.2)
			var tilt := (nrm + Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * 0.8).normalized()
			var bm := ProtoCrystal.mesh(len, len * rng.randf_range(0.14, 0.22), rng, style.habit)
			var y := tilt
			var x := y.cross(Vector3.UP if absf(y.y) < 0.9 else Vector3.RIGHT).normalized()
			var at := base + (fx * cos(a) + fz * sin(a)) * rng.randf_range(0.2, 0.5) - nrm * 0.03
			brush.append([bm, Transform3D(Basis(x, y, x.cross(y)), at)])
		# Щётка не бурится по кристаллику — одна сетка на друзу, без тени (вровень с породой).
		var bi := MeshInstance3D.new()
		bi.name = "brush"
		bi.mesh = ProtoBatch.merged(brush)
		bi.material_override = cmat
		bi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		druse.add_child(bi)
		if lights < 4:
			var l := OmniLight3D.new()
			l.light_color = col
			l.light_energy = 1.6
			l.omni_range = 6.0
			l.position = base + nrm * 0.7
			add_child(l)
			lights += 1
		mining.add_druse(druse)
		made += 1
	_cave_deposits(cs_sub, rng)

## Залежи прочих твёрдых веществ планеты — каждая в своей форме (ProtoDeposit):
## жилы и пласты — в стенах, конкреции, корки, глыбы и натёки — на полу.
func _cave_deposits(skip: Substance, rng: RandomNumberGenerator) -> void:
	var look := ProtoDeposit.planet_look(planet, style.habit)
	var cc: Vector3 = terrain.cave_c
	var placed: Array = []
	for d in mining.druses:
		if not d.crystals.is_empty():
			placed.append(d.crystals[0].global_position)
	var subs := _solid_mats().filter(func(m): return m != skip)
	var kinds := 0
	for s: Substance in subs:
		if kinds >= 4:
			break
		var form := ProtoDeposit.form_for(s)
		var mat := ProtoDeposit.material(s, form, look)
		var floor_form := ProtoDeposit.on_floor(form)
		var made := 0
		for i in 400:
			if made >= 2:
				break
			var dy := rng.randf_range(-0.95, -0.55) if floor_form else rng.randf_range(-0.6, 0.0)
			var dir := Vector3(rng.randf_range(-1, 1), dy, rng.randf_range(-1, 1)).normalized()
			var p := cc
			var hit := false
			for k in 60:
				p += dir * 0.2
				if terrain.solid(p.x, p.y, p.z):
					hit = true
					break
			if not hit or not _clear_of_view(p):
				continue
			var nrm := _normal_at(p)
			if floor_form and nrm.y < 0.6:
				continue
			if not floor_form:
				# В стене — на высоте, до которой робот дотянется с пола.
				var fl := terrain.floor_at(p + Vector3(nrm.x, 0, nrm.z).normalized() * 0.8 + Vector3(0, 0.5, 0))
				if absf(nrm.y) > 0.6 or p.y - fl < 0.2 or p.y - fl > 1.5:
					continue
			var pcq: Vector3 = terrain.pool_c()
			if Vector2(p.x, p.z).distance_to(Vector2(pcq.x, pcq.z)) < terrain.pool_r + 0.8:
				continue
			if placed.any(func(q): return q.distance_to(p) < 1.8):
				continue
			var n := ProtoDeposit.build(s, form, rng.randf_range(0.8, 1.1), rng, look, mat)
			add_child(n)
			ProtoDeposit.place(n, p - dir * 0.04, nrm, rng)
			n.name = "deposit_%s_%d" % [form, mining.druses.size()]
			mining.add_druse(n)
			placed.append(p)
			if made == 0:
				# Неяркий свет у первой залежи: в тёмной пещере её видно издали.
				var l := OmniLight3D.new()
				l.light_color = s.color.lerp(Color.WHITE, 0.5)
				l.light_energy = 0.9
				l.omni_range = 3.5
				l.position = p + nrm * 1.0
				add_child(l)
			made += 1
		if made > 0:
			kinds += 1
			print("Залежь: %s — %s" % [ProtoDeposit.NAMES[form], _label(s)])

## Место робота в пещере и желаемая точка камеры: [робот, цель взгляда, камера].
func _cave_spot() -> Array:
	var cc: Vector3 = terrain.cave_c
	var rp := Vector3(cc.x - 4.0, cc.y + 1.0, cc.z + 3.0)
	rp.y = terrain.floor_at(rp)
	var tg := Vector3(cc.x + 3.0, rp.y, cc.z - 3.0)
	var f := (tg - rp).normalized()
	var r := f.cross(Vector3.UP).normalized()
	return [rp, tg, rp - f * 4.2 + r * 2.0 + Vector3(0, 2.8, 0)]

## Не загораживать кадр: у робота и на линии к камере натёков и друз нет.
func _clear_of_view(p: Vector3) -> bool:
	var sp := _cave_spot()
	var a: Vector3 = sp[0]
	var b: Vector3 = sp[2]
	var ab := b - a
	var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	return p.distance_to(a + ab * t) > 2.2

## Нормаль поверхности породы по полю плотности (наружу, в воздух).
func _normal_at(p: Vector3) -> Vector3:
	var e := 0.3
	var g := Vector3(terrain.density(p.x + e, p.y, p.z) - terrain.density(p.x - e, p.y, p.z),
		terrain.density(p.x, p.y + e, p.z) - terrain.density(p.x, p.y - e, p.z),
		terrain.density(p.x, p.y, p.z + e) - terrain.density(p.x, p.y, p.z - e))
	return (-g).normalized()

# ---------------------------------------------------------------- особые места по тегам

## Лава в кратере вулкана, друзы у подножия игл, грибы снаружи и в гроте.
func _surface_features() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 7 + 3
	if style.volcano:
		var c := ProtoTerrain.VOLC_C
		var lava := MeshInstance3D.new()
		var disk := CylinderMesh.new()
		disk.top_radius = 3.6
		disk.bottom_radius = 3.6
		disk.height = 0.1
		lava.mesh = disk
		var lm := StandardMaterial3D.new()
		lm.albedo_color = Color(0.9, 0.3, 0.05)
		lm.emission_enabled = true
		lm.emission = Color(1.0, 0.4, 0.08)
		lm.emission_energy_multiplier = 3.0
		lava.material_override = lm
		lava.position = Vector3(c.x, 23.6, c.y)
		add_child(lava)
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.5, 0.2)
		l.light_energy = 3.0
		l.omni_range = 14.0
		l.position = Vector3(c.x, 26.0, c.y)
		add_child(l)
	if style.surface_druzes > 0:
		var col: Color = terrain.vein.lerp(Color(style.crystal_tint, 1.0), style.crystal_tint.a)
		var cmat := ProtoCrystal.material(col, style.crystal_glow * 0.6, style.crystal_alpha)
		var made := 0
		for i in 400:
			if made >= style.surface_druzes:
				break
			var x := rng.randf_range(4, terrain.sx - 4)
			var z := rng.randf_range(4, terrain.sz - 4)
			if not terrain.free_spot(x, z, 0.5):
				continue
			var p := Vector3(x, terrain.floor_at(Vector3(x, terrain.sy, z)), z)
			var nrm := _normal_at(p + Vector3(0, 0.05, 0))
			if nrm.y < 0.4:
				continue
			_druze(p, nrm, rng.randf_range(0.8, 1.8) * style.druze_size, cmat, rng)
			made += 1
	if style.mushrooms > 0:
		# Снаружи — крупные, в гроте — поменьше и ярче.
		var made := 0
		for i in 500:
			if made >= style.mushrooms / 2:
				break
			var x := rng.randf_range(4, terrain.sx - 4)
			var z := rng.randf_range(4, terrain.sz - 4)
			if not terrain.free_spot(x, z, 1.0):
				continue
			var p := Vector3(x, terrain.surface_h(x, z), z)
			if _normal_at(p + Vector3(0, 0.05, 0)).y < 0.7:
				continue
			_mushroom(p, rng.randf_range(1.6, 4.5), rng)
			made += 1
		made = 0
		var cc := terrain.cave_c
		for i in 400:
			if made >= style.mushrooms / 2:
				break
			var q := cc + Vector3(rng.randf_range(-1, 1) * terrain.cave_r, 0, rng.randf_range(-1, 1) * terrain.cave_r)
			if terrain.solid(q.x, q.y, q.z):
				continue
			var p := Vector3(q.x, terrain.floor_at(q), q.z)
			if terrain.solid(p.x, p.y + 1.2, p.z) or not _clear_of_view(p):
				continue
			var pcq := terrain.pool_c()
			if Vector2(p.x, p.z).distance_to(Vector2(pcq.x, pcq.z)) < terrain.pool_r + 0.4:
				continue
			_mushroom(p, rng.randf_range(0.35, 0.9), rng)
			made += 1

## Инопланетная органика по тегам (ProtoFlora): мох, заросли, пещерные трутовики.
func _flora() -> void:
	var keep := func(p: Vector3) -> bool:
		return not terrain.cave_box.has_point(p) or _clear_of_view(p)
	var meshes := flora.build(self, terrain, keep, ProtoDeck.active)
	print("Флора: %s; %d растений, %d вершин, %d сеток" % [flora.summary(), flora.plants, flora.verts(), meshes])

## --view=wild / shore: робот далеко от завода — у россыпи залежей (wild) или на
## берегу моря (shore); камера из-за плеча. Всё в системе планеты: при первом
## кадре шар повернётся под робота вместе с камерой.
func _wild_shot(shore: bool) -> void:
	var t := terrain
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + 5
	var rp := Vector3.INF
	var tg := Vector3.INF
	var best := INF
	for i in 3000:
		var ang := (rng.randf_range(260.0, 600.0) if wild_far < 0.0 else wild_far * rng.randf_range(0.93, 1.0)) / t.radius
		var th := rng.randf() * TAU
		var d := Vector3(sin(ang) * cos(th), cos(ang), sin(ang) * sin(th))
		if shore:
			if t.sea_level == -INF:
				break
			var h := t.sphere_h(d)
			if h < t.sea_level + 0.4 or h > t.sea_level + 1.6:
				continue
			# К морю: соседняя точка ниже уровня.
			var e1 := d.cross(Vector3.UP).normalized()
			var e2 := d.cross(e1)
			for k in 8:
				var a := k * TAU / 8.0
				var dd := (d + (e1 * cos(a) + e2 * sin(a)) * (14.0 / t.radius)).normalized()
				var back := (d - (dd - d) * 0.6).normalized()
				if t.sphere_h(dd) < t.sea_level - 1.0 and t.sphere_h(back) < h + 1.5:
					rp = t.center + d * (t.radius + h)
					tg = t.center + dd * (t.radius + t.sea_level)
					break
			if rp != Vector3.INF:
				break
		else:
			var k := planet_fill.key_of(d)
			var out := planet_fill._arrays(k)
			if out.deps.is_empty():
				continue
			var e: Array = out.deps[0]
			var fr: Transform3D = out.frame
			tg = fr * (e[0] as Vector3)
			var up := (tg - t.center).normalized()
			var side := up.cross(Vector3.FORWARD).normalized()
			var dd := (tg - t.center + side * 2.6).normalized()
			rp = t.center + dd * (t.radius + t.sphere_h(dd))
			break
	if rp == Vector3.INF:
		print("Вид %s: подходящего места не нашлось" % view)
		return
	var fr := planet_stream.frame_for(rp)
	var rw := fr * rp
	var tw := fr * tg
	var dw := Vector3(tw.x - rw.x, 0, tw.z - rw.z).normalized()
	robot.position = rp
	robot.rotation.y = atan2(dw.x, dw.z)
	var side := dw.cross(Vector3.UP)
	var cw := rw - dw * (4.0 if not shore else 7.0) + Vector3.UP * (2.2 if not shore else 4.5) + side * 1.8
	# Камера не ниже 2,5 м над землёй (за гребнем кадр слепой).
	var cp := fr.affine_inverse() * cw
	var cd := (cp - t.center).normalized()
	var cmin := t.radius + t.sphere_h(cd) + 2.5
	if (cp - t.center).length() < cmin:
		cw = fr * (t.center + cd * cmin)
	var ct := Transform3D(Basis(), cw).looking_at(tw.lerp(rw, 0.45) + Vector3.UP * 0.3, Vector3.UP)
	cam.far = 4000.0
	cam.global_transform = fr.affine_inverse() * ct

## --view=flora: робот у самых густых зарослей, камера из-за плеча на них.
func _flora_shot() -> void:
	var tg := flora.best
	# Откуда смотреть: посуше и поровнее, в 4,5 м от зарослей.
	var d := Vector3.FORWARD
	var rp := tg
	var best_h := -INF
	for i in 12:
		var dd := Vector3(cos(TAU * i / 12.0), 0, sin(TAU * i / 12.0))
		var q := tg - dd * 4.5
		q.y = terrain.floor_at(Vector3(q.x, terrain.sy, q.z))
		var dry := q.y - maxf(terrain.lake_level, terrain.river_level_at(q.x))
		var score := minf(dry, 1.0) - absf(q.y - tg.y) * 0.3
		if style.volcano and Vector2(q.x, q.z).distance_to(ProtoTerrain.VOLC_C) < 11.0:
			score -= 5.0
		# Камера за спиной должна видеть заросли, а не стену расщелины.
		var cp := q - dd * 4.0 + Vector3(0, 2.4, 0)
		for k in 10:
			var m := cp.lerp(tg + Vector3(0, 0.8, 0), k / 10.0)
			if terrain.solid(m.x, m.y, m.z):
				score -= 2.0
				break
		if score > best_h:
			best_h = score
			d = dd
			rp = q
	robot.position = rp
	robot.look_at(Vector3(tg.x, rp.y, tg.z), Vector3.UP, true)
	var r := d.cross(Vector3.UP).normalized()
	cam.position = rp - d * 4.0 + r * 1.6 + Vector3(0, 2.4, 0)
	cam.position.y = maxf(cam.position.y, terrain.surface_h(cam.position.x, cam.position.z) + 1.2)
	cam.look_at(tg + Vector3(0, 0.8, 0))

## Друза: главный кристалл и поросль вокруг, веером от поверхности.
func _druze(base: Vector3, nrm: Vector3, main_len: float, cmat: Material, rng: RandomNumberGenerator) -> void:
	# Друза на поверхности не бурится — одной сеткой.
	var parts := []
	for m in rng.randi_range(4, 8):
		var spread := 0.15 if m == 0 else rng.randf_range(0.25, 0.7)
		var y := (nrm + Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * spread).normalized()
		var len := main_len if m == 0 else main_len * rng.randf_range(0.25, 0.7)
		var cm := ProtoCrystal.mesh(len, len * rng.randf_range(0.11, 0.16), rng, style.habit)
		var x := y.cross(Vector3.UP if absf(y.y) < 0.9 else Vector3.RIGHT).normalized()
		var off := Vector3.ZERO if m == 0 else (x * cos(m * 2.4) + x.cross(y) * sin(m * 2.4)) * rng.randf_range(0.1, 0.35)
		parts.append([cm, Transform3D(Basis(x, y, x.cross(y)).rotated(y, rng.randf() * TAU), base + off - y * len * 0.12)])
	var ci := MeshInstance3D.new()
	ci.mesh = ProtoBatch.merged(parts)
	ci.material_override = cmat
	add_child(ci)

## Гриб: изогнутая ножка и светящаяся снизу шляпка.
func _mushroom(p: Vector3, h: float, rng: RandomNumberGenerator) -> void:
	var cap_col := Color.from_hsv(fposmod(0.78 + rng.randf_range(-0.1, 0.12), 1.0), 0.55, 0.75)
	var node := Node3D.new()
	node.position = p
	node.rotation = Vector3(rng.randf_range(-0.15, 0.15), rng.randf() * TAU, rng.randf_range(-0.15, 0.15))
	add_child(node)
	var stem := MeshInstance3D.new()
	var sc := CylinderMesh.new()
	sc.top_radius = h * 0.07
	sc.bottom_radius = h * 0.11
	sc.height = h
	sc.radial_segments = 8
	stem.mesh = sc
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color(0.85, 0.82, 0.74)
	sm.roughness = 0.8
	stem.material_override = sm
	stem.position.y = h * 0.5
	node.add_child(stem)
	var cap := MeshInstance3D.new()
	var cm := SphereMesh.new()
	cm.radius = h * 0.42
	cm.height = h * 0.34
	cm.is_hemisphere = true
	cm.radial_segments = 12
	cm.rings = 4
	cap.mesh = cm
	var capm := StandardMaterial3D.new()
	capm.albedo_color = cap_col
	capm.roughness = 0.6
	capm.emission_enabled = true
	capm.emission = cap_col.lerp(Color(0.6, 1.0, 0.7), 0.4)
	capm.emission_energy_multiplier = 0.9
	cap.material_override = capm
	cap.position.y = h * 0.95
	node.add_child(cap)
	if h < 1.0 and rng.randf() < 0.4:
		var l := OmniLight3D.new()
		l.light_color = capm.emission
		l.light_energy = 0.8
		l.omni_range = 3.0
		l.position.y = h * 0.8
		node.add_child(l)

# ---------------------------------------------------------------- завод

func _mat_with(tag: String):
	return ProtoSky.mat_with(planet, tag)

func _solid_mats() -> Array:
	return ProtoSky.solid_mats(planet)

## Живой пневмозавод на площадке: приёмник с добытыми кристаллами → трубы →
## дробилка → печь → бак, насос сбоку; за ним пушка бьёт через площадку в
## приёмник → центрифуга → спекатель → бак (ProtoPneumatics). Корпуса — из металла
## планеты; к моменту кадра завод уже работает.
func _factory() -> void:
	var metal = _mat_with("metallic")
	var cryst = _mat_with("crystalline")
	var a: Substance = metal if metal != null else World.starter_substance()
	var ore: Substance = cryst if cryst != null else (_solid_mats()[0] if not _solid_mats().is_empty() else a)
	var pc := terrain.plateau()
	var top := pc.y + 0.1
	var goals_row := view == "goals"
	var slab := ProtoMachines.slab(Vector3(17, 0.6, 21 if goals_row else 15), terrain.ground.lerp(Color(0.5, 0.5, 0.52), 0.6))
	slab.position = Vector3(pc.x, top - 0.28, pc.z + (5.5 if goals_row else 2.5))
	add_child(slab)
	ProtoMachines.add_box_collider(slab, ProtoMachines.LAYER_GROUND)
	pneu = ProtoPneumatics.new(planet)
	factory_mat = a
	pneu.build_demo(Vector2i(-3, 0), a)
	# Вторая труба линии — лаборатория: груз из приёмника проходит пробы.
	pneu.remove(Vector2i(-1, 0))
	pneu.place("lab", Vector2i(-1, 0), 0, a)
	# Приёмник пуст: сырьё для завода добывает робот (с 30 кг на старте первый
	# этап цели выполнялся сам за 20 с). Пушке — одна капсула: видно, как она бьёт.
	var cannon := pneu.build_logistics(Vector2i(-4, 3), a)
	cannon.items.append(Portion.new(ore, 2.0, planet.ambient_temp))
	if goals_row:
		pneu.build_goals(Vector2i(-4, 7), a, ore)
	pneu_view = ProtoPneumaticsView.new()
	pneu_view.name = "pneumatics"
	add_child(pneu_view)
	pneu_origin = Vector3(pc.x, top, pc.z - 1.0)
	pneu_view.setup(pneu, pneu_origin)
	pneu_view.warm(9.0)
	yard_light = OmniLight3D.new()
	yard_light.name = "yard_light"
	yard_light.light_color = Color(1.0, 0.88, 0.7)
	yard_light.omni_range = 18.0
	yard_light.omni_attenuation = 1.2
	yard_light.light_energy = 0.0
	yard_light.position = pneu_origin + Vector3(0, 7.0, 3.0)
	add_child(yard_light)
	# Знания лаборатория пишет с начала игры (разогрев кадра их не трогает).
	pneu.knowledge = lab_desk.world
	lab_desk.net = pneu
	lab_desk.origin = pneu_view.origin
	print("Завод: корпуса из %s, в приёмнике %s" % [_label(a), _label(ore)])

func _label(s: Substance) -> String:
	return "%s %s" % [s.name, str(s.tags)]

# ---------------------------------------------------------------- робот и камера

func _robot_and_camera() -> void:
	var drill = _mat_with("metallic")
	if robot_design != "old":
		# Идёт по планете; в пещере — стоит и светит глазом.
		RobotAnim.default_mode = "idle" if view in ["cave", "wild", "shore"] else "walk"
		robot = RobotDesigns.build(robot_design, drill.color if drill != null else Color(0, 0, 0, 0))
		# Сотни мелких деталей — по сетке на шарнир и материал (ProtoBatch).
		ProtoBatch.merge_children(robot)
	else:
		robot = ProtoRobot.new(Color(0.78, 0.8, 0.84), drill.color if drill != null else Color(0.6, 0.6, 0.65), Color(0.9, 0.55, 0.2))
	add_child(robot)
	cam = Camera3D.new()
	cam.fov = 62.0
	add_child(cam)
	var pc := terrain.plateau()
	var top := pc.y + 0.1
	match view:
		"factory":
			# Робот у линии завода лицом к свободной клетке; камера сверху-сбоку.
			robot.position = Vector3(pc.x + 2.0, top, pc.z + 3.0)
			robot.rotation.y = PI
			cam.position = Vector3(pc.x + 4.5, top + 6.5, pc.z + 10.5)
			cam.look_at(Vector3(pc.x - 0.5, top + 0.6, pc.z - 1.0))
		"goals":
			# Ряд сооружений целей (клетки y = 7) с южной стороны площадки.
			robot.position = Vector3(pc.x + 3.5, top, pc.z + 15.5)
			robot.rotation.y = PI * 0.8
			cam.position = Vector3(pc.x + 1.0, top + 6.0, pc.z + 22.5)
			cam.look_at(Vector3(pc.x + 1.0, top + 1.0, pc.z + 12.0))
		"plan":
			robot.position = Vector3(pc.x - 1.0, top, pc.z + 5.0)
			robot.rotation.y = PI
			cam.position = Vector3(pc.x - 4.0, top + 16.0, pc.z + 14.0)
			cam.look_at(Vector3(pc.x - 1.0, top, pc.z - 1.0))
		"horizon":
			# С края площадки завода — через участок к горизонту планеты.
			robot.position = Vector3(pc.x - 4.0, top, pc.z + 4.0)
			robot.rotation.y = PI * 0.75
			cam.far = 4000.0
			cam.fov = 62.0
			cam.position = Vector3(pc.x + 6.0, top + 9.0, pc.z - 8.0)
			cam.look_at(Vector3(pc.x - 30.0, top - 4.0, pc.z + 40.0))
		"far":
			# Далеко от завода: вокруг шар, над горизонтом — хребты.
			var fx := terrain.sx + 260.0
			var fz := terrain.sz * 0.5 + 20.0
			robot.position = Vector3(fx, terrain.surface_h(fx, fz), fz)
			robot.rotation.y = -PI * 0.5
			cam.far = 4000.0
			cam.position = robot.position + Vector3(7.0, 4.5, 3.0)
			cam.look_at(robot.position + Vector3(-30.0, 0.0, 0.0))
		"orbit":
			# Вся планета с высоты: место посадки сверху.
			robot.position = Vector3(pc.x, top, pc.z)
			cam.far = 20000.0
			cam.fov = 40.0
			var r := PLANET_R
			cam.position = Vector3(pc.x + r * 1.6, r * 1.3, pc.z + r * 2.2)
			cam.look_at(Vector3(pc.x, -r * 0.9, pc.z))
		"horizon_high":
			robot.position = Vector3(pc.x, top, pc.z)
			cam.far = 5000.0
			cam.fov = 60.0
			cam.position = Vector3(terrain.sx * 0.5 + 60.0, 150.0, terrain.sz + 160.0)
			cam.look_at(Vector3(terrain.sx * 0.5 - 60.0, -60.0, -200.0))
		"vista":
			# Робот на склоне над руслом, вдоль реки к озеру.
			var vx := 52.0
			var vz: float = terrain.river_z(vx) - 3.0
			while vz > 2.0 and terrain.surface_h(vx, vz) < terrain.river_level_at(vx) + 1.2:
				vz -= 0.5
			var rp2 := Vector3(vx, terrain.surface_h(vx, vz), vz)
			robot.position = rp2
			var tg := Vector3(terrain.lake_c.x, terrain.lake_level, terrain.lake_c.y)
			robot.look_at(Vector3(tg.x, rp2.y, tg.z), Vector3.UP, true)
			var f2 := (Vector3(tg.x, rp2.y, tg.z) - rp2).normalized()
			cam.position = rp2 - f2 * 5.0 + f2.cross(Vector3.UP).normalized() * 1.5 + Vector3(0, 3.5, 0)
			cam.look_at(rp2 + f2 * 20.0 + Vector3(0, -3.0, 0))
		"overview":
			# Вся карта сверху наискосок: видно форму рельефа.
			robot.position = Vector3(pc.x, top, pc.z)
			cam.fov = 58.0
			cam.position = Vector3(terrain.sx * 0.5 + 4.0, 68.0, terrain.sz + 22.0)
			cam.look_at(Vector3(terrain.sx * 0.5, 10.0, terrain.sz * 0.42))
		"cave":
			# Робот у края зала лицом к центру; камера над плечом смотрит вдоль зала.
			var sp := _cave_spot()
			var rp3: Vector3 = sp[0]
			robot.position = rp3
			if robot is ProtoRobot:
				(robot as ProtoRobot).walk = false
				(robot as ProtoRobot).eye_light.light_energy = 2.5
			else:
				var eye := robot.find_child("eye_light", true, false) as OmniLight3D
				if eye:
					eye.light_energy = 1.0
					eye.omni_range = 5.0
				var lamp := robot.find_child("head_lamp", true, false) as SpotLight3D
				if lamp:
					lamp.light_energy = 4.0
				robot.add_child(_dust())
			var tg3: Vector3 = sp[1]
			robot.look_at(tg3, Vector3.UP, true)
			var f3 := (tg3 - rp3).normalized()
			cam.position = _spring(rp3 + Vector3(0, 1.6, 0), sp[2])
			cam.look_at(rp3 + f3 * 3.5 + Vector3(0, 0.3, 0))
		"sky":
			# Небо: робот у завода, камера низко за ним смотрит вверх в сторону
			# полуденного солнца — видно путь солнца, луны, кольца, звёзды.
			var rs := Vector3(pc.x + 5.0, 0, pc.z + 4.0)
			rs.y = terrain.surface_h(rs.x, rs.z)
			robot.position = rs
			var nd := daynight.noon_dir if daynight != null else Vector3(0, 0.7, 0.7)
			var fl := Vector3(nd.x, 0, nd.z).normalized()
			robot.look_at(rs + fl * 10.0, Vector3.UP, true)
			cam.fov = 72.0
			cam.position = rs - fl * 3.2 + fl.cross(Vector3.UP) * 1.2 + Vector3(0, 1.4, 0)
			cam.look_at(cam.position + fl * 10.0 + Vector3(0, 4.2, 0))
		_:
			# Кадр без игрока — прежняя точка и ракурс через весь завод; играя —
			# свободное место (камеру ставит пружинная штанга ProtoPlayer).
			var rp := start_spot() if play or auto != "" else Vector3(pc.x + 5.0, 0, pc.z + 4.0)
			rp.y = terrain.surface_h(rp.x, rp.z)
			robot.position = rp
			var tgt := Vector3(pc.x - 4.0, rp.y, pc.z - 3.0)
			robot.look_at(tgt, Vector3.UP, true)
			var fwd := (tgt - rp).normalized()
			var right := fwd.cross(Vector3.UP).normalized()
			cam.position = rp - fwd * 4.2 + right * 1.3 + Vector3(0, 2.6, 0)
			cam.look_at(rp + fwd * 12.0 + Vector3(0, 0.2, 0))
	cam.current = true

## Где робот высаживается и собирается после поломки: у площадки завода, но не
## между машинами — линия логистики (капсулы) проходит рядом, и с прежней точки
## робот не мог выйти. Ищем ближайшее место в CLEAR м от любой детали.
const CLEAR := 3.5
func start_spot() -> Vector3:
	var pc := terrain.plateau()
	var want := Vector3(pc.x + 5.0, 0, pc.z + 4.0)
	var best := want
	var best_score := -INF
	if pneu != null and pneu_view != null:
		var cells: Array = []
		for c in pneu.parts:
			cells.append(ProtoPneumatics.cell_pos(pneu_view.origin, c))
		for ix in range(-12, 13):
			for iz in range(-12, 13):
				var q := want + Vector3(ix, 0, iz) * 0.5
				var clear := INF
				for p: Vector3 in cells:
					clear = minf(clear, Vector2(p.x - q.x, p.z - q.z).length())
				var score := minf(clear, CLEAR) - 0.05 * q.distance_to(want)
				if score > best_score:
					best_score = score
					best = q
	best.y = terrain.surface_h(best.x, best.z)
	return best

## Стройка роботом: призрак детали перед ним, HUD, выгрузка груза в приёмник.
func _builder() -> void:
	if pneu_view == null:
		return
	var b := ProtoBuilder.new()
	b.name = "builder"
	add_child(b)
	b.setup(pneu_view, robot, _solid_mats())
	# Сначала — материал, из которого стоит завод: насос из более прочного
	# поднимает давление всей сети выше предела её деталей, и они лопаются разом.
	var i := b.mats.find(factory_mat)
	if i >= 0:
		b.mat_i = i
	b.active = build

## Пол пещеры под точкой: вниз по полю плотности до породы.
func _floor_at(p: Vector3) -> float:
	var y := p.y
	while y > 1.0 and not terrain.solid(p.x, y - 0.1, p.z):
		y -= 0.1
	return y

## Камера на пружинной штанге: от опоры к желаемой точке, пока не упрётся в породу.
func _spring(from: Vector3, want: Vector3) -> Vector3:
	var d := want - from
	var steps := int(d.length() / 0.15) + 1
	var last := from
	for i in range(1, steps + 1):
		var q := from + d * (float(i) / steps)
		if terrain.solid(q.x, q.y, q.z) or terrain.solid(q.x, q.y + 0.3, q.z):
			return last - d.normalized() * 0.2
		last = q
	return want

## Пылинки в луче фары.
func _dust() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = 45
	p.lifetime = 6.0
	p.preprocess = 6.0
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(1.5, 0.8, 2.5)
	p.position = Vector3(0, 1.4, 4.0)
	p.direction = Vector3(0, 0.2, 0)
	p.spread = 180.0
	p.gravity = Vector3(0.02, -0.01, 0)
	p.initial_velocity_min = 0.02
	p.initial_velocity_max = 0.08
	p.scale_amount_min = 0.004
	p.scale_amount_max = 0.01
	var q := SphereMesh.new()
	q.radius = 1.0
	q.height = 2.0
	q.radial_segments = 4
	q.rings = 2
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.9, 0.9, 0.85)
	m.roughness = 1.0
	q.material = m
	p.mesh = q
	return p

func _caption() -> void:
	var layer := CanvasLayer.new()
	_caption_layer = layer
	layer.name = "caption"
	add_child(layer)
	var l := Label.new()
	l.position = Vector2(16, 12)
	l.size = Vector2(880, 0)             # справа сверху — панель завода в HUD
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", 16)
	l.add_theme_color_override("font_color", Color(1, 1, 1))
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	l.add_theme_constant_override("outline_size", 5)
	var liq := _liquid_mats().map(func(m): return "%s %s" % [m.name, ", ".join(PackedStringArray(m.tags.map(func(t): return MaterialTags.display(t))))])
	l.text = "%s (seed %d) — %s\n%.0f °C, %.2f атм, %.1f g, вид: %s\n%s; %s\nЖидкости: %s" % [planet.name, seed_value,
		", ".join(PackedStringArray(planet.tags.map(func(t): return PlanetTags.display(t)))), planet.ambient_temp, planet.atm_pressure, planet.gravity, view, style.summary(),
		flora.summary(),
		"; ".join(PackedStringArray(liq)) if not liq.is_empty() else "нет"]
	if hazard != null:
		l.text += "; %s в озере" % hazard.name.to_lower()
	layer.add_child(l)

## Прочность корпуса: корпус — из металла планеты (как и цвет робота), урон от
## жидкостей, среды и падений; ремонт у завода; поломка — возврат к заводу.
func _health(pl: ProtoPlayer) -> void:
	var hull = _mat_with("metallic")
	if hull == null:
		var solids := _solid_mats()
		solids.sort_custom(func(a, b): return a.hardness > b.hardness)
		hull = solids[0] if not solids.is_empty() else null
	health = ProtoHealth.new()
	health.name = "health"
	health.setup(robot, terrain, planet, hull)
	health.player = pl
	health.zones = liquid_zones
	health.active = (play and auto == "") or auto == "hurt"
	health.input_enabled = play and auto == ""
	var pc := terrain.plateau()
	health.base = start_spot()
	health.factory_at = pc + Vector3(0, 0, 2.5)    # центр площадки завода
	pl.health = health
	add_child(health)
	var wt := ProtoWater.new()
	wt.name = "water"
	wt.setup(pl, health, env, liquid_zones)
	add_child(wt)
	var fx := ProtoHurtFx.new()
	fx.name = "hurt_fx"
	fx.cam = cam
	fx.mute = mute
	add_child(fx)
	health.fx = fx
	if auto == "hurt":
		health.wrecked.connect(func(): pl.route = [])
		_hurt_start(pl)

## --auto=hurt: сброс с высоты у озера, шаг в жидкость, поломка, сборка на базе.
func _hurt_start(pl: ProtoPlayer) -> void:
	var pc := terrain.plateau()
	var lc := Vector3(terrain.lake_c.x, 0, terrain.lake_c.y)
	var dir := Vector3(pc.x - lc.x, 0, pc.z - lc.z).normalized()
	var st := lc + dir * (terrain.lake_r + 5.0)
	st.y = terrain.surface_h(st.x, st.z)
	# Высота, с которой удар снимет около трети прочности на этой гравитации.
	var v := ProtoHealth.SAFE_FALL_V + sqrt(health.max_hp * 0.3 * float(health.stats.get("flex", 1.0)) / ProtoHealth.FALL_K)
	var h := v * v / (2.0 * ProtoPlayer.G * style.gravity)
	robot.position = st + Vector3(0, h, 0)
	robot.rotation.y = atan2(-dir.x, -dir.z)
	pl.cam_yaw = robot.rotation.y
	pl.cam_pitch = 0.35
	pl.cam_dist = 5.5
	pl.air = true
	pl.vy = 0.0
	print("Прочность: корпус %s, %.0f ед, защита %s; падение с %.1f м" % [health.hull.name if health.hull else "—", health.max_hp, health.shield, h])

func _hurt_demo(dt: float) -> void:
	var pl := get_node("player") as ProtoPlayer
	hurt_t += dt
	var shot := ""
	match hurt_step:
		0:
			if not pl.air and health.hp < health.max_hp:
				hurt_mark = hurt_mark if hurt_mark >= 0.0 else hurt_t
				if hurt_t - hurt_mark > 0.15:
					shot = "удар"
					var lc := Vector3(terrain.lake_c.x, 0, terrain.lake_c.y)
					var to := (robot.position - lc) * Vector3(1, 0, 1)
					pl.route = [robot.position, lc + to.normalized() * terrain.lake_r * 0.45]
					pl.route_i = 1
					hurt_mark = -1.0
					if liquid_zones.is_empty():
						health.damage(health.hp + 1.0, "impact")
		1:
			if health.is_wrecked():
				hurt_step = 2        # жидкости нет — сразу к поломке
				hurt_mark = hurt_t
			elif health.liquid != null and health.dps > 0.5:
				hurt_mark = hurt_mark if hurt_mark >= 0.0 else hurt_t
				if hurt_t - hurt_mark > 1.0:
					shot = "в жидкости"
					hurt_mark = hurt_t
			elif pl.route_i >= pl.route.size() and health.liquid != null:
				# Безвредная жидкость: поломку показываем ударом.
				health.damage(health.hp + 1.0, "impact")
		2:
			if health.is_wrecked():
				if ProtoHealth.WRECK_TIME - health.wreck_t > 1.2:
					shot = "поломка"
			elif hurt_t - hurt_mark > 2.5:
				# Не доломался в жидкости (кислота медленная) — добить.
				health.damage(health.hp + 1.0, "impact")
		3:
			if health.is_wrecked():
				hurt_mark = -1.0
			else:
				hurt_mark = hurt_mark if hurt_mark >= 0.0 else hurt_t
				if hurt_t - hurt_mark > 1.6:
					shot = "на базе"
	if shot != "":
		hurt_step += 1
		var path := "%s_%d.png" % [hurt_prefix, hurt_step]
		get_viewport().get_texture().get_image().save_png(path)
		print("кадр прочности (%s): %s — прочность %.0f/%.0f" % [shot, path, health.hp, health.max_hp])
		if hurt_step >= 4:
			get_tree().quit(0)
	if hurt_t > 45.0:
		print("Прочность: время вышло на шаге ", hurt_step)
		get_tree().quit(1)

## HUD: груз робота, завод и стройка (когда они есть), подсказки кнопок.
func _hud() -> void:
	if demo_cargo:
		var cargo: Array = []
		var solids := _solid_mats()
		for i in mini(3, solids.size()):
			cargo.append(Portion.new(solids[i], 6.5 - i * 2.0, planet.ambient_temp))
		robot.set_meta("cargo", cargo)
	ProtoControls.ensure()
	hud = ProtoHud.new()
	hud.name = "hud"
	hud.setup(robot)
	if hud_pad:
		hud.pad = true
	if OS.has_feature("play3d"):
		# Выход — из меню рана (Esc / Menu, строка «Меню» в HUD).
		hud.extra_hints = [["Сохранить", "F5", "R3"]]
	hud.map = map_data
	add_child(hud)

## Обучение первых минут: в игре — пока не пройдено или не закрыто
## (ProtoTutorial помнит это в user://settings.json), --tutorial — заново.
func _tutorial() -> void:
	if tutorial_mode == "off" or hud == null:
		return
	var forced := tutorial_mode != ""
	if not forced and (not play or auto != "" or ProtoTutorial.is_done()):
		return
	if tutorial_mode == "0":
		ProtoTutorial.reset()
	tutorial = ProtoTutorial.new()
	tutorial.name = "tutorial"
	tutorial.setup(self, hud, int(tutorial_mode) if forced else -1)
	add_child(tutorial)

## Разведка материалов: карточка с пробами и догадками, анализатор, лента находок.
func _lab() -> void:
	lab_desk.robot = robot
	lab_desk.mining = mining
	if mining != null:
		mining.knowledge = lab_desk
		mining.hud = hud
	if not (play or auto != "" or show_hud or lab_demo):
		return
	lab_panel = ProtoLabPanel.new()
	lab_panel.name = "lab"
	add_child(lab_panel)
	lab_panel.setup(lab_desk, robot)
	lab_panel.builder = get_node_or_null("builder")
	if hud_pad:
		lab_panel.pad = true
	if hud != null:
		hud.knowledge = lab_desk
		if hud.radar != null:
			# Лента находок — слева от радара (справа под ним завод и подсказки).
			lab_panel._feed.offset_top = ProtoHud.PAD
			lab_panel._feed.offset_left -= ProtoRadar.D + 12.0
			lab_panel._feed.offset_right -= ProtoRadar.D + 12.0
	if lab_demo:
		_lab_demo.call_deferred()

## Кадр карточки: коснуться, одна проба и одна догадка — видно, как сужается поиск.
func _lab_demo() -> void:
	if not robot.has_meta("cargo") or (robot.get_meta("cargo") as Array).is_empty():
		var solids: Array = _solid_mats().duplicate()
		solids.sort_custom(func(a, b): return a.tags.size() > b.tags.size())
		var cargo: Array = []
		for i in mini(3, solids.size()):
			cargo.append(Portion.new(solids[i], 4.0, planet.ambient_temp))
		robot.set_meta("cargo", cargo)
	var w := lab_desk.world
	if view == "cave" and mining != null and lab_desk.druse_near() == null:
		# Кадр в пещере: робот встаёт вплотную к ближайшей друзе и смотрит на неё.
		var best: Node3D = null
		for c in mining.crystals():
			if best == null or c.global_position.distance_to(robot.global_position) < best.global_position.distance_to(robot.global_position):
				best = c
		if best != null:
			var d: Node3D = best.get_parent()
			var nrm: Vector3 = d.get_meta("normal", Vector3.UP)
			var flat := Vector3(nrm.x, 0, nrm.z)
			if flat.length() < 0.2:
				flat = (robot.global_position - best.global_position) * Vector3(1, 0, 1)
			var p := best.global_position + flat.normalized() * 1.5
			p.y = _floor_at(p + Vector3(0, 1.0, 0))
			robot.global_position = p
			robot.look_at(Vector3(best.global_position.x, p.y, best.global_position.z), Vector3.UP, true)
			var pl := get_node_or_null("player")
			if pl != null:
				pl.cam_yaw = robot.rotation.y + 0.5
	# Самое загадочное вещество — первым: так видно, как сужается поиск.
	var cg: Array = robot.get_meta("cargo")
	cg.sort_custom(func(a, b): return a.substance.tags.size() > b.substance.tags.size())
	if not lab_panel.touch_open():
		return
	var s: Substance = lab_panel.current()
	for pid in Probes.ORDER:
		if w.unknown_count(s) > 1 and lab_desk.probe_error(s, pid) == "" and Probes.PROBES[pid].tags.any(func(t): return t in s.tags) \
				and Probes.PROBES[pid].tags.filter(func(t): return t in s.tags).size() < w.unknown_count(s):
			lab_desk.probe(s, pid)
			break
	var pos: Array = w.possible_of(s)
	if not pos.is_empty():
		lab_desk.toggle_guess(s, pos[0])
	lab_panel._sig = ""

## Экран «Управление» (ProtoControlsMenu) сразу, для кадра (--menu); в игре он
## открывается из паузы: Настройки → Управление.
func _controls_menu() -> void:
	controls_menu = ProtoControlsMenu.new()
	controls_menu.name = "controls_menu"
	controls_menu.pause_tree = false   # без паузы, чтобы кадр снялся
	add_child(controls_menu)
	controls_menu.open()

func _process(dt: float) -> void:
	_t += dt
	_night_lights()
	_map_t -= dt
	if map_data != null and _map_t <= 0.0:
		_map_t = 0.5
		_map_mined()
	if hurt_prefix != "" and health != null:
		_hurt_demo(dt)
	if run != null:
		_run_visuals(dt)
	if lab_panel != null:
		# Подпись планеты — под карточкой материала; пока та открыта, прячем.
		var cap := get_node_or_null("caption") as CanvasLayer
		if cap:
			cap.visible = not lab_panel.open and run == null   # в ране слева сверху — цель
	if shot_path != "" and _t > 1.5 and not _shot_wait:
		var img := get_viewport().get_texture().get_image()
		img.save_png(shot_path)
		print("Кадров в секунду: ", Engine.get_frames_per_second(), " — скриншот: ", shot_path)
		shot_path = ""
		get_tree().quit(0)

## Ночью: прожектор над заводом; в кадре без игрока — и фара робота
## (играя, её включает ProtoPlayer).
func _night_lights() -> void:
	if daynight == null:
		return
	if yard_light != null:
		yard_light.light_energy = 2.2 * daynight.night
	if not (play or auto != "") and view != "cave" and robot != null:
		var lamp := robot.find_child("head_lamp", true, false) as SpotLight3D
		if lamp:
			lamp.light_energy = 3.2 * daynight.night
		var eye := robot.find_child("eye_light", true, false) as OmniLight3D
		if eye:
			eye.light_energy = 0.8 * daynight.night
			eye.omni_range = 5.0

# ---------------------------------------------------------------- карта

## Карта сверху: рельеф и цвет грунта (как у сетки), вода, пустоты под землёй
## и метки — завод, вход в пещеру, зал, друзы.
func _map_data() -> void:
	var t0 := Time.get_ticks_msec()
	map_data = ProtoMapData.new(Vector2.ZERO, Vector2(terrain.sx, terrain.sz))
	map_data.name = planet.name
	var liq := _liquid_mats()
	var river_c: Color = liq[0].color if not liq.is_empty() else Color(0, 0, 0, 0)
	var lake_c: Color = liq[1].color if liq.size() > 1 else river_c
	map_data.bake(func(x, z): return terrain.surface_h(x, z),
		func(x, z, h, n):
			var c: Color = terrain._color(Vector3(x, h, z), n)
			if river_c.a > 0.0:
				if Vector2(x, z).distance_to(terrain.lake_c) < terrain.lake_r + 4.5 and h < terrain.lake_level:
					c = lake_c.darkened(0.15)
				elif absf(z - terrain.river_z(x)) < 6.0 and x > terrain.lake_c.x + 2.0 and h < terrain.river_level_at(x):
					c = river_c.darkened(0.15)
			return c)
	map_data.bake_caves(func(x, z):
		var top := terrain.surface_h(x, z) - 2.5
		var y := 2.0
		while y < top:
			if not terrain.solid(x, y, z):
				return true
			y += 1.0
		return false)
	if pneu_view != null:
		map_data.add_marker("factory", pneu_view.origin)
	map_data.add_marker("cave", terrain.cave_entry)
	map_data.add_marker("hall", terrain.cave_c, "", true)
	if mining != null:
		for d in mining.druses:
			if d.crystals.is_empty() or d.node.has_meta("far_id"):
				continue
			var p := Vector3.ZERO
			for c in d.crystals:
				p += c.global_position / d.crystals.size()
			var m := map_data.add_marker("druse", p, "", p.y < terrain.surface_h(p.x, p.z) - 2.0)
			m.druse = d
	if planet_stream != null:
		# Весь шар: разведанное, радар вне участка, глобус на карте.
		map_data.globe = ProtoGlobe.new(planet_stream, planet_fill)
		map_data.globe.factory = pneu_view.origin if pneu_view != null else terrain.plateau()
		if play or map_demo != "":
			map_data.globe.prepare()
	print("Карта: %d мс, меток %d" % [Time.get_ticks_msec() - t0, map_data.markers.size()])

## Выбуренные друзы — серым.
func _map_mined() -> void:
	for m in map_data.markers:
		if m.kind == "druse" and m.has("druse"):
			var left: Array = m.druse.crystals.filter(func(c): return is_instance_valid(c) and not c.has_meta("broken"))
			if left.is_empty():
				m.kind = "mined"
				m.color = ProtoMapData.KINDS.mined[1]

## Полноэкранная 3D-карта (M / View). Узел — последним: кнопки сначала ей.
func _map_view() -> void:
	if not (play or map_demo != ""):
		return
	map_view = ProtoMapView.new()
	map_view.name = "map"
	add_child(map_view)
	map_view.setup(map_data, robot, _map_meshes, _map_caves, _map_water)
	map_view.cam_main = cam
	if hud_pad:
		map_view.pad = true
	if play:
		map_view.on_next_planet = _next_planet   # и из меню в редакторе, не только в сборке
	if map_demo != "":
		_map_demo.call_deferred()

## Кадр карты: разведан путь от робота к заводу, ко входу в пещеру и в зал.
func _map_demo() -> void:
	if map_demo == "globe" and map_data.globe != null:
		_globe_demo()
		return
	if map_demo == "all":
		map_data.reveal_all()
	else:
		var pts: Array = [robot.global_position, pneu_view.origin if pneu_view else robot.global_position, terrain.cave_entry]
		for i in pts.size() - 1:
			var a: Vector3 = pts[i]
			var b: Vector3 = pts[i + 1]
			for k in 21:
				var p := a.lerp(b, k / 20.0)
				map_data.reveal(Vector3(p.x, terrain.surface_h(p.x, p.z), p.z))
		var hall := terrain.cave_c
		for k in 21:
			var p := terrain.cave_entry.lerp(hall, k / 20.0) + Vector3(0, -1.5, 0)
			map_data.reveal(p, true)
		for k in 12:
			var an := TAU * k / 12.0
			map_data.reveal(hall + Vector3(cos(an), 0, sin(an)) * terrain.cave_r * 0.6, true)
	map_data.flush()
	map_view.show_map()

## --map=globe: робот прошёл по шару ~2 км петлёй от завода, по пути нашёл
## россыпи; карта открыта глобусом.
var _shot_wait := false           # кадр ждёт (глобус строится в потоке)

func _globe_demo() -> void:
	_shot_wait = true
	var g: ProtoGlobe = map_data.globe
	var t := terrain
	var pts: Array = []
	for k in 400:
		var a := (20.0 + k * 5.0) / t.radius
		var th := 0.4 + sin(k * 0.018) * 0.9
		var d := Vector3(sin(a) * cos(th), cos(a), sin(a) * sin(th)).normalized()
		pts.append(d)
		g.reveal(t.center + d * (t.radius + t.sphere_h(d)))
		if k % 25 == 12 and planet_fill != null:
			var key := planet_fill.key_of(d)
			planet_fill.record_find(key, planet_fill._arrays(key), true)
	g.flush()
	map_view.show_map()
	while not g.ready():
		await get_tree().process_frame
	var last: Vector3 = pts[-1]
	planet_stream.set_process(false)       # кадр: робот «там», шар не трогаем
	robot.set_meta("planet_pos", t.center + last * (t.radius + t.sphere_h(last)))
	map_view.set_globe(true)
	map_view._gdist = 175.0
	map_view._gpitch += 0.25
	await get_tree().create_timer(0.5).timeout
	_shot_wait = false

# ---------------------------------------------------------------- ран

## Ран: цель, награды, прокачка, события — логика общая с 2D (ProtoRun).
func _run() -> void:
	run = ProtoRun.new(planet, _solid_mats())
	if lab_desk != null:
		# Знания о веществах — у лаборатории (пробы, догадки): робот рана тот же,
		# теги сами от добычи не открываются.
		run.robot = lab_desk.world.robot
		run.auto_tags = false
	run.pneu_origin_v = pneu_origin
	var pc := terrain.plateau()
	run.attach(pneu, mining, robot, mining.sub if mining != null else null, Vector3(pc.x, pc.y, pc.z))
	run.robot_pos = robot.global_position
	if _caption_layer != null:
		_caption_layer.visible = false        # место слева сверху — панели цели
	run_ui = ProtoRunUi.new()
	run_ui.name = "run_ui"
	run_ui.setup(run, robot, hud)
	run_ui.on_new_planet = _next_planet
	run_ui.on_resume = _recapture
	if saves != null:
		run_ui.on_save = func() -> String: return ProtoSave.write(self)
	if play:
		run_ui.on_main_menu = _main_menu
	run_ui.pause_game = shot_path == ""          # для кадра сцена не должна вставать
	if play:
		run_ui.on_quit = _quit
	add_child(run_ui)
	_zone = MeshInstance3D.new()
	var ring := TorusMesh.new()
	ring.inner_radius = 0.94
	ring.outer_radius = 1.0
	ring.rings = 48
	ring.ring_segments = 4
	_zone.mesh = ring
	_zone.material_override = ProtoMachines.glow(Color(1.0, 0.25, 0.15), 1.5)
	_zone.visible = false
	add_child(_zone)
	if open_win != "":
		_open_for_shot()

## --open: окно или событие сразу — для кадров.
func _open_for_shot() -> void:
	run.briefing_seen = open_win != "briefing"
	match open_win:
		"choice":
			run.goals.stage = 1
		"reward":
			run.goals.reward_pending = Rewards.offer(run, 0)
		"event":
			run.start_event("meteors", robot.position + Vector3(1.5, 0, 1.0))
			run.ev.t = 0.01
			run.ev.strike = 0.3
		"skills":
			run.robot.knowledge = 5
			run.robot.xp.gatherer = 22.0
			run.robot.xp.crafter = 9.0
			run.learn("g1")
			run_ui.open.call_deferred("skills")
		"end":
			run.goals.completed = true
			run.mined = 42.0
			run.stats.hits = 21
		"menu", "settings":
			run_ui.open.call_deferred(open_win)

## «Новая планета» — выбор в главном меню (сид по умолчанию — новый случайный).
func _next_planet() -> void:
	if saves != null:
		saves.save_now(true)
	ProtoMainMenu.goto_picker(get_tree(), ProtoMainMenu.new_seed())

func _main_menu() -> void:
	if saves != null:
		saves.save_now(true)
	ProtoMainMenu.goto_menu(get_tree())

## После паузы — снова захватить мышь для камеры (если игрок это умеет).
func _recapture() -> void:
	var pl := get_node_or_null("player")
	if pl != null and pl.has_method("recapture"):
		pl.recapture()

func _quit() -> void:
	if saves != null:
		saves.save_now(true)
	get_tree().quit()

## Круг зоны события, удары метеоритов, дымка бури.
func _run_visuals(dt: float) -> void:
	var zoned: bool = not run.ev.is_empty() and float(run.ev.radius) > 0.0
	_zone.visible = zoned
	if zoned:
		var c: Vector3 = run.ev.center
		var r: float = run.ev.radius
		_zone.position = Vector3(c.x, terrain.floor_at(Vector3(c.x, terrain.sy, c.z)) + 0.15, c.z)
		_zone.scale = Vector3(r, 3.0, r)
		var pulse := 0.6 + 0.4 * sin(_t * (6.0 if run.ev.phase == "warn" else 3.0))
		(_zone.material_override as StandardMaterial3D).emission_energy_multiplier = 1.5 * pulse
	var at = run.ev.get("last_strike")
	if at != null and at != _strike_seen:
		_strike_seen = at
		_meteor(at)
	if env != null:
		if _fog_base < 0.0:
			_fog_base = env.fog_density
		var thick: bool = run.active_event() in ["storm", "acid", "spore_bloom", "flare"]
		env.fog_density = lerpf(env.fog_density, _fog_base * (2.5 if thick else 1.0), minf(1.0, dt))

## Метеорит: светящийся камень падает в точку и вспыхивает.
func _meteor(at: Vector3) -> void:
	var ground := Vector3(at.x, terrain.floor_at(Vector3(at.x, terrain.sy, at.z)), at.z)
	var rock := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.35
	sm.height = 0.7
	rock.mesh = sm
	rock.material_override = ProtoMachines.glow(Color(1.0, 0.5, 0.15), 4.0)
	add_child(rock)
	rock.position = ground + Vector3(6.0, 22.0, 3.0)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.55, 0.2)
	light.omni_range = 7.0
	light.light_energy = 0.0
	add_child(light)
	light.position = ground + Vector3(0, 1.0, 0)
	var tw := create_tween()
	tw.tween_property(rock, "position", ground, 0.55).set_ease(Tween.EASE_IN)
	tw.tween_callback(func(): light.light_energy = 6.0)
	tw.tween_property(light, "light_energy", 0.0, 0.7)
	tw.tween_callback(func():
		rock.queue_free()
		light.queue_free())
