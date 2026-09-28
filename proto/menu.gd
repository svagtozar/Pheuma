class_name ProtoMainMenu
extends Control
## Главное меню сборки play3d (res://proto/menu.tscn — главная сцена фичи play3d):
##   Продолжить   — последняя сохранённая планета (ProtoSave, user://saves3d/last.json);
##   Новая планета — выбор сида с превью тегов, условий и цели; если у планеты есть
##                  сохранение — «Высадиться» продолжает его, «Начать заново» — с нуля;
##   Настройки    — ProtoSettingsPanel (управление, графика, звук);
##   Выход.
## Геймпад: D-pad / левый стик — выбор, A — нажать, B — назад, LB/RB — сид.
## Клавиатура и мышь тоже работают. Размеры — под Steam Deck (1280×800).
##   --menu --screenshot=путь.png [--page=picker|settings] [--seed=N] — кадр меню
## С --screenshot без --menu меню сразу пропускается в игру (кадр сцены, как раньше).

const SCENE := "res://proto/menu.tscn"
const GAME := "res://proto/preview.tscn"
const Preview := preload("res://proto/preview.gd")

## Открыть меню сразу на странице (например, выбор планеты из паузы).
static var start_page := ""
static var picker_seed := -1

var page := "main"
var seed_value := 14             # сид в выборе планеты
var last_seed := -1
var shot_path := ""
var _t := 0.0
var _ui: Control
var _backdrop: Backdrop
var _pages := {}
var _settings: ProtoSettingsPanel
var _info: VBoxContainer         # превью планеты в выборе
var _seed_label: Label
var _go: Button
var _restart: Button
var _planets := {}               # сид → Planet (генерация не бесплатная)

# ---------------------------------------------------------------- переходы

## Запустить планету: fresh — начать заново (сохранение перезапишется).
static func launch(tree: SceneTree, s: int, fresh := false) -> void:
	Preview.build_seed = s
	Preview.start_fresh = fresh
	Preview._booted = true
	Preview.from_menu = true
	tree.paused = false
	tree.change_scene_to_file(GAME)

## Из игры — в меню, сразу на выбор планеты (сид по умолчанию — новый случайный).
static func goto_picker(tree: SceneTree, s := -1) -> void:
	start_page = "picker"
	picker_seed = s
	goto_menu(tree)

## Сид ещё не посещённой планеты: случайный, а не «следующий по счёту» — иначе
## каждая игра проходит одну и ту же цепочку 14, 15, 16…
static func new_seed() -> int:
	for i in 50:
		var s := randi() % 100000
		if ProtoSave.read(s).is_empty():
			return s
	return randi() % 100000

static func goto_menu(tree: SceneTree) -> void:
	tree.paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	tree.change_scene_to_file(SCENE)

# ---------------------------------------------------------------- сцена

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var menu_shot := args.has("--menu")
	for a in args:
		if a.begins_with("--screenshot="): shot_path = a.substr(13)
		elif a.begins_with("--page="): start_page = a.substr(7)
		elif a.begins_with("--seed="): picker_seed = int(a.substr(7))
	if shot_path != "" and not menu_shot:
		# Кадр игры (проверка сборки в CI): меню не нужно.
		get_tree().change_scene_to_file.call_deferred(GAME)
		return
	ProtoSettings.apply()
	ProtoControls.ensure()
	ensure_ui_actions()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	last_seed = ProtoSave.last_seed()
	if last_seed >= 0 and ProtoSave.read(last_seed).is_empty():
		last_seed = -1
	seed_value = picker_seed if picker_seed >= 0 else (new_seed() if last_seed >= 0 else 14)
	_backdrop = Backdrop.new()
	_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_backdrop)
	var layer := CanvasLayer.new()
	add_child(layer)
	_ui = ProtoUi.root(layer)
	_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_main()
	_build_picker()
	_build_settings()
	var p := start_page if start_page in _pages else "main"
	start_page = ""
	picker_seed = -1
	show_page(p)
	_backdrop.planet = _planet(last_seed if last_seed >= 0 and p == "main" else seed_value)

