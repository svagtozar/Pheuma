class_name TileTerrain
extends ProtoTerrain
## Объёмный рельеф из карты игры: у каждой клетки планеты своя высота (грунт —
## ровная равнина, скала — гребень, расщелина — провал, лава и кислота — низины
## под жидкостью, лёд — гладкие плиты, руины — ровные плиты под обломками).
## Цвета и шейдер — от ProtoTerrain, поверхность — карта высот (пещер нет).

const S := 2.0                  # метров на клетку игры (как ProtoMachines.CELL)
const BASE := 8.0               # высота равнины
const STEP := 0.5               # шаг сетки рельефа, м

var planet: Planet
var world: World
var heights := PackedFloat32Array()   # высота клетки игры в её центре
var tw := 0
var th := 0
var _gh := PackedFloat32Array()      # высоты в узлах сетки STEP
var _gt := PackedByteArray()         # клетка игры в узлах сетки STEP

## Высоты и клетки в узлах сетки: считаются один раз для рельефа и жидкостей.
func _prepare_grid() -> void:
	if not _gh.is_empty():
		return
	var nx := int(sx / STEP)
	var nz := int(sz / STEP)
	_gh.resize((nx + 1) * (nz + 1))
	_gt.resize(_gh.size())
	for iz in nz + 1:
		for ix in nx + 1:
			var i := iz * (nx + 1) + ix
			_gh[i] = surface_h(ix * STEP, iz * STEP)
			_gt[i] = tile_at(ix * STEP, iz * STEP)

func _init(w: World) -> void:
	world = w
	planet = w.planet
	tw = planet.width
	th = planet.height
	super(planet.seed_value)
	sx = int(tw * S)
	sz = int(th * S)
	sy = 24
	cave_c = Vector3(-100, -100, -100)
	heights.resize(tw * th)
	for y in th:
		for x in tw:
			heights[y * tw + x] = _tile_h(Vector2i(x, y))

## Высота клетки игры по её типу.
func _tile_h(c: Vector2i) -> float:
	var n := noise.get_noise_2d(c.x * S, c.y * S)
	match world.tile(c):
		Planet.Tile.ROCK: return BASE + 3.2 + absf(n) * 5.0 + 0.8 * noise3.get_noise_2d(c.x * 7.0, c.y * 7.0)
		Planet.Tile.CHASM: return BASE - 6.0
		Planet.Tile.LAVA, Planet.Tile.ACID: return BASE - 1.3
		Planet.Tile.ICE: return BASE - 0.05
	return BASE + n * 0.35

func _raw_h(x: float, z: float) -> float:
	if heights.is_empty():
		return BASE
	return surface_h(x, z)

## Клетка игры под точкой рельефа — с тем же изгибом границ, что у высот.
func tile_at(x: float, z: float) -> int:
	var g := _warp(x, z)
	return world.tile(Vector2i(floori(g.x), floori(g.y)))

## Координаты в клетках с изгибом: границы клеток на рельефе не по линейке.
func _warp(x: float, z: float) -> Vector2:
	return Vector2(x / S + noise3.get_noise_2d(x * 1.7, z * 1.7 + 300.0) * 0.45,
		z / S + noise3.get_noise_2d(x * 1.7 + 300.0, z * 1.7) * 0.45)

## Уровень жидкости в низинах лавы и кислоты.
func liquid_level() -> float:
	return BASE - 0.8

func _hc(x: int, y: int) -> float:
	x = clampi(x, 0, tw - 1)
	y = clampi(y, 0, th - 1)
	return heights[y * tw + x]

## Высота поверхности: между центрами клеток — плавно, у кромки гребня и провала
## переход сжат, чтобы равнина оставалась ровной почти до края.
func surface_h(x: float, z: float) -> float:
	if heights.is_empty():
		return BASE
	var g := _warp(x, z)
	var gx := g.x - 0.5
	var gz := g.y - 0.5
	var ix := floori(gx)
	var iz := floori(gz)
	var fx := _ease(gx - ix)
	var fz := _ease(gz - iz)
	var a := lerpf(_hc(ix, iz), _hc(ix + 1, iz), fx)
	var b := lerpf(_hc(ix, iz + 1), _hc(ix + 1, iz + 1), fx)
	return lerpf(a, b, fz) + noise3.get_noise_2d(x * 3.0, z * 3.0) * 0.06

static func _ease(t: float) -> float:
	# Ступенька: середина клетки плоская, склон — в узкой полосе у границы.
	return smoothstep(0.12, 0.88, t)

func density(x: float, y: float, z: float) -> float:
	return surface_h(x, z) - y

func sky_vis(_p: Vector3) -> float:
	return 1.0

