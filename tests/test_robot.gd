extends GutTest

var H := TestHelpers

func _sub(w: World, tags: Array) -> Substance:
	var n := "R" + str(w.db.by_id.size())
	return w.db.add(Substance.new(n, n, tags))

func _fab(w: World) -> void:
	w.place("fabricator", Vector2i(20, 21), 0, w.starter, true)

func test_learning_requires_knowledge_and_xp():
	var w := H.world()
	var r := w.robot
	assert_eq(Progression.learn(r, "h1"), "")
	assert_true(r.blueprints.has("hook"))
	assert_ne(Progression.can_learn(r, "h3"), "", "нельзя перескочить узел")
	r.knowledge = 10
	assert_string_contains(Progression.can_learn(r, "h2"), "опыта")
	r.xp.hunter = 20
	assert_eq(Progression.learn(r, "h2"), "")
	assert_gt(r.shield().radiation, 0.0)

func test_learning_unlocks_buildings_and_slots():
	var w := H.world()
	var r := w.robot
	r.knowledge = 10
	r.xp.crafter = 100
	assert_eq(r.slots(), 3)
	Progression.learn(r, "c1")
	Progression.learn(r, "c2")
	assert_true(r.unlocked.has("loom"))
	assert_eq(r.slots(), 4)

func test_all_classes_have_nodes_and_blueprints_exist():
	for c in SkillTree.CLASS_ORDER:
		assert_between(SkillTree.nodes_of(c).size(), 3, 4)
	for n in SkillTree.NODES:
		if n.has("blueprint"):
			assert_true(Modules.MODULES.has(n.blueprint), n.blueprint)
		for k in n.get("unlock", []):
			assert_true(Buildings.KINDS.has(k), k)
			assert_true(Buildings.KINDS[k].get("locked", false), "%s должен быть закрыт до изучения" % k)

func test_every_locked_building_is_unlockable():
	var unlockable := {}
	for n in SkillTree.NODES:
		for k in n.get("unlock", []):
			unlockable[k] = true
	for k in Buildings.KINDS:
		if Buildings.KINDS[k].get("locked", false):
			assert_true(unlockable.has(k), k)

func test_every_module_blueprint_is_reachable():
	var bp := {"hull": true, "hand_drill": true}
	for n in SkillTree.NODES:
		if n.has("blueprint"):
			bp[n.blueprint] = true
	for m in Modules.MODULES:
		assert_true(bp.has(m), m)

func test_fabricate_and_equip():
	var w := H.world()
	_fab(w)
	w.robot.blueprints["hook"] = true
	assert_eq(w.fabricate("hook", w.starter), "")
	var uid: int = w.robot.modules[0].uid
	assert_eq(w.robot.equip(uid), "")
	assert_true(w.robot.has_module("hook"))

func test_fabricate_requires_fabricator_nearby():
	var w := H.world()
	w.robot.blueprints["hook"] = true
	assert_string_contains(w.fabricate("hook", w.starter), "фабрикатор")

func test_module_material_matters():
	var w := H.world()
	var elastic := _sub(w, ["elastic", "fibrous"])
	var plain := _sub(w, ["dense", "metallic"])
	var a := w.robot.new_module("hook", elastic, 0.0)
	var b := w.robot.new_module("hook", plain, 0.0)
	assert_gt(Abilities.hook_range(w, a), Abilities.hook_range(w, b))
	var hull_ins := w.robot.new_module("hull", _sub(w, ["insulating", "crystalline"]), 0.0)
	var hull_plain := w.robot.new_module("hull", _sub(w, ["organic", "porous"]), 0.0)
	assert_gt(hull_ins.stats.shield_heat, hull_plain.stats.shield_heat)

func test_hook_crosses_chasm():
	var w := H.world()
	for y in w.planet.height:
		w.planet.set_tile(Vector2i(22, y), Planet.Tile.CHASM)
		w.planet.set_tile(Vector2i(23, y), Planet.Tile.CHASM)
	w.robot.pos = Vector2(21.5, 20.5)
	w.robot.equipped.append(w.robot.new_module("hook", w.starter, 0.0))
	w.robot.tank = 10.0
	w.move_robot(Vector2(3, 0))
	assert_lt(w.robot.pos.x, 22.0, "пешком не пройти")
	assert_eq(Abilities.use(w, "hook", Vector2(24.5, 20.5)), "")
	assert_gt(w.robot.pos.x, 24.0)
	assert_lt(w.robot.tank, 10.0, "газ потрачен")
	assert_eq(Abilities.use(w, "hook", Vector2(20.5, 20.5)), "перезарядка")

