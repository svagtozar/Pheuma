class_name ProtoWater
extends Node
## Как выглядит и звучит жидкость вокруг робота (плавание — ProtoPlayer/ProtoSwim):
##   • камера под поверхностью — туман цвета жидкости (густота — по мутности),
##     экран колышется и темнеет по краям, фара включается, звук глохнет;
##   • робот в жидкости — круги по поверхности (от шага, гребка, качки), всплеск
##     при входе, пузыри из-под головы.
## Работает поверх ProtoPlayer (идёт после него в дереве): туман он задаёт каждый
## кадр заново, здесь — только поправка под водой.

const RIPPLES := 8                # столько кругов шейдер жидкости рисует сразу
const OVERLAY := """
shader_type canvas_item;
uniform sampler2D screen : hint_screen_texture, filter_linear_mipmap;
uniform vec4 tint : source_color = vec4(0.2, 0.4, 0.6, 1.0);
uniform float murk = 0.5;
void fragment() {
	vec2 uv = SCREEN_UV;
	uv += vec2(sin(uv.y * 26.0 + TIME * 2.1), cos(uv.x * 21.0 + TIME * 1.7)) * 0.0022;
	vec3 c = textureLod(screen, uv, murk * 1.2).rgb;
	float v = length(UV - vec2(0.5, 0.45));
	c = mix(c, tint.rgb * (0.35 + 0.65 * (1.0 - UV.y)), 0.25 + 0.35 * murk);
	c *= 1.0 - v * v * (0.8 + murk);
	COLOR = vec4(c, 1.0);
}
"""

var robot: Node3D
var cam: Camera3D
var env: Environment
var player: ProtoPlayer
var health: ProtoHealth
var zones: Array = []             # liquid_zones превью: {sub, level, area, mat, flow}

var under := 0.0                  # 0..1 — камера под поверхностью (сглажено)
var cam_liquid: Substance = null  # в чём камера
var cam_depth := 0.0
var _rips: Array = []             # [{mat, pos: Vector2, age, s}]
var _rip_t := 0.0
var _was_f := 0.0
var _was_vy := 0.0
var _layer: CanvasLayer
var _rect: ColorRect
var _bubbles: CPUParticles3D
var _splash: CPUParticles3D
var _lowpass: AudioEffectLowPassFilter
var _mats: Array = []             # материалы жидкостей, у которых есть круги

func setup(pl: ProtoPlayer, h: ProtoHealth, e: Environment, z: Array) -> void:
	player = pl
	robot = pl.robot
	cam = pl.cam
	health = h
	env = e
	zones = z

func _ready() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 3                  # под вспышками урона (4) и HUD (5)
	_rect = ColorRect.new()
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = OVERLAY
	var m := ShaderMaterial.new()
	m.shader = sh
	_rect.material = m
	_layer.add_child(_rect)
	_layer.visible = false
	add_child(_layer)
	_bubbles = _particles(24, 1.4, 0.05, 0.1)
	_bubbles.gravity = Vector3(0, 2.2, 0)
	_bubbles.initial_velocity_min = 0.2
	_bubbles.initial_velocity_max = 0.6
	_bubbles.emission_sphere_radius = 0.15
	_bubbles.emitting = false
	robot.add_child(_bubbles)
	_bubbles.position = Vector3(0, 1.6, 0.15)
	_splash = _particles(40, 0.9, 0.06, 0.16)
	_splash.one_shot = true
	_splash.explosiveness = 0.95
	_splash.direction = Vector3.UP
	_splash.spread = 35.0
	_splash.initial_velocity_min = 2.0
	_splash.initial_velocity_max = 4.5
	_splash.emission_sphere_radius = 0.5
	_splash.emitting = false
	add_child(_splash)
	for z: Dictionary in zones:
		if z.get("mat") != null and not _mats.has(z.mat):
			_mats.append(z.mat)

func _particles(n: int, life: float, r0: float, r1: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = n
	p.lifetime = life
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.scale_amount_min = r0 / 0.05
	p.scale_amount_max = r1 / 0.05
	var s := SphereMesh.new()
	s.radius = 0.05
	s.height = 0.1
	s.radial_segments = 6
	s.rings = 3
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.9, 0.95, 1.0, 0.55)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	s.material = m
	p.mesh = s
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p

func _process(dt: float) -> void:
	dt = minf(dt, 0.25)
	if robot == null or health == null or get_tree().paused:
		return
	_view(dt)
	_robot_fx(dt)
	_update_ripples(dt)

# ---------------------------------------------------------------- под водой

## Мутность жидкости 0..1: прозрачная (сверхтекучая) — видно далеко, металл
## и лава — почти ничего.
static func murk_of(s: Substance, ambient: float) -> float:
	var look := ProtoLiquids.look(s, ambient)
	var m: float = clampf((look.alpha - 0.4) / 0.6, 0.0, 1.0)
	if s.has("metallic") or s.melt > 300.0:
		m = 1.0
	return m

