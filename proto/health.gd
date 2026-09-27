class_name ProtoHealth
extends Node
## Прочность корпуса робота в 3D-прототипе.
##   Урон: жидкости (лава и перегретое — жар, криожидкости — холод, кислота, яд,
##   радиоактивное), среда планеты (те же правила, что в 2D World._tick_world_hazards;
##   под сводом кислотный дождь и жар неба не достают) и падения (скорость удара
##   растёт с гравитацией планеты).
##   Защита — из материала корпуса (ComponentStats, как в 2D: корпус даёт половину
##   своей защиты); выше предела нагрева корпуса жар бьёт вдвое, упругий корпус
##   смягчает удар.
##   Починка: у завода — сама, H / D-pad → (держать; в стройке эта кнопка листает
##   детали) — материалами из груза
##   (металл и твёрдое чинят лучше).
##   Поломка: робот оседает, через пару секунд собирается на базе, груз потерян.
## Данные для HUD и звука «утиные»: robot.get_meta("health") — этот узел.

signal hit(amount: float, kind: String)
signal wrecked
signal restored

const REPAIR := &"repair"
const SAFE_FALL_V := 7.5       # м/с: мягче — без урона (прыжок на 1 g ≈ 5 м/с)
const FALL_K := 1.1            # урон за (м/с)² сверх безопасного
const FACTORY_R := 7.5         # м: у завода корпус чинится сам
const FACTORY_HEAL := 4.0      # ед/с (в 2D у фабрикатора 2 ед/с при меньшем запасе)
const REPAIR_KG := 0.8         # кг/с материала из груза при починке
const WRECK_TIME := 2.8        # с: сколько лежит сломанным до возврата
const HIT_STEP := 3.0          # непрерывный урон «вспыхивает» каждые столько единиц

var robot: Node3D
var terrain: ProtoTerrain
var planet: Planet
var player: Node                 # ProtoPlayer (vel, air, vy, fist)
var fx: ProtoHurtFx
var active := true               # false — урона нет (скриптовые маршруты для кадров)
var input_enabled := true        # H / D-pad → — починка из груза

var hull: Substance
var stats := {}
var shield := {"heat": 0.0, "radiation": 0.0, "toxic": 0.0, "acid": 0.0}
var hp := 100.0
var max_hp := 100.0
var zones: Array = []            # жидкости: {sub, temp, level: Callable(x, z), area: Callable(x, z)}
var base := Vector3.ZERO         # где робот собирается после поломки
var factory_at := Vector3.INF    # центр завода (ремонт рядом)

# Что происходит сейчас — для HUD и звука.
var dps := 0.0                   # урон в секунду (без ударов)
var kind := ""                   # heat, cold, acid, toxic, radiation, impact
var depth := 0.0                 # на сколько робот в жидкости, м
var liquid: Substance = null
var healing := ""                # "factory", "cargo" или ""
var status := ""
var tone := "ok"
var wreck_t := -1.0              # >= 0 — робот сломан, идёт отсчёт до возврата
var lost_kg := 0.0

var _acc := 0.0

func setup(r: Node3D, t: ProtoTerrain, p: Planet, hull_sub: Substance) -> void:
	robot = r
	terrain = t
	planet = p
	set_hull(hull_sub)
	hp = max_hp
	robot.set_meta("health", self)
	ensure_action()

## Корпус из материала: запас прочности и защита — по правилам 2D.
func set_hull(s: Substance) -> void:
	hull = s
	stats = ComponentStats.compute("hull", s) if s != null else {}
	max_hp = max_hp_of(stats)
	shield = hull_shield(stats)
	hp = minf(hp, max_hp)

static func ensure_action() -> void:
	if InputMap.has_action(REPAIR):
		return
	InputMap.add_action(REPAIR, 0.5)
	var k := InputEventKey.new()
	k.physical_keycode = KEY_H
	InputMap.action_add_event(REPAIR, k)
	var b := InputEventJoypadButton.new()
	b.device = -1
	b.button_index = JOY_BUTTON_DPAD_RIGHT
	InputMap.action_add_event(REPAIR, b)

# ---------------------------------------------------------------- правила

## Запас прочности: как RobotState.max_hp в 2D.
static func max_hp_of(st: Dictionary) -> float:
	return float(st.max_hp) * 1.2 if st.has("max_hp") else 60.0

## Защита корпуса: половина защиты его материала (RobotState.shield в 2D).
static func hull_shield(st: Dictionary) -> Dictionary:
	var s := {"heat": 0.0, "radiation": 0.0, "toxic": 0.0, "acid": 0.0}
	if st.is_empty():
		return s
	s.heat = float(st.shield_heat) * 0.5
	s.radiation = float(st.shield_radiation) * 0.5
	s.toxic = float(st.shield_toxic) * 0.5
	s.acid = float(st.shield_acid) * 0.5
	return s

