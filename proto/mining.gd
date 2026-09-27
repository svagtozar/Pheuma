class_name ProtoMining
extends Node3D
## Добыча кристаллов буром в пещере предпросмотра.
##   Друзы на стенах и полу — из кристаллического материала планеты (Substance
##   с тегом crystalline). Робот подходит, ближайший кристалл в досягаемости бура
##   подсвечивается кольцом у основания. Пока держат действие tool_work (F или
##   правый курок геймпада), бур выдвигается, рука тянется к кристаллу, летят
##   искры и крошка, кристалл дрожит; когда прочность выбрана — он откалывается,
##   падает, отскакивает от пола и притягивается к роботу. В груз — порция
##   материала (Portion, как в игре), масса по объёму и плотности. Груз —
##   метаданные "cargo" на узле робота (Array[Portion]); оттуда же его забирает
##   приёмник пневмозавода (ProtoBuilder, C — выгрузить).
##   Правило игры: бур берёт материал не твёрже себя (+0,5), иначе искры и
##   «бур слишком мягкий». Хрупкий (brittle) колется вдвое быстрее и на осколки,
##   твёрдость замедляет бурение.

const REACH := 1.2           # м от плеча до оси кристалла (с наклоном корпуса)
const BREAK_TIME := 1.1      # с на кристалл средней массы при равной твёрдости
const ACTION := &"tool_work"   # то же имя, что в раскладке ProtoControls

var sub: Substance           # материал кристаллов
var drill_hard := 2.5        # твёрдость бура (металл планеты)
var temp := 15.0
var terrain: ProtoTerrain
var cmat: StandardMaterial3D
var hot_mat: StandardMaterial3D
var druses: Array = []       # [{node, crystals: [MeshInstance3D]}]
var robot: Node3D           # чей груз показывать

var target: MeshInstance3D   # кристалл под прицелом
var progress := 0.0          # 0..1 — сколько выбурено у target
var status := ""
var drilling := false        # бур у кристалла и крутится
var contact := Vector3.ZERO  # точка касания, мир
var falling: Array = []      # отколотые куски в полёте: {node, vel, spin, t, land}
var marker: MeshInstance3D
var sparks: CPUParticles3D
var crumbs: CPUParticles3D
var hud_hint: Label
var hud_bar: ProgressBar
var hud_cargo: Label
var popups: Array = []       # [Label3D, t]
var rng := RandomNumberGenerator.new()

## Действие инструмента: F и правый курок; если его уже завёл кто-то ещё
## (например, раскладка геймпада) — не трогаем.
static func ensure_action() -> void:
	if InputMap.has_action(ACTION):
		return
	InputMap.add_action(ACTION, 0.3)
	var k := InputEventKey.new()
	k.physical_keycode = KEY_F
	InputMap.action_add_event(ACTION, k)
	var j := InputEventJoypadMotion.new()
	j.axis = JOY_AXIS_TRIGGER_RIGHT
	j.axis_value = 1.0
	InputMap.action_add_event(ACTION, j)

func setup(s: Substance, hard: float, t: float, tr: ProtoTerrain, mat: StandardMaterial3D) -> void:
	sub = s
	drill_hard = hard
	temp = t
	terrain = tr
	cmat = mat
	hot_mat = mat.duplicate()
	hot_mat.emission_energy_multiplier = mat.emission_energy_multiplier * 2.6
	hot_mat.albedo_color = mat.albedo_color.lerp(Color.WHITE, 0.3)
	rng.seed = 7
	_marker()
	sparks = _particles(Color(1.0, 0.8, 0.45), 0.012, 3.5, 60, true)
	crumbs = _particles(sub.color.lerp(Color.WHITE, 0.4), 0.011, 1.8, 40, false)
	_hud()

## Друза — узел с кристаллами-детьми; у каждого meta len, r (м).
func add_druse(node: Node3D) -> void:
	var list := []
	for c in node.get_children():
		if c is MeshInstance3D and c.has_meta("len"):
			list.append(c)
	druses.append({"node": node, "crystals": list})

## Все кристаллы, ещё сидящие в породе.
func crystals() -> Array:
	var r := []
	for d in druses:
		for c in d.crystals:
			if is_instance_valid(c) and not c.has_meta("broken"):
				r.append(c)
	return r

## Ось кристалла в мире: основание и вершина.
static func axis(c: MeshInstance3D) -> Array:
	var gt := c.global_transform
	return [gt.origin, gt.origin + gt.basis.y.normalized() * float(c.get_meta("len"))]

## Ближайшая к точке p точка на оси кристалла.
static func nearest_on(c: MeshInstance3D, p: Vector3) -> Vector3:
	var ax := axis(c)
	var ab: Vector3 = ax[1] - ax[0]
	var t := clampf((p - ax[0]).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.15, 0.8)
	return ax[0] + ab * t

