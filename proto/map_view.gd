class_name ProtoMapView
extends CanvasLayer
## Полноэкранная 3D-карта планеты (M / View на геймпаде). Настоящий рельеф
## (те же сетки, что в мире) в отдельном мире-макете: горизонтали, туман над
## неразведанным, пещеры рентгеном под поверхностью, метки на штырях и робот.
## Крутить: мышь с ЛКМ / правый стик; сдвигать: ПКМ, WASD / левый стик;
## масштаб: колесо / LT, RT (и D-pad). Пробел / A — к роботу, M, Esc / View, B —
## закрыть. В сборке для проверки Tab / Y — другая планета (on_next_planet).
## Пока карта открыта, робот стоит (мета "ui_busy"), а стройка не слушает кнопки
## (мета "map_open").

const TOGGLE := &"map_toggle"
const PITCH_MIN := 0.35
const PITCH_MAX := 1.45
const DIST_MIN := 18.0
const DIST_MAX := 150.0

## Глобус (ProtoGlobe): вся планета-шар — отдельно от макета участка.
const GLOBE_AT := Vector3(40, 0, 6000)
const GDIST_MIN := 70.0
const GDIST_MAX := 260.0

const GLOBE_SHADER := """
shader_type spatial;
render_mode unshaded;
uniform sampler2D fog : filter_linear, repeat_enable;
uniform float water = 0.0;
uniform vec3 water_col : source_color = vec3(0.3, 0.5, 0.7);
varying vec3 dir;
void vertex() {
	dir = VERTEX;
}
void fragment() {
	vec3 d = normalize(dir);
	vec2 uv = vec2(atan(d.z, d.x) / 6.2831853 + 0.5, acos(clamp(d.y, -1.0, 1.0)) / 3.14159265);
	float f = texture(fog, uv).r;
	vec3 col = mix(COLOR.rgb * 1.15, water_col * 0.85, water);
	// Свет — от камеры: какой стороной ни поверни, глобус освещён.
	float lit = 0.45 + 0.55 * max(dot(NORMAL, VIEW), 0.0);
	// Неразведанное: тёмный шар с сеткой параллелей и меридианов через 30°.
	vec2 q = vec2(uv.x * 12.0, uv.y * 6.0);
	vec2 g = abs(fract(q) - 0.5);
	vec2 w = fwidth(q) * 1.2;
	float grid = max(1.0 - smoothstep(0.0, w.x, 0.5 - g.x), 1.0 - smoothstep(0.0, w.y, 0.5 - g.y));
	grid *= smoothstep(0.02, 0.12, uv.y) * smoothstep(0.98, 0.88, uv.y);
	vec3 dark = vec3(0.075, 0.1, 0.14) * (0.6 + 0.8 * lit) + vec3(0.12, 0.3, 0.42) * grid * 0.6;
	ALBEDO = mix(dark, col * lit, f);
}
"""

const TERRAIN_SHADER := """
shader_type spatial;
render_mode cull_disabled;
uniform sampler2D fog : filter_linear, repeat_disable;
uniform vec4 bounds;
uniform float contour = 2.0;
varying vec3 wp;
void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	vec2 uv = (wp.xz - bounds.xy) / bounds.zw;
	float f = texture(fog, uv).r;
	vec3 col = COLOR.rgb * 1.15;
	// Горизонтали по высоте; каждая пятая — темнее.
	float k = wp.y / contour;
	float line = 1.0 - smoothstep(0.0, fwidth(k) * 1.4, abs(fract(k + 0.5) - 0.5));
	float major = 1.0 - step(0.5, abs(mod(round(k), 5.0)));
	col *= 1.0 - line * (0.22 + major * 0.2);
	// Неразведанное: тёмный макет с сеткой через 4 м.
	vec2 q = wp.xz / 4.0;
	vec2 g = abs(fract(q) - 0.5);
	float grid = 1.0 - smoothstep(0.0, max(fwidth(q.x), fwidth(q.y)) * 1.5, 0.5 - max(g.x, g.y));
	vec3 dark = vec3(0.075, 0.1, 0.14);
	ALBEDO = mix(dark, col, f);
	EMISSION = vec3(0.12, 0.3, 0.42) * grid * (1.0 - f) * 0.7;
	ROUGHNESS = 0.95;
}
"""

