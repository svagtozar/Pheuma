class_name Drill
extends Machine
## Бур на залежи. Берёт материал не твёрже себя, выдаёт порции вперёд.

var _t := 0.0

func tick(w, dt: float) -> void:
	status = ""
	var dep = w.planet.deposits.get(cell)
	if dep == null or dep.amount <= 0.0:
		status = "залежь пуста" if dep != null else "нет залежи"
		return
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
