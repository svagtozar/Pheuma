extends GutTest
## События планеты.

var H := TestHelpers

func _ev(w: World, id: String, at: Vector2i) -> EventDirector:
	var d := w.director
	d.enabled = true
	d.start(id, at)
	d.current.t = 0.01
	w.tick(0.1)          # предупреждение → активная фаза
	assert_eq(d.current.get("phase", ""), "active")
	return d

func test_director_deterministic_and_respects_tags():
	var a := World.create(21)
	var b := World.create(21)
	assert_eq(a.director.next_in, b.director.next_in)
	assert_eq(a.director.pick(), b.director.pick())
	var p := TestHelpers.planet([])
	assert_eq(Events.weight("storm", p), 0.0, "буря только на планете с бурями")
	var p2 := TestHelpers.planet(["storms"])
	assert_gt(Events.weight("storm", p2), 0.0)

func test_director_disabled_on_tutorial():
	var w := World.create(Tutorial.SEED, Tutorial.PLANET_TAGS)
	assert_false(w.director.enabled)

func test_event_runs_full_cycle():
	var w := World.create(8)
	w.director.next_in = 0.1
	var seen_warn := false
	var seen_active := false
	for i in 4000:
		w.tick(0.1)
		var ph: String = w.director.current.get("phase", "")
		seen_warn = seen_warn or ph == "warn"
		seen_active = seen_active or ph == "active"
		if w.director.count > 0:
			break
	assert_true(seen_warn and seen_active)
	assert_eq(w.director.count, 1)

func test_meteor_damages_machine_and_can_leave_deposit():
	var w := H.world()
	w.planet.materials = [w.db.add(Substance.new("m", "М", ["dense", "metallic"]))]
	var box := w.place("container", Vector2i(10, 10), 0, w.starter, true)
	var hp := box.hp
	w.director.meteor_hit(Vector2i(10, 10))
	assert_lt(box.hp, hp)
	var made := 0
	for x in 40:
		w.director.meteor_hit(Vector2i(2 + x % 30, 25 + x / 30))
	for c in w.planet.deposits:
		made += 1
	assert_gt(made, 3, "метеориты оставляют залежи")

func test_meteor_shower_spawns_meteors():
	var w := H.world()
	w.planet.materials = [w.starter]
	var d := _ev(w, "meteors", Vector2i(20, 20))
	H.run(w, 5.0)
	assert_gt(w.director.current.get("acc", 0.0) + w.projectiles.size(), 0.0)

func test_geyser_pumps_neighbor():
	var w := H.world()
	var tank := w.place("tank", Vector2i(11, 10), 0, w.starter, true)
	var p0 := w.gas.pressure(tank.id)
	_ev(w, "geyser", Vector2i(10, 10))
	H.run(w, 10.0)
	assert_gt(w.gas.pressure(tank.id), p0 + 1.0)

func test_acid_rain_triples_corrosion_only_in_open():
	var w := H.world(["acid_rain"])
	var acid := w.db.add(Substance.new("a", "A", ["acidic", "porous"]))
	var box := w.place("container", Vector2i(3, 3), 0, w.starter, true)
	var box2 := w.place("container", Vector2i(8, 3), 0, w.starter, true)
	box.store(Portion.new(acid, 10.0))
	H.run(w, 10.0)
	var calm_loss := box.max_hp() - box.hp
	_ev(w, "acid", Vector2i(3, 3))
	box2.store(Portion.new(acid, 10.0))
	H.run(w, 10.0)
	var storm_loss := box2.max_hp() - box2.hp
	assert_gt(storm_loss, calm_loss * 2.0)

func test_storm_scatter_and_restore():
	var w := H.world(["storms"])
	var d := _ev(w, "storm", Vector2i(5, 5))
	assert_eq(w.event_mods.scatter, 3.0)
	d.current.t = 0.01
	w.tick(0.1)
	assert_eq(w.event_mods.scatter, 1.0)

func test_temp_shift_changes_phase_and_restores():
	var w := H.world(["tidally_locked"], 15.0)
	var vol := w.db.add(Substance.new("v", "V", ["volatile", "crystalline"]))
	var t0 := w.planet.ambient_temp
	var d := _ev(w, "temp_shift", Vector2i(5, 5))
	assert_almost_eq(abs(w.planet.ambient_temp - t0), 40.0, 0.01)
	assert_almost_eq(w.gas.ambient, w.planet.ambient_temp, 0.01)
	d.current.t = 0.01
	w.tick(0.1)
	assert_almost_eq(w.planet.ambient_temp, t0, 0.01)

func test_quake_breaks_pipes_and_opens_deposits():
	var w := H.world(["seismic"])
	w.planet.materials = [w.starter]
	for x in 5:
		w.place("pipe", Vector2i(2 + x, 2), 0, w.db.add(Substance.new("p%d" % x, "P", ["porous"])), true)
	var pipes := w.machines_of("pipe").size()
	_ev(w, "quake", Vector2i(20, 20))
	assert_lt(w.machines_of("pipe").size(), pipes)
	assert_gt(w.planet.deposits.size(), 0)

func test_flare_mutates_open_cargo():
	var w := H.world(["anomalous_field"])
	var box := w.place("container", Vector2i(10, 10), 0, w.starter, true)
	var s := w.db.add(Substance.new("x", "X", ["dense"]))
	box.store(Portion.new(s, 5.0))
	_ev(w, "flare", Vector2i(10, 10))
	H.run(w, 12.0)
	assert_ne(box.items[0].substance.tags, ["dense"])

func test_event_survives_save_load():
	var w := World.create(8)
	w.director.start("temp_shift", w.planet.spawn)
	w.director.current.t = 0.01
	w.tick(0.1)
	var shifted := w.planet.ambient_temp
	var w2 := SaveGame.from_dict(JSON.parse_string(JSON.stringify(SaveGame.to_dict(w))))
	assert_eq(w2.director.current.id, "temp_shift")
	assert_almost_eq(w2.planet.ambient_temp, shifted, 0.01)
