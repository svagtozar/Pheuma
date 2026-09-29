extends GutTest
## Рельеф участка на Voxel Tools (ProtoVoxelGround, ProtoVoxelGen): воксели
## повторяют поле ProtoTerrain, правка рельефа доходит до вокселей, цвет
## породы запечён у поверхности, коллизия — на слое ног робота.

var t: ProtoTerrain

func before_all():
	t = ProtoTerrain.new(16, ProtoWorldStyle.for_planet(PlanetGen.generate(16)))
	t.build_field()

func test_extension_is_loaded():
	assert_true(ProtoVoxelGround.available(), "Voxel Tools (GDExtension) подключён")

func _block(origin: Vector3i, lod: int, gen: ProtoVoxelGen) -> VoxelBuffer:
	var b := VoxelBuffer.new()
	b.create(16, 16, 16)
	b.set_channel_depth(VoxelBuffer.CHANNEL_SDF, VoxelBuffer.DEPTH_32_BIT)
	gen._generate_block(b, origin, lod)
	return b

func test_generator_follows_terrain_field():
	var gen := ProtoVoxelGen.new()
	gen.load_field(t)
	gen.load_fine(t, t.cave_box)
	var x := 59
	var z := 30
	var h := t.surface_h(x, z)
	# LOD 0: воксель 0,5 м; блок вокруг поверхности в (59, h, 30).
	var o := Vector3i(x * 2 - 8, int(h * 2) - 8, z * 2 - 8)
	var b := _block(o, 0, gen)
	var below := b.get_voxel_f(8, int(h * 2) - 4 - o.y, 8, VoxelBuffer.CHANNEL_SDF)
	var above := b.get_voxel_f(8, int(h * 2) + 4 - o.y, 8, VoxelBuffer.CHANNEL_SDF)
	assert_lt(below, 0.0, "под поверхностью — порода (у модуля минус)")
	assert_gt(above, 0.0, "над поверхностью — воздух")
	# LOD 1 — те же узлы 1 м.
	var y0 := int(h) - 8
	var b1 := _block(Vector3i(x - 8, y0, z - 8) * 2, 1, gen)
	for y in [int(h) - 6, int(h) - 2, int(h) + 2]:
		assert_almost_eq(b1.get_voxel_f(8, y - y0, 8, VoxelBuffer.CHANNEL_SDF), -t.dens[t._i(x, y, z)], 0.001,
			"LOD 1 — копия поля 1 м (y = %d)" % y)

func test_cave_is_hollow_in_lod0():
	var gen := ProtoVoxelGen.new()
	gen.load_field(t)
	gen.load_fine(t, t.cave_box)
	var c := t.cave_c
	var v := Vector3i((c / ProtoVoxelGen.VOXEL).floor())
	var b := _block(v - Vector3i(8, 8, 8), 0, gen)
	assert_gt(b.get_voxel_f(8, 8, 8, VoxelBuffer.CHANNEL_SDF), 0.0, "в середине зала — воздух")

func test_far_from_surface_block_is_uniform():
	var gen := ProtoVoxelGen.new()
	gen.load_field(t)
	# Блок 8 м целиком в воздухе высоко над поверхностью.
	var found := false
	for bx in range(0, 72, 8):
		for bz in range(0, 72, 8):
			var ok := true
			for x in range(bx, bx + 9):
				for z in range(bz, bz + 9):
					for y in range(27, 36):
						ok = ok and t.dens[t._i(x, y, z)] < -2.5
			if ok and not found:
				found = true
				var b := _block(Vector3i(bx, 27, bz) * 2, 0, gen)
				assert_true(b.is_uniform(VoxelBuffer.CHANNEL_SDF), "воздух далеко от поверхности — одним значением")
	assert_true(found)

func test_ground_meshes_edits_and_colors():
	var root: Node3D = add_child_autofree(Node3D.new())
	var vg := ProtoVoxelGround.new()
	root.add_child(vg)
	vg.build(t, t.material())
	assert_eq(vg.vt.get("collision_layer"), RobotGround.LAYER, "коллизия — на слое ног робота")
	var x := 59.0
	var z := 30.0
	var h := t.surface_h(x, z)
	var eye := Node3D.new()
	root.add_child(eye)
	eye.position = Vector3(x, h + 1.0, z)
	ProtoVoxelGround.add_viewer(eye)
	var box := AABB(Vector3(x - 3, h - 3, z - 3), Vector3(6, 6, 6))
	for i in 300:
		if vg.is_meshed(box):
			break
		await get_tree().process_frame
	assert_true(vg.is_meshed(box), "модуль построил сетку у наблюдателя")
	# Цвет запечён у поверхности: видимость неба наверху — почти 1.
	var c := vg.color_at(Vector3(x, h, z))
	assert_gt(c.a, 0.5, "у поверхности цвет запечён")
	# Выемка: поле ProtoTerrain — и воксели (paste) в той же точке.
	var p := Vector3(x, h - 0.5, z)
	var vox := Vector3i((p / ProtoVoxelGen.VOXEL).floor())
	assert_lt(vg.tool.call("get_voxel_f", vox), 0.0, "до правки — порода")
	var eb := t.edit(Vector3(x, h - 0.3, z), 1.4, false)
	vg.rebuild(eb, true)
	assert_eq(vg.pending(), 0)
	assert_eq(vg.rebuilt, 1)
	assert_gt(vg.tool.call("get_voxel_f", vox), 0.0, "после правки воксели — воздух")
