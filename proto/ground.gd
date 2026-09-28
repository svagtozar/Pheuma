class_name ProtoGround
extends RefCounted
## Толща планеты: что лежит в точке — почва, осыпь, пласты пород, мерзлота.
## Не хранится, а вычисляется из сида и глубины под природной поверхностью:
## 0 байт на всю планету (кора вокселями по 1 м на 40 м вглубь — ~320 млн
## ячеек). Хранятся только правки рельефа (ProtoTerrain.edit) и состояние
## верха (ProtoSurfaceState).
## Почва и осыпь — по глубине (повторяют рельеф); пласты пород — по высоте,
## с наклоном и изгибом (на обрывах и в стенах пещер видны полосы); мерзлота —
## линзами под почвой холодных планет; жилы других пород секут пласты
## наискось тонкими листами, конкреции — вкраплениями в своём пласте.
## Цвет толщи — для рельефа (ProtoTerrain._color_h), материал — что даёт бур.

const SOIL := 0
const SUBSOIL := 1
const ICE := 2
const ROCK := 3                # и дальше: пласты по порядку
const VEIN := 4                # вид слоя «жила» / «конкреции» (номер слоя — после пластов)

## Слой: {"name", "sub" (Substance или null), "color", "kind"}.
var layers: Array = []
var soil_d := 0.6              # толщина почвы, м
var sub_d := 2.8               # подошва осыпи, м
var ice_on := false            # мерзлота
var band_h: PackedFloat32Array = []   # толщины пластов, м (по кругу)
var band_sum := 1.0
var dip := Vector2(0.08, -0.05)       # наклон пластов (м по высоте на м вбок)
var warp := FastNoiseLite.new()
var grain := FastNoiseLite.new()
var lens := FastNoiseLite.new()
## Жилы: {"layer", "noise", "w"} — лист там, где |шум| < w (тонкие изогнутые
## стенки через все пласты). Конкреции: {"layer", "noise", "band", "thr"} —
## округлые включения только в пласте band.
var veins: Array = []
var nodules: Array = []

static func for_planet(planet: Planet, ground: Color, cliff: Color, lush := false) -> ProtoGround:
	var g := ProtoGround.new()
	var r := Rng.new(planet.seed_value).fork("strata")
	g.warp.seed = planet.seed_value
	g.warp.frequency = 0.018
	g.grain.seed = planet.seed_value + 7
	g.grain.frequency = 0.9
	g.lens.seed = planet.seed_value + 13
	g.lens.frequency = 0.06
	g.soil_d = r.range_f(0.35, 0.8) * (1.4 if lush else 1.0)
	g.sub_d = g.soil_d + r.range_f(1.6, 3.2)
	g.dip = Vector2(r.range_f(-0.12, 0.12), r.range_f(-0.12, 0.12))
	g.ice_on = planet.has_tag("frozen") or planet.ambient_temp < -20.0
	var soil_c := ground.darkened(0.28).lerp(Color(0.24, 0.18, 0.12), 0.45) if lush else ground.darkened(0.08)
	g.layers.append({"name": "почва" if lush else "реголит", "sub": null, "color": soil_c, "kind": SOIL})
	g.layers.append({"name": "осыпь", "sub": null, "color": ground.lerp(cliff, 0.5).lightened(0.1), "kind": SUBSOIL})
	g.layers.append({"name": "лёд", "sub": null, "color": Color(0.78, 0.86, 0.92), "kind": ICE})
	# Пласты — из твёрдых материалов планеты; цвет — к общей гамме обрыва.
	var mats: Array = ProtoSky.solid_mats(planet).slice(0, 3)
	if mats.is_empty():
		mats = [null]
	var idx: Array = []
	for i in r.range_i(3, 5):
		idx.append(i % mats.size())
	for i in idx:
		var s = mats[i]
		var c: Color = cliff if s == null else cliff.lerp(s.color, 0.55)
		c = c * r.range_f(0.8, 1.15)
		c.a = 1.0
		g.layers.append({"name": s.name if s != null else "порода", "sub": s, "color": c, "kind": ROCK})
		g.band_h.append(r.range_f(2.0, 6.0))
	g.band_sum = 0.0
	for b in g.band_h:
		g.band_sum += b
	# Жилы и конкреции — из других твёрдых материалов (если их нет — из тех же).
	var all_solids: Array = ProtoSky.solid_mats(planet)
	var other: Array = all_solids.slice(3) if all_solids.size() > 3 else all_solids.duplicate()
	if other.is_empty():
		other = [null]
	for i in r.range_i(1, 2):
		var s = other[i % other.size()]
		var n := FastNoiseLite.new()
		n.seed = planet.seed_value + 101 + i * 17
		n.frequency = r.range_f(0.025, 0.045)
		n.fractal_type = FastNoiseLite.FRACTAL_NONE     # гладкий лист, а не крошка
		n.domain_warp_fractal_type = FastNoiseLite.DOMAIN_WARP_FRACTAL_NONE
		n.domain_warp_enabled = true
		n.domain_warp_amplitude = 12.0
		n.domain_warp_frequency = 0.02
		var vc: Color = Color(0.8, 0.8, 0.75) if s == null else cliff.lerp(s.color, 0.85).lightened(0.08)
		vc.a = 1.0
		g.veins.append({"layer": g.layers.size(), "noise": n, "w": r.range_f(0.02, 0.035)})
		g.layers.append({"name": (s.name if s != null else "кварц") + " (жила)", "sub": s, "color": vc, "kind": VEIN})
	var ns = other[other.size() - 1]
	var cn := FastNoiseLite.new()
	cn.seed = planet.seed_value + 303
	cn.noise_type = FastNoiseLite.TYPE_CELLULAR
	cn.cellular_return_type = FastNoiseLite.RETURN_DISTANCE
	cn.frequency = 0.35
	cn.fractal_type = FastNoiseLite.FRACTAL_NONE
	var nc: Color = Color(0.5, 0.45, 0.4) if ns == null else cliff.lerp(ns.color, 0.8).darkened(0.05)
	nc.a = 1.0
	g.nodules.append({"layer": g.layers.size(), "noise": cn, "band": r.range_i(0, g.band_h.size() - 1),
		"thr": r.range_f(-0.8, -0.72)})
	g.layers.append({"name": (ns.name if ns != null else "кремень") + " (конкреции)", "sub": ns, "color": nc, "kind": VEIN})
	return g

