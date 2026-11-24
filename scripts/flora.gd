class_name Flora
extends RefCounted
## The plants and ground cover along the highway, for each kind of country it runs through (Data.BIOMES "flora"):
## farmland ("temperate"), autumn woods ("autumn"), northern pines ("conifer"), desert ("desert"), the coast ("coast") and
## frosted plains ("snow"). Scenery builds a kind the first time its highway is chosen and keeps it.
##
## Everything here is plain data, with no scene: each plant is one small mesh with its colours baked into the vertices (the
## crown of a tree lighter on top and darker underneath, a blade of grass dark at the root and bright at the tip), made
## once, and the road is dressed with transforms of it: `build` returns, for a kind of country, the meshes and where each is
## planted. Scenery cuts the lists into chunks along the road and draws them as multimeshes (a draw call a chunk and a plant
## kind, however many plants). tools/flora_gallery.tscn shows every plant; tools/flora_test.tscn counts them.
##
## The colours are written as sRGB, as everywhere else, and the material says so (vertex_color_is_srgb): read as linear they
## came out three times too bright, which is why the old trees were pale mint.

const KINDS := ["temperate", "autumn", "conifer", "desert", "coast", "snow"]

## How much the ground beside the road rolls in each kind of country (1 is gentle farmland): Scenery raises the swells of the
## ground by this much, and the plants stand on them (`cfg.ground`).
const RELIEF := {"temperate": 1.0, "autumn": 1.15, "conifer": 1.6, "desert": 1.3, "coast": 0.8, "snow": 1.0}

## What each plant needs from the scene that draws it: thin (blades and fronds, drawn from both sides), whether it casts a
## shadow, and how far away it is drawn (m: beyond that the depth fog has long since hidden it).
const PROPS := {
	"oak0": {"shadow": true, "range": 420.0}, "oak1": {"shadow": true, "range": 420.0}, "poplar": {"shadow": true, "range": 420.0},
	"oakA0": {"shadow": true, "range": 420.0}, "oakA1": {"shadow": true, "range": 420.0}, "oakA2": {"shadow": true, "range": 420.0}, "poplarA": {"shadow": true, "range": 420.0},
	"bushA": {"shadow": false, "range": 300.0}, "far_blobA": {"shadow": false, "range": 0.0},
	"spruce0": {"shadow": true, "range": 420.0}, "spruce1": {"shadow": true, "range": 420.0},
	"snowspruce0": {"shadow": true, "range": 420.0}, "snowspruce1": {"shadow": true, "range": 420.0},
	"bare0": {"shadow": true, "range": 380.0, "thin": true}, "bare1": {"shadow": true, "range": 380.0, "thin": true},
	"palm0": {"shadow": false, "range": 380.0, "thin": true}, "palm1": {"shadow": false, "range": 380.0, "thin": true},
	"saguaro0": {"shadow": true, "range": 360.0}, "saguaro1": {"shadow": true, "range": 360.0},
	"barrel": {"shadow": false, "range": 200.0}, "pear": {"shadow": false, "range": 220.0}, "agave": {"shadow": false, "range": 200.0, "thin": true},
	"scrub": {"shadow": false, "range": 260.0}, "bush0": {"shadow": false, "range": 300.0}, "bush1": {"shadow": false, "range": 300.0},
	"fern": {"shadow": false, "range": 180.0, "thin": true}, "tuft": {"shadow": false, "range": 170.0, "thin": true},
	"tall": {"shadow": false, "range": 190.0, "thin": true},
	"far_blob": {"shadow": false, "range": 0.0}, "far_cone": {"shadow": false, "range": 0.0},
}

static var _cache := {}
static var _mats := {}


## The material every plant is drawn with: its colours are in the vertices. Blades and fronds are single sheets, so those are
## drawn from both sides; solid shapes keep their back faces culled.
static func material(thin: bool) -> StandardMaterial3D:
	var k := 1 if thin else 0
	if not _mats.has(k):
		var m := StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true
		m.vertex_color_is_srgb = true
		m.roughness = 1.0
		m.metallic_specular = 0.25
		m.cull_mode = BaseMaterial3D.CULL_DISABLED if thin else BaseMaterial3D.CULL_BACK
		_mats[k] = m
	return _mats[k]


## The mesh of a plant, by key (see PROPS), made the first time it is asked for.
static func mesh(key: String) -> ArrayMesh:
	if not _cache.has(key):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_make(key, st)
		_cache[key] = st.commit()
	return _cache[key]


static func thin(key: String) -> bool:
	return bool((PROPS[key] as Dictionary).get("thin", false))


# ---------------------------------------------------------------- helpers

static func _h(n: float) -> float:
	return fposmod(sin(n * 12.9898 + 4.1414) * 43758.5453, 1.0)


static func _shade(c: Color, f: float) -> Color:
	return Color(clampf(c.r * f, 0.0, 1.0), clampf(c.g * f, 0.0, 1.0), clampf(c.b * f, 0.0, 1.0))


## One triangle, wound so that it faces the way its normals do.
static func _tri(st: SurfaceTool, p: Array, n: Array, c: Array) -> void:
	var gn: Vector3 = ((p[1] as Vector3) - (p[0] as Vector3)).cross((p[2] as Vector3) - (p[0] as Vector3))
	var out: Vector3 = (n[0] as Vector3) + (n[1] as Vector3) + (n[2] as Vector3)
	var order: Array = [0, 1, 2] if gn.dot(out) < 0.0 else [0, 2, 1]  # (Godot's front faces are the clockwise ones)
	for i in order:
		st.set_color(c[i])
		st.set_normal(n[i])
		st.add_vertex(p[i])


