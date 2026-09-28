class_name ProtoHorizon
extends RefCounted
## Прототип «планета, а не кусок»: рельеф вокруг участка до самого горизонта.
## Одна карта высот с шагом от 1 м у края участка до ~40 м вдали; высоты — тот же
## шум, что у участка (с плавным переходом у края), вдали — крупные хребты.
## Кривизна планеты запечена в вершины: провал d² / 2R от центра участка.

const REACH := 1400.0        # докуда тянется рельеф от края участка, м
const RADIUS := 1600.0       # видимый радиус кривизны, м

static func build(t: ProtoTerrain, radius := RADIUS) -> MeshInstance3D:
	var xs := _axis(0.0, float(t.sx))
	var zs := _axis(0.0, float(t.sz))
	var big := FastNoiseLite.new()
	big.seed = t.noise.seed + 91
	big.frequency = 0.0022
	big.fractal_octaves = 5
	big.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	var c := Vector2(t.sx, t.sz) * 0.5
	var r0 := c.x
	var nx := xs.size()
	var nz := zs.size()
	var hs := PackedFloat32Array()
	hs.resize(nx * nz)
	var flat := PackedFloat32Array()
	flat.resize(nx * nz)
	for iz in nz:
		for ix in nx:
			var x: float = xs[ix]
			var z: float = zs[iz]
			var out := _out_dist(x, z, t)
			var near := t.surface_h(x, z) if out < 30.0 else 0.0
			var far := t._raw_h(x, z) + big.get_noise_2d(x, z) * 38.0 * smoothstep(40.0, 420.0, out) \
				- 6.0 * smoothstep(20.0, 120.0, out)
			var h := lerpf(near, far, smoothstep(0.0, 30.0, out))
			flat[iz * nx + ix] = h
			var d := Vector2(x, z).distance_to(c)
			var dd := maxf(d, r0)
			hs[iz * nx + ix] = h - (dd * dd - r0 * r0) / (2.0 * radius)
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var norms := PackedVector3Array()
	verts.resize(nx * nz)
	cols.resize(nx * nz)
	norms.resize(nx * nz)
	for iz in nz:
		for ix in nx:
			var i := iz * nx + ix
			var x: float = xs[ix]
			var z: float = zs[iz]
			var ia := iz * nx + maxi(ix - 1, 0)
			var ib := iz * nx + mini(ix + 1, nx - 1)
			var ja := maxi(iz - 1, 0) * nx + ix
			var jb := mini(iz + 1, nz - 1) * nx + ix
			var dx: float = xs[mini(ix + 1, nx - 1)] - xs[maxi(ix - 1, 0)]
			var dz: float = zs[mini(iz + 1, nz - 1)] - zs[maxi(iz - 1, 0)]
			var n := Vector3(-(flat[ib] - flat[ia]) / dx, 1.0, -(flat[jb] - flat[ja]) / dz).normalized()
			verts[i] = Vector3(x, hs[i], z)
			norms[i] = n
			var p := Vector3(x, flat[i], z)
			var col := t._color_h(p, n, 0.0, flat[i])
			col.a = 1.0
			cols[i] = col
	var idx := PackedInt32Array()
	for iz in nz - 1:
		for ix in nx - 1:
			# Внутри участка — свой объёмный рельеф.
			if xs[ix] >= 1.0 and xs[ix + 1] <= t.sx - 1.0 and zs[iz] >= 1.0 and zs[iz + 1] <= t.sz - 1.0:
				continue
			var a := iz * nx + ix
			var b := a + 1
			var cc := a + nx
			var d := cc + 1
			idx.append_array([a, b, cc, b, d, cc])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mi := MeshInstance3D.new()
	mi.name = "horizon"
	mi.mesh = mesh
	mi.material_override = t.material()
	# Край участка чуть ниже рельефа участка, чтобы не было щели.
	mi.position.y = -0.15
	return mi

## Узлы по оси: внутри участка раз в 8 м, у края по 1 м, дальше шаг растёт.
static func _axis(lo: float, hi: float) -> PackedFloat32Array:
	var inner: Array = []
	var s := 1.0
	var d := 0.0
	while d < REACH:
		inner.append(d)
		d += s
		s = minf(s * 1.09, 40.0)
	var out := PackedFloat32Array()
	for i in range(inner.size() - 1, 0, -1):
		out.append(lo - inner[i])
	out.append(lo)
	for x in range(int(lo) + 1, int(hi), 8):
		out.append(float(x))
	out.append(hi - 1.0)
	out.append(hi)
	for i in range(1, inner.size()):
		out.append(hi + inner[i])
	return out

## Насколько точка за краем участка (0 — внутри).
static func _out_dist(x: float, z: float, t: ProtoTerrain) -> float:
	var q := Vector2(maxf(maxf(-x, x - t.sx), 0.0), maxf(maxf(-z, z - t.sz), 0.0))
	return q.length()
