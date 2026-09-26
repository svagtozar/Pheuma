class_name Dome
extends Machine
## Купол для поселенцев: закрытый объём со своей температурой.
## Температура тянется к среде (изолирующий материал — медленнее);
## работающие печи рядом греют, конденсаторы — охлаждают.

var temp := 15.0

func tick(w, dt: float) -> void:
	super.tick(w, dt)
	var amb: float = w.planet.ambient_temp
	temp += (amb - temp) * min(1.0, 0.02 * stats.heat_loss * dt)
	for d in Machine.DIRS:
		var n = w.machine_at(cell + d)
		if n == null:
			continue
		if n.kind == "furnace" and n.hot:
			temp += 1.5 * dt
		elif n.kind == "condenser" and n.hot:
			temp -= 1.5 * dt
	status = "T %.0f °C, %.2f атм" % [temp, w.gas.pressure(id)]
