extends GutTest
## Контент-пак: новые теги, обработка, модули, планеты, события, цели.

var H := TestHelpers

func _env(p: Planet, cont = null, neighbors: Array = []) -> Dictionary:
	return H.env(p, {"container": cont, "neighbors": neighbors})

# ---------------------------------------------------------------- теги и обработка

func test_cryogenic_chills_neighbours_and_freezes_volatile():
	var p := H.planet([], 15.0)
	var cold := Portion.new(H.sub(p, ["cryogenic", "dense"]), 5.0, 15.0)
	var gas := Portion.new(H.sub(p, ["volatile"]), 2.0, 15.0)
	var env := _env(p, null, [cold, gas])
	for i in 20:
		Handling.tick(cold, "sealed", env, 0.25)
	assert_lt(gas.temp, -50.0, "соседняя порция остыла")
	assert_eq(gas.phase(), Substance.Phase.SOLID, "летучее застыло")

func test_superfluid_seeps_unless_dense_walls():
	var p := H.planet()
	var s := H.sub(p, ["superfluid", "metallic"])
	var a := Portion.new(s, 10.0, 15.0)
	var b := Portion.new(s, 10.0, 15.0)
	var plain := H.sub(p, ["metallic"])
	var dense := H.sub(p, ["dense", "metallic"])
	for i in 40:
		Handling.tick(a, "sealed", _env(p, plain), 0.25)
		Handling.tick(b, "sealed", _env(p, dense), 0.25)
	assert_lt(a.mass, 7.0, "утекает сквозь обычные стенки")
	assert_almost_eq(b.mass, 10.0, 0.01, "плотные стенки держат")

func test_self_assembling_mends_container():
	var w := H.world()
	var box := w.place("container", Vector2i(10, 10), 0, w.starter, true)
	box.hp = box.max_hp() * 0.5
	box.store(Portion.new(w.db.add(Substance.new("sa", "Самосбор", ["self_assembling", "metallic"])), 6.0))
	H.run(w, 20.0)
	assert_gt(box.hp, box.max_hp() * 0.6, "контейнер чинится")
	assert_lte(box.hp, box.max_hp())

func test_refractory_raises_heat_limit():
	var plain := Substance.new("a", "A", ["metallic"])
	var refr := Substance.new("b", "B", ["metallic", "refractory"])
	var d: float = ComponentStats.compute("furnace", refr).max_t - ComponentStats.compute("furnace", plain).max_t
	assert_gt(d, 1000.0, "тугоплавкий держит жар много выше")

func test_cryochamber_chain_to_superfluid():
	var p := H.planet([], 15.0)
	var ctx := {"db": p.db, "pressure": 3.0, "compress_bonus": 0.0, "target_t": 900.0, "ambient": 15.0, "reagent": null, "filter_tag": ""}
	var first := Processor.run("cryochamber", Portion.new(H.sub(p, ["volatile", "organic"]), 2.0), ctx)
	var q: Portion = first.outs[0][0]
	assert_true(q.has("cryogenic"))
	var second := Processor.run("cryochamber", q, ctx)
	assert_true(second.outs[0][0].has("superfluid"), "второй проход — сверхтекучее")

func test_resonator_makes_self_assembling_with_crystal_source():
	var w := H.world()
	var crystal := w.db.add(Substance.new("cr", "Кварц", ["crystalline"]))
	var feed := w.db.add(Substance.new("pc", "Пористый кварц", ["crystalline", "porous"]))
	var r := w.place("resonator", Vector2i(10, 10), 0, crystal, true)
	var out := w.place("container", Vector2i(11, 10), 0, w.starter, true)
	r.store(Portion.new(feed, 2.0))
	H.run(w, 8.0)
	assert_true(out.items.any(func(p): return p.has("self_assembling")), "резонатор с кристаллом в стенках")

func test_resonator_idles_without_source():
	var w := H.world()
	var r := w.place("resonator", Vector2i(10, 10), 0, w.starter, true)
	w.place("container", Vector2i(11, 10), 0, w.starter, true)
	r.store(Portion.new(w.db.add(Substance.new("pc", "П", ["crystalline", "porous"])), 2.0))
	H.run(w, 8.0)
	assert_false(r.items.is_empty(), "без кристалла не работает")

func test_new_buildings_unlock_via_skill_tree():
	for k in ["cryochamber", "resonator"]:
		var found := false
		for nd in SkillTree.NODES:
			if k in nd.get("unlock", []):
				found = true
		assert_true(found, "«%s» открывается прокачкой" % k)

# ---------------------------------------------------------------- модули

func _give(w: World, kind: String, sub: Substance = null) -> Dictionary:
	var m := w.robot.new_module(kind, sub if sub != null else w.starter, 0.0)
	w.robot.modules.append(m)
	w.robot.bonus_slots += 2
	assert_eq(w.robot.equip(m.uid), "")
	w.robot.tank = w.robot.tank_cap()
	return m

