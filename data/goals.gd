class_name Goals
## Масштабные цели планеты. Выбираются по тегам планеты; у каждой три этапа.
## Параметры в фигурных скобках ({rare}) подставляются генератором планеты.
##
## Типы этапов:
##   stockpile_tags  — {tags: {тег: кг}} в контейнерах и баках
##   dome_env        — купол с давлением p=[мин,макс] и T t=[мин,макс] держится hold секунд
##   launch_mass     — отправить mass кг через пусковую шахту
##   launch_tag      — отправить mass кг порций с тегом tag
##   launch_exotic   — отправить mass кг порций с любым невозможным тегом
##   build_count     — построить n машин типа kind
##   discover_tags   — знать n тегов
##   discover_exotic — знать n невозможных тегов
##   discover_interactions — открыть n взаимодействий
##   sensor_network  — n датчиков, подключённых проводами
##   phasing_contained — mass кг фазирующего материала в баке из якорного материала
##   beacon_hold     — маяк под давлением pressure держится hold секунд

const TEMPLATES := {
	"colony": {"n": "Подготовка к заселению",
		"desc": "Сделать планету пригодной для первых поселенцев.", "w": 1.0,
		"stages": [
			{"type": "stockpile_tags", "tags": {"insulating": 15.0, "dense": 15.0},
				"desc": "Запасти изолирующие и плотные материалы для купола"},
			{"type": "dome_env", "p": [0.8, 1.4], "t": [5.0, 35.0], "hold": 60.0,
				"desc": "Удержать в куполе пригодные давление и температуру"},
			{"type": "launch_mass", "mass": 25.0,
				"desc": "Отправить на орбиту припасы для корабля поселенцев"},
		]},
	"mining": {"n": "Добывающая колония",
		"desc": "Наладить поставки редкого материала на орбиту.", "w": 1.0,
		"stages": [
			{"type": "build_count", "kind": "drill", "n": 4, "desc": "Поставить 4 бура"},
			{"type": "stockpile_tags", "tags": {"{rare}": 10.0}, "desc": "Получить и запасти материал с редким тегом"},
			{"type": "launch_tag", "tag": "{rare}", "mass": 30.0, "desc": "Отправить редкий материал на орбиту"},
		]},
	"science": {"n": "Научная станция",
		"desc": "Изучить планету и её вещества.", "w": 1.0,
		"stages": [
			{"type": "discover_tags", "n": 14, "desc": "Узнать 14 тегов"},
			{"type": "discover_interactions", "n": 8, "desc": "Открыть 8 взаимодействий"},
			{"type": "sensor_network", "n": 6, "desc": "Построить сеть из 6 подключённых датчиков"},
		]},
	"anomaly": {"n": "Исследование аномалии",
		"desc": "Понять и приручить невозможные свойства.", "w": 0.0,
		"stages": [
			{"type": "discover_exotic", "n": 3, "desc": "Узнать 3 невозможных тега"},
			{"type": "phasing_contained", "mass": 5.0, "desc": "Удержать фазирующий материал в баке из якорного"},
			{"type": "launch_exotic", "mass": 10.0, "desc": "Отправить образцы экзотики на орбиту"},
		]},
	"beacon": {"n": "Маяк",
		"desc": "Построить маяк для будущих экспедиций.", "w": 0.8,
		"stages": [
			{"type": "stockpile_tags", "tags": {"conductive": 10.0, "crystalline": 10.0},
				"desc": "Запасти проводящие и кристаллические материалы"},
			{"type": "build_count", "kind": "beacon", "n": 1, "desc": "Построить маяк"},
			{"type": "beacon_hold", "pressure": 4.0, "hold": 90.0, "desc": "Держать маяк под давлением 4 атм"},
		]},
}

## Теги, которые цель требует получить (для проверки осуществимости).
static func required_tags(goal: Dictionary) -> Array:
	var out: Array = []
	for st in goal.stages:
		if st.has("tags"):
			out.append_array(st.tags.keys())
		if st.has("tag"):
			out.append(st.tag)
		if st.type == "phasing_contained":
			out.append_array(["phasing", "anchoring"])
	return out
