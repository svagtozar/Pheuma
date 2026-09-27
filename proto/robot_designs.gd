class_name RobotDesigns
extends RefCounted
## Варианты дизайна робота для витрины (proto/robots.tscn). Всё из простых тел:
## стержни между точками скелета, шарниры, капсулы, короба, торы, шланги по Безье.
## Гибрид «каркас, обрастающий планетой» — в трёх уровнях детальности (h1, h2, h3),
## плюс концепции pneumat, geologist, miner, jumper и concept — по концепт-арту
## (concept_b — он же с корпусом из металла другой планеты). clean — чистый
## хард-серфейс, buddy — коренастый компаньон. toon — стилизованная отрисовка.

const DESIGNS := ["h1", "h2", "h3", "concept", "concept_b", "clean", "buddy", "pneumat", "geologist", "miner", "jumper"]
const NAMES := {"h1": "Гибрид · Н1 силуэт", "h2": "Гибрид · Н2 рабочий", "h3": "Гибрид · Н3 детальный",
	"concept": "Концепт · медь", "concept_b": "Концепт · другой металл",
	"clean": "Хард-серфейс", "buddy": "Компаньон",
	"pneumat": "A · Пневмат", "geologist": "B · Геолог", "miner": "D · Горняк", "jumper": "E · Прыгун"}
## Металл корпуса по умолчанию — медь; в игре — металл планеты.
const COPPER := Color(0.78, 0.47, 0.29)
const ALT_METAL := Color(0.42, 0.55, 0.72)

static var _mats := {}
## Стилизованная отрисовка: ступенчатый свет и контур. Ставится до build().
static var toon := false
static var _outline_mat: ShaderMaterial

const OUTLINE := """
shader_type spatial;
render_mode unshaded, cull_front, depth_draw_opaque;
void vertex() {
	vec4 wp = MODEL_MATRIX * vec4(VERTEX, 1.0);
	vec3 wn = normalize(MODEL_NORMAL_MATRIX * NORMAL);
	float d = length(CAMERA_POSITION_WORLD - wp.xyz);
	wp.xyz += wn * clamp(d * 0.0035, 0.004, 0.04);
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * wp;
}
void fragment() {
	ALBEDO = vec3(0.035, 0.035, 0.045);
}
"""

# ---------------------------------------------------------------- материалы

static func mat(key: String) -> Material:
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	match key:
		"hull": m.albedo_color = Color(0.62, 0.65, 0.7); m.metallic = 0.75; m.roughness = 0.32
		"dark": m.albedo_color = Color(0.13, 0.13, 0.15); m.metallic = 0.5; m.roughness = 0.45
		"accent": m.albedo_color = Color(1.0, 0.6, 0.12); m.metallic = 0.3; m.roughness = 0.4
		"rubber": m.albedo_color = Color(0.07, 0.07, 0.08); m.roughness = 0.9
		"chrome": m.albedo_color = Color(0.85, 0.87, 0.9); m.metallic = 1.0; m.roughness = 0.12
		"glow":
			m.albedo_color = Color(0.3, 0.9, 1.0); m.emission_enabled = true
			m.emission = Color(0.3, 0.9, 1.0); m.emission_energy_multiplier = 3.0
		"steel": m.albedo_color = Color(0.72, 0.74, 0.77); m.metallic = 0.7; m.roughness = 0.28
		"iris":
			m.albedo_color = Color(0.2, 0.85, 1.0); m.emission_enabled = true
			m.emission = Color(0.15, 0.8, 1.0); m.emission_energy_multiplier = 1.4
		"glow_warm":
			m.albedo_color = Color(1.0, 0.75, 0.35); m.emission_enabled = true
			m.emission = Color(1.0, 0.7, 0.3); m.emission_energy_multiplier = 3.0
		"glass":
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.albedo_color = Color(0.8, 0.92, 1.0, 0.22); m.roughness = 0.02; m.metallic = 0.2
			m.rim_enabled = true
		"gas":
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.albedo_color = Color(0.5, 0.85, 1.0, 0.55); m.emission_enabled = true
			m.emission = Color(0.4, 0.8, 1.0); m.emission_energy_multiplier = 1.3
		"copper": m.albedo_color = Color(0.78, 0.45, 0.28); m.metallic = 0.9; m.roughness = 0.3
		"crystal":
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.albedo_color = Color(0.62, 0.45, 0.95, 0.7); m.roughness = 0.05
			m.rim_enabled = true; m.rim = 0.7
			m.emission_enabled = true; m.emission = Color(0.45, 0.3, 0.8); m.emission_energy_multiplier = 0.25
		"porous":
			m.albedo_color = Color(0.55, 0.38, 0.3); m.roughness = 1.0
			var tex := NoiseTexture2D.new()
			var n := FastNoiseLite.new()
			n.frequency = 0.2
			tex.noise = n
			tex.seamless = true
			m.albedo_texture = tex
			m.uv1_triplanar = true
			m.uv1_scale = Vector3(3, 3, 3)
		_:
			if key.begins_with("metal:"):
				m.albedo_color = Color(key.substr(6)); m.metallic = 0.9; m.roughness = 0.32
			elif key.begins_with("paint:"):
				# Окрашенная панель корпуса: светлая, почти матовая.
				m.albedo_color = Color(key.substr(6)); m.metallic = 0.2; m.roughness = 0.42
			elif key.begins_with("pod:"):
				var c := Color(key.substr(4))
				m.albedo_color = c; m.emission_enabled = true; m.emission = c; m.emission_energy_multiplier = 0.6
	if toon and m.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED:
		# Ступенчатый свет ярче обычного — чуть приглушаем цвет, чтобы не выгорал.
		if not m.emission_enabled:
			m.albedo_color = m.albedo_color.darkened(0.18)
		m.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
		m.specular_mode = BaseMaterial3D.SPECULAR_TOON
		if _outline_mat == null:
			_outline_mat = ShaderMaterial.new()
			var sh := Shader.new()
			sh.code = OUTLINE
			_outline_mat.shader = sh
		m.next_pass = _outline_mat
	_mats[key] = m
	return m

# ---------------------------------------------------------------- детали

static func _orient(mi: Node3D, a: Vector3, b: Vector3) -> void:
	var y := (b - a).normalized()
	var ref := Vector3.FORWARD if abs(y.dot(Vector3.FORWARD)) < 0.95 else Vector3.RIGHT
	var x := y.cross(ref).normalized()
	var z := x.cross(y).normalized()
	mi.transform = Transform3D(Basis(x, y, z), (a + b) / 2.0)

static func rod(p: Node3D, a: Vector3, b: Vector3, r: float, m: String, r_top := -1.0) -> MeshInstance3D:
	var c := CylinderMesh.new()
	c.bottom_radius = r
	c.top_radius = r if r_top < 0.0 else r_top
	c.height = a.distance_to(b)
	c.radial_segments = 12
	c.rings = 1
	var mi := MeshInstance3D.new()
	mi.mesh = c
	mi.material_override = mat(m)
	p.add_child(mi)
	_orient(mi, a, b)
	return mi

static func caps(p: Node3D, a: Vector3, b: Vector3, r: float, m: String) -> MeshInstance3D:
	var c := CapsuleMesh.new()
	c.radius = r
	c.height = a.distance_to(b) + r * 2.0
	c.radial_segments = 14
	c.rings = 4
	var mi := MeshInstance3D.new()
	mi.mesh = c
	mi.material_override = mat(m)
	p.add_child(mi)
	_orient(mi, a, b)
	return mi

static func ball(p: Node3D, c: Vector3, r: float, m: String) -> MeshInstance3D:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 14
	s.rings = 7
	var mi := MeshInstance3D.new()
	mi.mesh = s
	mi.material_override = mat(m)
	mi.position = c
	p.add_child(mi)
	return mi

static func box(p: Node3D, c: Vector3, size: Vector3, m: String, rot := Vector3.ZERO) -> MeshInstance3D:
	var b := BoxMesh.new()
	b.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = b
	mi.material_override = mat(m)
	mi.position = c
	mi.rotation = rot
	p.add_child(mi)
	return mi

static func ring(p: Node3D, c: Vector3, axis: Vector3, r_in: float, r_out: float, m: String) -> MeshInstance3D:
	var t := TorusMesh.new()
	t.inner_radius = r_in
	t.outer_radius = r_out
	t.rings = 20
	t.ring_segments = 8
	var mi := MeshInstance3D.new()
	mi.mesh = t
	mi.material_override = mat(m)
	p.add_child(mi)
	_orient(mi, c - axis * 0.01, c + axis * 0.01)
	mi.position = c
	return mi

## Шланг по кубической кривой Безье.
static func hose(p: Node3D, a: Vector3, ca: Vector3, cb: Vector3, b: Vector3, r: float, m: String = "rubber", seg: int = 10) -> void:
	var prev := a
	for i in range(1, seg + 1):
		var t := float(i) / seg
		var u := 1.0 - t
		var q := a * u * u * u + ca * 3.0 * u * u * t + cb * 3.0 * u * t * t + b * t * t * t
		rod(p, prev, q, r, m)
		ball(p, q, r, m)
		prev = q

## Пластина вдоль отрезка a→b, сдвинутая по out.
static func plate(p: Node3D, a: Vector3, b: Vector3, w: float, t: float, out: Vector3, m: String) -> MeshInstance3D:
	var mi := box(p, Vector3.ZERO, Vector3(w, a.distance_to(b), t), m)
	_orient(mi, a + out, b + out)
	return mi

## Поршень параллельно кости: корпус-цилиндр и хромированный шток.
static func piston(p: Node3D, a: Vector3, b: Vector3, off: Vector3, r: float) -> void:
	var a2 := a.lerp(b, 0.12) + off
	var b2 := a.lerp(b, 0.88) + off
	var mid := a2.lerp(b2, 0.55)
	rod(p, a2, mid, r, "dark")
	rod(p, mid, b2, r * 0.45, "chrome")

