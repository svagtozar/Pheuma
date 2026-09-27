extends Node3D
## Предпросмотр объёмного 3D-визуала (к игре не подключён).
##   godot --path . res://proto/preview.tscn -- --seed=14 --view=third|plan|cave|overview --screenshot=путь.png
##   --play — ходить самому (WASD, Shift, Q/E или мышь с ПКМ, колесо; F — бур,
##   G — выстрел кистью и подтягивание; геймпад — см. ProtoControls); --tool=drill — бур в правом предплечье
##   --auto=cave --screenshot=путь.png — маршрут в пещеру, кадры путь_1..4.png
##   --auto=drill --screenshot=путь.png — подойти к друзе и выбурить её (ProtoMining),
##   кадры путь_1..4.png; в --play бур по действию tool_work (F / правый курок)
##   --view=factory — пневмозавод крупно; --build — режим стройки (призрак детали)
##   В --play: B — стройка, T — деталь, R — повернуть, Пробел — поставить,
##   X — разобрать, C — выгрузить груз в приёмник (подробно — ProtoBuilder)
##   --auto=sound — тот же маршрут без кадров, в конце бур у стены и выстрел кистью
##   (для проверки звука); --record=путь.wav — записать звук, --mute — без звука
##   --hud — HUD (груз, завод, стройка, кнопки; в --play он есть всегда), --pad —
##   подсказки для геймпада, --cargo — положить роботу образцы груза (для кадра)
##   В --play игра сохраняется (ProtoSave): сама раз в минуту и при выходе, F5 / R3 —
##   сейчас, F9 — вернуться к сохранённому; --fresh — начать планету заново
##   Разведка материалов (ProtoLabDesk, ProtoLabPanel): Z / A — коснуться друзы, машины
##   или груза и открыть карточку (пробы, догадки), V / RB — анализатор; в линии
##   завода — лаборатория. --lab — открыть карточку сразу (для кадра)
##   Карта (ProtoMapData): радар в углу HUD и полноэкранная 3D-карта (ProtoMapView) —
##   M / View; туман над неразведанным, пещеры рентгеном. --map — открыть карту
##   сразу (для кадра; разведан путь от завода к пещере), --map=all — всё разведано
##   --robot=clean (по умолчанию; другой вариант из RobotDesigns или old — прежний
##   каркас; корпус — металл планеты)
## Сборка для проверки (фича play3d в export_presets.cfg) стартует прямо сюда,
## сразу с управлением: Tab (или Y в карте) — другая планета, Start или Esc — выход.
## Планета — настоящий генератор: теги задают небо, свет и дымку, жидкие при её
## температуре материалы — реки и озёра, твёрдые — корпуса машин. Форма рельефа,
## тип пещеры, облик кристаллов и гравитация — по тегам (ProtoWorldStyle).

var seed_value := 14
var view := "third"
var shot_path := ""
var planet: Planet
var terrain: ProtoTerrain
var style: ProtoWorldStyle
var robot: Node3D
var robot_design := "clean"
var cam: Camera3D
var _t := 0.0
var play := false            # --play: управление от третьего лица
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
var build := false           # --build: режим стройки (с --play или для кадра)
var fresh := false           # --fresh: не загружать сохранение
var saves: ProtoSave
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

## Сид следующей планеты в сборке для проверки (переживает перезагрузку сцены).
static var build_seed := 14
static var _booted := false

