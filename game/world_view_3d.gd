extends Node3D
## Объёмный вид игры (F3 — переключить с 2D). Рисует тот же мир рана, что и
## 2D-вид: рельеф из клеток планеты (TileTerrain), небо и свет по тегам
## (ProtoSky), залежи, машины и робота игрока (RobotDesigns). Ввод не читает:
## робот ходит по World, как в 2D, вид только следует за ним. Клетка под
## курсором — луч из камеры в рельеф (для стройки и Q/T/R).

const S := 2.0                   # метров на клетку игры, как TileTerrain.S
const CAM_BACK := 6.5            # камера сзади-сверху, смотрит на север карты (−z), как 2D
const CAM_UP := 4.6

var world: World
var main                         # game/main.gd — зум камеры и клетка под курсором
var terrain: TileTerrain
var robot: Node3D
var anim: RobotAnim
var cam: Camera3D
var env: Environment
var particles: CPUParticles3D
var cursor: MeshInstance3D
var _content: Node3D
var _chunks := {}                # Vector2i → Node3D: кусок рельефа с жидкостями
var _ground_mat: Material
var _world_env: WorldEnvironment
var _liquid_mats := {}
const CHUNK := 32                # ячеек сетки рельефа в куске (16 м)
var _machines: Node3D
var _deposits := {}              # Vector2i → [узел залежи, узел «камешка» до разведки]
var _machine_sig := ""
var _sync_t := 0.0
var _last_pos := Vector2.ZERO
var _yaw := PI
var build_ms := 0
var _live := {}                  # id машины → живые части модели (лампа, вращение, груз)
var _fx3d: WorldFx3D             # снаряды, дроны, огонь, порции, события, частицы
var _t := 0.0

func set_world(w: World) -> void:
	world = w
	if _content != null:
		_content.queue_free()
	_deposits.clear()
	_live.clear()
	_liquid_mats.clear()
	_machine_sig = ""
	_content = Node3D.new()
	add_child(_content)
	var t0 := Time.get_ticks_msec()
	terrain = TileTerrain.new(world)
	ProtoSky.palette(world.planet, terrain)
	_ground_mat = terrain.material()
	_chunks.clear()
	var n := terrain.grid_n()
	for cz in ceili(float(n.y) / CHUNK):
		for cx in ceili(float(n.x) / CHUNK):
			_build_chunk(Vector2i(cx, cz))
	var sky := ProtoSky.build(world.planet, _content)
	env = sky.env
	_world_env = sky.world_env
	particles = sky.particles
	_ruins()
	_build_deposits()
	_machines = Node3D.new()
	_content.add_child(_machines)
	_robot()
	_cursor()
	_fx3d = WorldFx3D.new()
	_content.add_child(_fx3d)
	_fx3d.setup(world, terrain, main.view.fx if main != null and main.view != null else null)
	cam = Camera3D.new()
	cam.fov = 55.0
	cam.far = 400.0
	_content.add_child(cam)
	_last_pos = world.robot.pos
	robot.position = terrain.world_pos(world.robot.pos)
	_sync(0.0, true)
	_follow(1.0)
	build_ms = Time.get_ticks_msec() - t0
	print("3D-вид: рельеф %d×%d м, %d мс" % [terrain.sx, terrain.sz, build_ms])

## Включить или спрятать: спрятанный вид не рисуется и не держит камеру и небо.
func activate(on: bool) -> void:
	visible = on
	if cam != null:
		if on:
			cam.make_current()
		else:
			cam.clear_current(false)
	if _world_env != null:
		_world_env.environment = env if on else null

# ---------------------------------------------------------------- построение

## Кусок рельефа: карта высот и гладь лавы и кислоты над ним.
func _build_chunk(k: Vector2i) -> void:
	if _chunks.has(k):
		_chunks[k].queue_free()
	var r := Rect2i(k * CHUNK, Vector2i(CHUNK, CHUNK))
	var node := Node3D.new()
	var ground := MeshInstance3D.new()
	ground.mesh = terrain.build_height_mesh(r)
	ground.material_override = _ground_mat
	node.add_child(ground)
	for t in [Planet.Tile.LAVA, Planet.Tile.ACID]:
		var mesh := terrain.liquid_mesh(t, terrain.liquid_level(), r)
		if mesh == null:
			continue
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = _liquid_mat(t)
		node.add_child(mi)
	_content.add_child(node)
	_chunks[k] = node

