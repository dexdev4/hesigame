class_name GarageScene
extends Node3D
## The main menu: your car on a turntable in a lit workshop. It lives on its
## own render layer (LAYER) with its own camera and lights, so the highway
## world never shows through or lights it. Drag to turn the camera round the
## car; left alone it drifts slowly round by itself.

const LAYER := 2           # render layer bit value (layer 2)
const ORIGIN := Vector3(0, -400, 0)  # well under the highway's ground

var cam: Camera3D
var car: CarModel
var _table: Node3D
var _yaw := 0.6
var _pitch := 0.2
var _dist := 7.0
var _drag_t := 0.0  # seconds since the last drag (auto-spin waits a little)
var _car_len := 4.4
var _car_h := 1.3
var active := false


func _ready() -> void:
	position = ORIGIN
	_build_room()
	cam = Camera3D.new()
	cam.fov = 42.0
	cam.cull_mask = LAYER
	cam.near = 0.05
	cam.far = 60.0
	# its own lighting: warm indoor ambient, no outdoor sky or haze
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#0d0f12")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#d9d4cc")
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.1
	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.glow_hdr_threshold = 1.2
	cam.environment = env
	add_child(cam)
	_update_cam()


func set_active(on: bool) -> void:
	active = on
	visible = on
	cam.current = on


## Show this car (a Data.CARS entry) with the given paint and style.
func set_car(c: Dictionary, color: Color, style: Dictionary) -> void:
	if car:
		car.queue_free()
	car = CarModel.new()
	car.build(c.shape, color, Color("#b5322a"), style)
	car.force_detail()
	var sh: Dictionary = Data.SHAPES[c.shape]
	_car_len = sh.l
	_car_h = sh.t
	car.position = Vector3(0, 0.06, sh.l / 2.0)  # centred on the turntable (cars face -z from the rear bumper)
	_table.add_child(car)
	car.build_interior()
	_set_layers(car)


func orbit(dx: float, dy: float) -> void:
	_yaw -= dx * 0.008
	_pitch = clampf(_pitch + dy * 0.004, 0.03, 0.75)
	_drag_t = 0.0


func _process(delta: float) -> void:
	if not active:
		return
	_drag_t += delta
	if _drag_t > 2.5:
		_yaw += delta * 0.12  # a slow walk round the car
	var vp := get_viewport().get_visible_rect().size
	var portrait := vp.y > vp.x
	# portrait: fit the car's length across the narrow screen; landscape: by height
	cam.keep_aspect = Camera3D.KEEP_WIDTH if portrait else Camera3D.KEEP_HEIGHT
	cam.fov = 64.0 if portrait else 40.0
	var want := _car_len * (0.9 if portrait else 1.45) + 1.8
	_dist = lerpf(_dist, want, minf(1.0, delta * 3.0))
	# keep the car clear of the menu panels: above the bottom sheet in
	# portrait, left of the side panel in landscape
	cam.v_offset = -1.75 if portrait else -0.15
	cam.h_offset = 0.0 if portrait else _dist * 0.2
	_update_cam()


func _update_cam() -> void:
	var aim := Vector3(0, _car_h * 0.45, 0)
	var off := Vector3(sin(_yaw) * cos(_pitch), sin(_pitch), cos(_yaw) * cos(_pitch)) * _dist
	cam.position = aim + off
	cam.look_at(global_position + aim)


# ---------------------------------------------------------------- the room

