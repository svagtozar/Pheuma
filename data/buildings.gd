class_name Buildings
## Постройки. Рецепт задаёт не конкретный материал, а требования к свойствам:
## любой подходящий твёрдый материал из инвентаря.
##
##   cost   — кг материала
##   hard   — минимальная твёрдость материала
##   any    — материал должен иметь хотя бы один из тегов
##   gas    — объём газового узла (0 — без газа)
##   cap    — вместимость по грузу, кг
##   cat    — раздел палитры
##   locked — открывается узлом прокачки
##   process — id из Processes
##   min_p  — материал должен выдерживать это давление (предел из ComponentStats)

const CATS := ["Добыча и хранение", "Пневматика", "Обработка", "Логика", "Цели", "Сборные сооружения"]

const KINDS := {
	"drill":      {"n": "Бур", "cat": 0, "cost": 6.0, "hard": 3.0, "cap": 5.0, "desc": "Ставится на залежь. Берёт материал не твёрже себя. Выход — вперёд."},
	"container":  {"n": "Контейнер", "cat": 0, "cost": 4.0, "hard": 1.5, "cap": 60.0, "desc": "Открытый. Летучее испаряется, газ улетает. Выдаёт вперёд, если включён сквозной режим или сигнал."},
	"tank":       {"n": "Бак", "cat": 0, "cost": 8.0, "hard": 3.5, "cap": 60.0, "gas": 6.0, "sealed": true, "desc": "Закрытый. Держит газ и летучее. Стенки должны выдерживать давление."},
	"receiver":   {"n": "Приёмник", "cat": 0, "cost": 5.0, "hard": 2.5, "cap": 30.0, "desc": "Ловит капсулы пневмопушек и выдаёт груз вперёд."},
	"fabricator": {"n": "Фабрикатор", "cat": 0, "cost": 10.0, "hard": 3.0, "desc": "Изготавливает модули и детали робота. Подойдите и нажмите F."},
	"pump":       {"n": "Насос", "cat": 1, "cost": 6.0, "hard": 3.0, "gas": 1.0, "desc": "Качает атмосферу в сеть. В разреженной атмосфере слаб."},
	"pipe":       {"n": "Труба", "cat": 1, "cost": 1.0, "hard": 2.0, "gas": 1.0, "desc": "Соединяет газовые узлы. Лопается выше предельного давления материала."},
	"valve":      {"n": "Клапан", "cat": 1, "cost": 2.0, "hard": 2.5, "gas": 1.0, "desc": "Открыт, пока на входе сигнал (без провода — всегда открыт)."},
	"cannon":     {"n": "Пневмопушка", "cat": 1, "cost": 10.0, "hard": 4.0, "min_p": 4.0, "gas": 3.0, "cap": 10.0, "desc": "Копит давление и стреляет капсулой в связанный приёмник (L — связать)."},
	"filter":     {"n": "Фильтр", "cat": 2, "cost": 4.0, "hard": 2.0, "cap": 10.0, "process": "filter"},
	"crusher":    {"n": "Дробилка", "cat": 2, "cost": 8.0, "hard": 4.0, "cap": 10.0, "gas": 1.0, "process": "crusher"},
	"furnace":    {"n": "Печь", "cat": 2, "cost": 8.0, "hard": 3.0, "cap": 10.0, "gas": 2.0, "process": "furnace"},
	"condenser":  {"n": "Конденсатор", "cat": 2, "cost": 8.0, "hard": 3.0, "cap": 10.0, "gas": 1.0, "process": "condenser"},
	"treater":    {"n": "Обработчик", "cat": 2, "cost": 8.0, "hard": 3.0, "cap": 10.0, "gas": 1.0, "process": "treater"},
	"compressor": {"n": "Компрессор", "cat": 2, "cost": 10.0, "hard": 5.0, "cap": 10.0, "gas": 2.0, "process": "compressor", "locked": true},
	"decompressor": {"n": "Декомпрессор", "cat": 2, "cost": 8.0, "hard": 3.5, "cap": 10.0, "gas": 2.0, "process": "decompressor", "locked": true},
	"distiller":  {"n": "Дистиллятор", "cat": 2, "cost": 8.0, "hard": 3.0, "cap": 10.0, "gas": 1.0, "process": "distiller", "locked": true},
	"centrifuge": {"n": "Центрифуга", "cat": 2, "cost": 8.0, "hard": 4.0, "cap": 10.0, "gas": 1.0, "process": "centrifuge", "locked": true},
	"magnet_sep": {"n": "Магн. сепаратор", "cat": 2, "cost": 6.0, "hard": 3.0, "cap": 10.0, "gas": 1.0, "process": "magnet_sep", "locked": true},
	"electrolyzer": {"n": "Электролизёр", "cat": 2, "cost": 8.0, "hard": 3.0, "any": ["conductive", "metallic"], "cap": 10.0, "gas": 1.0, "process": "electrolyzer", "locked": true},
	"sinter":     {"n": "Спекатель", "cat": 2, "cost": 8.0, "hard": 4.0, "cap": 10.0, "gas": 1.0, "process": "sinter", "locked": true},
	"irradiator": {"n": "Облучатель", "cat": 2, "cost": 8.0, "hard": 3.0, "cap": 10.0, "gas": 1.0, "process": "irradiator", "locked": true},
	"loom":       {"n": "Ткацкий станок", "cat": 2, "cost": 6.0, "hard": 2.0, "cap": 10.0, "gas": 1.0, "process": "loom", "locked": true},
	"sensor":     {"n": "Датчик", "cat": 3, "cost": 1.0, "hard": 1.0, "desc": "Смотрит на машину впереди: уровень, тег, давление или температура."},
	"gate_and":   {"n": "И", "cat": 3, "cost": 1.0, "hard": 1.0, "desc": "Сигнал, если на обоих входах сигнал."},
	"gate_or":    {"n": "ИЛИ", "cat": 3, "cost": 1.0, "hard": 1.0, "desc": "Сигнал, если хотя бы на одном входе сигнал."},
	"gate_not":   {"n": "НЕ", "cat": 3, "cost": 1.0, "hard": 1.0, "desc": "Сигнал, если на входе нет сигнала."},
	"battery_section": {"n": "Секция пневмобатареи", "cat": 5, "cost": 8.0, "hard": 4.5, "min_p": 5.0, "gas": 3.0, "desc": "Четыре секции квадратом 2×2 — тяжёлая пушка: 20 кг за выстрел, дальность ×2.2. Ведёт главная (левая верхняя) секция."},
	"catch_net":  {"n": "Ловчая сеть", "cat": 5, "cost": 2.0, "hard": 1.0, "desc": "Капсула, упавшая на сеть, скатывается в приёмник по соединённым сетям. Упругий или волокнистый материал — длиннее."},
	"warehouse_section": {"n": "Секция склада", "cat": 5, "cost": 5.0, "hard": 2.5, "cap": 20.0, "desc": "Четыре секции квадратом 2×2 собираются в склад на 320 кг."},
	"macro":      {"n": "Макроблок", "cat": -1, "cost": 0.0, "hard": 0.0, "desc": "Свёрнутый макроблок."},
	"launch_silo": {"n": "Пусковая шахта", "cat": 4, "cost": 20.0, "hard": 5.0, "min_p": 6.5, "gas": 12.0, "cap": 40.0, "desc": "Отправляет груз на орбиту при давлении ≥ 6 атм."},
	"dome":       {"n": "Купол", "cat": 4, "cost": 20.0, "hard": 3.0, "gas": 20.0, "cap": 60.0, "sealed": true, "desc": "Закрытый объём для поселенцев. Изолирующий материал держит тепло; печи рядом греют, конденсаторы охлаждают."},
	"beacon":     {"n": "Маяк", "cat": 4, "cost": 15.0, "hard": 3.0, "any": ["conductive", "crystalline"], "gas": 4.0, "desc": "Работает под давлением. Из проводящего или кристаллического материала."},
}

