class_name ProtoBuilder
extends Node
## Стройка пневмозавода роботом (в --play). Деталь ставится в клетку перед
## роботом, выходом туда, куда он смотрит (R — повернуть ещё).
##   B / Y на геймпаде      — режим стройки вкл/выкл
##   T / D-pad вправо-влево — выбрать деталь (Tab занят сменой планеты)
##   R / RB                  — повернуть
##   M / LB                  — материал детали (из твёрдых материалов планеты)
##   Пробел / A              — поставить
##   X / B на геймпаде       — разобрать (груз из детали — роботу)
##   C / X на геймпаде       — выгрузить груз робота в приёмник рядом (и вне стройки)
## Груз робота — метаданные "cargo" на узле робота: Array[Portion]. Бур кладёт
## добытое туда же, приёмник забирает отсюда.
## Действия регистрируются кодом, как в ProtoControls, без правки project.godot.

const BUILD_MODE := &"build_mode"
const BUILD_NEXT := &"build_next"
const BUILD_PREV := &"build_prev"
const BUILD_ROTATE := &"build_rotate"
const BUILD_MATERIAL := &"build_material"
const BUILD_PLACE := &"build_place"
const BUILD_REMOVE := &"build_remove"
const UNLOAD := &"cargo_unload"
const UNLOAD_R := 3.5

var view: ProtoPneumaticsView
var robot: Node3D
var mats: Array = []          # Substance — из чего можно строить
var active := false
var kind_i := 0
var mat_i := 0
var rot := 0
var hud: Label
var note := ""
var unloaded_kg := 0.0       # всего выгружено в приёмники (обучение проверяет по нему)
var _note_t := 0.0

## Раскладка стройки по умолчанию: действие → события.
static func layout() -> Dictionary:
	return {
		BUILD_MODE: [_key(KEY_B), _button(JOY_BUTTON_Y)],
		BUILD_NEXT: [_key(KEY_T), _button(JOY_BUTTON_DPAD_RIGHT)],
		BUILD_PREV: [_button(JOY_BUTTON_DPAD_LEFT)],
		BUILD_ROTATE: [_key(KEY_R), _button(JOY_BUTTON_RIGHT_SHOULDER)],
		BUILD_MATERIAL: [_key(KEY_M), _button(JOY_BUTTON_LEFT_SHOULDER)],
		BUILD_PLACE: [_key(KEY_SPACE), _button(JOY_BUTTON_A)],
		BUILD_REMOVE: [_key(KEY_X), _button(JOY_BUTTON_B)],
		UNLOAD: [_key(KEY_C), _button(JOY_BUTTON_X)],
	}

static func ensure_actions() -> void:
	var lay := layout()
	for a in lay:
		if InputMap.has_action(a):
			continue
		InputMap.add_action(a, 0.5)
		for e in lay[a]:
			InputMap.action_add_event(a, e)

func setup(v: ProtoPneumaticsView, r: Node3D, materials: Array) -> void:
	view = v
	robot = r
	# Прочнее — первым: насос и трубы из него держат больше давления.
	mats = materials.duplicate()
	mats.sort_custom(func(a, b): return ComponentStats.compute("pipe", a).max_p > ComponentStats.compute("pipe", b).max_p)
	ensure_actions()
	var layer := CanvasLayer.new()
	add_child(layer)
	hud = Label.new()
	hud.anchor_top = 1.0
	hud.anchor_bottom = 1.0
	hud.offset_left = 20
	hud.offset_top = -130
	hud.grow_vertical = Control.GROW_DIRECTION_BEGIN
	hud.add_theme_font_size_override("font_size", 20)
	hud.add_theme_color_override("font_outline_color", Color.BLACK)
	hud.add_theme_constant_override("outline_size", 6)
	layer.add_child(hud)

func kind() -> String:
	return ProtoPneumatics.ORDER[kind_i]

func material() -> Substance:
	return mats[mat_i] if not mats.is_empty() else World.starter_substance()

func cargo() -> Array:
	if not robot.has_meta("cargo"):
		robot.set_meta("cargo", [])
	return robot.get_meta("cargo")

## Клетка перед роботом и направление выхода.
func target() -> Array:
	var fwd := robot.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var c := ProtoPneumatics.cell_at(view.origin, robot.global_position + fwd * ProtoPneumatics.CELL * 1.1)
	return [c, (ProtoPneumatics.dir_of(fwd) + rot) % 4]

func _process(dt: float) -> void:
	_note_t = maxf(0.0, _note_t - dt)
	if robot != null and bool(robot.get_meta("map_open", false)):
		return                                 # открыта карта (ProtoMapView): кнопки — её
	if Input.is_action_just_pressed(BUILD_MODE):
		active = not active
	if Input.is_action_just_pressed(UNLOAD):
		unload()
	if active:
		var n := ProtoPneumatics.ORDER.size()
		if Input.is_action_just_pressed(BUILD_NEXT): kind_i = (kind_i + 1) % n
		if Input.is_action_just_pressed(BUILD_PREV): kind_i = (kind_i + n - 1) % n
		if Input.is_action_just_pressed(BUILD_ROTATE): rot = (rot + 1) % 4
		if Input.is_action_just_pressed(BUILD_MATERIAL) and not mats.is_empty(): mat_i = (mat_i + 1) % mats.size()
		if Input.is_action_just_pressed(BUILD_PLACE): place()
		if Input.is_action_just_pressed(BUILD_REMOVE): dismantle()
	var t := target()
	view.ghost(kind() if active else "", t[0], t[1], material(), view.net.can_place(t[0]))
	_hud()

func place() -> bool:
	var t := target()
	if not view.net.can_place(t[0]):
		_say("Клетка занята")
		return false
	view.net.place(kind(), t[0], t[1], material())
	return true

func dismantle() -> void:
	var t := target()
	var back := view.net.remove(t[0])
	cargo().append_array(back)

## Весь груз робота — в ближайший приёмник в пределах UNLOAD_R.
func unload() -> bool:
	var best := Vector2i.ZERO
	var bd := INF
	for c in view.net.parts:
		if view.net.parts[c].kind != "intake":
			continue
		var d := ProtoPneumatics.cell_pos(view.origin, c).distance_to(robot.global_position)
		if d < bd:
			bd = d
			best = c
	if bd > UNLOAD_R:
		_say("Рядом нет приёмника")
		return false
	var cg := cargo()
	if cg.is_empty():
		_say("Груза нет: добудьте буром")
		return false
	var m := 0.0
	for p in cg:
		m += p.mass
		view.net.feed(best, p)
	cg.clear()
	unloaded_kg += m
	_say("Выгружено %.1f кг" % m)
	return true

func _say(s: String) -> void:
	note = s
	_note_t = 2.5

func _hud() -> void:
	var lines: Array = []
	var m := 0.0
	for p in cargo():
		m += p.mass
	if active:
		var sub := material()
		var st := ComponentStats.compute(ProtoPneumatics.KINDS[kind()].stat, sub)
		lines.append("СТРОЙКА: %s  из «%s» (предел %.1f атм)" % [ProtoPneumatics.KINDS[kind()].n, sub.name, st.max_p])
		lines.append("T/D-pad — деталь · R/RB — повернуть · M/LB — материал · Пробел/A — поставить · X/B — разобрать")
	else:
		lines.append("B/Y — стройка")
	lines.append("Груз: %.1f кг · C/X — выгрузить в приёмник" % m)
	if _note_t > 0.0:
		lines.append(note)
	hud.text = "\n".join(lines)

static func _key(code: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = code
	return e

static func _button(b: JoyButton) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.device = -1
	e.button_index = b
	return e
