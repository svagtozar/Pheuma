class_name LogicGate
extends Machine
## Датчик и логические элементы.
## Датчик смотрит на машину впереди: level (заполненность ≥ порога),
## tag (есть груз с тегом), pressure (давление ≥ порога), temp (T груза ≥ порога).

const MODES := ["level", "tag", "pressure", "temp"]
const MODE_NAMES := {"level": "уровень", "tag": "тег", "pressure": "давление", "temp": "температура"}

func init_config() -> void:
	if kind == "sensor":
		config.mode = "level"
		config.threshold = 0.8
		config.tag = "dense"

func compute(w) -> bool:
	match kind:
		"gate_and":
			return w.logic.input(id, 0) and w.logic.input(id, 1)
		"gate_or":
			return w.logic.input(id, 0) or w.logic.input(id, 1)
		"gate_not":
			return not w.logic.input(id, 0)
		"sensor":
			var v := _sense(w)
			# Магнитная постройка рядом сбивает показания.
			for d in Machine.DIRS:
				var n = w.machine_at(cell + d)
				if n != null and n.stats.get("magnetic", false) and w.rng.chance(0.15):
					return not v
			return v
	return false

func _sense(w) -> bool:
	var t = w.machine_at(out_cell(0))
	if t == null:
		return false
	match config.mode:
		"level":
			return t.capacity() > 0.0 and t.total_mass() / t.capacity() >= config.threshold
		"tag":
			for p in t.items:
				if p.has(config.tag):
					return true
			return false
		"pressure":
			return t.has_gas() and w.gas.pressure(t.id) >= config.threshold
		"temp":
			if t is Dome:
				return t.temp >= config.threshold
			for p in t.items:
				if p.temp >= config.threshold:
					return true
	return false

func describe(w) -> Array:
	var l := super.describe(w)
	if kind == "sensor":
		var extra := ""
		if config.mode == "tag":
			extra = MaterialTags.display(config.tag)
		else:
			extra = "≥ %.2f" % config.threshold
		l.append("Режим: %s %s" % [MODE_NAMES[config.mode], extra])
	l.append("Сигнал: %s" % ("есть" if w.logic.outputs.get(id, false) else "нет"))
	return l
