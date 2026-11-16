extends Node3D
## The LED price rows (LedBoard, shaders/led_board.gdshader), looked at: a wall of rows showing prices from nought to
## 999.99 in the figures the game's boards use, shot from near, from middle distance and from far off, by day and by night.
##   xvfb-run -a godot --path . --rendering-method mobile --rendering-driver vulkan tools/led_test.tscn -- --out=/tmp/led
## writes /tmp/led_near.png, _mid.png, _far.png and _night.png. (--checks only runs the figure checks, headless.)

var _out := "/tmp/led"
var _rows: Array[MeshInstance3D] = []
var _cam: Camera3D
var _env: Environment
var _sun: DirectionalLight3D


func _ready() -> void:
	var checks := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
		if a == "--checks":
			checks = true
	if checks:
		_run_checks()
		return
	_env = Environment.new()
	_env.background_mode = Environment.BG_COLOR
	_env.background_color = Color("#7fa6cf")
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.ambient_light_color = Color("#aab6c4")
	_env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_env.glow_enabled = true
	_env.glow_intensity = 0.8
	_env.glow_hdr_threshold = 1.0
	var we := WorldEnvironment.new()
	we.environment = _env
	add_child(we)
	_sun = DirectionalLight3D.new()
	_sun.rotation_degrees = Vector3(-50, 30, 0)
	add_child(_sun)
	# a dark board for the rows to sit on, and the rows: three rows to a column, two columns
	var prices := [3.49, 4.09, 18.49, 0.0, 9.99, 123.45]
	var plate := MeshInstance3D.new()
	var pq := QuadMesh.new()
	pq.size = Vector2(7.6, 3.8)
	plate.mesh = pq
	var pm := StandardMaterial3D.new()
	pm.albedo_color = Color("#2b2f36")
	plate.material_override = pm
	plate.position = Vector3(0, 0, -0.02)
	add_child(plate)
	for i in prices.size():
		var col := i / 3
		var r := i % 3
		var row := LedBoard.row(0.86, Vector3(-1.95 + col * 3.9, 1.2 - r * 1.2, 0.0))
		LedBoard.set_price(row, prices[i])
		add_child(row)
		_rows.append(row)
	_cam = Camera3D.new()
	_cam.fov = 38.0
	add_child(_cam)
	_shoot()


func _shoot() -> void:
	var shots := [["near", Vector3(0, 0, 7.5), 0.0], ["mid", Vector3(1.0, 0.2, 40.0), 0.0], ["far", Vector3(3.0, 0.5, 220.0), 0.0], ["night", Vector3(0, 0, 7.5), 1.0]]
	for s in shots:
		var k: float = s[2]
		_env.background_color = Color("#7fa6cf").lerp(Color("#050912"), k)
		_env.ambient_light_color = Color("#aab6c4").lerp(Color("#101624"), k)
		_sun.light_energy = lerpf(1.0, 0.0, k)
		for row in _rows:
			LedBoard.set_night(row, k)
		_cam.position = s[1]
		_cam.look_at(Vector3(0, 0, 0))
		for f in 4:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png("%s_%s.png" % [_out, s[0]])
		print("shot ", s[0])
	get_tree().quit()


var _fails := 0


func _check(ok: bool, what: String) -> void:
	if not ok:
		_fails += 1
		print("  FAIL: ", what)


## The figures a price puts in the five cells: right-aligned, no leading zeros, 999.99 at most.
func _run_checks() -> void:
	var cases := {
		3.49: [10, 10, 3, 4, 9],
		0.0: [10, 10, 0, 0, 0],
		18.49: [10, 1, 8, 4, 9],
		123.45: [1, 2, 3, 4, 5],
		999.99: [9, 9, 9, 9, 9],
		5000.0: [9, 9, 9, 9, 9],
		-4.0: [10, 10, 0, 0, 0],
		4.096: [10, 10, 4, 1, 0],
	}
	for p in cases:
		var got := LedBoard.cells_for(p)
		var want: Array = cases[p]
		var ok := got.size() == 5
		for i in 5:
			ok = ok and int(got[i]) == int(want[i])
		_check(ok, "price %s shows as %s (wanted %s)" % [p, got, want])
	print("== %d checks failed" % _fails)
	get_tree().quit(1 if _fails > 0 else 0)
