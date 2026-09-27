extends GutTest
## Обучение первых минут в 3D: кнопки из InputMap, шаги по состоянию сцены,
## пропуск и запоминание в настройках.

class FakeNet:
	var parts := {}

class FakeBuilder:
	extends Node
	var unloaded_kg := 0.0
	var active := false

class FakeRoot:
	extends Node3D
	var robot: Node3D
	var pneu = null
	var pneu_view = null
	var mining = null
	var lab_panel = null
	var terrain = null

var _settings := ""

func before_all():
	ProtoControls.ensure()
	ProtoBuilder.ensure_actions()
	ProtoLabPanel.ensure_actions()
	ProtoTutorial.ensure_actions()

func before_each():
	_settings = ProtoTutorial.SETTINGS
	ProtoTutorial.SETTINGS = "user://test_settings3d.json"
	DirAccess.remove_absolute(ProtoTutorial.SETTINGS)

func after_each():
	DirAccess.remove_absolute(ProtoTutorial.SETTINGS)
	ProtoTutorial.SETTINGS = _settings

func _root(with_factory := true) -> FakeRoot:
	var r := FakeRoot.new()
	r.robot = Node3D.new()
	r.add_child(r.robot)
	if with_factory:
		r.pneu = FakeNet.new()
		r.pneu.parts[Vector2i(0, 0)] = {"kind": "pump"}
		var b := FakeBuilder.new()
		b.name = "builder"
		r.add_child(b)
	add_child_autofree(r)          # global_position — только в дереве
	return r

func _tut(r: Node, from := 0) -> ProtoTutorial:
	var t := ProtoTutorial.new()
	t.setup(r, null, from)
	t._begin()
	autofree(t)
	return t

## Прогнать кадры, пока шаг не сменится (пауза «Готово» — DONE_PAUSE).
func _run(t: ProtoTutorial) -> void:
	for i in 10:
		if t.advance(0.5):
			return

func test_text_reads_bindings_from_inputmap():
	var txt := ProtoTutorial.step_text(2, false, false)
	assert_string_contains(txt, "[F]", "бур — F на клавиатуре")
	assert_string_contains(ProtoTutorial.step_text(2, true, false), "[RT]", "на геймпаде — правый курок")
	# Переназначили бур — подсказка следует за InputMap.
	var old := InputMap.action_get_events(ProtoControls.WORK)
	InputMap.action_erase_events(ProtoControls.WORK)
	InputMap.action_add_event(ProtoControls.WORK, ProtoControls._key(KEY_K))
	assert_string_contains(ProtoTutorial.step_text(2, false, false), "[K]")
	InputMap.action_erase_events(ProtoControls.WORK)
	for e in old:
		InputMap.action_add_event(ProtoControls.WORK, e)

func test_missing_key_is_dropped_not_shown_empty():
	# build_prev есть только на геймпаде: на клавиатуре его в тексте нет.
	var kb := ProtoTutorial.step_text(5, false, false)
	assert_false(kb.contains("[]") or kb.contains("  "), kb)
	assert_string_contains(ProtoTutorial.step_text(5, true, false), "[←]")

func test_rich_text_has_pad_colors():
	assert_string_contains(ProtoTutorial.step_text(3, true), "[bgcolor=#")

func test_steps_advance_by_scene_state():
	var r := _root()
	var t := _tut(r, 1)
	assert_eq(ProtoTutorial.STEPS[t.step].id, "walk")
	_run(t)
	assert_eq(t.step, 1, "пока робот стоит, шаг не выполнен")
	r.robot.position = Vector3(10, 0, 0)
	_run(t)
	# Без пещеры и карточки бур и касание пропускаются — сразу выгрузка.
	assert_eq(ProtoTutorial.STEPS[t.step].id, "unload")
	(r.get_node("builder") as FakeBuilder).unloaded_kg = 3.0
	_run(t)
	assert_eq(ProtoTutorial.STEPS[t.step].id, "pump")
	r.pneu.parts[Vector2i(1, 0)] = {"kind": "pump"}
	_run(t)
	assert_eq(ProtoTutorial.STEPS[t.step].id, "pipe")
	assert_eq(ProtoTutorial.saved_step(), t.step, "прогресс записан")

func test_no_factory_skips_build_steps():
	var r := _root(false)
	var t := _tut(r, 1)
	r.robot.position = Vector3(10, 0, 0)
	_run(t)
	assert_eq(ProtoTutorial.STEPS[t.step].id, "goal")

func test_finishing_and_closing_are_remembered():
	var t := _tut(_root(), ProtoTutorial.STEPS.size() - 1)
	for i in 30:
		t.advance(0.5)
	assert_true(t.done and t.finished)
	assert_true(ProtoTutorial.is_done())
	ProtoTutorial.reset()
	assert_false(ProtoTutorial.is_done())
	var t2 := _tut(_root(), 0)
	t2.close()
	assert_true(ProtoTutorial.is_done() and not t2.finished)

func test_settings_keep_other_keys():
	var f := FileAccess.open(ProtoTutorial.SETTINGS, FileAccess.WRITE)
	f.store_string(JSON.stringify({"volume": 0.5, "tutorial_done": true}))
	f = null
	ProtoTutorial.save_settings({"tutorial3d_step": 3})
	var d := ProtoTutorial.settings()
	assert_eq(d.get("volume"), 0.5)
	assert_true(d.get("tutorial_done"))
	assert_eq(ProtoTutorial.saved_step(), 3)

func test_direction_word():
	var fwd := Vector3(0, 0, -1)
	assert_eq(ProtoTutorial.direction_word(fwd, Vector3(0, 0, -5)), "впереди")
	assert_eq(ProtoTutorial.direction_word(fwd, Vector3(5, 0, 0)), "справа")
	assert_eq(ProtoTutorial.direction_word(fwd, Vector3(0, 0, 5)), "сзади")
	assert_eq(ProtoTutorial.direction_word(fwd, Vector3(-5, 0, 0)), "слева")
