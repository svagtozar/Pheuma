class_name ProtoSave
extends Node
## Сохранение 3D-прототипа (--play и сборки play3d). У каждой планеты свой файл
## user://saves3d/planet_<seed>.json, в last.json — сид последней, с неё сборка
## и стартует. Рельеф и друзы строятся заново из сида, поверх накладывается:
##   робот — место, поворот, камера; груз — robot.get_meta("cargo") (Array[Portion]);
##   добытые друзы — мета "mined" корня сцены (id задаёт бурение; при загрузке
##   корень получает restore_mined(ids), если такой метод есть);
##   пневмозавод — детали, их груз, газ и капсулы (корень.pneu, если он есть);
##   ран — цель, прокачка и события (корень.run — ProtoRun, если он есть).
##   знания о веществах — корень.lab_desk (известные и исключённые теги, догадки, баллон);
##   разведанное на карте и найденные метки — корень.map_data (ProtoMapData).
## Порции пишутся как в 2D-сохранении (SaveGame.p_to), производные материалы —
## тоже, чтобы продукты завода пережили перезапуск.
## Когда: раз в AUTOSAVE_SEC, при смене планеты и выходе, по F5 / R3 (нажать
## правый стик); F9 — вернуться к сохранённому. Загрузка — сама при старте.

const VERSION := 1
const AUTOSAVE_SEC := 60.0
const SAVE_NOW := &"save3d_now"
const LOAD_LAST := &"save3d_load"

static var DIR := "user://saves3d"   # тесты подменяют на свою папку

var root: Node3D
var _timer := 0.0
var _toast: Label
var _toast_t := 0.0

# ---------------------------------------------------------------- узел в сцене

## fresh — не загружать сохранение (планета с нуля; первое сохранение его заменит).
func setup(r: Node3D, fresh := false) -> void:
	root = r
	ensure_actions()
	var layer := CanvasLayer.new()
	add_child(layer)
	_toast = Label.new()
	_toast.anchor_left = 1.0
	_toast.anchor_right = 1.0
	_toast.offset_left = -260
	_toast.offset_right = -16
	_toast.offset_top = 12
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_toast.add_theme_font_size_override("font_size", 18)
	_toast.add_theme_color_override("font_outline_color", Color.BLACK)
	_toast.add_theme_constant_override("outline_size", 5)
	layer.add_child(_toast)
	# Сцена достраивается в _ready корня (игрок, завод) — накладываем после.
	if not fresh:
		restore.call_deferred()

static func ensure_actions() -> void:
	var layout := {
		SAVE_NOW: [ProtoControls._key(KEY_F5), ProtoControls._button(JOY_BUTTON_RIGHT_STICK)],
		LOAD_LAST: [ProtoControls._key(KEY_F9)],
	}
	for a in layout:
		if InputMap.has_action(a):
			continue
		InputMap.add_action(a, 0.5)
		for e in layout[a]:
			InputMap.action_add_event(a, e)

func restore() -> void:
	var d := read(int(root.seed_value))
	if d.is_empty():
		return
	apply(root, d)
	_say("Загружено")

func save_now(quiet := false) -> void:
	var err := write(root)
	if not quiet:
		_say(err if err != "" else "Сохранено")

func _process(dt: float) -> void:
	_timer += dt
	if _timer >= AUTOSAVE_SEC:
		_timer = 0.0
		save_now(true)
	if Input.is_action_just_pressed(SAVE_NOW):
		_timer = 0.0
		save_now()
	elif Input.is_action_just_pressed(LOAD_LAST):
		get_tree().reload_current_scene()
	if _toast_t > 0.0:
		_toast_t -= dt
		_toast.modulate.a = clampf(_toast_t, 0.0, 1.0)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and root != null:
		save_now(true)

func _say(s: String) -> void:
	_toast.text = s
	_toast_t = 2.0

# ---------------------------------------------------------------- файлы

static func path_for(seed_value: int) -> String:
	return "%s/planet_%d.json" % [DIR, seed_value]

static func write(r: Node3D) -> String:
	DirAccess.make_dir_recursive_absolute(DIR)
	var f := FileAccess.open(path_for(int(r.seed_value)), FileAccess.WRITE)
	if f == null:
		return "Не удалось сохранить"
	f.store_string(JSON.stringify(to_dict(r)))
	f.close()
	var l := FileAccess.open(DIR + "/last.json", FileAccess.WRITE)
	if l != null:
		l.store_string(JSON.stringify({"seed": int(r.seed_value), "unix": Time.get_unix_time_from_system()}))
	return ""

