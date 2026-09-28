class_name MachineKit
extends RefCounted
## Облик машин завода — «индустриальный» набор деталей: тёмная стальная рама,
## кожух крашен по назначению машины (Buildings.CATS: добыча и склад — оливковый,
## пневматика — сине-бирюзовый, обработка — оранжевый, логика и лаборатория —
## светло-серый, цели — белый), жёлто-чёрная разметка, болты, фланцы, рёбра со
## скосом. Материал планеты — основание-салазки и боковые панели: машина «из
## местного», но не сливается с грунтом.
##
## Своя модель есть у машин 3D-завода (MODELS); остальные силуэты
## MachineModels одеваются в этот набор через dress(). Контракт как у
## MachineModels.build: выход на +Z, мета "h", живые части — именованные узлы
## (lamp, heap, fill, sample, gauge); движения за работой — anim()/animate().
## Материалы и сетки общие на все машины: ProtoBatch склеивает их по материалу.

const MODELS := ["intake", "pump", "crusher", "furnace", "tank", "centrifuge", "lab"]
## Buildings.CATS → краска.
const CAT_PAINT := ["store", "pneu", "proc", "logic", "goal", "store"]
const CAT := {"intake": "pneu", "lab": "logic"}
## Высота верха основания (салазок).
const BASE_H := 0.26

static var _mats := {}
static var _meshes := {}

## Назначение машины → ключ краски.
static func cat_of(kind: String) -> String:
	if CAT.has(kind):
		return CAT[kind]
	var info: Dictionary = Buildings.KINDS.get(kind, {})
	return CAT_PAINT[int(info.get("cat", 0))]

static func has_model(kind: String) -> bool:
	return kind in MODELS

## Своя модель машины в n. Возвращает высоту корпуса.
static func build_into(n: Node3D, kind: String, body: Material) -> float:
	match kind:
		"intake": return _intake(n, body)
		"pump": return _pump(n, body)
		"crusher": return _crusher(n, body)
		"furnace": return _furnace(n, body)
		"tank": return _tank(n, body)
		"centrifuge": return _centrifuge(n, body)
		"lab": return _lab(n, body)
	return 1.0

# ---------------------------------------------------------------- материалы

static func m(id: String) -> Material:
	if _mats.has(id):
		return _mats[id]
	var r: Material
	match id:
		"frame": r = _pbr(Color(0.16, 0.17, 0.19), 0.55, 0.6)
		"metal": r = _pbr(Color(0.62, 0.63, 0.66), 0.35, 0.9)
		"store": r = _pbr(Color(0.42, 0.47, 0.22), 0.55, 0.2)
		"pneu": r = _pbr(Color(0.13, 0.38, 0.5), 0.5, 0.2)
		"proc": r = _pbr(Color(0.9, 0.46, 0.1), 0.5, 0.2)
		"logic": r = _pbr(Color(0.74, 0.76, 0.78), 0.45, 0.2)
		"goal": r = _pbr(Color(0.88, 0.88, 0.85), 0.45, 0.1)
		"trim": r = _hazard()
		"screen": r = ProtoMachines.glow(Color(0.5, 1.0, 0.4), 1.4)
		"hot": r = ProtoMachines.glow(Color(1.0, 0.45, 0.1), 4.0)
		"glass": r = ProtoMachines.glass()
		"dark": r = _pbr(Color(0.08, 0.08, 0.09), 0.7, 0.3)
		"probe0": r = ProtoMachines.glow(Color(1.0, 0.45, 0.15), 1.2)
		"probe1": r = ProtoMachines.glow(Color(0.5, 0.95, 0.4), 1.2)
		"probe2": r = ProtoMachines.glow(Color(0.45, 0.55, 1.0), 1.2)
		"probe3": r = ProtoMachines.glow(Color(1.0, 0.95, 0.4), 1.2)
		"probe4": r = ProtoMachines.glow(Color(0.4, 1.0, 0.8), 1.2)
		_: r = _pbr(Color.MAGENTA, 0.5, 0.0)
	_mats[id] = r
	return r

static func paint(cat: String) -> Material:
	return m(cat)

static func _pbr(c: Color, rough: float, metal: float) -> StandardMaterial3D:
	var r := StandardMaterial3D.new()
	r.albedo_color = c
	r.roughness = rough
	r.metallic = metal
	return r

## Жёлто-чёрные косые полосы (разметка), по мировым координатам.
static func _hazard() -> StandardMaterial3D:
	var img := Image.create(32, 32, false, Image.FORMAT_RGB8)
	for y in 32:
		for x in 32:
			img.set_pixel(x, y, Color(0.95, 0.72, 0.1) if (x + y) % 32 < 16 else Color(0.07, 0.07, 0.07))
	img.generate_mipmaps()
	var r := _pbr(Color.WHITE, 0.6, 0.1)
	r.albedo_texture = ImageTexture.create_from_image(img)
	r.uv1_triplanar = true
	r.uv1_scale = Vector3(2.5, 2.5, 2.5)
	return r

