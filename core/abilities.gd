class_name Abilities
## Активные абилки модулей робота. Каждая тратит газ из бортового баллона.
## Возвращают текст ошибки или "".

static func use(w: World, kind: String, target: Vector2) -> String:
	var r := w.robot
	var m = r.module(kind)
	if m == null:
		return "модуль не установлен"
	var d: Dictionary = Modules.MODULES[kind]
	if not d.get("active", false):
		return "у модуля нет активной абилки"
	if r.cooldowns.has(kind):
		return "перезарядка"
	var cost: float = d.get("gas", 0.0)
	if r.tank + 0.001 < cost:
		return "мало газа в баллоне (R — подкачать)"
	var err: String = _dispatch(kind, w, m, target)
	if err != "":
		return err
	r.tank -= cost
	r.cooldowns[kind] = d.get("cd", 0.5)
	w.sound("whoosh", r.cell())
	return ""

static func _dispatch(kind: String, w: World, m: Dictionary, target: Vector2) -> String:
	match kind:
		"hook": return hook(w, m, target)
		"jet": return jet(w, m, target)
		"hand_cannon": return hand_cannon(w, m, target)
		"lance": return lance(w, m, target)
		"cryo": return cryo(w, m, target)
		"scanner": return scanner(w, m, target)
		"magnet": return magnet(w, m, target)
		"sampler": return sampler(w, m, target)
		"analyzer": return analyzer(w, m, target)
		"drone": return drone(w, m, target)
		"relay": return relay(w, m, target)
		"repair": return repair(w, m, target)
		"seismic_charge": return seismic_charge(w, m, target)
		"field_forge": return field_forge(w, m, target)
		"tuning_fork": return tuning_fork(w, m, target)
	return "неизвестная абилка"

## Новые залежи у курсора: материал — один из тех, что уже есть на планете.
static func seismic_charge(w: World, m: Dictionary, target: Vector2) -> String:
	var c := cell_of(target)
	if not w.near_robot(c, 10.0):
		return "слишком далеко"
	var mats: Array = w.planet.materials.filter(func(s): return not s.is_exotic())
	if mats.is_empty():
		return "нечему выходить на поверхность"
	var sub: Substance = w.rng.pick(mats)
	var want := 5 if m.sub.has("dense") else 3
	var n := 0
	for r in range(0, 4):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var q := c + Vector2i(dx, dy)
				if n >= want or max(abs(dx), abs(dy)) != r:
					continue
				if not w.planet.buildable(q) or w.planet.deposits.has(q) or w.grid.has(q) or w.tile_overrides.has(q):
					continue
				w.planet.deposits[q] = {"sub": sub.id, "amount": w.rng.range_f(40.0, 80.0)}
				w.revealed[q] = true
				n += 1
	if n == 0:
		return "здесь некуда: нужен свободный грунт"
	w.sound("boom", c)
	w.robot.xp.gatherer += 3.0
	w.log_event(c, "Сейсмозаряд: вышли жилы «%s» — %d" % [sub.name, n])
	return ""

## Спекание выбранного материала в руках (правила спекателя).
static func field_forge(w: World, _m: Dictionary, _target: Vector2) -> String:
	var r := w.robot
	if r.selected == "" or r.mass_of(r.selected) < 1.0:
		return "выберите в инвентаре материал (нужно хотя бы 1 кг)"
	var p := r.take_item(r.selected, min(3.0, r.mass_of(r.selected)))
	var ctx := {"db": w.db, "pressure": 0.0, "compress_bonus": 0.0, "target_t": 900.0,
		"ambient": w.planet.ambient_temp, "reagent": null, "filter_tag": ""}
	var res := Processor.run("sinter", p, ctx)
	var out: Portion = res.outs[0][0] if not res.outs.is_empty() else p
	out.temp = w.planet.ambient_temp
	r.add_item(out)
	if out.substance == p.substance:
		return "кузня не меняет этот материал"
	for t in res.added:
		w.discover_tag(t)
	r.selected = out.substance.id
	r.xp.crafter += 2.0
	w.log_event(r.cell(), "Кузня: %s → %s" % [p.substance.name, w.sub_label(out.substance)])
	return ""

## Анализ всего в радиусе у курсора.
static func tuning_fork(w: World, m: Dictionary, target: Vector2) -> String:
	var c := cell_of(target)
	if not w.near_robot(c, 10.0):
		return "слишком далеко"
	var radius := 6 if m.sub.has("crystalline") else 4
	var seen := {}
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			if dx * dx + dy * dy > radius * radius:
				continue
			for s in substances_at(w, c + Vector2i(dx, dy)):
				seen[s.id] = s
	if seen.is_empty():
		return "вокруг нечего слушать"
	# Касание всего вокруг и бесплатная проба «Ток» — камертон звенит в ответ.
	for s in seen.values():
		w.touch(s)
		w.probe(s.id, "spark", true)
	w.robot.xp.shaman += 1.0
	w.log_event(c, "Камертон: веществ услышано — %d" % seen.size())
	return ""

