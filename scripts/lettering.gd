class_name Lettering
extends RefCounted
## Words as real 3D lettering: the outlines of a font's glyphs turned into solid letters, for the names on the cars (see
## CarLettering). A letter is made like a cast badge: walls that stand off the panel, a chamfer along the front edge that
## catches the light, a flat front, and, if asked, a flat dark groove a little wider than the letter, which is the gap
## round an inlaid letter. (The old badges were Label3D text: a flat picture of letters, drawn over the paint.)
##
## The outlines come from the text server (`font_get_glyph_contours`), curves are cut into short straight pieces, holes
## (the inside of an A, an O, an 8) are cut out of the front face by splitting it along the line through the hole and
## subtracting the hole from each half (Geometry2D does the clipping), and every piece is triangulated by Geometry2D.
##
## A word is built once and kept (it is data, not nodes): a car that has the word puts a MeshInstance3D on it.

const READ_PX := 120      # the size the outlines are read at: big enough for smooth curves
const CURVE_PX := 5.0     # a curve is cut into pieces about this long, in px at READ_PX (and at most CURVE_MAX of them)
const CURVE_MAX := 7
const BIG := 1.0e4

static var _cache := {}
static var _cap_cache := {}


## The mesh of `text` set in `font`. `o` (all optional):
##   cap       the height of a capital, m (0.05)
##   depth     how far the letters stand off the panel, m (0.008)
##   bevel     the chamfer along the front edge, m (0: none)
##   halo      how far the groove round the letters reaches, m (0: none)
##   tracking  space added between letters, in em
##   skew      slant: x += y * skew
##   bow       the curve of the panel, 1/m: z += bow * x^2, x measured from the middle of the word
##   align     -1 the text starts at x = 0, 0 it is centred on it, 1 it ends there
## Returns {"mesh": ArrayMesh (surface 0 the letters, surface 1 the groove if there is one), "width": m, "cap": m, "tris": int}.
## The mesh stands in the XY plane, the front facing +z, y = 0 in the middle of the capitals.
static func word(text: String, font: Font, o := {}) -> Dictionary:
	var key := "%s|%s|%s" % [text, _font_key(font), str(o)]
	if not _cache.has(key):
		_cache[key] = _build(text, font, o)
	return _cache[key]


static func clear_cache() -> void:
	_cache.clear()


static func _font_key(font: Font) -> String:
	if font is FontVariation:
		var v := font as FontVariation
		return "%s%s" % [_font_key(v.base_font) if v.base_font != null else "", str(v.variation_opentype)]
	return font.resource_path if font.resource_path != "" else str(font.get_instance_id())


# ---------------------------------------------------------------- outlines

## The contours of one glyph as polygons in px (y up), curves cut into straight pieces.
static func _glyph(ts: TextServer, font_rid: RID, size: int, index: int) -> Array:
	var d: Dictionary = ts.font_get_glyph_contours(font_rid, size, index)
	var out: Array = []
	if d.is_empty() or not d.has("points"):
		return out
	var pts: PackedVector3Array = d.points
	var ends: PackedInt32Array = d.contours
	var start := 0
	for e in ends:
		var contour: Array = []
		for j in range(start, e + 1):
			contour.append(pts[j])
		start = e + 1
		var poly := _flatten(contour)
		if poly.size() >= 3:
			out.append(poly)
	return out


## One contour (points with a tag: 1 on the curve, 0 a control point of a quadratic curve, 2 of a cubic one) as a polygon.
static func _flatten(c: Array) -> PackedVector2Array:
	var n := c.size()
	if n < 3:
		return PackedVector2Array()
	# start on a point of the curve (or half way between two control points)
	var first := -1
	for i in n:
		if (c[i] as Vector3).z == 1.0:
			first = i
			break
	var seq: Array = []
	if first < 0:
		var m: Vector3 = ((c[0] as Vector3) + (c[n - 1] as Vector3)) * 0.5
		m.z = 1.0
		seq.append(m)
		seq.append_array(c)
	else:
		for i in n:
			seq.append(c[(first + i) % n])
	seq.append(seq[0])
	var out := PackedVector2Array()
	var cur := Vector2((seq[0] as Vector3).x, (seq[0] as Vector3).y)
	out.append(_up(cur))
	var i := 1
	while i < seq.size():
		var p: Vector3 = seq[i]
		var pv := Vector2(p.x, p.y)
		if p.z == 1.0:
			cur = pv
			out.append(_up(cur))
			i += 1
		elif p.z == 0.0:  # a quadratic curve
			var nxt: Vector3 = seq[mini(i + 1, seq.size() - 1)]
			var end: Vector2
			if nxt.z == 1.0:
				end = Vector2(nxt.x, nxt.y)
				i += 2
			else:  # two control points in a row: the curve passes half way between them
				end = (pv + Vector2(nxt.x, nxt.y)) * 0.5
				i += 1
			_quad(out, cur, pv, end)
			cur = end
		else:  # a cubic curve: two control points and then the end
			var p2: Vector3 = seq[mini(i + 1, seq.size() - 1)]
			var p3: Vector3 = seq[mini(i + 2, seq.size() - 1)]
			var end3 := Vector2(p3.x, p3.y)
			_cubic(out, cur, pv, Vector2(p2.x, p2.y), end3)
			cur = end3
			i += 3
	# the last point is the first again
	if out.size() > 1 and out[out.size() - 1].distance_to(out[0]) < 0.001:
		out.remove_at(out.size() - 1)
	return _clean(out)


