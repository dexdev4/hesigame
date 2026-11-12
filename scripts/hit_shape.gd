class_name HitShape
extends RefCounted
## A car's hit box: its outline seen from above (scripts/hulls.gd, made from the
## car models by tools/make_hulls.py), so a tapering nose, rounded tail corners
## and wheel-arch flares count and the empty corners of a plain rectangle do not.
## The outline is one convex piece (two for the truck: its box and its cab).
##
## Local coordinates: x across the car (+ right), y along it from the rear
## bumper forwards. "World" outlines are in road coordinates (x across the
## road, y along it), for a car turned by `yaw` (+ = nose to the right) about a
## pivot: the rear bumper for a car driving normally (that is how the models are
## turned), the middle of the car for a wreck.
##
## Contact is the separating-axis test (how far, which way to push them apart)
## with a contact point: the middle of the area the two outlines overlap in, so
## a crash knows where the cars touched as well as how far they overlap. That
## point is what makes an off-centre hit spin a car.

const INSET := 0.05  # the outline is pulled in this far: a graze with the paint is not a crash

static var _all := {}

var id := ""
var parts: Array[PackedVector2Array] = []
var length := 4.5
var width := 1.9
var rear_axle := 0.9
var front_axle := 3.6
var track := 0.8       # half the distance between the wheels
var k2 := 2.0          # radius of gyration squared about the middle of the car (inertia per unit mass)
var radius := 3.0      # of the outline about the middle of the car: for a quick "too far to touch"


static func of(shape_id: String) -> HitShape:
	if not _all.has(shape_id):
		_all[shape_id] = HitShape.new(shape_id)
	return _all[shape_id]


func _init(shape_id := "sedan") -> void:
	id = shape_id
	var sh: Dictionary = Data.SHAPES.get(shape_id, Data.SHAPES.sedan)
	length = float(sh.l)
	width = float(sh.w)
	var h: Dictionary = Hulls.DATA.get(shape_id, {})
	if h.is_empty():
		# no outline: a plain rectangle
		parts.append(_inset(PackedVector2Array([Vector2(-width / 2.0, 0.0), Vector2(width / 2.0, 0.0), Vector2(width / 2.0, length), Vector2(-width / 2.0, length)])))
	else:
		for flat: Array in h.parts:
			var poly := PackedVector2Array()
			for i in range(0, flat.size(), 2):
				poly.append(Vector2(float(flat[i]), float(flat[i + 1])))
			parts.append(_inset(poly))
		rear_axle = float(h.axles[0])
		front_axle = float(h.axles[1])
		track = float(h.track)
	k2 = (width * width + length * length) / 12.0
	var r2 := 0.0
	for part in parts:
		for p in part:
			r2 = maxf(r2, Vector2(p.x, p.y - length / 2.0).length_squared())
	radius = sqrt(r2)


## The outline moved in by INSET all round (corners mitred), counter-clockwise.
static func _inset(poly: PackedVector2Array) -> PackedVector2Array:
	var n := poly.size()
	var area := 0.0
	for i in n:
		area += poly[i].x * poly[(i + 1) % n].y - poly[(i + 1) % n].x * poly[i].y
	if area < 0.0:
		poly.reverse()
	var out := PackedVector2Array()
	for i in n:
		var prev := poly[(i + n - 1) % n]
		var cur := poly[i]
		var next := poly[(i + 1) % n]
		var e1 := (cur - prev).normalized()
		var e2 := (next - cur).normalized()
		var n1 := Vector2(e1.y, -e1.x)  # outward, for a counter-clockwise outline
		var n2 := Vector2(e2.y, -e2.x)
		var k := 1.0 + n1.dot(n2)
		out.append(cur - (n1 + n2) * (INSET / maxf(k, 0.2)))
	# very short edges can fold a corner back on itself: take the convex outline of what is left
	var hull := Geometry2D.convex_hull(out)
	if hull.size() > 1 and hull[0].is_equal_approx(hull[hull.size() - 1]):
		hull.remove_at(hull.size() - 1)
	var a2 := 0.0
	for i in hull.size():
		a2 += hull[i].x * hull[(i + 1) % hull.size()].y - hull[(i + 1) % hull.size()].x * hull[i].y
	if a2 < 0.0:
		hull.reverse()
	return hull


