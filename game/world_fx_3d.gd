class_name WorldFx3D
extends Node3D
## Подвижное в объёмном виде — то же, что 2D-вид рисует поверх клеток:
## капсулы пневмопушек и ракеты, метеоры и обломки, дроны с грузом, огонь,
## порции на земле, события (зоны метеоров и вспышек, гейзеры), провода логики
## и частицы FxLayer (дым, искры, иней, пар, пузыри, всплывающие надписи).
## Мир не меняет — только читает World и FxLayer 2D-вида каждый кадр.

const S := 2.0                   # метров на клетку, как TileTerrain.S
const DRONE_H := 2.6             # высота полёта дронов над рельефом
const MAX_TEXTS := 12

var world: World
var terrain: TileTerrain
var fx: FxLayer                  # частицы 2D-вида (обновляются им же)

var _shots: Array = []           # пул узлов снарядов
var _drones: Array = []          # пул узлов дронов
var _drone_prev: Array = []
var _fires := {}                 # Vector2i → узел огня
var _ground: Node3D
var _ground_sig := ""
var _event: Node3D
var _event_sig := ""
var _wires: Node3D
var _wire_sig := ""
var _parts: MultiMeshInstance3D
var _texts: Array = []
var _t := 0.0
var _mats := {}

func setup(w: World, t: TileTerrain, f: FxLayer) -> void:
	world = w
	terrain = t
	fx = f
	_ground = Node3D.new()
	add_child(_ground)
	_event = Node3D.new()
	add_child(_event)
	_wires = Node3D.new()
	add_child(_wires)
	_parts = MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var q := SphereMesh.new()
	q.radius = 0.5
	q.height = 1.0
	q.radial_segments = 6
	q.rings = 3
	mm.mesh = q
	mm.instance_count = FxLayer.MAX
	mm.visible_instance_count = 0
	_parts.multimesh = mm
	var pm := StandardMaterial3D.new()
	pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pm.vertex_color_use_as_albedo = true
	pm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_parts.material_override = pm
	_parts.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_parts)

func update(dt: float) -> void:
	if world == null:
		return
	_t += dt
	_update_shots()
	_update_drones(dt)
	_update_fires()
	_update_ground()
	_update_event()
	_update_wires()
	_update_particles()

## Рельеф под клетками поменялся: всё, что стоит на земле, переставить.
func terrain_changed() -> void:
	_ground_sig = ""
	_wire_sig = ""
	_event_sig = ""
	for c in _fires:
		_fires[c].position = terrain.cell_pos(c)

## Точка мира (в клетках, как World) на рельефе.
func _at(p: Vector2) -> Vector3:
	return terrain.world_pos(p)

func _glow(c: Color, e := 2.0) -> StandardMaterial3D:
	var key := "g%s%.1f" % [c.to_html(), e]
	if not _mats.has(key):
		_mats[key] = ProtoMachines.glow(c, e)
	return _mats[key]

func _flat(c: Color) -> StandardMaterial3D:
	var key := "f" + c.to_html()
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = 0.6
		if c.a < 1.0:
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_mats[key] = m
	return _mats[key]

## Мягкое круглое пятно для частиц огня и пара.
static var _soft: GradientTexture2D

static func soft_tex() -> GradientTexture2D:
	if _soft == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		_soft = GradientTexture2D.new()
		_soft.gradient = g
		_soft.fill = GradientTexture2D.FILL_RADIAL
		_soft.fill_from = Vector2(0.5, 0.5)
		_soft.fill_to = Vector2(0.5, 0.0)
		_soft.width = 64
		_soft.height = 64
	return _soft

