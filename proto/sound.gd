class_name ProtoSound
extends Node
## Звук 3D-прототипа без ассетов: всё синтезируется при запуске (AudioStreamWAV),
## лицензий и файлов нет. Слушатель — камера.
##   шаги     — на каждое касание стопы (по фазе шага RobotAnim): глухой удар
##              ботинка, металлический звон корпуса, хруст щебня; пять вариантов,
##              высота чуть гуляет;
##   бур      — сервопривод выдвигает бур, мотор раскручивается (высота растёт
##              вместе с оборотами), у породы добавляется скрежет со сколами;
##   кисть    — пневматический хлопок выстрела, лязг захвата, жужжание лебёдки;
##   фон      — ветер снаружи (порывы, громкость по атмосфере планеты), под
##              сводом — низкий гул пещеры и капли с потолка вокруг робота.
## Эхо пещеры: шаги, бур, кисть и капли идут через шину ProtoWorld с
## реверберацией; её «мокрая» доля растёт с тем, насколько робот под сводом.

const RATE := 22050
const BUS := "ProtoWorld"

var robot: Node3D
var anim: RobotAnim
var fist: RobotFist
var terrain: ProtoTerrain
var player: ProtoPlayer
var planet: Planet

var streams := {}
var steps: Array = []            # варианты шага
var drips: Array = []            # варианты капли
var _rng := RandomNumberGenerator.new()
var _sfx: Array = []             # пул AudioStreamPlayer3D
var _drill: AudioStreamPlayer3D
var _grind: AudioStreamPlayer3D
var _reel: AudioStreamPlayer3D
var _wind: AudioStreamPlayer
var _drone: AudioStreamPlayer
var _reverb: AudioEffectReverb
var _wind_db := -10.0
var _step_i := -1
var _drill_was := 0.0
var _fist_state := "dock"
var _drip_t := 1.0
var _record: AudioEffectRecord
var record_path := ""

## Шина с эхом пещеры (выход в Master); создаётся один раз.
static func ensure_bus() -> AudioEffectReverb:
	var i := AudioServer.get_bus_index(BUS)
	if i < 0:
		AudioServer.add_bus()
		i = AudioServer.bus_count - 1
		AudioServer.set_bus_name(i, BUS)
		AudioServer.set_bus_send(i, "Master")
		var r := AudioEffectReverb.new()
		r.room_size = 0.85
		r.damping = 0.45
		r.spread = 0.9
		r.predelay_msec = 70.0
		r.predelay_feedback = 0.35
		r.hipass = 0.15
		r.wet = 0.05
		r.dry = 1.0
		AudioServer.add_bus_effect(i, r)
	return AudioServer.get_bus_effect(i, 0) as AudioEffectReverb

func setup(r: Node3D, t: ProtoTerrain, p: ProtoPlayer, pl: Planet) -> void:
	robot = r
	terrain = t
	player = p
	planet = pl
	anim = robot.get_node_or_null("anim")
	fist = robot.get_node_or_null("fist")

func _ready() -> void:
	_rng.seed = 7
	_reverb = ensure_bus()
	build_streams()
	for i in 10:
		var sp := _player3d()
		_sfx.append(sp)
	_drill = _player3d(streams.drill)
	_grind = _player3d(streams.grind)
	_reel = _player3d(streams.reel)
	_wind = AudioStreamPlayer.new()
	_wind.stream = streams.wind
	add_child(_wind)
	_drone = AudioStreamPlayer.new()
	_drone.stream = streams.drone
	add_child(_drone)
	if planet:
		if planet.has_tag("storms"): _wind_db += 8.0
		if planet.has_tag("dense_atmosphere"): _wind_db += 3.0
		if planet.has_tag("thin_atmosphere"): _wind_db -= 14.0
	_wind.volume_db = _wind_db
	_drone.volume_db = -80.0
	_wind.play()
	_drone.play()
	if record_path != "":
		_record = AudioEffectRecord.new()
		AudioServer.add_bus_effect(0, _record)
		_record.set_recording_active(true)

func _exit_tree() -> void:
	if _record and _record.is_recording_active():
		var wav := _record.get_recording()
		_record.set_recording_active(false)
		if wav:
			wav.save_to_wav(record_path)
			print("звук записан: ", record_path)

func _player3d(s: AudioStream = null) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.bus = BUS
	p.unit_size = 6.0
	p.max_distance = 60.0
	p.attenuation_filter_cutoff_hz = 9000.0
	p.stream = s
	add_child(p)
	return p