## Жила или конкреция в точке (номер слоя) или −1. band — пласт точки.
func _vein(p: Vector3, band: int) -> int:
	for v: Dictionary in veins:
		if absf(v.noise.get_noise_3dv(p)) < v.w:
			return v.layer
	for c: Dictionary in nodules:
		if band == c.band and c.noise.get_noise_3dv(p) < c.thr:
			return c.layer
	return -1

## Номер слоя в точке p (система участка), under — глубина под природной
## поверхностью (surface_h − y).
func layer_at(p: Vector3, under: float) -> int:
	var k := _upper(p, under)
	if k >= 0:
		return k
	var b := _band(_band_y(p))
	var v := _vein(p, b)
	return v if v >= 0 else ROCK + b

## Почва, мерзлота или осыпь; −1 — ниже, в пластах.
func _upper(p: Vector3, under: float) -> int:
	if under < soil_d:
		return SOIL
	if ice_on and under < sub_d + 4.0 and lens.get_noise_3dv(p) > 0.25:
		return ICE
	if under < sub_d + warp.get_noise_2d(p.x * 3.0, p.z * 3.0) * 0.6:
		return SUBSOIL
	return -1

## Высота в «системе пластов»: наклон и изгиб.
func _band_y(p: Vector3) -> float:
	return p.y + dip.x * p.x + dip.y * p.z + warp.get_noise_3dv(p) * 4.0

func _band(y: float) -> int:
	var t := fposmod(y, band_sum)
	for i in band_h.size():
		t -= band_h[i]
		if t < 0.0:
			return i
	return band_h.size() - 1

## Цвет толщи в точке: слой, мелкое зерно, у границы пластов — тонкая тёмная прослойка.
func color_at(p: Vector3, under: float) -> Color:
	var k := _upper(p, under)
	var gr := grain.get_noise_3dv(p)
	var c: Color
	if k < 0:
		var y := _band_y(p)
		var b := _band(y)
		var v := _vein(p, b)
		if v >= 0:
			c = layers[v].color * (0.9 + 0.2 * gr)
			c.a = 1.0
			return c
		c = layers[ROCK + b].color
		var t := fposmod(y, band_sum)
		var acc := 0.0
		var dmin := 99.0
		for bh in band_h:
			acc += bh
			dmin = minf(dmin, absf(t - acc))
		dmin = minf(dmin, t)
		c = c * (0.93 + 0.1 * gr) * (0.78 + 0.22 * smoothstep(0.0, 0.35, dmin))
	elif k == SUBSOIL:
		c = layers[k].color * (0.85 + 0.3 * absf(gr))       # галька
	else:
		c = layers[k].color * (0.95 + 0.08 * gr)
	c.a = 1.0
	return c

## Что даёт бур или лопата в точке: {"name", "sub", "kind"}.
func dig_yield(p: Vector3, under: float) -> Dictionary:
	var l: Dictionary = layers[layer_at(p, under)]
	return {"name": l.name, "sub": l.sub, "kind": int(l.kind)}

func summary() -> String:
	var names: Array = []
	for i in range(ROCK, layers.size()):
		if layers[i].kind == ROCK and not names.has(layers[i].name):
			names.append(layers[i].name)
	var extra: Array = []
	for i in range(ROCK, layers.size()):
		if layers[i].kind == VEIN:
			extra.append(layers[i].name)
	return "толща: %s %.1f м, осыпь до %.1f м%s; пласты: %s" % [layers[SOIL].name, soil_d, sub_d,
		", мерзлота" if ice_on else "", ", ".join(PackedStringArray(names))] + "; в них: " + ", ".join(PackedStringArray(extra))
