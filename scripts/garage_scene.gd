class_name GarageScene
extends Node3D
## The main menu and the garage: your car on a turntable in a showroom workshop. It lives on its
## own render layer (LAYER) with its own camera and lights, so the highway world never shows through
## or lights it.
##
## - The room is built from a few dozen merged meshes (Batch), lit by long ceiling light bars, backlit
##   wall slats and three lamps on the car; the paint reflects the same room (the studio environment
##   of shaders/car_env.gdshaderinc, switched on by the global shader parameter `env_studio`).
## - The floor is dark glass over a mirrored copy of the car, so the car stands on its own reflection.
## - The camera frames the car in whatever part of the screen the menu panels leave free (`free_rect`),
##   eases between views as the tab changes (focus), drifts slowly round a car nobody is touching, and
##   a new car slides in from the side.
## Drag to turn the camera round the car.

const LAYER := 2           # render layer bit value (layer 2)
const ORIGIN := Vector3(0, -400, 0)  # well under the highway's ground
const ROOM_W := 22.0
const ROOM_D := 20.0
const ROOM_H := 5.8

## Camera views: where round the car (yaw 0 is from behind, PI from the front), how high, and how much
## of the frame the car fills.
const VIEWS := {
	"cars": {"yaw": 2.55, "pitch": 0.14, "fit": 1.0},    # front three-quarter: the showroom shot
	"up": {"yaw": 0.62, "pitch": 0.2, "fit": 0.96},      # rear three-quarter: the engine end
	"paint": {"yaw": 2.15, "pitch": 0.3, "fit": 0.92},   # a little higher, to see the roof and bonnet
	"wheels": {"yaw": 1.5, "pitch": 0.07, "fit": 0.4},   # side on and close, on the front wheel
	"repair": {"yaw": 2.7, "pitch": 0.12, "fit": 0.9},   # a little nearer the front, where most of it shows
}

var cam: Camera3D
var car: CarModel
var active := false
## Returns the part of the screen (0..1 each way) the menus leave free for the car; set by the game.
var free_rect_fn := Callable()

var _holder: Node3D                  # the car and its reflection, which slide in and out together
var _leaving: Array = []             # [[holder, seconds left, the direction it slides off in]] for the cars sliding out
var _slide := 0.0                    # seconds of the slide-in left
var _slide_dir := Vector3.RIGHT      # the way the car coming in sets out from (the screen's right for the next car)
var locked := false                  # the next car shown is one that is not on sale yet: it stands under a dark cover
static var _cover: StandardMaterial3D
var _view := "cars"
var _yaw := 2.55
var _pitch := 0.14
var _dist := 8.0
var _yaw_t := 2.55
var _pitch_t := 0.14
var _aim := Vector3(0, 0.6, 0)
var _aim_t := Vector3(0, 0.6, 0)
var _rect := Rect2(0.0, 0.1, 1.0, 0.5)
var _drag_t := 0.0                   # seconds since the last drag (the slow walk round waits a little)
var _clock := 0.0
var _car_len := 4.4
var _car_w := 1.8
var _car_h := 1.3
var _car_id := ""
var _key: SpotLight3D
var _flash := 0.0                    # a camera-flash of light when the car or its paint changes


func _ready() -> void:
	position = ORIGIN
	_build_room()
	cam = Camera3D.new()
	cam.fov = 34.0
	cam.keep_aspect = Camera3D.KEEP_WIDTH
	cam.cull_mask = LAYER
	cam.near = 0.1
	cam.far = 60.0
	# its own lighting: dark room, no outdoor sky or haze
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#07080a")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#a3aab4")
	env.ambient_light_energy = 0.95
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.15
	env.glow_enabled = true
	env.glow_intensity = 0.55
	env.glow_strength = 1.0
	env.glow_hdr_threshold = 1.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	env.fog_enabled = true
	env.fog_light_color = Color("#0a0c0f")
	env.fog_density = 0.01
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.07
	env.adjustment_saturation = 1.06
	cam.environment = env
	add_child(cam)
	_update_cam(0.0)


func set_active(on: bool) -> void:
	var was := active
	active = on
	visible = on
	cam.current = on
	RenderingServer.global_shader_parameter_set("env_studio", 1.0 if on else 0.0)
	if on:
		_drag_t = 0.0
		if not was:  # the lights come up and the camera swoops in
			_dist *= 1.35
			_yaw += 0.7
			_pitch += 0.06
			_flash = 0.9


