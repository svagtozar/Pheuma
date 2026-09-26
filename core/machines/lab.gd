class_name Lab
extends Machine
## Лаборатория: каждая порция, проходящая насквозь, получает все пробы,
## которые ещё что-то могут сказать (по 0.5 кг на пробу). Остаток уходит вперёд.
## Пока узнала новое — выдаёт логический сигнал.

const DUR := 4.0
const PULSE := 2.0

var busy: Portion = null
var _t := 0.0
var _pulse := 0.0

func tick(w, dt: float) -> void:
	var ww = w.world if w is InnerGrid else w
	status = ""
	if _pulse > 0.0:
		_pulse -= dt
		signal_out = true
	if not enabled:
		return
	if not out_queue.is_empty():
		status = "выход занят"
		return
	if busy == null:
		if items.is_empty():
			status = "ждёт образцы"
			return
		busy = items.pop_front()
		_t = 0.0
	_t += dt * stats.speed
	status = "пробы %d%%" % int(clamp(_t / DUR, 0.0, 1.0) * 100)
	if _t < DUR:
		return
	var s: Substance = busy.substance
	var before: int = ww.unknown_count(s) + ww.possible_of(s).size()
	for pid in Probes.ORDER:
		if ww.is_identified(s) or busy.mass < Probes.SAMPLE_KG + 0.01:
			break
		if not _useful(ww, s, pid):
			continue
		busy.mass -= Probes.SAMPLE_KG
		ww.probe(s.id, pid, true)
	if ww.unknown_count(s) + ww.possible_of(s).size() < before:
		_pulse = PULSE
		signal_out = true
	if busy.mass > 0.01:
		out_queue.append([busy, 0])
	busy = null

## Проба что-то скажет: в её наборе есть теги, о которых ещё ничего не известно.
func _useful(ww, s: Substance, pid: String) -> bool:
	var k: Dictionary = ww.robot.sub_known.get(s.id, {})
	for t in Probes.PROBES[pid].tags:
		if not k.has(t):
			return true
	return false

func total_mass() -> float:
	return super.total_mass() + (busy.mass if busy != null else 0.0)

func save_extra() -> Dictionary:
	var d := super.save_extra()
	if busy != null:
		d.busy = SaveGame.p_to(busy)
	d.t = _t
	return d

func load_extra(w, d: Dictionary) -> void:
	super.load_extra(w, d)
	if d.has("busy"):
		busy = SaveGame.p_from(w if not (w is InnerGrid) else w.world, d.busy)
	_t = float(d.get("t", 0.0))

func describe(w) -> Array:
	var l := super.describe(w)
	if busy != null:
		l.append("На пробах: %s %.1f кг" % [w.sub_label(busy.substance), busy.mass])
	return l