static func _mesh_sphere(r: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 10
	s.rings = 5
	return s

static func _add(parent: Node3D, mesh: Mesh, m: Material, pos := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.mesh = mesh
	mi.material_override = m
	mi.position = pos
	parent.add_child(mi)
	return mi

# ---------------------------------------------------------------- снаряды

## Узел снаряда: капсула (тёмный корпус с поясом цвета груза), ракета или метеор.
func _shot_node() -> Node3D:
	var n := Node3D.new()
	var body := _add(n, _mesh_sphere(0.3), _flat(Color(0.15, 0.15, 0.18)))
	body.name = "body"
	body.scale = Vector3(1, 1, 1.5)
	var band := _add(n, _mesh_sphere(0.22), _flat(Color.WHITE))
	band.name = "band"
	band.scale = Vector3(1.45, 1.45, 0.5)
	var tail := CylinderMesh.new()
	tail.top_radius = 0.2
	tail.bottom_radius = 0.0
	tail.height = 1.0
	var tr := _add(n, tail, _glow(Color(1.0, 0.6, 0.2), 3.0))
	tr.name = "tail"
	var l := OmniLight3D.new()
	l.name = "light"
	l.omni_range = 4.0
	n.add_child(l)
	add_child(n)
	return n

func _update_shots() -> void:
	var list: Array = world.projectiles
	while _shots.size() < list.size():
		_shots.append(_shot_node())
	for i in _shots.size():
		var n: Node3D = _shots[i]
		n.visible = i < list.size()
		if not n.visible:
			continue
		var pr: Dictionary = list[i]
		var k: float = clampf(pr.t / maxf(pr.dur, 0.001), 0.0, 1.0)
		var a := _at(pr.from)
		var b := _at(pr.to)
		var body := n.get_node("body") as MeshInstance3D
		var band := n.get_node("band") as MeshInstance3D
		var tail := n.get_node("tail") as MeshInstance3D
		var light := n.get_node("light") as OmniLight3D
		var pos: Vector3
		var vel: Vector3
		match pr.kind:
			"meteor", "debris":
				# Падают с неба наискосок в точку удара.
				var from := b + (a - b).normalized() * 18.0 + Vector3(0, 30.0, 0)
				if (a - b).length() < 0.01:
					from = b + Vector3(6, 30, 0)
				pos = from.lerp(b, k)
				vel = b - from
				var hot: bool = pr.kind == "meteor"
				body.material_override = _glow(Color(1.0, 0.75, 0.35), 4.0) if hot else _flat(Color(0.75, 0.78, 0.85))
				body.scale = Vector3.ONE * (1.8 if hot else 1.0)
				band.visible = false
				tail.visible = true
				tail.material_override = _glow(Color(1.0, 0.55, 0.2), 3.0) if hot else _glow(Color(0.75, 0.8, 0.9), 0.6)
				tail.scale = Vector3(1.6, 5.0, 1.6) if hot else Vector3(1.0, 3.0, 1.0)
				light.visible = hot
				light.light_color = Color(1.0, 0.55, 0.2)
				light.light_energy = 3.0
			"rocket":
				pos = a + Vector3(0, 60.0 * k * k, 0)
				vel = Vector3.UP
				body.material_override = _flat(Color(0.85, 0.85, 0.9))
				body.scale = Vector3(1.2, 1.2, 3.5)
				band.visible = false
				tail.visible = true
				tail.material_override = _glow(Color(1.0, 0.7, 0.2), 4.0)
				tail.scale = Vector3(2.5, 3.0 + randf(), 2.5)
				light.visible = true
				light.light_color = Color(1.0, 0.7, 0.3)
				light.light_energy = 4.0
			_:
				# Капсула пневмопушки: дуга, как в 2D (высота — треть дальности).
				var h := a.distance_to(b) * 0.35
				pos = a.lerp(b, k) + Vector3(0, 1.4 + sin(PI * k) * h, 0)
				vel = (b - a) + Vector3(0, cos(PI * k) * PI * h, 0)
				body.material_override = _flat(Color(0.15, 0.15, 0.18))
				body.scale = Vector3(1, 1, 1.5)
				band.visible = true
				var col := Color(0.85, 0.85, 0.9)
				if not pr.payload.is_empty():
					col = pr.payload[0].substance.color
				band.material_override = _glow(col, 1.2)
				tail.visible = true
				tail.material_override = _glow(Color(0.8, 0.9, 1.0, 0.6), 0.8)
				tail.scale = Vector3(0.6, 0.9, 0.6)
				light.visible = false
		n.position = pos
		if vel.length() > 0.001:
			var up := Vector3.UP if absf(vel.normalized().y) < 0.99 else Vector3.RIGHT
			n.look_at(pos + vel, up)
		# Хвост — позади по ходу (узел смотрит в −Z).
		tail.position = Vector3(0, 0, 0.3 + tail.scale.y * 0.5)
		tail.rotation = Vector3(PI / 2.0, 0, 0)

# ---------------------------------------------------------------- дроны

## Дрон: корпус, четыре винта на лучах, огонёк; груз висит снизу.
func _drone_node() -> Node3D:
	var n := Node3D.new()
	var hull := BoxMesh.new()
	hull.size = Vector3(0.45, 0.14, 0.45)
	_add(n, hull, _flat(Color(0.8, 0.88, 0.95)))
	for i in 4:
		var a := PI / 4.0 + i * PI / 2.0
		var arm := BoxMesh.new()
		arm.size = Vector3(0.62, 0.04, 0.05)
		var am := _add(n, arm, _flat(Color(0.3, 0.32, 0.36)), Vector3(cos(a), 0, sin(a)) * 0.3)
		am.rotation.y = -a
		var rotor := CylinderMesh.new()
		rotor.top_radius = 0.2
		rotor.bottom_radius = 0.2
		rotor.height = 0.015
		var r := _add(n, rotor, _flat(Color(0.7, 0.75, 0.8, 0.45)), Vector3(cos(a), 0.09, sin(a)) * 0.58 + Vector3(0, 0.09, 0))
		r.name = "rotor%d" % i
	_add(n, _mesh_sphere(0.06), _glow(Color(0.4, 0.9, 1.0), 3.0), Vector3(0, 0, 0.25))
	var cable := CylinderMesh.new()
	cable.top_radius = 0.01
	cable.bottom_radius = 0.01
	cable.height = 0.5
	var c := _add(n, cable, _flat(Color(0.2, 0.2, 0.2)), Vector3(0, -0.3, 0))
	c.name = "cable"
	var cargo := _add(n, _mesh_sphere(0.16), _flat(Color.WHITE), Vector3(0, -0.6, 0))
	cargo.name = "cargo"
	add_child(n)
	return n

func _update_drones(dt: float) -> void:
	var list: Array = world.drones
	while _drones.size() < list.size():
		_drones.append(_drone_node())
		_drone_prev.append(Vector2.ZERO)
	for i in _drones.size():
		var n: Node3D = _drones[i]
		n.visible = i < list.size()
		if not n.visible:
			continue
		var d: Dictionary = list[i]
		var p: Vector2 = d.pos
		var moved: Vector2 = p - _drone_prev[i]
		_drone_prev[i] = p
		n.position = _at(p) + Vector3(0, DRONE_H + 0.12 * sin(_t * 3.0 + i), 0)
		if moved.length() > 0.0005:
			n.rotation.y = lerp_angle(n.rotation.y, atan2(moved.x, moved.y), minf(1.0, dt * 8.0))
			n.rotation.x = 0.18
		else:
			n.rotation.x = 0.0
		for r in 4:
			var rotor := n.get_node("rotor%d" % r) as Node3D
			rotor.rotation.y += dt * 40.0
		var has: bool = d.cargo != null
		(n.get_node("cable") as Node3D).visible = has
		var cargo := n.get_node("cargo") as MeshInstance3D
		cargo.visible = has
		if has:
			cargo.material_override = _flat(d.cargo.substance.color)

# ---------------------------------------------------------------- огонь

func _fire_node() -> Node3D:
	var n := Node3D.new()
	var p := CPUParticles3D.new()
	p.amount = 28
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.lifetime = 0.9
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.6
	p.direction = Vector3.UP
	p.spread = 12.0
	p.gravity = Vector3(0, 2.5, 0)
	p.initial_velocity_min = 0.6
	p.initial_velocity_max = 1.6
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.0
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.6))
	curve.add_point(Vector2(0.3, 1.0))
	curve.add_point(Vector2(1, 0.0))
	p.scale_amount_curve = curve
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.9, 0.4, 1.0))
	grad.set_color(1, Color(0.4, 0.1, 0.05, 0.0))
	grad.add_point(0.4, Color(1.0, 0.4, 0.08, 0.9))
	p.color_ramp = grad
	var q := QuadMesh.new()
	q.size = Vector2(0.8, 0.8)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_texture = soft_tex()
	q.material = m
	p.mesh = q
	p.position = Vector3(0, 0.3, 0)
	n.add_child(p)
	var l := OmniLight3D.new()
	l.name = "light"
	l.light_color = Color(1.0, 0.5, 0.15)
	l.light_energy = 2.0
	l.omni_range = 5.0
	l.position = Vector3(0, 1.0, 0)
	n.add_child(l)
	# Обугленное пятно под огнём.
	var scorch := CylinderMesh.new()
	scorch.top_radius = 0.9
	scorch.bottom_radius = 0.9
	scorch.height = 0.02
	_add(n, scorch, _flat(Color(0.08, 0.06, 0.05, 0.7)), Vector3(0, 0.03, 0))
	add_child(n)
	return n

