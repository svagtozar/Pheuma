extends SceneTree
## Замер симуляции: среднее время World.tick(0.1) на заводах разного размера.
##   godot --headless --path . -s tools/bench.gd

func _init() -> void:
	for n in [13, 60, 150]:
		var w := World.create(5)
		w.director.enabled = false
		DemoFactory.build(w, w.planet.spawn + Vector2i(-14, -10), n)
		for i in 50:
			w.tick(0.1)
		var t0 := Time.get_ticks_usec()
		for i in 600:
			w.tick(0.1)
		var us := Time.get_ticks_usec() - t0
		print("TICK машин=%d: %.3f мс на тик" % [w.machines.size(), us / 600.0 / 1000.0])
	quit()
