class_name PlanetGen
## Генерация планеты по seed. Всё детерминировано.

const PREFIX := ["Кеп", "Ауро", "Тэл", "Ми", "Ксен", "Ор", "Вэй", "Сил", "Нур", "Грэ", "Иль", "Дзе"]
const SUFFIX := ["ра", "ион", "ус", "эя", "ант", "ида", "ос", "ен"]

## forced_tags — задать теги планеты вручную (учебная планета).
static func generate(seed_value: int, width: int = 80, height: int = 60, forced_tags: Array = []) -> Planet:
	var p := Planet.new()
	var rng := Rng.new(seed_value)
	p.seed_value = seed_value
	p.width = width
	p.height = height
	var nr := rng.fork("name")
	p.name = "%s%s-%d" % [nr.pick(PREFIX), nr.pick(SUFFIX), nr.range_i(2, 99)]

	if forced_tags.is_empty():
		p.tags = TagPool.pick(rng.fork("ptags"), PlanetTags.all(), rng.fork("pcount").range_i(3, 5),
			PlanetTags.pick_weights(), PlanetTags.compatible)
	else:
		p.tags = forced_tags.duplicate()
		p.tags.sort()
		p.forced = true
	_apply_environment(p)

	var exotic_mult := 1.0
	for t in p.tags:
		exotic_mult *= PlanetTags.TAGS[t].get("exotic_mult", 1.0)
	var mr := rng.fork("mats")
	p.materials = MaterialGen.generate(mr, mr.range_i(8, 12), p.tags, exotic_mult)

	p.atmosphere = _make_atmosphere(p)
	p.goal = _choose_goal(p, rng.fork("goal"))
	_ensure_goal_feasible(p, rng.fork("carrier"), exotic_mult)
	_ensure_buildable(p, rng.fork("builder"), exotic_mult)
	for m in p.materials:
		p.db.add(m)
	p.db.add(p.atmosphere)

	_generate_map(p, rng.fork("map"))
	_place_deposits(p, rng.fork("deposits"))
	return p

static func _apply_environment(p: Planet) -> void:
	p.ambient_temp = PlanetTags.BASE_TEMP
	p.atm_pressure = PlanetTags.BASE_PRESSURE
	p.gravity = PlanetTags.BASE_GRAVITY
	for t in p.tags:
		var d: Dictionary = PlanetTags.TAGS[t]
		p.ambient_temp += d.get("temp", 0.0)
		p.atm_pressure *= d.get("press", 1.0)
		p.gravity *= d.get("grav", 1.0)

static func _make_atmosphere(p: Planet) -> Substance:
	var tags: Array = ["volatile"]
	for t in p.tags:
		for a in PlanetTags.TAGS[t].get("atm", []):
			tags = MaterialTags.add_tag(tags, a)
	var s := Substance.new("atm", "Атмосфера", tags)
	# Атмосфера всегда газ при температуре среды.
	s.noise.boil += (p.ambient_temp - 90.0) - s.boil
	s.noise.melt += (p.ambient_temp - 150.0) - s.melt
	s.recompute()
	s.name = "Атмосфера"
	return s

static func _choose_goal(p: Planet, rng: Rng) -> Dictionary:
	var weights := {}
	var ids: Array = Goals.TEMPLATES.keys()
	ids.sort()
	for id in ids:
		var w: float = Goals.TEMPLATES[id].w
		if id == "anomaly" and p.has_anomaly():
			w = 1.0
		for t in p.tags:
			w *= PlanetTags.TAGS[t].get("goals", {}).get(id, 1.0)
		weights[id] = w
	var gid: String = rng.weighted_pick(ids, weights)
	var goal: Dictionary = Goals.TEMPLATES[gid].duplicate(true)
	goal.id = gid
	var flat: Array = []
	for raw in goal.stages:
		flat.append_array(Goals.options(raw))
	# «Узнать N тегов» — не больше, чем тегов в местном сырье: на бедной планете планка ниже.
	var present_n: int = p.material_tags_present().size()
	for st in flat:
		if st.type == "discover_tags" and st.n > present_n:
			st.n = max(12, present_n)
			st.desc = "Узнать %d тегов" % st.n
	var uses_rare := false
	for st in flat:
		if st.get("tag", "") == "{rare}" or st.get("tags", {}).has("{rare}"):
			uses_rare = true
	var rare := _choose_rare_tag(p, rng, uses_rare)
	for st in flat:
		if st.has("tag") and st.tag == "{rare}":
			st.tag = rare
		if st.has("tags") and st.tags.has("{rare}"):
			var m: float = st.tags["{rare}"]
			st.tags.erase("{rare}")
			st.tags[rare] = m
	goal.rare = rare
	return goal

