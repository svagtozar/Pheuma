extends GutTest
## Прочность корпуса робота в 3D (ProtoHealth): урон, защита материала, починка, поломка.

func _sub(n: String, tags: Array = []) -> Substance:
	return Substance.new(n, n, tags)

func _planet(tags: Array, temp := 20.0) -> Planet:
	var p := Planet.new()
	p.tags = tags
	p.ambient_temp = temp
	return p

func _health(hull: Substance = null) -> ProtoHealth:
	var h := ProtoHealth.new()
	var r := Node3D.new()
	add_child_autofree(r)
	add_child_autofree(h)
	h.setup(r, null, _planet([]), hull if hull != null else _sub("металл", ["metallic"]))
	return h

func test_hull_material_sets_hp_and_shield_like_2d():
	var soft := ProtoHealth.new()
	soft.set_hull(_sub("мягкий"))
	var hard := ProtoHealth.new()
	var hs := _sub("твёрдый", ["dense", "metallic"])
	hard.set_hull(hs)
	assert_gt(hard.max_hp, soft.max_hp, "твёрдый корпус прочнее")
	assert_almost_eq(hard.max_hp, ComponentStats.compute("hull", hs).max_hp * 1.2, 0.01, "как RobotState.max_hp")
	assert_gt(hard.shield.radiation, 0.0, "плотный металл защищает от радиации")
	assert_almost_eq(hard.shield.radiation, ComponentStats.compute("hull", hs).shield_radiation * 0.5, 0.001, "корпус — половина защиты")
	soft.free()
	hard.free()

func test_fall_damage_grows_with_gravity():
	var st := ComponentStats.compute("hull", _sub("металл", ["metallic"]))
	assert_eq(ProtoHealth.fall_damage(ProtoPlayer.JUMP_V, st), 0.0, "обычный прыжок не ранит")
	# Одна и та же высота: v = sqrt(2 g h).
	var h := 5.0
	var light := ProtoHealth.fall_damage(sqrt(2.0 * ProtoPlayer.G * 0.4 * h), st)
	var normal := ProtoHealth.fall_damage(sqrt(2.0 * ProtoPlayer.G * 1.0 * h), st)
	var heavy := ProtoHealth.fall_damage(sqrt(2.0 * ProtoPlayer.G * 1.8 * h), st)
	assert_eq(light, 0.0, "на лёгкой планете 5 м — не страшно")
	assert_gt(normal, 0.0)
	assert_gt(heavy, normal * 2.0, "на тяжёлой — много больнее")
	assert_gt(ProtoHealth.safe_height(0.4), ProtoHealth.safe_height(1.8))

func test_elastic_hull_softens_falls():
	var hard := ComponentStats.compute("hull", _sub("а", ["metallic"]))
	var springy := ComponentStats.compute("hull", _sub("б", ["metallic", "elastic"]))
	assert_lt(ProtoHealth.fall_damage(14.0, springy), ProtoHealth.fall_damage(14.0, hard))

func test_lava_burns_and_heat_resistant_hull_helps():
	var lava := ProtoHealth.hazard_liquid(_planet(["volcanic"], 85.0))
	assert_not_null(lava)
	var t := ProtoHealth.liquid_temp(lava, 85.0)
	assert_gt(t, 900.0, "лава горячая, хоть воздух и нет")
	var plain := ComponentStats.compute("hull", _sub("а", ["metallic"]))
	var insul := ComponentStats.compute("hull", _sub("б", ["metallic", "insulating"]))
	var r1 := ProtoHealth.liquid_rate(lava, t, 1.0, ProtoHealth.hull_shield(plain), plain)
	var r2 := ProtoHealth.liquid_rate(lava, t, 1.0, ProtoHealth.hull_shield(insul), insul)
	assert_eq(r1.kind, "heat")
	assert_gt(r1.dps, 15.0, "в лаве корпус горит быстро")
	assert_lt(r2.dps, r1.dps, "теплоизолятор держит жар лучше")
	var shallow := ProtoHealth.liquid_rate(lava, t, 0.1, ProtoHealth.hull_shield(plain), plain)
	assert_lt(shallow.dps, r1.dps, "по щиколотку — меньше, чем по пояс")

func test_hull_below_liquid_temperature_takes_double():
	var hot := _sub("горячее")
	var st := {"max_t": 500.0, "shield_heat": 0.0}
	var sh := {"heat": 0.0, "radiation": 0.0, "toxic": 0.0, "acid": 0.0}
	var under: float = ProtoHealth.liquid_rate(hot, 450.0, 1.0, sh, st).dps
	var over: float = ProtoHealth.liquid_rate(hot, 560.0, 1.0, sh, st).dps
	assert_gt(over, under * 2.0, "выше предела нагрева корпуса — вдвое")

func test_acid_eats_unless_corrosion_proof():
	var acid := ProtoHealth.hazard_liquid(_planet(["acid_rain"]))
	assert_true(acid.has("acidic"))
	var metal := ComponentStats.compute("hull", _sub("а", ["metallic"]))
	var glass := ComponentStats.compute("hull", _sub("б", ["crystalline"]))
	var r1 := ProtoHealth.liquid_rate(acid, 20.0, 1.0, ProtoHealth.hull_shield(metal), metal)
	var r2 := ProtoHealth.liquid_rate(acid, 20.0, 1.0, ProtoHealth.hull_shield(glass), glass)
	assert_eq(r1.kind, "acid")
	assert_lt(r2.dps, r1.dps, "кристаллический корпус не разъедается")

func test_plain_water_is_harmless():
	var water := _sub("вода")
	var sh := ProtoHealth.hull_shield({})
	assert_eq(ProtoHealth.liquid_rate(water, 20.0, 1.0, sh, {}).dps, 0.0)
	assert_null(ProtoHealth.hazard_liquid(_planet(["ringed"])))

