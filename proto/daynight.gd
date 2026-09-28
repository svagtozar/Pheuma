class_name ProtoDayNight
extends Node
## Смена дня и ночи и небо планеты (шейдер proto/sky.gdshader).
## Всё — по тегам и сиду планеты:
##   звезда — красный карлик, жёлтая или бело-голубая (цвет и размер диска),
##   иногда двойная; длина суток — 6–12 минут, ночь идёт вдвое быстрее дня;
##   приливный захват — солнце навсегда у горизонта (вечные сумерки);
##   разреженная атмосфера — чёрное небо и звёзды даже днём, плотная — мутное
##   небо, широкий ореол, звёзд почти не видно; луны (0–2) с фазами, кольца
##   (ringed) с тенью планеты, облака (бури — сплошные), полярное сияние
##   (радиация, магнитосфера), чёрная дыра (singularity), зарево лавы ночью.
## Узел двигает время, солнце (ночью тот же свет — от луны или звёзд,
## голубоватый и тусклый: одна лампа с тенью, как было), рассеянный свет и цвет
## дымки. Ночью играбельно: рассеянный свет не гаснет до нуля, у робота
## включается фара (ProtoPlayer, WorldView3D), у завода — прожектор.
##
## time: 0 — полночь, 0.25 — рассвет, 0.5 — полдень, 0.75 — закат.
##
## Все направления (солнце, луны, кольца, ось неба) считаются в местной системе
## наблюдателя: Y — местный верх. frame переводит её в мир: на плоском куске
## это единичный базис, на круглой планете — базис точки, где стоит робот
## (верх — от центра планеты); его можно менять каждый кадр.

const NIGHT_SPEED := 2.0           # ночь проходит вдвое быстрее дня
const UPDATE_SKY := 0.1            # с; параметры неба обновляются не каждый кадр
const NIGHT_AMBIENT := Color(0.32, 0.38, 0.55)

var planet: Planet
var env: Environment
var sun: DirectionalLight3D
var mat: ShaderMaterial
var cave := false                  # вид «пещера»: дымку не трогаем
var frame := Basis()               # местная система (Y — верх) → мир
## Поворот планеты → местная система наблюдателя. Солнце, луны и звёзды стоят
## над планетой, а робот ходит по шару: где он стоит, там и своё время суток
## (ProtoPlanetStream ставит turn каждый кадр; у завода — единичный).
var turn := Basis()
var running := true
var time := 0.34                   # утро
var day_len := 480.0               # реальных секунд на сутки (без ускорения ночи)
var locked := false                # приливный захват: время стоит

# Облик — из for_planet.
var star := "yellow"
var sun_col := Color(1, 0.96, 0.9)
var sun_size := 0.03
var binary := false
var noon_dir := Vector3(0, 0.7, 0.7)   # где солнце в полдень
var east := Vector3(1, 0, 0)
var pole := Vector3(0, 1, 0)           # ось вращения неба (звёзды)
var day_top := Color()
var day_hor := Color()
var night_top := Color()
var night_hor := Color()
var sunset := Color(1.0, 0.5, 0.25)
var haze := 1.0
var thin := false
var stars := 0.7
var clouds := 0.3
var wind := Vector2(0.004, 0.0015)
var aurora := 0.0
var aurora_col := Color(0.3, 1.0, 0.55)
var moons: Array = []              # {axis, phase, period, size, col}
var rings := false
var hole := false
var low_glow := Color(0, 0, 0)
var fog_day := Color()
var ambient_day := Color()
var sun_energy := 1.35

# Состояние (читают игрок и вид игры).
var day := 1.0                     # 0 — ночь, 1 — день
var night := 0.0                   # 1 — темно: пора фару
var fog_color := Color()
var _sky_t := 0.0
var _cloud := Vector2.ZERO

## Узел смены дня и ночи в сцене (или null).
static func of(n: Node) -> ProtoDayNight:
	if n == null or not n.is_inside_tree():
		return null
	return n.get_tree().get_first_node_in_group("daynight") as ProtoDayNight

