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
uniform float wave = 1.0;          // высота волн (вязкая жидкость — гладь)
uniform vec2 flow = vec2(0.0);     // течение, м/с (река): полосы и пена сносятся
uniform float rip_speed = 1.6;     // скорость кругов на воде, м/с
uniform float rip_damp = 1.2;      // затухание кругов, 1/с
uniform vec4 rip[8];               // круги: x, z, возраст (с), сила; сила 0 — нет
uniform bool vheat = false;        // живая лава (ProtoFlow): цвет вершины r — жар, остывшее — корка
uniform bool vflow = false;        // живая жидкость (ProtoFlow): цвет g, b — течение, UV.x — сдвиг к прошлой глади
uniform float morph = 1.0;         // 0 — гладь прошлой сборки, 1 — нынешняя (ProtoFlow пересобирает 2–4 раза в с)
varying float vh;
varying vec2 vvel;
varying vec2 vfall;                // завеса (ProtoLiquids.sloped): x — 1 на завесе, y — 0 у кромки … 1 внизу

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}

// Круги от робота: высота ряби в точке (сумма колец).
float ripples(vec2 p) {
	float h = 0.0;
	for (int i = 0; i < 8; i++) {
		vec4 r = rip[i];
		if (r.w <= 0.0) continue;
		float d = distance(p, r.xy);
		float front = r.z * rip_speed;
		float k = d - front;
		float env = exp(-k * k * 2.5) * exp(-r.z * rip_damp) * r.w / (1.0 + d * 0.6);
		h += sin(k * 7.0) * env * step(k, 0.6);
	}
	return h;
}

float waves(vec2 p, float t) {
	return (vnoise(p * 0.6 * scale + vec2(t * flow_x, t * 0.3) - flow * t * 0.25) - 0.5) * 0.12 / scale * wave;
}

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float t = TIME * speed;
	vh = vheat ? COLOR.r : 1.0;
	vfall = UV2;
	vvel = flow;
	if (vflow) {
		vvel = (COLOR.gb - 0.5) * 8.0;
		VERTEX.y += UV.x * (1.0 - morph);
		vh = vheat ? COLOR.r + UV.y * (1.0 - morph) : 1.0;
	}
	// Кромка завесы колышется вместе с гладью, ниже струя падает ровно.
	VERTEX.y += (waves(w.xz, t) + ripples(w.xz) * 0.06) * (1.0 - vfall.y);
}

