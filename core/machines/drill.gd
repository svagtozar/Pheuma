class_name Drill
extends Machine
## Бур на залежи. Берёт материал не твёрже себя, выдаёт порции вперёд.
## Когда своя клетка пуста, дотягивается до соседних клеток того же материала
## (кроме клеток под другими машинами).

const REACH := [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(-1, 1), Vector2i(-1, -1), Vector2i(1, -1)]

var _t := 0.0

## Залежь, из которой бур берёт сейчас: своя клетка, а если она пуста — соседняя.
func source(w):
	var own = w.planet.deposits.get(cell)
	if own == null:
		return null
	if own.amount > 0.0:
		return own
	for d in REACH:
		var c: Vector2i = cell + d
		var dep = w.planet.deposits.get(c)
		if dep != null and dep.sub == own.sub and dep.amount > 0.0 and w.machine_at(c) == null:
			return dep
	return own

func tick(w, dt: float) -> void:
	status = ""
	var dep = source(w)
	if dep == null or dep.amount <= 0.0:
		status = "залежь пуста" if dep != null else "нет залежи"
		return
	var own = w.planet.deposits.get(cell)
	if dep != own:
		status = "добывает соседнюю клетку"
	var sub: Substance = w.db.get_sub(dep.sub)
	if stats.hardness + 0.5 < sub.hardness:
		status = "материал бура слишком мягкий (нужно %.1f)" % sub.hardness
		return
	if not enabled:
		return
	if not out_queue.is_empty():
		status = "выход занят"
		return
	_t += dt * stats.speed * (1.0 + w.robot.passive("drill_yield")) * w.time_factor()
	if _t >= 2.0:
		_t = 0.0
		var m: float = min(1.0, dep.amount)
		dep.amount -= m
		out_queue.append([Portion.new(sub, m, w.planet.ambient_temp), 0])
		w.robot.xp.gatherer += 0.1