## Пещеры рентгеном: только то, что ниже поверхности и уже разведано снизу.
const XRAY_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_test_disabled, depth_draw_never, cull_disabled;
uniform sampler2D height_tex : filter_linear, repeat_disable;
uniform sampler2D fog_under : filter_linear, repeat_disable;
uniform vec4 bounds;
uniform vec3 tint : source_color = vec3(0.75, 0.55, 1.0);
varying vec3 wp;
void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	vec2 uv = (wp.xz - bounds.xy) / bounds.zw;
	float f = texture(fog_under, uv).r;
	if (wp.y > texture(height_tex, uv).r - 1.2 || f < 0.02) {
		discard;
	}
	float fres = pow(1.0 - abs(dot(NORMAL, VIEW)), 2.0);
	ALBEDO = tint * (0.05 + fres * 0.22) * f;
}
"""

const WATER_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled;
uniform sampler2D fog : filter_linear, repeat_disable;
uniform vec4 bounds;
uniform vec3 water : source_color;
varying vec3 wp;
void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	vec2 uv = (wp.xz - bounds.xy) / bounds.zw;
	float f = texture(fog, uv).r;
	vec2 q = wp.xz / 4.0;
	vec2 g = abs(fract(q) - 0.5);
	float grid = 1.0 - smoothstep(0.0, max(fwidth(q.x), fwidth(q.y)) * 1.5, 0.5 - max(g.x, g.y));
	ALBEDO = mix(vec3(0.075, 0.1, 0.14) + vec3(0.12, 0.3, 0.42) * grid * 0.7, water * 0.85, f);
	ALPHA = 0.85;
}
"""

var data: ProtoMapData
var robot: Node3D
var open := false
var pad := false
var on_next_planet := Callable()  # сборка для проверки: другая планета
var cam_main: Camera3D           # камера мира: карта открывается так же повёрнутой

var _root: Control
var _box: SubViewportContainer
var _vp: SubViewport
var _cam: Camera3D
var _marks: Node3D
var _mark_nodes: Array = []      # [маркер, узел, голова]
var _robot_mark: Node3D
var _ring: MeshInstance3D
var _legend: VBoxContainer
var _title: Label
var _stats: Label
var _hints: HBoxContainer
var _target := Vector3.ZERO
var _yaw := 0.0
var _pitch := 0.9
var _dist := 70.0
var _drag := 0                   # 1 — крутим, 2 — сдвигаем
var _mouse_mode := Input.MOUSE_MODE_VISIBLE
var globe_mode := false          # показан глобус (вся планета), а не участок
var _g_root: Node3D
var _g_built := false
var _g_robot: Node3D
var _g_marks: Node3D
var _g_sig := ""
var _gdist := 150.0
var _gyaw := 0.0
var _gpitch := 0.5
var _share_t := 0.0
var _t := 0.0
var _sig := ""

## Кнопки карты (переназначаются в экране «Управление», ProtoControls.REBIND).
static func layout() -> Dictionary:
	return {TOGGLE: [ProtoControls._key(KEY_M), ProtoControls._button(JOY_BUTTON_BACK)]}

static func ensure_actions() -> void:
	var lay := layout()
	for a in lay:
		if InputMap.has_action(a):
			continue
		InputMap.add_action(a, 0.5)
		for e in lay[a]:
			InputMap.action_add_event(a, e)

## terrain — сетки рельефа (цвет — в вершинах), caves — они же для рентгена,
## water — [[сетка, цвет]].
func setup(d: ProtoMapData, r: Node3D, terrain: Array, caves: Array, water: Array) -> void:
	data = d
	robot = r
	ensure_actions()
	layer = 20
	visible = false
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	_box = SubViewportContainer.new()
	_box.stretch = true
	_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_box)
	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.msaa_3d = Viewport.MSAA_2X
	_box.add_child(_vp)
	_scene(terrain, caves, water)
	_overlay()
	get_viewport().size_changed.connect(_fit)
	_fit()

