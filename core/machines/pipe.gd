class_name Pipe
extends Machine
## Труба и клапан. Клапан держит соединения открытыми, пока включён.

func tick(w, _dt: float) -> void:
	if kind != "valve":
		return
	for n in w.gas.neighbors(id):
		w.gas.set_open(id, n, enabled)
	status = "открыт" if enabled else "закрыт"
