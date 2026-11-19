extends Node3D
## Every plant of Flora, one beside another on a patch of ground under the game's sun, to look at them (and a screenshot of it):
##   godot --path . tools/flora_gallery.tscn -- --shot=/tmp/plants.png [--keys=oak0,saguaro0] [--cols=6] [--cam=x,y,z,tx,ty,tz]
##   (a window, or xvfb with --rendering-driver vulkan, is needed to see anything)
## The plants stand SPACING metres apart in rows of --cols (default 8); the camera looks at the middle of them from the front.

const SPACING := 9.0

var _frames := 0
var _shot := ""


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var keys: Array = Flora.PROPS.keys()
	var cols := 8
	var cam_arg := ""
	for a in args:
		if a.begins_with("--shot="):
			_shot = a.substr(7)
		if a.begins_with("--keys="):
			keys = a.substr(7).split(",")
		if a.begins_with("--cols="):
			cols = int(a.substr(7))
		if a.begins_with("--cam="):
			cam_arg = a.substr(6)
	# the sky, the sun and the ground, as the game has them at noon
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color("#2b5c96")
	sm.sky_horizon_color = Color("#d9d2c2")
	sm.sky_curve = 0.11
	sm.ground_horizon_color = Color("#c4b69c")
	sm.ground_bottom_color = Color("#3b4a2b")
	sm.ground_curve = 0.06
	sky.sky_material = sm
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 0.9
	env.ambient_light_energy = 0.75
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.05
	env.tonemap_white = 6.0
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.08
	env.adjustment_saturation = 1.12
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.light_energy = 1.45
	sun.light_color = Color("#fffaf0")
	sun.rotation_degrees = Vector3(-50.0, -35.0, 0.0)
	sun.shadow_enabled = true
	add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(400, 400)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color("#5d7c33")
	gm.roughness = 1.0
	ground.material_override = gm
	add_child(ground)
	var n := keys.size()
	var rows := ceili(float(n) / float(cols))
	for i in n:
		var key: String = keys[i]
		var mi := MeshInstance3D.new()
		mi.mesh = Flora.mesh(key)
		mi.material_override = Flora.material(Flora.thin(key))
		var cx := float(i % cols) - float(cols - 1) * 0.5
		var rz := float(i / cols) - float(rows - 1) * 0.5
		mi.position = Vector3(cx * SPACING, 0.0, rz * SPACING * 1.2)
		if key.begins_with("tuft") or key == "tall" or key == "fern" or key == "agave":
			mi.scale = Vector3(2.5, 2.5, 2.5)  # (small plants: bigger, to see them)
		add_child(mi)
		var tris := 0
		var m: ArrayMesh = Flora.mesh(key)
		for s in m.get_surface_count():
			tris += int(m.surface_get_array_len(s) / 3)
		print("%-12s %5d triangles" % [key, tris])
	var cam := Camera3D.new()
	add_child(cam)
	var w := float(cols) * SPACING
	cam.position = Vector3(0.0, 5.0 + float(rows) * 3.0, w * 0.62 + float(rows) * 6.0)
	var target := Vector3(0.0, 3.0, 0.0)
	if cam_arg != "":
		var c := cam_arg.split(",")
		cam.position = Vector3(float(c[0]), float(c[1]), float(c[2]))
		target = Vector3(float(c[3]), float(c[4]), float(c[5]))
	cam.look_at(target)
	cam.fov = 60.0
	cam.far = 800.0
	cam.current = true


func _process(_dt: float) -> void:
	_frames += 1
	if _shot != "" and _frames == 6:
		get_viewport().get_texture().get_image().save_png(_shot)
		get_tree().quit()
