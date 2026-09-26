extends GutTest

var H := TestHelpers

func _run(p: Portion, ctx: String, env: Dictionary, seconds: float) -> Dictionary:
	var total := Handling.new_result()
	for i in int(seconds * 10):
		var r := Handling.tick(p, ctx, env, 0.1)
		total.lost += r.lost
		total.robot_damage += r.robot_damage
		total.container_damage += r.container_damage
		total.fire = total.fire or r.fire
		total.signal = total.signal or r.signal
		total.absorb_gas += r.absorb_gas
	return total

func test_volatile_evaporates_in_open_but_not_sealed():
	var pl := H.planet()
	var s := H.sub(pl, ["volatile", "organic"])
	var a := Portion.new(s, 10.0, 15.0)
	var b := Portion.new(s, 10.0, 15.0)
	# летучее с поднятой T плавления, чтобы оно было твёрдым/жидким — неважно, всё равно теряется
	_run(a, "open", H.env(pl), 10.0)
	_run(b, "sealed", H.env(pl), 10.0)
	assert_lt(a.mass, 9.0)
	assert_almost_eq(b.mass, 10.0, 0.001)

func test_flammable_ignites_in_oxidizing_atmosphere():
	var ox := H.planet(["oxidizing_atmosphere"])
	var calm := H.planet()
	var s1 := H.sub(ox, ["flammable", "dense"])
	var s2 := H.sub(calm, ["flammable", "dense"])
	var a := Portion.new(s1, 10.0)
	var b := Portion.new(s2, 10.0)
	var ra := _run(a, "ground", H.env(ox), 5.0)
	_run(b, "ground", H.env(calm), 5.0)
	assert_true(ra.fire)
	assert_lt(a.mass, 9.0)
	assert_almost_eq(b.mass, 10.0, 0.001)

func test_flammable_ignites_near_hot_machine():
	var pl := H.planet()
	var s := H.sub(pl, ["flammable", "dense"])
	var p := Portion.new(s, 10.0)
	var r := _run(p, "open", H.env(pl, {"hot_nearby": true}), 3.0)
	assert_true(r.fire)

func test_pyrophoric_safe_in_sealed_tank():
	var ox := H.planet(["oxidizing_atmosphere"])
	var s := H.sub(ox, ["pyrophoric", "metallic"])
	var a := Portion.new(s, 10.0)
	var b := Portion.new(s, 10.0)
	_run(a, "open", H.env(ox), 3.0)
	_run(b, "sealed", H.env(ox), 3.0)
	assert_lt(a.mass, 8.0)
	assert_almost_eq(b.mass, 10.0, 0.001)

func test_brittle_shatters_on_launch():
	var pl := H.planet()
	var s := H.sub(pl, ["brittle", "crystalline"])
	var p := Portion.new(s, 8.0)
	var r := Handling.event(p, "launch", H.env(pl))
	assert_eq(r.spawn.size(), 1)
	assert_almost_eq(p.mass + r.spawn[0].mass, 8.0, 0.001)
	assert_true(r.spawn[0].has("porous"))
	assert_false(r.spawn[0].has("crystalline"))

func test_acid_corrodes_unless_resistant_container():
	var pl := H.planet()
	var acid := H.sub(pl, ["acidic", "porous"])
	var steel := H.sub(pl, ["metallic", "dense"])
	var glass := H.sub(pl, ["crystalline", "dense"])
	var r1 := _run(Portion.new(acid, 10.0), "open", H.env(pl, {"container": steel}), 5.0)
	var r2 := _run(Portion.new(acid, 10.0), "open", H.env(pl, {"container": glass}), 5.0)
	assert_gt(r1.container_damage, 0.5)
	assert_eq(r2.container_damage, 0.0)

func test_phasing_leaks_unless_anchoring():
	var pl := H.planet()
	var ph := H.sub(pl, ["phasing", "luminous"])
	var plain := H.sub(pl, ["metallic", "dense"])
	var anchor := H.sub(pl, ["anchoring", "dense"])
	var a := Portion.new(ph, 10.0)
	var b := Portion.new(ph, 10.0)
	_run(a, "sealed", H.env(pl, {"container": plain}), 10.0)
	_run(b, "sealed", H.env(pl, {"container": anchor}), 10.0)
	assert_lt(a.mass, 7.0)
	assert_almost_eq(b.mass, 10.0, 0.001)

