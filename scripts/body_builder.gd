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


func _init(p_id: String, p_pr: Dictionary, shape: Dictionary, p_style: Dictionary) -> void:
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
	var ps: Array = pr.pillars
	for i in ps.size():
		# rear pillar in body colour, the others gloss black like most modern cars
		pillars.append([lerpf(g[0], g[1], ps[i][0]), lerpf(g[0], g[1], ps[i][1]), "paint" if i == 0 else "gloss"])


# ---------------------------------------------------------------- shape

func top(d: float) -> float:
	return CarModel._station_at(stations, d, 1)


## Half width of the body at d: profile width, a bulge over each wheel and
## rounded corners at both ends.
func hw(d: float) -> float:
	var bulge := 0.0
	for a in axles:
		bulge = maxf(bulge, exp(-pow((d - a) / 0.6, 2.0)))
	var e := minf(d, l - d)
	var end_round := 1.0
	if e < 0.12:
		end_round = 1.0 - 0.05 * pow(1.0 - e / 0.12, 2.0)
	return w / 2.0 * CarModel._station_at(stations, d, 2) * (1.0 + 0.02 * bulge) * end_round


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
		return t + (float(g[5]) - t) * _ease((d - g[0]) / maxf(g[2] - g[0], 0.01), 0.4)
	if d > g[3]:
		return t + (float(g[5]) - t) * _ease((g[1] - d) / maxf(g[1] - g[3], 0.01), 0.3)
	return float(g[5]) + 0.012 * sin(PI * (d - g[2]) / maxf(g[3] - g[2], 0.01))


## Right half of the cross-section at d, from the bottom centre to the top centre.
func section(d: float) -> PackedVector2Array:
	var t := top(d)
	var hwd := hw(d)
	var yb := arch_y(d)
	var H := maxf(t - yb, 0.04)
	var p := PackedVector2Array()
	p.resize(N)
	p[0] = Vector2(0.0, floor_y)
	p[1] = Vector2(hwd * 0.6, floor_y)
	p[2] = Vector2(hwd * 0.62, yb)  # inner wheel-well wall where lifted
	p[3] = Vector2(hwd * 0.82, yb)
	p[4] = Vector2(hwd * 0.935, yb + H * 0.05)
	p[5] = Vector2(hwd * 0.985, yb + H * 0.14)
	p[6] = Vector2(hwd, yb + H * 0.42)
	p[7] = Vector2(hwd * 0.99, yb + H * 0.72)
	p[8] = Vector2(hwd * 0.972, yb + H * 0.9)
	p[9] = Vector2(hwd * 0.955, t - 0.012)
	p[10] = Vector2(hwd * 0.935, t)
	var flat := [Vector2(hwd * 0.92, t + 0.006), Vector2(hwd * 0.9, t + 0.01), Vector2(hwd * 0.88, t + 0.013),
		Vector2(hwd * 0.855, t + 0.016), Vector2(hwd * 0.78, t + 0.02), Vector2(hwd * 0.6, t + 0.024),
		Vector2(hwd * 0.32, t + 0.027), Vector2(0.0, t + 0.028)]
	var roof := roof_y(d)
	var gh_h := roof - t
	if gh_h <= 0.0005:
		for k in 8:
			p[11 + k] = flat[k]
		return p
	var full := maxf(float(g[5]) - t, 0.05)
	var hk := clampf(gh_h / full, 0.0, 1.0)
	var gw_base := minf(w / 2.0 * float(g[6]), hwd * 0.915)
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
	var n := int(ceil(l / 0.075))
	for i in n + 1:
		ds.append(l * i / n)
	for a in axles:
		for k in 13:
			ds.append(a + R * (-1.0 + k / 6.0) * 0.999)  # dense round each arch
		ds.append(a - R * 1.002)
		ds.append(a + R * 1.002)
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
	if seg == 10:
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
		return "paint" if (ws or rs) else "gloss"  # A/C pillar edge, or the trim above the side windows
	if seg == 15:
		return "paint"
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
	var groups := [[4, 10], [10, 18]]
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
			var gi := 0 if seg <= 9 else 1
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
	var gwb := minf(w / 2.0 * float(g[6]), hw(dmr) * 0.915)
	for s in [-1.0, 1.0]:
		var hc := Vector3(s * (gwb + 0.17), tm + 0.11, -dmr + 0.02)
		CarModel._box(S.gloss, Vector3(s * (gwb + 0.06), tm + 0.06, -dmr + 0.03), Vector3(0.12, 0.05, 0.1))
		CarModel._box(S.paint, hc, Vector3(0.2, 0.11, 0.08))
		CarModel._box(S.paint, hc + Vector3(0, 0, -0.045), Vector3(0.17, 0.09, 0.03))
		CarModel._box(S.paint, hc + Vector3(s * 0.095, 0, -0.012), Vector3(0.03, 0.09, 0.07))
		CarModel._quad(S.chrome, hc + Vector3(-0.085, -0.045, 0.041), hc + Vector3(0.085, -0.045, 0.041),
			hc + Vector3(0.085, 0.045, 0.041), hc + Vector3(-0.085, 0.045, 0.041), Vector3.BACK)
		CarModel._box(sig_l if s < 0 else sig_r, hc + Vector3(s * 0.07, -0.035, -0.052), Vector3(0.06, 0.016, 0.02))
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
	# door shut lines, the door bottoms and handles
	var four_door: bool = g[1] - g[0] > 2.4 and not ["muscle", "super"].has(id)
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
	# racing stripes over the roof (the bonnet and boot ones come with the style extras)
	if style.get("stripes", false):
		for k in 8:
			var a2 := lerpf(g[2], g[3], k / 8.0)
			var b2 := lerpf(g[2], g[3], (k + 1) / 8.0)
			for sx in [-1.0, 1.0]:
				CarModel._quad(S.accent, Vector3(sx * 0.07, roof_y(a2) + 0.03, -a2), Vector3(sx * 0.27, roof_y(a2) + 0.03, -a2),
					Vector3(sx * 0.27, roof_y(b2) + 0.03, -b2), Vector3(sx * 0.07, roof_y(b2) + 0.03, -b2), Vector3.UP)


