class_name ProtoDeck
extends Node
## Облегчённая графика для Steam Deck (фича steamdeck в сборке или --deck).
##   Солнце: тени только до 40 м (вместо 100).
##   Мелочь (меньше 0,3 м) не отбрасывает тени, небольшие предметы дальше 45 м
##   не рисуются (запас 5 м, чтобы не мигали на границе).
##   Пещера: всё, что лежит в зале под толщей породы, — на отдельном слое;
##   камера рисует его, только когда подошла к пещере, солнце его не освещает
##   (там и так тень). Снаружи эти десятки кристаллов и натёков не рисуются.
##   Частиц в воздухе вдвое меньше.
## Узел следит за камерой (ProtoDeck.apply добавляет его в корень сцены).

static var active := false

const CAVE_LAYER := 1 << 1       # слой 2
const SMALL_SHADOW := 0.3        # м: меньше — без тени
const FAR_SMALL := 45.0          # м: дальше небольшие предметы не рисуются
const SMALL_FAR_SIZE := 2.0      # м: «небольшой» предмет для FAR_SMALL

var cam: Camera3D
var near_cave := AABB()
var hidden := 0                  # сколько узлов на слое пещеры (для отчёта)

static func apply(root: Node3D, terrain: ProtoTerrain, cam: Camera3D, sun: DirectionalLight3D, skip: Array = []) -> ProtoDeck:
	if sun != null:
		# Четыре полосы (с двумя на площадке «рябь»), но только до 40 м вместо 100:
		# дальние предметы в карту теней не рисуются, а ближние тени чётче.
		sun.directional_shadow_max_distance = 40.0
		sun.light_cull_mask &= ~CAVE_LAYER
	var d := ProtoDeck.new()
	d.name = "deck"
	d.cam = cam
	d.near_cave = terrain.cave_box.grow(4.0)
	var stack: Array = root.get_children()
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if skip.has(n):
			continue
		stack.append_array(n.get_children())
		if n is CPUParticles3D:
			(n as CPUParticles3D).amount = maxi(1, (n as CPUParticles3D).amount / 2)
		var gi := n as GeometryInstance3D
		if gi == null:
			continue
		var box := gi.global_transform * gi.get_aabb()
		var size := box.get_longest_axis_size()
		var c := box.get_center()
		if terrain.cave_box.encloses(box) and terrain.surface_h(c.x, c.z) - c.y > 2.0:
			gi.layers = CAVE_LAYER
			d.hidden += 1
			continue
		if size < SMALL_SHADOW:
			gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if size < SMALL_FAR_SIZE and gi.visibility_range_end == 0.0:
			gi.visibility_range_end = FAR_SMALL
			gi.visibility_range_end_margin = 5.0
			gi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
	root.add_child(d)
	d._process(0.0)
	return d

func _process(_dt: float) -> void:
	if cam == null:
		return
	var inside := near_cave.has_point(cam.global_position)
	if inside:
		cam.cull_mask |= CAVE_LAYER
	else:
		cam.cull_mask &= ~CAVE_LAYER