## Клетки игры сменили тип: пересчитать сетку и перестроить задетые куски.
func _refresh_tiles() -> void:
	var cells := terrain.changed_cells()
	if cells.is_empty():
		return
	var dirty := {}
	var per := int(S / TileTerrain.STEP)       # узлов сетки на клетку
	for c in cells:
		# Высоты плавно переходят через соседние клетки — захватываем их.
		var r := Rect2i((c - Vector2i(2, 2)) * per, Vector2i(5, 5) * per)
		terrain.fill_grid(r)
		for cz in range(floori(float(r.position.y - 1) / CHUNK), floori(float(r.end.y + 1) / CHUNK) + 1):
			for cx in range(floori(float(r.position.x - 1) / CHUNK), floori(float(r.end.x + 1) / CHUNK) + 1):
				if _chunks.has(Vector2i(cx, cz)):
					dirty[Vector2i(cx, cz)] = true
	for k in dirty:
		_build_chunk(k)
	for c in _deposits:
		_deposits[c][0].position = terrain.cell_pos(c)
		_deposits[c][1].position = terrain.cell_pos(c) + Vector3(0, 0.04, 0)
	_machine_sig = ""
	if _fx3d != null:
		_fx3d.terrain_changed()

## Шейдер жидкостей прототипа: лава — с коркой и свечением, кислота — с пузырями.
func _liquid_mat(t: int) -> Material:
	if _liquid_mats.has(t):
		return _liquid_mats[t]
	var m := ProtoLiquids.material(Substance.new("liq", "liq"), world.planet.ambient_temp)
	if t == Planet.Tile.LAVA:
		m.set_shader_parameter("base_color", Color(0.85, 0.28, 0.06, 1.0))
		m.set_shader_parameter("glow", 1.4)
		m.set_shader_parameter("crust", 1.0)
		m.set_shader_parameter("speed", 0.3)
		m.set_shader_parameter("rough", 0.6)
	else:
		m.set_shader_parameter("base_color", Color(0.45, 0.7, 0.12, 0.8))
		m.set_shader_parameter("glow", 0.25)
		m.set_shader_parameter("bubbles", 1.0)
	_liquid_mats[t] = m
	return m

## Руины: обломки колонн и плит на клетках руин.
func _ruins() -> void:
	var rng := RandomNumberGenerator.new()
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color(0.55, 0.52, 0.47)
	stone.roughness = 0.95
	for y in world.planet.height:
		for x in world.planet.width:
			var c := Vector2i(x, y)
			if world.tile(c) != Planet.Tile.RUIN:
				continue
			rng.seed = hash(c) ^ world.planet.seed_value
			if rng.randf() > 0.45:
				continue
			var p := terrain.cell_pos(c) + Vector3(rng.randf_range(-0.5, 0.5), 0, rng.randf_range(-0.5, 0.5))
			var mi := MeshInstance3D.new()
			if rng.randf() < 0.5:
				var cy := CylinderMesh.new()
				cy.top_radius = 0.28
				cy.bottom_radius = 0.32
				cy.height = rng.randf_range(0.6, 2.4)
				cy.radial_segments = 8
				mi.mesh = cy
				mi.position = p + Vector3(0, cy.height / 2.0, 0)
			else:
				var b := BoxMesh.new()
				b.size = Vector3(rng.randf_range(0.6, 1.4), rng.randf_range(0.2, 0.5), rng.randf_range(0.6, 1.4))
				mi.mesh = b
				mi.position = p + Vector3(0, b.size.y / 2.0, 0)
				mi.rotation = Vector3(rng.randf_range(-0.15, 0.15), rng.randf() * TAU, 0)
			mi.material_override = stone
			_content.add_child(mi)

