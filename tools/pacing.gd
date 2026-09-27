extends SceneTree
## Бот темпа 3D-цикла: честно проходит планету — бурит друзы в пещере, носит груз
## к приёмнику, строит насосы и баки, берёт награды и прокачку — и замеряет,
## сколько уходит на каждый этап и на что (дорога, бур, ожидание завода, стройка,
## починка). Ходьбу не играет: робот переносится к цели, а время дороги
## (путь через вход в пещеру, бегом) проживается на месте — мир в это время идёт.
##   godot --headless --fixed-fps 30 --path . -s tools/pacing.gd -- --seed=N \
##     --run --mute --auto=pace [--limit=40] [--out=файл.json]
## Одна планета за запуск (сцена читает --seed сама); строка JSON — в --out.
## Несколько планет подряд и сводная таблица: tools/pacing.sh 1 7 8 12 …
##   (сводка: godot --headless --path . -s tools/pacing.gd -- --summary=папка).

const FPS := 30.0
const CARRY := 12.0          # кг: с таким грузом бот идёт к заводу
const PATH_K := 1.3          # дорога длиннее прямой

var game: Node
var run: ProtoRun
var limit := 40.0 * 60.0     # с симуляции на планету
var out_path := ""
var t := 0.0                 # время симуляции, с
var doing := "start"
var spent := {}              # занятие → с (за этап)
var stage_log: Array = []
var stage_start := 0.0
var stage_i := -1
var bad := {}                # кристаллы, к которым не подойти
var dmg := 0.0
var wrecks := 0
var min_hp := 1e9
var heal_trips := 0
var skills: Array = []       # [время, id]
var knowledge_log: Array = []
var events: Array = []
var notes: Array = []
var unloaded := 0.0
var built_parts: Array = []
var _hp_last := -1.0
var _was_wrecked := false
var _ev_seen := ""
var crystal_stats := {}
var rebuilt: Array = []       # [мин, деталь] — разбитое событием или давлением
var crystal_log: Array = []   # [кг, с бурения] по каждому кристаллу

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--summary="):
			print(summary(a.substr(10)))
			quit(0)
			return
		if a.begins_with("--limit="): limit = float(a.substr(8)) * 60.0
		elif a.begins_with("--out="): out_path = a.substr(6)
	var dir := "user://pacing"
	DirAccess.make_dir_recursive_absolute(dir)
	ProtoSave.DIR = dir + "/saves3d"
	ProtoSettings.PATH = dir + "/settings3d.cfg"
	ProtoTutorial.SETTINGS = dir + "/settings.json"
	ProtoControls.save_path = dir + "/controls.cfg"
	create_timer(3600, true).timeout.connect(func():
		print("Бот встал")
		_stage_done()
		_finish("watchdog"))
	_play.call_deferred()

func _play() -> void:
	RobotDesigns.tool_r = "drill"          # как в игре: бур в предплечье
	game = load("res://proto/preview.tscn").instantiate()
	root.add_child(game)
	await frames(3)
	run = game.run
	game.run_ui.pause_game = false
	game.health.active = true
	game.health.input_enabled = false
	run.briefing_seen = true
	var ms: Array = []
	for c in game.mining.crystals():
		ms.append(ProtoMining.mass_of(c, game.mining.sub_of(c)))
	ms.sort()
	crystal_stats = {"n": ms.size(), "p10": snappedf(ms[ms.size() / 10], 0.1), "median": snappedf(ms[ms.size() / 2], 0.1),
		"p90": snappedf(ms[ms.size() * 9 / 10], 0.1), "max": snappedf(ms[-1], 0.1), "total": snappedf(_crystal_kg(), 1.0)}
	print("Кристаллы, кг: ", crystal_stats)
	print("Планета %d: %s — %s, g %.2f, walk %.2f, druses %d, crystals %d, кг в друзах %.0f" % [
		game.seed_value, game.planet.name, run.orig_goal.get("n", ""), game.planet.gravity,
		game.terrain.style.walk_mult(), game.mining.druses.size(), game.mining.crystals().size(), _crystal_kg()])
	while t < limit and not run.goals.completed:
		await _step()
	_stage_done()
	_finish("done" if run.goals.completed else "limit")

