class_name ProtoWorldVariety
extends RefCounted
## Разброс облика планеты по сиду поверх тегов (ProtoWorldStyle). Теги задают
## характер (вулкан, лёд, жеода), а сид — всё остальное: размах и частоту холмов,
## столовые горы и гребни, изгиб русла, размер озера, форму пещеры и кристаллов
## там, где теги их не задали. Так две планеты с одинаковыми тегами не выглядят
## одним пресетом. Физику (тяжесть, давление) не трогает.

const CAVES := ["dome", "dome", "tube", "fissure", "grotto"]
const HABITS := ["prism", "prism", "needle", "blade", "shard", "cube"]

static func apply(s: ProtoWorldStyle, p: Planet) -> void:
	var r := Rng.new(p.seed_value).fork("look")
	# --- рельеф
	s.relief_amp = minf(s.relief_amp * r.range_f(0.7, 1.4), 15.0)
	s.relief_freq *= r.range_f(0.8, 1.3)
	if s.ridged == 0.0 and r.chance(0.3):
		s.ridged = r.range_f(0.2, 0.55)
	if s.terrace == 0.0 and r.chance(0.2):
		s.terrace = r.range_f(1.6, 3.0)     # столовые горы
	if r.chance(0.3):
		s.spires += r.range_i(2, 6)
	if s.craters == 0 and r.chance(0.25):
		s.craters = r.range_i(1, 3)
	s.lake_r *= r.range_f(0.8, 1.3)
	# Русло: свой изгиб и фаза. У входа в пещеру (x≈40) река не выше z 57 — иначе
	# зальёт вход; озеро (x=16) целиком на карте.
	for i in 12:
		s.river_amp = r.range_f(4.0, 9.0) * (1.0 if r.chance(0.5) else -1.0)
		s.river_freq = r.range_f(0.06, 0.13)
		s.river_phase = r.range_f(0.0, TAU)
		s.river_mid = r.range_f(54.0, 60.0)
		var lz := s.river_z(16.0)
		if s.river_z(40.0) <= 57.0 and lz >= 48.0 and lz + s.lake_r <= 77.0:
			break
		s.river_mid = 58.0; s.river_amp = 7.0; s.river_freq = 0.09; s.river_phase = 0.0
	# --- пещера: форма из тегов остаётся, иначе — по сиду
	if s.cave == "dome":
		s.cave = CAVES[r.range_i(0, CAVES.size() - 1)]
		ProtoWorldStyle._cave_shape(s)
	s.cave_len *= r.range_f(0.9, 1.15)
	s.cave_wid *= r.range_f(0.9, 1.15)
	s.cave_h *= r.range_f(0.9, 1.12)
	# --- кристаллы
	if s.habit == "prism":
		s.habit = HABITS[r.range_i(0, HABITS.size() - 1)]
	s.druzes = maxi(4, s.druzes + r.range_i(-3, 4))
	s.druze_size *= r.range_f(0.85, 1.2)
	if s.crystal_tint.a == 0.0 and r.chance(0.5):
		s.crystal_tint = Color.from_hsv(r.randf(), 0.5, 1.0, r.range_f(0.2, 0.4))
	s.drips = int(s.drips * r.range_f(0.6, 1.5))
	s.fog_mult *= r.range_f(0.8, 1.25)
