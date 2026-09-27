class_name ProtoWorldStyle
extends RefCounted
## Облик и физика 3D-планеты по её тегам: форма рельефа, тип пещеры, вид
## кристаллов, плотность воздуха. Теги складываются: вулканическая кора с
## кристаллической дают и конус вулкана, и скальные иглы.
##   Рельеф: ледяная — сглаженная, океаническая — низкая, вулканическая — конус
##   с кратером и ступени базальта, кристаллическая кора — острые гребни и иглы,
##   сейсмическая — расщелины, разреженная атмосфера и кольца — кратеры, бури —
##   рябь дюн, аномалии — парящие глыбы, гравитация — высота холмов.
##   Пещера: вулкан — лавовая труба, лёд — высокий ледяной грот с сосульками,
##   кристаллы — жеода, сейсмика — узкая трещина, грибы — низкий грот с грибами.
##   Механика: гравитация меняет скорость хода и высоту уступа, давление
##   атмосферы — производительность насосов (как в игре и в пневматике).

# Рельеф
var relief_amp := 9.0         # размах холмов, м
var relief_freq := 0.035
var octaves := 4
var ridged := 0.0             # доля острых гребней (1 — сплошь гребни)
var terrace := 0.0            # шаг ступеней, м (0 — без ступеней)
var volcano := false          # конус с кратером в дальнем углу
var spires := 0               # скальных игл
var craters := 0
var fissures := 0
var dunes := 0.0              # высота ряби дюн, м
var floaters := 0             # парящих глыб
var lake_r := 9.0

# Пещера: эллипсоид с полуосями вдоль оси, поперёк и вверх.
var cave := "dome"            # dome, tube, ice, geode, fissure, grotto
var cave_len := 7.0
var cave_wid := 7.0
var cave_h := 4.4
var cave_axis := Vector2(1, 0)    # направление длинной оси в плане
var worms := 0.035                # толщина случайных червоточин (0 — нет)

# Кристаллы
var habit := "prism"          # prism, needle, blade, cube, shard
var druzes := 9
var druze_size := 1.0
var crystal_glow := 0.7
var crystal_alpha := 0.85
var crystal_tint := Color(0, 0, 0, 0)   # подмешивается к цвету материала (a — доля)
var surface_druzes := 0       # друз на поверхности (кристаллическая кора)
var drips := 18               # натёков в пещере
var icicles := false
var mushrooms := 0
var vein_tint := Color(0, 0, 0, 0)

# Воздух и механика
var fog_mult := 1.0
var wind := 0.0
var gravity := 1.0
var pressure := 1.0

