class_name ProtoSettings
extends RefCounted
## Настройки 3D-прототипа и сборки play3d: графика и звук (управление хранит
## сам ProtoControls).
## Хранятся в user://settings3d.cfg (ConfigFile), применяются при старте меню и
## сцены и сразу при изменении в экране настроек (ProtoSettingsPanel).
##   graphics: fullscreen, vsync, render_scale (0.5–1 — доля разрешения 3D),
##             shadows (тени солнца), show_fps (счётчик кадров в углу)
##   audio:    master, world (звуки мира — шина ProtoWorld), mute

static var PATH := "user://settings3d.cfg"   # тесты подменяют на свой файл

const DEFAULTS := {
	"graphics": {"fullscreen": false, "vsync": true, "render_scale": 1.0, "shadows": true, "show_fps": false},
	"audio": {"master": 1.0, "world": 1.0, "mute": false},
}
const SCALES := [0.5, 0.67, 0.75, 0.85, 1.0]
const WORLD_BUS := "ProtoWorld"

static var _values := {}
static var _loaded := false

## Значение настройки (с загрузкой файла при первом обращении).
static func get_value(section: String, key: String):
	_ensure_loaded()
	return _values.get(section, {}).get(key, default_of(section, key))

## Значение по умолчанию: сборка для Steam Deck по умолчанию во весь экран.
static func default_of(section: String, key: String):
	if section == "graphics" and key == "fullscreen":
		return OS.has_feature("steamdeck")
	return DEFAULTS[section][key]

## Записать, сохранить в файл и применить.
static func set_value(section: String, key: String, v) -> void:
	_ensure_loaded()
	if not _values.has(section):
		_values[section] = {}
	_values[section][key] = v
	save()
	apply()

static func reset() -> void:
	_values = _defaults()
	_loaded = true

static func _defaults() -> Dictionary:
	var d := DEFAULTS.duplicate(true)
	for section in d:
		for key in d[section]:
			d[section][key] = default_of(section, key)
	return d

static func load_file() -> void:
	_values = _defaults()
	_loaded = true
	var cf := ConfigFile.new()
	if cf.load(PATH) != OK:
		return
	for section in DEFAULTS:
		for key in DEFAULTS[section]:
			var d = default_of(section, key)
			var v = cf.get_value(section, key, d)
			# Битое значение другого типа — берём по умолчанию.
			if typeof(v) == typeof(d) or (d is float and v is int):
				_values[section][key] = float(v) if d is float else v

static func save() -> void:
	var cf := ConfigFile.new()
	for section in _values:
		for key in _values[section]:
			cf.set_value(section, key, _values[section][key])
	cf.save(PATH)

static func _ensure_loaded() -> void:
	if not _loaded:
		load_file()

# ---------------------------------------------------------------- применение

## Применить всё, что не зависит от сцены: окно, звук, масштаб 3D, счётчик кадров.
static func apply() -> void:
	_ensure_loaded()
	var tree := Engine.get_main_loop() as SceneTree
	if DisplayServer.get_name() != "headless":
		var fs: bool = get_value("graphics", "fullscreen")
		var mode := DisplayServer.window_get_mode()
		var is_fs := mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
		if fs != is_fs:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if fs else DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if get_value("graphics", "vsync") else DisplayServer.VSYNC_DISABLED)
	if tree != null and tree.root != null:
		tree.root.scaling_3d_scale = clampf(get_value("graphics", "render_scale"), 0.25, 1.0)
	_apply_audio()
	if tree != null and tree.root != null:
		_fps_counter(tree.root, get_value("graphics", "show_fps"))
	if tree != null and tree.current_scene != null:
		apply_scene(tree.current_scene)

## Тени солнца в сцене (все DirectionalLight3D под root).
static func apply_scene(root: Node) -> void:
	var sh: bool = get_value("graphics", "shadows")
	for n in root.find_children("*", "DirectionalLight3D", true, false):
		(n as DirectionalLight3D).shadow_enabled = sh

static func _apply_audio() -> void:
	var mute: bool = get_value("audio", "mute")
	AudioServer.set_bus_mute(0, mute)
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(get_value("audio", "master"), 0.0001)))
	var i := AudioServer.get_bus_index(WORLD_BUS)
	if i >= 0:
		AudioServer.set_bus_volume_db(i, linear_to_db(maxf(get_value("audio", "world"), 0.0001)))

## Счётчик кадров в правом верхнем углу; живёт в корне дерева и переживает
## смену сцен (меню → игра).
static func _fps_counter(root: Window, on: bool) -> void:
	var layer := root.get_node_or_null("fps3d")
	if not on:
		if layer != null:
			layer.queue_free()
		return
	if layer != null:
		return
	layer = CanvasLayer.new()
	layer.name = "fps3d"
	layer.layer = 50
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	var l := Label.new()
	l.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	l.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	l.offset_right = -12
	l.offset_top = 6
	l.add_theme_font_size_override("font_size", 18)
	l.add_theme_color_override("font_color", Color(0.6, 1.0, 0.6))
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 5)
	layer.add_child(l)
	var tm := Timer.new()
	tm.wait_time = 0.5
	tm.autostart = true
	tm.timeout.connect(func(): l.text = "%d FPS" % Engine.get_frames_per_second())
	layer.add_child(tm)
	root.add_child.call_deferred(layer)
