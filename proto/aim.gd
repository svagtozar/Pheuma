class_name ProtoAim
extends CanvasLayer
## Прицел: перекрестье в центре экрана (луч камеры, ProtoPlayer._aim_point) и
## шар-кисть в мире — где бур вгрызётся или кисть насыплет грунт, как в Astroneer.
## Цвет перекрестья: белое — ничего под прицелом, янтарное — порода в
## досягаемости бура, зелёное — кристалл или растение, серое — далеко.

enum {IDLE, READY, TARGET, FAR}
const COLORS := [Color(1, 1, 1, 0.75), Color(1.0, 0.74, 0.32, 0.95),
	Color(0.55, 1.0, 0.65, 0.95), Color(0.75, 0.75, 0.75, 0.4)]

var state := IDLE
var marker: MeshInstance3D     # шар-кисть в мире (добавляется в сцену рядом с роботом)
var _cross: Control
var _pulse := 0.0

func _ready() -> void:
	layer = 4
	_cross = Control.new()
	_cross.name = "crosshair"
	_cross.set_anchors_preset(Control.PRESET_FULL_RECT)
	_cross.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cross.draw.connect(_draw_cross)
	add_child(_cross)

## Шар-кисть: полупрозрачная сфера поверх породы.
func make_marker(parent: Node) -> void:
	marker = MeshInstance3D.new()
	marker.name = "aim_brush"
	var m := SphereMesh.new()
	m.radius = 1.0
	m.height = 2.0
	m.radial_segments = 24
	m.rings = 12
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1.0, 0.74, 0.32, 0.13)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.no_depth_test = false
	mat.rim_enabled = false
	m.material = mat
	marker.mesh = m
	marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	marker.visible = false
	parent.add_child(marker)

## Кадр: состояние перекрестья; brush — центр шара-кисти (INF — спрятать), r — радиус.
func show_state(s: int, brush := Vector3.INF, r := 1.0, add := false, dt := 0.0) -> void:
	_pulse += dt
	if s != state:
		state = s
	_cross.queue_redraw()
	if marker != null:
		marker.visible = brush != Vector3.INF
		if marker.visible:
			marker.global_position = brush
			marker.scale = Vector3.ONE * maxf(r, 0.2) * (1.0 + 0.04 * sin(_pulse * 9.0))
			var mat := (marker.mesh as SphereMesh).material as StandardMaterial3D
			mat.albedo_color = Color(0.6, 0.85, 1.0, 0.14) if add else Color(1.0, 0.74, 0.32, 0.13)

func set_hidden(h: bool) -> void:
	_cross.visible = not h
	if h and marker != null:
		marker.visible = false

func _draw_cross() -> void:
	var sz := _cross.get_viewport_rect().size
	var c := sz * 0.5
	var k := sz.y / 1080.0
	var col: Color = COLORS[state]
	var shade := Color(0, 0, 0, col.a * 0.7)
	var gap := (8.0 if state == IDLE else 11.0) * k
	var len := 11.0 * k
	var w := maxf(2.0, 3.0 * k)
	for pass_i in 2:
		var cc := shade if pass_i == 0 else col
		var ww := w + (2.0 * k if pass_i == 0 else 0.0)
		for d in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
			_cross.draw_line(c + d * gap, c + d * (gap + len), cc, ww, true)
		_cross.draw_circle(c, (3.4 if pass_i == 0 else 2.2) * k, cc)
	if state == READY or state == TARGET:
		_cross.draw_arc(c, gap + len + 4.0 * k, 0.0, TAU, 32, Color(col, col.a * 0.6), maxf(1.0, 1.4 * k), true)
