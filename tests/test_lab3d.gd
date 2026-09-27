extends GutTest
## Разведка материалов в 3D: ProtoLabDesk (прототип и игра), лаборатория
## пневмозавода, карточка ProtoLabPanel.

var H := TestHelpers

class FakeMining:
	var sub: Substance
	var temp := 15.0
	var nodes: Array = []
	func crystals() -> Array:
		return nodes

var w: World
var robot: Node3D

func before_each():
	w = H.world()
	w.robot.tank = w.robot.tank_cap()
	robot = Node3D.new()
	add_child_autofree(robot)

func _sub(tags: Array, name: String = "Обр") -> Substance:
	return w.db.add(Substance.new(name, name, tags))

func _desk_with_cargo(s: Substance, kg: float) -> ProtoLabDesk:
	robot.set_meta("cargo", [Portion.new(s, kg)])
	return ProtoLabDesk.new(w, robot)

func _cargo_kg(s: Substance) -> float:
	var m := 0.0
	for p in robot.get_meta("cargo"):
		if p.substance == s:
			m += p.mass
	return m

func test_probe_takes_sample_from_cargo():
	var s := _sub(["flammable", "dense"])
	var d := _desk_with_cargo(s, 3.0)
	var inv0 := w.robot.inventory.size()
	assert_eq(d.probe(s, "heat"), "")
	assert_true("flammable" in w.known_tags_of(s), "проба нашла горючесть")
	assert_true("dense" in w.known_tags_of(s), "видимое заметно само")
	assert_almost_eq(_cargo_kg(s), 3.0 - Probes.SAMPLE_KG, 0.01, "образец взят из груза")
	assert_eq(w.robot.inventory.size(), inv0, "в инвентаре World ничего не осело")

func test_failed_probe_returns_sample():
	var s := _sub(["conductive", "brittle"])
	var d := _desk_with_cargo(s, 2.0)
	w.robot.tank = 0.0
	assert_ne(d.probe_error(s, "spark"), "", "без газа нельзя")
	assert_ne(d.probe(s, "spark"), "")
	assert_almost_eq(_cargo_kg(s), 2.0, 0.01, "образец вернулся в груз")
	assert_false("conductive" in w.known_tags_of(s))

func test_druse_gives_samples_without_cargo():
	var s := _sub(["crystalline", "magnetic"], "Кварц")
	var m := FakeMining.new()
	m.sub = s
	var c := Node3D.new()
	robot.add_child(c)
	c.position = Vector3(1.0, 0, 0)
	m.nodes = [c]
	var d := ProtoLabDesk.new(w, robot)
	d.mining = m
	var subj := d.subjects()
	assert_eq(subj.size(), 1)
	assert_eq(subj[0].where, "druse")
	assert_eq(d.probe_error(s, "magnet"), "")
	d.probe(s, "magnet")
	assert_true(w.is_identified(s), "касание + магнит опознали кварц")
	assert_true(robot.get_meta("cargo").is_empty(), "откол ушёл целиком на пробу")

func test_guess_then_check():
	var s := _sub(["acidic", "porous"])
	var d := _desk_with_cargo(s, 2.0)
	d.touch(s)
	assert_eq(d.toggle_guess(s, "acidic"), "")
	assert_true("acidic" in w.hypotheses_of(s))
	var k0 := w.robot.knowledge
	assert_eq(d.check_error(s, "acidic"), "")
	assert_eq(d.check(s, "acidic"), "")
	assert_true("acidic" in w.known_tags_of(s))
	assert_gt(w.robot.knowledge, k0, "верная догадка даёт знание")
	assert_almost_eq(_cargo_kg(s), 2.0 - Probes.SAMPLE_KG * 0.5, 0.01, "проверка вдвое дешевле пробы")

func test_analyzer_reveals_one_tag_and_recharges():
	var s := _sub(["toxic", "radioactive", "fibrous"])
	var d := _desk_with_cargo(s, 1.0)
	assert_eq(d.analyze_near(), "")
	assert_eq(w.known_tags_of(s).size(), 2, "касание (волокна) + один тег анализатора")
	assert_ne(d.analyze_near(), "", "перезарядка")
	d.tick(ProtoLabDesk.ANALYZER_CD + 0.1)
	assert_eq(d.analyze_near(), "")
	assert_true(w.is_identified(s))