func _update_fires() -> void:
	for c in _fires.keys():
		if not world.fires.has(c):
			_fires[c].queue_free()
			_fires.erase(c)
	for c in world.fires:
		if not _fires.has(c):
			_fires[c] = _fire_node()
			_fires[c].position = terrain.cell_pos(c)
		var l := _fires[c].get_node("light") as OmniLight3D
		l.light_energy = 1.6 + 0.6 * sin(_t * 17.0 + c.x) + 0.3 * sin(_t * 29.0 + c.y)

# ---------------------------------------------------------------- порции на земле

## Порции, выброшенные или выпавшие на клетку: твёрдое — куски, жидкое — лужица.
func _update_ground() -> void:
	var parts := PackedStringArray()
	for c in world.ground:
		for p in world.ground[c]:
			parts.append("%d,%d:%s:%.1f" % [c.x, c.y, p.substance.id, p.mass])
	var sig := ";".join(parts)
	if sig == _ground_sig:
		return
	_ground_sig = sig
	for ch in _ground.get_children():
		ch.queue_free()
	for c in world.ground:
		var i := 0
		for p in world.ground[c]:
			var col: Color = p.substance.color
			# Раскладка 3×N внутри клетки, как в 2D.
			var off := Vector2(-0.5 + (i % 3) * 0.5, -0.4 + (i / 3) * 0.5) * S * 0.6
			var base := terrain.cell_pos(c) + Vector3(off.x, 0, off.y)
			base.y = terrain.surface_h(base.x, base.z)
			var sz: float = clampf(0.12 + p.mass * 0.02, 0.12, 0.35)
			var mi := MeshInstance3D.new()
			if p.phase() == Substance.Phase.LIQUID:
				var pud := CylinderMesh.new()
				pud.top_radius = sz * 1.8
				pud.bottom_radius = sz * 1.8
				pud.height = 0.03
				pud.radial_segments = 14
				mi.mesh = pud
				var lm := StandardMaterial3D.new()
				lm.albedo_color = Color(col, 0.85)
				lm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				lm.roughness = 0.05
				lm.metallic = 0.3
				mi.material_override = lm
				mi.position = base + Vector3(0, 0.03, 0)
			else:
				var b := BoxMesh.new()
				b.size = Vector3(sz * 2.0, sz * 1.4, sz * 2.0)
				mi.mesh = b
				mi.material_override = ProtoMachines.surface(p.substance)
				mi.position = base + Vector3(0, sz * 0.6, 0)
				mi.rotation = Vector3(0.2 * sin(i + c.x), (i * 1.7 + c.y) * 0.9, 0.2 * cos(i + c.y))
			_ground.add_child(mi)
			i += 1