static func _quad(st: SurfaceTool, p: Array, n: Array, c: Array) -> void:
	_tri(st, [p[0], p[1], p[2]], [n[0], n[1], n[2]], [c[0], c[1], c[2]])
	_tri(st, [p[0], p[2], p[3]], [n[0], n[2], n[3]], [c[0], c[2], c[3]])


## A lumpy ellipsoid: lighter on top, darker underneath, its surface pushed in and out a little. A leafy crown, a bush, a rock.
static func _blob(st: SurfaceTool, ctr: Vector3, r: Vector3, sd: float, rings: int, segs: int, top: Color, bot: Color, jit := 0.16, soft := 0.55) -> void:
	var pos: Array = []
	var nor: Array = []
	var col: Array = []
	for i in rings + 1:
		var th := PI * float(i) / float(rings)
		for j in segs:
			var ph := TAU * float(j) / float(segs)
			var d := Vector3(sin(th) * cos(ph), cos(th), sin(th) * sin(ph))
			var k := 1.0
			if i > 0 and i < rings:
				k += jit * (_h(sd + float(i) * 7.31 + float(j) * 3.17) * 2.0 - 1.0)
			pos.append(ctr + d * r * k)
			# (the normals lean towards the sky: the underside of a crown is lit by the ground and the leaves round it, not black)
			nor.append((Vector3(d.x / maxf(r.x, 0.001), d.y / maxf(r.y, 0.001), d.z / maxf(r.z, 0.001)).normalized() + Vector3.UP * soft).normalized())
			col.append(_shade(bot.lerp(top, smoothstep(-0.6, 0.85, d.y)), 0.9 + 0.2 * _h(sd + float(i * 31 + j))))
	for i in rings:
		for j in segs:
			var j2 := (j + 1) % segs
			var a := i * segs + j
			var b := i * segs + j2
			var c2 := (i + 1) * segs + j2
			var d2 := (i + 1) * segs + j
			if i > 0:
				_tri(st, [pos[a], pos[b], pos[c2]], [nor[a], nor[b], nor[c2]], [col[a], col[b], col[c2]])
			if i < rings - 1:
				_tri(st, [pos[a], pos[c2], pos[d2]], [nor[a], nor[c2], nor[d2]], [col[a], col[c2], col[d2]])


## A tapered tube from a to b (a trunk, a branch, a cactus arm); `rib` > 0 flutes it, as a cactus is.
static func _prism(st: SurfaceTool, a: Vector3, b: Vector3, ra: float, rb: float, segs: int, ca: Color, cb: Color, rib := 0.0, tip := false) -> void:
	var axis := b - a
	var length := axis.length()
	if length < 0.0001:
		return
	var dir := axis / length
	var ref := Vector3.UP if absf(dir.y) < 0.95 else Vector3.RIGHT
	var u := dir.cross(ref).normalized()
	var v := dir.cross(u).normalized()
	for j in segs:
		var a0 := TAU * float(j) / float(segs)
		var a1 := TAU * float(j + 1) / float(segs)
		var n0 := u * cos(a0) + v * sin(a0)
		var n1 := u * cos(a1) + v * sin(a1)
		var k0 := 1.0 - rib * float(j % 2)
		var k1 := 1.0 - rib * float((j + 1) % 2)
		_quad(st, [a + n0 * ra * k0, a + n1 * ra * k1, b + n1 * rb * k1, b + n0 * rb * k0], [n0, n1, n1, n0], [ca, ca, cb, cb])
		if tip:  # a rounded end
			var cap := b + dir * rb * 0.9
			_tri(st, [b + n0 * rb * k0, b + n1 * rb * k1, cap], [(n0 + dir).normalized(), (n1 + dir).normalized(), dir], [cb, cb, cb])


## A tier of a spruce: a ragged cone seen from outside, dark at the hem and `top` on its upper side (white for snow).
static func _tier(st: SurfaceTool, y0: float, y1: float, r0: float, r1: float, sd: float, segs: int, hem: Color, mid: Color, top: Color) -> void:
	var rows := [[y0, r0, hem], [lerpf(y0, y1, 0.35), lerpf(r0, r1, 0.35), mid], [y1, r1, top]]
	var ring: Array = []
	for row in rows:
		var pts: Array = []
		for j in segs:
			var ph := TAU * float(j) / float(segs)
			var k := 1.0 + 0.16 * (_h(sd + float(j) * 5.7 + float(row[0]) * 3.1) * 2.0 - 1.0) if row[1] > 0.05 else 1.0
			pts.append(Vector3(cos(ph), 0.0, sin(ph)) * float(row[1]) * k + Vector3(0.0, float(row[0]) - 0.1 * (k - 1.0) * float(row[1]), 0.0))
		ring.append(pts)
	var slope := (r0 - r1)
	for s in 2:
		for j in segs:
			var j2 := (j + 1) % segs
			var pa: Vector3 = ring[s][j]
			var pb: Vector3 = ring[s][j2]
			var pc: Vector3 = ring[s + 1][j2]
			var pd: Vector3 = ring[s + 1][j]
			var ph0 := TAU * float(j) / float(segs)
			var ph1 := TAU * float(j2) / float(segs)
			var n0 := (Vector3(cos(ph0), 0.0, sin(ph0)) * (y1 - y0) + Vector3.UP * slope).normalized()
			var n1 := (Vector3(cos(ph1), 0.0, sin(ph1)) * (y1 - y0) + Vector3.UP * slope).normalized()
			var c0: Color = rows[s][2]
			var c1: Color = rows[s + 1][2]
			_quad(st, [pa, pb, pc, pd], [n0, n1, n1, n0], [c0, c0, c1, c1])


