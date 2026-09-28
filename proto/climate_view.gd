class_name ProtoClimateView
extends Node
## Как климат планеты (ProtoTerraform) виден в сцене:
##   небо синеет и дымка густеет, когда атмосфера плотнее и пригоднее;
##   жидкости пересобираются, когда материал тает или замерзает (лёд в руслах
##   становится рекой, река — льдом);
##   флора (ProtoFlora) — по пригодности и зелёным зонам куполов.

const LIVE_TOP := Color(0.26, 0.47, 0.82)
const LIVE_HORIZON := Color(0.72, 0.82, 0.92)
const EVERY := 0.5

var game: Node3D                 # сцена прототипа (preview.gd)
var terra: ProtoTerraform
var flora: ProtoFlora
var sky: ProceduralSkyMaterial
var base_top := Color()
var base_horizon := Color()
var base_fog := -1.0
var sky_k := 0.0                 # 0 — небо планеты, 1 — жилое
var liquids_rebuilt := 0
var _t := 0.0
var _liq_key := ""

func setup(g: Node3D, t: ProtoTerraform) -> void:
	game = g
	terra = t
	if g.env != null and g.env.sky != null:
		sky = g.env.sky.sky_material as ProceduralSkyMaterial
	if sky != null:
		base_top = sky.sky_top_color
		base_horizon = sky.sky_horizon_color
	_liq_key = liquid_key(g.planet)
	flora = ProtoFlora.new()
	flora.name = "flora"
	g.add_child(flora)
	flora.occupied = g.flora_occupied
	flora.setup(g.terrain, g.planet, g.flora_blocked)
	refresh()

## Какие материалы сейчас жидкие — ключ для пересборки жидкостей.
static func liquid_key(planet: Planet) -> String:
	var ids: Array = []
	for m in planet.materials:
		ids.append("%s:%d" % [m.id, m.phase_at(planet.ambient_temp)])
	return ",".join(PackedStringArray(ids))

func _process(dt: float) -> void:
	_t -= dt
	if _t > 0.0:
		return
	_t = EVERY
	refresh()

func refresh() -> void:
	var hab := terra.habitability()
	var gain := clampf(hab - terra.base_habitability(), 0.0, 1.0)
	var dp := clampf((terra.pressure() - terra.base_p) / 1.5, 0.0, 1.0)
	sky_k = maxf(gain, dp * 0.5)
	if sky != null:
		sky.sky_top_color = base_top.lerp(LIVE_TOP, sky_k)
		sky.sky_horizon_color = base_horizon.lerp(LIVE_HORIZON, sky_k)
		sky.ground_horizon_color = sky.sky_horizon_color.darkened(0.3)
	# Дымка — как у ProtoSky: плотнее воздух — гуще.
	if game.get("_fog_base") != null and float(game._fog_base) >= 0.0:
		if base_fog < 0.0:
			base_fog = game._fog_base
		game._fog_base = base_fog + 0.0035 * clampf(terra.pressure() - terra.base_p, 0.0, 3.0)
	var key := liquid_key(game.planet)
	if key != _liq_key:
		_liq_key = key
		liquids_rebuilt += 1
		game.refresh_liquids()
	flora.update(hab, terra.seeded(), zones())

## Зелёные зоны куполов в мире: [[центр, радиус]].
func zones() -> Array:
	var out: Array = []
	for c in terra.zones:
		out.append([ProtoPneumatics.cell_pos(game.pneu_origin, c), float(terra.zones[c])])
	return out
