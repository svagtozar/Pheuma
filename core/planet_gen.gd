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

	p.goal = _choose_goal(p, rng.fork("goal"))
	_ensure_goal_feasible(p, rng.fork("carrier"), exotic_mult)
	for m in p.materials:
		p.db.add(m)
	p.atmosphere = _make_atmosphere(p)
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
	var rare := _choose_rare_tag(p, rng)
	for st in goal.stages:
		if st.has("tag") and st.tag == "{rare}":
			st.tag = rare
		if st.has("tags") and st.tags.has("{rare}"):
			var m: float = st.tags["{rare}"]
			st.tags.erase("{rare}")
			st.tags[rare] = m
	goal.rare = rare
	return goal

## Редкий тег: достижим переработкой, но нет ни у одного исходного материала.
static func _choose_rare_tag(p: Planet, rng: Rng) -> String:
	var present := p.material_tags_present()
	var have := Recipes.reachable(present, p.tags)
	var cands: Array = []
	for t in MaterialTags.normal_tags():
		if have.has(t) and not t in present:
			cands.append(t)
	cands.sort()
	if cands.is_empty():
		return present[0] if not present.is_empty() else "dense"
	return rng.pick(cands)

## Если нужный цели тег недостижим — подмешиваем материал-носитель с этим тегом.
static func _ensure_goal_feasible(p: Planet, rng: Rng, exotic_mult: float) -> void:
	var used := {}
	for m in p.materials:
		used[m.root] = true
	var weights := MaterialGen.tag_weights(p.tags, exotic_mult)
	for t in Goals.required_tags(p.goal):
		var have := Recipes.reachable(p.material_tags_present(), p.tags)
		if not have.has(t):
			p.materials.append(MaterialGen.generate_one(rng, weights, used, [t]))

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
