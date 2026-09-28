class_name ProtoRadar
extends Control
## Радар в углу HUD: круг рельефа вокруг робота, повёрнутый по камере (вверх —
## куда она смотрит), туман неразведанного, метки (ProtoMapData) и стрелка
## робота по его курсу. Под землёй поверхность гаснет, видны ходы и залы.
## Важные метки за краем круга прижимаются к ободу стрелкой-указателем.

const D := 196.0                 # диаметр на экране 1280×800
const SPAN := 28.0               # м от центра до обода
const EDGE_KINDS := ["factory", "cave", "machine"]

const SHADER := """
shader_type canvas_item;
uniform sampler2D relief : filter_linear, repeat_disable;
uniform sampler2D fog : filter_linear, repeat_disable;
uniform sampler2D caves : filter_linear, repeat_disable;
uniform sampler2D fog_under : filter_linear, repeat_disable;
uniform vec2 center;        // робот в uv карты
uniform vec2 fwd;           // «вверх» радара — направление в uv
uniform vec2 span;          // радиус круга в uv (по осям)
uniform float under = 0.0;  // робот под землёй
uniform float t = 0.0;
void fragment() {
	vec2 s = UV * 2.0 - 1.0;
	float r = length(s);
	vec2 rt = vec2(-fwd.y, fwd.x);
	vec2 d = s.x * rt - s.y * fwd;
	vec2 uv = center + d * span;
	bool inside = all(greaterThanEqual(uv, vec2(0.0))) && all(lessThanEqual(uv, vec2(1.0)));
	vec3 c = texture(relief, uv).rgb;
	float f = inside ? texture(fog, uv).r : 0.0;
	// Неразведанное: тёмная сетка.
	vec2 g = abs(fract(uv * 16.0) - 0.5);
	float grid = step(0.46, max(g.x, g.y));
	vec3 dark = vec3(0.07, 0.09, 0.12) + grid * 0.05;
	c = mix(dark, c, f);
	float cv = inside ? texture(caves, uv).r * texture(fog_under, uv).r : 0.0;
	c = mix(c, c * 0.3 + vec3(0.02, 0.02, 0.04), under);
	c = mix(c, vec3(0.62, 0.45, 0.95), cv * under * 0.85);
	// Кольцо на полпути и обод; развёртка локатора.
	float ring = 1.0 - smoothstep(0.0, 0.012, abs(r - 0.5));
	c += vec3(0.25) * ring * 0.35;
	float a = atan(s.y, s.x);
	float sweep = fract((a / 6.2832) - t * 0.25);
	c += vec3(0.25, 0.55, 0.45) * pow(sweep, 12.0) * 0.18 * step(r, 1.0);
	float rim = smoothstep(0.93, 0.975, r);
	c = mix(c, vec3(0.85, 0.88, 0.92), rim * 0.55);
	COLOR = vec4(c, smoothstep(1.0, 0.985, r) * 0.95);
}
"""

var data: ProtoMapData
var robot: Node3D
var cam: Camera3D                # null — камера вьюпорта
var underground := false
var span := SPAN                 # м до обода
var icon_k := 1.0                # размер значков (в игре клетки мельче значка)
var _mat: ShaderMaterial
var _icons: Control
var _t := 0.0

func setup(d: ProtoMapData, r: Node3D) -> void:
	data = d
	robot = r

func _ready() -> void:
	custom_minimum_size = Vector2(D, D)
	size = Vector2(D, D)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = SHADER
	_mat.shader = sh
	material = _mat
	_icons = Control.new()
	_icons.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icons.set_anchors_preset(Control.PRESET_FULL_RECT)
	_icons.draw.connect(_draw_icons)
	add_child(_icons)

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color.WHITE)

## «Вверх» радара в мире (x, z): куда смотрит камера.
func heading() -> Vector2:
	var c := cam if cam != null else get_viewport().get_camera_3d()
	if c == null:
		return Vector2(0, -1)
	var f := -c.global_basis.z
	if robot != null and robot.has_meta("planet_turn"):
		f = (robot.get_meta("planet_turn") as Basis).inverse() * f    # на шаре — в системе планеты
	var v := Vector2(f.x, f.z)
	return v.normalized() if v.length() > 0.01 else Vector2(0, -1)

## Мир → экран радара (от центра, пиксели): вверх — heading().
static func to_screen(d: Vector2, up: Vector2, radius: float, reach := SPAN) -> Vector2:
	var rt := Vector2(-up.y, up.x)
	return Vector2(d.dot(rt), -d.dot(up)) / reach * radius