static func cell_of(v: Vector2) -> Vector2i:
	return Vector2i(floori(v.x), floori(v.y))

static func center(c: Vector2i) -> Vector2:
	return Vector2(c) + Vector2(0.5, 0.5)

static func hook_range(w: World, m: Dictionary) -> float:
	return 5.0 * m.stats.flex + 1.0

static func jet_range(w: World, m: Dictionary) -> float:
	return 3.5 / sqrt(w.planet.gravity) * clamp(80.0 / w.robot.total_mass(), 0.6, 1.6)

static func _no_rock_between(w: World, a: Vector2, b: Vector2) -> bool:
	var n := int(a.distance_to(b) * 3.0) + 1
	for i in n:
		var p := a.lerp(b, float(i) / n)
		if w.tile(cell_of(p)) == Planet.Tile.ROCK:
			return false
	return true

static func hook(w: World, m: Dictionary, target: Vector2) -> String:
	var c := cell_of(target)
	if not w.walkable(c):
		return "крюку не за что зацепиться"
	if w.robot.pos.distance_to(center(c)) > hook_range(w, m):
		return "слишком далеко (%.1f кл.)" % hook_range(w, m)
	if not _no_rock_between(w, w.robot.pos, center(c)):
		return "мешает скала"
	w.robot.pos = center(c)
	w.robot.xp.hunter += 2.0
	return ""

static func jet(w: World, m: Dictionary, target: Vector2) -> String:
	var dir := (target - w.robot.pos)
	if dir.length() < 0.1:
		return "укажите направление"
	var dist: float = min(dir.length(), jet_range(w, m))
	var land := w.robot.pos + dir.normalized() * dist
	if not w.walkable(cell_of(land)):
		return "некуда приземлиться"
	w.robot.pos = land
	w.robot.xp.hunter += 2.0
	return ""

static func hand_cannon(w: World, m: Dictionary, target: Vector2) -> String:
	var r := w.robot
	if r.selected == "":
		return "выберите материал для выстрела"
	if r.pos.distance_to(target) > 9.0 * m.stats.flex:
		return "слишком далеко"
	var p := r.take_item(r.selected, 1.0)
	w.spawn_projectile(r.pos, target, [p], false, "shot")
	r.xp.firekeeper += 1.0
	return ""

static func lance(w: World, m: Dictionary, target: Vector2) -> String:
	var c := cell_of(target)
	if not w.near_robot(c, 3.5):
		return "слишком далеко"
	if w.ground.has(c):
		for p in w.ground[c]:
			if p.has("flammable") or p.has("pyrophoric"):
				w.fires[c] = 6.0
	var dep = w.planet.deposits.get(c)
	if dep == null or dep.amount <= 0.0:
		return "" if w.fires.has(c) else "нечего плавить"
	var s: Substance = w.db.get_sub(dep.sub)
	var power: float = m.stats.max_t + 300.0
	if s.melt > power:
		return "копьё недостаточно горячее (нужно плавить %.0f °C)" % s.melt
	var mass: float = min(2.0, dep.amount)
	dep.amount -= mass
	w.drop_portions(c, [Portion.new(s, mass, s.melt + 50.0)])
	w.robot.xp.firekeeper += 1.0
	return ""

static func cryo(w: World, m: Dictionary, target: Vector2) -> String:
	var c := cell_of(target)
	if not w.near_robot(c, 4.5):
		return "слишком далеко"
	var dur := 20.0 * (1.5 if m.sub.has("insulating") else 1.0)
	var t := w.tile(c)
	var did := false
	if t == Planet.Tile.LAVA or t == Planet.Tile.ACID:
		w.tile_overrides[c] = {"tile": Planet.Tile.GROUND, "t": dur}
		did = true
	if w.fires.has(c):
		w.fires.erase(c)
		did = true
	if w.ground.has(c):
		for p in w.ground[c]:
			p.temp -= 150.0
		did = true
	for p in w.robot.inventory.values():
		if p.temp > w.planet.ambient_temp + 50.0:
			p.temp = w.planet.ambient_temp
			did = true
	return "" if did else "нечего замораживать"

