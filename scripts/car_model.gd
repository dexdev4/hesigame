class_name CarModel
extends Node3D
## Low-poly vehicle with real proportions. The body is lofted from a side
## profile with rounded shoulders; the greenhouse has a raked windshield and
## rear glass with painted pillars. Geometry is built once per vehicle type
## and shared; only materials differ per car. Origin is the centre of the
## rear bumper at ground level; the car faces -Z.

static var _mats := {}
static var _meshes := {}
static var _kits := {}
static var _shadow_mat: StandardMaterial3D
static var _shadow_mesh: PlaneMesh

# Per-type body data. body stations: [distance from rear (m), top height, width scale].
# gh (greenhouse): [base rear z, base front z, roof rear z, roof front z, base y, roof y, base width, roof width].
# pillars: side-window pillar spans along the side, 0 = rear edge, 1 = front edge.
const PROFILES := {
	"hatch": {
		"body": [[0.0, 0.82, 0.9], [0.1, 0.88, 0.97], [0.5, 0.9, 1.0], [2.4, 0.92, 1.0], [3.3, 0.86, 1.0], [3.72, 0.76, 0.97], [3.94, 0.62, 0.9], [4.0, 0.5, 0.84]],
		"gh": [0.12, 3.25, 0.32, 2.35, 0.9, 1.47, 0.94, 0.8], "pillars": [[0.0, 0.16], [0.47, 0.52], [0.92, 1.0]],
		"wheel": [0.31, 0.76, 3.25], "exhaust": 1},
	"sedan": {
		"body": [[0.0, 0.78, 0.9], [0.14, 0.84, 0.97], [0.9, 0.87, 1.0], [3.0, 0.87, 1.0], [3.9, 0.8, 1.0], [4.42, 0.7, 0.97], [4.64, 0.56, 0.9], [4.7, 0.45, 0.84]],
		"gh": [1.0, 3.72, 1.55, 3.02, 0.87, 1.42, 0.94, 0.8], "pillars": [[0.0, 0.14], [0.5, 0.55], [0.93, 1.0]],
		"wheel": [0.32, 0.95, 3.75], "exhaust": 2},
	"suv": {
		"body": [[0.0, 1.0, 0.92], [0.12, 1.05, 0.98], [0.6, 1.08, 1.0], [3.6, 1.08, 1.0], [4.2, 1.02, 1.0], [4.62, 0.92, 0.96], [4.8, 0.72, 0.9]],
		"gh": [0.22, 3.9, 0.36, 3.3, 1.08, 1.8, 0.95, 0.86], "pillars": [[0.0, 0.1], [0.36, 0.4], [0.66, 0.7], [0.94, 1.0]],
		"wheel": [0.38, 0.92, 3.85], "exhaust": 1},
	"muscle": {
		"body": [[0.0, 0.8, 0.92], [0.18, 0.86, 0.98], [1.2, 0.87, 1.0], [3.2, 0.86, 1.0], [4.35, 0.78, 0.98], [4.72, 0.62, 0.92], [4.8, 0.5, 0.88]],
		"gh": [1.2, 3.3, 1.78, 2.86, 0.87, 1.32, 0.92, 0.76], "pillars": [[0.0, 0.2], [0.9, 1.0]],
		"wheel": [0.35, 0.95, 3.85], "exhaust": 2, "spoiler": "lip"},
	"super": {
		"body": [[0.0, 0.7, 0.92], [0.18, 0.77, 0.98], [1.0, 0.81, 1.0], [2.2, 0.75, 1.0], [3.4, 0.66, 1.0], [4.2, 0.52, 0.96], [4.5, 0.4, 0.9]],
		"gh": [0.95, 3.3, 1.62, 2.6, 0.78, 1.14, 0.88, 0.7], "pillars": [[0.0, 0.25], [0.9, 1.0]],
		"wheel": [0.35, 0.9, 3.6], "exhaust": 4, "spoiler": "wing", "diffuser": true},
	"van": {
		"body": [[0.0, 2.15, 0.97], [0.08, 2.22, 0.99], [4.05, 2.25, 1.0], [4.3, 2.16, 1.0], [4.62, 1.38, 1.0], [5.05, 1.08, 0.97], [5.2, 0.72, 0.92]],
		"wheel": [0.36, 0.95, 4.35], "exhaust": 1, "van": true},
}


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


