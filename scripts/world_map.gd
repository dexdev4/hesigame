class_name WorldMap
extends Control
## The world map: fifteen cities joined end to end by highways. Open
## highways are drawn in amber, the chosen one brighter and wider, locked
## ones as grey dashes. Tap a highway (or the city it leads to) to choose it.

signal picked(route: int)

var unlocked := 1   # highways open
var selected := 0
var best := {}      # route index (as a string) -> best score
var _t := 0.0

const LAND := Color("#23402f")
const LAND_HI := Color("#2c4d38")
const WATER := Color("#1b3550")
const ROAD_OFF := Color(0.75, 0.78, 0.8, 0.35)
const AMBER := Color("#f5b52e")
const LINE := Color("#f3f5ef")


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true


func _process(delta: float) -> void:
	if is_visible_in_tree():
		_t += delta
		queue_redraw()


## Map area inside the control, keeping the map's 1:1.15 shape.
func _area() -> Rect2:
	var pad := 18.0
	var r := Rect2(Vector2(pad, pad), size - Vector2(pad, pad) * 2.0)
	var want := 1.0 / 1.15  # width / height
	if r.size.x / r.size.y > want:
		var w := r.size.y * want
		r.position.x += (r.size.x - w) / 2.0
		r.size.x = w
	else:
		var h := r.size.x / want
		r.position.y += (r.size.y - h) / 2.0
		r.size.y = h
	return r


func _pt(i: int) -> Vector2:
	var a := _area()
	var p: Vector2 = Data.CITIES[i].pos
	return a.position + p * a.size


func _draw() -> void:
	var a := _area()
	# sea all round, a landmass with a lake and a bay
	draw_rect(Rect2(Vector2.ZERO, size), WATER)
	var land := PackedVector2Array()
	var n := 48
	for k in n:
		var th := TAU * k / n
		var rr := 0.47 + 0.03 * sin(th * 5.0) + 0.02 * sin(th * 11.0 + 1.3)
		land.append(a.position + a.size * (Vector2(0.5, 0.5) + Vector2(cos(th), sin(th)) * Vector2(rr * 1.02, rr)))
	draw_colored_polygon(land, LAND)
	for k in 6:  # hills and forests as soft patches
		var c := a.position + a.size * Vector2(0.2 + 0.13 * k, 0.25 + 0.5 * fmod(k * 0.37, 1.0))
		draw_circle(c, a.size.x * (0.05 + 0.02 * (k % 3)), LAND_HI)
	draw_circle(a.position + a.size * Vector2(0.44, 0.5), a.size.x * 0.06, WATER)  # a lake mid-map
	# grid of faint lat/long lines
	for k in 7:
		var x := a.position.x + a.size.x * k / 6.0
		draw_line(Vector2(x, a.position.y), Vector2(x, a.end.y), Color(1, 1, 1, 0.04), 1.0)
		var y := a.position.y + a.size.y * k / 6.0
		draw_line(Vector2(a.position.x, y), Vector2(a.end.x, y), Color(1, 1, 1, 0.04), 1.0)
	# highways
	var font := get_theme_default_font()
	for i in Data.ROUTES.size():
		var p0 := _pt(i)
		var p1 := _pt(i + 1)
		if i < unlocked:
			var sel := i == selected
			draw_line(p0, p1, Color(0, 0, 0, 0.45), 11.0 if sel else 8.0, true)
			draw_line(p0, p1, AMBER if sel else AMBER.darkened(0.25), 7.0 if sel else 4.5, true)
			if sel:  # a moving dash shows the way you will drive
				var len := p0.distance_to(p1)
				var dir := (p1 - p0) / maxf(len, 1.0)
				var off := fmod(_t * 60.0, 24.0)
				var d := off
				while d < len:
					draw_line(p0 + dir * d, p0 + dir * minf(d + 10.0, len), LINE, 2.5, true)
					d += 24.0
			# route shield at the middle of the road
			var m := (p0 + p1) / 2.0
			var nm: String = Data.ROUTES[i].name
			var tw := font.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
			draw_rect(Rect2(m - Vector2(tw / 2.0 + 6.0, 11.0), Vector2(tw + 12.0, 22.0)), Color("#1b4e9b") if sel else Color("#173f7a"))
			draw_rect(Rect2(m - Vector2(tw / 2.0 + 6.0, 11.0), Vector2(tw + 12.0, 22.0)), LINE, false, 1.5)
			draw_string(font, m + Vector2(-tw / 2.0, 5.0), nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, LINE)
		else:
			var len := p0.distance_to(p1)
			var dir := (p1 - p0) / maxf(len, 1.0)
			var d := 0.0
			while d < len:
				draw_line(p0 + dir * d, p0 + dir * minf(d + 7.0, len), ROAD_OFF, 3.0, true)
				d += 14.0
	# cities
	for i in Data.CITIES.size():
		var p := _pt(i)
		var reached := i <= unlocked  # cities you can drive to
		var on := i == selected or i == selected + 1
		draw_circle(p, 11.0 if on else 8.0, Color(0, 0, 0, 0.5))
		draw_circle(p, 8.0 if on else 6.0, AMBER if on else (LINE if reached else Color(0.6, 0.62, 0.64)))
		if not reached:
			draw_circle(p, 3.0, Color(0.3, 0.32, 0.34))
		var name: String = Data.CITIES[i].name
		var fs := 17 if on else 15
		var w := font.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var lp := p + Vector2(-w / 2.0, -16.0)
		lp.x = clampf(lp.x, 4.0, size.x - w - 4.0)
		draw_string(font, lp + Vector2(1, 1), name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0, 0, 0, 0.7))
		draw_string(font, lp, name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, LINE if reached else Color(0.75, 0.77, 0.78))


func _gui_input(event: InputEvent) -> void:
	var pos := Vector2.INF
	if event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed:
		pos = (event as InputEventScreenTouch).position
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		pos = (event as InputEventMouseButton).position
	if pos == Vector2.INF:
		return
	# nearest highway to the touch (its line, or the city at its far end)
	var best_i := -1
	var best_d := 60.0
	for i in Data.ROUTES.size():
		var p0 := _pt(i)
		var p1 := _pt(i + 1)
		var q := Geometry2D.get_closest_point_to_segment(pos, p0, p1)
		var d := minf(pos.distance_to(q), pos.distance_to(p1))
		if d < best_d:
			best_d = d
			best_i = i
	if best_i >= 0:
		picked.emit(best_i)
		accept_event()
