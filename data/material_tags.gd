class_name MaterialTags
## Словарь тегов материалов. Материалов как таковых нет — есть только свойства.
##
## Поля:
##   n     — отображаемое имя
##   inc   — несовместимые теги (проверка симметричная)
##   melt, boil — сдвиг температур плавления/кипения, °C
##   dens  — сдвиг плотности, г/см³
##   hard  — сдвиг твёрдости (шкала ~0..10)
##   w     — вес при генерации
##   col   — вклад в цвет порции
##   exotic — невозможное в реальности свойство

const BASE_MELT := 700.0
const BASE_BOIL := 2200.0
const BASE_DENSITY := 3.0
const BASE_HARDNESS := 4.0

const TAGS := {
	# --- обычные ---
	"metallic":    {"n": "металлический", "inc": ["organic", "fibrous", "volatile", "insulating"], "melt": 500, "boil": 600, "dens": 3.5, "hard": 2.0, "w": 1.2, "col": Color(0.70, 0.72, 0.78)},
	"organic":     {"n": "органический", "inc": ["metallic", "crystalline"], "melt": -550, "boil": -1700, "dens": -1.8, "hard": -2.5, "w": 1.0, "col": Color(0.45, 0.62, 0.25)},
	"volatile":    {"n": "летучий", "inc": ["dense", "crystalline", "metallic", "void"], "melt": -700, "boil": -2150, "dens": -1.5, "hard": -3.0, "w": 0.9, "col": Color(0.80, 0.90, 1.00)},
	"flammable":   {"n": "горючий", "inc": ["oxidizer", "insulating"], "melt": -300, "boil": -900, "dens": -0.8, "hard": -1.0, "w": 1.0, "col": Color(0.95, 0.55, 0.15)},
	"oxidizer":    {"n": "окислитель", "inc": ["flammable", "pyrophoric"], "melt": -200, "boil": -800, "dens": 0.2, "hard": -0.5, "w": 0.8, "col": Color(0.95, 0.90, 0.35)},
	"acidic":      {"n": "кислотный", "inc": ["alkaline"], "melt": -400, "boil": -1600, "dens": 0.3, "hard": -1.5, "w": 0.8, "col": Color(0.60, 0.95, 0.30)},
	"alkaline":    {"n": "щелочной", "inc": ["acidic"], "melt": -100, "boil": -600, "dens": 0.1, "hard": -0.5, "w": 0.8, "col": Color(0.55, 0.55, 0.95)},
	"magnetic":    {"n": "магнитный", "inc": [], "melt": 200, "boil": 300, "dens": 1.5, "hard": 1.0, "w": 0.7, "col": Color(0.35, 0.35, 0.45)},
	"conductive":  {"n": "проводящий", "inc": ["insulating"], "melt": 100, "boil": 200, "dens": 1.0, "hard": 0.5, "w": 0.8, "col": Color(0.85, 0.60, 0.35)},
	"insulating":  {"n": "изолирующий", "inc": ["conductive", "metallic", "flammable"], "melt": 300, "boil": 400, "dens": -0.8, "hard": 0.0, "w": 0.8, "col": Color(0.92, 0.88, 0.80)},
	"brittle":     {"n": "хрупкий", "inc": ["elastic", "fibrous"], "melt": 0, "boil": 0, "dens": 0.0, "hard": 1.5, "w": 0.9, "col": Color(0.75, 0.75, 0.80)},
	"elastic":     {"n": "упругий", "inc": ["brittle", "crystalline"], "melt": -250, "boil": -500, "dens": -0.5, "hard": -1.0, "w": 0.7, "col": Color(0.30, 0.30, 0.30)},
	"fibrous":     {"n": "волокнистый", "inc": ["brittle", "crystalline", "metallic"], "melt": -150, "boil": -500, "dens": -1.0, "hard": -0.5, "w": 0.7, "col": Color(0.85, 0.75, 0.50)},
	"crystalline": {"n": "кристаллический", "inc": ["fibrous", "elastic", "volatile", "organic", "sticky"], "melt": 400, "boil": 500, "dens": 0.5, "hard": 2.5, "w": 1.0, "col": Color(0.65, 0.90, 0.95)},
	"dense":       {"n": "плотный", "inc": ["porous", "volatile", "antigravitic"], "melt": 300, "boil": 400, "dens": 4.0, "hard": 1.5, "w": 1.0, "col": Color(0.30, 0.28, 0.32)},
	"porous":      {"n": "пористый", "inc": ["dense"], "melt": -100, "boil": 0, "dens": -1.5, "hard": -1.5, "w": 1.0, "col": Color(0.70, 0.60, 0.55)},
	"hygroscopic": {"n": "гигроскопичный", "inc": ["pyrophoric"], "melt": -100, "boil": -300, "dens": 0.0, "hard": -0.5, "w": 0.7, "col": Color(0.60, 0.75, 0.85)},
	"radioactive": {"n": "радиоактивный", "inc": [], "melt": 400, "boil": 500, "dens": 3.0, "hard": 0.5, "w": 0.35, "col": Color(0.40, 1.00, 0.40)},
	"pyrophoric":  {"n": "пирофорный", "inc": ["hygroscopic", "oxidizer"], "melt": -200, "boil": -300, "dens": 0.5, "hard": -0.5, "w": 0.5, "col": Color(1.00, 0.35, 0.20)},
	"toxic":       {"n": "токсичный", "inc": [], "melt": -200, "boil": -700, "dens": 0.0, "hard": -0.5, "w": 0.7, "col": Color(0.55, 0.20, 0.60)},
	"sticky":      {"n": "липкий", "inc": ["crystalline", "phasing"], "melt": -350, "boil": -700, "dens": 0.0, "hard": -2.0, "w": 0.6, "col": Color(0.55, 0.40, 0.20)},
	"luminous":    {"n": "светящийся", "inc": [], "melt": 0, "boil": 0, "dens": 0.0, "hard": 0.0, "w": 0.5, "col": Color(1.00, 1.00, 0.70)},
	"refractory":  {"n": "тугоплавкий", "inc": ["volatile", "organic"], "melt": 900, "boil": 800, "dens": 0.5, "hard": 1.0, "w": 0.4, "col": Color(0.80, 0.45, 0.30)},
	"cryogenic":   {"n": "криогенный", "inc": ["pyrophoric", "refractory"], "melt": -400, "boil": -600, "dens": 0.0, "hard": -0.5, "w": 0.35, "col": Color(0.70, 0.90, 1.00)},
	# --- невозможные в реальности ---
	"antigravitic":     {"n": "антигравитационный", "inc": ["dense"], "melt": 100, "boil": 200, "dens": -6.0, "hard": 0.0, "w": 0.12, "col": Color(0.85, 0.60, 1.00), "exotic": true},
	"phasing":          {"n": "фазирующий", "inc": ["anchoring", "sticky", "tethered"], "melt": 0, "boil": 0, "dens": -1.0, "hard": -1.0, "w": 0.12, "col": Color(0.60, 0.95, 0.95), "exotic": true},
	"anchoring":        {"n": "якорный", "inc": ["phasing"], "melt": 600, "boil": 800, "dens": 2.0, "hard": 2.0, "w": 0.12, "col": Color(0.25, 0.35, 0.55), "exotic": true},
	"thermo_inverted":  {"n": "термоинвертный", "inc": ["phase_inverted"], "melt": 0, "boil": 0, "dens": 0.0, "hard": 0.0, "w": 0.1, "col": Color(0.30, 0.70, 1.00), "exotic": true},
	"phase_inverted":   {"n": "фазоинвертный", "inc": ["thermo_inverted"], "melt": 0, "boil": 0, "dens": 0.0, "hard": 0.0, "w": 0.1, "col": Color(1.00, 0.45, 0.70), "exotic": true},
	"self_replicating": {"n": "самовоспроизводящийся", "inc": [], "melt": -200, "boil": -400, "dens": -0.5, "hard": -1.0, "w": 0.1, "col": Color(0.95, 0.30, 0.45), "exotic": true},
	"resonant":         {"n": "резонирующий", "inc": [], "melt": 100, "boil": 100, "dens": 0.0, "hard": 0.5, "w": 0.12, "col": Color(0.95, 0.80, 1.00), "exotic": true},
	"void":             {"n": "пустотный", "inc": ["volatile", "echoing"], "melt": 300, "boil": 1000, "dens": -2.0, "hard": 0.0, "w": 0.1, "col": Color(0.08, 0.05, 0.12), "exotic": true},
	"mimetic":          {"n": "мимикрирующий", "inc": [], "melt": 0, "boil": 0, "dens": 0.0, "hard": 0.0, "w": 0.1, "col": Color(0.75, 0.75, 0.75), "exotic": true},
	"chrono_lagged":    {"n": "запаздывающий во времени", "inc": [], "melt": 0, "boil": 0, "dens": 0.5, "hard": 0.5, "w": 0.1, "col": Color(0.55, 0.50, 0.40), "exotic": true},
	"echoing":          {"n": "отзвучный", "inc": ["void"], "melt": 0, "boil": 0, "dens": 0.0, "hard": 0.0, "w": 0.1, "col": Color(0.70, 0.85, 0.70), "exotic": true},
	"tethered":         {"n": "привязанный", "inc": ["phasing"], "melt": 0, "boil": 0, "dens": 0.0, "hard": 0.0, "w": 0.1, "col": Color(0.95, 0.70, 0.40), "exotic": true},
	"superfluid":       {"n": "сверхтекучий", "inc": ["sticky", "dense"], "melt": -300, "boil": -200, "dens": -0.5, "hard": -1.5, "w": 0.08, "col": Color(0.55, 0.85, 1.00), "exotic": true},
	"self_assembling":  {"n": "самосборный", "inc": ["brittle"], "melt": 100, "boil": 200, "dens": 0.0, "hard": 0.5, "w": 0.08, "col": Color(0.90, 0.75, 0.95), "exotic": true},
}

static func all() -> Array:
	return TAGS.keys()

static func is_exotic(tag: String) -> bool:
	return TAGS.get(tag, {}).get("exotic", false)

static func exotic_tags() -> Array:
	return TAGS.keys().filter(func(t): return is_exotic(t))

static func normal_tags() -> Array:
	return TAGS.keys().filter(func(t): return not is_exotic(t))

static func display(tag: String) -> String:
	return TAGS.get(tag, {}).get("n", tag)

static func compatible(a: String, b: String) -> bool:
	if a == b:
		return false
	return not (b in TAGS[a].inc or a in TAGS[b].inc)

## Добавляет тег, вытесняя несовместимые с ним.
static func add_tag(tags: Array, tag: String) -> Array:
	if tag in tags:
		return tags.duplicate()
	var out: Array = tags.filter(func(t): return compatible(t, tag))
	out.append(tag)
	out.sort()
	return out