## Проба для планировщика: своя база веществ и робот со стартовыми открытиями.
## Planner пользуется только полями db, planet и robot.
class Probe:
	var db := SubstanceDB.new()
	var planet: Planet
	var robot := RobotState.new()

static func _probe(p: Planet) -> Probe:
	var pr := Probe.new()
	pr.planet = p
	pr.robot.drill = pr.robot.new_module("hand_drill", World.starter_substance(), 0.0)
	for m in p.materials:
		pr.db.add(m)
	return pr

## Тег получается настоящей обработкой (с фазами и температурами), а не только по таблице тегов.
static func _obtainable(pr: Probe, t: String, mats: Array) -> bool:
	for m in mats:
		if m.has(t):
			return true
	return Planner.feasible(pr, t, mats)

## Редкий тег: достижим переработкой, но нет ни у одного исходного материала.
static func _choose_rare_tag(p: Planet, rng: Rng, check: bool) -> String:
	var present := p.material_tags_present()
	var have := Recipes.reachable(present, p.tags)
	var cands: Array = []
	for t in MaterialTags.normal_tags():
		if have.has(t) and not t in present:
			cands.append(t)
	cands.sort()
	if cands.is_empty():
		return present[0] if not present.is_empty() else "dense"
	var start := rng.range_i(0, cands.size() - 1)
	if not check:
		return cands[start]
	var pr := _probe(p)
	for i in cands.size():
		var t: String = cands[(start + i) % cands.size()]
		if Planner.feasible(pr, t, p.materials):
			return t
	return cands[start]

## Если нужный цели тег не получить — подмешиваем материал-носитель с этим тегом:
## твёрдый при температуре среды и по зубам стартовому буру (если получится).
static func _ensure_goal_feasible(p: Planet, rng: Rng, exotic_mult: float) -> void:
	var used := {}
	for m in p.materials:
		used[m.root] = true
	var weights := MaterialGen.tag_weights(p.tags, exotic_mult)
	var pr := _probe(p)
	var drill: float = pr.robot.mining_hardness() + 0.5
	for t in Goals.required_tags(p.goal):
		if _obtainable(pr, t, p.materials):
			continue
		var best: Substance = null
		for _i in 5:
			var s := MaterialGen.generate_one(rng, weights, used, [t])
			best = s
			if s.phase_at(p.ambient_temp) == Substance.Phase.SOLID and s.hardness <= drill:
				break
		p.materials.append(best)
		pr.db.add(best)

## Машины, которые понадобятся под каждый тип этапа (все варианты развилок).
const STAGE_KINDS := {
	"launch_mass": ["launch_silo"], "launch_tag": ["launch_silo"], "launch_exotic": ["launch_silo"],
	"dome_env": ["dome", "furnace", "sensor"], "beacon_hold": ["beacon"],
	"deliveries": ["cannon", "receiver"], "sensor_network": ["sensor", "valve"],
	"machines_working": ["furnace"],
}
const BASE_KINDS := ["drill", "container", "tank", "pump", "pipe"]
const MAX_BUILDERS := 3

