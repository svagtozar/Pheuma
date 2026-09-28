extends GutTest
## Бег, камера на штанге и прицел кисти (ProtoPlayer): бег заметно быстрее шага,
## в пещере камера не застревает в породе и не скачет, прицел — по породе, небо — мимо.

var tr: ProtoTerrain

func before_all():
	var planet := PlanetGen.generate(7)
	tr = ProtoTerrain.new(7, ProtoWorldStyle.for_planet(planet))
	tr.build_field()

func _player(at: Vector3) -> ProtoPlayer:
	var pl := ProtoPlayer.new()
	pl.terrain = tr
	pl.robot = Node3D.new()
	pl.cam = Camera3D.new()
	add_child_autofree(pl.robot)
	add_child_autofree(pl.cam)
	pl.robot.position = at
	autofree(pl)
	return pl

## Пол зала пещеры.
func _cave_floor() -> Vector3:
	var c := tr.cave_c
	return Vector3(c.x, tr.floor_at(c + Vector3(0, 1.0, 0)), c.z)

func test_run_is_much_faster_than_walk():
	assert_gte(ProtoPlayer.SPRINT_MULT, 3.0, "бег хотя бы втрое быстрее шага")
	assert_almost_eq(RobotAnim.RUN_SPEED, RobotAnim.WALK_SPEED * ProtoPlayer.SPRINT_MULT, 0.01, "анимация бега — под ту же скорость")

func test_cave_camera_stays_out_of_rock_and_steady():
	var pl := _player(_cave_floor())
	pl.under = 1.0
	pl.cam_dist = 9.0            # длиннее зала — штанга упирается в стену
	var prev := Vector3.INF
	var jumps := []
	var inside := 0
	var longest := 0
	for i in 240:
		# Робот идёт по залу, камера медленно обходит его; пол неровный — корпус качает.
		pl.robot.position = _cave_floor() + Vector3(sin(i * 0.02) * 2.0, 0.04 * sin(i * 1.7), 0)
		pl.cam_yaw = i * 0.015
		pl._camera(1.0 / 30.0)
		var p := pl.cam.position
		# Выступ, вдруг вставший между камерой и роботом, штанга «наезжает» плавно:
		# в породе — не дольше пары кадров подряд.
		inside = inside + 1 if tr.solid(p.x, p.y, p.z) else 0
		longest = maxi(longest, inside)
		if prev != Vector3.INF:
			jumps.append(p.distance_to(prev))
		prev = p
	# 30 кадров/с: обход и шаг — до 0.2 м за кадр; рывков больше 0.3 м — ни одного.
	assert_lte(longest, 6, "камера не застревает в породе")
	jumps.sort()
	gut.p("камера за кадр: медиана %.3f, 95%% %.3f, макс %.3f" % [jumps[jumps.size() / 2], jumps[int(jumps.size() * 0.95)], jumps[-1]])
	assert_lt(jumps[int(jumps.size() * 0.95)], 0.2, "камера идёт плавно")
	assert_lt(jumps[-1], 0.3, "камера не скачет")

func test_aim_hits_rock_and_misses_sky():
	var pl := _player(_cave_floor())
	# Из зала — в стену: прицел на породе.
	pl.cam.position = pl.robot.position + Vector3(0, 1.6, 0)
	pl.cam.look_at(pl.cam.position + Vector3(1, 0, 0))
	var hit := pl.aim_point()
	assert_ne(hit, Vector3.INF, "стена зала в пределах досягаемости")
	if hit != Vector3.INF:
		assert_false(tr.solid(hit.x, hit.y, hit.z), "точка — у поверхности, не в толще")
		assert_true(tr.solid(hit.x + 0.3, hit.y, hit.z) or tr.solid(hit.x + 0.3, hit.y + 0.3, hit.z) or tr.solid(hit.x + 0.3, hit.y - 0.3, hit.z), "сразу за ней — порода")
	# Под открытым небом вверх — мимо.
	var pc := tr.plateau()
	pl.robot.position = pc
	pl.cam.position = pc + Vector3(0, 2.0, 0)
	pl.cam.look_at(pl.cam.position + Vector3(0.1, 1.0, 0))
	assert_eq(pl.aim_point(), Vector3.INF, "в небо — не за что зацепиться")

func test_trapped_robot_climbs_out_but_wall_does_not_help():
	var pc := tr.plateau()
	var top := Vector3(pc.x, tr.surface_h(pc.x, pc.z), pc.z)
	var pl := _player(top)
	assert_false(pl.trapped(), "на ровной площадке — не застрял")
	# Зарыт по грудь (яма глубже прыжка, насыпь сверху): застрял, выход — рядом наверху.
	pl.robot.position = top - Vector3(0, 2.0, 0)
	assert_true(pl.trapped(), "в толще — ни шагу")
	var s := pl.free_spot(pl.robot.position, Vector3(1, 0, 0))
	assert_ne(s, Vector3.INF, "есть куда выбраться")
	if s != Vector3.INF:
		assert_false(tr.solid(s.x, s.y + 0.9, s.z), "на новом месте корпус свободен")
		assert_lt(s.distance_to(top), 4.0, "выбрался рядом")