## The outline in road coordinates. The pivot (the point `pivot` metres up the
## car from the rear bumper) is at (x, z + pivot) and the car is turned about it.
func world(x: float, z: float, yaw: float, pivot := 0.0) -> Array[PackedVector2Array]:
	var s := sin(yaw)
	var c := cos(yaw)
	var out: Array[PackedVector2Array] = []
	for part in parts:
		var q := PackedVector2Array()
		q.resize(part.size())
		for i in part.size():
			var a := part[i].x
			var b := part[i].y - pivot
			q[i] = Vector2(x + a * c + b * s, z + pivot - a * s + b * c)
		out.append(q)
	return out


## How far the car reaches across the road (min, max, relative to x) when turned by yaw about the pivot.
func x_reach(yaw: float, pivot := 0.0) -> Vector2:
	var s := sin(yaw)
	var c := cos(yaw)
	var lo := INF
	var hi := -INF
	for part in parts:
		for p in part:
			var v := p.x * c + (p.y - pivot) * s
			lo = minf(lo, v)
			hi = maxf(hi, v)
	return Vector2(lo, hi)


## Where the contact patches of the four tyres are, relative to the middle of the car (x across, y along).
func wheel_points() -> PackedVector2Array:
	var m := length / 2.0
	return PackedVector2Array([Vector2(-track, rear_axle - m), Vector2(track, rear_axle - m), Vector2(-track, front_axle - m), Vector2(track, front_axle - m)])


# ---------------------------------------------------------------- queries on world outlines

static func x_range(parts_w: Array[PackedVector2Array]) -> Vector2:
	var lo := INF
	var hi := -INF
	for part in parts_w:
		for p in part:
			lo = minf(lo, p.x)
			hi = maxf(hi, p.x)
	return Vector2(lo, hi)


static func y_range(parts_w: Array[PackedVector2Array]) -> Vector2:
	var lo := INF
	var hi := -INF
	for part in parts_w:
		for p in part:
			lo = minf(lo, p.y)
			hi = maxf(hi, p.y)
	return Vector2(lo, hi)


## The span (min x, max x) of a convex outline at height y; (INF, -INF) if it does not reach that high.
static func x_at(poly: PackedVector2Array, y: float) -> Vector2:
	var lo := INF
	var hi := -INF
	var n := poly.size()
	for i in n:
		var p := poly[i]
		var q := poly[(i + 1) % n]
		if y < minf(p.y, q.y) or y > maxf(p.y, q.y):
			continue
		if is_equal_approx(p.y, q.y):
			lo = minf(lo, minf(p.x, q.x))
			hi = maxf(hi, maxf(p.x, q.x))
		else:
			var x := p.x + (q.x - p.x) * (y - p.y) / (q.y - p.y)
			lo = minf(lo, x)
			hi = maxf(hi, x)
	return Vector2(lo, hi)


static func _span_at(parts_w: Array[PackedVector2Array], y: float) -> Vector2:
	var lo := INF
	var hi := -INF
	for part in parts_w:
		var s := x_at(part, y)
		lo = minf(lo, s.x)
		hi = maxf(hi, s.y)
	return Vector2(lo, hi)


## The gap across the road between two cars, as the driver sees it: the least
## sideways distance between their outlines along the stretch where they are
## side by side (negative: they overlap there). Cars nose to tail use the
## nearest ends, so a close pass just ahead or behind still counts.
static func lateral_gap(a: Array[PackedVector2Array], b: Array[PackedVector2Array]) -> float:
	var ya := y_range(a)
	var yb := y_range(b)
	var lo := maxf(ya.x, yb.x)
	var hi := minf(ya.y, yb.y)
	var best := INF
	var samples := 7
	if lo > hi:
		samples = 1
		lo = (ya.y + yb.x) * 0.5 if ya.y < yb.x else (yb.y + ya.x) * 0.5
		hi = lo
	for i in samples:
		var y := lo if samples == 1 else lerpf(lo, hi, float(i) / float(samples - 1))
		var sa := _span_at(a, clampf(y, ya.x, ya.y))
		var sb := _span_at(b, clampf(y, yb.x, yb.y))
		if sa.x > sa.y or sb.x > sb.y:
			continue
		best = minf(best, maxf(sb.x - sa.y, sa.x - sb.y))
	return best


# ---------------------------------------------------------------- contact

