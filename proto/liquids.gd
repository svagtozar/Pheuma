class_name ProtoLiquids
extends RefCounted
## Жидкости без фиксированного набора: вид выводится из свойств и тегов материала
## планеты, который жидкий при её температуре. Один шейдер с параметрами.

const SHADER := """
shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_opaque;
uniform vec4 base_color : source_color = vec4(0.2, 0.4, 0.6, 0.7);
uniform float metal = 0.0;
uniform float rough = 0.15;
uniform float glow = 0.0;
uniform float speed = 1.0;
uniform float scale = 1.0;
uniform float bubbles = 0.0;
uniform float crust = 0.0;
uniform float flow_x = 0.4;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX.y += (vnoise(w.xz * 0.6 * scale + vec2(TIME * speed * flow_x, TIME * speed * 0.3)) - 0.5) * 0.12 / scale;
}

void fragment() {
	vec3 w = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 uv = w.xz * scale;
	float t = TIME * speed;
	float r = vnoise(uv * 1.3 + vec2(t * flow_x, t * 0.2)) * 0.6 + vnoise(uv * 3.1 - vec2(t * 0.4, t * flow_x)) * 0.4;
	vec3 col = base_color.rgb * (0.92 + 0.16 * r);
	float c = smoothstep(0.55, 0.7, vnoise(uv * 0.7 + vec2(t * 0.05, 0.0))) * crust;
	col = mix(col, vec3(0.08, 0.06, 0.05), c);
	float b = step(0.93, vnoise(uv * 6.0 + vec2(0.0, t * 1.5))) * bubbles;
	col += vec3(b) * 0.6;
	ALBEDO = col;
	ALPHA = mix(base_color.a, 1.0, c);
	METALLIC = metal;
	ROUGHNESS = rough + r * 0.04;
	SPECULAR = 0.8;
	EMISSION = base_color.rgb * glow * (1.0 - c) * (0.7 + 0.6 * r);
	NORMAL_MAP = vec3(0.5 + (r - 0.5) * 0.6, 0.5 + (vnoise(uv * 2.0 + t) - 0.5) * 0.6, 1.0);
}
"""

static var _shader: Shader

## Параметры вида жидкости из материала.
static func look(s: Substance, ambient: float) -> Dictionary:
	var d := {"color": s.color.darkened(0.25), "alpha": 0.8, "metal": 0.25, "rough": 0.04, "glow": 0.0,
		"speed": 1.0, "scale": 1.0, "bubbles": 0.0, "crust": 0.0, "vapor": false, "haze": false}
	if s.has("metallic"):
		d.metal = 0.95
		d.rough = 0.05
		d.alpha = 1.0
	if s.has("luminous"):
		d.glow = 1.2
	if s.has("dense"):
		d.speed = 0.35
		d.scale = 0.6
		d.alpha = max(d.alpha, 0.9)
	if s.has("sticky") or s.has("organic"):
		d.speed *= 0.3
		d.scale *= 0.5
		d.rough = 0.12
		d.alpha = max(d.alpha, 0.92)
	if s.has("superfluid"):
		d.speed = 3.0
		d.scale = 2.2
		d.alpha = 0.45
	if s.has("acidic"):
		d.bubbles = 1.0
	if s.has("volatile") or ambient > s.boil - 25.0:
		d.vapor = true
		d.alpha = min(d.alpha, 0.6)
	if s.has("toxic"):
		d.haze = true
	if s.melt > 300.0:
		d.glow = max(d.glow, 1.6)
		d.crust = 1.0
		d.speed *= 0.4
		d.alpha = 1.0
	return d

static func material(s: Substance, ambient: float) -> ShaderMaterial:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER
	var d := look(s, ambient)
	var m := ShaderMaterial.new()
	m.shader = _shader
	m.set_shader_parameter("base_color", Color(d.color, d.alpha))
	for k in ["metal", "rough", "glow", "speed", "scale", "bubbles", "crust"]:
		m.set_shader_parameter(k, d[k])
	return m

## Плоская поверхность жидкости на уровне level во всех клетках области, где на этой
## высоте воздух (area — Callable(x, z) -> bool).
static func surface_mesh(terrain: ProtoTerrain, level: float, area: Callable) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for z in terrain.sz:
		for x in terrain.sx:
			if not area.call(x + 0.5, z + 0.5):
				continue
			if terrain.density(x + 0.5, level, z + 0.5) > 0.0:
				continue
			var a := Vector3(x, level, z)
			for q in [[a, a + Vector3(1, 0, 0), a + Vector3(1, 0, 1)], [a, a + Vector3(1, 0, 1), a + Vector3(0, 0, 1)]]:
				for p in q:
					st.set_normal(Vector3.UP)
					st.add_vertex(p)
	return st.commit()

## Поверхность жидкости с уровнем, зависящим от места (level — Callable(x, z) -> float),
## только там, где рельеф ниже уровня: река спускается по руслу.
static func sloped_mesh(terrain: ProtoTerrain, level: Callable, area: Callable) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for z in terrain.sz:
		for x in terrain.sx:
			if not area.call(x + 0.5, z + 0.5):
				continue
			var y0: float = level.call(x + 0.5, z + 0.5)
			if terrain.surface_h(x + 0.5, z + 0.5) > y0 + 0.2:
				continue
			var ys := [level.call(x, z), level.call(x + 1, z), level.call(x + 1, z + 1), level.call(x, z + 1)]
			var c := [Vector3(x, ys[0], z), Vector3(x + 1, ys[1], z), Vector3(x + 1, ys[2], z + 1), Vector3(x, ys[3], z + 1)]
			for tri in [[0, 1, 2], [0, 2, 3]]:
				for k in tri:
					st.set_normal(Vector3.UP)
					st.add_vertex(c[k])
	return st.commit()

## Пар или дымка над жидкостью.
static func vapor(pos: Vector3, extent: Vector3, col: Color, haze: bool) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.position = pos
	p.amount = 60
	p.lifetime = 4.0
	p.preprocess = 4.0
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = extent
	p.direction = Vector3.UP
	p.spread = 25.0
	p.gravity = Vector3(0.3, 0.25, 0)
	p.initial_velocity_min = 0.1
	p.initial_velocity_max = 0.4
	p.scale_amount_min = 1.5
	p.scale_amount_max = 3.0
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	var m := StandardMaterial3D.new()
	var g := GradientTexture2D.new()
	g.fill = GradientTexture2D.FILL_RADIAL
	g.fill_from = Vector2(0.5, 0.5)
	g.fill_to = Vector2(1.0, 0.5)
	var gr := Gradient.new()
	gr.set_color(0, Color(1, 1, 1, 1))
	gr.set_color(1, Color(1, 1, 1, 0))
	g.gradient = gr
	m.albedo_texture = g
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.albedo_color = Color(col.lerp(Color.WHITE, 0.6), 0.12 if not haze else 0.18)
	m.vertex_color_use_as_albedo = false
	q.material = m
	p.mesh = q
	return p
