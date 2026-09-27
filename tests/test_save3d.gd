extends GutTest
## Сохранение 3D-прототипа: робот, груз, добытые друзы, производные материалы,
## пневмозавод (если он уже есть в proto/).

const PNEU := "res://proto/pneumatics.gd"

class FakeRoot:
	extends Node3D
	var seed_value := 0
	var planet: Planet
	var robot: Node3D
	var pneu = null
	var restored: Array = []
	func restore_mined(ids: Array) -> void:
		restored = ids

var _dir := ""

func before_each():
	_dir = ProtoSave.DIR
	ProtoSave.DIR = "user://test_saves3d"

func after_each():
	for f in DirAccess.get_files_at(ProtoSave.DIR):
		DirAccess.remove_absolute(ProtoSave.DIR + "/" + f)
	ProtoSave.DIR = _dir

func _root(seed_value: int) -> FakeRoot:
	var r := FakeRoot.new()
	r.seed_value = seed_value
	r.planet = PlanetGen.generate(seed_value)
	r.robot = Node3D.new()
	r.add_child(r.robot)
	if ResourceLoader.exists(PNEU):
		r.pneu = load(PNEU).new(r.planet)
	autofree(r)
	return r

func test_robot_cargo_and_mined_roundtrip():
	var a := _root(21)
	a.robot.position = Vector3(3.5, 12.25, -7.0)
	a.robot.rotation.y = 1.2
	var ore: Substance = a.planet.materials[0]
	var derived := a.planet.db.derive(ore, ["dense", "porous"] if ore.tags != ["dense", "porous"] else ["porous", "metallic"])
	a.robot.set_meta("cargo", [Portion.new(ore, 4.5, 20.0), Portion.new(derived, 1.5, 300.0)])
	a.set_meta("mined", [2, 5])
	assert_eq(ProtoSave.write(a), "")
	assert_eq(ProtoSave.last_seed(), 21)

	var b := _root(21)
	ProtoSave.apply(b, ProtoSave.read(21))
	assert_almost_eq(b.robot.position, Vector3(3.5, 12.25, -7.0), Vector3.ONE * 0.001)
	assert_almost_eq(b.robot.rotation.y, 1.2, 0.001)
	var cargo: Array = b.robot.get_meta("cargo")
	assert_eq(cargo.size(), 2)
	assert_eq(cargo[0].substance.id, ore.id)
	assert_almost_eq(cargo[0].mass, 4.5, 0.001)
	assert_eq(cargo[1].substance.id, derived.id, "производный материал пережил загрузку")
	assert_eq(cargo[1].substance.tags, derived.tags)
	assert_almost_eq(cargo[1].temp, 300.0, 0.001)
	assert_eq(b.get_meta("mined"), [2, 5])
	assert_eq(b.restored, [2, 5], "корень узнал, какие друзы уже добыты")

func test_each_planet_has_own_file():
	var a := _root(3)
	a.robot.position = Vector3(1, 2, 3)
	ProtoSave.write(a)
	var c := _root(4)
	c.robot.position = Vector3(9, 9, 9)
	ProtoSave.write(c)
	assert_eq(ProtoSave.last_seed(), 4)
	assert_eq(ProtoSave.read(3).robot.pos, [1.0, 2.0, 3.0])
	assert_true(ProtoSave.read(5).is_empty())

func test_broken_or_foreign_file_is_ignored():
	DirAccess.make_dir_recursive_absolute(ProtoSave.DIR)
	var f := FileAccess.open(ProtoSave.path_for(8), FileAccess.WRITE)
	f.store_string("{не json")
	f.close()
	assert_true(ProtoSave.read(8).is_empty())
	f = FileAccess.open(ProtoSave.path_for(9), FileAccess.WRITE)
	f.store_string(JSON.stringify({"version": ProtoSave.VERSION, "seed": 10}))
	f.close()
	assert_true(ProtoSave.read(9).is_empty(), "файл чужой планеты")

func test_actions_have_key_and_pad():
	ProtoSave.ensure_actions()
	var ev := InputMap.action_get_events(ProtoSave.SAVE_NOW)
	assert_true(ev.any(func(e): return e is InputEventKey))
	assert_true(ev.any(func(e): return e is InputEventJoypadButton))

func test_factory_roundtrip():
	if not ResourceLoader.exists(PNEU):
		pending("пневмозавода в proto/ ещё нет")
		return
	var a := _root(21)
	var metal: Substance = a.planet.materials[0]
	a.pneu.build_demo(Vector2i(-3, 0), metal)
	var intake := Vector2i(-3, 0)
	a.pneu.feed(intake, Portion.new(metal, 12.0, 15.0))
	for i in 120:
		a.pneu.step(0.05)
	ProtoSave.write(a)

	var b := _root(21)
	b.pneu.place("tank", Vector2i(10, 10), 0, metal)   # лишняя деталь пропадёт
	ProtoSave.apply(b, ProtoSave.read(21))
	assert_eq(b.pneu.parts.size(), a.pneu.parts.size())
	assert_false(b.pneu.parts.has(Vector2i(10, 10)))
	for c in a.pneu.parts:
		var pa: Dictionary = a.pneu.parts[c]
		var pb: Dictionary = b.pneu.parts[c]
		assert_eq(pb.kind, pa.kind)
		assert_eq(pb.dir, pa.dir)
		assert_almost_eq(b.pneu.pressure(c), a.pneu.pressure(c), 0.001, "давление в %s" % str(c))
		assert_almost_eq(b.pneu.mass_in(c), a.pneu.mass_in(c), 0.001, "груз в %s" % str(c))
	assert_eq(b.pneu.capsules().size(), a.pneu.capsules().size())
