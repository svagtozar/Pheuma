class_name Substance
extends RefCounted
## Материал. (Файл не называется material.gd: в Godot уже есть класс Material.)
## Физика целиком выводится из тегов плюс личного шума материала, поэтому
## производный материал (с другими тегами) остаётся «родственником» исходного.

enum Phase { SOLID, LIQUID, GAS }
const PHASE_NAMES := ["твёрдое", "жидкость", "газ"]

var id: String
var root: String          # корневое имя семейства
var name: String
var tags: Array = []
var noise := {"melt": 0.0, "boil": 0.0, "dens": 0.0, "hard": 0.0}
var melt := 0.0
var boil := 0.0
var density := 1.0
var hardness := 1.0
var color := Color.WHITE

func _init(p_id: String = "", p_root: String = "", p_tags: Array = [], p_noise: Dictionary = {}) -> void:
	id = p_id
	root = p_root
	name = p_root
	tags = p_tags.duplicate()
	tags.sort()
	for k in p_noise:
		noise[k] = p_noise[k]
	recompute()

func recompute() -> void:
	melt = MaterialTags.BASE_MELT + noise.melt
	boil = MaterialTags.BASE_BOIL + noise.boil
	density = MaterialTags.BASE_DENSITY + noise.dens
	hardness = MaterialTags.BASE_HARDNESS + noise.hard
	var c := Color(0, 0, 0)
	for t in tags:
		var d: Dictionary = MaterialTags.TAGS[t]
		melt += d.melt
		boil += d.boil
		density += d.dens
		hardness += d.hard
		c += d.col
	if tags.is_empty():
		c = Color(0.6, 0.6, 0.6)
	else:
		c /= float(tags.size())
	color = Color(c.r, c.g, c.b, 1.0)
	melt = max(melt, -260.0)
	boil = max(boil, melt + 20.0)
	density = max(density, 0.1)
	hardness = clamp(hardness, 0.0, 10.0)

func has(tag: String) -> bool:
	return tag in tags

func is_exotic() -> bool:
	for t in tags:
		if MaterialTags.is_exotic(t):
			return true
	return false

func phase_at(temp: float) -> int:
	if has("phase_inverted"):
		if temp >= boil:
			return Phase.SOLID
		if temp >= melt:
			return Phase.LIQUID
		return Phase.GAS
	if temp < melt:
		return Phase.SOLID
	if temp < boil:
		return Phase.LIQUID
	return Phase.GAS

func tag_names() -> String:
	return ", ".join(tags.map(func(t): return MaterialTags.display(t)))