func _ready() -> void:
	if OS.has_feature("play3d"):
		play = true
		if not _booted:
			# Первый запуск сборки — с планеты, где играли в прошлый раз.
			_booted = true
			var last := ProtoSave.last_seed()
			if last >= 0:
				build_seed = last
		seed_value = build_seed
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seed="): seed_value = int(a.substr(7))
		elif a.begins_with("--view="): view = a.substr(7)
		elif a.begins_with("--screenshot="): shot_path = a.substr(13)
		elif a.begins_with("--robot="): robot_design = a.substr(8)
		elif a == "--play": play = true
		elif a.begins_with("--tool="): RobotDesigns.tool_r = a.substr(7)
		elif a.begins_with("--auto="): auto = a.substr(7)
		elif a.begins_with("--drill-hard="): drill_hard = float(a.substr(13))
		elif a.begins_with("--record="): record = a.substr(9)
		elif a == "--mute": mute = true
		elif a == "--hud": show_hud = true
		elif a == "--pad": hud_pad = true
		elif a == "--cargo": demo_cargo = true
		elif a == "--build": build = true
		elif a == "--fresh": fresh = true
		elif a == "--lab": lab_demo = true
		elif a == "--map": map_demo = "route"
		elif a.begins_with("--map="): map_demo = a.substr(6)
	if auto == "drill":
		RobotDesigns.tool_r = "drill"
		view = "cave"
	if auto == "sound" and RobotDesigns.tool_r == "":
		RobotDesigns.tool_r = "drill"
	planet = PlanetGen.generate(seed_value)
	lab_desk = ProtoLabDesk.new(ProtoLabDesk.for_planet(planet))
	var t0 := Time.get_ticks_msec()
	style = ProtoWorldStyle.for_planet(planet)
	terrain = ProtoTerrain.new(seed_value, style)
	print("Облик планеты: ", style.summary())
	_palette()
	terrain.build_field()
	# Основная сетка (1 м) без пещерной коробки и детальная сетка пещеры (0,5 м).
	var mesh := terrain.build_mesh(Vector3.ZERO, Vector3i(-1, -1, -1), 1.0, terrain.coarse_skip())
	var cmesh := terrain.build_cave_mesh()
	print("Рельеф %d×%d×%d: %d мс, вершин %d + пещера %d" % [terrain.sx, terrain.sy, terrain.sz, Time.get_ticks_msec() - t0,
		mesh.surface_get_array_len(0), cmesh.surface_get_array_len(0)])
	var tm := terrain.material()
	_map_meshes = [mesh, cmesh]
	_map_caves = [cmesh]
	for m in [mesh, cmesh]:
		var ground := MeshInstance3D.new()
		ground.mesh = m
		ground.material_override = tm
		add_child(ground)
	_environment()
	_liquids()
	_cave_crystals()
	_surface_features()
	_factory()
	_robot_and_camera()
	_caption()
	_map_data()
	if play or auto != "":
		var pl := ProtoPlayer.new()
		pl.name = "player"
		add_child(pl)
		pl.setup(robot, cam, terrain, env)
		pl.mining = mining
		if auto == "drill":
			pl.auto_drill(shot_path.get_basename() if shot_path != "" else "user://drill")
			shot_path = ""
		elif auto == "cave":
			pl.auto_cave(shot_path.get_basename() if shot_path != "" else "user://route")
			shot_path = ""
		elif auto == "sound":
			pl.auto_sound()
		if not mute:
			var snd := ProtoSound.new()
			snd.name = "sound"
			snd.record_path = record
			snd.setup(robot, terrain, pl, planet)
			add_child(snd)
	if play or build:
		_builder()
	if play or auto != "" or show_hud:
		_hud()
	_lab()
	_map_view()
	if play and auto == "":
		saves = ProtoSave.new()
		saves.name = "saves"
		add_child(saves)
		saves.setup(self, fresh)

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
	# Плотность дымки и ветер — по тегам (ProtoWorldStyle); под землёй не трогаем.
	if view != "cave":
		env.fog_density *= style.fog_mult
	if sky.particles != null:
		sky.particles.position = Vector3(46, 26, 36)
		var g: Vector3 = sky.particles.gravity
		sky.particles.gravity = Vector3(g.x + style.wind * 3.0, g.y * style.gravity, g.z + style.wind)

# ---------------------------------------------------------------- жидкости

func _liquid_mats() -> Array:
	return planet.materials.filter(func(m): return m.phase_at(planet.ambient_temp) == Substance.Phase.LIQUID)

func _liquids() -> void:
	var liq := _liquid_mats()
	if liq.is_empty():
		print("Жидких материалов нет — русла сухие")
		return
	var river_mat: Substance = liq[0]
	var lake_mat: Substance = liq[1] if liq.size() > 1 else liq[0]
	var cave_mat: Substance = liq[-1]
	var rv := MeshInstance3D.new()
	rv.mesh = ProtoLiquids.sloped_mesh(terrain, func(x, z): return terrain.river_level_at(x, z),
		func(x, z): return abs(z - terrain.river_z(x)) < 6.0 and x > terrain.lake_c.x + 2.0)
	rv.material_override = ProtoLiquids.material(river_mat, planet.ambient_temp)
	add_child(rv)
	_map_water.append([rv.mesh, river_mat.color])
	var rl := ProtoLiquids.look(river_mat, planet.ambient_temp)
	if rl.vapor or rl.haze:
		add_child(ProtoLiquids.vapor(Vector3(40, terrain.river_level_at(40) + 0.8, 58), Vector3(38, 0.5, 5), river_mat.color, rl.haze))
	_liquid_surface(lake_mat, terrain.lake_level, func(x, z): return Vector2(x, z).distance_to(terrain.lake_c) < terrain.lake_r + 4.5,
		Vector3(terrain.lake_c.x, terrain.lake_level + 0.8, terrain.lake_c.y), Vector3(10, 0.5, 10))
	var pc: Vector3 = terrain.pool_c()
	var lv: float = terrain.pool_level()
	_liquid_surface(cave_mat, lv, func(x, z): return Vector2(x, z).distance_to(Vector2(pc.x, pc.z)) < terrain.pool_r + 1.0,
		Vector3(pc.x, lv + 0.6, pc.z), Vector3(2.5, 0.3, 2.5))

