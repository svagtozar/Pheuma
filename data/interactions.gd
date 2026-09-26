class_name Interactions
## Таблица взаимодействий тегов. Теги не смешиваются: тег применяемого
## (реагента — или планеты, для всего, что лежит открыто) действует на тег
## обрабатываемого материала.
##
##   a       — тег применяемого (тег материала-реагента или тег планеты)
##   b       — тег обрабатываемого
##   add/remove — изменение тегов обрабатываемого
##   heat    — нагрев обрабатываемого, °C
##   gas     — доля массы, уходящая в газ (в обработчике — в его газовый узел)
##   consume — доля реагента, которая расходуется (на единицу массы цели ×0.5)

const RULES := [
	# кислоты и щёлочи
	{"a": "acidic", "b": "alkaline", "remove": ["alkaline"], "add": ["hygroscopic"], "heat": 30.0, "consume": 1.0},
	{"a": "alkaline", "b": "acidic", "remove": ["acidic"], "add": ["hygroscopic"], "heat": 30.0, "consume": 1.0},
	{"a": "acidic", "b": "metallic", "add": ["porous"], "heat": 20.0, "gas": 0.1, "consume": 0.5},
	{"a": "acidic", "b": "organic", "add": ["toxic", "volatile"], "consume": 0.5},
	{"a": "acidic", "b": "porous", "add": ["hygroscopic"], "consume": 0.3},
	{"a": "alkaline", "b": "organic", "add": ["fibrous"], "consume": 0.5},
	{"a": "alkaline", "b": "crystalline", "add": ["porous"], "consume": 0.3},
	# окисление и горение
	{"a": "oxidizer", "b": "toxic", "remove": ["toxic"], "add": ["acidic"], "consume": 0.5},
	{"a": "oxidizer", "b": "flammable", "remove": ["flammable"], "heat": 400.0, "gas": 0.3, "consume": 1.0},
	{"a": "oxidizer", "b": "metallic", "add": ["brittle"], "consume": 0.3},
	{"a": "pyrophoric", "b": "flammable", "remove": ["flammable"], "heat": 300.0, "gas": 0.2, "consume": 0.5},
	{"a": "flammable", "b": "dense", "add": ["metallic"], "heat": 200.0, "consume": 1.0},
	# пропитка, связка, поглощение
	{"a": "volatile", "b": "porous", "add": ["flammable"], "consume": 0.8},
	{"a": "hygroscopic", "b": "volatile", "remove": ["volatile"], "consume": 0.5},
	{"a": "elastic", "b": "brittle", "remove": ["brittle"], "consume": 0.5},
	{"a": "fibrous", "b": "brittle", "add": ["elastic"], "consume": 0.5},
	{"a": "toxic", "b": "organic", "add": ["toxic"], "consume": 0.2},
	{"a": "magnetic", "b": "metallic", "add": ["magnetic"], "consume": 0.0},
	{"a": "luminous", "b": "hygroscopic", "add": ["organic"], "consume": 0.0},
	# невозможное
	{"a": "luminous", "b": "crystalline", "add": ["resonant"], "consume": 0.2},
	{"a": "radioactive", "b": "organic", "add": ["self_replicating", "toxic"], "consume": 0.1},
	{"a": "antigravitic", "b": "dense", "remove": ["dense"], "add": ["void"], "consume": 0.5},
	{"a": "self_replicating", "b": "crystalline", "add": ["mimetic"], "consume": 0.3},
	{"a": "void", "b": "luminous", "add": ["chrono_lagged"], "consume": 0.3},
	{"a": "resonant", "b": "porous", "add": ["echoing"], "consume": 0.2},
	{"a": "resonant", "b": "magnetic", "add": ["tethered"], "consume": 0.2},
	{"a": "anchoring", "b": "phasing", "remove": ["phasing"], "consume": 0.2},
	{"a": "phasing", "b": "dense", "remove": ["dense"], "add": ["porous"], "consume": 0.3},
	# среда планеты → открыто лежащие порции
	{"a": "acid_rain", "b": "metallic", "add": ["porous"], "env": true},
	{"a": "acid_rain", "b": "organic", "add": ["toxic"], "env": true},
	{"a": "acid_rain", "b": "porous", "add": ["acidic"], "env": true},
	{"a": "oceanic", "b": "porous", "add": ["organic"], "env": true},
	{"a": "oxidizing_atmosphere", "b": "metallic", "add": ["brittle"], "env": true},
	{"a": "toxic_atmosphere", "b": "organic", "add": ["toxic"], "env": true},
	{"a": "radiation", "b": "organic", "add": ["self_replicating"], "env": true},
	{"a": "strong_magnetosphere", "b": "metallic", "add": ["magnetic"], "env": true},
	{"a": "frozen", "b": "elastic", "add": ["brittle"], "env": true},
	{"a": "volcanic", "b": "organic", "add": ["flammable"], "env": true},
	{"a": "inverted_thermodynamics", "b": "volatile", "add": ["thermo_inverted"], "env": true},
	{"a": "temporal_drift", "b": "crystalline", "add": ["chrono_lagged"], "env": true},
	{"a": "fungal_biosphere", "b": "organic", "add": ["fibrous"], "env": true},
	{"a": "singularity", "b": "volatile", "add": ["superfluid"], "env": true},
	# холод, тугоплавкость, самосборка
	{"a": "cryogenic", "b": "volatile", "remove": ["volatile"], "add": ["dense"], "heat": -80.0, "consume": 0.5},
	{"a": "cryogenic", "b": "flammable", "remove": ["flammable"], "heat": -60.0, "consume": 0.4},
	{"a": "self_assembling", "b": "brittle", "remove": ["brittle"], "consume": 0.3},
	{"a": "refractory", "b": "porous", "add": ["refractory"], "heat": 50.0, "consume": 0.6},
]

static func key(rule: Dictionary) -> String:
	return "%s>%s" % [rule.a, rule.b]

## Применить теги-«применяемые» к тегам цели. Правила срабатывают по исходным
## тегам цели, результаты применяются по очереди (новый тег вытесняет несовместимые).
static func apply(applied_tags: Array, target_tags: Array, env_only: bool = false) -> Dictionary:
	var tags: Array = target_tags.duplicate()
	var res := {"tags": tags, "heat": 0.0, "gas": 0.0, "consume": 0.0, "keys": []}
	for r in RULES:
		if env_only != r.get("env", false):
			continue
		if not (r.a in applied_tags and r.b in target_tags):
			continue
		for t in r.get("remove", []):
			tags.erase(t)
		for t in r.get("add", []):
			tags = MaterialTags.add_tag(tags, t)
		res.heat += r.get("heat", 0.0)
		res.gas = max(res.gas, r.get("gas", 0.0))
		res.consume = max(res.consume, r.get("consume", 0.0))
		res.keys.append(key(r))
	tags.sort()
	res.tags = tags
	return res