## A на геймпаде — нажать, B — назад (во встроенных ui_accept/ui_cancel их нет).
static func ensure_ui_actions() -> void:
	for pair in [[&"ui_accept", JOY_BUTTON_A], [&"ui_cancel", JOY_BUTTON_B]]:
		var has := InputMap.action_get_events(pair[0]).any(func(e): return e is InputEventJoypadButton and e.button_index == pair[1])
		if not has:
			InputMap.action_add_event(pair[0], ProtoControls._button(pair[1]))

func show_page(p: String) -> void:
	page = p
	for k in _pages:
		_pages[k].visible = k == p
	if p == "picker":
		_refresh_picker()
	elif p == "main":
		_backdrop.planet = _planet(last_seed) if last_seed >= 0 else _planet(seed_value)
	_focus_default.call_deferred()

func _focus_default() -> void:
	match page:
		"settings": _settings.focus_first()
		"picker": _go.grab_focus()
		_:
			var f := ProtoUi.first_focusable(_pages.main)
			if f != null:
				f.grab_focus()

func _process(dt: float) -> void:
	_t += dt
	# Геймпаду нужен фокус: если он потерян (клик мимо) — вернуть.
	var f := get_viewport().gui_get_focus_owner()
	if f == null or not f.is_visible_in_tree():
		_focus_default()
	if shot_path != "" and _t > 1.0:
		get_viewport().get_texture().get_image().save_png(shot_path)
		print("Меню: скриншот ", shot_path)
		shot_path = ""
		get_tree().quit(0)

func _unhandled_input(e: InputEvent) -> void:
	if not e.is_pressed() or e.is_echo():
		return
	if page == "picker":
		if e.is_action_pressed(&"ui_cancel"):
			show_page("main")
			accept_event()
		elif (e is InputEventJoypadButton and e.button_index == JOY_BUTTON_LEFT_SHOULDER) or (e is InputEventKey and e.physical_keycode == KEY_Q):
			set_seed(seed_value - 1)
			accept_event()
		elif (e is InputEventJoypadButton and e.button_index == JOY_BUTTON_RIGHT_SHOULDER) or (e is InputEventKey and e.physical_keycode == KEY_E):
			set_seed(seed_value + 1)
			accept_event()
		elif e is InputEventJoypadButton and e.button_index == JOY_BUTTON_Y:
			_random()
			accept_event()

# ---------------------------------------------------------------- главная

func _build_main() -> void:
	var box := VBoxContainer.new()
	box.position = Vector2(96, 150)
	box.add_theme_constant_override("separation", 14)
	_ui.add_child(box)
	_pages.main = box
	var title := ProtoUi.label("PNEUMA", 84, ProtoUi.TEXT)
	title.add_theme_constant_override("outline_size", 0)
	box.add_child(title)
	box.add_child(ProtoUi.label("робот, пещеры и пневматика", ProtoUi.FONT, ProtoUi.DIM))
	var gap := Control.new()
	gap.custom_minimum_size.y = 30
	box.add_child(gap)
	var cont := ProtoUi.button("Продолжить", func(): launch(get_tree(), last_seed))
	cont.name = "continue"
	cont.custom_minimum_size.x = 440
	box.add_child(cont)
	if last_seed >= 0:
		var pl := _planet(last_seed)
		box.add_child(_sub_label("%s · сид %d%s" % [pl.name, last_seed, _saved_when(last_seed)]))
	else:
		cont.disabled = true
		cont.focus_mode = Control.FOCUS_NONE
		box.add_child(_sub_label("Сохранений пока нет"))
	for b in [["Новая планета", func(): show_page("picker")], ["Настройки", func(): show_page("settings")],
			["Выход", func(): get_tree().quit()]]:
		var btn := ProtoUi.button(b[0], b[1])
		btn.custom_minimum_size.x = 440
		box.add_child(btn)
	var hint := ProtoUi.label("A — выбрать  ·  стрелки или D-pad — пункт", ProtoUi.FONT_SMALL, ProtoUi.DIM)
	hint.position = Vector2(96, 740)
	_pages.main_hint = hint
	_ui.add_child(hint)

