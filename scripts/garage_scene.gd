class_name GarageScene
extends Node3D
## The main menu: your car on a turntable in a lit workshop. It lives on its
## own render layer (LAYER) with its own camera and lights, so the highway
## world never shows through or lights it. Drag to turn the camera round the
## car; left alone it drifts slowly round by itself.

const LAYER := 2           # render layer bit value (layer 2)
const ORIGIN := Vector3(0, -400, 0)  # well under the highway's ground
const ROOM_W := 24.0
const ROOM_D := 22.0
const ROOM_H := 6.0

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
	cam.fov = 64.0 if portrait else 50.0
	var want := _car_len * (0.9 if portrait else 1.25) + 1.6
	_dist = lerpf(_dist, want, minf(1.0, delta * 3.0))
	# keep the car clear of the menu panels: above the bottom sheet in
	# portrait, left of the side panel in landscape
	cam.v_offset = -1.75 if portrait else -0.1
	cam.h_offset = 0.0 if portrait else _dist * 0.16
	_update_cam()


func _update_cam() -> void:
	var aim := Vector3(0, _car_h * 0.45, 0)
	var dir := Vector3(sin(_yaw) * cos(_pitch), sin(_pitch), cos(_yaw) * cos(_pitch))
	# never through a wall or the ceiling: stop short of whichever comes first
	var reach := _dist
	var m := 0.8
	if absf(dir.x) > 0.001:
		reach = minf(reach, (ROOM_W / 2.0 - m) / absf(dir.x))
	if absf(dir.z) > 0.001:
		reach = minf(reach, (ROOM_D / 2.0 - m) / absf(dir.z))
	if dir.y > 0.001:
		reach = minf(reach, (ROOM_H - 0.6 - aim.y) / dir.y)
	cam.position = aim + dir * reach
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
	var W := ROOM_W
	var D := ROOM_D
	var H := ROOM_H
	var floor_m := _mat(Color("#2a2d31"), 0.22, 0.0)
	var wall_m := _mat(Color("#aeb3b9"), 0.85)
	var panel_m := _mat(Color("#b9bdc2"), 0.6, 0.3)
	var wall_low := _mat(Color("#33383f"), 0.7)
	var amber := _mat(Color("#f5b52e"), 0.5)
	var amber_glow := _mat(Color("#ffb43a"), 0.4, 0.0, 2.2)
	var dark := _mat(Color("#16181b"), 0.6)
	var steel := _mat(Color("#9aa0a6"), 0.35, 0.8)
	var beam_m := _mat(Color("#3b4047"), 0.5, 0.5)
	var red := _mat(Color("#b5322a"), 0.4, 0.1)
	var rubber := _mat(Color("#141516"), 0.9)
	var wood := _mat(Color("#7a5a3a"), 0.8)

	# ---- shell: polished floor with tile joints, walls with ribbed upper panels
	_box(self, Vector3(0, -0.05, 0), Vector3(W, 0.1, D), floor_m)
	var joint := _mat(Color("#202326"), 0.5)
	for k in range(-5, 6):
		_box(self, Vector3(k * 2.0, 0.001, 0), Vector3(0.02, 0.004, D), joint, Vector3.ZERO, false)
		_box(self, Vector3(0, 0.001, k * 2.0), Vector3(W, 0.004, 0.02), joint, Vector3.ZERO, false)
	_box(self, Vector3(0, H + 0.05, 0), Vector3(W, 0.1, D), _mat(Color("#4a4f56"), 0.9))
	for s in [-1.0, 1.0]:
		_box(self, Vector3(s * W / 2.0, H / 2.0, 0), Vector3(0.2, H, D), wall_m)
		_box(self, Vector3(s * (W / 2.0 - 0.11), 0.7, 0), Vector3(0.04, 1.4, D), wall_low)
		_box(self, Vector3(s * (W / 2.0 - 0.12), 1.44, 0), Vector3(0.04, 0.08, D), amber)
		for k in range(-10, 11):  # ribbed cladding above the stripe
			_box(self, Vector3(s * (W / 2.0 - 0.13), 3.4, k * 1.0), Vector3(0.05, 3.6, 0.08), panel_m, Vector3.ZERO, false)
	for z in [-D / 2.0, D / 2.0]:
		var dz := 1.0 if z < 0 else -1.0
		_box(self, Vector3(0, H / 2.0, z), Vector3(W, H, 0.2), wall_m)
		_box(self, Vector3(0, 0.7, z + dz * 0.11), Vector3(W, 1.4, 0.04), wall_low)
		_box(self, Vector3(0, 1.44, z + dz * 0.12), Vector3(W, 0.08, 0.04), amber)
	# amber LED strip along the foot of every wall
	for s in [-1.0, 1.0]:
		_box(self, Vector3(s * (W / 2.0 - 0.14), 0.06, 0), Vector3(0.03, 0.03, D - 0.4), amber_glow, Vector3.ZERO, false)
		_box(self, Vector3(0, 0.06, s * (D / 2.0 - 0.14)), Vector3(W - 0.4, 0.03, 0.03), amber_glow, Vector3.ZERO, false)

	# ---- ceiling: steel beams, skylights and hanging light bars
	for k in range(-4, 5):
		_box(self, Vector3(0, H - 0.25, k * 2.4), Vector3(W, 0.35, 0.18), beam_m, Vector3.ZERO, false)
	for x in [-6.0, 6.0]:
		_box(self, Vector3(x, H - 0.02, 0), Vector3(3.0, 0.04, 8.0), _mat(Color("#cfe2ff"), 0.3, 0.0, 1.4), Vector3.ZERO, false)  # skylights
	for x in [-3.2, 0.0, 3.2]:
		for z in [-3.0, 3.0]:
			_box(self, Vector3(x, H - 0.9, z), Vector3(0.3, 0.06, 2.6), dark, Vector3.ZERO, false)
			_box(self, Vector3(x, H - 0.94, z), Vector3(0.24, 0.02, 2.5), _mat(Color("#fffaf0"), 0.5, 0.0, 3.5), Vector3.ZERO, false)
			for e in [-1.1, 1.1]:
				_box(self, Vector3(x, H - 0.55, z + e), Vector3(0.01, 0.7, 0.01), steel, Vector3.ZERO, false)

	# ---- back wall: roller door, sign, high windows
	var door := Node3D.new()
	door.position = Vector3(0, 0, -D / 2.0 + 0.14)
	add_child(door)
	_box(door, Vector3(0, 2.1, 0), Vector3(6.4, 4.2, 0.04), _mat(Color("#8d939a"), 0.5, 0.5))
	for k in 21:
		_box(door, Vector3(0, 0.1 + k * 0.2, 0.03), Vector3(6.3, 0.03, 0.03), _mat(Color("#6c7177"), 0.5, 0.5))
	for s in [-1.0, 1.0]:
		_box(door, Vector3(s * 3.3, 2.15, 0.05), Vector3(0.2, 4.3, 0.1), amber)
		for k in 9:  # hazard chevrons up the door frame
			_box(door, Vector3(s * 3.3, 0.25 + k * 0.48, 0.11), Vector3(0.21, 0.12, 0.02), dark, Vector3(0, 0, s * 0.5))
	_box(door, Vector3(0, 4.35, 0.05), Vector3(6.8, 0.3, 0.16), dark)
	for x in [-8.5, -6.0, 6.0, 8.5]:  # high windows letting in daylight
		_box(door, Vector3(x, 4.3, 0.02), Vector3(1.8, 1.0, 0.04), _mat(Color("#bcd4f0"), 0.2, 0.0, 1.6), Vector3.ZERO, false)
		_box(door, Vector3(x, 4.3, 0.05), Vector3(1.9, 0.06, 0.06), dark)
		_box(door, Vector3(x, 4.3, 0.05), Vector3(0.06, 1.1, 0.06), dark)
	_box(self, Vector3(0, 5.2, -D / 2.0 + 0.16), Vector3(5.2, 0.8, 0.06), _mat(Color("#14563a"), 0.6))
	_box(self, Vector3(0, 5.2, -D / 2.0 + 0.13), Vector3(5.4, 1.0, 0.04), amber)
	_label(self, "REDLINE RUSH", Vector3(0, 5.24, -D / 2.0 + 0.2), 110, Color("#f3f5ef"), Vector3.ZERO, 0.0075)
	_label(self, "SERVICE · TUNING · PAINT", Vector3(0, 4.94, -D / 2.0 + 0.2), 44, Color("#f5b52e"), Vector3.ZERO, 0.006)

	# ---- turntable: dark plate, LED ring, rubber mat round it
	_table = Node3D.new()
	add_child(_table)
	_cyl(self, Vector3(0, 0.005, 0), 4.1, 0.01, _mat(Color("#1b1d20"), 0.95), Vector3.ZERO, 64)
	_cyl(self, Vector3(0, 0.02, 0), 3.3, 0.06, _mat(Color("#1d2024"), 0.3, 0.45), Vector3.ZERO, 64)
	_cyl(self, Vector3(0, 0.024, 0), 3.42, 0.05, amber_glow, Vector3.ZERO, 64)
	_cyl(self, Vector3(0, 0.052, 0), 3.2, 0.02, _mat(Color("#25292e"), 0.25, 0.55), Vector3.ZERO, 64)
	for k in 24:  # brushed rings on the plate
		var th := TAU * k / 24.0
		_box(self, Vector3(cos(th) * 2.4, 0.064, sin(th) * 2.4), Vector3(0.6, 0.004, 0.03), _mat(Color("#30353b"), 0.3, 0.6), Vector3(0, -th, 0), false)
	# bay lines and a drain grate
	for s in [-1.0, 1.0]:
		_box(self, Vector3(s * 4.6, 0.003, 0), Vector3(0.14, 0.01, 10.0), amber, Vector3.ZERO, false)
	_box(self, Vector3(0, 0.003, 5.0), Vector3(9.3, 0.01, 0.14), amber, Vector3.ZERO, false)
	_box(self, Vector3(0, 0.003, 6.2), Vector3(3.0, 0.01, 0.3), steel, Vector3.ZERO, false)

	# ---- left wall: tool chests, workbench with pegboard and a parts shelf
	var bench := Node3D.new()
	bench.position = Vector3(-W / 2.0 + 0.6, 0, -3.5)
	add_child(bench)
	for bz in [0.0, 1.8]:
		_box(bench, Vector3(0, 0.55, bz), Vector3(0.75, 1.1, 1.6), red)
		for k in 6:
			_box(bench, Vector3(0.38, 0.15 + k * 0.17, bz), Vector3(0.02, 0.13, 1.5), _mat(Color("#9b2a23"), 0.4))
			_box(bench, Vector3(0.4, 0.15 + k * 0.17, bz), Vector3(0.02, 0.02, 0.5), steel)
		_box(bench, Vector3(0, 1.12, bz), Vector3(0.78, 0.04, 1.65), dark)
	_box(bench, Vector3(0, 0.9, 4.2), Vector3(0.8, 0.06, 2.6), wood)  # bench top
	for z in [3.0, 5.4]:
		_box(bench, Vector3(0, 0.45, z), Vector3(0.7, 0.9, 0.06), dark)
	_box(bench, Vector3(-0.27, 2.0, 4.2), Vector3(0.04, 1.6, 2.6), _mat(Color("#d8d2c4"), 0.9))  # pegboard
	for k in 9:
		_box(bench, Vector3(-0.22, 1.6 + (k % 3) * 0.4, 3.2 + k * 0.24), Vector3(0.04, 0.32, 0.05), steel)
	_box(bench, Vector3(0.05, 1.0, 3.6), Vector3(0.3, 0.2, 0.4), _mat(Color("#2f6fd6"), 0.5))  # toolbox
	# parts shelf with boxes and oil cans
	var shelf := Node3D.new()
	shelf.position = Vector3(-W / 2.0 + 0.5, 0, 4.5)
	add_child(shelf)
	for y in [0.4, 1.2, 2.0, 2.8]:
		_box(shelf, Vector3(0, y, 0), Vector3(0.6, 0.04, 2.4), steel)
	for x in [-0.28, 0.28]:
		for z in [-1.18, 1.18]:
			_box(shelf, Vector3(x, 1.5, z), Vector3(0.04, 3.0, 0.04), dark)
	var box_cols := [Color("#b08850"), Color("#9c7a48"), Color("#c49a5e")]
	for y in [0.4, 1.2, 2.0]:
		for k in 4:
			_box(shelf, Vector3(0, y + 0.2, -0.9 + k * 0.6), Vector3(0.5, 0.36, 0.48), _mat(box_cols[k % 3], 0.9))
	for k in 6:
		_cyl(shelf, Vector3(0.05, 2.95, -1.0 + k * 0.4), 0.1, 0.26, _mat([Color("#c62828"), Color("#1f4e8c"), Color("#f5b52e")][k % 3], 0.4, 0.2), Vector3.ZERO, 16)

	# ---- right wall: tyre rack, drums, compressor, extinguisher, posters
	for row in 2:
		for k in 5:
			var tz := -6.0 + k * 0.62
			_cyl(self, Vector3(W / 2.0 - 0.6, 0.38 + row * 0.8, tz), 0.36, 0.24, rubber, Vector3(0, 0, PI / 2.0))
			_cyl(self, Vector3(W / 2.0 - 0.6, 0.38 + row * 0.8, tz), 0.22, 0.25, dark, Vector3(0, 0, PI / 2.0))
	for y in [0.0, 0.8, 1.6]:
		_box(self, Vector3(W / 2.0 - 0.6, y + 0.02, -4.75), Vector3(0.8, 0.04, 3.4), steel)
	_cyl(self, Vector3(W / 2.0 - 0.8, 0.45, 2.6), 0.3, 0.9, _mat(Color("#1f4e8c"), 0.5, 0.3))
	_cyl(self, Vector3(W / 2.0 - 1.5, 0.45, 2.9), 0.3, 0.9, red)
	_cyl(self, Vector3(W / 2.0 - 0.9, 0.35, 5.0), 0.28, 0.7, _mat(Color("#d64a1e"), 0.4, 0.2), Vector3(PI / 2.0, 0, 0))  # compressor tank
	_box(self, Vector3(W / 2.0 - 0.9, 0.8, 5.0), Vector3(0.4, 0.3, 0.4), dark)
	_cyl(self, Vector3(W / 2.0 - 0.3, 0.45, 0.6), 0.09, 0.55, red, Vector3.ZERO, 16)  # extinguisher
	var posters := [["TURBO", Color("#c62828")], ["PREMIUM OIL", Color("#1f4e8c")], ["RACE TYRES", Color("#1b1e23")]]
	for k in posters.size():
		var pz := -1.5 + k * 1.6
		_box(self, Vector3(W / 2.0 - 0.12, 2.6, pz), Vector3(0.02, 1.4, 1.0), _mat(posters[k][1], 0.6))
		_label(self, posters[k][0], Vector3(W / 2.0 - 0.14, 2.6, pz), 64, Color("#f3f5ef"), Vector3(0, -PI / 2.0, 0), 0.005)

	# ---- a two-post lift and a diagnostics cart in the back corners
	for s in [-1.0, 1.0]:
		_box(self, Vector3(W / 2.0 - 4.4 + s * 1.6, 2.0, -D / 2.0 + 1.8), Vector3(0.32, 4.0, 0.32), _mat(Color("#2f6fd6"), 0.45, 0.2))
	_box(self, Vector3(W / 2.0 - 4.4, 4.05, -D / 2.0 + 1.8), Vector3(3.5, 0.2, 0.32), _mat(Color("#2f6fd6"), 0.45, 0.2))
	var cart := Node3D.new()
	cart.position = Vector3(-W / 2.0 + 3.0, 0, -D / 2.0 + 1.6)
	add_child(cart)
	_box(cart, Vector3(0, 0.55, 0), Vector3(0.7, 0.9, 0.5), dark)
	_box(cart, Vector3(0, 1.3, 0), Vector3(0.6, 0.45, 0.06), dark)
	_box(cart, Vector3(0, 1.3, 0.035), Vector3(0.52, 0.36, 0.01), _mat(Color("#2a8ad8"), 0.3, 0.0, 1.8))
	for x in [-0.28, 0.28]:
		_cyl(cart, Vector3(x, 0.06, 0.2), 0.06, 0.05, rubber, Vector3(0, 0, PI / 2.0), 12)
	# traffic cones by the door
	for k in 3:
		var cp := Vector3(-4.2 + k * 0.6, 0, -D / 2.0 + 1.0)
		var cone := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.03
		cm.bottom_radius = 0.17
		cm.height = 0.55
		cone.mesh = cm
		cone.material_override = _mat(Color("#ff6a1a"), 0.5)
		cone.position = cp + Vector3(0, 0.3, 0)
		cone.layers = LAYER
		add_child(cone)
		_box(self, cp + Vector3(0, 0.02, 0), Vector3(0.4, 0.04, 0.4), _mat(Color("#ff6a1a"), 0.5))

	# ---- lights: key spots on the car, soft fill, a cool rim from the door side
	for p in [Vector3(-3.4, H - 1.0, 3.2), Vector3(3.4, H - 1.0, 3.2), Vector3(0.0, H - 1.0, -3.4)]:
		var sp := SpotLight3D.new()
		sp.position = p
		sp.light_color = Color("#fff4e2")
		sp.light_energy = 7.0
		sp.spot_range = 14.0
		sp.spot_angle = 46.0
		sp.spot_attenuation = 0.8
		sp.shadow_enabled = true
		sp.light_cull_mask = LAYER
		add_child(sp)
		sp.look_at(global_position + Vector3(0, 0.5, 0))
	var fill := OmniLight3D.new()
	fill.position = Vector3(0, 3.6, 5.0)
	fill.light_energy = 1.4
	fill.omni_range = 18.0
	fill.light_cull_mask = LAYER
	add_child(fill)
	var back := OmniLight3D.new()
	back.position = Vector3(0, 3.0, -7.0)
	back.light_energy = 1.0
	back.light_color = Color("#cfe0ff")
	back.omni_range = 14.0
	back.light_cull_mask = LAYER
	add_child(back)
	for x in [-9.0, 9.0]:  # the wall corners would be very dark otherwise
		var o := OmniLight3D.new()
		o.position = Vector3(x, 3.5, 0)
		o.light_energy = 0.7
		o.omni_range = 10.0
		o.light_cull_mask = LAYER
		add_child(o)


func _set_layers(n: Node) -> void:
	if n is VisualInstance3D:
		(n as VisualInstance3D).layers = LAYER
	for c in n.get_children():
		_set_layers(c)
