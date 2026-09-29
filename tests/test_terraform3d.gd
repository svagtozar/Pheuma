extends GutTest
## Терраформирование в 3D: климат планеты (ProtoTerraform), газоотвод завода,
## зеркала из пусковой шахты, этап p_vent, зелёные зоны куполов, флора и правка
## рельефа (ProtoTerrain.edit, ProtoTerrainChunks, ProtoDigger).

var planet: Planet
var steel: Substance
var crystal: Substance
var net: ProtoPneumatics
var run: ProtoRun

func before_each():
	planet = PlanetGen.generate(14)
	steel = TestHelpers.sub(planet, ["metallic", "dense"], "Сталь")
	crystal = TestHelpers.sub(planet, ["crystalline", "luminous"], "Кварц")
	net = ProtoPneumatics.new(planet)
	run = ProtoRun.new(planet, [steel])
	run.attach(net, null, autofree(Node3D.new()), crystal, Vector3.ZERO)
	run.ev_next = 1e9

func _tick(secs: float) -> void:
	var t := 0.0
	while t < secs:
		net.step(0.1)
		run.tick(0.1)
		t += 0.1

func test_vent_is_in_build_menu():
	assert_has(ProtoPneumatics.ORDER, "vent")
	assert_true(ProtoPneumatics.KINDS.has("vent"))

func test_pump_and_vent_raise_planet_pressure():
	var p0 := planet.atm_pressure
	net.place("pump", Vector2i(0, 0), 0, steel)
	net.place("vent", Vector2i(1, 0), 0, steel)
	_tick(30.0)
	assert_gt(net.vented, 10.0, "газоотвод выпускает газ, который накачал насос")
	assert_almost_eq(run.terra.vented, net.vented, 0.01)
	assert_gt(planet.atm_pressure, p0 + 0.03, "давление планеты растёт")
	assert_eq(net.gas.atm_pressure, planet.atm_pressure, "сеть завода знает новое давление")

func test_vent_without_pump_is_idle():
	net.place("vent", Vector2i(0, 0), 0, steel)
	_tick(5.0)
	assert_eq(net.vented, 0.0)
	assert_string_contains(net.parts[Vector2i(0, 0)].status, "насос")

func test_vent_accepts_no_cargo():
	var v := net.place("vent", Vector2i(1, 0), 0, steel)
	assert_false(net._accept(v, Portion.new(crystal, 1.0), Vector2i(0, 0)))

func test_mirrors_warm_cold_planet_and_shade_hot_one():
	var cold := ProtoTerraform.new()
	cold.base_t = -100.0
	cold.add_mirrors(crystal, 10.0)
	assert_gt(cold.temp(), -100.0, "на холодной планете зеркала греют")
	var hot := ProtoTerraform.new()
	hot.base_t = 85.0
	hot.add_mirrors(crystal, 10.0)
	assert_lt(hot.temp(), 85.0, "на жаркой — затеняют")
	var dull := TestHelpers.sub(planet, ["fibrous"], "Войлок")
	var a := ProtoTerraform.new()
	a.add_mirrors(dull, 10.0)
	assert_lt(a.mirrors, 10.0, "неотражающий материал — зеркало похуже")

func test_launch_becomes_mirrors_in_run():
	var t0 := planet.ambient_temp
	var silo := net.place("launch_silo", Vector2i.ZERO, 0, steel)
	silo.items.append(Portion.new(crystal, 4.0))
	net.gas.add_gas(silo.id, net.gas.gas_for_pressure(silo.id, net.silo_p(silo) + 0.2))
	_tick(0.3)
	assert_almost_eq(run.terra.mirrors, 4.0, 0.01)
	assert_ne(planet.ambient_temp, t0, "зеркала на орбите меняют температуру планеты")

func test_habitability():
	assert_almost_eq(ProtoTerraform.habit_at(1.0, 20.0), 1.0, 0.001)
	assert_eq(ProtoTerraform.habit_at(0.05, 20.0), 0.0, "почти вакуум")
	assert_eq(ProtoTerraform.habit_at(1.0, -120.0), 0.0, "мороз")
	assert_between(ProtoTerraform.habit_at(1.0, -25.0), 0.1, 0.9, "у края — частично")

func test_climate_change_does_not_burst_factory():
	# Потепление на сотню градусов не рвёт сеть: газ «успевает стравиться».
	net.place("pump", Vector2i(0, 0), 0, steel)
	net.place("pipe", Vector2i(1, 0), 0, steel)
	_tick(20.0)
	var p := net.pressure(Vector2i(1, 0))
	run.terra.mirrors = 40.0
	_tick(0.2)
	assert_almost_eq(net.pressure(Vector2i(1, 0)), p, p * 0.1)
	assert_true(net.burst_log.is_empty())

func test_temp_shift_event_still_moves_pressure():
	net.place("pipe", Vector2i(0, 0), 0, steel)
	var id: int = net.parts[Vector2i(0, 0)].id
	net.gas.add_gas(id, net.gas.gas_for_pressure(id, 2.0))
	var p0 := net.pressure(Vector2i(0, 0))
	run.start_event("temp_shift")
	run._begin_event()
	_tick(0.2)
	assert_ne(snappedf(net.pressure(Vector2i(0, 0)), 0.01), snappedf(p0, 0.01), "резкий перепад давление чувствует")