## Все звуки. Отдельно от _ready, чтобы тесты могли синтезировать без сцены.
func build_streams() -> void:
	steps = []
	for k in 5:
		steps.append(to_wav(footstep(k)))
	drips = []
	for k in 4:
		drips.append(to_wav(drip(k)))
	streams = {
		"drill": to_wav(drill_loop(), true),
		"grind": to_wav(grind_loop(), true),
		"reel": to_wav(reel_loop(), true),
		"wind": to_wav(wind_loop(), true),
		"drone": to_wav(drone_loop(), true),
		"servo_out": to_wav(servo(true)),
		"servo_in": to_wav(servo(false)),
		"shot": to_wav(shot()),
		"clank": to_wav(clank()),
	}

# ---------------------------------------------------------------- игра

func _process(dt: float) -> void:
	if robot == null:
		return
	var under := player.under if player else 0.0
	_reverb.wet = 0.04 + 0.5 * under
	_reverb.dry = 1.0 - 0.15 * under
	_reverb.room_size = lerpf(0.5, 0.9, under)
	_wind.volume_db = _wind_db + linear_to_db(maxf(1.0 - under * 0.95, 0.001))
	_drone.volume_db = linear_to_db(maxf(under, 0.001)) - 17.0
	_footsteps(under)
	_drill_sound(dt)
	_fist_sound()
	_drips(dt, under)

## Касание стопы: левая — на целых фазах цикла, правая — на половинах.
func _footsteps(under: float) -> void:
	if anim == null or anim.walk_k < 0.15:
		_step_i = -1
		return
	var i := int(floor(anim.phase * 2.0))
	if _step_i >= 0 and i != _step_i:
		var foot := robot.to_global(Vector3(0.12 if i % 2 else -0.12, 0.05, 0.0))
		var db := linear_to_db(clampf(anim.walk_k, 0.3, 1.0)) - 2.0
		# В пещере под ногами щебень — шаг ниже и глуше.
		play_at(steps[_rng.randi() % steps.size()], foot, db, _rng.randf_range(0.93, 1.07) - 0.05 * under)
	_step_i = i

func _drill_sound(dt: float) -> void:
	if anim == null or anim.drill == null:
		return
	var out := anim.drill_out
	if out > 0.01 and _drill_was <= 0.01:
		play_at(streams.servo_out, anim.drill.global_position, -6.0)
	elif out < 0.99 and _drill_was >= 0.99:
		play_at(streams.servo_in, anim.drill.global_position, -6.0)
	_drill_was = out
	# Обороты — как у сверла в RobotAnim: крутится, когда бур выдвинут.
	var spin := anim.work * smoothstep(0.85, 1.0, out)
	var tip: Vector3 = anim.bit.global_position if anim.bit else anim.drill.global_position
	_drill.global_position = tip
	_grind.global_position = tip
	if spin > 0.02:
		if not _drill.playing:
			_drill.play()
		_drill.pitch_scale = lerpf(0.45, 1.0, spin)
		_drill.volume_db = linear_to_db(spin) - 4.0
	elif _drill.playing:
		_drill.stop()
	# Порода у сверла — скрежет со сколами.
	var rock := 0.0
	if spin > 0.2:
		var fwd := robot.global_transform.basis.z.normalized()
		for d in [0.0, 0.3, 0.6]:
			var q: Vector3 = tip + fwd * d
			if terrain.solid(q.x, q.y, q.z):
				rock = 1.0
				break
	var g := move_toward(db_to_linear(_grind.volume_db) if _grind.playing else 0.0, rock * spin, dt * 4.0)
	if g > 0.02:
		if not _grind.playing:
			_grind.play()
		_grind.volume_db = linear_to_db(g) - 3.0
	elif _grind.playing:
		_grind.stop()

func _fist_sound() -> void:
	if fist == null:
		return
	var s := fist.state
	if s != _fist_state:
		var at := robot.to_global(fist.fist_pos)
		match s:
			"fly": play_at(streams.shot, at, -2.0)
			"grab": play_at(streams.clank, at, -4.0)
			"dock": play_at(streams.clank, at, -10.0, 1.3)
		_fist_state = s
	var reel := s == "pull" or s == "back"
	_reel.global_position = robot.to_global(Vector3(-0.3, 1.2, 0.2))
	if reel and not _reel.playing:
		_reel.volume_db = -12.0
		_reel.pitch_scale = 1.15 if s == "back" else 0.9
		_reel.play()
	elif not reel and _reel.playing:
		_reel.stop()

