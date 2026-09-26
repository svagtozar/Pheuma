class_name SkillTree
## Шесть классов по ассоциации с ролями в первобытном обществе.
## Узлы открываются очками знаний, если набран опыт класса и изучен предыдущий узел.
##
##   blueprint — открывает чертёж модуля
##   unlock    — открывает постройки
##   passive   — бонусы (ключ → значение, складываются)

const CLASSES := {
	"gatherer":   {"n": "Собиратель", "desc": "Разведка и добыча", "col": Color(0.55, 0.80, 0.35)},
	"hunter":     {"n": "Охотник", "desc": "Мобильность, опасности, меткость", "col": Color(0.85, 0.45, 0.30)},
	"crafter":    {"n": "Ремесленник", "desc": "Изготовление и качество деталей", "col": Color(0.80, 0.65, 0.35)},
	"firekeeper": {"n": "Хранитель огня", "desc": "Тепло и давление", "col": Color(0.95, 0.40, 0.15)},
	"shaman":     {"n": "Шаман", "desc": "Знание тегов и взаимодействий", "col": Color(0.65, 0.45, 0.90)},
	"chief":      {"n": "Вождь", "desc": "Автоматизация и цели", "col": Color(0.35, 0.65, 0.90)},
}

const CLASS_ORDER := ["gatherer", "hunter", "crafter", "firekeeper", "shaman", "chief"]

