class_name FxLayer
extends RefCounted
## Видимое движение: частицы дыма, искр, инея, пыли, пузырьков, пара, капель,
## расходящиеся кольца и всплывающие надписи. Мир только сообщает события
## (world.fx), а машины в работе подпитывают эмиттеры каждый кадр.

const MAX := 700
const T := 32.0

var parts: Array = []      # {pos, vel, life, max, col, size, kind, text}
var _cool := {}            # "вид:клетка" → время до следующего разового эффекта

func add(kind: String, pos: Vector2, vel: Vector2, life: float, col: Color, size: float, text: String = "") -> void:
	if parts.size() >= MAX:
		parts.remove_at(0)
	parts.append({"pos": pos, "vel": vel, "life": life, "max": life, "col": col, "size": size, "kind": kind, "text": text})

func update(dt: float) -> void:
	var keep: Array = []
	for p in parts:
		p.life -= dt
		if p.life <= 0.0:
			continue
		match p.kind:
			"spark", "drip":
				p.vel.y += 120.0 * dt
			"smoke", "vapor":
				p.vel *= 1.0 - 0.6 * dt
				p.size += 6.0 * dt
			"text":
				p.vel *= 1.0 - 1.5 * dt
		p.pos += p.vel * dt
		keep.append(p)
	parts = keep
	for k in _cool.keys():
		_cool[k] -= dt
		if _cool[k] <= 0.0:
			_cool.erase(k)

## Не чаще раза в gap секунд для этого вида в этой клетке.
func ready(key: String, gap: float) -> bool:
	if _cool.has(key):
		return false
	_cool[key] = gap
	return true

