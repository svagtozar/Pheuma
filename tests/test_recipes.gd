extends GutTest

func test_every_tag_has_a_recipe():
	var prod := Recipes.producers()
	for t in MaterialTags.TAGS:
		assert_gt(prod[t].size(), 0, "нет рецепта для %s" % t)

func test_every_tag_reachable_from_ordinary_tags():
	var have := Recipes.reachable(MaterialTags.normal_tags())
	for t in MaterialTags.TAGS:
		assert_true(have.has(t), "недостижим %s" % t)

func test_exotic_reachable_without_exotic_start():
	var have := Recipes.reachable(MaterialTags.normal_tags())
	for t in MaterialTags.exotic_tags():
		assert_true(have.has(t), t)

func test_interaction_tags_do_not_mix():
	var r := Interactions.apply(["acidic"], ["alkaline", "porous"])
	assert_false("acidic" in r.tags, "тег реагента не переходит в цель")
	assert_false("alkaline" in r.tags)
	assert_true("hygroscopic" in r.tags)
	assert_true("acidic>alkaline" in r.keys)

func test_env_rules_only_when_requested():
	var r := Interactions.apply(["acid_rain"], ["metallic"])
	assert_eq(r.tags, ["metallic"])
	var e := Interactions.apply(["acid_rain"], ["metallic"], true)
	assert_true("porous" in e.tags)

func test_interaction_tags_are_known():
	for r in Interactions.RULES:
		if r.get("env", false):
			assert_true(PlanetTags.TAGS.has(r.a), r.a)
		else:
			assert_true(MaterialTags.TAGS.has(r.a), r.a)
		assert_true(MaterialTags.TAGS.has(r.b), r.b)
		for t in r.get("add", []) + r.get("remove", []):
			assert_true(MaterialTags.TAGS.has(t), t)

func test_process_tags_are_known():
	for pid in Processes.PROCESSES:
		for rule in Processes.PROCESSES[pid].rules:
			for k in ["all", "any", "none", "add", "remove"]:
				for t in rule.get(k, []):
					assert_true(MaterialTags.TAGS.has(t), "%s: %s" % [pid, t])

func test_describe_all_producers():
	var prod := Recipes.producers()
	for t in prod:
		for e in prod[t]:
			assert_ne(Recipes.describe(e), "")