func _mat(c: Color, rough := 0.7, metal := 0.0, glow := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	if glow > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = glow
	return m


func _box(parent: Node3D, pos: Vector3, size: Vector3, m: Material, rot := Vector3.ZERO, shadow := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = m
	mi.position = pos
	mi.rotation = rot
	mi.layers = LAYER
	if not shadow:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


func _cyl(parent: Node3D, pos: Vector3, r: float, h: float, m: Material, rot := Vector3.ZERO, segs := 32) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = h
	cm.radial_segments = segs
	mi.mesh = cm
	mi.material_override = m
	mi.position = pos
	mi.rotation = rot
	mi.layers = LAYER
	parent.add_child(mi)
	return mi


func _label(parent: Node3D, text: String, pos: Vector3, size: int, c: Color, rot := Vector3.ZERO, px := 0.01) -> void:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = px
	l.modulate = c
	l.outline_size = 0
	l.position = pos
	l.rotation = rot
	l.layers = LAYER
	l.shaded = false
	l.double_sided = false
	parent.add_child(l)


func _build_room() -> void:
	var W := 16.0   # room width (x)
	var D := 14.0   # depth (z)
	var H := 5.2
	var floor_m := _mat(Color("#2b2e33"), 0.28, 0.0)
	var wall_m := _mat(Color("#c9ccd0"), 0.85)
	var wall_low := _mat(Color("#3a3f46"), 0.7)
	var amber := _mat(Color("#f5b52e"), 0.5)
	var dark := _mat(Color("#16181b"), 0.6)
	var steel := _mat(Color("#9aa0a6"), 0.35, 0.8)
	var red := _mat(Color("#b5322a"), 0.45, 0.1)
	var rubber := _mat(Color("#141516"), 0.9)

	# floor, walls, ceiling
	_box(self, Vector3(0, -0.05, 0), Vector3(W, 0.1, D), floor_m)
	_box(self, Vector3(0, H + 0.05, 0), Vector3(W, 0.1, D), _mat(Color("#55595f"), 0.9))
	for s in [-1.0, 1.0]:
		_box(self, Vector3(s * W / 2.0, H / 2.0, 0), Vector3(0.2, H, D), wall_m)
		_box(self, Vector3(s * (W / 2.0 - 0.11), 0.6, 0), Vector3(0.04, 1.2, D), wall_low)  # dark lower band
		_box(self, Vector3(s * (W / 2.0 - 0.12), 1.24, 0), Vector3(0.04, 0.08, D), amber)   # amber stripe
	_box(self, Vector3(0, H / 2.0, -D / 2.0), Vector3(W, H, 0.2), wall_m)
	_box(self, Vector3(0, 0.6, -D / 2.0 + 0.11), Vector3(W, 1.2, 0.04), wall_low)
	_box(self, Vector3(0, 1.24, -D / 2.0 + 0.12), Vector3(W, 0.08, 0.04), amber)
	_box(self, Vector3(0, H / 2.0, D / 2.0), Vector3(W, H, 0.2), wall_m)

	# roller door on the back wall, with ribbed slats
	var door := Node3D.new()
	door.position = Vector3(0, 0, -D / 2.0 + 0.14)
	add_child(door)
	_box(door, Vector3(0, 1.9, 0), Vector3(5.6, 3.8, 0.04), _mat(Color("#8d939a"), 0.5, 0.5))
	for k in 19:
		_box(door, Vector3(0, 0.1 + k * 0.2, 0.03), Vector3(5.5, 0.03, 0.03), _mat(Color("#6c7177"), 0.5, 0.5))
	for s in [-1.0, 1.0]:
		_box(door, Vector3(s * 2.9, 1.95, 0.05), Vector3(0.18, 3.9, 0.1), amber)
	_box(door, Vector3(0, 3.95, 0.05), Vector3(6.0, 0.25, 0.14), dark)

	# sign over the door
	_box(self, Vector3(0, 4.55, -D / 2.0 + 0.16), Vector3(4.6, 0.7, 0.06), _mat(Color("#14563a"), 0.6))
	_label(self, "REDLINE RUSH", Vector3(0, 4.56, -D / 2.0 + 0.2), 96, Color("#f3f5ef"), Vector3.ZERO, 0.0075)
	_label(self, "SERVICE · TUNING · PAINT", Vector3(0, 4.3, -D / 2.0 + 0.2), 40, Color("#f5b52e"), Vector3.ZERO, 0.006)

	# turntable with an amber ring
	_table = Node3D.new()
	add_child(_table)
	_cyl(self, Vector3(0, 0.02, 0), 3.3, 0.06, _mat(Color("#1d2024"), 0.35, 0.4), Vector3.ZERO, 64)
	_cyl(self, Vector3(0, 0.025, 0), 3.42, 0.05, amber, Vector3.ZERO, 64)
	_cyl(self, Vector3(0, 0.05, 0), 3.2, 0.02, _mat(Color("#25292e"), 0.3, 0.5), Vector3.ZERO, 64)
	# painted bay lines on the floor
	for s in [-1.0, 1.0]:
		_box(self, Vector3(s * 4.2, 0.002, 0), Vector3(0.12, 0.01, 9.0), amber, Vector3.ZERO, false)
	_box(self, Vector3(0, 0.002, 4.5), Vector3(8.5, 0.01, 0.12), amber, Vector3.ZERO, false)

	# tool chest and workbench along the left wall
	var bench := Node3D.new()
	bench.position = Vector3(-W / 2.0 + 0.6, 0, -2.5)
	add_child(bench)
	_box(bench, Vector3(0, 0.55, 0), Vector3(0.75, 1.1, 1.6), red)
	for k in 6:
		_box(bench, Vector3(0.38, 0.15 + k * 0.17, 0), Vector3(0.02, 0.13, 1.5), _mat(Color("#9b2a23"), 0.45))
		_box(bench, Vector3(0.4, 0.15 + k * 0.17, 0), Vector3(0.02, 0.02, 0.5), steel)
	_box(bench, Vector3(0, 1.12, 0), Vector3(0.78, 0.04, 1.65), dark)
	_box(bench, Vector3(0, 0.45, 2.1), Vector3(0.8, 0.06, 2.2), _mat(Color("#7a5a3a"), 0.8))  # bench top
	for z in [1.1, 3.1]:
		_box(bench, Vector3(0, 0.22, z), Vector3(0.7, 0.44, 0.06), dark)
	_box(bench, Vector3(-0.27, 1.7, 2.1), Vector3(0.04, 1.6, 2.2), _mat(Color("#d8d2c4"), 0.9))  # pegboard
	for k in 7:
		_box(bench, Vector3(-0.22, 1.35 + (k % 3) * 0.4, 1.3 + k * 0.26), Vector3(0.04, 0.32, 0.05), steel)

	# stacked tyres and an oil drum on the right
	for k in 4:
		var tz := -3.6 + (k % 2) * 0.05
		_cyl(self, Vector3(W / 2.0 - 0.7, 0.13 + k * 0.25, tz), 0.36, 0.24, rubber)
		_cyl(self, Vector3(W / 2.0 - 0.7, 0.13 + k * 0.25, tz), 0.22, 0.25, dark)
	for k in 3:
		_cyl(self, Vector3(W / 2.0 - 0.7, 0.13 + k * 0.25, -2.6), 0.36, 0.24, rubber)
	_cyl(self, Vector3(W / 2.0 - 0.8, 0.45, 2.6), 0.3, 0.9, _mat(Color("#1f4e8c"), 0.5, 0.3))
	_cyl(self, Vector3(W / 2.0 - 1.5, 0.45, 2.9), 0.3, 0.9, red)

	# a two-post lift standing at the back right
	for s in [-1.0, 1.0]:
		_box(self, Vector3(W / 2.0 - 3.4 + s * 1.5, 1.9, -D / 2.0 + 1.6), Vector3(0.3, 3.8, 0.3), _mat(Color("#2f6fd6"), 0.5, 0.2))
	_box(self, Vector3(W / 2.0 - 3.4, 3.85, -D / 2.0 + 1.6), Vector3(3.3, 0.18, 0.3), _mat(Color("#2f6fd6"), 0.5, 0.2))

	# ceiling light strips and the lights themselves
	for x in [-3.0, 0.0, 3.0]:
		_box(self, Vector3(x, H - 0.05, 0), Vector3(0.25, 0.05, 6.5), _mat(Color("#fffaf0"), 0.5, 0.0, 3.0), Vector3.ZERO, false)
	for p in [Vector3(-3.2, H - 0.3, 2.6), Vector3(3.2, H - 0.3, 2.6), Vector3(0.0, H - 0.3, -3.0)]:
		var sp := SpotLight3D.new()
		sp.position = p
		sp.light_color = Color("#fff4e2")
		sp.light_energy = 6.0
		sp.spot_range = 12.0
		sp.spot_angle = 48.0
		sp.spot_attenuation = 0.8
		sp.shadow_enabled = true
		sp.light_cull_mask = LAYER
		add_child(sp)
		sp.look_at(global_position + Vector3(0, 0.5, 0))
	var fill := OmniLight3D.new()
	fill.position = Vector3(0, 3.2, 4.0)
	fill.light_energy = 1.2
	fill.omni_range = 14.0
	fill.light_cull_mask = LAYER
	add_child(fill)
	var back := OmniLight3D.new()
	back.position = Vector3(0, 2.5, -5.0)
	back.light_energy = 0.8
	back.light_color = Color("#cfe0ff")
	back.omni_range = 10.0
	back.light_cull_mask = LAYER
	add_child(back)


func _set_layers(n: Node) -> void:
	if n is VisualInstance3D:
		(n as VisualInstance3D).layers = LAYER
	for c in n.get_children():
		_set_layers(c)
