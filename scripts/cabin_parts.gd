class_name CabinParts
extends RefCounted
## The finely made parts of a cockpit, kept apart from CarModel.build_interior(): the instrument panel with its
## needles, the infotainment screen, the steering wheel (rim, stitching, spokes, hub, buttons), vents, knobs and
## the dash trim. Flat artwork (dial faces, the screen's map, wood and carbon) is baked by tools/make_cockpit_art.py
## into assets/textures/cockpit/; everything with a shape is real geometry here, so needles stand off their dials
## and wheels have a rim you could grip.
##
## All of it is small: a handful of draw calls and a few thousand triangles for the whole cabin, and nothing here
## runs per frame.

const CLUSTER_W := 0.32     # the instrument panel's size, m (the art is 1024 x 384)
const CLUSTER_H := 0.12
const DIAL_DX := 0.09625    # the two dials sit this far either side of the middle
const RIM_R := 0.172        # the steering wheel's rim, from its middle to the middle of the rim's tube

static var _tex := {}
static var _mats := {}
static var _needle: ArrayMesh
static var _bezel: TorusMesh
static var _cap: CylinderMesh


## The rev counter's full scale in rpm for an engine with this redline: the next thousand above 108% of it. The
## baked dial faces use the same rule (tools/make_cockpit_art.py tach_max).
static func tach_max(redline: float) -> float:
	return ceilf(redline * 1.08 / 1000.0) * 1000.0


## One of the baked cockpit textures (null if it is missing: the parts then fall back to plain colours).
static func tex(name: String) -> Texture2D:
	if not _tex.has(name):
		_tex[name] = load("res://assets/textures/cockpit/%s.png" % name) as Texture2D
	return _tex[name]


# ------------------------------------------------------------------ the instrument cluster

static func cluster_material(shape_id: String) -> StandardMaterial3D:
	var key := "cluster|" + shape_id
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	var t := tex("cluster_" + shape_id)
	if t:
		m.albedo_texture = t
		m.emission_enabled = true  # backlit: the numerals glow whatever the daylight
		m.emission_texture = t
		m.emission_energy_multiplier = 1.15
	else:
		m.albedo_color = Color("#0a0b0c")
	m.roughness = 0.3
	m.metallic_specular = 0.55
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR  # (the panel's corners are cut round)
	m.alpha_scissor_threshold = 0.5
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_mats[key] = m
	return m


## A needle lying along +y from its pivot at the origin: a long taper with a short tail, flat in the xy plane.
static func needle_mesh() -> ArrayMesh:
	if _needle == null:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var pts := [Vector2(-0.0019, -0.014), Vector2(0.0019, -0.014), Vector2(0.0024, -0.003), Vector2(0.0011, 0.026),
			Vector2(0.0, 0.0445), Vector2(-0.0011, 0.026), Vector2(-0.0024, -0.003)]
		for i in range(1, pts.size() - 1):
			var a: Vector2 = pts[0]
			var b: Vector2 = pts[i]
			var c: Vector2 = pts[i + 1]
			CarModel._tri(st, Vector3(a.x, a.y, 0), Vector3(b.x, b.y, 0), Vector3(c.x, c.y, 0), Vector3.BACK, Vector3.BACK, Vector3.BACK)
		_needle = st.commit()
	return _needle


static func _needle_material(col: Color, glow: float) -> StandardMaterial3D:
	var key := "needle|%s|%s" % [col.to_html(), glow]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if glow > 0.0:
		m.emission_enabled = true
		m.emission = col
		m.emission_energy_multiplier = glow
	else:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.5
	_mats[key] = m
	return m


static func _glare_material(t: Texture2D) -> StandardMaterial3D:
	if not _mats.has("glare"):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_texture = t
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		_mats["glare"] = m
	return _mats["glare"]


