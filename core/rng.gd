class_name Rng
extends RefCounted
## Детерминированный генератор. fork(label) даёт независимый поток для подсистемы,
## чтобы изменения в одной части генерации не сдвигали другие.

var seed_value: int
var _r := RandomNumberGenerator.new()

func _init(s: int = 0) -> void:
	seed_value = s
	_r.seed = s

func fork(label: String) -> Rng:
	return Rng.new(hash(str(seed_value) + ":" + label))

func randf() -> float:
	return _r.randf()

func range_f(a: float, b: float) -> float:
	return _r.randf_range(a, b)

func range_i(a: int, b: int) -> int:
	return _r.randi_range(a, b)

func chance(p: float) -> bool:
	return _r.randf() < p

func pick(arr: Array):
	if arr.is_empty():
		return null
	return arr[_r.randi_range(0, arr.size() - 1)]

## keys — порядок перебора (для детерминизма), weights — ключ → вес.
func weighted_pick(keys: Array, weights: Dictionary):
	var total := 0.0
	for k in keys:
		total += max(0.0, float(weights.get(k, 1.0)))
	if total <= 0.0:
		return pick(keys)
	var x := _r.randf() * total
	for k in keys:
		x -= max(0.0, float(weights.get(k, 1.0)))
		if x <= 0.0:
			return k
	return keys[keys.size() - 1]