## Glossy car paint with a clear coat.
static func paint(c: Color) -> StandardMaterial3D:
	var key := "paint|%s" % c.to_html()
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.albedo_color = c.darkened(0.08)
	m.metallic = 0.25
	m.metallic_specular = 0.5
	m.roughness = 0.32
	m.clearcoat_enabled = true
	m.clearcoat = 1.0
	m.clearcoat_roughness = 0.08
	_mats[key] = m
	return m


static func box_mesh(size: Vector3) -> BoxMesh:
	var key := "b%s" % size
	if not _meshes.has(key):
		var bm := BoxMesh.new()
		bm.size = size
		_meshes[key] = bm
	return _meshes[key]


# ---------------------------------------------------------------- geometry helpers

## Adds a triangle, wound so its front face points along n (Godot: clockwise front faces).
static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, na: Vector3, nb: Vector3, nc: Vector3) -> void:
	if (b - a).cross(c - a).dot(na + nb + nc) > 0.0:
		var tv := b
		b = c
		c = tv
		var tn := nb
		nb = nc
		nc = tn
	st.set_normal(na)
	st.add_vertex(a)
	st.set_normal(nb)
	st.add_vertex(b)
	st.set_normal(nc)
	st.add_vertex(c)


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3) -> void:
	_tri(st, a, b, c, n, n, n)
	_tri(st, a, c, d, n, n, n)


static func _face_n(a: Vector3, b: Vector3, c: Vector3, hint: Vector3) -> Vector3:
	var n := (b - a).cross(c - a).normalized()
	return -n if n.dot(hint) < 0.0 else n


static func _box(st: SurfaceTool, center: Vector3, size: Vector3, basis := Basis()) -> void:
	var h := size / 2.0
	var axes := [basis.x, basis.y, basis.z]
	for ax in 3:
		for sgn in [-1.0, 1.0]:
			var n: Vector3 = axes[ax] * sgn
			var u: Vector3 = axes[(ax + 1) % 3] * h[(ax + 1) % 3]
			var v: Vector3 = axes[(ax + 2) % 3] * h[(ax + 2) % 3]
			var c: Vector3 = center + n * h[ax]
			_quad(st, c - u - v, c + u - v, c + u + v, c - u + v, n)


## Cylinder along X (wheels) or Z (exhaust tips), with end caps.
static func _cyl(st: SurfaceTool, center: Vector3, r: float, length: float, axis: Vector3, segs := 14, caps := true) -> void:
	var a := axis.normalized()
	var u := Vector3.UP if absf(a.y) < 0.9 else Vector3.FORWARD
	var v := a.cross(u).normalized()
	u = v.cross(a).normalized()
	var h := a * length / 2.0
	for i in segs:
		var t0 := TAU * i / segs
		var t1 := TAU * (i + 1) / segs
		var d0 := u * cos(t0) + v * sin(t0)
		var d1 := u * cos(t1) + v * sin(t1)
		var p0 := center + d0 * r
		var p1 := center + d1 * r
		_tri(st, p0 - h, p1 - h, p1 + h, d0, d1, d1)
		_tri(st, p0 - h, p1 + h, p0 + h, d0, d1, d0)
		if caps:
			_tri(st, center + h, p0 + h, p1 + h, a, a, a)
			_tri(st, center - h, p1 - h, p0 - h, -a, -a, -a)


## Cross-section of the lower body at one station: rounded shoulders, tucked sill.
static func _ring(hw: float, top: float) -> Array:
	var b := minf(0.3, top - 0.3)
	var y2 := maxf(top - 0.18, b + 0.16)
	var y1 := minf(b + 0.14, y2 - 0.02)
	var y3 := maxf(top - 0.05, y2 + 0.01)
	var right := [
		[Vector2(hw * 0.93, b), Vector2(0.3, -1)],
		[Vector2(hw, y1), Vector2(1, -0.2)],
		[Vector2(hw, y2), Vector2(1, 0.1)],
		[Vector2(hw * 0.96, y3), Vector2(0.7, 0.7)],
		[Vector2(hw * 0.8, top), Vector2(0.15, 1)],
	]
	var ring := []
	for p in right:
		ring.append(p)
	for i in range(right.size() - 1, -1, -1):
		var p: Array = right[i]
		ring.append([Vector2(-p[0].x, p[0].y), Vector2(-p[1].x, p[1].y)])
	return ring


