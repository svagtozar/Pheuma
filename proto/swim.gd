class_name ProtoSwim
extends RefCounted
## Плавучесть робота в жидкостях 3D-прототипа (ProtoPlayer).
## Архимед: выталкивает вес вытесненной жидкости, так что всплывёт робот или
## пойдёт ко дну — решает только отношение плотностей жидкости и робота
## (плотность — от металла корпуса и груза). Гравитация планеты меняет не исход,
## а темп: на тяжёлой планете всё быстрее тонет и быстрее выпрыгивает наверх.
## Вязкость (по тегам жидкости) — сопротивление: вязкая жидкость тормозит шаг,
## гасит качку и падение.

const BODY_H := 1.85          # высота робота, м: погружение = глубина / BODY_H
const VOLUME := 0.55          # объём корпуса, м³ (для груза)
const HULL_SHARE := 0.25      # доля объёма — металл корпуса, остальное — начинка
const CORE_DENSITY := 0.8     # начинка (механика, баллоны), г/см³
const SWIM_UP := 0.55         # тяга вверх (Прыжок в жидкости), доля g
const SWIM_DOWN := 0.45       # нырок (Бег в жидкости), доля g
const FLOW_SPEED := 1.6       # течение реки на воде, м/с (вязкость его гасит)

## Средняя плотность робота, г/см³: корпус + начинка + груз.
static func robot_density(hull: Substance, cargo_kg := 0.0) -> float:
	var h := hull.density if hull != null else 6.5
	return maxf(0.3, HULL_SHARE * h + (1.0 - HULL_SHARE) * CORE_DENSITY + cargo_kg / (VOLUME * 1000.0))

## Вязкость жидкости — коэффициент сопротивления, 1/с.
static func viscosity(s: Substance) -> float:
	if s == null:
		return 0.0
	var v := 1.2
	if s.has("sticky"):
		v = 4.5
	elif s.has("organic") or s.has("fibrous"):
		v = 2.6
	if s.has("dense"):
		v += 1.2
	if s.has("elastic"):
		v += 0.8
	if s.has("volatile"):
		v *= 0.7
	if s.melt > 300.0:
		v = 6.0                  # расплав (лава, металл)
	if s.has("superfluid"):
		v = 0.15
	return v

## Доля робота под поверхностью (0..1) при глубине depth под ногами.
static func submerged(depth: float) -> float:
	return clampf(depth / BODY_H, 0.0, 1.0)

## Отношение плотностей: > 1 — робот всплывает, < 1 — тонет.
static func ratio(liquid: Substance, robot_rho: float) -> float:
	return liquid.density / maxf(robot_rho, 0.01) if liquid != null else 0.0

## На какой глубине сидит плавающий робот (ноги под поверхностью), м;
## INF — не плавает, тонет.
static func float_depth(r: float) -> float:
	return BODY_H / r if r > 1.0 else INF

## Вертикальное ускорение, м/с²: тяжесть минус выталкивание, минус вязкость
## (только погружённой частью). g — ускорение свободного падения планеты.
static func accel(g: float, r: float, f: float, vy: float, visc: float) -> float:
	return -g * (1.0 - r * f) - visc * f * vy

## Во сколько раз медленнее шаг/гребок в жидкости при погружении f.
static func speed_mult(visc: float, f: float) -> float:
	var deep := clampf(1.0 / (1.0 + visc * 0.35), 0.25, 0.8)
	return lerpf(1.0, deep, clampf(f * 1.6, 0.0, 1.0))

## Скорость течения на поверхности, м/с.
static func flow_speed(visc: float) -> float:
	return FLOW_SPEED / (1.0 + visc * 0.5)
