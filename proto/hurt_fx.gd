class_name ProtoHurtFx
extends CanvasLayer
## Отклик на урон робота: красная (оранжевая, зелёная — по виду урона) кромка
## экрана, искры из корпуса, дрожь камеры, звук удара, шипение в лаве и кислоте,
## тревога на малой прочности; при поломке — дым и надпись. Одна и та же для
## прототипа (ProtoHealth) и F3-вида игры (WorldView3D, по падению World.robot.hp).
## bar = true — своя полоса прочности сверху по центру (в прототипе она в ProtoHud).

const COLORS := {"heat": Color(1.0, 0.42, 0.08), "cold": Color(0.45, 0.78, 1.0),
	"acid": Color(0.55, 0.92, 0.18), "toxic": Color(0.62, 0.8, 0.28),
	"radiation": Color(0.95, 0.95, 0.3), "impact": Color(1.0, 0.18, 0.12), "": Color(1.0, 0.2, 0.15)}

var cam: Camera3D                # дрожит при ударах (h_offset / v_offset)
var bar := false
var mute := false

var _edge: TextureRect
var _banner: Label
var _sub: Label
var _bar: Control
var _frac := 1.0
var _bar_text := ""
var _flash := 0.0
var _flash_col := Color.RED
var _steady := 0.0               # кромка от непрерывного урона
var _steady_col := Color.RED
var _shake := 0.0
var _banner_t := 0.0
var _crunch: AudioStreamPlayer
var _sizzle: AudioStreamPlayer
var _alarm: AudioStreamPlayer
var _alarm_t := 0.0
var _smoke: CPUParticles3D
var _t := 0.0

func _ready() -> void:
	layer = 4
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_edge = TextureRect.new()
	_edge.texture = _edge_texture()
	_edge.set_anchors_preset(Control.PRESET_FULL_RECT)
	_edge.stretch_mode = TextureRect.STRETCH_SCALE
	_edge.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_edge.modulate = Color(1, 0, 0, 0)
	root.add_child(_edge)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_child(box)
	_banner = _label(40, Color(1.0, 0.42, 0.36))
	_sub = _label(20, Color(0.93, 0.94, 0.95))
	box.add_child(_banner)
	box.add_child(_sub)
	if bar:
		_bar = Control.new()
		_bar.set_anchors_preset(Control.PRESET_CENTER_TOP)
		_bar.custom_minimum_size = Vector2(260, 22)
		_bar.offset_left = -130
		_bar.offset_right = 130
		_bar.offset_top = 8
		_bar.offset_bottom = 30
		_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_bar.draw.connect(_draw_bar)
		root.add_child(_bar)
	_crunch = _player(ProtoSound.to_wav(ProtoSound.crunch()), -4.0)
	_sizzle = _player(ProtoSound.to_wav(ProtoSound.sizzle_loop(), true), -80.0)
	_alarm = _player(ProtoSound.to_wav(ProtoSound.alarm()), -10.0)

func _label(size: int, col: Color) -> Label:
	var l := Label.new()
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 6)
	l.modulate.a = 0.0
	return l

func _player(s: AudioStream, db: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = s
	p.volume_db = db
	add_child(p)
	return p

## Кромка: прозрачная середина, к краям — цвет.
static func _edge_texture() -> GradientTexture2D:
	var g := GradientTexture2D.new()
	g.width = 256
	g.height = 160
	g.fill = GradientTexture2D.FILL_RADIAL
	g.fill_from = Vector2(0.5, 0.5)
	g.fill_to = Vector2(1.08, 0.5)
	var gr := Gradient.new()
	gr.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	gr.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 0.05), Color(1, 1, 1, 0.95)])
	g.gradient = gr
	return g

# ---------------------------------------------------------------- события

## Удар или порция непрерывного урона: вспышка, искры, дрожь, звук.
func hit(amount: float, kind: String, robot: Node3D) -> void:
	var k := clampf(amount / 25.0, 0.25, 1.0)
	_flash = maxf(_flash, 0.35 + 0.55 * k)
	_flash_col = COLORS.get(kind, COLORS[""])
	_shake = maxf(_shake, 0.06 + 0.25 * k if kind == "impact" else 0.03 * k)
	if robot != null:
		robot.add_child(sparks(kind, int(10 + 30 * k)))
	if not mute and (kind == "impact" or amount >= 6.0):
		_crunch.pitch_scale = randf_range(0.85, 1.1)
		_crunch.volume_db = linear_to_db(0.4 + 0.6 * k)
		_crunch.play()

## Постоянное: доля прочности, урон в секунду и его вид (кромка, шипение, тревога).
func set_state(frac: float, dps: float, kind: String, bar_text := "") -> void:
	_frac = clampf(frac, 0.0, 1.0)
	_bar_text = bar_text
	_steady = clampf(dps / 20.0, 0.0, 0.6) + (0.25 if _frac < 0.25 else 0.0)
	_steady_col = COLORS.get(kind, COLORS[""]) if dps > 0.3 else COLORS[""]
	var hiss := kind in ["heat", "acid"] and dps > 1.0
	if not mute:
		if hiss and not _sizzle.playing:
			_sizzle.play()
		_sizzle.volume_db = linear_to_db(clampf(dps / 25.0, 0.05, 0.8)) if hiss else -80.0
	if _bar:
		_bar.queue_redraw()