# ---------------------------------------------------------------- события

func _update_event() -> void:
	var d: EventDirector = world.director
	var sig := "" if d.current.is_empty() else "%s:%s:%s:%s" % [d.current.id, d.current.phase, d.current.get("center", []), d.current.get("radius", 0)]
	if sig != _event_sig:
		_event_sig = sig
		for ch in _event.get_children():
			ch.queue_free()
		if sig != "":
			_build_event(d)
	if _event.get_child_count() > 0 and not d.current.is_empty():
		var warn: bool = d.current.phase == "warn"
		var k := 0.5 + 0.5 * sin(_t * (6.0 if warn else 3.0))
		var ring := _event.get_node_or_null("ring") as MeshInstance3D
		if ring != null:
			(ring.material_override as StandardMaterial3D).emission_energy_multiplier = 0.8 + 1.8 * k

func _build_event(d: EventDirector) -> void:
	var id: String = d.current.id
	var ctr := terrain.cell_pos(d.center())
	var warn: bool = d.current.phase == "warn"
	match id:
		"meteors", "flare":
			var col := Color(1.0, 0.45, 0.2) if id == "meteors" else Color(0.8, 0.5, 1.0)
			var r: float = (float(d.current.radius) + 0.5) * S
			# Сам круг зоны рисует WorldView3D._event_zone.
			if not warn:
				# Зона накрыта: полупрозрачный купол над ней.
				var dome := SphereMesh.new()
				dome.radius = r
				dome.height = r * 0.6
				dome.is_hemisphere = true
				var dm := StandardMaterial3D.new()
				dm.albedo_color = Color(col, 0.08)
				dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				dm.cull_mode = BaseMaterial3D.CULL_DISABLED
				_add(_event, dome, dm, ctr)
		"geyser":
			var p := CPUParticles3D.new()
			p.amount = 40 if not warn else 10
			p.lifetime = 1.6
			p.direction = Vector3.UP
			p.spread = 8.0
			p.initial_velocity_min = 4.0 if not warn else 0.8
			p.initial_velocity_max = 7.0 if not warn else 1.5
			p.gravity = Vector3(0, -3.0, 0)
			p.scale_amount_min = 0.6
			p.scale_amount_max = 1.4
			var q := QuadMesh.new()
			q.size = Vector2(0.6, 0.6)
			var m := StandardMaterial3D.new()
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.albedo_color = Color(0.88, 0.93, 1.0, 0.45)
			m.albedo_texture = soft_tex()
			q.material = m
			p.mesh = q
			p.position = ctr + Vector3(0, 0.2, 0)
			_event.add_child(p)
			var vent := CylinderMesh.new()
			vent.top_radius = 0.35
			vent.bottom_radius = 0.6
			vent.height = 0.3
			_add(_event, vent, _flat(Color(0.35, 0.33, 0.3)), ctr + Vector3(0, 0.1, 0))
		_:
			pass