func test_seismic_charge_adds_deposits():
	var w := H.world()
	w.planet.materials = [w.db.add(Substance.new("ore", "Руда", ["brittle"]))]
	_give(w, "seismic_charge")
	var n0 := w.planet.deposits.size()
	assert_eq(Abilities.use(w, "seismic_charge", w.robot.pos + Vector2(3, 0)), "")
	assert_gt(w.planet.deposits.size(), n0 + 1, "появились новые залежи")
	assert_ne(Abilities.use(w, "seismic_charge", w.robot.pos + Vector2(3, 0)), "", "перезарядка")

func test_new_deposits_survive_save_load():
	var w := H.world()
	var ore := w.db.add(Substance.new("ore", "Руда", ["brittle"]))
	w.planet.deposits[Vector2i(3, 3)] = {"sub": ore.id, "amount": 42.0}
	var d := SaveGame.to_dict(w)
	assert_eq(d.deposits["3,3"].amount, 42.0)
	assert_eq(d.deposits["3,3"].sub, ore.id)

func test_field_forge_sinters_in_hands():
	var w := H.world()
	_give(w, "field_forge")
	var powder := w.db.add(Substance.new("pw", "Порошок", ["porous", "metallic"]))
	w.robot.add_item(Portion.new(powder, 3.0))
	w.robot.selected = powder.id
	assert_eq(Abilities.use(w, "field_forge", w.robot.pos), "")
	var got: Substance = w.db.get_sub(w.robot.selected)
	assert_true(got.has("dense") and got.has("crystalline"), "порошок спёкся: %s" % [got.tags])
	assert_almost_eq(w.robot.mass_of(powder.id), 0.0, 0.01)

func test_cold_pack_stops_fire_in_hands():
	var w := H.world(["oxidizing_atmosphere"])
	var pyro := w.db.add(Substance.new("py", "Пиро", ["pyrophoric", "dense"]))
	w.robot.add_item(Portion.new(pyro, 5.0))
	H.run(w, 4.0)
	var burnt := 5.0 - w.robot.mass_of(pyro.id)
	assert_gt(burnt, 0.5, "без ранца горит в руках")
	_give(w, "cold_pack")
	var m0 := w.robot.mass_of(pyro.id)
	H.run(w, 4.0)
	assert_almost_eq(w.robot.mass_of(pyro.id), m0, 0.01, "с ранцем не горит")

func test_tuning_fork_analyzes_around():
	var w := H.world()
	var a := w.db.add(Substance.new("a", "А", ["brittle"]))
	var b := w.db.add(Substance.new("b", "Б", ["dense"]))
	var c0 := w.robot.cell() + Vector2i(3, 0)
	w.planet.deposits[c0] = {"sub": a.id, "amount": 10.0}
	w.planet.deposits[c0 + Vector2i(2, 1)] = {"sub": b.id, "amount": 10.0}
	_give(w, "tuning_fork")
	assert_eq(Abilities.use(w, "tuning_fork", Vector2(c0) + Vector2(0.5, 0.5)), "")
	assert_true(w.is_analyzed(a) and w.is_analyzed(b))

# ---------------------------------------------------------------- планеты и события

func _director_world(tags: Array) -> World:
	var w := H.world(tags)
	w.director.enabled = true
	return w

func _activate(w: World, id: String, at: Vector2i) -> void:
	w.director.start(id, at)
	w.director.current.t = 0.0
	w.director.tick(0.01)   # предупреждение закончилось — событие началось
	assert_eq(w.director.active_id(), id)

func test_new_planet_tags_exist_and_generate():
	for t in ["fungal_biosphere", "ringed", "singularity"]:
		assert_true(PlanetTags.TAGS.has(t))
	var p := PlanetGen.generate(7, 80, 60, ["singularity", "dense_atmosphere", "seismic"])
	assert_gt(p.gravity, 1.5, "сингулярность тяжёлая")

func test_spore_bloom_clogs_pumps_and_sprouts():
	var w := _director_world(["fungal_biosphere"])
	var org := w.db.add(Substance.new("fung", "Грибница", ["organic", "dense"]))
	w.planet.materials = [org]
	var pump := w.place("pump", Vector2i(12, 12), 0, w.starter, true)
	var box := w.place("container", Vector2i(13, 12), 0, w.starter, true)
	box.store(Portion.new(org, 3.0))
	_activate(w, "spore_bloom", Vector2i(12, 12))
	H.run(w, 1.0)
	var p0: float = w.gas.pressure(pump.id)
	H.run(w, 10.0)
	assert_eq(pump.status, "забит спорами")
	assert_almost_eq(w.gas.pressure(pump.id), p0, 0.05, "забитый насос не качает")
	assert_true(box.items[0].has("fibrous"), "споры проросли в органике")
	var n0 := w.planet.deposits.size()
	w.director.finish()
	assert_gt(w.planet.deposits.size(), n0, "после выброса — новые залежи")
	H.run(w, 2.0)
	assert_ne(pump.status, "забит спорами")

