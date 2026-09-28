class_name ProtoHarvest
extends Node3D
## Сбор органики: робот срезает растения планеты (ProtoFlora) тем же буром.
##   Когда под прицелом нет кристалла или залежи, бур берёт ближайшее растение
##   перед роботом: кольцо у основания, подсказка «[F] срезать». Пока держат
##   tool_work, летят обрезки цвета растения; срезанное валится набок, потом
##   притягивается к роботу, как отколотый кристалл, и в груз ложится порция
##   органики планеты (Portion). Мелкую поросль (мох, щетину, завитки) бур
##   выкашивает полосой — всё низкое в полуметре от цели разом.
##   Вещество — органический материал планеты, волокнистый (растения — волокно);
##   если органики среди материалов нет или она здесь жидкая — биомасса от самого
##   мягкого твёрдого (при нужде изолирующая, как пробка, чтобы была твёрдой).
##   На заводе волокно идёт в ткацкий станок (упругое изолирующее полотно),
##   жидкая органика в печи густеет — это уже правила Processor.
##   Срезанное не отрастает; номера срезанных — в метаданных "cut" корня сцены
##   (ProtoSave).

const REACH := 1.35          # м от плеча до точки среза
const AIM_TOL := 0.5          # луч прицела проходит мимо растения не дальше, м
const MOW_R := 0.6           # полоса выкоса вокруг мелкой поросли, м
const LOW := ["moss", "tuft", "curls"]
const NAMES := {"moss": "мох", "tuft": "щетину", "curls": "завитки", "frond": "ваи",
	"lantern": "фонарик", "coral": "коралл", "bladder": "пузырь", "tubes": "трубчатых червей",
	"shelf": "трутовик"}
const CELL := 2.0

var aim_from := Vector3.INF  # луч прицела из камеры (ProtoPlayer); INF — без прицела
var aim_dir := Vector3.ZERO
var aim_hit := Vector3.INF
var flora: ProtoFlora
var mining: ProtoMining      # подсказка, полоса прогресса и груз — общие с буром
var sub: Substance
var robot: Node3D
var target := -1             # номер растения под прицелом
var progress := 0.0
var cutting := false
var contact := Vector3.ZERO  # точка среза, мир
var falling: Array = []      # срезанное: {node, t, axis, mass}
var harvested_total := 0.0   # кг органики за всё время
var cuts := 0                # сколько раз срезали
var speed_mult := 1.0
var marker: MeshInstance3D
var chips: CPUParticles3D
var _cells := {}             # клетка 2 м → номера растений

## Органика планеты для груза: свой органический материал (твёрдый — первым)
## или биомасса от самого мягкого твёрдого; растения всегда волокнистые.
static func biomass(p: Planet) -> Substance:
	var t := p.ambient_temp
	# Кандидаты: [основа, теги]. Органика планеты с волокном; биомасса от самого
	# мягкого неметалла; она же изолирующая (пробка: плавится выше) — первое,
	# что при здешней температуре твёрдое. Органика легкоплавкая, а жидкий
	# «срезанный куст» в грузе — странно.
	var cands := []
	for m: Substance in p.materials:
		if m.has("organic") or m.has("fibrous"):
			cands.append([m, MaterialTags.add_tag(MaterialTags.add_tag(m.tags, "organic"), "fibrous")])
	var soft: Substance = null
	for m: Substance in p.materials:
		if m.phase_at(t) == Substance.Phase.SOLID and not m.has("metallic") \
				and (soft == null or m.hardness < soft.hardness):
			soft = m
	if soft == null and not p.materials.is_empty():
		soft = p.materials[0]
	if soft != null:
		cands.append([soft, ["fibrous", "organic"]])
		cands.append([soft, ["fibrous", "insulating", "organic"]])
	if cands.is_empty():
		return p.db.add(Substance.new("Био", "Био", ["fibrous", "insulating", "organic"]))
	var pick: Array = cands[-1]
	for c in cands:
		var probe := Substance.new("", c[0].root, c[1], c[0].noise)
		if probe.phase_at(t) == Substance.Phase.SOLID:
			pick = c
			break
	var base: Substance = pick[0]
	var s := p.db.derive(base, pick[1])
	if s != base and not s.name.ends_with("-био"):
		s.name = "%s-био" % base.root
	return s

