class_name Recipes
## Рецепты тегов, выведенные из таблицы взаимодействий, способов обработки и среды.
## Используется для проверки «у каждого тега есть рецепт», выбора целей планеты и
## подсказок Шамана.

## tag → [{kind, id, needs, reagent|planet|source}]
static func producers() -> Dictionary:
	var out := {}
	for t in MaterialTags.TAGS:
		out[t] = []
	for r in Interactions.RULES:
		for t in r.get("add", []):
			if r.get("env", false):
				out[t].append({"kind": "env", "id": Interactions.key(r), "needs": [r.b], "planet": r.a})
			else:
				out[t].append({"kind": "interaction", "id": Interactions.key(r), "needs": [r.b], "reagent": r.a})
	for pid in Processes.PROCESSES:
		var p: Dictionary = Processes.PROCESSES[pid]
		for rule in p.rules:
			for t in rule.get("add", []):
				out[t].append({"kind": "process", "id": pid, "needs": rule.get("all", []),
					"any": rule.get("any", []) + p.get("needs_any", []), "source": p.get("source", "")})
	return out

static func describe(entry: Dictionary) -> String:
	var needs := ", ".join(entry.needs.map(func(t): return MaterialTags.display(t)))
	match entry.kind:
		"interaction":
			return "Обработчик: реагент «%s» → материал «%s»" % [MaterialTags.display(entry.reagent), needs]
		"env":
			return "Среда «%s» на открытом воздухе → «%s»" % [PlanetTags.display(entry.planet), needs]
		_:
			var s: String = Processes.PROCESSES[entry.id].n
			if needs != "":
				s += ": из «%s»" % needs
			if not entry.any.is_empty():
				s += " (нужно одно из: %s)" % ", ".join(entry.any.map(func(t): return MaterialTags.display(t)))
			return s

## Какие теги можно получить, имея исходные теги и среду планеты.
static func reachable(start_tags: Array, planet_tags: Array = []) -> Dictionary:
	var have := {}
	for t in start_tags:
		have[t] = true
	var prod := producers()
	var changed := true
	while changed:
		changed = false
		for t in prod:
			if have.has(t):
				continue
			for e in prod[t]:
				if _applicable(e, have, planet_tags):
					have[t] = true
					changed = true
					break
	return have

static func _applicable(e: Dictionary, have: Dictionary, planet_tags: Array) -> bool:
	for n in e.needs:
		if not have.has(n):
			return false
	match e.kind:
		"interaction":
			return have.has(e.reagent)
		"env":
			return e.planet in planet_tags
		_:
			if e.source != "" and not have.has(e.source):
				return false
			if not e.any.is_empty():
				for a in e.any:
					if have.has(a):
						return true
				return false
			return true
