class_name BodyBuilder
extends RefCounted
## Smooth one-piece car body for every car with a greenhouse.
##
## A cross-section is swept from the rear bumper (d = 0) to the nose (d = l):
## underbody, rocker, a slightly bulging side, a rounded shoulder, then either
## the bonnet or boot top, or the greenhouse: side glass leaning inwards, the
## window trim and a crowned roof. The windshield and rear glass appear where
## the roof height ramps between the shoulder and the roof line. Wheel arches
## are cut by lifting the outer bottom of the section over each wheel, and the
## sides swell a little over the wheels. Each quad goes to a surface (paint,
## glass, gloss trim, underbody...) by where it is, and each vertex carries a
## baked ambient-occlusion shade in its colour (darker low down and round the
## arches), which the paint multiplies in.
##
## Coordinates match CarModel: x right, y up, z = -d, origin at the centre of
## the rear bumper on the ground.

const N := 19  # points in the right half of a section, bottom centre (0) to top centre (18)
const LED_UV := Vector2(0.55, 0.17)  # a spot on the tail-light texture's top LED bar

var id: String
var pr: Dictionary
var style: Dictionary
var w: float
var l: float
var g: Array  # greenhouse: [base rear d, base front d, roof rear d, roof front d, base y, roof y, base w, roof w]
var r: float  # wheel radius
var axles: Array
var R: float  # wheel-arch radius
var floor_y: float
var stations: Array  # smoothed [d, shoulder height, width scale]
var pillars: Array = []  # [d0, d1, surface]
var rc_r: float   # plan-view corner radius at the tail
var rc_f: float   # and at the nose
var flare_ra: Array  # how far the body swells out over the [rear, front] wheels (fraction of the half width)
var fender_ra: Array # wing tops rising above the bonnet over the [rear, front] wheels (low cars)
var crease: float # height of the shoulder crease, as a fraction of the side
var tumble: float # how far the side leans in above the crease
var sharp: bool   # crisp shoulder crease (separate shading above and below)


var lq := false  # the light version drawn for cars further than CarModel.LOD_NEAR away


func _init(p_id: String, p_pr: Dictionary, shape: Dictionary, p_style: Dictionary, p_lq := false) -> void:
	lq = p_lq
	id = p_id
	pr = p_pr
	style = p_style
	w = shape.w
	l = shape.l
	g = pr.gh
	r = pr.wheel[0]
	axles = [float(pr.wheel[1]), float(pr.wheel[2])]
	R = r + 0.055
	floor_y = 0.28 if float(g[5]) > 1.6 else (0.17 if float(g[5]) < 1.2 else 0.2)
	stations = CarModel._smooth(pr.body)
	var cr: Array = pr.get("corner", [0.2, 0.26])
	rc_r = cr[0]
	rc_f = cr[1]
	flare_ra = _pair(pr.get("flare", 0.03))
	fender_ra = _pair(pr.get("fender", 0.0))
	crease = pr.get("crease_h", 0.7)
	tumble = pr.get("tumble", 0.06)
	sharp = pr.get("sharp", true)
	var ps: Array = pr.pillars
	for i in ps.size():
		# rear pillar in body colour, the others gloss black like most modern cars
		pillars.append([lerpf(g[0], g[1], ps[i][0]), lerpf(g[0], g[1], ps[i][1]), "paint" if i == 0 else "gloss"])


# ---------------------------------------------------------------- shape

func top(d: float) -> float:
	return CarModel._station_at(stations, d, 1)


## How far a rounded corner of radius rc pulls the outline in, at distance e from the end.
static func _corner_pull(e: float, rc: float) -> float:
	if e >= rc or rc <= 0.0:
		return 0.0
	var u := rc - e
	return rc - sqrt(maxf(rc * rc - u * u, 0.0))


static func _pair(v: Variant) -> Array:
	return [float(v[0]), float(v[1])] if v is Array else [float(v), float(v)]


## 0..1: how close d is to a wheel centre (for the arch flares and wing peaks).
func wheel_bulge(d: float) -> float:
	var b := 0.0
	for a in axles:
		b = maxf(b, exp(-pow((d - a) / 0.62, 2.0)))
	return b


## The flare (k = 0) or wing peak (k = 1) at d, blended between the axles.
func _axle_amount(d: float, k: int) -> float:
	var v: Array = flare_ra if k == 0 else fender_ra
	var br := exp(-pow((d - float(axles[0])) / 0.62, 2.0))
	var bf := exp(-pow((d - float(axles[1])) / 0.62, 2.0))
	return float(v[0]) * br + float(v[1]) * bf


## Half width of the body at d: profile width, flared out over each wheel,
## with the corners rounded off in plan view at both ends.
func hw(d: float) -> float:
	var base := w / 2.0 * CarModel._station_at(stations, d, 2)
	var pull := _corner_pull(d, rc_r) + _corner_pull(l - d, rc_f)
	return (base - pull) * (1.0 + _axle_amount(d, 0))


## Height of the bottom of the side at d: the floor, or the arch edge over a wheel.
func arch_y(d: float) -> float:
	var y := floor_y
	for a in axles:
		var dd := absf(d - a)
		if dd < R:
			y = maxf(y, r + sqrt(R * R - dd * dd))
	return y


## Straight glass that rounds into the roof over the last k of its length.
static func _ease(s: float, k: float) -> float:
	s = clampf(s, 0.0, 1.0)
	var m := 1.0 / (1.0 - k / 2.0)
	if s <= 1.0 - k:
		return m * s
	var u := s - (1.0 - k)
	return m * (1.0 - k) + m * (u - u * u / (2.0 * k))


## Roof line along the car: the shoulder outside the cabin, rising up the rear
## glass, a slightly crowned roof, and down the windshield.
func roof_y(d: float) -> float:
	var t := top(d)
	if d <= g[0] or d >= g[1]:
		return t
	if d < g[2]:
		return t + (_roof_line(g[2]) - t) * _ease((d - g[0]) / maxf(g[2] - g[0], 0.01), 0.4)
	if d > g[3]:
		return t + (float(g[5]) - t) * _ease((g[1] - d) / maxf(g[1] - g[3], 0.01), 0.3)
	return _roof_line(d) + 0.012 * sin(PI * (d - g[2]) / maxf(g[3] - g[2], 0.01))


## How far back from the windscreen base the glass reaches height h (the
## largest d inside the cabin where the windscreen or roof is at least h).
func glass_d(h: float) -> float:
	var d: float = g[1]
	while d > float(g[0]) and roof_y(d) < h:
		d -= 0.01
	return d


## The roof falls away towards the back (profile "roof_drop"), peaking over
## the front seats, instead of running flat to the rear glass.
func _roof_line(d: float) -> float:
	var drop: float = pr.get("roof_drop", 0.0)
	return float(g[5]) - drop * (1.0 - smoothstep(float(g[2]), lerpf(g[2], g[3], 0.7), d))


