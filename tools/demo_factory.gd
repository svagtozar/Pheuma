class_name DemoFactory
## Демонстрационный завод для скриншотов и замеров производительности.
## Блок 8×6 клеток, 13 машин: подача → печь с насосом → контейнер, трубы к баку,
## подача → дробилка → контейнер, открытый контейнер с летучим. Блоки — сеткой.

const BLOCK := 13
const BW := 8
const BH := 6

## Строит завод из n машин (кратно блоку, последний блок — сколько влезет).
## Возвращает центр завода в клетках.
static func build(w: World, origin: Vector2i, n: int = BLOCK) -> Vector2:
	var blocks := int(ceil(float(n) / BLOCK))
	var cols := int(ceil(sqrt(float(blocks))))
	var rows := int(ceil(float(blocks) / cols))
	for dy in range(-1, rows * BH + 1):
		for dx in range(-1, cols * BW + 1):
			var q := origin + Vector2i(dx, dy)
			if q.x <= 0 or q.y <= 0 or q.x >= w.planet.width - 1 or q.y >= w.planet.height - 1:
				continue
			w.planet.set_tile(q, Planet.Tile.GROUND)
			w.planet.deposits.erase(q)
	var ore := w.db.get_sub("demo_ore")
	if ore == null:
		ore = w.db.add(Substance.new("demo_ore", "Демит", ["brittle", "flammable"]))
	var vol := w.db.get_sub("demo_gas")
	if vol == null:
		vol = w.db.add(Substance.new("demo_gas", "Летан", ["volatile", "organic"]))
	var left := n
	for b in blocks:
		var o := origin + Vector2i((b % cols) * BW, (b / cols) * BH)
		left -= _block(w, o, ore, vol, left)
	return Vector2(origin) + Vector2(cols * BW, rows * BH) / 2.0

static func _block(w: World, o: Vector2i, ore: Substance, vol: Substance, budget: int) -> int:
	var plan: Array = [
		["container", Vector2i(0, 0)], ["furnace", Vector2i(1, 0)], ["container", Vector2i(2, 0)],
		["pump", Vector2i(1, 1)], ["pipe", Vector2i(1, 2)], ["pipe", Vector2i(2, 2)], ["pipe", Vector2i(3, 2)],
		["pipe", Vector2i(4, 2)], ["tank", Vector2i(5, 2)], ["container", Vector2i(4, 0)],
		["crusher", Vector2i(5, 0)], ["container", Vector2i(6, 0)], ["container", Vector2i(3, 4)],
	]
	var made := 0
	for i in plan.size():
		if made >= budget:
			break
		var m := w.place(plan[i][0], o + plan[i][1], 0, w.starter, true)
		if m == null:
			continue
		made += 1
		match i:
			0, 9:
				m.config.pass_through = true
				m.store(Portion.new(ore, 40.0))
			3:
				m.config.target_p = 6.0
			12:
				m.store(Portion.new(vol, 20.0))
	return made
