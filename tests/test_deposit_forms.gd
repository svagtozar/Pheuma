extends GutTest
## Формы залежей (ProtoDeposit): форма по тегам, куски бурятся, как кристаллы друзы.

func _sub(tags: Array) -> Substance:
	return Substance.new("t", "t", tags)

func test_form_by_tags():
	assert_eq(ProtoDeposit.form_for(_sub(["crystalline", "brittle"])), "druse")
	assert_eq(ProtoDeposit.form_for(_sub(["metallic", "conductive"])), "vein")
	assert_eq(ProtoDeposit.form_for(_sub(["dense", "magnetic"])), "nodules")
	assert_eq(ProtoDeposit.form_for(_sub(["brittle", "insulating"])), "strata")
	assert_eq(ProtoDeposit.form_for(_sub(["acidic", "oxidizer"])), "crust")
	assert_eq(ProtoDeposit.form_for(_sub(["fibrous", "toxic"])), "fibers")
	assert_eq(ProtoDeposit.form_for(_sub(["organic", "sticky"])), "resin")
	assert_eq(ProtoDeposit.form_for(_sub(["porous"])), "boulders")
	assert_eq(ProtoDeposit.form_for(_sub(["antigravitic", "crystalline"])), "floaters")

func test_every_form_has_drillable_pieces():
	var rng := RandomNumberGenerator.new()
	var look := ProtoDeposit.planet_look(null)
	for form in ProtoDeposit.NAMES:
		rng.seed = 3
		var s := _sub(["dense"])
		var n := ProtoDeposit.build(s, form, 1.0, rng, look)
		var pieces := n.get_children().filter(func(c): return c is MeshInstance3D and c.has_meta("len"))
		assert_gt(pieces.size(), 0, form)
		for p in pieces:
			assert_gt(float(p.get_meta("len")), 0.0, form)
			assert_gt(float(p.get_meta("r")), 0.0, form)
			assert_gt(ProtoMining.mass_of(p, s), 0.0, form)
		assert_eq(n.get_meta("sub"), s)
		assert_eq(n.get_meta("form"), form)
		n.free()

func test_gravity_squashes():
	var rng := RandomNumberGenerator.new()
	var heavy := {"squash": 0.7}
	rng.seed = 1
	var a := ProtoDeposit.build(_sub(["porous"]), "boulders", 1.0, rng, {})
	rng.seed = 1
	var b := ProtoDeposit.build(_sub(["porous"]), "boulders", 1.0, rng, heavy)
	assert_almost_eq(float(b.get_child(0).get_meta("len")), float(a.get_child(0).get_meta("len")) * 0.7, 0.001)
	a.free()
	b.free()

func test_mining_takes_substance_of_deposit():
	var m := ProtoMining.new()
	m.base_sub = _sub(["crystalline"])
	var vein := _sub(["metallic"])
	var rng := RandomNumberGenerator.new()
	var n := ProtoDeposit.build(vein, "vein", 1.0, rng, {})
	assert_eq(m.sub_of(n.get_child(0)), vein)
	assert_eq(ProtoMining.form_of(n.get_child(0)), "vein")
	n.free()
	m.free()