func _liquid_surface(s: Substance, level: float, area: Callable, vpos: Vector3, vext: Vector3) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = ProtoLiquids.surface_mesh(terrain, level, area)
	mi.material_override = ProtoLiquids.material(s, planet.ambient_temp)
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
	# Натёки: сталактиты со свода, сталагмиты с пола.
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
		var mi := MeshInstance3D.new()
		mi.mesh = c
		mi.material_override = rock
		mi.position = p + Vector3(0, -len / 2.0 + 0.1 if down else len / 2.0 - 0.1, 0)
		add_child(mi)
		made += 1
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
		for m in rng.randi_range(8, 14):
			var a := rng.randf() * TAU
			var len := rng.randf_range(0.06, 0.2)
			var tilt := (nrm + Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * 0.8).normalized()
			var ci := MeshInstance3D.new()
			ci.mesh = ProtoCrystal.mesh(len, len * rng.randf_range(0.14, 0.22), rng, style.habit)
			ci.material_override = cmat
			var y := tilt
			var x := y.cross(Vector3.UP if absf(y.y) < 0.9 else Vector3.RIGHT).normalized()
			var at := base + (fx * cos(a) + fz * sin(a)) * rng.randf_range(0.2, 0.5) - nrm * 0.03
			ci.transform = Transform3D(Basis(x, y, x.cross(y)), at)
			druse.add_child(ci)
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

## Друза: главный кристалл и поросль вокруг, веером от поверхности.
func _druze(base: Vector3, nrm: Vector3, main_len: float, cmat: Material, rng: RandomNumberGenerator) -> void:
	for m in rng.randi_range(4, 8):
		var spread := 0.15 if m == 0 else rng.randf_range(0.25, 0.7)
		var y := (nrm + Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * spread).normalized()
		var len := main_len if m == 0 else main_len * rng.randf_range(0.25, 0.7)
		var ci := MeshInstance3D.new()
		ci.mesh = ProtoCrystal.mesh(len, len * rng.randf_range(0.11, 0.16), rng, style.habit)
		ci.material_override = cmat
		var x := y.cross(Vector3.UP if absf(y.y) < 0.9 else Vector3.RIGHT).normalized()
		var off := Vector3.ZERO if m == 0 else (x * cos(m * 2.4) + x.cross(y) * sin(m * 2.4)) * rng.randf_range(0.1, 0.35)
		ci.transform = Transform3D(Basis(x, y, x.cross(y)).rotated(y, rng.randf() * TAU), base + off - y * len * 0.12)
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
## дробилка → печь → бак, насос сбоку (ProtoPneumatics). Корпуса — из металла
## планеты; к моменту кадра завод уже работает.
func _factory() -> void:
	var metal = _mat_with("metallic")
	var cryst = _mat_with("crystalline")
	var a: Substance = metal if metal != null else World.starter_substance()
	var ore: Substance = cryst if cryst != null else (_solid_mats()[0] if not _solid_mats().is_empty() else a)
	var pc := terrain.plateau()
	var top := pc.y + 0.1
	var slab := ProtoMachines.slab(Vector3(15, 0.6, 9), terrain.ground.lerp(Color(0.5, 0.5, 0.52), 0.6))
	slab.position = Vector3(pc.x, top - 0.28, pc.z)
	add_child(slab)
	pneu = ProtoPneumatics.new(planet)
	pneu.build_demo(Vector2i(-3, 0), a)
	# Вторая труба линии — лаборатория: груз из приёмника проходит пробы.
	pneu.remove(Vector2i(-1, 0))
	pneu.place("lab", Vector2i(-1, 0), 0, a)
	pneu.feed(Vector2i(-3, 0), Portion.new(ore, 30.0, planet.ambient_temp))
	pneu_view = ProtoPneumaticsView.new()
	pneu_view.name = "pneumatics"
	add_child(pneu_view)
	pneu_view.setup(pneu, Vector3(pc.x, top, pc.z - 1.0))
	pneu_view.warm(9.0)
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
		RobotAnim.default_mode = "idle" if view == "cave" else "walk"
		robot = RobotDesigns.build(robot_design, drill.color if drill != null else Color(0, 0, 0, 0))
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
		"plan":
			robot.position = Vector3(pc.x - 1.0, top, pc.z + 5.0)
			robot.rotation.y = PI
			cam.position = Vector3(pc.x - 4.0, top + 16.0, pc.z + 14.0)
			cam.look_at(Vector3(pc.x - 1.0, top, pc.z - 1.0))
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
		_:
			var rp := Vector3(pc.x + 5.0, 0, pc.z + 4.0)
			rp.y = terrain.surface_h(rp.x, rp.z)
			robot.position = rp
			var tgt := Vector3(pc.x - 4.0, rp.y, pc.z - 3.0)
			robot.look_at(tgt, Vector3.UP, true)
			var fwd := (tgt - rp).normalized()
			var right := fwd.cross(Vector3.UP).normalized()
			cam.position = rp - fwd * 4.2 + right * 1.3 + Vector3(0, 2.6, 0)
			cam.look_at(rp + fwd * 12.0 + Vector3(0, 0.2, 0))
	cam.current = true