# ---------------------------------------------------------------- время

func frames(n: int) -> void:
	for i in n:
		await process_frame
		t += 1.0 / FPS
		spent[doing] = spent.get(doing, 0.0) + 1.0 / FPS
		_watch()

func sim(sec: float, what: String) -> void:
	var prev := doing
	doing = what
	await frames(maxi(1, int(sec * FPS)))
	doing = prev

## Каждый кадр: награды, выбор пути, прокачка, урон, события, смена этапа.
func _watch() -> void:
	if run == null:
		return
	var h: ProtoHealth = game.health
	if _hp_last >= 0.0 and h.hp < _hp_last:
		dmg += _hp_last - h.hp
	_hp_last = h.hp
	min_hp = minf(min_hp, h.hp)
	var wr := h.is_wrecked()
	if wr and not _was_wrecked:
		wrecks += 1
		notes.append("%s поломка (%s)" % [_ts(), h.kind])
	_was_wrecked = wr
	if not run.goals.reward_pending.is_empty():
		var pick := _best_card(run.goals.reward_pending)
		notes.append("%s награда: %s" % [_ts(), pick])
		run.take_reward(pick)
	if run.goals.choice_pending():
		var alt: Array = run.goals.raw_stage(run.goals.stage).alt
		var k := _easier(alt)
		run.goals.choices[str(run.goals.stage)] = k
		notes.append("%s путь этапа %d: %s (из %s / %s)" % [_ts(), run.goals.stage + 1, alt[k].desc, alt[0].desc, alt[1].desc])
	for id in ["g1", "f1", "h1", "k1", "s1", "c1", "g2", "h2", "f2", "k2", "g3", "k3", "k4", "g4", "h3", "f3", "f4"]:
		if Progression.can_learn(run.robot, id) == "":
			run.learn(id)
			skills.append([snappedf(t / 60.0, 0.1), id])
	if game.run_ui.modal != "":
		game.run_ui.close()
	if run.goals.stage != stage_i:
		if stage_i >= 0:
			_stage_done()
		stage_i = run.goals.stage
		stage_start = t
		spent = {}
	var e: String = run.ev.get("id", "")
	if e != _ev_seen:
		_ev_seen = e
		if e != "":
			events.append([snappedf(t / 60.0, 0.1), e])

func _stage_done() -> void:
	var st := run.goals.current() if not run.goals.completed else {}
	var rec := {"i": stage_i, "min": snappedf((t - stage_start) / 60.0, 0.01), "spent": {}}
	for k in spent:
		rec.spent[k] = snappedf(spent[k], 0.1)
	if stage_i >= 0 and stage_i < run.planet.goal.stages.size():
		var raw: Dictionary = run.goals.raw_stage(stage_i)
		var cur: Dictionary = raw.alt[int(run.goals.choices.get(str(stage_i), 0))] if raw.has("alt") else raw
		rec.desc = cur.get("desc", "")
		rec.type = cur.get("type", "")
	rec.done = stage_i < run.goals.stage or run.goals.completed
	if not rec.done:
		rec.progress = run.stage_numbers()
	stage_log.append(rec)
	print("  этап %d: %s — %.1f мин %s %s" % [stage_i + 1, rec.get("desc", "?"), rec.min, "" if rec.done else "НЕ ДОДЕЛАН", rec.spent])

func _ts() -> String:
	return "%.1f" % (t / 60.0)

## Награда: припасы и прокачка полезнее всего боту; иначе — первая.
func _best_card(list: Array) -> String:
	for want in ["supply", "knowledge", "repair"]:
		if want in list:
			return want
	return list[0]

## Путь этапа: тот, что по прикидке быстрее (стройка и бур — быстрее завода).
func _easier(alt: Array) -> int:
	var rank := {"p_parts": 0, "p_mine": 1, "p_process": 2, "deliveries": 3, "p_store": 4, "p_pressure": 5}
	return 0 if rank.get(alt[0].type, 9) <= rank.get(alt[1].type, 9) else 1

# ---------------------------------------------------------------- решение

