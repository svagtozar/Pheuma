extends GutTest

var H := TestHelpers

func _json(d):
	return JSON.parse_string(JSON.stringify(d))

func test_save_load_roundtrip():
	var w := World.create(11)
	var r := w.robot
	var c := w.planet.spawn + Vector2i(2, 0)
	var box := w.place("container", c, 1, w.starter)
	box.store(Portion.new(w.starter, 3.0))
	var derived := w.db.derive(w.starter, ["porous", "metallic"])
	box.store(Portion.new(derived, 2.0, 40.0))
	var sensor := w.place("sensor", c + Vector2i(0, 2), 3, w.starter)
	var wp := Vector2(c) + Vector2(1.5, 1.5)
	assert_eq(w.add_wire(sensor.cell, box.cell, 0, w.starter, [wp]), "")
	r.knowledge = 7
	r.learned["h1"] = true
	r.known_tags["porous"] = true
	w.launched.mass = 12.0
	w.goals.stage = 1
	r.pos += Vector2(1.0, 0.5)
	for i in 30:
		w.tick(0.1)
	var d = _json(SaveGame.to_dict(w))
	var w2 := SaveGame.from_dict(d)
	assert_eq(w2.planet.seed_value, 11)
	assert_eq(w2.machines.size(), w.machines.size())
	var box2 = w2.machine_at(c)
	assert_not_null(box2)
	assert_eq(box2.facing, 1)
	assert_almost_eq(box2.total_mass(), box.total_mass(), 0.01)
	var found := false
	for p in box2.items:
		if p.substance.tags == derived.tags and p.substance.id == derived.id:
			found = true
	assert_true(found, "производный материал восстановлен")
	assert_eq(w2.logic.wires.size(), 1)
	assert_eq(w2.logic.wires.values()[0].points, [wp])
	assert_eq(w2.robot.knowledge, 7)
	assert_true(w2.robot.learned.has("h1"))
	assert_almost_eq(w2.robot.pos.x, r.pos.x, 0.001)
	assert_almost_eq(w2.robot.mass_of(w.starter.id), r.mass_of(w.starter.id), 0.01)
	assert_eq(w2.goals.stage, 1)
	assert_almost_eq(w2.launched.mass, 12.0, 0.001)
	assert_not_null(w2.robot.hull)
	for i in 30:
		w2.tick(0.1)
	assert_true(true, "загруженный мир тикается")

func test_save_keeps_gas_and_cannon_link():
	var w := H.world()
	var cannon := w.place("cannon", Vector2i(3, 3), 0, w.starter, true)
	var recv := w.place("receiver", Vector2i(8, 3), 0, w.starter, true)
	w.link_cannon(cannon.cell, recv.cell)
	w.gas.add_gas(cannon.id, 4.0)
	var d = SaveGame.to_dict(w)
	assert_eq(int(d.machines[0].config.target), recv.id)

func test_macroblock_capture_and_place_rotated():
	var w := H.world()
	w.robot.add_item(Portion.new(w.starter, 200.0))
	var a := w.place("filter", Vector2i(5, 5), 0, w.starter, true)
	a.config.tag = "porous"
	var b := w.place("container", Vector2i(6, 5), 0, w.starter, true)
	var s := w.place("sensor", Vector2i(6, 6), 3, w.starter, true)
	w.logic.add_wire(s.id, a.id, 0, [Vector2(5.5, 6.5)])
	var mb = _json(Macroblocks.capture(w, Rect2i(5, 5, 2, 2), "тест"))
	assert_eq(mb.parts.size(), 3)
	assert_eq(mb.wires.size(), 1)
	assert_gt(mb.ports.size(), 0)
	assert_eq(Macroblocks.place(w, mb, Vector2i(20, 20), 1, w.starter), "")
	# Поворот на 90°: (0,0)→(1,0), (1,0)→(1,1), (1,1)→(0,1)
	var fa = w.machine_at(Vector2i(21, 20))
	var fb = w.machine_at(Vector2i(21, 21))
	var fs = w.machine_at(Vector2i(20, 21))
	assert_eq(fa.kind, "filter")
	assert_eq(fa.facing, 1)
	assert_eq(fa.config.tag, "porous")
	assert_eq(fb.kind, "container")
	assert_eq(fs.kind, "sensor")
	assert_eq(fs.facing, 0)
	var wires := w.logic.wires_to(fa.id)
	assert_eq(wires.size(), 1)
	assert_eq(wires[0].from, fs.id)

func test_macroblock_blocked_and_costs_material():
	var w := H.world()
	w.place("container", Vector2i(5, 5), 0, w.starter, true)
	w.place("container", Vector2i(6, 5), 0, w.starter, true)
	var mb := Macroblocks.capture(w, Rect2i(5, 5, 2, 1), "пара")
	assert_ne(Macroblocks.can_place(w, mb, Vector2i(5, 5), 0, w.starter), "", "место занято")
	var before := w.robot.mass_of(w.starter.id)
	assert_eq(Macroblocks.place(w, mb, Vector2i(10, 10), 0, w.starter), "")
	assert_almost_eq(w.robot.mass_of(w.starter.id), before - 8.0, 0.01)

func test_macroblock_keeps_internal_cannon_target():
	var w := H.world()
	w.robot.add_item(Portion.new(w.starter, 200.0))
	var c := w.place("cannon", Vector2i(2, 2), 0, w.starter, true)
	var r := w.place("receiver", Vector2i(6, 2), 0, w.starter, true)
	w.link_cannon(c.cell, r.cell)
	var mb = _json(Macroblocks.capture(w, Rect2i(2, 2, 5, 1), "пушка"))
	assert_eq(Macroblocks.place(w, mb, Vector2i(2, 10), 0, w.starter), "")
	var c2 = w.machine_at(Vector2i(2, 10))
	var r2 = w.machine_at(Vector2i(6, 10))
	assert_eq(c2.config.target, r2.id)

func test_slots_meta_and_latest():
	var old_dir := SaveGame.DIR
	SaveGame.DIR = "user://test_saves"
	var w := World.create(4)
	for s in SaveGame.all_slots():
		SaveGame.delete_slot(s)
	assert_eq(SaveGame.latest_slot(), "")
	assert_eq(SaveGame.save_file(w, "slot2"), "")
	var m := SaveGame.slot_meta("slot2")
	assert_eq(m.planet, w.planet.name)
	assert_eq(int(m.stage), 1)
	assert_eq(SaveGame.latest_slot(), "slot2")
	assert_not_null(SaveGame.load_file("slot2"))
	SaveGame.delete_slot("slot2")
	assert_true(SaveGame.slot_meta("slot2").is_empty())
	SaveGame.DIR = old_dir
