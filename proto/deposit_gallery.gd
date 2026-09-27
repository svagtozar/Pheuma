extends Node3D
## Витрина форм залежей (ProtoDeposit): все формы в ряд на одной площадке.
##   godot --path . res://proto/deposit_gallery.tscn -- --look=plain|frozen|volcanic|heavy|light|seismic --screenshot=путь.png
## Вещества — из тегов, как в игре: у каждой формы свой характерный набор.

const SAMPLES := [
	["druse", ["crystalline", "brittle"]],
	["vein", ["metallic", "conductive"]],
	["nodules", ["dense", "magnetic"]],
	["strata", ["brittle", "insulating"]],
	["crust", ["acidic", "oxidizer"]],
	["crust", ["alkaline", "hygroscopic"]],
	["fibers", ["fibrous", "insulating"]],
	["resin", ["organic", "sticky"]],
	["boulders", ["porous", "hygroscopic"]],
	["floaters", ["antigravitic", "luminous"]],
]

var look_name := "plain"
var shot_path := ""
var _t := 0.0

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--look="): look_name = a.substr(7)
		elif a.begins_with("--screenshot="): shot_path = a.substr(13)
	var look := {"frost": look_name == "frozen", "hot": look_name == "volcanic", "glow": 0.0,
		"squash": {"heavy": 0.72, "light": 1.3}.get(look_name, 1.0),
		"tilt": 0.5 if look_name == "seismic" else 0.0,
		"habit": {"frozen": "needle", "volcanic": "blade", "heavy": "cube", "seismic": "shard"}.get(look_name, "prism")}
	var ground_col: Color = {"frozen": Color(0.45, 0.5, 0.58), "volcanic": Color(0.2, 0.17, 0.16)}.get(look_name, Color(0.42, 0.37, 0.33))
	var ground := MeshInstance3D.new()
	var gm := BoxMesh.new()
	gm.size = Vector3(40, 1, 20)
	ground.mesh = gm
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = ground_col
	gmat.roughness = 1.0
	ground.material_override = gmat
	ground.position = Vector3(0, -0.5, 0)
	add_child(ground)
	var rng := RandomNumberGenerator.new()
	for i in SAMPLES.size():
		var form: String = SAMPLES[i][0]
		var tags: Array = SAMPLES[i][1]
		var s := Substance.new("g%d" % i, form, tags)
		rng.seed = 100 + i
		var n := ProtoDeposit.build(s, form, 1.0, rng, look)
		var col := i % 5
		var row := i / 5
		n.position = Vector3((col - 2) * 2.7, 0, row * 3.0 - 1.5)
		add_child(n)
		var l := Label3D.new()
		l.text = "%s\n%s" % [ProtoDeposit.NAMES[form], ", ".join(PackedStringArray(tags.map(func(t): return MaterialTags.display(t))))]
		l.font_size = 40
		l.pixel_size = 0.006
		l.outline_size = 10
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.font_size = 30
		l.position = n.position + Vector3(0, 0.35, 1.3)
		add_child(l)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -35, 0)
	sun.light_energy = 1.0
	sun.shadow_enabled = true
	add_child(sun)
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.12, 0.13, 0.16)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.58, 0.65)
	env.ambient_light_energy = 0.45
	env.glow_enabled = true
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	we.environment = env
	add_child(we)
	var cam := Camera3D.new()
	cam.fov = 40.0
	add_child(cam)
	cam.look_at_from_position(Vector3(0, 7.0, 11.0), Vector3(0, 0.1, 0.3))
	var cap := Label.new()
	cap.text = "Формы залежей · планета: %s" % look_name
	cap.position = Vector2(16, 12)
	cap.add_theme_font_size_override("font_size", 22)
	var layer := CanvasLayer.new()
	layer.add_child(cap)
	add_child(layer)

func _process(dt: float) -> void:
	_t += dt
	if shot_path != "" and _t > 0.6:
		get_viewport().get_texture().get_image().save_png(shot_path)
		print("Кадр: ", shot_path)
		get_tree().quit()
