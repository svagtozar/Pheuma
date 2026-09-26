class_name Machine
extends RefCounted
## Базовая постройка. Сама по себе — хранилище (контейнер, бак, приёмник, купол).
## Каждая постройка сделана из материала (built_from) и наследует его свойства.

const DIRS := [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]
const SIDE_NAMES := {"front": "спереди", "back": "сзади", "left": "слева", "right": "справа"}
const STORAGE := ["container", "tank", "receiver", "dome", "warehouse_section"]

var id := 0
var kind := ""
var cell := Vector2i.ZERO
var facing := 0
var built_from: Substance
var stats := {}
var quality := 0.0
var hp := 100.0
var info := {}
var items: Array = []           # Portion
var out_queue: Array = []       # [Portion, индекс выхода]
var config := {}
var enabled := true
var manual_off := false
var signal_out := false
var status := ""
var hot := false
var _out_timer := 0.0
# Сборные сооружения 2×2: id главной секции, её участники и слабая ссылка на неё.
var master_id := -1
var group: Array = []
var master: WeakRef

static func create(p_kind: String) -> Machine:
	var m: Machine
	var d: Dictionary = Buildings.KINDS[p_kind]
	if d.has("process"):
		m = Processor.new()
	else:
		match p_kind:
			"drill": m = Drill.new()
			"pump": m = Pump.new()
			"pipe", "valve": m = Pipe.new()
			"cannon", "launch_silo": m = Cannon.new()
			"sensor", "gate_and", "gate_or", "gate_not": m = LogicGate.new()
			"dome": m = Dome.new()
			"warehouse_section", "catch_net": m = Structure.new()
			"battery_section": m = Battery.new()
			"macro": m = MacroMachine.new()
			"lab": m = Lab.new()
			_: m = Machine.new()
	m.kind = p_kind
	m.info = d
	m.init_config()
	return m

func init_config() -> void:
	if kind == "container" or kind == "tank":
		config.pass_through = false
	if kind == "receiver":
		config.pass_through = true

func display_name() -> String:
	return Buildings.name_of(kind)

func capacity() -> float:
	return info.get("cap", 0.0)

func sealed() -> bool:
	return info.get("sealed", false)

func has_gas() -> bool:
	return info.get("gas", 0.0) > 0.0

func max_hp() -> float:
	return stats.get("max_hp", 100.0)

func total_mass() -> float:
	var s := 0.0
	for p in items:
		s += p.mass
	return s

func free_space() -> float:
	return capacity() - total_mass()

func out_cell(idx: int = 0) -> Vector2i:
	return cell + DIRS[(facing + idx) % 4]

func side_of(from_cell: Vector2i) -> String:
	var d := from_cell - cell
	if d == DIRS[facing]: return "front"
	if d == DIRS[(facing + 2) % 4]: return "back"
	if d == DIRS[(facing + 3) % 4]: return "left"
	if d == DIRS[(facing + 1) % 4]: return "right"
	return "far"

func is_storage() -> bool:
	return kind in STORAGE

## Принять порцию от соседа (или от робота/капсулы).
func accept(p: Portion, from_cell: Vector2i) -> bool:
	if capacity() <= 0.0 or p.mass > free_space() + 0.001:
		return false
	if not is_storage() and side_of(from_cell) == "front":
		return false
	store(p)
	return true

func store(p: Portion) -> void:
	for q in items:
		if q.substance == p.substance:
			q.absorb(p)
			return
	items.append(p)

func save_extra() -> Dictionary:
	return {"master": master_id, "group": group}

func load_extra(_w, d: Dictionary) -> void:
	master_id = int(d.get("master", -1))
	group = d.get("group", []).map(func(x): return int(x))

func take_all() -> Array:
	var out := items
	items = []
	return out

func tick(w, dt: float) -> void:
	if not is_storage():
		return
	var wants_out: bool = config.get("pass_through", false) or w.logic.has_input(id, 0)
	if not enabled or not wants_out or items.is_empty() or not out_queue.is_empty():
		return
	_out_timer += dt
	if _out_timer < 0.5:
		return
	_out_timer = 0.0
	var p: Portion = items[0]
	var chunk := p.split(min(2.0, p.mass))
	if p.mass <= 0.001:
		items.remove_at(0)
	if not w.push(self, chunk, out_cell(0)):
		store(chunk)
		status = "выдача: спереди никто не принимает"

func flush_outputs(w) -> void:
	var left: Array = []
	for e in out_queue:
		if not w.push(self, e[0], out_cell(e[1])):
			left.append(e)
	out_queue = left
	if not left.is_empty() and status == "":
		status = "выход занят"

func handling_ctx() -> String:
	return "sealed" if sealed() else "open"

func describe(w) -> Array:
	var lines: Array = []
	lines.append("%s  (прочность %.0f/%.0f)" % [display_name(), hp, max_hp()])
	lines.append("Материал: %s" % w.sub_label(built_from))
	for s in ComponentStats.describe(kind, built_from, 0.0):
		lines.append("  · " + s)
	if has_gas():
		lines.append("Давление: %.2f атм" % w.gas.pressure(id))
	if capacity() > 0.0:
		lines.append("Груз: %.1f / %.0f кг" % [total_mass(), capacity()])
		for p in items:
			lines.append("  %s — %.1f кг, %.0f °C, %s" % [w.sub_label(p.substance), p.mass, p.temp, Substance.PHASE_NAMES[p.phase()]])
	if not enabled:
		lines.append("Выключено")
	if status != "":
		lines.append("Состояние: " + status)
	return lines