## Жидкость планеты-«рельефа», как клетки 2D: вулканическая — лава,
## кислотные дожди и океаны — кислотные озёра. null — таких нет.
static func hazard_liquid(p: Planet) -> Substance:
	if p.has_tag("volcanic"):
		var s := Substance.new("lava", "Лава")
		s.melt = 950.0
		s.boil = 2600.0
		s.density = 3.1
		s.color = Color(1.0, 0.36, 0.08)
		return s
	if p.has_tag("acid_rain") or p.has_tag("oceanic"):
		var s := Substance.new("acid_lake", "Кислота", ["acidic"])
		s.color = Color(0.5, 0.78, 0.16)
		return s
	return null

## Температура жидкости: лава — выше точки плавления, остальное — как воздух.
static func liquid_temp(s: Substance, ambient: float) -> float:
	return maxf(ambient, s.melt + 150.0) if s.melt > 300.0 else ambient

## Урон жидкости в секунду: {dps, kind}. depth — глубина погружения, м.
static func liquid_rate(s: Substance, temp: float, dep: float, sh: Dictionary, st: Dictionary) -> Dictionary:
	var contact := clampf(dep / 0.8, 0.3, 1.0)
	var parts := {}
	if temp > 90.0:
		var h := minf((temp - 90.0) / 25.0, 40.0)
		# Выше предела нагрева материала корпуса — вдвое (как детали в 2D).
		if st.has("max_t") and temp > float(st.max_t):
			h *= 2.0
		parts.heat = h * (1.0 - sh.heat)
	elif temp < -110.0:
		parts.cold = minf((-110.0 - temp) / 20.0, 12.0) * (1.0 - sh.heat)
	if s.has("acidic"):
		parts.acid = 9.0 * (1.0 - sh.acid)
	if s.has("toxic"):
		parts.toxic = 3.0 * (1.0 - sh.toxic)
	if s.has("radioactive"):
		parts.radiation = 5.0 * (1.0 - sh.radiation)
	return _sum(parts, contact)

## Среда планеты в секунду — правила 2D; sky — сколько неба над роботом (0 — под сводом).
static func ambient_rate(p: Planet, sh: Dictionary, sky: float) -> Dictionary:
	var parts := {}
	if p.has_tag("radiation"):
		parts.radiation = 0.25 * (1.0 - sh.radiation) * lerpf(0.5, 1.0, sky)
	if p.has_tag("toxic_atmosphere"):
		parts.toxic = 0.15 * (1.0 - sh.toxic)
	if p.has_tag("acid_rain"):
		parts.acid = 0.1 * (1.0 - sh.acid) * sky
	if p.ambient_temp > 60.0:
		parts.heat = 0.15 * (1.0 - sh.heat) * lerpf(0.4, 1.0, sky)
	elif p.ambient_temp < -60.0:
		parts.cold = 0.15 * (1.0 - sh.heat)
	return _sum(parts, 1.0)

static func _sum(parts: Dictionary, k: float) -> Dictionary:
	var total := 0.0
	var worst := ""
	for key in parts:
		total += parts[key] * k
		if worst == "" or parts[key] > parts[worst]:
			worst = key
	return {"dps": total, "kind": worst}

## Урон от удара о землю со скоростью v (м/с). На тяжёлой планете с той же высоты
## скорость больше (v² = 2gh) — и урон больше. Упругий корпус гасит удар.
static func fall_damage(v: float, st: Dictionary) -> float:
	if v <= SAFE_FALL_V:
		return 0.0
	var d := pow(v - SAFE_FALL_V, 2.0) * FALL_K
	return d / float(st.get("flex", 1.0))

## Сколько прочности даёт килограмм материала при починке.
static func repair_value(s: Substance) -> float:
	var v := 4.0 + s.hardness * 2.0
	if s.has("metallic"):
		v *= 1.5
	if s.has("brittle"):
		v *= 0.6
	return v

## Высота падения, после которой робот получает урон, м (для подсказок и тестов).
static func safe_height(gravity: float) -> float:
	return SAFE_FALL_V * SAFE_FALL_V / (2.0 * ProtoPlayer.G * gravity)

# ---------------------------------------------------------------- игра

## Жидкость под роботом: {sub, temp, depth} или пусто.
func liquid_at(p: Vector3) -> Dictionary:
	for z: Dictionary in zones:
		if not z.area.call(p.x, p.z):
			continue
		var lv: float = z.level.call(p.x, p.z)
		if lv > p.y + 0.05:
			return {"sub": z.sub, "temp": z.temp, "depth": lv - p.y}
	return {}

func is_wrecked() -> bool:
	return wreck_t >= 0.0

## Урон: копится, вспышки (искры, звук) — на крупных ударах и каждые HIT_STEP единиц.
func damage(amount: float, k: String) -> void:
	if amount <= 0.0 or is_wrecked() or not active:
		return
	hp -= amount
	_acc += amount
	if amount >= HIT_STEP or _acc >= HIT_STEP:
		hit.emit(_acc, k)
		if fx:
			fx.hit(_acc, k, robot)
		_acc = 0.0
	if hp <= 0.0:
		_wreck()

## Приземление (ProtoPlayer): v — скорость удара вниз.
func landed(v: float) -> void:
	var d := fall_damage(v, stats)
	if d > 0.0:
		damage(maxf(d, HIT_STEP), "impact")

