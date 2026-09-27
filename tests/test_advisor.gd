extends GutTest
## Совет «что дальше»: диагностика простоев и шаг к этапу без раскрытия скрытых тегов.

var H := TestHelpers

func _stage(w: World, st: Dictionary) -> void:
	w.planet.goal = {"id": "t", "n": "Тест", "stages": [st, st, st]}
	w.goals.stage = 0

func test_start_points_to_nearest_deposit_for_drill_stage():
	var w := H.world()
	_stage(w, {"type": "build_count", "kind": "drill", "n": 4, "desc": "Поставить 4 бура"})
	w.planet.deposits[Vector2i(24, 20)] = {"sub": w.starter.id, "amount": 50.0}
	w.planet.deposits[Vector2i(35, 35)] = {"sub": w.starter.id, "amount": 50.0}
	var a := Advisor.advise(w)
	assert_true(a.text.contains("бур"), a.text)
	assert_eq(a.cell, Vector2i(24, 20), "показывает ближайшую залежь")

func test_drill_without_output_is_diagnosed():
	var w := H.world()
	var c := Vector2i(12, 12)
	w.planet.deposits[c] = {"sub": w.starter.id, "amount": 50.0}
	w.place("drill", c, 0, w.starter, true)
	H.run(w, 20.0)
	var a := Advisor.advise(w)
	assert_true(a.text.contains("некуда отдавать"), a.text)
	assert_eq(a.cell, c + Vector2i(1, 0), "показывает клетку выхода")

func test_full_container_is_diagnosed():
	var w := H.world()
	var c := Vector2i(12, 12)
	w.planet.deposits[c] = {"sub": w.starter.id, "amount": 500.0}
	w.place("drill", c, 0, w.starter, true)
	var box := w.place("container", c + Vector2i(1, 0), 0, w.starter, true)
	box.store(Portion.new(w.starter, box.capacity() - 0.5))
	H.run(w, 20.0)
	assert_true(Advisor.advise(w).text.contains("полон"))

func test_low_pressure_without_pump_asks_for_pump():
	var w := H.world()
	var d := w.db.add(Substance.new("d", "Д", ["porous"]))
	w.robot.unlocked["compressor"] = true
	var comp := w.place("compressor", Vector2i(12, 12), 0, w.starter, true)
	comp.store(Portion.new(d, 2.0))
	H.run(w, 1.0)
	assert_true(Advisor.advise(w).text.contains("насос"), Advisor.advise(w).text)
	w.place("pump", Vector2i(12, 13), 0, w.starter, true)
	H.run(w, 0.5)
	assert_false(Advisor.diagnose(w).get("text", "").contains("насос вплотную"), "насос уже стоит — не просим ещё")

func test_cannon_without_target():
	var w := H.world()
	var gun := w.place("cannon", Vector2i(12, 12), 0, w.starter, true)
	w.place("pump", Vector2i(12, 13), 0, w.starter, true)
	gun.store(Portion.new(w.starter, 2.0))
	H.run(w, 1.0)
	assert_true(Advisor.advise(w).text.contains("L"), Advisor.advise(w).text)

func test_stockpile_does_not_reveal_hidden_tag():
	var w := H.world()
	var s := w.db.add(Substance.new("cond", "Проводник", ["conductive", "brittle"]))
	w.planet.materials.append(s)
	w.planet.deposits[Vector2i(25, 25)] = {"sub": s.id, "amount": 50.0}
	_stage(w, {"type": "stockpile_tags", "tags": {"conductive": 10.0}, "desc": "Запасти проводящее"})
	var a := Advisor.advise(w)
	assert_false(a.text.contains("Проводник"), "незнакомый материал не называется: " + a.text)
	assert_true(a.text.contains("Ток"), "подсказывает пробу, которая различает тег: " + a.text)
	# Образец в руках — материал знаком, но тег ещё не проверен.
	w.robot.add_item(Portion.new(s, 2.0))
	a = Advisor.advise(w)
	assert_true(a.text.contains("Проводник") and a.text.contains("Ток"), a.text)
	# Тег узнан — совет ведёт к залежи.
	w.robot.sub_known[s.id] = {"conductive": true}
	a = Advisor.advise(w)
	assert_true(a.text.contains("есть у Проводник"), a.text)
	assert_eq(a.cell, Vector2i(25, 25))

func test_makers_of_names_machine_and_condition():
	var w := H.world()
	var t := Advisor.makers_of(w, "crystalline")
	assert_true(t.contains("Компрессор"), t)
	assert_true(t.contains("6 атм"), t)

func test_launch_steps():
	var w := H.world()
	_stage(w, {"type": "launch_mass", "mass": 20.0, "desc": "На орбиту 20 кг"})
	assert_true(Advisor.advise(w).text.contains("пусковую шахту"))
	var silo := w.place("launch_silo", Vector2i(12, 12), 0, w.starter, true)
	assert_true(Advisor.advise(w).text.contains("пуста"))
	silo.store(Portion.new(w.starter, 5.0))
	assert_true(Advisor.advise(w).text.contains("атм"))