## Сохранение планеты или {} (нет файла, битый, другая версия).
static func read(seed_value: int) -> Dictionary:
	var p := path_for(seed_value)
	if not FileAccess.file_exists(p):
		return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string(p))
	if typeof(d) != TYPE_DICTIONARY or int(d.get("version", 0)) != VERSION or int(d.get("seed", -1)) != seed_value:
		return {}
	return d

## Сид последней сохранённой планеты или -1.
static func last_seed() -> int:
	var p := DIR + "/last.json"
	if not FileAccess.file_exists(p):
		return -1
	var d = JSON.parse_string(FileAccess.get_file_as_string(p))
	return int(d.get("seed", -1)) if typeof(d) == TYPE_DICTIONARY else -1

# ---------------------------------------------------------------- состояние

static func to_dict(r: Node3D) -> Dictionary:
	var planet: Planet = r.planet
	var robot: Node3D = r.robot
	var d := {"version": VERSION, "seed": int(r.seed_value), "time": Time.get_datetime_string_from_system(false, true)}
	# На планете-шаре — место на планете (шар под роботом повёрнут), см. ProtoPlanetStream.
	d.robot = {"pos": _v3(robot.get_meta("planet_pos", robot.position)), "yaw": robot.rotation.y}
	var h = robot.get_meta("health", null)
	if h != null:
		d.robot.hp = h.hp
	var pl := r.get_node_or_null("player")
	if pl != null:
		d.camera = {"yaw": pl.cam_yaw, "pitch": pl.cam_pitch, "dist": pl.cam_dist}
	d.cargo = (robot.get_meta("cargo", []) as Array).map(func(p): return SaveGame.p_to(p))
	d.mined = (r.get_meta("mined", []) as Array).duplicate(true)
	d.mined_far = (r.get_meta("mined_far", []) as Array).duplicate(true)
	var fill = r.get("planet_fill")
	if fill != null:
		d.far_finds = fill.save_finds()
	var derived: Array = []
	for s in planet.db.all():
		if "#" in s.id:
			derived.append({"id": s.id, "root": s.root, "name": s.name, "tags": s.tags})
	d.substances = derived
	var net = r.get("pneu")
	if net != null:
		d.pneumatics = _net_to(net)
	var run = r.get("run")
	if run != null:
		d.run = run.to_dict()
	var desk = r.get("lab_desk")
	if desk != null:
		d.knowledge = desk.save_dict()
	var map = r.get("map_data")
	if map != null:
		d.map = map.save_dict()
	var dn = r.get("daynight")
	if dn != null:
		d.day_time = dn.time
	var surf = r.get("surface")
	if surf != null:
		d.surface = surf.save_dict()
	return d

static func apply(r: Node3D, d: Dictionary) -> void:
	var planet: Planet = r.planet
	for s in d.get("substances", []):
		planet.db.restore(s.id, s.root, s.name, s.tags)
	var robot: Node3D = r.robot
	if d.has("robot"):
		robot.position = _to_v3(d.robot.pos)
		robot.rotation.y = float(d.robot.yaw)
		var h = robot.get_meta("health", null)
		if h != null and d.robot.has("hp"):
			h.hp = clampf(float(d.robot.hp), 1.0, h.max_hp)
	var pl := r.get_node_or_null("player")
	if pl != null:
		pl.vel = Vector3.ZERO
		if d.has("camera"):
			pl.cam_yaw = float(d.camera.yaw)
			pl.cam_pitch = float(d.camera.pitch)
			pl.cam_dist = float(d.camera.dist)
	var cargo: Array = []
	for a in d.get("cargo", []):
		var p := _p_from(planet, a)
		if p != null:
			cargo.append(p)
	robot.set_meta("cargo", cargo)
	var mined: Array = _ints(d.get("mined", []))
	r.set_meta("mined", mined.duplicate(true))
	if r.has_method("restore_mined"):
		r.restore_mined(mined)
	# Россыпи на шаре вдали от участка (ProtoPlanetFill): id строками.
	var far: Array = (d.get("mined_far", []) as Array).map(func(x): return str(x))
	r.set_meta("mined_far", far)
	var fill = r.get("planet_fill")
	if fill != null:
		fill.hide_mined(far)
		fill.load_finds(d.get("far_finds", []))
	var net = r.get("pneu")
	if net != null and d.has("pneumatics"):
		_net_from(net, planet, d.pneumatics)
	# Ран (цель, прокачка, события) — ProtoRun; счётчики сверяет по заводу.
	var run = r.get("run")
	if run != null and d.has("run"):
		run.from_dict(d.run)
	var desk = r.get("lab_desk")
	if desk != null and d.has("knowledge"):
		desk.load_dict(d.knowledge)
	var map = r.get("map_data")
	if map != null and d.has("map"):
		map.load_dict(d.map)
	var dn = r.get("daynight")
	if dn != null and d.has("day_time") and dn.running:
		dn.time = float(d.day_time)
		dn.update_now()
	var surf = r.get("surface")
	if surf != null and d.has("surface"):
		surf.load_dict(d.surface)
		surf.upload()

