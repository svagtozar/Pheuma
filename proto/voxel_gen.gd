class_name ProtoVoxelGen
extends VoxelGeneratorScript
## Генератор для ProtoVoxelGround. Источник правды — поле ProtoTerrain:
##   LOD 1 и дальше (1 м, 2 м, …) — копии из заранее собранных VoxelBuffer'ов
##   (узлы поля 1 м и их прореживания): одна операция на блок, в C++.
##   LOD 0 (0,5 м) — у поверхности трилинейно по узлам 1 м, а в коробке пещеры —
##   точное поле с шагом 0,5 м (как у прежней детальной сетки пещеры). Блоки
##   целиком в толще или в воздухе заполняются одним значением.
## Знак у модуля обратный: минус — порода. Значения — в метрах.

const VOXEL := 0.5              # м на воксель LOD 0
const PAD := 2                  # узлов запаса по краям буферов (повтор края)

var levels: Array = []          # VoxelBuffer: [k] — узлы с шагом 2^k м, со сдвигом PAD
var size := Vector3i.ZERO       # узлов поля 1 м
var terrain: ProtoTerrain       # его dens — поле 1 м (x быстрее всех)
var fine := PackedFloat32Array()  # поле 0,5 м в коробке пещеры (x быстрее всех)
var fine_o := Vector3i.ZERO     # угол коробки, в вокселях LOD 0
var fine_n := Vector3i.ZERO     # узлов коробки по осям

func load_field(t: ProtoTerrain) -> void:
	size = Vector3i(t.sx + 1, t.sy + 1, t.sz + 1)
	terrain = t
	levels = [_level0()]
	for k in range(1, 4):
		var prev: VoxelBuffer = levels[k - 1]
		var ps := prev.get_size() - Vector3i.ONE * PAD * 2
		var d := _new_buffer(Vector3i((ps.x + 1) / 2, (ps.y + 1) / 2, (ps.z + 1) / 2) + Vector3i.ONE * PAD * 2)
		for z in d.get_size().z:
			for x in d.get_size().x:
				for y in d.get_size().y:
					var q := (Vector3i(x, y, z) - Vector3i.ONE * PAD) * 2 + Vector3i.ONE * PAD
					q = q.clamp(Vector3i.ZERO, prev.get_size() - Vector3i.ONE)
					d.set_voxel_f(prev.get_voxel_f(q.x, q.y, q.z, VoxelBuffer.CHANNEL_SDF), x, y, z, VoxelBuffer.CHANNEL_SDF)
		levels.append(d)

## Поле 0,5 м в коробке box (метры, углы кратны 0,5) — из ProtoTerrain.
func load_fine(t: ProtoTerrain, box: AABB) -> void:
	var o := (box.position / VOXEL).floor()
	var e := (box.end / VOXEL).ceil()
	fine_o = Vector3i(o)
	fine_n = Vector3i(e - o) + Vector3i.ONE
	fine = t.fine_field(Vector3(fine_o) * VOXEL, fine_n - Vector3i.ONE, VOXEL)

static func _new_buffer(n: Vector3i) -> VoxelBuffer:
	var b := VoxelBuffer.new()
	b.create(n.x, n.y, n.z)
	b.set_channel_depth(VoxelBuffer.CHANNEL_SDF, VoxelBuffer.DEPTH_32_BIT)
	return b

## Узлы 1 м в порядке модуля (ZXY: y быстрее всех), с запасом PAD: сверху и
## по бокам воздух (края участка — отвесной «юбкой» вниз, под шаром её не видно),
## снизу порода.
func _level0() -> VoxelBuffer:
	var dens := terrain.dens
	var n := size + Vector3i.ONE * PAD * 2
	var f := PackedFloat32Array()
	f.resize(n.x * n.y * n.z)
	var j := 0
	for z in n.z:
		var sz := z - PAD
		for x in n.x:
			var sx := x - PAD
			var out_xz := sx < 0 or sz < 0 or sx >= size.x or sz >= size.z
			var i0 := sx + size.x * size.y * sz
			for y in n.y:
				var yy := y - PAD
				if out_xz:
					f[j] = 1.0
				elif yy < 0:
					f[j] = -1.0
				elif yy >= size.y:
					f[j] = 1.0
				else:
					f[j] = -dens[i0 + size.x * yy]
				j += 1
	var b := _new_buffer(n)
	b.set_channel_from_byte_array(VoxelBuffer.CHANNEL_SDF, f.to_byte_array())
	return b

