class_name Structure
extends Machine
## Сборные сооружения (не пушки):
## Склад: четыре секции (warehouse_section) квадратом 2×2 объединяются в одно
##   хранилище на 320 кг. Порознь секция — ящик на 20 кг.
## Ловчая сеть (catch_net): сама ничего не делает, но капсула, упавшая на сеть,
##   скатывается по соединённым сетям в ближайший приёмник. Упругие и волокнистые
##   сети тянутся дальше.

const WAREHOUSE_CAP := 320.0

func init_config() -> void:
	if kind == "warehouse_section":
		config.pass_through = false

func capacity() -> float:
	if kind == "warehouse_section":
		if master_id == id:
			return WAREHOUSE_CAP
		if master_id >= 0:
			return 0.0
	return info.get("cap", 0.0)

func accept(p: Portion, from_cell: Vector2i) -> bool:
	if kind == "catch_net":
		return false
	if master_id >= 0 and master_id != id:
		var mm = master.get_ref() if master != null else null
		return mm != null and mm.accept(p, from_cell)
	return super.accept(p, from_cell)

## Сколько клеток сеть протягивает капсулу.
func net_reach() -> int:
	return 2 + int(stats.get("flex", 1.0) > 1.2) + int(stats.get("flex", 1.0) > 1.6)

func tick(w, dt: float) -> void:
	match kind:
		"warehouse_section":
			if master_id < 0 or master_id == id:
				super.tick(w, dt)
			if master_id >= 0 and w.machines.has(master_id):
				status = "склад собран: 4 секции, %.0f/%.0f кг" % [w.machines[master_id].total_mass(), WAREHOUSE_CAP]
			else:
				status = "не собрано: нужны 4 секции квадратом 2×2"
		"catch_net":
			var r = w.net_receiver(cell)
			status = "ловит в %s" % r.display_name() if r != null else "не связана с приёмником"

func describe(w) -> Array:
	var l := super.describe(w)
	if kind == "catch_net":
		l.append("Протягивает капсулу на %d кл." % net_reach())
	return l
