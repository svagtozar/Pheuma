extends GutTest
## Плавучесть в 3D (ProtoSwim, ProtoPlayer): Архимед, вязкость, вид из-под воды.

func _sub(n: String, tags: Array = [], dens := -1.0) -> Substance:
	var s := Substance.new(n, n, tags)
	if dens > 0.0:
		s.density = dens
	return s

## Робот, отпущенный на поверхности, через 20 с: погружение f (0..1).
func _settle_f(r: float, g: float, visc: float) -> float:
	var y := 0.0            # ноги относительно поверхности (0 — на уровне)
	var vy := 0.0
	for i in 20 * 60:
		var dt := 1.0 / 60.0
		var f := ProtoSwim.submerged(-y)
		var a := ProtoSwim.accel(g, r, f, 0.0, 0.0)
		vy = (vy + a * dt) / (1.0 + visc * f * dt)
		y += vy * dt
		if y < -6.0:
			return 1.0          # ушёл ко дну
	return ProtoSwim.submerged(-y)

func test_heavier_hull_and_cargo_make_robot_denser():
	var light := ProtoSwim.robot_density(_sub("лёгкий", [], 4.0))
	var heavy := ProtoSwim.robot_density(_sub("тяжёлый", [], 10.0))
	assert_gt(heavy, light, "тяжёлый металл корпуса — плотнее робот")
	assert_gt(ProtoSwim.robot_density(_sub("лёгкий", [], 4.0), 150.0), light, "груз утяжеляет")
	assert_gt(light, 1.0, "обычный робот тонет в воде (1 г/см³)")

func test_floats_only_in_denser_liquid_whatever_gravity():
	var rho := ProtoSwim.robot_density(_sub("металл", [], 6.5))
	var lava := ProtoSwim.ratio(_sub("лава", [], 3.1), rho)
	var water := ProtoSwim.ratio(_sub("вода", [], 1.0), rho)
	assert_gt(lava, 1.0, "в лаве робот всплывает")
	assert_lt(water, 1.0, "в воде тонет")
	for g in [0.4 * ProtoPlayer.G, ProtoPlayer.G, 1.8 * ProtoPlayer.G]:
		assert_almost_eq(_settle_f(lava, g, 3.0), 1.0 / lava, 0.03, "плавает на глубине BODY_H / отношение при g=%.1f" % g)
		assert_eq(_settle_f(water, g, 1.2), 1.0, "в воде уходит ко дну при g=%.1f" % g)

func test_float_depth_matches_equilibrium():
	assert_eq(ProtoSwim.float_depth(0.8), INF, "легче робота — не держит")
	assert_almost_eq(ProtoSwim.float_depth(2.0), ProtoSwim.BODY_H * 0.5, 0.001, "вдвое плотнее — по пояс")

func test_viscosity_by_tags_slows_and_calms():
	var water := _sub("вода", ["volatile"])
	var syrup := _sub("смола", ["sticky"])
	assert_gt(ProtoSwim.viscosity(syrup), ProtoSwim.viscosity(water), "липкая гуще")
	assert_lt(ProtoSwim.speed_mult(ProtoSwim.viscosity(syrup), 1.0), ProtoSwim.speed_mult(ProtoSwim.viscosity(water), 1.0), "в густой — медленнее")
	assert_eq(ProtoSwim.speed_mult(2.0, 0.0), 1.0, "на суше не тормозит")
	assert_lt(ProtoSwim.flow_speed(4.5), ProtoSwim.flow_speed(1.0), "густая река течёт медленнее")
	assert_lt(ProtoLiquids.look(syrup, 20.0).wave, ProtoLiquids.look(water, 20.0).wave, "густая — гладь, волны ниже")

func test_underwater_fog_thicker_in_murky_liquid():
	var clear := _sub("сверхтекучая", ["superfluid"])
	clear.melt = -100.0      # жидкая при 20 °C
	var lava := ProtoHealth.hazard_liquid(_lava_planet())
	assert_gt(ProtoWater.fog_of(lava, 20.0, 1.0).density, ProtoWater.fog_of(clear, 20.0, 1.0).density, "в лаве не видно ничего")
	assert_gt(ProtoWater.fog_of(clear, 20.0, 8.0).density, ProtoWater.fog_of(clear, 20.0, 1.0).density, "глубже — темнее")

func test_liquid_zone_reports_level_and_zone():
	var h := ProtoHealth.new()
	var zone := {"sub": _sub("вода", [], 1.0), "temp": 20.0, "level": func(_x, _z): return 5.0,
		"area": func(_x, _z): return true, "flow": func(_x, _z): return Vector3(-1, 0, 0)}
	h.zones = [zone]
	var lq := h.liquid_at(Vector3(0, 3.0, 0))
	assert_almost_eq(float(lq.depth), 2.0, 0.001)
	assert_eq(float(lq.level), 5.0)
	assert_eq(lq.zone, zone, "зона — для течения и кругов")
	assert_true(h.liquid_at(Vector3(0, 6.0, 0)).is_empty(), "над поверхностью сухо")
	h.free()

func test_hud_renames_jump_and_sprint_while_swimming():
	ProtoControls.ensure()
	var hud := ProtoHud.new()
	var r := Node3D.new()
	add_child_autofree(r)
	hud.robot = r
	var names := func(): return hud.hint_rows(false, false).map(func(x): return x[0])
	assert_has(names.call(), "Прыжок")
	r.set_meta("swim", true)
	assert_has(names.call(), "Всплыть", "плывя — Прыжок гребёт вверх")
	assert_has(names.call(), "Нырнуть", "плывя — Бег ныряет")
	hud.free()

func _lava_planet() -> Planet:
	var p := Planet.new()
	p.tags = ["volcanic"]
	return p
