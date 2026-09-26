class_name Progression
## Изучение узлов прокачки: очки знаний + опыт класса + предыдущий узел.

static func can_learn(r: RobotState, id: String) -> String:
	var n := SkillTree.node(id)
	if n.is_empty():
		return "нет такого узла"
	if r.learned.has(id):
		return "уже изучено"
	var prev := SkillTree.prev_of(id)
	if prev != "" and not r.learned.has(prev):
		return "сначала изучите «%s»" % SkillTree.node(prev).n
	if r.xp[n.cls] < n.xp:
		return "нужно опыта «%s»: %d (есть %d)" % [SkillTree.CLASSES[n.cls].n, n.xp, int(r.xp[n.cls])]
	if r.knowledge < n.cost:
		return "нужно знаний: %d (есть %d)" % [n.cost, r.knowledge]
	return ""

static func learn(r: RobotState, id: String) -> String:
	var err := can_learn(r, id)
	if err != "":
		return err
	var n := SkillTree.node(id)
	r.knowledge -= n.cost
	r.learned[id] = true
	if n.has("blueprint"):
		r.blueprints[n.blueprint] = true
	for k in n.get("unlock", []):
		r.unlocked[k] = true
	return ""

static func class_level(r: RobotState, cls: String) -> int:
	var c := 0
	for n in SkillTree.nodes_of(cls):
		if r.learned.has(n.id):
			c += 1
	return c