func test_jet_needs_gas():
	var w := H.world()
	w.robot.equipped.append(w.robot.new_module("jet", w.starter, 0.0))
	w.robot.tank = 0.2
	assert_string_contains(Abilities.use(w, "jet", w.robot.pos + Vector2(3, 0)), "газа")

func test_low_gravity_jumps_farther():
	var w1 := H.world()
	var w2 := H.world(["low_gravity"])
	w2.planet.gravity = 0.4
	var m := w1.robot.new_module("jet", w1.starter, 0.0)
	assert_gt(Abilities.jet_range(w2, m), Abilities.jet_range(w1, m))

func test_cryo_bridges_lava():
	var w := H.world()
	var c := Vector2i(21, 20)
	w.planet.set_tile(c, Planet.Tile.LAVA)
	w.robot.equipped.append(w.robot.new_module("cryo", w.starter, 0.0))
	w.robot.tank = 10.0
	assert_false(w.walkable(c))
	assert_eq(Abilities.use(w, "cryo", Vector2(21.5, 20.5)), "")
	assert_true(w.walkable(c))
	H.run(w, 40.0)
	assert_false(w.walkable(c), "мост растаял")

func test_scanner_and_analyzer():
	var w := H.world()
	var ore := _sub(w, ["magnetic", "dense"])
	w.planet.deposits[Vector2i(24, 20)] = {"sub": ore.id, "amount": 10.0}
	w.robot.equipped.append(w.robot.new_module("scanner", w.starter, 0.0))
	w.robot.equipped.append(w.robot.new_module("analyzer", w.starter, 0.0))
	w.robot.tank = 10.0
	assert_eq(Abilities.use(w, "scanner", w.robot.pos), "")
	assert_true(w.revealed.has(Vector2i(24, 20)))
	assert_false(w.is_analyzed(ore))
	assert_eq(Abilities.use(w, "analyzer", Vector2(24.5, 20.5)), "")
	assert_true(w.is_analyzed(ore))
	assert_true(w.robot.known_tags.has("magnetic"))

func test_manual_mining_respects_drill_hardness():
	var w := H.world()
	var hard := _sub(w, ["crystalline", "dense", "anchoring"])
	var soft := _sub(w, ["porous", "organic"])
	w.planet.deposits[Vector2i(21, 20)] = {"sub": hard.id, "amount": 10.0}
	w.planet.deposits[Vector2i(19, 20)] = {"sub": soft.id, "amount": 10.0}
	assert_string_contains(w.mine(Vector2i(21, 20), 1.0), "мягкий")
	assert_eq(w.mine(Vector2i(19, 20), 1.1), "")
	assert_gt(w.robot.mass_of(soft.id), 0.9)

func test_refill_from_tank():
	var w := H.world()
	var t := w.place("tank", Vector2i(21, 20), 0, w.starter, true)
	w.gas.add_gas(t.id, 20.0)
	w.robot.tank = 0.0
	w.refill_robot(1.0)
	assert_gt(w.robot.tank, 2.0)

func test_radiation_planet_hurts_and_shield_helps():
	var w1 := H.world(["radiation"])
	var w2 := H.world(["radiation"])
	var dense := w2.db.add(Substance.new("lead", "lead", ["dense", "metallic", "anchoring"]))
	w2.robot.equipped.append(w2.robot.new_module("shield", dense, 0.0))
	var h1 := w1.robot.hp
	var h2 := w2.robot.hp
	H.run(w1, 20.0)
	H.run(w2, 20.0)
	assert_lt(w1.robot.hp, h1)
	assert_gt(h1 - w1.robot.hp, h2 - w2.robot.hp)

func test_drone_ferries():
	var w := H.world()
	var a := w.place("container", Vector2i(21, 20), 0, w.starter, true)
	var b := w.place("container", Vector2i(26, 20), 0, w.starter, true)
	a.store(Portion.new(w.starter, 6.0))
	w.robot.equipped.append(w.robot.new_module("drone", w.starter, 0.0))
	w.robot.tank = 10.0
	assert_eq(Abilities.use(w, "drone", Vector2(21.5, 20.5)), "")
	w.robot.cooldowns.clear()
	assert_eq(Abilities.use(w, "drone", Vector2(26.5, 20.5)), "")
	H.run(w, 20.0)
	assert_gt(b.total_mass(), 3.0)

func test_death_respawns_and_drops_half():
	var w := H.world()
	var m := w.robot.mass_of(w.starter.id)
	w.robot.pos = Vector2(25.5, 25.5)
	w.robot.hp = -1.0
	w.tick(0.1)
	assert_almost_eq(w.robot.mass_of(w.starter.id), m * 0.5, 0.1)
	assert_eq(w.robot_cell(), w.planet.spawn)
