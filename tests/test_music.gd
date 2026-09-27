extends GutTest
## Процедурная музыка: тема планеты из seed и тегов, сведение слоёв в петлю.

func test_compose_is_deterministic():
	var a := Music.compose(12, ["frozen", "storms"])
	var b := Music.compose(12, ["frozen", "storms"])
	assert_eq(JSON.stringify(a), JSON.stringify(b))

func test_mood_follows_planet_tags():
	assert_true(Music.compose(3, ["volcanic"]).mode in ["phrygian", "aeolian"])
	assert_true(Music.compose(3, ["frozen"]).mode in ["lydian", "dorian"])
	assert_eq(Music.compose(3, ["singularity"]).mode, "anomaly")
	assert_eq(Music.compose(3, ["oceanic"]).mode, "dorian")
	var seen := {}
	for s in range(1, 20):
		var t := Music.compose(s, [])
		seen["%s/%d/%d" % [t.mode, t.root, t.bpm]] = true
	assert_gt(seen.size(), 10, "у разных планет разные темы")

func test_notes_in_mode_and_loop_length():
	for s in range(1, 10):
		var t := Music.compose(s, ["volcanic"] if s % 2 == 0 else [])
		var scale: Array = Music.MODES[t.mode]
		assert_almost_eq(float(t.length), float(t.beat) * 4.0 * Music.BARS, 0.001)
		for layer in ["pad", "bass", "arp"]:
			for e in t.layers[layer]:
				var pc := posmod(int(e[1]) - int(t.root), 12)
				assert_true(pc in scale or posmod(pc - 7, 12) in scale, "seed %d: %s — нота %d вне лада" % [s, layer, e[1]])
				assert_lt(float(e[0]), float(t.length) + 0.001)

func test_render_loop():
	var t := Music.compose(5, [])
	var t0 := Time.get_ticks_msec()
	var buf := Music.render(t.layers.arp, "bell", t.length, 11025)
	var ms := Time.get_ticks_msec() - t0
	assert_eq(buf.size(), int(t.length * 11025))
	var peak := 0.0
	var energy := 0.0
	for v in buf:
		peak = max(peak, abs(v))
		energy += v * v
	assert_lte(peak, 0.8001)
	assert_gt(energy, 1.0, "не тишина")
	assert_lt(abs(buf[buf.size() - 1] - buf[0]), 0.3, "стык петли без скачка")
	assert_lt(ms, 3000, "сведение слоя быстрое: %d мс" % ms)

func test_all_layers_render():
	var t := Music.compose(7, ["storms"])
	for layer in ["pad", "bass", "arp", "tension"]:
		var buf := Music.render(t.layers[layer], Music.instrument_of(layer), t.length, 8000)
		assert_eq(buf.size(), int(t.length * 8000), layer)
	assert_true(Music.describe(t).contains("уд/мин"))
