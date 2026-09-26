class_name RobotState
extends RefCounted
## Состояние робота: здоровье, бортовой баллон, инвентарь, модули, прокачка, знания.

const BASE_SLOTS := 3
const BASE_TANK := 10.0
const BASE_MASS := 50.0

var pos := Vector2.ZERO               # в клетках (центр клетки = x + 0.5)
var hp := 100.0
var tank := 5.0                       # газ в бортовом баллоне
var inventory := {}                   # id материала → Portion
var selected := ""                    # выбранный материал
var modules: Array = []               # изготовленные, но не установленные модули
var equipped: Array = []              # установленные модули абилок
var hull = null                       # модуль-корпус
var drill = null                      # ручной бур
var cooldowns := {}
var mine_progress := 0.0
var last_safe := Vector2i.ZERO

var xp := {}
var knowledge := 2
var learned := {}
var blueprints := {"hull": true, "hand_drill": true}
var unlocked := {}                    # постройки
var known_tags := {}
var analyzed := {}                    # id материалов, которых касались (физика известна)
var sub_known := {}                   # id материала → {тег: true (есть) | false (исключён)}
var last_probe := ""                  # текст последней пробы (для карточки материала)
var focus_sub := ""                   # залежь, которой коснулись (Z): её карточка в инвентаре
var known_interactions := {}
var bonus_slots := 0                  # награды за этапы
var _next_module := 1

func _init() -> void:
	for c in SkillTree.CLASS_ORDER:
		xp[c] = 0.0
	for k in Buildings.KINDS:
		if not Buildings.KINDS[k].get("locked", false):
			unlocked[k] = true

func cell() -> Vector2i:
	return Vector2i(floori(pos.x), floori(pos.y))

## Сумма пассивных бонусов изученных узлов.
func passive(key: String) -> float:
	var s := 0.0
	for id in learned:
		s += float(SkillTree.node(id).get("passive", {}).get(key, 0.0))
	return s

func slots() -> int:
	return BASE_SLOTS + int(passive("slots")) + bonus_slots

func max_hp() -> float:
	return hull.stats.max_hp * 1.2 if hull != null else 60.0

func tank_cap() -> float:
	var flex: float = hull.stats.flex if hull != null else 1.0
	return BASE_TANK * flex * (1.0 + passive("tank_cap"))

func mining_hardness() -> float:
	return drill.stats.hardness if drill != null else 2.5

func shield() -> Dictionary:
	var s := {"heat": 0.0, "radiation": 0.0, "toxic": 0.0, "acid": 0.0}
	var sources: Array = []
	if hull != null:
		sources.append([hull, 0.5])
	var sh = module("shield")
	if sh != null:
		sources.append([sh, 1.0])
	for pair in sources:
		var st: Dictionary = pair[0].stats
		var f: float = pair[1]
		s.heat = max(s.heat, st.shield_heat * f)
		s.radiation = max(s.radiation, st.shield_radiation * f)
		s.toxic = max(s.toxic, st.shield_toxic * f)
		s.acid = max(s.acid, st.shield_acid * f)
	var r := passive("hazard_resist")
	for k in s:
		s[k] = clamp(s[k] + r * (1.0 - s[k]), 0.0, 0.95)
	return s

func module(kind: String):
	for m in equipped:
		if m.kind == kind:
			return m
	return null

func has_module(kind: String) -> bool:
	return module(kind) != null

func carried_mass() -> float:
	var s := 0.0
	for p in inventory.values():
		s += p.mass
	return s

func total_mass() -> float:
	var m := BASE_MASS + carried_mass() * 0.3
	for mod in equipped:
		m += mod.stats.mass
	if hull != null:
		m += hull.stats.mass
	return max(10.0, m)

func can_carry(p: Portion) -> bool:
	return p.phase() == Substance.Phase.SOLID or has_module("sampler")

func add_item(p: Portion) -> void:
	if p.mass <= 0.0:
		return
	var id := p.substance.id
	if inventory.has(id):
		inventory[id].absorb(p)
	else:
		inventory[id] = p.copy()
	if selected == "":
		selected = id

func mass_of(id: String) -> float:
	return inventory[id].mass if inventory.has(id) else 0.0

func take_item(id: String, m: float) -> Portion:
	if not inventory.has(id):
		return null
	var p: Portion = inventory[id]
	var out := p.split(m)
	if p.mass <= 0.001:
		inventory.erase(id)
		if selected == id:
			selected = "" if inventory.is_empty() else inventory.keys()[0]
	return out

func cycle_selected(dir: int) -> void:
	var keys: Array = inventory.keys()
	if keys.is_empty():
		selected = ""
		return
	keys.sort()
	var i := keys.find(selected)
	selected = keys[(i + dir + keys.size()) % keys.size()]

func damage(amount: float) -> void:
	hp -= amount

func new_module(kind: String, sub: Substance, quality: float) -> Dictionary:
	var sk := kind if kind in ["hull", "hand_drill"] else "module"
	var m := {"uid": _next_module, "kind": kind, "sub": sub, "q": quality, "stats": ComponentStats.compute(sk, sub, quality)}
	_next_module += 1
	return m

## Установить модуль из запаса. Возвращает текст ошибки или "".
func equip(uid: int) -> String:
	var m = null
	for x in modules:
		if x.uid == uid:
			m = x
	if m == null:
		return "нет такого модуля"
	match Modules.MODULES[m.kind].slot:
		"hull":
			if hull != null:
				modules.append(hull)
			hull = m
			hp = min(hp, max_hp())
		"drill":
			if drill != null:
				modules.append(drill)
			drill = m
		_:
			if equipped.size() >= slots():
				return "нет свободного слота"
			if has_module(m.kind):
				return "такой модуль уже стоит"
			equipped.append(m)
	modules.erase(m)
	return ""

func unequip(uid: int) -> void:
	for m in equipped:
		if m.uid == uid:
			equipped.erase(m)
			modules.append(m)
			return
