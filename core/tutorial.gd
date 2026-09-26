class_name Tutorial
extends RefCounted
## Пошаговое обучение. Каждый шаг — задание и проверка по состоянию мира.
## Учебная планета спокойная: плотная атмосфера (насосы сильные), низкая
## гравитация (пушки бьют далеко), без опасностей.

const PLANET_TAGS := ["dense_atmosphere", "low_gravity", "tidally_locked"]
const SEED := 20260926

const STEPS := [
	{"id": "move", "title": "Движение",
		"text": "Походите по планете: WASD или стрелки. Колесо мыши — масштаб.",
		"hint": "Отойдите на несколько клеток от капсулы."},
	{"id": "mine", "title": "Добыча",
		"text": "Подойдите к цветной залежи и удерживайте E. Накопайте 3 кг местного материала.",
		"hint": "Залежи — цветные пятна. Серые точки вдали — залежи, которые вы ещё не разглядели."},
	{"id": "analyze", "title": "Касание и пробы",
		"text": "Теги материала скрыты. Нажмите Z у залежи — касание покажет видимое. Потом выберите материал в инвентаре и сделайте пробу (Нагрев, Капля, Магнит, Ток, Счётчик).",
		"hint": "Каждая проба тратит 0.5 кг образца и говорит «есть» или «нет» про свой набор тегов. Остальное выдаст поведение материала в машинах. Новые теги дают знания."},
	{"id": "fabricator", "title": "Фабрикатор",
		"text": "Откройте постройки (B) и поставьте фабрикатор рядом с собой. ЛКМ — поставить, R — повернуть.",
		"hint": "Каждая постройка делается из материала и наследует его свойства — смотрите подсказку на кнопке."},
	{"id": "learn", "title": "Прокачка",
		"text": "Откройте прокачку (K) и изучите первый узел любого класса.",
		"hint": "Шесть классов. Узлы открывают чертежи модулей, постройки и бонусы."},
	{"id": "module", "title": "Модуль",
		"text": "Встаньте у фабрикатора, нажмите F, изготовьте модуль по открытому чертежу и установите его.",
		"hint": "Активные модули срабатывают клавишами 1–6 и тратят газ из бортового баллона (G — подкачать)."},
	{"id": "drill", "title": "Бур и контейнер",
		"text": "Поставьте бур на залежь, а перед ним (по стрелке) — контейнер. Дождитесь, пока в контейнер пойдёт материал.",
		"hint": "Машины передают груз соседу по стрелке выхода. Вход — сзади или сбоку."},
	{"id": "pressure", "title": "Давление",
		"text": "Поставьте пневмопушку и насос вплотную к ней. Доведите давление в пушке до 2 атм.",
		"hint": "Насос качает атмосферу. Соседние газовые машины соединяются сами; трубы продлевают сеть."},
	{"id": "cannon", "title": "Пневмопушка",
		"text": "Поставьте приёмник в нескольких клетках, нажмите L: клик по пушке, затем по приёмнику. Положите груз в пушку (Q) или подведите бур.",
		"hint": "Дальность растёт с давлением. Плотный груз летит короче, на ветру капсулы сносит."},
	{"id": "process", "title": "Обработка",
		"text": "Поставьте дробилку, печь или другую машину обработки и пропустите через неё груз.",
		"hint": "Машины меняют теги материала. Новые теги узнаются сразу и дают знания."},
	{"id": "logic", "title": "Логика",
		"text": "Поставьте датчик и проведите провод (V): клик по датчику, затем по машине, которой он будет управлять.",
		"hint": "ЛКМ по проводу — путевая точка, её можно тянуть; ПКМ — удалить."},
	{"id": "route", "title": "Маршруты пушек",
		"text": "Выберите пушку (ЛКМ), в инспекторе выберите тег маршрута и нажмите «Маршрут → выбрать цель», затем кликните по другому приёмнику.",
		"hint": "Груз с этим тегом полетит в свою цель, остальное — в цель по умолчанию. Так пушки сортируют грузы."},
	{"id": "assembly", "title": "Сборное сооружение",
		"text": "Соберите склад или пневмобатарею: четыре секции квадратом 2×2 (раздел «Сборные сооружения»).",
		"hint": "Батарея стреляет 20 кг на двойную дальность, но ей нужно больше насосов."},
	{"id": "macro", "title": "Макроблок",
		"text": "Нажмите M, протяните рамку по группе машин и выберите «Сохранить в библиотеку».",
		"hint": "Макроблок помнит настройки, провода и маршруты; библиотека общая для всех планет."},
	{"id": "collapse", "title": "Свёртка",
		"text": "Сверните схему: M → рамка → «Свернуть на месте», или в палитре (B) поставьте макроблок «Свёрнутым».",
		"hint": "Сворачиваются схемы без буров и сборных сооружений. Входы, выходы, газ и провода — на сторонах клетки; «Развернуть» в инспекторе вернёт машины."},
	{"id": "goal", "title": "Цель планеты",
		"text": "Справа вверху — цель планеты из трёх этапов. Обучение закончено: дальше — сами! Нажмите «Готово».",
		"hint": "Shift+N — новая планета со случайными тегами. H — вся справка."},
]

