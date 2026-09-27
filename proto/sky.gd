class_name ProtoSky
extends RefCounted
## Облик планеты по её тегам: цвета породы, небо, солнце, дымка и частицы в
## воздухе. Общий для предпросмотра (proto/preview.gd) и 3D-вида игры.

## Цвета породы рельефа: грунт, обрыв, пятна выходов материалов, жила.
static func palette(planet: Planet, terrain: ProtoTerrain) -> void:
	var c := ground_color(planet)
	terrain.ground = c
	terrain.cliff = c.darkened(0.25).lerp(Color(0.35, 0.33, 0.32), 0.3)
	terrain.outcrops = solid_mats(planet).slice(0, 5).map(func(m): return m.color)
	var vein = mat_with(planet, "crystalline")
	terrain.vein = vein.color if vein != null else Color(0.5, 0.8, 1.0)

## Цвет грунта по тегам (рельеф, диск планеты в меню).
static func ground_color(planet: Planet) -> Color:
	var c := Color(0.36, 0.31, 0.26)
	if planet.has_tag("volcanic"): c = Color(0.30, 0.20, 0.18)
	if planet.has_tag("frozen"): c = Color(0.62, 0.68, 0.74)
	if planet.has_tag("oceanic"): c = Color(0.25, 0.36, 0.30)
	if planet.has_tag("crystalline_crust"): c = c.lerp(Color(0.5, 0.55, 0.65), 0.35)
	if planet.has_tag("toxic_atmosphere"): c = c.lerp(Color(0.4, 0.45, 0.2), 0.25)
	if planet.has_tag("fungal_biosphere"): c = c.lerp(Color(0.42, 0.33, 0.4), 0.3)
	if planet.has_tag("anomalous_field"): c = c.lerp(Color(0.4, 0.3, 0.5), 0.3)
	return c

## Твёрдые при температуре планеты материалы.
static func solid_mats(planet: Planet) -> Array:
	return planet.materials.filter(func(m): return m.phase_at(planet.ambient_temp) == Substance.Phase.SOLID)

## Первый твёрдый материал с тегом (или null).
static func mat_with(planet: Planet, tag: String):
	for m in planet.materials:
		if m.has(tag) and m.phase_at(planet.ambient_temp) == Substance.Phase.SOLID:
			return m
	return null

## Небо, солнце, дымка и частицы в parent. cave — тёмный плотный воздух подземелья.
## Возвращает {"env": Environment, "world_env": WorldEnvironment, "sun": DirectionalLight3D,
## "particles": CPUParticles3D или null}.
static func build(planet: Planet, parent: Node, cave := false) -> Dictionary:
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
	if cave:
		# Под землёй: тёмный плотный воздух — дальние стены уходят в темноту.
		env.fog_light_color = Color(0.04, 0.045, 0.055)
		env.fog_density = 0.06
	var we := WorldEnvironment.new()
	we.environment = env
	parent.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.light_color = sun_col
	sun.light_energy = 1.35
	sun.shadow_enabled = true
	sun.rotation_degrees = Vector3(sun_pitch, -35.0, 0)
	parent.add_child(sun)
	var p := _particles(planet)
	if p != null:
		parent.add_child(p)
	return {"env": env, "world_env": we, "sun": sun, "particles": p}

## Частицы в воздухе: пепел, снег, споры или пыль — по тегам.
static func _particles(planet: Planet) -> CPUParticles3D:
	var kind := ""
	if planet.has_tag("volcanic"): kind = "ash"
	elif planet.has_tag("frozen"): kind = "snow"
	elif planet.has_tag("fungal_biosphere"): kind = "spores"
	elif planet.has_tag("storms"): kind = "dust"
	if kind == "":
		return null
	var p := CPUParticles3D.new()
	p.amount = 400
	p.lifetime = 8.0
	p.preprocess = 8.0
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(30, 8, 30)
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
	return p