# ---------------------------------------------------------------- тела

static func _add(p: Node3D, mesh: Mesh, mat: Material, pos: Vector3, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	p.add_child(mi)
	return mi

## Коробка со скошенными рёбрами (фаска r): свет ложится на рёбра.
static func bevel(size: Vector3, r: float) -> ArrayMesh:
	var key := "bv%s/%.3f" % [size, r]
	if _meshes.has(key):
		return _meshes[key]
	var h := size / 2.0
	r = minf(r, minf(h.x, minf(h.y, h.z)) * 0.9)
	var pt := func(sg: Vector3, axis: int) -> Vector3:
		var v := Vector3(sg.x * (h.x - r), sg.y * (h.y - r), sg.z * (h.z - r))
		v[axis] = sg[axis] * h[axis]
		return v
	var polys := []
	for ax in 3:
		var u := (ax + 1) % 3
		var w := (ax + 2) % 3
		for s in [-1.0, 1.0]:
			var q := []
			for k in [[-1, -1], [1, -1], [1, 1], [-1, 1]]:
				var sg := Vector3.ZERO
				sg[ax] = s
				sg[u] = k[0]
				sg[w] = k[1]
				q.append(pt.call(sg, ax))
			polys.append(q)
		# Фаска вдоль оси ax между гранями u и w.
		for su in [-1.0, 1.0]:
			for sw in [-1.0, 1.0]:
				var q := []
				for sa in [-1.0, 1.0]:
					var sg := Vector3.ZERO
					sg[ax] = sa
					sg[u] = su
					sg[w] = sw
					q.append(pt.call(sg, u))
				for sa in [1.0, -1.0]:
					var sg := Vector3.ZERO
					sg[ax] = sa
					sg[u] = su
					sg[w] = sw
					q.append(pt.call(sg, w))
				polys.append(q)
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				var sg := Vector3(sx, sy, sz)
				polys.append([pt.call(sg, 0), pt.call(sg, 1), pt.call(sg, 2)])
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for q in polys:
		var c := Vector3.ZERO
		for p in q:
			c += p
		c /= q.size()
		var nrm: Vector3 = (q[1] - q[0]).cross(q[2] - q[0]).normalized()
		if nrm.dot(c) > 0.0:
			q.reverse()
			nrm = -nrm
		# Godot: лицевая грань — по часовой стрелке, нормаль наружу.
		for i in range(1, q.size() - 1):
			for p in [q[0], q[i], q[i + 1]]:
				st.set_normal(-nrm)
				st.add_vertex(p)
	var mesh := st.commit()
	_meshes[key] = mesh
	return mesh

static func _bx(p: Node3D, size: Vector3, mat: Material, pos: Vector3, r := 0.04, rot := Vector3.ZERO) -> MeshInstance3D:
	return _add(p, bevel(size, r), mat, pos, rot)

static func _cy(p: Node3D, r: float, h: float, mat: Material, pos: Vector3, top := -1.0, rot := Vector3.ZERO, seg := 24) -> MeshInstance3D:
	var key := "cy%.3f/%.3f/%.3f/%d" % [r, h, top, seg]
	if not _meshes.has(key):
		var c := CylinderMesh.new()
		c.top_radius = r if top < 0.0 else top
		c.bottom_radius = r
		c.height = h
		c.radial_segments = seg
		c.rings = 1
		_meshes[key] = c
	return _add(p, _meshes[key], mat, pos, rot)

static func _sp(p: Node3D, r: float, mat: Material, pos: Vector3, hemi := false, sy := 1.0) -> MeshInstance3D:
	var key := "sp%.3f/%s/%.2f" % [r, hemi, sy]
	if not _meshes.has(key):
		var s := SphereMesh.new()
		s.radius = r
		s.height = (r if hemi else r * 2.0) * sy
		s.is_hemisphere = hemi
		s.radial_segments = 24
		s.rings = 10
		_meshes[key] = s
	return _add(p, _meshes[key], mat, pos)

static func _tor(p: Node3D, r: float, w: float, mat: Material, pos: Vector3, rot := Vector3.ZERO) -> MeshInstance3D:
	var key := "to%.3f/%.3f" % [r, w]
	if not _meshes.has(key):
		var t := TorusMesh.new()
		t.inner_radius = r - w
		t.outer_radius = r + w
		t.rings = 28
		t.ring_segments = 8
		_meshes[key] = t
	return _add(p, _meshes[key], mat, pos, rot)

static func _piv(p: Node3D, pos: Vector3, rot := Vector3.ZERO) -> Node3D:
	var q := Node3D.new()
	q.position = pos
	q.rotation = rot
	p.add_child(q)
	return q

# ---------------------------------------------------------------- детали

## Основание-салазки на клетку w×d. Возвращает высоту верха.
static func base(n: Node3D, body: Material, w := 1.8, d := 1.8) -> float:
	_bx(n, Vector3(w, 0.2, d), m("frame"), Vector3(0, 0.1, 0), 0.03)
	_bx(n, Vector3(w - 0.12, 0.06, d - 0.12), body, Vector3(0, 0.23, 0), 0.02)
	for sz in [-1.0, 1.0]:
		_bx(n, Vector3(w + 0.02, 0.07, 0.12), m("trim"), Vector3(0, 0.12, sz * (d / 2.0 - 0.04)), 0.01)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_bx(n, Vector3(0.22, 0.12, 0.22), m("frame"), Vector3(sx * (w / 2.0 - 0.1), 0.06, sz * (d / 2.0 - 0.1)), 0.03)
			_cy(n, 0.035, 0.04, m("metal"), Vector3(sx * (w / 2.0 - 0.1), 0.22, sz * (d / 2.0 - 0.1)), -1.0, Vector3.ZERO, 6)
	return BASE_H

## Кожух-коробка: краска, рама по вертикальным рёбрам, панели из материала
## планеты с болтами по бокам, рама по верху.
static func housing(n: Node3D, size: Vector3, pos: Vector3, cat: String, body: Material) -> void:
	_bx(n, size, paint(cat), pos, 0.05)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_bx(n, Vector3(0.1, size.y + 0.04, 0.1), m("frame"), pos + Vector3(sx * size.x / 2.0, 0, sz * size.z / 2.0), 0.02)
	_panels(n, size, pos, body)
	_bx(n, Vector3(size.x + 0.04, 0.08, size.z + 0.04), m("frame"), pos + Vector3(0, size.y / 2.0, 0), 0.02)

static func _panels(n: Node3D, size: Vector3, pos: Vector3, body: Material) -> void:
	for sx in [-1.0, 1.0]:
		_bx(n, Vector3(0.04, size.y * 0.6, size.z * 0.6), body, pos + Vector3(sx * (size.x / 2.0 + 0.01), 0, 0), 0.01)
		_bolts(n, pos + Vector3(sx * (size.x / 2.0 + 0.03), size.y * 0.3 + 0.02, 0), Vector3(0, 0, 1), size.z * 0.6, 4)

## Сосуд-цилиндр: краска, рамные пояса сверху и снизу, пояс из материала планеты.
static func vessel(n: Node3D, r: float, h: float, pos: Vector3, cat: String, body: Material, rot := Vector3.ZERO) -> Node3D:
	var p := _piv(n, pos, rot)
	_cy(p, r, h, paint(cat), Vector3.ZERO, -1.0, Vector3.ZERO, 24)
	_bands(p, r, h, Vector3.ZERO)
	_cy(p, r + 0.015, h * 0.35, body, Vector3.ZERO, -1.0, Vector3.ZERO, 24)
	return p

static func _bands(p: Node3D, r: float, h: float, at: Vector3) -> void:
	for y in [-h / 2.0 + 0.06, h / 2.0 - 0.06]:
		_cy(p, r + 0.04, 0.1, m("frame"), at + Vector3(0, y, 0), -1.0, Vector3.ZERO, 24)

## Табло на передней стороне (смотрит в +Z). named — узел "gauge" со своим
## материалом: его красит вид по давлению.
static func gauge(n: Node3D, pos: Vector3, yaw := 0.0, named := false) -> void:
	var p := _piv(n, pos, Vector3(0, yaw, 0))
	_bx(p, Vector3(0.3, 0.22, 0.08), m("frame"), Vector3.ZERO, 0.02)
	var s := _bx(p, Vector3(0.22, 0.12, 0.02), m("screen"), Vector3(0, 0.01, 0.04), 0.005)
	if named:
		s.name = "gauge"
		s.material_override = ProtoMachines.glow(Color(0.3, 1.0, 0.4), 1.5)

## Лампа состояния в колпаке; материал задаёт вид (MachineModels.mat).
static func lamp(n: Node3D, pos: Vector3) -> MeshInstance3D:
	_cy(n, 0.09, 0.05, m("frame"), pos - Vector3(0, 0.05, 0), -1.0, Vector3.ZERO, 12)
	var l := _cy(n, 0.07, 0.14, MachineModels.mat("lamp_idle"), pos + Vector3(0, 0.04, 0), 0.05, Vector3.ZERO, 12)
	l.name = "lamp"
	return l

static func _bolts(n: Node3D, center: Vector3, dir: Vector3, span: float, count: int) -> void:
	for i in count:
		var t := (i / float(count - 1) - 0.5) * span if count > 1 else 0.0
		_cy(n, 0.028, 0.03, m("metal"), center + dir * t, -1.0, Vector3(0, 0, PI / 2.0), 6)

## Выход (+Z): короб с белой меткой, как стрелка выхода в 2D. tip — свой цвет метки.
static func outlet(n: Node3D, pos: Vector3, tip: Material = null) -> Node3D:
	var p := _piv(n, pos)
	_bx(p, Vector3(0.4, 0.26, 0.14), m("frame"), Vector3.ZERO, 0.03)
	_bx(p, Vector3(0.44, 0.05, 0.05), tip if tip != null else MachineModels.mat("out"), Vector3(0, 0.16, 0.05), 0.01)
	return p

# ---------------------------------------------------------------- одеть силуэт

## Одеть в набор тела, добавленные в n начиная с first (силуэты MachineModels,
## окрашенные краской paint): поднять на y0 (основание), рёбра со скосом,
## тонкие стойки и тяги — рама, крупные кожухи — с панелями из материала
## планеты, крупные сосуды — с рамными поясами, кольца — рама, мелкие
## цилиндры и шары — светлый металл (патрубки, штоки, головки).
static func dress(n: Node3D, first: int, y0: float, pnt: Material, body: Material) -> void:
	var kids := n.get_children().slice(first)
	for c in kids:
		if c is Node3D:
			(c as Node3D).position.y += y0
	for c in kids:
		_dress_node(c, pnt, body, true)

static func _dress_node(c: Node, pnt: Material, body: Material, extras: bool) -> void:
	var mi := c as MeshInstance3D
	if mi != null and mi.material_override == pnt:
		var still := mi.rotation.is_zero_approx()
		if mi.mesh is BoxMesh:
			var s: Vector3 = (mi.mesh as BoxMesh).size
			var lo := minf(s.x, minf(s.y, s.z))
			var hi := maxf(s.x, maxf(s.y, s.z))
			mi.mesh = bevel(s, clampf(lo * 0.25, 0.008, 0.05))
			if lo < 0.16 and hi > 0.3:
				mi.material_override = m("frame")
			elif extras and still and s.x >= 0.7 and s.z >= 0.5 and s.y >= 0.45:
				_panels(mi.get_parent(), s, mi.position, body)
				_bx(mi.get_parent(), Vector3(s.x + 0.04, 0.08, s.z + 0.04), m("frame"), mi.position + Vector3(0, s.y / 2.0, 0), 0.02)
		elif mi.mesh is CylinderMesh:
			var cm := mi.mesh as CylinderMesh
			var r := maxf(cm.top_radius, cm.bottom_radius)
			if r < 0.09 and cm.height > 0.25:
				mi.material_override = m("frame")
			elif r < 0.2:
				mi.material_override = m("metal")
			elif extras and still and absf(cm.top_radius - cm.bottom_radius) < 0.01 and r >= 0.35 and cm.height >= 0.5:
				_bands(mi.get_parent(), r, cm.height, mi.position)
		elif mi.mesh is TorusMesh:
			mi.material_override = m("frame")
		elif mi.mesh is SphereMesh and (mi.mesh as SphereMesh).radius < 0.25:
			mi.material_override = m("metal")
	# Живые части (spin, fill и т. п.) только перекрашиваем — без лишних тел.
	var live := not String(c.name).begins_with("@") and mi == null
	for ch in c.get_children():
		_dress_node(ch, pnt, body, extras and not live)

# ---------------------------------------------------------------- машины 3D-завода

static func _intake(n: Node3D, body: Material) -> float:
	var y0 := base(n, body)
	var cat := "pneu"
	for i in 4:
		var a := i * TAU / 4.0 + PI / 4.0
		_bx(n, Vector3(0.12, 1.25, 0.12), m("frame"), Vector3(cos(a) * 0.62, y0 + 0.6, sin(a) * 0.62), 0.02)
	vessel(n, 0.32, 0.7, Vector3(0, y0 + 0.4, 0), cat, body)
	# Четырёхгранная воронка с разметкой по краю.
	var fy := y0 + 1.25
	var frot := Vector3(0, PI / 4.0, 0)
	_cy(n, 0.34, 0.75, paint(cat), Vector3(0, fy, 0), 0.95, frot, 4)
	_cy(n, 0.3, 0.72, m("dark"), Vector3(0, fy + 0.03, 0), 0.86, frot, 4)
	for i in 4:
		var a := i * PI / 2.0
		_bx(n, Vector3(1.4, 0.1, 0.1), m("trim"), Vector3(sin(a) * 0.67, fy + 0.4, cos(a) * 0.67), 0.02, Vector3(0, a, 0))
	gauge(n, Vector3(0.36, y0 + 0.55, 0.3), 0.6)
	# Ворошитель в горловине и пыль над воронкой, пока в приёмнике груз.
	var ag := _piv(n, Vector3(0, fy - 0.2, 0))
	anim(ag, "spin", {"speed": 4.0})
	_cy(ag, 0.04, 0.5, m("metal"), Vector3.ZERO, -1.0, Vector3.ZERO, 8)
	for i in 3:
		_bx(ag, Vector3(0.5, 0.03, 0.08), m("metal"), Vector3(0, 0.1, 0), 0.01, Vector3(0.4, i * TAU / 3.0, 0))
	puff(n, Vector3(0, fy + 0.45, 0), DUST, 0.35, 0.6, 6)
	# Внутри воронки — горка груза (цвет задаёт вид).
	var heap := MeshInstance3D.new()
	heap.name = "heap"
	var hm := SphereMesh.new()
	hm.radius = 0.6
	hm.height = 0.5
	heap.mesh = hm
	heap.position = Vector3(0, fy + 0.25, 0)
	heap.visible = false
	n.add_child(heap)
	lamp(n, Vector3(-0.75, y0 + 0.08, 0.75))
	return fy + 0.45

static func _pump(n: Node3D, body: Material) -> float:
	var y0 := base(n, body, 1.6, 1.3)
	var cat := "pneu"
	# Цилиндр с поршнем слева, мотор справа, маховик сзади.
	vessel(n, 0.3, 1.0, Vector3(-0.35, y0 + 0.5, 0), cat, body)
	var piston := _cy(n, 0.09, 0.8, m("metal"), Vector3(-0.35, y0 + 1.34, 0), -1.0, Vector3.ZERO, 12)
	anim(piston, "bob", {"amp": 0.13, "freq": 9.0})
	housing(n, Vector3(0.6, 0.55, 0.7), Vector3(0.4, y0 + 0.3, 0), cat, body)
	# Маховик со спицами: крутится, пока насос качает.
	var fw := _piv(n, Vector3(0.4, y0 + 0.75, -0.42), Vector3(PI / 2.0, 0, 0))
	anim(fw, "spin", {"speed": 9.0})
	_tor(fw, 0.3, 0.04, m("frame"), Vector3.ZERO)
	for i in 3:
		_bx(fw, Vector3(0.56, 0.05, 0.06), m("trim"), Vector3.ZERO, 0.01, Vector3(0, i * PI / 3.0, 0))
	_cy(fw, 0.08, 0.12, m("metal"), Vector3.ZERO, -1.0, Vector3.ZERO, 12)
	var d := Vector3(-0.35, y0 + 0.35, 0.6) - Vector3(-0.35, y0 + 1.0, 0.28)
	var tube := _cy(n, 0.07, d.length(), m("metal"), Vector3(-0.35, y0 + 0.675, 0.44), -1.0, Vector3.ZERO, 12)
	tube.basis = Basis(Quaternion(Vector3.UP, d.normalized()))
	gauge(n, Vector3(0.4, y0 + 0.75, 0.38), 0.0, true)
	outlet(n, Vector3(0.4, y0 + 0.2, 0.72))
	lamp(n, Vector3(0.62, y0 + 0.62, -0.1))
	return y0 + 1.5

static func _crusher(n: Node3D, body: Material) -> float:
	var y0 := base(n, body)
	var cat := "proc"
	housing(n, Vector3(1.2, 0.85, 1.1), Vector3(0, y0 + 0.43, 0), cat, body)
	var hy := y0 + 1.1
	_cy(n, 0.4, 0.5, m("frame"), Vector3(0, hy, 0), 0.72, Vector3(0, PI / 4.0, 0), 4)
	for i in 4:
		var a := i * PI / 2.0
		_bx(n, Vector3(1.04, 0.08, 0.08), m("trim"), Vector3(sin(a) * 0.5, hy + 0.25, cos(a) * 0.5), 0.02, Vector3(0, a, 0))
	# Валы с зубьями по бокам — видно, что мелет.
	for side in [-1.0, 1.0]:
		var rot := _piv(n, Vector3(side * 0.72, y0 + 0.5, 0))
		anim(rot, "spin", {"axis": Vector3.RIGHT, "speed": -7.0 * side})
		_cy(rot, 0.3, 0.14, m("frame"), Vector3.ZERO, -1.0, Vector3(0, 0, PI / 2.0), 16)
		for k in 8:
			var a := k * TAU / 8.0
			_bx(rot, Vector3(0.16, 0.12, 0.1), m("metal"), Vector3(0, cos(a) * 0.33, sin(a) * 0.33), 0.02, Vector3(-a, 0, 0))
		_cy(rot, 0.08, 0.2, m("trim"), Vector3(side * 0.05, 0, 0), -1.0, Vector3(0, 0, PI / 2.0), 12)
	# Бункер трясётся, над ним пыль, пока мелет.
	var hop := _piv(n, Vector3(0, hy + 0.3, 0))
	anim(hop, "shake", {"amp": 0.012, "freq": 14.0})
	_cy(hop, 0.36, 0.06, m("dark"), Vector3.ZERO, 0.66, Vector3(0, PI / 4.0, 0), 4)
	puff(n, Vector3(0, hy + 0.4, 0), DUST, 0.4, 0.7)
	outlet(n, Vector3(0, y0 + 0.25, 0.84))
	lamp(n, Vector3(0.45, y0 + 0.92, 0.42))
	return hy + 0.3

static func _furnace(n: Node3D, body: Material) -> float:
	var y0 := base(n, body)
	var cat := "proc"
	housing(n, Vector3(1.4, 1.2, 1.3), Vector3(0, y0 + 0.6, 0), cat, body)
	# Топка: раскалённое окно в раме, решётка.
	var fz := 0.66
	_bx(n, Vector3(0.8, 0.55, 0.06), m("frame"), Vector3(0, y0 + 0.62, fz), 0.03)
	var fire := _bx(n, Vector3(0.62, 0.38, 0.04), own_glow(Color(1.0, 0.45, 0.1), 4.0), Vector3(0, y0 + 0.62, fz + 0.02), 0.01)
	anim(fire, "glow", {"energy": 4.0, "freq": 7.0})
	for i in 4:
		_bx(n, Vector3(0.03, 0.4, 0.03), m("dark"), Vector3(-0.2 + i * 0.133, y0 + 0.62, fz + 0.05), 0.005)
	_cy(n, 0.2, 1.1, m("frame"), Vector3(0.42, y0 + 1.7, -0.35), -1.0, Vector3.ZERO, 16)
	_cy(n, 0.23, 0.12, m("trim"), Vector3(0.42, y0 + 2.0, -0.35), -1.0, Vector3.ZERO, 16)
	_cy(n, 0.25, 0.08, m("frame"), Vector3(0.42, y0 + 2.28, -0.35), -1.0, Vector3.ZERO, 16)
	puff(n, Vector3(0.42, y0 + 2.35, -0.35), SMOKE, 0.5, 1.0, 10)
	gauge(n, Vector3(-0.5, y0 + 1.05, 0.66))
	outlet(n, Vector3(0.52, y0 + 0.25, 0.8))
	lamp(n, Vector3(-0.55, y0 + 1.28, -0.5))
	return y0 + 1.25

## Бак: низ и верх — крашеный сосуд в раме, посередине стекло; уровень груза —
## узел "fill" (MachineModels._fill: масштаб по Y — доля заполнения).
static func _tank(n: Node3D, body: Material) -> float:
	var y0 := base(n, body)
	var cat := "store"
	var r := 0.72
	_cy(n, r, 0.35, paint(cat), Vector3(0, y0 + 0.18, 0), -1.0, Vector3.ZERO, 24)
	_cy(n, r, 0.3, paint(cat), Vector3(0, y0 + 1.5, 0), -1.0, Vector3.ZERO, 24)
	_sp(n, r, paint(cat), Vector3(0, y0 + 1.65, 0), true, 0.45)
	for y in [0.36, 1.34]:
		_cy(n, r + 0.05, 0.08, m("frame"), Vector3(0, y0 + y, 0), -1.0, Vector3.ZERO, 24)
	for i in 6:
		var a := i * TAU / 6.0
		_bx(n, Vector3(0.09, 1.9, 0.09), m("frame"), Vector3(cos(a) * (r + 0.07), y0 + 0.95, sin(a) * (r + 0.07)), 0.02)
	_cy(n, r + 0.02, 0.12, m("trim"), Vector3(0, y0 + 0.2, 0), -1.0, Vector3.ZERO, 24)
	_cy(n, r + 0.015, 0.12, body, Vector3(0, y0 + 1.5, 0), -1.0, Vector3.ZERO, 24)
	_cy(n, r - 0.03, 0.95, m("glass"), Vector3(0, y0 + 0.87, 0), -1.0, Vector3.ZERO, 24)
	_cy(n, 0.12, 0.3, m("frame"), Vector3(0, y0 + 2.05, 0), -1.0, Vector3.ZERO, 12)
	MachineModels._fill(n, r - 0.08, 0.95, y0 + 0.4)
	gauge(n, Vector3(0.5, y0 + 1.55, 0.55), 0.7)
	outlet(n, Vector3(0, y0 + 0.25, 0.84))
	lamp(n, Vector3(-0.6, y0 + 1.75, 0.35))
	return y0 + 2.15

static func _centrifuge(n: Node3D, body: Material) -> float:
	var y0 := base(n, body)
	var cat := "proc"
	# Восьмигранная станина, над ней барабан под стеклом, ротор виден.
	_cy(n, 0.78, 0.45, paint(cat), Vector3(0, y0 + 0.23, 0), 0.7, Vector3(0, PI / 8.0, 0), 8)
	_cy(n, 0.8, 0.08, m("frame"), Vector3(0, y0 + 0.48, 0), -1.0, Vector3(0, PI / 8.0, 0), 8)
	_cy(n, 0.8, 0.08, m("trim"), Vector3(0, y0 + 0.05, 0), -1.0, Vector3(0, PI / 8.0, 0), 8)
	_cy(n, 0.7, 0.55, m("glass"), Vector3(0, y0 + 0.8, 0), -1.0, Vector3.ZERO, 32)
	_tor(n, 0.72, 0.04, m("frame"), Vector3(0, y0 + 1.08, 0))
	var s := MachineModels._spin(n, Vector3(0, y0 + 0.78, 0), 14.0)
	_cy(s, 0.08, 0.5, m("metal"), Vector3.ZERO, -1.0, Vector3.ZERO, 12)
	for i in 4:
		var a := i * TAU / 4.0
		_bx(s, Vector3(0.5, 0.06, 0.08), m("frame"), Vector3(cos(a) * 0.28, 0.1, sin(a) * 0.28), 0.01, Vector3(0, -a, 0))
		_cy(s, 0.1, 0.3, paint(cat), Vector3(cos(a) * 0.55, 0.0, sin(a) * 0.55), -1.0, Vector3.ZERO, 12)
	housing(n, Vector3(0.5, 0.5, 0.4), Vector3(0, y0 + 0.3, -0.65), cat, body)
	gauge(n, Vector3(0.62, y0 + 0.6, 0.38), 0.8)
	outlet(n, Vector3(0, y0 + 0.25, 0.84))
	lamp(n, Vector3(-0.62, y0 + 1.2, -0.5))
	return y0 + 1.15

## Лаборатория: светлый стол в раме, пять щупов (по одному на пробу) под
## стеклянным колпаком, в центре — вращающаяся чашка с образцом ("sample"),
## спереди табло ("lamp": его цвет — состояние, материал свой).
static func _lab(n: Node3D, body: Material) -> float:
	var y0 := base(n, body)
	var cat := "logic"
	housing(n, Vector3(1.3, 0.6, 1.2), Vector3(0, y0 + 0.3, 0), cat, body)
	var top := y0 + 0.64
	_cy(n, 0.62, 0.06, m("frame"), Vector3(0, top, 0), -1.0, Vector3.ZERO, 32)
	_sp(n, 0.56, m("glass"), Vector3(0, top, 0), true, 0.75)
	var cup := _piv(n, Vector3(0, top + 0.08, 0))
	anim(cup, "spin", {"speed": 3.0})
	_cy(cup, 0.22, 0.08, m("metal"), Vector3.ZERO, 0.14, Vector3(PI, 0, 0), 16)
	var sample := MeshInstance3D.new()
	sample.name = "sample"
	var sm := SphereMesh.new()
	sm.radius = 0.12
	sm.height = 0.16
	sm.radial_segments = 6
	sm.rings = 3
	sample.mesh = sm
	sample.position = Vector3(0, 0.08, 0)
	sample.visible = false
	cup.add_child(sample)
	# Пять щупов по кругу — цвета проб (нагрев, капля, магнит, ток, счётчик).
	for i in 5:
		var a := i * TAU / 5.0
		_cy(n, 0.03, 0.42, m("frame"), Vector3(cos(a) * 0.32, top + 0.2, sin(a) * 0.32), 0.022, Vector3(sin(a) * 0.6, 0, -cos(a) * 0.6), 8)
		_sp(n, 0.045, m("probe%d" % i), Vector3(cos(a) * 0.2, top + 0.04, sin(a) * 0.2))
	# Табло спереди в раме.
	_bx(n, Vector3(0.6, 0.3, 0.06), m("frame"), Vector3(0, y0 + 0.36, 0.62), 0.02)
	var board := _bx(n, Vector3(0.5, 0.2, 0.03), ProtoMachines.glow(Color(0.3, 0.3, 0.3), 0.2), Vector3(0, y0 + 0.36, 0.65), 0.01)
	board.name = "lamp"
	return top + 0.45

# ---------------------------------------------------------------- движения за работой

## Живая часть с движением за работой. type и параметры:
##   "spin"  — axis (локальная ось), speed (рад/с): вращается, пока работает;
##   "bob"   — axis, amp, freq: ходит туда-обратно (поршень);
##   "press" — axis, amp, freq: резкий удар вдоль оси и медленный возврат (пресс);
##   "swing" — axis, amp, freq: качается вокруг оси (рычаг, батан);
##   "shake" — amp, freq: мелкая дрожь;
##   "glow"  — energy, freq: свечение своего материала дышит, в простое тускнеет;
##   "puff"  — CPUParticles3D: дым, пар, пыль, пузыри — только пока работает;
##   "flicker" — Light3D: свет пламени мерцает, в простое гаснет.
## Узел получает своё имя — живые части не склеивает ProtoBatch; name — если
## вид ищет часть по имени (оно должно быть единственным в модели).
static func anim(node: Node, type: String, params := {}, name := "") -> Node:
	var d := params.duplicate()
	d.type = type
	node.set_meta("anim", d)
	_anim_n += 1
	node.name = name if name != "" else "%s_%d" % [type, _anim_n]
	return node

static var _anim_n := 0

## Двигать живые части модели n; working — машина сейчас работает.
## Список частей и их исходное положение собираются при первом вызове.
static func animate(n: Node3D, working: bool, t: float, dt: float) -> void:
	if not n.has_meta("anims"):
		_collect(n)
	var ph: float = n.get_meta("anim_phase", 0.0)
	for a: Node in n.get_meta("anims"):
		if not is_instance_valid(a):
			continue
		var d: Dictionary = a.get_meta("anim")
		var tt := t + ph
		match d.type:
			"spin":
				if working:
					(a as Node3D).rotate_object_local(d.get("axis", Vector3.UP), d.get("speed", 3.0) * dt)
			"bob", "press", "shake":
				var base: Vector3 = a.get_meta("anim_pos")
				var off := Vector3.ZERO
				if working:
					var amp: float = d.get("amp", 0.1)
					var w: float = d.get("freq", 6.0) * tt
					match d.type:
						"bob": off = d.get("axis", Vector3.UP) * amp * sin(w)
						"press": off = -d.get("axis", Vector3.UP) * amp * pow(0.5 + 0.5 * sin(w), 6.0)
						"shake": off = Vector3(sin(w * 1.7), sin(w * 2.3), sin(w * 3.1)) * amp
				(a as Node3D).position = base + off
			"swing":
				var r: Vector3 = a.get_meta("anim_rot")
				var k: float = sin(d.get("freq", 4.0) * tt) * d.get("amp", 0.3) if working else 0.0
				(a as Node3D).rotation = r + d.get("axis", Vector3.RIGHT) * k
			"glow":
				var m := (a as GeometryInstance3D).material_override as StandardMaterial3D
				if m:
					var e: float = d.get("energy", 2.0)
					var f: float = d.get("freq", 5.0)
					m.emission_energy_multiplier = e * (0.8 + 0.2 * sin(f * tt) + 0.12 * sin(f * 2.7 * tt)) if working else e * 0.25
			"puff":
				var p := a as CPUParticles3D
				if p.emitting != working:
					p.emitting = working
			"flicker":
				var l := a as Light3D
				var e2: float = d.get("energy", 1.5)
				l.light_energy = e2 * (0.85 + 0.15 * sin(13.0 * tt) + 0.08 * sin(29.0 * tt)) if working else e2 * 0.25

static func _collect(n: Node3D) -> void:
	var list: Array = []
	var stack: Array = [n]
	while not stack.is_empty():
		var c: Node = stack.pop_back()
		if c != n and c.has_meta("anim"):
			list.append(c)
			if c is Node3D:
				c.set_meta("anim_pos", (c as Node3D).position)
				c.set_meta("anim_rot", (c as Node3D).rotation)
		stack.append_array(c.get_children())
	n.set_meta("anims", list)
	# Одинаковые машины рядом не качаются в такт.
	n.set_meta("anim_phase", float(n.get_instance_id() % 997) * 0.37)

## Свой светящийся материал (его дыхание не трогает другие машины).
static func own_glow(c: Color, e: float) -> StandardMaterial3D:
	return ProtoMachines.glow(c, e)

static var _puff_mats := {}
static var _puff_mesh: QuadMesh

## Дым, пар, пыль или пузыри: несколько мягких пятен вверх из точки pos.
static func puff(n: Node3D, pos: Vector3, col: Color, size := 0.35, up := 1.0, amount := 8) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.position = pos
	p.emitting = false
	p.amount = amount
	p.lifetime = 1.6
	p.local_coords = false
	p.direction = Vector3.UP
	p.spread = 12.0
	p.initial_velocity_min = 0.5 * up
	p.initial_velocity_max = 0.9 * up
	p.gravity = Vector3(0, 0.25 * up, 0)
	p.damping_min = 0.3
	p.damping_max = 0.6
	p.scale_amount_min = size * 0.7
	p.scale_amount_max = size
	var sc := Curve.new()
	# Растёт и тает к концу жизни (цвет вершин в Compatibility не доходит —
	# прозрачность задаёт материал, а исчезает пятно уменьшаясь).
	sc.add_point(Vector2(0, 0.4))
	sc.add_point(Vector2(0.6, 1.5))
	sc.add_point(Vector2(1, 0.0))
	p.scale_amount_curve = sc
	if _puff_mesh == null:
		_puff_mesh = QuadMesh.new()
		_puff_mesh.size = Vector2(1, 1)
	p.mesh = _puff_mesh
	var key := col.to_html()
	if not _puff_mats.has(key):
		var m := StandardMaterial3D.new()
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		m.albedo_color = Color(col, 0.5)
		m.albedo_texture = _soft_dot()
		_puff_mats[key] = m
	p.material_override = _puff_mats[key]
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.add_child(p)
	anim(p, "puff")
	return p

static var _dot: ImageTexture

static func _soft_dot() -> ImageTexture:
	if _dot == null:
		var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
		for y in 32:
			for x in 32:
				var r := Vector2(x - 15.5, y - 15.5).length() / 16.0
				img.set_pixel(x, y, Color(1, 1, 1, clampf(1.0 - r, 0.0, 1.0) ** 1.5))
		_dot = ImageTexture.create_from_image(img)
	return _dot

## Цвета дыма и пара.
const SMOKE := Color(0.35, 0.33, 0.32)
const STEAM := Color(0.92, 0.94, 0.97)
const DUST := Color(0.62, 0.55, 0.45)
const FROST := Color(0.75, 0.9, 1.0)
