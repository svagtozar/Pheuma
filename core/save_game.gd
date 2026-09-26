class_name SaveGame
## Сохранение и загрузка рана. Планета восстанавливается из seed,
## поверх неё накладываются изменения: карта, залежи, производные материалы,
## постройки, сети, порции, робот, прогресс цели.

const VERSION := 1
static var DIR := "user://saves"   # тесты подменяют на свою папку

static func v2i(a) -> Vector2i:
	return Vector2i(int(a[0]), int(a[1]))

static func p_to(p: Portion) -> Array:
	return [p.substance.id, p.mass, p.temp]

static func p_from(w: World, a) -> Portion:
	if a == null:
		return null
	var s := w.db.get_sub(a[0])
	if s == null:
		return null
	return Portion.new(s, float(a[1]), float(a[2]))

static func mod_to(m) -> Dictionary:
	if m == null:
		return {}
	return {"uid": m.uid, "kind": m.kind, "sub": m.sub.id, "q": m.get("q", 0.0)}

static func mod_from(w: World, d: Dictionary):
	if d.is_empty():
		return null
	var sub := w.db.get_sub(d.sub)
	var sk: String = d.kind if d.kind in ["hull", "hand_drill"] else "module"
	return {"uid": int(d.uid), "kind": d.kind, "sub": sub, "q": float(d.q), "stats": ComponentStats.compute(sk, sub, float(d.q))}

static func machine_to(m: Machine, gas: GasNet) -> Dictionary:
	var md := {"id": m.id, "kind": m.kind, "cell": [m.cell.x, m.cell.y], "facing": m.facing, "sub": m.built_from.id,
		"q": m.quality, "hp": m.hp, "config": m.config, "off": m.manual_off,
		"items": m.items.map(func(p): return p_to(p)),
		"out": m.out_queue.map(func(e): return [p_to(e[0]), e[1]])}
	if m.has_gas():
		md.gas = gas.amount(m.id)
	if m is Processor:
		md.busy = p_to(m.busy) if m.busy != null else null
		md.reagent = p_to(m.reagent) if m.reagent != null else null
		md.progress = m.progress
	if m is Dome:
		md.temp = m.temp
	if m.master_id >= 0 or m is MacroMachine:
		md.extra = m.save_extra()
	return md

static func machine_restore(w: World, m: Machine, md: Dictionary, gas: GasNet) -> void:
	var sub := w.db.get_sub(md.sub)
	m.quality = float(md.q)
	m.stats = ComponentStats.compute(m.kind, sub, m.quality)
	m.hp = float(md.hp)
	m.manual_off = md.off
	for k in md.config:
		var v = md.config[k]
		if k == "target":
			v = int(v)
		elif k == "routes":
			v = v.map(func(r): return [r[0], int(r[1])])
		m.config[k] = v
	m.items = md.items.map(func(a): return p_from(w, a)).filter(func(p): return p != null)
	m.out_queue = md.out.map(func(e): return [p_from(w, e[0]), int(e[1])]).filter(func(e): return e[0] != null)
	if m is Processor:
		m.busy = p_from(w, md.get("busy"))
		m.reagent = p_from(w, md.get("reagent"))
		m.progress = float(md.get("progress", 0.0))
	if m is Dome:
		m.temp = float(md.get("temp", w.planet.ambient_temp))
	# Сначала extra: свёрнутый блок заводит в нём свой газовый узел, потом газ.
	if md.has("extra"):
		m.load_extra(w, md.extra)
	if md.has("gas") and gas.has_node(m.id):
		gas.nodes[m.id].n = float(md.gas)