func _scene(terrain: Array, caves: Array, water: Array) -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.03, 0.04, 0.055)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.8, 0.9)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	we.environment = env
	_vp.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-52), deg_to_rad(-35), 0)
	sun.light_energy = 1.1
	_vp.add_child(sun)
	var bounds := Vector4(data.origin.x, data.origin.y, data.size.x, data.size.y)
	var tm := _shader_mat(TERRAIN_SHADER)
	tm.set_shader_parameter("fog", data.fog)
	tm.set_shader_parameter("bounds", bounds)
	tm.set_shader_parameter("contour", ProtoMapData.CONTOUR)
	for m in terrain:
		var mi := MeshInstance3D.new()
		mi.mesh = m
		mi.material_override = tm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_vp.add_child(mi)
	var xm := _shader_mat(XRAY_SHADER)
	xm.set_shader_parameter("height_tex", data.height)
	xm.set_shader_parameter("fog_under", data.fog_under)
	xm.set_shader_parameter("bounds", bounds)
	xm.render_priority = 1
	for m in caves:
		var mi := MeshInstance3D.new()
		mi.mesh = m
		mi.material_override = xm
		_vp.add_child(mi)
	for w in water:
		var wm := _shader_mat(WATER_SHADER)
		wm.set_shader_parameter("fog", data.fog)
		wm.set_shader_parameter("bounds", bounds)
		wm.set_shader_parameter("water", w[1])
		var mi := MeshInstance3D.new()
		mi.mesh = w[0]
		mi.material_override = wm
		_vp.add_child(mi)
	_marks = Node3D.new()
	_vp.add_child(_marks)
	_robot_mark = _robot_marker()
	_vp.add_child(_robot_mark)
	_cam = Camera3D.new()
	_cam.fov = 50.0
	_cam.far = 600.0
	_vp.add_child(_cam)
	_g_root = Node3D.new()
	_g_root.name = "globe"
	_g_root.position = GLOBE_AT
	_vp.add_child(_g_root)

## Глобус: сетки из ProtoGlobe (строятся в потоке), метки завода и россыпей, робот.
func _build_globe() -> bool:
	if _g_built:
		return true
	var g: ProtoGlobe = data.globe
	if g == null or not g.ready():
		return false
	_g_built = true
	var gm := _shader_mat(GLOBE_SHADER)
	gm.set_shader_parameter("fog", g.fog)
	var mi := MeshInstance3D.new()
	mi.mesh = g.globe_mesh
	mi.material_override = gm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_g_root.add_child(mi)
	if g.sea_mesh != null:
		var sm := _shader_mat(GLOBE_SHADER)
		sm.set_shader_parameter("fog", g.fog)
		sm.set_shader_parameter("water", 1.0)
		sm.set_shader_parameter("water_col", g.fill.sea_sub.color)
		var si := MeshInstance3D.new()
		si.mesh = g.sea_mesh
		si.material_override = sm
		_g_root.add_child(si)
	_g_marks = Node3D.new()
	_g_root.add_child(_g_marks)
	_g_robot = _globe_pin("robot", "Робот", Color.WHITE)
	_g_root.add_child(_g_robot)
	return true

## Штырь на глобусе: вдоль «вверх» от центра шара, голова по виду метки.
func _globe_pin(kind: String, label: String, col: Color) -> Node3D:
	var n := Node3D.new()
	var tall := 3.0 if kind in ["factory", "robot"] else 1.6
	var stem := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.07
	cyl.bottom_radius = 0.07
	cyl.height = tall
	cyl.radial_segments = 6
	cyl.rings = 1
	stem.mesh = cyl
	stem.position.y = tall * 0.5
	stem.material_override = _flat(Color(col, 0.8))
	n.add_child(stem)
	var head := MeshInstance3D.new()
	head.position.y = tall
	if kind == "factory":
		var b := BoxMesh.new()
		b.size = Vector3(0.9, 0.9, 0.9)
		head.mesh = b
	else:
		var sp := SphereMesh.new()
		sp.radius = 0.45 if kind == "robot" else 0.35
		sp.height = sp.radius * (2.0 if kind == "robot" else 2.5)
		if kind != "robot":
			sp.radial_segments = 4
			sp.rings = 2
		head.mesh = sp
	head.material_override = _flat(col)
	n.add_child(head)
	if label != "":
		var l := Label3D.new()
		l.text = label
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.fixed_size = true
		l.pixel_size = 0.0011
		l.font_size = 28
		l.outline_size = 10
		l.modulate = col.lerp(Color.WHITE, 0.5)
		l.no_depth_test = true
		l.render_priority = 3
		l.outline_render_priority = 2
		l.position.y = tall
		l.offset = Vector2(0, 34)
		n.add_child(l)
	return n

