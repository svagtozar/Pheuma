extends Node3D
## Витрина машин завода (ProtoPneumaticsView.build_part — как в игре) в ряд.
##   godot --path . res://proto/machine_gallery.tscn -- [--set=key|process|goals] [--planet=volcanic|frozen|rock] --screenshot=путь.png
## key — машины 3D-завода, process — машины обработки, goals — пушка, лаборатория
## и сооружения целей.

const SETS := {
	"key": ["intake", "pump", "crusher", "furnace", "tank", "centrifuge"],
	"process": ["filter", "condenser", "treater", "compressor", "distiller", "magnet_sep",
		"electrolyzer", "sinter", "irradiator", "cryochamber", "resonator", "loom"],
	"goals": ["pipe", "cannon", "lab", "decompressor", "launch_silo", "beacon", "dome"],
}
const PLANETS := {
	"volcanic": [Color(0.8, 0.5, 0.25), ["metallic"], Color(0.62, 0.42, 0.3), Color(0.55, 0.45, 0.3)],
	"frozen": [Color(0.55, 0.6, 0.68), ["metallic"], Color(0.72, 0.78, 0.86), Color(0.5, 0.58, 0.7)],
	"rock": [Color(0.45, 0.42, 0.4), ["porous"], Color(0.4, 0.38, 0.33), Color(0.45, 0.5, 0.55)],
}

var set_name := "key"
var planet := "volcanic"
var shot_path := ""
var _t := 0.0

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--set="): set_name = a.substr(6)
		elif a.begins_with("--planet="): planet = a.substr(9)
		elif a.begins_with("--screenshot="): shot_path = a.substr(13)
	var pl: Array = PLANETS[planet]
	var sub := Substance.new("hull", "Корпус", pl[1])
	sub.color = pl[0]
	var ground := MeshInstance3D.new()
	var gm := BoxMesh.new()
	gm.size = Vector3(400, 1, 400)
	ground.mesh = gm
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = pl[2]
	gmat.roughness = 1.0
	ground.material_override = gmat
	ground.position = Vector3(0, -0.5, 0)
	add_child(ground)
	var kinds: Array = SETS[set_name]
	var per_row := 6
	var rows := ceili(kinds.size() / float(per_row))
	for i in kinds.size():
		var k: String = kinds[i]
		var n := ProtoPneumaticsView.build_part(k, sub, 1, [0, 2] if k == "pipe" else [])
		var row := i / per_row
		var in_row := mini(per_row, kinds.size() - row * per_row)
		n.position = Vector3((i % per_row - (in_row - 1) / 2.0) * 2.7, 0, (row - (rows - 1) / 2.0) * 4.4)
		add_child(n)
		var l := Label3D.new()
		l.text = ProtoPneumatics.KINDS[k].n
		l.font_size = 36
		l.pixel_size = 0.006
		l.outline_size = 10
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.position = n.position + Vector3(0, 0.35, 1.35)
		add_child(l)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42, -30, 0)
	sun.light_energy = 1.0
	sun.shadow_enabled = true
	add_child(sun)
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = pl[3].darkened(0.45)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = pl[3].lerp(Color.WHITE, 0.4)
	env.ambient_light_energy = 0.35
	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	we.environment = env
	add_child(we)
	var cam := Camera3D.new()
	cam.fov = 36.0
	add_child(cam)
	cam.look_at_from_position(Vector3(0, 4.0 + rows * 2.2, 10.0 + rows * 4.0), Vector3(0, 0.6, 0))
	var cap := Label.new()
	cap.text = "Машины завода · %s" % planet
	cap.position = Vector2(20, 14)
	cap.add_theme_font_size_override("font_size", 34)
	cap.add_theme_color_override("font_outline_color", Color.BLACK)
	cap.add_theme_constant_override("outline_size", 8)
	var layer := CanvasLayer.new()
	layer.add_child(cap)
	add_child(layer)

func _process(dt: float) -> void:
	_t += dt
	if shot_path != "" and _t > 0.8:
		get_viewport().get_texture().get_image().save_png(shot_path)
		print("Кадр: ", shot_path)
		get_tree().quit()