func _step() -> void:
	var h: ProtoHealth = game.health
	if h.is_wrecked():
		await sim(1.0, "wreck")
		return
	if h.hp < h.max_hp * 0.4 and not _near_factory():
		heal_trips += 1
		await go(_factory_stand(), "heal_walk")
		while h.hp < h.max_hp * 0.95 and not h.is_wrecked():
			await sim(1.0, "heal")
		return
	await _dodge()
	var broken: Array = game.pneu.burst_log.filter(func(b): return not game.pneu.parts.has(b[1]))
	if not broken.is_empty():
		await rebuild(broken[0])
		return
	var st := run.goals.current()
	if OS.has_environment("PACE_DEBUG"): print("step ", _ts(), " ", st.get("type", ""), " cargo ", run.cargo_mass(), " p ", run.net_pressure())
	match st.get("type", ""):
		"p_mine":
			await drill_trip(CARRY)
			if run.cargo_mass() >= CARRY:
				await unload()
		"p_parts":
			await build_one()
		"p_pressure":
			if run.net_pressure() < float(st.p) and _pumps() < 8:
				await build_pump()
			else:
				await _feed_or_wait()
		_:
			await _feed_or_wait()

## Этапы завода: сырьё есть — ждём и докладываем; баки полны — ставим бак;
## давления нет — насос.
func _feed_or_wait() -> void:
	if not run.full_tanks().is_empty():
		await build_part("tank")
		return
	if run.net_pressure() - game.planet.atm_pressure < ProtoPneumatics.MOVE_P * 2.0 and _pumps() < 6:
		await build_pump()
		return
	if _intake_kg() < 4.0:
		if run.cargo_mass() > 1.0:
			await unload()
		else:
			await drill_trip(CARRY)
			await unload()
		return
	await sim(3.0, "wait_factory")

func _pumps() -> int:
	var n := 0
	for c in game.pneu.parts:
		if game.pneu.parts[c].kind == "pump":
			n += 1
	return n

func _intake_kg() -> float:
	var net: ProtoPneumatics = game.pneu
	var s := 0.0
	for c in net.parts:
		if net.parts[c].kind == "intake":
			s += net.mass_in(c)
	return s

## Уйти из круга метеоритов, пока не началось.
func _dodge() -> void:
	if run.ev.is_empty() or not run.ev.id in ["meteors", "ring_debris"]:
		return
	if not run.in_zone(game.robot.global_position):
		return
	var c: Vector3 = run.ev.center
	var p: Vector3 = game.robot.global_position
	var away := Vector3(p.x - c.x, 0, p.z - c.z)
	if away.length() < 0.1:
		away = Vector3(1, 0, 0)
	var to: Vector3 = c + away.normalized() * (float(run.ev.radius) + 1.5)
	to.y = game.terrain.floor_at(to + Vector3(0, 1.5, 0))
	await go(to, "dodge")

# ---------------------------------------------------------------- дорога

func speed() -> float:
	return RobotAnim.WALK_SPEED * game.terrain.style.walk_mult() * ProtoPlayer.SPRINT_MULT

func in_cave(p: Vector3) -> bool:
	return game.terrain.surface_h(p.x, p.z) - p.y > 1.5

func path_len(a: Vector3, b: Vector3) -> float:
	var tr: ProtoTerrain = game.terrain
	if in_cave(a) != in_cave(b):
		var e := tr.cave_entry
		e.y = tr.surface_h(e.x, e.z)
		return _leg(a, e) + _leg(e, b)
	return _leg(a, b)

