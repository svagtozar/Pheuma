class_name ComponentStats
## Единая формула: (тип детали, материал, качество) → характеристики.
## Используется и постройками, и модулями робота — материал определяет деталь.

const SIZE := {"pipe": 0.3, "sensor": 0.2, "gate_and": 0.2, "gate_or": 0.2, "gate_not": 0.2, "wire": 0.1,
	"module": 1.0, "hull": 3.0, "hand_drill": 0.8, "launch_silo": 6.0, "dome": 5.0}

static func compute(kind: String, sub: Substance, quality: float = 0.0) -> Dictionary:
	var q := 1.0 + quality
	var s := {}
	var max_p := 2.0 + sub.hardness * 0.9
	if sub.has("elastic"): max_p += 3.0
	if sub.has("dense"): max_p += 2.0
	if sub.has("brittle"): max_p -= 2.0
	if sub.has("anchoring"): max_p += 2.0
	s.max_p = max(1.5, max_p * q)
	s.max_t = 5000.0 if sub.has("thermo_inverted") else sub.melt - 30.0 + 50.0 * quality
	s.heat_loss = 0.2 if sub.has("insulating") else 1.0
	s.corrosion_proof = sub.has("insulating") or sub.has("crystalline") or sub.has("anchoring")
	s.wire_range = 8.0 + (16.0 if sub.has("conductive") else 0.0) + (4.0 if sub.has("metallic") else 0.0)
	s.wire_range *= q
	s.wireless = sub.has("resonant")
	var mass: float = sub.density * SIZE.get(kind, 1.5)
	if sub.has("antigravitic"):
		mass = -abs(mass) * 0.5
	s.mass = mass
	s.hardness = sub.hardness * q
	s.burst_risk = 0.15 if sub.has("brittle") else 0.0
	s.radiation = 0.3 if sub.has("radioactive") else 0.0
	s.magnetic = sub.has("magnetic")
	s.storm_proof = sub.has("anchoring") or sub.has("dense")
	s.self_repair = 0.5 if sub.has("self_replicating") else 0.0
	s.wear = 0.2 if sub.has("chrono_lagged") else 1.0
	s.light = sub.has("luminous")
	s.leaky = sub.has("phasing")
	s.speed = (1.2 if sub.has("conductive") else 1.0) * (1.0 + quality * 0.5)
	s.max_hp = (40.0 + sub.hardness * 12.0) * q
	# Защита (для корпуса и оболочки робота)
	s.shield_heat = clamp((0.6 if sub.has("insulating") else 0.0) + max(0.0, sub.melt - 800.0) / 2000.0, 0.0, 0.9) * q
	s.shield_radiation = clamp((0.5 if sub.has("dense") else 0.0) + (0.3 if sub.has("metallic") else 0.0) + (0.4 if sub.has("anchoring") else 0.0), 0.0, 0.9)
	s.shield_toxic = clamp((0.5 if sub.has("crystalline") or sub.has("insulating") else 0.0) + (0.3 if sub.has("elastic") else 0.0), 0.0, 0.9)
	s.shield_acid = 0.8 if s.corrosion_proof else 0.0
	s.flex = (1.5 if sub.has("elastic") else 1.0) * (1.3 if sub.has("fibrous") else 1.0)
	s.shield_heat = min(s.shield_heat, 0.9)
	return s

## Короткое описание значимых свойств для инспектора.
static func describe(kind: String, sub: Substance, quality: float = 0.0) -> Array:
	var s := compute(kind, sub, quality)
	var out: Array = []
	out.append("предельное давление %.1f атм" % s.max_p)
	out.append("выдерживает до %.0f °C" % s.max_t)
	if s.heat_loss < 1.0: out.append("хорошо держит тепло")
	if s.corrosion_proof: out.append("не разъедается кислотой")
	if sub.has("anchoring"): out.append("удерживает фазирующее")
	if s.leaky: out.append("груз просачивается сквозь стенки!")
	if s.burst_risk > 0.0: out.append("хрупкий: может лопнуть")
	if s.radiation > 0.0: out.append("облучает робота рядом")
	if s.magnetic: out.append("сбивает датчики рядом")
	if s.storm_proof: out.append("не боится бурь и толчков")
	if s.self_repair > 0.0: out.append("сам себя чинит")
	if s.wear < 1.0: out.append("почти не изнашивается")
	if s.wireless: out.append("беспроводная связь")
	if s.speed > 1.0: out.append("работает быстрее ×%.1f" % s.speed)
	if s.mass < 0.0: out.append("отрицательная масса")
	return out
