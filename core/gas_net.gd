class_name GasNet
extends RefCounted
## Сеть давления. Узлы — объёмы газа (трубы, баки, камеры пушек), рёбра —
## соединения с проводимостью. Поток ∝ ΔP. Газ сохраняется; извне его
## добавляют только насосы, а убирают вентиляция, потребители и разрывы.

var nodes := {}   # id → {"v": объём, "n": количество газа, "max_p": предельное давление, "vent": bool}
var edges := {}   # "a:b" → {"a", "b", "k", "open"}
var atm_pressure := 1.0
var ambient := 15.0

func temp_factor() -> float:
	return (ambient + 273.0) / 288.0

func add_node(id: int, volume: float, max_p: float = INF, fill_atm: bool = true) -> void:
	var n: float = atm_pressure * volume / temp_factor() if fill_atm else 0.0
	nodes[id] = {"v": volume, "n": n, "max_p": max_p, "vent": false}

func has_node(id: int) -> bool:
	return nodes.has(id)

## Удаляет узел; возвращает потерянный газ.
func remove_node(id: int) -> float:
	if not nodes.has(id):
		return 0.0
	var lost: float = nodes[id].n
	nodes.erase(id)
	for k in edges.keys():
		if edges[k].a == id or edges[k].b == id:
			edges.erase(k)
	return lost

func _key(a: int, b: int) -> String:
	return "%d:%d" % [min(a, b), max(a, b)]

func connect_nodes(a: int, b: int, k: float = 1.0) -> void:
	if a == b or not nodes.has(a) or not nodes.has(b):
		return
	edges[_key(a, b)] = {"a": min(a, b), "b": max(a, b), "k": k, "open": true}

func disconnect_nodes(a: int, b: int) -> void:
	edges.erase(_key(a, b))

func connected(a: int, b: int) -> bool:
	return edges.has(_key(a, b))

func set_open(a: int, b: int, open: bool) -> void:
	var k := _key(a, b)
	if edges.has(k):
		edges[k].open = open

func neighbors(id: int) -> Array:
	var out: Array = []
	for e in edges.values():
		if e.a == id:
			out.append(e.b)
		elif e.b == id:
			out.append(e.a)
	return out

func pressure(id: int) -> float:
	if not nodes.has(id):
		return 0.0
	var nd: Dictionary = nodes[id]
	return nd.n / nd.v * temp_factor()

func amount(id: int) -> float:
	return nodes[id].n if nodes.has(id) else 0.0

func add_gas(id: int, amt: float) -> void:
	if nodes.has(id):
		nodes[id].n = max(0.0, nodes[id].n + amt)

func take_gas(id: int, amt: float) -> float:
	if not nodes.has(id):
		return 0.0
	var t: float = clamp(amt, 0.0, nodes[id].n)
	nodes[id].n -= t
	return t

## Сколько газа нужно добавить, чтобы довести узел до давления p.
func gas_for_pressure(id: int, p: float) -> float:
	var nd: Dictionary = nodes[id]
	return p * nd.v / temp_factor() - nd.n

func set_vent(id: int, v: bool) -> void:
	if nodes.has(id):
		nodes[id].vent = v

func total_gas() -> float:
	var s := 0.0
	for nd in nodes.values():
		s += nd.n
	return s

## Шаг симуляции. Возвращает id узлов, превысивших предельное давление.
func step(dt: float) -> Array:
	var delta := {}
	for id in nodes:
		delta[id] = 0.0
	for e in edges.values():
		if not e.open:
			continue
		var na: Dictionary = nodes[e.a]
		var nb: Dictionary = nodes[e.b]
		var dp := pressure(e.a) - pressure(e.b)
		var q_eq: float = (na.n * nb.v - nb.n * na.v) / (na.v + nb.v)
		var flow: float = e.k * dp * dt * 4.0
		if abs(flow) > abs(q_eq) * 0.5:
			flow = q_eq * 0.5
		delta[e.a] -= flow
		delta[e.b] += flow
	for id in nodes:
		var nd: Dictionary = nodes[id]
		nd.n = max(0.0, nd.n + delta[id])
		if nd.vent:
			var target: float = atm_pressure * nd.v / temp_factor()
			nd.n += (target - nd.n) * min(1.0, 2.0 * dt)
	var burst: Array = []
	for id in nodes:
		if pressure(id) > nodes[id].max_p:
			burst.append(id)
	return burst