static func for_planet(p: Planet) -> ProtoWorldStyle:
	var s := ProtoWorldStyle.new()
	s.gravity = p.gravity
	s.pressure = p.atm_pressure
	var t := func(tag: String) -> bool: return p.has_tag(tag)
	# --- гравитация: при слабой холмы выше, кристаллы тянутся вверх
	s.relief_amp *= clampf(1.0 / sqrt(p.gravity), 0.7, 1.4)
	if p.gravity < 0.8:
		s.relief_freq = 0.028
		s.druze_size = 1.35
		s.spires += 4
	elif p.gravity > 1.3:
		s.druze_size = 0.75
		s.octaves = 3
	# --- кора и климат
	if t.call("frozen"):
		s.octaves = 2
		s.relief_amp *= 0.75
		s.cave = "ice"
		s.habit = "needle"
		s.icicles = true
		s.crystal_glow = 0.35
		s.crystal_alpha = 0.6
		s.crystal_tint = Color(0.8, 0.92, 1.0, 0.45)
		s.worms = 0.0
	if t.call("oceanic"):
		s.relief_amp *= 0.7
		s.lake_r = 12.5
	if t.call("volcanic"):
		s.volcano = true
		s.terrace = 2.2
		s.cave = "tube"
		s.habit = "blade"
		s.crystal_tint = Color(0.12, 0.08, 0.08, 0.35)
		s.crystal_glow = 1.0
		s.vein_tint = Color(1.0, 0.45, 0.12, 0.8)
		s.drips = 4
	if t.call("crystalline_crust"):
		s.ridged = 0.8
		s.spires += 9
		s.cave = "geode"
		s.druzes = 22
		s.druze_size *= 1.2
		s.surface_druzes = 14
	if t.call("seismic"):
		s.fissures = 4
		s.ridged = maxf(s.ridged, 0.35)
		if s.cave == "dome":
			s.cave = "fissure"
		if s.habit == "prism":
			s.habit = "shard"
	if t.call("fungal_biosphere"):
		s.mushrooms = 26
		if s.cave == "dome":
			s.cave = "grotto"
		s.drips = 8
	if t.call("high_gravity") and s.habit == "prism":
		s.habit = "cube"
	# --- небо
	if t.call("thin_atmosphere"):
		s.craters += 7
		s.fog_mult = 0.25
	if t.call("ringed"):
		s.craters += 3
	if t.call("storms"):
		s.dunes = 0.45
		s.wind = 1.0
		s.fog_mult *= 1.3
	if t.call("dense_atmosphere"):
		s.fog_mult *= 1.5
		s.wind = maxf(s.wind, 0.3)
	if t.call("radiation"):
		s.crystal_glow += 0.6
		s.crystal_tint = s.crystal_tint.lerp(Color(0.6, 1.0, 0.4, 0.3), 0.6)
	# --- аномалии
	if t.call("anomalous_field") or t.call("singularity"):
		s.floaters = 9
		s.crystal_tint = Color(0.75, 0.45, 1.0, 0.35)
		s.crystal_glow += 0.4
	_cave_shape(s)
	return s

static func _cave_shape(s: ProtoWorldStyle) -> void:
	# Длинная ось — по линии взгляда в пещерном кадре (с юго-запада на северо-восток).
	var diag := Vector2(1, -0.85).normalized()
	match s.cave:
		"tube":     # лавовая труба: длинная, низкая, с плоским полом
			s.cave_len = 12.5; s.cave_wid = 5.2; s.cave_h = 3.4; s.cave_axis = diag
		"ice":      # ледяной грот: высокий купол
			s.cave_len = 7.5; s.cave_wid = 7.0; s.cave_h = 6.2
		"geode":    # жеода: почти шар
			s.cave_len = 6.8; s.cave_wid = 6.8; s.cave_h = 5.8
		"fissure":  # трещина: узкая и высокая
			s.cave_len = 11.0; s.cave_wid = 3.6; s.cave_h = 7.0; s.cave_axis = diag
		"grotto":   # грибной грот: широкий и низкий
			s.cave_len = 9.0; s.cave_wid = 8.5; s.cave_h = 3.6

## Скорость хода робота: при сильной тяжести медленнее.
func walk_mult() -> float:
	return clampf(1.0 / sqrt(gravity), 0.7, 1.35)

## Какой уступ робот берёт с шага.
func step_height() -> float:
	return clampf(0.35 / gravity, 0.22, 0.75)

## Во сколько раз насос качает больше, чем при 1 атм.
func pump_mult() -> float:
	return pressure

func summary() -> String:
	return "рельеф: %s; пещера: %s; кристаллы: %s; насосы ×%.2f, ход ×%.2f, уступ %.2f м" % [
		", ".join(PackedStringArray(_relief_words())), {"dome": "купол", "tube": "лавовая труба", "ice": "ледяной грот",
		"geode": "жеода", "fissure": "трещина", "grotto": "грибной грот"}[cave],
		{"prism": "призмы", "needle": "иглы", "blade": "лезвия", "cube": "кубы", "shard": "осколки"}[habit],
		pump_mult(), walk_mult(), step_height()]

func _relief_words() -> Array:
	var w := []
	if volcano: w.append("вулкан")
	if terrace > 0.0: w.append("ступени")
	if ridged > 0.5: w.append("гребни")
	if spires > 0: w.append("иглы")
	if craters > 0: w.append("кратеры")
	if fissures > 0: w.append("расщелины")
	if dunes > 0.0: w.append("дюны")
	if floaters > 0: w.append("парящие глыбы")
	if w.is_empty(): w.append("холмы" if octaves > 2 else "пологие холмы")
	return w