## Raised bonnet centre: a power dome or a scoop (style), as part of the panel.
func hood_lift(d: float, x: float) -> float:
	var d0: float = g[1] + 0.1
	var d1: float = l - 0.38
	if d <= d0 or d >= d1:
		return 0.0
	var along := smoothstep(d0, d0 + 0.25, d) * (1.0 - smoothstep(d1 - 0.18, d1, d))
	if style.get("scoop", false):
		# a raised scoop with a flat top, rising towards its open front
		var across := 1.0 - smoothstep(0.24, 0.34, absf(x))
		var rise := lerpf(0.035, 0.07, smoothstep(d0, d1, d))
		return rise * along * across * (1.0 - smoothstep(d1 - 0.36, d1 - 0.3, d))
	if style.get("dome", false):
		return 0.026 * along * (1.0 - smoothstep(0.1, 0.3, absf(x)))
	return 0.0


## Right half of the cross-section at d, from the bottom centre to the top centre.
func section(d: float) -> PackedVector2Array:
	var t := top(d)
	var hwd := hw(d)
	var yb := arch_y(d)
	var fb := _axle_amount(d, 1)  # wing peak over the wheel
	var ts := t + fb                   # top of the side (the wing line)
	var Hf := maxf(ts - floor_y, 0.08)
	var p := PackedVector2Array()
	p.resize(N)
	p[0] = Vector2(0.0, floor_y)
	p[1] = Vector2(hwd * 0.6, floor_y)
	p[2] = Vector2(hwd * 0.62, yb)  # inner wheel-well wall where lifted
	p[3] = Vector2(hwd * 0.82, yb)
	# side heights measured from the floor, so the crease runs level along the
	# car; over a wheel the lower points bunch up at the arch edge
	var hs: Array = [0.035, 0.12, 0.42, crease, crease + (1.0 - crease) * 0.55]
	var xs: Array = [0.93, 0.975, 1.0, 0.996, 0.996 - tumble * 0.5]
	var lo := yb
	for k in 5:
		var y := maxf(floor_y + Hf * float(hs[k]), lo + 0.004)
		y = minf(y, ts - 0.02 + 0.003 * k)
		lo = y
		p[4 + k] = Vector2(hwd * float(xs[k]), y)
	p[9] = Vector2(hwd * (0.996 - tumble * 0.85), maxf(ts - 0.014, p[8].y + 0.002))
	p[10] = Vector2(hwd * (0.996 - tumble), maxf(ts, p[9].y + 0.002))
	var e0 := 0.996 - tumble
	var flat := [Vector2(hwd * (e0 - 0.015), ts + 0.006), Vector2(hwd * (e0 - 0.035), ts + 0.009 - fb * 0.1), Vector2(hwd * (e0 - 0.055), t + 0.012 + fb * 0.75),
		Vector2(hwd * (e0 - 0.08), t + 0.015 + fb * 0.45), Vector2(hwd * 0.78, t + 0.02 + fb * 0.12), Vector2(hwd * 0.6, t + 0.024),
		Vector2(hwd * 0.32, t + 0.027), Vector2(0.0, t + 0.028)]
	if d > float(g[1]) + 0.1:
		for k in 8:
			var q: Vector2 = flat[k]
			flat[k] = Vector2(q.x, q.y + hood_lift(d, q.x))
	var roof := roof_y(d)
	var gh_h := roof - t
	if gh_h <= 0.0005:
		for k in 8:
			p[11 + k] = flat[k]
		return p
	var full := maxf(float(g[5]) - t, 0.05)
	var hk := clampf(gh_h / full, 0.0, 1.0)
	# vans: the cargo box carries the side straight up to the roof, no step at the belt
	var gw_base := minf(w / 2.0 * float(g[6]), hwd * (0.99 - tumble if pr.get("slab", false) else 0.915))
	var gw_roof := w / 2.0 * float(g[7])
	var xs_top := lerpf(gw_base, minf(gw_roof * 1.03, gw_base), hk)
	var drop := clampf(gh_h * 0.22, 0.0, 0.055)
	var y0 := t + 0.012
	var ytop := maxf(roof - drop, y0 + 0.002)
	var hk2 := clampf(gh_h / 0.2, 0.0, 1.0)
	var cab: Array = [
		Vector2(gw_base, y0),
		Vector2(lerpf(gw_base, xs_top, 0.33), lerpf(y0, ytop, 0.33)),
		Vector2(lerpf(gw_base, xs_top, 0.66), lerpf(y0, ytop, 0.66)),
		Vector2(xs_top, ytop),
		Vector2(xs_top - 0.022 * hk2, ytop + drop * 0.55),
		Vector2(xs_top - 0.075 * hk2, roof - drop * 0.08),
		Vector2((xs_top - 0.075 * hk2) * 0.55, roof + 0.02),
		Vector2(0.0, roof + 0.026),
	]
	var bl := smoothstep(0.0, 0.05, gh_h)
	for k in 8:
		p[11 + k] = (flat[k] as Vector2).lerp(cab[k], bl)
	return p


## Point and outward normal on the right side of the body at height y.
func side_pn(d: float, y: float) -> Array:
	var p := section(d)
	var j := 9
	for k in range(4, 10):
		if y <= p[k + 1].y:
			j = k
			break
	var a: Vector2 = p[j]
	var b: Vector2 = p[j + 1]
	var f := clampf((y - a.y) / maxf(b.y - a.y, 0.0001), 0.0, 1.0)
	var q := a.lerp(b, f)
	var dir := (b - a).normalized()
	return [Vector3(q.x, q.y, -d), Vector3(dir.y, -dir.x, 0.0).normalized()]


## Height of the top surface (bonnet, boot, glass or roof) at lateral offset x.
func surf_y(d: float, x: float) -> float:
	var p := section(d)
	x = absf(x)
	for j in range(10, N - 1):
		var a: Vector2 = p[j]
		var b: Vector2 = p[j + 1]
		if x <= a.x and x >= b.x:
			return lerpf(a.y, b.y, (a.x - x) / maxf(a.x - b.x, 0.0001))
	return p[10].y if x > p[10].x else p[N - 1].y


# ---------------------------------------------------------------- body

func _sample() -> PackedFloat32Array:
	var ds: Array = []
	var n := int(ceil(l / (0.16 if lq else 0.075)))
	for i in n + 1:
		ds.append(l * i / n)
	var na := 7 if lq else 13
	for a in axles:
		for k in na:
			ds.append(a + R * (-1.0 + k / ((na - 1) / 2.0)) * 0.999)  # dense round each arch
		ds.append(a - R * 1.002)
		ds.append(a + R * 1.002)
	var nc := 7 if lq else 16
	for k in nc:  # the rounded corners need close sections to look round
		var th := PI / 2.0 * k / (nc - 1.0)
		ds.append(rc_r * (1.0 - cos(th)))
		ds.append(l - rc_f * (1.0 - cos(th)))
	for v in [g[0], g[1], g[2], g[3], g[1] + 0.09]:
		ds.append(float(v))
	for p in pillars:
		ds.append(p[0])
		ds.append(p[1])
	if pr.has("kink"):
		ds.append(lerpf(g[0], g[1], pr.kink[1]))
	ds.sort()
	var out := PackedFloat32Array()
	for d in ds:
		var dc := clampf(d, 0.0, l)
		if out.is_empty() or dc - out[out.size() - 1] > 0.004:
			out.append(dc)
	return out


