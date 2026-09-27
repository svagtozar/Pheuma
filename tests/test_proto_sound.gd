extends GutTest
## Звук 3D-прототипа: синтез без ассетов, петли без щелчков, без перегруза.

var snd: ProtoSound

func before_all():
	snd = ProtoSound.new()
	snd.build_streams()

func after_all():
	snd.free()

func _peak(b: PackedFloat32Array) -> float:
	var m := 0.0
	for v in b:
		m = maxf(m, absf(v))
	return m

func test_one_shots_are_audible_and_not_clipped():
	var bufs := {"shot": snd.shot(), "clank": snd.clank(), "servo": snd.servo(true), "drip": snd.drip(0)}
	for k in 5:
		bufs["step%d" % k] = snd.footstep(k)
	for name in bufs:
		var p := _peak(bufs[name])
		assert_gt(p, 0.05, "%s слышен" % name)
		assert_lt(p, 1.0, "%s без перегруза" % name)

func test_loops_have_no_click_at_seam():
	for name in ["drill_loop", "grind_loop", "reel_loop", "wind_loop", "drone_loop"]:
		var b: PackedFloat32Array = snd.call(name)
		assert_lt(_peak(b), 1.0, "%s без перегруза" % name)
		# Скачок на стыке не больше обычного скачка между соседними отсчётами.
		var seam := absf(b[0] - b[b.size() - 1])
		var typical := 0.0
		for i in range(1, b.size()):
			typical = maxf(typical, absf(b[i] - b[i - 1]))
		assert_lt(seam, typical * 1.01 + 0.001, "%s: стык петли" % name)

func test_streams_built():
	assert_eq(snd.steps.size(), 5)
	assert_eq(snd.drips.size(), 4)
	for k in ["drill", "grind", "reel", "wind", "drone"]:
		assert_eq(snd.streams[k].loop_mode, AudioStreamWAV.LOOP_FORWARD, k)

func test_footstep_variants_differ():
	assert_ne(snd.footstep(0), snd.footstep(1))