void fragment() {
	vec3 w = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 uv = w.xz * scale;
	float t = TIME * speed;
	vec2 fl = flow * TIME * 0.35 * scale;
	float r = vnoise(uv * 1.3 + vec2(t * flow_x, t * 0.2) - fl) * 0.6 + vnoise(uv * 3.1 - vec2(t * 0.4, t * flow_x) - fl * 1.6) * 0.4;
	// Живая жидкость: рябь и корка плывут по течению клетки (две фазы сноса
	// вперемешку, чтобы узор не растягивался), стоячая — колышется на месте.
	float cr = 0.0;
	float cs = 0.0;
	if (vflow) {
		float ph = fract(TIME * 0.5);
		float mixk = abs(ph - 0.5) * 2.0;
		vec2 va = vvel * scale * 2.0;
		vec2 u0 = uv - va * ph;
		vec2 u1 = uv - va * fract(ph + 0.5) + vec2(3.7, 1.3);
		float r0 = vnoise(u0 * 1.3 + vec2(t * flow_x, t * 0.2)) * 0.6 + vnoise(u0 * 3.1 - vec2(t * 0.4, t * flow_x)) * 0.4;
		float r1 = vnoise(u1 * 1.3 + vec2(t * flow_x, t * 0.2)) * 0.6 + vnoise(u1 * 3.1 - vec2(t * 0.4, t * flow_x)) * 0.4;
		r = mix(r0, r1, mixk);
		// Корка — крупные пятна: цикл дольше (6 с), иначе при смене фаз они «кипят».
		float pc = fract(TIME / 6.0);
		float mc = abs(pc - 0.5) * 2.0;
		vec2 c0 = uv - vvel * scale * 6.0 * pc;
		vec2 c1 = uv - vvel * scale * 6.0 * fract(pc + 0.5) + vec2(5.1, 2.9);
		cr = mix(vnoise(c0 * 1.7), vnoise(c1 * 1.7), mc);
		cs = mix(vnoise(c0 * 0.7), vnoise(c1 * 0.7), mc);
	}
	// Рябь от робота — в нормаль (сетка крупная, одной вершиной круг не нарисовать).
	float e = 0.08;
	float h0 = ripples(w.xz);
	vec2 grad = clamp(vec2(ripples(w.xz + vec2(e, 0.0)) - h0, ripples(w.xz + vec2(0.0, e)) - h0) / e, vec2(-2.0), vec2(2.0));
	vec3 col = base_color.rgb * (0.92 + 0.16 * r);
	// Течение: вытянутые вдоль потока светлые полосы пены.
	float fs = length(vflow ? vvel : flow);
	if (fs > 0.01 && !vflow) {
		vec2 fd = flow / fs;
		vec2 q = vec2(dot(w.xz, fd), dot(w.xz, vec2(-fd.y, fd.x)));
		float streak = vnoise(vec2(q.x * 0.35 - TIME * fs * 0.8, q.y * 2.2)) * vnoise(vec2(q.x * 0.9 - TIME * fs, q.y * 4.0));
		col = mix(col, mix(base_color.rgb, vec3(1.0), 0.55), smoothstep(0.35, 0.6, streak) * 0.45 * (1.0 - crust));
	}
	col += vec3(clamp(h0, 0.0, 1.0)) * 0.5 * (1.0 - crust);
	float c = smoothstep(0.55, 0.7, vflow ? cs : vnoise(uv * 0.7 + vec2(t * 0.05, 0.0) - fl * 0.2)) * crust;
	// Остывая, лава затягивается коркой с краёв пятен, пока не застынет целиком.
	c = max(c, 1.0 - smoothstep(0.15, 0.65, vh + ((vflow ? cr : vnoise(uv * 1.7)) - 0.5) * 0.3));
	// Быстрое течение светлее (пена воды, жар раскрытой лавы).
	if (vflow) {
		col = mix(col, mix(base_color.rgb, vec3(1.0), 0.5), smoothstep(0.6, 2.5, fs) * (0.35 + r * 0.3) * (1.0 - crust));
		col += base_color.rgb * glow * smoothstep(0.4, 2.0, fs) * 0.35 * crust * (1.0 - c);
	}
	col = mix(col, vec3(0.045, 0.04, 0.042) * (0.7 + 0.6 * vnoise(uv * 4.0)), c);
	float b = step(0.93, vnoise(uv * 6.0 + vec2(0.0, t * 1.5))) * bubbles;
	col += vec3(b) * 0.6;
	// Завеса (ProtoLiquids.sloped): жидкость переливается через кромку и падает
	// дугой — струи бегут вниз, у кромки пена, внизу струя рвётся в брызги и тает.
	float fall = vfall.x;
	float ft = vfall.y;
	float jets = 0.0;
	if (fall > 0.0) {
		// Струи: узкие светлые жгуты вдоль падения, между ними просветы.
		float along = (w.x + w.z) * 2.6;
		float fy = w.y * 0.35 + TIME * 3.0;
		jets = smoothstep(0.35, 0.75, vnoise(vec2(along, fy)) * 0.65 + vnoise(vec2(along * 2.7 + 3.0, fy * 0.6)) * 0.35);
		float lip = 1.0 - smoothstep(0.0, 0.18, ft);
		vec3 foam = mix(base_color.rgb, vec3(1.0), 0.75);
		col = mix(mix(base_color.rgb, foam, 0.35), foam, clamp(jets + lip + ft * 0.4, 0.0, 1.0)) * (1.0 - crust) + col * crust;
	}
	vec3 nm = vec3(0.5 + (r - 0.5) * 0.6 * wave - grad.x * 0.1, 0.5 + (vnoise(uv * 2.0 + t) - 0.5) * 0.6 * wave - grad.y * 0.1, 1.0);
	if (FRONT_FACING || fall > 0.5) {
		ALBEDO = col;
		ALPHA = mix(base_color.a, 1.0, c);
		if (fall > 0.0) {
			// Кромка — сплошная пена, ниже вода рвётся на струи и к низу тает в брызги.
			float lip = 1.0 - smoothstep(0.0, 0.18, ft);
			ALPHA = clamp(max(lip * 0.9, 0.12 + jets * 0.8) * (1.0 - smoothstep(0.65, 1.0, ft)), 0.0, 1.0);
		}
		METALLIC = metal * (1.0 - c);
		ROUGHNESS = mix(rough + r * 0.04, 0.9, c);
		SPECULAR = mix(0.8, 0.05, c);
		EMISSION = base_color.rgb * glow * (1.0 - c) * (0.7 + 0.6 * r);
	} else {
		// Снизу: светлое колышущееся «окно» неба, по краям ряби — блики.
		float sw = 0.55 + 0.45 * vnoise(uv * 2.4 + vec2(t * 0.6, -t * 0.5) - fl);
		vec3 lit = mix(base_color.rgb, vec3(0.9, 0.95, 1.0), 0.45 * (1.0 - metal));
		ALBEDO = col * 0.3;
		ALPHA = mix(0.9, 1.0, max(c, metal));
		METALLIC = 0.0;
		ROUGHNESS = 0.6;
		SPECULAR = 0.2;
		EMISSION = mix(lit * (0.55 + 0.6 * sw) + vec3(abs(h0)) * 1.5, col * 0.2, c) + base_color.rgb * glow * (1.0 - c);
	}
	NORMAL_MAP = nm;
}
"""

static var _shader: Shader

## Параметры вида жидкости из материала.
static func look(s: Substance, ambient: float) -> Dictionary:
	var d := {"color": s.color.darkened(0.25), "alpha": 0.8, "metal": 0.25, "rough": 0.04, "glow": 0.0,
		"speed": 1.0, "scale": 1.0, "bubbles": 0.0, "crust": 0.0, "vapor": false, "haze": false,
		"wave": 1.0, "rip_speed": 1.6, "rip_damp": 1.2}
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
	# Вязкая жидкость — гладкая, круги медленные и быстро гаснут; текучая — наоборот.
	var visc := ProtoSwim.viscosity(s)
	d.wave = clampf(1.6 / (1.0 + visc * 0.6), 0.2, 1.4)
	d.rip_speed = clampf(2.2 / (1.0 + visc * 0.25), 0.5, 2.4)
	d.rip_damp = 0.8 + visc * 0.45
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
	for k in ["metal", "rough", "glow", "speed", "scale", "bubbles", "crust", "wave", "rip_speed", "rip_damp"]:
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

## Круглая гладь (чаша): диск радиуса r на уровне level — край уходит под стенку
## чаши ровно по кругу, а не квадратными клетками над её склоном.
static func disc_mesh(c: Vector2, r: float, level: float, seg := 40) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var o := Vector3(c.x, level, c.y)
	for k in seg:
		var a0 := TAU * k / seg
		var a1 := TAU * (k + 1) / seg
		for p in [o, o + Vector3(cos(a1), 0, sin(a1)) * r, o + Vector3(cos(a0), 0, sin(a0)) * r]:
			st.set_normal(Vector3.UP)
			st.add_vertex(p)
	return st.commit()

## Поверхность жидкости с уровнем, зависящим от места (level — Callable(x, z) -> float),
## только там, где рельеф ниже уровня: река спускается по руслу.
static func sloped_mesh(terrain: ProtoTerrain, level: Callable, area: Callable) -> ArrayMesh:
	return sloped(terrain, level, area)[0]

const VOID := 1.8            # пол глубже под гладью — там дыра (ход в пещеру, яма), м
const CURTAIN := 0.35        # край выше пола снаружи на столько — опускаем завесу, м

## Как sloped_mesh, но по настоящему полю плотности (с правками рельефа) и без
## висящих краёв: над дырой (ход в пещеру под руслом, глубокая яма) глади нет,
## а где соседняя клетка ниже глади (край над ямой, конец русла) — с края вниз
## до пола опущена завеса: вода стекает водопадом, а не висит плёнкой.
## other — Callable(x, z) -> bool: там другая жидкость (озеро), к ней не
## стекаем и завес не ставим. target — сетка, в которую собрать (иначе новая).
## span — Callable(x) -> Vector2i: полоса клеток z в столбце x, где вообще может
## быть область (русло), чтобы не обходить всю карту.
## Возвращает [сетка, мокрые клетки (PackedByteArray sx × sz)].
static func sloped(terrain: ProtoTerrain, level: Callable, area: Callable, other := Callable(),
		target: ArrayMesh = null, span := Callable()) -> Array:
	var nx := terrain.sx
	var nz := terrain.sz
	var wet := PackedByteArray()
	wet.resize(nx * nz)
	var lv := PackedFloat32Array()
	lv.resize(nx * nz)
	var zr := PackedInt32Array()
	zr.resize(nx * 2)
	for x in nx:
		var sp: Vector2i = span.call(x) if span.is_valid() else Vector2i(0, nz - 1)
		zr[x * 2] = clampi(sp.x, 0, nz - 1)
		zr[x * 2 + 1] = clampi(sp.y, 0, nz - 1)
	for x in nx:
		for z in range(zr[x * 2], zr[x * 2 + 1] + 1):
			var cx := x + 0.5
			var cz := z + 0.5
			if not area.call(cx, cz) or (other.is_valid() and other.call(cx, cz)):
				continue
			var y0: float = level.call(cx, cz)
			lv[x + z * nx] = y0
			if terrain.field_at(Vector3(cx, y0 + 0.2, cz)) > 0.0:
				continue                          # берег выше глади
			if _drop(terrain, cx, y0, cz, VOID, 0.3) > VOID:
				continue                          # под гладью дыра
			wet[x + z * nx] = 1
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var nb := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	var feet := PackedVector3Array()
	for x in nx:
		for z in range(zr[x * 2], zr[x * 2 + 1] + 1):
			if wet[x + z * nx] == 0:
				continue
			var ys := [level.call(x, z), level.call(x + 1, z), level.call(x + 1, z + 1), level.call(x, z + 1)]
			var c := [Vector3(x, ys[0], z), Vector3(x + 1, ys[1], z), Vector3(x + 1, ys[2], z + 1), Vector3(x, ys[3], z + 1)]
			for tri in [[0, 1, 2], [0, 2, 3]]:
				for k in tri:
					st.set_uv2(Vector2.ZERO)
					st.set_normal(Vector3.UP)
					st.add_vertex(c[k])
			# Завесы: к соседу, который ниже глади и не мокрый (и не другая жидкость).
			var y0 := lv[x + z * nx]
			for k in 4:
				var n: Vector2i = Vector2i(x, z) + nb[k]
				if n.x < 0 or n.y < 0 or n.x >= nx or n.y >= nz or wet[n.x + n.y * nx] == 1:
					continue
				var ncx := n.x + 0.5
				var ncz := n.y + 0.5
				if other.is_valid() and other.call(ncx, ncz):
					continue
				if terrain.field_at(Vector3(ncx, y0 - CURTAIN, ncz)) > 0.0:
					continue                      # берег держит воду
				var fl := y0 - _drop(terrain, ncx, y0, ncz, 12.0, 0.4)   # низ завесы уходит в породу
				# Ребро клетки со стороны соседа: два угла.
				var e: Array = [[1, 2], [3, 0], [2, 3], [0, 1]][k]
				var out := Vector3(nb[k].x, 0, nb[k].y)
				_fall(st, c[e[0]], c[e[1]], fl, out)
				feet.append(Vector3(ncx, fl + 0.2, ncz))
	if target != null:
		target.clear_surfaces()
		return [st.commit(target), wet, feet]
	return [st.commit(), wet, feet]

const FALL_SEG := 7          # отрезков по высоте в дуге водопада
const FALL_V := 0.8          # скорость струи через кромку, м/с (дуга наружу)

## Водопад с ребра a–b вниз до fl: струя срывается с кромки со скоростью FALL_V
## и падает дугой наружу (out), UV2 = (1, доля высоты) — шейдеру для пены и
## просветов. Кромка — ровно ребро глади, без шва.
static func _fall(st: SurfaceTool, a: Vector3, b: Vector3, fl: float, out: Vector3) -> void:
	var rows: Array = []
	for sgm in FALL_SEG + 1:
		var t := float(sgm) / FALL_SEG
		var ra := a.lerp(Vector3(a.x, fl, a.z), t)
		var rb := b.lerp(Vector3(b.x, fl, b.z), t)
		# Сколько пролетела вниз — столько времени летит: смещение v·√(2h/g).
		var off := minf(FALL_V * sqrt(2.0 * (a.y - ra.y) / 9.8), 0.9)
		rows.append([ra + out * off, rb + out * off, t])
	for sgm in FALL_SEG:
		var r0: Array = rows[sgm]
		var r1: Array = rows[sgm + 1]
		var nrm: Vector3 = (out + Vector3(0, 0.15, 0)).normalized()
		for q in [[r0[0], r0[2]], [r0[1], r0[2]], [r1[1], r1[2]], [r0[0], r0[2]], [r1[1], r1[2]], [r1[0], r1[2]]]:
			st.set_uv2(Vector2(1.0, q[1]))
			st.set_normal(nrm)
			st.add_vertex(q[0])

## На сколько ниже y пол в столбце (шагом step, не глубже limit) — по сетке поля
## (как видимый рельеф, с правками): грубо, зато быстро.
static func _drop(terrain: ProtoTerrain, x: float, y: float, z: float, limit: float, step: float) -> float:
	var dy := 0.0
	while dy < limit:
		dy += step
		if terrain.field_at(Vector3(x, y - dy, z)) > 0.0:
			return dy
	return limit + step

## Брызги и водяная пыль внизу водопадов (points — низы завес из sloped).
static func spray(points: PackedVector3Array, col: Color) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.name = "falls_spray"
	p.amount = 90
	p.lifetime = 1.2
	p.preprocess = 1.2
	p.direction = Vector3.UP
	p.spread = 70.0
	p.gravity = Vector3(0, -4.0, 0)
	p.initial_velocity_min = 0.6
	p.initial_velocity_max = 1.8
	p.scale_amount_min = 0.25
	p.scale_amount_max = 0.7
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
	m.albedo_color = Color(col.lerp(Color.WHITE, 0.7), 0.35)
	q.material = m
	p.mesh = q
	set_spray(p, points)
	return p

static func set_spray(p: CPUParticles3D, points: PackedVector3Array) -> void:
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_POINTS
	p.emission_points = points
	p.emitting = not points.is_empty()
	p.visible = not points.is_empty()

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
