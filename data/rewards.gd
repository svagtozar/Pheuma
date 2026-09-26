class_name Rewards
## Награды за этапы цели: после этапа предлагаются три карточки, игрок берёт одну.

const CARDS := {
	"supply": {"n": "Сброс припасов", "desc": "С орбиты к базе прилетит капсула с 40 кг сплава капсулы."},
	"knowledge": {"n": "Архив экспедиции", "desc": "+4 знания для прокачки."},
	"blueprint": {"n": "Чертёж с орбиты", "desc": "Случайный неизученный чертёж модуля."},
	"slot": {"n": "Лишний слот", "desc": "+1 слот модуля до конца рана."},
	"repair": {"n": "Ремонтная бригада", "desc": "Все машины и робот полностью починены."},
	"survey": {"n": "Орбитальная разведка", "desc": "Залежи в радиусе 25 клеток раскрыты и их материалы проанализированы."},
}

static func unlearned_blueprints(w: World) -> Array:
	var out: Array = []
	for k in Modules.MODULES:
		if not w.robot.blueprints.has(k):
			out.append(k)
	out.sort()
	return out

## Три разные карточки, детерминированно от seed и номера этапа.
static func offer(w: World, stage: int) -> Array:
	var rng: Rng = w.rng.fork("rewards%d" % stage)
	var pool: Array = CARDS.keys()
	pool.sort()
	if unlearned_blueprints(w).is_empty():
		pool.erase("blueprint")
	var out: Array = []
	while out.size() < 3 and not pool.is_empty():
		var c: String = rng.pick(pool)
		out.append(c)
		pool.erase(c)
	return out

static func apply(w: World, id: String) -> String:
	var r := w.robot
	match id:
		"supply":
			var to := Vector2(w.planet.spawn) + Vector2(2.5, 0.5)
			w.spawn_projectile(to + Vector2(-8, -24), to, [Portion.new(w.starter, 40.0, w.planet.ambient_temp)], false, "capsule")
			return "Капсула с припасами летит к базе"
		"knowledge":
			r.knowledge += 4
			return "+4 знания"
		"blueprint":
			var bps := unlearned_blueprints(w)
			if bps.is_empty():
				r.knowledge += 3
				return "Все чертежи уже есть — вместо этого +3 знания"
			var k: String = w.rng.fork("bp%d" % w.goals.stage).pick(bps)
			r.blueprints[k] = true
			return "Новый чертёж: " + Modules.MODULES[k].n
		"slot":
			r.bonus_slots += 1
			return "+1 слот модуля"
		"repair":
			for m in w.machines.values():
				m.hp = m.max_hp()
			r.hp = r.max_hp()
			return "Всё починено"
		"survey":
			for c in w.planet.deposits:
				if w.near_robot(c, 25.0):
					w.revealed[c] = true
					w.touch(w.db.get_sub(w.planet.deposits[c].sub))
			return "Залежи вокруг раскрыты"
	return ""
