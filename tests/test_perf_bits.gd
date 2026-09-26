extends GutTest
## Кусочки оптимизаций: демо-завод, отпечатки запечённых чанков.

var H := TestHelpers

func test_demo_factory_builds_exact_count():
	for n in [13, 40, 150]:
		var w := World.create(5)
		DemoFactory.build(w, w.planet.spawn + Vector2i(-14, -10), n)
		assert_eq(w.machines.size(), n, "завод из %d машин" % n)

class FakeView:
	var world: World
	func _deposit_visible(_c: Vector2i) -> bool:
		return true
	func ground_color() -> Color:
		return Color.GRAY

func test_tile_chunk_fingerprint_changes_with_tiles_and_deposits():
	var w := World.create(5)
	var v := FakeView.new()
	v.world = w
	var ch := TileChunk.new()
	ch.view = v
	ch.origin = Vector2i(16, 16)
	var f0 := ch.compute_fingerprint()
	assert_eq(ch.compute_fingerprint(), f0, "без изменений — тот же отпечаток")
	var c := Vector2i(20, 20)
	w.planet.set_tile(c, Planet.Tile.ROCK if w.tile(c) != Planet.Tile.ROCK else Planet.Tile.GROUND)
	var f1 := ch.compute_fingerprint()
	assert_ne(f1, f0, "клетка изменилась")
	w.tile_overrides[c] = {"tile": Planet.Tile.GROUND, "t": 5.0}
	assert_ne(ch.compute_fingerprint(), f1, "мост изменил отпечаток")
	var f2 := ch.compute_fingerprint()
	w.planet.deposits[Vector2i(21, 21)] = {"sub": w.starter.id, "amount": 50.0}
	assert_ne(ch.compute_fingerprint(), f2, "новая залежь")
	ch.free()

class FakeM:
	var cell: Vector2i
	func _init(c: Vector2i) -> void:
		cell = c

func test_machine_chunk_runs_merge_neighbours_without_overlap():
	var org := Vector2i(16, 0)
	var ms := [FakeM.new(Vector2i(16, 2)), FakeM.new(Vector2i(17, 2)), FakeM.new(Vector2i(18, 2)),
		FakeM.new(Vector2i(22, 2)), FakeM.new(Vector2i(20, 5))]
	var runs := MachineChunk.compute_runs(ms, org)
	assert_eq(runs.size(), 3, "три полосы: подряд идущие машины слились")
	var row2 := runs.filter(func(r): return r.position.y == 64.0)
	assert_eq(row2.size(), 2)
	row2.sort_custom(func(a, b): return a.position.x < b.position.x)
	assert_eq(row2[0].position.x, 0.0, "у края участка запас обрезан")
	assert_eq(row2[0].end.x, 3 * 32.0 + 6.0)
	assert_false(row2[0].intersects(row2[1]), "полосы не перекрываются")
