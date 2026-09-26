class_name TestHelpers
## Общие заготовки для тестов.

static func planet(tags: Array = [], temp: float = 15.0) -> Planet:
	var p := Planet.new()
	p.tags = tags
	p.ambient_temp = temp
	p.atmosphere = Substance.new("atm", "Атм", ["volatile"])
	p.width = 20
	p.height = 20
	p.tiles.resize(400)
	p.spawn = Vector2i(10, 10)
	return p

static func env(p: Planet, extra: Dictionary = {}) -> Dictionary:
	var e := {"planet": p, "db": p.db, "rng": Rng.new(1), "container": null, "neighbors": [], "shield": {}}
	e.merge(extra, true)
	return e

static func sub(p: Planet, tags: Array, name: String = "") -> Substance:
	if name == "":
		name = "S" + str(p.db.by_id.size())
	return p.db.add(Substance.new(name, name, tags))