## Залежи: у разведанных и тех, что рядом с роботом, — самородки или друзы
## кристаллов цвета вещества; у прочих — серый камешек, как метка в 2D.
func _build_deposits() -> void:
	var rng := RandomNumberGenerator.new()
	var mats := {}
	for c in world.planet.deposits:
		var dep: Dictionary = world.planet.deposits[c]
		var s: Substance = world.db.get_sub(dep.sub)
		if s == null:
			continue
		if not mats.has(s.id):
			mats[s.id] = ProtoCrystal.material(s.color) if s.has("crystalline") else ProtoMachines.surface(s)
		rng.seed = hash(c) ^ world.planet.seed_value
		var base := terrain.cell_pos(c)
		var n := Node3D.new()
		n.position = base
		var k: float = clampf(0.5 + dep.amount / 150.0, 0.6, 1.5)
		if s.has("crystalline"):
			for i in rng.randi_range(4, 7):
				var len := rng.randf_range(0.35, 0.9) * k
				var ci := MeshInstance3D.new()
				ci.mesh = ProtoCrystal.mesh(len, len * rng.randf_range(0.12, 0.17), rng)
				ci.material_override = mats[s.id]
				var off := Vector3(rng.randf_range(-0.55, 0.55), -len * 0.1, rng.randf_range(-0.55, 0.55))
				ci.position = off
				ci.rotation = Vector3(rng.randf_range(-0.5, 0.5), rng.randf() * TAU, rng.randf_range(-0.5, 0.5))
				n.add_child(ci)
		else:
			for i in rng.randi_range(3, 6):
				var r := rng.randf_range(0.14, 0.32) * k
				var sp := SphereMesh.new()
				sp.radius = r
				sp.height = r * 1.4
				sp.radial_segments = 6
				sp.rings = 3
				var mi := MeshInstance3D.new()
				mi.mesh = sp
				mi.material_override = mats[s.id]
				mi.position = Vector3(rng.randf_range(-0.6, 0.6), r * 0.35, rng.randf_range(-0.6, 0.6))
				mi.rotation = Vector3(rng.randf(), rng.randf() * TAU, rng.randf())
				n.add_child(mi)
		_content.add_child(n)
		var pebble := MeshInstance3D.new()
		var ps := SphereMesh.new()
		ps.radius = 0.16
		ps.height = 0.16
		ps.radial_segments = 6
		ps.rings = 3
		pebble.mesh = ps
		var pm := StandardMaterial3D.new()
		pm.albedo_color = Color(0.55, 0.5, 0.45)
		pebble.material_override = pm
		pebble.position = base + Vector3(0, 0.04, 0)
		_content.add_child(pebble)
		_deposits[c] = [n, pebble]

func _robot() -> void:
	var hull_col: Color = world.robot.hull.sub.color if world.robot.hull != null else Color(0, 0, 0, 0)
	robot = RobotDesigns.build("clean", hull_col)
	anim = robot.get_node_or_null("anim")
	if anim:
		anim.mode = "play"          # скорость задаёт вид — по движению робота в мире
	_content.add_child(robot)
	var lamp := robot.find_child("head_lamp", true, false) as SpotLight3D
	if lamp:
		lamp.light_energy = 1.5

func _cursor() -> void:
	cursor = MeshInstance3D.new()
	var q := BoxMesh.new()
	q.size = Vector3(S * 0.96, 0.06, S * 0.96)
	cursor.mesh = q
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.4, 0.9, 1.0, 0.16)
	cursor.material_override = m
	_content.add_child(cursor)

# ---------------------------------------------------------------- машины

func _machine_node(m: Machine) -> Node3D:
	var body := ProtoMachines.surface(m.built_from) if m.built_from != null else ProtoMachines.surface(world.starter)
	var n := MachineModels.build(m.kind, body)
	n.position = terrain.cell_pos(m.cell)
	var d: Vector2i = Machine.DIRS[m.facing]
	n.rotation.y = atan2(float(d.x), float(d.y))
	if m.outputs() == 2:
		var d2: Vector2i = Machine.DIRS[(m.facing + 1) % 4]
		MachineModels.add_outlet(n, n.basis.inverse() * Vector3(d2.x, 0, d2.y))
	_live[m.id] = {"node": n, "lamp": n.get_node_or_null("lamp"), "spin": n.find_child("spin", true, false),
		"fill": n.get_node_or_null("fill"), "h": float(n.get_meta("h", 1.2)), "busy": null, "light": null}
	if m.stats.get("light", false):
		var l := OmniLight3D.new()
		l.light_color = Color(1, 1, 0.75)
		l.light_energy = 0.8
		l.omni_range = 5.0
		l.position = Vector3(0, _live[m.id].h + 0.5, 0)
		n.add_child(l)
	return n