## Нужные машины: базовые, машины цепочек тегов цели и машины этапов.
## Возвращает {kind: true} и заполняет ores — исходные материалы цепочек (под бур).
static func _needed_kinds(p: Planet, pr: Probe, ores: Array) -> Dictionary:
	var kinds := {}
	for k in BASE_KINDS:
		kinds[k] = true
	var flat: Array = []
	for raw in p.goal.stages:
		flat.append_array(Goals.options(raw))
	for st in flat:
		for k in STAGE_KINDS.get(st.type, []):
			kinds[k] = true
		if st.type == "build_count":
			kinds[st.kind] = true
	for t in Goals.required_tags(p.goal):
		var pl := Planner.probe_plan(pr, t, p.materials)
		if pl.is_empty():
			continue
		if not pl.mat in ores:
			ores.append(pl.mat)
		for step in pl.steps:
			kinds[step.kind] = true
	return kinds

## Что берёт стартовый ручной бур робота (твёрдость + 0.5).
static func _drill_limit() -> float:
	var r := RobotState.new()
	r.drill = r.new_module("hand_drill", World.starter_substance(), 0.0)
	return r.mining_hardness() + 0.5

## Есть ли материал планеты для постройки: подходит по свойствам, копается
## стартовым буром и безопасен в руках. min_hard — для бура под твёрдую руду.
static func _buildable_from(p: Planet, kind: String, min_hard: float = 0.0) -> bool:
	var drill: float = _drill_limit()
	for s in p.materials:
		if s.hardness > drill or s.hardness < min_hard:
			continue
		if Buildings.check_material(kind, s, p.ambient_temp) != "":
			continue
		if Handling.safe_to_carry(s, p):
			return true
	return false

## Если нужную машину не из чего построить — добавляем «строительный» материал.
static func _ensure_buildable(p: Planet, rng: Rng, exotic_mult: float) -> void:
	var used := {}
	for m in p.materials:
		used[m.root] = true
	var weights := MaterialGen.tag_weights(p.tags, exotic_mult)
	var pr := _probe(p)
	var ores: Array = []
	var kinds: Array = _needed_kinds(p, pr, ores).keys()
	kinds.sort()
	# Бур под каждую руду цепочек: не мягче руды − 0.5.
	var needs: Array = []
	for k in kinds:
		needs.append([k, 0.0])
	var drill_max: float = _drill_limit()
	for ore in ores:
		if ore.hardness - 0.5 > Buildings.KINDS.drill.hard and ore.hardness - 0.5 <= drill_max:
			needs.append(["drill", ore.hardness - 0.5])
	var added := 0
	for nd in needs:
		var kind: String = nd[0]
		var min_hard: float = nd[1]
		if _buildable_from(p, kind, min_hard):
			continue
		if added >= MAX_BUILDERS:
			p.unbuildable.append(kind)
			continue
		var d: Dictionary = Buildings.KINDS[kind]
		var forced: Array = [d.any[0]] if d.has("any") else (["dense"] if d.has("min_p") else ["metallic"])
		var ok := false
		for _i in 8:
			var s := MaterialGen.generate_one(rng, weights, used, forced)
			p.materials.append(s)
			if _buildable_from(p, kind, min_hard):
				ok = true
				added += 1
				pr.db.add(s)
				break
			p.materials.pop_back()
		if not ok:
			p.unbuildable.append(kind)

static func _noise(rng: Rng, freq: float, type: int = FastNoiseLite.TYPE_SIMPLEX_SMOOTH) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = rng.range_i(0, 1 << 30)
	n.frequency = freq
	n.noise_type = type
	return n

