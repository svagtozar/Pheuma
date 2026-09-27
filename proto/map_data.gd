class_name ProtoMapData
extends RefCounted
## Данные карты для радара (ProtoRadar) и полноэкранной 3D-карты (ProtoMapView):
## рельеф сверху (цвет, отмывка, горизонтали), пустоты под землёй, разведанное
## (туман войны) и метки. Рельеф и метки задаёт владелец — предпросмотр или
## F3-вид игры; разведанное растёт само: reveal() вокруг робота.
## Координаты карты — мировые x и z; пиксель рельефа — 1 / res метра.

const REVEAL_R := 18.0           # м вокруг робота на поверхности открываются на карте
const REVEAL_UNDER := 9.0        # под землёй видно ближе
const FIND_R := 14.0             # метка «найдена», если робот подошёл ближе (3D)
const CONTOUR := 2.0             # шаг горизонталей, м

## Вид метки → [подпись по умолчанию, цвет, известна с начала].
const KINDS := {
	"factory": ["Завод", Color(1.0, 0.78, 0.25), true],
	"cave": ["Вход в пещеру", Color(1.0, 0.52, 0.25), false],
	"hall": ["Пещерный зал", Color(0.78, 0.55, 1.0), false],
	"druse": ["Друза", Color(0.45, 0.9, 1.0), false],
	"mined": ["Выбурено", Color(0.55, 0.58, 0.62), false],
	"deposit": ["Залежь", Color(0.55, 0.95, 0.55), false],
	"machine": ["Машина", Color(1.0, 0.78, 0.25), true],
}

var origin := Vector2.ZERO       # мировые x, z угла карты
var size := Vector2(80, 80)      # м
var res := 2.0                   # пикселей на метр у рельефа
var relief: ImageTexture         # цвет сверху с отмывкой и горизонталями
var height: ImageTexture         # высота поверхности (FORMAT_RF, для рентгена пещеры)
var caves: ImageTexture          # 1 — под поверхностью есть пустота (L8, 1 px = 1 м)
var fog: ImageTexture            # разведано на поверхности: 0..1 (L8, 1 px = 1 м)
var fog_under: ImageTexture      # разведано под землёй (ходы и залы)
var markers: Array = []          # {kind, pos: Vector3, name, color, found, under}
var name := ""                   # название планеты для заголовка карты
var _fog_img: Image
var _under_img: Image
var _fog_dirty := false
var _last_reveal := Vector3.INF
var _heights := PackedFloat32Array()
var _hw := 0

## Пустая карта размером w×h м с углом в o.
func _init(o := Vector2.ZERO, s := Vector2(80, 80), px_per_m := 2.0) -> void:
	origin = o
	size = s
	res = px_per_m
	_fog_img = Image.create(int(ceil(s.x)), int(ceil(s.y)), false, Image.FORMAT_L8)
	fog = ImageTexture.create_from_image(_fog_img)
	_under_img = _fog_img.duplicate()
	fog_under = ImageTexture.create_from_image(_under_img)
	var blank := Image.create(4, 4, false, Image.FORMAT_L8)
	caves = ImageTexture.create_from_image(blank)

# ---------------------------------------------------------------- рельеф

## Рельеф: h(x, z) → высота поверхности, tint(x, z, h, нормаль) → цвет грунта.
## Отмывка (свет с северо-запада) и горизонтали — поверх цвета.
func bake(h: Callable, tint: Callable) -> void:
	var w := int(ceil(size.x * res))
	var hh := int(ceil(size.y * res))
	_hw = w
	_heights.resize(w * hh)
	for j in hh:
		for i in w:
			var p := _px_world(i, j)
			_heights[j * w + i] = h.call(p.x, p.y)
	var img := Image.create(w, hh, false, Image.FORMAT_RGB8)
	var him := Image.create(w, hh, false, Image.FORMAT_RF)
	var light := Vector3(-0.6, 0.75, -0.45).normalized()
	for j in hh:
		for i in w:
			var hc := _heights[j * w + i]
			var dx := (_hat(i + 1, j, hh) - _hat(i - 1, j, hh)) * res * 0.5
			var dz := (_hat(i, j + 1, hh) - _hat(i, j - 1, hh)) * res * 0.5
			var n := Vector3(-dx, 1.0, -dz).normalized()
			var p := _px_world(i, j)
			var c: Color = tint.call(p.x, p.y, hc, n)
			var shade := clampf(0.55 + 0.6 * n.dot(light), 0.35, 1.25)
			c = Color(c.r * shade, c.g * shade, c.b * shade)
			# Горизонталь: рядом с кратной CONTOUR высотой, каждая пятая — ярче.
			var k := hc / CONTOUR
			var slope := maxf(Vector2(dx, dz).length() / res / CONTOUR, 0.02)
			if absf(k - roundf(k)) < slope * 0.6:
				var major := int(roundf(k)) % 5 == 0
				c = c.darkened(0.32 if major else 0.18)
			img.set_pixel(i, j, c)
			him.set_pixel(i, j, Color(hc, 0, 0))
	relief = ImageTexture.create_from_image(img)
	height = ImageTexture.create_from_image(him)

