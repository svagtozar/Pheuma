class_name TileChunk
extends Node2D
## Кусок карты 16×16 клеток, запечённый в текстуру: грунт, препятствия и залежи.
## Вместо сотен прямоугольников и кружков за кадр — один квадрат с текстурой.
## Перезапекается, только когда меняется «отпечаток» его клеток.

const SIZE := 16
const PX := 16          # пикселей на клетку в текстуре (на экране клетка — 32)
const T := 32.0

var view                 # game/world_view.gd
var origin := Vector2i.ZERO
var fingerprint := -1
var anim_cells: Array = []     # лава и кислота — анимируются поверх текстуры
var exotic_cells: Array = []   # видимые залежи экзотики — мерцают поверх
var _tex: ImageTexture

func _init() -> void:
	show_behind_parent = true
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

## Отпечаток: клетки, мосты, трещины льда, залежи (с точностью до 10 кг) и их видимость.
func compute_fingerprint() -> int:
	var w: World = view.world
	var p := w.planet
	var h := 17
	for y in range(origin.y, min(origin.y + SIZE, p.height)):
		for x in range(origin.x, min(origin.x + SIZE, p.width)):
			var c := Vector2i(x, y)
			h = (h * 31 + w.tile(c)) & 0x7fffffff
			if w.tile_overrides.has(c):
				h = (h * 31 + 7) & 0x7fffffff
			var st: float = w.ice_stress.get(c, 0.0)
			if st > 0.0:
				h = (h * 31 + int(st * 4.0) + 11) & 0x7fffffff
			var dep = p.deposits.get(c)
			if dep != null and dep.amount > 0.0:
				h = (h * 31 + int(dep.amount / 10.0) * 3 + (1 if view._deposit_visible(c) else 2) + dep.sub.hash()) & 0x7fffffff
	return h

func refresh_if_changed() -> bool:
	var f := compute_fingerprint()
	if f == fingerprint:
		return false
	fingerprint = f
	_bake()
	queue_redraw()
	return true

func _bake() -> void:
	var w: World = view.world
	var p := w.planet
	var img := Image.create(SIZE * PX, SIZE * PX, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	anim_cells.clear()
	exotic_cells.clear()
	var g: Color = view.ground_color()
	var k := PX / T
	for y in range(origin.y, min(origin.y + SIZE, p.height)):
		for x in range(origin.x, min(origin.x + SIZE, p.width)):
			var c := Vector2i(x, y)
			var lp := Vector2i((x - origin.x) * PX, (y - origin.y) * PX)
			var r := Rect2i(lp, Vector2i(PX, PX))
			var shade := 0.94 + 0.06 * float((x * 7 + y * 13) % 5) / 4.0
			match w.tile(c):
				Planet.Tile.GROUND:
					img.fill_rect(r, g * shade)
					if w.tile_overrides.has(c):
						img.fill_rect(r, g.lerp(Color(0.7, 0.9, 1.0), 0.55))
				Planet.Tile.ROCK:
					img.fill_rect(r, Color(0.16, 0.15, 0.16) * shade)
					img.fill_rect(r.grow(-int(6 * k)), Color(0.22, 0.21, 0.22))
				Planet.Tile.CHASM:
					img.fill_rect(r, Color(0.02, 0.02, 0.03))
				Planet.Tile.LAVA:
					img.fill_rect(r, Color(0.85, 0.35, 0.05))
					anim_cells.append(c)
				Planet.Tile.ICE:
					img.fill_rect(r, Color(0.70, 0.86, 0.95) * shade)
					var st: float = w.ice_stress.get(c, 0.0)
					if st > 0.0:
						for i in PX - 4:
							img.set_pixel(lp.x + 2 + i, lp.y + 3 + int(i * 0.8), Color(0.2, 0.3, 0.4))
				Planet.Tile.ACID:
					img.fill_rect(r, Color(0.35, 0.75, 0.20))
					anim_cells.append(c)
				Planet.Tile.RUIN:
					img.fill_rect(r, Color(0.32, 0.28, 0.36) * shade)
					var inner := r.grow(-int(9 * k))
					var oc := Color(0.45, 0.40, 0.55)
					img.fill_rect(Rect2i(inner.position, Vector2i(inner.size.x, 1)), oc)
					img.fill_rect(Rect2i(inner.position + Vector2i(0, inner.size.y - 1), Vector2i(inner.size.x, 1)), oc)
					img.fill_rect(Rect2i(inner.position, Vector2i(1, inner.size.y)), oc)
					img.fill_rect(Rect2i(inner.position + Vector2i(inner.size.x - 1, 0), Vector2i(1, inner.size.y)), oc)
			_bake_deposit(img, w, c, lp, k)
	if _tex == null:
		_tex = ImageTexture.create_from_image(img)
	else:
		_tex.update(img)

func _bake_deposit(img: Image, w: World, c: Vector2i, lp: Vector2i, k: float) -> void:
	var dep = w.planet.deposits.get(c)
	if dep == null or dep.amount <= 0.0:
		return
	var s: Substance = w.db.get_sub(dep.sub)
	if s == null:
		return
	var ctr := Vector2(lp) + Vector2(PX, PX) * 0.5
	if view._deposit_visible(c):
		var rad: float = clampf(4.0 + dep.amount * 0.12, 5.0, 12.0) * 0.6 * k
		for i in 3:
			var off := Vector2(cos(i * 2.1 + c.x), sin(i * 2.1 + c.y)) * 7.0 * k
			_disc(img, ctr + off, rad, s.color.darkened(0.15))
		if s.is_exotic() and w.is_analyzed(s):
			exotic_cells.append(c)
	else:
		_disc(img, ctr, 4.0 * k, Color(0.55, 0.5, 0.45, 0.6))

static func _disc(img: Image, ctr: Vector2, rad: float, col: Color) -> void:
	var r := int(ceil(rad))
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if dx * dx + dy * dy <= rad * rad + 0.5:
				var px := int(ctr.x) + dx
				var py := int(ctr.y) + dy
				if px >= 0 and py >= 0 and px < img.get_width() and py < img.get_height():
					img.set_pixel(px, py, img.get_pixel(px, py).blend(col))

func _draw() -> void:
	if _tex != null:
		draw_texture_rect(_tex, Rect2(Vector2(origin) * T, Vector2(SIZE, SIZE) * T), false)
