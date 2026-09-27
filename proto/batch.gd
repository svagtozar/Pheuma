class_name ProtoBatch
extends RefCounted
## Склейка неподвижных деталей: у каждого узла его безымянные сетки-листья с
## одним материалом становятся одной сеткой. Узлы-шарниры (плечо, палец,
## диафрагма) остаются и двигают склейку целиком, так что анимация та же, а
## вызовов отрисовки (и в тенях тоже) — в разы меньше. Не трогаем сетки с
## именем, метаданными, детьми или скрытые: их ищет и переключает код.

## Возвращает, сколько сеток стало меньше.
static func merge_children(root: Node) -> int:
	var saved := 0
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Node3D:
			saved += _merge_leaves(n)
		stack.append_array(n.get_children())
	return saved

static func _merge_leaves(n: Node3D) -> int:
	var groups := {}
	for c in n.get_children():
		var mi := c as MeshInstance3D
		if mi == null or not _leaf(mi):
			continue
		var k := "%d/%d/%d" % [mi.material_override.get_instance_id(), mi.cast_shadow, mi.layers]
		if not groups.has(k):
			groups[k] = []
		groups[k].append(mi)
	var saved := 0
	for k in groups:
		var list: Array = groups[k]
		if list.size() < 2:
			continue
		var parts := []
		for mi: MeshInstance3D in list:
			parts.append([mi.mesh, mi.transform])
		var first: MeshInstance3D = list[0]
		var out := MeshInstance3D.new()
		out.mesh = merged(parts)
		out.material_override = first.material_override
		out.cast_shadow = first.cast_shadow
		out.layers = first.layers
		n.add_child(out)
		n.move_child(out, first.get_index())
		for mi: MeshInstance3D in list:
			n.remove_child(mi)
			mi.free()
		saved += list.size() - 1
	return saved

## Сетки parts ([[Mesh, Transform3D], ...]) одной сеткой: позиция, нормаль, цвет
## вершины и UV (чего у сетки нет — белый цвет и нулевой UV). Зеркальные
## преобразования разворачивают треугольники, чтобы не пропали лицевые грани.
static func merged(parts: Array) -> ArrayMesh:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	for pt in parts:
		var m: Mesh = pt[0]
		var xf: Transform3D = pt[1]
		var nb := xf.basis.inverse().transposed()
		var flip := xf.basis.determinant() < 0.0
		for si in m.get_surface_count():
			if m is ArrayMesh and (m as ArrayMesh).surface_get_primitive_type(si) != Mesh.PRIMITIVE_TRIANGLES:
				continue
			var a := m.surface_get_arrays(si)
			var sv: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
			var sn = a[Mesh.ARRAY_NORMAL]
			var sc = a[Mesh.ARRAY_COLOR]
			var su = a[Mesh.ARRAY_TEX_UV]
			var si_ = a[Mesh.ARRAY_INDEX]
			var base := verts.size()
			for i in sv.size():
				verts.append(xf * sv[i])
				norms.append((nb * (sn[i] as Vector3)).normalized() if sn != null and not sn.is_empty() else Vector3.UP)
				cols.append(sc[i] if sc != null and not sc.is_empty() else Color.WHITE)
				uvs.append(su[i] if su != null and not su.is_empty() else Vector2.ZERO)
			var tri: PackedInt32Array = si_ if si_ != null and not si_.is_empty() else PackedInt32Array(range(sv.size()))
			for t in range(0, tri.size() - 2, 3):
				if flip:
					idx.append_array([base + tri[t], base + tri[t + 2], base + tri[t + 1]])
				else:
					idx.append_array([base + tri[t], base + tri[t + 1], base + tri[t + 2]])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = idx
	var out := ArrayMesh.new()
	if not verts.is_empty():
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return out

static func _leaf(mi: MeshInstance3D) -> bool:
	return mi.mesh != null and mi.material_override != null and mi.visible \
		and mi.get_child_count() == 0 and String(mi.name).begins_with("@") \
		and mi.get_meta_list().is_empty() and _no_overrides(mi)

static func _no_overrides(mi: MeshInstance3D) -> bool:
	for i in mi.get_surface_override_material_count():
		if mi.get_surface_override_material(i) != null:
			return false
	return true
