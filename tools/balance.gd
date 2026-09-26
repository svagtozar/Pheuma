extends SceneTree
## Прогон бота баланса по многим планетам.
##   godot --headless --path . -s tools/balance.gd -- --seeds=40 --start=1
## Отчёт пишется в build/balance_report.md.

func _init() -> void:
	var n := 40
	var start := 1
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seeds="): n = int(a.substr(8))
		if a.begins_with("--start="): start = int(a.substr(8))
	var rows: Array = []
	var t0 := Time.get_ticks_msec()
	for s in range(start, start + n):
		var w := World.create(s)
		var bot := BalanceBot.new(w)
		bot.play()
		rows.append({"seed": s, "w": w, "bot": bot})
		var last: Dictionary = bot.stages[-1] if not bot.stages.is_empty() else {}
		print("seed %d %-24s %s  %s" % [s, w.planet.goal.n, "ГОТОВО" if w.goals.completed else "стоп на этапе %d" % (bot.stages.size()), last.get("why", "")])
	var path := "res://build/balance_report.md"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://build"))
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(report(rows, (Time.get_ticks_msec() - t0) / 1000.0))
	print("Отчёт: ", ProjectSettings.globalize_path(path))
	quit(0)

func report(rows: Array, secs: float) -> String:
	var s := "# Отчёт бота баланса\n\nПланет: %d, время прогона %.0f с. Лимит на этап: %.0f мин симуляции.\n\n" % [rows.size(), secs, BalanceBot.STAGE_LIMIT / 60.0]
	# Сводка по целям и этапам.
	var by_goal := {}
	var fails := {}
	for r in rows:
		var g: String = r.w.planet.goal.n
		if not by_goal.has(g):
			by_goal[g] = {"n": 0, "done": 0, "stage_ok": [0, 0, 0], "stage_t": [0.0, 0.0, 0.0]}
		var d: Dictionary = by_goal[g]
		d.n += 1
		if r.w.goals.completed:
			d.done += 1
		for i in r.bot.stages.size():
			var st: Dictionary = r.bot.stages[i]
			if st.ok:
				d.stage_ok[i] += 1
				d.stage_t[i] += st.time
			elif st.why != "":
				var key: String = st.why.split(":")[0].split("(")[0].strip_edges()
				fails[key] = fails.get(key, 0) + 1
	s += "## Цели\n\n| Цель | Планет | Пройдено | Этап 1 | Этап 2 | Этап 3 |\n|---|---|---|---|---|---|\n"
	for g in by_goal:
		var d: Dictionary = by_goal[g]
		var cells: Array = []
		for i in 3:
			cells.append("%d/%d, ~%.1f мин" % [d.stage_ok[i], d.n, d.stage_t[i] / max(1, d.stage_ok[i]) / 60.0] if d.stage_ok[i] > 0 else "0/%d" % d.n)
		s += "| %s | %d | %d | %s |\n" % [g, d.n, d.done, " | ".join(cells)]
	s += "\n## Причины остановок\n\n"
	var keys: Array = fails.keys()
	keys.sort_custom(func(a, b): return fails[a] > fails[b])
	for k in keys:
		s += "- %s — %d\n" % [k, fails[k]]
	# Статика планет.
	var soft := 0.0
	var solid := 0.0
	var total := 0.0
	for r in rows:
		var w: World = r.w
		for m in w.planet.materials:
			total += 1
			if m.hardness <= w.starter.hardness + 0.5: soft += 1
			if m.phase_at(w.planet.ambient_temp) == Substance.Phase.SOLID: solid += 1
	s += "\n## Материалы\n\n- копаются стартовым буром: %d%%\n- твёрдые при температуре среды: %d%%\n" % [int(100 * soft / max(1, total)), int(100 * solid / max(1, total))]
	s += "\n## По планетам\n\n"
	for r in rows:
		var w: World = r.w
		s += "### seed %d — %s, %s\n" % [r.seed, w.planet.goal.n, ", ".join(w.planet.tags.map(func(t): return PlanetTags.display(t)))]
		for st in r.bot.stages:
			s += "- %s: %s\n" % [st.desc, "%.1f мин" % (st.time / 60.0) if st.ok else "НЕТ — " + st.why]
		s += "<details><summary>журнал бота</summary>\n\n" + "\n".join(r.bot.notes.slice(0, 60).map(func(x): return "    " + x)) + "\n</details>\n\n"
	return s
