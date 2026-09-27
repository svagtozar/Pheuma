extends GutTest
## Главное меню 3D-прототипа, выбор планеты и настройки (графика, звук).

var _dir := ""
var _cfg := ""

func before_each():
	_dir = ProtoSave.DIR
	ProtoSave.DIR = "user://test_menu_saves3d"
	_cfg = ProtoSettings.PATH
	ProtoSettings.PATH = "user://test_settings3d.cfg"
	ProtoSettings.reset()

func after_each():
	if DirAccess.dir_exists_absolute(ProtoSave.DIR):
		for f in DirAccess.get_files_at(ProtoSave.DIR):
			DirAccess.remove_absolute(ProtoSave.DIR + "/" + f)
	ProtoSave.DIR = _dir
	DirAccess.remove_absolute(ProtoSettings.PATH)
	ProtoSettings.PATH = _cfg
	ProtoSettings.load_file()
	ProtoSettings.apply()

func test_settings_roundtrip():
	ProtoSettings.set_value("graphics", "render_scale", 0.75)
	ProtoSettings.set_value("audio", "mute", true)
	ProtoSettings.reset()
	assert_eq(ProtoSettings.get_value("graphics", "render_scale"), 1.0, "сброс — по умолчанию")
	ProtoSettings.load_file()
	assert_almost_eq(float(ProtoSettings.get_value("graphics", "render_scale")), 0.75, 0.001)
	assert_true(ProtoSettings.get_value("audio", "mute"))

func test_settings_apply_audio_and_scale():
	ProtoSettings.set_value("audio", "master", 0.5)
	assert_almost_eq(AudioServer.get_bus_volume_db(0), linear_to_db(0.5), 0.01)
	ProtoSettings.set_value("audio", "mute", true)
	assert_true(AudioServer.is_bus_mute(0))
	ProtoSettings.set_value("graphics", "render_scale", 0.6)
	assert_almost_eq(get_tree().root.scaling_3d_scale, 0.6, 0.001)

func test_bad_settings_file_falls_back_to_defaults():
	var cf := ConfigFile.new()
	cf.set_value("graphics", "shadows", "да")        # не bool
	cf.set_value("audio", "master", 1)               # int вместо float — годится
	cf.save(ProtoSettings.PATH)
	ProtoSettings.load_file()
	assert_true(ProtoSettings.get_value("graphics", "shadows"))
	assert_eq(typeof(ProtoSettings.get_value("audio", "master")), TYPE_FLOAT)

func test_shadows_setting_reaches_scene_lights():
	var root := Node3D.new()
	var sun := DirectionalLight3D.new()
	sun.shadow_enabled = true
	root.add_child(sun)
	ProtoSettings.set_value("graphics", "shadows", false)
	ProtoSettings.apply_scene(root)
	assert_false(sun.shadow_enabled)
	root.free()

func test_planet_info_lists_tags_conditions_and_goal():
	var pl := PlanetGen.generate(14)
	var info := ProtoMainMenu.planet_info(pl)
	assert_eq(info.name, pl.name)
	assert_eq(info.tags.size(), pl.tags.size())
	assert_ne(info.tags[0][1], "", "у тега есть описание")
	assert_string_contains(info.conditions, "°C")

func test_ago():
	assert_eq(ProtoMainMenu.ago(10), "только что")
	assert_eq(ProtoMainMenu.ago(600), "10 мин назад")
	assert_eq(ProtoMainMenu.ago(7200), "2 ч назад")

func test_menu_without_save_disables_continue():
	var m: ProtoMainMenu = load(ProtoMainMenu.SCENE).instantiate()
	add_child_autofree(m)
	await wait_process_frames(2)
	assert_eq(m.last_seed, -1)
	var cont := m.find_child("continue", true, false) as Button
	assert_true(cont.disabled)
	assert_eq(m.page, "main")

func test_menu_continue_and_picker_know_the_save():
	DirAccess.make_dir_recursive_absolute(ProtoSave.DIR)
	var f := FileAccess.open(ProtoSave.path_for(9), FileAccess.WRITE)
	f.store_string(JSON.stringify({"version": ProtoSave.VERSION, "seed": 9}))
	f.close()
	f = FileAccess.open(ProtoSave.DIR + "/last.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"seed": 9, "unix": Time.get_unix_time_from_system()}))
	f.close()
	ProtoMainMenu.start_page = "picker"
	ProtoMainMenu.picker_seed = 9
	var m: ProtoMainMenu = load(ProtoMainMenu.SCENE).instantiate()
	add_child_autofree(m)
	await wait_process_frames(2)
	assert_eq(m.last_seed, 9)
	assert_false((m.find_child("continue", true, false) as Button).disabled)
	assert_eq(m.page, "picker")
	assert_eq(m.seed_value, 9)
	assert_eq(m._go.text, "Продолжить", "у планеты есть сохранение")
	assert_true(m._restart.visible)
	m.set_seed(10)
	assert_eq(m._go.text, "Высадиться")
	assert_false(m._restart.visible)

func test_settings_panel_tabs():
	var p := ProtoSettingsPanel.new()
	add_child_autofree(p)
	await wait_process_frames(1)
	for i in ProtoSettingsPanel.TABS.size():
		p.show_tab(i)
		await wait_process_frames(1)
		assert_eq(p.tab, i)
		assert_not_null(ProtoUi.first_focusable(p), "есть что выбрать геймпадом")
	p.show_tab(3)
	assert_eq(p.tab, 0, "по кругу")

func test_binding_rows_have_keys_and_pad():
	ProtoControls.ensure()
	var rows := ProtoSettingsPanel.binding_rows()
	assert_gt(rows.size(), 3)
	for r in rows:
		assert_true(r[1] != "" or r[2] != "", r[0])