# ---------------------------------------------------------------- скелет

static func skeleton(w: float = 1.0) -> Dictionary:
	return {
		"pelvis": Vector3(0, 0.95, 0), "chest": Vector3(0, 1.32, 0), "neck": Vector3(0, 1.52, 0), "head": Vector3(0, 1.67, 0.02),
		"sh_l": Vector3(-0.23 * w, 1.45, 0), "sh_r": Vector3(0.23 * w, 1.45, 0),
		"el_l": Vector3(-0.3 * w, 1.17, -0.02), "el_r": Vector3(0.31 * w, 1.19, 0.07),
		"ha_l": Vector3(-0.3 * w, 0.93, 0.06), "ha_r": Vector3(0.35 * w, 0.98, 0.2),
		"hi_l": Vector3(-0.11 * w, 0.92, 0), "hi_r": Vector3(0.11 * w, 0.92, 0),
		"kn_l": Vector3(-0.13 * w, 0.5, 0.05), "kn_r": Vector3(0.12 * w, 0.5, 0.03),
		"an_l": Vector3(-0.14 * w, 0.08, -0.02), "an_r": Vector3(0.13 * w, 0.08, 0.0),
	}

static func _limbs_rods(n: Node3D, s: Dictionary, r: float, m: String, joints: bool = true) -> void:
	for side in ["l", "r"]:
		rod(n, s["sh_" + side], s["el_" + side], r, m)
		rod(n, s["el_" + side], s["ha_" + side], r * 0.85, m)
		rod(n, s["hi_" + side], s["kn_" + side], r * 1.2, m)
		rod(n, s["kn_" + side], s["an_" + side], r, m)
		if joints:
			for j in ["sh_", "el_", "hi_", "kn_", "an_"]:
				ball(n, s[j + side], r * 1.7, "dark")

static func _feet(n: Node3D, s: Dictionary, size := Vector3(0.11, 0.06, 0.24), m := "dark") -> void:
	for side in ["l", "r"]:
		box(n, s["an_" + side] + Vector3(0, -0.05, 0.05), size, m)

## Голова-объектив: короткий широкий цилиндр вперёд, светящаяся линза.
static func _lens_head(n: Node3D, c: Vector3, r: float, ring_glow: bool) -> void:
	rod(n, c + Vector3(0, 0, -0.09), c + Vector3(0, 0, 0.09), r, "hull")
	rod(n, c + Vector3(0, 0, 0.09), c + Vector3(0, 0, 0.11), r * 0.8, "dark")
	rod(n, c + Vector3(0, 0, 0.11), c + Vector3(0, 0, 0.125), r * 0.5, "glow")
	if ring_glow:
		ring(n, c + Vector3(0, 0, 0.1), Vector3(0, 0, 1), r * 0.82, r * 0.92, "accent")

## Колба-баллон с видимым газом.
static func _flask(n: Node3D, base: Vector3, h: float, r: float, level: float, stripes: bool = false) -> void:
	rod(n, base, base + Vector3(0, 0.05, 0), r * 1.05, "dark")
	rod(n, base + Vector3(0, h - 0.05, 0), base + Vector3(0, h, 0), r * 1.05, "dark")
	rod(n, base + Vector3(0, 0.05, 0), base + Vector3(0, h - 0.05, 0), r, "glass")
	rod(n, base + Vector3(0, 0.06, 0), base + Vector3(0, 0.06 + (h - 0.12) * level, 0), r * 0.85, "gas")
	rod(n, base + Vector3(0, h, 0), base + Vector3(0, h + 0.05, 0), r * 0.35, "chrome")
	if stripes:
		for k in 3:
			ring(n, base + Vector3(0, 0.12 + k * (h - 0.24) / 2.0, 0), Vector3.UP, r * 1.0, r * 1.08, "accent")

# ---------------------------------------------------------------- варианты

## hull — цвет металла корпуса (для concept); прозрачный — по умолчанию.
static func build(design: String, hull := Color(0, 0, 0, 0)) -> Node3D:
	var n := Node3D.new()
	n.name = design
	match design:
		"concept": _concept(n, COPPER if hull.a == 0.0 else hull)
		"concept_b": _concept(n, ALT_METAL if hull.a == 0.0 else hull)
		"clean": _clean(n, COPPER if hull.a == 0.0 else hull)
		"buddy": _buddy(n, COPPER if hull.a == 0.0 else hull)
		"h1": _h1(n)
		"h2": _h2(n, false)
		"h3": _h2(n, true)
		"pneumat": _pneumat(n)
		"geologist": _geologist(n)
		"miner": _miner(n)
		"jumper": _jumper(n)
	return n

## Н1 — только крупные формы: проверка силуэта.
static func _h1(n: Node3D) -> void:
	var s := skeleton()
	box(n, Vector3(0, 1.3, 0), Vector3(0.38, 0.4, 0.22), "hull")
	box(n, s.pelvis, Vector3(0.3, 0.14, 0.18), "dark")
	_lens_head(n, s.head, 0.13, false)
	_flask(n, Vector3(0, 1.12, -0.2), 0.52, 0.11, 0.7)
	for side in ["l", "r"]:
		caps(n, s["sh_" + side], s["el_" + side], 0.055, "hull")
		caps(n, s["el_" + side], s["ha_" + side], 0.05, "hull")
		caps(n, s["hi_" + side], s["kn_" + side], 0.07, "hull")
		caps(n, s["kn_" + side], s["an_" + side], 0.06, "hull")
	_feet(n, s)

## Н2 / Н3 — каркас с поршнями, объективом, колбой и капсулами; Н3 — пластины из
## разных материалов, манометр, модули, светящиеся швы.
static func _h2(n: Node3D, detailed: bool) -> void:
	var s := skeleton()
	# Каркас торса: позвоночник, рёбра-кольца, плечевая и тазовая балки.
	rod(n, s.pelvis, s.neck, 0.03, "dark")
	for k in 3:
		var t := ring(n, Vector3(0, 1.2 + k * 0.12, 0.0), Vector3.UP, 0.15 - k * 0.005, 0.175 - k * 0.005, "hull")
		t.scale = Vector3(1.3 - k * 0.08, 1, 0.8)
	rod(n, s.sh_l, s.sh_r, 0.035, "hull")
	box(n, s.pelvis, Vector3(0.3, 0.12, 0.17), "dark")
	# Шея и голова-объектив со сканирующим кольцом.
	rod(n, s.neck, s.head + Vector3(0, -0.08, 0), 0.03, "dark")
	_lens_head(n, s.head, 0.12, true)
	rod(n, s.head + Vector3(0.1, 0.06, -0.04), s.head + Vector3(0.14, 0.24, -0.06), 0.008, "dark")
	ball(n, s.head + Vector3(0.14, 0.25, -0.06), 0.015, "glow_warm")
	_limbs_rods(n, s, 0.028, "hull")
	# Поршни на бёдрах и плечах.
	for side in ["l", "r"]:
		var sg := -1.0 if side == "l" else 1.0
		piston(n, s["hi_" + side], s["kn_" + side], Vector3(sg * 0.045, 0, 0.04), 0.022)
		piston(n, s["sh_" + side], s["el_" + side], Vector3(sg * 0.04, 0, -0.03), 0.018)
	_feet(n, s)
	# Рюкзак: рамка, колба, капсулы образцов.
	var back := Vector3(0, 1.1, -0.19)
	rod(n, back + Vector3(-0.14, 0, 0), back + Vector3(-0.14, 0.5, 0), 0.015, "dark")
	rod(n, back + Vector3(0.14, 0, 0), back + Vector3(0.14, 0.5, 0), 0.015, "dark")
	rod(n, back + Vector3(-0.14, 0.5, 0), back + Vector3(0.14, 0.5, 0), 0.015, "dark")
	_flask(n, back + Vector3(0, 0.02, -0.03), 0.46, 0.085, 0.65, detailed)
	var pods := ["#e0a030", "#50c8ff", "#b060ff"] if not detailed else ["#e0a030", "#50c8ff", "#b060ff", "#70e070", "#ff6050", "#f0f0f0"]
	for i in pods.size():
		var sx := -0.19 if i % 2 == 0 else 0.19
		var y := 1.14 + int(i / 2) * 0.13
		var c := back + Vector3(sx, y - 1.1, -0.02)
		caps(n, c + Vector3(0, -0.04, 0), c + Vector3(0, 0.04, 0), 0.03, "glass")
		caps(n, c + Vector3(0, -0.035, 0), c + Vector3(0, 0.02, 0), 0.024, "pod:" + pods[i])
	# Шланги от колбы к плечам.
	for side in ["l", "r"]:
		var sh: Vector3 = s["sh_" + side]
		hose(n, back + Vector3(0, 0.5, -0.03), back + Vector3(0, 0.62, -0.03), sh + Vector3(0, 0.18, -0.12), sh + Vector3(0, 0.03, -0.02), 0.012)
	# Пластины: грудь (металл планеты) и наплечник (кристалл).
	plate(n, Vector3(0, 1.22, 0.13), Vector3(0, 1.42, 0.11), 0.26, 0.025, Vector3.ZERO, "copper")
	var pa := box(n, s.sh_l + Vector3(-0.03, 0.05, 0), Vector3(0.14, 0.05, 0.16), "crystal", Vector3(0, 0, 0.35))
	if not detailed:
		return
	# --- Н3: больше пластин, манометр, модули, швы.
	box(n, s.sh_r + Vector3(0.03, 0.05, 0), Vector3(0.14, 0.05, 0.16), "copper", Vector3(0, 0, -0.35))
	for side in ["l", "r"]:
		var sg2 := -1.0 if side == "l" else 1.0
		plate(n, s["el_" + side], s["ha_" + side].lerp(s["el_" + side], 0.15), 0.07, 0.02, Vector3(sg2 * 0.035, 0, 0.0), "porous")
		plate(n, s["hi_" + side].lerp(s["kn_" + side], 0.1), s["kn_" + side].lerp(s["hi_" + side], 0.15), 0.08, 0.02, Vector3(0, 0, 0.05), "copper" if side == "l" else "crystal")
		plate(n, s["kn_" + side].lerp(s["an_" + side], 0.08), s["an_" + side].lerp(s["kn_" + side], 0.25), 0.07, 0.02, Vector3(0, 0, 0.045), "hull")
		ball(n, s["kn_" + side] + Vector3(0, 0, 0.04), 0.045, "accent")
	# Светящиеся швы на груди и манометр.
	box(n, Vector3(-0.08, 1.32, 0.145), Vector3(0.01, 0.16, 0.006), "glow")
	box(n, Vector3(0.08, 1.32, 0.145), Vector3(0.01, 0.16, 0.006), "glow")
	rod(n, Vector3(0, 1.3, 0.135), Vector3(0, 1.3, 0.16), 0.045, "dark")
	rod(n, Vector3(0, 1.3, 0.16), Vector3(0, 1.3, 0.165), 0.038, "glow_warm")
	box(n, Vector3(0.012, 1.31, 0.168), Vector3(0.004, 0.03, 0.003), "dark", Vector3(0, 0, -0.6))
	# Модули: крюк-пускатель на левом предплечье, бур на правой кисти.
	var fl: Vector3 = s.el_l.lerp(s.ha_l, 0.5) + Vector3(-0.06, 0, 0.02)
	rod(n, fl + Vector3(0, 0.08, 0), fl + Vector3(0, -0.12, 0.04), 0.03, "dark")
	ring(n, fl + Vector3(0, -0.15, 0.05), Vector3(1, 0, 0), 0.03, 0.045, "accent")
	var hr: Vector3 = s.ha_r
	rod(n, hr, hr + Vector3(0.02, -0.06, 0.05), 0.04, "dark")
	rod(n, hr + Vector3(0.02, -0.06, 0.05), hr + Vector3(0.05, -0.24, 0.17), 0.045, "chrome", 0.0)
	for k in 3:
		ring(n, hr.lerp(hr + Vector3(0.05, -0.24, 0.17), 0.4 + k * 0.15), Vector3(0.15, -0.7, 0.55).normalized(), 0.03 - k * 0.008, 0.038 - k * 0.008, "accent")
	# Провода вдоль позвоночника, выпускные клапаны.
	hose(n, s.pelvis + Vector3(0.05, 0, -0.08), s.pelvis + Vector3(0.1, 0.2, -0.12), s.neck + Vector3(0.08, -0.2, -0.1), s.neck + Vector3(0.03, 0, -0.03), 0.007, "accent", 8)
	for side in [-1.0, 1.0]:
		rod(n, back + Vector3(side * 0.1, 0.05, -0.02), back + Vector3(side * 0.13, -0.05, -0.05), 0.02, "dark", 0.03)