static func _wheel_mesh(r: float, width: float) -> ArrayMesh:
	var key := "wheel%s_%s" % [r, width]
	if _meshes.has(key):
		return _meshes[key]
	var tire := SurfaceTool.new()
	tire.begin(Mesh.PRIMITIVE_TRIANGLES)
	_cyl(tire, Vector3.ZERO, r, width, Vector3.RIGHT, 16)
	var rim := SurfaceTool.new()
	rim.begin(Mesh.PRIMITIVE_TRIANGLES)
	for side in [-1.0, 1.0]:
		var x: float = side * (width / 2.0 + 0.004)
		_cyl(rim, Vector3(x, 0, 0), r * 0.64, 0.012, Vector3.RIGHT, 14)
		for k in 5:  # spokes, so you can see the wheels turn
			var ang := TAU * k / 5.0
			var b := Basis(Vector3.RIGHT, ang)
			_box(rim, Vector3(x + side * 0.012, 0, 0) + b.y * r * 0.33, Vector3(0.02, r * 0.6, 0.07), b)
		_cyl(rim, Vector3(x + side * 0.02, 0, 0), r * 0.16, 0.03, Vector3.RIGHT, 8)
	var m := ArrayMesh.new()
	tire.commit(m)
	rim.commit(m)
	m.surface_set_material(0, mat(Color("#121315"), 0.0, 0.92))
	m.surface_set_material(1, mat(Color("#b9bec4"), 0.0, 0.22, 0.85))
	_meshes[key] = m
	return m


# ---------------------------------------------------------------- per-type kits

## Builds (once) the shared meshes for a vehicle type.
## Body surfaces: 0 paint, 1 glass, 2 dark trim, 3 chrome, 4 plate, 5 headlights.
static func _kit(id: String) -> Dictionary:
	if _kits.has(id):
		return _kits[id]
	var kit := {}
	if id == "truck":
		kit = _truck_kit()
	else:
		kit = _car_kit(id)
	_kits[id] = kit
	return kit


static func _new_st() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st