## Облик неба планеты. top/hor — дневные цвета неба, col — цвет солнца
## сквозь атмосферу, pitch/yaw — солнце в полдень (как прежнее неподвижное).
func setup(p: Planet, top: Color, hor: Color, col: Color, pitch: float, yaw: float) -> void:
	planet = p
	add_to_group("daynight")
	var r := Rng.new(p.seed_value).fork("daynight")
	var press := clampf(p.atm_pressure, 0.25, 3.0)
	thin = p.has_tag("thin_atmosphere")
	locked = p.has_tag("tidally_locked")
	day_len = r.range_f(360.0, 720.0)
	# Звезда: у приливно захваченных — почти всегда красный карлик рядом.
	var kinds := {"red": 0.3, "yellow": 0.45, "white": 0.25}
	if locked:
		kinds = {"red": 0.8, "yellow": 0.2, "white": 0.0}
	star = r.weighted_pick(kinds.keys(), kinds)
	var tint: Color = {"red": Color(1.0, 0.6, 0.4), "yellow": Color(1.0, 0.95, 0.86), "white": Color(0.86, 0.92, 1.0)}[star]
	sun_size = {"red": 0.055, "yellow": 0.03, "white": 0.02}[star] * r.range_f(0.8, 1.25)
	sun_col = Color(col.r * tint.r, col.g * tint.g, col.b * tint.b).lerp(tint, 0.3)
	binary = r.chance(0.15) and not locked
	# Путь солнца: полдень — прежнее положение (pitch/yaw), восход — на 90° левее.
	var el := deg_to_rad(clampf(-pitch, 15.0, 75.0))
	var az := deg_to_rad(yaw)
	var flat := Vector3(sin(az), 0, cos(az))   # к солнцу по горизонтали (как rotation_degrees прежде)
	noon_dir = (flat * cos(el) + Vector3.UP * sin(el)).normalized()
	east = Vector3.UP.cross(flat).normalized()
	pole = east.cross(noon_dir).normalized()   # ось неба: солнце крутится вокруг неё
	if locked:
		running = false
		time = 0.25 + r.range_f(0.02, 0.04)    # солнце низко над горизонтом
	# Небо днём и ночью.
	day_top = top
	day_hor = hor
	haze = clampf(0.6 + press * 0.45, 0.6, 2.0)
	if thin:
		day_top = Color(0.015, 0.015, 0.03)
		day_hor = hor.darkened(0.55).lerp(Color(0.25, 0.25, 0.3), 0.5)
		haze = 0.35
	night_top = Color(0.008, 0.011, 0.028).lerp(top * 0.05, 0.3)
	night_hor = Color(0.03, 0.037, 0.065).lerp(hor * 0.08, 0.5)
	# Закат: оранжевый; в густом воздухе — красный, в пыльно-янтарном небе —
	# голубой (как на Марсе), в ядовитом — жёлто-зелёный.
	sunset = Color(1.0, 0.48, 0.22)
	if press > 2.0: sunset = Color(0.95, 0.28, 0.15)
	if top.r > top.b + 0.1: sunset = Color(0.45, 0.62, 1.0)
	if p.has_tag("toxic_atmosphere") or p.has_tag("fungal_biosphere"): sunset = Color(0.85, 0.75, 0.25)
	if thin: sunset = sunset.lerp(hor, 0.5) * 0.5
	# Звёзды: в разреженном воздухе — ярко, в густом и мутном — едва.
	stars = 1.0 if thin else clampf(1.0 - (press - 1.0) * 0.3, 0.3, 0.8)
	if p.has_tag("toxic_atmosphere") or p.has_tag("storms"): stars *= 0.6
	# Облака.
	clouds = 0.0 if thin else r.range_f(0.15, 0.4)
	if p.has_tag("oceanic"): clouds += 0.15
	if p.has_tag("dense_atmosphere"): clouds += 0.15
	if p.has_tag("storms"): clouds = maxf(clouds, 0.62)
	if p.has_tag("frozen"): clouds *= 0.7
	clouds = clampf(clouds, 0.0, 0.8)
	var wa := r.range_f(0.0, TAU)
	wind = Vector2(cos(wa), sin(wa)) * (0.012 if p.has_tag("storms") else 0.004)
	# Сияние.
	if p.has_tag("strong_magnetosphere") or p.has_tag("radiation"):
		aurora = 1.0 if p.has_tag("strong_magnetosphere") else 0.7
		aurora_col = Color(0.3, 1.0, 0.55) if not p.has_tag("radiation") else Color(0.85, 0.35, 1.0)
	# Луны: 0–2 (у кольцевых — не больше одной), своя орбита и цвет.
	var nm := r.range_i(0, 1 if p.has_tag("ringed") else 2)
	for i in nm:
		var ax := (pole + Vector3(r.range_f(-0.3, 0.3), r.range_f(-0.3, 0.3), r.range_f(-0.3, 0.3))).normalized()
		moons.append({"axis": ax, "phase": r.range_f(0.0, TAU),
			"period": r.range_f(1.3, 4.0) * (1.0 if r.chance(0.5) else -1.0), "size": r.range_f(0.03, 0.09),
			"col": [Color(0.85, 0.85, 0.83), Color(0.8, 0.62, 0.48), Color(0.75, 0.85, 0.95), Color(0.9, 0.82, 0.6)][r.range_i(0, 3)]})
	rings = p.has_tag("ringed")
	hole = p.has_tag("singularity")
	if p.has_tag("volcanic"):
		low_glow = Color(0.35, 0.08, 0.02)
	fog_day = hor.lerp(Color(0.6, 0.6, 0.62), 0.4)
	ambient_day = Color(0.55, 0.55, 0.58).lerp(top.lerp(hor, 0.5), 0.35)
	_material(r)
	if env != null:
		var sky := Sky.new()
		sky.sky_material = mat
		sky.radiance_size = Sky.RADIANCE_SIZE_32
		env.sky = sky
		env.background_mode = Environment.BG_SKY
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	update_now()