func setup(f: ProtoFlora, m: ProtoMining, p: Planet) -> void:
	flora = f
	mining = m
	sub = biomass(p)
	for i in flora.items.size():
		var q: Vector3 = flora.items[i].p
		var c := Vector2i(floori(q.x / CELL), floori(q.z / CELL))
		if not _cells.has(c):
			_cells[c] = []
		_cells[c].append(i)
	marker = MeshInstance3D.new()
	var tor := TorusMesh.new()
	tor.inner_radius = 0.9
	tor.outer_radius = 1.0
	tor.rings = 24
	tor.ring_segments = 4
	marker.mesh = tor
	var mm := StandardMaterial3D.new()
	mm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mm.albedo_color = Color(0.7, 1.0, 0.5, 0.8)
	mm.no_depth_test = true
	marker.material_override = mm
	marker.visible = false
	add_child(marker)
	chips = CPUParticles3D.new()
	chips.amount = 36
	chips.lifetime = 0.9
	chips.emitting = false
	chips.direction = Vector3.UP
	chips.spread = 80.0
	chips.gravity = Vector3(0, -4.0, 0)
	chips.initial_velocity_min = 0.8
	chips.initial_velocity_max = 2.2
	chips.angular_velocity_min = -360.0
	chips.angular_velocity_max = 360.0
	chips.scale_amount_min = 0.6
	chips.scale_amount_max = 1.4
	var qm := QuadMesh.new()
	qm.size = Vector2(0.035, 0.018)
	var cm := StandardMaterial3D.new()
	cm.cull_mode = BaseMaterial3D.CULL_DISABLED
	qm.material = cm
	chips.mesh = qm
	chips.local_coords = false
	add_child(chips)

## Сколько растений ещё стоит.
func standing() -> int:
	var n := 0
	for it in flora.items:
		if not it.cut:
			n += 1
	return n

## Точка среза растения i в системе флоры: у мелочи — у земли, у крупного — по пояс.
func _aim(i: int) -> Vector3:
	var it: Dictionary = flora.items[i]
	return it.p + Vector3.UP * clampf(float(it.h) * 0.4, 0.08, 0.8)

func _reach(i: int, sh: Vector3) -> float:
	var q := _aim(i)
	var low := sh - Vector3(0, ProtoMining.STOOP, 0)
	return minf(sh.distance_to(q), low.distance_to(q) + 0.05)

## Растение под прицелом: в досягаемости от правого плеча и перед роботом.
func pick(r: Node3D) -> int:
	var sh := flora.node.to_local(r.to_global(Vector3(0.23, 1.4, 0.1)))
	var rp := flora.node.to_local(r.global_position)
	var fwd := flora.node.global_transform.basis.inverse() * r.global_transform.basis.z
	var c0 := Vector2i(floori(sh.x / CELL), floori(sh.z / CELL))
	var best := -1
	var best_d := INF
	var aimed := aim_from != Vector3.INF
	var ground := aimed and ProtoMining.aim_claims_ground(aim_hit, r.to_global(Vector3(0.23, 1.4, 0.1)))
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			for i: int in _cells.get(c0 + Vector2i(dx, dz), []):
				var it: Dictionary = flora.items[i]
				if it.cut:
					continue
				var d := _reach(i, sh)
				if d > REACH:
					continue
				var q := _aim(i)
				var flat := Vector3(q.x - rp.x, 0, q.z - rp.z)
				if flat.length() > 0.2 and flat.normalized().dot(Vector3(fwd.x, 0, fwd.z).normalized()) < 0.0:
					continue
				if aimed:
					# С перекрестьем — растение, мимо которого прошёл луч; иначе
					# (порода под прицелом близко) бур копает грунт.
					var w := flora.node.to_global(q)
					var along := maxf(0.0, (w - aim_from).dot(aim_dir))
					var off := (aim_from + aim_dir * along).distance_to(w) - clampf(float(it.h) * 0.3, 0.0, 0.5)
					if off > AIM_TOL:
						if ground:
							continue
					else:
						d -= 1.0 - off
				# Крупное — чуть приоритетнее мелочи.
				d -= float(it.h) * 0.2
				if d < best_d:
					best_d = d
					best = i
	return best

## Масса срезанного, кг: по высоте и размаху, мелочь — граммы.
func mass_of(i: int) -> float:
	var it: Dictionary = flora.items[i]
	var m := 2.5 * float(it.h) * (float(it.r) + 0.2) * clampf(sub.density, 0.5, 2.0)
	if LOW.has(it.form):
		m *= 0.35     # поросль — пучки травы, не кусты
	return clampf(m, 0.05, 6.0)

## Что уйдёт в груз, если срезать i: мелочь — вся полоса вокруг.
func _group(i: int) -> Array:
	var it: Dictionary = flora.items[i]
	if not LOW.has(it.form):
		return [i]
	var out := [i]
	var p: Vector3 = it.p
	var c0 := Vector2i(floori(p.x / CELL), floori(p.z / CELL))
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			for j: int in _cells.get(c0 + Vector2i(dx, dz), []):
				var o: Dictionary = flora.items[j]
				if j != i and not o.cut and LOW.has(o.form) and o.key == it.key \
						and (o.p as Vector3).distance_to(p) < MOW_R:
					out.append(j)
	return out

func _group_mass(i: int) -> float:
	var m := 0.0
	for j in _group(i):
		m += mass_of(j)
	return m