func _process(dt: float) -> void:
	dt = minf(dt, 0.25)
	if robot == null:
		return
	if is_wrecked():
		_wreck_step(dt)
		return
	var p := robot.position
	dps = 0.0
	kind = ""
	liquid = null
	var lq := liquid_at(p)
	depth = lq.get("depth", 0.0)
	if not lq.is_empty():
		liquid = lq.sub
		var r := liquid_rate(lq.sub, lq.temp, depth, shield, stats)
		dps += r.dps
		kind = r.kind
	var sky := terrain.sky_vis(p + Vector3(0, 1.5, 0)) if terrain else 1.0
	var a := ambient_rate(planet, shield, sky)
	dps += a.dps
	if kind == "":
		kind = a.kind
	if not active:
		dps = 0.0
	damage(dps * dt, kind)
	if is_wrecked():
		return
	_heal(dt)
	_status()
	if fx:
		fx.set_state(hp / maxf(max_hp, 1.0), dps, kind)

func _heal(dt: float) -> void:
	healing = ""
	if hp >= max_hp:
		return
	if factory_at != Vector3.INF and Vector2(robot.position.x - factory_at.x, robot.position.z - factory_at.z).length() < FACTORY_R \
			and dps < FACTORY_HEAL * 0.5:
		hp = minf(max_hp, hp + FACTORY_HEAL * dt)
		healing = "factory"
		return
	# В карточке материала и на карте D-pad → выбирает кнопки, а не чинит.
	var busy := robot != null and bool(robot.get_meta("ui_busy", false))
	if input_enabled and Input.is_action_pressed(REPAIR) and not _building() and not busy:
		var got := repair_from_cargo(REPAIR_KG * dt)
		if got > 0.0:
			healing = "cargo"

func _building() -> bool:
	var b := get_parent().get_node_or_null("builder") if get_parent() else null
	return b != null and bool(b.get("active"))

## Починка материалом из груза: берёт до kg лучшего для ремонта вещества.
## Возвращает восстановленную прочность.
func repair_from_cargo(kg: float) -> float:
	var cargo: Array = robot.get_meta("cargo", [])
	var best: Portion = null
	var best_v := 0.0
	for p: Portion in cargo:
		var v := repair_value(p.substance)
		if p.mass > 0.0 and v > best_v:
			best = p
			best_v = v
	if best == null:
		return 0.0
	var need := (max_hp - hp) / best_v
	var take := minf(minf(kg, need), best.mass)
	best.mass -= take
	if best.mass <= 0.001:
		cargo.erase(best)
	var got := take * best_v
	hp = minf(max_hp, hp + got)
	return got

func can_repair_from_cargo() -> bool:
	if hp >= max_hp:
		return false
	for p: Portion in robot.get_meta("cargo", []):
		if repair_value(p.substance) > 0.0:
			return true
	return false

const KIND_WORDS := {"heat": "жар", "cold": "холод", "acid": "кислота", "toxic": "яд",
	"radiation": "радиация", "impact": "удар"}

func _status() -> void:
	var frac := hp / maxf(max_hp, 1.0)
	tone = "ok" if frac > 0.6 else ("warn" if frac > 0.3 else "bad")
	if liquid != null and dps > 0.5:
		var w: String = KIND_WORDS.get(kind, kind)
		status = "%s −%.0f/с" % [liquid.name, dps] if w in liquid.name.to_lower() else "%s: %s −%.0f/с" % [liquid.name, w, dps]
		tone = "bad"
	elif healing == "factory":
		status = "ремонт у завода"
	elif healing == "cargo":
		status = "починка из груза"
	elif dps > 0.05:
		status = "%s −%.1f/с" % [KIND_WORDS.get(kind, kind).capitalize(), dps]
	else:
		status = ""

# ---------------------------------------------------------------- поломка

func _wreck() -> void:
	hp = 0.0
	wreck_t = WRECK_TIME
	lost_kg = 0.0
	for p: Portion in robot.get_meta("cargo", []):
		lost_kg += p.mass
	robot.set_meta("wrecked", true)
	status = "корпус разрушен"
	tone = "bad"
	if player != null:
		var fist = player.get("fist")
		if fist != null and fist.state != "dock":
			fist.release()
	if fx:
		fx.set_state(0.0, 0.0, "")
		fx.wreck(robot, lost_kg)
	wrecked.emit()

func _wreck_step(dt: float) -> void:
	wreck_t -= dt
	# Робот оседает набок.
	robot.rotation.z = lerpf(robot.rotation.z, 0.55, minf(1.0, dt * 3.0))
	if wreck_t <= 0.0:
		respawn()

## Возврат на базу: полная прочность, груз потерян.
func respawn() -> void:
	wreck_t = -1.0
	robot.rotation.z = 0.0
	robot.position = base
	robot.set_meta("cargo", [])
	robot.set_meta("wrecked", false)
	hp = max_hp
	_acc = 0.0
	if player != null:
		player.set("vel", Vector3.ZERO)
		player.set("vy", 0.0)
		player.set("air", false)
		player.set("cam_yaw", robot.rotation.y)
	status = ""
	if fx:
		fx.restored(lost_kg)
	restored.emit()
