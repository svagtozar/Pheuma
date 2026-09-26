class_name PlanetTags
## Словарь тегов планеты. 3–5 тегов на ран делают каждую планету непохожей.
##
##   temp   — сдвиг температуры среды, °C
##   press  — множитель давления атмосферы
##   grav   — множитель гравитации
##   weights — множители веса тегов материалов при генерации
##   atm    — теги, которые получает газ атмосферы
##   terrain — какие препятствия появляются на карте
##   goals  — множители веса шаблонов целей

const BASE_TEMP := 15.0
const BASE_PRESSURE := 1.0
const BASE_GRAVITY := 1.0

const TAGS := {
	"volcanic": {"n": "вулканическая", "desc": "Жарко, лавовые реки, много горючего и плотного.",
		"inc": ["frozen"], "temp": 70.0, "weights": {"flammable": 2.0, "dense": 1.8, "pyrophoric": 2.5, "metallic": 1.4},
		"terrain": ["lava"], "goals": {"mining": 1.5}},
	"frozen": {"n": "ледяная", "desc": "Мороз, тонкий лёд над расщелинами. Летучее здесь часто твёрдое.",
		"inc": ["volcanic", "oceanic"], "temp": -110.0, "weights": {"volatile": 1.8, "brittle": 1.8, "crystalline": 1.5},
		"terrain": ["ice"], "goals": {"science": 1.3}},
	"thin_atmosphere": {"n": "разреженная атмосфера", "desc": "Насосам почти нечего качать.",
		"inc": ["dense_atmosphere", "storms", "acid_rain"], "press": 0.25, "goals": {"colony": 1.4}},
	"dense_atmosphere": {"n": "плотная атмосфера", "desc": "Насосы работают отлично, капсулы тормозятся воздухом.",
		"inc": ["thin_atmosphere"], "press": 3.0, "temp": 25.0},
	"toxic_atmosphere": {"n": "ядовитая атмосфера", "desc": "Незащищённый корпус медленно разъедает.",
		"inc": [], "atm": ["toxic"], "weights": {"toxic": 1.8}, "goals": {"colony": 1.3}},
	"oxidizing_atmosphere": {"n": "окисляющая атмосфера", "desc": "Горючее вспыхивает на открытом воздухе.",
		"inc": [], "atm": ["oxidizer"], "weights": {"oxidizer": 1.5}},
	"low_gravity": {"n": "низкая гравитация", "desc": "Пушки бьют дальше, прыжки выше.",
		"inc": ["high_gravity"], "grav": 0.4, "goals": {"mining": 1.3}},
	"high_gravity": {"n": "высокая гравитация", "desc": "Пушкам нужно больше давления.",
		"inc": ["low_gravity"], "grav": 1.8, "weights": {"dense": 1.5}},
	"storms": {"n": "бури", "desc": "Капсулы сносит ветром, лёгкие постройки ломаются.",
		"inc": ["thin_atmosphere"], "goals": {"beacon": 1.5}},
	"radiation": {"n": "радиационный фон", "desc": "Корпус робота облучается, радиоактивного больше.",
		"inc": ["strong_magnetosphere"], "weights": {"radioactive": 3.0, "luminous": 1.5}},
	"strong_magnetosphere": {"n": "сильная магнитосфера", "desc": "Магнитные грузы сбивают прицел пушек.",
		"inc": ["radiation"], "weights": {"magnetic": 2.0, "conductive": 1.4}, "goals": {"beacon": 1.3}},
	"tidally_locked": {"n": "приливный захват", "desc": "Вечные сумерки и перепады температур.",
		"inc": [], "temp": -30.0, "weights": {"luminous": 1.8}},
	"oceanic": {"n": "океаническая", "desc": "Сыро: гигроскопичное набирает воду, пористое обрастает.",
		"inc": ["frozen"], "weights": {"hygroscopic": 2.0, "organic": 1.8, "alkaline": 1.3},
		"terrain": ["acid"], "goals": {"colony": 1.4}},
	"acid_rain": {"n": "кислотные дожди", "desc": "Открытые контейнеры и порции разъедает.",
		"inc": ["thin_atmosphere"], "atm": ["acidic"], "weights": {"acidic": 1.8},
		"terrain": ["acid"]},
	"crystalline_crust": {"n": "кристаллическая кора", "desc": "Твёрдые, хрупкие породы.",
		"inc": [], "weights": {"crystalline": 2.2, "brittle": 1.6}, "goals": {"beacon": 1.3}},
	"seismic": {"n": "сейсмическая", "desc": "Землетрясения иногда рвут трубы.",
		"inc": [], "weights": {"dense": 1.3}, "terrain": ["chasm"], "goals": {"mining": 1.2}},
	"fungal_biosphere": {"n": "грибная биосфера", "desc": "Грибницы повсюду: органика, волокна, споровые выбросы забивают насосы.",
		"inc": ["frozen"], "atm": ["toxic"], "weights": {"organic": 2.5, "fibrous": 2.0, "toxic": 1.5},
		"goals": {"science": 1.3, "terraform": 1.6}},
	"ringed": {"n": "кольца", "desc": "Над горизонтом кольца; обломки падают вместе с металлом и тугоплавкой породой.",
		"inc": [], "weights": {"metallic": 1.5, "crystalline": 1.5, "refractory": 2.0}, "goals": {"orbital": 2.0}},
	# --- аномалии ---
	"anomalous_field": {"n": "аномальное поле", "desc": "Невозможные свойства встречаются часто.",
		"inc": [], "anomaly": true, "exotic_mult": 5.0, "goals": {"anomaly": 3.0}},
	"inverted_thermodynamics": {"n": "обращённая термодинамика", "desc": "Часть материалов греется от холода.",
		"inc": [], "anomaly": true, "weights": {"thermo_inverted": 12.0, "phase_inverted": 6.0}, "goals": {"anomaly": 1.5}},
	"temporal_drift": {"n": "временной дрейф", "desc": "Процессы идут то быстрее, то медленнее.",
		"inc": [], "anomaly": true, "weights": {"chrono_lagged": 12.0}, "goals": {"science": 1.5}},
	"ancient_ruins": {"n": "древние руины", "desc": "Остатки чужих машин и залежи экзотики.",
		"inc": [], "anomaly": true, "exotic_mult": 3.0, "goals": {"anomaly": 2.0, "archaeology": 4.0}},
	"singularity": {"n": "сингулярность", "desc": "Рядом крошечная чёрная дыра: тяжело, время петляет, пустотное и сверхтекучее не редкость.",
		"inc": ["low_gravity"], "anomaly": true, "grav": 1.6, "exotic_mult": 2.0,
		"weights": {"void": 3.0, "chrono_lagged": 2.0, "superfluid": 2.0}, "goals": {"anomaly": 1.5}},
}

static func all() -> Array:
	return TAGS.keys()

static func display(tag: String) -> String:
	return TAGS.get(tag, {}).get("n", tag)

static func compatible(a: String, b: String) -> bool:
	if a == b:
		return false
	return not (b in TAGS[a].get("inc", []) or a in TAGS[b].get("inc", []))

## Веса выбора тегов планеты: аномалии редки.
static func pick_weights() -> Dictionary:
	var w := {}
	for t in TAGS:
		w[t] = 0.35 if TAGS[t].get("anomaly", false) else 1.0
	return w