static func _car_kit(id: String) -> Dictionary:
	var sh: Dictionary = Data.SHAPES[id]
	var pr: Dictionary = PROFILES[id]
	var w: float = sh.w
	var l: float = sh.l
	var paint_st := _new_st()
	var glass := _new_st()
	var dark := _new_st()
	var chrome := _new_st()
	var plate := _new_st()
	var head := _new_st()
	var tails := _new_st()
	var sig_l := _new_st()
	var sig_r := _new_st()

	# --- lower body loft
	var stations: Array = pr.body
	var rings := []
	for s in stations:
		rings.append(_ring(w / 2.0 * s[2], s[1]))
	for i in stations.size() - 1:
		var z0: float = -stations[i][0]
		var z1: float = -stations[i + 1][0]
		var r0: Array = rings[i]
		var r1: Array = rings[i + 1]
		for j in r0.size():
			var j2 := (j + 1) % r0.size()
			var a := Vector3(r0[j][0].x, r0[j][0].y, z0)
			var b := Vector3(r0[j2][0].x, r0[j2][0].y, z0)
			var c := Vector3(r1[j2][0].x, r1[j2][0].y, z1)
			var d := Vector3(r1[j][0].x, r1[j][0].y, z1)
			var na := Vector3(r0[j][1].x, r0[j][1].y, 0).normalized()
			var nb := Vector3(r0[j2][1].x, r0[j2][1].y, 0).normalized()
			var nc := Vector3(r1[j2][1].x, r1[j2][1].y, 0).normalized()
			var nd := Vector3(r1[j][1].x, r1[j][1].y, 0).normalized()
			_tri(paint_st, a, b, c, na, nb, nc)
			_tri(paint_st, a, c, d, na, nc, nd)
	# end caps
	for end in [0, stations.size() - 1]:
		var rg: Array = rings[end]
		var z: float = -stations[end][0]
		var n := Vector3(0, 0, 1) if end == 0 else Vector3(0, 0, -1)
		var cy := 0.0
		for p in rg:
			cy += p[0].y
		var ctr := Vector3(0, cy / rg.size(), z)
		for j in rg.size():
			var j2 := (j + 1) % rg.size()
			_tri(paint_st, ctr, Vector3(rg[j][0].x, rg[j][0].y, z), Vector3(rg[j2][0].x, rg[j2][0].y, z), n, n, n)

	var rear_top: float = stations[0][1]
	var rear_hw: float = w / 2.0 * stations[0][2]
	var front_top: float = stations[stations.size() - 1][1]
	var front_hw: float = w / 2.0 * stations[stations.size() - 1][2]
	var sill := minf(0.3, rear_top - 0.3)

	# --- greenhouse: raked glass, painted roof and pillars
	if pr.has("gh"):
		var g: Array = pr.gh
		var hb: float = w / 2.0 * g[6]
		var hr: float = w / 2.0 * g[7]
		var yb: float = g[4] - 0.01
		var yr: float = g[5]
		var BRL := Vector3(-hb, yb, -g[0])
		var BRR := Vector3(hb, yb, -g[0])
		var BFL := Vector3(-hb, yb, -g[1])
		var BFR := Vector3(hb, yb, -g[1])
		var RRL := Vector3(-hr, yr, -g[2])
		var RRR := Vector3(hr, yr, -g[2])
		var RFL := Vector3(-hr, yr, -g[3])
		var RFR := Vector3(hr, yr, -g[3])
		var n_rear := _face_n(BRL, BRR, RRR, Vector3(0, 0.5, 1))
		var n_front := _face_n(BFL, BFR, RFR, Vector3(0, 0.5, -1))
		var n_left := _face_n(BRL, BFL, RFL, Vector3(-1, 0.3, 0))
		var n_right := _face_n(BRR, BFR, RFR, Vector3(1, 0.3, 0))
		_quad(glass, BRL, BRR, RRR, RRL, n_rear)
		_quad(glass, BFL, BFR, RFR, RFL, n_front)
		_quad(glass, BRL, BFL, RFL, RRL, n_left)
		_quad(glass, BRR, BFR, RFR, RRR, n_right)
		# roof panel
		var up := Vector3.UP
		_quad(paint_st, RRL + Vector3(-0.01, 0.006, 0.02), RRR + Vector3(0.01, 0.006, 0.02), RFR + Vector3(0.01, 0.006, -0.02), RFL + Vector3(-0.01, 0.006, -0.02), up)
		# side-window pillars and chrome belt trim
		for side in [[BRL, BFL, RRL, RFL, n_left], [BRR, BFR, RRR, RFR, n_right]]:
			var off: Vector3 = side[4] * 0.008
			for pl in pr.pillars:
				var a: Vector3 = side[0].lerp(side[1], pl[0]) + off
				var b: Vector3 = side[0].lerp(side[1], pl[1]) + off
				var c: Vector3 = side[2].lerp(side[3], pl[1]) + off
				var d: Vector3 = side[2].lerp(side[3], pl[0]) + off
				_quad(paint_st, a, b, c, d, side[4])
			var t0: Vector3 = side[0] + off
			var t1: Vector3 = side[1] + off
			var lift: Vector3 = (side[2] - side[0]).normalized() * 0.035
			_quad(chrome, t0, t1, t1 + lift, t0 + lift, side[4])
		# windshield and rear-glass frames
		for gl in [[BFL, BFR, RFL, RFR, n_front, 0.06, 0.08], [BRL, BRR, RRL, RRR, n_rear, 0.05, 0.07]]:
			var off2: Vector3 = gl[4] * 0.008
			var fw: float = gl[5]
			for u in [[0.0, fw], [1.0 - fw, 1.0]]:
				var a: Vector3 = gl[0].lerp(gl[1], u[0]) + off2
				var b: Vector3 = gl[0].lerp(gl[1], u[1]) + off2
				var c: Vector3 = gl[2].lerp(gl[3], u[1]) + off2
				var d: Vector3 = gl[2].lerp(gl[3], u[0]) + off2
				_quad(paint_st, a, b, c, d, gl[4])
			var hv: float = gl[6]
			var a2: Vector3 = gl[0].lerp(gl[2], 1.0 - hv) + off2
			var b2: Vector3 = gl[1].lerp(gl[3], 1.0 - hv) + off2
			_quad(paint_st, a2, b2, gl[3] + off2, gl[2] + off2, gl[4])
		# third brake light at the top of the rear glass
		var cb: Vector3 = BRL.lerp(BRR, 0.5).lerp(RRL.lerp(RRR, 0.5), 0.86) + n_rear * 0.02
		_box(tails, cb, Vector3(0.36, 0.04, 0.03))
		# mirrors
		for s in [-1.0, 1.0]:
			_box(paint_st, Vector3(s * (hb + 0.1), yb + 0.1, -g[1] + 0.22), Vector3(0.14, 0.11, 0.08))
			_box(dark, Vector3(s * (hb + 0.03), yb + 0.08, -g[1] + 0.24), Vector3(0.06, 0.04, 0.05))

	if pr.get("van", false):
		var hw2 := w / 2.0
		_quad(glass, Vector3(-hw2 * 0.86, 1.4, 0.006), Vector3(-0.05, 1.4, 0.006), Vector3(-0.05, 2.0, 0.006), Vector3(-hw2 * 0.86, 2.0, 0.006), Vector3.BACK)
		_quad(glass, Vector3(0.05, 1.4, 0.006), Vector3(hw2 * 0.86, 1.4, 0.006), Vector3(hw2 * 0.86, 2.0, 0.006), Vector3(0.05, 2.0, 0.006), Vector3.BACK)
		_box(dark, Vector3(0, 1.2, 0.01), Vector3(0.03, 1.6, 0.02))
		var wn := Vector3(0, 0.88, -0.48).normalized()
		_quad(glass, Vector3(-hw2 * 0.86, 1.45, -4.6), Vector3(hw2 * 0.86, 1.45, -4.6), Vector3(hw2 * 0.86, 2.08, -4.33), Vector3(-hw2 * 0.86, 2.08, -4.33), wn)
		for s in [-1.0, 1.0]:
			var x: float = s * (hw2 + 0.006)
			_quad(glass, Vector3(x, 1.45, -3.55), Vector3(x, 1.45, -4.25), Vector3(x, 2.0, -4.25), Vector3(x, 2.0, -3.55), Vector3(s, 0, 0))
			_box(paint_st, Vector3(s * (hw2 + 0.1), 1.6, -4.4), Vector3(0.12, 0.2, 0.08))

	# --- rear details
	var bumper_y := sill + 0.07
	_box(dark, Vector3(0, bumper_y + 0.01, -0.12), Vector3(rear_hw * 2.0 * 0.97, 0.18, 0.3))
	_box(plate, Vector3(0, bumper_y + 0.2, 0.012), Vector3(0.52, 0.12, 0.02))
	var ty0 := 1.05 if pr.get("van", false) else rear_top - 0.25
	var ty1 := 1.3 if pr.get("van", false) else rear_top - 0.08
	var tz := 0.012
	for s in [-1.0, 1.0]:
		var x0: float = s * rear_hw * 0.58
		var x1: float = s * rear_hw * 0.93
		_box(tails, Vector3((x0 + x1) / 2.0, (ty0 + ty1) / 2.0, tz), Vector3(absf(x1 - x0), ty1 - ty0, 0.03))
		_box(sig_l if s < 0 else sig_r, Vector3(s * rear_hw * 0.5, (ty0 + ty1) / 2.0, tz), Vector3(0.12, (ty1 - ty0) * 0.8, 0.032))
		_box(chrome, Vector3(s * rear_hw * 0.755, ty0 - 0.02, tz), Vector3(rear_hw * 0.38, 0.015, 0.02))
	if not pr.get("van", false) and pr.has("gh"):
		_box(chrome, Vector3(0, ty0 - 0.02, tz), Vector3(rear_hw * 0.95, 0.015, 0.02))
	var ex: int = pr.get("exhaust", 1)
	var ex_x: Array = [-rear_hw * 0.62] if ex == 1 else ([-rear_hw * 0.6, rear_hw * 0.6] if ex == 2 else [-0.22, -0.08, 0.08, 0.22])
	for x in ex_x:
		_cyl(chrome, Vector3(x, bumper_y - 0.04, 0.02), 0.045 if ex < 4 else 0.04, 0.16, Vector3.BACK, 10, false)
		_cyl(dark, Vector3(x, bumper_y - 0.04, 0.025), 0.033, 0.16, Vector3.BACK, 8, true)
	if pr.get("diffuser", false):
		for k in 5:
			_box(dark, Vector3(-0.5 + k * 0.25, sill - 0.02, -0.32), Vector3(0.03, 0.1, 0.5))
	match pr.get("spoiler", ""):
		"wing":
			_box(dark, Vector3(0, rear_top + 0.3, -0.3), Vector3(w - 0.14, 0.05, 0.38), Basis(Vector3.RIGHT, -0.1))
			for s in [-1.0, 1.0]:
				_box(dark, Vector3(s * 0.48, rear_top + 0.14, -0.3), Vector3(0.05, 0.3, 0.12))
				_box(dark, Vector3(s * (w / 2.0 - 0.08), rear_top + 0.27, -0.3), Vector3(0.03, 0.14, 0.42))
		"lip":
			_box(paint_st, Vector3(0, rear_top + 0.035, -0.14), Vector3(w * 0.82, 0.05, 0.16), Basis(Vector3.RIGHT, 0.15))

	# --- front details
	var fz := -l - 0.012
	for s in [-1.0, 1.0]:
		_box(head, Vector3(s * front_hw * 0.68, front_top - 0.1, fz + 0.03), Vector3(front_hw * 0.42, 0.1, 0.04))
	_box(dark, Vector3(0, sill + 0.14, fz + 0.03), Vector3(front_hw * 1.1, 0.16, 0.05))

	var body := ArrayMesh.new()
	for st in [paint_st, glass, dark, chrome, plate, head]:
		st.commit(body)
	var r: float = pr.wheel[0]
	return {
		"body": body, "tails": tails.commit(), "sig_l": sig_l.commit(), "sig_r": sig_r.commit(),
		"wheels": [[-(w / 2.0 - 0.13), -pr.wheel[1]], [w / 2.0 - 0.13, -pr.wheel[1]], [-(w / 2.0 - 0.13), -pr.wheel[2]], [w / 2.0 - 0.13, -pr.wheel[2]]],
		"r": r, "ww": 0.24,
	}