func test_ring_debris_hits_and_leaves_deposits():
	var w := _director_world(["ringed"])
	w.planet.materials = [w.db.add(Substance.new("rf", "Огнеупор", ["refractory", "metallic"]))]
	_activate(w, "ring_debris", Vector2i(30, 30))
	var n0 := w.planet.deposits.size()
	H.run(w, 30.0)
	assert_gt(w.planet.deposits.size(), n0, "обломки оставили жилы")

func test_time_loop_speeds_machines_and_drains_tank():
	var w := _director_world(["singularity"])
	_activate(w, "time_loop", Vector2i(20, 20))
	assert_almost_eq(w.time_factor(), 1.5, 0.01)
	w.robot.tank = 5.0
	H.run(w, 10.0)
	assert_lt(w.robot.tank, 4.0, "баллон утекает")
	w.director.finish()
	assert_almost_eq(w.time_factor(), 1.0, 0.01)

func test_meteor_material_survives_save_load():
	var w := World.create(3)
	var extra := Substance.new("Экзит", "Экзит", ["void", "dense"])
	w.planet.materials.append(extra)
	w.db.add(extra)
	w.planet.deposits[w.planet.spawn + Vector2i(5, 5)] = {"sub": extra.id, "amount": 50.0}
	var w2 := SaveGame.from_dict(JSON.parse_string(JSON.stringify(SaveGame.to_dict(w))))
	assert_not_null(w2.db.get_sub("Экзит"), "материал метеорита восстановлен")
	assert_eq(w2.planet.deposits[w.planet.spawn + Vector2i(5, 5)].sub, "Экзит")

# ---------------------------------------------------------------- цели

func _goal_world(gid: String) -> World:
	var w := H.world()
	var g: Dictionary = Goals.TEMPLATES[gid].duplicate(true)
	g.id = gid
	w.planet.goal = g
	return w

func test_new_templates_present():
	for id in ["terraform", "orbital", "archaeology"]:
		assert_true(Goals.TEMPLATES.has(id))

func test_vent_gas_progress_counts_released_gas():
	var w := _goal_world("terraform")
	w.goals.stage = 1
	w.goals.choose(0)   # vent_gas
	var dec := w.place("decompressor", Vector2i(10, 10), 0, w.starter, true)
	var pump := w.place("pump", Vector2i(11, 10), 0, w.starter, true)
	pump.config.target_p = 5.0
	H.run(w, 40.0)
	assert_gt(w.gas.vented_total, 5.0, "декомпрессор сбрасывает газ")
	assert_gt(w.goals.progress, 0.03)
	assert_eq(dec.kind, "decompressor")

func test_launch_variety_counts_distinct_materials():
	var w := _goal_world("orbital")
	var a := w.db.add(Substance.new("a", "А", ["dense"]))
	var b := w.db.add(Substance.new("b", "Б", ["brittle"]))
	w.launch_orbit([Portion.new(a, 1.0), Portion.new(w.db.derive(a, ["dense", "porous"]), 1.0)], Vector2i(5, 5))
	assert_eq(w.launched.subs.size(), 1, "производное того же корня — тот же материал")
	w.launch_orbit([Portion.new(b, 1.0)], Vector2i(5, 5))
	assert_almost_eq(w.goals.evaluate({"type": "launch_variety", "n": 3}, 1.0), 2.0 / 3.0, 0.01)

func test_excavation_yields_artifacts_and_exhausts_ruin():
	var w := World.create(1, ["ancient_ruins", "seismic", "storms"])
	assert_false(w.artifacts.is_empty(), "на планете с руинами есть артефакты")
	assert_true(w.artifacts.all(func(s): return s.is_exotic()), "у артефактов невозможный тег")
	var ruin := Vector2i(-1, -1)
	for y in w.planet.height:
		for x in w.planet.width:
			var c := Vector2i(x, y)
			if ruin.x < 0 and w.tile(c) == Planet.Tile.RUIN and not w.planet.deposits.has(c):
				ruin = c
	assert_ne(ruin, Vector2i(-1, -1))
	w.robot.pos = Vector2(ruin) + Vector2(0.5, 1.5)
	for i in 30:
		w.mine(ruin, 1.0)
	assert_gte(w.excavated, World.RUIN_KG)
	assert_eq(w.tile(ruin), Planet.Tile.GROUND, "руина выработана")
	var d := SaveGame.to_dict(w)
	var w2 := SaveGame.from_dict(JSON.parse_string(JSON.stringify(d)))
	assert_almost_eq(w2.excavated, w.excavated, 0.01)
	assert_not_null(w2.db.get_sub(w.artifacts[0].id), "артефакты есть после загрузки")

func test_vented_total_saved():
	var w := H.world()
	w.gas.vented_total = 77.0
	var d := SaveGame.to_dict(w)
	assert_eq(d.vented, 77.0)
