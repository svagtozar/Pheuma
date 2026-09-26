class_name Pump
extends Machine
## Насос: качает атмосферу в свой газовый узел, пока давление ниже заданного.
## Производительность зависит от давления атмосферы планеты.

func init_config() -> void:
	config.target_p = 5.0

func tick(w, dt: float) -> void:
	status = ""
	if not enabled:
		return
	var limit: float = min(config.target_p, stats.max_p * 0.95)
	if w.gas.pressure(id) >= limit:
		status = "давление набрано"
		return
	var rate: float = 0.8 * w.planet.atm_pressure * (1.0 + w.robot.passive("pump_rate")) * stats.speed
	w.gas.add_gas(id, rate * dt)
	w.robot.xp.firekeeper += 0.02 * dt

func describe(w) -> Array:
	var l := super.describe(w)
	l.append("Целевое давление: %.1f атм" % config.target_p)
	return l