func test_factory_lab_probes_passing_portion():
	var planet := w.planet
	var steel := w.db.add(Substance.new("st", "Сталь", ["metallic", "dense"]))
	var s := _sub(["magnetic", "conductive"])
	var n := ProtoPneumatics.new(planet)
	n.knowledge = w
	n.place("lab", Vector2i.ZERO, 0, steel)
	n.parts[Vector2i.ZERO].items.append(Portion.new(s, 3.0))
	var t := 0.0
	while t < ProtoPneumatics.LAB_DUR + 0.5:
		n.step(0.1)
		t += 0.1
	assert_true(w.is_identified(s), "лаборатория опознала материал")
	var cap = n.parts[Vector2i.ZERO].cap
	assert_not_null(cap, "остаток ждёт на выходе")
	assert_lt(cap.p.mass, 3.0, "пробы потратили образец")
	assert_true(n.events.any(func(e): return e.kind == "lab" and e.learned))

func test_factory_lab_without_knowledge_passes_through():
	var steel := w.db.add(Substance.new("st", "Сталь", ["metallic", "dense"]))
	var s := _sub(["magnetic"])
	var n := ProtoPneumatics.new(w.planet)
	n.place("lab", Vector2i.ZERO, 0, steel)
	n.parts[Vector2i.ZERO].items.append(Portion.new(s, 2.0))
	for i in 60:
		n.step(0.1)
	assert_almost_eq(n.parts[Vector2i.ZERO].cap.p.mass, 2.0, 0.001, "без знаний ничего не тратит")

func test_save_roundtrip():
	var s := _sub(["flammable", "sticky"])
	var d := _desk_with_cargo(s, 3.0)
	d.probe(s, "heat")
	d.toggle_guess(s, "toxic")
	var data := JSON.parse_string(JSON.stringify(d.save_dict()))
	var w2 := H.world()
	w2.db.add(Substance.new(s.id, s.root, s.tags))
	var d2 := ProtoLabDesk.new(w2)
	d2.load_dict(data)
	var s2: Substance = w2.db.get_sub(s.id)
	assert_eq(w2.known_tags_of(s2), w.known_tags_of(s))
	assert_eq(w2.excluded_of(s2), w.excluded_of(s))
	assert_eq(w2.hypotheses_of(s2), ["toxic"])
	assert_eq(w2.robot.knowledge, w.robot.knowledge)

func test_game_mode_uses_deposit_near_robot():
	var s := _sub(["alkaline", "porous"], "Мел")
	var c := w.robot_cell() + Vector2i(1, 0)
	w.planet.deposits[c] = {"sub": s.id, "amount": 50.0}
	var d := ProtoLabDesk.new(w)
	var subj := d.subjects(c)
	assert_eq(subj[0].sub, s)
	assert_eq(subj[0].where, "deposit")
	assert_eq(d.probe(s, "drop"), "")
	assert_true("alkaline" in w.known_tags_of(s))
	assert_almost_eq(float(w.planet.deposits[c].amount), 50.0 - Probes.SAMPLE_KG, 0.01, "образец — из залежи")

func test_panel_probe_button():
	var s := _sub(["flammable", "brittle", "toxic"])
	var d := _desk_with_cargo(s, 3.0)
	var panel := ProtoLabPanel.new()
	panel.setup(d, robot)
	add_child_autofree(panel)
	await wait_process_frames(1)
	assert_true(panel.touch_open())
	assert_true(robot.get_meta("ui_busy"), "робот стоит, пока открыта карточка")
	panel._refresh()
	var heat: Button = null
	for b in panel._card.find_children("*", "Button", true, false):
		if b.get_meta("key", "") == "probe:heat":
			heat = b
	assert_not_null(heat, "кнопка «Нагрев» есть")
	heat.pressed.emit()
	assert_true("flammable" in w.known_tags_of(s))
	panel.close()
	assert_false(robot.get_meta("ui_busy"))