## Узлы 1 м в области [lo, hi] поменялись (правка рельефа): в буферы LOD.
func refresh(lo: Vector3i, hi: Vector3i) -> void:
	lo = lo.clamp(Vector3i.ZERO, size - Vector3i.ONE)
	hi = hi.clamp(Vector3i.ZERO, size - Vector3i.ONE)
	var dens := terrain.dens
	var b: VoxelBuffer = levels[0]
	for z in range(lo.z, hi.z + 1):
		for x in range(lo.x, hi.x + 1):
			var i0 := x + size.x * size.y * z
			for y in range(lo.y, hi.y + 1):
				b.set_voxel_f(-dens[i0 + size.x * y], x + PAD, y + PAD, z + PAD, VoxelBuffer.CHANNEL_SDF)
	for k in range(1, levels.size()):
		lo /= 2
		hi = (hi + Vector3i.ONE) / 2
		var prev: VoxelBuffer = levels[k - 1]
		var d: VoxelBuffer = levels[k]
		for z in range(lo.z, hi.z + 1):
			for x in range(lo.x, hi.x + 1):
				for y in range(lo.y, hi.y + 1):
					var q := Vector3i(x, y, z) * 2 + Vector3i.ONE * PAD
					if q.x < prev.get_size().x and q.y < prev.get_size().y and q.z < prev.get_size().z:
						d.set_voxel_f(prev.get_voxel_f(q.x, q.y, q.z, VoxelBuffer.CHANNEL_SDF),
							x + PAD, y + PAD, z + PAD, VoxelBuffer.CHANNEL_SDF)

## Поле 0,5 м в узлах коробки пещеры поменялось: пересчитать из ProtoTerrain.
func refresh_fine(t: ProtoTerrain, box: AABB) -> void:
	if fine.is_empty():
		return
	var lo := (Vector3i((box.position / VOXEL).floor()) - fine_o).clamp(Vector3i.ZERO, fine_n - Vector3i.ONE)
	var hi := (Vector3i((box.end / VOXEL).ceil()) - fine_o).clamp(Vector3i.ZERO, fine_n - Vector3i.ONE)
	for z in range(lo.z, hi.z + 1):
		for x in range(lo.x, hi.x + 1):
			var p := Vector3(fine_o + Vector3i(x, 0, z)) * VOXEL
			var h := t.surface_h(p.x, p.z)
			for y in range(lo.y, hi.y + 1):
				fine[x + fine_n.x * (y + fine_n.y * z)] = t.density(p.x, (fine_o.y + y) * VOXEL, p.z, h)

## LOD 0 в области (угол lo, n вокселей) — для вставки правки VoxelTool'ом.
func lod0_buffer(lo: Vector3i, n: Vector3i) -> VoxelBuffer:
	var b := _new_buffer(n)
	fill_lod0(b, lo)
	return b

## Поле 0,5 м коробки пещеры буфером (для сетки карты).
func fine_buffer() -> VoxelBuffer:
	var b := _new_buffer(fine_n)
	var f := PackedFloat32Array()
	f.resize(fine.size())
	var j := 0
	for z in fine_n.z:
		for x in fine_n.x:
			for y in fine_n.y:
				f[j] = -fine[x + fine_n.x * (y + fine_n.y * z)]
				j += 1
	b.set_channel_from_byte_array(VoxelBuffer.CHANNEL_SDF, f.to_byte_array())
	return b

static func sdf_mask() -> int:
	return 1 << VoxelBuffer.CHANNEL_SDF

func _get_used_channels_mask() -> int:
	return 1 << VoxelBuffer.CHANNEL_SDF

func _generate_block(out: VoxelBuffer, origin: Vector3i, lod: int) -> void:
	if lod == 0:
		fill_lod0(out, origin)
		return
	var src: VoxelBuffer = levels[mini(lod - 1, levels.size() - 1)]
	var o := origin / (1 << lod) + Vector3i.ONE * PAD
	var n := out.get_size()
	var ss := src.get_size()
	out.fill_f(1.0, VoxelBuffer.CHANNEL_SDF)
	var lo := o.clamp(Vector3i.ZERO, ss)
	var hi := (o + n).clamp(Vector3i.ZERO, ss)
	if lo.x >= hi.x or lo.y >= hi.y or lo.z >= hi.z:
		return
	out.copy_channel_from_area(src, lo, hi, lo - o, VoxelBuffer.CHANNEL_SDF)

