extends GutTest
## Инопланетная органика в 3D (ProtoFlora): сколько жизни по тегам, формы, стройка.

func _planet(tags: Array, temp := 20.0, grav := 1.0) -> Planet:
	var p := Planet.new()
	p.tags = tags
	p.ambient_temp = temp
	p.gravity = grav
	return p

func _flora(tags: Array, temp := 20.0, seed_value := 1) -> ProtoFlora:
	var p := _planet(tags, temp)
	return ProtoFlora.for_planet(p, ProtoWorldStyle.for_planet(p), seed_value)

func test_life_by_tags():
	assert_eq(_flora(["fungal_biosphere"]).life, 3, "грибная биосфера — буйная жизнь")
	assert_eq(_flora(["oceanic"]).life, 2, "океан — заросли")
	assert_eq(_flora(["frozen"], -110.0).life, 0, "мороз — мёртвая")
	assert_eq(_flora(["thin_atmosphere"]).life, 0, "без воздуха — мёртвая")
	assert_eq(_flora(["frozen"], -110.0).summary(), "жизнь: нет")

func test_forms_follow_tags_and_seed():
	var f := _flora(["oceanic"])
	assert_eq(f.forms.size(), 2, "у зарослей две крупные формы")
	for k in f.forms:
		assert_true(k in ProtoFlora.BIG_FORMS)
	# Одна и та же планета — одна и та же флора; разные seed — разные палитры.
	assert_eq(_flora(["oceanic"], 20.0, 5).hue, _flora(["oceanic"], 20.0, 5).hue)
	assert_ne(_flora(["oceanic"], 20.0, 5).hue, _flora(["oceanic"], 20.0, 6).hue)

func test_builds_batched_meshes():
	var p := _planet(["fungal_biosphere", "oceanic"])
	var st := ProtoWorldStyle.for_planet(p)
	var t := ProtoTerrain.new(8, st)
	var f := ProtoFlora.for_planet(p, st, 8)
	f.attach(t)
	t.build_field()
	var root := Node3D.new()
	add_child_autofree(root)
	var n := f.build(root, t, func(_q): return true)
	assert_gt(f.plants, 100, "растений много")
	assert_between(n, 1, 30, "склеены по кускам — десятки сеток, не тысячи")
	assert_eq(root.get_child_count(), n)
	assert_lt(f.verts(), 400000, "в пределах бюджета вершин")
	assert_true(t.bio.is_valid(), "ковёр поросли красит грунт")
