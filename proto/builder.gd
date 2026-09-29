class_name ProtoBuilder
extends Node
## Стройка пневмозавода роботом (в --play). Деталь ставится в клетку перед
## роботом, выходом туда, куда он смотрит (R — повернуть ещё).
##   B / Y на геймпаде      — стройка: каталог деталей (ProtoBuildMenu); в каталоге
##                            ещё раз — выйти из стройки
##   T / D-pad вправо-влево — деталь с быстрой панели (1–8 на клавиатуре)
##   R / RB                  — повернуть (перед роботом деталь — повернуть её)
##   M / LB                  — материал детали (из твёрдых материалов планеты)
##   Пробел / A              — поставить; держать и идти — труба тянется следом;
##                            перед роботом деталь — взять такую же в руки
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
## Стройка вне площадки: деталь встаёт на грунт своей клетки — посередине
## между самым низким и самым высоким местом клетки: с верхней стороны она
## врезана в склон, под нижней — фундамент. Перепад больше MAX_STEP — круто
## (у холма площадки обычный перепад в клетке 1–2 м).
const MAX_STEP := 2.5
const SNAP_DOWN := 0.3       # к соседней детали: ниже грунта не больше (врастает)
const SNAP_UP := 0.6         # ... и выше (на фундаменте) — трубы идут ровно

var view: ProtoPneumaticsView
var robot: Node3D
var terrain: ProtoTerrain = null   # null — всё на высоте площадки (кадры без рельефа)
var liquid_at := Callable()        # мир → {} или жидкость (ProtoHealth.liquid_at)
var _ground := {}                  # клетка → [время, ground()]: грунт не щупаем каждый кадр
var mats: Array = []          # Substance — из чего можно строить
var active := false
var kind_i := 0
var mat_i := 0
## Быстрая панель (как в Satisfactory): деталь из каталога встаёт в выбранную
## ячейку. slot — выбранная ячейка, kind_i — ORDER-индекс детали в руках.
const HOTBAR_N := 8
var hotbar: Array = ["pipe", "pump", "intake", "splitter", "crusher", "tank", "relief", "lamp"]
var slot := 0
var menu: ProtoBuildMenu = null
var _drag_last := Vector2i(-9999, -9999)  # последняя труба, протянутая удержанием «поставить»
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

func setup(v: ProtoPneumaticsView, r: Node3D, materials: Array, t: ProtoTerrain = null) -> void:
	view = v
	robot = r
	terrain = t
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
	menu = ProtoBuildMenu.new()
	menu.name = "build_menu"
	add_child(menu)
	menu.setup(self)

func kind() -> String:
	return ProtoPneumatics.ORDER[kind_i]

## Взять деталь в руки: есть на панели — выбрать ячейку, нет — положить в выбранную.
func choose(k: String) -> void:
	var i := ProtoPneumatics.ORDER.find(k)
	if i < 0:
		return
	kind_i = i
	var h := hotbar.find(k)
	if h >= 0:
		slot = h
	else:
		hotbar[slot] = k
	_drag_last = Vector2i(-9999, -9999)

func select_slot(i: int) -> void:
	slot = posmod(i, HOTBAR_N)
	kind_i = ProtoPneumatics.ORDER.find(hotbar[slot])

func next_material(step := 1) -> void:
	if not mats.is_empty():
		mat_i = posmod(mat_i + step, mats.size())

## Войти в стройку — сразу с каталогом; выйти — из каталога той же кнопкой.
func open_menu() -> void:
	active = true
	menu.show_menu()

func exit_build() -> void:
	active = false
	menu.hide_menu()

func material() -> Substance:
	return mats[mat_i] if not mats.is_empty() else World.starter_substance()

func cargo() -> Array:
	if not robot.has_meta("cargo"):
		robot.set_meta("cargo", [])
	return robot.get_meta("cargo")