static func _truck_kit() -> Dictionary:
	var sh: Dictionary = Data.SHAPES.truck
	var w: float = sh.w
	var l: float = sh.l
	var box := _new_st()   # surface 0: trailer (box colour)
	var cab := _new_st()   # surface 1: cab (cab colour)
	var glass := _new_st()
	var dark := _new_st()
	var chrome := _new_st()
	var plate := _new_st()
	var head := _new_st()
	var tails := _new_st()
	var sig_l := _new_st()
	var sig_r := _new_st()
	var tl := l - 2.7
	_box(box, Vector3(0, 2.45, -tl / 2.0), Vector3(w, 2.9, tl))
	for k in int(tl / 0.6):  # side ribs
		for s in [-1.0, 1.0]:
			_box(box, Vector3(s * (w / 2.0 + 0.01), 2.45, -0.3 - k * 0.6), Vector3(0.03, 2.8, 0.06))
	_box(dark, Vector3(0, 0.98, -tl / 2.0), Vector3(w - 0.1, 0.12, tl))  # chassis rail
	for s in [-1.0, 1.0]:
		_box(dark, Vector3(s * (w / 2.0 - 0.02), 1.05, -tl * 0.55), Vector3(0.04, 0.45, tl * 0.42))  # side skirt
		_box(dark, Vector3(s * (w / 2.0 - 0.3), 0.55, -0.15), Vector3(0.5, 0.55, 0.02))  # mud flap
	# rear doors: hinges, lock bars, reflective tape, underride guard
	_box(dark, Vector3(0, 2.45, 0.01), Vector3(0.03, 2.8, 0.02))
	for x in [-0.6, -0.4, 0.4, 0.6]:
		_box(chrome, Vector3(x, 2.4, 0.03), Vector3(0.035, 2.6, 0.035))
	for k in 8:
		var x := -w / 2.0 + 0.16 + k * (w - 0.32) / 7.0
		_box(tails if k % 2 == 0 else plate, Vector3(x, 1.08, 0.022), Vector3(0.2, 0.05, 0.01))
	_box(dark, Vector3(0, 0.58, 0.04), Vector3(w - 0.3, 0.14, 0.1))
	_box(plate, Vector3(0, 0.82, 0.03), Vector3(0.5, 0.12, 0.02))
	for s in [-1.0, 1.0]:
		_box(tails, Vector3(s * (w / 2.0 - 0.28), 1.22, 0.025), Vector3(0.32, 0.18, 0.03))
		_box(sig_l if s < 0 else sig_r, Vector3(s * (w / 2.0 - 0.12), 1.22, 0.026), Vector3(0.12, 0.18, 0.03))
	# cab
	var cz := -(l - 1.25)
	_box(cab, Vector3(0, 1.85, cz), Vector3(w - 0.08, 2.7, 2.5))
	_box(cab, Vector3(0, 3.3, cz + 0.3), Vector3(w - 0.2, 0.5, 1.6))  # roof fairing
	_quad(glass, Vector3(-(w / 2.0 - 0.2), 2.2, -l - 0.006), Vector3(w / 2.0 - 0.2, 2.2, -l - 0.006),
		Vector3(w / 2.0 - 0.2, 3.0, -l - 0.006), Vector3(-(w / 2.0 - 0.2), 3.0, -l - 0.006), Vector3.FORWARD)
	for s in [-1.0, 1.0]:
		var x: float = s * (w / 2.0 - 0.03)
		_quad(glass, Vector3(x, 2.2, -l + 0.2), Vector3(x, 2.2, -l + 1.2), Vector3(x, 3.0, -l + 1.2), Vector3(x, 3.0, -l + 0.2), Vector3(s, 0, 0))
		_cyl(chrome, Vector3(s * (w / 2.0 - 0.25), 0.85, cz + 0.4), 0.28, 1.0, Vector3.BACK, 12)  # fuel tank
		_cyl(chrome, Vector3(s * (w / 2.0 - 0.15), 3.3, cz + 1.15), 0.07, 1.6, Vector3.UP, 8)   # exhaust stack
		_box(dark, Vector3(s * (w / 2.0 + 0.18), 2.6, -l + 0.4), Vector3(0.05, 0.5, 0.25))      # mirror
		_box(head, Vector3(s * (w / 2.0 - 0.35), 0.95, -l - 0.02), Vector3(0.4, 0.18, 0.04))
	_box(chrome, Vector3(0, 1.45, -l - 0.02), Vector3(w * 0.6, 0.9, 0.04))  # grille
	_box(chrome, Vector3(0, 0.6, -l - 0.06), Vector3(w, 0.3, 0.12))         # bumper

	var body := ArrayMesh.new()
	for st in [box, cab, glass, dark, chrome, plate, head]:
		st.commit(body)
	var wheels := []
	for s in [-1.0, 1.0]:
		for z in [-0.95, -2.15, -(l - 0.95)]:
			wheels.append([s * (w / 2.0 - 0.3), z])
	return {"body": body, "tails": tails.commit(), "sig_l": sig_l.commit(), "sig_r": sig_r.commit(),
		"wheels": wheels, "r": 0.5, "ww": 0.5, "truck": true}


