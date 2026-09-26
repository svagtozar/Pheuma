class_name Portion
extends RefCounted
## Порция материала — то, что физически движется по заводу.

var substance: Substance
var mass := 1.0
var temp := 15.0

func _init(s: Substance = null, m: float = 1.0, t: float = 15.0) -> void:
	substance = s
	mass = m
	temp = t

func phase() -> int:
	return substance.phase_at(temp)

func has(tag: String) -> bool:
	return substance.has(tag)

func copy() -> Portion:
	return Portion.new(substance, mass, temp)

func split(m: float) -> Portion:
	m = min(m, mass)
	mass -= m
	return Portion.new(substance, m, temp)

## Слить другую порцию того же материала в эту.
func absorb(other: Portion) -> void:
	var total := mass + other.mass
	if total > 0.0:
		temp = (temp * mass + other.temp * other.mass) / total
	mass = total
