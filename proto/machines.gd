class_name ProtoMachines
extends RefCounted
## Процедурные машины из простых тел: бак со стеклянным окном и уровнем груза,
## печь с раскалённым окном, насос, пушка, трубы с бусинами газа, машина на втором
## этаже. Поверхность корпуса — из тегов материала, изучен он или нет: что о
## материале ещё не известно, показывает метка «?» (unknown_badge) у залежи и
## друзы и карточка материала, а не прозрачность. Голограмма — только призрак
## детали в режиме стройки.

const CELL := 2.0

const HOLO := """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;
uniform vec4 tint : source_color = vec4(0.3, 0.9, 1.0, 1.0);
void fragment() {
	vec3 w = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 g = abs(fract(w * 3.0) - 0.5);
	float line = step(0.46, max(max(g.x, g.y), g.z));
	float scan = 0.5 + 0.5 * sin(w.y * 8.0 - TIME * 3.0);
	ALBEDO = tint.rgb * (line * 0.9 + 0.08 + scan * 0.05);
	ALPHA = 1.0;
}
"""

static var _holo: Shader

## Голограмма: призрак детали в режиме стройки.
static func hologram() -> Material:
	if _holo == null:
		_holo = Shader.new()
		_holo.code = HOLO
	var h := ShaderMaterial.new()
	h.shader = _holo
	return h

## Метка «ещё не опознан»: янтарный «?» над залежью или друзой, всегда лицом к
## камере, видна вблизи (до BADGE_RANGE м). Сам предмет выглядит как обычно.
const BADGE_RANGE := 10.0

static func unknown_badge() -> Label3D:
	var l := Label3D.new()
	l.name = "unknown_badge"
	l.text = "?"
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.font_size = 72
	l.pixel_size = 0.004
	l.outline_size = 14
	l.modulate = Color(1.0, 0.8, 0.3)
	l.outline_modulate = Color(0.1, 0.07, 0.02, 0.9)
	l.visibility_range_end = BADGE_RANGE
	return l

## Поверхность из тегов материала.
static func surface(s: Substance) -> Material:
	var m := StandardMaterial3D.new()
	m.albedo_color = s.color
	m.roughness = 0.7
	if s.has("metallic"):
		m.metallic = 0.85
		m.roughness = 0.28
	if s.has("crystalline"):
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color = Color(s.color.lerp(Color.WHITE, 0.2), 0.72)
		m.roughness = 0.08
		m.rim_enabled = true
		m.rim = 0.6
	if s.has("porous") or s.has("fibrous"):
		var tex := NoiseTexture2D.new()
		var n := FastNoiseLite.new()
		n.frequency = 0.12 if s.has("porous") else 0.03
		if s.has("fibrous"):
			n.noise_type = FastNoiseLite.TYPE_CELLULAR
		tex.noise = n
		tex.seamless = true
		m.albedo_texture = tex
		m.uv1_triplanar = true
		m.uv1_scale = Vector3(1.5, 1.5, 1.5)
		m.roughness = 1.0
	if s.has("dense"):
		m.albedo_color = m.albedo_color.darkened(0.25)
	if s.has("luminous"):
		m.emission_enabled = true
		m.emission = s.color
		m.emission_energy_multiplier = 0.8
	return m

static func glass() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.75, 0.9, 1.0, 0.18)
	m.roughness = 0.02
	m.metallic = 0.2
	m.rim_enabled = true
	return m

static func glow(c: Color, e: float = 2.5) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = e
	return m