func _material(r: Rng) -> void:
	mat = ShaderMaterial.new()
	mat.shader = preload("res://proto/sky.gdshader")
	mat.set_shader_parameter("sun_size", sun_size)
	mat.set_shader_parameter("sun_glow", 0.12 if thin else 0.35)
	mat.set_shader_parameter("haze", haze)
	mat.set_shader_parameter("day_top", day_top)
	mat.set_shader_parameter("day_hor", day_hor)
	mat.set_shader_parameter("night_top", night_top)
	mat.set_shader_parameter("night_hor", night_hor)
	mat.set_shader_parameter("sunset_col", sunset)
	mat.set_shader_parameter("ground_col", day_hor.darkened(0.5))
	mat.set_shader_parameter("low_glow", low_glow)
	mat.set_shader_parameter("stars", stars)
	_band_n = Vector3(r.range_f(-1, 1), r.range_f(-0.5, 0.5), r.range_f(-1, 1)).normalized()
	mat.set_shader_parameter("cloud_cover", clouds)
	mat.set_shader_parameter("cloud_col", Color(0.95, 0.95, 0.95).lerp(day_hor, 0.3))
	mat.set_shader_parameter("aurora", aurora)
	mat.set_shader_parameter("aurora_col", aurora_col)
	if rings:
		# Кольца лежат в плоскости экватора: дугой над горизонтом со стороны
		# полуденного солнца (там экватор); у экватора дуга выше и тоньше.
		var tilt := r.range_f(0.95, 1.3)
		var fl := Vector3(noon_dir.x, 0, noon_dir.z).normalized().rotated(Vector3.UP, r.range_f(-0.4, 0.4))
		mat.set_shader_parameter("ring_on", 1.0)
		_ring_n = (Vector3.UP * cos(tilt) - fl * sin(tilt)).normalized()
		var r0 := r.range_f(1.4, 1.9)
		mat.set_shader_parameter("ring_r", Vector2(r0, r0 + r.range_f(0.6, 1.2)))
		mat.set_shader_parameter("ring_col", [Color(0.85, 0.8, 0.7), Color(0.75, 0.8, 0.88), Color(0.8, 0.65, 0.5)][r.range_i(0, 2)])
		mat.set_shader_parameter("ring_seed", r.range_f(0.0, 10.0))
	if hole:
		var fl := Vector3(noon_dir.x, 0, noon_dir.z).normalized()
		var hd := (fl * r.range_f(0.6, 1.0) + east * r.range_f(-0.5, 0.5) + Vector3.UP * r.range_f(0.35, 0.7)).normalized()
		_hole = Vector4(hd.x, hd.y, hd.z, r.range_f(0.03, 0.05))

# Направления в системе планеты (как у наблюдателя на участке); в местную — через turn.
var _band_n := Vector3(0.3, 0.2, 0.93)
var _ring_n := Vector3.ZERO
var _hole := Vector4.ZERO

## Направление на солнце в момент t суток (местная система наблюдателя).
func sun_dir_at(t: float) -> Vector3:
	var a := (t - 0.25) * TAU
	return turn * (east * cos(a) + noon_dir * sin(a)).normalized()

## Местное время: на другой стороне шара полдень наступает в другой момент.
## Сдвиг — угол от участка до робота вокруг оси неба.
func local_time() -> float:
	var up := turn.inverse() * Vector3.UP
	var a := Vector3.UP - pole * pole.dot(Vector3.UP)
	var b := up - pole * pole.dot(up)
	if a.length_squared() < 1.0e-6 or b.length_squared() < 1.0e-6:
		return time
	return fposmod(time - a.signed_angle_to(b, pole) / TAU, 1.0)

## Высота солнца (синус угла над горизонтом) сейчас.
func sun_height() -> float:
	return sun_dir_at(time).y

## Часы для HUD: «06:30».
func clock() -> String:
	var m := int(local_time() * 24.0 * 60.0)
	return "%02d:%02d" % [m / 60, m % 60]

func _process(dt: float) -> void:
	if running:
		# Ночью время бежит быстрее: темнота не затягивается.
		var k := lerpf(NIGHT_SPEED, 1.0, day)
		time = fposmod(time + dt * k / day_len, 1.0)
	_cloud += wind * dt
	_sky_t -= dt
	_apply(_sky_t <= 0.0)
	if _sky_t <= 0.0:
		_sky_t = UPDATE_SKY