## Which surface a quad of section segment `seg` at distance d belongs to.
func _kind(seg: int, d: float) -> String:
	if seg <= 3:
		return "under"
	if seg <= 9:
		return "paint"
	var cab: bool = d > g[0] + 0.0005 and d < g[1] - 0.0005
	if not cab:
		if seg >= 12 and d > g[1] and d < g[1] + 0.09:
			return "dark"  # cowl panel at the foot of the windshield
		return "paint"
	var slab: bool = pr.get("slab", false)
	if seg == 10:
		if slab and d < pillars[1][0]:
			return "paint"  # cargo box: no windows, so no seal
		return "gloss"  # window seal along the belt line
	if seg <= 13:
		var row := seg - 11
		for i in pillars.size():
			var pl: Array = pillars[i]
			var d1: float = pl[1]
			if i == 0 and pr.has("kink") and row == 0:
				d1 = lerpf(g[0], g[1], pr.kink[1])  # pillar kinks forward at its foot
			if d >= pl[0] - 0.0005 and d <= d1 + 0.0005:
				return pl[2]
		return "glass"
	var ws: bool = d > g[3]
	var rs: bool = d < g[2]
	if seg == 14:
		if slab:
			return "paint"
		return "paint" if (ws or rs) else "gloss"  # A/C pillar edge, or the trim above the side windows
	if seg == 15:
		return "paint"
	if rs and slab:
		return "paint"  # rear doors are panels (their windows are added as details)
	return "glass" if (ws or rs) else "paint"


func _ao(p: Vector2, d: float, under: bool) -> Color:
	if under:
		return Color(0.3, 0.3, 0.3)
	var a := lerpf(0.55, 1.0, smoothstep(floor_y + 0.02, floor_y + 0.45, p.y))
	for ax in axles:
		var dist := Vector2(d - ax, p.y - r).length()
		a *= lerpf(0.55, 1.0, smoothstep(R, R + 0.18, dist))
	if p.y > top(d) - 0.02:
		a = maxf(a, 0.96)
	return Color(a, a, a)


static func _tri3(st: SurfaceTool, v: Array, n: Array, c: Array, uv: Array = []) -> void:
	var order := [0, 1, 2]
	var e1: Vector3 = v[1] - v[0]
	var e2: Vector3 = v[2] - v[0]
	if e1.cross(e2).dot(n[0] + n[1] + n[2]) > 0.0:
		order = [0, 2, 1]
	for k in order:
		if not c.is_empty():
			st.set_color(c[k])
		if not uv.is_empty():
			st.set_uv(uv[k])
		st.set_normal(n[k])
		st.add_vertex(v[k])


static func _quad4(st: SurfaceTool, v: Array, n: Array, c: Array, uv: Array = []) -> void:
	_tri3(st, [v[0], v[1], v[2]], [n[0], n[1], n[2]], [c[0], c[1], c[2]] if not c.is_empty() else [],
		[uv[0], uv[1], uv[2]] if not uv.is_empty() else [])
	_tri3(st, [v[0], v[2], v[3]], [n[0], n[2], n[3]], [c[0], c[2], c[3]] if not c.is_empty() else [],
		[uv[0], uv[2], uv[3]] if not uv.is_empty() else [])


## Sweeps the body into the surfaces in S.
func emit(S: Dictionary) -> void:
	var ds := _sample()
	var ns := ds.size()
	var P: Array = []
	for d in ds:
		P.append(section(d))
	# smooth normals inside two groups (side, top), so the shoulder keeps a crease
	var groups := [[4, 7], [7, 10], [10, 18]] if sharp else [[4, 10], [4, 10], [10, 18]]
	var NR: Array = []
	for gr in groups:
		var j0: int = gr[0]
		var j1: int = gr[1]
		var rows: Array = []
		for i in ns:
			var row := PackedVector3Array()
			row.resize(N)
			var im := maxi(i - 1, 0)
			var ip := mini(i + 1, ns - 1)
			for j in range(j0, j1 + 1):
				var pa: Vector2 = P[i][maxi(j - 1, j0)]
				var pb: Vector2 = P[i][mini(j + 1, j1)]
				var ts := Vector3(pb.x - pa.x, pb.y - pa.y, 0.0)
				var q0: Vector2 = P[im][j]
				var q1: Vector2 = P[ip][j]
				var td := Vector3(q1.x - q0.x, q1.y - q0.y, -(ds[ip] - ds[im]))
				var n := ts.cross(td)
				var pt: Vector2 = P[i][j]
				var hint := Vector3(pt.x, pt.y - (floor_y + top(ds[i])) * 0.5, 0.0)
				if n.length() < 0.000001:
					n = hint
				n = n.normalized()
				if n.dot(hint) < 0.0:
					n = -n
				row[j] = n
			rows.append(row)
		NR.append(rows)
	for i in ns - 1:
		var dm := (ds[i] + ds[i + 1]) * 0.5
		for seg in N - 1:
			var kind := _kind(seg, dm)
			var st: SurfaceTool = S[kind]
			var under := seg <= 3
			var gi := 0 if seg < 7 else (1 if seg < 10 else 2)
			var idx := [[i, seg], [i, seg + 1], [i + 1, seg + 1], [i + 1, seg]]
			for side in [1.0, -1.0]:
				var v: Array = []
				var nn: Array = []
				var cc: Array = []
				for k in 4:
					var ii: int = idx[k][0]
					var jj: int = idx[k][1]
					var p2: Vector2 = P[ii][jj]
					v.append(Vector3(p2.x * side, p2.y, -ds[ii]))
					var n: Vector3
					if under:
						n = Vector3(side, 0, 0) if seg == 1 else Vector3(0, -1, 0)
					else:
						n = NR[gi][ii][jj]
						n.x *= side
					nn.append(n)
					cc.append(_ao(p2, ds[ii], under))
				_quad4(st, v, nn, cc)
	# rear face and nose
	for e in [0, ns - 1]:
		var sec: PackedVector2Array = P[e]
		var z := -ds[e]
		var n := Vector3(0, 0, 1) if e == 0 else Vector3(0, 0, -1)
		var ctr := Vector3(0, (floor_y + top(ds[e])) * 0.5, z)
		var cc := _ao(Vector2(0, ctr.y), ds[e], false)
		for side in [1.0, -1.0]:
			for j in N - 1:
				var a := Vector3(sec[j].x * side, sec[j].y, z)
				var b := Vector3(sec[j + 1].x * side, sec[j + 1].y, z)
				_tri3(S.paint, [ctr, a, b], [n, n, n], [cc, _ao(sec[j], ds[e], false), _ao(sec[j + 1], ds[e], false)])
	for k in S:
		(S[k] as SurfaceTool).set_color(Color.WHITE)  # later boxes are unshaded


# ---------------------------------------------------------------- details