static func _mi(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi

static func _cyl(r: float, h: float, top := -1.0) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r if top < 0.0 else top
	c.bottom_radius = r
	c.height = h
	c.radial_segments = 20
	return c

static func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b

## Бак: корпус, стеклянный пояс, внутри — груз до уровня.
static func tank(body: Material, cargo: Color, level: float) -> Node3D:
	var n := Node3D.new()
	_mi(n, _cyl(0.75, 0.5), body, Vector3(0, 0.25, 0))
	_mi(n, _cyl(0.75, 0.35), body, Vector3(0, 1.72, 0))
	_mi(n, _cyl(0.72, 1.1), glass(), Vector3(0, 1.0, 0))
	var cm := StandardMaterial3D.new()
	cm.albedo_color = cargo
	_mi(n, _cyl(0.64, 1.1 * level), cm, Vector3(0, 0.45 + 1.1 * level / 2.0, 0))
	for a in 4:
		var ang := a * TAU / 4.0
		_mi(n, _cyl(0.05, 1.1), body, Vector3(cos(ang) * 0.74, 1.0, sin(ang) * 0.74))
	_mi(n, _cyl(0.12, 0.3), body, Vector3(0, 2.02, 0))   # горловина
	return n

## Печь: корпус, раскалённое окно, труба.
static func furnace(body: Material) -> Node3D:
	var n := Node3D.new()
	_mi(n, _box(Vector3(1.6, 1.4, 1.6)), body, Vector3(0, 0.7, 0))
	_mi(n, _box(Vector3(0.9, 0.5, 0.05)), glow(Color(1.0, 0.45, 0.1), 4.0), Vector3(0, 0.75, 0.81))
	_mi(n, _cyl(0.2, 1.2), body, Vector3(0.45, 1.9, -0.4))
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.5, 0.2)
	light.light_energy = 1.2
	light.omni_range = 3.0
	light.position = Vector3(0, 0.75, 1.3)
	n.add_child(light)
	return n

## Насос: основание, цилиндр с поршнем, маховик.
static func pump(body: Material) -> Node3D:
	var n := Node3D.new()
	_mi(n, _box(Vector3(1.2, 0.4, 0.9)), body, Vector3(0, 0.2, 0))
	_mi(n, _cyl(0.28, 1.0), body, Vector3(-0.25, 0.9, 0))
	_mi(n, _cyl(0.08, 0.6), glow(Color(0.8, 0.9, 1.0), 0.3), Vector3(-0.25, 1.6, 0))
	var t := TorusMesh.new()
	t.inner_radius = 0.28
	t.outer_radius = 0.38
	_mi(n, t, body, Vector3(0.35, 0.75, 0), Vector3(PI / 2.0, 0, 0))
	return n

## Пушка: станина и наклонный ствол.
static func cannon(body: Material) -> Node3D:
	var n := Node3D.new()
	_mi(n, _box(Vector3(1.2, 0.5, 1.2)), body, Vector3(0, 0.25, 0))
	_mi(n, _cyl(0.32, 0.5), body, Vector3(0, 0.7, 0))
	_mi(n, _cyl(0.18, 1.8, 0.14), body, Vector3(0, 1.4, 0.55), Vector3(-0.85, 0, 0))
	return n

## Труба между двумя точками, с бусинами газа.
static func pipe(parent: Node3D, a: Vector3, b: Vector3, body: Material, beads: int = 3) -> void:
	var mid := (a + b) / 2.0
	var len := a.distance_to(b)
	var mi := MeshInstance3D.new()
	mi.mesh = _cyl(0.11, len)
	mi.material_override = body
	parent.add_child(mi)
	mi.global_position = mid
	var dir := (b - a).normalized()
	var up := Vector3.UP
	if abs(dir.dot(up)) > 0.99:
		up = Vector3.RIGHT
	mi.look_at(mid + dir, up)
	mi.rotate_object_local(Vector3.RIGHT, PI / 2.0)
	var s := SphereMesh.new()
	s.radius = 0.07
	s.height = 0.14
	for i in beads:
		var bead := MeshInstance3D.new()
		bead.mesh = s
		bead.material_override = glow(Color(0.7, 0.8, 1.0), 1.5)
		parent.add_child(bead)
		bead.global_position = a.lerp(b, (i + 0.5) / beads) + Vector3(0, 0.14, 0)

## Фундамент-площадка.
static func slab(size: Vector3, col: Color) -> MeshInstance3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 0.9
	var mi := MeshInstance3D.new()
	mi.mesh = _box(size)
	mi.material_override = m
	return mi

## Этажерка: четыре стойки и настил на высоте h.
static func frame(body: Material, h: float) -> Node3D:
	var n := Node3D.new()
	for dx in [-0.9, 0.9]:
		for dz in [-0.9, 0.9]:
			_mi(n, _box(Vector3(0.12, h, 0.12)), body, Vector3(dx, h / 2.0, dz))
	_mi(n, _box(Vector3(2.0, 0.12, 2.0)), body, Vector3(0, h, 0))
	return n
