class_name ProtoTerraform
extends RefCounted
## Климат планеты, который меняет игрок (терраформирование в 3D).
##   Атмосфера: газ из газоотводов завода (ProtoPneumatics «vent») уходит в небо,
##   давление планеты растёт. Насосы качают быстрее, небо синеет, дымка гуще.
##   Тепло: груз, ушедший на орбиту из пусковой шахты, становится зеркалами.
##   На холодной планете они греют, на жаркой — затеняют (остужают). Плотнее
##   атмосфера — сильнее парниковый эффект.
##   Пригодность 0..1 — насколько давление и температура близки к жилым; от неё
##   и от занесённой жизни (seeded) растёт флора по всей планете, а купол с
##   жилыми условиями зеленит округу.
## Базовые давление и температура — из генератора; сдвиг события «перепад
## температуры» живёт отдельно (ProtoRun) и сюда не входит.

const P_PER_GAS := 0.004       # атм на единицу выпущенного газа (150 ед. — +0,6 атм)
const MAX_DP := 2.5            # больше атмосферы не надуть
const T_PER_KG := 2.5          # °C на кг зеркал на орбите
const MAX_MIRROR_T := 110.0
const GREENHOUSE := 15.0       # °C на каждую добавленную атмосферу
const HOT := 35.0              # выше этого зеркала затеняют, а не греют
const LIVE_P := [0.5, 3.5]     # жилое давление
const LIVE_T := [-5.0, 40.0]   # жилая температура
const P_FADE := 0.35           # на сколько атм за краем пригодность падает до нуля
const T_FADE := 40.0
## Материалы, которые отражают лучше: их килограмм — полный килограмм зеркал.
const REFLECT := ["metallic", "crystalline", "conductive", "luminous"]
const SEED_GAS := 250.0        # столько газа в небо — и жизнь занесена по всей планете
const SEED_KG := 60.0          # или столько кг зеркал
const DOME_GROW := 0.25        # м/с роста зелёной зоны вокруг жилого купола
const DOME_R := [4.0, 14.0]    # радиус зоны: без пригодности планеты — и при полной

var base_p := 1.0
var base_t := 15.0
var vented := 0.0              # газа выпущено в небо за ран
var mirrors := 0.0             # кг зеркал (с учётом отражения материала)
var _last_t := 15.0            # температура прошлого apply (для пересчёта газа сети)
var zones := {}                # клетка купола (Vector2i) → радиус зелёной зоны, м

func _init(p: Planet = null) -> void:
	if p != null:
		base_p = p.atm_pressure
		base_t = p.ambient_temp
		_last_t = base_t

func add_vented(units: float) -> void:
	vented += maxf(0.0, units)

## Груз ушёл на орбиту: отражающие материалы — целиком, прочие — на треть.
func add_mirrors(sub: Substance, kg: float) -> void:
	var k := 0.35
	if sub != null:
		for t in REFLECT:
			if sub.has(t):
				k = 1.0
				break
	mirrors += maxf(0.0, kg) * k

func pressure() -> float:
	return base_p + minf(MAX_DP, vented * P_PER_GAS)

## Сдвиг от зеркал: греют холодную планету, остужают жаркую.
func mirror_shift() -> float:
	var s := minf(MAX_MIRROR_T, mirrors * T_PER_KG)
	return -s if base_t > HOT else s

func temp() -> float:
	return base_t + mirror_shift() + GREENHOUSE * (pressure() - base_p)

static func score(v: float, lo: float, hi: float, fade: float) -> float:
	if v < lo:
		return clampf(1.0 - (lo - v) / fade, 0.0, 1.0)
	if v > hi:
		return clampf(1.0 - (v - hi) / fade, 0.0, 1.0)
	return 1.0

## Пригодность при давлении p и температуре t (0 — мёртвая, 1 — жилая).
static func habit_at(p: float, t: float) -> float:
	return score(p, LIVE_P[0], LIVE_P[1], P_FADE) * score(t, LIVE_T[0], LIVE_T[1], T_FADE)

func habitability() -> float:
	return habit_at(pressure(), temp())

## Сколько жизни занесено на планету (0..1): вместе с газом из газоотводов в небо
## уходят споры из баков, зеркала греют их. Без этого даже жилая планета голая.
func seeded() -> float:
	return clampf(vented / SEED_GAS + mirrors / SEED_KG, 0.0, 1.0)

func base_habitability() -> float:
	return habit_at(base_p, base_t)

## Меняет давление и температуру планеты и сети завода. shift — сдвиг события.
func apply(planet: Planet, net = null, shift := 0.0) -> void:
	planet.atm_pressure = pressure()
	planet.ambient_temp = temp()
	if net != null:
		net.gas.atm_pressure = planet.atm_pressure
		# Климат меняется медленно: газ в сети успевает стравиться и остыть, давление
		# в деталях от этого не скачет (иначе потепление рвало бы весь завод).
		# Сдвиг события — резкий, его давление чувствует.
		net.gas.ambient = _last_t + shift
		var f_mid: float = net.gas.temp_factor()
		net.gas.ambient = planet.ambient_temp + shift
		var f_new: float = net.gas.temp_factor()
		if absf(f_new - f_mid) > 0.00001:
			for id in net.gas.nodes:
				net.gas.nodes[id].n *= f_mid / f_new
	_last_t = planet.ambient_temp

## Купола с жилыми условиями растят вокруг себя зелёную зону; купол пропал —
## зона пропадает. ok_domes — клетки куполов, где сейчас жилые условия.
func grow_zones(ok_domes: Array, all_domes: Array, dt: float) -> void:
	var cap := lerpf(DOME_R[0], DOME_R[1], habitability())
	for c in zones.keys():
		if not all_domes.has(c):
			zones.erase(c)
	for c in ok_domes:
		zones[c] = minf(cap, float(zones.get(c, 0.0)) + DOME_GROW * dt)

## Короткая строка для HUD: «0,8 атм · −42 °C · пригодность 12%».
func summary() -> String:
	return "%.2f атм · %.0f °C · пригодность %d%%" % [pressure(), temp(), roundi(habitability() * 100.0)]

func to_dict() -> Dictionary:
	var z := []
	for c in zones:
		z.append([c.x, c.y, zones[c]])
	return {"vented": vented, "mirrors": mirrors, "zones": z}

func from_dict(d: Dictionary) -> void:
	vented = float(d.get("vented", 0.0))
	mirrors = float(d.get("mirrors", 0.0))
	zones = {}
	for a in d.get("zones", []):
		zones[Vector2i(int(a[0]), int(a[1]))] = float(a[2])
