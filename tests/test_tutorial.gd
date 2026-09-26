extends GutTest
## Обучение проходится целиком на учебной планете.

func _free_cell(w: World, near: Vector2i, taken: Dictionary) -> Vector2i:
	for r in range(1, 20):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var c := near + Vector2i(dx, dy)
				if w.planet.buildable(c) and not w.grid.has(c) and not w.planet.deposits.has(c) and not taken.has(c):
					return c
	return near

func _line_free(w: World, o: Vector2i, d: Vector2i, n: int) -> bool:
	for k in n:
		var c := o + d * k
		if not w.planet.buildable(c) or w.grid.has(c) or w.planet.deposits.has(c):
			return false
	return true

func test_tutorial_planet_is_mild():
	var w := World.create(Tutorial.SEED, Tutorial.PLANET_TAGS)
	assert_eq(w.planet.tags, ["dense_atmosphere", "low_gravity", "tidally_locked"])
	assert_true(w.planet.forced)

func test_tutorial_can_be_completed():
	var w := World.create(Tutorial.SEED, Tutorial.PLANET_TAGS)
	Tutorial.setup_world(w)
	var t := Tutorial.new(w)
	var r := w.robot
	var steps_done: Array = []
	var tick := func(n: int):
		for i in n:
			w.tick(0.1)
			if t.update(w):
				steps_done.append(t.STEPS[t.step - 1].id if not t.done else "goal")
	# 1. Движение
	w.move_robot(Vector2(5, 0))
	tick.call(1)
	# 2. Добыча: ближайшая мягкая залежь
	var dep := Vector2i(-1, -1)
	var best := INF
	for c in w.planet.deposits:
		var s: Substance = w.db.get_sub(w.planet.deposits[c].sub)
		if s.hardness <= r.mining_hardness() and s.phase_at(w.planet.ambient_temp) == Substance.Phase.SOLID:
			var d := (Vector2(c) - r.pos).length()
			if d < best:
				best = d
				dep = c
	assert_ne(dep, Vector2i(-1, -1), "есть мягкая залежь")
	r.pos = Vector2(dep) + Vector2(0.5, 1.5)
	for i in 5:
		w.mine(dep, 1.0)
	tick.call(1)
	# 3. Анализ
	w.analyze(w.db.get_sub(w.planet.deposits[dep].sub))
	tick.call(1)
	# 4. Фабрикатор
	var taken := {}
	var fc := _free_cell(w, r.cell(), taken)
	assert_not_null(w.place("fabricator", fc, 0, w.starter))
	r.pos = Vector2(fc) + Vector2(0.5, 1.5)
	tick.call(1)
	# 5. Прокачка
	assert_eq(Progression.learn(r, "h1"), "")
	tick.call(1)
	# 6. Модуль
	assert_eq(w.fabricate("hook", w.starter), "")
	assert_eq(r.equip(r.modules[0].uid), "")
	tick.call(1)
	# 7. Бур и контейнер
	var placed := false
	for c in w.planet.deposits:
		for f in 4:
			var front: Vector2i = c + Machine.DIRS[f]
			if w.planet.buildable(front) and not w.grid.has(front) and not w.planet.deposits.has(front) and not w.grid.has(c):
				var s: Substance = w.db.get_sub(w.planet.deposits[c].sub)
				if s.hardness <= w.starter.hardness:
					w.place("drill", c, f, w.starter)
					w.place("container", front, 0, w.starter)
					placed = true
					break
		if placed:
			break
	assert_true(placed)
	tick.call(40)
	# 8–9. Давление и пушка
	var o := Vector2i(-1, -1)
	for c in w.planet.deposits.keys() + [w.planet.spawn]:
		for y in range(-12, 12):
			var cand: Vector2i = w.planet.spawn + Vector2i(-10, y)
			if _line_free(w, cand, Vector2i(1, 0), 9) and _line_free(w, cand + Vector2i(0, 1), Vector2i(1, 0), 9):
				o = cand
				break
		break
	assert_ne(o, Vector2i(-1, -1), "есть место под пушку")
	r.add_item(Portion.new(w.starter, 60.0))
	var cannon := w.place("cannon", o, 0, w.starter)
	w.place("pump", o + Vector2i(0, 1), 0, w.starter)
	tick.call(30)
	var recv := w.place("receiver", o + Vector2i(6, 0), 0, w.starter)
	assert_eq(w.link_cannon(cannon.cell, recv.cell), "")
	cannon.store(Portion.new(w.starter, 2.0))
	tick.call(30)
	# 10. Обработка
	var cr := w.place("crusher", o + Vector2i(8, 1), 0, w.starter)
	cr.accept(Portion.new(w.starter, 1.0), cr.cell + Vector2i(-1, 0))
	tick.call(30)
	# 11. Логика
	var sensor := w.place("sensor", o + Vector2i(2, 1), 0, w.starter)
	assert_eq(w.add_wire(sensor.cell, cannon.cell, 0, w.starter), "")
	tick.call(1)
	# 12. Маршрут
	var recv2 := w.place("receiver", o + Vector2i(4, 1), 0, w.starter)
	assert_eq(w.link_cannon(cannon.cell, recv2.cell, "dense"), "")
	tick.call(1)
	# 13. Склад
	var wo := Vector2i(-1, -1)
	for y in range(-14, 14):
		var cand: Vector2i = w.planet.spawn + Vector2i(6, y)
		if _line_free(w, cand, Vector2i(1, 0), 2) and _line_free(w, cand + Vector2i(0, 1), Vector2i(1, 0), 2):
			wo = cand
			break
	for d in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]:
		assert_not_null(w.place("warehouse_section", wo + d, 0, w.starter))
	tick.call(15)
	# 14–15. Макроблок и свёртка
	var mb = JSON.parse_string(JSON.stringify(Macroblocks.capture(w, Rect2i(cr.cell, Vector2i.ONE), "дробилка")))
	t.macros_made += 1
	tick.call(1)
	var mc := _free_cell(w, w.planet.spawn + Vector2i(0, 4), {})
	assert_eq(Macroblocks.place_collapsed(w, mb, mc, 0, w.starter), "")
	tick.call(1)
	# 16. Цель
	t.acknowledged = true
	tick.call(1)
	assert_true(t.done, "обучение пройдено, выполнено: %s" % str(steps_done))
	assert_eq(steps_done.size(), Tutorial.STEPS.size())
