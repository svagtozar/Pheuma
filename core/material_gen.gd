class_name MaterialGen
## Генерация материалов: теги выбираются последовательно из пересечения
## пулов совместимых тегов; веса зависят от тегов планеты.

const SYL := ["ка", "рви", "тол", "ми", "ор", "зен", "лат", "ун", "бре", "сол", "нэ", "ир", "дар",
	"ку", "фе", "ло", "гри", "ас", "вел", "мор", "тан", "ри", "эс", "шо", "пе", "гал", "ви", "дро"]
const END := ["ит", "ий", "ан", "ол", "ум", "ид", "ин", "ор", "ен", "ат"]

static func make_name(rng: Rng, used: Dictionary) -> String:
	for _i in 50:
		var s: String = ""
		for _j in rng.range_i(1, 2):
			s += rng.pick(SYL)
		s += rng.pick(END)
		s = s.substr(0, 1).to_upper() + s.substr(1)
		if not used.has(s):
			used[s] = true
			return s
	return "Образец%d" % used.size()

static func tag_weights(planet_tags: Array, exotic_mult: float) -> Dictionary:
	var w := {}
	for t in MaterialTags.TAGS:
		w[t] = MaterialTags.TAGS[t].w
		if MaterialTags.is_exotic(t):
			w[t] *= exotic_mult
	for pt in planet_tags:
		var pw: Dictionary = PlanetTags.TAGS[pt].get("weights", {})
		for t in pw:
			w[t] = w.get(t, 0.0) * pw[t]
	return w

static func generate_one(rng: Rng, weights: Dictionary, used_names: Dictionary, forced: Array = []) -> Substance:
	var count := rng.range_i(2, 4)
	var tags := TagPool.pick(rng, MaterialTags.all(), count, weights, MaterialTags.compatible, forced)
	var noise := {
		"melt": rng.range_f(-120, 120), "boil": rng.range_f(-150, 150),
		"dens": rng.range_f(-0.4, 0.4), "hard": rng.range_f(-0.8, 0.8),
	}
	var nm := make_name(rng, used_names)
	return Substance.new(nm, nm, tags, noise)

static func generate(rng: Rng, count: int, planet_tags: Array = [], exotic_mult: float = 1.0) -> Array:
	var weights := tag_weights(planet_tags, exotic_mult)
	var used := {}
	var seen := {}
	var out: Array = []
	var attempts := 0
	while out.size() < count and attempts < count * 20:
		attempts += 1
		var s := generate_one(rng, weights, used)
		var key := ",".join(s.tags)
		if seen.has(key):
			continue
		seen[key] = true
		out.append(s)
	return out