## Mirrors, wipers, third brake light, antenna, door shut lines, handles,
## fuel filler and roof stripes.
func details(S: Dictionary, tails: SurfaceTool, sig_l: SurfaceTool, sig_r: SurfaceTool) -> void:
	# wing mirrors on the black sail at the front of the side glass
	var dmr := lerpf(g[0], g[1], 0.962)
	var tm := top(dmr)
	var gwb := minf(w / 2.0 * float(g[6]), hw(dmr) * (0.99 - tumble if pr.get("slab", false) else 0.915))
	for s in ([] if pr.get("slab", false) else [-1.0, 1.0]):
		# rounded housing on a short arm, mirror glass facing back, indicator
		# strip along its leading edge
		var hc := Vector3(s * (gwb + 0.17), tm + 0.115, -dmr + 0.02)
		CarModel._box(S.gloss, Vector3(s * (gwb + 0.05), tm + 0.05, -dmr + 0.03), Vector3(0.1, 0.045, 0.12))
		CarModel._strap(S.gloss, Vector3(s * (gwb + 0.06), tm + 0.06, -dmr + 0.03), hc + Vector3(-s * 0.05, -0.03, 0.0), 0.04, 0.03)
		CarModel._ellipsoid(S.paint, hc, Vector3(0.115, 0.064, 0.06), Basis(), 8 if lq else 16, 4 if lq else 8, 0.0, PI)
		if not lq:
			CarModel._ellipsoid(S.gloss, hc + Vector3(0, 0, 0.012), Vector3(0.1, 0.052, 0.05), Basis(Vector3.RIGHT, -PI / 2.0), 16, 4, 0.0, PI / 2.0)
		CarModel._quad(S.chrome, hc + Vector3(-0.088, -0.042, 0.052), hc + Vector3(0.088, -0.042, 0.052),
			hc + Vector3(0.088, 0.042, 0.052), hc + Vector3(-0.088, 0.042, 0.052), Vector3.BACK)
		CarModel._strap(sig_l if s < 0 else sig_r, hc + Vector3(s * 0.02, -0.046, -0.045), hc + Vector3(s * 0.105, -0.022, -0.012), 0.012, 0.012)
	if lq:
		return  # far away: wipers, shut lines and handles are smaller than a pixel
	# windscreen wipers parked at the foot of the glass
	for k in 2:
		var x0 := -0.1 if k == 0 else 0.42
		var x1 := -0.66 if k == 0 else -0.05
		var da: float = g[1] - 0.07
		var db: float = g[1] - 0.13
		var a := Vector3(x0, surf_y(da, x0) + 0.014, -da)
		var b := Vector3(x1, surf_y(db, x1) + 0.014, -db)
		CarModel._strap(S.dark, a, b, 0.018, 0.012)
		CarModel._cyl(S.dark, a, 0.02, 0.025, Vector3.UP, 8)
	# third brake light on the rear edge of the roof, shark-fin antenna
	var d3: float = g[2] + 0.02
	CarModel._box(tails, Vector3(0, roof_y(d3) + 0.04, -d3), Vector3(0.34, 0.025, 0.05))
	var da2: float = g[2] + 0.2
	CarModel._box(S.gloss, Vector3(0, roof_y(da2) + 0.055, -da2), Vector3(0.07, 0.06, 0.18))
	if pr.get("slab", false):
		_van_details(S)
		return
	# door shut lines, the door bottoms and handles
	var four_door: bool = g[1] - g[0] > 2.4 and not ["muscle", "fastback", "super", "rcoupe", "hyper"].has(id)
	var lines: Array = [axles[1] - R - 0.05, lerpf(axles[0], axles[1], 0.52)]
	if four_door:
		lines.append(axles[0] + R + 0.05)
	var y_lo := floor_y + 0.07
	for s in [-1.0, 1.0]:
		for dz in lines:
			var y_hi := top(dz) - 0.025
			for k in 7:
				var pa: Array = side_pn(dz, lerpf(y_lo, y_hi, k / 7.0))
				var pb: Array = side_pn(dz, lerpf(y_lo, y_hi, (k + 1) / 7.0))
				_line(S.dark, pa, pb, Vector3(0, 0, 0.0035), s)
		var d_front: float = lines[0]
		var d_back: float = lines[lines.size() - 1]
		for k in 10:
			var pa: Array = side_pn(lerpf(d_back, d_front, k / 10.0), y_lo)
			var pb: Array = side_pn(lerpf(d_back, d_front, (k + 1) / 10.0), y_lo)
			_line(S.dark, pa, pb, Vector3(0, 0.0035, 0), s)
		var handles: Array = [lines[1] + 0.2]
		if four_door:
			handles.append(lines[2] + 0.2)
		for hd in handles:
			var hp: Array = side_pn(hd, top(hd) - 0.11)
			var pos: Vector3 = hp[0] + hp[1] * 0.012
			CarModel._box(S.chrome, Vector3(pos.x * s, pos.y, pos.z), Vector3(0.025, 0.032, 0.17))
	# fuel filler on the right rear quarter
	var fd: float = axles[0] + R + 0.2
	var fp: Array = side_pn(fd, top(fd) - 0.16)
	CarModel._box(S.dark, fp[0] + fp[1] * 0.002, Vector3(0.01, 0.15, 0.15))
	CarModel._box(S.paint, fp[0] + fp[1] * 0.006, Vector3(0.01, 0.135, 0.135))
	# mid-engined cars: louvres over the engine on the rear deck
	if pr.get("grille", "frame") == "none" and float(g[0]) > 1.2:
		var n_l := 7
		for k in n_l:
			var dl := lerpf(0.42, float(g[0]) - 0.16, float(k) / (n_l - 1))
			var xl := hw(dl) * 0.42
			var ya := surf_y(dl, 0.0) + 0.004
			CarModel._box(S.gloss, Vector3(0, ya + 0.008, -dl), Vector3(xl * 2.0, 0.018, 0.05), Basis(Vector3.RIGHT, -0.35))
			CarModel._box(S.dark, Vector3(0, ya + 0.001, -dl - 0.012), Vector3(xl * 2.0 - 0.02, 0.006, 0.03))
	# racing stripes over the roof (the bonnet and boot ones come with the style extras)
	if style.get("stripes", false):
		for k in 8:
			var a2 := lerpf(g[2], g[3], k / 8.0)
			var b2 := lerpf(g[2], g[3], (k + 1) / 8.0)
			for sx in [-1.0, 1.0]:
				CarModel._quad(S.accent, Vector3(sx * 0.07, roof_y(a2) + 0.03, -a2), Vector3(sx * 0.27, roof_y(a2) + 0.03, -a2),
					Vector3(sx * 0.27, roof_y(b2) + 0.03, -b2), Vector3(sx * 0.07, roof_y(b2) + 0.03, -b2), Vector3.UP)


