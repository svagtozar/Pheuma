class_name ProtoDeposit
extends RefCounted
## Форма залежи по тегам вещества, облик — по тегам планеты.
##   druse    — друза кристаллов (crystalline; вид кристаллов — habit планеты)
##   vein     — рудная жила: цепочка металлических желваков вдоль стены (metallic, conductive)
##   nodules  — конкреции: тяжёлые окатыши, наполовину в породе (dense, magnetic,
##              radioactive, anchoring)
##   strata   — пласт: стопка плит-ступеней из чередующихся слоёв (brittle,
##              insulating, refractory)
##   crust    — корка выцветов: бугорки серы или кубики соли по кругу (acidic,
##              oxidizer, toxic — бугорки; alkaline, hygroscopic — кубики)
##   fibers   — волокнистые пучки, как асбест (fibrous, elastic)
##   resin    — смоляной натёк: глянцевые капли (organic, sticky, flammable)
##   boulders — пористые глыбы (porous; и всё прочее)
##   floaters — парящие осколки над гнездом (antigravitic, phasing)
## Планета: мороз — иней, вулкан — раскалённые прожилки, радиация и светящиеся
## вещества — свечение, тяжесть — приплюснутые формы, слабая тяжесть — вытянутые,
## сейсмика — куски сбиты и наклонены.
##
## Узел залежи: локальная +Y — нормаль породы, начало — на её поверхности.
## Каждый кусок, который можно выбурить, — MeshInstance3D с meta len и r (как
## кристалл друзы в ProtoMining: основание в начале куска, ось — его +Y). У узла
## meta sub (Substance), form, mat (материал кусков) и normal.

const NAMES := {"druse": "друза", "vein": "жила", "nodules": "конкреции", "strata": "пласт",
	"crust": "корка", "fibers": "волокна", "resin": "натёк", "boulders": "глыбы", "floaters": "парящие осколки"}

## Форма залежи вещества — по его тегам, в порядке важности.
static func form_for(s: Substance) -> String:
	if s.has("antigravitic") or s.has("phasing"):
		return "floaters"
	if s.has("crystalline"):
		return "druse"
	if s.has("metallic") or s.has("conductive"):
		return "vein"
	if s.has("dense") or s.has("magnetic") or s.has("radioactive") or s.has("anchoring"):
		return "nodules"
	if s.has("fibrous") or s.has("elastic"):
		return "fibers"
	if s.has("organic") or s.has("sticky") or s.has("flammable"):
		return "resin"
	if s.has("acidic") or s.has("alkaline") or s.has("oxidizer") or s.has("hygroscopic") or s.has("toxic"):
		return "crust"
	if s.has("brittle") or s.has("insulating") or s.has("refractory"):
		return "strata"
	return "boulders"

## Лежит на полу (true) или растёт из стены — где форма уместнее.
static func on_floor(form: String) -> bool:
	return form in ["crust", "boulders", "nodules", "floaters", "resin"]

## Облик по планете: {frost, hot, glow, squash, tilt, habit}.
static func planet_look(p: Planet, habit := "prism") -> Dictionary:
	var g := p.gravity if p != null else 1.0
	return {
		"frost": p != null and p.has_tag("frozen"),
		"hot": p != null and p.has_tag("volcanic"),
		"glow": 0.5 if p != null and p.has_tag("radiation") else 0.0,
		"squash": clampf(1.0 / sqrt(g), 0.7, 1.35),
		"tilt": 0.5 if p != null and p.has_tag("seismic") else 0.0,
		"habit": habit,
	}

