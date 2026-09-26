class_name Modules
## Модули робота. Изготавливаются на фабрикаторе из любого подходящего
## материала; характеристики модуля считает ComponentStats по материалу.
##
##   cls   — класс прокачки, открывающий чертёж ("" — доступен сразу)
##   slot  — "ability" (слоты абилок), "hull" (корпус), "drill" (ручной бур)
##   active — есть активная абилка (клавиши 1–4)
##   gas   — расход давления из бортового баллона за применение
##   cd    — перезарядка, с
##   target — "point" (курсор), "self"

const MODULES := {
	"hull":       {"n": "Корпус", "cls": "", "slot": "hull", "cost": 12.0, "hard": 3.0,
		"desc": "Прочность, защита от жара/радиации/яда и объём бортового баллона — от материала."},
	"hand_drill": {"n": "Ручной бур", "cls": "", "slot": "drill", "cost": 4.0, "hard": 3.0,
		"desc": "Твёрдость бура определяет, какие залежи можно копать руками."},
	"hook":       {"n": "Пневмокрюк", "cls": "hunter", "slot": "ability", "active": true, "gas": 1.0, "cd": 1.0, "target": "point", "cost": 5.0, "hard": 3.0,
		"desc": "Трос в точку — подтянуться через расщелину или лаву. Упругий и волокнистый материал — длиннее трос."},
	"jet":        {"n": "Реактивный прыжок", "cls": "hunter", "slot": "ability", "active": true, "gas": 1.5, "cd": 1.5, "target": "point", "cost": 6.0, "hard": 3.0,
		"desc": "Импульс сжатым газом. Чем легче робот и слабее гравитация, тем дальше."},
	"shield":     {"n": "Защитная оболочка", "cls": "hunter", "slot": "ability", "cost": 6.0, "hard": 2.0,
		"desc": "Защита от жара, радиации, яда и кислоты — по свойствам материала."},
	"hand_cannon": {"n": "Ручная пневмопушка", "cls": "firekeeper", "slot": "ability", "active": true, "gas": 1.0, "cd": 0.8, "target": "point", "cost": 6.0, "hard": 4.0,
		"desc": "Стреляет выбранным материалом: в приёмник/контейнер, поджигает горючее, раскалывает хрупкие залежи."},
	"lance":      {"n": "Термокопьё", "cls": "firekeeper", "slot": "ability", "active": true, "gas": 1.0, "cd": 1.0, "target": "point", "cost": 6.0, "hard": 3.0,
		"desc": "Плавит любую залежь на месте и поджигает горючее. Материал с высокой T плавления — горячее копьё."},
	"cryo":       {"n": "Криораспылитель", "cls": "firekeeper", "slot": "ability", "active": true, "gas": 1.0, "cd": 1.5, "target": "point", "cost": 5.0, "hard": 2.0,
		"desc": "Замораживает лаву и кислоту в мост на время, гасит пожары, охлаждает груз. Изолирующий — дольше."},
	"scanner":    {"n": "Пульс-сканер", "cls": "gatherer", "slot": "ability", "active": true, "gas": 0.5, "cd": 4.0, "target": "self", "cost": 4.0, "hard": 2.0,
		"desc": "Волна показывает залежи вокруг. Светящийся материал — больше радиус."},
	"magnet":     {"n": "Магнитный захват", "cls": "gatherer", "slot": "ability", "active": true, "gas": 0.3, "cd": 1.0, "target": "self", "cost": 5.0, "hard": 2.0, "any": ["magnetic", "metallic"],
		"desc": "Притягивает порции с земли и ловит промахнувшиеся капсулы. Магнитный материал — сильнее."},
	"sampler":    {"n": "Газозаборник", "cls": "gatherer", "slot": "ability", "active": true, "gas": 0.0, "cd": 5.0, "target": "self", "cost": 5.0, "hard": 3.0,
		"desc": "Позволяет носить жидкости и газы. Применение — взять пробу атмосферы и узнать её теги."},
	"analyzer":   {"n": "Анализатор", "cls": "shaman", "slot": "ability", "active": true, "gas": 0.2, "cd": 0.5, "target": "point", "cost": 4.0, "hard": 1.5,
		"desc": "Мгновенно раскрывает теги материала под курсором (залежь, земля, машина)."},
	"predictor":  {"n": "Предсказатель реакций", "cls": "shaman", "slot": "ability", "cost": 4.0, "hard": 1.5,
		"desc": "Инспектор показывает, что выйдет из машины, и рецепты тегов."},
	"drone":      {"n": "Дрон-носильщик", "cls": "chief", "slot": "ability", "active": true, "gas": 0.5, "cd": 0.3, "target": "point", "cost": 8.0, "hard": 3.0,
		"desc": "Первое применение — машина-источник, второе — машина-получатель. Лёгкий материал — быстрее дрон."},
	"relay":      {"n": "Ретранслятор", "cls": "chief", "slot": "ability", "active": true, "gas": 0.0, "cd": 0.3, "target": "point", "cost": 5.0, "hard": 2.0,
		"desc": "Включает и выключает машину издалека. Провода дотягиваются вдвое дальше."},
	"repair":     {"n": "Ремнабор", "cls": "crafter", "slot": "ability", "active": true, "gas": 0.0, "cd": 1.0, "target": "point", "cost": 4.0, "hard": 2.0,
		"desc": "Чинит машину под курсором или робота (курсор на себе), тратит 1 кг выбранного материала."},
}

static func check_material(id: String, sub: Substance, ambient: float) -> String:
	var d: Dictionary = MODULES[id]
	if sub.phase_at(ambient) != Substance.Phase.SOLID:
		return "материал не твёрдый"
	if sub.hardness < d.get("hard", 0.0):
		return "нужна твёрдость ≥ %.1f" % d.hard
	var any: Array = d.get("any", [])
	if not any.is_empty():
		for t in any:
			if sub.has(t):
				return ""
		return "нужен тег: " + " или ".join(any.map(func(t): return MaterialTags.display(t)))
	return ""
