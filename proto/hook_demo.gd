class_name ProtoHookDemo
extends Node
## --auto=hook --screenshot=путь.png — кисть-крюк: робот у подножия уступа
## стреляет кистью в его кромку, трос втягивает его наверх. Кадры путь_1..4.png:
## прицел, кисть летит, робот на тросе, робот наверху. Итог (подъём) в консоль.

var pl: ProtoPlayer
var robot: Node3D
var terrain: ProtoTerrain
var prefix := ""
var t := 0.0
var step := 0
var y0 := 0.0
var lip := Vector3.ZERO
var top_y := 0.0

func setup(p: ProtoPlayer, out: String) -> void:
	pl = p
	robot = p.robot
	terrain = p.terrain
	prefix = out

func _ready() -> void:
	var c := find_cliff(terrain, terrain.plateau())
	if c.is_empty():
		print("Крюк: уступа рядом нет")
		get_tree().quit(1)
		return
	var st: Vector3 = c.foot
	robot.position = st
	var f: Vector3 = c.dir
	robot.rotation.y = atan2(f.x, f.z)
	lip = c.lip
	top_y = c.top
	y0 = st.y
	# Камера сзади-сбоку, чуть снизу — видно и робота, и кромку.
	pl.cam_yaw = robot.rotation.y + 0.9
	pl.cam_pitch = 0.05
	pl.cam_dist = 6.5

## Уступ 2–4.5 м рядом с p: подножие (ровно, над ним небо), направление к стене,
## кромка (куда стрелять) и высота верха.
static func find_cliff(tr: ProtoTerrain, p: Vector3) -> Dictionary:
	var best := {}
	var best_cost := INF
	for r: float in [8.0, 11.0, 14.0, 17.0, 20.0, 24.0]:
		for k in 32:
			var a := TAU * k / 32.0
			var q := p + Vector3(sin(a), 0, cos(a)) * r
			var h := tr.surface_h(q.x, q.z)
			for m in 8:
				var b := TAU * m / 8.0
				var f := Vector3(sin(b), 0, cos(b))
				var near := tr.surface_h(q.x + f.x * 1.2, q.z + f.z * 1.2)
				var up := tr.surface_h(q.x + f.x * 3.0, q.z + f.z * 3.0)
				var rise := up - h
				if rise < 2.0 or rise > 4.5 or near - h > 0.8:
					continue
				if tr.solid(q.x, h + 1.5, q.z) or tr.solid(q.x + f.x * 3.0, up + 1.5, q.z + f.z * 3.0):
					continue
				var cost := absf(rise - 3.2) + r * 0.05 + absf(tr.surface_h(q.x - f.x, q.z - f.z) - h)
				if cost < best_cost:
					# Кромка — первая порода по лучу от груди к верху стены.
					var from := Vector3(q.x, h + 1.5, q.z)
					var to := Vector3(q.x + f.x * 3.0, up + 0.25, q.z + f.z * 3.0)
					var hit := Vector3.INF
					for i in 60:
						var s := from.lerp(to, i / 59.0)
						if tr.solid(s.x, s.y, s.z):
							hit = s - (to - from).normalized() * 0.1
							break
					if hit == Vector3.INF:
						continue
					best_cost = cost
					best = {"foot": Vector3(q.x, h, q.z), "dir": f, "lip": hit, "top": up}
	return best

func _process(dt: float) -> void:
	t += dt
	var shot := ""
	match step:
		0:
			if t > 1.2:
				shot = "прицел"
				pl.hook_to(lip)
		1:
			if pl.fist.state == "fly" and pl.fist.st_t > 0.15:
				shot = "кисть летит"
		2:
			if pl.fist.state == "pull" and robot.position.y > y0 + 0.5:
				shot = "на тросе"
		3:
			if not pl.air and pl.fist.state != "pull" and robot.position.y > y0 + 1.5 and t > 1.0:
				shot = "наверху"
	if shot != "":
		step += 1
		var path := "%s_%d.png" % [prefix, step]
		get_viewport().get_texture().get_image().save_png(path)
		print("кадр крюка (%s): %s" % [shot, path])
		if step >= 4:
			print("Крюк: подъём %.2f м (уступ %.2f м) за %.1f с" % [robot.position.y - y0, top_y - y0, t])
			get_tree().quit(0)
	if t > 14.0:
		print("Крюк: время вышло, подъём %.2f м из %.2f, кисть %s" % [robot.position.y - y0, top_y - y0, pl.fist.state])
		get_tree().quit(1)
