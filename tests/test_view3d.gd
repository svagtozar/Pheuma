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