## A «Пневмат» — механизм напоказ: два баллона, шланги к суставам, поршни на всём.
static func _pneumat(n: Node3D) -> void:
	var s := skeleton()
	rod(n, s.pelvis, s.neck, 0.035, "dark")
	ring(n, Vector3(0, 1.3, 0), Vector3.UP, 0.16, 0.19, "hull").scale = Vector3(1.25, 1, 0.8)
	rod(n, s.sh_l, s.sh_r, 0.04, "hull")
	box(n, s.pelvis, Vector3(0.3, 0.12, 0.17), "dark")
	# Голова-капсула с визорной щелью.
	caps(n, s.head + Vector3(-0.1, 0, 0), s.head + Vector3(0.1, 0, 0), 0.085, "hull")
	box(n, s.head + Vector3(0, 0.01, 0.075), Vector3(0.2, 0.03, 0.02), "glow")
	rod(n, s.neck, s.head + Vector3(0, -0.07, 0), 0.03, "dark")
	_limbs_rods(n, s, 0.026, "hull")
	for side in ["l", "r"]:
		var sg := -1.0 if side == "l" else 1.0
		piston(n, s["hi_" + side], s["kn_" + side], Vector3(sg * 0.05, 0, 0.03), 0.024)
		piston(n, s["kn_" + side], s["an_" + side], Vector3(sg * 0.045, 0, -0.03), 0.02)
		piston(n, s["sh_" + side], s["el_" + side], Vector3(sg * 0.04, 0, -0.03), 0.02)
		piston(n, s["el_" + side], s["ha_" + side], Vector3(sg * 0.035, 0, 0.02), 0.017)
	_feet(n, s)
	# Два баллона с куполами.
	for sx in [-0.09, 0.09]:
		var b := Vector3(sx, 1.1, -0.2)
		rod(n, b, b + Vector3(0, 0.45, 0), 0.075, "accent")
		ball(n, b + Vector3(0, 0.45, 0), 0.075, "accent")
		ball(n, b, 0.075, "accent")
		ring(n, b + Vector3(0, 0.22, 0), Vector3.UP, 0.075, 0.085, "dark")
	# Шланги от баллонов к локтям и коленям.
	for side in ["l", "r"]:
		var sg := -1.0 if side == "l" else 1.0
		var top := Vector3(sg * 0.09, 1.57, -0.2)
		hose(n, top, top + Vector3(sg * 0.1, 0.05, 0), s["el_" + side] + Vector3(sg * 0.12, 0.15, -0.1), s["el_" + side] + Vector3(sg * 0.03, 0, -0.03), 0.011)
		var bot := Vector3(sg * 0.09, 1.08, -0.2)
		hose(n, bot, bot + Vector3(0, -0.2, -0.05), s["kn_" + side] + Vector3(sg * 0.1, 0.2, -0.1), s["kn_" + side] + Vector3(sg * 0.03, 0, -0.03), 0.011)
	# Манометр на груди.
	rod(n, Vector3(0, 1.32, 0.13), Vector3(0, 1.32, 0.16), 0.05, "chrome")
	rod(n, Vector3(0, 1.32, 0.16), Vector3(0, 1.32, 0.166), 0.043, "glow_warm")

## B «Геолог» — стройный учёный: большой объектив, стойка с образцами, пояс.
static func _geologist(n: Node3D) -> void:
	var s := skeleton(0.92)
	caps(n, Vector3(0, 1.2, 0), Vector3(0, 1.4, 0), 0.13, "hull").scale = Vector3(1.15, 1, 0.8)
	box(n, s.pelvis, Vector3(0.26, 0.1, 0.15), "dark")
	rod(n, s.neck, s.head + Vector3(0, -0.1, 0), 0.028, "dark")
	_lens_head(n, s.head + Vector3(0, 0.02, 0), 0.155, true)
	ring(n, s.head + Vector3(0, 0.02, 0.02), Vector3(0, 0, 1), 0.17, 0.185, "glow")
	for side in ["l", "r"]:
		caps(n, s["sh_" + side], s["el_" + side], 0.035, "hull")
		caps(n, s["el_" + side], s["ha_" + side], 0.032, "hull")
		caps(n, s["hi_" + side], s["kn_" + side], 0.045, "hull")
		caps(n, s["kn_" + side], s["an_" + side], 0.04, "hull")
		for j in ["sh_", "el_", "kn_"]:
			ball(n, s[j + side], 0.045, "dark")
	_feet(n, s, Vector3(0.09, 0.05, 0.22))
	# Пояс с инструментами и пробирками.
	ring(n, s.pelvis + Vector3(0, 0.04, 0), Vector3.UP, 0.15, 0.17, "rubber").scale = Vector3(1, 1, 0.75)
	for i in 5:
		var a := -1.2 + i * 0.6
		var c: Vector3 = s.pelvis + Vector3(sin(a) * 0.17, 0.0, cos(a) * 0.13)
		if i % 2 == 0:
			box(n, c, Vector3(0.05, 0.08, 0.04), "dark")
		else:
			caps(n, c + Vector3(0, -0.04, 0), c + Vector3(0, 0.04, 0), 0.018, "pod:#70e070")
	# Стойка с капсулами образцов.
	var back := Vector3(0, 1.05, -0.17)
	box(n, back + Vector3(0, 0.28, 0), Vector3(0.32, 0.56, 0.03), "dark")
	var cols := ["#e0a030", "#50c8ff", "#b060ff", "#70e070", "#ff6050", "#f0f0f0", "#40a0a0", "#d0d060"]
	for i in cols.size():
		var c := back + Vector3(-0.11 + (i % 4) * 0.075, 0.12 + int(i / 4) * 0.22, -0.05)
		caps(n, c + Vector3(0, -0.06, 0), c + Vector3(0, 0.06, 0), 0.028, "glass")
		caps(n, c + Vector3(0, -0.055, 0), c + Vector3(0, 0.02, 0), 0.022, "pod:" + cols[i])
	rod(n, back + Vector3(0.12, 0.56, 0), back + Vector3(0.14, 0.9, 0.02), 0.007, "dark")
	ball(n, back + Vector3(0.14, 0.91, 0.02), 0.018, "glow_warm")

