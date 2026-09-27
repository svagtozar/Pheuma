class_name Music
## Процедурная музыка планеты: лад, тоника, темп и мелодия выводятся из seed и тегов
## планеты. Четыре слоя одной длины (петля 8 тактов): pad, bass, arp, tension —
## проигрыватель (game/audio.gd) смешивает их по обстановке. Без узлов: сочинение и
## сведение в буфер — чистые функции.

const BARS := 8
const RATE := 22050

const MODES := {
	"ionian":   [0, 2, 4, 5, 7, 9, 11],
	"dorian":   [0, 2, 3, 5, 7, 9, 10],
	"phrygian": [0, 1, 3, 5, 7, 8, 10],
	"lydian":   [0, 2, 4, 6, 7, 9, 11],
	"aeolian":  [0, 2, 3, 5, 7, 8, 10],
	"maj_pent": [0, 2, 4, 7, 9],
	"min_pent": [0, 3, 5, 7, 10],
	"anomaly":  [0, 2, 4, 6, 7, 10],
}
const MODE_NAMES := {"ionian": "ионийский", "dorian": "дорийский", "phrygian": "фригийский", "lydian": "лидийский",
	"aeolian": "эолийский", "maj_pent": "мажорная пентатоника", "min_pent": "минорная пентатоника", "anomaly": "аномальный"}
const NOTE_NAMES := ["до", "до♯", "ре", "ре♯", "ми", "фа", "фа♯", "соль", "соль♯", "ля", "ля♯", "си"]
const PROGRESSIONS_7 := [[0, 5, 3, 4], [0, 3, 4, 0], [0, 6, 5, 6], [0, 4, 5, 3], [0, 2, 3, 4]]
const PROGRESSIONS_5 := [[0, 3, 4, 0], [0, 2, 3, 1], [0, 4, 3, 2], [0, 1, 3, 2]]
const NOISE := -1          # «нота» шумового удара в слое tension

## Лад по тегам планеты.
static func mode_for(tags: Array, rng: Rng) -> String:
	var has := func(t): return t in tags
	if has.call("anomalous_field") or has.call("singularity") or has.call("temporal_drift") or has.call("inverted_thermodynamics"):
		return "anomaly"
	if has.call("volcanic") or has.call("radiation") or has.call("acid_rain") or has.call("toxic_atmosphere"):
		return "phrygian" if rng.chance(0.5) else "aeolian"
	if has.call("frozen") or has.call("low_gravity"):
		return "lydian" if rng.chance(0.5) else "dorian"
	if has.call("oceanic") or has.call("fungal_biosphere") or has.call("ancient_ruins"):
		return "dorian"
	return "maj_pent" if rng.chance(0.5) else "min_pent"

## Тема планеты: {mode, root, bpm, beat, length, progression, layers: {pad, bass, arp, tension}}.
## Событие слоя — [время, midi, длительность, громкость] (midi = NOISE — шумовой удар).
static func compose(seed_value: int, tags: Array) -> Dictionary:
	var rng := Rng.new(seed_value).fork("music")
	var mode := mode_for(tags, rng)
	var scale: Array = MODES[mode]
	var root := rng.range_i(40, 52)
	var bpm := rng.range_i(56, 76)
	if "storms" in tags or "seismic" in tags:
		bpm += 8
	var beat := 60.0 / bpm
	var bar := beat * 4.0
	var length := bar * BARS
	var progs: Array = PROGRESSIONS_7 if scale.size() == 7 else PROGRESSIONS_5
	var prog: Array = rng.pick(progs)
	var layers := {"pad": [], "bass": [], "arp": [], "tension": []}
	for b in BARS:
		var t0 := b * bar
		var deg: int = prog[b % prog.size()]
		var chord := chord_of(scale, deg)
		for n in chord:
			layers.pad.append([t0, root + 12 + n, bar, 0.22])
		var bass_note: int = root + int(scale[deg % scale.size()]) - (12 if int(scale[deg % scale.size()]) > 6 else 0)
		layers.bass.append([t0, bass_note, beat * 2.0, 0.5])
		layers.bass.append([t0 + beat * 2.0, bass_note + (7 if rng.chance(0.3) else 0), beat * 2.0, 0.42])
		for i in 8:
			var n: int = chord[i % chord.size()] + (12 if i >= 4 else 0)
			layers.arp.append([t0 + i * beat * 0.5, root + 24 + n, beat * 0.5, 0.16])
		for k in 4:
			layers.tension.append([t0 + k * beat, root - 12, beat * 0.9, 0.45])
			if k == 1 or k == 3:
				layers.tension.append([t0 + k * beat, NOISE, beat * 0.25, 0.35])
		layers.tension.append([t0, root + 6, bar, 0.12])   # тритон — гул тревоги
	# Мелодия поверх арпеджио: блуждание по ладу, с паузами.
	var pent: Array = scale if scale.size() <= 6 else [scale[0], scale[1], scale[2], scale[4], scale[5]]
	var idx := rng.range_i(0, pent.size() - 1)
	var octave := 24
	for s in BARS * 4:
		if rng.chance(0.35):
			continue
		idx += rng.pick([-1, -1, 0, 1, 1, 2, -2])
		if idx < 0:
			idx += pent.size()
			octave -= 12
		elif idx >= pent.size():
			idx -= pent.size()
			octave += 12
		octave = clampi(octave, 12, 36)
		layers.arp.append([s * beat, root + octave + int(pent[idx]), beat * (2.0 if rng.chance(0.2) else 1.0), 0.24])
	return {"mode": mode, "root": root, "bpm": bpm, "beat": beat, "length": length, "progression": prog, "layers": layers}

