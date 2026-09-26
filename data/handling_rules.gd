class_name HandlingRules
## Как теги меняют обращение с материалом ВНЕ обработчиков.
##
## Контексты:
##   open    — в открытом контейнере
##   ground  — лежит на земле
##   sealed  — в закрытом баке
##   capsule — летит в капсуле
##   launch  — в момент выстрела
##   impact  — в момент удара о приёмник/землю
##   carried — в руках (инвентаре) робота
##
## effect — имя эффекта, реализованного в core/handling.gd; rate — его сила.
## planet — эффект срабатывает, только если у планеты есть один из тегов.
## oxidizing — только в окисляющей атмосфере.

const RULES := [
	{"tag": "volatile", "ctx": ["open", "ground"], "effect": "evaporate", "rate": 0.04,
		"desc": "Испаряется на открытом воздухе — храните в закрытом баке."},
	{"tag": "flammable", "ctx": ["open", "ground", "carried"], "effect": "ignite", "rate": 0.08, "oxidizing": true,
		"desc": "В окисляющей атмосфере или рядом с горячей машиной загорается."},
	{"tag": "pyrophoric", "ctx": ["open", "ground", "carried", "capsule"], "effect": "ignite", "rate": 0.25, "oxidizing": true, "always": true,
		"desc": "Воспламеняется сам на воздухе с окислителем; в баке безопасен."},
	{"tag": "brittle", "ctx": ["launch", "impact"], "effect": "shatter", "rate": 0.25,
		"desc": "При выстреле и ударе часть превращается в порошок."},
	{"tag": "acidic", "ctx": ["open", "sealed"], "effect": "corrode", "rate": 1.0,
		"desc": "Разъедает контейнеры, если они не из изолирующего, кристаллического или якорного."},
	{"tag": "phasing", "ctx": ["open", "sealed", "capsule"], "effect": "phase_leak", "rate": 0.06,
		"desc": "Просачивается сквозь стенки, если они не из якорного материала."},
	{"tag": "antigravitic", "ctx": ["open", "ground"], "effect": "float_away", "rate": 0.08,
		"desc": "Улетает из открытых контейнеров."},
	{"tag": "radioactive", "ctx": ["carried"], "effect": "irradiate", "rate": 0.4,
		"desc": "Облучает робота, который его несёт."},
	{"tag": "radioactive", "ctx": ["open", "sealed"], "effect": "warm", "rate": 0.5,
		"desc": "Греет контейнер."},
	{"tag": "hygroscopic", "ctx": ["open", "ground"], "effect": "absorb_water", "rate": 0.02, "planet": ["oceanic", "acid_rain"],
		"desc": "Во влажной атмосфере набирает воду и массу."},
	{"tag": "toxic", "ctx": ["carried"], "effect": "poison", "rate": 0.25,
		"desc": "Разъедает робота без защитной оболочки."},
	{"tag": "sticky", "ctx": ["launch"], "effect": "jam", "rate": 0.3,
		"desc": "Часть застревает в стволе пушки."},
	{"tag": "self_replicating", "ctx": ["open", "sealed"], "effect": "replicate", "rate": 0.03,
		"desc": "Растёт, поглощая соседние порции в контейнере."},
	{"tag": "mimetic", "ctx": ["open", "sealed"], "effect": "mimic", "rate": 0.02,
		"desc": "Перенимает теги соседних порций."},
	{"tag": "echoing", "ctx": ["launch"], "effect": "echo", "rate": 0.3,
		"desc": "При выстреле часть порции дублируется (без отзвучности)."},
	{"tag": "tethered", "ctx": ["ground"], "effect": "crawl", "rate": 1.0,
		"desc": "Сам ползёт к ближайшему контейнеру со своим материалом."},
	{"tag": "chrono_lagged", "ctx": ["open", "sealed", "ground", "carried"], "effect": "lag", "rate": 0.2,
		"desc": "Все изменения с ним идут медленно."},
	{"tag": "resonant", "ctx": ["open", "sealed"], "effect": "emit_signal", "rate": 1.0,
		"desc": "Контейнер с ним сам выдаёт логический сигнал."},
	{"tag": "void", "ctx": ["sealed"], "effect": "absorb_gas", "rate": 0.3,
		"desc": "Поглощает газ — давление в баке падает."},
]

## Влияние на дальность и точность пушек (множители и разброс в клетках).
const CANNON := {
	"dense": {"range": 0.65},
	"antigravitic": {"range": 1.7},
	"porous": {"range": 1.1},
	"magnetic": {"scatter": 2.5, "planet": "strong_magnetosphere"},
}

static func rules_for(tag: String) -> Array:
	return RULES.filter(func(r): return r.tag == tag)