const NODES := [
	{"id": "g1", "cls": "gatherer", "n": "Чутьё залежей", "cost": 1, "xp": 0, "blueprint": "scanner", "passive": {"mine_speed": 0.5},
		"desc": "Ручная добыча +50%. Чертёж: пульс-сканер."},
	{"id": "g2", "cls": "gatherer", "n": "Магнитная хватка", "cost": 2, "xp": 15, "blueprint": "magnet", "unlock": ["magnet_sep"],
		"desc": "Чертёж: магнитный захват. Постройка: магнитный сепаратор."},
	{"id": "g3", "cls": "gatherer", "n": "Богатые жилы", "cost": 3, "xp": 40, "blueprint": "seismic_charge", "unlock": ["centrifuge"], "passive": {"drill_yield": 0.5},
		"desc": "Буры добывают на 50% больше. Чертёж: сейсмозаряд. Постройка: центрифуга."},
	{"id": "g4", "cls": "gatherer", "n": "Пробы воздуха", "cost": 3, "xp": 80, "blueprint": "sampler",
		"desc": "Чертёж: газозаборник."},
	{"id": "h1", "cls": "hunter", "n": "Пневмокрюк", "cost": 1, "xp": 0, "blueprint": "hook",
		"desc": "Чертёж: пневмокрюк."},
	{"id": "h2", "cls": "hunter", "n": "Толстая шкура", "cost": 2, "xp": 15, "blueprint": "shield", "passive": {"hazard_resist": 0.2},
		"desc": "Урон от среды −20%. Чертёж: защитная оболочка."},
	{"id": "h3", "cls": "hunter", "n": "Прыжок", "cost": 3, "xp": 40, "blueprint": "jet",
		"desc": "Чертёж: реактивный прыжок."},
	{"id": "h4", "cls": "hunter", "n": "Глаз охотника", "cost": 3, "xp": 80, "passive": {"aim": 0.6},
		"desc": "Разброс пушек от бурь и магнитосферы −60%."},
	{"id": "c1", "cls": "crafter", "n": "Мастер", "cost": 1, "xp": 0, "blueprint": "repair", "passive": {"quality": 0.15},
		"desc": "Качество деталей +15%. Чертёж: ремнабор."},
	{"id": "c2", "cls": "crafter", "n": "Лишний слот", "cost": 2, "xp": 15, "unlock": ["loom"], "passive": {"slots": 1},
		"desc": "+1 слот модуля. Постройка: ткацкий станок."},
	{"id": "c3", "cls": "crafter", "n": "Спекание", "cost": 3, "xp": 40, "blueprint": "field_forge", "unlock": ["sinter"], "passive": {"quality": 0.15},
		"desc": "Качество +15%. Чертёж: походная кузня. Постройка: спекатель."},
	{"id": "c4", "cls": "crafter", "n": "Бережливость", "cost": 3, "xp": 80, "passive": {"slots": 1, "build_discount": 0.25},
		"desc": "+1 слот, постройки дешевле на 25%."},
	{"id": "f1", "cls": "firekeeper", "n": "Раздувание", "cost": 1, "xp": 0, "blueprint": "hand_cannon", "passive": {"pump_rate": 0.5},
		"desc": "Насосы +50%. Чертёж: ручная пневмопушка."},
	{"id": "f2", "cls": "firekeeper", "n": "Жар", "cost": 2, "xp": 15, "blueprint": "lance", "unlock": ["compressor"], "passive": {"furnace_t": 200.0},
		"desc": "Печи горячее на 200 °C. Чертёж: термокопьё. Постройка: компрессор."},
	{"id": "f3", "cls": "firekeeper", "n": "Укротитель огня", "cost": 3, "xp": 40, "blueprint": "cryo", "unlock": ["decompressor"], "passive": {"safe_fire": 1},
		"desc": "Горючее в руках не вспыхивает. Чертёж: криораспылитель. Постройка: декомпрессор."},
	{"id": "f4", "cls": "firekeeper", "n": "Высокое давление", "cost": 3, "xp": 80, "passive": {"tank_cap": 0.5, "compress_bonus": 2.0},
		"desc": "Бортовой баллон +50%, компрессоры давят сильнее."},
	{"id": "f5", "cls": "firekeeper", "n": "Вечный холод", "cost": 3, "xp": 110, "blueprint": "cold_pack", "unlock": ["cryochamber"],
		"desc": "Чертёж: холодильный ранец. Постройка: криокамера — криогенное и сверхтекучее."},
	{"id": "s1", "cls": "shaman", "n": "Анализатор", "cost": 1, "xp": 0, "blueprint": "analyzer", "unlock": ["distiller"],
		"desc": "Чертёж: анализатор. Постройка: дистиллятор."},
	{"id": "s2", "cls": "shaman", "n": "Чутьё веществ", "cost": 2, "xp": 15, "unlock": ["electrolyzer"], "passive": {"auto_analyze": 1},
		"desc": "Подобранные материалы раскрываются сами. Постройка: электролизёр."},
	{"id": "s3", "cls": "shaman", "n": "Предвидение", "cost": 3, "xp": 40, "blueprint": "predictor", "unlock": ["irradiator"],
		"desc": "Чертёж: предсказатель реакций. Постройка: облучатель."},
	{"id": "s4", "cls": "shaman", "n": "Знание невозможного", "cost": 3, "xp": 80, "passive": {"exotic_insight": 1},
		"desc": "Невозможные теги дают вдвое больше знаний."},
	{"id": "s5", "cls": "shaman", "n": "Созвучие", "cost": 3, "xp": 110, "blueprint": "tuning_fork", "unlock": ["resonator"],
		"desc": "Чертёж: камертон. Постройка: резонатор — кристалл, собирающий сам себя."},
	{"id": "k1", "cls": "chief", "n": "Порядок", "cost": 1, "xp": 0, "blueprint": "relay", "passive": {"machine_limit": 30},
		"desc": "Лимит машин +30. Чертёж: ретранслятор."},
	{"id": "k2", "cls": "chief", "n": "Носильщики", "cost": 2, "xp": 15, "blueprint": "drone",
		"desc": "Чертёж: дрон-носильщик."},
	{"id": "k3", "cls": "chief", "n": "Длинные связи", "cost": 3, "xp": 40, "passive": {"wire_range": 0.5, "drones": 1},
		"desc": "Провода длиннее на 50%, +1 дрон."},
	{"id": "k4", "cls": "chief", "n": "Лидер экспедиции", "cost": 3, "xp": 80, "passive": {"goal_speed": 0.5, "silo_bonus": 2.0},
		"desc": "Удержание в этапах цели идёт быстрее, пусковой шахте нужно меньше давления."},
]

static func node(id: String) -> Dictionary:
	for n in NODES:
		if n.id == id:
			return n
	return {}

static func nodes_of(cls: String) -> Array:
	return NODES.filter(func(n): return n.cls == cls)

static func prev_of(id: String) -> String:
	var n := node(id)
	var list := nodes_of(n.cls)
	var i := list.find(n)
	return "" if i <= 0 else list[i - 1].id