func _process(dt: float) -> void:
	if data == null or robot == null or not is_visible_in_tree():
		return
	_t += dt
	var p: Vector3 = robot.get_meta("planet_pos", robot.global_position)
	underground = p.y < data.height_at(p.x, p.z) - 2.5
	data.reveal(p, underground)
	data.flush()
	var up := heading()
	_mat.set_shader_parameter("relief", data.relief)
	_mat.set_shader_parameter("fog", data.fog)
	_mat.set_shader_parameter("caves", data.caves)
	_mat.set_shader_parameter("fog_under", data.fog_under)
	_mat.set_shader_parameter("center", (Vector2(p.x, p.z) - data.origin) / data.size)
	_mat.set_shader_parameter("fwd", up)
	_mat.set_shader_parameter("span", Vector2(span, span) / data.size)
	_mat.set_shader_parameter("under", 1.0 if underground else 0.0)
	_mat.set_shader_parameter("t", _t)
	_icons.queue_redraw()

func _draw_icons() -> void:
	if data == null or robot == null:
		return
	var c := size * 0.5
	var rad := size.x * 0.5
	var up := heading()
	var p: Vector3 = robot.get_meta("planet_pos", robot.global_position)
	var font := get_theme_default_font()
	# Север — буква на ободе.
	var n := to_screen(Vector2(0, -1), up, rad).normalized() * (rad - 14.0)
	_icons.draw_circle(c + n, 9.0, Color(0.1, 0.12, 0.15, 0.9))
	_icons.draw_string(font, c + n + Vector2(-5, 5), "С", HORIZONTAL_ALIGNMENT_CENTER, -1, 13, Color(0.95, 0.5, 0.45))
	for m in data.found():
		var d := Vector2(m.pos.x - p.x, m.pos.z - p.z)
		var s := to_screen(d, up, rad, span)
		var edge := s.length() > rad - 12.0
		if edge:
			if not m.kind in EDGE_KINDS:
				continue
			s = s.normalized() * (rad - 12.0)
		var col: Color = m.color
		if m.under and not underground:
			col = col.darkened(0.3)
		if edge:
			_edge_arrow(c + s, s.normalized(), col)
		else:
			draw_marker(_icons, m.kind, c + s, col, icon_k)
	# Робот: стрелка по курсу, в центре.
	var f := robot.global_basis.z
	var a := to_screen(Vector2(f.x, f.z), up, 1.0)
	_arrow(_icons, c, a.normalized() if a.length() > 0.001 else Vector2(0, -1), 11.0, Color(1, 1, 1))

func _edge_arrow(at: Vector2, dir: Vector2, col: Color) -> void:
	var s := Vector2(-dir.y, dir.x)
	_icons.draw_colored_polygon(PackedVector2Array([at + dir * 7.0, at - dir * 4.0 + s * 5.0, at - dir * 4.0 - s * 5.0]), col)

static func _arrow(ci: CanvasItem, at: Vector2, dir: Vector2, l: float, col: Color) -> void:
	var s := Vector2(-dir.y, dir.x)
	var pts := PackedVector2Array([at + dir * l, at - dir * l * 0.6 + s * l * 0.7, at - dir * l * 0.25, at - dir * l * 0.6 - s * l * 0.7])
	ci.draw_colored_polygon(pts, Color(0, 0, 0, 0.6) if col.a < 0 else col)
	pts.append(pts[0])
	ci.draw_polyline(pts, Color(0, 0, 0, 0.8), 1.5, true)

## Значок метки (общий для радара и легенды 3D-карты).
static func draw_marker(ci: CanvasItem, kind: String, at: Vector2, col: Color, k: float) -> void:
	var dark := Color(0, 0, 0, 0.75)
	match kind:
		"factory", "machine":
			var r := Rect2(at - Vector2(6, 6) * k, Vector2(12, 12) * k)
			ci.draw_rect(r, col)
			ci.draw_rect(r, dark, false, 1.5)
		"cave":
			# Арка входа.
			var pts := PackedVector2Array()
			for i in 9:
				var an := PI + PI * i / 8.0
				pts.append(at + Vector2(cos(an), sin(an)) * 7.0 * k + Vector2(0, 3) * k)
			pts.append(at + Vector2(7, 4) * k)
			pts.append(at + Vector2(-7, 4) * k)
			ci.draw_colored_polygon(pts, col)
			ci.draw_circle(at + Vector2(0, 2.5) * k, 3.0 * k, dark)
		"hall":
			ci.draw_arc(at, 8.0 * k, 0, TAU, 20, col, 2.0, true)
			ci.draw_circle(at, 2.5 * k, col)
		"druse", "mined", "deposit":
			var pts := PackedVector2Array([at + Vector2(0, -7) * k, at + Vector2(5, 0) * k, at + Vector2(0, 7) * k, at + Vector2(-5, 0) * k])
			ci.draw_colored_polygon(pts, col)
			pts.append(pts[0])
			ci.draw_polyline(pts, dark, 1.2, true)
		_:
			ci.draw_circle(at, 5.0 * k, col)