func _sub_label(t: String) -> Label:
	var l := ProtoUi.label(t, ProtoUi.FONT_SMALL, ProtoUi.DIM)
	l.custom_minimum_size.x = 440
	return l

## « · 5 мин назад» по времени последнего сохранения.
func _saved_when(s: int) -> String:
	var p := ProtoSave.DIR + "/last.json"
	var d = JSON.parse_string(FileAccess.get_file_as_string(p)) if FileAccess.file_exists(p) else null
	if typeof(d) != TYPE_DICTIONARY or int(d.get("seed", -1)) != s or not d.has("unix"):
		return ""
	return " · " + ago(Time.get_unix_time_from_system() - float(d.unix))

static func ago(sec: float) -> String:
	if sec < 90.0:
		return "только что"
	if sec < 3600.0:
		return "%d мин назад" % roundi(sec / 60.0)
	if sec < 86400.0 * 2.0:
		return "%d ч назад" % roundi(sec / 3600.0)
	return "%d дн назад" % roundi(sec / 86400.0)

# ---------------------------------------------------------------- выбор планеты

func _build_picker() -> void:
	var panel := PanelContainer.new()
	panel.position = Vector2(64, 56)
	panel.custom_minimum_size = Vector2(680, 688)
	_ui.add_child(panel)
	_pages.picker = panel
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	panel.add_child(v)
	v.add_child(ProtoUi.label("Новая планета", 36))
	var sr := HBoxContainer.new()
	sr.add_theme_constant_override("separation", 12)
	v.add_child(sr)
	var prev := ProtoUi.button("◀", func(): set_seed(seed_value - 1))
	prev.custom_minimum_size = Vector2(64, 50)
	sr.add_child(prev)
	_seed_label = ProtoUi.label("", ProtoUi.FONT)
	_seed_label.custom_minimum_size.x = 150
	_seed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_seed_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sr.add_child(_seed_label)
	var next := ProtoUi.button("▶", func(): set_seed(seed_value + 1))
	next.custom_minimum_size = Vector2(64, 50)
	sr.add_child(next)
	var rnd := ProtoUi.button("Случайная", _random)
	rnd.custom_minimum_size = Vector2(200, 50)
	sr.add_child(rnd)
	sr.add_child(_chip_hint("LB / RB, Y"))
	_info = VBoxContainer.new()
	_info.add_theme_constant_override("separation", 8)
	_info.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(_info)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	v.add_child(row)
	_go = ProtoUi.button("Высадиться", func(): launch(get_tree(), seed_value))
	_go.custom_minimum_size = Vector2(250, 56)
	row.add_child(_go)
	_restart = ProtoUi.button("Начать заново", func(): launch(get_tree(), seed_value, true))
	_restart.custom_minimum_size = Vector2(230, 56)
	row.add_child(_restart)
	var back := ProtoUi.button("Назад", func(): show_page("main"))
	back.custom_minimum_size = Vector2(150, 56)
	row.add_child(back)

func _chip_hint(t: String) -> Label:
	var l := ProtoUi.label(t, ProtoUi.FONT_SMALL, ProtoUi.DIM)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return l

func set_seed(s: int) -> void:
	seed_value = maxi(s, 0)
	_refresh_picker()

func _random() -> void:
	set_seed(new_seed())