## Клетка перед роботом и направление выхода (в системе завода: на шаре
## площадка повёрнута под роботом, см. ProtoPlanetStream).
func target() -> Array:
	var fwd := view.global_transform.basis.inverse() * robot.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var c := ProtoPneumatics.cell_at(view.origin, view.to_local(robot.global_position) + fwd * ProtoPneumatics.CELL * 1.1)
	return [c, (ProtoPneumatics.dir_of(fwd) + rot) % 4]

## Грунт клетки: {ok, lift, foot, why}. lift — подъём над площадкой (на ней 0),
## foot — высота фундамента до самого низкого места клетки.
func ground(c: Vector2i) -> Dictionary:
	var now := Time.get_ticks_msec() / 1000.0
	var hit: Array = _ground.get(c, [])
	if not hit.is_empty() and now - float(hit[0]) < 0.4:
		return hit[1]
	var g := _probe(c)
	_ground[c] = [now, g]
	return g

func _probe(c: Vector2i) -> Dictionary:
	if terrain == null:
		return {"ok": true, "lift": 0.0, "foot": 0.0, "why": ""}
	var ctr := ProtoPneumatics.cell_pos(view.origin, c)
	var lo := INF
	var hi := -INF
	for o in [Vector2(0, 0), Vector2(-0.8, -0.8), Vector2(0.8, -0.8), Vector2(-0.8, 0.8), Vector2(0.8, 0.8)]:
		var w := view.to_global(ctr + Vector3(o.x, 40.0, o.y))
		var y := view.to_local(Vector3(w.x, terrain.floor_at(w), w.z)).y
		lo = minf(lo, y)
		hi = maxf(hi, y)
	# На площадке lo == hi — ровно её высота (origin на 0.1 выше грунта).
	var lift := (lo + hi) / 2.0 + 0.1 - view.origin.y
	var best := INF
	for d in ProtoPneumatics.DIRS:
		if not view.net.parts.has(c + d):
			continue
		var ln := view.net.lift(c + d)
		if ln >= lift - SNAP_DOWN and ln <= lift + SNAP_UP and absf(ln - lift) < absf(best - lift):
			best = ln
	if best != INF:
		lift = best
	if absf(lift) < 0.12:
		lift = 0.0
	var g := {"ok": true, "lift": lift, "foot": view.origin.y + lift - lo, "why": ""}
	if hi - lo > MAX_STEP:
		g.ok = false
		g.why = "Слишком круто: нужно ровнее"
	elif liquid_at.is_valid() and not liquid_at.call(view.to_global(ctr + Vector3(0, lift + 0.3, 0))).is_empty():
		g.ok = false
		g.why = "Здесь жидкость"
	return g

func _process(dt: float) -> void:
	_note_t = maxf(0.0, _note_t - dt)
	if menu != null and menu.open:
		view.ghost("", Vector2i.ZERO, 0, material(), true)
		_hud()
		return                                 # каталог сам слушает кнопки
	if robot != null and (bool(robot.get_meta("map_open", false)) or bool(robot.get_meta("ui_busy", false))):
		return                                 # открыта карта или карточка материала: кнопки — их
	if menu != null and Engine.get_process_frames() - menu.closed_frame <= 1:
		_hud()
		return                                 # кнопка, закрывшая каталог, больше ничего не делает
	if Input.is_action_just_pressed(BUILD_MODE):
		open_menu()
		_hud()
		return
	if Input.is_action_just_pressed(UNLOAD):
		unload()
	if active:
		if Input.is_action_just_pressed(BUILD_NEXT): select_slot(slot + 1)
		if Input.is_action_just_pressed(BUILD_PREV): select_slot(slot - 1)
		if Input.is_action_just_pressed(BUILD_ROTATE): rotate_or_turn()
		if Input.is_action_just_pressed(BUILD_MATERIAL): next_material()
		if Input.is_action_just_pressed(BUILD_PLACE):
			if not view.net.can_place(target()[0]):
				pipette()
			elif place():
				_drag_last = target()[0]
		elif Input.is_action_pressed(BUILD_PLACE):
			_drag()
		else:
			_drag_last = Vector2i(-9999, -9999)
		if Input.is_action_just_pressed(BUILD_REMOVE): dismantle()
	var t := target()
	var g := ground(t[0]) if active else {"ok": true, "lift": 0.0}
	view.ghost(kind() if active else "", t[0], t[1], material(), view.net.can_place(t[0]) and g.ok, g.lift)
	_hud()

