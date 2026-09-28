class_name ProtoSwimDemo
extends Node
## --auto=swim --screenshot=путь.png — жидкости крупно, кадры путь_1..4.png:
##   1 — вброд по реке (течение сносит, круги по воде);
##   2 — прыжок в озеро (всплеск);
##   3 — в озере: на дне под водой или на плаву — как решит плотность;
##   4 — камера под поверхностью смотрит вверх (плавучий робот сначала ныряет).
## Итог в консоль: плотности, погружение, снос течением.

var pl: ProtoPlayer
var robot: Node3D
var terrain: ProtoTerrain
var health: ProtoHealth
var prefix := ""
var t := 0.0
var step := 0
var _mark := -1.0
var _river_x0 := 0.0

func setup(p: ProtoPlayer, h: ProtoHealth, out: String) -> void:
	pl = p
	robot = p.robot
	terrain = p.terrain
	health = h
	prefix = out

func _ready() -> void:
	# Берег реки ниже по течению от завода: робот входит поперёк русла.
	var x := terrain.lake_c.x + terrain.lake_r + 14.0
	var rz := terrain.river_z(x)
	var st := Vector3(x, 0, rz - 6.5)
	st.y = terrain.surface_h(st.x, st.z)
	robot.position = st
	robot.rotation.y = 0.0
	pl.route = [st, Vector3(x, 0, rz)]
	pl.route_i = 1
	_river_x0 = x
	_cam(PI * 0.5 + 0.35, 0.32, 5.5)

func _wet() -> float:
	var f = pl.get("wet_f")
	return float(f) if f != null else health.depth / 1.85

func _cam(yaw: float, pitch: float, dist: float) -> void:
	pl.cam_yaw = yaw
	pl.cam_pitch = pitch
	pl.cam_dist = dist

func _process(dt: float) -> void:
	t += dt
	var shot := ""
	match step:
		0:
			# Дошёл до середины русла — постоять в потоке.
			if pl.route_i >= pl.route.size():
				_mark = _mark if _mark >= 0.0 else t
				if t - _mark > 2.5:
					shot = "река"
					print("Река: снесло течением на %.2f м по x за %.1f с" % [robot.position.x - _river_x0, t - _mark])
					_to_lake()
			elif t > 25.0:
				shot = "река"
				_to_lake()
		1:
			if _wet() > 0.05:
				_mark = _mark if _mark >= 0.0 else t
				if t - _mark > 0.3:
					shot = "всплеск"
			elif t - _mark > 8.0 and _mark >= 0.0:
				shot = "всплеск"
		2:
			if t - _mark > 5.0:
				var lc := Vector3(terrain.lake_c.x, 0, terrain.lake_c.y)
				_cam(atan2(robot.position.x - lc.x, robot.position.z - lc.z) + 0.6, 0.12, 4.2)
				if t - _mark > 6.0:
					shot = "в озере"
		3:
			# Плавучий — нырнуть, чтобы камера ушла под поверхность.
			if "swim_hold" in pl:
				pl.swim_hold = -1.0 if bool(pl.get("swim")) else 0.0
			pl.cam_pitch = move_toward(pl.cam_pitch, -0.45, dt * 0.6)
			pl.cam_dist = 3.4
			if t - _mark > 2.4:
				shot = "снизу"
	if shot != "":
		step += 1
		_mark = t if step >= 2 else -1.0
		var path := "%s_%d.png" % [prefix, step]
		get_viewport().get_texture().get_image().save_png(path)
		var buoy = pl.get("buoy")
		print("кадр жидкости (%s): %s — погружение %.2f, выталкивание/вес %s, робот y=%.2f" % [
			shot, path, _wet(), ("%.2f" % buoy) if buoy != null else "—", robot.position.y])
		if step >= 4:
			get_tree().quit(0)
	if t > 60.0:
		print("Жидкости: время вышло на шаге ", step)
		get_tree().quit(1)

## Прыжок в озеро с разбега над серединой.
func _to_lake() -> void:
	var lc := Vector3(terrain.lake_c.x, 0, terrain.lake_c.y)
	var pc := terrain.plateau()
	var dir := Vector3(pc.x - lc.x, 0, pc.z - lc.z).normalized()
	var at := lc + dir * terrain.lake_r * 0.2
	robot.position = Vector3(at.x, terrain.lake_level + 2.2, at.z)
	robot.rotation.y = atan2(-dir.x, -dir.z)
	pl.route = []
	pl.vel = Vector3.ZERO
	pl.air = true
	pl.vy = 1.0
	_mark = -1.0
	_cam(robot.rotation.y + 0.5, 0.3, 6.5)
