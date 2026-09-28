extends GutTest
## Состояние поверхности планеты (ProtoSurfaceState): грани кубосферы, кисть,
## рост поросли, таяние льда, сохранение.

const C := Vector3(40.0, -800.0, 40.0)

func _state() -> ProtoSurfaceState:
	var s := ProtoSurfaceState.new(C, 800.0)
	autofree(s)
	return s

func test_faces_match_planet_stream():
	# Те же грани и (u, v), что у сеток шара: иначе пятна съедут с рельефа.
	var ps := ProtoPlanetStream.new()
	autofree(ps)
	for f in 6:
		for uv in [Vector2(0.1, 0.2), Vector2(0.5, 0.5), Vector2(0.93, 0.07)]:
			var d := ProtoSurfaceState.dir_of(f, uv.x, uv.y)
			assert_almost_eq(d.distance_to(ps._dir(f, uv.x, uv.y)), 0.0, 1.0e-5)
			var back := ProtoSurfaceState.face_uv(d)
			assert_eq(int(back.z), f)
			assert_almost_eq(Vector2(back.x, back.y).distance_to(uv), 0.0, 1.0e-4)

func test_paint_is_local_and_soft():
	var s := _state()
	var site := Vector3(40.0, 10.0, 40.0)
	s.paint(site, 30.0, ProtoSurfaceState.VEG, 1.0)
	assert_gt(s.sample(site).r, 0.95, "в середине мазка — полная поросль")
	assert_eq(s.sample(site + Vector3(120.0, 0.0, 0.0)).r, 0.0, "за 120 м — нетронуто")
	# Мазок через шов граней (участок на макушке, край грани ~630 м по дуге).
	var edge := C + ProtoSurfaceState.dir_of(0, 1.0, 0.5) * 800.0
	s.paint(edge, 40.0, ProtoSurfaceState.ICE, 1.0)
	assert_gt(s.sample(edge + Vector3(3.0, 0.0, 0.0)).b, 0.9, "по одну сторону шва")
	assert_gt(s.sample(edge - Vector3(3.0, 0.0, 0.0)).b, 0.9, "и по другую")

func test_vegetation_spreads_and_ice_stops_it():
	var s := _state()
	var site := Vector3(40.0, 10.0, 40.0)
	var ice_at := site + Vector3(0.0, 0.0, -60.0)
	s.paint(ice_at, 25.0, ProtoSurfaceState.ICE, 1.0)
	s.paint(site, 12.0, ProtoSurfaceState.VEG, 1.0)
	var near := site + Vector3(35.0, 0.0, 0.0)
	assert_eq(s.sample(near).r, 0.0)
	s.step_now(60)
	assert_gt(s.sample(near).r, 0.3, "поросль доползла на 35 м")
	assert_lt(s.sample(ice_at).r, 0.05, "на льду не растёт")
	# Лёд растаял — талая вода мочит грунт, поросль заходит.
	s.melt = 20.0
	s.step_now(80)
	assert_lt(s.sample(ice_at).b, 0.05, "лёд растаял")
	assert_gt(s.sample(ice_at).r, 0.3, "и там уже поросль")

func test_quiet_planet_costs_nothing():
	var s := _state()
	s.paint(Vector3(40.0, 10.0, 40.0), 10.0, ProtoSurfaceState.SOIL, 1.0)
	s.step_now(300)
	assert_eq(s._active.size(), 0, "где ничего не меняется, шагов нет")
	assert_lt(s.steps, 300)

func test_save_roundtrip_is_small():
	var s := _state()
	s.paint(Vector3(40.0, 10.0, 40.0), 50.0, ProtoSurfaceState.VEG, 0.7)
	var d := s.save_dict()
	assert_lt(JSON.stringify(d).length(), 20000, "в сохранении — сжато")
	var t := _state()
	t.load_dict(JSON.parse_string(JSON.stringify(d)))
	assert_eq(t.data, s.data)
	assert_eq(t._active.size(), s._active.size())