## A blade: three sections bending away from upright, narrowing to a point; dark at the root, bright at the tip.
static func _blade(st: SurfaceTool, base: Vector3, yaw: float, length: float, width: float, lean: float, root: Color, tip: Color) -> void:
	var out := Vector3(cos(yaw), 0.0, sin(yaw))
	var side := Vector3(-sin(yaw), 0.0, cos(yaw))
	var pts: Array = []
	for i in 4:
		var t := float(i) / 3.0
		pts.append(base + out * (lean * length * t * t) + Vector3.UP * (length * (t - 0.18 * t * t)))
	for i in 3:
		var t0 := float(i) / 3.0
		var t1 := float(i + 1) / 3.0
		var w0 := width * (1.0 - t0)
		var w1 := width * (1.0 - t1)
		var c0 := root.lerp(tip, t0)
		var c1 := root.lerp(tip, t1)
		var nrm := (Vector3.UP * 0.75 + out * 0.45).normalized()
		if i < 2:
			_quad(st, [pts[i] - side * w0, pts[i] + side * w0, pts[i + 1] + side * w1, pts[i + 1] - side * w1], [nrm, nrm, nrm, nrm], [c0, c0, c1, c1])
		else:
			_tri(st, [pts[i] - side * w0, pts[i] + side * w0, pts[i + 1]], [nrm, nrm, nrm], [c0, c0, c1])


## A palm frond: a long leaf arching up and out from `base` and drooping at the end.
static func _frond(st: SurfaceTool, base: Vector3, yaw: float, length: float, rise: float, droop: float, width: float, root: Color, tip: Color) -> void:
	var out := Vector3(cos(yaw), 0.0, sin(yaw))
	var side := Vector3(-sin(yaw), 0.0, cos(yaw))
	var n := 5
	var pts: Array = []
	for i in n + 1:
		var t := float(i) / float(n)
		pts.append(base + out * (length * t) + Vector3.UP * (length * (rise * t - droop * t * t)))
	for i in n:
		var t0 := float(i) / float(n)
		var t1 := float(i + 1) / float(n)
		var w0 := width * sin(PI * clampf(t0 * 0.9 + 0.1, 0.0, 1.0))
		var w1 := width * sin(PI * clampf(t1 * 0.9 + 0.1, 0.0, 1.0)) if i < n - 1 else 0.0
		var c0 := root.lerp(tip, t0)
		var c1 := root.lerp(tip, t1)
		var nrm := (Vector3.UP + out * 0.2).normalized()
		_quad(st, [pts[i] - side * w0, pts[i] + side * w0, pts[i + 1] + side * w1, pts[i + 1] - side * w1], [nrm, nrm, nrm, nrm], [c0, c0, c1, c1])


# ---------------------------------------------------------------- the plants

const BARK := Color("#4a3b2b")
const BARK_DARK := Color("#33291e")
const BIRCH := Color("#d6d2c6")


static func _make(key: String, st: SurfaceTool) -> void:
	match key:
		"oak0": _oak(st, 1.0, Color("#527a32"), Color("#44693a"))
		"oak1": _oak(st, 2.0, Color("#5f8238"), Color("#4b6f3a"))
		"poplar": _poplar(st, Color("#62863a"), Color("#4b6f3a"))
		"oakA0": _oak(st, 1.0, Color("#d27a22"), Color("#a65a24"))   # (autumn: orange, red and gold crowns on ordinary bark)
		"oakA1": _oak(st, 2.0, Color("#bd3f1f"), Color("#8c3a22"))
		"oakA2": _oak(st, 3.0, Color("#dcab2c"), Color("#b0782a"))
		"poplarA": _poplar(st, Color("#dcae30"), Color("#b0802a"))
		"bushA": _bush(st, 1.0, Color("#b9671f"), Color("#7e4a22"))
		"far_blobA": _far_blob(st, Color("#c47a28"), Color("#94582a"))
		"spruce0": _spruce(st, 1.0, false)
		"spruce1": _spruce(st, 2.0, false)
		"snowspruce0": _spruce(st, 1.0, true)
		"snowspruce1": _spruce(st, 2.0, true)
		"bare0": _bare(st, 1.0)
		"bare1": _bare(st, 2.0)
		"palm0": _palm(st, 1.0)
		"palm1": _palm(st, 2.0)
		"saguaro0": _saguaro(st, 1.0)
		"saguaro1": _saguaro(st, 2.0)
		"barrel": _barrel(st)
		"pear": _pear(st)
		"agave": _agave(st)
		"scrub": _scrub(st)
		"bush0": _bush(st, 1.0, Color("#4f7330"), Color("#44693a"))
		"bush1": _bush(st, 2.0, Color("#5d7e34"), Color("#44693a"))
		"fern": _fern(st)
		"tuft": _tuft(st, false)
		"tall": _tuft(st, true)
		"far_blob": _far_blob(st, Color("#4d7030"), Color("#44693a"))
		"far_cone": _far_cone(st)