## Трезвучие на ступени лада (через одну ступень).
static func chord_of(scale: Array, deg: int) -> Array:
	var out: Array = []
	for k in 3:
		var i: int = deg + k * 2
		out.append(int(scale[i % scale.size()]) + 12 * int(i / scale.size()))
	return out

static func describe(theme: Dictionary) -> String:
	return "%s, %d уд/мин, тоника %s" % [MODE_NAMES[theme.mode], theme.bpm, NOTE_NAMES[int(theme.root) % 12]]

static func freq(midi: int) -> float:
	return 440.0 * pow(2.0, (midi - 69) / 12.0)

## Звук одной ноты инструмента (с хвостом затухания).
static func note_samples(instrument: String, midi: int, dur: float, rate: int, rng: RandomNumberGenerator) -> PackedFloat32Array:
	var tail: float = {"pad": 1.2, "bass": 0.3, "bell": 0.8, "pulse": 0.15}.get(instrument, 0.3)
	var n := int((dur + tail) * rate)
	var out := PackedFloat32Array()
	out.resize(n)
	if midi == NOISE:
		var y := 0.0
		for i in n:
			var t := float(i) / rate
			y += 0.6 * (rng.randf_range(-1.0, 1.0) - y)
			out[i] = y * exp(-t * 30.0)
		return out
	var f := freq(midi)
	var ph := [0.0, 0.0, 0.0]
	var detune := [1.0, 1.003, 0.997]
	for i in n:
		var t := float(i) / rate
		var v := 0.0
		var env := 1.0
		match instrument:
			"pad":
				var a: float = min(1.0, t / 0.6)
				var r: float = 1.0 if t < dur else max(0.0, 1.0 - (t - dur) / tail)
				env = a * r
				for k in 3:
					ph[k] += TAU * f * detune[k] / rate
					v += sin(ph[k]) / 3.0
			"bass":
				env = min(1.0, t * 200.0) * exp(-t * 2.5) * (1.0 if t < dur else max(0.0, 1.0 - (t - dur) / tail))
				ph[0] += TAU * f / rate
				v = sin(ph[0]) * 0.8 + sin(ph[0] * 2.0) * 0.2
			"bell":
				env = min(1.0, t * 300.0) * exp(-t * 4.0)
				ph[0] += TAU * f / rate
				v = sin(ph[0]) * 0.75 + sin(ph[0] * 2.0) * 0.25
			"pulse":
				env = min(1.0, t * 150.0) * exp(-t * 9.0)
				ph[0] += TAU * f / rate
				v = sin(ph[0])
		out[i] = v * env
	return out

## Свести слой в петлю длиной length_s: хвосты нот заворачиваются в начало,
## пик нормализуется до 0.8.
static func render(events: Array, instrument: String, length_s: float, rate: int = RATE) -> PackedFloat32Array:
	var n := int(length_s * rate)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var cache := {}
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	for e in events:
		var midi: int = int(e[1])
		var inst := "pulse" if midi == NOISE else instrument
		if instrument == "pulse" and midi > 0 and float(e[2]) > 1.0:
			inst = "pad"   # тритон-гул в слое тревоги тянется
		var key := "%s:%d:%.3f" % [inst, midi, float(e[2])]
		if not cache.has(key):
			cache[key] = note_samples(inst, midi, float(e[2]), rate, rng)
		var s: PackedFloat32Array = cache[key]
		var start := int(float(e[0]) * rate)
		var vel: float = float(e[3])
		for i in s.size():
			var j := (start + i) % n
			buf[j] += s[i] * vel
	var peak := 0.0
	for i in n:
		peak = max(peak, abs(buf[i]))
	if peak > 0.0:
		var k := 0.8 / peak
		for i in n:
			buf[i] *= k
	return buf

## Инструмент слоя.
static func instrument_of(layer: String) -> String:
	return {"pad": "pad", "bass": "bass", "arp": "bell", "tension": "pulse"}[layer]
