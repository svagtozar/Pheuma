class_name Processes
## Способы обработки. Каждый процесс — машина со своими правилами изменения тегов.
##
## Процесс:
##   n, desc   — имя и описание
##   dur       — длительность цикла, с
##   gas_min   — минимальное давление в узле машины, атм (0 — газ не нужен)
##   gas_use   — расход газа за цикл (в единицах газа)
##   outs      — число выходов (1 или 2; второй выход — справа от направления)
##   split     — доля массы во второй выход (для разделяющих машин)
##   temp      — режим температуры: "heat" (к заданной T), "cool" (ниже T плавления),
##               "sinter" (чуть ниже T плавления)
##   reagent   — обработчик: берёт реагент из бокового входа
##   source    — нужен источник с тегом (в материале постройки или в реагенте)
##   route     — "magnetic"/"tag": не меняет теги, сортирует
## Правило:
##   all/any/none — условия по тегам входа; phase — фаза после смены T;
##   min_p — минимальное давление; min_t — минимальная T после нагрева;
##   was_hot — вход был жидким/газом, а выход твёрдый (закалка);
##   out — к какому выходу применяется (0, 1; нет — ко всем);
##   add/remove — изменения тегов; gas — доля массы в газовый узел

const PROCESSES := {
	"crusher": {"n": "Дробилка", "desc": "Размалывает хрупкое и кристаллическое в порошок. Упругое не дробится.",
		"dur": 2.0, "outs": 1, "rules": [
			{"any": ["brittle", "crystalline", "metallic"], "none": ["elastic"], "phase": "solid", "add": ["porous"], "remove": ["crystalline"]},
			{"all": ["metallic"], "none": ["elastic"], "phase": "solid", "add": ["pyrophoric"]},
		]},
	"furnace": {"n": "Печь", "desc": "Нагревает до заданной T; раздувается давлением. Горючее сгорает и даёт газ.",
		"dur": 3.0, "gas_min": 1.2, "gas_use": 0.4, "outs": 1, "temp": "heat", "rules": [
			{"all": ["flammable"], "remove": ["flammable"], "gas": 0.4},
			{"all": ["organic"], "phase": "liquid", "add": ["sticky"]},
			{"min_t": 600.0, "remove": ["volatile", "hygroscopic"]},
			{"all": ["thermo_inverted"], "add": ["phase_inverted"]},
		]},
	"condenser": {"n": "Конденсатор", "desc": "Охлаждает ниже T плавления. Резко застывшее становится хрупким.",
		"dur": 3.0, "outs": 1, "temp": "cool", "rules": [
			{"was_hot": true, "add": ["brittle"]},
			{"all": ["antigravitic"], "add": ["thermo_inverted"]},
		]},
	"compressor": {"n": "Компрессор", "desc": "Давит давлением сети: пористое уплотняется, при сверхдавлении — странное.",
		"dur": 3.0, "gas_min": 3.0, "gas_use": 1.5, "outs": 1, "rules": [
			{"all": ["porous"], "add": ["dense"]},
			{"all": ["dense"], "min_p": 6.0, "add": ["crystalline"]},
			{"all": ["dense", "metallic"], "min_p": 9.0, "add": ["radioactive"]},
			{"all": ["phasing"], "min_p": 6.0, "add": ["anchoring"]},
			{"all": ["crystalline", "conductive"], "min_p": 9.0, "add": ["antigravitic"]},
		]},
	"decompressor": {"n": "Декомпрессор", "desc": "Резкий сброс давления: летучая фракция отделяется во второй выход.",
		"dur": 2.0, "outs": 2, "split": 0.3, "rules": [
			{"out": 1, "add": ["volatile"], "gas": 0.2},
			{"out": 0, "remove": ["volatile"]},
			{"all": ["crystalline", "luminous"], "out": 0, "add": ["phasing"]},
		]},
	"treater": {"n": "Обработчик", "desc": "Применяет реагент (вход слева) к материалу (вход сзади) по таблице взаимодействий.",
		"dur": 2.5, "outs": 1, "reagent": true, "rules": []},
	"distiller": {"n": "Дистиллятор", "desc": "Делит на тяжёлую (прямо) и лёгкую летучую (вправо) фракции.",
		"dur": 3.0, "outs": 2, "split": 0.4, "rules": [
			{"out": 0, "remove": ["volatile"]},
			{"out": 1, "add": ["volatile"]},
		]},
	"centrifuge": {"n": "Центрифуга", "desc": "Делит по плотности: плотная фракция прямо, пористая вправо.",
		"dur": 2.5, "outs": 2, "split": 0.5, "rules": [
			{"out": 0, "add": ["dense"]},
			{"out": 1, "add": ["porous"]},
		]},
	"filter": {"n": "Фильтр", "desc": "Груз с выбранным тегом — прямо, остальное — вправо.",
		"dur": 0.5, "outs": 2, "route": "tag", "rules": []},
	"magnet_sep": {"n": "Магнитный сепаратор", "desc": "Магнитное — прямо, остальное — вправо.",
		"dur": 1.0, "outs": 2, "route": "magnetic", "rules": []},
	"electrolyzer": {"n": "Электролизёр", "desc": "Расщепляет жидкость: щёлочь и проводник — прямо, окислитель и кислота — вправо.",
		"dur": 3.0, "outs": 2, "split": 0.5, "rules": [
			{"out": 0, "remove": ["acidic"], "add": ["alkaline"]},
			{"out": 0, "all": ["metallic"], "add": ["conductive"]},
			{"out": 1, "remove": ["alkaline"], "add": ["oxidizer"]},
			{"out": 1, "all": ["hygroscopic"], "add": ["acidic"]},
		], "needs_phase": "liquid", "needs_any": ["conductive", "acidic", "alkaline", "hygroscopic", "metallic"]},
	"sinter": {"n": "Спекатель", "desc": "Порошок у самой T плавления спекается в плотное и кристаллическое.",
		"dur": 4.0, "outs": 1, "temp": "sinter", "rules": [
			{"all": ["porous"], "add": ["dense", "crystalline"]},
			{"all": ["metallic"], "add": ["magnetic"]},
		]},
	"irradiator": {"n": "Облучатель", "desc": "Нужен радиоактивный источник (материал постройки или реагент слева).",
		"dur": 3.0, "outs": 1, "source": "radioactive", "rules": [
			{"add": ["luminous"], "remove": ["toxic"]},
			{"all": ["magnetic"], "remove": ["magnetic"], "add": ["antigravitic"]},
		]},
	"loom": {"n": "Ткацкий станок", "desc": "Из волокнистого делает упругое изолирующее полотно.",
		"dur": 3.0, "outs": 1, "rules": [
			{"all": ["fibrous"], "phase": "solid", "add": ["elastic", "insulating"]},
		]},
}

const PHASE_BY_NAME := {"solid": Substance.Phase.SOLID, "liquid": Substance.Phase.LIQUID, "gas": Substance.Phase.GAS}

static func ids() -> Array:
	return PROCESSES.keys()

## Подходит ли правило (без учёта выхода).
static func rule_matches(rule: Dictionary, tags: Array, phase: int, pressure: float, temp: float, was_hot: bool) -> bool:
	for t in rule.get("all", []):
		if not t in tags:
			return false
	var any: Array = rule.get("any", [])
	if not any.is_empty():
		var ok := false
		for t in any:
			if t in tags:
				ok = true
		if not ok:
			return false
	for t in rule.get("none", []):
		if t in tags:
			return false
	if rule.has("phase") and PHASE_BY_NAME[rule.phase] != phase:
		return false
	if pressure < rule.get("min_p", -INF):
		return false
	if temp < rule.get("min_t", -INF):
		return false
	if rule.get("was_hot", false) and not was_hot:
		return false
	return true