## Panel van: cab doors, a sliding side door on the kerb side, a rubbing strip
## along the flanks, and twin rear doors with windows, handle and hinges.
func _van_details(S: Dictionary) -> void:
	var y_lo := floor_y + 0.07
	var d_b: float = pillars[1][0] + 0.02        # cab door rear edge, at the B-pillar
	var d_a: float = axles[1] + R + 0.04          # cab door front edge, behind the front wheel
	var slide1 := d_b - 0.03                      # sliding door, front edge
	var slide0 := slide1 - 1.25                   # and rear edge
	var y_top := roof_y(2.0) - 0.12
	for s in [-1.0, 1.0]:
		var verts: Array = [d_b, d_a]
		if s > 0.0:
			verts.append_array([slide1, slide0])
		for dz in verts:
			# cab door edges stop under the glass; the sliding door runs almost to the roof
			var top_y: float = y_top if dz < d_b - 0.01 else top(dz) - 0.025
			for k in 9:
				_line(S.dark, wall_pn(dz, lerpf(y_lo, top_y, k / 9.0)), wall_pn(dz, lerpf(y_lo, top_y, (k + 1) / 9.0)), Vector3(0, 0, 0.0035), s)
		var runs: Array = [[d_b, d_a, y_lo]]
		if s > 0.0:
			runs.append([slide0, slide1, y_lo])
			runs.append([slide0, slide1, y_top])
			runs.append([slide0 - 0.25, slide0 + 0.05, lerpf(y_lo, y_top, 0.62)])  # the slide rail
		for rr in runs:
			for k in 8:
				_line(S.dark, wall_pn(lerpf(rr[0], rr[1], k / 8.0), rr[2]), wall_pn(lerpf(rr[0], rr[1], (k + 1) / 8.0), rr[2]), Vector3(0, 0.0035, 0), s)
		# black rubbing strip along the lower flank, broken by the wheel arches
		var ys := floor_y + 0.36
		for span in [[0.12, axles[0] - R - 0.03], [axles[0] + R + 0.03, axles[1] - R - 0.03]]:
			var n := 12
			for k in n:
				var pa: Array = wall_pn(lerpf(span[0], span[1], float(k) / n), ys)
				var pb: Array = wall_pn(lerpf(span[0], span[1], float(k + 1) / n), ys)
				var a: Vector3 = pa[0] + pa[1] * 0.012
				var b: Vector3 = pb[0] + pb[1] * 0.012
				a.x *= s
				b.x *= s
				CarModel._box(S.dark, (a + b) * 0.5, Vector3(0.024, 0.075, absf(b.z - a.z) + 0.002))
		# door handles
		var hp: Array = wall_pn(d_b + 0.18, top(d_b) - 0.12)
		var hpos: Vector3 = hp[0] + hp[1] * 0.012
		CarModel._box(S.dark, Vector3(hpos.x * s, hpos.y, hpos.z), Vector3(0.025, 0.035, 0.18))
		if s > 0.0:
			var sp: Array = wall_pn(slide1 - 0.18, top(slide1) - 0.12)
			var spos: Vector3 = sp[0] + sp[1] * 0.012
			CarModel._box(S.dark, spos, Vector3(0.025, 0.035, 0.18))
	# tall commercial mirrors on the doors, ahead of the car mirrors' place
	var dm: float = lerpf(g[0], g[1], 0.955)
	var ym := top(dm) + 0.22
	var xm := hw(dm) + 0.2
	for s in [-1.0, 1.0]:
		CarModel._strap(S.gloss, Vector3(s * (hw(dm) - 0.02), top(dm) + 0.05, -dm), Vector3(s * (xm - 0.04), ym - 0.12, -dm + 0.03), 0.03, 0.03)
		CarModel._box(S.gloss, Vector3(s * xm, ym, -dm + 0.04), Vector3(0.1, 0.36, 0.08))
		CarModel._box(S.chrome, Vector3(s * xm, ym, -dm + 0.081), Vector3(0.085, 0.33, 0.004))
	# rear doors: centre seam, a window in each, handle, hinges and a step bumper
	var hr := hw(0.03)
	var zb := -0.004
	var r_top := float(g[5]) - 0.1
	CarModel._box(S.dark, Vector3(0, (floor_y + r_top) * 0.5 + 0.05, zb), Vector3(0.012, r_top - floor_y - 0.1, 0.012))
	for sx in [-1.0, 1.0]:
		var x0: float = sx * 0.07
		var x1: float = sx * (hr - 0.16)
		var c := Vector3((x0 + x1) * 0.5, 1.68, zb - 0.002)
		var sz := Vector3(absf(x1 - x0), 0.5, 0.012)
		CarModel._box(S.gloss, c, sz + Vector3(0.05, 0.05, 0.0))
		CarModel._box(S.glass_solid, c + Vector3(0, 0, 0.003), sz)
		for hy in [0.9, 1.9]:
			CarModel._box(S.dark, Vector3(sx * (hr - 0.04), hy, zb - 0.01), Vector3(0.07, 0.09, 0.03))
	CarModel._box(S.dark, Vector3(0.12, 1.2, zb - 0.012), Vector3(0.05, 0.16, 0.03))
	CarModel._box(S.dark, Vector3(0, floor_y + 0.355, 0.045), Vector3(0.9, 0.025, 0.1))  # step plate on the bumper


## Point and outward normal on the right side wall at height y, including the
## flat-sided cargo box above the shoulder (vans).
func wall_pn(d: float, y: float) -> Array:
	var p := section(d)
	var top_k := 14
	for k in range(4, top_k):
		if y <= p[k + 1].y or k == top_k - 1:
			var a: Vector2 = p[k]
			var b: Vector2 = p[k + 1]
			var f := clampf((y - a.y) / maxf(b.y - a.y, 0.0001), 0.0, 1.0)
			var q := a.lerp(b, f)
			var dir := (b - a).normalized()
			var n := Vector3(dir.y, -dir.x, 0.0)
			if n.x < 0.2:
				n = Vector3(1, 0, 0)
			return [Vector3(q.x, q.y, -d), n.normalized()]
	return side_pn(d, y)


## A thin dark strip between two side points, mirrored to side s.
func _line(st: SurfaceTool, pa: Array, pb: Array, half: Vector3, s: float) -> void:
	var a: Vector3 = pa[0] + pa[1] * 0.0015
	var b: Vector3 = pb[0] + pb[1] * 0.0015
	var m := Vector3(s, 1, 1)
	var n: Vector3 = pa[1] * m
	CarModel._quad(st, (a - half) * m, (a + half) * m, (b + half) * m, (b - half) * m, n)


# ---------------------------------------------------------------- lights and grille

## Point on the right side of the body at (d, y) with its true outward
## normal: round the rounded corners it faces partly forwards or backwards.
func surf_pn(d: float, y: float) -> Array:
	var p: Vector3 = side_pn(d, y)[0]
	var e := 0.004
	var pa: Vector3 = side_pn(maxf(d - e, 0.0), y)[0]
	var pb: Vector3 = side_pn(minf(d + e, l), y)[0]
	var qa: Vector3 = side_pn(d, y - 0.008)[0]
	var qb: Vector3 = side_pn(d, y + 0.008)[0]
	var n := (pb - pa).cross(qb - qa)
	if n.length() < 0.0000001:
		n = Vector3(0, 0, 1.0 if d < l * 0.5 else -1.0)
	n = n.normalized()
	var hint := Vector3(0.2, 0.0, 1.0 if d < l * 0.5 else -1.0)
	if n.dot(hint) < 0.0:
		n = -n
	return [p, n]


## The outline of the body at height y, seen from above: across the end face
## from x_from, round the corner and back along the side to wrap_d. Points
## come with outward normals; dir is +1 at the tail, -1 at the nose.
func outline(end_d: float, wrap_d: float, y: float, x_from := 0.0, n_face := 3, n_round := 10) -> Array:
	var dir := 1.0 if end_d < l * 0.5 else -1.0
	var pts: Array = []
	var xe: float = side_pn(end_d, y)[0].x
	for k in n_face:
		pts.append([Vector3(lerpf(x_from, xe, float(k) / n_face), y, -end_d), Vector3(0, 0, dir)])
	var span := absf(wrap_d - end_d)
	for k in n_round + 1:
		var e := span * (1.0 - cos(PI / 2.0 * k / n_round))  # close together round the corner
		pts.append(surf_pn(end_d + dir * e, y))
	return pts


