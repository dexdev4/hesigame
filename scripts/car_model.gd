class_name CarModel
extends Node3D
## A low-poly vehicle built from boxes. Origin is the centre of the rear
## bumper at ground level; the car faces -Z.

static var _mats := {}
static var _meshes := {}

var shape: Dictionary
var _tails: Array[MeshInstance3D] = []
var _sig_l: Array[MeshInstance3D] = []
var _sig_r: Array[MeshInstance3D] = []
var _body: Node3D
var _braking := false


static func mat(c: Color, glow := 0.0, rough := 0.55, metal := 0.0) -> StandardMaterial3D:
	var key := "%s|%s|%s|%s" % [c.to_html(), glow, rough, metal]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	if glow > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = glow
	_mats[key] = m
	return m


static func box_mesh(size: Vector3) -> BoxMesh:
	var key := "b%s" % size
	if not _meshes.has(key):
		var bm := BoxMesh.new()
		bm.size = size
		_meshes[key] = bm
	return _meshes[key]


static func wheel_mesh(r: float, w: float) -> CylinderMesh:
	var key := "w%s_%s" % [r, w]
	if not _meshes.has(key):
		var cm := CylinderMesh.new()
		cm.top_radius = r
		cm.bottom_radius = r
		cm.height = w
		cm.radial_segments = 12
		_meshes[key] = cm
	return _meshes[key]


func _part(size: Vector3, pos: Vector3, m: Material, parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = box_mesh(size)
	mi.material_override = m
	mi.position = pos
	(parent if parent else _body).add_child(mi)
	return mi


func _wheel(x: float, z: float, r: float) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = wheel_mesh(r, 0.26)
	mi.material_override = mat(Color("#141517"), 0.0, 0.9)
	mi.rotation_degrees.z = 90.0
	mi.position = Vector3(x, r, z)
	add_child(mi)  # wheels do not roll with the body


func build(shape_id: String, color: Color, cab_color := Color("#b5322a")) -> void:
	shape = Data.SHAPES[shape_id]
	_body = Node3D.new()
	add_child(_body)
	var w: float = shape.w
	var l: float = shape.l
	var b: float = shape.b
	var paint := mat(color, 0.0, 0.35, 0.25)
	var dark := mat(color.darkened(0.6), 0.0, 0.7)
	var glass := mat(Color("#18212b"), 0.0, 0.1, 0.3)
	var tail_off := mat(Color("#7a1010"), 0.6)
	var amber := mat(Color("#ffb020"), 3.0)
	var plate := mat(Color("#e6e3d6"), 0.0, 0.8)

	if shape.get("truck", false):
		var cab := mat(cab_color, 0.0, 0.4, 0.2)
		_part(Vector3(w - 0.1, 2.6, 2.4), Vector3(0, 0.5 + 1.3, -(l - 1.2)), cab)
		_part(Vector3(w - 0.14, 0.9, 0.05), Vector3(0, 2.3, -(l - 0.02)), glass)
		_part(Vector3(w, 2.95, l - 2.7), Vector3(0, 0.95 + 1.475, -(l - 2.7) / 2.0), mat(color, 0.0, 0.6))
		_part(Vector3(w - 0.3, 0.14, 0.1), Vector3(0, 0.6, 0.05), mat(Color("#1a1b1d")))
		_part(Vector3(0.04, 2.8, 0.02), Vector3(0, 2.45, 0.01), mat(Color("#9a9c98")))
		for s in [-1.0, 1.0]:
			_tails.append(_part(Vector3(0.32, 0.2, 0.04), Vector3(s * (w / 2 - 0.26), 1.12, 0.02), tail_off))
			var sg := _part(Vector3(0.16, 0.14, 0.04), Vector3(s * (w / 2 - 0.18), 1.33, 0.02), amber)
			sg.visible = false
			(_sig_l if s < 0 else _sig_r).append(sg)
			for z in [-1.0, -2.2, -(l - 1.0)]:
				_wheel(s * (w / 2 - 0.25), z, 0.5)
		return

	# body
	_part(Vector3(w, b - 0.28, l), Vector3(0, (0.28 + b) / 2.0, -l / 2.0), paint)
	_part(Vector3(w + 0.02, 0.16, 0.08), Vector3(0, 0.36, 0.02), dark)  # rear bumper
	_part(Vector3(w + 0.02, 0.16, 0.08), Vector3(0, 0.36, -l - 0.02), dark)  # front bumper
	_part(Vector3(0.52, 0.14, 0.03), Vector3(0, 0.53, 0.05), plate)
	# cabin
	if shape.c1 > 0.0:
		var cl: float = l * (shape.c1 - shape.c0)
		var cw: float = w - 2.0 * shape.ins
		var ch: float = shape.t - b
		var cz: float = -l * (shape.c0 + shape.c1) / 2.0
		_part(Vector3(cw, ch, cl), Vector3(0, b + ch / 2.0, cz), glass)
		_part(Vector3(cw - 0.06, 0.06, cl - 0.18), Vector3(0, shape.t + 0.01, cz), paint)
		_part(Vector3(0.06, ch, 0.12), Vector3(-cw / 2 + 0.03, b + ch / 2.0, cz + cl / 2.0 - 0.06), paint)
		_part(Vector3(0.06, ch, 0.12), Vector3(cw / 2 - 0.03, b + ch / 2.0, cz + cl / 2.0 - 0.06), paint)
	if shape.get("van", false):
		_part(Vector3(w - 0.3, 0.6, 0.03), Vector3(0, 1.75, 0.01), glass)
		_part(Vector3(w - 0.2, 0.55, 0.03), Vector3(0, 1.8, -l - 0.01), glass)
	if shape.get("spoiler", false):
		_part(Vector3(w - 0.16, 0.06, 0.4), Vector3(0, b + 0.2, -0.24), dark)
		_part(Vector3(0.08, 0.18, 0.1), Vector3(-0.5, b + 0.08, -0.24), dark)
		_part(Vector3(0.08, 0.18, 0.1), Vector3(0.5, b + 0.08, -0.24), dark)
	# lights
	var ty := 1.18 if shape.get("van", false) else b - 0.17
	for s in [-1.0, 1.0]:
		_tails.append(_part(Vector3(0.42, 0.17, 0.04), Vector3(s * (w / 2 - 0.27), ty, 0.01), tail_off))
		var sg := _part(Vector3(0.12, 0.17, 0.045), Vector3(s * (w / 2 - 0.05), ty, 0.012), amber)
		sg.visible = false
		(_sig_l if s < 0 else _sig_r).append(sg)
		_part(Vector3(0.36, 0.12, 0.04), Vector3(s * (w / 2 - 0.3), b - 0.18, -l - 0.01), mat(Color("#fff6d8"), 1.5))
		_wheel(s * (w / 2 - 0.13), -0.85, 0.33)
		_wheel(s * (w / 2 - 0.13), -(l - 0.9), 0.33)


func set_brake(on: bool) -> void:
	if on == _braking:
		return
	_braking = on
	var m := mat(Color("#ff2a1a"), 5.0) if on else mat(Color("#7a1010"), 0.6)
	for t in _tails:
		t.material_override = m


## dir: -1 left, 1 right, 0 off. lit toggles the blink phase.
func set_signal(dir: int, lit: bool) -> void:
	for s in _sig_l:
		s.visible = dir < 0 and lit
	for s in _sig_r:
		s.visible = dir > 0 and lit


## Lean the body (not the wheels) for a sense of weight when steering.
func set_roll(r: float) -> void:
	if _body:
		_body.rotation.z = r
