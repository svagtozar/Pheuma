extends Node3D
## Витрина вариантов робота (к игре не подключена).
##   godot --path . res://proto/robots.tscn -- --shot=front|back|top|close:N|closeback:N|head:N|hand:N|far:N|gauge:N  [--toon] --screenshot=путь.png

var shot := "front"
var shot_path := ""
var _t := 0.0
const GAP := 1.6

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="): shot = a.substr(7)
		elif a.begins_with("--screenshot="): shot_path = a.substr(13)
		elif a == "--toon": RobotDesigns.toon = true
	_stage()
	var n := RobotDesigns.DESIGNS.size()
	for i in n:
		var d: String = RobotDesigns.DESIGNS[i]
		var x := (i - (n - 1) / 2.0) * GAP
		var ped := MeshInstance3D.new()
		var pc := CylinderMesh.new()
		pc.top_radius = 0.55
		pc.bottom_radius = 0.6
		pc.height = 0.08
		ped.mesh = pc
		var pm := StandardMaterial3D.new()
		pm.albedo_color = Color(0.18, 0.19, 0.22)
		pm.roughness = 0.6
		ped.material_override = pm
		ped.position = Vector3(x, 0.04, 0)
		add_child(ped)
		var r := RobotDesigns.build(d)
		r.position = Vector3(x, 0.08, 0)
		add_child(r)
		var l := Label3D.new()
		l.text = RobotDesigns.NAMES[d]
		l.font_size = 42
		l.pixel_size = 0.003
		l.position = Vector3(x, 0.02, 0.75)
		l.rotation = Vector3(-PI / 2.0 + 0.5, 0, 0)
		l.modulate = Color(0.9, 0.93, 1.0)
		l.outline_size = 8
		if shot == "back" or shot.begins_with("closeback:") or shot.begins_with("gauge:"):
			l.rotation.y = PI
			l.position.z = -0.75
		add_child(l)
	_camera(n)

func _stage() -> void:
	var env := Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.1, 0.12, 0.18)
	sm.sky_horizon_color = Color(0.32, 0.35, 0.42)
	sm.ground_horizon_color = Color(0.2, 0.21, 0.24)
	sm.ground_bottom_color = Color(0.08, 0.08, 0.1)
	sky.sky_material = sm
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var key := DirectionalLight3D.new()
	key.light_energy = 1.3
	key.shadow_enabled = true
	key.rotation_degrees = Vector3(-40, -30, 0)
	add_child(key)
	var rim := DirectionalLight3D.new()
	rim.light_energy = 0.8
	rim.light_color = Color(0.6, 0.8, 1.0)
	rim.rotation_degrees = Vector3(-25, 160, 0)
	add_child(rim)
	var floor := MeshInstance3D.new()
	var pl := PlaneMesh.new()
	pl.size = Vector2(40, 40)
	floor.mesh = pl
	var fm := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
void fragment() {
	vec3 w = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 g = abs(fract(w.xz * 2.0) - 0.5);
	float line = step(0.47, max(g.x, g.y));
	ALBEDO = mix(vec3(0.11, 0.115, 0.13), vec3(0.2, 0.22, 0.26), line);
	ROUGHNESS = 0.8;
}
"""
	fm.shader = sh
	floor.material_override = fm
	add_child(floor)

func _camera(n: int) -> void:
	var cam := Camera3D.new()
	cam.fov = 40.0
	add_child(cam)
	var width := (n - 1) * GAP
	if shot.begins_with("close:") or shot.begins_with("closeback:"):
		var back := shot.begins_with("closeback:")
		var i := int(shot.substr(shot.find(":") + 1))
		var x := (i - (n - 1) / 2.0) * GAP
		cam.position = Vector3(x + (-1.5 if back else 1.5), 1.35, -3.3 if back else 3.3)
		cam.look_at(Vector3(x, 0.92, 0))
		cam.fov = 36.0
	if shot.begins_with("far:"):
		# Игровая дистанция: от третьего лица, сзади-сверху, ~5 м.
		var fx := (int(shot.substr(4)) - (n - 1) / 2.0) * GAP
		cam.position = Vector3(fx + 1.4, 2.7, -4.3)
		cam.look_at(Vector3(fx, 0.8, 1.5))
		cam.fov = 62.0
	if shot.begins_with("hand:"):
		var kx := (int(shot.substr(5)) - (n - 1) / 2.0) * GAP
		cam.position = Vector3(kx + 0.75, 1.0, 0.5)
		cam.look_at(Vector3(kx + 0.3, 0.88, 0.08))
		cam.fov = 30.0
	if shot.begins_with("gauge:"):
		var gx := (int(shot.substr(6)) - (n - 1) / 2.0) * GAP
		cam.position = Vector3(gx + 0.75, 1.6, -0.9)
		cam.look_at(Vector3(gx + 0.2, 1.4, -0.3))
		cam.fov = 35.0
	if shot.begins_with("head:"):
		var hx := (int(shot.substr(5)) - (n - 1) / 2.0) * GAP
		cam.position = Vector3(hx + 0.35, 1.85, 1.0)
		cam.look_at(Vector3(hx, 1.7, 0))
		cam.fov = 40.0
	match shot:
		"front":
			cam.position = Vector3(1.5, 2.0, width * 0.95 + 1.0)
			cam.look_at(Vector3(0, 0.9, 0))
		"back":
			cam.position = Vector3(-1.5, 2.2, -(width * 0.95 + 1.0))
			cam.look_at(Vector3(0, 0.9, 0))
		"top":
			cam.position = Vector3(0, width * 1.1 + 2.0, width * 0.55)
			cam.look_at(Vector3(0, 0.5, 0))
	cam.current = true

func _process(dt: float) -> void:
	_t += dt
	if shot_path != "" and _t > 1.0:
		get_viewport().get_texture().get_image().save_png(shot_path)
		print("скриншот: ", shot_path)
		shot_path = ""
		get_tree().quit(0)