# ---------------------------------------------------------------- провода логики

func _update_wires() -> void:
	var parts := PackedStringArray()
	for wid in world.logic.wires:
		var w: Dictionary = world.logic.wires[wid]
		parts.append("%s:%s>%s:%s:%s" % [wid, w.from, w.to, w.points.size(), world.logic.outputs.get(w.from, false)])
	var sig := ";".join(parts)
	if sig == _wire_sig:
		return
	_wire_sig = sig
	for ch in _wires.get_children():
		ch.queue_free()
	for w in world.logic.wires.values():
		var a = world.machines.get(w.from)
		var b = world.machines.get(w.to)
		if a == null or b == null:
			continue
		var on: bool = world.logic.outputs.get(w.from, false)
		var m := _glow(Color(1.0, 0.85, 0.2), 2.0) if on else _flat(Color(0.5, 0.5, 0.45))
		var pts: Array = [terrain.cell_pos(a.cell)]
		for p in w.points:
			pts.append(_at(p))
		pts.append(terrain.cell_pos(b.cell))
		for i in pts.size() - 1:
			_wire_seg(pts[i] + Vector3(0, 0.25, 0), pts[i + 1] + Vector3(0, 0.25, 0), m)
		for p in w.points:
			_add(_wires, _mesh_sphere(0.08), m, _at(p) + Vector3(0, 0.25, 0))