static func to_dict(w: World) -> Dictionary:
	var d := {"version": VERSION, "seed": w.planet.seed_value, "time": w.time,
		"forced": w.planet.tags if w.planet.forced else []}
	d.tiles = Marshalls.raw_to_base64(w.planet.tiles)
	var dep := {}
	for c in w.planet.deposits:
		dep["%d,%d" % [c.x, c.y]] = {"sub": w.planet.deposits[c].sub, "amount": w.planet.deposits[c].amount}
	d.deposits = dep
	# Материалы планеты: после генерации могут добавиться новые (экзотика метеоритов).
	d.planet_materials = w.planet.materials.map(func(s): return {"id": s.id, "name": s.name, "tags": s.tags, "noise": s.noise})
	var derived: Array = []
	for s in w.db.all():
		if "#" in s.id:
			derived.append({"id": s.id, "root": s.root, "name": s.name, "tags": s.tags})
	d.substances = derived
	var ms: Array = []
	for m in w.machines.values():
		ms.append(machine_to(m, w.gas))
	d.machines = ms
	d.wires = w.logic.wires.values().map(func(x): return {"from": x.from, "to": x.to, "port": x.port,
		"points": x.points.map(func(p): return [p.x, p.y]), "material": x.material})
	var ground := {}
	for c in w.ground:
		ground["%d,%d" % [c.x, c.y]] = w.ground[c].map(func(p): return p_to(p))
	for pr in w.projectiles:
		if pr.orbit or pr.payload.is_empty():
			continue
		var key := "%d,%d" % [floori(pr.to.x), floori(pr.to.y)]
		if not ground.has(key):
			ground[key] = []
		for p in pr.payload:
			ground[key].append(p_to(p))
	d.ground = ground
	d.drones = w.drones.map(func(x): return {"src": x.src, "dst": x.dst, "pos": [x.pos.x, x.pos.y],
		"speed": x.speed, "cap": x.cap, "cargo": p_to(x.cargo) if x.cargo != null else null})
	d.revealed = w.revealed.keys().map(func(c): return [c.x, c.y])
	d.overrides = w.tile_overrides.keys().map(func(c): return [c.x, c.y, w.tile_overrides[c].tile, w.tile_overrides[c].t])
	d.launched = w.launched
	d.built_kinds = w.built_kinds.keys()
	d.events = w.director.to_dict()
	d.stats = w.stats
	d.meta = w.meta
	d.goals = {"stage": w.goals.stage, "hold": w.goals.hold, "completed": w.goals.completed, "progress": w.goals.progress,
		"choices": w.goals.choices, "reward_pending": w.goals.reward_pending, "base_hits": w.goals.base_hits}
	var r := w.robot
	d.robot = {"pos": [r.pos.x, r.pos.y], "hp": r.hp, "tank": r.tank, "selected": r.selected,
		"inventory": r.inventory.values().map(func(p): return p_to(p)),
		"modules": r.modules.map(func(m): return mod_to(m)), "equipped": r.equipped.map(func(m): return mod_to(m)),
		"hull": mod_to(r.hull), "drill": mod_to(r.drill), "next_module": r._next_module,
		"xp": r.xp, "knowledge": r.knowledge, "learned": r.learned.keys(), "blueprints": r.blueprints.keys(),
		"unlocked": r.unlocked.keys(), "known_tags": r.known_tags.keys(), "analyzed": r.analyzed.keys(),
		"interactions": r.known_interactions.keys(), "last_safe": [r.last_safe.x, r.last_safe.y], "bonus_slots": r.bonus_slots}
	return d

static func from_dict(d: Dictionary) -> World:
	var w := World.create(int(d.seed), d.get("forced", []))
	w.events.clear()
	w.time = float(d.time)
	w.planet.tiles = Marshalls.base64_to_raw(d.tiles)
	for md in d.get("planet_materials", []):
		if w.db.get_sub(md.id) == null:
			var s := Substance.new(md.id, md.id, md.tags, md.noise)
			s.name = md.name
			w.planet.materials.append(s)
			w.db.add(s)
	for k in d.deposits:
		var c := v2i(k.split(","))
		var v = d.deposits[k]
		if typeof(v) == TYPE_DICTIONARY:
			# Новые залежи (метеориты, сейсмозаряд) создаются заново.
			w.planet.deposits[c] = {"sub": str(v.sub), "amount": float(v.amount)}
		elif w.planet.deposits.has(c):
			w.planet.deposits[c].amount = float(v)   # старый формат сохранения
	for s in d.substances:
		w.db.restore(s.id, s.root, s.name, s.tags)
	for md in d.machines:
		var sub := w.db.get_sub(md.sub)
		var m := w.place(md.kind, v2i(md.cell), int(md.facing), sub, true, int(md.id))
		machine_restore(w, m, md, w.gas)
	for x in d.wires:
		w.logic.add_wire(int(x.from), int(x.to), int(x.port), x.points.map(func(p): return Vector2(p[0], p[1])), x.material)
	for k in d.ground:
		w.drop_portions(v2i(k.split(",")), d.ground[k].map(func(a): return p_from(w, a)))
	for x in d.drones:
		w.drones.append({"src": int(x.src), "dst": int(x.dst), "pos": Vector2(x.pos[0], x.pos[1]),
			"speed": float(x.speed), "cap": float(x.cap), "cargo": p_from(w, x.cargo)})
	for c in d.revealed:
		w.revealed[v2i(c)] = true
	for o in d.overrides:
		w.tile_overrides[Vector2i(int(o[0]), int(o[1]))] = {"tile": int(o[2]), "t": float(o[3])}
	w.launched = {"mass": float(d.launched.mass), "tags": d.launched.tags, "exotic": float(d.launched.exotic)}
	w.meta = d.get("meta", {})
	if d.has("stats"):
		for k in d.stats:
			w.stats[k] = int(d.stats[k])
	if d.has("events"):
		w.director.from_dict(d.events)
	w.built_kinds = {}
	for k in d.built_kinds:
		w.built_kinds[k] = true
	w.goals.stage = int(d.goals.stage)
	w.goals.hold = float(d.goals.hold)
	w.goals.completed = d.goals.completed
	w.goals.progress = float(d.goals.progress)
	w.goals.choices = d.goals.get("choices", {})
	w.goals.reward_pending = d.goals.get("reward_pending", [])
	w.goals.base_hits = int(d.goals.get("base_hits", 0))
	var rd: Dictionary = d.robot
	var r := w.robot
	r.pos = Vector2(rd.pos[0], rd.pos[1])
	r.hp = float(rd.hp)
	r.tank = float(rd.tank)
	r.inventory = {}
	for a in rd.inventory:
		var p := p_from(w, a)
		if p != null:
			r.add_item(p)
	r.selected = rd.selected if r.inventory.has(rd.selected) else ""
	r.modules = rd.modules.map(func(m): return mod_from(w, m))
	r.equipped = rd.equipped.map(func(m): return mod_from(w, m))
	r.hull = mod_from(w, rd.hull)
	r.drill = mod_from(w, rd.drill)
	r._next_module = int(rd.next_module)
	for k in rd.xp:
		r.xp[k] = float(rd.xp[k])
	r.knowledge = int(rd.knowledge)
	r.bonus_slots = int(rd.get("bonus_slots", 0))
	r.last_safe = v2i(rd.last_safe)
	r.learned = _as_set(rd.learned)
	r.blueprints = _as_set(rd.blueprints)
	r.unlocked = _as_set(rd.unlocked)
	r.known_tags = _as_set(rd.known_tags)
	r.analyzed = _as_set(rd.analyzed)
	r.known_interactions = _as_set(rd.interactions)
	w.log_event(w.robot_cell(), "Игра загружена")
	return w