## Columns of a lamp strip that runs across the rear face (or nose), round the
## corner and back along the side. Each column: [bottom, top, normal, u].
func _strip_cols(end_d: float, wrap_d: float, x_in: float, y0: float, y1: float, lift := 0.005) -> Array:
	var lo := outline(end_d, wrap_d, y0, x_in, 2, 9)
	var hi := outline(end_d, wrap_d, y1, x_in, 2, 9)
	var cols: Array = []
	for i in lo.size():
		var a: Array = lo[i]
		var b: Array = hi[i]
		cols.append([(a[0] as Vector3) + (a[1] as Vector3) * lift, (b[0] as Vector3) + (b[1] as Vector3) * lift, a[1]])
	var acc := 0.0
	var us := [0.0]
	for i in range(1, cols.size()):
		acc += ((cols[i][0] as Vector3) - (cols[i - 1][0] as Vector3)).length()
		us.append(acc)
	for i in cols.size():
		cols[i].append(us[i] / maxf(acc, 0.001))
	return cols


## A band wrapped round one end of the body between heights y0 and y1,
## standing `out` metres proud of it: bumpers, valances, splitters. Closed
## on top and underneath, mirrored to both sides.
func band(st: SurfaceTool, end_d: float, wrap_d: float, y0: float, y1: float, out: float, top_in := 0.03) -> void:
	var lo := outline(end_d, wrap_d, y0)
	var hi := outline(end_d, wrap_d, y1)
	for s in [-1.0, 1.0]:
		var m := Vector3(s, 1, 1)
		for i in lo.size() - 1:
			var a0: Vector3 = lo[i][0]
			var a1: Vector3 = lo[i + 1][0]
			var b0: Vector3 = hi[i][0]
			var b1: Vector3 = hi[i + 1][0]
			var na: Vector3 = lo[i][1]
			var nb: Vector3 = lo[i + 1][1]
			var nh0: Vector3 = hi[i][1]
			var nh1: Vector3 = hi[i + 1][1]
			# outer face
			_quad4(st, [(a0 + na * out) * m, (b0 + nh0 * out) * m, (b1 + nh1 * out) * m, (a1 + nb * out) * m],
				[na * m, nh0 * m, nh1 * m, nb * m], [])
			# top and bottom, tucked back into the body
			_quad4(st, [(b0 + nh0 * out) * m, (b0 - nh0 * top_in) * m, (b1 - nh1 * top_in) * m, (b1 + nh1 * out) * m],
				[Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP], [])
			_quad4(st, [(a0 + na * out) * m, (a0 - na * top_in) * m, (a1 - nb * top_in) * m, (a1 + nb * out) * m],
				[Vector3.DOWN, Vector3.DOWN, Vector3.DOWN, Vector3.DOWN], [])


## A strip along the side between two distances (sills, side skirts).
func side_strip(st: SurfaceTool, d0: float, d1: float, y0: float, y1: float, out: float, steps := 10) -> void:
	for s in [-1.0, 1.0]:
		var m := Vector3(s, 1, 1)
		for k in steps:
			var da := lerpf(d0, d1, float(k) / steps)
			var db := lerpf(d0, d1, float(k + 1) / steps)
			var a0: Array = surf_pn(da, y0)
			var a1: Array = surf_pn(da, y1)
			var b0: Array = surf_pn(db, y0)
			var b1: Array = surf_pn(db, y1)
			var na: Vector3 = a0[1]
			_quad4(st, [((a0[0] as Vector3) + na * out) * m, ((a1[0] as Vector3) + na * out) * m, ((b1[0] as Vector3) + na * out) * m, ((b0[0] as Vector3) + na * out) * m],
				[na * m, na * m, na * m, na * m], [])
			_quad4(st, [((a1[0] as Vector3) + na * out) * m, (a1[0] as Vector3) * m, (b1[0] as Vector3) * m, ((b1[0] as Vector3) + na * out) * m],
				[Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP], [])
			_quad4(st, [((a0[0] as Vector3) + na * out) * m, (a0[0] as Vector3) * m, (b0[0] as Vector3) * m, ((b0[0] as Vector3) + na * out) * m],
				[Vector3.DOWN, Vector3.DOWN, Vector3.DOWN, Vector3.DOWN], [])


## Side walls from a raised lamp strip back down to the body, top and bottom.
func _walls(st: SurfaceTool, cols: Array, s: float, lift: float) -> void:
	var m := Vector3(s, 1, 1)
	for i in cols.size() - 1:
		var a: Array = cols[i]
		var b: Array = cols[i + 1]
		var na: Vector3 = a[2]
		var nb: Vector3 = b[2]
		for e in [0, 1]:
			var pa: Vector3 = a[e]
			var pb: Vector3 = b[e]
			var up := Vector3.UP if e == 1 else Vector3.DOWN
			_quad4(st, [pa * m, (pa - na * lift) * m, (pb - nb * lift) * m, pb * m], [up, up, up, up], [])


## A thin band along the top (side = 1) or bottom (side = 0) edge of a lamp strip.
func _edge(cols: Array, side: float, frac: float) -> Array:
	var out: Array = []
	for c in cols:
		var lo: Vector3 = c[0]
		var hi: Vector3 = c[1]
		var n: Vector3 = c[2]
		var a: Vector3 = lo.lerp(hi, side) + n * 0.002
		var b: Vector3 = lo.lerp(hi, side + (frac if side < 0.5 else -frac)) + n * 0.002
		out.append([a, b, n, c[3]] if side < 0.5 else [b, a, n, c[3]])
	return out


## A projector lens in a chrome ring, sitting in the lamp at fraction u along it.
func _projector(S: Dictionary, cols: Array, u: float, s: float) -> void:
	var i := 0
	while i < cols.size() - 2 and float(cols[i + 1][3]) < u:
		i += 1
	var a: Array = cols[i]
	var b: Array = cols[i + 1]
	var f := clampf((u - float(a[3])) / maxf(float(b[3]) - float(a[3]), 0.001), 0.0, 1.0)
	var lo: Vector3 = (a[0] as Vector3).lerp(b[0], f)
	var hi: Vector3 = (a[1] as Vector3).lerp(b[1], f)
	var n: Vector3 = ((a[2] as Vector3).lerp(b[2], f)).normalized()
	var r := minf(0.04, (hi - lo).length() * 0.36)
	var c := (lo + hi) * 0.5 + n * 0.004
	var m := Vector3(s, 1, 1)
	CarModel._cyl(S.chrome, c * m, r, 0.012, n * m, 18, false)
	CarModel._cyl(S.head, (c - n * 0.002) * m, r * 0.72, 0.006, n * m, 18, true)