## Материал кусков залежи.
static func material(s: Substance, form: String, look: Dictionary) -> Material:
	var col := s.color
	var glow: float = look.get("glow", 0.0) + (0.8 if s.has("luminous") else 0.0) + (0.6 if s.has("radioactive") else 0.0)
	if form == "druse":
		return ProtoCrystal.material(col, 0.7 + glow, 0.85)
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 0.85
	match form:
		"vein":
			m.metallic = 0.9
			m.roughness = 0.32
			m.albedo_color = col.lerp(Color(0.8, 0.8, 0.82), 0.2)
		"nodules":
			m.roughness = 0.6
			m.metallic = 0.35 if s.has("magnetic") else 0.1
			m.albedo_color = col.darkened(0.15)
		"strata":
			m.vertex_color_use_as_albedo = true
			m.albedo_color = Color.WHITE
			m.roughness = 0.95
		"crust":
			m.albedo_color = col.lerp(Color.WHITE, 0.35)
			m.roughness = 1.0
		"fibers":
			m.albedo_color = col.lerp(Color.WHITE, 0.2)
			m.roughness = 0.55
			m.rim_enabled = true
			m.rim = 0.5
		"resin":
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.albedo_color = Color(col.darkened(0.1), 0.82)
			m.roughness = 0.04
			m.clearcoat_enabled = true
			m.clearcoat = 1.0
			m.rim_enabled = true
			m.rim = 0.4
		"boulders":
			m.roughness = 1.0
			m.albedo_color = col.darkened(0.05)
		"floaters":
			m.roughness = 0.2
			m.metallic = 0.3
			m.rim_enabled = true
			m.rim = 0.8
			glow += 0.6
	if look.get("frost", false):
		m.albedo_color = m.albedo_color.lerp(Color(0.9, 0.95, 1.0, m.albedo_color.a), 0.35)
		m.roughness = maxf(m.roughness, 0.5)
		m.rim_enabled = true
		m.rim = maxf(m.rim, 0.5)
	if look.get("hot", false) and form in ["vein", "nodules", "strata", "boulders"]:
		glow += 0.25
		col = col.lerp(Color(1.0, 0.45, 0.12), 0.6)
	if glow > 0.0:
		m.emission_enabled = true
		m.emission = col
		m.emission_energy_multiplier = glow
	return m

## Тот же материал раскалённым от бура.
static func hot(m: Material) -> Material:
	var h: Material = m.duplicate()
	if h is StandardMaterial3D:
		var sm := h as StandardMaterial3D
		sm.emission_enabled = true
		if m is StandardMaterial3D and (m as StandardMaterial3D).emission_enabled:
			sm.emission_energy_multiplier = (m as StandardMaterial3D).emission_energy_multiplier * 2.6
		else:
			sm.emission = Color(1.0, 0.55, 0.25)
			sm.emission_energy_multiplier = 0.7
		sm.albedo_color = sm.albedo_color.lerp(Color(1, 1, 1, sm.albedo_color.a), 0.3)
	return h

## Залежь: узел с кусками. size ~1 — обычная (0,5–1,6), look — planet_look().
## mat — готовый материал (иначе material()).
static func build(s: Substance, form: String, size: float, rng: RandomNumberGenerator, look: Dictionary, mat: Material = null) -> Node3D:
	var n := Node3D.new()
	n.name = "deposit_" + form
	if mat == null:
		mat = material(s, form, look)
	n.set_meta("sub", s)
	n.set_meta("form", form)
	n.set_meta("mat", mat)
	n.set_meta("normal", Vector3.UP)
	var sq: float = look.get("squash", 1.0)
	var tilt: float = look.get("tilt", 0.0)
	match form:
		"druse": _druse(n, size, rng, look.get("habit", "prism"), mat)
		"vein": _vein(n, size, rng, mat, look.get("hot", false))
		"nodules": _nodules(n, size, rng, mat)
		"strata": _strata(n, s, size, rng, mat)
		"crust": _crust(n, s, size, rng, mat)
		"fibers": _fibers(n, size, rng, mat)
		"resin": _resin(n, size, rng, mat)
		"floaters": _floaters(n, s, size, rng, mat)
		_: _boulders(n, size, rng, mat)
	for c in n.get_children():
		if c is MeshInstance3D and c.has_meta("len"):
			# Тяжесть: вдоль нормали сплющено или вытянуто; сейсмика — сбито.
			c.scale = Vector3(1.0, sq, 1.0) * c.scale
			c.set_meta("len", float(c.get_meta("len")) * sq)
			if tilt > 0.0:
				c.rotate_object_local(Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized(), rng.randf_range(0.1, 0.45) * tilt)
	return n