## Show this car (a Data.CARS entry) with the given paint and style. A different car slides in from the side the
## way the list is going: `dir` 1 (the next car, the default) brings it in from the right of the screen and sends the
## old one off to the left, -1 (the previous car) the other way round. The same car with new paint or wheels is just swapped.
func set_car(c: Dictionary, color: Color, style: Dictionary, dir := 1) -> void:
	var fresh: bool = c.id != _car_id and _holder != null
	if _holder:
		if fresh:
			# along the screen's own sideways direction, whichever way the camera is turned round the car
			var rt := cam.transform.basis.x
			rt.y = 0.0
			rt = rt.normalized() if rt.length() > 0.01 else Vector3.RIGHT
			_slide_dir = rt * (1.0 if dir >= 0 else -1.0)
			_leaving.append([_holder, 0.45, -_slide_dir])
		else:
			_holder.queue_free()
	_car_id = c.id
	_holder = Node3D.new()
	add_child(_holder)
	car = CarModel.new()
	car.build(c.shape, color, Color("#b5322a"), style)
	car.force_detail()
	var sh: Dictionary = Data.SHAPES[c.shape]
	_car_len = sh.l
	_car_w = sh.w
	_car_h = sh.t
	car.position = Vector3(0, 0.0, sh.l / 2.0)  # centred on the turntable (cars face -z from the rear bumper)
	_holder.add_child(car)
	car.build_interior()
	var rec: Dictionary = Save.damage_of(String(c.id))  # a car shows its damage until it is repaired in the workshop
	if not rec.is_empty():
		car.restore_damage(rec, false)
		if car.dmg != null:
			car.dmg.done.connect(_remirror, CONNECT_ONE_SHOT)  # (the reflection in the floor shows the dents too, once they are in)
	_set_layers(car)
	_mirror_car()
	if locked:
		_cover_up(car)
		if _mirror_root != null:
			_cover_up(_mirror_root)
	_slide = 0.55 if fresh else 0.0
	_flash = 1.0 if fresh else 1.4
	_holder.position = _slide_dir * 7.0 if fresh else Vector3.ZERO
	_aim_t = _view_aim()


## A dark, see-through cover over every surface of a car (a car you cannot buy yet).
func _cover_up(n: Node) -> void:
	if _cover == null:
		_cover = StandardMaterial3D.new()
		_cover.albedo_color = Color(0.015, 0.02, 0.03, 0.74)
		_cover.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_cover.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_cover.cull_mode = BaseMaterial3D.CULL_BACK
	var stack: Array[Node] = [n]
	while not stack.is_empty():
		var x: Node = stack.pop_back()
		if x is MeshInstance3D and not x is Label3D:
			(x as MeshInstance3D).material_overlay = _cover
		for ch in x.get_children():
			stack.append(ch)


## Which view the camera takes: "cars", "up", "paint" or "wheels".
func focus(view: String) -> void:
	if not VIEWS.has(view):
		view = "cars"
	if view != _view:
		_view = view
		_yaw_t = float(VIEWS[view].yaw)
		_pitch_t = float(VIEWS[view].pitch)
		_aim_t = _view_aim()
		_drag_t = 0.0


func orbit(dx: float, dy: float) -> void:
	_yaw_t -= dx * 0.008
	_yaw -= dx * 0.008
	_pitch_t = clampf(_pitch_t + dy * 0.004, 0.03, 0.8)
	_pitch = clampf(_pitch + dy * 0.004, 0.03, 0.8)
	_drag_t = 0.0


## Where the camera looks: the middle of the car, or its front wheel in the close view.
func _view_aim() -> Vector3:
	if _view == "wheels":
		return Vector3(_car_w * 0.5, 0.36, -_car_len * 0.5 + _car_len * 0.22)
	return Vector3(0, _car_h * 0.3, 0)