## Стройка роботом: призрак детали перед ним, HUD, выгрузка груза в приёмник.
func _builder() -> void:
	if pneu_view == null:
		return
	var b := ProtoBuilder.new()
	b.name = "builder"
	add_child(b)
	b.setup(pneu_view, robot, _solid_mats())
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
	l.text = "%s (seed %d) — %s\n%.0f °C, %.2f атм, %.1f g, вид: %s\n%s\nЖидкости: %s" % [planet.name, seed_value,
		", ".join(PackedStringArray(planet.tags.map(func(t): return PlanetTags.display(t)))), planet.ambient_temp, planet.atm_pressure, planet.gravity, view, style.summary(),
		"; ".join(PackedStringArray(liq)) if not liq.is_empty() else "нет"]
	layer.add_child(l)

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
		hud.extra_hints = [["Сохранить", "F5", "R3"], ["Другая планета", "Tab", "View Y"], ["Выход", "Esc", "Menu"]]
	hud.map = map_data
	add_child(hud)

## Разведка материалов: карточка с пробами и догадками, анализатор, лента находок.
func _lab() -> void:
	lab_desk.robot = robot
	lab_desk.mining = mining
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
			lab_panel._feed.offset_top += ProtoRadar.D + 10.0   # лента находок — под радаром и заводом
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

## Сборка для проверки: другая планета и выход с геймпада или клавиатуры.
func _unhandled_input(e: InputEvent) -> void:
	if not OS.has_feature("play3d") or not e.is_pressed() or e.is_echo():
		return
	# View на геймпаде — карта; из неё Y — другая планета (ProtoMapView.on_next_planet).
	var next: bool = e is InputEventKey and e.physical_keycode == KEY_TAB
	var quit: bool = (e is InputEventJoypadButton and e.button_index == JOY_BUTTON_START) \
		or (e is InputEventKey and e.physical_keycode == KEY_ESCAPE)
	if quit and saves != null:
		saves.save_now(true)
	if next:
		_next_planet()
	elif quit:
		get_tree().quit()

func _next_planet() -> void:
	if saves != null:
		saves.save_now(true)
	build_seed = seed_value + 1
	get_tree().reload_current_scene()

func _process(dt: float) -> void:
	_t += dt
	_map_t -= dt
	if map_data != null and _map_t <= 0.0:
		_map_t = 0.5
		_map_mined()
	if lab_panel != null:
		# Подпись планеты — под карточкой материала; пока та открыта, прячем.
		var cap := get_node_or_null("caption") as CanvasLayer
		if cap:
			cap.visible = not lab_panel.open
	if shot_path != "" and _t > 1.5:
		var img := get_viewport().get_texture().get_image()
		img.save_png(shot_path)
		print("Кадров в секунду: ", Engine.get_frames_per_second(), " — скриншот: ", shot_path)
		shot_path = ""
		get_tree().quit(0)

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
			if d.crystals.is_empty():
				continue
			var p := Vector3.ZERO
			for c in d.crystals:
				p += c.global_position / d.crystals.size()
			var m := map_data.add_marker("druse", p, "", p.y < terrain.surface_h(p.x, p.z) - 2.0)
			m.druse = d
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
	if OS.has_feature("play3d"):
		map_view.on_next_planet = _next_planet
	if map_demo != "":
		_map_demo.call_deferred()

## Кадр карты: разведан путь от робота к заводу, ко входу в пещеру и в зал.
func _map_demo() -> void:
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