## Развернуть узел залежи нормалью наружу в точке base.
static func place(n: Node3D, base: Vector3, nrm: Vector3, rng: RandomNumberGenerator) -> void:
	var y := nrm.normalized()
	var ref := Vector3.UP if absf(y.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
	var x := y.cross(ref).normalized()
	n.transform = Transform3D(Basis(x, y, x.cross(y)).rotated(y, rng.randf() * TAU), base)
	n.set_meta("normal", y)

## Кусок: меш, основание в at, ось вдоль up; len и r — для бура.
static func _piece(n: Node3D, mesh: Mesh, mat: Material, at: Vector3, up: Vector3, len: float, r: float, spin := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	var y := up.normalized()
	var ref := Vector3.UP if absf(y.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
	var x := y.cross(ref).normalized()
	mi.transform = Transform3D(Basis(x, y, x.cross(y)).rotated(y, spin), at)
	mi.name = "piece_%d" % n.get_child_count()
	mi.set_meta("len", len)
	mi.set_meta("r", r)
	n.add_child(mi)
	return mi

# ---------------------------------------------------------------- формы

static func _druse(n: Node3D, size: float, rng: RandomNumberGenerator, habit: String, mat: Material) -> void:
	var main_len := rng.randf_range(0.7, 1.2) * size
	for m in rng.randi_range(5, 8):
		var spread := 0.15 if m == 0 else rng.randf_range(0.25, 0.7)
		var up := (Vector3.UP + Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)) * spread).normalized()
		var len := main_len if m == 0 else main_len * rng.randf_range(0.25, 0.7)
		var r := len * rng.randf_range(0.11, 0.16)
		var a := m * 2.4
		var off := Vector3.ZERO if m == 0 else Vector3(cos(a), 0, sin(a)) * rng.randf_range(0.08, 0.3)
		_piece(n, ProtoCrystal.mesh(len, r, rng, habit), mat, off - up * len * 0.12, up, len, r, rng.randf() * TAU)

## Жила: извилистая лента желваков по стене, крупные посередине.
static func _vein(n: Node3D, size: float, rng: RandomNumberGenerator, mat: Material, hot: bool) -> void:
	var cnt := rng.randi_range(6, 9)
	var span := rng.randf_range(1.8, 2.6) * size
	var ph := rng.randf() * TAU
	for i in cnt:
		var t := float(i) / (cnt - 1) - 0.5
		var mid := 1.0 - absf(t) * 1.2
		var at := Vector3(t * span, 0, sin(t * 4.0 + ph) * 0.35 * size)
		var r := rng.randf_range(0.14, 0.22) * size * (0.6 + mid)
		var h := r * rng.randf_range(0.55, 0.9)
		var mesh := rock(rng, r * 1.4, r * 0.8, h, 0.18, 6)
		_piece(n, mesh, mat, at - Vector3(0, h * 0.3, 0), Vector3.UP, h, r, rng.randf() * TAU)
	if hot:
		# Раскалённая трещина вдоль жилы — не бурится, только светит.
		var seam := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = Vector3(span * 1.05, 0.03, 0.06)
		seam.mesh = b
		var sm := StandardMaterial3D.new()
		sm.albedo_color = Color(1.0, 0.5, 0.15)
		sm.emission_enabled = true
		sm.emission = Color(1.0, 0.45, 0.1)
		sm.emission_energy_multiplier = 2.5
		seam.material_override = sm
		n.add_child(seam)

## Конкреции: гладкие тяжёлые шары, наполовину в породе.
static func _nodules(n: Node3D, size: float, rng: RandomNumberGenerator, mat: Material) -> void:
	for i in rng.randi_range(3, 6):
		var r := rng.randf_range(0.16, 0.36) * size * (1.3 if i == 0 else 1.0)
		var at := Vector3.ZERO if i == 0 else Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized() * rng.randf_range(0.35, 0.75) * size
		var mesh := rock(rng, r, r * rng.randf_range(0.85, 1.0), r * 1.9, 0.07, 8)
		_piece(n, mesh, mat, at - Vector3(0, r * 0.35, 0), Vector3.UP, r * 1.9, r, rng.randf() * TAU)

## Пласт: стопка плит, каждая следующая меньше и сдвинута — выход слоёв.
static func _strata(n: Node3D, s: Substance, size: float, rng: RandomNumberGenerator, mat: Material) -> void:
	var y := -0.05
	var w := rng.randf_range(1.4, 1.8) * size
	var d := w * rng.randf_range(0.55, 0.75)
	var shift := Vector3(rng.randf_range(-0.08, 0.08), 0, rng.randf_range(0.04, 0.1))
	var off := Vector3.ZERO
	for i in rng.randi_range(4, 6):
		var h := rng.randf_range(0.1, 0.18) * size
		var col := s.color.darkened(0.4) if i % 2 == 1 else s.color.lerp(Color(0.9, 0.88, 0.82), 0.15)
		var mesh := slab(rng, w, d, h, col)
		_piece(n, mesh, mat, off + Vector3(0, y, 0), Vector3.UP, h, sqrt(w * d / 2.6), rng.randf_range(-0.12, 0.12))
		y += h
		w *= rng.randf_range(0.72, 0.88)
		d *= rng.randf_range(0.75, 0.9)
		off += shift * size

## Корка: пятна выцветов — бугорки (сера) или кубики (соль).
static func _crust(n: Node3D, s: Substance, size: float, rng: RandomNumberGenerator, mat: Material) -> void:
	var cubes := s.has("alkaline") or s.has("hygroscopic")
	for k in rng.randi_range(3, 4):
		var a := k * TAU / 3.5 + rng.randf_range(-0.4, 0.4)
		var at := Vector3(cos(a), 0, sin(a)) * rng.randf_range(0.15, 0.55) * size
		var pr := rng.randf_range(0.28, 0.42) * size
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		# Плоская подложка и бугорки на ней.
		_add_rock(st, rng, Vector3(0, -0.02, 0), pr, pr * 0.9, 0.05, 0.25, 7, Basis())
		for b in rng.randi_range(9, 16):
			var ba := rng.randf() * TAU
			var bd := sqrt(rng.randf()) * pr * 0.85
			var br := rng.randf_range(0.035, 0.09) * size
			var p := Vector3(cos(ba) * bd, 0.0, sin(ba) * bd)
			if cubes:
				var basis := Basis(Vector3.UP, rng.randf() * TAU).rotated(Vector3(1, 0, 0), rng.randf_range(-0.3, 0.3))
				_add_box(st, p + Vector3(0, br * 0.4, 0), Vector3.ONE * br * 1.3, basis)
			else:
				_add_rock(st, rng, p - Vector3(0, br * 0.3, 0), br, br, br * 1.4, 0.25, 5, Basis())
		st.generate_normals()
		_piece(n, st.commit(), mat, at, Vector3.UP, 0.12 * size, pr * 0.6, rng.randf() * TAU)

## Волокна: пучки тонких изогнутых нитей веером.
static func _fibers(n: Node3D, size: float, rng: RandomNumberGenerator, mat: Material) -> void:
	for k in rng.randi_range(3, 5):
		var a := k * 2.1 + rng.randf_range(-0.3, 0.3)
		var at := Vector3(cos(a), 0, sin(a)) * rng.randf_range(0.0, 0.4) * size
		var len := rng.randf_range(0.45, 0.85) * size
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var bend := Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized() * rng.randf_range(0.1, 0.3)
		for f in rng.randi_range(14, 22):
			var fa := rng.randf() * TAU
			var fr := sqrt(rng.randf()) * 0.07 * size
			var root := Vector3(cos(fa) * fr, 0, sin(fa) * fr)
			var fl := len * rng.randf_range(0.7, 1.05)
			var splay := root * 2.5 + bend
			_add_strand(st, root, fl, splay, rng.randf_range(0.006, 0.012) * size)
		st.generate_normals()
		_piece(n, st.commit(), mat, at - Vector3(0, 0.03, 0), Vector3.UP, len, 0.08 * size, rng.randf() * TAU)

## Натёк смолы: лужица и вытянутые капли на ней — глянцевые и полупрозрачные.
static func _resin(n: Node3D, size: float, rng: RandomNumberGenerator, mat: Material) -> void:
	for k in rng.randi_range(2, 4):
		var a := k * 2.4 + rng.randf()
		var at := Vector3(cos(a), 0, sin(a)) * rng.randf_range(0.0, 0.5) * size
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var pr := rng.randf_range(0.22, 0.34) * size
		_add_blob(st, Vector3(0, -0.03, 0), pr, 0.12 * size, 12)
		var h := 0.1 * size
		for b in rng.randi_range(1, 3):
			var ba := rng.randf() * TAU
			var p := Vector3(cos(ba), 0, sin(ba)) * rng.randf_range(0.0, 0.5) * pr
			var r := rng.randf_range(0.07, 0.13) * size
			var dh := r * rng.randf_range(2.0, 3.2)
			_add_blob(st, p, r, dh, 10)
			h = maxf(h, dh)
		st.generate_normals()
		_piece(n, st.commit(), mat, at, Vector3.UP, h, pr * 0.5, rng.randf() * TAU)

## Глыбы: угловатые шершавые камни.
static func _boulders(n: Node3D, size: float, rng: RandomNumberGenerator, mat: Material) -> void:
	for i in rng.randi_range(2, 4):
		var r := rng.randf_range(0.3, 0.55) * size * (1.3 if i == 0 else 1.0)
		var at := Vector3.ZERO if i == 0 else Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized() * rng.randf_range(0.55, 0.9) * size
		var h := r * rng.randf_range(1.0, 1.5)
		var mesh := rock(rng, r, r * rng.randf_range(0.7, 1.0), h, 0.3, 7)
		_piece(n, mesh, mat, at - Vector3(0, h * 0.15, 0), Vector3.UP, h, r, rng.randf() * TAU)

## Парящие осколки: гнездо-воронка в породе и куски над ним.
static func _floaters(n: Node3D, s: Substance, size: float, rng: RandomNumberGenerator, mat: Material) -> void:
	var cnt := rng.randi_range(4, 7)
	for i in cnt:
		var a := i * TAU / cnt + rng.randf_range(-0.3, 0.3)
		var len := rng.randf_range(0.25, 0.5) * size
		var r := len * rng.randf_range(0.25, 0.35)
		var at := Vector3(cos(a), 0, sin(a)) * rng.randf_range(0.2, 0.55) * size + Vector3(0, rng.randf_range(0.5, 1.4) * size, 0)
		var up := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.3, 1), rng.randf_range(-1, 1)).normalized()
		_piece(n, ProtoCrystal.mesh(len, r, rng, "shard"), mat, at, up, len, r, rng.randf() * TAU)
	# Кольцо свечения под ними — не бурится.
	var ring := MeshInstance3D.new()
	var tor := TorusMesh.new()
	tor.inner_radius = 0.45 * size
	tor.outer_radius = 0.55 * size
	tor.rings = 24
	tor.ring_segments = 4
	ring.mesh = tor
	var rm := StandardMaterial3D.new()
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.albedo_color = s.color.lerp(Color.WHITE, 0.3)
	rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rm.albedo_color.a = 0.6
	ring.material_override = rm
	ring.scale = Vector3(1, 0.3, 1)
	ring.position = Vector3(0, 0.02, 0)
	n.add_child(ring)

