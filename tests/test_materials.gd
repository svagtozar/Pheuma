extends GutTest

func test_incompatible_tags_never_cooccur():
	for s in range(30):
		var mats := MaterialGen.generate(Rng.new(s), 12, [], 3.0)
		for m in mats:
			for a in m.tags:
				for b in m.tags:
					if a != b:
						assert_true(MaterialTags.compatible(a, b), "%s: %s + %s" % [m.name, a, b])

func test_generation_is_deterministic():
	var a := MaterialGen.generate(Rng.new(42), 10)
	var b := MaterialGen.generate(Rng.new(42), 10)
	assert_eq(a.size(), b.size())
	for i in a.size():
		assert_eq(a[i].name, b[i].name)
		assert_eq(a[i].tags, b[i].tags)
		assert_almost_eq(a[i].melt, b[i].melt, 0.0001)

func test_different_seeds_differ():
	var a := MaterialGen.generate(Rng.new(1), 10)
	var b := MaterialGen.generate(Rng.new(2), 10)
	var same := true
	for i in min(a.size(), b.size()):
		if a[i].tags != b[i].tags:
			same = false
	assert_false(same)

func test_unique_tag_sets():
	var mats := MaterialGen.generate(Rng.new(7), 12)
	var keys := {}
	for m in mats:
		keys[",".join(m.tags)] = true
	assert_eq(keys.size(), mats.size())

func test_phases():
	var s := Substance.new("x", "X", ["metallic"])
	assert_eq(s.phase_at(s.melt - 1), Substance.Phase.SOLID)
	assert_eq(s.phase_at((s.melt + s.boil) / 2.0), Substance.Phase.LIQUID)
	assert_eq(s.phase_at(s.boil + 1), Substance.Phase.GAS)

func test_phase_inverted():
	var s := Substance.new("x", "X", ["phase_inverted"])
	assert_eq(s.phase_at(s.boil + 10), Substance.Phase.SOLID)
	assert_eq(s.phase_at(s.melt - 10), Substance.Phase.GAS)

func test_add_tag_displaces_incompatible():
	var t := MaterialTags.add_tag(["porous", "organic"], "dense")
	assert_true("dense" in t)
	assert_false("porous" in t)
	assert_true("organic" in t)

func test_incompatibility_table_references_known_tags():
	for t in MaterialTags.TAGS:
		for i in MaterialTags.TAGS[t].inc:
			assert_true(MaterialTags.TAGS.has(i), "%s -> %s" % [t, i])

func test_derive_reuses_variants():
	var db := SubstanceDB.new()
	var base := db.add(Substance.new("A", "A", ["porous", "organic"]))
	var d1 := db.derive(base, ["dense", "organic"])
	var d2 := db.derive(base, ["organic", "dense"])
	assert_eq(d1, d2)
	assert_eq(d1.root, "A")
	assert_gt(d1.density, base.density)
