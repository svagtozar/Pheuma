class_name RobotDesigns
extends RefCounted
## Варианты дизайна робота для витрины (proto/robots.tscn). Всё из простых тел:
## стержни между точками скелета, шарниры, капсулы, короба, торы, шланги по Безье.
## Гибрид «каркас, обрастающий планетой» — в трёх уровнях детальности (h1, h2, h3),
## плюс концепции pneumat, geologist, miner, jumper и concept — по концепт-арту
## (concept_b — он же с корпусом из металла другой планеты).

const DESIGNS := ["h1", "h2", "h3", "concept", "concept_b", "pneumat", "geologist", "miner", "jumper"]
const NAMES := {"h1": "Гибрид · Н1 силуэт", "h2": "Гибрид · Н2 рабочий", "h3": "Гибрид · Н3 детальный",
	"concept": "Концепт · медь", "concept_b": "Концепт · другой металл",
	"pneumat": "A · Пневмат", "geologist": "B · Геолог", "miner": "D · Горняк", "jumper": "E · Прыгун"}
## Металл корпуса по умолчанию — медь; в игре — металл планеты.
const COPPER := Color(0.78, 0.47, 0.29)
const ALT_METAL := Color(0.42, 0.55, 0.72)

static var _mats := {}

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
			elif key.begins_with("pod:"):
				var c := Color(key.substr(4))
				m.albedo_color = c; m.emission_enabled = true; m.emission = c; m.emission_energy_multiplier = 0.6
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
static func _ear(n: Node3D, pivot: Vector3, sg: float, hull: String) -> Node3D:
	var e := Node3D.new()
	e.name = "ear_l" if sg < 0.0 else "ear_r"
	var y := Vector3(sg * 0.62, 0.74, -0.26).normalized()
	# Плоскость пластины перпендикулярна объективу: ширина — вперёд, толщина — вбок.
	var x := (Vector3.BACK - y * y.dot(Vector3.BACK)).normalized()
	e.transform = Transform3D(Basis(x, y, x.cross(y).normalized()), pivot)
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
	rod(n, hc + Vector3(0, 0, -0.08), hc + Vector3(0, 0, 0.07), 0.15, hull)
	ball(n, hc + Vector3(0, 0, -0.08), 0.15, hull).scale = Vector3(1, 1, 0.55)
	ring(n, hc + Vector3(0, 0, -0.02), Vector3(0, 0, 1), 0.15, 0.162, "dark")
	ring(n, hc + Vector3(0, 0, 0.07), Vector3(0, 0, 1), 0.122, 0.158, hull)
	rod(n, hc + Vector3(0, 0, 0.07), hc + Vector3(0, 0, 0.088), 0.126, "dark")
	ring(n, hc + Vector3(0, 0, 0.09), Vector3(0, 0, 1), 0.084, 0.1, "accent")
	rod(n, hc + Vector3(0, 0, 0.088), hc + Vector3(0, 0, 0.097), 0.056, "iris")
	rod(n, hc + Vector3(0, 0, 0.097), hc + Vector3(0, 0, 0.101), 0.022, "dark")
	ball(n, hc + Vector3(0, 0, 0.09), 0.084, "glass").scale = Vector3(1, 1, 0.3)
	box(n, hc + Vector3(0, 0.15, -0.04), Vector3(0.07, 0.03, 0.08), hull)
	for sg in [-1.0, 1.0]:
		_ear(n, hc + Vector3(sg * 0.125, 0.085, -0.03), sg, hull)
	# --- Шея.
	rod(n, Vector3(0, 1.42, -0.01), hc + Vector3(0, -0.12, -0.02), 0.026, "dark")
	ring(n, Vector3(0, 1.5, -0.01), Vector3.UP, 0.028, 0.042, hull)
	for sg in [-1.0, 1.0]:
		hose(n, Vector3(sg * 0.05, 1.4, -0.05), Vector3(sg * 0.07, 1.48, -0.08), hc + Vector3(sg * 0.06, -0.2, -0.08), hc + Vector3(sg * 0.05, -0.13, -0.06), 0.01, "rubber", 6)
	# --- Позвоночник: хромированный стержень и позвонки.
	rod(n, s.pelvis + Vector3(0, 0, -0.03), Vector3(0, 1.45, -0.03), 0.018, "steel")
	for k in 8:
		var y := 1.0 + k * 0.064
		box(n, Vector3(0, y, -0.03 - sin(k * 0.4) * 0.012), Vector3(0.075 - k * 0.002, 0.04, 0.065), hull if k % 2 == 0 else "dark")
	# Грудная клетка: рёбра, грудные пластины, механизм в центре.
	for k in 3:
		ring(n, Vector3(0, 1.22 + k * 0.08, 0.0), Vector3.UP, 0.125 + k * 0.005, 0.138 + k * 0.005, "dark").scale = Vector3(1.25, 1, 0.8)
	for sg in [-1.0, 1.0]:
		plate(n, Vector3(sg * 0.075, 1.23, 0.105), Vector3(sg * 0.1, 1.42, 0.09), 0.07, 0.016, Vector3.ZERO, hull)
	ring(n, Vector3(0, 1.32, 0.105), Vector3(0, 0, 1), 0.028, 0.048, "dark")
	ball(n, Vector3(0, 1.32, 0.11), 0.024, "steel")
	rod(n, s.sh_l, s.sh_r, 0.03, hull)
	box(n, Vector3(0, 1.08, -0.01), Vector3(0.12, 0.07, 0.08), "dark")
	# Таз и V-щиток.
	box(n, s.pelvis, Vector3(0.26, 0.1, 0.15), "dark")
	for sg in [-1.0, 1.0]:
		plate(n, Vector3(sg * 0.12, 1.0, 0.085), Vector3(0, 0.88, 0.085), 0.05, 0.018, Vector3.ZERO, hull)
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
		# Бандажи и пластины.
		for bone in [[sh, el, 0.034], [el, ha, 0.03], [hi, kn, 0.041], [kn, an, 0.036]]:
			var a: Vector3 = bone[0]
			var b: Vector3 = bone[1]
			var r: float = bone[2]
			for t in [0.3, 0.7]:
				ring(n, a.lerp(b, t), (b - a).normalized(), r, r + 0.012, hull)
		plate(n, sh.lerp(el, 0.25), sh.lerp(el, 0.75), 0.045, 0.016, Vector3(sg * 0.035, 0, 0), hull)
		plate(n, el.lerp(ha, 0.25), el.lerp(ha, 0.7), 0.042, 0.016, Vector3(sg * 0.03, 0, 0.005), hull)
		plate(n, hi.lerp(kn, 0.2), hi.lerp(kn, 0.75), 0.05, 0.016, Vector3(0, 0, 0.045), hull)
		ball(n, kn + Vector3(0, 0, 0.05), 0.03, hull)
		piston(n, kn, an, Vector3(0, 0, 0.055), 0.022)
		piston(n, el, ha, Vector3(0, 0, 0.04), 0.016)
		# Кисть: ладонь и пальцы.
		ring(n, ha, (ha - el).normalized(), 0.026, 0.038, hull)
		var pc := ha + Vector3(0, -0.05, 0)
		box(n, pc, Vector3(0.025, 0.07, 0.055), "dark")
		for f in 3:
			var fz := -0.018 + f * 0.018
			rod(n, pc + Vector3(0, -0.03, fz), pc + Vector3(sg * -0.012, -0.09, fz + 0.01), 0.007, "steel")
		rod(n, pc + Vector3(sg * -0.01, 0.0, 0.03), pc + Vector3(sg * -0.03, -0.04, 0.05), 0.008, "steel")
		# Шланг по ноге: от таза к колену снаружи.
		hose(n, hi + Vector3(sg * 0.06, 0.02, -0.05), hi + Vector3(sg * 0.12, -0.15, -0.08), kn + Vector3(sg * 0.1, 0.15, -0.06), kn + Vector3(sg * 0.05, 0.02, -0.03), 0.011, "rubber", 8)
		# Ботинок.
		var bc := Vector3(an.x, 0.065, an.z + 0.045)
		box(n, bc, Vector3(0.12, 0.08, 0.24), hull)
		box(n, Vector3(an.x, 0.015, an.z + 0.045), Vector3(0.13, 0.03, 0.26), "dark")
		box(n, bc + Vector3(0, 0.03, 0.09), Vector3(0.115, 0.03, 0.08), hull, Vector3(-0.35, 0, 0))
		box(n, bc + Vector3(0, 0.0, -0.1), Vector3(0.1, 0.1, 0.05), "dark")
		ring(n, Vector3(an.x, 0.12, an.z), Vector3.UP, 0.045, 0.062, hull)
	# --- Колба за правым плечом на ремнях, крышки из корпуса.
	var fb := Vector3(0.14, 1.1, -0.22)
	var fh := 0.5
	rod(n, fb, fb + Vector3(0, 0.05, 0), 0.122, hull)
	rod(n, fb + Vector3(0, 0.05, 0), fb + Vector3(0, fh - 0.05, 0), 0.115, "glass")
	rod(n, fb + Vector3(0, 0.06, 0), fb + Vector3(0, 0.06 + (fh - 0.12) * 0.8, 0), 0.1, "gas")
	rod(n, fb + Vector3(0, fh - 0.05, 0), fb + Vector3(0, fh, 0), 0.122, hull)
	rod(n, fb + Vector3(0, fh, 0), fb + Vector3(0, fh + 0.04, 0), 0.03, "steel")
	ball(n, fb + Vector3(0, fh + 0.045, 0), 0.028, hull)
	for t in [0.15, 0.3]:
		ring(n, fb + Vector3(0, fh * t / 0.45 + 0.05, 0), Vector3.UP, 0.115, 0.132, hull)
	for y in [1.25, 1.4]:
		rod(n, Vector3(0.02, y, -0.06), Vector3(0.12, y, -0.2), 0.012, hull)
	# Кассета капсул под колбой.
	var pc2 := Vector3(0.14, 1.02, -0.22)
	box(n, pc2 + Vector3(0, 0.068, 0), Vector3(0.25, 0.014, 0.08), hull)
	box(n, pc2 + Vector3(0, -0.068, 0), Vector3(0.25, 0.014, 0.08), hull)
	box(n, pc2 + Vector3(0, 0, 0.035), Vector3(0.25, 0.13, 0.01), "dark")
	var pods := ["#e8c547", "#9b5de5", "#e05a4a", "#5ad17a"]
	for i in pods.size():
		var c := pc2 + Vector3(-0.09 + i * 0.06, 0, -0.005)
		caps(n, c + Vector3(0, -0.035, 0), c + Vector3(0, 0.035, 0), 0.026, "glass")
		caps(n, c + Vector3(0, -0.03, 0), c + Vector3(0, 0.02, 0), 0.02, "pod:" + pods[i])
	# Шланги от колбы: к затылку, к обоим плечам, к правому бедру.
	var top := fb + Vector3(0, fh + 0.045, 0)
	hose(n, top, top + Vector3(0, 0.12, 0), hc + Vector3(0.05, -0.02, -0.24), hc + Vector3(0.02, -0.06, -0.12), 0.012)
	hose(n, fb + Vector3(-0.06, fh - 0.02, -0.03), fb + Vector3(-0.18, fh + 0.08, -0.02), s.sh_l + Vector3(0.1, 0.12, -0.12), s.sh_l + Vector3(0.02, 0.03, -0.04), 0.011)
	hose(n, fb + Vector3(0.07, fh - 0.03, 0.0), fb + Vector3(0.14, fh + 0.03, 0.0), s.sh_r + Vector3(0.06, 0.1, -0.1), s.sh_r + Vector3(0.0, 0.03, -0.04), 0.011)
	hose(n, fb + Vector3(0.07, 0.02, 0.0), fb + Vector3(0.12, -0.2, 0.0), s.hi_r + Vector3(0.12, 0.1, -0.12), s.hi_r + Vector3(0.05, 0.0, -0.04), 0.011)
	# --- Точки крепления.
	_socket(n, "socket_flask", fb + Vector3(0, fh / 2.0, 0))
	_socket(n, "socket_pods", pc2)
	_socket(n, "socket_hand_l", s.ha_l + Vector3(0, -0.1, 0))
	_socket(n, "socket_hand_r", s.ha_r + Vector3(0, -0.1, 0))
	_socket(n, "socket_plate_chest", Vector3(0, 1.33, 0.12))
	_socket(n, "socket_plate_sh_l", s.sh_l + Vector3(-0.02, 0.06, 0))
	_socket(n, "socket_plate_sh_r", s.sh_r + Vector3(0.02, 0.06, 0))
	_socket(n, "socket_plate_thigh_l", s.hi_l.lerp(s.kn_l, 0.5) + Vector3(0, 0, 0.06))
	_socket(n, "socket_plate_thigh_r", s.hi_r.lerp(s.kn_r, 0.5) + Vector3(0, 0, 0.06))