## A thin dark strip between two side points, mirrored to side s.
func _line(st: SurfaceTool, pa: Array, pb: Array, half: Vector3, s: float) -> void:
	var a: Vector3 = pa[0] + pa[1] * 0.0015
	var b: Vector3 = pb[0] + pb[1] * 0.0015
	var m := Vector3(s, 1, 1)
	var n: Vector3 = pa[1] * m
	CarModel._quad(st, (a - half) * m, (a + half) * m, (b + half) * m, (b - half) * m, n)


# ---------------------------------------------------------------- lights and grille

## Columns of a lamp strip that runs across the rear face (or nose), round the
## corner and back along the side. Each column: [bottom, top, normal, u].
func _strip_cols(end_d: float, dir: float, corner_d: float, wrap_d: float, x_in: float, y0: float, y1: float) -> Array:
	var zc := -end_d + dir * 0.006
	var ym := (y0 + y1) * 0.5
	var xe: float = side_pn(end_d, ym)[0].x
	var ncap := Vector3(0, 0, dir)
	var cols: Array = [
		[Vector3(x_in, y0, zc), Vector3(x_in, y1, zc), ncap],
		[Vector3(xe - 0.03, y0, zc), Vector3(xe - 0.03, y1, zc), ncap],
		[Vector3(xe + 0.003, y0 + 0.005, -end_d + dir * 0.003), Vector3(xe + 0.003, y1 - 0.002, -end_d + dir * 0.003), (ncap + Vector3.RIGHT).normalized()],
	]
	var c0: Array = side_pn(corner_d, y0 + 0.015)
	var c1: Array = side_pn(corner_d, y1 - 0.008)
	cols.append([c0[0] + c0[1] * 0.004, c1[0] + c1[1] * 0.004, c0[1]])
	var q0: Array = side_pn(wrap_d, y0 + 0.05)
	var q1: Array = side_pn(wrap_d, y1 - 0.025)
	cols.append([q0[0] + q0[1] * 0.004, q1[0] + q1[1] * 0.004, q0[1]])
	var acc := 0.0
	var us := [0.0]
	for i in range(1, cols.size()):
		acc += ((cols[i][0] as Vector3) - (cols[i - 1][0] as Vector3)).length()
		us.append(acc)
	for i in cols.size():
		cols[i].append(us[i] / acc)
	return cols


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
	# tail lights wrapping round the rear corners
	var tr := top(0.0)
	var y0 := tr - 0.25
	var y1 := tr - 0.07
	for s in [-1.0, 1.0]:
		var cols := _strip_cols(0.0, 1.0, 0.07, 0.24, hw(0.0) * 0.52, y0, y1)
		_strip(tails, cols, s)
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
	if style.get("lightbar", false):
		CarModel._box(tails, Vector3(0, y1 - 0.02, 0.01), Vector3(hw(0.0) * 1.05, 0.022, 0.012))
	# headlights wrapping round the front corners
	var tf := top(l)
	for s in [-1.0, 1.0]:
		_strip(S.headlens, _strip_cols(l, -1.0, l - 0.07, l - 0.26, hw(l) * 0.36, tf - 0.18, tf - 0.05), s)
	# grille, lower intake, fog lights and the lower lip
	var gz := -l - 0.008
	var n := Vector3(0, 0, -1)
	var gy0 := tf - 0.21
	var gy1 := tf - 0.07
	if style.get("split_grille", false):
		for c in [-0.15, 0.15]:
			_panel(S.grille, Vector3(c - 0.09, gy0, gz), Vector3(c + 0.09, gy1 + 0.01, gz), n, Vector2(0, 0), Vector2(0.35, 1))
			_frame(S.chrome, Vector3(c - 0.09, gy0, gz - 0.002), Vector3(c + 0.09, gy1 + 0.01, gz - 0.002))
	else:
		var gx := hw(l) * 0.3
		_panel(S.grille, Vector3(-gx, gy0, gz), Vector3(gx, gy1, gz), n, Vector2(0, 0), Vector2(1, 1))
		_frame(S.chrome, Vector3(-gx, gy0, gz - 0.002), Vector3(gx, gy1, gz - 0.002))
	var ix := hw(l) * 0.55
	_panel(S.grille, Vector3(-ix, floor_y + 0.07, gz), Vector3(ix, floor_y + 0.19, gz), n, Vector2(0, 0), Vector2(1.6, 0.6))
	for s in [-1.0, 1.0]:
		CarModel._box(S.head, Vector3(s * hw(l) * 0.72, floor_y + 0.13, gz - 0.002), Vector3(0.12, 0.05, 0.02))
	CarModel._box(S.dark, Vector3(0, floor_y + 0.025, -l + 0.04), Vector3(hw(l) * 1.9, 0.05, 0.1))
	CarModel._box(S.head, Vector3(0, floor_y + 0.345, 0.03), Vector3(0.12, 0.012, 0.02))  # plate light


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
	CarModel._box(st, Vector3(0, t + 0.06, -(g[1] - 0.32)), Vector3(gw * 2.0, 0.14, 0.4))
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