static func _as_set(arr: Array) -> Dictionary:
	var out := {}
	for k in arr:
		out[k] = true
	return out

const SLOTS := ["slot1", "slot2", "slot3", "slot4", "slot5"]
const SLOT_NAMES := {"auto": "Автосохранение", "quick": "Быстрое (F5)"}

static func path_for(slot: String) -> String:
	return "%s/%s.json" % [DIR, slot]

static func meta_path(slot: String) -> String:
	return "%s/%s.meta.json" % [DIR, slot]

static func slot_title(slot: String) -> String:
	if SLOT_NAMES.has(slot):
		return SLOT_NAMES[slot]
	return "Слот %s" % slot.trim_prefix("slot")

## Короткое описание сохранения для списка слотов.
static func make_meta(w: World, slot: String) -> Dictionary:
	return {"slot": slot, "planet": w.planet.name, "seed": w.planet.seed_value,
		"tags": w.planet.tags.map(func(t): return PlanetTags.display(t)), "goal": w.planet.goal.n,
		"stage": w.goals.stage + 1, "stages": w.planet.goal.stages.size(), "completed": w.goals.completed,
		"time": w.time, "date": Time.get_datetime_string_from_system(false, true),
		"unix": Time.get_unix_time_from_system(), "tutorial": w.meta.has("tutorial_step")}

static func save_file(w: World, slot: String = "quick") -> String:
	DirAccess.make_dir_recursive_absolute(DIR)
	var f := FileAccess.open(path_for(slot), FileAccess.WRITE)
	if f == null:
		return "не удалось записать сохранение"
	f.store_string(JSON.stringify(to_dict(w)))
	f.close()
	var m := FileAccess.open(meta_path(slot), FileAccess.WRITE)
	if m != null:
		m.store_string(JSON.stringify(make_meta(w, slot)))
	return ""

static func load_file(slot: String = "quick") -> World:
	if not FileAccess.file_exists(path_for(slot)):
		return null
	var data = JSON.parse_string(FileAccess.get_file_as_string(path_for(slot)))
	if typeof(data) != TYPE_DICTIONARY or int(data.get("version", 0)) != VERSION:
		return null
	return from_dict(data)

static func exists(slot: String = "quick") -> bool:
	return FileAccess.file_exists(path_for(slot))

static func delete_slot(slot: String) -> void:
	for p in [path_for(slot), meta_path(slot)]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)

## Описание слота или {} если он пуст.
static func slot_meta(slot: String) -> Dictionary:
	if not exists(slot):
		return {}
	if FileAccess.file_exists(meta_path(slot)):
		var d = JSON.parse_string(FileAccess.get_file_as_string(meta_path(slot)))
		if typeof(d) == TYPE_DICTIONARY:
			return d
	return {"slot": slot, "planet": "?", "goal": "", "stage": 0, "stages": 0, "time": 0.0, "date": "", "unix": 0}

## Все слоты: автосохранение, быстрое, ручные.
static func all_slots() -> Array:
	return ["auto", "quick"] + SLOTS

## Самое свежее сохранение ("" — нет ни одного).
static func latest_slot() -> String:
	var best := ""
	var t := -1.0
	for s in all_slots():
		var m := slot_meta(s)
		if not m.is_empty() and float(m.get("unix", 0)) > t:
			t = float(m.get("unix", 0))
			best = s
	return best

static func format_time(sec: float) -> String:
	var m := int(sec) / 60
	return "%d ч %02d мин" % [m / 60, m % 60] if m >= 60 else "%d мин" % m
