class_name WorldMap
extends Control
## The world map, drawn like a road atlas: shaded terrain (shaders/
## map_terrain.gdshader) with coast, rivers, forests and mountains, winding
## highways with route shields, and a little skyline for every city. Open
## highways are amber, the chosen one wider with a moving dash; locked ones
## are thin grey dashes. Tap a highway (or the city it leads to) to choose it.

signal picked(route: int)

var unlocked := 1   # highways open
var selected := 0
var best := {}      # route index (as a string) -> best score
var _t := 0.0
var _terrain: ColorRect
var _overlay: Control
var _paths: Array = []  # per highway: PackedVector2Array in 0..1 map space

const WATER := Color("#17324c")
const AMBER := Color("#f5b52e")
const LINE := Color("#f3f5ef")
const CASING := Color(0.08, 0.07, 0.06, 0.85)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	_terrain = ColorRect.new()
	_terrain.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/map_terrain.gdshader")
	var nh := FastNoiseLite.new()
	nh.seed = 7
	nh.frequency = 0.006
	nh.fractal_octaves = 5
	nh.fractal_gain = 0.5
	var th := NoiseTexture2D.new()
	th.width = 512
	th.height = 512
	th.normalize = true
	th.noise = nh
	var nd := FastNoiseLite.new()
	nd.seed = 21
	nd.frequency = 0.012
	nd.fractal_octaves = 4
	var td := NoiseTexture2D.new()
	td.width = 512
	td.height = 512
	td.seamless = true
	td.normalize = true
	td.noise = nd
	m.set_shader_parameter("height_tex", th)
	m.set_shader_parameter("detail_tex", td)
	var pts := PackedVector2Array()
	for c in Data.CITIES:
		pts.append(c.pos)
	m.set_shader_parameter("cities", pts)
	var cols := PackedColorArray()
	var snow := PackedFloat32Array()
	for r in Data.ROUTES:
		var land: Dictionary = Data.BIOMES[r.biome]
		cols.append((land.grass_a as Color).lerp(land.field, 0.25).lightened(0.08))
		snow.append(1.0 if r.biome == "tundra" else 0.0)
	var v3 := PackedVector3Array()
	for c in cols:
		v3.append(Vector3(c.r, c.g, c.b))
	m.set_shader_parameter("seg_col", v3)
	m.set_shader_parameter("seg_snow", snow)
	_terrain.material = m
	add_child(_terrain)
	_overlay = Control.new()
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)
	_build_paths()
	resized.connect(_fit)
	_fit()


## Winding roads: each highway bends gently between its two cities.
func _build_paths() -> void:
	_paths.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = 404
	for i in Data.ROUTES.size():
		var a: Vector2 = Data.CITIES[i].pos
		var b: Vector2 = Data.CITIES[i + 1].pos
		var n := (b - a).orthogonal().normalized()
		var bend := rng.randf_range(-0.05, 0.05)
		var wig := rng.randf_range(0.006, 0.014)
		var ph := rng.randf() * TAU
		var p := PackedVector2Array()
		var steps := 24
		for k in steps + 1:
			var t := float(k) / steps
			var off := sin(t * PI) * bend + sin(t * TAU * 2.0 + ph) * wig * sin(t * PI)
			p.append(a.lerp(b, t) + n * off)
		_paths.append(p)


func _fit() -> void:
	var a := _area()
	_terrain.position = a.position
	_terrain.size = a.size
	_overlay.queue_redraw()


func _process(delta: float) -> void:
	if is_visible_in_tree():
		_t += delta
		_overlay.queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), WATER)


## Map area inside the control, keeping the map's 1:1.15 shape.
func _area() -> Rect2:
	var pad := 10.0
	var r := Rect2(Vector2(pad, pad), size - Vector2(pad, pad) * 2.0)
	var want := 1.0 / 1.15  # width / height
	if r.size.x / maxf(r.size.y, 1.0) > want:
		var w := r.size.y * want
		r.position.x += (r.size.x - w) / 2.0
		r.size.x = w
	else:
		var h := r.size.x / want
		r.position.y += (r.size.y - h) / 2.0
		r.size.y = h
	return r


func _to_px(p: Vector2) -> Vector2:
	var a := _area()
	return a.position + p * a.size