func _process(delta: float) -> void:
	if not active:
		return
	_clock += delta
	_drag_t += delta
	if _drag_t > 2.5 and _view != "wheels":
		_yaw_t += delta * 0.12  # a slow walk round the car
		_yaw += delta * 0.12
	_update_cam(delta)
	# the new car slides in, the old one out
	if _slide > 0.0 and _holder:
		_slide = maxf(0.0, _slide - delta)
		var k := _slide / 0.55
		_holder.position = _slide_dir * (7.0 * k * k * k)
	for lv in _leaving:
		lv[1] -= delta
		var h: Node3D = lv[0]
		var kk := 1.0 - maxf(lv[1], 0.0) / 0.45
		h.position = (lv[2] as Vector3) * (8.0 * kk * kk)
		if lv[1] <= 0.0:
			h.queue_free()
	_leaving = _leaving.filter(func(lv: Array) -> bool: return lv[1] > 0.0)


## Place the camera: round the car at the distance that fits it in the free part of the screen, then turned
## a little so the car sits in the middle of that part.
func _update_cam(delta: float) -> void:
	var vp := get_viewport().get_visible_rect().size
	var aspect := vp.x / maxf(vp.y, 1.0)
	var portrait := aspect < 1.0
	cam.keep_aspect = Camera3D.KEEP_WIDTH if portrait else Camera3D.KEEP_HEIGHT
	cam.fov = 34.0 if portrait else 30.0
	var hfov := deg_to_rad(cam.fov) if portrait else 2.0 * atan(tan(deg_to_rad(cam.fov) / 2.0) * aspect)
	var vfov := 2.0 * atan(tan(hfov / 2.0) / aspect) if portrait else deg_to_rad(cam.fov)
	var want := free_rect_fn.call() as Rect2 if free_rect_fn.is_valid() else Rect2(0.0, 0.1, 1.0, 0.5)
	var ease_k := 1.0 - exp(-delta * 6.0) if delta > 0.0 else 1.0
	_rect = Rect2(_rect.position.lerp(want.position, ease_k), _rect.size.lerp(want.size, ease_k))
	var spec: Dictionary = VIEWS[_view]
	# the distance at which the car fills the free rectangle
	var yaw_f := absf(sin(_yaw))
	var extent := _car_len * yaw_f + _car_w * absf(cos(_yaw))
	var need_w := extent * 1.1 / maxf(_rect.size.x * 0.92, 0.2)
	var need_h := (_car_h * 1.9 + 0.5) / maxf(_rect.size.y * 0.92, 0.2)
	var d := maxf(need_w / (2.0 * tan(hfov / 2.0)), need_h / (2.0 * tan(vfov / 2.0))) * float(spec.fit)
	if _view == "wheels":
		d = 3.6 + _car_len * 0.12
	d = clampf(d, 2.6, 11.0)
	var k := 1.0 - exp(-delta * 4.5) if delta > 0.0 else 1.0
	_yaw = lerp_angle(_yaw, _yaw_t, k)
	_pitch = lerpf(_pitch, _pitch_t, k)
	_dist = lerpf(_dist, d, k)
	_aim = _aim.lerp(_aim_t, k)
	var pitch := _pitch + sin(_clock * 0.45) * 0.004
	var dir := Vector3(sin(_yaw) * cos(pitch), sin(pitch), cos(_yaw) * cos(pitch))
	# never through a wall or the ceiling: stop short of whichever comes first
	var reach := _dist
	var m := 0.8
	if absf(dir.x) > 0.001:
		reach = minf(reach, (ROOM_W / 2.0 - m) / absf(dir.x))
	if absf(dir.z) > 0.001:
		reach = minf(reach, (ROOM_D / 2.0 - m) / absf(dir.z))
	if dir.y > 0.001:
		reach = minf(reach, (ROOM_H - 0.6 - _aim.y) / dir.y)
	cam.position = _aim + dir * reach
	cam.look_at(global_position + _aim)
	# turn the camera a little so the car lands in the middle of the free rectangle
	var c := _rect.get_center() * 2.0 - Vector2.ONE
	var b := cam.global_transform.basis
	b = b.rotated(b.y, atan(c.x * tan(hfov / 2.0)))
	b = b.rotated(b.x, atan(c.y * tan(vfov / 2.0)))
	cam.global_transform = Transform3D(b, cam.global_position)
	if _key:
		_flash = move_toward(_flash, 0.0, delta * 3.0)
		_key.light_energy = 15.0 + _flash * 22.0
		_key.position = Vector3(-1.4 + sin(_clock * 0.2) * 0.8, 5.2, 1.0)  # the key light drifts a little: the highlights move
		_key.look_at(global_position + Vector3(0, 0.3, 0))


