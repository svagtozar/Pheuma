extends GutTest
## Анализ через касание, пробы и наблюдение.

var H := TestHelpers

func _w() -> World:
	var w := H.world()
	w.robot.tank = w.robot.tank_cap()
	return w

func _give(w: World, tags: Array, mass: float = 3.0, name: String = "Обр") -> Substance:
	var s := w.db.add(Substance.new(name, name, tags))
	w.robot.add_item(Portion.new(s, mass))
	return s

func test_every_tag_has_a_way_to_be_recognised():
	for t in MaterialTags.all():
		var ok: bool = t in Probes.VISIBLE or Probes.probe_of(t) != ""
		if not ok:
			ok = HandlingRules.rules_for(t).any(func(r): return r.ctx.any(func(c): return c in ["open", "sealed", "ground"]))
		assert_true(ok, "тег «%s» можно распознать" % t)
		assert_true(Probes.SIGNS.has(t) or not (t in Probes.VISIBLE or Probes.probe_of(t) != ""), "есть признак для «%s»" % t)

func test_touch_reveals_only_visible_tags():
	var w := _w()
	var s := _give(w, ["metallic", "flammable"])
	w.touch(s)
	assert_eq(w.known_tags_of(s), ["metallic"])
	assert_eq(w.unknown_count(s), 1)
	assert_true("crystalline" in w.excluded_of(s), "видимое, которого нет, исключено")
	assert_true(w.sub_label(s).contains("+1 ?"))

func test_heat_probe_reveals_and_excludes():
	var w := _w()
	var s := _give(w, ["flammable", "dense"])
	var g0 := w.robot.tank
	assert_eq(w.probe(s.id, "heat"), "")
	assert_true("flammable" in w.known_tags_of(s))
	assert_true("volatile" in w.excluded_of(s))
	assert_almost_eq(w.robot.mass_of(s.id), 3.0 - Probes.SAMPLE_KG, 0.01, "образец потрачен")
	assert_lt(w.robot.tank, g0, "газ потрачен")

func test_probe_refuses_without_sample():
	var w := _w()
	var s := _give(w, ["acidic"], 0.2)
	assert_ne(w.probe(s.id, "drop"), "")
	assert_false("acidic" in w.known_tags_of(s))

func test_possible_narrows_and_identification_rewards_once():
	var w := _w()
	var s := _give(w, ["magnetic", "conductive"], 5.0)
	var before := w.possible_of(s).size()
	w.probe(s.id, "magnet")
	assert_lt(w.possible_of(s).size(), before, "возможных стало меньше")
	var k0 := w.robot.knowledge
	w.probe(s.id, "spark")
	assert_true(w.is_identified(s))
	var k1 := w.robot.knowledge
	assert_gt(k1, k0, "опознание дало знания")
	w.analyze(s)
	w.touch(s)
	assert_eq(w.robot.knowledge, k1, "за опознание — один раз")

func test_observation_volatile_evaporates_in_open_container():
	var w := _w()
	var s := w.db.add(Substance.new("gz", "Летун", ["volatile", "organic"]))
	var box := w.place("container", Vector2i(10, 10), 0, w.starter, true)
	box.store(Portion.new(s, 5.0))
	H.run(w, 6.0)
	assert_true("volatile" in w.known_tags_of(s), "испарение выдало летучесть")

func test_observation_phasing_leaks_from_tank():
	var w := _w()
	var s := w.db.add(Substance.new("ph", "Фаз", ["phasing", "metallic"]))
	var tank := w.place("tank", Vector2i(10, 10), 0, w.starter, true)
	tank.store(Portion.new(s, 5.0))
	H.run(w, 6.0)
	assert_true("phasing" in w.known_tags_of(s))

func test_observation_furnace_reveals_matched_tag():
	var p := H.planet()
	var s := H.sub(p, ["flammable", "dense"])
	var ctx := {"db": p.db, "pressure": 3.0, "compress_bonus": 0.0, "target_t": 900.0, "ambient": 15.0, "reagent": null, "filter_tag": ""}
	var res := Processor.run("furnace", Portion.new(s, 2.0), ctx)
	assert_true("flammable" in res.matched, "печь: сработало правило горючего")

func test_knowledge_passes_to_derived_substance():
	var w := _w()
	var a := _give(w, ["porous", "metallic"])
	w.touch(a)
	var b := w.db.derive(a, ["dense", "metallic", "crystalline"])
	w.inherit_knowledge(a, b, ["dense", "crystalline"])
	assert_true("metallic" in w.known_tags_of(b), "известное осталось известным")
	assert_true(w.is_identified(b))

func test_sub_known_saved_and_legacy_loaded():
	var w := World.create(2)
	var s: Substance = w.planet.materials[0]
	w.robot.add_item(Portion.new(s, 3.0))
	w.robot.tank = w.robot.tank_cap()
	w.touch(s)
	w.probe(s.id, "heat")
	var d := SaveGame.to_dict(w)
	var w2 := SaveGame.from_dict(JSON.parse_string(JSON.stringify(d)))
	assert_eq(w2.known_tags_of(w2.db.get_sub(s.id)), w.known_tags_of(s))
	# Старое сохранение без sub_known: всё проанализированное известно целиком.
	var d2: Dictionary = JSON.parse_string(JSON.stringify(d))
	d2.robot.erase("sub_known")
	var w3 := SaveGame.from_dict(d2)
	assert_true(w3.is_identified(w3.db.get_sub(s.id)))

func test_probe_from_nearby_deposit_for_liquids():
	var w := _w()
	var gas := w.db.add(Substance.new("lq", "Жижа", ["volatile", "acidic"]))
	var c := w.robot.cell() + Vector2i(1, 0)
	w.planet.deposits[c] = {"sub": gas.id, "amount": 10.0}
	assert_eq(w.probe_error(gas.id, "drop"), "", "образец — из залежи рядом")
	assert_eq(w.probe(gas.id, "drop"), "")
	assert_true("acidic" in w.known_tags_of(gas))
	assert_almost_eq(w.planet.deposits[c].amount, 10.0 - Probes.SAMPLE_KG, 0.01)
	w.robot.pos += Vector2(10, 0)
	assert_ne(w.probe_error(gas.id, "heat"), "", "далеко от залежи — нельзя")
