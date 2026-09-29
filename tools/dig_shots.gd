extends SceneTree
## Кадры бура и кисти в игре (настоящие действия WORK и FILL): робот у склона,
## перекрестье на стене, бур вгрызается, потом кисть насыпает грунт обратно.
##   xvfb-run -a godot --path . --rendering-driver opengl3 --resolution 1280x800 --fixed-fps 30 \
##     -s tools/dig_shots.gd -- --seed=14 --shots=папка [--gif]
## Время — в кадрах по 1/30 с (--fixed-fps 30): медленная машина снимает то же.
## --gif — ещё кадры каждые 0.1 с (папка/gif_NNN.png) для анимации.

var shots := ""
var gif := false
var game: Node
var pl: Node
var n := 0
var g := 0

func _initialize() -> void:
	var sd := 14
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="): shots = a.substr(8)
		elif a.begins_with("--seed="): sd = int(a.substr(7))
		elif a == "--gif": gif = true
	var dir := "user://dig_shots"
	DirAccess.make_dir_recursive_absolute(dir)
	ProtoSave.DIR = dir + "/saves3d"
	ProtoSettings.PATH = dir + "/settings3d.cfg"
	ProtoTutorial.SETTINGS = dir + "/settings.json"
	DirAccess.make_dir_recursive_absolute(shots)
	create_timer(240, true).timeout.connect(func(): quit(99))
	var sc: Node = load("res://proto/preview.tscn").instantiate()
	sc.set("seed_value", sd)
	sc.set("play", true)
	sc.set("fresh", true)
	game = sc
	root.add_child(sc)
	_run.call_deferred()

func frames(k: int) -> void:
	for i in k:
		await process_frame

func shot(name: String) -> void:
	await frames(2)
	n += 1
	var p := "%s/%d_%s.png" % [shots, n, name]
	root.get_texture().get_image().save_png(p)
	print("кадр ", p)

## Держать действие t секунд; с --gif — кадр каждые 0.1 с.
func hold(action: StringName, t: float) -> void:
	Input.action_press(action)
	for i in int(t * 30.0):
		await process_frame
		if OS.has_environment("DIG_DEBUG") and i % 15 == 0:
			var dg = game.get("digger")
			var an = pl.get("robot").get_node_or_null("anim")
			print("  %s work %.2f out %.2f dug %s soil %.2f '%s' aim %s robot %s bite %s r %.2f" % [action, an.work, an.drill_out, dg.dug, dg.soil, dg.status, pl.get("aim_hit"), pl.get("robot").global_position, dg.get("_bite_c"), dg.get("_bite_r")])
		if gif and i % 3 == 0:
			g += 1
			root.get_texture().get_image().save_png("%s/gif_%03d.png" % [shots, g])
	Input.action_release(action)

func _run() -> void:
	await frames(30)
	var ui = game.get("run_ui")
	if ui != null and ui.get("modal") != "":
		ui.close()
	pl = game.get_node("player")
	var t: ProtoTerrain = game.get("terrain")
	var robot: Node3D = pl.get("robot")
	# Место: склон рядом с площадкой — в 2.5 м впереди земля выше на 1.5–3 м.
	var pc := t.plateau()
	var best := Vector3.INF
	var face := Vector3.FORWARD
	var best_rise := 0.6
	var fl = game.get("flora")
	var plants: Array = []
	if fl != null and fl.node != null:
		for it in fl.items:
			plants.append(fl.node.to_global(it.p))
	for x in range(12, t.sx - 12, 2):
		for z in range(12, t.sz - 12, 2):
			var p := Vector3(x, 0, z)
			if Vector2(x - pc.x, z - pc.z).length() < 9.0:
				continue
			var h0 := t.floor_at(Vector3(p.x, 60, p.z))
			if int(game.call("flora_blocked", p.x, p.z, h0)) == 1 or not t.can_edit(Vector3(p.x, h0, p.z)):
				continue
			var clear := true
			for q in plants:
				if Vector2(q.x - p.x, q.z - p.z).length() < 5.0:
					clear = false
					break
			if not clear:
				continue
			for k in 16:
				var dd := Vector3(sin(TAU * k / 16.0), 0, cos(TAU * k / 16.0))
				var q := p + dd * 2.2
				var h1 := t.floor_at(Vector3(q.x, 60, q.z))
				var hb := t.floor_at(Vector3(p.x - dd.x * 1.5, 60, p.z - dd.z * 1.5))
				var hb2 := t.floor_at(Vector3(p.x - dd.x * 4.0, 60, p.z - dd.z * 4.0))
				var side := Vector3(-dd.z, 0, dd.x)
				var hl := t.floor_at(Vector3(p.x + side.x * 2.5 - dd.x, 60, p.z + side.z * 2.5 - dd.z))
				var hr := t.floor_at(Vector3(p.x - side.x * 2.5 - dd.x, 60, p.z - side.z * 2.5 - dd.z))
				var rise := h1 - h0
				# Сзади и по бокам открыто — камере есть где встать.
				if rise > best_rise and rise < 3.0 and absf(hb - h0) < 0.8 and hb2 < h0 + 0.6 \
						and hl < h0 + 0.8 and hr < h0 + 0.8:
					best_rise = rise
					best = Vector3(p.x, h0, p.z)
					face = dd
	if best == Vector3.INF:
		print("склон не найден")
		quit(1)
		return
	print("склон: ", best, " подъём ", best_rise)
	robot.global_position = best
	robot.rotation.y = atan2(face.x, face.z)
	pl.set("cam_yaw", robot.rotation.y)
	pl.set("cam_pitch", 0.06)
	pl.set("cam_dist", 3.6)
	pl.set("vel", Vector3.ZERO)
	await frames(40)
	await shot("aim")
	await hold(ProtoControls.WORK, 0.9)
	Input.action_press(ProtoControls.WORK)
	await shot("drilling")
	Input.action_release(ProtoControls.WORK)
	await hold(ProtoControls.WORK, 3.2)
	await frames(20)
	await shot("tunnel")
	# Кисть: взгляд на пол тоннеля — засыпать его обратно.
	pl.set("cam_pitch", 0.3)
	await frames(20)
	if InputMap.has_action(&"tool_fill"):
		await hold(&"tool_fill", 0.8)
		Input.action_press(&"tool_fill")
		await shot("brush")
		Input.action_release(&"tool_fill")
		await hold(&"tool_fill", 3.0)
	await frames(20)
	await shot("mound")
	var dg = game.get("digger")
	if dg != null:
		print("бур: лунок %s, насыпей %s, грунта %s" % [dg.dug, dg.filled, dg.soil])
	quit(0)
