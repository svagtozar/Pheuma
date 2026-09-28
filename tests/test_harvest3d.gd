extends GutTest
## Сбор органики в 3D (ProtoHarvest): вещество, срез растения, выкос мелочи,
## груз и сохранение срезанного.

var H := TestHelpers

func _world() -> Array:
	var p := Planet.new()
	p.tags = ["fungal_biosphere", "oceanic"]
	p.ambient_temp = 20.0
	p.gravity = 1.0
	var s := H.sub(p, ["dense", "metallic"])
	p.materials = [s, H.sub(p, ["porous", "brittle"])]
	var st := ProtoWorldStyle.for_planet(p)
	var t := ProtoTerrain.new(8, st)
	var f := ProtoFlora.for_planet(p, st, 8)
	f.attach(t)
	t.build_field()
	var root := Node3D.new()
	add_child_autofree(root)
	f.build(root, t, func(_q): return true)
	return [p, f, root, t]

func test_biomass_is_fibrous_organic():
	var p := Planet.new()
	p.ambient_temp = 20.0
	var hard := H.sub(p, ["dense", "metallic"])
	var soft := H.sub(p, ["porous", "brittle"])
	p.materials = [hard, soft]
	var b := ProtoHarvest.biomass(p)
	assert_true(b.has("organic") and b.has("fibrous"), "растения — волокнистая органика")
	assert_eq(b.phase_at(20.0), Substance.Phase.SOLID, "срезанное — твёрдое")
	assert_eq(b.root, soft.root, "без органики на планете — от мягкого неметалла")
	assert_eq(ProtoHarvest.biomass(p), b, "одно и то же вещество при повторе")
	# Своя органика планеты — её и берём.
	var org := H.sub(p, ["organic", "dense"])
	p.materials.append(org)
	assert_eq(ProtoHarvest.biomass(p).root, org.root)
	# Жидкая здесь органика не годится — снова биомасса от мягкого.
	p.materials = [hard, soft, H.sub(p, ["organic", "sticky"])]
	assert_eq(ProtoHarvest.biomass(p).root, soft.root)

func test_loom_weaves_biomass():
	var pl := H.planet()
	pl.materials = [H.sub(pl, ["porous"])]
	var b := ProtoHarvest.biomass(pl)
	var ctx := {"db": pl.db, "pressure": 1.0, "compress_bonus": 0.0, "target_t": 900.0, "ambient": 15.0, "reagent": null, "filter_tag": ""}
	var r := Processor.run("loom", Portion.new(b, 2.0, 15.0), ctx)
	var tags: Array = r.outs[0][0].substance.tags
	assert_true("elastic" in tags and "insulating" in tags, "завод ткёт из органики полотно")

func test_items_cover_plants():
	var w := _world()
	var f: ProtoFlora = w[1]
	assert_gt(f.items.size(), 100, "растения запомнены для среза")
	var big := f.items.filter(func(it): return not ProtoHarvest.LOW.has(it.form))
	assert_gt(big.size(), 5, "есть крупные формы")
	for it in f.items.slice(0, 50):
		assert_gt(it.v1, it.v0)
		assert_gt(it.h, 0.0)

func test_cut_removes_plant_and_mows_low():
	var w := _world()
	var p: Planet = w[0]
	var f: ProtoFlora = w[1]
	var root: Node3D = w[2]
	var m := ProtoMining.new()
	root.add_child(m)
	var robot := Node3D.new()
	root.add_child(robot)
	m.robot = robot
	var hv := ProtoHarvest.new()
	root.add_child(hv)
	hv.setup(f, m, p)
	hv.robot = robot
	var n0 := hv.standing()
	# Крупное растение: только оно, отдельной сеткой, стоявшие вершины стянуты.
	var bi := -1
	for i in f.items.size():
		if not ProtoHarvest.LOW.has(f.items[i].form):
			bi = i
			break
	var it: Dictionary = f.items[bi]
	robot.position = it.p + Vector3(1.0, 0, 0)
	hv._cut(bi)
	assert_true(f.items[bi].cut)
	assert_eq(hv.standing(), n0 - 1)
	assert_eq(hv.falling.size(), 1)
	var mi: MeshInstance3D = f.meshes[it.key]
	var v: PackedVector3Array = mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	assert_almost_eq(v[it.v0].distance_to(it.p), 0.08, 0.001, "вершины среза стянуты под основание")
	assert_eq(root.get_meta("cut"), [bi])
	# Мелочь выкашивается полосой.
	var li := -1
	for i in f.items.size():
		if ProtoHarvest.LOW.has(f.items[i].form) and hv._group(i).size() >= 2:
			li = i
			break
	assert_gt(li, -1, "есть поросль кучками")
	var g := hv._group(li)
	hv._cut(li)
	for j in g:
		assert_true(f.items[j].cut)
	# Долетело — в грузе органика, в добычу кристаллов не засчитана.
	for k in 40:
		hv._falling(0.05)
	assert_eq(hv.falling.size(), 0)
	var cargo := ProtoMining.cargo_of(robot)
	assert_eq(cargo.size(), 1)
	assert_eq(cargo[0].substance, hv.sub)
	assert_almost_eq(cargo[0].mass, hv.harvested_total, 0.001)
	assert_eq(m.mined_total, 0.0)

func test_restore_cut():
	var w := _world()
	var f: ProtoFlora = w[1]
	var root: Node3D = w[2]
	var hv := ProtoHarvest.new()
	root.add_child(hv)
	hv.setup(f, ProtoMining.new(), w[0])
	var n0 := hv.standing()
	hv.restore_cut([3, 7, 99999])
	assert_eq(hv.standing(), n0 - 2)
	assert_eq(root.get_meta("cut"), [3, 7])

func test_pick_in_reach_and_in_front():
	var w := _world()
	var f: ProtoFlora = w[1]
	var root: Node3D = w[2]
	var hv := ProtoHarvest.new()
	root.add_child(hv)
	hv.setup(f, ProtoMining.new(), w[0])
	var bi := -1
	for i in f.items.size():
		if f.items[i].form == "tuft" or f.items[i].form == "curls":
			bi = i
			break
	var p: Vector3 = f.items[bi].p
	var robot := Node3D.new()
	root.add_child(robot)
	robot.position = p - Vector3(0, 0, 0.6)
	robot.rotation.y = 0.0          # смотрит на +Z — на растение
	var got := hv.pick(robot)
	assert_gt(got, -1, "поросль перед роботом в досягаемости")
	robot.position = p - Vector3(0, 0, 6.0)
	assert_eq(hv.pick(robot), -1, "далеко — ничего")
