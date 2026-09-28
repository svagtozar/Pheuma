shader_type sky;
// Небо планеты со сменой дня и ночи (ProtoDayNight задаёт параметры):
// градиент дня/ночи, закат у солнца, диск звезды (и второй у двойной),
// звёзды и полоса галактики, луны с фазой, кольца с тенью планеты,
// облака, полярное сияние и чёрная дыра. В проходе кубокарты (отражения,
// сияние) — только градиент и ореол солнца: деталям там делать нечего.

uniform mat3 local_frame = mat3(1.0);         // мир → местная система (на круглой планете — своя в каждой точке)
uniform vec3 sun_dir = vec3(0.0, 0.7, 0.7);   // к солнцу
uniform vec3 sun_color : source_color = vec3(1.0, 0.96, 0.9);
uniform float sun_size = 0.03;                // угловой радиус, рад
uniform float sun_glow = 0.35;
uniform float haze = 1.0;                     // плотность атмосферы: шире ореол
uniform vec4 sun2 = vec4(0.0);                // второе солнце: направление, радиус (0 — нет)
uniform vec3 sun2_color : source_color = vec3(1.0);

uniform vec3 day_top : source_color = vec3(0.25, 0.42, 0.7);
uniform vec3 day_hor : source_color = vec3(0.7, 0.72, 0.75);
uniform vec3 night_top : source_color = vec3(0.01, 0.015, 0.035);
uniform vec3 night_hor : source_color = vec3(0.05, 0.06, 0.09);
uniform vec3 sunset_col : source_color = vec3(1.0, 0.5, 0.25);
uniform vec3 ground_col : source_color = vec3(0.2, 0.18, 0.16);
uniform vec3 low_glow : source_color = vec3(0.0);   // зарево снизу ночью (лава)
uniform float day = 1.0;                      // 0 — ночь, 1 — день
uniform float twilight = 0.0;                 // закат/рассвет

uniform float stars = 0.7;
uniform mat3 star_rot = mat3(1.0);
uniform vec3 band_n = vec3(0.3, 0.2, 0.93);   // полоса галактики — нормаль её плоскости

uniform vec4 moon0 = vec4(0.0);               // направление, радиус (0 — нет)
uniform vec3 moon0_col : source_color = vec3(0.8);
uniform vec4 moon1 = vec4(0.0);
uniform vec3 moon1_col : source_color = vec3(0.8);

uniform float ring_on = 0.0;
uniform vec3 ring_n = vec3(0.0, 0.8, 0.6);    // нормаль плоскости колец
uniform vec2 ring_r = vec2(1.6, 2.5);         // радиусы в радиусах планеты
uniform vec3 ring_col : source_color = vec3(0.8, 0.75, 0.68);
uniform float ring_seed = 0.0;

uniform float cloud_cover = 0.3;
uniform vec2 cloud_shift = vec2(0.0);
uniform vec3 cloud_col : source_color = vec3(0.9);

uniform float aurora = 0.0;
uniform vec3 aurora_col : source_color = vec3(0.3, 1.0, 0.55);
uniform vec2 aurora_shift = vec2(0.0);

uniform vec4 hole = vec4(0.0);                // чёрная дыра: направление, радиус

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float hash12(vec2 p) {
	vec3 q = fract(vec3(p.xyx) * 0.1031);
	q += dot(q, q.yzx + 33.33);
	return fract((q.x + q.y) * q.z);
}

float noise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash12(i);
	float b = hash12(i + vec2(1.0, 0.0));
	float c = hash12(i + vec2(0.0, 1.0));
	float d = hash12(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
	float s = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		s += a * noise2(p);
		p = p * 2.03 + vec2(17.1, 9.2);
		a *= 0.5;
	}
	return s;
}

// Один слой звёзд: ячейки сетки на сфере, в части ячеек — звезда.
vec3 star_layer(vec3 d, float scale, float density, float size) {
	vec3 p = d * scale;
	vec3 c = floor(p);
	float h = hash13(c);
	if (h > density) {
		return vec3(0.0);
	}
	vec3 o = vec3(hash13(c + 11.3), hash13(c + 27.7), hash13(c + 41.9)) * 0.6 + 0.2;
	float dist = length(fract(p) - o);
	float b = smoothstep(size, 0.0, dist) * (0.35 + 1.4 * pow(hash13(c + 5.1), 3.0));
	float t = hash13(c + 71.0);
	vec3 tint = t < 0.3 ? vec3(1.0, 0.75, 0.55) : (t < 0.8 ? vec3(1.0, 0.97, 0.92) : vec3(0.7, 0.82, 1.0));
	return tint * b;
}