func _leg(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length() * PATH_K + absf(a.y - b.y)

func go(to: Vector3, what := "walk") -> void:
	var r: Node3D = game.robot
	var d := path_len(r.global_position, to)
	var pl = game.get_node("player")
	r.global_position = to
	pl.vel = Vector3.ZERO
	pl.vy = 0.0
	await sim(d / speed(), what)

func _near_factory() -> bool:
	var f: Vector3 = game.health.factory_at
	var p: Vector3 = game.robot.global_position
	return Vector2(p.x - f.x, p.z - f.z).length() < ProtoHealth.FACTORY_R - 1.0

func _factory_stand() -> Vector3:
	var c: Vector3 = game.health.factory_at + Vector3(0, 0, 4.0)
	c.y = game.terrain.floor_at(c + Vector3(0, 3.0, 0))
	return c

func _intake_cell() -> Vector2i:
	return Vector2i(-3, 0) if game.pneu.parts.has(Vector2i(-3, 0)) else game.pneu.parts.keys()[0]

func _intake_stand() -> Vector3:
	var c := ProtoPneumatics.cell_pos(game.pneu_view.origin, _intake_cell()) + Vector3(-1.6, 0, 0)
	c.y = game.terrain.floor_at(c + Vector3(0, 2.0, 0))
	return c

# ---------------------------------------------------------------- бур

func _crystal_kg() -> float:
	var s := 0.0
	for c in game.mining.crystals():
		s += ProtoMining.mass_of(c, game.mining.sub_of(c))
	return s

## Сходить в пещеру и набурить want кг (или сколько выйдет).
func drill_trip(want: float) -> void:
	var m: ProtoMining = game.mining
	var tries := 0
	while run.cargo_mass() < want and tries < 40:
		tries += 1
		var c := _nearest_crystal()
		if c == null:
			notes.append("%s кристаллы кончились" % _ts())
			await sim(5.0, "no_crystals")
			return
		var spot := _stand_for(c)
		if spot.is_empty():
			bad[c] = true
			continue
		await go(spot[0], "walk")
		var r: Node3D = game.robot
		var to: Vector3 = c.global_position - r.global_position
		r.rotation.y = atan2(to.x, to.z) - 0.25
		var before := run.cargo_mass()
		if OS.has_environment("PACE_DEBUG"):
			await frames(2)
			var hh: ProtoHealth = game.health
			print("  у кристалла ", c.global_position, " стою ", r.global_position, " пещера ", in_cave(r.global_position), " dps ", hh.dps, " ", hh.kind, " глубина ", hh.depth, " жидкость ", hh.liquid.name if hh.liquid else "-", " цель ", m.target, " ", m.status)
		var prev := doing
		doing = "drill"
		Input.action_press(ProtoControls.WORK)
		var k := 0
		while k < int(20.0 * FPS):
			await frames(1)
			k += 1
			if not is_instance_valid(c) or c.has_meta("broken"):
				break
			if k == int(2.5 * FPS) and OS.has_environment("PACE_DEBUG"):
				var an = game.get_node("player").anim
				print("   2.5с: цель ", m.target, " прогресс ", m.progress, " work ", an.work, " out ", an.drill_out, " drilling ", m.drilling, " '", m.status, "' ui_busy ", game.robot.get_meta("ui_busy", false))
			if k == int(2.5 * FPS) and (m.target == null or m.status != ""):
				break
			if game.health.is_wrecked():
				break
		Input.action_release(ProtoControls.WORK)
		if OS.has_environment("PACE_DEBUG"):
			print("   выход k=", k, " valid ", is_instance_valid(c), " broken ", is_instance_valid(c) and c.has_meta("broken"), " wreck ", game.health.is_wrecked(), " груз ", run.cargo_mass(), " mined_total ", m.mined_total, " falling ", m.falling.size())
		# Куски долетают до робота.
		var w := 0
		while not m.falling.is_empty() and w < int(4.0 * FPS):
			await frames(1)
			w += 1
		doing = prev
		if is_instance_valid(c) and c.has_meta("broken"):
			crystal_log.append([snappedf(run.cargo_mass() - before, 0.1), snappedf(k / FPS, 0.1)])
		if is_instance_valid(c) and not c.has_meta("broken"):
			bad[c] = true
			if m.status != "":
				notes.append("%s %s" % [_ts(), m.status])
		if game.health.is_wrecked():
			return
		if run.cargo_mass() <= before and tries > 30:
			return

func _nearest_crystal() -> MeshInstance3D:
	var p: Vector3 = game.robot.global_position
	var best: MeshInstance3D = null
	var bd := INF
	for c in game.mining.crystals():
		if bad.has(c):
			continue
		if game.mining.drill_hard + 0.5 < game.mining.sub_of(c).hardness:
			continue
		var d := path_len(p, c.global_position)
		if d < bd:
			bd = d
			best = c
	return best

## Стоянка, с которой бур достаёт кристалл: [точка] или [].
func _stand_for(c: MeshInstance3D) -> Array:
	var tr: ProtoTerrain = game.terrain
	var ax := ProtoMining.axis(c)
	var q: Vector3 = (ax[0] + ax[1]) * 0.5
	var best := []
	var bd := INF
	for rad in [0.55, 0.75, 0.95]:
		for i in 12:
			var a := TAU * i / 12.0
			var sp: Vector3 = q + Vector3(cos(a), 0, sin(a)) * rad
			sp.y = tr.floor_at(sp + Vector3(0, 1.2, 0))
			if tr.solid(sp.x, sp.y + 1.2, sp.z) or tr.solid(sp.x, sp.y + 0.5, sp.z):
				continue
			if not game.health.liquid_at(sp).is_empty():
				continue
			var sh: Vector3 = sp + Vector3(0, 1.4, 0)
			var d := ProtoMining.reach_dist(c, sh)
			if d < ProtoMining.REACH - 0.15 and d < bd:
				bd = d
				best = [sp]
	return best

func unload() -> void:
	await go(_intake_stand(), "walk")
	var net: ProtoPneumatics = game.pneu
	var cg := run.cargo()
	var m := 0.0
	for p in cg:
		m += p.mass
		net.feed(_intake_cell(), p)
	cg.clear()
	unloaded += m
	await sim(1.0, "unload")

# ---------------------------------------------------------------- стройка

func build_one() -> void:
	# Полезная стройка: сначала насосы (давление), потом трубы.
	if _pumps() < 4:
		await build_pump()
	else:
		await build_part("pipe")

func build_pump() -> void:
	await build_part("pump")

## Поставить деталь рядом с сетью: свободная клетка, соседняя с трубой/насосом.
func build_part(kind: String) -> void:
	var net: ProtoPneumatics = game.pneu
	# Материал — как у стройки по умолчанию: тот, из которого стоит завод.
	var sub: Substance = game.factory_mat if game.get("factory_mat") != null else World.starter_substance()
	var cell := Vector2i(9999, 0)
	var dir := 3
	var keys: Array = net.parts.keys()
	keys.sort()
	if kind == "tank":
		# Бак — на выход полного: полный бак пропускает груз дальше.
		for c in keys:
			var tk: Dictionary = net.parts[c]
			var front: Vector2i = c + ProtoPneumatics.DIRS[tk.dir]
			if tk.kind == "tank" and c in run.full_tanks() and net.can_place(front):
				cell = front
				dir = tk.dir
				break
		if cell.x == 9999:
			await sim(3.0, "wait_factory")
			return
	for c in keys:
		if not net.parts[c].kind in ["pipe", "pump", "tank"]:
			continue
		for d in ProtoPneumatics.DIRS:
			var n: Vector2i = c + d
			if net.can_place(n) and absi(n.x) < 5 and n.y >= -2 and n.y <= 6:
				cell = n
				break
		if cell.x != 9999:
			break
	if cell.x == 9999:
		notes.append("%s негде поставить %s" % [_ts(), kind])
		await sim(3.0, "stuck_build")
		return
	var at := ProtoPneumatics.cell_pos(game.pneu_view.origin, cell) + Vector3(0, 0, -2.2)
	at.y = game.terrain.floor_at(at + Vector3(0, 2.0, 0))
	await go(at, "walk")
	await sim(3.0, "build")        # выбрать деталь, материал, повернуть, поставить
	net.place(kind, cell, dir, sub)
	built_parts.append([snappedf(t / 60.0, 0.1), kind, sub.name, snappedf(ComponentStats.compute(ProtoPneumatics.KINDS[kind].stat, sub).max_p, 0.1)])

## Поставить разбитую деталь на место (подсказка рана говорит об этом игроку).
func rebuild(b: Array) -> void:
	var net: ProtoPneumatics = game.pneu
	var cell: Vector2i = b[1]
	var at := ProtoPneumatics.cell_pos(game.pneu_view.origin, cell) + Vector3(0, 0, -2.2)
	at.y = game.terrain.floor_at(at + Vector3(0, 2.0, 0))
	await go(at, "walk")
	await sim(3.0, "build")
	if net.can_place(cell):
		net.place(b[0], cell, b[2], b[3])
		rebuilt.append([snappedf(t / 60.0, 0.1), b[0]])
	net.burst_log.erase(b)

# ---------------------------------------------------------------- итог

func _finish(why: String) -> void:
	var p: Planet = game.planet
	var d := {"seed": game.seed_value, "planet": p.name, "goal": run.orig_goal.get("n", ""),
		"tags": p.tags, "gravity": p.gravity, "atm": p.atm_pressure, "temp": p.ambient_temp,
		"walk": snappedf(game.terrain.style.walk_mult(), 0.01), "result": why,
		"total_min": snappedf(t / 60.0, 0.1), "stages": stage_log, "mined": snappedf(run.mined, 0.1),
		"unloaded": snappedf(unloaded, 0.1), "crystals_left_kg": snappedf(_crystal_kg(), 0.1),
		"hits": run.stats.hits, "processed": run.processed, "built": run.built,
		"damage": snappedf(dmg, 0.1), "max_hp": game.health.max_hp, "min_hp": snappedf(min_hp, 0.1),
		"wrecks": wrecks, "heal_trips": heal_trips, "hull": game.health.hull.name if game.health.hull else "",
		"drill_hard": game.mining.drill_hard, "crystal_hard": game.mining.base_sub.hardness if game.mining.base_sub else 0.0,
		"knowledge": run.robot.knowledge, "tags_known": run.robot.known_tags.size(), "xp": run.robot.xp,
		"skills": skills, "events": events, "parts": built_parts, "pressure_cap": run._pressure_cap(),
		"notes": notes.slice(0, 40), "crystal_stats": crystal_stats, "rebuilt": rebuilt, "factory": _factory_dump(), "crystal_log": crystal_log}
	print("ИТОГ ", JSON.stringify(d))
	if out_path != "":
		var f := FileAccess.open(out_path, FileAccess.WRITE)
		f.store_string(JSON.stringify(d))
	quit(0)

func _factory_dump() -> Array:
	var net: ProtoPneumatics = game.pneu
	var out: Array = []
	var keys: Array = net.parts.keys()
	keys.sort()
	for c in keys:
		var p: Dictionary = net.parts[c]
		out.append("%s %s %s p=%.1f/%.1f %s kg=%.1f" % [str(c), p.kind, p.sub.name, net.pressure(c), p.stats.max_p, str(p.status).replace("\n", " "), net.mass_in(c)])
	return out

# ---------------------------------------------------------------- сводка

## Таблица по JSON-файлам папки: планета, итог, минуты по этапам, куда ушло время.
static func summary(dir: String) -> String:
	var rows: Array = []
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".json"):
			var d = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join(f)))
			if typeof(d) == TYPE_DICTIONARY:
				rows.append(d)
	rows.sort_custom(func(a, b): return a.seed < b.seed)
	var s := "| Сид | Цель | g | Итог | Этапы, мин | Всего, мин | Дорога | Бур | Ждал завод | Урон / HP | Поломок | Знаний |\n|---|---|---|---|---|---|---|---|---|---|---|---|\n"
	var total := {}
	for d in rows:
		var st: Array = []
		for x in d.stages:
			st.append(("%.1f" % x.min) + ("" if x.done else "✗"))
			for k in x.spent:
				total[k] = total.get(k, 0.0) + float(x.spent[k])
		var sp := {}
		for x in d.stages:
			for k in x.spent:
				sp[k] = sp.get(k, 0.0) + float(x.spent[k])
		var all := maxf(1.0, float(d.total_min) * 60.0)
		s += "| %d | %s | %.1f | %s | %s | %.1f | %d%% | %d%% | %d%% | %d / %d | %d | %d |\n" % [d.seed, d.goal, d.gravity,
			"✓" if d.result == "done" else "стоп", " · ".join(st), d.total_min,
			int(100.0 * (sp.get("walk", 0.0) + sp.get("heal_walk", 0.0)) / all), int(100.0 * sp.get("drill", 0.0) / all),
			int(100.0 * sp.get("wait_factory", 0.0) / all), int(d.damage), int(d.max_hp), int(d.wrecks), int(d.knowledge)]
	return s
