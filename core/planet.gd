class_name Planet
extends RefCounted
## Сгенерированная планета: теги, среда, материалы, карта, цель.

enum Tile { GROUND, ROCK, CHASM, LAVA, ICE, ACID, RUIN }
const TILE_NAMES := ["грунт", "скала", "расщелина", "лава", "тонкий лёд", "кислотное озеро", "руины"]

var seed_value := 0
var name := ""
var tags: Array = []
var ambient_temp := 15.0
var atm_pressure := 1.0
var gravity := 1.0
var atmosphere: Substance
var materials: Array = []          # исходные материалы планеты
var db := SubstanceDB.new()
var width := 80
var height := 60
var tiles := PackedByteArray()
var deposits := {}                 # Vector2i → {"sub": id, "amount": кг}
var spawn := Vector2i.ZERO
var goal := {}                     # экземпляр шаблона из Goals
var forced := false                # теги заданы вручную (учебная планета)
var unbuildable: Array = []        # машины цели, для которых генератор не нашёл материала

func has_tag(t: String) -> bool:
	return t in tags

func oxidizing() -> bool:
	return has_tag("oxidizing_atmosphere") or atmosphere.has("oxidizer")

func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < width and c.y < height

func tile(c: Vector2i) -> int:
	if not in_bounds(c):
		return Tile.ROCK
	return tiles[c.y * width + c.x]

func set_tile(c: Vector2i, t: int) -> void:
	if in_bounds(c):
		tiles[c.y * width + c.x] = t

func buildable(c: Vector2i) -> bool:
	var t := tile(c)
	return t == Tile.GROUND or t == Tile.RUIN

func walkable(c: Vector2i) -> bool:
	var t := tile(c)
	return t == Tile.GROUND or t == Tile.RUIN or t == Tile.ICE

func has_anomaly() -> bool:
	for t in tags:
		if PlanetTags.TAGS[t].get("anomaly", false):
			return true
	return false

func material_tags_present() -> Array:
	var d := {}
	for m in materials:
		for t in m.tags:
			d[t] = true
	return d.keys()