static func _up(p: Vector2) -> Vector2:
	return Vector2(p.x, -p.y)  # (the text server's y points down)


static func _quad(out: PackedVector2Array, a: Vector2, b: Vector2, c: Vector2) -> void:
	var n := clampi(int(ceil((a.distance_to(b) + b.distance_to(c)) / CURVE_PX)), 2, CURVE_MAX)
	for k in range(1, n + 1):
		var t := float(k) / float(n)
		var u := 1.0 - t
		out.append(_up(a * (u * u) + b * (2.0 * u * t) + c * (t * t)))


static func _cubic(out: PackedVector2Array, a: Vector2, b: Vector2, c: Vector2, d: Vector2) -> void:
	var n := clampi(int(ceil((a.distance_to(b) + b.distance_to(c) + c.distance_to(d)) / CURVE_PX)), 2, CURVE_MAX)
	for k in range(1, n + 1):
		var t := float(k) / float(n)
		var u := 1.0 - t
		out.append(_up(a * (u * u * u) + b * (3.0 * u * u * t) + c * (3.0 * u * t * t) + d * (t * t * t)))


## No two neighbouring points the same, and no point that lies on the line between its neighbours.
static func _clean(p: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for v in p:
		if out.is_empty() or out[out.size() - 1].distance_to(v) > 0.01:
			out.append(v)
	if out.size() > 1 and out[0].distance_to(out[out.size() - 1]) <= 0.01:
		out.remove_at(out.size() - 1)
	var changed := true
	while changed and out.size() > 3:
		changed = false
		for i in out.size():
			var a: Vector2 = out[(i + out.size() - 1) % out.size()]
			var b: Vector2 = out[i]
			var c: Vector2 = out[(i + 1) % out.size()]
			if absf((b - a).cross(c - b)) < 0.0004 * maxf(a.distance_to(b), 1.0) and (b - a).dot(c - b) > 0.0:
				out.remove_at(i)
				changed = true
				break
	return out


static func _area(p: PackedVector2Array) -> float:
	var a := 0.0
	for i in p.size():
		a += p[i].cross(p[(i + 1) % p.size()])
	return a * 0.5


static func _bounds(p: PackedVector2Array) -> Rect2:
	var r := Rect2(p[0], Vector2.ZERO)
	for v in p:
		r = r.expand(v)
	return r


## Outer outlines and their holes, from a glyph's contours (outers counter-clockwise, holes clockwise, seen with y up).
static func _shapes(contours: Array) -> Array:
	var outers: Array = []
	var holes: Array = []
	if contours.is_empty():
		return []
	var big := 0.0
	for c in contours:
		if absf(_area(c)) > absf(big):
			big = _area(c)
	for c in contours:
		var a := _area(c)
		if absf(a) < 0.5:
			continue
		var same := (a > 0.0) == (big > 0.0)
		var poly: PackedVector2Array = c
		if same:
			if a < 0.0:
				poly.reverse()
			outers.append(poly)
		else:
			if a > 0.0:
				poly.reverse()
			holes.append(poly)
	var shapes: Array = []
	for o in outers:
		shapes.append({"outer": o, "holes": []})
	for h in holes:
		var best := -1
		var best_area := INF
		for i in outers.size():
			if Geometry2D.is_point_in_polygon(h[0], outers[i]) and absf(_area(outers[i])) < best_area:
				best = i
				best_area = absf(_area(outers[i]))
		if best >= 0:
			(shapes[best].holes as Array).append(h)
	return shapes


# ---------------------------------------------------------------- the front face

## A shape's face as simple polygons: each hole is cut out by splitting the face along the vertical line through the hole
## and subtracting the hole from each half (the hole then opens onto the cut, and nothing is left inside a polygon).
static func _pieces(outer: PackedVector2Array, holes: Array) -> Array:
	var pieces: Array = [outer]
	for h in holes:
		var hb := _bounds(h)
		var xc := (hb.position.x + hb.end.x) * 0.5
		var next: Array = []
		for p in pieces:
			if Geometry2D.intersect_polygons(p, h).is_empty():
				next.append(p)
				continue
			for side in [-1.0, 1.0]:
				var half := PackedVector2Array([Vector2(xc, -BIG), Vector2(xc + side * BIG, -BIG), Vector2(xc + side * BIG, BIG), Vector2(xc, BIG)])
				for q in Geometry2D.intersect_polygons(p, half):
					for r in Geometry2D.clip_polygons(q, h):
						if not Geometry2D.is_polygon_clockwise(r) and absf(_area(r)) > 0.0001:
							next.append(r)
		pieces = next
	return pieces


## Triangles (as index triples into `poly`) of a simple polygon.
static func _triangulate(poly: PackedVector2Array) -> PackedInt32Array:
	if poly.size() < 3:
		return PackedInt32Array()
	return Geometry2D.triangulate_polygon(poly)


# ---------------------------------------------------------------- the solid

## A vertex with its normal and the matching colour, wound so that it faces the way its normals do (Godot's front faces are
## the clockwise ones, so the geometric normal of a front-facing triangle points the other way).
static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, na: Vector3, nb: Vector3, nc: Vector3) -> void:
	var gn := (b - a).cross(c - a)
	var out := na + nb + nc
	if gn.dot(out) > 0.0:
		var t := b
		b = c
		c = t
		var tn := nb
		nb = nc
		nc = tn
	st.set_normal(na)
	st.add_vertex(a)
	st.set_normal(nb)
	st.add_vertex(b)
	st.set_normal(nc)
	st.add_vertex(c)