## Поставить штырь n на глобус в точку p (система планеты).
func _pin_at(n: Node3D, p: Vector3) -> void:
	var g: ProtoGlobe = data.globe
	var at := g.to_globe(p)
	var up := at.normalized()
	var x := up.cross(Vector3.FORWARD if absf(up.z) < 0.9 else Vector3.RIGHT).normalized()
	n.transform = Transform3D(Basis(x, up, x.cross(up)), at)

func _sync_globe_marks() -> void:
	var g: ProtoGlobe = data.globe
	var list: Array = [{"kind": "factory", "name": "Завод", "pos": g.factory, "color": ProtoMapData.KINDS.factory[1]}]
	if g.fill != null:
		for id in g.fill.finds:
			if g.fill.finds[id].found:
				list.append(g.fill.finds[id])
	var sig := str(list.size())
	if sig == _g_sig:
		return
	_g_sig = sig
	for c in _g_marks.get_children():
		c.queue_free()
	for m in list:
		var n := _globe_pin(m.kind, "Завод" if m.kind == "factory" else "", m.color)
		_pin_at(n, m.pos)
		_g_marks.add_child(n)

## Глобус ↔ участок. На глобус — повернуть так, чтобы робот был к камере.
func set_globe(on: bool) -> void:
	if on and not _build_globe():
		return
	globe_mode = on
	if on:
		_face_robot()
		_gdist = 150.0
	_cam.far = 1000.0 if on else 600.0
	_hint_key = ""
	_fill_legend()

func _face_robot() -> void:
	if robot == null or data.globe == null:
		return
	var p: Vector3 = robot.get_meta("planet_pos", robot.global_position)
	var d := (p - (data.globe as ProtoGlobe).terrain.center).normalized()
	_gyaw = atan2(d.x, d.z)
	_gpitch = clampf(asin(d.y), -1.35, 1.35)

func _shader_mat(code: String) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = code
	m.shader = sh
	return m

static func _flat(c: Color, over := true) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	m.no_depth_test = over
	m.render_priority = 2 if over else 0
	if c.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m

# ---------------------------------------------------------------- метки

## Метка: штырь от места вверх, над ним значок (виден сквозь рельеф) и подпись.
func _marker_node(m: Dictionary) -> Array:
	var n := Node3D.new()
	var p: Vector3 = m.pos
	n.position = p
	var col: Color = m.color
	var tall := 7.0 if m.kind in ["factory", "cave", "hall", "machine"] else 2.5
	if m.under:
		# Подземное — штырь до поверхности и выше: видно, что оно глубоко.
		tall += maxf(0.0, data.height_at(p.x, p.z) - p.y)
	var stem := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.09
	cyl.bottom_radius = 0.09
	cyl.height = tall
	cyl.radial_segments = 6
	cyl.rings = 1
	stem.mesh = cyl
	stem.position.y = tall * 0.5
	stem.material_override = _flat(Color(col, 0.7), m.under)
	n.add_child(stem)
	var head := MeshInstance3D.new()
	head.position.y = tall
	match m.kind:
		"factory", "machine":
			var b := BoxMesh.new()
			b.size = Vector3(1, 1, 1)
			head.mesh = b
		"cave":
			var t := TorusMesh.new()
			t.inner_radius = 0.35
			t.outer_radius = 0.7
			head.mesh = t
		"hall":
			var s := SphereMesh.new()
			s.radius = 0.6
			s.height = 1.2
			head.mesh = s
		_:
			# Друза и залежь — ромб (октаэдр).
			var s := SphereMesh.new()
			s.radius = 0.4
			s.height = 1.0
			s.radial_segments = 4
			s.rings = 2
			head.mesh = s
	head.material_override = _flat(col)
	n.add_child(head)
	if m.kind in ["factory", "cave", "hall", "machine"]:
		var l := Label3D.new()
		l.text = m.name
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.fixed_size = true
		l.pixel_size = 0.0011
		l.font_size = 30
		l.outline_size = 10
		l.modulate = col.lerp(Color.WHITE, 0.5)
		l.no_depth_test = true
		l.render_priority = 3
		l.outline_render_priority = 2
		l.position.y = tall
		l.offset = Vector2(0, 34)
		n.add_child(l)
	_marks.add_child(n)
	return [m, n, head]

