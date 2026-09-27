class_name ProtoMachines
extends RefCounted
## Общее для машин: поверхность из материала, стекло, свечение, трубы с бусинами
## газа, коробки столкновений (модели машин — MachineModels / MachineKit).
## Поверхность корпуса — из тегов материала, изучен он или нет: в мире
## неизученное выглядит как обычно, что о нём ещё не известно, показывают
## «?N» в карточке материала, грузе и стройке. Голограмма — только призрак
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

## Труба между двумя точками, с бусинами газа.
## Один материал на все бусины: так их склеивает ProtoBatch.
static var _bead_mat := glow(Color(0.7, 0.8, 1.0), 1.5)

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
		bead.material_override = _bead_mat
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

## Слои столкновений: рельеф (RobotGround.LAYER — по нему лучи стоп и корпуса)
## и машины (в них упирается корпус ProtoPlayer). Машины лежат на обоих слоях:
## на верх трубы или настила робот встаёт, как на рельеф.
const LAYER_GROUND := RobotGround.LAYER
const LAYER_MACHINES := 1 << 18

## Коробка столкновений по всем сеткам узла n (и его самого), в его пространстве.
## Низкую коробку (трубу, настил) робот перешагивает как уступ, высокую обходит.
static func add_box_collider(n: Node3D, layer := LAYER_MACHINES | LAYER_GROUND) -> StaticBody3D:
	var box := AABB()
	var first := true
	var meshes: Array = n.find_children("*", "MeshInstance3D", true, false)
	if n is MeshInstance3D:
		meshes.append(n)
	for mi in meshes:
		var m := mi as MeshInstance3D
		if m.mesh == null or not m.visible:
			continue
		var x := Transform3D()
		var c: Node = m
		while c != n and c is Node3D and c != null:
			x = (c as Node3D).transform * x
			c = c.get_parent()
		var bb := x * m.mesh.get_aabb()
		box = bb if first else box.merge(bb)
		first = false
	if first:
		return null
	var b := StaticBody3D.new()
	b.name = "collider"
	b.collision_layer = layer
	b.collision_mask = 0
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = box.size
	cs.shape = sh
	cs.position = box.get_center()
	b.add_child(cs)
	n.add_child(b)
	return b