## Склад и пневмобатарея 2×2: главная секция несёт общую крышу или тяжёлый ствол.
func _structure_node(m: Machine) -> Node3D:
	var body := ProtoMachines.surface(m.built_from if m.built_from != null else world.starter)
	var n := Node3D.new()
	n.position = (terrain.cell_pos(m.cell) + terrain.cell_pos(m.cell + Vector2i(1, 1))) / 2.0
	if m.kind == "warehouse_section":
		var roof := MeshInstance3D.new()
		var pr := PrismMesh.new()
		pr.size = Vector3(4.0, 0.8, 4.0)
		roof.mesh = pr
		roof.material_override = body
		roof.position = Vector3(0, 1.75, 0)
		n.add_child(roof)
	else:
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.38
		cyl.bottom_radius = 0.5
		cyl.height = 3.4
		var barrel := MeshInstance3D.new()
		barrel.mesh = cyl
		barrel.material_override = body
		var d: Vector2i = Machine.DIRS[m.facing]
		barrel.position = Vector3(d.x, 0, d.y) * 0.9 + Vector3(0, 2.6, 0)
		barrel.rotation.y = atan2(float(d.x), float(d.y))
		barrel.rotate_object_local(Vector3.RIGHT, PI / 2.0 - 0.55)
		n.add_child(barrel)
	return n

## Меняющаяся часть машин каждый кадр: лампа, вращение, груз, порция в работе.
func _update_live(dt: float) -> void:
	_t += dt
	for id in _live:
		var m = world.machines.get(id)
		if m == null:
			continue
		var L: Dictionary = _live[id]
		var working: bool = m.hot or (m is Processor and m.busy != null)
		if m is Drill or m.kind in ["pump", "fabricator", "beacon", "resonator"]:
			working = working or m.enabled
		if L.lamp != null:
			var key := "lamp_idle"
			if not m.enabled:
				key = "lamp_off"
			elif world.logic.outputs.get(id, false):
				key = "lamp_sig"
			elif working:
				key = "lamp_work"
			L.lamp.material_override = MachineModels.mat(key)
		if L.spin != null and working:
			L.spin.rotation.y += dt * (9.0 if m.kind in ["centrifuge", "drill"] else 2.5)
		if L.fill != null and m.capacity() > 0.0:
			var f: float = clampf(m.total_mass() / m.capacity(), 0.0, 1.0)
			L.fill.scale.y = maxf(0.001, f * float(L.fill.get_meta("h", 1.0)))
			L.fill.visible = f > 0.001
			if f > 0.001:
				var fm := L.fill.get_node("fill_mesh") as MeshInstance3D
				var col: Color = m.items[0].substance.color
				if fm.get_meta("col", Color.TRANSPARENT) != col:
					fm.set_meta("col", col)
					(fm.material_override as StandardMaterial3D).albedo_color = col
		# Порция в работе едет от входа (сзади) к центру, как в 2D.
		var busy = m.busy if m is Processor else null
		if busy != null:
			if L.busy == null:
				L.busy = _portion_mesh(busy.substance, 0.16, false)
				L.node.add_child(L.busy)
			var k: float = clampf(m.progress / m.proc.dur, 0.0, 1.0)
			L.busy.position = Vector3(0, L.h + 0.25 + 0.05 * sin(_t * 8.0), -0.8 * (1.0 - k))
		elif L.busy != null:
			L.busy.queue_free()
			L.busy = null

func _rebuild_machines() -> void:
	for ch in _machines.get_children():
		ch.queue_free()
	_live.clear()
	var mats := {}
	for id in world.machines:
		var m: Machine = world.machines[id]
		_machines.add_child(_machine_node(m))
		if m.kind in ["warehouse_section", "battery_section"] and m.master_id == m.id:
			_machines.add_child(_structure_node(m))
		if m.kind == "pipe":
			# Труба тянется к соседним трубам и машинам (к трубам — один раз на пару).
			for d in Machine.DIRS:
				var o = world.machine_at(m.cell + d)
				if o == null or (o.kind == "pipe" and o.id < m.id):
					continue
				var a := terrain.cell_pos(m.cell) + Vector3(0, 0.4, 0)
				var b := terrain.cell_pos(m.cell + d) + Vector3(0, 0.4, 0)
				if o.kind != "pipe":
					b = a.lerp(b, 0.6)
				if not mats.has(m.id):
					mats[m.id] = ProtoMachines.surface(m.built_from if m.built_from != null else world.starter)
				ProtoMachines.pipe(_machines, a, b, mats[m.id], 2)