# ---------------------------------------------------------------- сетки

## Камень: сплюснутый многогранник с шероховатостью rough, низ — у y = 0.
## rx, rz — радиусы в плане, h — высота, seg — граней по кругу.
static func rock(rng: RandomNumberGenerator, rx: float, rz: float, h: float, rough: float, seg: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_add_rock(st, rng, Vector3.ZERO, rx, rz, h, rough, seg, Basis())
	st.generate_normals()
	return st.commit()

static func _add_rock(st: SurfaceTool, rng: RandomNumberGenerator, at: Vector3, rx: float, rz: float, h: float, rough: float, seg: int, basis: Basis) -> void:
	var rings := maxi(3, seg / 2)
	var pts := []
	for i in rings + 1:
		var v := float(i) / rings
		var phi := v * PI
		var row := []
		for j in seg:
			var th := j * TAU / seg
			var k := 1.0 + rng.randf_range(-rough, rough) if i > 0 and i < rings else 1.0
			var p := Vector3(sin(phi) * cos(th) * rx * k, (1.0 - cos(phi)) * 0.5 * h, sin(phi) * sin(th) * rz * k)
			if i > 0 and i < rings:
				p.y += rng.randf_range(-rough, rough) * h * 0.3
			row.append(at + basis * p)
		pts.append(row)
	for i in rings:
		for j in seg:
			var j2 := (j + 1) % seg
			var a: Vector3 = pts[i][j]
			var b: Vector3 = pts[i][j2]
			var c: Vector3 = pts[i + 1][j]
			var d: Vector3 = pts[i + 1][j2]
			if i > 0:
				_tri(st, a, b, c)
			if i < rings - 1:
				_tri(st, b, d, c)

## Плита слоя с неровными краями и цветом слоя в вершинах.
static func slab(rng: RandomNumberGenerator, w: float, d: float, h: float, col: Color) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var seg := 10
	var bot := []
	var top := []
	for j in seg:
		var th := j * TAU / seg
		# Скруглённый прямоугольник, края обломаны.
		var c := Vector2(cos(th), sin(th))
		var sq := Vector2(signf(c.x) * pow(absf(c.x), 0.4), signf(c.y) * pow(absf(c.y), 0.4))
		var k := rng.randf_range(0.8, 1.05)
		bot.append(Vector3(sq.x * w * 0.5 * k, 0, sq.y * d * 0.5 * k))
		var k2 := k * rng.randf_range(0.88, 0.98)
		top.append(Vector3(sq.x * w * 0.5 * k2, h + rng.randf_range(-0.2, 0.2) * h, sq.y * d * 0.5 * k2))
	st.set_color(col)
	var ct := Vector3(0, h, 0)
	for j in seg:
		var j2 := (j + 1) % seg
		_tri(st, bot[j], top[j], bot[j2])
		_tri(st, bot[j2], top[j], top[j2])
		_tri(st, top[j], ct, top[j2])
		_tri(st, bot[j], bot[j2], Vector3.ZERO)
	st.generate_normals()
	return st.commit()

static func _add_box(st: SurfaceTool, at: Vector3, sz: Vector3, basis: Basis) -> void:
	var h := sz * 0.5
	var v := []
	for i in 8:
		v.append(at + basis * Vector3(h.x * (1 if i & 1 else -1), h.y * (1 if i & 2 else -1), h.z * (1 if i & 4 else -1)))
	for f in [[0, 1, 3, 2], [4, 6, 7, 5], [0, 4, 5, 1], [2, 3, 7, 6], [0, 2, 6, 4], [1, 5, 7, 3]]:
		_tri(st, v[f[0]], v[f[1]], v[f[2]])
		_tri(st, v[f[0]], v[f[2]], v[f[3]])

## Нить: треугольная трубка из нескольких звеньев, изгибается в сторону splay.
static func _add_strand(st: SurfaceTool, root: Vector3, len: float, splay: Vector3, r: float) -> void:
	var segs := 5
	var prev := []
	for i in segs + 1:
		var t := float(i) / segs
		var c := root + Vector3(0, t * len, 0) + splay * t * t * len
		var rr := r * (1.0 - t * 0.8)
		var ring := []
		for k in 3:
			var a := k * TAU / 3.0
			ring.append(c + Vector3(cos(a) * rr, 0, sin(a) * rr))
		if i > 0:
			for k in 3:
				var k2 := (k + 1) % 3
				_tri(st, prev[k], ring[k], prev[k2])
				_tri(st, prev[k2], ring[k], ring[k2])
		prev = ring

## Капля: эллипсоид, низ у at.
static func _add_blob(st: SurfaceTool, at: Vector3, r: float, h: float, seg: int) -> void:
	var rings := seg / 2
	var pts := []
	for i in rings + 1:
		var phi := float(i) / rings * PI
		var row := []
		for j in seg:
			var th := j * TAU / seg
			row.append(at + Vector3(sin(phi) * cos(th) * r, (1.0 - cos(phi)) * 0.5 * h, sin(phi) * sin(th) * r))
		pts.append(row)
	for i in rings:
		for j in seg:
			var j2 := (j + 1) % seg
			if i > 0:
				_tri(st, pts[i][j], pts[i][j2], pts[i + 1][j])
			if i < rings - 1:
				_tri(st, pts[i][j2], pts[i + 1][j2], pts[i + 1][j])

## Треугольник с обходом, при котором generate_normals() смотрит наружу
## (порядок Godot — по часовой стрелке при взгляде снаружи).
static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)