## Кадр сбора. free — бур не занят кристаллом (у кристалла приоритет).
func step(dt: float, r: Node3D, work: float, out: float, free: bool) -> void:
	robot = r
	cutting = false
	var t := target
	if not free:
		t = -1
	else:
		var sh := flora.node.to_local(r.to_global(Vector3(0.23, 1.4, 0.1)))
		var keep: bool = work > 0.05 and t >= 0 and not flora.items[t].cut and _reach(t, sh) < REACH * 1.25
		if not keep:
			t = pick(r)
	if t != target:
		target = t
		progress = 0.0
		if target >= 0:
			var col: Color = flora.items[target].col
			(chips.mesh.material as StandardMaterial3D).albedo_color = Color(col, 1.0)
	if target >= 0:
		contact = flora.node.to_global(_aim(target))
		if work > 0.6 and out > 0.95:
			cutting = true
			var h := float(flora.items[target].h)
			progress += dt * speed_mult / (0.35 + 0.4 * clampf(h, 0.0, 2.0))
			if progress >= 1.0:
				_cut(target)
				target = -1
				progress = 0.0
				cutting = false
	chips.global_position = contact
	chips.emitting = cutting
	_marker_update()
	_falling(dt)
	if free:
		_hud()

func _cut(i: int) -> void:
	var group := _group(i)
	var total := _group_mass(i)
	cuts += 1
	var rp := flora.node.to_local(robot.global_position)
	for k in group.size():
		var j: int = group[k]
		var it: Dictionary = flora.items[j]
		var mesh := flora.cut(j)
		if mesh == null:
			continue
		var n := MeshInstance3D.new()
		n.mesh = mesh
		n.material_override = flora.mat
		n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		flora.node.add_child(n)
		n.position = it.p
		# Валится от робота: ось — поперёк направления робот → растение.
		var away: Vector3 = it.p - rp
		away.y = 0.0
		away = away.normalized() if away.length() > 0.05 else Vector3.FORWARD
		falling.append({"node": n, "t": -0.06 * k, "axis": Vector3.UP.cross(away).normalized(),
			"mass": total if k == 0 else 0.0, "pull": 0.0})
	flora.flush()
	var root := get_parent()
	if root != null:
		root.set_meta("cut", flora.cut_ids())

## После загрузки: срезанные растения убрать.
func restore_cut(ids: Array) -> void:
	for id in ids:
		var i := int(id)
		if i >= 0 and i < flora.items.size():
			flora.cut(i, false)
	flora.flush()
	var root := get_parent()
	if root != null:
		root.set_meta("cut", flora.cut_ids())

func _falling(dt: float) -> void:
	var keep := []
	for f in falling:
		var n: MeshInstance3D = f.node
		if not is_instance_valid(n):
			continue
		f.t += dt
		if f.t < 0.0:
			keep.append(f)
			continue
		if f.t < 0.5:
			# Валится набок, ускоряясь.
			var a := pow(f.t / 0.5, 2.0) * 1.35
			n.transform.basis = Basis(f.axis, a)
			keep.append(f)
			continue
		# Потом — к роботу, уменьшаясь, в груз.
		f.pull += dt
		var home := flora.node.to_local(robot.global_position + Vector3(0, 1.0, 0))
		var to: Vector3 = home - n.position
		n.position += to * minf(1.0, dt * (3.0 + f.pull * 8.0))
		n.transform.basis = Basis(f.axis, 1.35).rotated(Vector3.UP, f.pull * 8.0).scaled(Vector3.ONE * maxf(0.05, 1.0 - f.pull * 1.6))
		if to.length() < 0.25 or f.pull > 0.8:
			if f.mass > 0.0:
				harvested_total += f.mass
				mining.collect(f.mass, sub, false)
			n.queue_free()
			continue
		keep.append(f)
	falling = keep

func _marker_update() -> void:
	marker.visible = target >= 0
	if target < 0:
		return
	var it: Dictionary = flora.items[target]
	var r := clampf(float(it.r) * 0.8, 0.2, 0.9) * (1.0 + 0.08 * sin(Time.get_ticks_msec() * 0.008))
	var base := flora.node.to_global(it.p + Vector3(0, 0.05, 0))
	marker.global_transform = Transform3D(flora.node.global_transform.basis.orthonormalized().scaled(Vector3(r, r * 0.5, r)), base)

## Подсказка и полоса — в общих с буром местах HUD (бур их гасит, когда цели нет).
func _hud() -> void:
	var busy := robot != null and bool(robot.get_meta("ui_busy", false))
	if target < 0 or busy:
		return
	var what: String = NAMES.get(flora.items[target].form, "растение")
	if cutting:
		mining.hud_hint.text = "Срезаю %s: %s, ≈%.1f кг" % [what, mining.sub_label(sub), _group_mass(target)]
	else:
		var key := ProtoHud.glyph([ProtoMining.ACTION], mining.hud.pad) if mining.hud != null else "F / правый курок"
		mining.hud_hint.text = "[%s] срезать %s — %s, ≈%.1f кг" % [key, what, sub.name, _group_mass(target)]
	mining.hud_bar.visible = progress > 0.0
	mining.hud_bar.value = progress
	(mining.hud_bar.get_theme_stylebox("fill") as StyleBoxFlat).bg_color = Color(flora.items[target].col, 1.0).lerp(Color.WHITE, 0.3)
