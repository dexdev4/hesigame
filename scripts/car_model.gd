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
		"body": [[0.0, 0.82, 0.9], [0.1, 0.88, 0.97], [0.5, 0.9, 1.0], [2.4, 0.92, 1.0], [3.3, 0.86, 1.0], [3.72, 0.8, 0.97], [3.94, 0.72, 0.92], [4.0, 0.64, 0.87]],
		"gh": [0.12, 3.25, 0.32, 2.35, 0.9, 1.47, 0.94, 0.8], "pillars": [[0.0, 0.16], [0.47, 0.52], [0.92, 1.0]],
		"wheel": [0.31, 0.76, 3.25], "exhaust": 1},
	"sedan": {
		"body": [[0.0, 0.78, 0.9], [0.14, 0.84, 0.97], [0.9, 0.87, 1.0], [3.0, 0.87, 1.0], [3.9, 0.84, 1.0], [4.42, 0.78, 0.97], [4.64, 0.7, 0.92], [4.7, 0.64, 0.87]],
		"gh": [1.0, 3.72, 1.55, 3.02, 0.87, 1.42, 0.94, 0.8], "pillars": [[0.0, 0.14], [0.5, 0.55], [0.93, 1.0]],
		"wheel": [0.32, 0.95, 3.75], "exhaust": 2},
	"suv": {
		"body": [[0.0, 1.0, 0.92], [0.12, 1.05, 0.98], [0.6, 1.08, 1.0], [3.6, 1.08, 1.0], [4.2, 1.04, 1.0], [4.62, 0.98, 0.96], [4.8, 0.88, 0.9]],
		"gh": [0.22, 3.9, 0.36, 3.3, 1.08, 1.8, 0.95, 0.86], "pillars": [[0.0, 0.1], [0.36, 0.4], [0.66, 0.7], [0.94, 1.0]],
		"wheel": [0.38, 0.92, 3.85], "exhaust": 1},
	# compact performance saloon after the 2007 E90 M3: 4.58 m long, 1.82 m wide,
	# 2.76 m wheelbase, short rear and front overhangs, long bonnet, high short
	# boot, kinked C-pillar, quad exhausts
	"msedan": {
		"body": [[0.0, 0.76, 0.9], [0.08, 0.86, 0.96], [0.22, 0.92, 0.99], [0.85, 0.93, 1.0], [3.1, 0.92, 1.0], [3.6, 0.88, 1.0], [4.1, 0.85, 0.98], [4.44, 0.8, 0.94], [4.58, 0.7, 0.88]],
		"gh": [0.88, 3.1, 1.42, 2.5, 0.92, 1.43, 0.93, 0.78], "pillars": [[0.0, 0.16], [0.47, 0.51], [0.92, 1.0]],
		"kink": [0.16, 0.25, 0.34], "wheel": [0.335, 0.98, 3.74], "exhaust": 4, "exhaust_pairs": true},
	"muscle": {
		"body": [[0.0, 0.8, 0.92], [0.18, 0.86, 0.98], [1.2, 0.87, 1.0], [3.2, 0.86, 1.0], [4.35, 0.8, 0.98], [4.72, 0.72, 0.93], [4.8, 0.64, 0.89]],
		"gh": [1.2, 3.3, 1.55, 2.86, 0.87, 1.32, 0.92, 0.76], "pillars": [[0.0, 0.2], [0.9, 1.0]],
		"wheel": [0.35, 0.95, 3.85], "exhaust": 2, "spoiler": "lip"},
	"super": {
		"body": [[0.0, 0.7, 0.92], [0.18, 0.77, 0.98], [1.0, 0.81, 1.0], [2.2, 0.75, 1.0], [3.4, 0.68, 1.0], [4.2, 0.6, 0.96], [4.5, 0.5, 0.9]],
		"gh": [0.95, 3.3, 1.4, 2.6, 0.78, 1.14, 0.88, 0.7], "pillars": [[0.0, 0.25], [0.9, 1.0]],
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


## Emissive lamp that fades out with distance. A lit pixel that flickers on
## and off at the horizon (and gets bloomed) reads as a flashing car, so far
## lamps dissolve smoothly instead.
static func lamp(c: Color, glow: float) -> StandardMaterial3D:
	var key := "lamp|%s|%s" % [c.to_html(), glow]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.3
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = glow
	m.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_DITHER
	m.distance_fade_min_distance = 230.0  # min > max: fully faded beyond 230 m, solid within 110 m
	m.distance_fade_max_distance = 110.0
	_mats[key] = m
	return m


## Glossy car paint with a clear coat.
## Glossy metallic paint with a clear coat.
static func paint(c: Color) -> StandardMaterial3D:
	var key := "paint|%s" % c.to_html()
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c.darkened(0.08)
	m.metallic = 0.25
	m.metallic_specular = 0.5
	m.roughness = 0.3
	m.clearcoat_enabled = true
	m.clearcoat = 1.0
	m.clearcoat_roughness = 0.06
	m.rim_enabled = true  # sheen along panel edges facing away from the light
	m.rim = 0.12
	m.rim_tint = 0.6
	m.vertex_color_use_as_albedo = true  # baked occlusion from BodyBuilder (white elsewhere)
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
	var y2 := maxf(top - 0.2, b + 0.16)
	var y1 := minf(b + 0.14, y2 - 0.02)
	var rise := top - y2
	var right := [
		[Vector2(hw * 0.93, b), Vector2(0.3, -1)],
		[Vector2(hw, y1), Vector2(1, -0.2)],
		[Vector2(hw, y2), Vector2(1, 0.05)],
	]
	# rounded shoulder: quarter ellipse from the side up to the top surface
	for deg in [30.0, 60.0, 90.0]:
		var a := deg_to_rad(deg)
		right.append([Vector2(hw * (0.8 + 0.2 * cos(a)), y2 + rise * sin(a)), Vector2(cos(a) / 0.2, sin(a) * hw / maxf(rise, 0.05)).normalized()])
	right.append([Vector2(hw * 0.4, top + 0.014), Vector2(0.06, 1)])  # crowned bonnet and boot lid
	var ring := []
	for p in right:
		ring.append(p)
	for i in range(right.size() - 1, -1, -1):
		var p: Array = right[i]
		ring.append([Vector2(-p[0].x, p[0].y), Vector2(-p[1].x, p[1].y)])
	return ring


## Catmull-Rom resampling of body stations so the profile curves smoothly.
static func _smooth(st: Array, sub := 3) -> Array:
	var out := []
	var n := st.size()
	for i in n - 1:
		var p0: Array = st[maxi(i - 1, 0)]
		var p1: Array = st[i]
		var p2: Array = st[i + 1]
		var p3: Array = st[mini(i + 2, n - 1)]
		for k in sub:
			var t := float(k) / sub
			var row := []
			for c in 3:
				var a: float = p0[c]
				var b: float = p1[c]
				var cc: float = p2[c]
				var d: float = p3[c]
				row.append(0.5 * (2.0 * b + (-a + cc) * t + (2.0 * a - 5.0 * b + 4.0 * cc - d) * t * t + (-a + 3.0 * b - 3.0 * cc + d) * t * t * t))
			out.append(row)
	out.append(st[n - 1])
	return out


## Surface of revolution around X from a profile of (radius, x) points.
static func _lathe(st: SurfaceTool, profile: Array, segs: int) -> void:
	for i in profile.size() - 1:
		var a: Vector2 = profile[i]
		var b: Vector2 = profile[i + 1]
		var dr := b.x - a.x
		var dx := b.y - a.y
		var nr := dx
		var nx := -dr
		var nl := sqrt(nr * nr + nx * nx)
		if nl < 0.00001:
			continue
		nr /= nl
		nx /= nl
		for k in segs:
			var t0 := TAU * k / segs
			var t1 := TAU * (k + 1) / segs
			var d0 := Vector3(0, cos(t0), sin(t0))
			var d1 := Vector3(0, cos(t1), sin(t1))
			var pa := Vector3(a.y, 0, 0) + d0 * a.x
			var pb := Vector3(a.y, 0, 0) + d1 * a.x
			var pc := Vector3(b.y, 0, 0) + d1 * b.x
			var pd := Vector3(b.y, 0, 0) + d0 * b.x
			var n0 := d0 * nr + Vector3(nx, 0, 0)
			var n1 := d1 * nr + Vector3(nx, 0, 0)
			_tri(st, pa, pb, pc, n0, n1, n1)
			_tri(st, pa, pc, pd, n0, n1, n0)


const RIM_STYLES := ["steel", "5spoke", "multi", "mesh", "turbine", "double"]


static func _wheel_mesh(r: float, width: float, style := "5spoke", rim_col := Color("#c3c8ce")) -> ArrayMesh:
	var key := "wheel%s_%s_%s_%s" % [r, width, style, rim_col.to_html()]
	if _meshes.has(key):
		return _meshes[key]
	var hw := width / 2.0
	var tire := _new_st()
	# rounded tyre: bead, bulging sidewall, shoulder, tread and back again
	_lathe(tire, [Vector2(0.64 * r, -hw + 0.01), Vector2(0.86 * r, -hw - 0.008), Vector2(0.96 * r, -hw + 0.015),
		Vector2(r, -hw + 0.055), Vector2(r, hw - 0.055), Vector2(0.96 * r, hw - 0.015), Vector2(0.86 * r, hw + 0.008),
		Vector2(0.64 * r, hw - 0.01)], 20)
	var rim := _new_st()
	var brake := _new_st()
	for side in [-1.0, 1.0]:
		var face: float = side * (hw + 0.002)
		# dark wheel well behind the spokes, then the brake disc
		_cyl(tire, Vector3(face - side * 0.08, 0, 0), r * 0.62, 0.01, Vector3.RIGHT, 16)
		_cyl(brake, Vector3(face - side * 0.055, 0, 0), r * 0.47, 0.022, Vector3.RIGHT, 18)
		# rim lip
		_lathe(rim, [Vector2(r * 0.6, face - side * 0.05), Vector2(r * 0.66, face - side * 0.012), Vector2(r * 0.66, face), Vector2(r * 0.6, face + side * 0.004)], 22)
		var c := Vector3(face - side * 0.012, 0, 0)
		match style:
			"steel":
				_cyl(rim, c - Vector3(side * 0.01, 0, 0), r * 0.6, 0.012, Vector3.RIGHT, 18)
				for k in 6:
					var b := Basis(Vector3.RIGHT, TAU * k / 6.0)
					_cyl(tire, c + Vector3(side * 0.001, 0, 0) + b.y * r * 0.4, r * 0.06, 0.014, Vector3.RIGHT, 8)
			"multi":
				for k in 10:
					var b := Basis(Vector3.RIGHT, TAU * k / 10.0)
					_box(rim, c + b.y * r * 0.36, Vector3(0.022, r * 0.5, 0.03), b)
			"mesh":
				for k in 8:
					for tw in [-0.22, 0.22]:
						var b := Basis(Vector3.RIGHT, TAU * k / 8.0) * Basis(Vector3.RIGHT, tw)
						_box(rim, c + b.y * r * 0.34, Vector3(0.018, r * 0.52, 0.022), b)
			"turbine":
				for k in 12:
					var b := Basis(Vector3.RIGHT, TAU * k / 12.0) * Basis(Vector3.UP, 0.5)
					_box(rim, c + b.y * r * 0.36, Vector3(0.02, r * 0.5, 0.045), b)
			"double":  # five pairs of slim spokes
				for k in 5:
					for tw in [-0.12, 0.12]:
						var b := Basis(Vector3.RIGHT, TAU * k / 5.0 + tw)
						_box(rim, c + b.y * r * 0.35, Vector3(0.026, r * 0.55, 0.032), b)
			_:  # 5spoke
				for k in 5:
					var b := Basis(Vector3.RIGHT, TAU * k / 5.0)
					_box(rim, c + b.y * r * 0.34, Vector3(0.03, r * 0.54, 0.085), b)
		_cyl(rim, c + Vector3(side * 0.008, 0, 0), r * 0.17, 0.035, Vector3.RIGHT, 12)
		for k in 5:  # lug nuts
			var b := Basis(Vector3.RIGHT, TAU * k / 5.0 + 0.3)
			_cyl(brake, c + Vector3(side * 0.028, 0, 0) + b.y * r * 0.1, r * 0.025, 0.02, Vector3.RIGHT, 6)
	var m := ArrayMesh.new()
	tire.commit(m)
	rim.commit(m)
	brake.commit(m)
	m.surface_set_material(0, mat(Color("#141517"), 0.0, 0.9))
	m.surface_set_material(1, mat(rim_col, 0.0, 0.22, 0.85) if style != "steel" else mat(Color("#6f7378"), 0.0, 0.5, 0.5))
	m.surface_set_material(2, mat(Color("#6d7176"), 0.0, 0.45, 0.8))
	_meshes[key] = m
	return m


## Interpolates a body station value (1 = top height, 2 = width scale) at a distance from the rear.
static func _station_at(stations: Array, d: float, idx: int) -> float:
	for i in stations.size() - 1:
		var a: Array = stations[i]
		var b: Array = stations[i + 1]
		if d <= b[0]:
			return lerpf(a[idx], b[idx], clampf((d - a[0]) / maxf(b[0] - a[0], 0.001), 0.0, 1.0))
	return stations[stations.size() - 1][idx]


## Flat half-annulus (upper half) on a car side: wheel arches.
static func _arch(st: SurfaceTool, x: float, cy: float, cz: float, r0: float, r1: float, n: Vector3) -> void:
	var segs := 12
	for i in segs:
		var a0 := PI * i / segs
		var a1 := PI * (i + 1) / segs
		var p0 := Vector3(x, cy + sin(a0) * r0, cz + cos(a0) * r0)
		var p1 := Vector3(x, cy + sin(a1) * r0, cz + cos(a1) * r0)
		var q0 := Vector3(x, cy + sin(a0) * r1, cz + cos(a0) * r1)
		var q1 := Vector3(x, cy + sin(a1) * r1, cz + cos(a1) * r1)
		_quad(st, p0, p1, q1, q0, n)


# ---------------------------------------------------------------- per-type kits

## Builds (once) the shared meshes for a vehicle type.
## Body surfaces: 0 paint, 1 glass, 2 dark trim, 3 chrome, 4 plate, 5 headlights.
## Body options that change geometry. Anything else (rims, badges) is per instance.
const KIT_KEYS := ["stripes", "scoop", "intakes", "roofwing", "wiper", "lightbar", "splitter", "vents", "dome", "gills", "split_grille", "ltail", "halo", "lip", "crease", "m_bumper", "quad_diffuser"]


static func _kit(id: String, style := {}) -> Dictionary:
	var key := id
	for k in KIT_KEYS:
		if style.get(k, false):
			key += "|" + k
	if _kits.has(key):
		return _kits[key]
	var kit := {}
	if id == "truck":
		kit = _truck_kit()
	else:
		kit = _car_kit(id, style)
	_kits[key] = kit
	return kit


static func _new_st() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_color(Color.WHITE)
	st.set_uv(Vector2.ZERO)
	return st


## Surfaces of a car body mesh, in commit order (empty ones are skipped).
const SURFACES := ["paint", "glass", "glass_solid", "dark", "gloss", "under", "chrome", "plate", "head", "headlens", "grille", "accent"]


static func _car_kit(id: String, style := {}) -> Dictionary:
	var sh: Dictionary = Data.SHAPES[id]
	var pr: Dictionary = PROFILES[id]
	var w: float = sh.w
	var l: float = sh.l
	var S := {}
	for k in SURFACES:
		S[k] = _new_st()
	var paint_st: SurfaceTool = S.paint
	var dark: SurfaceTool = S.dark
	var chrome: SurfaceTool = S.chrome
	var plate: SurfaceTool = S.plate
	var head: SurfaceTool = S.head
	var accent: SurfaceTool = S.accent
	var tails := _new_st()
	tails.set_uv(BodyBuilder.LED_UV)
	var sig_l := _new_st()
	var sig_r := _new_st()
	var bb: BodyBuilder = null
	var stations: Array
	var rear_top: float
	var rear_hw: float
	var front_top: float
	var front_hw: float
	var sill: float
	if pr.has("gh"):
		# smooth one-piece body with glass, lights and grille (scripts/body_builder.gd)
		bb = BodyBuilder.new(id, pr, sh, style)
		bb.emit(S)
		bb.details(S, tails, sig_l, sig_r)
		bb.lights(S, tails, sig_l, sig_r)
		stations = bb.stations
		rear_top = bb.top(0.0)
		rear_hw = bb.hw(0.0)
		front_top = bb.top(l)
		front_hw = bb.hw(l)
		sill = bb.floor_y
	else:
		# vans: a lofted box body
		stations = _smooth(pr.body)
		var rings := []
		for st0 in stations:
			rings.append(_ring(w / 2.0 * st0[2], st0[1]))
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
		for e in [0, stations.size() - 1]:
			var rg: Array = rings[e]
			var z: float = -stations[e][0]
			var n := Vector3(0, 0, 1) if e == 0 else Vector3(0, 0, -1)
			var cy := 0.0
			for q in rg:
				cy += q[0].y
			var ctr := Vector3(0, cy / rg.size(), z)
			for j in rg.size():
				var j2 := (j + 1) % rg.size()
				_tri(paint_st, ctr, Vector3(rg[j][0].x, rg[j][0].y, z), Vector3(rg[j2][0].x, rg[j2][0].y, z), n, n, n)
		rear_top = stations[0][1]
		rear_hw = w / 2.0 * stations[0][2]
		front_top = stations[stations.size() - 1][1]
		front_hw = w / 2.0 * stations[stations.size() - 1][2]
		sill = minf(0.3, rear_top - 0.3)
		var glass: SurfaceTool = S.glass_solid
		var hw2 := w / 2.0
		_quad(glass, Vector3(-hw2 * 0.86, 1.4, 0.006), Vector3(-0.05, 1.4, 0.006), Vector3(-0.05, 2.0, 0.006), Vector3(-hw2 * 0.86, 2.0, 0.006), Vector3.BACK)
		_quad(glass, Vector3(0.05, 1.4, 0.006), Vector3(hw2 * 0.86, 1.4, 0.006), Vector3(hw2 * 0.86, 2.0, 0.006), Vector3(0.05, 2.0, 0.006), Vector3.BACK)
		_box(dark, Vector3(0, 1.2, 0.01), Vector3(0.03, 1.6, 0.02))
		var wn := Vector3(0, 0.88, -0.48).normalized()
		_quad(glass, Vector3(-hw2 * 0.86, 1.45, -4.6), Vector3(hw2 * 0.86, 1.45, -4.6), Vector3(hw2 * 0.86, 2.08, -4.33), Vector3(-hw2 * 0.86, 2.08, -4.33), wn)
		for sd in [-1.0, 1.0]:
			var x: float = sd * (hw2 + 0.006)
			_quad(glass, Vector3(x, 1.45, -3.55), Vector3(x, 1.45, -4.25), Vector3(x, 2.0, -4.25), Vector3(x, 2.0, -3.55), Vector3(sd, 0, 0))
			_box(paint_st, Vector3(sd * (hw2 + 0.1), 1.6, -4.4), Vector3(0.12, 0.2, 0.08))

	# --- rear details
	var bumper_y := sill + 0.07
	_box(paint_st, Vector3(0, bumper_y + 0.05, -0.1), Vector3(rear_hw * 2.0 * 0.98, 0.2, 0.26))
	_box(dark, Vector3(0, bumper_y - 0.07, -0.1), Vector3(rear_hw * 2.0 * 0.9, 0.07, 0.25))
	_box(plate, Vector3(0, bumper_y + 0.2, 0.012), Vector3(0.52, 0.12, 0.02))
	if bb == null:
		var ty0 := 1.05
		var ty1 := 1.3
		var tz := 0.012
		for sd in [-1.0, 1.0]:
			var x0: float = sd * rear_hw * 0.66
			var x1: float = sd * rear_hw * 0.93
			var tcy := (ty0 + ty1) / 2.0
			var th := ty1 - ty0
			_box(dark, Vector3((x0 + x1) / 2.0 - sd * 0.02, tcy, tz - 0.004), Vector3(absf(x1 - x0) + 0.1, th + 0.03, 0.03))
			_box(head, Vector3(sd * rear_hw * 0.61, tcy, tz), Vector3(rear_hw * 0.1, th * 0.9, 0.028))
			_box(tails, Vector3((x0 + x1) / 2.0, tcy, tz + 0.004), Vector3(absf(x1 - x0), th * 0.8, 0.03))
			_box(sig_l if sd < 0 else sig_r, Vector3(sd * rear_hw * 0.5, tcy, tz), Vector3(0.12, th * 0.8, 0.032))
	var ex: int = pr.get("exhaust", 1)
	var ex_x: Array = [-rear_hw * 0.62] if ex == 1 else ([-rear_hw * 0.6, rear_hw * 0.6] if ex == 2 else [-0.22, -0.08, 0.08, 0.22])
	if pr.get("exhaust_pairs", false):
		ex_x = [-rear_hw * 0.66, -rear_hw * 0.66 + 0.12, rear_hw * 0.66 - 0.12, rear_hw * 0.66]
	for x in ex_x:
		_cyl(chrome, Vector3(x, bumper_y - 0.04, 0.02), 0.045 if ex < 4 else 0.04, 0.16, Vector3.BACK, 10, false)
		_cyl(dark, Vector3(x, bumper_y - 0.04, 0.025), 0.033, 0.16, Vector3.BACK, 8, true)
	if pr.get("diffuser", false):
		for k in 5:
			_box(dark, Vector3(-0.5 + k * 0.25, sill - 0.02, -0.32), Vector3(0.03, 0.1, 0.5))
	match pr.get("spoiler", ""):
		"wing":
			var wt: float = bb.top(0.3) if bb else rear_top
			_box(dark, Vector3(0, wt + 0.3, -0.3), Vector3(w - 0.14, 0.05, 0.38), Basis(Vector3.RIGHT, -0.1))
			for sd in [-1.0, 1.0]:
				_box(dark, Vector3(sd * 0.48, wt + 0.14, -0.3), Vector3(0.05, 0.3, 0.12))
				_box(dark, Vector3(sd * (w / 2.0 - 0.08), wt + 0.27, -0.3), Vector3(0.03, 0.14, 0.42))
		"lip":
			var lt: float = bb.top(0.14) if bb else rear_top
			_box(paint_st, Vector3(0, lt + 0.035, -0.14), Vector3(w * 0.82, 0.05, 0.16), Basis(Vector3.RIGHT, 0.15))

	# --- front details (the smooth bodies get theirs from BodyBuilder.lights)
	if bb == null:
		var fz := -l - 0.012
		for sd in [-1.0, 1.0]:
			var hx: float = sd * front_hw * 0.68
			var hy := front_top - 0.1
			_box(dark, Vector3(hx, hy, fz + 0.035), Vector3(front_hw * 0.46, 0.13, 0.03))
			_box(head, Vector3(hx, hy, fz + 0.015), Vector3(front_hw * 0.42, 0.08, 0.03))
		_box(chrome, Vector3(0, front_top - 0.13, fz + 0.03), Vector3(front_hw * 0.62, 0.17, 0.03))
		_box(dark, Vector3(0, front_top - 0.13, fz + 0.015), Vector3(front_hw * 0.56, 0.13, 0.03))
		_box(dark, Vector3(0, sill + 0.12, fz + 0.03), Vector3(front_hw * 0.9, 0.14, 0.04))

	var r: float = pr.wheel[0]
	_style_extras(id, style, pr, stations, w, l, sill, rear_top, front_top, paint_st, dark, chrome, accent, S.glass, bb)
	_details(id, pr, stations, w, l, sill, dark, paint_st, chrome, head, bb)
	if bb == null:
		for sd in [-1.0, 1.0]:
			var n := Vector3(sd, 0, 0)
			for ax in [pr.wheel[1], pr.wheel[2]]:
				var hx: float = w / 2.0 * _station_at(stations, ax, 2)
				_arch(dark, sd * (hx + 0.006), r, -ax, 0.0, r + 0.04, n)
				_arch(dark, sd * (hx + 0.008), r, -ax, r + 0.04, r + 0.085, n)

	var kit := {
		"tails": tails.commit(), "sig_l": sig_l.commit(), "sig_r": sig_r.commit(),
		"wheels": [[-(w / 2.0 - 0.11), -pr.wheel[1]], [w / 2.0 - 0.11, -pr.wheel[1]], [-(w / 2.0 - 0.11), -pr.wheel[2]], [w / 2.0 - 0.11, -pr.wheel[2]]],
		"r": r, "ww": 0.24, "plate_y": bumper_y + 0.2,
	}
	var body := ArrayMesh.new()
	var names: Array = []
	for k in SURFACES:
		(S[k] as SurfaceTool).index()  # share vertices between neighbouring quads: far less for the GPU to process
		var arr: Array = (S[k] as SurfaceTool).commit_to_arrays()
		var verts: Variant = arr[Mesh.ARRAY_VERTEX]
		if verts == null or (verts as PackedVector3Array).is_empty():
			continue
		body.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		names.append(k)
	kit["body"] = body
	kit["surfaces"] = names
	if bb:
		kit["cabin"] = bb.cabin_mesh()
	return kit


## Details every car has: bonnet and boot shut lines, fuel filler, roof rails,
## fog lights and the number-plate light.
static func _details(id: String, pr: Dictionary, stations: Array, w: float, l: float, sill: float,
		dark: SurfaceTool, paint_st: SurfaceTool, chrome: SurfaceTool, head: SurfaceTool, bb: BodyBuilder = null) -> void:
	var g: Array = pr.get("gh", [])
	var fz := -l - 0.012
	var front_hw: float = w / 2.0 * stations[stations.size() - 1][2]
	if bb == null:
		for s in [-1.0, 1.0]:
			_box(head, Vector3(s * front_hw * 0.72, sill + 0.1, fz + 0.012), Vector3(0.12, 0.045, 0.02))  # fog lights
		_box(head, Vector3(0, sill + 0.36, 0.03), Vector3(0.12, 0.012, 0.02))  # plate light
	if not g.is_empty():
		var lines := func(d0: float, d1: float, across: float) -> void:
			for i in stations.size() - 1:
				var a: Array = stations[i]
				var b: Array = stations[i + 1]
				if b[0] < d0 or a[0] > d1:
					continue
				var za: float = -maxf(a[0], d0)
				var zb: float = -minf(b[0], d1)
				for sx in [-1.0, 1.0]:
					var x: float = sx * w / 2.0 * a[2] * 0.78
					var y0: float = (bb.surf_y(-za, x) + 0.003) if bb else (_station_at(stations, -za, 1) + 0.006)
					var y1: float = (bb.surf_y(-zb, x) + 0.003) if bb else (_station_at(stations, -zb, 1) + 0.006)
					_quad(dark, Vector3(x - 0.004, y0, za), Vector3(x + 0.004, y0, za), Vector3(x + 0.004, y1, zb), Vector3(x - 0.004, y1, zb), Vector3.UP)
			var hw: float = w / 2.0 * _station_at(stations, across, 2) * 0.78
			for k in 8:
				var xa := lerpf(-hw, hw, k / 8.0)
				var xb := lerpf(-hw, hw, (k + 1) / 8.0)
				var ya: float = (bb.surf_y(across, xa) + 0.003) if bb else (_station_at(stations, across, 1) + 0.015)
				var yb: float = (bb.surf_y(across, xb) + 0.003) if bb else (_station_at(stations, across, 1) + 0.015)
				_quad(dark, Vector3(xa, ya, -across - 0.004), Vector3(xb, yb, -across - 0.004), Vector3(xb, yb, -across + 0.004), Vector3(xa, ya, -across + 0.004), Vector3.UP)
		lines.call(g[1] + 0.06, l - 0.24, l - 0.24)   # bonnet
		if g[0] > 0.5:
			lines.call(0.14, g[0] - 0.06, 0.14)        # boot lid
		# fuel filler on the right rear quarter (BodyBuilder adds its own)
		var fd: float = pr.wheel[1] + pr.wheel[0] + 0.3
		if bb:
			fd = -10.0
		if fd > 0.0:
			var fx: float = w / 2.0 * _station_at(stations, fd, 2)
			_box(dark, Vector3(fx + 0.004, g[4] - 0.17, -fd), Vector3(0.01, 0.15, 0.15))
			_box(paint_st, Vector3(fx + 0.008, g[4] - 0.17, -fd), Vector3(0.01, 0.135, 0.135))
		if id == "suv":
			var hr: float = w / 2.0 * g[7]
			for sx in [-1.0, 1.0]:
				_box(dark, Vector3(sx * (hr - 0.08), g[5] + 0.08, -(g[2] + g[3]) / 2.0), Vector3(0.04, 0.035, g[3] - g[2] - 0.1))
				for t in 3:
					_box(dark, Vector3(sx * (hr - 0.08), g[5] + 0.035, -lerpf(g[2] + 0.1, g[3] - 0.1, t / 2.0)), Vector3(0.05, 0.07, 0.06))
	elif pr.get("van", false):
		for sx in [-1.0, 1.0]:
			_box(dark, Vector3(sx * w * 0.4, 2.33, -2.2), Vector3(0.05, 0.04, 3.6))
			for t in 4:
				_box(dark, Vector3(sx * w * 0.4, 2.28, -0.6 - t * 1.1), Vector3(0.06, 0.08, 0.08))


## Geometry for a car's styling kit: racing stripes, bonnet scoop, side
## intakes, roof spoiler, rear wiper, splitter and skirts, bonnet vents.
static func _style_extras(id: String, style: Dictionary, pr: Dictionary, stations: Array, w: float, l: float, sill: float,
		rear_top: float, front_top: float, paint_st: SurfaceTool, dark: SurfaceTool, chrome: SurfaceTool, accent: SurfaceTool, glass: SurfaceTool, bb: BodyBuilder = null) -> void:
	var g: Array = pr.get("gh", [])
	# body side x at a height (smooth bodies), or the profile width
	var side_x := func(d: float, y: float) -> float:
		return (bb.side_pn(d, y)[0] as Vector3).x if bb else w / 2.0 * _station_at(stations, d, 2)
	var top_at := func(d: float, x: float, lift: float) -> float:
		return bb.surf_y(d, x) + 0.004 if bb else _station_at(stations, d, 1) + lift
	if style.get("stripes", false):
		# twin stripes over boot and bonnet, following the crowned top surface
		for i in stations.size() - 1:
			var a: Array = stations[i]
			var b: Array = stations[i + 1]
			if not g.is_empty() and a[0] >= g[0] - 0.05 and b[0] <= g[1] + 0.05:
				continue  # the greenhouse covers this part
			for sx in [-1.0, 1.0]:
				var ya: float = top_at.call(a[0], 0.17, 0.018)
				var yb: float = top_at.call(b[0], 0.17, 0.018)
				_quad(accent, Vector3(sx * 0.07, ya, -a[0]), Vector3(sx * 0.27, ya, -a[0]),
					Vector3(sx * 0.27, yb, -b[0]), Vector3(sx * 0.07, yb, -b[0]), Vector3.UP)
		for sx in [-1.0, 1.0]:  # down the rear panel
			_box(accent, Vector3(sx * 0.17, rear_top - 0.15, 0.014), Vector3(0.2, 0.3, 0.01))
	if style.get("scoop", false) and not g.is_empty():
		var d: float = g[1] + 0.55
		var top := _station_at(stations, d, 1)
		_box(paint_st, Vector3(0, top + 0.04, -d), Vector3(0.62, 0.08, 0.8))
		_box(dark, Vector3(0, top + 0.05, -d - 0.405), Vector3(0.5, 0.05, 0.02))
	if style.get("dome", false) and not g.is_empty():  # raised power dome down the bonnet
		var d0: float = g[1] + 0.12
		var d1: float = l - 0.4
		var mid := (d0 + d1) / 2.0
		var top := _station_at(stations, mid, 1)
		_box(paint_st, Vector3(0, top + 0.022, -mid), Vector3(0.46, 0.04, d1 - d0), Basis(Vector3.RIGHT, -0.06))
	if style.get("gills", false) and not g.is_empty():  # vents behind the front wheels
		var gd: float = pr.wheel[2] - pr.wheel[0] - 0.22
		for sx in [-1.0, 1.0]:
			var hx: float = side_x.call(gd, g[4] - 0.2)
			_box(chrome, Vector3(sx * (hx + 0.006), g[4] - 0.2, -gd), Vector3(0.012, 0.08, 0.2))
			for k in 2:
				_box(dark, Vector3(sx * (hx + 0.01), g[4] - 0.22 + k * 0.035, -gd), Vector3(0.012, 0.012, 0.17))
	if style.get("crease", false) and not g.is_empty():  # shoulder line running from the front wheel to the tail light
		for sx in [-1.0, 1.0]:
			var d0 := 0.3
			var d1: float = pr.wheel[2] - pr.wheel[0] - 0.05
			var steps := 6
			for k in steps:
				var da := lerpf(d0, d1, float(k) / steps)
				var db := lerpf(d0, d1, float(k + 1) / steps)
				var ya: float = g[4] - 0.11 - 0.03 * float(k) / steps
				var yb2: float = g[4] - 0.11 - 0.03 * float(k + 1) / steps
				var xa: float = sx * (side_x.call(da, ya) + 0.004)
				var xb: float = sx * (side_x.call(db, yb2) + 0.004)
				_quad(dark, Vector3(xa, ya - 0.005, -da), Vector3(xb, yb2 - 0.005, -db), Vector3(xb, yb2 + 0.005, -db), Vector3(xa, ya + 0.005, -da), Vector3(sx, 0, 0))
	if style.get("m_bumper", false):  # deep front bumper: big outer intakes either side of the centre intake
		var fz2 := -l - 0.01
		var fhw: float = w / 2.0 * stations[stations.size() - 1][2]
		for sx in [-1.0, 1.0]:
			_box(dark, Vector3(sx * fhw * 0.66, sill + 0.17, fz2 + 0.02), Vector3(0.24, 0.2, 0.04))
			_box(chrome, Vector3(sx * fhw * 0.66, sill + 0.27, fz2 + 0.025), Vector3(0.24, 0.012, 0.03))
	if style.get("quad_diffuser", false):  # black rear valance framing the four exhausts
		var rhw: float = w / 2.0 * stations[0][2]
		_box(dark, Vector3(0, sill + 0.03, 0.025), Vector3(rhw * 1.9, 0.14, 0.04))
		for k in 4:
			_box(dark, Vector3(-0.18 + k * 0.12, sill - 0.02, -0.1), Vector3(0.025, 0.08, 0.3))
	if style.get("lip", false) and not g.is_empty():  # small boot-lid spoiler
		var lt: float = bb.top(0.1) if bb else rear_top
		_box(paint_st, Vector3(0, lt + 0.03, -0.1), Vector3(w * 0.7, 0.03, 0.1), Basis(Vector3.RIGHT, 0.18))
	if style.get("vents", false) and not g.is_empty():
		for sx in [-1.0, 1.0]:
			var d2: float = g[1] + 0.35
			for k in 4:
				var t2: float = top_at.call(d2 + k * 0.07, 0.32, 0.012)
				_box(dark, Vector3(sx * 0.32, t2 + 0.002, -d2 - k * 0.07), Vector3(0.3, 0.012, 0.035))
	if style.get("intakes", false):
		var rz: float = pr.wheel[0] + pr.wheel[1] + 0.15
		for sx in [-1.0, 1.0]:
			var hx: float = side_x.call(rz + 0.3, sill + 0.38)
			_box(dark, Vector3(sx * (hx - 0.01), sill + 0.38, -rz - 0.3), Vector3(0.04, 0.24, 0.55))
			for k in 3:
				_box(chrome, Vector3(sx * (hx + 0.005), sill + 0.3 + k * 0.08, -rz - 0.3), Vector3(0.012, 0.012, 0.52))
	if style.get("roofwing", false) and not g.is_empty():
		_box(paint_st, Vector3(0, g[5] + 0.015, -g[2] + 0.06), Vector3(w * 0.78, 0.035, 0.26), Basis(Vector3.RIGHT, -0.12))
		_box(dark, Vector3(0, g[5] - 0.02, -g[2] + 0.12), Vector3(w * 0.7, 0.03, 0.04))
	if style.get("wiper", false) and not g.is_empty():
		var base := Vector3(0, g[4] + 0.1, -g[0] - 0.04)
		var tip := Vector3(-0.42, g[4] + 0.32, -g[0] - 0.12)
		if bb:
			base = Vector3(0, bb.surf_y(g[0] + 0.05, 0.0) + 0.02, -g[0] - 0.05)
			tip = Vector3(-0.42, bb.surf_y(g[0] + 0.12, 0.42) + 0.018, -g[0] - 0.12)
		_strap(dark, base, tip, 0.02, 0.015)
	if style.get("splitter", false):
		_box(dark, Vector3(0, sill - 0.06, -l + 0.12), Vector3(w * 0.96, 0.03, 0.3))
		var a0: float = pr.wheel[1] + pr.wheel[0] + 0.1
		var a1: float = pr.wheel[2] - pr.wheel[0] - 0.1
		for sx in [-1.0, 1.0]:
			var hx3: float = side_x.call((a0 + a1) / 2.0, sill + 0.03)
			_box(dark, Vector3(sx * (hx3 - 0.02), sill + 0.02, -(a0 + a1) / 2.0), Vector3(0.08, 0.09, a1 - a0))


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
	tails.set_uv(BodyBuilder.LED_UV)
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
var _road := 0.0
var _phase := randf() * TAU
var _braking := false
var _shape_id := ""
var _needles: Array[Node3D] = []
var _steer_node: Node3D
var _display: Label3D
var _screen: Label3D
var _lever: Node3D
var _lever_base := Vector3.ZERO
var _lever_target := Vector3.ZERO
var _last_screen := ""
var _cabin_mi: MeshInstance3D
var _halo: MeshInstance3D
var _halo_mat: StandardMaterial3D
var _msg: Label3D
var _msg_until := 0
var _hands: Array[MeshInstance3D] = []
var _arms: Array = []
var _shoulders: Array = []
var _shadow_mi: MeshInstance3D


## Cars further away than this are fully hidden by haze, so they are not drawn.
const DRAW_DISTANCE := 360.0


## style (optional): {"rim", "rim_color", "caliper", "accent", "badge", "plate"} plus
## any KIT_KEYS flags. Traffic passes only a rim; the player and bosses get full kits.
func build(shape_id: String, color: Color, cab_color := Color("#b5322a"), style := {}) -> void:
	shape = Data.SHAPES[shape_id]
	_shape_id = shape_id
	var kit := _kit(shape_id, style)
	_body = Node3D.new()
	add_child(_body)

	var body := MeshInstance3D.new()
	body.mesh = kit.body
	if kit.has("surfaces"):
		var M := {
			"paint": paint(color), "glass": _glass(), "glass_solid": _glass_solid(),
			"dark": mat(Color("#18191b"), 0.0, 0.6), "gloss": _gloss(), "under": mat(Color("#0b0c0e"), 0.0, 0.95),
			"chrome": mat(Color("#d9dde1"), 0.0, 0.15, 0.95), "plate": mat(Color("#e8e6dc"), 0.0, 0.6),
			"head": lamp(Color("#fff6d8"), 2.0), "headlens": _headlens_mat(style.get("halo", false)), "grille": _grille_mat(),
			"accent": paint(Color(style.get("accent", "#f3f5ef"))),
		}
		var names: Array = kit.surfaces
		for i in names.size():
			body.set_surface_override_material(i, M[names[i]])
	else:
		var mats: Array[Material] = [mat(color, 0.0, 0.55, 0.1), paint(cab_color), _glass_solid(), mat(Color("#18191b"), 0.0, 0.7),
			mat(Color("#d9dde1"), 0.0, 0.15, 0.95), mat(Color("#e8e6dc"), 0.0, 0.6), lamp(Color("#fff6d8"), 2.0)]
		for i in mats.size():
			body.set_surface_override_material(i, mats[i])
	_body.add_child(body)
	if kit.has("cabin"):
		_cabin_mi = MeshInstance3D.new()
		_cabin_mi.mesh = kit.cabin
		_cabin_mi.material_override = mat(Color("#222327"), 0.0, 0.85)
		_cabin_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_body.add_child(_cabin_mi)

	_tails = _light(kit.tails, _tail_mat(false))
	_sig_l = _light(kit.sig_l, lamp(Color("#ffaa18"), 5.0))
	_sig_r = _light(kit.sig_r, lamp(Color("#ffaa18"), 5.0))
	_sig_l.visible = false
	_sig_r.visible = false

	_wheel_r = kit.r
	var wm := _wheel_mesh(kit.r, kit.ww, style.get("rim", "steel" if kit.get("truck", false) else "5spoke"), Color(style.get("rim_color", "#c3c8ce")))
	var cal_col: String = style.get("caliper", "#55595e")
	for p in kit.wheels:
		var wn := Node3D.new()
		wn.position = Vector3(p[0], kit.r, p[1])
		var mi := MeshInstance3D.new()
		mi.mesh = wm
		wn.add_child(mi)
		add_child(wn)  # wheels stay level when the body rolls
		_wheels.append(wn)
		if not kit.get("truck", false):
			# brake caliper: fixed to the car, visible through the spokes
			var cal := MeshInstance3D.new()
			cal.mesh = box_mesh(Vector3(0.05, kit.r * 0.34, kit.r * 0.42))
			cal.material_override = mat(Color(cal_col), 0.0, 0.4, 0.3)
			var outward := signf(p[0])
			cal.position = Vector3(p[0] + outward * (kit.ww / 2.0 - 0.045), kit.r + kit.r * 0.3, p[1] + kit.r * 0.22)
			add_child(cal)

	if style.has("plate") or style.has("badge"):
		var py: float = kit.get("plate_y", 0.6)
		if style.has("plate"):
			var pl := Label3D.new()
			pl.text = style.plate
			pl.font_size = 48
			pl.pixel_size = 0.0019
			pl.modulate = Color("#1b2a4a")
			pl.outline_size = 0
			pl.position = Vector3(0, py, 0.024)
			_body.add_child(pl)
		if style.has("badge"):
			var bd := Label3D.new()
			bd.text = style.badge
			bd.font_size = 40
			bd.pixel_size = 0.0018
			bd.modulate = Color("#d9dde1")
			bd.outline_size = 0
			bd.position = Vector3(0.0, (PROFILES.get(shape_id, {}).get("body", [[0, 0.8]])[0][1]) - 0.34, 0.02)
			_body.add_child(bd)

	# soft contact shadow so cars sit on the road even beyond the shadow distance
	var sh := MeshInstance3D.new()
	sh.mesh = _shadow()
	sh.material_override = _shadow_mat
	sh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sh.scale = Vector3(shape.w + 0.7, 1.0, shape.l + 0.9)
	sh.position = Vector3(0, 0.02, -shape.l / 2.0)
	add_child(sh)
	_shadow_mi = sh
	_set_draw_distance(self)


func _set_draw_distance(n: Node) -> void:
	for c in n.get_children():
		if c is GeometryInstance3D:
			var gi := c as GeometryInstance3D
			gi.visibility_range_end = DRAW_DISTANCE
			gi.visibility_range_end_margin = 0.0  # fully hidden by the depth fog there anyway
			gi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		_set_draw_distance(c)


func _light(m: Mesh, material: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_body.add_child(mi)
	return mi


## Tinted car glass: see-through, so the seats show, with reflections that
## get stronger at glancing angles.
static func _glass() -> StandardMaterial3D:
	var key := "glass"
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color = Color(0.03, 0.045, 0.06, 0.64)
		m.metallic = 0.2
		m.metallic_specular = 1.0
		m.roughness = 0.03
		m.rim_enabled = true
		m.rim = 0.4
		m.rim_tint = 0.15
		_mats[key] = m
	return _mats[key]


## Opaque dark glass for vans and trucks, whose bodies are closed boxes.
static func _glass_solid() -> StandardMaterial3D:
	var key := "glass_solid"
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = Color("#10161d")
		m.metallic = 0.85
		m.metallic_specular = 1.0
		m.roughness = 0.02
		m.rim_enabled = true
		m.rim = 0.35
		m.rim_tint = 0.2
		_mats[key] = m
	return _mats[key]


## Gloss-black trim: window surrounds, B-pillars, mirror arms.
static func _gloss() -> StandardMaterial3D:
	var key := "gloss"
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = Color("#0b0c0e")
		m.roughness = 0.14
		m.metallic = 0.1
		m.metallic_specular = 0.6
		m.clearcoat_enabled = true
		m.clearcoat = 0.8
		m.clearcoat_roughness = 0.05
		_mats[key] = m
	return _mats[key]


## Textured lamp lens (CarTextures) that glows and fades out with distance.
static func _lens(key: String, tex: Array, energy: float) -> StandardMaterial3D:
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex[0]
	m.emission_enabled = true
	m.emission_texture = tex[1]
	m.emission = Color.WHITE
	m.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY  # glow only where the texture has LEDs
	m.emission_energy_multiplier = energy
	# satin lens: a glossy one mirrors the bright sky and washes the colour out to white
	m.roughness = 0.35
	m.metallic = 0.0
	m.metallic_specular = 0.25
	m.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_DITHER
	m.distance_fade_min_distance = 230.0
	m.distance_fade_max_distance = 110.0
	_mats[key] = m
	return m


static func _headlens_mat(halo := false) -> StandardMaterial3D:
	return _lens("headlens%s" % halo, CarTextures.headlight(halo), 2.2)


static func _grille_mat() -> StandardMaterial3D:
	var key := "grille"
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_texture = CarTextures.grille()[0]
		m.roughness = 0.45
		m.metallic = 0.35
		_mats[key] = m
	return _mats[key]


static func _tail_mat(on: bool) -> StandardMaterial3D:
	return _lens("tail_on", CarTextures.taillight(), 5.0) if on else _lens("tail_off", CarTextures.taillight(), 0.9)


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


var _tag_pop: Label3D
var _tag_tween: Tween


## A boss's score message, floating above its name tag.
func show_tag_pop(text: String) -> void:
	if _tag_pop == null:
		_tag_pop = Label3D.new()
		_tag_pop.font_size = 56
		_tag_pop.pixel_size = 0.011
		_tag_pop.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_tag_pop.no_depth_test = true
		_tag_pop.modulate = Color("#ffb347")
		_tag_pop.outline_modulate = Color("#3a0d0d")
		_tag_pop.outline_size = 14
		add_child(_tag_pop)
	_tag_pop.text = text
	_tag_pop.position = Vector3(0, shape.t + 2.3, -shape.l / 2.0)
	_tag_pop.modulate.a = 1.0
	_tag_pop.outline_modulate.a = 1.0
	if _tag_tween:
		_tag_tween.kill()
	_tag_tween = create_tween()
	_tag_tween.tween_interval(0.9)
	_tag_tween.tween_property(_tag_pop, "modulate:a", 0.0, 0.5)
	_tag_tween.parallel().tween_property(_tag_pop, "outline_modulate:a", 0.0, 0.5)


## Crash pose: the whole car (body and wheels) turned by `heading` (radians,
## + = nose to the right) and rolled by `roll` (radians, + = right side up),
## pivoting on its centre so it never sinks into the road. `air` lifts it.
func set_crash_pose(x: float, heading: float, roll: float, air: float) -> void:
	var hw: float = shape.w / 2.0
	var hh: float = shape.t / 2.0
	var b := Basis(Vector3.UP, -heading) * Basis(Vector3.BACK, roll)
	var cy := hw * absf(sin(roll)) + hh * absf(cos(roll)) + air
	var centre := Vector3(0, hh, -shape.l / 2.0)
	transform = Transform3D(b, Vector3(x, cy, -shape.l / 2.0) - b * centre)
	if _body:
		_body.rotation = Vector3.ZERO
	if _shadow_mi:  # the contact shadow only suits a car standing on its wheels
		_shadow_mi.visible = absf(roll) < 0.3 and air < 0.1


## Back on its wheels after a crash pose.
func clear_crash_pose() -> void:
	rotation = Vector3.ZERO
	if _shadow_mi:
		_shadow_mi.visible = true


## World positions of the four tyre contact patches.
func wheel_contacts() -> Array[Vector3]:
	var out: Array[Vector3] = []
	for wn in _wheels:
		out.append(wn.global_position - global_transform.basis.y * _wheel_r)
	return out


## Pitch the body: positive dips the nose (braking), negative squats (accelerating).
func set_pitch(p: float) -> void:
	if _body:
		_body.rotation.x = -p


## Turn the wheels for a car travelling at v m/s.
func spin(v: float, dt: float) -> void:
	_spin = fmod(_spin - v / _wheel_r * dt, TAU)
	if _body:
		_road += v * dt
		var k := minf(v / 30.0, 1.0)
		_body.position.y = (0.005 * sin(_road * 1.3 + _phase) + 0.0025 * sin(_road * 4.1 + _phase * 2.0)) * k
	for wn in _wheels:
		wn.rotation.x = _spin


# ---------------------------------------------------------------- first-person

## The body node, which carries roll and pitch. First-person cameras ride on it.
func body_node() -> Node3D:
	return _body


## Driver's eye position in car space.
func cockpit_eye() -> Vector3:
	var pr: Dictionary = PROFILES.get(_shape_id, PROFILES.sedan)
	if not pr.has("gh"):
		return Vector3(-0.42, 1.72, -3.95)
	var g: Array = pr.gh
	var y: float = minf(g[4] + 0.38, g[5] - 0.16)
	return Vector3(-0.36 * shape.w / 1.84, y, -(g[1] - 1.45))


## Bonnet camera position in car space.
func hood_eye() -> Vector3:
	var pr: Dictionary = PROFILES.get(_shape_id, PROFILES.sedan)
	if not pr.has("gh"):
		return Vector3(0, 1.62, -4.75)
	var d: float = pr.gh[1] + 0.3
	return Vector3(0, _station_at(pr.body, d, 1) + 0.2, -d)


## Box oriented along a segment (seat belts, levers).
static func _strap(st: SurfaceTool, a: Vector3, b: Vector3, w: float, t: float) -> void:
	var y := (b - a).normalized()
	var x := y.cross(Vector3.FORWARD if absf(y.z) < 0.9 else Vector3.RIGHT).normalized()
	var z := x.cross(y).normalized()
	_box(st, (a + b) / 2.0, Vector3(w, (b - a).length(), t), Basis(x, y, z))


## A full cabin for the player's car: carpeted floor, dashboard with vents,
## trim and infotainment screen, live instrument cluster, steering wheel,
## centre console with gear lever and handbrake, seats with bolsters and
## headrests, rear bench, door cards, headliner, visors and mirror.
func build_interior() -> void:
	var pr: Dictionary = PROFILES.get(_shape_id, {})
	if pr.is_empty() or not pr.has("gh") or _steer_node:
		return
	if _cabin_mi:  # the simple see-through cabin is replaced by the real one
		_cabin_mi.queue_free()
		_cabin_mi = null
	var g: Array = pr.gh
	var w: float = shape.w
	var hb: float = w / 2.0 * g[6] - 0.03     # inner half-width of the cabin
	var hr: float = w / 2.0 * g[7]
	var yb: float = g[4]
	var yr: float = g[5]
	var rear_top: float = pr.body[0][1]
	var floor_y: float = minf(0.3, rear_top - 0.3) + 0.08
	var eye := cockpit_eye()
	var ex := eye.x
	var ez := eye.z
	var dz: float = -(g[1] - 0.05)            # windshield base
	var zr: float = -g[0]                     # rear of the cabin

	var S := {}
	var keys := ["carpet", "trim", "dash", "pad", "leather", "cloth", "chrome", "alu", "vent", "screen", "red", "stitch", "ambient", "map", "route"]
	for k in keys:
		S[k] = _new_st()

	# --- shell: floor, firewall, rear wall, door cards
	_quad(S.carpet, Vector3(-hb, floor_y, zr), Vector3(hb, floor_y, zr), Vector3(hb, floor_y, dz + 0.15), Vector3(-hb, floor_y, dz + 0.15), Vector3.UP)
	_quad(S.carpet, Vector3(-hb, floor_y, dz + 0.15), Vector3(hb, floor_y, dz + 0.15), Vector3(hb, yb - 0.2, dz + 0.15), Vector3(-hb, yb - 0.2, dz + 0.15), Vector3.BACK)
	_quad(S.trim, Vector3(-hb, floor_y, zr - 0.01), Vector3(hb, floor_y, zr - 0.01), Vector3(hb, yb + 0.02, zr - 0.01), Vector3(-hb, yb + 0.02, zr - 0.01), Vector3.FORWARD)
	for sd in [-1.0, 1.0]:
		var x: float = sd * hb
		var inward := Vector3(-sd, 0, 0)
		_quad(S.trim, Vector3(x, floor_y, zr), Vector3(x, floor_y, dz + 0.1), Vector3(x, yb + 0.02, dz + 0.1), Vector3(x, yb + 0.02, zr), inward)
		_box(S.leather, Vector3(x - sd * 0.02, yb - 0.02, (zr + dz) / 2.0), Vector3(0.07, 0.09, absf(dz - zr)))      # upper door trim
		_box(S.leather, Vector3(x - sd * 0.05, yb - 0.27, ez + 0.05), Vector3(0.1, 0.05, 0.6))                      # armrest
		_box(S.dash, Vector3(x - sd * 0.075, yb - 0.24, ez - 0.12), Vector3(0.05, 0.02, 0.16))                      # window switches
		_box(S.chrome, Vector3(x - sd * 0.02, yb - 0.12, ez - 0.32), Vector3(0.03, 0.04, 0.12))                     # door handle
		_box(S.alu, Vector3(x - sd * 0.005, yb - 0.17, (ez + dz) / 2.0 + 0.2), Vector3(0.01, 0.015, absf(dz - ez) * 0.9))  # trim line
		_cyl(S.vent, Vector3(x - sd * 0.008, floor_y + 0.2, ez - 0.45), 0.09, 0.012, Vector3.RIGHT, 14)                  # speaker
		_box(S.trim, Vector3(sd * (hb - 0.06), yb + 0.18, ez + 0.5), Vector3(0.06, 0.4, 0.1))                        # B-pillar trim
		_box(S.trim, Vector3(sd * (hr - 0.08), yr - 0.07, ez + 0.05), Vector3(0.04, 0.03, 0.22))                     # grab handle

	# --- dashboard
	_box(S.dash, Vector3(0, yb - 0.08, dz + 0.3), Vector3(hb * 2.0, 0.26, 0.6))
	_box(S.pad, Vector3(0, yb + 0.06, dz + 0.27), Vector3(hb * 2.0 - 0.02, 0.03, 0.52))
	_box(S.stitch, Vector3(0, yb + 0.076, dz + 0.53), Vector3(hb * 2.0 - 0.06, 0.004, 0.006))
	_box(S.dash, Vector3(0, yb - 0.3, dz + 0.35), Vector3(hb * 2.0, 0.18, 0.4))               # lower dash
	_box(S.alu, Vector3(0, yb - 0.11, dz + 0.605), Vector3(hb * 2.0 - 0.1, 0.025, 0.012))     # trim strip
	_box(S.ambient, Vector3(0, yb - 0.126, dz + 0.607), Vector3(hb * 2.0 - 0.12, 0.004, 0.006))  # ambient light line
	for sd in [-1.0, 1.0]:
		_box(S.ambient, Vector3(sd * (hb - 0.062), yb - 0.07, (zr + dz) / 2.0), Vector3(0.004, 0.004, absf(dz - zr) * 0.9))
	# sat-nav map under the radio text
	_box(S.map, Vector3(0, yb - 0.172, dz + 0.6265), Vector3(0.23, 0.05, 0.002))
	for rd in [[-0.06, 0.0, 0.11, 0.005], [0.03, -0.01, 0.005, 0.045], [0.07, 0.008, 0.07, 0.004]]:
		_box(S.screen, Vector3(rd[0], yb - 0.172 + rd[1], dz + 0.628), Vector3(rd[2], rd[3], 0.002))
	_box(S.route, Vector3(0.0, yb - 0.172, dz + 0.6285), Vector3(0.004, 0.04, 0.002))
	_box(S.route, Vector3(-0.03, yb - 0.152, dz + 0.6285), Vector3(0.06, 0.004, 0.002))
	_box(S.trim, Vector3(-ex, yb - 0.3, dz + 0.56), Vector3(0.46, 0.16, 0.02))               # glovebox lid
	_box(S.chrome, Vector3(-ex + 0.17, yb - 0.25, dz + 0.575), Vector3(0.06, 0.015, 0.015))  # glovebox latch
	for sd in [-1.0, 1.0]:
		_box(S.dash, Vector3(sd * 0.36, yb - 0.32, dz + 0.58), Vector3(0.34, 0.14, 0.08))      # knee bolsters
	for vx in [-0.1, 0.1, -(hb - 0.14), hb - 0.14]:
		var c := Vector3(vx, yb - 0.02, dz + 0.605)
		_box(S.chrome, c, Vector3(0.16, 0.075, 0.01))
		_box(S.vent, c + Vector3(0, 0, 0.004), Vector3(0.145, 0.062, 0.01))
		for k in 3:
			_box(S.trim, c + Vector3(0, -0.02 + k * 0.02, 0.008), Vector3(0.14, 0.006, 0.006))
	# binnacle and instrument cluster backing
	_box(S.dash, Vector3(ex, yb + 0.19, dz + 0.5), Vector3(0.38, 0.06, 0.24))
	_box(S.dash, Vector3(ex, yb + 0.07, dz + 0.55), Vector3(0.36, 0.22, 0.1))
	# centre stack with screen, climate knobs and hazard switch
	_box(S.dash, Vector3(0, yb - 0.27, dz + 0.54), Vector3(0.32, 0.44, 0.16))
	_box(S.chrome, Vector3(0, yb - 0.13, dz + 0.621), Vector3(0.27, 0.165, 0.004))
	_box(S.screen, Vector3(0, yb - 0.13, dz + 0.624), Vector3(0.25, 0.145, 0.004))
	for k in 3:
		_cyl(S.chrome, Vector3(-0.08 + k * 0.08, yb - 0.33, dz + 0.625), 0.026, 0.02, Vector3.BACK, 14)
		_cyl(S.vent, Vector3(-0.08 + k * 0.08, yb - 0.33, dz + 0.636), 0.02, 0.005, Vector3.BACK, 12)
	_box(S.red, Vector3(0, yb - 0.24, dz + 0.624), Vector3(0.04, 0.025, 0.01))
	# steering column, stalks and pedals
	_box(S.dash, Vector3(ex, yb - 0.14, dz + 0.69), Vector3(0.12, 0.1, 0.24))
	for sd in [-1.0, 1.0]:
		_strap(S.dash, Vector3(ex + sd * 0.05, yb - 0.12, dz + 0.74), Vector3(ex + sd * 0.17, yb - 0.1, dz + 0.72), 0.018, 0.018)
	for k in 3:
		_box(S.alu, Vector3(ex - 0.12 + k * 0.1, floor_y + 0.12, dz + 0.3), Vector3(0.07, 0.1, 0.02), Basis(Vector3.RIGHT, -0.5))

	# --- centre console
	var cz0: float = dz + 0.62
	var cz1: float = ez + 0.5
	_box(S.trim, Vector3(0, (floor_y + yb - 0.42) / 2.0, (cz0 + cz1) / 2.0), Vector3(0.24, yb - 0.42 - floor_y, absf(cz1 - cz0)))
	_box(S.alu, Vector3(0, yb - 0.415, (cz0 + cz1) / 2.0), Vector3(0.25, 0.01, absf(cz1 - cz0)))
	_box(S.leather, Vector3(0, yb - 0.36, ez + 0.28), Vector3(0.22, 0.09, 0.42))  # armrest lid
	for k in 2:
		_cyl(S.vent, Vector3(-0.045 + k * 0.09, yb - 0.405, cz0 + 0.14), 0.035, 0.01, Vector3.UP, 12)  # cup holders
	_box(S.leather, Vector3(0, yb - 0.39, ez - 0.32), Vector3(0.13, 0.04, 0.16))  # shifter boot
	_strap(S.dash, Vector3(0.0, yb - 0.4, ez - 0.02), Vector3(0.0, yb - 0.3, ez + 0.16), 0.045, 0.06)  # handbrake
	_box(S.chrome, Vector3(0.0, yb - 0.27, ez + 0.2), Vector3(0.02, 0.02, 0.03))

	# --- front seats
	var cushion_top: float = floor_y + 0.27
	# height of the roof or the rear window at a distance d from the rear bumper
	var roof_line := func(d: float) -> float:
		if d >= g[2]:
			return yr
		return yb + (yr - yb) * clampf((d - g[0]) / maxf(g[2] - g[0], 0.01), 0.0, 1.0)
	for sx in [ex, -ex]:
		_box(S.dash, Vector3(sx, floor_y + 0.06, ez + 0.05), Vector3(0.4, 0.06, 0.45))                      # rails and base
		_box(S.leather, Vector3(sx, cushion_top - 0.07, ez + 0.03), Vector3(0.46, 0.14, 0.5))
		_box(S.cloth, Vector3(sx, cushion_top + 0.005, ez + 0.03), Vector3(0.28, 0.01, 0.44))                # insert
		for q in 5:  # quilting
			_box(S.stitch, Vector3(sx, cushion_top + 0.011, ez - 0.17 + q * 0.1), Vector3(0.28, 0.002, 0.006))
		for sd in [-1.0, 1.0]:
			_box(S.leather, Vector3(sx + sd * 0.21, cushion_top - 0.01, ez + 0.03), Vector3(0.07, 0.12, 0.48))  # cushion bolster
		var back := Basis(Vector3.RIGHT, 0.2)
		# fit the seat under the roof or rear window: the backrest and headrest shrink on low cars
		var room: float = minf(yr - 0.08, roof_line.call(-(ez + 0.46)) - 0.05) - cushion_top
		var hh: float = clampf(room * 0.27, 0.1, 0.19)
		var bh: float = clampf(room - hh - 0.08, 0.3, 0.62)
		var bc := Vector3(sx, cushion_top + bh / 2.0 - 0.01, ez + 0.3)
		_box(S.leather, bc, Vector3(0.48, bh, 0.12), back)
		_box(S.cloth, bc + back.z * -0.065, Vector3(0.28, bh - 0.12, 0.01), back)
		for q in 6:
			_box(S.stitch, bc + back.z * -0.071 + back.y * (-bh / 2.0 + 0.08 + q * (bh - 0.16) / 5.0), Vector3(0.28, 0.006, 0.002), back)
		for sd in [-1.0, 1.0]:
			_box(S.leather, bc + back.x * sd * 0.22 + back.z * -0.05, Vector3(0.07, bh - 0.06, 0.1), back)  # back bolster
		var top: Vector3 = bc + back.y * (bh / 2.0)
		for sd in [-1.0, 1.0]:
			_box(S.chrome, top + back.y * 0.035 + Vector3(sd * 0.07, 0, 0), Vector3(0.012, 0.07, 0.012), back)
		_box(S.leather, top + back.y * (0.06 + hh / 2.0), Vector3(0.26, hh, 0.1), back)                       # headrest
	# seat belt across the (empty) driver seat, from the B-pillar to the buckle
	_strap(S.dash, Vector3(signf(ex) * (hb - 0.08), yb + 0.32, ez + 0.4), Vector3(ex - signf(ex) * 0.22, cushion_top + 0.05, ez + 0.1), 0.045, 0.006)

	# --- rear bench, tucked under the rear window (the cabin runs from zr forward to -z)
	var glass_z := func(h: float) -> float:
		return -(g[0] + (g[2] - g[0]) * clampf((h - yb) / (yr - yb), 0.0, 1.0))
	var rb := Basis(Vector3.RIGHT, 0.22)
	var back_top: float = cushion_top + 0.46
	var back_z: float = minf(zr - 0.16, glass_z.call(back_top + 0.15) - 0.13)
	var cush_z: float = back_z - 0.3
	if cush_z - 0.2 > ez + 0.27:  # only if there is legroom behind the front seats
		_box(S.leather, Vector3(0, cushion_top - 0.1, cush_z), Vector3(hb * 2.0 - 0.06, 0.14, 0.4))
		_box(S.cloth, Vector3(0, cushion_top - 0.025, cush_z), Vector3(hb * 2.0 - 0.3, 0.01, 0.34))
		_box(S.leather, Vector3(0, cushion_top + 0.2, back_z), Vector3(hb * 2.0 - 0.06, 0.46, 0.12), rb)
		for k in 3:
			var hx: float = (k - 1) * hb * 0.62
			_box(S.leather, Vector3(hx, back_top + 0.07, back_z + 0.06), Vector3(0.22, 0.12, 0.09), rb)
		# parcel shelf behind the bench, at the base of the rear window
		var shelf_len: float = absf(back_z - zr) - 0.02
		if shelf_len > 0.06:
			_box(S.trim, Vector3(0, yb - 0.01, (zr + back_z) / 2.0 + 0.01), Vector3(hb * 2.0, 0.03, shelf_len))

	# --- headliner, visors, dome light, inner A-pillars
	_quad(S.cloth, Vector3(-hr, yr - 0.02, -g[2]), Vector3(hr, yr - 0.02, -g[2]), Vector3(hr, yr - 0.02, -g[3]), Vector3(-hr, yr - 0.02, -g[3]), Vector3.DOWN)
	_box(S.cloth, Vector3(0, yr - 0.05, -g[3] + 0.05), Vector3(hr * 2.0, 0.05, 0.12))
	for sd in [-1.0, 1.0]:
		_box(S.cloth, Vector3(sd * 0.33, yr - 0.06, -g[3] + 0.16), Vector3(0.34, 0.025, 0.17), Basis(Vector3.RIGHT, 0.12))
		var b0 := Vector3(sd * (hb + 0.03), yb, -g[1])
		var r0 := Vector3(sd * hr, yr, -g[3])
		var inward := Vector3(-sd * 0.09, 0, 0)
		_quad(S.trim, b0 + Vector3(0, 0, 0.03), b0 + inward + Vector3(0, 0, 0.05), r0 + inward + Vector3(0, -0.02, 0.05), r0 + Vector3(0, -0.02, 0.03), Vector3(-sd, 0, 0.6).normalized())
	_box(S.screen, Vector3(0, yr - 0.03, (-g[2] - g[3]) / 2.0), Vector3(0.14, 0.012, 0.08))  # dome light

	var interior := ArrayMesh.new()
	var mats := {
		"carpet": mat(Color("#232427"), 0.0, 1.0), "trim": mat(Color("#34363a"), 0.0, 0.8),
		"dash": mat(Color("#17181b"), 0.0, 0.7), "pad": mat(Color("#1f2023"), 0.0, 0.9),
		"leather": mat(Color("#2b2624"), 0.0, 0.55), "chrome": mat(Color("#c9ced3"), 0.0, 0.3, 0.35),
		"alu": mat(Color("#8d939a"), 0.0, 0.45, 0.25), "vent": mat(Color("#0d0e10"), 0.0, 0.8),
		"screen": mat(Color("#20425e"), 1.2, 0.2), "red": mat(Color("#d02a1a"), 1.0), "stitch": mat(Color("#b3462c"), 0.0, 0.6),
		"ambient": mat(Color("#ff7a3a"), 1.4), "map": mat(Color("#0c1a26"), 0.6), "route": mat(Color("#f5b52e"), 2.5),
	}
	var cloth := StandardMaterial3D.new()  # unshaded: down-facing fabric would pick up the green ground light
	cloth.albedo_color = Color("#4a4a4c")
	cloth.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mats["cloth"] = cloth
	var order: Array = []
	for k in keys:
		var arrays: Array = (S[k] as SurfaceTool).commit_to_arrays()
		if arrays[Mesh.ARRAY_VERTEX] == null or (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).is_empty():
			continue
		interior.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		order.append(k)
	var mi := MeshInstance3D.new()
	mi.mesh = interior
	for i in order.size():
		mi.set_surface_override_material(i, mats[order[i]])
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_body.add_child(mi)

	# soft bounce light inside the cabin, as daylight would reflect off the seats and dash
	var fill := OmniLight3D.new()
	fill.light_color = Color("#ffeedd")
	fill.light_energy = 0.7
	fill.omni_range = 1.9
	fill.omni_attenuation = 1.4
	fill.shadow_enabled = false
	fill.light_specular = 0.2
	fill.position = Vector3(0, yr - 0.25, ez - 0.25)
	_body.add_child(fill)

	# faint reflection on the inside of the windscreen
	var sheen := StandardMaterial3D.new()
	sheen.albedo_color = Color(0.85, 0.92, 1.0, 0.05)
	sheen.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sheen.roughness = 0.03
	sheen.metallic_specular = 1.0
	var ws := _new_st()
	var wb0 := Vector3(-hb - 0.03, yb, -g[1])
	var wb1 := Vector3(hb + 0.03, yb, -g[1])
	var wr0 := Vector3(-hr, yr, -g[3])
	var wr1 := Vector3(hr, yr, -g[3])
	var wn := -_face_n(wb0, wb1, wr1, Vector3(0, 0.5, -1))
	_quad(ws, wb0 + wn * 0.012, wb1 + wn * 0.012, wr1 + wn * 0.012, wr0 + wn * 0.012, wn)
	var wsm := MeshInstance3D.new()
	wsm.mesh = ws.commit()
	wsm.material_override = sheen
	wsm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_body.add_child(wsm)

	# rear-view mirror with stem
	var stem := MeshInstance3D.new()
	stem.mesh = box_mesh(Vector3(0.02, 0.08, 0.02))
	stem.material_override = mats.dash
	stem.position = Vector3(0, yr - 0.06, -(g[3] - 0.06))
	_body.add_child(stem)
	var mirror := MeshInstance3D.new()
	mirror.mesh = box_mesh(Vector3(0.24, 0.07, 0.03))
	mirror.material_override = mats.dash
	mirror.position = Vector3(0, yr - 0.12, -(g[3] - 0.08))
	_body.add_child(mirror)
	var glassm := MeshInstance3D.new()
	glassm.mesh = box_mesh(Vector3(0.22, 0.055, 0.005))
	glassm.material_override = _glass()
	glassm.position = mirror.position + Vector3(0, 0, 0.016)
	_body.add_child(glassm)

	# instrument cluster: speedometer and rev counter with ticks and needles
	for k in 2:
		var dial := Node3D.new()
		dial.position = Vector3(ex + (0.085 if k == 0 else -0.085), yb + 0.09, dz + 0.645)
		dial.rotation.x = -0.35
		_body.add_child(dial)
		var face := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.065
		cm.bottom_radius = 0.065
		cm.height = 0.01
		cm.radial_segments = 24
		face.mesh = cm
		face.rotation.x = PI / 2.0
		face.material_override = mat(Color("#0e0f11"), 0.0, 0.4)
		dial.add_child(face)
		var ring := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.06
		tm.outer_radius = 0.068
		tm.rings = 24
		tm.ring_segments = 4
		ring.mesh = tm
		ring.rotation.x = PI / 2.0
		ring.material_override = mat(Color("#f5b52e") if k == 0 else Color("#e6e6e6"), 1.6)
		dial.add_child(ring)
		for t in 9:
			var a := lerpf(2.2, -2.2, t / 8.0)
			var tick := MeshInstance3D.new()
			tick.mesh = box_mesh(Vector3(0.004, 0.012, 0.002))
			tick.position = Vector3(-sin(a), cos(a), 0) * 0.05 + Vector3(0, 0, 0.007)
			tick.rotation.z = a
			tick.material_override = mat(Color("#ff3b2a") if (k == 1 and t >= 7) else Color("#e8e8e8"), 1.4)
			dial.add_child(tick)
		var pivot := Node3D.new()
		pivot.position = Vector3(0, 0, 0.009)
		dial.add_child(pivot)
		var needle := MeshInstance3D.new()
		needle.mesh = box_mesh(Vector3(0.005, 0.052, 0.003))
		needle.position = Vector3(0, 0.024, 0)
		needle.material_override = mat(Color("#ff4a2a"), 3.0)
		pivot.add_child(needle)
		_needles.append(pivot)
	# digital readout between the dials, and the infotainment screen
	_display = Label3D.new()
	_display.font_size = 40
	_display.pixel_size = 0.00055
	_display.modulate = Color("#f5b52e")
	_display.outline_size = 0
	_display.position = Vector3(ex, yb + 0.09, dz + 0.652)
	_display.rotation.x = -0.35
	_body.add_child(_display)
	_screen = Label3D.new()
	_screen.font_size = 30
	_screen.pixel_size = 0.0008
	_screen.modulate = Color("#cfe8ff")
	_screen.outline_size = 0
	_screen.position = Vector3(0, yb - 0.105, dz + 0.628)
	_screen.font_size = 26
	_body.add_child(_screen)

	# steering wheel: tilted column with a spinning rim, spokes, airbag hub and paddles
	var tilt := Node3D.new()
	tilt.position = Vector3(ex, yb - 0.1, dz + 0.8)
	tilt.rotation.x = 1.15  # wheel face points back at the driver and up
	_body.add_child(tilt)
	_steer_node = Node3D.new()
	tilt.add_child(_steer_node)
	var rim := MeshInstance3D.new()
	var wt := TorusMesh.new()
	wt.inner_radius = 0.155
	wt.outer_radius = 0.188
	wt.rings = 32
	wt.ring_segments = 10
	rim.mesh = wt
	rim.material_override = mats.leather
	_steer_node.add_child(rim)
	for a in [0.0, PI, PI * 0.5]:  # left, right and bottom spokes
		var spoke := MeshInstance3D.new()
		spoke.mesh = box_mesh(Vector3(0.13, 0.025, 0.045))
		spoke.position = Vector3(cos(a) * 0.1, 0, sin(a) * 0.1)
		spoke.rotation.y = -a
		spoke.material_override = mats.dash
		_steer_node.add_child(spoke)
	var hub := MeshInstance3D.new()
	hub.mesh = box_mesh(Vector3(0.12, 0.05, 0.1))
	hub.material_override = mats.dash
	_steer_node.add_child(hub)
	var badge := MeshInstance3D.new()
	badge.mesh = box_mesh(Vector3(0.03, 0.005, 0.02))
	badge.position = Vector3(0, 0.028, 0)
	badge.material_override = mat(Color("#f5b52e"), 1.5)
	_steer_node.add_child(badge)
	for sd in [-1.0, 1.0]:
		var paddle := MeshInstance3D.new()
		paddle.mesh = box_mesh(Vector3(0.05, 0.008, 0.08))
		paddle.position = Vector3(sd * 0.13, -0.05, -0.02)
		paddle.material_override = mats.alu
		_steer_node.add_child(paddle)

	# the driver: gloved hands on the rim at a quarter to three, arms that follow the wheel
	var glove := mat(Color("#141416"), 0.0, 0.45)
	var sleeve := mat(Color("#2a2f38"), 0.0, 0.85)
	for sd in [-1.0, 1.0]:
		var hand := MeshInstance3D.new()
		var cap := CapsuleMesh.new()
		cap.radius = 0.04
		cap.height = 0.14
		cap.radial_segments = 10
		cap.rings = 3
		hand.mesh = cap
		hand.material_override = glove
		hand.position = Vector3(sd * 0.168, 0.01, -0.045)
		hand.rotation = Vector3(PI / 2.0, 0, sd * 0.25)
		_steer_node.add_child(hand)
		var knuckles := MeshInstance3D.new()
		knuckles.mesh = box_mesh(Vector3(0.05, 0.07, 0.1))
		knuckles.material_override = glove
		knuckles.position = Vector3(sd * 0.15, 0.03, -0.04)
		_steer_node.add_child(knuckles)
		_hands.append(hand)
		var arm := []
		for k in 2:
			var seg := MeshInstance3D.new()
			var cyl := CylinderMesh.new()
			cyl.top_radius = 0.038 if k == 0 else 0.048
			cyl.bottom_radius = 0.042 if k == 0 else 0.052
			cyl.height = 1.0
			cyl.radial_segments = 10
			seg.mesh = cyl
			seg.material_override = sleeve
			seg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_body.add_child(seg)
			arm.append(seg)
		_arms.append(arm)
	_shoulders = [Vector3(ex - 0.2, eye.y - 0.24, ez + 0.16), Vector3(ex + 0.2, eye.y - 0.24, ez + 0.16)]
	_update_arms()

	# gear lever on an H-pattern gate
	_lever = Node3D.new()
	_lever_base = Vector3(0, yb - 0.37, ez - 0.32)
	_lever.position = _lever_base
	_body.add_child(_lever)
	var rod := MeshInstance3D.new()
	rod.mesh = box_mesh(Vector3(0.018, 0.14, 0.018))
	rod.position = Vector3(0, 0.07, 0)
	rod.material_override = mats.chrome
	_lever.add_child(rod)
	var knob := MeshInstance3D.new()
	var km := SphereMesh.new()
	km.radius = 0.03
	km.height = 0.06
	knob.mesh = km
	knob.position = Vector3(0, 0.15, 0)
	knob.material_override = mats.leather
	_lever.add_child(knob)


## speed and rpm as 0..1 fractions of full scale.
func set_gauges(speed_frac: float, rpm_frac: float) -> void:
	if _needles.size() < 2:
		return
	_needles[0].rotation.z = lerpf(2.2, -2.2, clampf(speed_frac, 0.0, 1.0))
	_needles[1].rotation.z = lerpf(2.2, -2.2, clampf(rpm_frac, 0.0, 1.0))


## Steering wheel angle in radians (positive turns right).
func set_steer(angle: float) -> void:
	if _steer_node:
		_steer_node.rotation.y = -angle
		_update_arms()


## Upper arm from the shoulder to an elbow below and outside, forearm to the glove.
func _update_arms() -> void:
	for i in _hands.size():
		var hand: Vector3 = _body.to_local(_hands[i].global_position)
		var sh: Vector3 = _shoulders[i]
		var sd := -1.0 if i == 0 else 1.0
		var elbow: Vector3 = sh.lerp(hand, 0.52) + Vector3(sd * 0.07, -0.13, 0.02)
		_segment(_arms[i][1], sh, elbow)
		_segment(_arms[i][0], elbow, hand)


func _segment(mi: MeshInstance3D, a: Vector3, b: Vector3) -> void:
	var d := b - a
	var y := d.normalized()
	var x := y.cross(Vector3.FORWARD if absf(y.z) < 0.9 else Vector3.RIGHT).normalized()
	var z := x.cross(y)
	mi.transform = Transform3D(Basis(x, y * d.length(), z), (a + b) / 2.0)


var _bar_l: MeshInstance3D
var _bar_r: MeshInstance3D


## Police light bar on the roof (roof_y: roof height).
func add_lightbar(roof_y: float) -> void:
	var base := MeshInstance3D.new()
	base.mesh = box_mesh(Vector3(1.1, 0.08, 0.26))
	base.material_override = mat(Color("#1b1d21"), 0.0, 0.5)
	var z: float = -shape.l * 0.5 + 0.15
	base.position = Vector3(0, roof_y + 0.08, z)
	_body.add_child(base)
	_bar_l = MeshInstance3D.new()
	_bar_l.mesh = box_mesh(Vector3(0.5, 0.09, 0.22))
	_bar_l.position = Vector3(-0.28, roof_y + 0.16, z)
	_body.add_child(_bar_l)
	_bar_r = MeshInstance3D.new()
	_bar_r.mesh = box_mesh(Vector3(0.5, 0.09, 0.22))
	_bar_r.position = Vector3(0.28, roof_y + 0.16, z)
	_body.add_child(_bar_r)
	flash_lightbar(0.0)


## Alternating red and blue flashes.
func flash_lightbar(t: float) -> void:
	if _bar_l == null:
		return
	var phase := int(t * 6.0) % 2 == 0
	_bar_l.material_override = mat(Color("#ff2a2a"), 6.0 if phase else 0.4)
	_bar_r.material_override = mat(Color("#2a6bff"), 0.4 if phase else 6.0)


## Invulnerability glow: a soft amber halo pulsing on the road under the car.
func set_ghost(on: bool, t: float) -> void:
	if not on:
		if _halo:
			_halo.visible = false
		return
	if _halo == null:
		_shadow()
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		g.add_point(0.5, Color(1, 1, 1, 0.6))
		var tex := GradientTexture2D.new()
		tex.gradient = g
		tex.fill = GradientTexture2D.FILL_RADIAL
		tex.fill_from = Vector2(0.5, 0.5)
		tex.fill_to = Vector2(0.5, 0.0)
		tex.width = 64
		tex.height = 64
		_halo_mat = StandardMaterial3D.new()
		_halo_mat.albedo_texture = tex
		_halo_mat.albedo_color = Color(1.0, 0.72, 0.2, 0.0)
		_halo_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_halo_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_halo_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_halo_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		_halo = MeshInstance3D.new()
		_halo.mesh = _shadow_mesh
		_halo.material_override = _halo_mat
		_halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_halo.scale = Vector3(shape.w + 1.8, 1.0, shape.l + 2.2)
		_halo.position = Vector3(0, 0.03, -shape.l / 2.0)
		add_child(_halo)
	_halo.visible = true
	_halo_mat.albedo_color = Color(1.0, 0.72, 0.2, 0.55 + 0.35 * sin(t * 7.0))


## Shows a scoring or crash message on the infotainment screen for a moment.
func show_message(text: String, kind := "") -> void:
	if _screen == null:
		return
	if _msg == null:
		_msg = Label3D.new()
		_msg.font_size = 32
		_msg.pixel_size = 0.0007
		_msg.outline_size = 0
		_msg.width = 300
		_msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_msg.position = _screen.position + Vector3(0, 0.004, 0.002)
		_body.add_child(_msg)
	_msg.text = text
	_msg.modulate = Color("#f5b52e") if kind == "hot" else (Color("#ff5a45") if kind == "bad" else Color("#ffffff"))
	_msg.visible = true
	_screen.visible = false
	_msg_until = Time.get_ticks_msec() + 1500


## Cockpit readouts: gear and speed on the cluster, radio and trip on the screen.
func set_display(gear: int, speed: String, unit: String, trip: String) -> void:
	if _msg and _msg.visible and Time.get_ticks_msec() > _msg_until:
		_msg.visible = false
		_screen.visible = true
	if _display:
		_display.text = "%d\n%s %s" % [gear, speed, unit]
	if _screen:
		var t := "REDLINE FM  98.4\n%s\nTrip %s" % [Data.car_by_id(Save.data.selected).name, trip]
		if t != _last_screen:
			_last_screen = t
			_screen.text = t


## Moves the gear lever through an H pattern (1-2 left, 3-4 middle, 5-6 right).
func set_gear(gear: int, dt: float) -> void:
	if _lever == null:
		return
	var col := (clampi(gear, 1, 6) - 1) / 2
	var fwd := gear % 2 == 1
	_lever_target = _lever_base + Vector3((col - 1) * 0.035, 0, -0.035 if fwd else 0.035)
	_lever.position = _lever.position.lerp(_lever_target, minf(1.0, dt * 14.0))
	_lever.rotation.x = (-0.25 if fwd else 0.25)