## D «Горняк» — широкие плечи, гаунтлеты, большой бур, фонарь, баллон в полоску.
static func _miner(n: Node3D) -> void:
	var s := skeleton(1.35)
	s.head = Vector3(0, 1.58, 0.06)
	box(n, Vector3(0, 1.3, 0.02), Vector3(0.5, 0.42, 0.3), "hull")
	box(n, Vector3(0, 1.08, 0), Vector3(0.36, 0.14, 0.24), "dark")
	box(n, s.pelvis, Vector3(0.36, 0.14, 0.2), "dark")
	box(n, s.head, Vector3(0.18, 0.13, 0.16), "hull")
	ball(n, s.head + Vector3(-0.04, 0.01, 0.08), 0.02, "glow")
	ball(n, s.head + Vector3(0.04, 0.01, 0.08), 0.02, "glow")
	rod(n, Vector3(0, 1.36, 0.17), Vector3(0, 1.36, 0.2), 0.06, "dark")
	rod(n, Vector3(0, 1.36, 0.2), Vector3(0, 1.36, 0.205), 0.05, "glow_warm")
	for side in ["l", "r"]:
		var sg := -1.0 if side == "l" else 1.0
		box(n, s["sh_" + side] + Vector3(sg * 0.03, 0.06, 0), Vector3(0.2, 0.08, 0.26), "accent", Vector3(0, 0, sg * -0.3))
		caps(n, s["sh_" + side], s["el_" + side], 0.06, "hull")
		rod(n, s["el_" + side], s["ha_" + side], 0.1, "dark", 0.085)
		caps(n, s["hi_" + side], s["kn_" + side], 0.08, "hull")
		caps(n, s["kn_" + side], s["an_" + side], 0.07, "hull")
		plate(n, s["kn_" + side].lerp(s["an_" + side], 0.05), s["an_" + side].lerp(s["kn_" + side], 0.2), 0.12, 0.03, Vector3(0, 0, 0.07), "accent")
		ball(n, s["kn_" + side] + Vector3(0, 0, 0.05), 0.07, "dark")
	_feet(n, s, Vector3(0.16, 0.08, 0.3))
	# Бур.
	var hr: Vector3 = s.ha_r
	rod(n, hr, hr + Vector3(0.03, -0.35, 0.2), 0.11, "chrome", 0.0)
	for k in 4:
		ring(n, hr.lerp(hr + Vector3(0.03, -0.35, 0.2), 0.15 + k * 0.17), Vector3(0.08, -0.87, 0.5).normalized(), 0.085 - k * 0.02, 0.1 - k * 0.02, "dark")
	# Клешня слева.
	var hl: Vector3 = s.ha_l
	box(n, hl + Vector3(-0.03, -0.08, 0.04), Vector3(0.04, 0.12, 0.06), "dark", Vector3(0.3, 0, 0.2))
	box(n, hl + Vector3(0.03, -0.08, 0.04), Vector3(0.04, 0.12, 0.06), "dark", Vector3(0.3, 0, -0.2))
	# Баллон в полоску опасности.
	var b := Vector3(0, 1.05, -0.25)
	rod(n, b, b + Vector3(0, 0.55, 0), 0.13, "dark")
	for k in 4:
		ring(n, b + Vector3(0, 0.1 + k * 0.12, 0), Vector3.UP, 0.13, 0.145, "accent")
	ball(n, b + Vector3(0, 0.55, 0), 0.13, "dark")

## E «Прыгун» — ноги с обратным коленом, пневмоцилиндры на голенях, выхлопы на бёдрах.
static func _jumper(n: Node3D) -> void:
	var s := skeleton(0.95)
	box(n, Vector3(0, 1.32, 0), Vector3(0.3, 0.3, 0.2), "hull", Vector3(0.15, 0, 0))
	box(n, Vector3(0, 1.1, -0.02), Vector3(0.2, 0.14, 0.14), "dark")
	box(n, Vector3(0, 0.98, 0), Vector3(0.28, 0.1, 0.16), "dark")
	# Голова-клин с визором.
	box(n, s.head, Vector3(0.14, 0.1, 0.22), "hull", Vector3(0.1, 0, 0))
	box(n, s.head + Vector3(0, 0.0, 0.1), Vector3(0.12, 0.025, 0.03), "glow")
	rod(n, s.neck, s.head + Vector3(0, -0.05, -0.03), 0.028, "dark")
	# Длинные руки.
	var hl := Vector3(-0.3, 0.82, 0.08)
	var hr := Vector3(0.32, 0.84, 0.14)
	for side in ["l", "r"]:
		var h: Vector3 = hl if side == "l" else hr
		rod(n, s["sh_" + side], s["el_" + side] + Vector3(0, -0.05, 0), 0.028, "hull")
		rod(n, s["el_" + side] + Vector3(0, -0.05, 0), h, 0.024, "hull")
		ball(n, s["sh_" + side], 0.05, "dark")
		ball(n, s["el_" + side] + Vector3(0, -0.05, 0), 0.04, "dark")
	# Крюк-пускатель на левой руке.
	rod(n, hl + Vector3(0, 0.1, 0), hl + Vector3(0, -0.12, 0.05), 0.035, "accent")
	ring(n, hl + Vector3(0, -0.15, 0.06), Vector3(1, 0, 0), 0.03, 0.05, "chrome")
	# Ноги с обратным коленом.
	for side in [-1.0, 1.0]:
		var hip := Vector3(side * 0.12, 0.95, 0)
		var knee := Vector3(side * 0.13, 0.62, 0.2)
		var ank := Vector3(side * 0.13, 0.26, -0.13)
		var toe := Vector3(side * 0.13, 0.03, 0.12)
		rod(n, hip, knee, 0.04, "hull")
		rod(n, knee, ank, 0.032, "hull")
		rod(n, ank, toe, 0.028, "hull")
		for j in [hip, knee, ank]:
			ball(n, j, 0.05, "dark")
		piston(n, knee, ank, Vector3(0, 0, -0.06), 0.035)
		box(n, toe + Vector3(0, -0.01, 0.03), Vector3(0.1, 0.04, 0.12), "dark")
		rod(n, ank, ank + Vector3(0, -0.22, -0.06), 0.015, "dark")
		# Выхлоп-сопло на бедре.
		var noz := hip + Vector3(side * 0.08, -0.05, -0.08)
		rod(n, noz, noz + Vector3(0, -0.1, -0.02), 0.03, "dark", 0.045)
		rod(n, noz + Vector3(0, -0.1, -0.02), noz + Vector3(0, -0.11, -0.02), 0.04, "glow_warm")
	# Небольшой баллон.
	_flask(n, Vector3(0, 1.16, -0.16), 0.34, 0.07, 0.8)

# ---------------------------------------------------------------- концепт-арт

## Поверхность-сетка по параметрам u, v ∈ [0, 1]; лицевая сторона — du × dv.
static func _surf(st: SurfaceTool, f: Callable, nu: int, nv: int, flip: bool = false) -> void:
	for i in nu:
		for j in nv:
			var p00: Vector3 = f.call(float(i) / nu, float(j) / nv)
			var p10: Vector3 = f.call(float(i + 1) / nu, float(j) / nv)
			var p11: Vector3 = f.call(float(i + 1) / nu, float(j + 1) / nv)
			var p01: Vector3 = f.call(float(i) / nu, float(j + 1) / nv)
			if flip:
				st.add_vertex(p00); st.add_vertex(p10); st.add_vertex(p11)
				st.add_vertex(p00); st.add_vertex(p11); st.add_vertex(p01)
			else:
				st.add_vertex(p00); st.add_vertex(p11); st.add_vertex(p10)
				st.add_vertex(p00); st.add_vertex(p01); st.add_vertex(p11)

## Узел с мешем, у которого локальная Y идёт вдоль axis, Z — к face.
static func _placed(p: Node3D, mesh: Mesh, c: Vector3, axis: Vector3, face: Vector3, m: String) -> MeshInstance3D:
	var y := axis.normalized()
	var z := (face - y * y.dot(face)).normalized()
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat(m)
	mi.transform = Transform3D(Basis(y.cross(z), y, z), c)
	p.add_child(mi)
	return mi

## Изогнутая накладка: кусок трубы (дуга arc радиан) вдоль a→b, обращённый к face,
## с выпуклостью посередине и сужением к концу.
static func shell(p: Node3D, a: Vector3, b: Vector3, r: float, arc: float, t: float, face: Vector3, m: String, taper: float = 1.0, bulge: float = 0.12) -> MeshInstance3D:
	var l := a.distance_to(b)
	var rad := func(v: float) -> float: return r * (1.0 + bulge * sin(PI * v)) * lerpf(1.0, taper, v)
	var pt := func(th: float, v: float, dr: float) -> Vector3:
		var rr: float = rad.call(v) + dr
		return Vector3(sin(th) * rr, v * l, cos(th) * rr)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(1)
	_surf(st, func(u, v): return pt.call((u - 0.5) * arc, v, t), 12, 8)
	st.set_smooth_group(2)
	_surf(st, func(u, v): return pt.call((0.5 - u) * arc, v, 0.0), 12, 8)
	st.set_smooth_group(0xFFFFFFFF)
	_surf(st, func(u, v): return pt.call(arc / 2.0, v, t * (1.0 - u)), 1, 8)
	_surf(st, func(u, v): return pt.call(-arc / 2.0, v, t * u), 1, 8)
	_surf(st, func(u, v): return pt.call((u - 0.5) * arc, 0.0, t * v), 12, 1)
	_surf(st, func(u, v): return pt.call((u - 0.5) * arc, 1.0, t * (1.0 - v)), 12, 1)
	st.generate_normals()
	return _placed(p, st.commit(), a, b - a, face, m)

## Точёная деталь: профиль (радиус, высота) снизу вверх, вращённый вокруг axis.
static func lathe(p: Node3D, c: Vector3, axis: Vector3, profile: Array, m: String, seg: int = 20, face := Vector3.BACK) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var np := profile.size() - 1
	for j in np:
		st.set_smooth_group(1)
		var q0: Vector2 = profile[j]
		var q1: Vector2 = profile[j + 1]
		_surf(st, func(u, v):
			var q := q0.lerp(q1, v)
			return Vector3(sin(u * TAU) * q.x, q.y, cos(u * TAU) * q.x), seg, 1)
	st.generate_normals()
	if abs(axis.normalized().dot(face.normalized())) > 0.95:
		face = Vector3.UP if abs(axis.normalized().y) < 0.95 else Vector3.BACK
	return _placed(p, st.commit(), c, axis, face, m)