static func _bezel_material(cab: Dictionary) -> StandardMaterial3D:
	var chrome: bool = cab.get("bezel", "dark") == "chrome"
	return CarModel.mat(Color("#d3d8dd"), 0.0, 0.16, 1.0) if chrome else CarModel.mat(Color("#2b2e33"), 0.0, 0.38, 0.8)


## The instrument panel: the baked art with a bezel and a needle standing above each dial. The needles' pivots go
## into `needles` (speed, then revs) and the shadows they throw on the dial into `shadows`. Returns the panel's
## node: the readout labels hang from it.
static func cluster(parent: Node3D, pos: Vector3, tilt: float, shape_id: String, cab: Dictionary, needles: Array, shadows: Array) -> Node3D:
	var root := Node3D.new()
	root.position = pos
	root.rotation.x = -tilt
	parent.add_child(root)
	var panel := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(CLUSTER_W, CLUSTER_H)
	panel.mesh = qm
	panel.material_override = cluster_material(shape_id)
	panel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(panel)
	var dials: Array = cab.get("dials", ["#f5b52e", "#e6e6e6", "#ff4a2a"])
	var needle_col := Color(String(dials[2]))
	if _bezel == null:
		_bezel = TorusMesh.new()
		_bezel.inner_radius = 0.0492
		_bezel.outer_radius = 0.0548
		_bezel.rings = 40
		_bezel.ring_segments = 6
		_cap = CylinderMesh.new()
		_cap.top_radius = 0.0085
		_cap.bottom_radius = 0.0092
		_cap.height = 0.005
		_cap.radial_segments = 18
	var glare_tex := tex("cluster_glare")
	if glare_tex:  # the glass over the dials catches the light
		var glare := MeshInstance3D.new()
		glare.mesh = qm
		glare.position.z = 0.0112
		glare.material_override = _glare_material(glare_tex)
		glare.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(glare)
	var bezel_mat := _bezel_material(cab)
	var cap_mat := CarModel.mat(Color("#23252a"), 0.0, 0.3, 0.85)
	for k in 2:
		var dial := Node3D.new()
		dial.position = Vector3(DIAL_DX if k == 0 else -DIAL_DX, 0.0, 0.0)
		root.add_child(dial)
		var ring := MeshInstance3D.new()
		ring.mesh = _bezel
		ring.rotation.x = PI / 2.0
		ring.position.z = 0.0026
		ring.material_override = bezel_mat
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		dial.add_child(ring)
		# the shadow the needle throws on the dial (it turns with the needle, a little down and to the right of it)
		var sh_pivot := Node3D.new()
		sh_pivot.position = Vector3(0.0016, -0.0022, 0.0012)
		dial.add_child(sh_pivot)
		var sh := MeshInstance3D.new()
		sh.mesh = needle_mesh()
		sh.material_override = _needle_material(Color(0, 0, 0, 0.5), 0.0)
		sh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		sh_pivot.add_child(sh)
		var pivot := Node3D.new()
		pivot.position = Vector3(0, 0, 0.0065)
		dial.add_child(pivot)
		var needle := MeshInstance3D.new()
		needle.mesh = needle_mesh()
		needle.material_override = _needle_material(needle_col, 2.4)
		needle.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		pivot.add_child(needle)
		var cap := MeshInstance3D.new()
		cap.mesh = _cap
		cap.rotation.x = PI / 2.0
		cap.position.z = 0.0078
		cap.material_override = cap_mat
		cap.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		dial.add_child(cap)
		needles.append(pivot)
		shadows.append(sh_pivot)
	return root


# ------------------------------------------------------------------ the infotainment screen

static func screen_material(shape_id: String) -> StandardMaterial3D:
	var key := "screen|" + shape_id
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	var t := tex("screen_" + shape_id)
	if t:
		m.albedo_texture = t
		m.albedo_color = Color(0.4, 0.4, 0.45)
		m.emission_enabled = true
		m.emission_texture = t
		m.emission_energy_multiplier = 0.95
	else:
		m.albedo_color = Color("#20425e")
	m.roughness = 0.1  # glass: it catches the sky
	m.metallic_specular = 0.9
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_mats[key] = m
	return m