static func scanner(w: World, m: Dictionary, _target: Vector2) -> String:
	var radius := 12.0 * (1.5 if m.sub.has("luminous") else 1.0)
	var n := 0
	for c in w.planet.deposits:
		if w.near_robot(c, radius) and not w.revealed.has(c):
			w.revealed[c] = true
			n += 1
	w.robot.xp.gatherer += 2.0
	w.log_event(w.robot_cell(), "Сканер: найдено залежей — %d" % n)
	return ""

static func magnet(w: World, m: Dictionary, _target: Vector2) -> String:
	var radius := 6.0 * (1.5 if m.sub.has("magnetic") else 1.0)
	var n := 0
	for c in w.ground.keys():
		if not w.near_robot(c, radius):
			continue
		var keep: Array = []
		for p in w.ground[c]:
			if (p.has("magnetic") or w.near_robot(c, radius * 0.4)) and w.robot.can_carry(p):
				w.robot.add_item(p)
				n += 1
			else:
				keep.append(p)
		if keep.is_empty():
			w.ground.erase(c)
		else:
			w.ground[c] = keep
	return "" if n > 0 else "поблизости нечего притянуть"

static func sampler(w: World, _m: Dictionary, _target: Vector2) -> String:
	w.analyze(w.planet.atmosphere)
	w.robot.xp.gatherer += 1.0
	return ""

## Материал в клетке: залежь, порция на земле или груз машины.
static func substances_at(w: World, c: Vector2i) -> Array:
	var out: Array = []
	var dep = w.planet.deposits.get(c)
	if dep != null:
		out.append(w.db.get_sub(dep.sub))
	for p in w.ground.get(c, []):
		out.append(p.substance)
	var mm = w.machine_at(c)
	if mm != null:
		for p in mm.items:
			out.append(p.substance)
		out.append(mm.built_from)
	return out

static func analyzer(w: World, _m: Dictionary, target: Vector2) -> String:
	var c := cell_of(target)
	if not w.near_robot(c, 8.0):
		return "слишком далеко"
	var subs := substances_at(w, c)
	if subs.is_empty():
		return "здесь нечего анализировать"
	if reveal_one_each(w, subs) == 0:
		return "здесь всё уже известно"
	return ""

## Анализатор раскрывает по одному неизвестному тегу у каждого вещества
## (общий с 3D-видом и прототипом). Возвращает, у скольких узнал новое.
static func reveal_one_each(w: World, subs: Array) -> int:
	var n := 0
	for s in subs:
		w.touch(s)
		var hidden: Array = s.tags.filter(func(t): return not t in w.known_tags_of(s))
		if not hidden.is_empty():
			w.reveal(s, w.rng.pick(hidden), "анализатор")
			n += 1
	return n

static func drone(w: World, m: Dictionary, target: Vector2) -> String:
	var mm = w.machine_at(cell_of(target))
	if mm == null:
		return "укажите машину"
	if w.drone_pending < 0:
		w.drone_pending = mm.id
		w.log_event(mm.cell, "Дрон: источник выбран, укажите получателя")
		return ""
	var limit := 1 + int(w.robot.passive("drones"))
	if w.drones.size() >= limit:
		w.drones.remove_at(0)
	var src = w.machines.get(w.drone_pending)
	w.drone_pending = -1
	if src == null or src == mm:
		return "нужны две разные машины"
	var speed := clampf(6.0 / maxf(0.5, m.sub.density), 1.5, 8.0)
	w.drones.append({"src": src.id, "dst": mm.id, "pos": center(src.cell), "cargo": null, "speed": speed, "cap": 2.0})
	w.robot.xp.chief += 3.0
	return ""

static func relay(w: World, _m: Dictionary, target: Vector2) -> String:
	var mm = w.machine_at(cell_of(target))
	if mm == null:
		return "укажите машину"
	if not w.near_robot(mm.cell, 25.0):
		return "вне зоны связи"
	mm.manual_off = not mm.manual_off
	w.log_event(mm.cell, "%s %s" % [mm.display_name(), "выключен" if mm.manual_off else "включён"])
	return ""

static func repair(w: World, _m: Dictionary, target: Vector2) -> String:
	var r := w.robot
	if r.selected == "":
		return "выберите материал для ремонта"
	var c := cell_of(target)
	var mm = w.machine_at(c)
	if mm != null:
		if not w.near_robot(c, 3.0):
			return "слишком далеко"
		r.take_item(r.selected, 1.0)
		mm.hp = min(mm.max_hp(), mm.hp + 30.0)
		return ""
	if w.near_robot(c, 1.0):
		r.take_item(r.selected, 1.0)
		r.hp = min(r.max_hp(), r.hp + 25.0)
		return ""
	return "укажите машину или себя"
