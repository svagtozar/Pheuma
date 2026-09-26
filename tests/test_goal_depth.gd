extends GutTest
## Развилки в целях и награды за этапы.

var H := TestHelpers

func _mining(w: World) -> void:
	var g: Dictionary = Goals.TEMPLATES.mining.duplicate(true)
	g.id = "mining"
	for raw in g.stages:
		for st in Goals.options(raw):
			if st.has("tags") and st.tags.has("{rare}"):
				st.tags = {"dense": 1.0}
			if st.has("tag") and st.tag == "{rare}":
				st.tag = "dense"
	w.planet.goal = g

func test_every_template_has_alternatives_with_known_types():
	var known := ["stockpile_tags", "dome_env", "launch_mass", "launch_tag", "launch_exotic", "build_count", "discover_tags",
		"discover_exotic", "discover_interactions", "sensor_network", "phasing_contained", "beacon_hold",
		"deliveries", "machines_working", "stockpile_mass", "vent_gas", "launch_variety", "excavate"]
	for id in Goals.TEMPLATES:
		var alts := 0
		for raw in Goals.TEMPLATES[id].stages:
			if raw.has("alt"):
				alts += 1
				assert_eq(raw.alt.size(), 2)
			for st in Goals.options(raw):
				assert_true(st.type in known, "%s: %s" % [id, st.type])
				assert_true(st.has("desc"))
		assert_eq(alts, 2, id)

func test_rare_placeholder_resolved_in_alternatives():
	for s in 60:
		var p := PlanetGen.generate(s)
		for raw in p.goal.stages:
			for st in Goals.options(raw):
				assert_ne(st.get("tag", ""), "{rare}")
				assert_false(st.get("tags", {}).has("{rare}"))

func test_choice_blocks_progress_until_chosen():
	var w := H.world()
	_mining(w)
	for i in 4:
		w.planet.deposits[Vector2i(3 + i, 3)] = {"sub": w.starter.id, "amount": 1.0}
		w.place("drill", Vector2i(3 + i, 3), 1, w.starter, true)
	H.run(w, 2.0)
	assert_eq(w.goals.stage, 1)
	assert_true(w.goals.choice_pending())
	assert_eq(w.goals.reward_pending.size(), 3, "за этап предложены три награды")
	assert_eq(w.goals.current().type, "choice")
	w.goals.choose(0)
	assert_false(w.goals.choice_pending())
	assert_eq(w.goals.current().type, "stockpile_tags")
	var box := w.place("container", Vector2i(10, 10), 0, w.starter, true)
	box.store(Portion.new(w.starter, 2.0))
	H.run(w, 2.0)
	assert_eq(w.goals.stage, 2, "выбранный вариант засчитан")

func test_second_option_is_evaluated():
	var w := H.world()
	_mining(w)
	w.goals.stage = 1
	w.goals.choose(1)
	assert_eq(w.goals.current().type, "machines_working")
	for i in 4:
		var m := w.place("crusher", Vector2i(3 + i * 2, 8), 0, w.starter, true)
		m.store(Portion.new(w.db.add(Substance.new("b%d" % i, "B", ["brittle", "crystalline"])), 8.0))
	H.run(w, 1.5)
	assert_eq(w.goals.stage, 2)

func test_deliveries_count_from_stage_start():
	var w := H.world()
	var g: Dictionary = Goals.TEMPLATES.colony.duplicate(true)
	g.id = "colony"
	w.planet.goal = g
	w.stats.hits = 50
	w.goals.stage = 2
	w.goals.choose(1)
	var r := w.place("receiver", Vector2i(10, 10), 0, w.starter, true)
	for i in 3:
		w.spawn_projectile(Vector2(3.5, 10.5), Vector2(10.5, 10.5), [Portion.new(w.starter, 1.0)])
	H.run(w, 3.0)
	assert_eq(w.stats.hits - w.goals.base_hits, 3)

func test_rewards_apply():
	var w := H.world()
	var r := w.robot
	var k := r.knowledge
	Rewards.apply(w, "knowledge")
	assert_eq(r.knowledge, k + 4)
	var slots := r.slots()
	Rewards.apply(w, "slot")
	assert_eq(r.slots(), slots + 1)
	var bps := r.blueprints.size()
	Rewards.apply(w, "blueprint")
	assert_eq(r.blueprints.size(), bps + 1)
	var box := w.place("container", Vector2i(3, 3), 0, w.starter, true)
	box.hp = 1.0
	Rewards.apply(w, "repair")
	assert_eq(box.hp, box.max_hp())
	var before := r.mass_of(w.starter.id)
	r.pos = Vector2(w.planet.spawn) + Vector2(2.5, 0.5)
	Rewards.apply(w, "supply")
	H.run(w, 4.0)
	assert_almost_eq(r.mass_of(w.starter.id), before + 40.0, 0.5, "припасы долетели и подобраны")

func test_take_reward_only_offered():
	var w := H.world()
	w.goals.reward_pending = ["knowledge", "slot", "repair"]
	assert_eq(w.goals.take_reward("supply"), "")
	assert_ne(w.goals.take_reward("slot"), "")
	assert_true(w.goals.reward_pending.is_empty())

func test_offer_is_deterministic_and_distinct():
	var a := World.create(3)
	var b := World.create(3)
	var oa := Rewards.offer(a, 0)
	assert_eq(oa, Rewards.offer(b, 0))
	assert_eq(oa.size(), 3)
	var d := {}
	for x in oa:
		d[x] = true
	assert_eq(d.size(), 3)

func test_choices_and_rewards_survive_save():
	var w := World.create(9)
	w.goals.stage = 1
	w.goals.choose(1)
	w.goals.reward_pending = ["knowledge", "slot", "repair"]
	w.robot.bonus_slots = 2
	var w2 := SaveGame.from_dict(JSON.parse_string(JSON.stringify(SaveGame.to_dict(w))))
	assert_eq(int(w2.goals.choices["1"]), 1)
	assert_eq(w2.goals.reward_pending, ["knowledge", "slot", "repair"])
	assert_eq(w2.robot.bonus_slots, 2)