## Пересчитать всё сразу (после смены времени).
func update_now() -> void:
	_apply(true)

func _apply(sky_too: bool) -> void:
	var sd := sun_dir_at(time)
	var h := sd.y
	day = smoothstep(-0.12, 0.2, h)
	var tw := clampf(1.0 - absf(h) / 0.22, 0.0, 1.0)
	night = 1.0 - smoothstep(-0.1, 0.12, h)
	# Лампа: днём — солнце; когда оно ушло за горизонт — луна (или звёзды).
	var sun_k := smoothstep(-0.03, 0.15, h)
	var col := sun_col.lerp(sunset.lerp(sun_col, 0.3), tw * 0.8)
	if sun != null:
		if sun_k > 0.02:
			_aim(sd)
			sun.light_color = col
			sun.light_energy = sun_energy * sun_k * (0.55 if thin and h < 0.1 else 1.0)
		else:
			var md := _brightest_moon()
			_aim(md if md != Vector3.ZERO else (turn * pole).slerp(Vector3.UP, 0.6))
			var moon_k := smoothstep(-0.03, -0.18, h)
			sun.light_color = Color(0.6, 0.7, 1.0)
			sun.light_energy = (0.28 if md != Vector3.ZERO else 0.14) * moon_k
	if env != null:
		var amb := NIGHT_AMBIENT.lerp(ambient_day, day)
		env.ambient_light_color = amb
		env.ambient_light_energy = lerpf(0.3 if not thin else 0.24, 0.45, day)
		fog_color = night_hor.lerp(Color(0.05, 0.06, 0.09), 0.5).lerp(fog_day, day)
		fog_color = fog_color.lerp(sunset * 0.8, tw * 0.35)
		if not cave:
			env.fog_light_color = fog_color
	if sky_too and mat != null:
		mat.set_shader_parameter("local_frame", frame.inverse())
		mat.set_shader_parameter("sun_dir", sd)
		mat.set_shader_parameter("sun_color", col)
		mat.set_shader_parameter("day", day)
		mat.set_shader_parameter("twilight", tw)
		if binary:
			var s2 := sun_dir_at(time + 0.02).rotated(turn * pole, 0.12)
			mat.set_shader_parameter("sun2", Vector4(s2.x, s2.y, s2.z, sun_size * 0.45))
			mat.set_shader_parameter("sun2_color", Color(1.0, 0.7, 0.45) if star != "red" else Color(0.85, 0.9, 1.0))
		# Небо поворачивается вместе с сутками (у захваченных — стоит).
		mat.set_shader_parameter("star_rot", Basis(pole, -time * TAU) * turn.inverse())
		mat.set_shader_parameter("band_n", turn * _band_n)
		if rings:
			mat.set_shader_parameter("ring_n", turn * _ring_n)
		if hole:
			var hd := turn * Vector3(_hole.x, _hole.y, _hole.z)
			mat.set_shader_parameter("hole", Vector4(hd.x, hd.y, hd.z, _hole.w))
		for i in 2:
			var key := "moon%d" % i
			if i < moons.size():
				var md := moon_dir(i)
				mat.set_shader_parameter(key, Vector4(md.x, md.y, md.z, moons[i].size))
				mat.set_shader_parameter(key + "_col", moons[i].col)
			else:
				mat.set_shader_parameter(key, Vector4.ZERO)
		mat.set_shader_parameter("cloud_shift", _cloud)
		mat.set_shader_parameter("aurora_shift", _cloud * 3.0 + Vector2(time * 4.0, 0.0))

## Направление на луну i: своя орбита, отстаёт от неба (фазы меняются день ото дня).
func moon_dir(i: int) -> Vector3:
	var m: Dictionary = moons[i]
	var a: float = (time - 0.25) * TAU * (1.0 - 1.0 / m.period) + m.phase
	var ax: Vector3 = m.axis
	var e := ax.cross(Vector3.FORWARD if absf(ax.z) < 0.9 else Vector3.RIGHT).normalized()
	return turn * e.rotated(ax, a)

func _brightest_moon() -> Vector3:
	var best := Vector3.ZERO
	for i in moons.size():
		var d := moon_dir(i)
		if d.y > 0.15 and (best == Vector3.ZERO or d.y > best.y):
			best = d
	return best

## Направить свет: из d (к источнику, в местной системе) к земле.
func _aim(d: Vector3) -> void:
	var dn := (frame * d).normalized()
	var up := Vector3.UP if absf(dn.y) < 0.99 else Vector3.RIGHT
	sun.basis = Basis.looking_at(-dn, up)