## An oak or an ash: a clear trunk, a few limbs, and a crown of lumps of leaves (about 330 triangles; the old crown was seven
## balls and 700).
static func _oak(st: SurfaceTool, sd: float, top: Color, bot: Color) -> void:
	var th := 2.7 if sd < 1.5 else 3.2
	_prism(st, Vector3(0, 0, 0), Vector3(0, th, 0), 0.34, 0.2, 7, BARK_DARK, BARK)
	_prism(st, Vector3(0, th * 0.8, 0), Vector3(1.3, th + 1.5, 0.4), 0.14, 0.08, 5, BARK, BARK)
	_prism(st, Vector3(0, th * 0.85, 0), Vector3(-1.2, th + 1.3, -0.6), 0.13, 0.07, 5, BARK, BARK)
	var cy := th + 2.4
	_blob(st, Vector3(0, cy, 0), Vector3(3.1, 2.5, 3.0), sd * 11.0, 5, 9, top, bot, 0.14)
	_blob(st, Vector3(1.9, cy - 0.5, 0.7), Vector3(1.9, 1.6, 1.8), sd * 13.0, 4, 7, top, bot, 0.18)
	_blob(st, Vector3(-1.8, cy - 0.3, -0.9), Vector3(1.9, 1.5, 1.8), sd * 17.0, 4, 7, top, bot, 0.18)
	_blob(st, Vector3(0.3, cy + 1.5, -1.0), Vector3(1.9, 1.4, 1.8), sd * 19.0, 4, 7, _shade(top, 1.1), bot, 0.18)
	_blob(st, Vector3(-0.4, cy - 0.2, 2.0), Vector3(1.8, 1.4, 1.5), sd * 23.0, 4, 7, top, bot, 0.18)


static func _poplar(st: SurfaceTool, top: Color, bot: Color) -> void:
	_prism(st, Vector3.ZERO, Vector3(0, 2.0, 0), 0.22, 0.14, 6, BARK_DARK, BARK)
	_blob(st, Vector3(0, 6.2, 0), Vector3(1.5, 5.0, 1.5), 41.0, 6, 8, top, bot, 0.12)
	_blob(st, Vector3(0.3, 3.7, 0.2), Vector3(1.3, 2.0, 1.3), 43.0, 4, 7, _shade(top, 0.95), bot, 0.15)


## A spruce: a trunk and tiers of branches that get smaller towards the tip (about 150 triangles). With snow each tier is
## white on top and green at its hem.
static func _spruce(st: SurfaceTool, sd: float, snow: bool) -> void:
	var tiers := 7
	var height := 12.0
	var hem := Color("#1d3624") if sd < 1.5 else Color("#22412a")
	var mid := Color("#27472c") if sd < 1.5 else Color("#2c5232")
	var top := Color("#325c37") if sd < 1.5 else Color("#376540")
	if snow:
		hem = Color("#2a4a3a")
		mid = Color("#9fb5b8")
		top = Color("#eef3f6")
	_prism(st, Vector3.ZERO, Vector3(0, 2.2, 0), 0.3, 0.22, 6, BARK_DARK, BARK)
	for t in tiers:
		var f := float(t) / float(tiers)
		var y0 := 1.3 + f * height * 0.84
		var y1 := y0 + height * 0.26
		var r0 := (3.0 if sd < 1.5 else 2.6) * pow(1.0 - f, 0.85) + 0.35
		var r1 := r0 * 0.3
		_tier(st, y0, y1, r0, r1, sd * 7.0 + float(t) * 3.3, 9, hem, mid, top)
	var y_last := 1.3 + float(tiers - 1) / float(tiers) * height * 0.84 + height * 0.26
	_tier(st, y_last - 1.1, y_last + 2.6, 0.85, 0.0, sd * 3.0, 6, hem, mid, top)


## A tree with no leaves: a trunk forking into branches that fork again, thin and grey-brown.
static func _bare(st: SurfaceTool, sd: float) -> void:
	var bark := Color("#5d5348") if sd < 1.5 else Color("#6a6258")
	_prism(st, Vector3.ZERO, Vector3(0.1, 4.6, 0.0), 0.3, 0.14, 6, _shade(bark, 0.75), bark)
	for i in 5:
		var ang := TAU * float(i) / 5.0 + sd * 1.3
		var out := Vector3(cos(ang), 0.0, sin(ang))
		var h0 := 2.6 + 0.6 * float(i % 3)
		var p0 := Vector3(0.1, h0, 0.0)
		var p1 := p0 + out * 1.9 + Vector3.UP * 2.0
		_prism(st, p0, p1, 0.13, 0.06, 5, bark, bark)
		for q in 2:
			var a2 := ang + (0.75 if q == 0 else -0.75)
			var o2 := Vector3(cos(a2), 0.0, sin(a2))
			var p2 := p1 + o2 * 1.3 + Vector3.UP * 1.5
			_prism(st, p1, p2, 0.065, 0.03, 4, bark, bark)
			_prism(st, p2, p2 + (o2 + out).normalized() * 0.8 + Vector3.UP * 0.9, 0.035, 0.015, 3, bark, bark)
	_prism(st, Vector3(0.1, 4.6, 0.0), Vector3(0.0, 7.2, 0.2), 0.14, 0.04, 4, bark, bark)


