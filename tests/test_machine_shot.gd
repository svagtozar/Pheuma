extends GutTest
## Выстрел выхода: машины отдают груз выстрелом в цель — цепочку можно разнести.

var H := TestHelpers

func _crusher_line(w: World) -> Dictionary:
	var ore := w.db.add(Substance.new("ore", "Руда", ["brittle", "crystalline"]))
	var cr := w.place("crusher", Vector2i(10, 10), 0, w.starter, true)
	var box := w.place("container", Vector2i(14, 10), 0, w.starter, true)
	cr.store(Portion.new(ore, 4.0))
	return {"cr": cr, "box": box, "ore": ore}

func test_crusher_shoots_output_into_far_container():
	var w := H.world()
	var d := _crusher_line(w)
	w.place("pump", Vector2i(10, 11), 0, w.starter, true)
	assert_eq(w.link_output(d.cr.cell, d.box.cell), "")
	H.run(w, 30.0)
	var porous := 0.0
	for p in d.box.items:
		if p.has("porous"):
			porous += p.mass
	assert_gt(porous, 3.0, "раздробленное долетело до контейнера в 4 клетках")
	assert_gt(w.stats.hits, 0)

func test_shot_waits_without_pressure():
	var w := H.world()
	var d := _crusher_line(w)
	w.link_output(d.cr.cell, d.box.cell)
	H.run(w, 10.0)
	assert_true(d.box.items.is_empty(), "без газа рядом не стреляет")
	assert_true(d.cr.status.contains("мало давления"), d.cr.status)
	assert_true(Advisor.advise(w).text.contains("насос") or Advisor.advise(w).text.contains("труб"), Advisor.advise(w).text)

func test_relink_same_target_unlinks():
	var w := H.world()
	var d := _crusher_line(w)
	w.link_output(d.cr.cell, d.box.cell)
	assert_eq(d.cr.shot_target(0), d.box.id)
	w.link_output(d.cr.cell, d.box.cell)
	assert_eq(d.cr.shot_target(0), -1, "повторная связь снимает выстрел")

func test_removing_target_drops_link():
	var w := H.world()
	var d := _crusher_line(w)
	w.link_output(d.cr.cell, d.box.cell)
	w.remove_at(d.box.cell, false)
	assert_eq(d.cr.shot_target(0), -1)

func test_out_of_range_waits_for_pressure():
	var w := H.world()
	var ore := w.db.add(Substance.new("ore", "Руда", ["brittle"]))
	var cr := w.place("crusher", Vector2i(2, 2), 0, w.starter, true)
	var far := w.place("container", Vector2i(37, 37), 0, w.starter, true)
	w.place("pump", Vector2i(2, 3), 0, w.starter, true)
	cr.store(Portion.new(ore, 2.0))
	w.link_output(cr.cell, far.cell)
	H.run(w, 30.0)
	assert_true(far.items.is_empty(), "до цели не долетит")
	assert_true(w.ground.is_empty(), "и не стреляет впустую — ждёт давления")
	assert_true(cr.status.contains("чтобы долететь"), cr.status)

func test_split_chain_keeps_separate_pressure():
	var w := H.world()
	w.robot.unlocked["compressor"] = true
	var d := w.db.add(Substance.new("d", "Д", ["dense"]))
	var weak := w.db.add(Substance.new("weak", "Слабый", ["porous"]))
	weak.hardness = 3.0
	# Слабая машина (предел ~ниже 6 атм) выше по цепочке, компрессор отдельно через пустую клетку.
	var cr := w.place("crusher", Vector2i(10, 10), 0, weak, true)
	var comp := w.place("compressor", Vector2i(12, 10), 0, w.starter, true)
	var out := w.place("container", Vector2i(13, 10), 0, w.starter, true)
	var p1 := w.place("pump", Vector2i(10, 11), 0, w.starter, true)
	p1.config.target_p = 3.0
	for c in [Vector2i(12, 11), Vector2i(12, 9)]:
		var p := w.place("pump", c, 0, w.starter, true)
		p.config.target_p = 8.0
	assert_eq(w.link_output(cr.cell, comp.cell), "")
	cr.store(Portion.new(d, 4.0))
	H.run(w, 120.0)
	assert_true(w.machines.has(cr.id), "слабая дробилка цела")
	assert_lt(w.gas.pressure(cr.id) if w.gas.has_node(cr.id) else 0.0, 5.0)
	var cryst := 0.0
	for p in out.items:
		if p.has("crystalline"):
			cryst += p.mass
	assert_gt(cryst, 2.0, "компрессор на своей сети дожал до кристаллического")

func test_save_load_keeps_shot():
	var w := H.world()
	var d := _crusher_line(w)
	w.link_output(d.cr.cell, d.box.cell)
	var md = JSON.parse_string(JSON.stringify(SaveGame.machine_to(d.cr, w.gas)))
	var m2 := w.place("crusher", Vector2i(20, 20), 0, w.starter, true)
	SaveGame.machine_restore(w, m2, md, w.gas)
	assert_eq(m2.shot_target(0), d.box.id)

func test_macroblock_keeps_shot_link():
	var w := H.world()
	var d := _crusher_line(w)
	w.link_output(d.cr.cell, d.box.cell)
	var mb = JSON.parse_string(JSON.stringify(Macroblocks.capture(w, Rect2i(10, 10, 5, 1), "стрелок")))
	w.robot.add_item(Portion.new(w.starter, 200.0))
	assert_eq(Macroblocks.place(w, mb, Vector2i(20, 20), 1, w.starter), "")
	var cr2 = w.machine_at(Vector2i(20, 20))
	var box2 = w.machine_at(Vector2i(20, 24))
	assert_eq(cr2.kind, "crusher")
	assert_eq(cr2.shot_target(0), box2.id, "связь выхода переехала с блоком (с поворотом)")
	# Свёртка и разворот.
	var res := Macroblocks.collapse_region(w, Rect2i(20, 20, 1, 5), "стрелок")
	assert_eq(res.err, "")
	var inner_cr: Machine = res.macro.inner.machines_of("crusher")[0]
	var inner_box: Machine = res.macro.inner.machines_of("container")[0]
	assert_eq(inner_cr.shot_target(0), inner_box.id, "внутри блока связь сохранена")
	assert_eq(Macroblocks.unfold(w, res.macro), "")
	var cr3 = w.machine_at(Vector2i(20, 20))
	assert_eq(cr3.shot_target(0), w.machine_at(Vector2i(20, 24)).id, "после разворота — тоже")

func test_advisor_names_weak_link():
	var w := H.world()
	w.robot.unlocked["compressor"] = true
	var d := w.db.add(Substance.new("d", "Д", ["dense"]))
	var weak := w.db.add(Substance.new("weak", "Слабый", ["porous"]))
	weak.hardness = 3.0
	var cr := w.place("crusher", Vector2i(10, 10), 0, weak, true)
	var comp: Processor = w.place("compressor", Vector2i(11, 10), 0, w.starter, true)
	w.place("container", Vector2i(12, 10), 0, w.starter, true)
	var p := w.place("pump", Vector2i(11, 11), 0, weak, true)
	p.config.target_p = 5.0
	comp.store(Portion.new(d, 2.0))
	H.run(w, 60.0)
	assert_gt(comp.need_p, 0.0, "компрессор ждёт давления")
	var a := Advisor.advise(w)
	assert_true(a.text.contains("Разнесите") or a.text.contains("держит"), a.text)
