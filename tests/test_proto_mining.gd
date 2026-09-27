extends GutTest
## Добыча кристаллов буром в 3D-прототипе (ProtoMining): прицел, откол, груз.

var root: Node3D
var robot: Node3D
var mining: ProtoMining

func _crystal_sub(hard: float) -> Substance:
	var s := Substance.new("t_cr", "Тест", ["crystalline"])
	s.hardness = hard
	return s

func _setup(sub: Substance, drill_hard: float) -> void:
	root = Node3D.new()
	add_child_autofree(root)
	robot = Node3D.new()
	root.add_child(robot)
	mining = ProtoMining.new()
	root.add_child(mining)
	mining.setup(sub, drill_hard, 15.0, null, ProtoCrystal.material(sub.color))
	# Друза на полу в полуметре перед роботом (робот смотрит в +Z).
	var druse := Node3D.new()
	druse.set_meta("normal", Vector3.UP)
	root.add_child(druse)
	var rng := RandomNumberGenerator.new()
	for i in 2:
		var c := MeshInstance3D.new()
		c.name = "crystal_%d" % i
		c.mesh = ProtoCrystal.mesh(0.8, 0.1, rng)
		c.set_meta("len", 0.8)
		c.set_meta("r", 0.1)
		c.position = Vector3(0.25 + i * 0.1, 0.0, 0.5)
		druse.add_child(c)
	mining.add_druse(druse)

func _run(seconds: float, work: float) -> void:
	var t := 0.0
	while t < seconds:
		mining.step(0.05, robot, work, work, Vector3.INF)
		t += 0.05

func test_drilling_breaks_crystal_into_cargo():
	_setup(_crystal_sub(3.0), 4.0)
	mining.step(0.05, robot, 0.0, 0.0, Vector3.INF)
	assert_not_null(mining.target, "кристалл перед роботом под прицелом")
	_run(6.0, 1.0)
	var cargo := ProtoMining.cargo_of(robot)
	assert_eq(cargo.size(), 1, "одна порция одного материала")
	assert_gt(cargo[0].mass, 0.0)
	assert_eq(cargo[0].substance.id, "t_cr")
	assert_lt(mining.crystals().size(), 2, "хотя бы один кристалл отколот")

func test_no_drilling_without_tool():
	_setup(_crystal_sub(3.0), 4.0)
	_run(3.0, 0.0)
	assert_eq(ProtoMining.cargo_of(robot).size(), 0)
	assert_eq(mining.crystals().size(), 2)

func test_soft_drill_cannot_mine():
	_setup(_crystal_sub(7.0), 3.0)
	_run(4.0, 1.0)
	assert_eq(ProtoMining.cargo_of(robot).size(), 0)
	assert_string_contains(mining.status, "слишком мягкий")

func test_cargo_is_shared_array_and_merges():
	_setup(_crystal_sub(3.0), 4.0)
	robot.set_meta("cargo", [])
	var shared: Array = robot.get_meta("cargo")
	_run(12.0, 1.0)
	assert_eq(shared.size(), 1, "та же порция пополняется, не плодятся новые")
	assert_eq(mining.crystals().size(), 0, "оба кристалла выбурены")

func test_action_registered_once():
	ProtoMining.ensure_action()
	assert_true(InputMap.has_action(ProtoMining.ACTION))
	var n := InputMap.action_get_events(ProtoMining.ACTION).size()
	ProtoMining.ensure_action()
	assert_eq(InputMap.action_get_events(ProtoMining.ACTION).size(), n)

func test_mined_druse_recorded_and_restored():
	_setup(_crystal_sub(3.0), 4.0)
	_run(12.0, 1.0)
	assert_eq(root.get_meta("mined", []), [0], "выбуренная друза — в метаданных корня")
	_setup(_crystal_sub(3.0), 4.0)
	mining.restore_mined([0])
	assert_eq(mining.crystals().size(), 0, "после загрузки кристаллов нет")
	assert_eq(root.get_meta("mined", []), [0])