## Груз робота: Array[Portion] в метаданных "cargo" (общий с ProtoBuilder).
static func cargo_of(r: Node3D) -> Array:
	if not r.has_meta("cargo"):
		r.set_meta("cargo", [])
	return r.get_meta("cargo")

static func mass_of(c: MeshInstance3D, s: Substance) -> float:
	var l: float = c.get_meta("len")
	var r: float = c.get_meta("r")
	# Шестигранная призма ≈ 2,6·r²·l; плотность в т/м³, масштаб прототипа — десятая.
	return 2.6 * r * r * l * s.density * 100.0

## Кристалл под прицелом: в досягаемости от правого плеча и перед роботом.
func pick(r: Node3D) -> MeshInstance3D:
	var sh := r.to_global(Vector3(0.23, 1.4, 0.1))
	var fwd := r.global_transform.basis.z.normalized()
	var best: MeshInstance3D = null
	var best_d := INF
	for c in crystals():
		var q := nearest_on(c, sh)
		var d := sh.distance_to(q)
		if d > REACH:
			continue
		var flat := Vector3(q.x - r.global_position.x, 0, q.z - r.global_position.z)
		if flat.length() > 0.2 and flat.normalized().dot(fwd) < -0.1:
			continue
		# Главные кристаллы друзы — чуть приоритетнее мелкой поросли.
		d -= float(c.get_meta("len")) * 0.15
		if d < best_d:
			best_d = d
			best = c
	return best

## Кадр добычи. work — 0..1 рука с инструментом, out — 0..1 бур выдвинут,
## tip — острие бура в мире (или INF).
func step(dt: float, r: Node3D, work: float, out: float, tip: Vector3) -> void:
	robot = r
	# Пока инструмент в работе, цель держится (иначе доворот робота её сбивал бы).
	var t := target
	var sh := robot.to_global(Vector3(0.23, 1.4, 0.1))
	var keep := work > 0.05 and t != null and is_instance_valid(t) and not t.has_meta("broken") \
		and sh.distance_to(nearest_on(t, sh)) < REACH * 1.25
	if not keep:
		t = pick(robot)
	if t != target:
		if target and is_instance_valid(target) and not target.has_meta("broken"):
			target.material_override = cmat
			target.position = target.get_meta("rest_pos", target.position)
		target = t
		progress = 0.0
	drilling = false
	status = ""
	if target:
		if not target.has_meta("rest_pos"):
			target.set_meta("rest_pos", target.position)
		contact = nearest_on(target, sh)
		var too_soft := drill_hard + 0.5 < sub.hardness
		if work > 0.6 and out > 0.95:
			drilling = true
			if too_soft:
				status = "бур слишком мягкий (нужно %.1f)" % sub.hardness
			else:
				var rate := 1.0 / (BREAK_TIME * clampf(sub.hardness / maxf(drill_hard, 0.5), 0.5, 2.0))
				if sub.has("brittle"): rate *= 2.0
				rate /= clampf(sqrt(mass_of(target, sub) / 1.5), 0.6, 2.2)
				progress += dt * rate
		target.material_override = hot_mat if drilling and not too_soft else cmat
		var rest: Vector3 = target.get_meta("rest_pos")
		target.position = rest + (Vector3(rng.randf() - 0.5, rng.randf() - 0.5, rng.randf() - 0.5) * 0.012 * (0.5 + progress) if drilling and not too_soft else Vector3.ZERO)
		if progress >= 1.0:
			_break(target)
			target = null
			progress = 0.0
			drilling = false
	# Искры — всегда при касании; крошка — если бур берёт.
	var at := contact if tip == Vector3.INF or tip.distance_to(contact) > 0.4 else tip
	sparks.global_position = at
	crumbs.global_position = at
	sparks.emitting = drilling
	crumbs.emitting = drilling and status == ""
	_marker_update(dt)
	_falling(dt)
	_hud_update(dt)