# ---------------------------------------------------------------- instance

var shape: Dictionary
var _tails: MeshInstance3D
var _sig_l: MeshInstance3D
var _sig_r: MeshInstance3D
var _body: Node3D
var _wheels: Array[Node3D] = []
var _wheel_r := 0.32
var _spin := 0.0
var _braking := false


func build(shape_id: String, color: Color, cab_color := Color("#b5322a")) -> void:
	shape = Data.SHAPES[shape_id]
	var kit := _kit(shape_id)
	_body = Node3D.new()
	add_child(_body)

	var body := MeshInstance3D.new()
	body.mesh = kit.body
	var mats: Array[Material]
	if kit.get("truck", false):
		mats = [mat(color, 0.0, 0.55, 0.1), paint(cab_color), _glass(), mat(Color("#18191b"), 0.0, 0.7),
			mat(Color("#d9dde1"), 0.0, 0.15, 0.95), mat(Color("#e8e6dc"), 0.0, 0.6), mat(Color("#fff6d8"), 2.0)]
	else:
		mats = [paint(color), _glass(), mat(Color("#18191b"), 0.0, 0.6), mat(Color("#d9dde1"), 0.0, 0.15, 0.95),
			mat(Color("#e8e6dc"), 0.0, 0.6), mat(Color("#fff6d8"), 2.0)]
	for i in mats.size():
		body.set_surface_override_material(i, mats[i])
	_body.add_child(body)

	_tails = _light(kit.tails, _tail_mat(false))
	_sig_l = _light(kit.sig_l, mat(Color("#ffaa18"), 6.0))
	_sig_r = _light(kit.sig_r, mat(Color("#ffaa18"), 6.0))
	_sig_l.visible = false
	_sig_r.visible = false

	_wheel_r = kit.r
	var wm := _wheel_mesh(kit.r, kit.ww)
	for p in kit.wheels:
		var wn := Node3D.new()
		wn.position = Vector3(p[0], kit.r, p[1])
		var mi := MeshInstance3D.new()
		mi.mesh = wm
		wn.add_child(mi)
		add_child(wn)  # wheels stay level when the body rolls
		_wheels.append(wn)

	# soft contact shadow so cars sit on the road even beyond the shadow distance
	var sh := MeshInstance3D.new()
	sh.mesh = _shadow()
	sh.material_override = _shadow_mat
	sh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sh.scale = Vector3(shape.w + 0.7, 1.0, shape.l + 0.9)
	sh.position = Vector3(0, 0.02, -shape.l / 2.0)
	add_child(sh)