func _robot_marker() -> Node3D:
	var n := Node3D.new()
	var arrow := MeshInstance3D.new()
	var pm := PrismMesh.new()
	pm.size = Vector3(1.6, 2.4, 0.5)
	arrow.mesh = pm
	# Острие призмы (+Y) — вперёд робота (+Z), плашмя.
	arrow.rotation.x = PI * 0.5
	arrow.material_override = _flat(Color(1, 1, 1))
	var holder := Node3D.new()
	holder.name = "arrow"
	holder.add_child(arrow)
	n.add_child(holder)
	_ring = MeshInstance3D.new()
	var t := TorusMesh.new()
	t.inner_radius = 1.9
	t.outer_radius = 2.2
	t.rings = 32
	_ring.mesh = t
	_ring.material_override = _flat(Color(1, 1, 1, 0.8))
	n.add_child(_ring)
	var l := Label3D.new()
	l.text = "Робот"
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.fixed_size = true
	l.pixel_size = 0.0011
	l.font_size = 26
	l.outline_size = 10
	l.no_depth_test = true
	l.render_priority = 3
	l.outline_render_priority = 2
	l.offset = Vector2(0, 44)
	n.add_child(l)
	return n

func _sync_marks() -> void:
	var sig := str(data.markers.map(func(m): return [m.kind, m.found]))
	if sig == _sig:
		return
	_sig = sig
	for e in _mark_nodes:
		e[1].queue_free()
	_mark_nodes.clear()
	for m in data.found():
		_mark_nodes.append(_marker_node(m))
	_fill_legend()

# ---------------------------------------------------------------- открыть / закрыть

func toggle() -> void:
	if open:
		close()
	else:
		show_map()

func show_map() -> void:
	open = true
	visible = true
	_mouse_mode = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_set_meta(true)
	center_on_robot()
	var c := cam_main if cam_main != null else get_viewport().get_camera_3d()
	if c != null:
		var f := -c.global_basis.z
		if Vector2(f.x, f.z).length() > 0.01:
			_yaw = atan2(-f.x, -f.z)
	_pitch = 0.95
	_dist = 72.0
	data.flush()
	_sync_marks()
	# Робот ушёл с участка по шару — сразу глобус.
	var g: ProtoGlobe = data.globe
	var q: Vector3 = robot.get_meta("planet_pos", robot.global_position) if robot else Vector3.ZERO
	set_globe(g != null and g.away(q))
	_place_cam()

func close() -> void:
	open = false
	visible = false
	_drag = 0
	Input.mouse_mode = _mouse_mode
	_set_meta(false)

func _set_meta(on: bool) -> void:
	if robot != null:
		robot.set_meta("ui_busy", on)
		robot.set_meta("map_open", on)

func center_on_robot() -> void:
	if robot != null:
		var p: Vector3 = robot.get_meta("planet_pos", robot.global_position)
		_target = Vector3(p.x, maxf(p.y, data.height_at(p.x, p.z)), p.z)

func _place_cam() -> void:
	if globe_mode:
		var go := Vector3(sin(_gyaw) * cos(_gpitch), sin(_gpitch), cos(_gyaw) * cos(_gpitch))
		_cam.position = GLOBE_AT + go * _gdist
		_cam.look_at(GLOBE_AT, Vector3.UP)
		return
	var off := Vector3(sin(_yaw) * cos(_pitch), sin(_pitch), cos(_yaw) * cos(_pitch))
	_cam.position = _target + off * _dist
	_cam.look_at(_target, Vector3.UP)

# ---------------------------------------------------------------- ввод

## Можно ли открыть карту сейчас: не в стройке (там M — материал), не в карточке
## и не в окне рана.
func _can_open() -> bool:
	if robot == null:
		return false
	if bool(robot.get_meta("ui_busy", false)):
		return false
	var ru = get_parent().get("run_ui") if get_parent() else null
	if ru != null and str(ru.get("modal")) != "":
		return false                           # открыто окно рана (меню, цель, награда)
	var b := get_parent().get_node_or_null("builder") if get_parent() else null
	return b == null or not bool(b.get("active"))

