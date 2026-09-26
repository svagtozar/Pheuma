class_name Battery
extends Cannon
## Тяжёлая пневмобатарея: четыре секции квадратом 2×2 собираются в одну пушку.
## Главная секция стреляет за всех: груз до 20 кг, дальность ×2.2, газ берётся
## из камер всех секций. Порознь секции не стреляют.

func init_config() -> void:
	super.init_config()
	config.fire_p = 4.0

func capacity() -> float:
	return 40.0 if master_id == id else 0.0

func accept(p: Portion, from_cell: Vector2i) -> bool:
	if master_id < 0:
		return false
	if master_id != id:
		var mm = master.get_ref() if master != null else null
		return mm != null and mm.accept(p, from_cell)
	if p.mass > free_space() + 0.001:
		return false
	store(p)
	return true

func payload_limit() -> float:
	return 20.0

func range_mult() -> float:
	return 2.2

func consume_gas(w) -> void:
	for gid in group:
		if w.gas.has_node(gid):
			w.gas.take_gas(gid, w.gas.amount(gid) * 0.7)

func tick(w, dt: float) -> void:
	if master_id < 0:
		status = "не собрано: нужны 4 секции квадратом 2×2"
		return
	if master_id != id:
		status = "часть батареи"
		return
	super.tick(w, dt)
