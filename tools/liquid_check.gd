extends SceneTree
## Проверка жидкостей 3D-прототипа: не висит ли гладь в воздухе. Для каждой
## сетки жидкости берёт свободные края (ребро одного треугольника) и смотрит, что
## снаружи: берег должен быть не ниже глади. Если снаружи рельеф ниже глади больше
## чем на LIMIT — край «висит»: видно тонкий лист жидкости над обрывом.
##   godot --headless --path . -s tools/liquid_check.gd -- --seeds=1-40 [--dig] [--flow=150]
## Код выхода — число сеток с висящими краями.

const LIMIT := 0.35

var seeds: Array = []
var dig := false
var flow := 0.0
var bad := 0
var verbose := false

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seeds="):
			var r := a.substr(8).split("-")
			for s in range(int(r[0]), int(r[-1]) + 1):
				seeds.append(s)
		elif a == "--dig": dig = true
		elif a == "-v": verbose = true
		elif a.begins_with("--flow="): flow = float(a.substr(7))
	if seeds.is_empty():
		seeds = [1, 7, 8, 14, 32]
	_run.call_deferred()

func _run() -> void:
	for s in seeds:
		await _check(s)
	print("Висящих сеток: %d" % bad)
	quit(bad)

func _check(s: int) -> void:
	var game: Node = load("res://proto/preview.tscn").instantiate()
	game.seed_value = s
	game.flow_time = flow
	game.planet_on = true
	root.add_child(game)
	await process_frame
	await process_frame
	var t: ProtoTerrain = game.terrain
	if dig and game.liquid_life != null and game.liquid_life.lake != null:
		_dig_at_shore(game)
	var root_l: Node = game.get_node_or_null("liquids")
	if root_l == null and game.planet_stream != null:
		root_l = game.planet_stream.get_node_or_null("liquids")
	var out := []
	if root_l != null:
		for c in root_l.get_children():
			if c is MeshInstance3D and c.mesh != null and c.mesh.get_surface_count() > 0:
				if verbose:
					print("  ", c.name)
				var r := _site_edges(t, c.mesh, game.liquid_zones)
				out.append("%s: краёв %d, висят %d (до %.1f м)" % [c.name, r[0], r[1], r[2]])
				if r[1] > 0:
					bad += 1
	var pf = game.planet_fill
	if pf != null and pf.sea_mi != null:
		var r := _sea_edges(t, pf.sea_mi.mesh)
		out.append("море: краёв %d, висят %d (до %.1f м)" % [r[0], r[1], r[2]])
		if r[1] > 0:
			bad += 1
	print("seed %d: %s" % [s, "; ".join(out)])
	game.queue_free()
	await process_frame

## Свободные рёбра глади: [a, b, третья вершина треугольника]. Ребро, к которому
## примыкает завеса (водопад с края вниз), не свободно; рёбра самих завес (UV2.x = 1,
## и крутые, и изогнутые у кромки) не проверяем.
func _free_edges(m: Mesh) -> Array:
	var cnt := {}
	var info := {}
	for si in m.get_surface_count():
		var arr := m.surface_get_arrays(si)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var uv2 = arr[Mesh.ARRAY_TEX_UV2]
		var idx = arr[Mesh.ARRAY_INDEX]
		var n: int = idx.size() if idx != null and idx.size() > 0 else v.size()
		for i in range(0, n, 3):
			var ids := [i, i + 1, i + 2]
			if idx != null and idx.size() > 0:
				ids = [idx[i], idx[i + 1], idx[i + 2]]
			var tri := [v[ids[0]], v[ids[1]], v[ids[2]]]
			var flat := absf((tri[1] - tri[0]).cross(tri[2] - tri[0]).normalized().y) >= 0.5
			if uv2 != null and uv2.size() == v.size() and (uv2[ids[0]].x > 0.5 or uv2[ids[1]].x > 0.5 or uv2[ids[2]].x > 0.5):
				flat = false
			for k in 3:
				var a: Vector3 = tri[k]
				var b: Vector3 = tri[(k + 1) % 3]
				var key := _key(a, b)
				cnt[key] = cnt.get(key, 0) + 1
				if flat:
					info[key] = [a, b, tri[(k + 2) % 3]]
	var res := []
	for key in info:
		if cnt[key] == 1:
			res.append(info[key])
	return res

func _key(a: Vector3, b: Vector3) -> String:
	var ka := "%d,%d,%d" % [roundi(a.x * 100), roundi(a.y * 100), roundi(a.z * 100)]
	var kb := "%d,%d,%d" % [roundi(b.x * 100), roundi(b.y * 100), roundi(b.z * 100)]
	return ka + "|" + kb if ka < kb else kb + "|" + ka

## Участок: снаружи ребра (0,4 м наружу) у уровня глади должна быть порода.
func _site_edges(t: ProtoTerrain, m: Mesh, zones: Array) -> Array:
	var n := 0
	var hang := 0
	var worst := 0.0
	for e in _free_edges(m):
		var a: Vector3 = e[0]
		var b: Vector3 = e[1]
		var mid := (a + b) * 0.5
		var dir: Vector3 = mid - e[2]
		dir.y = 0.0
		var along := (b - a)
		along.y = 0.0
		var nrm := Vector3(-along.z, 0, along.x).normalized()
		if nrm.dot(dir) < 0.0:
			nrm = -nrm
		var p := mid + nrm * 0.4
		n += 1
		if p.x < 0.5 or p.z < 0.5 or p.x > t.sx - 0.5 or p.z > t.sz - 0.5:
			continue
		if t.solid(p.x, mid.y - 0.05, p.z) or _other_liquid(zones, p, mid.y):
			continue
		var fl := t.floor_at(Vector3(p.x, mid.y, p.z))
		var gap := mid.y - fl
		if gap > LIMIT:
			hang += 1
			worst = maxf(worst, gap)
			if verbose:
				print("   висит: (%.1f, %.1f, %.1f) на %.1f м, пол %.1f, рельеф %.1f; ребро %s–%s" % [p.x, mid.y, p.z, gap, fl, t.surface_h(p.x, p.z), a, b])
	return [n, hang, worst]

## Снаружи ребра другая жидкость почти на той же высоте (река входит в озеро).
func _other_liquid(zones: Array, p: Vector3, y: float) -> bool:
	for zn in zones:
		if zn.has("sea"):
			continue
		if zn.area.call(p.x, p.z) and float(zn.level.call(p.x, p.z)) > y - LIMIT:
			return true
	return false

## Море на шаре: снаружи ребра дно (sphere_h) должно быть выше уровня.
func _sea_edges(t: ProtoTerrain, m: Mesh) -> Array:
	var n := 0
	var hang := 0
	var worst := 0.0
	for e in _free_edges(m):
		var a: Vector3 = e[0]
		var b: Vector3 = e[1]
		var mid := (a + b) * 0.5
		var dir: Vector3 = (mid - e[2]).normalized()
		var d: Vector3 = (mid + dir * 2.0 - t.center).normalized()
		n += 1
		var gap := t.sea_level - t.sphere_h(d)
		if gap > LIMIT:
			hang += 1
			worst = maxf(worst, gap)
			if verbose:
				print("   море висит: дуга %.0f м, на %.1f м" % [t.arc_from_site(d), gap])
	return [n, hang, worst]

func _dig_at_shore(_game: Node) -> void:
	pass