func _machine_signature() -> String:
	var parts := PackedStringArray()
	for id in world.machines:
		var m: Machine = world.machines[id]
		parts.append("%d:%s:%d:%d" % [id, m.kind, m.facing, m.master_id])
	return ",".join(parts)

# ---------------------------------------------------------------- кадр

func _sync(dt: float, force := false) -> void:
	_sync_t -= dt
	if _sync_t > 0.0 and not force:
		return
	_sync_t = 0.3
	_refresh_tiles()
	var sig := _machine_signature()
	if sig != _machine_sig:
		_machine_sig = sig
		_rebuild_machines()
	for c in _deposits:
		var dep = world.planet.deposits.get(c)
		var left: bool = dep != null and dep.amount > 0.0
		var seen: bool = world.revealed.has(c) or world.near_robot(c, 4.5)
		_deposits[c][0].visible = left and seen
		_deposits[c][1].visible = left and not seen

func _process(dt: float) -> void:
	if world == null or not visible:
		return
	dt = minf(dt, 0.25)
	var moved := world.robot.pos - _last_pos
	_last_pos = world.robot.pos
	var speed := moved.length() * S / maxf(dt, 0.0001)
	if moved.length() > 0.0005:
		_yaw = atan2(moved.x, moved.y)
	robot.rotation.y = lerp_angle(robot.rotation.y, _yaw, minf(1.0, dt * 10.0))
	if anim:
		# Скорость игры рассчитана на 2D (клеток в секунду) — шаг ограничен бегом.
		anim.speed = minf(speed, RobotAnim.WALK_SPEED * 2.6)
	robot.position = terrain.world_pos(world.robot.pos)
	_sync(dt)
	_update_live(dt)
	_fx3d.update(dt)
	_follow(dt)
	if main != null and cursor != null:
		var mc: Vector2i = main.mouse_cell()
		cursor.visible = world.planet.in_bounds(mc)
		cursor.position = terrain.cell_pos(mc) + Vector3(0, 0.05, 0)

func _cam_dist() -> float:
	var z := 1.5
	if main != null and main.cam != null:
		z = main.cam.zoom.x
	return clampf(1.5 / z, 0.5, 3.75)

func _follow(dt: float) -> void:
	var k := _cam_dist()
	var target := robot.position + Vector3(0, 1.0, 0)
	var want := target + Vector3(0, CAM_UP * k, CAM_BACK * k)
	cam.position = cam.position.lerp(want, minf(1.0, dt * 6.0))
	cam.look_at(target + Vector3(0, 0, -2.0 * k))
	if particles != null:
		particles.position = robot.position + Vector3(0, 8, -10)

## Клетка мира (в клетках, как World.robot.pos) под точкой экрана: луч в рельеф.
func screen_to_world(screen: Vector2) -> Vector2:
	if cam == null:
		return world.robot.pos
	var o := cam.project_ray_origin(screen)
	var d := cam.project_ray_normal(screen)
	var t := 0.0
	var prev := o
	for i in 400:
		t += 0.25 + t * 0.01
		var p := o + d * t
		if p.y <= terrain.surface_h(p.x, p.z):
			# Уточнить пересечение делением отрезка.
			var a := prev
			var b := p
			for j in 8:
				var m := (a + b) * 0.5
				if m.y <= terrain.surface_h(m.x, m.z):
					b = m
				else:
					a = m
			return Vector2(b.x, b.z) / S
		prev = p
	return Vector2(prev.x, prev.z) / S

## Порция вещества шариком (твёрдое — матовое, светящееся — по тегам материала).
func _portion_mesh(sub: Substance, r: float, _glow: bool) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sp := SphereMesh.new()
	sp.radius = r
	sp.height = r * 2.0
	sp.radial_segments = 10
	sp.rings = 5
	mi.mesh = sp
	mi.material_override = ProtoMachines.surface(sub)
	return mi