func _refresh_picker() -> void:
	if _info == null:
		return
	var pl := _planet(seed_value)
	_backdrop.planet = pl
	_seed_label.text = "сид %d" % seed_value
	for c in _info.get_children():
		_info.remove_child(c)
		c.queue_free()
	var info := planet_info(pl)
	_info.add_child(ProtoUi.label(info.name, 32, ProtoUi.ACCENT))
	_info.add_child(ProtoUi.label(info.conditions, ProtoUi.FONT_BODY, ProtoUi.DIM))
	for t in info.tags:
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 12)
		var n := ProtoUi.label(t[0], ProtoUi.FONT_BODY)
		n.custom_minimum_size.x = 250
		h.add_child(n)
		var d := ProtoUi.label(t[1], ProtoUi.FONT_SMALL, ProtoUi.DIM)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.custom_minimum_size.x = 360
		h.add_child(d)
		_info.add_child(h)
	if info.goal != "":
		_info.add_child(ProtoUi.label("Цель: " + info.goal, ProtoUi.FONT_BODY))
	var saved := not ProtoSave.read(seed_value).is_empty()
	_info.add_child(ProtoUi.label("Есть сохранение — «Высадиться» продолжит его" if saved else "Здесь ещё не были",
		ProtoUi.FONT_SMALL, ProtoHud.OK if saved else ProtoUi.DIM))
	_go.text = "Продолжить" if saved else "Высадиться"
	_restart.visible = saved

## Что показать о планете до высадки: имя, условия, теги с описаниями, цель.
static func planet_info(pl: Planet) -> Dictionary:
	var tags: Array = []
	for t in pl.tags:
		tags.append([PlanetTags.display(t), str(PlanetTags.TAGS.get(t, {}).get("desc", ""))])
	return {
		"name": pl.name,
		"conditions": "%.0f °C · %.2f атм · %.1f g" % [pl.ambient_temp, pl.atm_pressure, pl.gravity],
		"tags": tags,
		"goal": str(pl.goal.get("n", "")),
	}

func _planet(s: int) -> Planet:
	if not _planets.has(s):
		_planets[s] = PlanetGen.generate(s)
	return _planets[s]

# ---------------------------------------------------------------- настройки

func _build_settings() -> void:
	_settings = ProtoSettingsPanel.new()
	_settings.position = Vector2(64, 56)
	_settings.custom_minimum_size = Vector2(900, 688)
	_settings.closed.connect(func(): show_page("main"))
	_ui.add_child(_settings)
	_pages.settings = _settings

# ---------------------------------------------------------------- фон