static func info(kind: String) -> Dictionary:
	return KINDS[kind]

static func name_of(kind: String) -> String:
	var d: Dictionary = KINDS[kind]
	if d.has("process"):
		return Processes.PROCESSES[d.process].n
	return d.n

static func desc_of(kind: String) -> String:
	var d: Dictionary = KINDS[kind]
	if d.has("process"):
		return Processes.PROCESSES[d.process].desc
	return d.get("desc", "")

## Почему материал не подходит ("" — подходит).
static func check_material(kind: String, sub: Substance, ambient: float) -> String:
	var d: Dictionary = KINDS[kind]
	if sub.phase_at(ambient) != Substance.Phase.SOLID:
		return "материал не твёрдый при температуре среды"
	if sub.hardness < d.get("hard", 0.0):
		return "нужна твёрдость ≥ %.1f" % d.hard
	if d.has("min_p"):
		var mp: float = ComponentStats.compute(kind, sub).max_p
		if mp < d.min_p:
			return "материал держит только %.1f атм, нужно ≥ %.1f (подойдёт твёрже, упругий или плотный)" % [mp, d.min_p]
	var any: Array = d.get("any", [])
	if not any.is_empty():
		var ok := false
		for t in any:
			if sub.has(t):
				ok = true
		if not ok:
			return "нужен тег: " + " или ".join(any.map(func(t): return MaterialTags.display(t)))
	return ""