## The edge normals of a closed contour (pointing away from the solid: to the right of the direction of travel for the
## counter-clockwise outers and the clockwise holes) and the vertex normals (smooth where the edges bend gently, a
## corner where they do not).
static func _normals(c: PackedVector2Array) -> Array:
	var n := c.size()
	var edge: Array = []
	for i in n:
		var e := c[(i + 1) % n] - c[i]
		edge.append(Vector2(e.y, -e.x).normalized())
	return edge


## One solid letter shape (an outline and its holes): walls from z = 0 to depth - bevel, a chamfer, and the front at depth.
static func _solid(st: SurfaceTool, shape: Dictionary, depth: float, bevel: float) -> void:
	var contours: Array = [shape.outer]
	contours.append_array(shape.holes)
	# the chamfer first: it decides the front face
	var front_outer: PackedVector2Array = shape.outer
	var front_holes: Array = []
	var inset: Array = []
	var ok := bevel > 0.0
	if ok:
		for c in contours:
			var ic := _inset(c, bevel)
			if ic.is_empty():
				ok = false
				break
			inset.append(ic)
		if ok:
			var area_o := absf(_area(shape.outer))
			var area_i := _area(inset[0])
			var holes_o := 0.0
			var holes_i := 0.0
			for h in shape.holes:
				holes_o += absf(_area(h))
			for k in range(1, inset.size()):
				holes_i += absf(_area(inset[k]))
			var solid_o := area_o - holes_o
			var solid_i := area_i - holes_i
			# an inset that has turned inside out, or eaten the letter, is no chamfer
			if area_i <= 0.0 or solid_i < 0.25 * solid_o or solid_i > solid_o or _area(inset[0]) < 0.0:
				ok = false
			for k in range(1, inset.size()):
				if _area(inset[k]) > 0.0:
					ok = false
	var z_wall := depth - bevel if ok else depth
	for ci in contours.size():
		var c: PackedVector2Array = contours[ci]
		var n := c.size()
		var edge_n := _normals(c)
		var vn: Array = []
		for i in n:
			var n1: Vector2 = edge_n[(i + n - 1) % n]
			var n2: Vector2 = edge_n[i]
			vn.append((n1 + n2).normalized() if n1.dot(n2) > 0.8 else Vector2.ZERO)
		for i in n:
			var j := (i + 1) % n
			var ne: Vector2 = edge_n[i]
			var na: Vector2 = vn[i] if vn[i] != Vector2.ZERO else ne
			var nb: Vector2 = vn[j] if vn[j] != Vector2.ZERO else ne
			var a0 := Vector3(c[i].x, c[i].y, 0.0)
			var b0 := Vector3(c[j].x, c[j].y, 0.0)
			var a1 := Vector3(c[i].x, c[i].y, z_wall)
			var b1 := Vector3(c[j].x, c[j].y, z_wall)
			var n3a := Vector3(na.x, na.y, 0.0)
			var n3b := Vector3(nb.x, nb.y, 0.0)
			_tri(st, a0, b0, b1, n3a, n3b, n3b)
			_tri(st, a0, b1, a1, n3a, n3b, n3a)
			if ok:
				var ic: PackedVector2Array = inset[ci]
				var a2 := Vector3(ic[i].x, ic[i].y, depth)
				var b2 := Vector3(ic[j].x, ic[j].y, depth)
				var cn := Vector3(ne.x, ne.y, 1.0).normalized()
				_tri(st, a1, b1, b2, cn, cn, cn)
				_tri(st, a1, b2, a2, cn, cn, cn)
	if ok:
		front_outer = inset[0]
		for k in range(1, inset.size()):
			front_holes.append(inset[k])
	for piece in _pieces(front_outer, front_holes):
		var p: PackedVector2Array = piece
		var idx := _triangulate(p)
		var up := Vector3(0, 0, 1)
		for t in range(0, idx.size(), 3):
			_tri(st, Vector3(p[idx[t]].x, p[idx[t]].y, depth), Vector3(p[idx[t + 1]].x, p[idx[t + 1]].y, depth),
				Vector3(p[idx[t + 2]].x, p[idx[t + 2]].y, depth), up, up, up)