## A palm: a trunk leaning a little and ringed, and a crown of drooping fronds.
static func _palm(st: SurfaceTool, sd: float) -> void:
	var seg := 7
	var lean := 1.3 if sd < 1.5 else 1.9
	var height := 7.8 if sd < 1.5 else 6.6
	var prev := Vector3.ZERO
	for i in seg:
		var t := float(i + 1) / float(seg)
		var p := Vector3(lean * t * t, height * t, 0.0)
		var ring := 1.0 if i % 2 == 0 else 0.84
		_prism(st, prev, p, 0.34 * (1.0 - 0.32 * float(i) / seg), 0.34 * (1.0 - 0.32 * t), 7, _shade(Color("#6e5f4b"), ring), _shade(Color("#86765f"), ring))
		prev = p
	var top := Vector3(lean, height, 0.0)
	for i in 14:
		var yaw := TAU * float(i) / 14.0 + sd * 0.7
		var len := 4.2 + 1.0 * _h(sd * 5.0 + float(i))
		_frond(st, top, yaw, len, 0.5 + 0.3 * _h(float(i) * 2.3), 0.95, 0.62, Color("#33602a"), Color("#6a9a38"))
	_blob(st, top + Vector3(0, -0.2, 0), Vector3(0.5, 0.42, 0.5), sd, 3, 6, Color("#6a5a40"), Color("#4a3c2a"), 0.1)


## A saguaro: a fluted green column with arms that rise from an elbow.
static func _saguaro(st: SurfaceTool, sd: float) -> void:
	var green := Color("#56794a")
	var dark := Color("#3d5b3a")
	var h := 5.6 if sd < 1.5 else 4.4
	_prism(st, Vector3.ZERO, Vector3(0, h, 0), 0.4, 0.36, 10, dark, green, 0.14, true)
	var arms := 2 if sd < 1.5 else 1
	for i in arms:
		var side := -1.0 if i == 0 else 1.0
		var y0 := 1.7 + 1.0 * float(i) + 0.3 * sd
		var out := Vector3(side * 1.35, y0 + 0.25, 0.0)
		_prism(st, Vector3(side * 0.2, y0, 0.0), out, 0.27, 0.27, 8, dark, green, 0.14)
		_prism(st, out, out + Vector3(side * 0.15, 1.9 + 0.5 * float(i), 0.0), 0.27, 0.25, 8, green, green, 0.14, true)


static func _barrel(st: SurfaceTool) -> void:
	_blob(st, Vector3(0, 0.38, 0), Vector3(0.42, 0.42, 0.42), 5.0, 4, 10, Color("#5b8250"), Color("#3a5a35"), 0.1)
	_blob(st, Vector3(0, 0.78, 0), Vector3(0.16, 0.07, 0.16), 6.0, 2, 6, Color("#e0c050"), Color("#b89a30"), 0.05)


## A prickly pear: flat pads growing out of one another.
static func _pear(st: SurfaceTool) -> void:
	var pads := [[Vector3(0, 0.35, 0), Vector3(0.3, 0.38, 0.07)], [Vector3(0.28, 0.72, 0.05), Vector3(0.26, 0.32, 0.06)], [Vector3(-0.26, 0.68, -0.04), Vector3(0.25, 0.3, 0.06)],
		[Vector3(0.05, 1.05, 0.02), Vector3(0.22, 0.28, 0.06)], [Vector3(0.52, 1.0, 0.08), Vector3(0.2, 0.26, 0.05)]]
	var i := 0
	for p in pads:
		_blob(st, p[0], p[1], 9.0 + float(i), 3, 7, Color("#6c9a58"), Color("#456b3c"), 0.06)
		i += 1


## An agave or a yucca: a rosette of stiff pointed leaves.
static func _agave(st: SurfaceTool) -> void:
	for i in 13:
		var yaw := TAU * float(i) / 13.0 + 0.4 * _h(float(i))
		_blade(st, Vector3(0, 0.05, 0), yaw, 0.95 + 0.25 * _h(float(i) * 3.0), 0.11, 0.55 + 0.3 * _h(float(i) * 1.7), Color("#3f5f4a"), Color("#8fb59a"))


## Sagebrush: a low grey-green clump.
static func _scrub(st: SurfaceTool) -> void:
	_blob(st, Vector3(0, 0.35, 0), Vector3(0.85, 0.42, 0.75), 15.0, 3, 8, Color("#8b9568"), Color("#5a6244"), 0.2)
	_blob(st, Vector3(0.5, 0.28, 0.3), Vector3(0.5, 0.3, 0.45), 16.0, 3, 7, Color("#99a272"), Color("#646c49"), 0.2)


static func _bush(st: SurfaceTool, sd: float, top: Color, bot: Color) -> void:
	_blob(st, Vector3(0, 0.5, 0), Vector3(1.0, 0.62, 0.9), sd * 21.0, 4, 8, top, bot, 0.18)
	_blob(st, Vector3(0.8, 0.38, 0.2), Vector3(0.7, 0.46, 0.65), sd * 23.0, 3, 7, top, bot, 0.2)
	_blob(st, Vector3(-0.7, 0.36, -0.3), Vector3(0.65, 0.44, 0.6), sd * 25.0, 3, 7, top, bot, 0.2)


static func _fern(st: SurfaceTool) -> void:
	for i in 9:
		var yaw := TAU * float(i) / 9.0 + 0.3 * _h(float(i) * 1.3)
		_blade(st, Vector3.ZERO, yaw, 0.8 + 0.3 * _h(float(i) * 2.9), 0.15, 0.9, Color("#2a4a24"), Color("#5f8a3a"))


