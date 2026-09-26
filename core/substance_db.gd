class_name SubstanceDB
extends RefCounted
## Реестр материалов рана. Производные материалы (тот же корень, другие теги)
## создаются по требованию и переиспользуются.

var by_id := {}
var _by_key := {}
var _variants := {}

func add(s: Substance) -> Substance:
	by_id[s.id] = s
	_by_key[_key(s.root, s.tags)] = s
	return s

func get_sub(id: String) -> Substance:
	return by_id.get(id)

func all() -> Array:
	return by_id.values()

func derive(base: Substance, new_tags: Array) -> Substance:
	var tags := new_tags.duplicate()
	tags.sort()
	if tags == base.tags:
		return base
	var key := _key(base.root, tags)
	if _by_key.has(key):
		return _by_key[key]
	var n: int = _variants.get(base.root, 1) + 1
	_variants[base.root] = n
	var s := Substance.new("%s#%d" % [base.root, n], base.root, tags, base.noise)
	s.name = "%s-%d" % [base.root, n]
	return add(s)

## Восстановить производный материал из сохранения (с тем же id).
func restore(id: String, root: String, name: String, tags: Array) -> Substance:
	if by_id.has(id):
		return by_id[id]
	var base: Substance = null
	for s in by_id.values():
		if s.root == root:
			base = s
			break
	var s := Substance.new(id, root, tags, base.noise if base != null else {})
	s.name = name
	var parts := id.split("#")
	if parts.size() == 2:
		_variants[root] = max(_variants.get(root, 1), int(parts[1]))
	return add(s)

func _key(root: String, tags: Array) -> String:
	return root + "|" + ",".join(tags)