func _input(e: InputEvent) -> void:
	if e is InputEventKey or e is InputEventMouseButton:
		pad = false
	elif e is InputEventJoypadButton or (e is InputEventJoypadMotion and absf(e.axis_value) > 0.5):
		pad = true
	if not open:
		if e.is_action_pressed(TOGGLE) and not e.is_echo() and _can_open():
			show_map()
			get_viewport().set_input_as_handled()
		return
	get_viewport().set_input_as_handled()
	if e is InputEventMouseButton:
		if e.button_index == MOUSE_BUTTON_WHEEL_UP and e.pressed:
			_zoom(0.9)
		elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN and e.pressed:
			_zoom(1.1)
		elif e.button_index == MOUSE_BUTTON_LEFT:
			_drag = 1 if e.pressed else 0
		elif e.button_index in [MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
			_drag = 2 if e.pressed else 0
		return
	if e is InputEventMouseMotion:
		if globe_mode and _drag > 0:
			_gyaw -= e.relative.x * 0.006
			_gpitch = clampf(_gpitch + e.relative.y * 0.005, -1.35, 1.35)
		elif _drag == 1:
			_yaw -= e.relative.x * 0.006
			_pitch = clampf(_pitch + e.relative.y * 0.005, PITCH_MIN, PITCH_MAX)
		elif _drag == 2:
			_pan(Vector2(-e.relative.x, e.relative.y) * _dist * 0.0022)
		return
	if not e.is_pressed() or e.is_echo():
		return
	var key: int = e.physical_keycode if e is InputEventKey else KEY_NONE
	var btn: int = e.button_index if e is InputEventJoypadButton else -1
	if e.is_action_pressed(TOGGLE) or key == KEY_ESCAPE or btn == JOY_BUTTON_B:
		close()
	elif key == KEY_SPACE or btn == JOY_BUTTON_A:
		center_on_robot()
		_face_robot()
	elif key == KEY_G or btn == JOY_BUTTON_X:
		set_globe(not globe_mode)
	elif (key == KEY_TAB or btn == JOY_BUTTON_Y) and on_next_planet.is_valid():
		close()
		on_next_planet.call()

## Масштаб: за краем участка — глобус, из глобуса ближе — снова участок.
func _zoom(k: float) -> void:
	if globe_mode:
		_gdist *= k
		if _gdist < GDIST_MIN and k < 1.0:
			set_globe(false)
			_dist = DIST_MAX
		_gdist = clampf(_gdist, GDIST_MIN, GDIST_MAX)
		return
	if _dist >= DIST_MAX and k > 1.0 and data.globe != null:
		set_globe(true)
		_gdist = GDIST_MIN + 10.0
		return
	_dist = clampf(_dist * k, DIST_MIN, DIST_MAX)

## Сдвиг цели: x — вправо по экрану, y — «вверх» (от камеры по земле).
func _pan(v: Vector2) -> void:
	var fwd := Vector3(-sin(_yaw), 0, -cos(_yaw))
	var right := Vector3(-fwd.z, 0, fwd.x)
	_target += right * v.x + fwd * v.y
	_target.x = clampf(_target.x, data.origin.x, data.origin.x + data.size.x)
	_target.z = clampf(_target.z, data.origin.y, data.origin.y + data.size.y)
	_target.y = data.height_at(_target.x, _target.z)

func _process(dt: float) -> void:
	if not open:
		return
	_t += dt
	# Стики и клавиши: левый / WASD — сдвиг, правый / Q,E — поворот и наклон,
	# курки и D-pad — масштаб.
	var mv := ProtoControls.move_vector()
	var lk := Input.get_vector(ProtoControls.CAM_LEFT, ProtoControls.CAM_RIGHT, ProtoControls.CAM_DOWN, ProtoControls.CAM_UP)
	var zoom := Input.get_action_strength(ProtoControls.WORK) - Input.get_action_strength(ProtoControls.FIST)
	if Input.is_action_pressed(ProtoControls.CAM_ZOOM_IN): zoom += 1.0
	if Input.is_action_pressed(ProtoControls.CAM_ZOOM_OUT): zoom -= 1.0
	if globe_mode:
		_process_globe(dt, mv + lk, zoom)
		return
	if mv.length() > 0.0:
		_pan(mv * dt * (12.0 + _dist * 0.6))
	_yaw -= lk.x * dt * 2.0
	_pitch = clampf(_pitch - lk.y * dt * 1.2, PITCH_MIN, PITCH_MAX)
	if absf(zoom) > 0.0:
		_zoom(1.0 - zoom * dt * 1.4)
		if globe_mode:
			return
	_place_cam()
	data.flush()
	_sync_marks()
	# Значки — постоянного размера на экране.
	var k := _dist * 0.022
	for e in _mark_nodes:
		e[2].scale = Vector3.ONE * k
		if e[0].kind in ["druse", "deposit", "mined"]:
			e[2].rotation.y += dt * 1.2
	if robot != null:
		_robot_mark.position = (robot.get_meta("planet_pos", robot.global_position) as Vector3) + Vector3(0, 0.6, 0)
		var f := robot.global_basis.z
		if robot.has_meta("planet_turn"):
			f = (robot.get_meta("planet_turn") as Basis).inverse() * f
		(_robot_mark.get_node("arrow") as Node3D).rotation.y = atan2(f.x, f.z)
		(_robot_mark.get_node("arrow") as Node3D).scale = Vector3.ONE * k
		var pulse := fmod(_t * 0.8, 1.0)
		_ring.scale = Vector3.ONE * k * (0.6 + pulse * 1.2)
		(_ring.material_override as StandardMaterial3D).albedo_color.a = 0.9 * (1.0 - pulse)
	_stats.text = "Разведано %d%%" % roundi(data.explored_share() * 100.0)
	_fill_hints()

## Глобус: стики и WASD крутят шар, курки — масштаб; робот — штырь по курсу.
func _process_globe(dt: float, turn: Vector2, zoom: float) -> void:
	_gyaw -= turn.x * dt * 1.6
	_gpitch = clampf(_gpitch - turn.y * dt * 1.2, -1.35, 1.35)
	if absf(zoom) > 0.0:
		_zoom(1.0 - zoom * dt * 1.4)
		if not globe_mode:
			return
	_place_cam()
	var g: ProtoGlobe = data.globe
	g.flush()
	_sync_globe_marks()
	if robot != null:
		_pin_at(_g_robot, robot.get_meta("planet_pos", robot.global_position))
		# Штыри — одного размера на экране.
		var ks := _gdist / 150.0
		_g_robot.scale = Vector3.ONE * ks
		for c: Node3D in _g_marks.get_children():
			c.scale = Vector3.ONE * ks
		var pulse := fmod(_t * 0.8, 1.0)
		_g_robot.get_child(1).scale = Vector3.ONE * (1.0 + 0.35 * sin(pulse * TAU))
	_share_t -= dt
	if _share_t <= 0.0:
		_share_t = 0.5
		_stats.text = "Разведано %.1f%% планеты" % (g.explored_share() * 100.0)
	_fill_hints()

# ---------------------------------------------------------------- подписи

func _fit() -> void:
	var vs := get_viewport().get_visible_rect().size
	var s := clampf(minf(vs.x / ProtoHud.BASE.x, vs.y / ProtoHud.BASE.y), 0.75, 2.0)
	var ui := _root.get_node("ui") as Control
	ui.scale = Vector2(s, s)
	ui.size = vs / s

func _overlay() -> void:
	var ui := Control.new()
	ui.name = "ui"
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(ui)
	var head := _panel()
	ui.add_child(head)
	head.position = Vector2(ProtoHud.PAD, ProtoHud.PAD)
	var hb: VBoxContainer = head.get_child(0)
	_title = _label("КАРТА", ProtoHud.FONT + 4, ProtoHud.TEXT)
	hb.add_child(_title)
	_stats = _label("", ProtoHud.FONT_SMALL, ProtoHud.DIM)
	hb.add_child(_stats)
	_legend = VBoxContainer.new()
	_legend.add_theme_constant_override("separation", 4)
	hb.add_child(_legend)
	var bar := _panel()
	ui.add_child(bar)
	bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bar.offset_top = -ProtoHud.PAD
	bar.offset_bottom = -ProtoHud.PAD
	_hints = HBoxContainer.new()
	_hints.add_theme_constant_override("separation", 22)
	bar.get_child(0).add_child(_hints)

func _fill_legend() -> void:
	_title.text = "КАРТА · " + data.name if data.name != "" else "КАРТА"
	if globe_mode:
		_title.text = "ПЛАНЕТА · " + data.name if data.name != "" else "ПЛАНЕТА"
	for c in _legend.get_children():
		c.queue_free()
	var kinds := []
	var found: Array = data.found()
	if globe_mode:
		found = [{"kind": "factory"}]
		var g: ProtoGlobe = data.globe
		if g.fill != null:
			for id in g.fill.finds:
				if g.fill.finds[id].found:
					found.append(g.fill.finds[id])
	for m in found:
		if not m.kind in kinds:
			kinds.append(m.kind)
	var rows: Array = [["robot", "Робот", Color.WHITE]]
	for k in ProtoMapData.KINDS:
		if k in kinds:
			rows.append([k, {"druse": "Друзы", "deposit": "Залежи", "machine": "Машины"}.get(k, ProtoMapData.KINDS[k][0]), ProtoMapData.KINDS[k][1]])
	rows.append(["fog", "Не разведано", Color(0.3, 0.45, 0.55)])
	for r in rows:
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 8)
		var ic := Control.new()
		ic.custom_minimum_size = Vector2(20, 20)
		var kind: String = r[0]
		var col: Color = r[2]
		ic.draw.connect(func():
			var c := ic.size * 0.5
			if kind == "robot":
				ProtoRadar._arrow(ic, c, Vector2(0, -1), 8.0, col)
			elif kind == "fog":
				ic.draw_rect(Rect2(c - Vector2(8, 8), Vector2(16, 16)), Color(0.075, 0.1, 0.14))
				ic.draw_rect(Rect2(c - Vector2(8, 8), Vector2(16, 16)), col, false, 1.0)
			else:
				ProtoRadar.draw_marker(ic, kind, c, col, 0.9))
		line.add_child(ic)
		line.add_child(_label(r[1], ProtoHud.FONT_SMALL, ProtoHud.TEXT))
		_legend.add_child(line)