## A tuft of grass: five or six blades (about 12 triangles). `tall` is the long wispy grass of dunes and verges.
static func _tuft(st: SurfaceTool, tall: bool) -> void:
	var n := 6 if not tall else 7
	for i in n:
		var yaw := TAU * float(i) / float(n) + 0.5 * _h(float(i) * 1.9)
		var length := (0.75 + 0.35 * _h(float(i) * 3.1)) * (1.0 if not tall else 1.7)
		_blade(st, Vector3(0.06 * cos(yaw), 0, 0.06 * sin(yaw)), yaw, length, 0.06 if not tall else 0.05, 0.35 + 0.35 * _h(float(i) * 5.3) + (0.25 if tall else 0.0), Color("#3d5a22"), Color("#9bb04a"))


## What a wood looks like from a long way off: two lumps, or two cones (about 40 triangles).
static func _far_blob(st: SurfaceTool, top: Color, bot: Color) -> void:
	_prism(st, Vector3.ZERO, Vector3(0, 2.6, 0), 0.28, 0.2, 5, BARK_DARK, BARK)
	_blob(st, Vector3(0, 5.6, 0), Vector3(3.0, 3.0, 3.0), 61.0, 4, 8, top, bot, 0.14)


static func _far_cone(st: SurfaceTool) -> void:
	_prism(st, Vector3.ZERO, Vector3(0, 1.6, 0), 0.3, 0.2, 5, BARK_DARK, BARK)
	_tier(st, 1.2, 7.0, 2.7, 0.5, 71.0, 7, Color("#1d3624"), Color("#26452b"), Color("#315a36"))
	_tier(st, 5.0, 11.0, 1.8, 0.0, 73.0, 7, Color("#1f3a26"), Color("#28492d"), Color("#335c38"))


# ---------------------------------------------------------------- where they stand

## `cfg`: period (m of road one pattern covers), behind (how far behind the car the first pattern starts), rail and opp_x (the
## x of the near rail and of the opposite carriageway's centre), median_x, site_clear(pz, x) -> bool (true where a fuel stop
## or a speed check needs the ground bare) and ground(x, pz) -> Vector2 (how high the swell of the ground and the hills stand
## there, before the country's relief).
##
## Returns {"batches": [{"key", "mesh", "thin", "shadow", "range", "items": [[Transform3D, Color], ...]}, ...],
## "blobs": [Transform3D, ...]} (the blobs are the soft contact shadows under the big plants).
static func build(kind: String, cfg: Dictionary) -> Dictionary:
	var ctx := {"cfg": cfg, "rng": RandomNumberGenerator.new(), "by": {}, "blobs": [], "kind": kind, "relief": float(RELIEF.get(kind, 1.0))}
	(ctx.rng as RandomNumberGenerator).seed = 7 + KINDS.find(kind) * 101
	match kind:
		"autumn": _farm(ctx, true)
		"conifer": _forest(ctx)
		"desert": _desert(ctx)
		"coast": _coast(ctx)
		"snow": _snow(ctx)
		_: _farm(ctx, false)
	var out: Array = []
	for key in ctx.by:
		var p: Dictionary = PROPS[key]
		out.append({"key": key, "mesh": mesh(key), "thin": bool(p.get("thin", false)), "shadow": bool(p.shadow), "range": float(p.range), "items": ctx.by[key]})
	return {"batches": out, "blobs": ctx.blobs}


## `n` places in one pattern: right of the road with probability `right_p`, d metres beyond the rail (d0 to d1), not on a
## fuel stop or a speed check's bay. Pattern positions: x, 0, z along the pattern.
static func _spots(ctx: Dictionary, n: int, right_p: float, d0: float, d1: float) -> Array:
	var cfg: Dictionary = ctx.cfg
	var rng: RandomNumberGenerator = ctx.rng
	var out: Array = []
	for i in n:
		var z := rng.randf() * float(cfg.period)
		var right := rng.randf() < right_p
		var d := rng.randf_range(d0, d1)
		var x: float = (float(cfg.rail) + d) if right else (float(cfg.opp_x) - float(cfg.rail) - d)
		if not (cfg.site_clear as Callable).call(z, x):
			out.append(Vector3(x, 0.0, z))
	return out


static func _median(ctx: Dictionary, n: int) -> Array:
	var cfg: Dictionary = ctx.cfg
	var rng: RandomNumberGenerator = ctx.rng
	var out: Array = []
	for i in n:
		out.append(Vector3(float(cfg.median_x) + rng.randf_range(-1.3, 1.3), 0.0, rng.randf() * float(cfg.period)))
	return out


## Plant `key` at each pattern position (once in each of the three repeats of the pattern along the road): a random turn,
## a size from `s0` to `s1` (and `tall` times that high) and a tint of `tint` varied a little.
static func _plant(ctx: Dictionary, key: String, spots: Array, s0: float, s1: float, tint: Color, tall := 1.0, blob := 0.0) -> void:
	var cfg: Dictionary = ctx.cfg
	var rng: RandomNumberGenerator = ctx.rng
	var by: Dictionary = ctx.by
	if not by.has(key):
		by[key] = []
	var list: Array = by[key]
	for p in spots:
		var s := rng.randf_range(s0, s1)
		var yaw := rng.randf() * TAU
		var b := Basis(Vector3.UP, yaw).scaled(Vector3(s, s * tall, s))
		var v := rng.randf_range(0.86, 1.1)
		var tn := Color(clampf(tint.r * v * rng.randf_range(0.94, 1.06), 0.0, 2.0), clampf(tint.g * v, 0.0, 2.0), clampf(tint.b * v * rng.randf_range(0.94, 1.06), 0.0, 2.0))
		var g: Vector2 = (cfg.ground as Callable).call((p as Vector3).x, (p as Vector3).z)  # (the swell of the ground, the hills)
		var y := maxf(g.x * float(ctx.relief), g.y)
		for rep in 3:
			var pos := Vector3((p as Vector3).x, y, -((p as Vector3).z + float(rep) * float(cfg.period)) + float(cfg.behind))
			list.append([Transform3D(b, pos), tn])
			if blob > 0.0:
				(ctx.blobs as Array).append(Transform3D(Basis().scaled(Vector3(blob * s, 1.0, blob * s)), pos + Vector3(0.5 * s, 0.03, 0.25 * s)))


