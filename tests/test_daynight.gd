extends GutTest
## Смена дня и ночи и небо (ProtoDayNight): по тегам и сиду планеты.

func _cycle(seed_value: int) -> ProtoDayNight:
	var root := Node3D.new()
	add_child_autofree(root)
	var sky := ProtoSky.build(PlanetGen.generate(seed_value), root)
	return sky.cycle

func test_sun_rises_and_sets():
	var c := _cycle(14)
	assert_gt(c.sun_dir_at(0.5).y, 0.2, "в полдень солнце высоко")
	assert_lt(c.sun_dir_at(0.0).y, -0.2, "в полночь — под горизонтом")
	assert_almost_eq(c.sun_dir_at(0.25).y, 0.0, 0.01, "на рассвете — у горизонта")
	c.time = 0.0
	c.update_now()
	assert_gt(c.night, 0.9, "ночью темно — фара включается")
	assert_gt(c.env.ambient_light_energy, 0.2, "но не в полную черноту")
	c.time = 0.5
	c.update_now()
	assert_lt(c.night, 0.05)
	assert_gt(c.sun.light_energy, 1.0)

func test_night_passes_faster():
	var c := _cycle(14)
	c.time = 0.5
	c.update_now()
	c._process(10.0)
	var day_step := c.time - 0.5
	c.time = 0.0
	c.update_now()
	c._process(10.0)
	assert_almost_eq(c.time / day_step, ProtoDayNight.NIGHT_SPEED, 0.1)

func test_tidally_locked_stands_still():
	var c := _cycle(12)
	assert_false(c.running)
	var t := c.time
	c._process(100.0)
	assert_eq(c.time, t, "время стоит")
	assert_between(c.sun_height(), 0.0, 0.3, "солнце низко: вечные сумерки")

func test_tags_shape_the_sky():
	var thin := _cycle(32)           # разреженная атмосфера, кольца, радиация
	assert_lt(thin.day_top.get_luminance(), 0.05, "чёрное небо днём")
	assert_eq(thin.stars, 1.0)
	assert_eq(thin.clouds, 0.0)
	assert_true(thin.rings)
	assert_gt(thin.aurora, 0.0)
	var dense := _cycle(5)           # плотная, бури
	assert_lt(dense.stars, thin.stars)
	assert_gt(dense.clouds, 0.5)
	assert_true(_cycle(22).hole, "сингулярность — чёрная дыра на небе")

func test_same_seed_same_sky():
	var a := _cycle(21)
	var b := _cycle(21)
	assert_eq(a.day_len, b.day_len)
	assert_eq(a.star, b.star)
	assert_eq(a.moons.size(), b.moons.size())
	var lens := {}
	for s in 20:
		lens["%.0f" % _cycle(s).day_len] = true
	assert_gt(lens.size(), 10, "длина суток у планет разная")