func _set_layers(n: Node) -> void:
	if n is VisualInstance3D:
		(n as VisualInstance3D).layers = LAYER
	for c in n.get_children():
		_set_layers(c)


# ---------------------------------------------------------------- the reflection in the floor

## A mirrored copy of every mesh of the car, below the floor: seen through the dark glass of the floor it is
## the car's reflection. (Only meshes, no lights; it casts no shadow.)
var _mirror_root: Node3D


## The reflection again, once damage has been pressed into the car.
func _remirror() -> void:
	if car != null and is_instance_valid(car) and _holder != null:
		_mirror_car()


func _mirror_car() -> void:
	if _mirror_root != null and is_instance_valid(_mirror_root):
		_mirror_root.queue_free()
	var mirror := Node3D.new()
	_mirror_root = mirror
	_holder.add_child(mirror)
	var flip := Transform3D(Basis.from_scale(Vector3(1.0, -1.0, 1.0)), Vector3.ZERO)
	var inv := _holder.global_transform.affine_inverse()
	var stack: Array[Node] = [car]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		# the car shows its detailed meshes (force_detail hides the light ones); a reflection in dark glass
		# makes do with the light ones, a fraction of the triangles
		var lod := n.has_meta("lod")
		var light: bool = lod and n is GeometryInstance3D and (n as GeometryInstance3D).visibility_range_begin > 0.0
		if (n is Node3D and not (n as Node3D).visible and not light) or (lod and not light):
			continue
		if n is MeshInstance3D and n != car:
			var mi := n as MeshInstance3D
			if mi.mesh and mi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY:
				var cp := MeshInstance3D.new()
				cp.mesh = mi.mesh
				cp.material_override = mi.material_override
				for i in mi.mesh.get_surface_count():
					cp.set_surface_override_material(i, mi.get_surface_override_material(i))
				cp.layers = LAYER
				cp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				mirror.add_child(cp)
				cp.transform = flip * (inv * mi.global_transform)
		for ch in n.get_children():
			stack.append(ch)


# ---------------------------------------------------------------- building the room