## Сплюснутый шар с полуосями-векторами ax, ay, az.
static func ellipsoid(p: Node3D, c: Vector3, ax: Vector3, ay: Vector3, az: Vector3, m: String) -> MeshInstance3D:
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = 18
	sm.rings = 9
	var mi := MeshInstance3D.new()
	mi.mesh = sm
	mi.material_override = mat(m)
	mi.transform = Transform3D(Basis(ax, ay, az), c)
	p.add_child(mi)
	return mi

## Диск со скруглённым краем (позвонок, гофра).
static func disc(p: Node3D, c: Vector3, axis: Vector3, r: float, h: float, m: String) -> MeshInstance3D:
	return lathe(p, c, axis, [Vector2(0, -h / 2), Vector2(r * 0.8, -h / 2), Vector2(r, -h / 4), Vector2(r, h / 4), Vector2(r * 0.8, h / 2), Vector2(0, h / 2)], m, 16)

## Кисть с фалангами: ладонь, четыре пальца по три фаланги и большой палец.
## dn — вниз вдоль кисти, side — к ладонной стороне.
static func hand(p: Node3D, wrist: Vector3, dn: Vector3, side: Vector3, hull: String, k: float = 1.0) -> void:
	if k != 1.0:
		var h := Node3D.new()
		h.position = wrist
		h.scale = Vector3.ONE * k
		p.add_child(h)
		p = h
		wrist = Vector3.ZERO
	dn = dn.normalized()
	side = (side - dn * dn.dot(side)).normalized()
	var fw := dn.cross(side).normalized()
	if fw.z < 0.0:
		fw = -fw
	var pc := wrist + dn * 0.04
	ellipsoid(p, pc, side * 0.016, dn * 0.036, fw * 0.03, "dark")
	ellipsoid(p, pc - side * 0.009 + dn * 0.004, side * 0.009, dn * 0.03, fw * 0.03, hull)
	var lens := [0.85, 1.0, 0.95, 0.78]
	for i in 4:
		var fk: float = lens[i]
		var q := pc + dn * 0.032 + fw * (-0.024 + i * 0.016)
		ball(p, q, 0.0085, "dark")
		var spread := fw * (i - 1.5) * 0.06
		var curl := 0.25
		for sl in [0.026, 0.019, 0.015]:
			var d := (dn * cos(curl) + side * sin(curl) + spread).normalized()
			var q2: Vector3 = q + d * sl * fk
			rod(p, q, q2, 0.0062, "steel")
			ball(p, q2, 0.0072, "dark")
			q = q2
			curl += 0.3
	# Большой палец: отходит вперёд и к ладони.
	var tq := pc + fw * 0.026 - dn * 0.012 + side * 0.006
	ball(p, tq, 0.009, "dark")
	var tc := 0.2
	for sl in [0.024, 0.018, 0.014]:
		var d := (dn * 0.7 + fw * 0.45 * cos(tc) + side * (0.3 + sin(tc))).normalized()
		var t2: Vector3 = tq + d * sl
		rod(p, tq, t2, 0.0068, "steel")
		ball(p, t2, 0.0076, "dark")
		tq = t2
		tc += 0.35

## Точка крепления для игры: модуль, пластина, уровень газа.
static func _socket(n: Node3D, sname: String, pos: Vector3) -> void:
	var m := Marker3D.new()
	m.name = sname
	m.position = pos
	n.add_child(m)

## Плоская скошенная пластина: вдоль +Y длиной l, ширина w0 у основания и w1 у
## конца, толщина t, конец сдвинут по X на skew.
static func blade(p: Node3D, l: float, w0: float, w1: float, t: float, skew: float, m: String) -> MeshInstance3D:
	var b := [Vector3(-w0 / 2, 0, -t / 2), Vector3(w0 / 2, 0, -t / 2), Vector3(w0 / 2, 0, t / 2), Vector3(-w0 / 2, 0, t / 2)]
	var u := [Vector3(-w1 / 2 + skew, l, -t / 2), Vector3(w1 / 2 + skew, l, -t / 2), Vector3(w1 / 2 + skew, l, t / 2), Vector3(-w1 / 2 + skew, l, t / 2)]
	var faces := [[u[3], u[2], b[2], b[3]], [u[1], u[0], b[0], b[1]], [u[2], u[1], b[1], b[2]],
		[u[0], u[3], b[3], b[0]], [u[0], u[1], u[2], u[3]], [b[3], b[2], b[1], b[0]]]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(0xFFFFFFFF)   # плоские грани, без сглаживания рёбер
	for f in faces:
		for k in [0, 1, 2, 0, 2, 3]:
			st.add_vertex(f[k])
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat(m)
	p.add_child(mi)
	return mi

## Антенна-«ухо»: узел-шарнир (поворачивается в игре) и плоская пластина по
## диагонали вверх-назад-наружу, плоскостью поперёк объектива, со светящимся
## передним ребром.
static func _ear(n: Node3D, pivot: Vector3, sg: float, hull: String, k: float = 1.0) -> Node3D:
	var e := Node3D.new()
	e.name = "ear_l" if sg < 0.0 else "ear_r"
	var y := Vector3(sg * 0.62, 0.74, -0.26).normalized()
	# Плоскость пластины перпендикулярна объективу: ширина — вперёд, толщина — вбок.
	var x := (Vector3.BACK - y * y.dot(Vector3.BACK)).normalized()
	e.transform = Transform3D(Basis(x, y, x.cross(y).normalized()).scaled(Vector3.ONE * k), pivot)
	n.add_child(e)
	ball(e, Vector3.ZERO, 0.022, "dark")
	ring(e, Vector3(0, 0.01, 0), Vector3.UP, 0.02, 0.03, hull)
	var l := 0.21
	var w0 := 0.09
	var w1 := 0.05
	blade(e, l, w0, w1, 0.012, (w0 - w1) / 2.0, "dark")
	blade(e, l * 0.35, w0 * 1.05, w0 * 0.9, 0.016, 0.0, hull)
	for z in [-0.0075, 0.0075]:
		box(e, Vector3(w0 / 2.0 - 0.006, l * 0.62, z), Vector3(0.008, l * 0.7, 0.003), "glow")
	return e

## Короб с фаской: 6 граней, 12 скосов по рёбрам, 8 уголков — плоские грани
## ловят блик и дают чёткую линию.
static func _rbox_mesh(size: Vector3, b: float) -> ArrayMesh:
	var h := size / 2.0
	b = minf(b, minf(h.x, minf(h.y, h.z)) * 0.9)
	var tris := []
	for ax in 3:
		var a1 := (ax + 1) % 3
		var a2 := (ax + 2) % 3
		for sgn in [-1.0, 1.0]:
			var q := []
			for s1 in [-1.0, 1.0]:
				for s2 in [-1.0, 1.0]:
					var v := Vector3.ZERO
					v[ax] = sgn * h[ax]
					v[a1] = s1 * (h[a1] - b)
					v[a2] = s2 * (h[a2] - b)
					q.append(v)
			tris.append([q[0], q[1], q[3]])
			tris.append([q[0], q[3], q[2]])
	for a3 in 3:
		var a1 := (a3 + 1) % 3
		var a2 := (a3 + 2) % 3
		for s1 in [-1.0, 1.0]:
			for s2 in [-1.0, 1.0]:
				var q := []
				for s3 in [-1.0, 1.0]:
					var v1 := Vector3.ZERO
					v1[a1] = s1 * h[a1]
					v1[a2] = s2 * (h[a2] - b)
					v1[a3] = s3 * (h[a3] - b)
					var v2 := Vector3.ZERO
					v2[a1] = s1 * (h[a1] - b)
					v2[a2] = s2 * h[a2]
					v2[a3] = s3 * (h[a3] - b)
					q.append(v1)
					q.append(v2)
				tris.append([q[0], q[2], q[3]])
				tris.append([q[0], q[3], q[1]])
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				tris.append([Vector3(sx * h.x, sy * (h.y - b), sz * (h.z - b)),
					Vector3(sx * (h.x - b), sy * h.y, sz * (h.z - b)),
					Vector3(sx * (h.x - b), sy * (h.y - b), sz * h.z)])
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(0xFFFFFFFF)
	for t in tris:
		var a: Vector3 = t[0]
		var bb: Vector3 = t[1]
		var c: Vector3 = t[2]
		# Тело выпуклое и с центром в нуле: лицевая сторона — наружу.
		if (c - a).cross(bb - a).dot(a + bb + c) < 0.0:
			var tmp := bb
			bb = c
			c = tmp
		st.add_vertex(a)
		st.add_vertex(bb)
		st.add_vertex(c)
	st.generate_normals()
	return st.commit()

static func rbox(p: Node3D, c: Vector3, size: Vector3, bevel: float, m: String, basis := Basis()) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _rbox_mesh(size, bevel)
	mi.material_override = mat(m)
	mi.transform = Transform3D(basis, c)
	p.add_child(mi)
	return mi

## Короб с фаской вдоль кости a→b: ширина w, глубина d (к face).
static func rbox_along(p: Node3D, a: Vector3, b: Vector3, w: float, d: float, bevel: float, face: Vector3, m: String) -> MeshInstance3D:
	return _placed(p, _rbox_mesh(Vector3(w, a.distance_to(b), d), bevel), (a + b) / 2.0, b - a, face, m)