func _light(m: Mesh, material: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_body.add_child(mi)
	return mi


static func _glass() -> StandardMaterial3D:
	var key := "glass"
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = Color("#141c25")
		m.metallic = 0.9
		m.metallic_specular = 0.8
		m.roughness = 0.04
		_mats[key] = m
	return _mats[key]


static func _tail_mat(on: bool) -> StandardMaterial3D:
	return mat(Color("#ff2414"), 7.0, 0.3) if on else mat(Color("#8c1010"), 0.9, 0.25)


static func _shadow() -> PlaneMesh:
	if _shadow_mesh == null:
		_shadow_mesh = PlaneMesh.new()
		_shadow_mesh.size = Vector2(1, 1)
		var g := Gradient.new()
		g.set_color(0, Color(0, 0, 0, 0.62))
		g.set_color(1, Color(0, 0, 0, 0.0))
		g.add_point(0.55, Color(0, 0, 0, 0.45))
		var tex := GradientTexture2D.new()
		tex.gradient = g
		tex.fill = GradientTexture2D.FILL_RADIAL
		tex.fill_from = Vector2(0.5, 0.5)
		tex.fill_to = Vector2(0.5, 0.0)
		tex.width = 64
		tex.height = 64
		_shadow_mat = StandardMaterial3D.new()
		_shadow_mat.albedo_texture = tex
		_shadow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_shadow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_shadow_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	return _shadow_mesh


func set_brake(on: bool) -> void:
	if on == _braking:
		return
	_braking = on
	_tails.material_override = _tail_mat(on)


## dir: -1 left, 1 right, 0 off. lit toggles the blink phase.
func set_signal(dir: int, lit: bool) -> void:
	_sig_l.visible = dir < 0 and lit
	_sig_r.visible = dir > 0 and lit


## Lean the body (not the wheels) for a sense of weight when steering.
func set_roll(r: float) -> void:
	if _body:
		_body.rotation.z = r


## Pitch the body: positive dips the nose (braking), negative squats (accelerating).
func set_pitch(p: float) -> void:
	if _body:
		_body.rotation.x = -p


## Turn the wheels for a car travelling at v m/s.
func spin(v: float, dt: float) -> void:
	_spin = fmod(_spin - v / _wheel_r * dt, TAU)
	for wn in _wheels:
		wn.rotation.x = _spin
