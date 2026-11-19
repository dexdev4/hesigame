class_name FloatStick
extends Control
## Floating analog stick: it appears wherever a finger lands (away from the
## pedals and buttons), centred on that spot, and the knob follows the finger.
## Only the sideways push steers. The game feeds it touches; this draws it.

const RADIUS := 86.0  # how far the knob travels for full lock, before Pedal size

var origin := Vector2.ZERO
var knob := Vector2.ZERO  # offset of the knob from the origin, clamped to the radius (for drawing)
var active := false
var heading := 0.0  # which way the car's nose points relative to the road, radians (+ = right)
var load := 0.0     # how much of its grip the car is using, 0 .. 1 (the limit)
var _x := 0.0       # how far the finger is from the origin sideways, clamped to the radius: the steering


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func radius() -> float:
	return RADIUS * float(Save.setting("pedal_scale"))


func press(pos: Vector2) -> void:
	origin = pos
	knob = Vector2.ZERO
	_x = 0.0
	active = true
	queue_redraw()


func drag(pos: Vector2) -> void:
	var r := radius()
	var off := pos - origin
	if absf(off.x) > r:
		# past the edge the stick follows the finger, so turning back answers at once
		# instead of first having to travel back across the overshoot
		origin.x = pos.x - signf(off.x) * r
		off.x = signf(off.x) * r
	_x = off.x
	knob = Vector2(_x, clampf(off.y, -r, r)).limit_length(r)
	queue_redraw()


func release() -> void:
	active = false
	knob = Vector2.ZERO
	_x = 0.0
	queue_redraw()


## The car's state, drawn on the stick: where its nose points and how hard its
## tyres are working. Only redraws when it changes enough to see.
func set_feel(h: float, l: float) -> void:
	if not active:
		heading = h
		load = l
		return
	if absf(h - heading) > 0.004 or absf(l - load) > 0.02:
		heading = h
		load = l
		queue_redraw()


## -1 (full left) .. 1 (full right), with a small dead zone in the middle (Settings > Dead zones).
func value() -> float:
	if not active:
		return 0.0
	return SteerInput.dead(_x / (radius() * 0.8), float(Save.setting("dz_stick")))  # full lock at four-fifths of the way out


func _draw() -> void:
	if not active:
		return
	var r := radius()
	draw_circle(origin, r + 6.0, Color(0, 0, 0, 0.22))
	# the ring warms from white through amber to red as the tyres reach their limit
	var ring := Color(1, 1, 1, 0.55).lerp(Color(Hud.AMBER, 0.9), smoothstep(0.6, 0.95, load)).lerp(Color("#ff5a3c", 0.95), smoothstep(0.95, 1.2, load))
	draw_arc(origin, r, 0.0, TAU, 48, ring, 3.0 + 3.0 * smoothstep(0.6, 1.1, load), true)
	# the steering axis: only left-right counts
	draw_line(origin - Vector2(r - 12.0, 0), origin + Vector2(r - 12.0, 0), Color(1, 1, 1, 0.25), 2.0)
	# where the car's nose points, on a rail above the ring (clear of the thumb): steer the other
	# way to bring the marker back to the middle
	var hx := clampf(heading / 0.3, -1.0, 1.0) * (r - 12.0)
	var rail := origin + Vector2(0, -(r + 22.0))
	draw_line(rail - Vector2(r - 12.0, 0), rail + Vector2(r - 12.0, 0), Color(0, 0, 0, 0.3), 6.0, true)
	draw_line(rail - Vector2(r - 12.0, 0), rail + Vector2(r - 12.0, 0), Color(1, 1, 1, 0.3), 2.0, true)
	draw_line(rail + Vector2(0, -7), rail + Vector2(0, 7), Color(1, 1, 1, 0.55), 2.0, true)
	var mark := Color(1, 1, 1, 0.8) if absf(heading) < 0.012 else Color(Hud.AMBER, 1.0)
	var tri := PackedVector2Array([rail + Vector2(hx - 10.0, -14.0), rail + Vector2(hx + 10.0, -14.0), rail + Vector2(hx, -1.0)])
	draw_colored_polygon(tri, mark)
	draw_polyline(PackedVector2Array([tri[0], tri[1], tri[2], tri[0]]), Color(0, 0, 0, 0.45), 1.5, true)
	var k := origin + knob
	draw_circle(k, r * 0.42, Color(0.06, 0.07, 0.08, 0.55))
	draw_circle(k, r * 0.38, Color(Hud.AMBER, 0.85))
	draw_circle(k, r * 0.16, Color(1, 1, 1, 0.5))