## Голова-объектив с антеннами-ушами в своём узле head (наклон — поворот узла).
## r — радиус объектива; shell_m — корпус головы, trim_m — ободки.
static func _head(p: Node3D, pos: Vector3, r: float, shell_m: String, trim_m: String, tilt := Vector3.ZERO) -> Node3D:
	var hd := Node3D.new()
	hd.name = "head"
	hd.position = pos
	hd.rotation = tilt
	p.add_child(hd)
	var k := r / 0.15
	rod(hd, Vector3(0, 0, -0.08) * k, Vector3(0, 0, 0.07) * k, 0.15 * k, shell_m)
	ball(hd, Vector3(0, 0, -0.08) * k, 0.15 * k, shell_m).scale = Vector3(1, 1, 0.55)
	ring(hd, Vector3(0, 0, -0.02) * k, Vector3(0, 0, 1), 0.15 * k, 0.162 * k, "dark")
	ring(hd, Vector3(0, 0, 0.07) * k, Vector3(0, 0, 1), 0.122 * k, 0.158 * k, trim_m)
	rod(hd, Vector3(0, 0, 0.07) * k, Vector3(0, 0, 0.088) * k, 0.126 * k, "dark")
	ring(hd, Vector3(0, 0, 0.09) * k, Vector3(0, 0, 1), 0.084 * k, 0.1 * k, "accent")
	rod(hd, Vector3(0, 0, 0.088) * k, Vector3(0, 0, 0.097) * k, 0.056 * k, "iris")
	rod(hd, Vector3(0, 0, 0.097) * k, Vector3(0, 0, 0.101) * k, 0.022 * k, "dark")
	ball(hd, Vector3(0, 0, 0.09) * k, 0.084 * k, "glass").scale = Vector3(1, 1, 0.3)
	for sg in [-1.0, 1.0]:
		_ear(hd, Vector3(sg * 0.125, 0.085, -0.03) * k, sg, trim_m, k)
	return hd

## Колба на ремнях и кассета капсул под ней; r — радиус стекла. Возвращает точку
## над клапаном (для шлангов).
static func _flask_pack(n: Node3D, fb: Vector3, fh: float, r: float, hull: String) -> Vector3:
	var k := r / 0.115
	rod(n, fb, fb + Vector3(0, 0.05 * k, 0), 0.122 * k, hull)
	rod(n, fb + Vector3(0, 0.05 * k, 0), fb + Vector3(0, fh - 0.05 * k, 0), 0.115 * k, "glass")
	rod(n, fb + Vector3(0, 0.06 * k, 0), fb + Vector3(0, 0.06 * k + (fh - 0.12 * k) * 0.8, 0), 0.1 * k, "gas")
	rod(n, fb + Vector3(0, fh - 0.05 * k, 0), fb + Vector3(0, fh, 0), 0.122 * k, hull)
	rod(n, fb + Vector3(0, fh, 0), fb + Vector3(0, fh + 0.04 * k, 0), 0.03 * k, "steel")
	ball(n, fb + Vector3(0, fh + 0.045 * k, 0), 0.028 * k, hull)
	for t in [0.15, 0.3]:
		ring(n, fb + Vector3(0, fh * t / 0.45 + 0.05 * k, 0), Vector3.UP, 0.115 * k, 0.132 * k, hull)
	var pc2 := fb + Vector3(0, -0.08 * k, 0)
	for y in [0.052, -0.052]:
		caps(n, pc2 + Vector3(-0.115, y, 0.02) * k, pc2 + Vector3(0.115, y, 0.02) * k, 0.011 * k, "dark")
	var pods := ["#e8c547", "#9b5de5", "#e05a4a", "#5ad17a"]
	for i in pods.size():
		var c := pc2 + Vector3(-0.09 + i * 0.06, 0, -0.005) * k
		caps(n, c + Vector3(0, -0.035, 0) * k, c + Vector3(0, 0.035, 0) * k, 0.026 * k, "glass")
		caps(n, c + Vector3(0, -0.03, 0) * k, c + Vector3(0, 0.02, 0) * k, 0.02 * k, "pod:" + pods[i])
		for y in [0.052, -0.052]:
			ring(n, c + Vector3(0, y, 0) * k, Vector3.UP, 0.026 * k, 0.034 * k, hull)
	_socket(n, "socket_flask", fb + Vector3(0, fh / 2.0, 0))
	_socket(n, "socket_pods", pc2)
	return fb + Vector3(0, fh + 0.045 * k, 0)

## По концепт-арту: голова-объектив с антеннами-ушами, тонкий каркас с открытым
## позвоночником, шарниры-шары с бандажами, колба за правым плечом, под ней кассета
## капсул, тяжёлые ботинки. hull — металл корпуса (медь по умолчанию).
static func _concept(n: Node3D, hull_col: Color) -> void:
	var hull := "metal:#" + hull_col.to_html(false)
	var s := skeleton()
	s.el_l = Vector3(-0.28, 1.17, -0.03)
	s.el_r = Vector3(0.29, 1.18, 0.02)
	s.ha_l = Vector3(-0.29, 0.91, 0.03)
	s.ha_r = Vector3(0.31, 0.93, 0.1)
	var hc := Vector3(0, 1.68, 0.02)
	# --- Голова-объектив.
	_head(n, hc, 0.15, hull, hull)
	# --- Шея.
	rod(n, Vector3(0, 1.42, -0.01), hc + Vector3(0, -0.12, -0.02), 0.026, "dark")
	ring(n, Vector3(0, 1.5, -0.01), Vector3.UP, 0.028, 0.042, hull)
	for sg in [-1.0, 1.0]:
		hose(n, Vector3(sg * 0.05, 1.4, -0.05), Vector3(sg * 0.07, 1.48, -0.08), hc + Vector3(sg * 0.06, -0.2, -0.08), hc + Vector3(sg * 0.05, -0.13, -0.06), 0.01, "rubber", 6)
	# --- Позвоночник: хромированный стержень и позвонки.
	rod(n, s.pelvis + Vector3(0, 0, -0.03), Vector3(0, 1.45, -0.03), 0.018, "steel")
	for k in 15:
		var y := 1.0 + k * 0.032
		var wide := k % 2 == 0
		disc(n, Vector3(0, y, -0.03 - sin(k * 0.2) * 0.012), Vector3.UP, (0.036 if wide else 0.027) - k * 0.0006, 0.022 if wide else 0.014, hull if wide else "dark")
	# Грудная клетка: рёбра, грудные пластины, механизм в центре.
	for k in 3:
		ring(n, Vector3(0, 1.22 + k * 0.08, 0.0), Vector3.UP, 0.125 + k * 0.005, 0.138 + k * 0.005, "dark").scale = Vector3(1.25, 1, 0.8)
	# Выпуклый грудной щиток — кусок сферы, в центре механизм-шестерня.
	var dome := []
	for k in 7:
		var al := 0.62 * (1.0 - k / 6.0)
		dome.append(Vector2(0.17 * sin(al), 0.17 * cos(al) - 0.17 * cos(0.62)))
	dome.push_front(Vector2(0, 0))
	lathe(n, Vector3(0, 1.33, 0.09), Vector3.BACK, dome, hull).scale = Vector3(1.3, 0.8, 0.85)   # ширина, глубина, высота
	ring(n, Vector3(0, 1.33, 0.125), Vector3(0, 0, 1), 0.026, 0.044, "dark")
	for k in 8:
		var ga := k * TAU / 8.0
		box(n, Vector3(cos(ga) * 0.047, 1.33 + sin(ga) * 0.047, 0.125), Vector3(0.012, 0.012, 0.012), "dark", Vector3(0, 0, ga))
	ball(n, Vector3(0, 1.33, 0.13), 0.022, "steel")
	for sg in [-1.0, 1.0]:
		shell(n, Vector3(sg * 0.2, 1.47, 0.0), Vector3(sg * 0.07, 1.46, 0.02), 0.045, 2.4, 0.012, Vector3(0, 1, 0.3), hull, 0.9)
	rod(n, s.sh_l, s.sh_r, 0.03, hull)
	# Поясница — гофра.
	for k in 4:
		disc(n, Vector3(0, 1.05 + k * 0.022, -0.01), Vector3.UP, 0.05 - abs(k - 1.5) * 0.006, 0.016, "dark" if k % 2 else "rubber")
	# Таз — чаша с поясом, спереди изогнутый щиток.
	lathe(n, s.pelvis, Vector3.UP, [Vector2(0, -0.06), Vector2(0.06, -0.058), Vector2(0.1, -0.035), Vector2(0.118, 0.0), Vector2(0.12, 0.03), Vector2(0.1, 0.045), Vector2(0, 0.05)], "dark").scale = Vector3(1.15, 1.0, 0.8)
	ring(n, s.pelvis + Vector3(0, 0.025, 0), Vector3.UP, 0.13, 0.143, hull).scale = Vector3(1.05, 1.0, 0.78)
	shell(n, s.pelvis + Vector3(0, -0.05, 0), s.pelvis + Vector3(0, 0.02, 0), 0.105, 2.0, 0.012, Vector3.BACK, hull, 1.08, 0.0)
	# --- Конечности: хромированные кости, шары с бандажами, пластины корпуса.
	for side in ["l", "r"]:
		var sg: float = -1.0 if side == "l" else 1.0
		var sh: Vector3 = s["sh_" + side]
		var el: Vector3 = s["el_" + side]
		var ha: Vector3 = s["ha_" + side]
		var hi: Vector3 = s["hi_" + side]
		var kn: Vector3 = s["kn_" + side]
		var an: Vector3 = s["an_" + side]
		rod(n, sh, el, 0.03, "steel")
		rod(n, el, ha, 0.026, "steel")
		rod(n, hi, kn, 0.036, "steel")
		rod(n, kn, an, 0.031, "steel")
		for j in [[sh, 0.056], [el, 0.045], [hi, 0.05], [kn, 0.055], [an, 0.042]]:
			var jp: Vector3 = j[0]
			var jr: float = j[1]
			ball(n, jp, jr, "steel")
			ring(n, jp, Vector3(1, 0, 0), jr * 0.85, jr * 1.08, hull)
		# Изогнутые накладки корпуса и бандажи на открытых костях.
		shell(n, sh.lerp(el, 0.18), sh.lerp(el, 0.82), 0.042, 2.6, 0.01, Vector3(sg, 0, -0.2), hull, 0.85)
		shell(n, el.lerp(ha, 0.2), el.lerp(ha, 0.72), 0.038, 2.3, 0.009, Vector3(sg, 0, 0.3), hull, 0.8)
		shell(n, hi.lerp(kn, 0.12), hi.lerp(kn, 0.8), 0.05, 2.9, 0.011, Vector3(sg * 0.25, 0, 1), hull, 0.8)
		shell(n, kn.lerp(an, 0.15), kn.lerp(an, 0.6), 0.044, 2.2, 0.009, Vector3(0, 0, -1), hull, 0.75, 0.2)
		for bone in [[el, ha, 0.03, 0.85], [kn, an, 0.036, 0.78]]:
			var a: Vector3 = bone[0]
			var b: Vector3 = bone[1]
			var r: float = bone[2]
			ring(n, a.lerp(b, bone[3]), (b - a).normalized(), r, r + 0.012, hull)
		ball(n, kn + Vector3(0, 0, 0.05), 0.03, hull)
		piston(n, kn, an, Vector3(0, 0, 0.055), 0.022)
		piston(n, el, ha, Vector3(0, 0, 0.04), 0.016)
		# Кисть: ладонь и пальцы.
		ring(n, ha, (ha - el).normalized(), 0.026, 0.038, hull)
		hand(n, ha, (ha - el).normalized() + Vector3(0, -0.6, 0), Vector3(-sg, 0, 0), hull)
		# Шланг по ноге: от таза к колену снаружи.
		hose(n, hi + Vector3(sg * 0.06, 0.02, -0.05), hi + Vector3(sg * 0.12, -0.15, -0.08), kn + Vector3(sg * 0.1, 0.15, -0.06), kn + Vector3(sg * 0.05, 0.02, -0.03), 0.011, "rubber", 8)
		# Ботинок.
		var bz := an.z + 0.05
		ellipsoid(n, Vector3(an.x, 0.02, bz), Vector3(0.068, 0, 0), Vector3(0, 0.022, 0), Vector3(0, 0, 0.14), "dark")
		ellipsoid(n, Vector3(an.x, 0.06, bz - 0.01), Vector3(0.06, 0, 0), Vector3(0, 0.05, 0), Vector3(0, 0, 0.11), hull)
		ellipsoid(n, Vector3(an.x, 0.05, bz + 0.075), Vector3(0.063, 0, 0), Vector3(0, 0.042, 0), Vector3(0, 0, 0.06), hull)
		ring(n, Vector3(an.x, 0.055, bz + 0.05), Vector3(0, 0.3, 1), 0.052, 0.06, "dark")
		rod(n, Vector3(an.x, 0.005, bz - 0.08), Vector3(an.x, 0.085, bz - 0.08), 0.045, "dark")
		ring(n, Vector3(an.x, 0.12, an.z), Vector3.UP, 0.045, 0.062, hull)
	# --- Колба за правым плечом на ремнях, под ней кассета капсул.
	var fb := Vector3(0.14, 1.1, -0.22)
	var fh := 0.5
	var top := _flask_pack(n, fb, fh, 0.115, hull)
	for y in [1.25, 1.4]:
		rod(n, Vector3(0.02, y, -0.06), Vector3(0.12, y, -0.2), 0.012, hull)
	# Шланги от колбы: к затылку, к обоим плечам, к правому бедру.
	hose(n, top, top + Vector3(0, 0.12, 0), hc + Vector3(0.05, -0.02, -0.24), hc + Vector3(0.02, -0.06, -0.12), 0.012)
	hose(n, fb + Vector3(-0.06, fh - 0.02, -0.03), fb + Vector3(-0.18, fh + 0.08, -0.02), s.sh_l + Vector3(0.1, 0.12, -0.12), s.sh_l + Vector3(0.02, 0.03, -0.04), 0.011)
	hose(n, fb + Vector3(0.07, fh - 0.03, 0.0), fb + Vector3(0.14, fh + 0.03, 0.0), s.sh_r + Vector3(0.06, 0.1, -0.1), s.sh_r + Vector3(0.0, 0.03, -0.04), 0.011)
	hose(n, fb + Vector3(0.07, 0.02, 0.0), fb + Vector3(0.12, -0.2, 0.0), s.hi_r + Vector3(0.12, 0.1, -0.12), s.hi_r + Vector3(0.05, 0.0, -0.04), 0.011)
	# --- Точки крепления.
	_socket(n, "socket_hand_l", s.ha_l + Vector3(0, -0.1, 0))
	_socket(n, "socket_hand_r", s.ha_r + Vector3(0, -0.1, 0))
	_socket(n, "socket_plate_chest", Vector3(0, 1.33, 0.12))
	_socket(n, "socket_plate_sh_l", s.sh_l + Vector3(-0.02, 0.06, 0))
	_socket(n, "socket_plate_sh_r", s.sh_r + Vector3(0.02, 0.06, 0))
	_socket(n, "socket_plate_thigh_l", s.hi_l.lerp(s.kn_l, 0.5) + Vector3(0, 0, 0.06))
	_socket(n, "socket_plate_thigh_r", s.hi_r.lerp(s.kn_r, 0.5) + Vector3(0, 0, 0.06))