## A contour moved `d` towards the solid (it is to the left of the direction of travel), each corner along its miter.
static func _inset(c: PackedVector2Array, d: float) -> PackedVector2Array:
	var n := c.size()
	var out := PackedVector2Array()
	for i in n:
		var a := c[(i + n - 1) % n]
		var b := c[i]
		var e := c[(i + 1) % n]
		var n1 := (b - a).normalized()
		var n2 := (e - b).normalized()
		var l1 := Vector2(-n1.y, n1.x)   # to the left of each edge: into the solid
		var l2 := Vector2(-n2.y, n2.x)
		var m := (l1 + l2)
		var k := 1.0 + l1.dot(l2)
		if k < 0.25:  # a very sharp corner: do not let the miter run away
			m = m.normalized() * 2.0
		else:
			m = m / k
		out.append(b + m * d)
	return out


# ---------------------------------------------------------------- a word

static func _cap_px(ts: TextServer, font: Font) -> float:
	var k := _font_key(font)
	if _cap_cache.has(k):
		return _cap_cache[k]
	var line := TextLine.new()
	line.add_string("H", font, READ_PX)
	var gl: Array = ts.shaped_text_get_glyphs(line.get_rid())
	var cap := READ_PX * 0.7
	if gl.size() > 0:
		var polys := _glyph(ts, gl[0].font_rid, gl[0].font_size, gl[0].index)
		if not polys.is_empty():
			var top := 0.0
			var bottom := 0.0
			var first := true
			for p in polys:
				var b := _bounds(p)
				top = b.end.y if first else maxf(top, b.end.y)
				bottom = b.position.y if first else minf(bottom, b.position.y)
				first = false
			cap = maxf(top - bottom, 1.0)
	_cap_cache[k] = cap
	return cap


