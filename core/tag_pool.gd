class_name TagPool
## Общий алгоритм выбора тегов для материалов и планет:
## пул = все теги; выбрали тег → пул = пул ∩ совместимые(тег); повторить.

## compat: Callable(a, b) -> bool
static func pick(rng: Rng, all_tags: Array, count: int, weights: Dictionary, compat: Callable, forced: Array = []) -> Array:
	var result: Array = []
	var pool: Array = all_tags.duplicate()
	pool.sort()
	for f in forced:
		if f in pool:
			result.append(f)
			pool = pool.filter(func(t): return compat.call(f, t))
	while result.size() < count and not pool.is_empty():
		var chosen: String = rng.weighted_pick(pool, weights)
		result.append(chosen)
		pool = pool.filter(func(t): return compat.call(chosen, t))
	result.sort()
	return result