func _break(c: MeshInstance3D) -> void:
	c.set_meta("broken", true)
	c.material_override = cmat
	var gt := c.global_transform
	var nrm: Vector3 = c.get_parent().get_meta("normal", Vector3.UP)
	var m := mass_of(c, sub)
	# Пенёк в породе: обломанное основание.
	var stump := MeshInstance3D.new()
	var r2 := RandomNumberGenerator.new()
	r2.seed = hash(c.name)
	stump.mesh = ProtoCrystal.mesh(float(c.get_meta("len")) * 0.18, float(c.get_meta("r")) * 0.95, r2)
	stump.material_override = cmat
	stump.transform = c.transform
	c.get_parent().add_child(stump)
	# Сам кристалл — в свободный полёт (в мировых координатах).
	var pieces := [c]
	if sub.has("brittle"):
		# Хрупкий — раскалывается ещё и на пару осколков.
		for k in 2:
			var sh := MeshInstance3D.new()
			sh.mesh = ProtoCrystal.mesh(float(c.get_meta("len")) * 0.4, float(c.get_meta("r")) * 0.7, rng)
			sh.material_override = cmat
			add_child(sh)
			sh.global_transform = gt.translated(gt.basis.y * 0.3 * (k + 1))
			pieces.append(sh)
	c.get_parent().remove_child(c)
	add_child(c)
	c.global_transform = gt
	var away := (contact - robot.global_position)
	away.y = 0
	away = away.normalized() if away.length() > 0.01 else Vector3.FORWARD
	for i in pieces.size():
		# Отлетает от бура вбок-вверх и падает рядом с друзой.
		var v: Vector3 = nrm * 0.6 + Vector3.UP * rng.randf_range(1.6, 2.3) + away * 0.5 + Vector3(rng.randf_range(-0.4, 0.4), 0, rng.randf_range(-0.4, 0.4))
		falling.append({"node": pieces[i], "vel": v,
			"spin": Vector3(rng.randf_range(-6, 6), rng.randf_range(-4, 4), rng.randf_range(-6, 6)),
			"t": 0.0, "land": 0.0, "mass": m / pieces.size(), "pull": 0.0})
	# Всплеск крошки при отколе.
	var burst := _particles(sub.color.lerp(Color.WHITE, 0.5), 0.016, 2.6, 50, false)
	burst.one_shot = true
	burst.explosiveness = 0.9
	burst.global_position = contact
	burst.emitting = true
	get_tree().create_timer(2.0).timeout.connect(burst.queue_free)

func _falling(dt: float) -> void:
	var keep := []
	var home := robot.global_position + Vector3(0, 1.0, 0)
	for f in falling:
		var n: Node3D = f.node
		f.t += dt
		if f.pull > 0.0 or (f.land > 0.0 and f.t - f.land > 0.6):
			# Притягивается к роботу и уменьшается — в груз.
			f.pull += dt
			var to: Vector3 = home - n.global_position
			n.global_position += to * minf(1.0, dt * (3.0 + f.pull * 8.0))
			n.scale = Vector3.ONE * maxf(0.05, 1.0 - f.pull * 1.6)
			n.rotate_y(dt * 8.0)
			if to.length() < 0.25 or f.pull > 0.8:
				_collect(f.mass)
				n.queue_free()
				continue
		else:
			f.vel.y -= 9.8 * dt
			n.global_position += f.vel * dt
			if f.spin.length() > 0.01:
				n.rotate(f.spin.normalized(), f.spin.length() * dt)
			var g := terrain.floor_at(n.global_position + Vector3(0, 0.3, 0)) if terrain else 0.0
			if n.global_position.y < g + 0.05 and f.vel.y < 0.0:
				n.global_position.y = g + 0.05
				if f.vel.y < -1.2:
					f.vel = Vector3(f.vel.x * 0.5, -f.vel.y * 0.35, f.vel.z * 0.5)
					f.spin *= 0.5
				else:
					f.vel = Vector3.ZERO
					f.spin = Vector3.ZERO
					if f.land == 0.0:
						f.land = f.t
		keep.append(f)
	falling = keep

func _collect(m: float) -> void:
	var p := Portion.new(sub, m, temp)
	var list := cargo_of(robot)
	for q: Portion in list:
		if q.substance == sub:
			q.absorb(p)
			p = null
			break
	if p != null:
		list.append(p)
	var l := Label3D.new()
	l.text = "+%.1f кг %s" % [m, sub.name]
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.font_size = 32
	l.pixel_size = 0.0022
	l.outline_size = 8
	l.modulate = sub.color.lerp(Color.WHITE, 0.5)
	l.no_depth_test = true
	add_child(l)
	l.global_position = robot.global_position + Vector3(0, 1.85, 0)
	popups.append([l, 0.0])

# ---------------------------------------------------------------- вид

func _marker() -> void:
	marker = MeshInstance3D.new()
	var tor := TorusMesh.new()
	tor.inner_radius = 0.9
	tor.outer_radius = 1.0
	tor.rings = 24
	tor.ring_segments = 4
	marker.mesh = tor
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(1.0, 0.85, 0.4, 0.8)
	m.no_depth_test = true
	marker.material_override = m
	marker.visible = false
	add_child(marker)