## Oval headlamps that follow the curve of the front wings (rear-engined
## coupe): a black bezel, a smoked lens, a projector ring and four LED points,
## each a layer laid onto the wing surface.
func _round_lamps(S: Dictionary) -> void:
	var dc := l - 0.24
	for s in [-1.0, 1.0]:
		var xc := hw(dc) * 0.62
		_surface_ellipse(S.gloss, dc, xc, 0.15, 0.115, 0.004, s)
		_surface_ellipse(S.headlens, dc, xc, 0.13, 0.098, 0.007, s)
		_surface_ellipse(S.chrome, dc + 0.01, xc, 0.045, 0.038, 0.009, s)
		_surface_ellipse(S.head, dc + 0.01, xc, 0.03, 0.026, 0.0105, s)
		for k in 4:
			var a := TAU * k / 4.0 + PI / 4.0
			_surface_ellipse(S.head, dc + 0.01 + cos(a) * 0.085, xc + sin(a) * 0.066, 0.016, 0.014, 0.0105, s)


## A filled ellipse laid on the top surface (bonnet/wings) round (dc, xc),
## lift metres above it, mirrored to side s.
func _surface_ellipse(st: SurfaceTool, dc: float, xc: float, rd: float, rx: float, lift: float, s: float) -> void:
	var seg := 24
	var pos := func(d: float, x: float) -> Array:
		var y := surf_y(d, x)
		var gd := (surf_y(d + 0.01, x) - surf_y(d - 0.01, x)) / 0.02
		var gx := (surf_y(d, x + 0.01) - surf_y(d, x - 0.01)) / 0.02
		var n := Vector3(-gx, 1.0, gd).normalized()
		return [Vector3(x * s, y, -d) + Vector3(n.x * s, n.y, n.z) * lift, Vector3(n.x * s, n.y, n.z)]
	var c: Array = pos.call(dc, xc)
	for i in seg:
		var a0 := TAU * i / seg
		var a1 := TAU * (i + 1) / seg
		var p0: Array = pos.call(dc + cos(a0) * rd, xc + sin(a0) * rx)
		var p1: Array = pos.call(dc + cos(a1) * rd, xc + sin(a1) * rx)
		_tri3(st, [c[0], p0[0], p1[0]], [c[1], p0[1], p1[1]], [])


## Emits a lamp strip mirrored to side s, with UVs across the lens texture.
func _strip(st: SurfaceTool, cols: Array, s: float) -> void:
	var m := Vector3(s, 1, 1)
	for i in cols.size() - 1:
		var a: Array = cols[i]
		var b: Array = cols[i + 1]
		var na: Vector3 = (a[2] as Vector3) * m
		var nb: Vector3 = (b[2] as Vector3) * m
		_quad4(st, [(a[0] as Vector3) * m, (a[1] as Vector3) * m, (b[1] as Vector3) * m, (b[0] as Vector3) * m], [na, na, nb, nb], [],
			[Vector2(a[3], 1.0), Vector2(a[3], 0.0), Vector2(b[3], 0.0), Vector2(b[3], 1.0)])


## Flat textured quad facing n (a rectangle from lo to hi in x and y at lo.z).
static func _panel(st: SurfaceTool, lo: Vector3, hi: Vector3, n: Vector3, uv0: Vector2, uv1: Vector2) -> void:
	_quad4(st, [Vector3(lo.x, lo.y, lo.z), Vector3(hi.x, lo.y, lo.z), Vector3(hi.x, hi.y, lo.z), Vector3(lo.x, hi.y, lo.z)], [n, n, n, n], [],
		[Vector2(uv0.x, uv1.y), Vector2(uv1.x, uv1.y), Vector2(uv1.x, uv0.y), Vector2(uv0.x, uv0.y)])