func test_vent_stage_from_terraform_goal():
	var g := ProtoRun.adapt_goal(Goals.TEMPLATES.terraform)
	var types: Array = []
	for st in g.stages:
		for a in st.get("alt", [st]):
			types.append(a.type)
	assert_has(types, "p_vent")
	assert_has(ProtoRun.STAGE_TYPES, "p_vent")
	var st := ProtoRun.make_stage("p_vent", 1, 4.0)
	assert_eq(st.amount, 120.0)

func test_vent_stage_progress():
	planet.goal = {"n": "т", "stages": [ProtoRun.make_stage("p_vent", 0, 4.0), ProtoRun.make_stage("p_mine", 1, 4.0),
		ProtoRun.make_stage("p_mine", 2, 4.0)]}
	run.goals = GoalsTracker.new(run)
	run.resync()
	net.place("pump", Vector2i(0, 0), 0, steel)
	net.place("vent", Vector2i(1, 0), 0, steel)
	_tick(10.0)
	var nums := run.stage_numbers()
	assert_gt(nums[0], 1.0)
	assert_eq(nums[1], 60.0)
	assert_string_contains(run.advise(func(_a): return "?"), "небо")

func test_dome_grows_green_zone_and_loses_it():
	var dome := net.place("dome", Vector2i(0, 0), 0, steel)
	net.place("pump", Vector2i(1, 0), 0, steel)
	dome.temp = 20.0
	planet.ambient_temp = 20.0
	run.terra.base_t = 20.0
	run.terra._last_t = 20.0
	_tick(12.0)
	assert_true(run.terra.zones.has(Vector2i(0, 0)), "жилой купол зеленит округу")
	assert_gt(run.terra.zones[Vector2i(0, 0)], 1.0)
	net.remove(Vector2i(0, 0))
	_tick(0.2)
	assert_false(run.terra.zones.has(Vector2i(0, 0)), "нет купола — нет зоны")

func test_terra_save_roundtrip():
	run.terra.vented = 77.0
	run.terra.mirrors = 5.0
	run.terra.zones[Vector2i(2, 3)] = 4.5
	var d = JSON.parse_string(JSON.stringify(run.to_dict()))
	var fresh := ProtoRun.new(PlanetGen.generate(14), [steel])
	fresh.from_dict(d)
	assert_eq(fresh.terra.vented, 77.0)
	assert_eq(fresh.terra.mirrors, 5.0)
	assert_eq(fresh.terra.zones.get(Vector2i(2, 3)), 4.5)

func test_flora_share_needs_habitability_and_seeding():
	assert_eq(ProtoTerraFlora.global_share(0.2), 0.0)
	assert_gt(ProtoTerraFlora.global_share(1.0), 0.5)
	var t := ProtoTerraform.new()
	assert_eq(t.seeded(), 0.0, "жизни ещё нет")
	t.vented = ProtoTerraform.SEED_GAS
	assert_eq(t.seeded(), 1.0)

# ---------------------------------------------------------------- рельеф

func _terrain() -> ProtoTerrain:
	var t := ProtoTerrain.new(16, ProtoWorldStyle.for_planet(PlanetGen.generate(16)))
	t.build_field()
	return t

func test_terrain_dig_and_fill_change_density():
	var t := _terrain()
	var x := 59.0
	var z := 30.0
	var h := t.surface_h(x, z)
	assert_true(t.solid(x, h - 0.5, z))
	t.edit(Vector3(x, h - 0.1, z), 1.2, false)
	assert_false(t.solid(x, h - 0.5, z), "выкопано")
	assert_lt(t.floor_at(Vector3(x, h + 2.0, z)), h - 0.5, "пол — на дне ямы")
	assert_lt(t.field_at(Vector3(x, h - 0.5, z)), 0.0, "поле в узлах тоже поправлено")
	t.edit(Vector3(x + 6.0, t.surface_h(x + 6.0, z) - 0.3, z), 1.2, true)
	var h2 := t.surface_h(x + 6.0, z)
	assert_true(t.solid(x + 6.0, h2 + 0.4, z), "насыпано")
	assert_gt(t.floor_at(Vector3(x + 6.0, h2 + 3.0, z)), h2 + 0.3, "пол — на насыпи")

func test_pad_is_protected_and_edits_roundtrip():
	var t := _terrain()
	var pc := t.plateau()
	assert_false(t.can_edit(Vector3(pc.x, pc.y - 0.5, pc.z)), "площадка завода укреплена")
	t.edit(Vector3(59, t.surface_h(59, 30) - 0.1, 30), 1.2, false)
	var a := t.edits_to_array()
	var t2 := _terrain()
	var box := t2.edits_from_array(JSON.parse_string(JSON.stringify(a)))
	assert_ne(box.size, Vector3.ZERO)
	assert_eq(t2.solid(59, t.surface_h(59, 30) - 0.5, 30), t.solid(59, t.surface_h(59, 30) - 0.5, 30))