# ---------------------------------------------------------------- чистые варианты

## Светлая краска корпуса из металла планеты и сам металл — акцентом.
static func _scheme(hull_col: Color) -> Array:
	var paint := hull_col.lerp(Color(0.86, 0.84, 0.8), 0.55).darkened(0.08)
	return ["paint:#" + paint.to_html(false), "metal:#" + hull_col.to_html(false)]

## «Хард-серфейс»: крупные гладкие панели с фасками, кираса, массивные
## предплечья и голени, тёмная механика, медь — акцентом; поза с контрапостом.
static func _clean(n: Node3D, hull_col: Color) -> void:
	var sc := _scheme(hull_col)
	var paint: String = sc[0]
	var metal: String = sc[1]
	# Вес на левой ноге: левое бедро выше, левое плечо ниже, правое колено согнуто.
	var s := {
		"pelvis": Vector3(0, 0.93, 0),
		"sh_l": Vector3(-0.24, 1.43, 0), "sh_r": Vector3(0.24, 1.455, 0),
		"el_l": Vector3(-0.3, 1.17, -0.04), "el_r": Vector3(0.31, 1.19, -0.02),
		"ha_l": Vector3(-0.31, 0.94, 0.05), "ha_r": Vector3(0.33, 0.97, 0.09),
		"hi_l": Vector3(-0.11, 0.93, 0), "hi_r": Vector3(0.11, 0.91, 0),
		"kn_l": Vector3(-0.12, 0.5, 0.04), "kn_r": Vector3(0.14, 0.49, 0.1),
		"an_l": Vector3(-0.13, 0.09, 0.0), "an_r": Vector3(0.18, 0.09, 0.07),
	}
	var tilt := Basis(Vector3.BACK, 0.05)
	# --- Голова: наклон вбок и чуть вниз — «присматривается».
	var hc := Vector3(0.0, 1.63, 0.03)
	_head(n, hc, 0.14, paint, metal, Vector3(-0.08, 0.12, 0.12))
	rod(n, Vector3(0, 1.44, -0.01), hc + Vector3(0, -0.1, -0.02), 0.03, "dark")
	disc(n, Vector3(0, 1.475, -0.01), Vector3.UP, 0.07, 0.035, "dark")
	# --- Кираса: грудь с фаской, медная полоса, светящиеся щели.
	# Верх шире низа — «героический» клин.
	rbox(n, Vector3(0, 1.37, 0), Vector3(0.39, 0.18, 0.25), 0.045, paint, tilt)
	rbox(n, Vector3(0, 1.235, 0.005), Vector3(0.29, 0.12, 0.21), 0.035, paint, tilt)
	rbox(n, Vector3(0, 1.31, 0.121), Vector3(0.05, 0.24, 0.03), 0.01, metal, tilt)
	for sg in [-1.0, 1.0]:
		rbox(n, Vector3(sg * 0.105, 1.41 + sg * 0.005, 0.126), Vector3(0.09, 0.013, 0.01), 0.003, "glow", tilt)
	# Живот, поясница-гофра, таз.
	rbox(n, Vector3(0, 1.145, -0.005), Vector3(0.18, 0.06, 0.14), 0.02, "dark")
	for k in 3:
		disc(n, Vector3(0, 1.07 + k * 0.022, -0.01), Vector3.UP, 0.055, 0.017, "rubber" if k % 2 else "dark")
	var pb := Basis(Vector3.BACK, -0.04)
	rbox(n, s.pelvis + Vector3(0, 0.02, 0), Vector3(0.27, 0.1, 0.17), 0.03, "dark", pb)
	rbox(n, s.pelvis + Vector3(0, 0.01, 0.09), Vector3(0.16, 0.075, 0.03), 0.012, paint, pb * Basis(Vector3.RIGHT, -0.2))
	# --- Руки и ноги.
	for side in ["l", "r"]:
		var sg: float = -1.0 if side == "l" else 1.0
		var sh: Vector3 = s["sh_" + side]
		var el: Vector3 = s["el_" + side]
		var ha: Vector3 = s["ha_" + side]
		var hi: Vector3 = s["hi_" + side]
		var kn: Vector3 = s["kn_" + side]
		var an: Vector3 = s["an_" + side]
		# Наплечник с фаской.
		rbox(n, sh + Vector3(sg * 0.025, 0.05, 0), Vector3(0.13, 0.065, 0.16), 0.025, paint, Basis(Vector3.BACK, -sg * 0.35))
		ball(n, sh, 0.05, "dark")
		rod(n, sh, el, 0.034, "dark")
		piston(n, sh, el, Vector3(sg * 0.04, 0, -0.025), 0.017)
		ball(n, el, 0.042, "dark")
		# Предплечье — массивный щиток с медным бандажом у запястья.
		rbox_along(n, el.lerp(ha, 0.12), el.lerp(ha, 0.8), 0.085, 0.095, 0.022, Vector3(sg * 0.3, 0, 1), paint)
		rbox_along(n, el.lerp(ha, 0.8), el.lerp(ha, 0.9), 0.09, 0.1, 0.012, Vector3(sg * 0.3, 0, 1), metal)
		ball(n, ha, 0.03, "dark")
		hand(n, ha, (ha - el).normalized() + Vector3(0, -0.6, 0), Vector3(-sg, 0, 0), paint, 1.25)
		# Бедро — тёмная кость с поршнем, колено — щиток.
		ball(n, hi, 0.05, "dark")
		rod(n, hi, kn, 0.038, "dark")
		piston(n, hi, kn, Vector3(sg * 0.055, 0, -0.02), 0.02)
		rbox_along(n, hi.lerp(kn, 0.14), hi.lerp(kn, 0.72), 0.09, 0.1, 0.024, Vector3(sg * 0.2, 0, 1), paint)
		ball(n, kn, 0.046, "dark")
		rbox(n, kn + Vector3(0, 0.015, 0.05), Vector3(0.085, 0.1, 0.05), 0.018, paint, Basis(Vector3.RIGHT, -0.2))
		# Голень — щиток с медным бандажом, поршень сзади.
		rbox_along(n, kn.lerp(an, 0.14), kn.lerp(an, 0.86), 0.1, 0.12, 0.026, Vector3.BACK, paint)
		rbox_along(n, kn.lerp(an, 0.2), kn.lerp(an, 0.27), 0.106, 0.126, 0.012, Vector3.BACK, metal)
		piston(n, kn, an, Vector3(0, 0, -0.07), 0.02)
		ball(n, an, 0.038, "dark")
		# Ступня: корпус, подошва, скошенный носок; правая развёрнута наружу.
		var fbas := Basis(Vector3.UP, 0.0 if side == "l" else 0.28)
		var fc := Vector3(an.x, 0, an.z)
		rbox(n, fc + fbas * Vector3(0, 0.017, 0.05), Vector3(0.14, 0.034, 0.27), 0.012, "dark", fbas)
		rbox(n, fc + fbas * Vector3(0, 0.06, 0.02), Vector3(0.13, 0.07, 0.19), 0.025, paint, fbas)
		rbox(n, fc + fbas * Vector3(0, 0.05, 0.14), Vector3(0.125, 0.05, 0.08), 0.02, paint, fbas * Basis(Vector3.RIGHT, 0.3))
	# --- Колба за правым плечом, два шланга.
	var fb := Vector3(0.15, 1.13, -0.24)
	var fh := 0.46
	var top := _flask_pack(n, fb, fh, 0.105, metal)
	for y in [1.26, 1.4]:
		rod(n, Vector3(0.04, y, -0.1), Vector3(0.13, y, -0.22), 0.013, "dark")
	hose(n, fb + Vector3(-0.06, fh - 0.02, -0.02), fb + Vector3(-0.18, fh + 0.08, -0.02), s.sh_l + Vector3(0.1, 0.12, -0.12), s.sh_l + Vector3(0.02, 0.03, -0.05), 0.013)
	hose(n, top, top + Vector3(0.02, 0.1, 0.0), s.sh_r + Vector3(0.04, 0.14, -0.12), s.sh_r + Vector3(0.0, 0.04, -0.05), 0.013)
	_socket(n, "socket_hand_l", s.ha_l + Vector3(0, -0.12, 0))
	_socket(n, "socket_hand_r", s.ha_r + Vector3(0, -0.12, 0))
	_socket(n, "socket_plate_chest", Vector3(0, 1.33, 0.13))
	_socket(n, "socket_plate_sh_l", s.sh_l + Vector3(-0.03, 0.09, 0))
	_socket(n, "socket_plate_sh_r", s.sh_r + Vector3(0.03, 0.09, 0))
	_socket(n, "socket_plate_thigh_l", s.hi_l.lerp(s.kn_l, 0.5) + Vector3(0, 0, 0.05))
	_socket(n, "socket_plate_thigh_r", s.hi_r.lerp(s.kn_r, 0.5) + Vector3(0, 0, 0.05))