func lights(S: Dictionary, tails: SurfaceTool, sig_l: SurfaceTool, sig_r: SurfaceTool) -> void:
	# tail lights wrapping round the rear corners, raised a little off the body
	# with gloss-black walls so each reads as a lamp unit
	var tr := top(0.0)
	var tl: Array = pr.get("tail", [-0.25, -0.07, 0.5])
	var y0: float = tr + float(tl[0])
	var y1: float = tr + float(tl[1])
	var x_tail := maxf(hw(0.0) * float(tl[2]), 0.04)
	for s in [-1.0, 1.0]:
		var cols := _strip_cols(0.0, minf(rc_r + 0.08, axles[0] - R - 0.1), x_tail, y0, y1, 0.012)
		_strip(tails, cols, s)
		_walls(S.gloss, cols, s, 0.012)
		# indicator: an amber patch over the inner part of the lens, drawn only while blinking
		var a: Array = cols[0]
		var b: Array = cols[1]
		var f0 := clampf(0.2 / maxf(b[3], 0.01), 0.0, 1.0)
		var f1 := clampf(0.36 / maxf(b[3], 0.01), 0.0, 1.0)
		var p0: Vector3 = (a[0] as Vector3).lerp(b[0], f0) + Vector3(0, 0, 0.003)
		var p1: Vector3 = (a[0] as Vector3).lerp(b[0], f1) + Vector3(0, 0, 0.003)
		var lo := Vector3(minf(p0.x, p1.x) * s, lerpf(y0, y1, 0.3), p0.z)
		var hi := Vector3(maxf(p0.x, p1.x) * s, lerpf(y0, y1, 0.72), p0.z)
		CarModel._quad(sig_l if s < 0 else sig_r, Vector3(lo.x, lo.y, lo.z), Vector3(hi.x, lo.y, lo.z),
			Vector3(hi.x, hi.y, lo.z), Vector3(lo.x, hi.y, lo.z), Vector3.BACK)
	tails.set_uv(LED_UV)
	if style.get("lightbar", false) or tl[2] <= 0.0:
		CarModel._box(tails, Vector3(0, lerpf(y0, y1, 0.6), 0.012), Vector3(x_tail * 2.0 + 0.02, minf(0.022, (y1 - y0) * 0.5), 0.014))
	# headlights: lamp units wrapping round the front corners, with projector
	# lenses in chrome rings and an LED daytime-running-light line
	var tf := top(l)
	var hd: Array = pr.get("head", [-0.18, -0.05, 0.3])
	var hy0: float = tf + float(hd[0])
	var hy1: float = tf + float(hd[1])
	if pr.get("round_lamps", false):
		_round_lamps(S)
	else:
		for s in [-1.0, 1.0]:
			var cols := _strip_cols(l, maxf(l - rc_f - 0.1, axles[1] + R + 0.1), hw(l) * float(hd[2]), hy0, hy1, 0.01)
			_strip(S.headlens, cols, s)
			_walls(S.gloss, cols, s, 0.01)
			var proj: int = pr.get("projectors", 1)
			for k in proj:
				var u: float = [0.22, 0.48][k] if proj == 2 else 0.3
				_projector(S, cols, u, s)
			match pr.get("drl", "brow"):
				"brow":  # a thin LED line along the top edge
					_strip(S.head, _edge(cols, 1.0, 0.16), s)
				"L":  # down the inner end and along the bottom
					_strip(S.head, _edge(cols, 0.0, 0.18), s)
					var c0: Array = cols[0]
					var c1: Array = cols[1]
					var inner: Array = [[c0[0], c0[1], c0[2], 0.0], [(c0[0] as Vector3).lerp(c1[0], 0.12), (c0[1] as Vector3).lerp(c1[1], 0.12), c0[2], 0.1]]
					_strip(S.head, inner, s)
	# grille, lower intake, fog lights and the lower lip
	var gz := -l - 0.008
	var n := Vector3(0, 0, -1)
	var gy0 := tf - 0.21
	var gy1 := tf - 0.07
	var kind: String = pr.get("grille", "frame")
	if style.get("split_grille", false):
		for c in [-0.15, 0.15]:
			_panel(S.grille, Vector3(c - 0.09, gy0, gz), Vector3(c + 0.09, gy1 + 0.01, gz), n, Vector2(0, 0), Vector2(0.35, 1))
			_frame(S.chrome, Vector3(c - 0.09, gy0, gz - 0.002), Vector3(c + 0.09, gy1 + 0.01, gz - 0.002))
	elif kind == "frame":
		var gx := hw(l) * 0.3
		_panel(S.grille, Vector3(-gx, gy0, gz), Vector3(gx, gy1, gz), n, Vector2(0, 0), Vector2(1, 1))
		_frame(S.chrome, Vector3(-gx, gy0, gz - 0.002), Vector3(gx, gy1, gz - 0.002))
	elif kind == "van":  # a tall grille filling the gap between the lamps, with chrome slats
		var vx := hw(l) * 0.39
		var vy0 := tf - 0.3
		var vy1 := tf - 0.03
		_panel(S.grille, Vector3(-vx, vy0, gz), Vector3(vx, vy1, gz), n, Vector2(0, 0), Vector2(1.6, 0.9))
		_frame(S.gloss, Vector3(-vx, vy0, gz - 0.002), Vector3(vx, vy1, gz - 0.002))
		for k in 3:
			var sy := lerpf(vy0, vy1, (k + 1) / 4.0)
			CarModel._box(S.chrome, Vector3(0, sy, gz - 0.01), Vector3(vx * 2.0 - 0.04, 0.022, 0.012))
		# unpainted black lower bumper wrapping the nose
		CarModel._box(S.dark, Vector3(0, floor_y + 0.17, -l + 0.03), Vector3(hw(l) * 2.0 - 0.06, 0.2, 0.09))
	elif kind == "bar":  # a slim slot between the lamps
		var bx := hw(l) * 0.26
		_panel(S.grille, Vector3(-bx, tf - 0.15, gz), Vector3(bx, tf - 0.1, gz), n, Vector2(0, 0), Vector2(1.2, 0.3))
		_frame(S.gloss, Vector3(-bx, tf - 0.15, gz - 0.002), Vector3(bx, tf - 0.1, gz - 0.002))
	# lower intake: wide and deep on the cars without a grille, framed in black
	var big := kind != "frame"
	var ix := hw(l) * (0.68 if big else 0.55)
	var iy1 := floor_y + (0.25 if big else 0.19)
	_panel(S.grille, Vector3(-ix, floor_y + 0.07, gz), Vector3(ix, iy1, gz), n, Vector2(0, 0), Vector2(1.8, 0.7))
	_frame(S.gloss, Vector3(-ix, floor_y + 0.07, gz - 0.003), Vector3(ix, iy1, gz - 0.003))
	if big:
		for s in [-1.0, 1.0]:  # splitter blades dividing the intake
			CarModel._box(S.gloss, Vector3(s * ix * 0.45, (floor_y + 0.07 + iy1) * 0.5, gz - 0.01), Vector3(0.018, iy1 - floor_y - 0.07, 0.03))
	else:
		for s in [-1.0, 1.0]:
			CarModel._box(S.head, Vector3(s * hw(l) * 0.72, floor_y + 0.13, gz - 0.002), Vector3(0.12, 0.05, 0.02))
	CarModel._box(S.dark, Vector3(0, floor_y + 0.025, -l + 0.04), Vector3(hw(l) * 1.9, 0.05, 0.1))
	CarModel._box(S.head, Vector3(0, floor_y + 0.335, 0.045), Vector3(0.12, 0.012, 0.02))  # plate light


## Chrome surround round a rectangle on the nose.
static func _frame(st: SurfaceTool, lo: Vector3, hi: Vector3) -> void:
	var t := 0.014
	var z := lo.z
	CarModel._box(st, Vector3((lo.x + hi.x) / 2.0, hi.y, z), Vector3(hi.x - lo.x + t, t, 0.012))
	CarModel._box(st, Vector3((lo.x + hi.x) / 2.0, lo.y, z), Vector3(hi.x - lo.x + t, t, 0.012))
	CarModel._box(st, Vector3(lo.x, (lo.y + hi.y) / 2.0, z), Vector3(t, hi.y - lo.y, 0.012))
	CarModel._box(st, Vector3(hi.x, (lo.y + hi.y) / 2.0, z), Vector3(t, hi.y - lo.y, 0.012))


# ---------------------------------------------------------------- simple cabin

## Dark seats, dashboard and wheel seen through the tinted glass of traffic
## and rival cars (the player's car gets a full interior instead).
func cabin_mesh() -> ArrayMesh:
	var st := CarModel._new_st()
	var dm := (float(g[0]) + float(g[1])) * 0.5
	var t := top(dm)
	var gw := minf(w / 2.0 * float(g[6]), hw(dm) * 0.915) - 0.06
	var fl := floor_y + 0.12
	CarModel._box(st, Vector3(0, (fl + t - 0.02) * 0.5, -dm), Vector3(gw * 2.0, t - 0.02 - fl, g[1] - g[0] - 0.12))
	# dashboard: its front edge stays under the raked windscreen
	var dash_top := t + 0.13
	var d_front := minf(float(g[1]) - 0.12, glass_d(dash_top + 0.03))
	CarModel._box(st, Vector3(0, dash_top - 0.07, -(d_front - 0.2)), Vector3(gw * 2.0, 0.14, 0.4))
	var eye_d: float = g[1] - 1.45
	var sx := 0.36 * w / 1.84
	var seat_top := minf(t + 0.45, roof_y(eye_d - 0.28) - 0.16)
	for x in [-sx, sx]:
		CarModel._box(st, Vector3(x, (t - 0.05 + seat_top) * 0.5, -(eye_d - 0.25)), Vector3(0.46, seat_top - t + 0.05, 0.12), Basis(Vector3.RIGHT, 0.2))
		CarModel._box(st, Vector3(x, seat_top + 0.08, -(eye_d - 0.3)), Vector3(0.26, 0.16, 0.1))
	CarModel._box(st, Vector3(-sx, t + 0.15, -(g[1] - 0.85)), Vector3(0.34, 0.34, 0.04), Basis(Vector3.RIGHT, -0.4))
	var rd := eye_d - 0.95
	if rd > g[0] + 0.25 and roof_y(rd) - t > 0.42:
		var rtop := minf(t + 0.42, roof_y(rd) - 0.12)
		CarModel._box(st, Vector3(0, (t - 0.05 + rtop) * 0.5, -rd), Vector3(gw * 2.0 - 0.1, rtop - t + 0.05, 0.12), Basis(Vector3.RIGHT, 0.22))
		for x in [-sx, 0.0, sx]:
			CarModel._box(st, Vector3(x, rtop + 0.07, -(rd - 0.03)), Vector3(0.24, 0.13, 0.09))
	return st.commit()