var _hint_key := ""

func _fill_hints() -> void:
	var rows := [["Повернуть", "ЛКМ", "R-стик"], ["Сдвинуть", "WASD ПКМ", "L-стик"],
		["Масштаб", "Колесо", "LT RT"], ["К роботу", "Пробел", "A"]]
	if globe_mode:
		rows = [["Крутить", "ЛКМ WASD", "Стики"], ["Масштаб", "Колесо", "LT RT"], ["К роботу", "Пробел", "A"]]
	if data.globe != null:
		rows.append(["Участок" if globe_mode else "Вся планета", "G", "X"])
	if on_next_planet.is_valid():
		rows.append(["Другая планета", "Tab", "Y"])
	rows.append(["Закрыть", "M Esc", "View B"])
	var key := str([rows, pad, globe_mode])
	if key == _hint_key:
		return
	_hint_key = key
	for c in _hints.get_children():
		c.queue_free()
	for r in rows:
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 6)
		for g in (r[2] if pad else r[1]).split(" "):
			line.add_child(_chip(g))
		line.add_child(_label(r[0], ProtoHud.FONT_SMALL + 1, ProtoHud.TEXT))
		_hints.add_child(line)

func _panel() -> PanelContainer:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = ProtoHud.BG
	sb.border_color = ProtoHud.EDGE
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	p.add_theme_stylebox_override("panel", sb)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	p.add_child(box)
	return p

func _label(t: String, sz: int, col: Color) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", sz)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("outline_size", 4)
	return l

func _chip(t: String) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	var round := pad and ProtoHud.PAD_COLORS.has(t)
	sb.bg_color = ProtoHud.PAD_COLORS[t] if round else Color(0.22, 0.24, 0.28)
	sb.border_color = Color(1, 1, 1, 0.35)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(14 if round else 6)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 1
	sb.content_margin_bottom = 1
	p.add_theme_stylebox_override("panel", sb)
	p.custom_minimum_size = Vector2(28, 28)
	var l := _label(t, ProtoHud.FONT_SMALL, Color.WHITE)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	p.add_child(l)
	return p