## Блок LOD 0 (или любой буфер в вокселях LOD 0 с углом origin).
func fill_lod0(out: VoxelBuffer, origin: Vector3i) -> void:
	var dens := terrain.dens
	var n := out.get_size()
	var in_fine := not fine.is_empty() and origin.x < fine_o.x + fine_n.x and origin.x + n.x > fine_o.x \
		and origin.y < fine_o.y + fine_n.y and origin.y + n.y > fine_o.y \
		and origin.z < fine_o.z + fine_n.z and origin.z + n.z > fine_o.z
	if not in_fine:
		# Весь блок далеко от поверхности — одним значением.
		var lo := (origin / 2).clamp(Vector3i.ZERO, size - Vector3i.ONE)
		var hi := ((origin + n) / 2 + Vector3i.ONE).clamp(Vector3i.ZERO, size - Vector3i.ONE)
		var mn := INF
		var mx := -INF
		for z in range(lo.z, hi.z + 1):
			for x in range(lo.x, hi.x + 1):
				var i0 := x + size.x * size.y * z
				for y in range(lo.y, hi.y + 1):
					var d := dens[i0 + size.x * y]
					mn = minf(mn, d)
					mx = maxf(mx, d)
		if origin.y + n.y > size.y * 2 or origin.x < 0 or origin.z < 0 \
				or origin.x + n.x > (size.x - 1) * 2 or origin.z + n.z > (size.z - 1) * 2:
			mn = minf(mn, -2.5)
		if origin.y < 0:
			mx = maxf(mx, 2.5)
		if mn > 2.0 or mx < -2.0:
			out.fill_f(-clampf(mn if mn > 2.0 else mx, -2.5, 2.5), VoxelBuffer.CHANNEL_SDF)
			return
	var f := PackedFloat32Array()
	f.resize(n.x * n.y * n.z)
	var j := 0
	var sxy := size.x * size.y
	for z in n.z:
		var vz := origin.z + z
		var out_z := vz < 0 or vz > (size.z - 1) * 2
		var fz := clampf(vz * VOXEL, 0.0, size.z - 1.0)
		var z0 := mini(int(fz), size.z - 2)
		var tz := fz - z0
		for x in n.x:
			var vx := origin.x + x
			var out_xz := out_z or vx < 0 or vx > (size.x - 1) * 2
			var fx := clampf(vx * VOXEL, 0.0, size.x - 1.0)
			var x0 := mini(int(fx), size.x - 2)
			var tx := fx - x0
			var i00 := x0 + sxy * z0
			var fine_col := -1
			if in_fine and vx >= fine_o.x and vx < fine_o.x + fine_n.x and vz >= fine_o.z and vz < fine_o.z + fine_n.z:
				fine_col = (vx - fine_o.x) + fine_n.x * fine_n.y * (vz - fine_o.z)
			for y in n.y:
				var vy := origin.y + y
				var v: float
				if out_xz:
					v = -1.0
				elif fine_col >= 0 and vy >= fine_o.y and vy < fine_o.y + fine_n.y:
					v = fine[fine_col + fine_n.x * (vy - fine_o.y)]
				elif vy < 0:
					v = 1.0
				elif vy * VOXEL > size.y - 1.0:
					v = -1.0
				else:
					var fy := vy * VOXEL
					var y0 := mini(int(fy), size.y - 2)
					var ty := fy - y0
					var i := i00 + size.x * y0
					var c00 := lerpf(dens[i], dens[i + 1], tx)
					var c10 := lerpf(dens[i + size.x], dens[i + size.x + 1], tx)
					var c01 := lerpf(dens[i + sxy], dens[i + sxy + 1], tx)
					var c11 := lerpf(dens[i + sxy + size.x], dens[i + sxy + size.x + 1], tx)
					v = lerpf(lerpf(c00, c10, ty), lerpf(c01, c11, ty), tz)
				f[j] = -v
				j += 1
	if out.get_channel_depth(VoxelBuffer.CHANNEL_SDF) != VoxelBuffer.DEPTH_32_BIT:
		# Запрос VoxelTool'а мимо загруженных блоков — буфер формата по умолчанию.
		j = 0
		for z in n.z:
			for x in n.x:
				for y in n.y:
					out.set_voxel_f(f[j], x, y, z, VoxelBuffer.CHANNEL_SDF)
					j += 1
		return
	out.set_channel_from_byte_array(VoxelBuffer.CHANNEL_SDF, f.to_byte_array())
