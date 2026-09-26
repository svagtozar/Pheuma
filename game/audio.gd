extends Node
## Звук без ассетов: все эффекты синтезируются при запуске (AudioStreamWAV).
## Мир складывает события в world.sfx, этот узел их проигрывает с громкостью
## по расстоянию до робота. Фоновый ветер зависит от атмосферы планеты.

const RATE := 22050
const MAX_DIST := 30.0

var world: World
var players: Array = []
var streams := {}
var ambient: AudioStreamPlayer
var _rng := RandomNumberGenerator.new()
var _last := {}
var _alarm_t := 0.0
var _crackle_t := 0.0

func _ready() -> void:
	_rng.seed = 1234
	for i in 14:
		var p := AudioStreamPlayer.new()
		add_child(p)
		players.append(p)
	streams = {
		"click": _mix([_tone(1500, 1500, 0.05, "sine", 50.0, 0.35)]),
		"clunk": _mix([_tone(260, 190, 0.09, "square", 30.0, 0.25)]),
		"tick": _mix([_noise(0.04, 80.0, 0.5, 0.35)]),
		"thump": _mix([_tone(140, 40, 0.35, "sine", 8.0, 0.9), _noise(0.35, 12.0, 0.15, 0.5)]),
		"hiss": _mix([_noise(0.3, 6.0, 0.9, 0.22)]),
		"land": _mix([_tone(90, 50, 0.15, "sine", 20.0, 0.6), _noise(0.15, 25.0, 0.3, 0.4)]),
		"boom": _mix([_noise(0.8, 4.0, 0.08, 1.0), _tone(60, 30, 0.8, "sine", 4.0, 0.7)]),
		"whoosh": _mix([_sweep_noise(0.35, 0.05, 0.6, 0.45)]),
		"chime": _mix([_tone(880, 880, 0.6, "sine", 6.0, 0.25), _tone(1320, 1320, 0.6, "sine", 7.0, 0.18)]),
		"fanfare": _mix([_seq([523, 659, 784, 1047], 0.16, 0.3)]),
		"rocket": _mix([_sweep_noise(1.6, 0.25, 0.08, 0.8), _tone(80, 50, 1.6, "sine", 1.5, 0.5)]),
		"alarm": _mix([_seq([700, 900, 700, 900], 0.1, 0.25, "square")]),
		"crackle": _mix([_noise(0.06, 60.0, 0.7, 0.25)]),
	}
	ambient = AudioStreamPlayer.new()
	ambient.stream = _to_wav(_noise(4.0, 0.0, 0.025, 0.6), true)
	add_child(ambient)

func set_world(w: World) -> void:
	world = w
	var db := -18.0
	if w.planet.has_tag("storms"): db += 9.0
	if w.planet.has_tag("dense_atmosphere"): db += 3.0
	if w.planet.has_tag("thin_atmosphere"): db -= 12.0
	ambient.volume_db = db
	if not ambient.playing:
		ambient.play()

func stop_all() -> void:
	world = null
	for p in players:
		p.stop()
		p.stream = null
	ambient.stop()
	ambient.stream = null
	streams.clear()

func _exit_tree() -> void:
	stop_all()

func play(name: String, dist: float = 0.0) -> void:
	if world == null or not streams.has(name) or dist > MAX_DIST:
		return
	var now := Time.get_ticks_msec()
	if now - _last.get(name, 0) < 50:
		return
	_last[name] = now
	for p in players:
		if not p.playing:
			p.stream = streams[name]
			p.volume_db = -dist * 0.7
			p.pitch_scale = _rng.randf_range(0.94, 1.06)
			p.play()
			return

func _process(dt: float) -> void:
	if world == null:
		return
	for e in world.sfx:
		play(e.name, (Vector2(e.cell) + Vector2(0.5, 0.5)).distance_to(world.robot.pos))
	world.sfx.clear()
	_alarm_t -= dt
	if world.robot.hp < world.robot.max_hp() * 0.3 and _alarm_t <= 0.0:
		play("alarm")
		_alarm_t = 2.5
	_crackle_t -= dt
	if not world.fires.is_empty() and _crackle_t <= 0.0:
		var c: Vector2i = world.fires.keys()[_rng.randi() % world.fires.size()]
		play("crackle", (Vector2(c) + Vector2(0.5, 0.5)).distance_to(world.robot.pos))
		_crackle_t = _rng.randf_range(0.08, 0.3)

# ---------------------------------------------------------------- синтез

func _tone(f0: float, f1: float, dur: float, wave: String, decay: float, vol: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / RATE
		var f: float = lerp(f0, f1, t / dur)
		phase += TAU * f / RATE
		var v := sin(phase)
		if wave == "square":
			v = 1.0 if v >= 0.0 else -1.0
		var env: float = exp(-decay * t) * min(1.0, t * 400.0)
		out[i] = v * env * vol
	return out

func _noise(dur: float, decay: float, lp: float, vol: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var y := 0.0
	for i in n:
		var t := float(i) / RATE
		y += lp * (_rng.randf_range(-1.0, 1.0) - y)
		var env: float = exp(-decay * t) * min(1.0, t * 400.0)
		if decay == 0.0:
			env = 1.0
		out[i] = y * env * vol * (1.0 / sqrt(max(lp, 0.02)))
	return out

func _sweep_noise(dur: float, lp0: float, lp1: float, vol: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var y := 0.0
	for i in n:
		var k := float(i) / n
		var lp: float = lerp(lp0, lp1, k)
		y += lp * (_rng.randf_range(-1.0, 1.0) - y)
		out[i] = y * sin(PI * k) * vol * 2.0
	return out

func _seq(freqs: Array, step: float, vol: float, wave: String = "sine") -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for f in freqs:
		out.append_array(_tone(f, f, step, wave, 10.0, vol))
	return out

func _mix(parts: Array) -> AudioStreamWAV:
	var n := 0
	for p in parts:
		n = max(n, p.size())
	var out := PackedFloat32Array()
	out.resize(n)
	for p in parts:
		for i in p.size():
			out[i] += p[i]
	return _to_wav(out)

func _to_wav(samples: PackedFloat32Array, loop: bool = false) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(clamp(samples[i], -1.0, 1.0) * 32767.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = RATE
	s.stereo = false
	s.data = bytes
	if loop:
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_end = samples.size()
	return s