static func screen(parent: Node3D, pos: Vector3, size: Vector2, shape_id: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = size
	mi.mesh = qm
	mi.position = pos
	mi.material_override = screen_material(shape_id)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


# ------------------------------------------------------------------ trim

## A finish for a trim strip: "wood", "carbon", "brushed" (with the cabin's strip colour as a tint) or "paint".
static func trim_material(kind: String, col: Color, tile: Vector2) -> StandardMaterial3D:
	var key := "trim|%s|%s|%s" % [kind, col.to_html(), tile]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	var t: Texture2D = tex("trim_" + kind) if kind != "paint" else null
	if t:
		m.albedo_texture = t
		m.uv1_scale = Vector3(tile.x, tile.y, 1.0)
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	match kind:
		"wood":
			m.roughness = 0.28  # lacquered
			m.metallic_specular = 0.7
		"carbon":
			m.roughness = 0.2
			m.metallic = 0.35
			m.metallic_specular = 0.8
		"brushed":
			m.albedo_color = col.lerp(Color.WHITE, 0.45)
			m.metallic = 0.9
			m.roughness = 0.42
		_:
			m.albedo_color = col
			m.roughness = 0.4
			m.metallic = 0.2
	_mats[key] = m
	return m


## A trim strip as its own little mesh (the art tiles along it), at `pos` with `size`.
static func trim_strip(parent: Node3D, kind: String, col: Color, pos: Vector3, size: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	var tile := Vector2(maxf(size.x, size.z) / 0.045, maxf(size.y, 0.02) / 0.045)
	mi.material_override = trim_material(kind, col, tile)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


# ------------------------------------------------------------------ vents, knobs, buttons (into the cabin's surface tools S)

## A round turbine vent facing the driver: chrome ring, dark throat, five vanes and a pivot.
static func vent_round(S: Dictionary, c: Vector3, r: float) -> void:
	CarModel._cyl(S.chrome, c, r, 0.012, Vector3.BACK, 22)
	CarModel._cyl(S.vent, c + Vector3(0, 0, 0.004), r * 0.86, 0.012, Vector3.BACK, 22)
	for k in 5:
		var a := TAU * k / 5.0 + 0.35
		var dir := Vector3(cos(a), sin(a), 0.0)
		CarModel._box(S.trim, c + dir * r * 0.42 + Vector3(0, 0, 0.0105), Vector3(r * 0.8, 0.0055, 0.004), Basis(Vector3.BACK, a))
	CarModel._cyl(S.chrome, c + Vector3(0, 0, 0.0125), r * 0.2, 0.006, Vector3.BACK, 14)


## A long slim vent: a dark slot behind horizontal slats in a thin chrome frame.
static func vent_strip(S: Dictionary, x0: float, x1: float, y: float, z: float, h := 0.03) -> void:
	var cx := (x0 + x1) / 2.0
	var w := x1 - x0
	CarModel._box(S.chrome, Vector3(cx, y, z), Vector3(w, h + 0.008, 0.01))
	CarModel._box(S.vent, Vector3(cx, y, z + 0.004), Vector3(w - 0.012, h, 0.01))
	for k in 3:
		CarModel._box(S.trim, Vector3(cx, y - h * 0.3 + k * h * 0.3, z + 0.0085), Vector3(w - 0.018, 0.0035, 0.004))


## The rectangular vent: chrome frame, dark throat, three blades.
static func vent_rect(S: Dictionary, c: Vector3, w: float, h: float) -> void:
	CarModel._box(S.chrome, c, Vector3(w, h, 0.01))
	CarModel._box(S.vent, c + Vector3(0, 0, 0.004), Vector3(w - 0.015, h - 0.013, 0.01))
	for k in 3:
		CarModel._box(S.trim, c + Vector3(0, -h * 0.27 + k * h * 0.27, 0.008), Vector3(w - 0.02, 0.006, 0.006))


## A slotted demister grille along the top of the dash, against the windscreen.
static func defrost(S: Dictionary, half_w: float, y: float, z: float) -> void:
	CarModel._box(S.vent, Vector3(0, y, z), Vector3(half_w * 2.0, 0.003, 0.045))
	var n := 26
	for k in n:
		var x := lerpf(-half_w + 0.03, half_w - 0.03, float(k) / (n - 1))
		CarModel._box(S.pad, Vector3(x, y + 0.001, z), Vector3(0.004, 0.0034, 0.045))


## A climate knob: a knurled chrome body, a dark cap and a lit mark.
static func knob(S: Dictionary, c: Vector3, r: float) -> void:
	CarModel._cyl(S.chrome, c, r, 0.02, Vector3.BACK, 20)
	CarModel._cyl(S.vent, c + Vector3(0, 0, 0.0105), r * 0.76, 0.004, Vector3.BACK, 16)
	CarModel._box(S.ambient, c + Vector3(0, r * 0.45, 0.0135), Vector3(0.0035, r * 0.55, 0.002))


## A row of small push buttons with a lit line under each.
static func button_row(S: Dictionary, cx: float, y: float, z: float, count: int, pitch: float) -> void:
	for k in count:
		var x := cx + (k - (count - 1) / 2.0) * pitch
		CarModel._box(S.vent, Vector3(x, y, z), Vector3(pitch * 0.78, 0.014, 0.008))
		CarModel._box(S.ambient, Vector3(x, y - 0.0105, z + 0.0035), Vector3(pitch * 0.5, 0.0025, 0.002))


# ------------------------------------------------------------------ the steering wheel

static func _hexa(st: SurfaceTool, p: Array, centre: Vector3) -> void:
	for f in [[0, 1, 2, 3], [4, 7, 6, 5], [0, 4, 5, 1], [3, 2, 6, 7], [0, 3, 7, 4], [1, 5, 6, 2]]:
		var a: Vector3 = p[f[0]]
		var b: Vector3 = p[f[1]]
		var c: Vector3 = p[f[2]]
		var d: Vector3 = p[f[3]]
		var mid := (a + b + c + d) / 4.0
		CarModel._quad(st, a, b, c, d, CarModel._face_n(a, b, c, mid - centre))


## A spoke from the hub out to the rim: tapered, narrower at the rim, lying in the wheel's plane.
static func _spoke(st: SurfaceTool, ang: float, r0: float, r1: float, w0: float, w1: float, t: float) -> void:
	var d := Vector3(cos(ang), 0.0, sin(ang))
	var s := Vector3(-sin(ang), 0.0, cos(ang))
	var up := Vector3.UP * (t / 2.0)
	var p := [
		d * r0 - s * w0 / 2.0 - up, d * r0 + s * w0 / 2.0 - up, d * r1 + s * w1 / 2.0 - up, d * r1 - s * w1 / 2.0 - up,
		d * r0 - s * w0 / 2.0 + up, d * r0 + s * w0 / 2.0 + up, d * r1 + s * w1 / 2.0 + up, d * r1 - s * w1 / 2.0 + up]
	_hexa(st, p, d * (r0 + r1) / 2.0)


## A prism standing on the wheel's plane: the convex outline `pts` (x, z pairs) from y0 up to y1.
static func _extrude(st: SurfaceTool, pts: Array, y0: float, y1: float) -> void:
	var n := pts.size()
	var c := Vector2.ZERO
	for q in pts:
		c += q as Vector2
	c /= n
	for i in n:
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[(i + 1) % n]
		var e := b - a
		var nn := Vector2(e.y, -e.x).normalized()
		if nn.dot((a + b) / 2.0 - c) < 0.0:
			nn = -nn
		CarModel._quad(st, Vector3(a.x, y0, a.y), Vector3(b.x, y0, b.y), Vector3(b.x, y1, b.y), Vector3(a.x, y1, a.y), Vector3(nn.x, 0.0, nn.y))
	for i in n:
		var a2: Vector2 = pts[i]
		var b2: Vector2 = pts[(i + 1) % n]
		CarModel._tri(st, Vector3(c.x, y1, c.y), Vector3(a2.x, y1, a2.y), Vector3(b2.x, y1, b2.y), Vector3.UP, Vector3.UP, Vector3.UP)
		CarModel._tri(st, Vector3(c.x, y0, c.y), Vector3(a2.x, y0, a2.y), Vector3(b2.x, y0, b2.y), Vector3.DOWN, Vector3.DOWN, Vector3.DOWN)


static func _rounded_rect(hx: float, hz: float, r: float) -> Array:
	var pts: Array = []
	for corner in 4:
		var cx := (hx - r) * (1.0 if corner in [0, 3] else -1.0)
		var cz := (hz - r) * (1.0 if corner in [0, 1] else -1.0)
		var a0: float = [0.0, PI / 2.0, PI, PI * 1.5][corner]
		for k in 6:
			var a: float = a0 + (PI / 2.0) * k / 5.0
			pts.append(Vector2(cx + r * cos(a), cz + r * sin(a)))
	return pts


## The rim: an oval-section tube, slimmer at the top and bottom and fuller where the hands go (at three and nine),
## with a seam of contrast stitching along the face towards the driver. `kind` is "round", "flat" (flat bottom) or
## "yoke" (flat top and bottom). L takes the leather, S the stitches.
static func _rim_into(L: SurfaceTool, S: SurfaceTool, kind: String, thin: bool) -> void:
	var n := 72
	var m := 14
	var path: Array[Vector3] = []
	var rad: Array[float] = []
	for i in n:
		var th := TAU * i / n
		var p := Vector3(cos(th), 0.0, sin(th)) * RIM_R
		if kind == "flat" or kind == "yoke":
			p.z = minf(p.z, 0.118)
		if kind == "yoke":
			p.z = maxf(p.z, -0.105)
		path.append(p)
		rad.append((0.0132 if thin else 0.0170) * (0.88 + 0.24 * (0.5 + 0.5 * cos(2.0 * th))))
	var bs: Array[Vector3] = []
	for i in n:
		var t := (path[(i + 1) % n] - path[(i - 1 + n) % n]).normalized()
		bs.append(t.cross(Vector3.UP).normalized())  # (towards the middle of the wheel)
	for i in n:
		var i2 := (i + 1) % n
		var ra0 := rad[i]
		var ra1 := rad[i2]
		for j in m:
			var a0 := TAU * j / m
			var a1 := TAU * (j + 1) / m
			var n00 := (bs[i] * cos(a0) / ra0 + Vector3.UP * sin(a0) / (ra0 * 1.12)).normalized()
			var n01 := (bs[i] * cos(a1) / ra0 + Vector3.UP * sin(a1) / (ra0 * 1.12)).normalized()
			var n10 := (bs[i2] * cos(a0) / ra1 + Vector3.UP * sin(a0) / (ra1 * 1.12)).normalized()
			var n11 := (bs[i2] * cos(a1) / ra1 + Vector3.UP * sin(a1) / (ra1 * 1.12)).normalized()
			var p00 := path[i] + bs[i] * cos(a0) * ra0 + Vector3.UP * sin(a0) * ra0 * 1.12
			var p01 := path[i] + bs[i] * cos(a1) * ra0 + Vector3.UP * sin(a1) * ra0 * 1.12
			var p10 := path[i2] + bs[i2] * cos(a0) * ra1 + Vector3.UP * sin(a0) * ra1 * 1.12
			var p11 := path[i2] + bs[i2] * cos(a1) * ra1 + Vector3.UP * sin(a1) * ra1 * 1.12
			CarModel._tri(L, p00, p01, p11, n00, n01, n11)
			CarModel._tri(L, p00, p11, p10, n00, n11, n10)
		# one stitch per step along the face towards the driver
		var u0 := 0.18
		var u1 := 0.68
		var q0 := path[i].lerp(path[i2], u0)
		var q1 := path[i].lerp(path[i2], u1)
		var b0 := bs[i].lerp(bs[i2], u0).normalized()
		var b1 := bs[i].lerp(bs[i2], u1).normalized()
		var lift := Vector3.UP * (rad[i] * 1.12 + 0.0004)
		CarModel._quad(S, q0 - b0 * 0.0016 + lift, q0 + b0 * 0.0016 + lift, q1 + b1 * 0.0016 + lift, q1 - b1 * 0.0016 + lift, Vector3.UP)


## Builds the whole wheel into `steer` (its plane is xz, the face towards the driver is +y, twelve o'clock is -z).
static func wheel(steer: Node3D, cab: Dictionary, leather: Material, body: Material, chrome: Material, dark: Material, stitch: Material) -> void:
	var kind: String = cab.get("wheel", "round")
	var metal: bool = cab.get("spoke_metal", false)
	var sts := {}
	for k in ["leather", "stitch", "body", "dark", "chrome", "accent"]:
		sts[k] = CarModel._new_st()
	_rim_into(sts.leather, sts.stitch, kind, cab.get("thin_rim", false))
	var spokes: Array = cab.get("spokes", [0.0, PI, PI * 0.5])
	for a in spokes:
		var ang := float(a)
		var reach := RIM_R
		if kind != "round" and sin(ang) > 0.7:
			reach = 0.118  # down to the flat bottom
		if metal:
			_spoke(sts.body, ang, 0.03, reach - 0.004, 0.04, 0.03, 0.011)
			for k in 3:  # slots cut through the spoke
				var d := Vector3(cos(ang), 0.0, sin(ang))
				var r := lerpf(0.085, reach - 0.035, k / 2.0)
				CarModel._box(sts.dark, d * r, Vector3(reach * 0.12, 0.0118, 0.012), Basis(Vector3.UP, -ang))
		else:
			_spoke(sts.body, ang, 0.03, reach - 0.004, 0.06, 0.036, 0.022)
			if absf(cos(ang)) > 0.8:  # buttons on the side spokes: two rows of two, with a lit edge
				var d2 := Vector3(cos(ang), 0.0, sin(ang))
				var s2 := Vector3(-sin(ang), 0.0, cos(ang))
				for rr in 2:
					for ss in 2:
						var c := d2 * (0.082 + rr * 0.026) + s2 * ((ss - 0.5) * 0.017) + Vector3.UP * 0.012
						CarModel._box(sts.dark, c, Vector3(0.019, 0.004, 0.015), Basis(Vector3.UP, -ang))
						CarModel._box(sts.accent, c + s2 * ((ss - 0.5) * 0.0) + Vector3.UP * 0.0022, Vector3(0.008, 0.0012, 0.0025), Basis(Vector3.UP, -ang))
	# the hub with the airbag cover, and the badge on it
	var top_y := 0.0
	if cab.get("hub", "box") == "round":
		CarModel._cyl(sts.body, Vector3(0, 0.0, 0), 0.064, 0.034, Vector3.UP, 28)
		CarModel._cyl(sts.body, Vector3(0, 0.024, 0), 0.056, 0.014, Vector3.UP, 28)
		CarModel._cyl(sts.chrome, Vector3(0, 0.0275, 0), 0.0585, 0.0016, Vector3.UP, 28)
		top_y = 0.0315
	else:
		_extrude(sts.body, _rounded_rect(0.062, 0.05, 0.026), -0.02, 0.026)
		_extrude(sts.dark, _rounded_rect(0.052, 0.04, 0.02), 0.0255, 0.0272)
		top_y = 0.0272
	CarModel._cyl(sts.chrome, Vector3(0, top_y + 0.002, 0), 0.0185, 0.004, Vector3.UP, 20)
	CarModel._cyl(sts.accent, Vector3(0, top_y + 0.0045, 0), 0.0125, 0.0025, Vector3.UP, 20)
	var mesh := ArrayMesh.new()
	var mats: Array = []
	var by := {"leather": leather, "stitch": stitch, "body": body, "dark": dark, "chrome": chrome,
		"accent": CarModel.mat(Color(String(cab.get("accent", cab.get("stitch", "#f5b52e")))), 1.4)}
	for k in ["leather", "stitch", "body", "dark", "chrome", "accent"]:
		var arrays: Array = (sts[k] as SurfaceTool).commit_to_arrays()
		if arrays[Mesh.ARRAY_VERTEX] == null or (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).is_empty():
			continue
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mats.append(by[k])
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	for i in mats.size():
		mi.set_surface_override_material(i, mats[i])
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	steer.add_child(mi)
	if cab.has("marker"):  # the straight-ahead mark at twelve o'clock
		var mk := MeshInstance3D.new()
		mk.mesh = CarModel.box_mesh(Vector3(0.014, 0.036, 0.045))
		mk.position = Vector3(0, 0, -0.105 if kind == "yoke" else -RIM_R)
		mk.material_override = CarModel.mat(Color(String(cab.marker)), 0.6)
		steer.add_child(mk)


# ------------------------------------------------------------------ the driver's hands

## An ellipsoid with semi-axes r (in the frame `b`) about c.
static func _blob(st: SurfaceTool, c: Vector3, r: Vector3, b: Basis, rings := 6, segs := 10) -> void:
	for i in rings:
		var la0 := -PI / 2.0 + PI * i / rings
		var la1 := -PI / 2.0 + PI * (i + 1) / rings
		for j in segs:
			var lo0 := TAU * j / segs
			var lo1 := TAU * (j + 1) / segs
			var q := []
			for pr in [[la0, lo0], [la0, lo1], [la1, lo1], [la1, lo0]]:
				var local := Vector3(cos(pr[0]) * cos(pr[1]), sin(pr[0]), cos(pr[0]) * sin(pr[1]))
				var pos := c + b * (local * r)
				var nrm := (b * (local / r)).normalized()
				q.append([pos, nrm])
			CarModel._tri(st, q[0][0], q[1][0], q[2][0], q[0][1], q[1][1], q[2][1])
			CarModel._tri(st, q[0][0], q[2][0], q[3][0], q[0][1], q[2][1], q[3][1])


## A gloved hand gripping the rim at about a quarter to three, seen from the driver's seat: the back of the hand
## over the rim, the fingers curling round it to the inside and the thumb along its face. `side` is -1 for the left
## hand, +1 for the right. Positions are from the grip point, in the wheel's own frame (x right, y towards the
## driver, z down).
static func hand_mesh(side: float) -> ArrayMesh:
	var st := CarModel._new_st()
	var yaw := Basis(Vector3.UP, side * 0.2)
	_blob(st, Vector3(0.0, 0.017, 0.0), Vector3(0.031, 0.016, 0.042), yaw, 7, 12)                       # the back of the hand
	_blob(st, Vector3(-side * 0.012, 0.012, 0.0), Vector3(0.026, 0.019, 0.044), yaw, 6, 10)            # the heel of it
	for k in 4:  # four fingers hooked over the inner edge of the rim
		var z := -0.0285 + k * 0.019 + 0.004
		var len_k := 0.0165 - absf(k - 1.5) * 0.0012
		_blob(st, Vector3(-side * 0.026, 0.0, z + 0.004), Vector3(len_k, 0.0078, 0.0083), Basis(Vector3.UP, side * 0.1), 4, 8)
		_blob(st, Vector3(-side * 0.0395, -0.0075, z + 0.004), Vector3(0.0078, 0.0088, 0.0079), Basis(), 4, 8)  # the knuckle turning round
	_blob(st, Vector3(-side * 0.012, 0.03, -0.037), Vector3(0.0085, 0.0092, 0.027), Basis(Vector3.UP, side * 0.25), 5, 8)  # the thumb along the face
	var m := st.commit()
	return m