## Plants in a row along the road at one distance: a hedge, a line of poplars, a shelter belt.
static func _row(ctx: Dictionary, key: String, rows: int, length: float, gap: float, d: float, s0: float, s1: float, tint: Color, tall := 1.0, blob := 0.0) -> void:
	var cfg: Dictionary = ctx.cfg
	var rng: RandomNumberGenerator = ctx.rng
	var spots: Array = []
	for r in rows:
		var z0 := rng.randf() * float(cfg.period)
		var right := rng.randf() < 0.55
		var dd := d + rng.randf_range(-3.0, 3.0)
		var x: float = (float(cfg.rail) + dd) if right else (float(cfg.opp_x) - float(cfg.rail) - dd)
		var n := int(length / gap)
		for i in n:
			var z := fposmod(z0 + float(i) * gap + rng.randf_range(-0.5, 0.5), float(cfg.period))
			var xj := x + rng.randf_range(-0.6, 0.6)
			if not (cfg.site_clear as Callable).call(z, xj):  # (the place it will really stand, not the line it is in)
				spots.append(Vector3(xj, 0.0, z))
	_plant(ctx, key, spots, s0, s1, tint, tall, blob)


## What goes everywhere: the grass along the verges and in the median, and the far woods.
static func _verge(ctx: Dictionary, tufts: int, key := "tuft", tint := Color(1, 1, 1)) -> void:
	_plant(ctx, key, _spots(ctx, int(tufts * 0.6), 0.5, 0.8, 13.0), 0.45, 1.0, tint)
	_plant(ctx, key, _median(ctx, int(tufts * 0.2)), 0.45, 0.95, tint)
	_plant(ctx, key, _spots(ctx, int(tufts * 0.2), 0.0, 25.0, 60.0), 0.6, 1.3, tint)


## Farmland (and autumn woods): oaks, rows of poplars, hedges and bushes along the fields, a few spruces.
static func _farm(ctx: Dictionary, autumn: bool) -> void:
	var g1 := Color(1, 1, 1)
	var spots := _spots(ctx, 70 if not autumn else 80, 0.55, 7.0, 80.0)
	if autumn:
		var third := int(spots.size() / 3.0)
		_plant(ctx, "oakA0", spots.slice(0, third), 0.8, 1.45, g1, 1.0, 3.6)
		_plant(ctx, "oakA1", spots.slice(third, third * 2), 0.8, 1.45, g1, 1.0, 3.6)
		_plant(ctx, "oakA2", spots.slice(third * 2), 0.8, 1.45, g1, 1.0, 3.6)
		_plant(ctx, "spruce0", _spots(ctx, 26, 0.5, 8.0, 80.0), 0.7, 1.2, g1, 1.0, 2.4)
		_row(ctx, "poplarA", 3, 60.0, 8.0, 44.0, 0.9, 1.3, g1, 1.0, 1.6)
	else:
		var half := int(spots.size() * 0.5)
		_plant(ctx, "oak0", spots.slice(0, half), 0.8, 1.45, g1, 1.0, 3.6)
		_plant(ctx, "oak1", spots.slice(half), 0.8, 1.45, g1, 1.0, 3.6)
		_plant(ctx, "spruce1", _spots(ctx, 12, 0.5, 10.0, 80.0), 0.6, 1.1, g1, 1.0, 2.2)
		_row(ctx, "poplar", 4, 70.0, 7.5, 40.0, 0.9, 1.35, g1, 1.0, 1.6)
	var bush_key := "bush0" if not autumn else "bushA"
	var hedge_key := "bush1" if not autumn else "bushA"
	_plant(ctx, bush_key, _spots(ctx, 60, 0.5, 2.0, 9.0), 0.5, 1.0, g1)
	_plant(ctx, hedge_key, _median(ctx, 30), 0.5, 0.9, g1)
	_row(ctx, hedge_key, 6, 50.0, 2.6, 14.0, 0.7, 1.2, g1)  # hedges along the field edges
	_verge(ctx, 1500, "tuft", g1 if not autumn else Color(1.4, 1.0, 0.8))
	_plant(ctx, "far_blob" if not autumn else "far_blobA", _spots(ctx, 260, 0.5, 80.0, 170.0), 0.9, 1.5, g1, 1.0)