func _path_px(i: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in _paths[i]:
		out.append(_to_px(p))
	return out


func _draw_overlay() -> void:
	var a := _area()
	var font := get_theme_default_font()
	var s := clampf(a.size.x / 520.0, 0.7, 1.6)  # scale for line widths and icons
	# neat line round the map
	_overlay.draw_rect(a, Color(0.95, 0.92, 0.84, 0.9), false, 3.0 * s)
	_overlay.draw_rect(a.grow(-6.0 * s), Color(0.1, 0.1, 0.1, 0.5), false, 1.0)
	# highways: dark casing, then the road colour
	for i in Data.ROUTES.size():
		var p := _path_px(i)
		if i < unlocked:
			var sel := i == selected
			_overlay.draw_polyline(p, CASING, (10.0 if sel else 7.0) * s, true)
			_overlay.draw_polyline(p, AMBER if sel else Color("#e3a43a"), (6.0 if sel else 4.0) * s, true)
			_overlay.draw_polyline(p, Color(1, 1, 1, 0.35), 1.0 * s, true)  # centre line
			if sel:
				_dash(p, fmod(_t * 50.0 * s, 22.0 * s), 9.0 * s, 22.0 * s, LINE, 2.4 * s)
		else:
			_overlay.draw_polyline(p, Color(0, 0, 0, 0.35), 4.0 * s, true)
			_dash(p, 0.0, 6.0 * s, 12.0 * s, Color(0.85, 0.85, 0.82, 0.75), 2.2 * s)
	# route shields
	for i in Data.ROUTES.size():
		var p := _path_px(i)
		var m := p[p.size() / 2]
		_shield(m, Data.ROUTES[i].name, i < unlocked, i == selected, s, font)
	# cities: a skyline on a plinth, name in an outlined label
	for i in Data.CITIES.size():
		var c := _to_px(Data.CITIES[i].pos)
		var reached := i <= unlocked
		var on := i == selected or i == selected + 1
		_skyline(c, i, reached, on, s)
		var name: String = Data.CITIES[i].name
		var fs := int((17 if on else 14) * s)
		var w := font.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var lp := c + Vector2(-w / 2.0, 22.0 * s + fs)
		lp.x = clampf(lp.x, a.position.x + 6.0, a.end.x - w - 6.0)
		_overlay.draw_string_outline(font, lp, name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, int(4 * s), Color(0.05, 0.06, 0.07, 0.9))
		_overlay.draw_string(font, lp, name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, (AMBER if on else LINE) if reached else Color(0.78, 0.78, 0.76))
	_compass(a.position + Vector2(a.size.x - 44.0 * s, 48.0 * s), 30.0 * s, font, s)
	_scale_bar(a.position + Vector2(18.0 * s, a.size.y - 22.0 * s), s, font)


func _dash(p: PackedVector2Array, offset: float, on: float, period: float, col: Color, width: float) -> void:
	var walked := 0.0
	for k in p.size() - 1:
		var a := p[k]
		var b := p[k + 1]
		var seg := a.distance_to(b)
		var d := 0.0
		while d < seg:
			var phase := fmod(walked + d - offset + period * 100.0, period)
			if phase < on:
				var e := minf(seg, d + on - phase)
				_overlay.draw_line(a.lerp(b, d / seg), a.lerp(b, e / seg), col, width, true)
				d = e
			else:
				d += period - phase
		walked += seg


## A blue interstate shield with the route number.
func _shield(c: Vector2, text: String, open: bool, sel: bool, s: float, font: Font) -> void:
	var fs := int(13 * s)
	var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var w := tw + 12.0 * s
	var h := 20.0 * s
	var r := Rect2(c - Vector2(w / 2.0, h / 2.0), Vector2(w, h))
	var pts := PackedVector2Array([r.position, r.position + Vector2(w, 0), r.position + Vector2(w, h * 0.7),
		c + Vector2(0, h * 0.75), r.position + Vector2(0, h * 0.7)])
	var fill := Color("#1b4e9b") if open else Color("#5b6068")
	_overlay.draw_colored_polygon(pts, fill.lightened(0.15) if sel else fill)
	var outline := pts.duplicate()
	outline.append(pts[0])
	_overlay.draw_polyline(outline, LINE, 1.5 * s, true)
	_overlay.draw_rect(Rect2(r.position, Vector2(w, 4.0 * s)), Color("#c62828") if open else Color("#777b80"))
	_overlay.draw_string(font, Vector2(c.x - tw / 2.0, c.y + fs * 0.45), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, LINE)


## A small city skyline: towers of different heights (each city its own),
## lit windows once you can drive there, a glow round the chosen route's ends.
func _skyline(c: Vector2, idx: int, reached: bool, on: bool, s: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1000 + idx * 37
	var k := s * (1.25 if on else 1.0)
	if on:
		_overlay.draw_circle(c + Vector2(0, -6.0 * k), 24.0 * k, Color(1.0, 0.75, 0.25, 0.22 + 0.08 * sin(_t * 3.0)))
	# plinth (the city's footprint) and shadow
	_overlay.draw_set_transform(c + Vector2(0, 2.0 * k), 0.0, Vector2(1.0, 0.35))
	_overlay.draw_circle(Vector2.ZERO, 20.0 * k, Color(0, 0, 0, 0.45))
	_overlay.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var n := rng.randi_range(5, 8)
	var total := 34.0 * k
	var x := c.x - total / 2.0
	var base := c.y
	var tallest := -1
	var tall_h := 0.0
	var bw: Array = []
	for b in n:
		bw.append(rng.randf_range(0.7, 1.4))
	var sum := 0.0
	for v in bw:
		sum += v
	var body := Color(0.42, 0.47, 0.56) if reached else Color(0.5, 0.5, 0.5)
	var dark := body.darkened(0.35)
	for b in n:
		var w: float = total * float(bw[b]) / sum
		var centre := 1.0 - absf((x + w / 2.0 - c.x) / (total / 2.0))  # taller in the middle
		var h := (8.0 + rng.randf_range(4.0, 14.0) + centre * 14.0) * k
		if h > tall_h:
			tall_h = h
			tallest = b
		var r := Rect2(x, base - h, w - 1.0 * k, h)
		_overlay.draw_rect(r, body.lightened(rng.randf_range(-0.08, 0.12)))
		_overlay.draw_rect(Rect2(r.position + Vector2(r.size.x * 0.62, 0), Vector2(r.size.x * 0.38, h)), dark)  # shaded side
		if reached:  # lit windows
			var wy := base - h + 3.0 * k
			while wy < base - 3.0 * k:
				var wx := x + 1.5 * k
				while wx < x + w - 3.0 * k:
					if rng.randf() < 0.55:
						_overlay.draw_rect(Rect2(wx, wy, 1.4 * k, 1.6 * k), Color(1.0, 0.86, 0.45, 0.9))
					wx += 3.2 * k
				wy += 3.6 * k
		_overlay.draw_rect(r, Color(0, 0, 0, 0.55), false, 1.0)
		x += w
	# an antenna on the tallest tower
	var tx := c.x - total / 2.0
	for b in tallest:
		tx += total * float(bw[b]) / sum
	var tw: float = total * float(bw[tallest]) / sum
	_overlay.draw_line(Vector2(tx + tw * 0.4, base - tall_h), Vector2(tx + tw * 0.4, base - tall_h - 7.0 * k), Color(0.2, 0.2, 0.22), 1.2 * k)
	_overlay.draw_circle(Vector2(tx + tw * 0.4, base - tall_h - 7.0 * k), 1.6 * k, Color(1.0, 0.25, 0.2) if reached else Color(0.5, 0.5, 0.5))
	if not reached:  # a padlock over cities you can't reach yet
		var lc := c + Vector2(0, -tall_h * 0.5)
		_overlay.draw_rect(Rect2(lc - Vector2(5, 2) * k, Vector2(10, 8) * k), Color(0.15, 0.15, 0.16, 0.9))
		_overlay.draw_arc(lc + Vector2(0, -2.0 * k), 3.5 * k, PI, TAU, 10, Color(0.15, 0.15, 0.16, 0.9), 1.6 * k)


func _compass(c: Vector2, r: float, font: Font, s: float) -> void:
	_overlay.draw_circle(c, r, Color(0.95, 0.92, 0.84, 0.85))
	_overlay.draw_arc(c, r, 0.0, TAU, 32, Color(0.1, 0.1, 0.1, 0.8), 1.5 * s)
	var pts := PackedVector2Array([c + Vector2(0, -r * 0.85), c + Vector2(r * 0.22, 0), c + Vector2(0, r * 0.85), c + Vector2(-r * 0.22, 0)])
	_overlay.draw_colored_polygon(PackedVector2Array([pts[0], pts[1], pts[3]]), Color("#c62828"))
	_overlay.draw_colored_polygon(PackedVector2Array([pts[2], pts[1], pts[3]]), Color(0.2, 0.2, 0.22))
	var fs := int(13 * s)
	_overlay.draw_string(font, c + Vector2(-4.0 * s, -r - 4.0 * s), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.05, 0.05, 0.05))


func _scale_bar(p: Vector2, s: float, font: Font) -> void:
	var seg := 26.0 * s
	for k in 4:
		_overlay.draw_rect(Rect2(p + Vector2(k * seg, 0), Vector2(seg, 6.0 * s)), Color(0.1, 0.1, 0.1) if k % 2 == 0 else Color(0.95, 0.92, 0.84))
	_overlay.draw_rect(Rect2(p, Vector2(seg * 4.0, 6.0 * s)), Color(0.1, 0.1, 0.1), false, 1.0)
	var fs := int(12 * s)
	_overlay.draw_string_outline(font, p + Vector2(0, -4.0 * s), "0      50     100 km", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, int(3 * s), Color(0.05, 0.06, 0.07, 0.9))
	_overlay.draw_string(font, p + Vector2(0, -4.0 * s), "0      50     100 km", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, LINE)


func _gui_input(event: InputEvent) -> void:
	var pos := Vector2.INF
	if event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed:
		pos = (event as InputEventScreenTouch).position
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		pos = (event as InputEventMouseButton).position
	if pos == Vector2.INF:
		return
	# nearest highway to the touch (along its curve, or the city at its far end)
	var best_i := -1
	var best_d := 60.0
	for i in Data.ROUTES.size():
		var p := _path_px(i)
		var d := pos.distance_to(p[p.size() - 1])
		for k in p.size() - 1:
			d = minf(d, pos.distance_to(Geometry2D.get_closest_point_to_segment(pos, p[k], p[k + 1])))
		if d < best_d:
			best_d = d
			best_i = i
	if best_i >= 0:
		picked.emit(best_i)
		accept_event()