## Поломка: дым из корпуса, надпись.
func wreck(robot: Node3D, lost_kg: float) -> void:
	show_banner("КОРПУС РАЗРУШЕН", "Возврат на базу%s" % (" · груз потерян (%.1f кг)" % lost_kg if lost_kg > 0.05 else ""), 3.0)
	_flash = 0.8
	_flash_col = COLORS.impact
	_shake = 0.35
	if robot != null:
		robot.add_child(sparks("impact", 60))
		_smoke = smoke()
		robot.add_child(_smoke)
	if not mute:
		_crunch.pitch_scale = 0.7
		_crunch.volume_db = 0.0
		_crunch.play()

func restored(lost_kg: float) -> void:
	show_banner("РОБОТ СОБРАН НА БАЗЕ", "Прочность восстановлена%s" % (", груз потерян" if lost_kg > 0.05 else ""), 2.5)
	if _smoke != null and is_instance_valid(_smoke):
		_smoke.queue_free()
	_smoke = null

## Надпись по центру на t секунд.
func show_banner(title: String, sub: String, t: float) -> void:
	_banner.text = title
	_sub.text = sub
	_banner_t = t

func _process(dt: float) -> void:
	_t += dt
	_flash = move_toward(_flash, 0.0, dt * 1.6)
	var pulse := 0.0
	if _frac < 0.25:
		pulse = 0.12 * (0.5 + 0.5 * sin(_t * 6.0))
	var a := maxf(_flash, _steady + pulse)
	var col := _flash_col if _flash >= _steady else _steady_col
	_edge.modulate = Color(col.r, col.g, col.b, clampf(a, 0.0, 0.95))
	_banner_t -= dt
	var ba := clampf(_banner_t * 2.0, 0.0, 1.0)
	_banner.modulate.a = ba
	_sub.modulate.a = ba
	if cam != null and is_instance_valid(cam):
		_shake = move_toward(_shake, 0.0, dt * 1.2)
		cam.h_offset = randf_range(-1.0, 1.0) * _shake * 0.5
		cam.v_offset = randf_range(-1.0, 1.0) * _shake * 0.5
	_alarm_t -= dt
	if _frac < 0.25 and _frac > 0.0 and _alarm_t <= 0.0 and not mute:
		_alarm.play()
		_alarm_t = 1.6

func _draw_bar() -> void:
	var r := Rect2(Vector2.ZERO, _bar.size)
	_bar.draw_rect(r, Color(0.06, 0.07, 0.09, 0.72))
	var col := ProtoHud.OK if _frac > 0.6 else (ProtoHud.WARN if _frac > 0.3 else ProtoHud.BAD)
	_bar.draw_rect(Rect2(r.position + Vector2(2, 2), Vector2((r.size.x - 4) * _frac, r.size.y - 4)), col.darkened(0.25))
	if _bar_text != "":
		var f := ThemeDB.fallback_font
		_bar.draw_string_outline(f, Vector2(0, 16), _bar_text, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 14, 4, Color(0, 0, 0, 0.8))
		_bar.draw_string(f, Vector2(0, 16), _bar_text, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 14, Color.WHITE)

# ---------------------------------------------------------------- частицы

## Искры (удар, жар), капли (кислота) или изморозь — одноразовый выброс из корпуса.
static func sparks(kind: String, n: int) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.position = Vector3(0, 1.1, 0)
	p.one_shot = true
	p.explosiveness = 0.9
	p.amount = maxi(4, n)
	p.lifetime = 0.7
	p.direction = Vector3.UP
	p.spread = 80.0
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 5.5
	p.gravity = Vector3(0, -9.0, 0)
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.35
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.2
	var col: Color = COLORS.get(kind, COLORS[""])
	if kind == "impact" or kind == "":
		col = Color(1.0, 0.85, 0.45)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = col
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = 3.0
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	var q := QuadMesh.new()
	q.size = Vector2(0.05, 0.05)
	q.material = m
	p.mesh = q
	p.emitting = true
	p.finished.connect(p.queue_free)
	return p

## Дым из сломанного корпуса.
static func smoke() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.position = Vector3(0, 1.3, 0)
	p.amount = 40
	p.lifetime = 2.5
	p.direction = Vector3.UP
	p.spread = 15.0
	p.initial_velocity_min = 0.6
	p.initial_velocity_max = 1.4
	p.gravity = Vector3(0.2, 0.4, 0)
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.6
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.12, 0.12, 0.13, 0.55)
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	var g := GradientTexture2D.new()
	g.fill = GradientTexture2D.FILL_RADIAL
	g.fill_from = Vector2(0.5, 0.5)
	g.fill_to = Vector2(1.0, 0.5)
	var gr := Gradient.new()
	gr.set_color(0, Color(1, 1, 1, 1))
	gr.set_color(1, Color(1, 1, 1, 0))
	g.gradient = gr
	m.albedo_texture = g
	var q := QuadMesh.new()
	q.size = Vector2(0.6, 0.6)
	q.material = m
	p.mesh = q
	return p