func _marker_update(dt: float) -> void:
	marker.visible = target != null
	if target == null:
		return
	var ax := axis(target)
	var up: Vector3 = (ax[1] - ax[0]).normalized()
	var ref := Vector3.RIGHT if absf(up.dot(Vector3.RIGHT)) < 0.9 else Vector3.FORWARD
	var x := up.cross(ref).normalized()
	var r: float = float(target.get_meta("r")) * 1.9
	var pulse := 1.0 + 0.08 * sin(Time.get_ticks_msec() * 0.008)
	marker.global_transform = Transform3D(Basis(x, up, x.cross(up)).scaled(Vector3(r, r * 0.5, r) * pulse), ax[0].lerp(ax[1], 0.12))
	(marker.material_override as StandardMaterial3D).albedo_color = Color(1.0, 0.45, 0.3, 0.85) if status != "" else Color(1.0, 0.85, 0.4, 0.8)

func _particles(col: Color, size: float, speed: float, amount: int, glow: bool) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = 0.5 if glow else 0.9
	p.emitting = false
	p.direction = Vector3(0, 1, 0)
	p.spread = 70.0
	p.gravity = Vector3(0, -9.8, 0)
	p.initial_velocity_min = speed * 0.4
	p.initial_velocity_max = speed
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.2
	var mesh: PrimitiveMesh = BoxMesh.new() if not glow else SphereMesh.new()
	if mesh is BoxMesh:
		mesh.size = Vector3.ONE * size
	else:
		mesh.radius = size * 0.5
		mesh.height = size
		mesh.radial_segments = 4
		mesh.rings = 2
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	if glow:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.emission_enabled = true
		m.emission = col
	mesh.material = m
	p.mesh = mesh
	p.local_coords = false
	add_child(p)
	return p

func _hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	hud_hint = _label(layer, 18)
	hud_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud_hint.anchor_left = 0.5
	hud_hint.anchor_right = 0.5
	hud_hint.anchor_top = 1.0
	hud_hint.anchor_bottom = 1.0
	hud_hint.offset_left = -400
	hud_hint.offset_right = 400
	hud_hint.offset_top = -100
	hud_hint.offset_bottom = -70
	hud_bar = ProgressBar.new()
	hud_bar.show_percentage = false
	hud_bar.anchor_left = 0.5
	hud_bar.anchor_right = 0.5
	hud_bar.anchor_top = 1.0
	hud_bar.anchor_bottom = 1.0
	hud_bar.offset_left = -140
	hud_bar.offset_right = 140
	hud_bar.offset_top = -62
	hud_bar.offset_bottom = -50
	hud_bar.max_value = 1.0
	var fill := StyleBoxFlat.new()
	fill.bg_color = sub.color.lerp(Color.WHITE, 0.35)
	hud_bar.add_theme_stylebox_override("fill", fill)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.5)
	hud_bar.add_theme_stylebox_override("background", bg)
	layer.add_child(hud_bar)
	hud_cargo = _label(layer, 17)
	hud_cargo.anchor_top = 1.0
	hud_cargo.anchor_bottom = 1.0
	hud_cargo.grow_vertical = Control.GROW_DIRECTION_BEGIN
	hud_cargo.offset_left = 16
	hud_cargo.offset_top = -80
	hud_cargo.offset_bottom = -16

func _label(layer: CanvasLayer, fs: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", Color(1, 1, 1))
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	l.add_theme_constant_override("outline_size", 5)
	layer.add_child(l)
	return l

func _hud_update(dt: float) -> void:
	var tags := ", ".join(PackedStringArray(sub.tags.map(func(t): return MaterialTags.display(t))))
	if target == null:
		hud_hint.text = ""
	elif status != "":
		hud_hint.text = "%s — %s" % [sub.name, status]
	elif drilling:
		hud_hint.text = "Бурю: %s (%s), ≈%.1f кг" % [sub.name, tags, mass_of(target, sub)]
	else:
		hud_hint.text = "[F / правый курок] бурить — %s, ≈%.1f кг" % [sub.name, mass_of(target, sub)]
	hud_bar.visible = target != null and progress > 0.0
	hud_bar.value = progress
	var lines := ["Груз:"]
	var cargo := cargo_of(robot) if robot else []
	for p: Portion in cargo:
		lines.append("  %s (%s) — %.1f кг" % [p.substance.name, ", ".join(PackedStringArray(p.substance.tags.map(func(t): return MaterialTags.display(t)))), p.mass])
	hud_cargo.text = "\n".join(PackedStringArray(lines)) if not cargo.is_empty() else ""
	var keep := []
	for pp in popups:
		pp[1] += dt
		var l: Label3D = pp[0]
		l.global_position.y += dt * 0.25
		l.modulate.a = clampf(2.0 - pp[1], 0.0, 1.0)
		if pp[1] > 2.0:
			l.queue_free()
		else:
			keep.append(pp)
	popups = keep