static func _generate_map(p: Planet, rng: Rng) -> void:
	p.tiles.resize(p.width * p.height)
	var h := _noise(rng, 0.06)
	var ridge := _noise(rng, 0.035)
	var lava := _noise(rng, 0.03)
	var wet := _noise(rng, 0.05)
	var chasm_w := 0.05 if p.has_tag("seismic") else 0.025
	for y in p.height:
		for x in p.width:
			var t := Planet.Tile.GROUND
			var hv := h.get_noise_2d(x, y)
			var wv := wet.get_noise_2d(x, y)
			if hv > 0.42:
				t = Planet.Tile.ROCK
			elif abs(ridge.get_noise_2d(x, y)) < chasm_w:
				t = Planet.Tile.CHASM
			elif p.has_tag("volcanic") and abs(lava.get_noise_2d(x, y)) < 0.045:
				t = Planet.Tile.LAVA
			elif (p.has_tag("acid_rain") or p.has_tag("oceanic")) and wv < -0.45:
				t = Planet.Tile.ACID
			elif p.has_tag("frozen") and wv > 0.35:
				t = Planet.Tile.ICE
			p.tiles[y * p.width + x] = t
	# Края карты — скалы.
	for x in p.width:
		p.set_tile(Vector2i(x, 0), Planet.Tile.ROCK)
		p.set_tile(Vector2i(x, p.height - 1), Planet.Tile.ROCK)
	for y in p.height:
		p.set_tile(Vector2i(0, y), Planet.Tile.ROCK)
		p.set_tile(Vector2i(p.width - 1, y), Planet.Tile.ROCK)
	if p.has_tag("ancient_ruins"):
		for _i in 4:
			var c := Vector2i(rng.range_i(5, p.width - 6), rng.range_i(5, p.height - 6))
			for dy in range(-2, 3):
				for dx in range(-2, 3):
					p.set_tile(c + Vector2i(dx, dy), Planet.Tile.RUIN)
	p.spawn = Vector2i(p.width / 2, p.height / 2)
	for dy in range(-6, 7):
		for dx in range(-6, 7):
			if dx * dx + dy * dy <= 36:
				p.set_tile(p.spawn + Vector2i(dx, dy), Planet.Tile.GROUND)

static func _place_deposits(p: Planet, rng: Rng) -> void:
	var mats: Array = p.materials.duplicate()
	mats.sort_custom(func(a, b): return a.hardness < b.hardness)
	for i in mats.size():
		var m: Substance = mats[i]
		var clusters := rng.range_i(2, 4)
		for k in clusters:
			var center: Vector2i
			if i < 3 and k == 0:
				# Самые мягкие материалы — рядом со стартом, чтобы было с чего начать.
				center = p.spawn + Vector2i(rng.range_i(-12, 12), rng.range_i(-12, 12))
				if (center - p.spawn).length() < 4:
					center += Vector2i(5, 0)
			elif m.is_exotic() or rng.chance(0.3):
				center = _cell_near_obstacle(p, rng)
			else:
				center = Vector2i(rng.range_i(3, p.width - 4), rng.range_i(3, p.height - 4))
			var r := rng.range_i(1, 2)
			for dy in range(-r, r + 1):
				for dx in range(-r, r + 1):
					var c := center + Vector2i(dx, dy)
					if dx * dx + dy * dy > r * r + 1 or not p.buildable(c) or p.deposits.has(c):
						continue
					if (c - p.spawn).length() < 3:
						continue
					p.deposits[c] = {"sub": m.id, "amount": rng.range_f(60.0, 150.0)}

## Клетка грунта рядом с препятствием: такие залежи требуют абилок мобильности.
static func _cell_near_obstacle(p: Planet, rng: Rng) -> Vector2i:
	for _i in 200:
		var c := Vector2i(rng.range_i(3, p.width - 4), rng.range_i(3, p.height - 4))
		if not p.buildable(c):
			continue
		for d in [Vector2i(2, 0), Vector2i(-2, 0), Vector2i(0, 2), Vector2i(0, -2)]:
			var t := p.tile(c + d)
			if t == Planet.Tile.CHASM or t == Planet.Tile.LAVA or t == Planet.Tile.ACID:
				return c
	return Vector2i(rng.range_i(3, p.width - 4), rng.range_i(3, p.height - 4))