## Туман под поверхностью: цвет и плотность по жидкости и глубине.
static func fog_of(s: Substance, ambient: float, depth: float) -> Dictionary:
	var m := murk_of(s, ambient)
	var col := s.color.darkened(0.35 + clampf(depth / 12.0, 0.0, 0.4))
	return {"color": col, "density": lerpf(0.05, 0.55, m * m) + depth * 0.004}

func _view(dt: float) -> void:
	var cp := cam.global_position
	var lq := health.liquid_at(cp)
	cam_liquid = lq.get("sub")
	cam_depth = lq.get("depth", 0.0)
	under = move_toward(under, 1.0 if cam_liquid != null else 0.0, dt * 6.0)
	_layer.visible = under > 0.02
	_muffle(under > 0.5)
	if cam_liquid == null:
		return
	var amb: float = health.planet.ambient_temp if health.planet else 20.0
	var f := fog_of(cam_liquid, amb, cam_depth)
	env.fog_light_color = env.fog_light_color.lerp(f.color, under)
	env.fog_density = lerpf(env.fog_density, f.density, under)
	var m := _rect.material as ShaderMaterial
	m.set_shader_parameter("tint", cam_liquid.color.darkened(0.2))
	m.set_shader_parameter("murk", murk_of(cam_liquid, amb))
	# Под водой темно — фара и подсветка глаза.
	var lamp := robot.find_child("head_lamp", true, false) as SpotLight3D
	if lamp:
		lamp.light_energy = maxf(lamp.light_energy, 4.0 * under)
	var eye := robot.find_child("eye_light", true, false) as OmniLight3D
	if eye:
		eye.light_energy = maxf(eye.light_energy, 1.0 * under)

## Под водой звук глохнет: фильтр низких частот на общей шине.
func _muffle(on: bool) -> void:
	if _lowpass == null:
		if not on:
			return
		_lowpass = AudioEffectLowPassFilter.new()
		_lowpass.cutoff_hz = 700.0
		AudioServer.add_bus_effect(0, _lowpass)
	for i in AudioServer.get_bus_effect_count(0):
		if AudioServer.get_bus_effect(0, i) == _lowpass:
			AudioServer.set_bus_effect_enabled(0, i, on)

func _exit_tree() -> void:
	if _lowpass == null:
		return
	for i in AudioServer.get_bus_effect_count(0):
		if AudioServer.get_bus_effect(0, i) == _lowpass:
			AudioServer.remove_bus_effect(0, i)
			break

# ---------------------------------------------------------------- круги, всплеск, пузыри

func _robot_fx(dt: float) -> void:
	var wet: Dictionary = player.wet
	var f := player.wet_f
	var p := robot.position
	if f > 0.0 and wet.has("zone"):
		var lv: float = wet.level
		var mat = wet.zone.get("mat")
		# Всплеск: вошёл в жидкость с разгону.
		if _was_f <= 0.02 and -_was_vy > 2.0:
			_splash.global_position = Vector3(p.x, lv, p.z)
			var sm := (_splash.mesh as SphereMesh).material as StandardMaterial3D
			sm.albedo_color = Color(wet.sub.color.lerp(Color.WHITE, 0.5), 0.7)
			_splash.initial_velocity_max = clampf(-_was_vy * 0.7, 2.0, 6.0) / (1.0 + player.visc * 0.3)
			_splash.restart()
			_ripple(mat, p, clampf(-_was_vy * 0.25, 0.6, 1.6))
		# Круги там, где корпус пересекает поверхность: чаще, когда идёт или гребёт.
		var head_out := lv < p.y + ProtoSwim.BODY_H + 0.2
		var moving := Vector2(player.vel.x, player.vel.z).length() > 0.3 or absf(player.vy) > 0.3
		_rip_t -= dt
		if head_out and _rip_t <= 0.0:
			_rip_t = 0.35 if moving else 1.3
			_ripple(mat, p, 0.55 if moving else 0.3)
		# Пузыри — голова под поверхностью.
		var deep := lv - (p.y + 1.6)
		if wet.sub.melt > 300.0:
			deep = 0.0                   # из расплава пузырей не видно
		_bubbles.emitting = deep > 0.3
		if deep > 0.3:
			_bubbles.lifetime = clampf(deep / 1.4, 0.3, 2.0)
	else:
		_bubbles.emitting = false
	_was_f = f
	_was_vy = player.vy if player.air else 0.0

func _ripple(mat, p: Vector3, s: float) -> void:
	if mat == null:
		return
	_rips.append({"mat": mat, "pos": Vector2(p.x, p.z), "age": 0.0, "s": s})
	while _rips.size() > RIPPLES:
		_rips.pop_front()

func _update_ripples(dt: float) -> void:
	for r: Dictionary in _rips:
		r.age += dt
	_rips = _rips.filter(func(r): return r.age < 4.0)
	for m: ShaderMaterial in _mats:
		var arr := PackedVector4Array()
		arr.resize(RIPPLES)
		var i := 0
		for r: Dictionary in _rips:
			if r.mat == m:
				arr[i] = Vector4(r.pos.x, r.pos.y, r.age, r.s)
				i += 1
		m.set_shader_parameter("rip", arr)
