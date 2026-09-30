extends SceneTree
## Скорость живых жидкостей (ProtoFlow): как быстро идёт фронт.
##   godot --headless --path . -s tools/flow_speed.gd
## Прорыв воды: столб 2 м у края озера (сид 32) — где фронт через 1/2/4 с.
## Извержение (сид 7): на сколько метров от жерла ушла лава через 5/10/20/30 с.
## И стоимость шага, мс.

func _initialize() -> void:
	_run.call_deferred()

func _water() -> Substance:
	var s := Substance.new("water_t", "Вода")
	s.melt = 0.0
	s.boil = 100.0
	s.density = 1.0
	return s

func _run() -> void:
	var t := ProtoTerrain.new(32, ProtoWorldStyle.for_planet(PlanetGen.generate(32)))
	t.build_field()
	var f := ProtoFlow.new(t, _water())
	# Ровная площадка: заливаем квадрат 6×6 на 2 м над дном и смотрим, как далеко
	# уходит край по суше (клетки мокрее 3 см дальше всего от центра).
	var c := Vector2(t.lake_c.x + t.lake_r + 8.0, t.lake_c.y)
	var ci := f.cell_of(c.x, c.y)
	for dz in range(-3, 3):
		for dx in range(-3, 3):
			var i := ci + dx + dz * f.nx
			f.d[i] = 2.0
			f._grow(i % f.nx, i / f.nx)
	var us := 0
	var marks := [1.0, 2.0, 4.0, 8.0]
	var tt := 0.0
	var line := "вода: фронт"
	while not marks.is_empty():
		var t0 := Time.get_ticks_usec()
		f.step(0.1)
		us += Time.get_ticks_usec() - t0
		tt += 0.1
		if tt >= marks[0] - 0.001:
			line += "  %.0f с: %.1f м" % [marks[0], _front(f, c)]
			marks.pop_front()
	print(line, "  (шаг %.2f мс)" % (us / 80.0 / 1000.0))
	var t7 := ProtoTerrain.new(7, ProtoWorldStyle.for_planet(PlanetGen.generate(7)))
	t7.build_field()
	var lava := ProtoHealth.hazard_liquid(PlanetGen.generate(7))
	var ll := ProtoLiquidLife.new()
	root.add_child(ll)
	ll.setup_lake(t7, lava, t7.lake_level, func(x, z): return Vector2(x, z).distance_to(t7.lake_c) < t7.lake_r + 4.5, 7)
	var lf := ll.setup_volcano(lava)
	ll.erupt_next = 0.0
	line = "лава: от жерла"
	var done := 0.0
	us = 0
	for m in [5.0, 10.0, 20.0, 30.0, 60.0]:
		var t0 := Time.get_ticks_usec()
		for k in int(round((m - done) / ProtoLiquidLife.TICK)):
			ll._tick()
		us += Time.get_ticks_usec() - t0
		done = m
		line += "  %.0f с: %.1f м" % [m, _front(lf, ProtoTerrain.VOLC_C)]
	print(line, "  (тик %.2f мс)" % (us / 600.0 / 1000.0))
	quit()

func _front(f: ProtoFlow, c: Vector2) -> float:
	var best := 0.0
	for z in range(maxi(f.lo.y, 0), f.hi.y + 1):
		for x in range(maxi(f.lo.x, 0), f.hi.x + 1):
			if f.d[f.idx(x, z)] > 0.03:
				best = maxf(best, Vector2(x + 0.5, z + 0.5).distance_to(c))
	return best