## «Компаньон»: коренастый, торс-яйцо, крупная голова на плечах, короткие толстые
## конечности, крупные кисти и ступни.
static func _buddy(n: Node3D, hull_col: Color) -> void:
	var sc := _scheme(hull_col)
	var paint: String = sc[0]
	var metal: String = sc[1]
	var s := {
		"pelvis": Vector3(0, 0.63, 0),
		"sh_l": Vector3(-0.22, 1.0, 0), "sh_r": Vector3(0.22, 1.01, 0),
		"el_l": Vector3(-0.29, 0.83, 0.02), "el_r": Vector3(0.3, 0.84, 0.05),
		"ha_l": Vector3(-0.3, 0.69, 0.09), "ha_r": Vector3(0.31, 0.71, 0.13),
		"hi_l": Vector3(-0.1, 0.62, 0), "hi_r": Vector3(0.1, 0.61, 0),
		"kn_l": Vector3(-0.11, 0.36, 0.04), "kn_r": Vector3(0.12, 0.36, 0.08),
		"an_l": Vector3(-0.12, 0.1, 0.0), "an_r": Vector3(0.14, 0.1, 0.05),
	}
	# --- Голова крупная, посажена на плечи.
	var hc := Vector3(0, 1.25, 0.03)
	_head(n, hc, 0.19, paint, metal, Vector3(-0.06, -0.1, -0.14))
	disc(n, Vector3(0, 1.07, 0), Vector3.UP, 0.075, 0.05, "dark")
	# --- Торс-яйцо, тёмный пояс, «сердце» с подсветкой.
	var egg := [Vector2(0, -0.2), Vector2(0.1, -0.19), Vector2(0.16, -0.14), Vector2(0.19, -0.05),
		Vector2(0.19, 0.05), Vector2(0.165, 0.13), Vector2(0.11, 0.19), Vector2(0, 0.215)]
	lathe(n, Vector3(0, 0.86, 0), Vector3.UP, egg, paint, 24).scale = Vector3(1.08, 1.0, 0.88)
	ring(n, Vector3(0, 0.74, 0), Vector3.UP, 0.165, 0.185, "dark").scale = Vector3(1.08, 1.0, 0.88)
	disc(n, Vector3(0, 0.92, 0.155), Vector3.BACK, 0.05, 0.022, metal)
	ring(n, Vector3(0, 0.92, 0.167), Vector3.BACK, 0.03, 0.038, "glow")
	lathe(n, s.pelvis, Vector3.UP, [Vector2(0, -0.06), Vector2(0.1, -0.05), Vector2(0.13, 0.0), Vector2(0.12, 0.04), Vector2(0, 0.05)], "dark").scale = Vector3(1.1, 1.0, 0.85)
	# --- Конечности.
	for side in ["l", "r"]:
		var sg: float = -1.0 if side == "l" else 1.0
		var sh: Vector3 = s["sh_" + side]
		var el: Vector3 = s["el_" + side]
		var ha: Vector3 = s["ha_" + side]
		var hi: Vector3 = s["hi_" + side]
		var kn: Vector3 = s["kn_" + side]
		var an: Vector3 = s["an_" + side]
		ellipsoid(n, sh + Vector3(sg * 0.02, 0.02, 0), Vector3(0.075, 0, 0), Vector3(0, 0.065, 0), Vector3(0, 0, 0.08), paint)
		caps(n, sh, el, 0.035, "dark")
		ball(n, el, 0.042, metal)
		caps(n, el.lerp(ha, 0.1), el.lerp(ha, 0.8), 0.052, paint)
		hand(n, ha, (ha - el).normalized() + Vector3(0, -0.6, 0), Vector3(-sg, 0, 0), paint, 1.4)
		caps(n, hi, kn, 0.045, "dark")
		ball(n, kn, 0.05, metal)
		caps(n, kn.lerp(an, 0.2), kn.lerp(an, 0.75), 0.064, paint)
		piston(n, kn, an, Vector3(0, 0, -0.075), 0.018)
		ellipsoid(n, Vector3(an.x, 0.022, an.z + 0.04), Vector3(0.085, 0, 0), Vector3(0, 0.024, 0), Vector3(0, 0, 0.14), "dark")
		ellipsoid(n, Vector3(an.x, 0.06, an.z + 0.04), Vector3(0.08, 0, 0), Vector3(0, 0.055, 0), Vector3(0, 0, 0.125), paint)
	# --- Колба поменьше, два шланга.
	var fb := Vector3(0.12, 0.8, -0.22)
	var fh := 0.34
	var top := _flask_pack(n, fb, fh, 0.085, metal)
	hose(n, fb + Vector3(-0.05, fh - 0.02, -0.02), fb + Vector3(-0.15, fh + 0.06, -0.02), s.sh_l + Vector3(0.08, 0.1, -0.1), s.sh_l + Vector3(0.02, 0.03, -0.05), 0.012)
	hose(n, top, top + Vector3(0.02, 0.08, 0.0), s.sh_r + Vector3(0.03, 0.12, -0.1), s.sh_r + Vector3(0.0, 0.04, -0.05), 0.012)
	_socket(n, "socket_hand_l", s.ha_l + Vector3(0, -0.12, 0))
	_socket(n, "socket_hand_r", s.ha_r + Vector3(0, -0.12, 0))
	_socket(n, "socket_plate_chest", Vector3(0, 0.92, 0.17))
	_socket(n, "socket_plate_sh_l", s.sh_l + Vector3(-0.02, 0.08, 0))
	_socket(n, "socket_plate_sh_r", s.sh_r + Vector3(0.02, 0.08, 0))
	_socket(n, "socket_plate_thigh_l", s.hi_l.lerp(s.kn_l, 0.5) + Vector3(0, 0, 0.05))
	_socket(n, "socket_plate_thigh_r", s.hi_r.lerp(s.kn_r, 0.5) + Vector3(0, 0, 0.05))