func place() -> bool:
	var t := target()
	if not view.net.can_place(t[0]):
		_say("Клетка занята")
		return false
	var g := ground(t[0])
	if not g.ok:
		_say(g.why)
		return false
	var part := view.net.place(kind(), t[0], t[1], material())
	part.lift = g.lift
	part.foot = g.foot
	_ground.clear()          # соседи теперь тянутся к высоте этой детали
	return true

## Держат «поставить» и идут с трубой в руках: труба тянется в соседнюю клетку,
## прошлая поворачивается к новой — так же сворачивает линия (как конвейер Factorio).
func _drag() -> void:
	if kind() != "pipe" or _drag_last.x == -9999:
		return
	var c: Vector2i = target()[0]
	var d := c - _drag_last
	var di := ProtoPneumatics.DIRS.find(d)
	if di < 0 or not view.net.can_place(c) or not ground(c).ok:
		return
	var last: Dictionary = view.net.parts.get(_drag_last, {})
	if last.is_empty():
		return
	if last.kind == "pipe":
		last.dir = di
	var g := ground(c)
	var part := view.net.place("pipe", c, di, material())
	part.lift = g.lift
	part.foot = g.foot
	_ground.clear()
	_drag_last = c

## Перед роботом деталь — взять в руки такую же (вид, материал, поворот), как пипетка.
func pipette() -> void:
	var part: Dictionary = view.net.parts.get(target()[0], {})
	if part.is_empty():
		return
	choose(part.kind)
	var mi := mats.find(part.sub)
	if mi >= 0:
		mat_i = mi
	var fwd := ProtoPneumatics.dir_of(view.global_transform.basis.inverse() * robot.global_transform.basis.z)
	rot = posmod(part.dir - fwd, 4)
	_say("В руках: %s" % ProtoPneumatics.KINDS[part.kind].n)

## R: перед роботом деталь — повернуть её, иначе — призрак.
func rotate_or_turn() -> void:
	var c: Vector2i = target()[0]
	if view.net.parts.has(c):
		view.net.rotate(c)
	else:
		rot = (rot + 1) % 4

## Что перед роботом: {name, status} или пусто.
func aim_info() -> Dictionary:
	if not active:
		return {}
	var part: Dictionary = view.net.parts.get(target()[0], {})
	if part.is_empty():
		return {}
	return {"name": ProtoPneumatics.KINDS[part.kind].n, "status": str(part.status), "sub": part.sub}

func dismantle() -> void:
	var t := target()
	var back := view.net.remove(t[0])
	cargo().append_array(back)
	_ground.clear()

## Весь груз робота — в ближайший приёмник в пределах UNLOAD_R.
func unload() -> bool:
	var best := Vector2i.ZERO
	var bd := INF
	for c in view.net.parts:
		if view.net.parts[c].kind != "intake":
			continue
		var d := view.to_global(view.net.at(view.origin, c)).distance_to(robot.global_position)
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
		var g := ground(target()[0])
		if not g.ok:
			lines.append(g.why)
	else:
		lines.append("B/Y — стройка")
	lines.append("Груз: %.1f кг · C/X — выгрузить в приёмник" % m)
	if _note_t > 0.0:
		lines.append(note)
	hud.text = "\n".join(lines)

## Цифры 1–8 — ячейки быстрой панели (только клавиатура, только в стройке).
func _unhandled_input(e: InputEvent) -> void:
	if not active or (menu != null and menu.open) or not (e is InputEventKey) or not e.pressed or e.echo:
		return
	var k: int = e.physical_keycode
	if k >= KEY_1 and k <= KEY_8:
		select_slot(k - KEY_1)
		get_viewport().set_input_as_handled()

static func _key(code: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = code
	return e

static func _button(b: JoyButton) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.device = -1
	e.button_index = b
	return e