func test_radioactive_hurts_carrier_shield_helps():
	var pl := H.planet()
	var s := H.sub(pl, ["radioactive", "dense"])
	var r1 := _run(Portion.new(s, 10.0), "carried", H.env(pl), 5.0)
	var r2 := _run(Portion.new(s, 10.0), "carried", H.env(pl, {"shield": {"radiation": 0.8}}), 5.0)
	assert_gt(r1.robot_damage, 1.0)
	assert_lt(r2.robot_damage, r1.robot_damage * 0.5)

func test_toxic_poisons_carrier():
	var pl := H.planet()
	var s := H.sub(pl, ["toxic", "dense"])
	var r := _run(Portion.new(s, 5.0), "carried", H.env(pl), 4.0)
	assert_gt(r.robot_damage, 0.5)

func test_antigravitic_floats_away():
	var pl := H.planet()
	var s := H.sub(pl, ["antigravitic", "crystalline"])
	var p := Portion.new(s, 10.0)
	_run(p, "open", H.env(pl), 5.0)
	assert_lt(p.mass, 8.0)

func test_self_replicating_eats_neighbors():
	var pl := H.planet()
	var rep := Portion.new(H.sub(pl, ["self_replicating", "organic"]), 5.0)
	var food := Portion.new(H.sub(pl, ["dense", "metallic"]), 5.0)
	var e := H.env(pl, {"neighbors": [rep, food]})
	_run(rep, "sealed", e, 5.0)
	assert_gt(rep.mass, 5.2)
	assert_lt(food.mass, 4.8)
	assert_almost_eq(rep.mass + food.mass, 10.0, 0.01)

func test_echoing_duplicates_on_launch():
	var pl := H.planet()
	var s := H.sub(pl, ["echoing", "dense"])
	var p := Portion.new(s, 10.0)
	var r := Handling.event(p, "launch", H.env(pl))
	assert_almost_eq(p.mass, 10.0, 0.001)
	assert_eq(r.spawn.size(), 1)
	assert_false(r.spawn[0].has("echoing"))

func test_sticky_jams_cannon():
	var pl := H.planet()
	var p := Portion.new(H.sub(pl, ["sticky", "organic"]), 10.0)
	var r := Handling.event(p, "launch", H.env(pl))
	assert_not_null(r.jammed)
	assert_almost_eq(p.mass + r.jammed.mass, 10.0, 0.001)

func test_resonant_emits_signal_and_void_absorbs_gas():
	var pl := H.planet()
	var r1 := _run(Portion.new(H.sub(pl, ["resonant", "dense"]), 5.0), "sealed", H.env(pl), 1.0)
	var r2 := _run(Portion.new(H.sub(pl, ["void", "crystalline"]), 5.0), "sealed", H.env(pl), 1.0)
	assert_true(r1.signal)
	assert_gt(r2.absorb_gas, 0.0)

func test_chrono_lag_slows_effects():
	var pl := H.planet()
	var fast := Portion.new(H.sub(pl, ["volatile", "organic"]), 10.0)
	var slow := Portion.new(H.sub(pl, ["volatile", "organic", "chrono_lagged"]), 10.0)
	_run(fast, "open", H.env(pl), 5.0)
	_run(slow, "open", H.env(pl), 5.0)
	assert_gt(slow.mass, fast.mass)

func test_gas_escapes_open_container():
	var pl := H.planet()
	var s := H.sub(pl, ["metallic"])
	var p := Portion.new(s, 5.0, s.boil + 100.0)
	var r := Handling.tick(p, "open", H.env(pl), 0.5)
	assert_gt(r.lost, 0.5)

func test_cannon_modifiers():
	var pl := H.planet(["strong_magnetosphere"])
	var heavy := Portion.new(H.sub(pl, ["dense", "metallic"]), 1.0)
	var light := Portion.new(H.sub(pl, ["antigravitic", "crystalline"]), 1.0)
	var mag := Portion.new(H.sub(pl, ["magnetic"]), 1.0)
	assert_lt(Handling.cannon_range_factor(heavy, pl), 1.0)
	assert_gt(Handling.cannon_range_factor(light, pl), 1.0)
	assert_gt(Handling.cannon_scatter(mag, pl), 0.0)

func test_handling_rules_reference_known_tags():
	for r in HandlingRules.RULES:
		assert_true(MaterialTags.TAGS.has(r.tag), r.tag)

func test_volatile_cargo_does_not_evaporate_in_cannon():
	var w := TestHelpers.world()
	var vol := w.db.add(Substance.new("v", "V", ["volatile", "organic"]))
	var c := w.place("cannon", Vector2i(3, 3), 0, w.starter, true)
	c.store(Portion.new(vol, 5.0))
	TestHelpers.run(w, 10.0)
	assert_almost_eq(c.total_mass(), 5.0, 0.01)
