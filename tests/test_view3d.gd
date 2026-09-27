extends GutTest
## 3D-вид игры: рельеф повторяет клетки планеты, робот стоит на поверхности.

const WorldView3D := preload("res://game/world_view_3d.gd")

func test_terrain_follows_tiles():
	var w := World.create(14)
	var t := TileTerrain.new(w)
	var seen := {}
	for y in range(2, w.planet.height - 2):
		for x in range(2, w.planet.width - 2):
			var c := Vector2i(x, y)
			var k := w.tile(c)
			if seen.has(k):
				continue
			# Клетка, окружённая такими же, — её центр без влияния соседей.
			var same := true
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				if w.tile(c + d) != k:
					same = false
			if same:
				seen[k] = t.cell_pos(c).y
	assert_true(seen.has(Planet.Tile.GROUND) and seen.has(Planet.Tile.ROCK))
	assert_gt(seen[Planet.Tile.ROCK], seen[Planet.Tile.GROUND] + 2.0, "скала выше равнины")
	if seen.has(Planet.Tile.CHASM):
		assert_lt(seen[Planet.Tile.CHASM], seen[Planet.Tile.GROUND] - 3.0, "расщелина ниже равнины")
	if seen.has(Planet.Tile.LAVA):
		assert_lt(seen[Planet.Tile.LAVA], t.liquid_level(), "лава под своей гладью")

func test_view_builds_and_tracks_robot():
	var w := World.create(14)
	var v := WorldView3D.new()
	add_child_autofree(v)
	v.set_world(w)
	assert_gt(v._chunks.size(), 1, "рельеф собран кусками")
	w.move_robot(Vector2(2.0, 0.0))
	v._process(0.1)
	var want := v.terrain.world_pos(w.robot.pos)
	assert_almost_eq(v.robot.position.x, want.x, 0.01)
	assert_almost_eq(v.robot.position.y, want.y, 0.01)
	# Луч из камеры в сторону робота попадает в клетку рядом с ним.
	var hit: Vector2 = v.screen_to_world(v.cam.unproject_position(v.robot.position))
	assert_lt(hit.distance_to(w.robot.pos), 1.5)

func test_tile_change_rebuilds_terrain():
	var w := World.create(14)
	var v := WorldView3D.new()
	add_child_autofree(v)
	v.set_world(w)
	var c := w.robot_cell() + Vector2i(3, 0)
	var before := v.terrain.cell_pos(c).y
	w.planet.set_tile(c, Planet.Tile.CHASM)       # толчок открыл расщелину
	v._sync(0.0, true)
	assert_lt(v.terrain.cell_pos(c).y, before - 3.0, "в 3D тоже провал")

func test_robot_stands_on_visible_mesh():
	# Высота робота — ровно на треугольниках сетки рельефа, а не на гладкой формуле.
	var w := World.create(14)
	var t := TileTerrain.new(w)
	t.fill_grid(Rect2i(Vector2i.ZERO, t.grid_n()))
	var r := Rect2i(Vector2i(40, 40), Vector2i(4, 4))
	var m := t.build_height_mesh(r)
	var v: PackedVector3Array = m.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	for p in [v[0], v[6], v[12]]:
		assert_almost_eq(t.mesh_h(p.x, p.z), p.y, 0.001, "в узле сетки")
	# Середина диагонали a-d квадрата — среднее двух узлов.
	var a := v[0]
	var d := v[6]
	assert_almost_eq(t.mesh_h((a.x + d.x) / 2.0, (a.z + d.z) / 2.0), (a.y + d.y) / 2.0, 0.001)

func test_robot_walks_around_machines_in_3d():
	var Main := preload("res://game/main.gd")
	var w := World.create(14)
	var c := w.robot_cell() + Vector2i(2, 0)
	var sub := World.starter_substance()
	assert_not_null(w.place("tank", c, 0, sub, true))
	var from := Vector2(c.x - 0.4, c.y + 0.5)
	# Прямо в бак — стоит на месте; вдоль стенки — скользит.
	assert_eq(Main.around_machines(w, from, from + Vector2(0.2, 0)), from)
	var along: Vector2 = Main.around_machines(w, from, from + Vector2(0.2, 0.1))
	assert_almost_eq(along.y, from.y + 0.1, 0.001)
	assert_almost_eq(along.x, from.x, 0.001)
	# Труба — не препятствие.
	var pc := c + Vector2i(0, 3)
	assert_not_null(w.place("pipe", pc, 0, sub, true))
	var f2 := Vector2(pc.x - 0.4, pc.y + 0.5)
	assert_eq(Main.around_machines(w, f2, f2 + Vector2(0.2, 0)), f2 + Vector2(0.2, 0))