## Boxes and cylinders that share a material are merged into one mesh each: the room is a few dozen draw
## calls instead of hundreds of nodes.
class Batch:
	var mats := {}
	var verts := {}
	var norms := {}

	func _lists(key: String) -> void:
		if not verts.has(key):
			verts[key] = PackedVector3Array()
			norms[key] = PackedVector3Array()

	## A quad whose corners go clockwise as seen from the front (the way Godot wants them).
	func quad_cw(key: String, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3) -> void:
		_lists(key)
		var v: PackedVector3Array = verts[key]
		var nn: PackedVector3Array = norms[key]
		v.append_array(PackedVector3Array([a, b, c, a, c, d]))
		nn.append_array(PackedVector3Array([n, n, n, n, n, n]))

	## The same with the corners given counter-clockwise (the way they are easiest to think of).
	func quad(key: String, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3) -> void:
		quad_cw(key, a, d, c, b, n)

	## A flat ring (face up) between two radii.
	func ring(key: String, y: float, r_in: float, r_out: float, segs := 72) -> void:
		for i in segs:
			var a0 := TAU * i / segs
			var a1 := TAU * (i + 1) / segs
			var i0 := Vector3(cos(a0) * r_in, y, sin(a0) * r_in)
			var o0 := Vector3(cos(a0) * r_out, y, sin(a0) * r_out)
			var o1 := Vector3(cos(a1) * r_out, y, sin(a1) * r_out)
			var i1 := Vector3(cos(a1) * r_in, y, sin(a1) * r_in)
			quad_cw(key, i0, o0, o1, i1, Vector3.UP)

	func box(key: String, center: Vector3, size: Vector3, rot := Vector3.ZERO) -> void:
		var h := size / 2.0
		var bs := Basis.from_euler(rot)
		var p := [Vector3(-h.x, -h.y, -h.z), Vector3(h.x, -h.y, -h.z), Vector3(h.x, h.y, -h.z), Vector3(-h.x, h.y, -h.z),
			Vector3(-h.x, -h.y, h.z), Vector3(h.x, -h.y, h.z), Vector3(h.x, h.y, h.z), Vector3(-h.x, h.y, h.z)]
		for i in 8:
			p[i] = center + bs * p[i]
		# each face wound so that it looks outward (counter-clockwise)
		quad(key, p[4], p[5], p[6], p[7], bs * Vector3(0, 0, 1))
		quad(key, p[1], p[0], p[3], p[2], bs * Vector3(0, 0, -1))
		quad(key, p[5], p[1], p[2], p[6], bs * Vector3(1, 0, 0))
		quad(key, p[0], p[4], p[7], p[3], bs * Vector3(-1, 0, 0))
		quad(key, p[7], p[6], p[2], p[3], bs * Vector3(0, 1, 0))
		quad(key, p[0], p[1], p[5], p[4], bs * Vector3(0, -1, 0))

	## A cylinder standing on y (turned by rot).
	func cyl(key: String, center: Vector3, r: float, height: float, segs := 24, rot := Vector3.ZERO) -> void:
		var bs := Basis.from_euler(rot)
		var h := height / 2.0
		for i in segs:
			var a0 := TAU * i / segs
			var a1 := TAU * (i + 1) / segs
			var c0 := Vector3(cos(a0), 0, sin(a0))
			var c1 := Vector3(cos(a1), 0, sin(a1))
			var n := bs * ((c0 + c1).normalized())
			var p0 := center + bs * (c0 * r + Vector3(0, -h, 0))
			var p1 := center + bs * (c1 * r + Vector3(0, -h, 0))
			var p2 := center + bs * (c1 * r + Vector3(0, h, 0))
			var p3 := center + bs * (c0 * r + Vector3(0, h, 0))
			quad(key, p1, p0, p3, p2, n)
			var up := bs * Vector3.UP
			var tc := center + bs * Vector3(0, h, 0)
			var bc := center + bs * Vector3(0, -h, 0)
			_lists(key)
			(verts[key] as PackedVector3Array).append_array(PackedVector3Array([tc, p3, p2, bc, p1, p0]))
			(norms[key] as PackedVector3Array).append_array(PackedVector3Array([up, up, up, -up, -up, -up]))

	func build(parent: Node3D, layer: int) -> void:
		for key in verts:
			var arr := []
			arr.resize(Mesh.ARRAY_MAX)
			arr[Mesh.ARRAY_VERTEX] = verts[key]
			arr[Mesh.ARRAY_NORMAL] = norms[key]
			var mesh := ArrayMesh.new()
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
			var mi := MeshInstance3D.new()
			mi.mesh = mesh
			mi.material_override = mats[key]
			mi.layers = layer
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			parent.add_child(mi)


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


## A line of lettering made by SignKit, put in this room (its own render layer, seen from the front only).
func _sign_line(l: Label3D) -> void:
	l.layers = LAYER
	l.shaded = false
	l.double_sided = false
	add_child(l)