// Диск луны с фазой: освещена сторона к солнцу, кратеры — шумом.
vec4 moon_at(vec3 d, vec4 m, vec3 col) {
	if (m.w <= 0.0) {
		return vec4(0.0);
	}
	vec3 md = normalize(m.xyz);
	float cd = dot(d, md);
	if (cd < cos(m.w * 1.05)) {
		return vec4(0.0);
	}
	vec3 t = normalize(cross(md, abs(md.y) < 0.95 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0)));
	vec3 b = cross(md, t);
	vec2 xy = vec2(dot(d, t), dot(d, b)) / m.w;
	float r2 = dot(xy, xy);
	float a = smoothstep(1.0, 0.94, sqrt(r2));
	float z = sqrt(max(0.0, 1.0 - r2));
	vec3 n = normalize(t * xy.x + b * xy.y - md * z);
	float lit = clamp(dot(n, sun_dir) * 1.3, 0.0, 1.0);
	float crater = 0.75 + 0.35 * fbm(xy * 3.0 + md.xz * 40.0);
	return vec4(col * crater * (lit + 0.025), a);
}

void sky() {
	// Все направления — в местной системе наблюдателя (Y — местный верх).
	vec3 d = normalize(local_frame * EYEDIR);
	float up = d.y;
	float h = clamp(up, 0.0, 1.0);
	vec3 top = mix(night_top, day_top, day);
	vec3 hor = mix(night_hor, day_hor, day);
	vec3 col = mix(hor, top, pow(h, 0.45));
	float sd = dot(d, sun_dir);
	// Закат: у горизонта со стороны солнца.
	float toward = pow(clamp(sd * 0.5 + 0.5, 0.0, 1.0), 3.0);
	col = mix(col, sunset_col, twilight * toward * (1.0 - smoothstep(-0.05, 0.45, up)));
	col += sunset_col * twilight * 0.25 * (1.0 - smoothstep(0.0, 0.3, up));
	// Зарево снизу (лава) ночью.
	col += low_glow * (1.0 - day) * (1.0 - smoothstep(-0.05, 0.25, up));
	// Ореол солнца: в густой атмосфере шире.
	float vis_sun = smoothstep(-0.12, 0.02, sun_dir.y);
	col += sun_color * pow(max(sd, 0.0), 6.0 / haze) * sun_glow * vis_sun;
	col += sun_color * pow(max(sd, 0.0), 60.0 / haze) * sun_glow * vis_sun;
	// Под горизонтом — земля в дымке.
	if (up < 0.0) {
		col = mix(col, ground_col * (0.15 + 0.85 * day), smoothstep(0.0, -0.25, up));
	}
	if (AT_CUBEMAP_PASS) {
		COLOR = col;
	} else {
		float sky_open = smoothstep(-0.02, 0.03, up);
		// Звёзды и галактика: видны ночью, в разреженном воздухе — и днём.
		float star_vis = stars * clamp(1.0 - day * 1.25, 0.0, 1.0) * sky_open;
		vec3 sp = star_rot * d;
		// Возле чёрной дыры звёзды отодвигает (линза).
		float ha = 10.0;
		if (hole.w > 0.0) {
			vec3 hd = normalize(hole.xyz);
			ha = acos(clamp(dot(d, hd), -1.0, 1.0));
			vec3 away = normalize(d - hd * dot(d, hd) + vec3(1e-4));
			sp = star_rot * normalize(d + away * hole.w * hole.w * 2.0 / max(ha, hole.w));
		}
		if (star_vis > 0.001) {
			vec3 s = star_layer(sp, 90.0, 0.10, 0.22) * 1.6 + star_layer(sp, 230.0, 0.22, 0.28) * 0.7;
			float band = exp(-pow(dot(sp, band_n) * 3.2, 2.0));
			s += star_layer(sp, 400.0, 0.35 * band, 0.3) * 0.6;
			vec3 milky = vec3(0.55, 0.55, 0.7) * band * (0.25 + 0.75 * fbm(vec2(atan(sp.z, sp.x) * 6.0, sp.y * 9.0)));
			col += (s + milky * 0.09) * star_vis;
		}
		// Кольца: луч от наблюдателя на плоскость колец через центр планеты.
		if (ring_on > 0.0 && up > 0.0) {
			vec3 c = vec3(0.0, -1.0, 0.0);
			float dn = dot(d, ring_n);
			if (abs(dn) > 1e-4) {
				float t = dot(c, ring_n) / dn;
				if (t > 0.0) {
					vec3 q = d * t - c;
					float r = length(q);
					if (r > ring_r.x && r < ring_r.y) {
						float u = (r - ring_r.x) / (ring_r.y - ring_r.x);
						float bands = 0.55 + 0.45 * sin(u * 26.0 + ring_seed) * sin(u * 9.0 + ring_seed * 2.0);
						bands *= smoothstep(0.0, 0.06, u) * smoothstep(1.0, 0.9, u);
						bands *= 1.0 - 0.85 * smoothstep(0.02, 0.0, abs(u - 0.62)); // щель
						float along = dot(q, sun_dir);
						float shadow = along < 0.0 && length(q - sun_dir * along) < 1.0 ? 0.12 : 1.0;
						vec3 rc = ring_col * sun_color * (0.1 + 0.9 * shadow);
						float a = clamp(bands, 0.0, 1.0) * ring_on * mix(0.9, 0.55, day) * smoothstep(0.0, 0.05, up);
						col = mix(col, max(col, rc), a);
					}
				}
			}
		}
		// Луны.
		vec4 m0 = moon_at(d, moon0, moon0_col);
		vec4 m1 = moon_at(d, moon1, moon1_col);
		float moon_fade = mix(1.0, 0.55, day) * sky_open;
		col = mix(col, col * 0.3 * day + m0.rgb, m0.a * moon_fade);
		col = mix(col, col * 0.3 * day + m1.rgb, m1.a * moon_fade);
		// Чёрная дыра: тёмное ядро, яркое кольцо.
		if (hole.w > 0.0) {
			float ring = exp(-pow((ha - hole.w * 1.35) / (hole.w * 0.22), 2.0));
			col = mix(col, vec3(0.0), smoothstep(hole.w * 1.05, hole.w * 0.95, ha) * sky_open);
			col += vec3(1.0, 0.75, 0.5) * ring * 1.6 * sky_open;
			col += vec3(0.6, 0.4, 0.8) * exp(-ha / (hole.w * 3.0)) * 0.12 * sky_open;
		}
		// Полярное сияние — ночью, ленты над горизонтом.
		if (aurora > 0.0 && up > 0.0) {
			vec2 uv = d.xz / (up + 0.35);
			float n = fbm(uv * vec2(0.8, 0.25) + aurora_shift);
			float rib = exp(-pow((n - 0.5) * 16.0, 2.0)) + 0.5 * exp(-pow((n - 0.62) * 22.0, 2.0));
			float fade = smoothstep(0.03, 0.18, up) * (1.0 - smoothstep(0.35, 0.85, up));
			vec3 ac = mix(aurora_col, aurora_col.bgr, smoothstep(0.1, 0.5, up));
			col += ac * rib * fade * aurora * (1.0 - day) * 0.5;
		}
		// Солнце (и второе) — диск с потемнением к краю.
		float cover = 0.0;
		if (cloud_cover > 0.0 && up > 0.0) {
			vec2 uv = d.xz / (up + 0.08) * 0.55 + cloud_shift;
			float n = fbm(uv);
			float edge = 0.72 - cloud_cover * 0.5;
			cover = smoothstep(edge, edge + 0.2, n) * smoothstep(0.0, 0.1, up);
		}
		float disc = smoothstep(cos(sun_size), cos(sun_size * 0.85), sd);
		float limb = 0.6 + 0.4 * smoothstep(cos(sun_size), 1.0, sd);
		col += sun_color * 7.0 * disc * limb * vis_sun * (1.0 - cover * 0.92);
		if (sun2.w > 0.0) {
			float s2d = dot(d, normalize(sun2.xyz));
			float disc2 = smoothstep(cos(sun2.w), cos(sun2.w * 0.85), s2d);
			float v2 = smoothstep(-0.05, 0.02, sun2.y);
			col += sun2_color * (6.0 * disc2 + pow(max(s2d, 0.0), 200.0) * 0.8) * v2 * (1.0 - cover * 0.92);
		}
		// Облака: днём белые с тёплым краем к солнцу, в сумерках — в цвет заката,
		// ночью — тёмные силуэты (с заревом снизу у лавовых).
		if (cover > 0.0) {
			vec3 lit = cloud_col * mix(vec3(0.75), sun_color * 1.15, 0.4 + 0.6 * toward);
			vec3 cc = mix(hor * 0.9, lit, day);
			cc = mix(cc, sunset_col * 0.9 + cloud_col * 0.2, twilight * (0.4 + 0.6 * toward));
			cc = mix(cc, night_hor * 1.4 + low_glow * 0.6, (1.0 - day) * (1.0 - twilight));
			col = mix(col, cc, cover * 0.92);
		}
		COLOR = col;
	}
}