# ---------------------------------------------------------------- пневмозавод

## Детали ProtoPneumatics (PR пневматики): ячейка, вид, направление, материал,
## груз, обработка, капсула на выходе и газ в детали.
static func _net_to(net) -> Dictionary:
	var parts: Array = []
	for c in net.parts:
		var part: Dictionary = net.parts[c]
		var pd := {"kind": part.kind, "cell": [c.x, c.y], "dir": part.dir, "sub": part.sub.id,
			"items": part.items.map(func(p): return SaveGame.p_to(p)),
			"out_q": part.get("out_q", []).map(func(p): return SaveGame.p_to(p)),
			"busy": SaveGame.p_to(part.busy) if part.get("busy") != null else null,
			"progress": part.get("progress", 0.0), "cd": part.get("cd", 0.0),
			"gas": net.gas.amount(part.id)}
		if part.has("temp"):
			pd.temp = part.temp
		var cap = part.get("cap")
		if cap != null:
			pd.cap = {"p": SaveGame.p_to(cap.p), "cell": [cap.cell.x, cap.cell.y], "from": [cap.from.x, cap.from.y], "t": cap.t}
		parts.append(pd)
	return {"parts": parts, "produced": net.produced.duplicate(),
		"launched": {"kg": net.launched_kg, "subs": net.launched_subs.duplicate()}}

static func _net_from(net, planet: Planet, d: Dictionary) -> void:
	for c in net.parts.keys():
		net.remove(c)
	for pd in d.get("parts", []):
		var sub := planet.db.get_sub(str(pd.sub))
		if sub == null:
			continue
		var part: Dictionary = net.place(str(pd.kind), SaveGame.v2i(pd.cell), int(pd.dir), sub)
		if part.is_empty():
			continue
		part.items = []
		for a in pd.items:
			var p := _p_from(planet, a)
			if p != null:
				part.items.append(p)
		part.out_q = []
		for a in pd.get("out_q", []):
			var oq := _p_from(planet, a)
			if oq != null:
				part.out_q.append(oq)
		part.busy = _p_from(planet, pd.busy)
		part.progress = float(pd.progress)
		part.cd = float(pd.cd)
		if pd.has("temp"):
			part.temp = float(pd.temp)
		if pd.has("cap"):
			var cp := _p_from(planet, pd.cap.p)
			if cp != null:
				part.cap = {"p": cp, "cell": SaveGame.v2i(pd.cap.cell), "from": SaveGame.v2i(pd.cap.from), "t": float(pd.cap.t)}
	# Газ — после всех деталей: place() заполняет новые детали атмосферой.
	for pd in d.get("parts", []):
		var c := SaveGame.v2i(pd.cell)
		if not net.parts.has(c):
			continue
		var id: int = net.parts[c].id
		net.gas.take_gas(id, net.gas.amount(id))
		net.gas.add_gas(id, float(pd.gas))
	net.produced = {}
	var pr: Dictionary = d.get("produced", {})
	for k in pr:
		net.produced[k] = float(pr[k])
	var la: Dictionary = d.get("launched", {})
	net.launched_kg = float(la.get("kg", 0.0))
	net.launched_subs = {}
	for k in la.get("subs", {}):
		net.launched_subs[k] = float(la.subs[k])
	net.events.clear()

# ---------------------------------------------------------------- мелочи

static func _p_from(planet: Planet, a) -> Portion:
	if a == null:
		return null
	var s := planet.db.get_sub(str(a[0]))
	if s == null:
		return null
	return Portion.new(s, float(a[1]), float(a[2]))

## JSON читает все числа как float; целые id друз возвращаем в int.
static func _ints(v):
	if v is Array:
		return v.map(func(x): return _ints(x))
	if v is float and v == floorf(v):
		return int(v)
	return v

static func _v3(v: Vector3) -> Array:
	return [v.x, v.y, v.z]

static func _to_v3(a) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2]))
