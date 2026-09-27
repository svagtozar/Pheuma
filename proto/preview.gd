extends Node3D
## Предпросмотр объёмного 3D-визуала (к игре не подключён).
##   godot --path . res://proto/preview.tscn -- --seed=14 --view=third|plan|cave --screenshot=путь.png
##   --play — ходить самому (WASD, Shift, Q/E или мышь с ПКМ, колесо; F — бур,
##   G — выстрел кистью и подтягивание; геймпад — см. ProtoControls); --tool=drill — бур в правом предплечье
##   --auto=cave --screenshot=путь.png — маршрут в пещеру, кадры путь_1..4.png
##   --robot=clean (по умолчанию; другой вариант из RobotDesigns или old — прежний
##   каркас; корпус — металл планеты)
## Планета — настоящий генератор: теги задают небо, свет и дымку, жидкие при её
## температуре материалы — реки и озёра, твёрдые — корпуса машин.

var seed_value := 14
var view := "third"
var shot_path := ""
var planet: Planet
var terrain: ProtoTerrain
var robot: Node3D
var robot_design := "clean"
var cam: Camera3D
var _t := 0.0
var play := false            # --play: управление от третьего лица
var auto := ""               # --auto=cave: скриптовый маршрут с кадрами
var env: Environment

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seed="): seed_value = int(a.substr(7))
		elif a.begins_with("--view="): view = a.substr(7)
		elif a.begins_with("--screenshot="): shot_path = a.substr(13)
		elif a.begins_with("--robot="): robot_design = a.substr(8)
		elif a == "--play": play = true
		elif a.begins_with("--tool="): RobotDesigns.tool_r = a.substr(7)
		elif a.begins_with("--auto="): auto = a.substr(7)
	planet = PlanetGen.generate(seed_value)
	var t0 := Time.get_ticks_msec()
	terrain = ProtoTerrain.new(seed_value)
	_palette()
	terrain.build_field()
	# Основная сетка (1 м) без пещерной коробки и детальная сетка пещеры (0,5 м).
	var mesh := terrain.build_mesh(Vector3.ZERO, Vector3i(-1, -1, -1), 1.0, terrain.coarse_skip())
	var cmesh := terrain.build_cave_mesh()
	print("Рельеф %d×%d×%d: %d мс, вершин %d + пещера %d" % [terrain.sx, terrain.sy, terrain.sz, Time.get_ticks_msec() - t0,
		mesh.surface_get_array_len(0), cmesh.surface_get_array_len(0)])
	var tm := terrain.material()
	for m in [mesh, cmesh]:
		var ground := MeshInstance3D.new()
		ground.mesh = m
		ground.material_override = tm
		add_child(ground)
	_environment()
	_liquids()
	_cave_crystals()
	_factory()
	_robot_and_camera()
	_caption()
	if play or auto != "":
		var pl := ProtoPlayer.new()
		pl.name = "player"
		add_child(pl)
		pl.setup(robot, cam, terrain, env)
		if auto == "cave":
			pl.auto_cave(shot_path.get_basename() if shot_path != "" else "user://route")
			shot_path = ""

# ---------------------------------------------------------------- палитра и свет

func _palette() -> void:
	var c := Color(0.36, 0.31, 0.26)
	if planet.has_tag("volcanic"): c = Color(0.30, 0.20, 0.18)
	if planet.has_tag("frozen"): c = Color(0.62, 0.68, 0.74)
	if planet.has_tag("oceanic"): c = Color(0.25, 0.36, 0.30)
	if planet.has_tag("crystalline_crust"): c = c.lerp(Color(0.5, 0.55, 0.65), 0.35)
	if planet.has_tag("toxic_atmosphere"): c = c.lerp(Color(0.4, 0.45, 0.2), 0.25)
	if planet.has_tag("fungal_biosphere"): c = c.lerp(Color(0.42, 0.33, 0.4), 0.3)
	if planet.has_tag("anomalous_field"): c = c.lerp(Color(0.4, 0.3, 0.5), 0.3)
	terrain.ground = c
	terrain.cliff = c.darkened(0.25).lerp(Color(0.35, 0.33, 0.32), 0.3)
	terrain.outcrops = _solid_mats().slice(0, 5).map(func(m): return m.color)
	var vein = _mat_with("crystalline")
	terrain.vein = vein.color if vein != null else Color(0.5, 0.8, 1.0)