func _vein(_p: Vector3) -> float:
	return 0.0

## Цвет по типу клетки поверх общего цвета породы.
func _color(p: Vector3, n: Vector3, vein_m: float = 0.0) -> Color:
	var c := super._color(p, n, vein_m)
	var t := tile_at(p.x, p.z)
	var low := clampf((BASE - 0.3 - p.y) / 5.0, 0.0, 1.0)
	match t:
		Planet.Tile.ICE:
			c = c.lerp(Color(0.72, 0.86, 0.95), 0.75)
		Planet.Tile.RUIN:
			var tiles_k := 0.5 + 0.5 * signf(sin(p.x * 3.14) * sin(p.z * 3.14))
			c = c.lerp(Color(0.52, 0.5, 0.46), 0.6) * (0.85 + 0.15 * tiles_k)
		Planet.Tile.LAVA:
			c = c.lerp(Color(0.12, 0.08, 0.07), 0.7)
		Planet.Tile.ACID:
			c = c.lerp(Color(0.35, 0.38, 0.2), 0.5)
		Planet.Tile.CHASM:
			c = c.darkened(0.2 + 0.6 * low)
	c.a = 1.0
	return c

## Карта высот сеткой STEP с цветом вершин под шейдер ProtoTerrain.
func build_height_mesh() -> ArrayMesh:
	var nx := int(sx / STEP)
	var nz := int(sz / STEP)
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var uvs := PackedVector2Array()
	verts.resize((nx + 1) * (nz + 1))
	norms.resize(verts.size())
	cols.resize(verts.size())
	uvs.resize(verts.size())
	_prepare_grid()
	var hs := _gh
	for iz in nz + 1:
		for ix in nx + 1:
			var i := iz * (nx + 1) + ix
			var hl := hs[iz * (nx + 1) + maxi(ix - 1, 0)]
			var hr := hs[iz * (nx + 1) + mini(ix + 1, nx)]
			var hd := hs[maxi(iz - 1, 0) * (nx + 1) + ix]
			var hu := hs[mini(iz + 1, nz) * (nx + 1) + ix]
			var nrm := Vector3(hl - hr, 2.0 * STEP, hd - hu).normalized()
			var p := Vector3(ix * STEP, hs[i], iz * STEP)
			verts[i] = p
			norms[i] = nrm
			cols[i] = _color(p, nrm)
			uvs[i] = Vector2.ZERO
	var idx := PackedInt32Array()
	idx.resize(nx * nz * 6)
	var k := 0
	for iz in nz:
		for ix in nx:
			var a := iz * (nx + 1) + ix
			var b := a + 1
			var c := a + nx + 1
			var d := c + 1
			idx[k] = a; idx[k + 1] = b; idx[k + 2] = d
			idx[k + 3] = a; idx[k + 4] = d; idx[k + 5] = c
			k += 6
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return mesh

## Точка клетки игры в 3D (центр клетки на поверхности).
func cell_pos(c: Vector2i) -> Vector3:
	var x := (c.x + 0.5) * S
	var z := (c.y + 0.5) * S
	return Vector3(x, surface_h(x, z), z)

## Позиция робота игры (в клетках) в 3D.
func world_pos(p: Vector2) -> Vector3:
	var x := p.x * S
	var z := p.y * S
	return Vector3(x, surface_h(x, z), z)

## Гладь жидкости на уровне level сеткой STEP: у клеток типа tile (с запасом в
## шаг сетки) и там, где рельеф ниже уровня. Край прячется под берегом.
func liquid_mesh(tile: int, level: float) -> ArrayMesh:
	_prepare_grid()
	var nx := int(sx / STEP)
	var nz := int(sz / STEP)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var any := false
	for iz in nz:
		for ix in nx:
			var near := false
			for dz in range(-1, 3):
				for dx in range(-1, 3):
					var jx := clampi(ix + dx, 0, nx)
					var jz := clampi(iz + dz, 0, nz)
					if _gt[jz * (nx + 1) + jx] == tile:
						near = true
			if not near:
				continue
			var i := iz * (nx + 1) + ix
			var lo := minf(minf(_gh[i], _gh[i + 1]), minf(_gh[i + nx + 1], _gh[i + nx + 2]))
			if lo > level:
				continue
			any = true
			var a := Vector3(ix * STEP, level, iz * STEP)
			for p in [a, a + Vector3(STEP, 0, 0), a + Vector3(STEP, 0, STEP), a, a + Vector3(STEP, 0, STEP), a + Vector3(0, 0, STEP)]:
				st.set_normal(Vector3.UP)
				st.add_vertex(p)
	if not any:
		return ArrayMesh.new()
	return st.commit()