## Northern pines: a wall of spruce close to the road, ferns and undergrowth beneath.
static func _forest(ctx: Dictionary) -> void:
	var spots := _spots(ctx, 190, 0.55, 6.0, 85.0)
	var half := int(spots.size() * 0.5)
	_plant(ctx, "spruce0", spots.slice(0, half), 0.65, 1.3, Color(1, 1, 1), 1.0, 2.8)
	_plant(ctx, "spruce1", spots.slice(half), 0.65, 1.3, Color(0.95, 1.0, 1.05), 1.1, 2.8)
	_plant(ctx, "spruce1", _spots(ctx, 60, 0.6, 4.5, 24.0), 0.55, 1.0, Color(0.92, 1.0, 1.04), 1.0, 2.6)  # (a closer wall along the road)
	_plant(ctx, "oak1", _spots(ctx, 10, 0.5, 8.0, 60.0), 0.7, 1.1, Color(0.85, 1.0, 0.85), 1.0, 3.0)
	_plant(ctx, "fern", _spots(ctx, 230, 0.5, 2.5, 26.0), 0.8, 1.6, Color(1, 1, 1))
	_plant(ctx, "fern", _median(ctx, 40), 0.8, 1.3, Color(1, 1, 1))
	_plant(ctx, "bush0", _spots(ctx, 50, 0.5, 3.0, 14.0), 0.5, 0.95, Color(0.65, 0.85, 0.7))
	_verge(ctx, 700, "tuft", Color(0.8, 0.95, 0.75))
	_plant(ctx, "far_cone", _spots(ctx, 380, 0.5, 80.0, 175.0), 0.9, 1.5, Color(1, 1, 1), 1.0)


## Desert: saguaros, barrel cacti, prickly pears, agaves, sagebrush and dry grass, and plenty of bare ground.
static func _desert(ctx: Dictionary) -> void:
	var sp := _spots(ctx, 36, 0.5, 7.0, 95.0)
	var half := int(sp.size() * 0.5)
	_plant(ctx, "saguaro0", sp.slice(0, half), 1.0, 1.7, Color(1, 1, 1), 1.0, 1.4)
	_plant(ctx, "saguaro1", sp.slice(half), 1.0, 1.6, Color(1, 1, 1), 1.0, 1.2)
	_plant(ctx, "barrel", _spots(ctx, 44, 0.5, 4.0, 60.0), 0.7, 1.4, Color(1, 1, 1))
	_plant(ctx, "pear", _spots(ctx, 36, 0.5, 5.0, 70.0), 0.8, 1.5, Color(1, 1, 1))
	_plant(ctx, "agave", _spots(ctx, 60, 0.5, 3.0, 50.0), 0.8, 1.6, Color(1, 1, 1))
	_plant(ctx, "scrub", _spots(ctx, 150, 0.5, 3.0, 75.0), 0.7, 1.6, Color(1, 1, 1))
	_plant(ctx, "scrub", _median(ctx, 30), 0.6, 1.1, Color(1, 1, 1))
	_plant(ctx, "bare0", _spots(ctx, 6, 0.5, 15.0, 80.0), 0.8, 1.2, Color(1.45, 1.35, 1.2), 0.9, 1.0)  # a dead tree, grey and dry
	_verge(ctx, 1300, "tuft", Color(1.45, 1.0, 1.15))


## The coast: palms, dune grass, low scrub.
static func _coast(ctx: Dictionary) -> void:
	var sp := _spots(ctx, 48, 0.5, 9.0, 70.0)
	var half := int(sp.size() * 0.5)
	_plant(ctx, "palm0", sp.slice(0, half), 0.85, 1.3, Color(1, 1, 1), 1.0, 2.6)
	_plant(ctx, "palm1", sp.slice(half), 0.85, 1.3, Color(1, 1, 1), 1.0, 2.6)
	_plant(ctx, "tall", _spots(ctx, 900, 0.5, 1.0, 40.0), 0.6, 1.2, Color(1.25, 1.05, 1.3))
	_plant(ctx, "tall", _median(ctx, 80), 0.6, 1.1, Color(1.25, 1.05, 1.3))
	_plant(ctx, "bush0", _spots(ctx, 100, 0.5, 3.0, 30.0), 0.4, 0.9, Color(0.95, 1.1, 0.85))
	_plant(ctx, "bush1", _median(ctx, 30), 0.4, 0.8, Color(0.95, 1.1, 0.85))
	_verge(ctx, 500, "tuft", Color(1.2, 1.05, 1.25))
	_plant(ctx, "far_blob", _spots(ctx, 70, 1.0, 90.0, 170.0), 0.8, 1.3, Color(0.95, 1.1, 0.8))  # (the left is the sea: nothing stands out there)


## Frosted plains: spruces under snow, bare trees, drifts and clumps of dead grass.
static func _snow(ctx: Dictionary) -> void:
	var sp := _spots(ctx, 95, 0.55, 7.0, 85.0)
	var half := int(sp.size() * 0.5)
	_plant(ctx, "snowspruce0", sp.slice(0, half), 0.7, 1.3, Color(1, 1, 1), 1.0, 2.6)
	_plant(ctx, "snowspruce1", sp.slice(half), 0.7, 1.25, Color(1, 1, 1), 1.05, 2.6)
	var bt := _spots(ctx, 46, 0.5, 8.0, 85.0)
	_plant(ctx, "bare0", bt.slice(0, int(bt.size() * 0.5)), 0.8, 1.3, Color(1, 1, 1), 1.0, 1.6)
	_plant(ctx, "bare1", bt.slice(int(bt.size() * 0.5)), 0.8, 1.3, Color(1, 1, 1), 1.0, 1.6)
	_plant(ctx, "bush0", _spots(ctx, 70, 0.5, 2.5, 14.0), 0.45, 0.9, Color(3.0, 2.1, 5.0))  # (a bush under snow: a white mound)
	_plant(ctx, "bush1", _median(ctx, 26), 0.4, 0.8, Color(3.0, 2.1, 5.0))
	_verge(ctx, 800, "tuft", Color(1.15, 0.87, 1.3))
	_plant(ctx, "far_cone", _spots(ctx, 340, 0.5, 80.0, 175.0), 0.9, 1.5, Color(1.0, 1.15, 1.2), 1.0)
