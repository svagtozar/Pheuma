class_name Pump
extends Machine
## Насос: качает атмосферу в свой газовый узел, пока давление ниже заданного.
## Производительность зависит от давления атмосферы планеты.
## В режиме откачки (config.reverse) выбрасывает газ из сети наружу, пока давление
## выше заданного, — так можно получить давление ниже атмосферного.

func init_config() -> void:
	config.target_p = 5.0
	config.reverse = false

func tick(w, dt: float) -> void:
	status = ""
	if not enabled:
		return
	var rate: float = 0.8 * (1.0 + w.robot.passive("pump_rate")) * stats.speed
	if config.get("reverse", false):
		if w.gas.pressure(id) <= config.target_p:
			status = "откачано до %.1f атм" % config.target_p
			return
		w.gas.take_gas(id, rate * dt)
		w.robot.xp.firekeeper += 0.02 * dt
		return
	var limit: float = min(config.target_p, stats.max_p * 0.95)
	if w.gas.pressure(id) >= limit:
		status = "давление набрано" if limit >= config.target_p else "упёрся в предел материала: %.1f атм" % limit
		return
	w.gas.add_gas(id, rate * w.planet.atm_pressure * dt)
	w.robot.xp.firekeeper += 0.02 * dt

func describe(w) -> Array:
	var l := super.describe(w)
	l.append("%s: %.1f атм" % ["Откачка до" if config.get("reverse", false) else "Накачка до", config.target_p])
	l.append("Предел этого насоса: %.1f атм (материал)" % (stats.max_p * 0.95))
	return l