var step := 0
var done := false
var macros_made := 0
var acknowledged := false
var _start_pos := Vector2.ZERO
var _start_analyzed := 0

func _init(w: World) -> void:
	_begin(w)

static func setup_world(w: World) -> void:
	w.robot.add_item(Portion.new(w.starter, 80.0, w.planet.ambient_temp))
	w.robot.knowledge += 3
	w.log_event(w.planet.spawn, "Обучение: следуйте заданиям в верхней панели")

func current() -> Dictionary:
	return STEPS[min(step, STEPS.size() - 1)]

func _begin(w: World) -> void:
	_start_pos = w.robot.pos
	_start_analyzed = w.robot.analyzed.size()

func skip(w: World) -> void:
	_advance(w)

## Проверить текущий шаг; вернуть true, если он только что выполнен.
func update(w: World) -> bool:
	if done:
		return false
	if check(w, current().id):
		_advance(w)
		return true
	return false

func _advance(w: World) -> void:
	step += 1
	if step >= STEPS.size():
		done = true
		step = STEPS.size() - 1
	_begin(w)

func check(w: World, id: String) -> bool:
	var r := w.robot
	match id:
		"move":
			return r.pos.distance_to(_start_pos) > 4.0
		"mine":
			for k in r.inventory:
				if k != w.starter.id and r.inventory[k].mass >= 3.0:
					return true
			return false
		"analyze":
			return r.last_probe != "" and r.analyzed.size() > _start_analyzed
		"fabricator":
			return not w.machines_of("fabricator").is_empty()
		"learn":
			return not r.learned.is_empty()
		"module":
			return not r.equipped.is_empty()
		"drill":
			for m in w.machines.values():
				if m.kind == "container" and not m.items.is_empty():
					for d in Machine.DIRS:
						var n = w.machine_at(m.cell + d)
						if n != null and n.kind == "drill":
							return true
			return false
		"pressure":
			for m in w.machines_of("cannon"):
				if w.gas.pressure(m.id) >= 2.0:
					return true
			return false
		"cannon":
			return w.stats.hits > 0
		"process":
			return w.stats.processed > 0
		"logic":
			return not w.logic.wires.is_empty()
		"route":
			for m in w.machines.values():
				if m is Cannon and not m.config.get("routes", []).is_empty():
					return true
			return false
		"assembly":
			for m in w.machines.values():
				if m.master_id == m.id:
					return true
			return false
		"macro":
			return macros_made > 0
		"collapse":
			return not w.machines_of("macro").is_empty()
		"goal":
			return acknowledged
	return false