## A soft glow lying on the floor (additive), brightest `peak` of the way out from the middle.
func _glow_disc(pos: Vector3, radius: float, c: Color, peak := 0.0) -> void:
	var g := Gradient.new()
	if peak > 0.0:
		g.offsets = PackedFloat32Array([0.0, peak * 0.6, peak, 1.0])
		g.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	else:
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 256
	tex.height = 256
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_texture = tex
	m.albedo_color = c
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	var q := QuadMesh.new()
	q.size = Vector2(radius * 2.0, radius * 2.0)
	q.orientation = PlaneMesh.FACE_Y
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.material_override = m
	mi.position = pos
	mi.layers = LAYER
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _build_room() -> void:
	var W := ROOM_W
	var D := ROOM_D
	var H := ROOM_H
	var b := Batch.new()
	b.mats = {
		"wall": _mat(Color("#2b3036"), 0.8),
		"slat": _mat(Color("#191c20"), 0.5, 0.35),
		"amber": _mat(Color("#ffb43a"), 0.5, 0.0, 1.0),
		"amber_dim": _mat(Color("#ffa830"), 0.5, 0.0, 0.4),
		"wash": _mat(Color("#8fbcff"), 0.5, 0.0, 0.55),
		"white": _mat(Color("#fff7ea"), 0.5, 0.0, 3.4),
		"cool": _mat(Color("#d6e6ff"), 0.5, 0.0, 2.4),
		"joint": _mat(Color("#2b2f35"), 0.4),
		"table": _mat(Color("#121417"), 0.22, 0.4),
		"ring_in": _mat(Color("#0c0d0f"), 0.3),
		"steel": _mat(Color("#8b9198"), 0.35, 0.8),
		"dark": _mat(Color("#1a1d21"), 0.6),
		"red": _mat(Color("#a8302a"), 0.4, 0.1),
		"red_dark": _mat(Color("#7d2420"), 0.4),
		"rubber": _mat(Color("#101112"), 0.9),
		"green": _mat(Color("#0d6a42"), 0.55),
		"paper": _mat(Color("#f3f5ef"), 0.6),
		"door": _mat(Color("#62686f"), 0.45, 0.5),
		"cone": _mat(Color("#ff6a1a"), 0.5),
		"blue": _mat(Color("#2557a8"), 0.45, 0.2),
	}
	# ---- shell: walls with backlit slats, a dark ceiling with long light bars
	b.box("wall", Vector3(0, H + 0.1, 0), Vector3(W + 0.4, 0.2, D + 0.4))
	for s in [-1.0, 1.0]:
		b.box("wall", Vector3(s * (W / 2.0 + 0.1), H / 2.0, 0), Vector3(0.2, H, D + 0.4))
		b.box("wall", Vector3(0, H / 2.0, s * (D / 2.0 + 0.1)), Vector3(W + 0.4, H, 0.2))
		# warm light behind the slats, lines of LED at the foot and head of them
		b.box("wash", Vector3(s * (W / 2.0 - 0.04), 2.45, 0), Vector3(0.03, 2.7, D - 1.6))
		b.box("amber", Vector3(s * (W / 2.0 - 0.06), 0.9, 0), Vector3(0.05, 0.05, D - 0.6))
		b.box("amber", Vector3(s * (W / 2.0 - 0.06), 3.85, 0), Vector3(0.05, 0.05, D - 0.6))
		b.box("amber_dim", Vector3(0, 0.9, s * (D / 2.0 - 0.06)), Vector3(W - 0.6, 0.05, 0.05))
		b.box("amber_dim", Vector3(0, 3.85, s * (D / 2.0 - 0.06)), Vector3(W - 0.6, 0.05, 0.05))
		b.box("wash", Vector3(0, 2.45, s * (D / 2.0 - 0.04)), Vector3(W - 1.6, 2.7, 0.03))
		var n_side := int((D - 1.0) / 0.5)
		for k in n_side:
			var z := -D / 2.0 + 0.5 + k * 0.5
			b.box("slat", Vector3(s * (W / 2.0 - 0.16), 2.45, z), Vector3(0.12, 2.7, 0.34))
		var n_end := int((W - 1.0) / 0.5)
		for k in n_end:
			var x := -W / 2.0 + 0.5 + k * 0.5
			b.box("slat", Vector3(x, 2.45, s * (D / 2.0 - 0.16)), Vector3(0.34, 2.7, 0.12))
	# the skirting below the slats
	for s in [-1.0, 1.0]:
		b.box("dark", Vector3(s * (W / 2.0 - 0.1), 0.45, 0), Vector3(0.2, 0.9, D - 0.4))
		b.box("dark", Vector3(0, 0.45, s * (D / 2.0 - 0.1)), Vector3(W - 0.4, 0.9, 0.2))
	for x in [-4.5, -1.5, 1.5, 4.5]:  # long light bars in the ceiling (the paint reflects these)
		b.box("dark", Vector3(x, H - 0.1, 0), Vector3(0.7, 0.14, 12.6))
		b.box("white", Vector3(x, H - 0.19, 0), Vector3(0.4, 0.03, 12.0))
	for z in [-7.0, 7.0]:
		b.box("cool", Vector3(0, H - 0.19, z), Vector3(11.0, 0.03, 0.12))
	# ---- the brand wall (behind the car in the showroom shot): a green guide sign between two light posts, lettered like a
	# road sign (a white line inset from the edge; the exit number over the services, both centred on the panel)
	var sz := D / 2.0 - 0.3
	var sx := 6.5  # (off to one side: out of the showroom shot, but there as the camera walks round)
	b.box("green", Vector3(sx, 3.0, sz), Vector3(6.2, 1.7, 0.08))
	for edge in [[0.0, 0.7, 5.8, 0.05], [0.0, -0.7, 5.8, 0.05], [-2.875, 0.0, 0.05, 1.4], [2.875, 0.0, 0.05, 1.4]]:
		b.box("paper", Vector3(sx + edge[0], 3.0 + edge[1], sz - 0.045), Vector3(edge[2], edge[3], 0.016))
	for x in [sx - 3.6, sx + 3.6]:
		b.box("steel", Vector3(x, 2.4, sz), Vector3(0.14, 3.0, 0.14))
		b.box("white", Vector3(x, 2.4, sz - 0.09), Vector3(0.07, 2.6, 0.03))
	var cap_a := SignKit.CAP * 0.62
	var cap_b := SignKit.CAP * 0.3
	var top := 3.0 + (cap_a + 0.3 + cap_b) / 2.0
	_sign_line(SignKit.line("EXIT 12", 0.62, SignKit.WHITE, Vector3(sx, top - cap_a / 2.0, sz - 0.07), HORIZONTAL_ALIGNMENT_CENTER, Basis(Vector3.UP, PI)))
	_sign_line(SignKit.line("SERVICE AREA  ·  TUNING  ·  PAINT", 0.3, Color("#f5b52e"), Vector3(sx, top - cap_a - 0.3 - cap_b / 2.0, sz - 0.07), HORIZONTAL_ALIGNMENT_CENTER, Basis(Vector3.UP, PI)))
	# ---- the roller door on the opposite wall
	var dz := -D / 2.0 + 0.3
	b.box("door", Vector3(0, 2.1, dz), Vector3(6.4, 4.2, 0.06))
	for k in 21:
		b.box("slat", Vector3(0, 0.1 + k * 0.2, dz + 0.04), Vector3(6.3, 0.03, 0.03))
	for s in [-1.0, 1.0]:
		b.box("amber", Vector3(s * 3.3, 2.15, dz + 0.04), Vector3(0.14, 4.3, 0.1))
	b.box("dark", Vector3(0, 4.35, dz + 0.04), Vector3(6.8, 0.3, 0.16))
	# ---- the turntable: a flat dark disc with an LED ring round it
	b.ring("amber", 0.006, 3.58, 3.68)
	b.ring("table", 0.004, 3.7, 3.95)
	for k in 36:  # fine radial marks on the plate
		var th := TAU * k / 36.0
		b.box("joint", Vector3(cos(th) * 2.4, 0.003, sin(th) * 2.4), Vector3(1.2, 0.002, 0.02), Vector3(0, -th, 0))
	# bay lines and tile joints on the floor
	for k in range(-4, 5):
		b.box("joint", Vector3(k * 2.5, 0.001, 0), Vector3(0.025, 0.002, D - 0.4))
		b.box("joint", Vector3(0, 0.001, k * 2.5), Vector3(W - 0.4, 0.002, 0.025))
	for s in [-1.0, 1.0]:
		b.box("amber_dim", Vector3(s * 5.6, 0.003, 0), Vector3(0.1, 0.004, 12.0))
	# ---- left wall: a tool cabinet with a bench, and a shelf of oil cans
	for bz in [-4.0, -2.2]:
		b.box("red", Vector3(-W / 2.0 + 1.0, 0.55, bz), Vector3(0.8, 1.1, 1.6))
		for k in 6:
			b.box("red_dark", Vector3(-W / 2.0 + 1.41, 0.15 + k * 0.17, bz), Vector3(0.02, 0.13, 1.5))
			b.box("steel", Vector3(-W / 2.0 + 1.43, 0.15 + k * 0.17, bz), Vector3(0.02, 0.02, 0.5))
		b.box("dark", Vector3(-W / 2.0 + 1.0, 1.12, bz), Vector3(0.84, 0.04, 1.65))
	b.box("steel", Vector3(-W / 2.0 + 0.9, 0.9, 0.8), Vector3(0.7, 0.05, 2.4))
	for z in [-0.3, 1.9]:
		b.box("dark", Vector3(-W / 2.0 + 0.9, 0.45, z), Vector3(0.6, 0.9, 0.05))
	b.box("blue", Vector3(-W / 2.0 + 0.9, 1.05, 0.8), Vector3(0.3, 0.18, 0.5))
	# ---- right wall: a tyre rack, two drums
	for y in [0.0, 0.8, 1.6]:
		b.box("steel", Vector3(W / 2.0 - 0.7, y + 0.02, -4.0), Vector3(0.9, 0.04, 3.6))
	for row in 2:
		for k in 5:
			var tz := -5.4 + k * 0.7
			b.cyl("rubber", Vector3(W / 2.0 - 0.7, 0.4 + row * 0.8, tz), 0.36, 0.26, 20, Vector3(0, 0, PI / 2.0))
	b.cyl("blue", Vector3(W / 2.0 - 0.8, 0.45, 2.6), 0.3, 0.9, 20)
	b.cyl("red", Vector3(W / 2.0 - 1.5, 0.45, 2.9), 0.3, 0.9, 20)
	# traffic cones by the door
	for k in 3:
		var cp := Vector3(-4.2 + k * 0.6, 0.0, -D / 2.0 + 1.1)
		b.cyl("cone", cp + Vector3(0, 0.25, 0), 0.14, 0.5, 14)
		b.box("cone", cp + Vector3(0, 0.02, 0), Vector3(0.4, 0.04, 0.4))
	b.build(self, LAYER)
	# ---- the floor: dark glass over the mirrored car
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.028, 0.03, 0.034, 0.8)
	fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fm.roughness = 0.14
	fm.metallic = 0.0
	fm.metallic_specular = 0.9
	var fq := PlaneMesh.new()
	fq.size = Vector2(W, D)
	var floor_mi := MeshInstance3D.new()
	floor_mi.mesh = fq
	floor_mi.material_override = fm
	floor_mi.layers = LAYER
	floor_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(floor_mi)
	_glow_disc(Vector3(0, 0.02, 0), 5.0, Color(1.0, 0.62, 0.2, 0.12), 3.63 / 5.0)  # the amber ring's glow on the floor
	# ---- lights: a key lamp over the car (no shadow map: the contact shadow and the reflection ground the car, and
	# a shadow map would draw the whole car again), a cool and a warm rim lamp, a soft fill, washes on the end walls
	_key = SpotLight3D.new()
	_key.position = Vector3(-1.4, 5.2, 1.0)
	_key.light_color = Color("#fff4e4")
	_key.light_energy = 15.0
	_key.spot_range = 14.0
	_key.spot_angle = 40.0
	_key.spot_attenuation = 0.7
	_key.shadow_enabled = false
	_key.light_cull_mask = LAYER
	add_child(_key)
	for rim in [[Vector3(-6.5, 2.6, 5.0), Color("#cfe2ff"), 7.0], [Vector3(6.5, 2.2, -5.0), Color("#ffc98a"), 6.0],
			[Vector3(6.0, 2.4, 5.5), Color("#e8f0ff"), 3.5]]:
		var sp := SpotLight3D.new()
		sp.position = rim[0]
		sp.light_color = rim[1]
		sp.light_energy = rim[2]
		sp.spot_range = 16.0
		sp.spot_angle = 34.0
		sp.spot_attenuation = 0.8
		sp.light_cull_mask = LAYER
		add_child(sp)
		sp.look_at(global_position + Vector3(0, 0.6, 0))
	var fill := OmniLight3D.new()
	fill.position = Vector3(0, 3.4, 0)
	fill.light_energy = 1.4
	fill.omni_range = 16.0
	fill.light_cull_mask = LAYER
	add_child(fill)
	for wz in [-1.0, 1.0]:  # soft washes on the end walls, so the slats and the sign show
		var wash := SpotLight3D.new()
		wash.position = Vector3(wz * -1.0, 4.6, -wz * 6.0)
		wash.light_color = Color("#ffe9cc")
		wash.light_energy = 6.0
		wash.spot_range = 18.0
		wash.spot_angle = 55.0
		wash.spot_attenuation = 0.6
		wash.light_cull_mask = LAYER
		add_child(wash)
		wash.look_at(global_position + Vector3(0, 2.0, wz * 10.0))