## Фон меню: звёзды и шар планеты в цветах её тегов (грунт, атмосфера).
class Backdrop extends Control:
	const SHADER := """
shader_type canvas_item;
uniform vec3 ground = vec3(0.4, 0.35, 0.3);
uniform vec3 air = vec3(0.45, 0.62, 0.9);
uniform float seed = 0.0;
uniform float atm = 1.0;
uniform float radius = 0.8;   // доля квадрата под сам шар, остальное — ореол

float hash(vec3 p) { return fract(sin(dot(p, vec3(12.9898, 78.233, 37.719)) + seed) * 43758.5453); }
float noise(vec3 p) {
	vec3 i = floor(p); vec3 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1,0,0)), f.x), mix(hash(i + vec3(0,1,0)), hash(i + vec3(1,1,0)), f.x), f.y),
		mix(mix(hash(i + vec3(0,0,1)), hash(i + vec3(1,0,1)), f.x), mix(hash(i + vec3(0,1,1)), hash(i + vec3(1,1,1)), f.x), f.y), f.z);
}
float fbm(vec3 p) { float v = 0.0; float a = 0.5; for (int k = 0; k < 5; k++) { v += a * noise(p); p *= 2.07; a *= 0.5; } return v; }

void fragment() {
	vec2 q = (UV * 2.0 - 1.0) / radius;
	float d = length(q);
	vec3 light = normalize(vec3(-0.6, -0.45, 0.65));
	if (d < 1.0) {
		vec3 n = vec3(q, sqrt(1.0 - d * d));
		// Вращение вокруг вертикальной оси.
		float a = TIME * 0.03;
		vec3 r = vec3(n.x * cos(a) + n.z * sin(a), n.y, -n.x * sin(a) + n.z * cos(a));
		float h = fbm(r * 2.6 + seed * 0.01);
		vec3 c = mix(ground * 0.55, ground * 1.35, smoothstep(0.35, 0.7, h));
		c = mix(c, vec3(0.9, 0.92, 0.95) * ground * 1.6, smoothstep(0.72, 0.8, h) * 0.5);
		float lit = clamp(dot(n, light), 0.0, 1.0);
		c *= 0.08 + 1.05 * lit;
		// Край шара светится атмосферой.
		c += air * pow(1.0 - n.z, 2.5) * 0.7 * atm * (0.3 + lit);
		COLOR = vec4(c, 1.0);
	} else {
		float g = (d - 1.0) / (1.0 / radius - 1.0);
		float side = clamp(dot(normalize(vec3(q, 0.0)), light) * 0.5 + 0.6, 0.0, 1.0);
		COLOR = vec4(air, pow(max(0.0, 1.0 - g), 3.0) * 0.55 * atm * side);
	}
}
"""
	var planet: Planet:
		set(p):
			planet = p
			_apply()
	var _stars: Array = []
	var _t := 0.0
	var _ball: ColorRect

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		var rng := RandomNumberGenerator.new()
		rng.seed = 7
		for i in 160:
			_stars.append([Vector2(rng.randf(), rng.randf()), rng.randf_range(0.6, 2.0), rng.randf()])
		_ball = ColorRect.new()
		_ball.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sh := Shader.new()
		sh.code = SHADER
		var m := ShaderMaterial.new()
		m.shader = sh
		_ball.material = m
		add_child(_ball)
		resized.connect(_layout)
		_layout()
		_apply()

	func _layout() -> void:
		var r := size.y * 0.42 / 0.8          # шар — 0.8 квадрата, остальное — ореол
		_ball.position = Vector2(size.x * 0.76, size.y * 0.56) - Vector2(r, r)
		_ball.size = Vector2(r, r) * 2.0

	func _apply() -> void:
		if _ball == null or planet == null:
			return
		var m := _ball.material as ShaderMaterial
		var g := ProtoSky.ground_color(planet)
		var a := sky_color(planet)
		m.set_shader_parameter("ground", Vector3(g.r, g.g, g.b))
		m.set_shader_parameter("air", Vector3(a.r, a.g, a.b))
		m.set_shader_parameter("seed", float(planet.seed_value % 1000))
		m.set_shader_parameter("atm", clampf(0.35 + planet.atm_pressure * 0.5, 0.2, 1.4))

	func _process(dt: float) -> void:
		_t += dt
		queue_redraw()

	func _draw() -> void:
		var s := size
		draw_rect(Rect2(Vector2.ZERO, s), Color(0.035, 0.04, 0.06))
		for k in 12:
			var y := s.y * k / 12.0
			draw_rect(Rect2(0, y, s.x, s.y / 12.0 + 1.0), Color(0.08, 0.1, 0.16, 0.05 * k))
		for st in _stars:
			var a: float = 0.35 + 0.35 * sin(_t * 0.8 + st[2] * 20.0)
			draw_circle(st[0] * s, st[1], Color(0.85, 0.9, 1.0, a))

	static func sky_color(p: Planet) -> Color:
		var c := Color(0.45, 0.62, 0.9)
		if p.has_tag("volcanic"): c = Color(0.95, 0.55, 0.35)
		if p.has_tag("frozen"): c = Color(0.7, 0.85, 1.0)
		if p.has_tag("toxic_atmosphere") or p.has_tag("fungal_biosphere"): c = c.lerp(Color(0.6, 0.8, 0.3), 0.5)
		if p.has_tag("thin_atmosphere"): c = Color(0.5, 0.5, 0.6)
		return c