## Капли с потолка: под сводом, в случайной точке вокруг робота.
func _drips(dt: float, under: float) -> void:
	_drip_t -= dt
	if _drip_t > 0.0:
		return
	_drip_t = _rng.randf_range(0.5, 2.8)
	if under < 0.5:
		return
	var p := robot.global_position + Vector3(_rng.randf_range(-7, 7), 0, _rng.randf_range(-7, 7))
	p.y = terrain.floor_at(p + Vector3(0, 1.0, 0)) + 0.1
	play_at(drips[_rng.randi() % drips.size()], p, _rng.randf_range(-12.0, -4.0), _rng.randf_range(0.85, 1.2))

func play_at(s: AudioStream, at: Vector3, db := 0.0, pitch := 1.0) -> void:
	for p in _sfx:
		if not p.playing:
			p.stream = s
			p.global_position = at
			p.volume_db = db
			p.pitch_scale = pitch
			p.play()
			return

# ---------------------------------------------------------------- синтез

func _buf(dur: float) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(int(dur * RATE))
	return b

## Шаг: глухой удар ботинка, звон металла корпуса и хруст щебня.
func footstep(k: int) -> PackedFloat32Array:
	var r := RandomNumberGenerator.new()
	r.seed = 100 + k
	var out := _buf(0.45)
	var n := out.size()
	var f0 := r.randf_range(95.0, 125.0)
	var ring := r.randf_range(380.0, 520.0)
	var partials := [1.0, 2.76, 5.40, 8.93]
	var ph := 0.0
	for i in n:
		var t := float(i) / RATE
		ph += TAU * lerpf(f0, f0 * 0.5, minf(t / 0.12, 1.0)) / RATE
		var v := sin(ph) * exp(-t * 26.0) * 0.55
		for j in partials.size():
			v += sin(TAU * ring * partials[j] * t) * exp(-t * (28.0 + 14.0 * j)) * 0.07 / (1.0 + j * 0.6)
		out[i] = v * minf(1.0, t * 800.0)
	# Щебень: короткие щелчки в первые 150 мс.
	var y := 0.0
	for c in 26:
		var at := int(r.randf_range(0.0, 0.15) * RATE)
		var amp := r.randf_range(0.05, 0.22) * exp(-float(at) / RATE * 12.0)
		var lp := r.randf_range(0.3, 0.8)
		for i in int(0.012 * RATE):
			if at + i >= n:
				break
			y += lp * (r.randf_range(-1.0, 1.0) - y)
			out[at + i] += y * amp * exp(-float(i) / RATE * 400.0)
	# Пшик пневматики в щиколотке.
	y = 0.0
	for i in int(0.08 * RATE):
		var t := float(i) / RATE
		y += 0.9 * (r.randf_range(-1.0, 1.0) - y)
		out[i] += y * 0.04 * exp(-t * 40.0) * minf(1.0, t * 300.0)
	return out

## Мотор бура: пила на 220 Гц с гармониками, вой шестерён, дрожь. Все частоты
## целые, петля — ровно секунда, стык без щелчка.
func drill_loop() -> PackedFloat32Array:
	var r := RandomNumberGenerator.new()
	r.seed = 11
	var out := _buf(1.0)
	var y := 0.0
	for i in out.size():
		var t := float(i) / RATE
		var v := 0.0
		for h in range(1, 9):
			v += sin(TAU * 220.0 * h * t) / h
		v *= 0.22 * (0.8 + 0.2 * sin(TAU * 30.0 * t))
		v += sin(TAU * 1760.0 * t) * 0.06 + sin(TAU * 2640.0 * t) * 0.03
		y += 0.5 * (r.randf_range(-1.0, 1.0) - y)
		out[i] = v + y * 0.08
	return out

## Скрежет по породе: полосовой шум с неровной амплитудой и сколами.
func grind_loop() -> PackedFloat32Array:
	var r := RandomNumberGenerator.new()
	r.seed = 12
	var n := int(2.0 * RATE)
	var out := _buf(2.0 + 0.1)
	var a := 0.0
	var b := 0.0
	var am := 0.5
	for i in out.size():
		var w := r.randf_range(-1.0, 1.0)
		a += 0.6 * (w - a)
		b += 0.08 * (w - b)
		if i % 300 == 0:
			am = r.randf_range(0.4, 1.0)
		var v := (a - b) * 0.45 * am
		if r.randf() < 0.0012:
			v += r.randf_range(-0.6, 0.6)
		out[i] = v
	return loopify(out, out.size() - n)

## Лебёдка троса: жужжание мотора с треском храповика.
func reel_loop() -> PackedFloat32Array:
	var out := _buf(0.5)
	for i in out.size():
		var t := float(i) / RATE
		var v := 0.0
		for h in range(1, 6):
			v += sin(TAU * 140.0 * h * t) / (h * h)
		var tick := fposmod(t * 24.0, 1.0)
		out[i] = v * 0.25 + sin(TAU * 3000.0 * t) * 0.12 * exp(-tick * 30.0)
	return out