func test_ambient_hazards_follow_2d_and_rock_shelters_from_rain():
	var sh := ProtoHealth.hull_shield({})
	var p := _planet(["acid_rain", "radiation"])
	var open_air := ProtoHealth.ambient_rate(p, sh, 1.0)
	var cave := ProtoHealth.ambient_rate(p, sh, 0.0)
	assert_almost_eq(open_air.dps, 0.35, 0.001, "0.25 радиации + 0.1 дождя, как в 2D")
	assert_lt(cave.dps, open_air.dps, "под сводом дождь не достаёт")
	assert_eq(ProtoHealth.ambient_rate(_planet([]), sh, 1.0).dps, 0.0)

func test_liquid_zone_lookup():
	var h := _health()
	var lava := ProtoHealth.hazard_liquid(_planet(["volcanic"]))
	h.zones = [{"sub": lava, "temp": 1100.0, "level": func(_x, _z): return 2.0,
		"area": func(x, z): return Vector2(x, z).length() < 5.0}]
	assert_eq(h.liquid_at(Vector3(0, 1.0, 0)).sub, lava)
	assert_almost_eq(h.liquid_at(Vector3(0, 1.0, 0)).depth, 1.0, 0.001)
	assert_true(h.liquid_at(Vector3(0, 3.0, 0)).is_empty(), "над гладью — сухо")
	assert_true(h.liquid_at(Vector3(9, 1.0, 0)).is_empty(), "вне озера — сухо")

## Зона русла по x, z накрывает и пещеру под ним: под сводом робот сухой.
func test_cave_under_river_is_dry():
	var h := _health()
	var planet := PlanetGen.generate(14)
	var tr := ProtoTerrain.new(14, ProtoWorldStyle.for_planet(planet))
	tr.build_field()
	h.terrain = tr
	var water := _sub("вода")
	h.zones = [{"sub": water, "temp": 20.0, "level": func(x, _z): return tr.river_level_at(x),
		"area": func(x, z): return abs(z - tr.river_z(x)) < 6.0}]
	# Зал пещеры под руслом: над роботом — свод, выше него — вода.
	var p := Vector3(50.6, 3.5, 55.4)
	assert_false(tr.solid(p.x, p.y, p.z), "точка — в зале")
	assert_lt(p.y, tr.river_level_at(p.x), "ниже зеркала реки")
	assert_true(h.liquid_at(p).is_empty(), "под сводом — сухо")
	# Там же, но в русле на поверхности — мокро.
	var q := Vector3(50.6, tr.river_level_at(50.6) - 0.5, tr.river_z(50.6))
	if not tr.solid(q.x, q.y, q.z):
		assert_false(h.liquid_at(q).is_empty(), "в русле — мокро")

func test_repair_from_cargo_prefers_metal_and_spends_it():
	var h := _health()
	h.hp = 10.0
	var rock := Portion.new(_sub("камень"), 5.0)
	var metal := Portion.new(_sub("железо", ["metallic"]), 0.5)
	h.robot.set_meta("cargo", [rock, metal])
	assert_true(h.can_repair_from_cargo())
	var got := h.repair_from_cargo(0.2)
	assert_gt(got, 0.0)
	assert_almost_eq(metal.mass, 0.3, 0.001, "берёт металл первым")
	assert_almost_eq(rock.mass, 5.0, 0.001)
	assert_almost_eq(h.hp, 10.0 + got, 0.001)
	h.hp = h.max_hp
	assert_false(h.can_repair_from_cargo(), "целому корпусу чинить нечего")

func test_wreck_loses_cargo_and_respawns_at_base():
	var h := _health()
	h.base = Vector3(3, 1, 4)
	h.robot.position = Vector3(40, 0, 40)
	h.robot.set_meta("cargo", [Portion.new(_sub("руда"), 7.0)])
	var got := {"wrecked": false, "restored": false}
	h.wrecked.connect(func(): got.wrecked = true)
	h.restored.connect(func(): got.restored = true)
	h.damage(h.max_hp + 5.0, "heat")
	assert_true(got.wrecked)
	assert_true(h.is_wrecked())
	assert_true(h.robot.get_meta("wrecked"))
	assert_almost_eq(h.lost_kg, 7.0, 0.001)
	h.damage(10.0, "heat")
	assert_eq(h.hp, 0.0, "сломанному урон не идёт")
	for i in int(ProtoHealth.WRECK_TIME / 0.25) + 2:
		h._process(0.25)
	assert_true(got.restored)
	assert_false(h.is_wrecked())
	assert_eq(h.robot.position, Vector3(3, 1, 4))
	assert_eq(h.hp, h.max_hp)
	assert_true((h.robot.get_meta("cargo") as Array).is_empty(), "груз потерян")

func test_factory_repairs_nearby():
	var h := _health()
	h.factory_at = Vector3.ZERO
	h.robot.position = Vector3(2, 0, 1)
	h.hp = 20.0
	h._process(1.0)
	assert_gt(h.hp, 20.0)
	assert_eq(h.healing, "factory")

func test_hud_shows_health_and_repair_hint():
	ProtoControls.ensure()
	ProtoHealth.ensure_action()
	var h := _health()
	h.hp = h.max_hp * 0.25
	var s := ProtoHud.health_summary(h)
	assert_eq(s.tone, "ok", "тон — от ProtoHealth до первого кадра")
	assert_almost_eq(s.frac, 0.25, 0.01)
	assert_true(ProtoHud.health_summary(null).is_empty())
	var hud := ProtoHud.new()
	hud.pad = false
	var rows := hud.hint_rows(false, true, true)
	assert_true(rows.any(func(r): return r[0] == "Починить из груза" and r[1] == "H"))
	hud.free()