## How far polygon b lies in front of the nearest-facing edge of a: (edge, separation), negative inside.
static func _max_sep(a: PackedVector2Array, b: PackedVector2Array) -> Vector2:
	var best := -INF
	var idx := 0
	var na := a.size()
	for i in na:
		var p := a[i]
		var e := a[(i + 1) % na] - p
		var ln := e.length()
		if ln < 0.000001:
			continue
		var nrm := Vector2(e.y, -e.x) / ln
		var s := INF
		for v in b:
			s = minf(s, nrm.dot(v - p))
		if s > best:
			best = s
			idx = i
	return Vector2(idx, best)


## The area where two convex counter-clockwise polygons overlap, as a polygon (a is cut by each edge of b in turn).
static func _overlap(a: PackedVector2Array, b: PackedVector2Array) -> PackedVector2Array:
	var out := a
	var nb := b.size()
	for i in nb:
		if out.is_empty():
			break
		var p := b[i]
		var e := b[(i + 1) % nb] - p
		var src := out
		out = PackedVector2Array()
		var m := src.size()
		for k in m:
			var s := src[k]
			var t := src[(k + 1) % m]
			var ds := e.cross(s - p)  # >= 0: on the inside of this edge
			var dt := e.cross(t - p)
			if ds >= 0.0:
				out.append(s)
			if (ds >= 0.0) != (dt >= 0.0):
				out.append(s + (t - s) * (ds / (ds - dt)))
	return out


static func _centroid(poly: PackedVector2Array) -> Vector2:
	# worked out about the first corner: road coordinates run into the thousands, and a float
	# cross product of two of those would lose everything
	var n := poly.size()
	var o := poly[0]
	var area2 := 0.0
	var c := Vector2.ZERO
	var mean := Vector2.ZERO
	for i in n:
		var p := poly[i] - o
		var q := poly[(i + 1) % n] - o
		var cr := p.cross(q)
		area2 += cr
		c += (p + q) * cr
		mean += p
	if absf(area2) < 0.0000001:
		return o + mean / maxf(float(n), 1.0)
	return o + c / (3.0 * area2)


## Contact between two convex counter-clockwise polygons: {} if they do not
## touch, else {"n": the way from a to b, "depth": how far they overlap (the
## shortest way to push them apart), "p": the middle of the area they overlap in,
## where the force of the blow goes through}.
static func _pair(a: PackedVector2Array, b: PackedVector2Array) -> Dictionary:
	var sa := _max_sep(a, b)
	if sa.y > 0.0:
		return {}
	var sb := _max_sep(b, a)
	if sb.y > 0.0:
		return {}
	var flip := sb.y > sa.y + 0.002  # the shallower face is the reference; a wins a tie
	var ref := b if flip else a
	var ri := int(sb.x if flip else sa.x)
	var r1 := ref[ri]
	var r2 := ref[(ri + 1) % ref.size()]
	var rt := (r2 - r1).normalized()
	var rn := Vector2(rt.y, -rt.x)  # out of the reference outline
	var area := _overlap(a, b)
	var point := _centroid(area) if area.size() >= 3 else (a[0] + b[0]) * 0.5
	return {"n": -rn if flip else rn, "depth": -(sb.y if flip else sa.y), "p": point}


## Contact between two cars' world outlines (arrays of convex parts): {} or the deepest {n, depth, p} (see _pair).
static func contact(a: Array[PackedVector2Array], b: Array[PackedVector2Array]) -> Dictionary:
	var best := {}
	for pa in a:
		for pb in b:
			var c := _pair(pa, pb)
			if not c.is_empty() and (best.is_empty() or c.depth > best.depth):
				best = c
	return best


## Contact between a car and a guardrail: a straight wall along the road at
## x = wall_x with the car on the road side (side = +1 for the rail on the
## right, -1 for the one on the left). {} or {"n": from the car into the wall,
## "depth": how far the worst corner is through it, "p": the middle of the
## corners that are through it}. `slop` counts a car just touching as in contact.
static func wall_contact(a: Array[PackedVector2Array], wall_x: float, side: float, slop := 0.0) -> Dictionary:
	var worst := -INF
	for part in a:
		for p in part:
			worst = maxf(worst, (p.x - wall_x) * side)
	if worst < -slop:
		return {}
	var sum := Vector2.ZERO
	var cnt := 0
	for part in a:
		for p in part:
			if (p.x - wall_x) * side > worst - 0.06:
				sum += p
				cnt += 1
	return {"n": Vector2(side, 0.0), "depth": maxf(worst, 0.0), "p": sum / float(cnt)}