func _wire_seg(a: Vector3, b: Vector3, m: Material) -> void:
	var len := a.distance_to(b)
	if len < 0.01:
		return
	var c := CylinderMesh.new()
	c.top_radius = 0.035
	c.bottom_radius = 0.035
	c.height = len
	c.radial_segments = 4
	var mi := _add(_wires, c, m, (a + b) / 2.0)
	var dir := (b - a).normalized()
	var up := Vector3.UP if absf(dir.y) < 0.99 else Vector3.RIGHT
	mi.look_at(mi.position + dir, up)
	mi.rotate_object_local(Vector3.RIGHT, PI / 2.0)

# ---------------------------------------------------------------- частицы 2D

## Частицы FxLayer — в объём: место на земле из 2D, высота — по возрасту и виду.
func _update_particles() -> void:
	if fx == null:
		_parts.multimesh.visible_instance_count = 0
		return
	var mm := _parts.multimesh
	var n := 0
	var ti := 0
	for p in fx.parts:
		var k: float = clampf(p.life / p.max, 0.0, 1.0)
		var age: float = p.max - p.life
		var pos: Vector2 = p.pos / FxLayer.T
		var base := _at(pos)
		if p.kind == "text":
			if ti < MAX_TEXTS:
				_text(ti, base + Vector3(0, 2.4 + age * 0.8, 0), p.text, Color(p.col, minf(1.0, k * 2.0)))
				ti += 1
			continue
		var y := 0.6
		var sz: float = p.size / FxLayer.T * S * 0.6
		match p.kind:
			"smoke", "vapor":
				y = 1.0 + age * 1.3
				sz *= 1.3
			"bubble":
				y = 0.9 + age * 0.8
			"spark":
				y = 1.0 + age * 2.5 - age * age * 5.0
			"drip":
				y = maxf(0.05, 1.0 - age * 1.5)
			"dust":
				y = 0.2 + age * 0.4
			"frost":
				y = 0.5 + age * 0.3
			"ring":
				y = 0.15
				sz = (p.size + (1.0 - k) * 18.0) / FxLayer.T * S
			"bolt":
				y = 1.5 + randf() * 1.0
		if y < 0.0:
			continue
		var col: Color = p.col
		col.a *= k
		var basis := Basis.from_scale(Vector3.ONE * maxf(sz, 0.03))
		if p.kind == "ring":
			basis = Basis.from_scale(Vector3(sz * 2.0, 0.02, sz * 2.0))
		mm.set_instance_transform(n, Transform3D(basis, base + Vector3(0, y, 0)))
		mm.set_instance_color(n, col)
		n += 1
		if n >= mm.instance_count:
			break
	mm.visible_instance_count = n
	for i in range(ti, _texts.size()):
		_texts[i].visible = false

func _text(i: int, at: Vector3, s: String, col: Color) -> void:
	while _texts.size() <= i:
		var l := Label3D.new()
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.font_size = 40
		l.pixel_size = 0.004
		l.outline_size = 12
		l.outline_modulate = Color(0.05, 0.06, 0.08, 0.8)
		l.no_depth_test = true
		add_child(l)
		_texts.append(l)
	var l: Label3D = _texts[i]
	l.visible = true
	l.text = s
	l.position = at
	l.modulate = col