func _environment() -> void:
	var sky_top := Color(0.25, 0.42, 0.7)
	var horizon := Color(0.7, 0.72, 0.75)
	var sun_col := Color(1.0, 0.96, 0.9)
	var sun_pitch := -48.0
	if planet.has_tag("volcanic"):
		sky_top = Color(0.3, 0.2, 0.18); horizon = Color(0.7, 0.5, 0.38); sun_col = Color(1.0, 0.7, 0.5); sun_pitch = -22.0
	if planet.has_tag("frozen"):
		sky_top = Color(0.35, 0.5, 0.75); horizon = Color(0.85, 0.9, 0.97); sun_col = Color(0.9, 0.95, 1.0); sun_pitch = -30.0
	if planet.has_tag("toxic_atmosphere") or planet.has_tag("fungal_biosphere"):
		sky_top = sky_top.lerp(Color(0.35, 0.45, 0.2), 0.5); horizon = horizon.lerp(Color(0.65, 0.7, 0.4), 0.5)
	if planet.has_tag("thin_atmosphere"):
		sky_top = Color(0.03, 0.03, 0.06); horizon = Color(0.25, 0.25, 0.3)
	if planet.has_tag("tidally_locked"):
		sun_pitch = -8.0; sun_col = sun_col.lerp(Color(1.0, 0.55, 0.35), 0.5)
	var env := Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = sky_top
	sm.sky_horizon_color = horizon
	sm.ground_horizon_color = horizon.darkened(0.3)
	sm.ground_bottom_color = horizon.darkened(0.7)
	sm.sun_angle_max = 20.0
	sky.sky_material = sm
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.45
	env.ambient_light_sky_contribution = 0.5
	env.ambient_light_color = Color(0.55, 0.55, 0.58)
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = horizon.lerp(Color(0.6, 0.6, 0.62), 0.4)
	env.fog_density = 0.0015 + 0.0035 * clampf(planet.atm_pressure, 0.0, 3.0) + (0.006 if planet.has_tag("toxic_atmosphere") else 0.0)
	env.fog_sky_affect = 0.3
	if view == "cave":
		# Под землёй: тёмный плотный воздух — дальние стены уходят в темноту.
		env.fog_light_color = Color(0.04, 0.045, 0.055)
		env.fog_density = 0.06
	self.env = env
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.light_color = sun_col
	sun.light_energy = 1.35
	sun.shadow_enabled = true
	sun.rotation_degrees = Vector3(sun_pitch, -35.0, 0)
	add_child(sun)
	# Частицы в воздухе.
	var kind := ""
	if planet.has_tag("volcanic"): kind = "ash"
	elif planet.has_tag("frozen"): kind = "snow"
	elif planet.has_tag("fungal_biosphere"): kind = "spores"
	elif planet.has_tag("storms"): kind = "dust"
	if kind != "":
		var p := CPUParticles3D.new()
		p.amount = 400
		p.lifetime = 8.0
		p.preprocess = 8.0
		p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		p.emission_box_extents = Vector3(30, 8, 30)
		p.position = Vector3(46, 26, 36)
		p.direction = Vector3(0.3, -1, 0.1)
		p.gravity = Vector3(0.6, -0.4 if kind != "spores" else 0.05, 0.2)
		p.initial_velocity_min = 0.2
		p.initial_velocity_max = 0.8
		var q := QuadMesh.new()
		q.size = Vector2(0.07, 0.07) if kind != "spores" else Vector2(0.1, 0.1)
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		var g := GradientTexture2D.new()
		g.fill = GradientTexture2D.FILL_RADIAL
		g.fill_from = Vector2(0.5, 0.5)
		g.fill_to = Vector2(1.0, 0.5)
		var gr := Gradient.new()
		gr.set_color(0, Color(1, 1, 1, 1))
		gr.set_color(1, Color(1, 1, 1, 0))
		g.gradient = gr
		m.albedo_texture = g
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color = {"ash": Color(0.2, 0.18, 0.17, 0.8), "snow": Color(1, 1, 1, 0.9),
			"spores": Color(0.8, 1.0, 0.5, 0.8), "dust": Color(0.7, 0.6, 0.45, 0.6)}[kind]
		if kind == "spores":
			m.emission_enabled = true
			m.emission = Color(0.7, 1.0, 0.4)
		q.material = m
		p.mesh = q
		add_child(p)

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
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var rock := StandardMaterial3D.new()
	rock.albedo_color = terrain.cliff.lerp(terrain.ground, 0.3).darkened(0.1)
	rock.roughness = 0.95
	var glow := ProtoMachines.glow(col, 0.75)
	var cmat := ProtoCrystal.material(col)
	var cc: Vector3 = terrain.cave_c
	# Натёки: сталактиты со свода, сталагмиты с пола.
	var made := 0
	for i in 300:
		if made >= 18:
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
		if made >= 9:
			break
		# Друзы ниже середины стен и на полу — их видно в луче фары, они «стоят», а не висят.
		var dir := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.9, 0.15), rng.randf_range(-1, 1)).normalized()
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
		var cnt := rng.randi_range(5, 9)
		var main_len := rng.randf_range(0.7, 1.3)
		for m in cnt:
			var spread := 0.15 if m == 0 else rng.randf_range(0.25, 0.7)
			var tilt := (nrm + Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * spread).normalized()
			var len := main_len if m == 0 else main_len * rng.randf_range(0.25, 0.7)
			var r := len * rng.randf_range(0.11, 0.16)
			var ci := MeshInstance3D.new()
			ci.mesh = ProtoCrystal.mesh(len, r, rng)
			ci.material_override = cmat
			var y := tilt
			var ref := Vector3.UP if absf(y.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
			var x := y.cross(ref).normalized()
			var off := Vector3.ZERO if m == 0 else (x * cos(m * 2.4) + x.cross(y) * sin(m * 2.4)) * rng.randf_range(0.08, 0.28)
			ci.transform = Transform3D(Basis(x, y, x.cross(y)).rotated(y, rng.randf() * TAU), base + off - tilt * len * 0.12)
			add_child(ci)
		# Щётка: мелкие кристаллики вокруг подножия, почти вровень с породой.
		var fx := nrm.cross(Vector3.UP if absf(nrm.y) < 0.9 else Vector3.RIGHT).normalized()
		var fz := nrm.cross(fx)
		for m in rng.randi_range(8, 14):
			var a := rng.randf() * TAU
			var len := rng.randf_range(0.06, 0.2)
			var tilt := (nrm + Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * 0.8).normalized()
			var ci := MeshInstance3D.new()
			ci.mesh = ProtoCrystal.mesh(len, len * rng.randf_range(0.14, 0.22), rng)
			ci.material_override = cmat
			var y := tilt
			var x := y.cross(Vector3.UP if absf(y.y) < 0.9 else Vector3.RIGHT).normalized()
			var at := base + (fx * cos(a) + fz * sin(a)) * rng.randf_range(0.2, 0.5) - nrm * 0.03
			ci.transform = Transform3D(Basis(x, y, x.cross(y)), at)
			add_child(ci)
		if lights < 4:
			var l := OmniLight3D.new()
			l.light_color = col
			l.light_energy = 1.6
			l.omni_range = 6.0
			l.position = base + nrm * 0.7
			add_child(l)
			lights += 1
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

# ---------------------------------------------------------------- завод

func _mat_with(tag: String):
	for m in planet.materials:
		if m.has(tag) and m.phase_at(planet.ambient_temp) == Substance.Phase.SOLID:
			return m
	return null

func _solid_mats() -> Array:
	return planet.materials.filter(func(m): return m.phase_at(planet.ambient_temp) == Substance.Phase.SOLID)

func _factory() -> void:
	var solids := _solid_mats()
	var metal = _mat_with("metallic")
	var cryst = _mat_with("crystalline")
	var rough = _mat_with("porous")
	if rough == null: rough = _mat_with("fibrous")
	var a: Substance = metal if metal != null else World.starter_substance()
	var b: Substance = cryst if cryst != null else (solids[0] if not solids.is_empty() else a)
	var c: Substance = rough if rough != null else (solids[-1] if not solids.is_empty() else a)
	var pc := terrain.plateau()
	var top := pc.y + 0.1
	var base := Node3D.new()
	base.position = Vector3(pc.x, top, pc.z)
	add_child(base)
	var slab := ProtoMachines.slab(Vector3(13, 0.6, 9), terrain.ground.lerp(Color(0.5, 0.5, 0.52), 0.6))
	slab.position = Vector3(0, -0.28, 0)
	base.add_child(slab)
	var C := ProtoMachines.CELL
	var liq := _liquid_mats()
	var cargo: Color = liq[0].color if not liq.is_empty() else c.color
	var tank := ProtoMachines.tank(ProtoMachines.surface(a), cargo, 0.62)
	tank.position = Vector3(-C * 2, 0, -C * 0.5)
	base.add_child(tank)
	var fur := ProtoMachines.furnace(ProtoMachines.surface(c))
	fur.position = Vector3(-C * 0.5, 0, -C * 0.5)
	base.add_child(fur)
	var pump := ProtoMachines.pump(ProtoMachines.surface(a))
	pump.position = Vector3(-C * 2, 0, C * 1.2)
	base.add_child(pump)
	var gun := ProtoMachines.cannon(ProtoMachines.surface(b))
	gun.position = Vector3(C * 2.2, 0, C * 1.2)
	base.add_child(gun)
	var fr := ProtoMachines.frame(ProtoMachines.surface(a), 2.2)
	fr.position = Vector3(C * 1.2, 0, -C * 0.6)
	base.add_child(fr)
	var up := ProtoMachines.furnace(ProtoMachines.surface(b, false))   # неизученный материал — голограмма
	up.position = Vector3(C * 1.2, 2.26, -C * 0.6)
	up.scale = Vector3(0.8, 0.8, 0.8)
	base.add_child(up)
	var holo_tank := ProtoMachines.tank(ProtoMachines.surface(b), cargo.lerp(Color.WHITE, 0.3), 0.3)
	holo_tank.position = Vector3(C * 0.5, 0, C * 1.2)
	base.add_child(holo_tank)
	var pm := ProtoMachines.surface(a)
	var bp := base.position
	ProtoMachines.pipe(self, bp + Vector3(-C * 2, 0.4, C * 1.0), bp + Vector3(-C * 2, 0.4, -C * 0.1), pm)
	ProtoMachines.pipe(self, bp + Vector3(-C * 1.6, 0.4, C * 1.2), bp + Vector3(C * 1.8, 0.4, C * 1.2), pm, 5)
	ProtoMachines.pipe(self, bp + Vector3(C * 0.5, 0.4, C * 0.6), bp + Vector3(C * 0.5, 2.6, C * 0.6), pm, 3)
	ProtoMachines.pipe(self, bp + Vector3(C * 0.5, 2.6, C * 0.6), bp + Vector3(C * 1.2, 2.6, -C * 0.2), pm, 2)
	print("Материалы машин: %s | %s | %s (голограмма — неизученный)" % [_label(a), _label(b), _label(c)])

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
	add_child(layer)
	var l := Label.new()
	l.position = Vector2(16, 12)
	l.add_theme_font_size_override("font_size", 16)
	l.add_theme_color_override("font_color", Color(1, 1, 1))
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	l.add_theme_constant_override("outline_size", 5)
	var liq := _liquid_mats().map(func(m): return "%s %s" % [m.name, ", ".join(PackedStringArray(m.tags.map(func(t): return MaterialTags.display(t))))])
	l.text = "%s (seed %d) — %s\n%.0f °C, %.2f атм, вид: %s\nЖидкости: %s" % [planet.name, seed_value,
		", ".join(PackedStringArray(planet.tags.map(func(t): return PlanetTags.display(t)))), planet.ambient_temp, planet.atm_pressure, view,
		"; ".join(PackedStringArray(liq)) if not liq.is_empty() else "нет"]
	layer.add_child(l)

func _process(dt: float) -> void:
	_t += dt
	if shot_path != "" and _t > 1.5:
		var img := get_viewport().get_texture().get_image()
		img.save_png(shot_path)
		print("Кадров в секунду: ", Engine.get_frames_per_second(), " — скриншот: ", shot_path)
		shot_path = ""
		get_tree().quit(0)