## Пустоты под землёй: open(x, z) → true, если под этим местом есть ход или зал.
func bake_caves(open: Callable) -> void:
	var img := Image.create(int(ceil(size.x)), int(ceil(size.y)), false, Image.FORMAT_L8)
	for j in img.get_height():
		for i in img.get_width():
			if open.call(origin.x + i + 0.5, origin.y + j + 0.5):
				img.set_pixel(i, j, Color.WHITE)
	caves = ImageTexture.create_from_image(img)

func _px_world(i: int, j: int) -> Vector2:
	return origin + Vector2(i + 0.5, j + 0.5) / res

func _hat(i: int, j: int, hh: int) -> float:
	return _heights[clampi(j, 0, hh - 1) * _hw + clampi(i, 0, _hw - 1)]

## Высота поверхности по запечённому рельефу (для меток и камеры карты).
func height_at(x: float, z: float) -> float:
	if _heights.is_empty():
		return 0.0
	var hh := _heights.size() / _hw
	return _hat(int((x - origin.x) * res), int((z - origin.y) * res), hh)

# ---------------------------------------------------------------- метки

func add_marker(kind: String, pos: Vector3, label := "", under := false) -> Dictionary:
	var k: Array = KINDS.get(kind, ["", Color.WHITE, false])
	var m := {"kind": kind, "pos": pos, "name": label if label != "" else k[0],
		"color": k[1], "found": k[2], "under": under}
	markers.append(m)
	return m

## Метки, которые уже можно показывать (найдены).
func found() -> Array:
	return markers.filter(func(m): return m.found)

# ---------------------------------------------------------------- разведка

## Открыть карту вокруг робота. under — робот под землёй: открываются ходы
## и залы рядом (своя маска), а поверхность над ними остаётся в тумане.
func reveal(p: Vector3, under := false) -> void:
	if p.distance_to(_last_reveal) < 1.0:
		return
	_last_reveal = p
	var img := _under_img if under else _fog_img
	var r := REVEAL_UNDER if under else REVEAL_R
	var c := Vector2(p.x, p.z) - origin
	var w := img.get_width()
	var hh := img.get_height()
	for j in range(maxi(0, int(c.y - r)), mini(hh, int(c.y + r) + 1)):
		for i in range(maxi(0, int(c.x - r)), mini(w, int(c.x + r) + 1)):
			var d := Vector2(i + 0.5, j + 0.5).distance_to(c)
			if d > r:
				continue
			# Край открытого — мягкий: 1 внутри, к краю тает.
			var v := clampf((r - d) / 4.0, 0.0, 1.0)
			if v > img.get_pixel(i, j).r:
				img.set_pixel(i, j, Color(v, v, v))
				_fog_dirty = true
	# Подземное находится только снизу: с поверхности друз в зале не видно.
	for m in markers:
		if not m.found and (under or not m.under) and m.pos.distance_to(p) < (FIND_R if under else REVEAL_R):
			m.found = true

## Разведано ли место (0..1) на поверхности или под землёй.
func explored(x: float, z: float, under := false) -> float:
	var img := _under_img if under else _fog_img
	var i := int(x - origin.x)
	var j := int(z - origin.y)
	if i < 0 or j < 0 or i >= img.get_width() or j >= img.get_height():
		return 0.0
	return img.get_pixel(i, j).r

## Доля разведанной поверхности, 0..1.
func explored_share() -> float:
	var raw := _fog_img.get_data()
	var sum := 0
	for b in raw:
		sum += b
	return sum / (255.0 * maxf(1.0, raw.size()))

## Залить в текстуру то, что открылось с прошлого кадра.
func flush() -> void:
	if _fog_dirty:
		_fog_dirty = false
		fog.update(_fog_img)
		fog_under.update(_under_img)

## Сохранение: разведанное (base64 байтов) и найденные метки.
func save_dict() -> Dictionary:
	var ids: Array = []
	for i in markers.size():
		if markers[i].found:
			ids.append(i)
	return {"fog": Marshalls.raw_to_base64(_fog_img.get_data()),
		"under": Marshalls.raw_to_base64(_under_img.get_data()), "found": ids}

func load_dict(d: Dictionary) -> void:
	for pair in [["fog", _fog_img], ["under", _under_img]]:
		var img: Image = pair[1]
		var raw := Marshalls.base64_to_raw(str(d.get(pair[0], "")))
		if raw.size() == img.get_data().size():
			img.set_data(img.get_width(), img.get_height(), false, Image.FORMAT_L8, raw)
			_fog_dirty = true
	for i in d.get("found", []):
		if int(i) >= 0 and int(i) < markers.size():
			markers[int(i)].found = true
	_last_reveal = Vector3.INF
	flush()

## Открыть всё (отладка и кадры).
func reveal_all() -> void:
	_fog_img.fill(Color.WHITE)
	_under_img.fill(Color.WHITE)
	for m in markers:
		m.found = true
	_fog_dirty = true
	flush()