## Ветер: шум через фильтр, частота среза и громкость гуляют порывами.
func wind_loop() -> PackedFloat32Array:
	var r := RandomNumberGenerator.new()
	r.seed = 13
	var len_s := 8.0
	var out := _buf(len_s + 0.5)
	var y := 0.0
	var y2 := 0.0
	for i in out.size():
		var t := float(i) / RATE
		var g := 0.5 + 0.3 * sin(TAU * t / len_s) + 0.2 * sin(TAU * 3.0 * t / len_s + 1.3)
		y += (0.01 + 0.05 * g) * (r.randf_range(-1.0, 1.0) - y)
		y2 += 0.3 * (y - y2)
		out[i] = y2 * (0.9 + 1.5 * g)
	return loopify(out, int(0.5 * RATE))

## Гул пещеры: очень низкий шум и тихие биения низких тонов.
func drone_loop() -> PackedFloat32Array:
	var r := RandomNumberGenerator.new()
	r.seed = 14
	var len_s := 6.0
	var out := _buf(len_s + 0.5)
	var y := 0.0
	for i in out.size():
		var t := float(i) / RATE
		y += 0.008 * (r.randf_range(-1.0, 1.0) - y)
		out[i] = y * 6.0 + (sin(TAU * 55.0 * t) + sin(TAU * 55.5 * t) * 0.8 + sin(TAU * 82.4 * t) * 0.3) * 0.05
	return loopify(out, int(0.5 * RATE))

## Капля: «плинк» с падающей высотой и тихий отзвук выше.
func drip(k: int) -> PackedFloat32Array:
	var r := RandomNumberGenerator.new()
	r.seed = 200 + k
	var out := _buf(0.3)
	var f := r.randf_range(900.0, 1500.0)
	var ph := 0.0
	for i in out.size():
		var t := float(i) / RATE
		ph += TAU * f * (1.0 + 0.9 * exp(-t * 60.0)) / RATE
		out[i] = (sin(ph) + 0.3 * sin(ph * 2.3)) * exp(-t * 22.0) * minf(1.0, t * 2000.0) * 0.35
	return out

## Сервопривод бура: короткий подъём (выдвигается) или спад (уходит) тона.
func servo(extend: bool) -> PackedFloat32Array:
	var out := _buf(0.28)
	var ph := 0.0
	var n := out.size()
	for i in n:
		var k := float(i) / n
		var f := lerpf(260.0, 520.0, k if extend else 1.0 - k)
		ph += TAU * f / RATE
		var v := sin(ph) + 0.4 * sin(ph * 2.0) + 0.2 * sin(ph * 3.0)
		out[i] = v * 0.18 * sin(PI * k)
	# Щелчок фиксатора в конце.
	for i in int(0.02 * RATE):
		var t := float(i) / RATE
		out[n - int(0.02 * RATE) + i] += sin(TAU * 2400.0 * t) * 0.25 * exp(-t * 300.0)
	return out

## Выстрел кистью: хлопок сжатого газа и удар.
func shot() -> PackedFloat32Array:
	var r := RandomNumberGenerator.new()
	r.seed = 15
	var out := _buf(0.5)
	var y := 0.0
	for i in out.size():
		var t := float(i) / RATE
		y += 0.55 * (r.randf_range(-1.0, 1.0) - y)
		out[i] = y * 0.7 * exp(-t * 14.0) * minf(1.0, t * 3000.0) + sin(TAU * 70.0 * t) * 0.5 * exp(-t * 18.0)
	return out

## Лязг захвата: металлические обертоны.
func clank() -> PackedFloat32Array:
	var out := _buf(0.3)
	for i in out.size():
		var t := float(i) / RATE
		var v := 0.0
		var j := 0
		for p in [620.0, 1710.0, 2950.0, 4100.0]:
			v += sin(TAU * p * t) * exp(-t * (20.0 + 12.0 * j)) / (1.0 + j)
			j += 1
		out[i] = v * 0.3 * minf(1.0, t * 3000.0)
	return out

## Петля без щелчка: хвост длиной xf сводится крест-накрест с началом.
static func loopify(buf: PackedFloat32Array, xf: int) -> PackedFloat32Array:
	var n := buf.size() - xf
	var out := buf.slice(0, n)
	for i in xf:
		var k := float(i) / xf
		out[i] = buf[i] * k + buf[n + i] * (1.0 - k)
	return out

static func to_wav(samples: PackedFloat32Array, loop := false) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = RATE
	s.stereo = false
	s.data = bytes
	if loop:
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_end = samples.size()
	return s
