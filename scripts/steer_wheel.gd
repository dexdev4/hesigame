class_name SteerWheel
extends Control
## On-screen steering wheel. The game turns it from touch drags (multi-touch
## safe); this control only draws it and reports its hit area.

const MAX_ANGLE := 1.6  # about 92 degrees each way: a short, quick travel

var angle := 0.0:
	set(v):
		if v != angle:
			angle = v
			queue_redraw()
var held := false:
	set(v):
		if v != held:
			held = v
			queue_redraw()
var heading := 0.0  # which way the car's nose points relative to the road, radians (+ = right)
var load := 0.0     # how much of its grip the car is using, 0 .. 1 (the limit)


## The car's state, drawn on the wheel. Only redraws when it changes enough to see.
func set_feel(h: float, l: float) -> void:
	if absf(h - heading) > 0.004 or absf(l - load) > 0.02:
		heading = h
		load = l
		queue_redraw()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func centre() -> Vector2:
	return global_position + size / 2.0


func radius() -> float:
	return minf(size.x, size.y) / 2.0


func hit(pos: Vector2) -> bool:
	return pos.distance_to(centre()) < radius() * 1.2


func _draw() -> void:
	var c := size / 2.0
	var r := radius() - 10.0
	if held:
		draw_circle(c, r + 12.0, Color(0.96, 0.71, 0.18, 0.18))
	# a ring round the wheel that warms to amber and red as the tyres reach their limit
	if load > 0.6:
		var ring := Color(Hud.AMBER, 0.9).lerp(Color("#ff5a3c", 0.95), smoothstep(0.95, 1.2, load))
		draw_arc(c, r + 18.0, 0.0, TAU, 64, Color(ring, ring.a * smoothstep(0.6, 0.95, load)), 3.0 + 3.0 * smoothstep(0.6, 1.1, load), true)
	# where the car's nose points: a marker sliding round the top of the wheel; steer back to bring it to the middle
	var ha := clampf(heading / 0.3, -1.0, 1.0) * 0.8
	var dir := Vector2(sin(ha), -cos(ha))
	var tip := c + dir * (r + 14.0)
	var side := Vector2(dir.y * -1.0, dir.x)
	var mark := Color(1, 1, 1, 0.6) if absf(heading) < 0.012 else Color(Hud.AMBER, 0.95)
	draw_colored_polygon(PackedVector2Array([tip + dir * 12.0 + side * 8.0, tip + dir * 12.0 - side * 8.0, tip]), mark)
	draw_circle(c + Vector2(0, -(r + 14.0)), 2.5, Color(1, 1, 1, 0.4))
	draw_set_transform(c, angle, Vector2.ONE)
	var rim := Color("#1b1e22")
	var trim := Color("#555c64")
	draw_arc(Vector2.ZERO, r, 0, TAU, 64, Color(0, 0, 0, 0.35), 30.0, true)
	draw_arc(Vector2.ZERO, r, 0, TAU, 64, rim, 24.0, true)
	draw_arc(Vector2.ZERO, r + 10.0, 0, TAU, 64, trim, 3.0, true)
	draw_arc(Vector2.ZERO, r - 10.0, 0, TAU, 64, trim, 2.0, true)
	for a in [0.0, PI, PI * 0.5]:  # spokes: left, right, bottom
		var d := Vector2(cos(a), sin(a))
		draw_line(d * r * 0.28, d * (r - 8.0), trim, 16.0, true)
		draw_line(d * r * 0.28, d * (r - 8.0), rim, 10.0, true)
	draw_circle(Vector2.ZERO, r * 0.3, trim)
	draw_circle(Vector2.ZERO, r * 0.26, rim)
	draw_circle(Vector2.ZERO, r * 0.07, Color("#f5b52e"))
	draw_line(Vector2(0, -r - 11.0), Vector2(0, -r + 11.0), Color("#f5b52e"), 8.0, true)  # top-centre marker
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