func test_chunks_tile_like_one_mesh_and_rebuild_only_touched():
	var t := _terrain()
	var area := AABB(Vector3(40, 0, 20), Vector3(24, t.sy, 24))
	var whole := t.build_mesh(area.position, Vector3i(24, t.sy, 24), 1.0)
	var ch: ProtoTerrainChunks = add_child_autofree(ProtoTerrainChunks.new())
	ch.build(t, area, 1.0, 9, null)
	var tris := 0
	for m in ch.meshes():
		if m.get_surface_count() > 0:
			tris += m.surface_get_array_index_len(0)
	assert_eq(tris, whole.surface_get_array_index_len(0), "куски вместе — те же грани, без щелей и дублей")
	var n := ch.rebuild(AABB(Vector3(42, 10, 22), Vector3(1, 1, 1)))
	assert_between(n, 1, 2, "перестраивается только задетый кусок")
	assert_eq(ch.pending(), n, "по куску за кадр — сначала в очередь")
	ch.flush()
	assert_eq(ch.pending(), 0)
	assert_eq(ch.rebuilt, n)

func test_digger_digs_ahead_and_fills_back():
	var t := _terrain()
	var root: Node3D = add_child_autofree(Node3D.new())
	var robot := Node3D.new()
	root.add_child(robot)
	var x := 59.0
	var z := 30.0
	robot.position = Vector3(x, t.surface_h(x, z), z)
	var d: ProtoDigger = add_child_autofree(ProtoDigger.new())
	d.setup(t, [], robot)
	var at := d.dig_point()
	var before := t.floor_at(at + Vector3(0, 3, 0))
	assert_true(d.step(0.05, true, false), "бур без кристалла копает")
	var n := t.edits.size()
	var s1 := d.soil
	for i in 8:
		d.step(0.05, true, false)
	assert_eq(t.edits.size(), n, "лунка растёт, а не множится правками")
	assert_gt(d.soil, s1, "грунт прибывает плавно")
	assert_lt(t.floor_at(at + Vector3(0, 3, 0)), before - 0.4)
	for i in 60:
		d.step(0.05, false, true)
	assert_almost_eq(d.soil, 0.0, 0.001, "грунт насыпан обратно")
	d.step(0.05, false, true)
	assert_string_contains(d.status, "грунта нет")
	assert_true(InputMap.has_action(ProtoDigger.FILL))

## Прицел: бур вгрызается туда, куда смотрит перекрестье — в стену, не только вниз.
func test_digger_digs_toward_aim_and_brush_spares_robot():
	var t := _terrain()
	var root: Node3D = add_child_autofree(Node3D.new())
	var robot := Node3D.new()
	root.add_child(robot)
	var x := 59.0
	var z := 30.0
	var g := t.surface_h(x, z)
	robot.position = Vector3(x, g, z)
	var d: ProtoDigger = add_child_autofree(ProtoDigger.new())
	d.setup(t, [], robot)
	# Точка сбоку и выше пола — как стена перед роботом.
	var wall := Vector3(x + 2.0, g + 1.2, z)
	d.aim = wall
	d.aim_dir = Vector3.RIGHT
	for i in 12:
		d.step(0.05, true, false)
	var e: Array = t.edits[t.edits.size() - 1]
	assert_almost_eq((e[0] as Vector3).y, g + 1.2, 0.01, "лунка на высоте прицела, не в полу")
	assert_gt((e[0] as Vector3).x, wall.x, "и чуть глубже по лучу")
	d.aim = Vector3(x + 20.0, g, z)
	d.step(0.05, true, false)
	assert_string_contains(d.status, "далеко")
	# Кисть у самых ног — насыпь не растёт на корпус.
	d.soil = 3.0
	d.aim = robot.position + Vector3(0.5, 0.1, 0)
	d.aim_dir = Vector3.DOWN
	for i in 20:
		d.step(0.05, false, true)
	if t.edits[t.edits.size() - 1][2] > 0.0:
		assert_lt(float(t.edits[t.edits.size() - 1][1]), 0.6, "насыпь не накрывает робота")

func test_digger_keeps_digging_with_full_bunker():
	var t := _terrain()
	var root: Node3D = add_child_autofree(Node3D.new())
	var robot := Node3D.new()
	root.add_child(robot)
	var x := 59.0
	var z := 30.0
	robot.position = Vector3(x, t.surface_h(x, z), z)
	var d: ProtoDigger = add_child_autofree(ProtoDigger.new())
	d.setup(t, [], robot)
	d.soil = ProtoDigger.SOIL_MAX
	var at := d.dig_point()
	var before := t.floor_at(at + Vector3(0, 3, 0))
	assert_true(d.step(0.05, true, false), "полный бункер копать не мешает")
	for i in 7:
		d.step(0.05, true, false)
	assert_almost_eq(d.soil, float(ProtoDigger.SOIL_MAX), 0.001)
	assert_eq(d.spilled, 1, "лишний грунт ссыпался")
	assert_string_contains(d.status, "полон")
	assert_lt(t.floor_at(at + Vector3(0, 3, 0)), before - 0.4)