static func _build(text: String, font: Font, o: Dictionary) -> Dictionary:
	var cap_m: float = float(o.get("cap", 0.05))
	var depth: float = float(o.get("depth", 0.008))
	var bevel: float = float(o.get("bevel", 0.0))
	var halo: float = float(o.get("halo", 0.0))
	var tracking: float = float(o.get("tracking", 0.0))
	var skew: float = float(o.get("skew", 0.0))
	var bow: float = float(o.get("bow", 0.0))
	var align: int = int(o.get("align", 0))
	var ts := TextServerManager.get_primary_interface()
	var cap_px := _cap_px(ts, font)
	var s := cap_m / cap_px
	var line := TextLine.new()
	line.add_string(text, font, READ_PX)
	var glyphs: Array = ts.shaped_text_get_glyphs(line.get_rid())
	var shapes: Array = []
	var pen := 0.0
	var last_ink := 0.0
	var first_ink := INF
	for g in glyphs:
		var x0: float = pen + (g.offset as Vector2).x
		var contours := _glyph(ts, g.font_rid, int(g.font_size), int(g.index))
		for sh in _shapes(contours):
			shapes.append({"outer": _place(sh.outer, x0, cap_px, s, skew), "holes": (sh.holes as Array).map(func(h: PackedVector2Array) -> PackedVector2Array: return _place(h, x0, cap_px, s, skew))})
			var b := _bounds(sh.outer)
			last_ink = maxf(last_ink, x0 + b.end.x)
			first_ink = minf(first_ink, x0 + b.position.x)
		pen += float(g.advance) + tracking * READ_PX
	if shapes.is_empty():
		var e := ArrayMesh.new()
		return {"mesh": e, "width": 0.0, "cap": cap_m, "tris": 0}
	# the text spans its ink, from the left of its first letter to the right of its last
	var width_px := last_ink - first_ink
	var shift := -first_ink
	if align == 0:
		shift -= width_px * 0.5
	elif align > 0:
		shift -= width_px
	for sh in shapes:
		sh.outer = _shift(sh.outer, shift * s)
		sh.holes = (sh.holes as Array).map(func(h: PackedVector2Array) -> PackedVector2Array: return _shift(h, shift * s))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for sh in shapes:
		_solid(st, sh, depth, bevel)
	var mesh := ArrayMesh.new()
	var tris := 0
	var mid := width_px * s * (0.5 if align < 0 else (-0.5 if align > 0 else 0.0))   # (the bow is about the middle of the word)
	var ar := _finish(st, bow, mid)
	if not ar.is_empty():
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, ar)
		tris += (ar[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	if halo > 0.0:
		var st2 := SurfaceTool.new()
		st2.begin(Mesh.PRIMITIVE_TRIANGLES)
		for sh in shapes:
			_plate(st2, sh, halo)
		var ar2 := _finish(st2, bow, mid)
		if not ar2.is_empty():
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, ar2)
			tris += (ar2[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	return {"mesh": mesh, "width": width_px * s, "cap": cap_m, "tris": tris}


static func _place(p: PackedVector2Array, x0: float, cap_px: float, s: float, skew: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for v in p:
		var y := (v.y - cap_px * 0.5) * s       # (y = 0 in the middle of the capitals)
		var x := (v.x + x0) * s + skew * y
		out.append(Vector2(x, y))
	return out


static func _shift(p: PackedVector2Array, dx: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for v in p:
		out.append(Vector2(v.x + dx, v.y))
	return out


## The flat groove round a shape: its outline grown by `halo`, its holes shrunk, drawn flat at the panel.
static func _plate(st: SurfaceTool, shape: Dictionary, halo: float) -> void:
	var outs: Array = Geometry2D.offset_polygon(shape.outer, halo, Geometry2D.JOIN_ROUND)
	var holes: Array = []
	for h in shape.holes:
		for q in Geometry2D.offset_polygon(h, -halo, Geometry2D.JOIN_ROUND):
			holes.append(q)
	for op in outs:
		var outer: PackedVector2Array = op
		var mine: Array = []
		for h in holes:
			if Geometry2D.is_point_in_polygon(h[0], outer):
				mine.append(h)
		for piece in _pieces(outer, mine):
			var p: PackedVector2Array = piece
			var idx := _triangulate(p)
			var up := Vector3(0, 0, 1)
			for t in range(0, idx.size(), 3):
				_tri(st, Vector3(p[idx[t]].x, p[idx[t]].y, 0.0), Vector3(p[idx[t + 1]].x, p[idx[t + 1]].y, 0.0), Vector3(p[idx[t + 2]].x, p[idx[t + 2]].y, 0.0), up, up, up)


## The arrays of what the SurfaceTool holds, with the panel's bow put in (z += bow * (x - mid)^2, the normals leaning with it).
static func _finish(st: SurfaceTool, bow: float, mid: float) -> Array:
	var ar := st.commit_to_arrays()
	if ar.is_empty() or ar[Mesh.ARRAY_VERTEX] == null or (ar[Mesh.ARRAY_VERTEX] as PackedVector3Array).is_empty():
		return []
	if bow != 0.0:
		var v: PackedVector3Array = ar[Mesh.ARRAY_VERTEX]
		var nrm: PackedVector3Array = ar[Mesh.ARRAY_NORMAL]
		for i in v.size():
			var p := v[i]
			var dx := p.x - mid
			v[i] = Vector3(p.x, p.y, p.z + bow * dx * dx)
			var n := nrm[i]
			nrm[i] = Vector3(n.x - 2.0 * bow * dx * n.z, n.y, n.z + 2.0 * bow * dx * n.x).normalized()
		ar[Mesh.ARRAY_VERTEX] = v
		ar[Mesh.ARRAY_NORMAL] = nrm
	return ar