func draw(ci: CanvasItem, font: Font) -> void:
	for p in parts:
		var k: float = clampf(p.life / p.max, 0.0, 1.0)
		var col: Color = p.col
		match p.kind:
			"smoke", "vapor", "bubble", "dust", "spark", "drip":
				col.a *= k
				ci.draw_circle(p.pos, p.size, col)
			"frost":
				col.a *= k
				var s: float = p.size
				ci.draw_line(p.pos - Vector2(s, 0), p.pos + Vector2(s, 0), col, 1.0)
				ci.draw_line(p.pos - Vector2(0, s), p.pos + Vector2(0, s), col, 1.0)
			"ring":
				col.a *= k
				ci.draw_arc(p.pos, p.size + (1.0 - k) * 18.0, 0.0, TAU, 20, col, 1.5)
			"bolt":
				col.a *= k
				var a: Vector2 = p.pos
				for i in 4:
					var b := a + Vector2(randf_range(-6, 6), 5.0)
					ci.draw_line(a, b, col, 2.0)
					a = b
			"text":
				col.a *= minf(1.0, k * 2.0)
				var w := font.get_string_size(p.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
				ci.draw_rect(Rect2(p.pos + Vector2(-w / 2.0 - 4, -12), Vector2(w + 8, 16)), Color(0.05, 0.06, 0.08, 0.75 * col.a))
				ci.draw_string(font, p.pos + Vector2(-w / 2.0, 0), p.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, col)

# ---------------------------------------------------------------- эмиттеры

static func center(c: Vector2i) -> Vector2:
	return (Vector2(c) + Vector2(0.5, 0.5)) * T

func _rv(sx: float, sy: float) -> Vector2:
	return Vector2(randf_range(-sx, sx), randf_range(-sy, sy))

func smoke(at: Vector2, n: int = 1) -> void:
	for i in n:
		add("smoke", at + _rv(5, 3), Vector2(randf_range(-6, 6), randf_range(-26, -14)), randf_range(1.2, 2.0), Color(0.55, 0.55, 0.58, 0.55), 3.0)

func sparks(at: Vector2, n: int = 3) -> void:
	for i in n:
		add("spark", at, Vector2(randf_range(-40, 40), randf_range(-70, -30)), randf_range(0.4, 0.8), Color(1.0, randf_range(0.5, 0.8), 0.2), 1.5)

func frost(at: Vector2, n: int = 2) -> void:
	for i in n:
		add("frost", at + _rv(12, 12), _rv(8, 8), randf_range(0.8, 1.4), Color(0.75, 0.9, 1.0, 0.9), 2.5)

func dust(at: Vector2, n: int = 3) -> void:
	for i in n:
		add("dust", at + _rv(8, 8), _rv(30, 30), randf_range(0.4, 0.8), Color(0.6, 0.5, 0.38, 0.8), 1.8)

func bubbles(at: Vector2, col: Color, n: int = 2) -> void:
	for i in n:
		add("bubble", at + _rv(8, 4), Vector2(randf_range(-4, 4), randf_range(-24, -12)), randf_range(0.6, 1.1), col.lightened(0.3), 2.2)

func ring(at: Vector2, col: Color) -> void:
	add("ring", at, Vector2.ZERO, 0.9, col, 4.0)

func vapor(at: Vector2, col: Color, n: int = 2) -> void:
	for i in n:
		add("vapor", at + _rv(8, 4), Vector2(randf_range(-5, 5), randf_range(-22, -12)), randf_range(0.9, 1.5), Color(col.r, col.g, col.b, 0.35).lerp(Color(0.9, 0.95, 1.0, 0.35), 0.5), 2.5)

func drip(at: Vector2, col: Color) -> void:
	add("drip", at + _rv(8, 2), Vector2(randf_range(-6, 6), 10.0), 0.7, col.darkened(0.1), 2.0)

func bolt(at: Vector2) -> void:
	add("bolt", at + Vector2(0, -18), Vector2.ZERO, 0.25, Color(0.7, 0.85, 1.0), 1.0)

func popup(at: Vector2, text: String, col: Color) -> void:
	# Свежие надписи рядом — столбиком, чтобы не наезжали.
	var n := 0
	for p in parts:
		if p.kind == "text" and p.life > p.max - 1.0 and (p.pos - at).length() < 60.0:
			n += 1
	add("text", at + Vector2(0, -14 - 18 * n), Vector2(0, -28), 2.2, col.lightened(0.35), 1.0, text)

## Разовое событие из world.fx.
func event(e: Dictionary) -> void:
	var at := center(e.cell)
	var col: Color = e.col
	var kind: String = e.kind
	match kind:
		"reveal":
			popup(at, e.text, col)
			ring(at, col)
		"identified":
			popup(at + Vector2(0, -16), e.text, Color(0.5, 1.0, 0.6))
			ring(at, Color(0.5, 1.0, 0.6))
		"vapor":
			if ready("vapor:%s" % [e.cell], 0.5):
				vapor(at, col, 3)
		"drip":
			if ready("drip:%s" % [e.cell], 0.5):
				drip(at, col)
				drip(at, col)
		"probe_heat":
			sparks(at + Vector2(10, -6), 6)
			smoke(at + Vector2(10, -6), 2)
		"probe_drop":
			drip(at + Vector2(10, -14), Color(0.6, 0.95, 0.4))
			bubbles(at + Vector2(10, -4), Color(0.6, 0.95, 0.4), 3)
		"probe_magnet":
			ring(at + Vector2(10, -6), Color(0.8, 0.3, 0.3))
			ring(at + Vector2(10, -6), Color(0.3, 0.4, 0.9))
		"probe_spark":
			bolt(at + Vector2(10, 0))
			sparks(at + Vector2(10, 0), 3)
		"probe_count":
			ring(at, Color(0.5, 1.0, 0.4))
		_:
			if kind.begins_with("process_"):
				_process_burst(kind.substr(8), at, col)

func _process_burst(pid: String, at: Vector2, col: Color) -> void:
	match pid:
		"furnace", "sinter":
			sparks(at, 5)
			smoke(at + Vector2(0, -8), 2)
		"cryochamber", "condenser":
			frost(at, 6)
		"crusher":
			dust(at, 8)
		"treater", "electrolyzer", "distiller", "centrifuge":
			bubbles(at, col, 4)
		"resonator", "irradiator":
			ring(at, col)
		_:
			ring(at, col)

## Работающая машина подпитывает свой эмиттер (вызывается каждый кадр).
func machine(m, dt: float) -> void:
	var at := center(m.cell)
	if m is Processor and m.busy != null:
		var r := randf()
		match m.pid:
			"furnace", "sinter":
				if r < 3.0 * dt:
					smoke(at + Vector2(0, -10))
				if r < 1.5 * dt:
					sparks(at, 1)
			"cryochamber", "condenser":
				if r < 4.0 * dt:
					frost(at, 1)
			"crusher":
				if r < 6.0 * dt:
					dust(at, 1)
			"treater", "electrolyzer", "distiller", "centrifuge":
				if r < 4.0 * dt:
					bubbles(at, m.busy.substance.color, 1)
			"resonator", "irradiator":
				if r < 1.2 * dt:
					ring(at, m.busy.substance.color)
	elif m.kind == "drill" and m.status == "" or m.kind == "drill" and m.status == "добывает соседнюю клетку":
		if randf() < 4.0 * dt:
			dust(at + Vector2(0, 8), 1)
	elif m.kind == "pump" and m.status == "":
		if randf() < 3.0 * dt:
			var dir := _rv(1, 1).normalized()
			add("dust", at + dir * 16.0, -dir * 30.0, 0.5, Color(0.8, 0.9, 1.0, 0.6), 1.2)
	elif m.kind == "decompressor" or (m.kind == "pump" and m.config.get("reverse", false) and m.status == ""):
		if randf() < 3.0 * dt:
			vapor(at + Vector2(0, -8), Color(0.85, 0.9, 1.0), 1)
