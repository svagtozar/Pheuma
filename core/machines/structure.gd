class_name Structure
extends Machine
## Сборные логистические сооружения — работают, только когда собраны из частей.
##
## Пневмопровод: вход (tube_inlet) → сегменты (tube) → выход (tube_outlet).
##   Вход отправляет капсулы по трубе, если есть путь до выхода и давление ≥ 1.5 атм.
##   Капсулы видно на трубе; скорость растёт с давлением. Разобрали сегмент —
##   капсула вываливается на землю.
## Склад: четыре секции (warehouse_section) квадратом 2×2 объединяются в одно
##   хранилище на 320 кг. Порознь секция — ящик на 20 кг.

const WAREHOUSE_CAP := 320.0
const TUBE_MIN_P := 1.5

var master_id := -1            # склад: id главной секции (или -1)
var group: Array = []          # склад: id секций (только у главной)
var path: Array = []           # вход пневмопровода: клетки пути
var master: WeakRef            # склад: слабая ссылка на главную секцию
var _cd := 0.0
var _path_t := 0.0

func init_config() -> void:
	if kind == "tube_outlet":
		config.pass_through = true
	if kind == "warehouse_section":
		config.pass_through = false

func assembled() -> bool:
	match kind:
		"tube_inlet": return not path.is_empty()
		"warehouse_section": return master_id >= 0
	return true

func capacity() -> float:
	if kind == "warehouse_section":
		if master_id == id:
			return WAREHOUSE_CAP
		if master_id >= 0:
			return 0.0
	return info.get("cap", 0.0)

func accept(p: Portion, from_cell: Vector2i) -> bool:
	if kind == "tube":
		return false
	if kind == "warehouse_section" and master_id >= 0 and master_id != id:
		var mm = master.get_ref() if master != null else null
		return mm != null and mm.accept(p, from_cell)
	if kind == "tube_inlet":
		if p.mass > free_space() + 0.001 or side_of(from_cell) == "front":
			return false
		store(p)
		return true
	return super.accept(p, from_cell)

func tick(w, dt: float) -> void:
	match kind:
		"tube_inlet":
			_tick_inlet(w, dt)
		"tube_outlet":
			super.tick(w, dt)
		"warehouse_section":
			if master_id < 0 or master_id == id:
				super.tick(w, dt)
			status = "склад собран: 4 секции, %.0f/%.0f кг" % [w.machines[master_id].total_mass(), WAREHOUSE_CAP] if master_id >= 0 and w.machines.has(master_id) else "не собрано: нужны 4 секции квадратом 2×2"

func _tick_inlet(w, dt: float) -> void:
	_cd -= dt
	_path_t -= dt
	if _path_t <= 0.0:
		_path_t = 1.0
		path = find_path(w)
	if path.is_empty():
		status = "не собрано: нет трубы до выхода"
		return
	if not enabled:
		status = "выключено"
		return
	var p: float = w.gas.pressure(id)
	if items.is_empty():
		status = "собрано, %d сегм., ждёт груз" % (path.size() - 2)
		return
	if p < TUBE_MIN_P:
		status = "мало давления: %.1f / %.1f атм" % [p, TUBE_MIN_P]
		return
	if _cd > 0.0:
		return
	var q: Portion = items[0]
	var part := q.split(min(3.0, q.mass))
	if q.mass <= 0.001:
		items.remove_at(0)
	w.gas.take_gas(id, 0.25)
	var speed: float = clamp(2.0 + 2.5 * (p - 1.0), 2.0, 14.0) * stats.speed
	w.tube_capsules.append({"path": path.duplicate(), "pos": 0.0, "speed": speed, "payload": [part], "t": 0.0})
	_cd = 0.5
	status = "отправляет, %.1f кл/с" % speed

## Путь по сегментам трубы от входа до ближайшего выхода (поиск в ширину).
func find_path(w) -> Array:
	var prev := {cell: cell}
	var queue: Array = [cell]
	while not queue.is_empty():
		var c: Vector2i = queue.pop_front()
		for d in Machine.DIRS:
			var n: Vector2i = c + d
			if prev.has(n):
				continue
			var m = w.machine_at(n)
			if m == null:
				continue
			if m.kind == "tube_outlet":
				prev[n] = c
				var out: Array = [n]
				var k: Vector2i = c
				while k != cell:
					out.push_front(k)
					k = prev[k]
				out.push_front(cell)
				return out
			if m.kind == "tube":
				prev[n] = c
				queue.append(n)
	return []

func save_extra() -> Dictionary:
	return {"master": master_id, "group": group}

func load_extra(_w, d: Dictionary) -> void:
	master_id = int(d.get("master", -1))
	group = d.get("group", []).map(func(x): return int(x))

func describe(w) -> Array:
	var l := super.describe(w)
	match kind:
		"tube_inlet":
			l.append("Путь: %s" % ("%d клеток" % path.size() if not path.is_empty() else "не собран"))
		"tube":
			l.append("Сегмент пневмопровода")
	return l
