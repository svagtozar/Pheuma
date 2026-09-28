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
func test_every_2d_machine_kind_has_its_own_3d_model():
	var mat := StandardMaterial3D.new()
	var shapes := {}
	for k in Buildings.KINDS:
		var n := MachineModels.build(k, mat)
		assert_gt(float(n.get_meta("h", 0.0)), 0.2, "%s: у модели есть высота" % k)
		assert_gt(n.get_child_count(), 1, "%s: модель из нескольких тел" % k)
		shapes[_shape(n)] = true
		n.free()
	# Кроме пар «компрессор/декомпрессор» и логических вентилей силуэты разные.
	assert_gt(shapes.size(), Buildings.KINDS.size() - 4, "силуэты машин различаются")

func _shape(n: Node) -> String:
	var parts := PackedStringArray()
	for ch in n.find_children("*", "MeshInstance3D", true, false):
		parts.append("%s@%s" % [ch.mesh.get_class(), str(ch.position.snapped(Vector3.ONE * 0.05))])
	parts.sort()
	return ",".join(parts)

func test_moving_things_show_in_3d():
	var w := World.create(14)
	var v := WorldView3D.new()
	add_child_autofree(v)
	v.set_world(w)
	var c := w.robot_cell()
	var p := w.robot.pos
	var ore: Substance = w.starter
	w.spawn_projectile(p, p + Vector2(6, 0), [Portion.new(ore, 2.0)])
	w.drones.append({"src": -1, "dst": -1, "pos": p + Vector2(1, 1), "cargo": Portion.new(ore, 1.0), "speed": 1.0, "cap": 2.0})
	w.fires[c + Vector2i(2, 0)] = 5.0
	w.ground[c + Vector2i(0, 2)] = [Portion.new(ore, 3.0), Portion.new(ore, 1.0)]
	v._process(0.1)
	var fx: WorldFx3D = v._fx3d
	assert_true(fx._shots.size() >= 1 and fx._shots[0].visible, "капсула летит")
	var arc: Vector3 = fx._shots[0].position
	assert_gt(arc.y, v.terrain.world_pos(p).y + 1.0, "капсула над землёй, на дуге")
	assert_true(fx._drones.size() >= 1 and fx._drones[0].visible, "дрон в воздухе")
	assert_true(fx._drones[0].get_node("cargo").visible, "дрон несёт груз")
	assert_true(fx._fires.has(c + Vector2i(2, 0)), "огонь горит")
	assert_eq(fx._ground.get_child_count(), 2, "две порции на земле")
	w.fires.clear()
	w.projectiles.clear()
	v._process(0.1)
	assert_false(fx._fires.has(c + Vector2i(2, 0)), "огонь погас и в 3D")
	assert_false(fx._shots[0].visible, "капсула долетела")

func test_machines_get_models_and_lamps():
	var w := World.create(14)
	var c := w.robot_cell() + Vector2i(2, 0)
	var m := w.place("centrifuge", c, 0, w.starter, true)
	var v := WorldView3D.new()
	add_child_autofree(v)
	v.set_world(w)
	assert_true(v._live.has(m.id), "у машины живые части")
	assert_not_null(v._live[m.id].lamp, "есть лампа")
	var spins: Array = v._live[m.id].node.find_children("*", "", true, false).filter(
		func(c): return c.has_meta("anim") and c.get_meta("anim").type == "spin")
	assert_eq(spins.size(), 1, "у центрифуги крутится барабан")
	m.enabled = false
	v._process(0.1)
	assert_eq(v._live[m.id].lamp.material_override, MachineModels.mat("lamp_off"), "выключенная — красная лампа")

func test_machine_parts_move_only_while_working():
	# Движения за работой (MachineKit.anim): крутится, ходит, дымит — только в работе.
	var body := StandardMaterial3D.new()
	for kind in ["pump", "crusher", "sinter", "loom", "centrifuge", "fabricator"]:
		var n := MachineModels.build(kind, body)
		add_child_autofree(n)
		MachineKit.animate(n, false, 0.0, 0.1)
		var anims: Array = n.get_meta("anims")
		assert_gt(anims.size(), 0, "%s: есть живые части" % kind)
		var still := anims.map(func(a): return a.transform if a is Node3D else Transform3D())
		MachineKit.animate(n, false, 1.3, 0.1)
		assert_eq(anims.map(func(a): return a.transform if a is Node3D else Transform3D()), still, "%s: в простое стоит" % kind)
		MachineKit.animate(n, true, 1.3, 0.1)
		assert_ne(anims.map(func(a): return a.transform if a is Node3D else Transform3D()), still, "%s: в работе движется" % kind)
		MachineKit.animate(n, false, 2.0, 0.1)
		for a in anims:
			if a is CPUParticles3D:
				assert_false(a.emitting, "%s: в простое не дымит" % kind)
	# Печь: дым из трубы и дыхание пламени — только в работе.
	var f := MachineModels.build("furnace", body)
	add_child_autofree(f)
	MachineKit.animate(f, true, 0.5, 0.1)
	var smoke: Array = f.get_meta("anims").filter(func(a): return a is CPUParticles3D)
	assert_eq(smoke.size(), 1, "у печи дымит труба")
	assert_true(smoke[0].emitting, "в работе дымит")
	MachineKit.animate(f, false, 0.6, 0.1)
	assert_false(smoke[0].emitting, "в простое не дымит")
