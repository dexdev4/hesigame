class_name SteerBar
extends Control
## A slim bar for steering by tilting the phone, which has no stick or wheel to
## look at: the white tick is your tilt, the amber marker above it where the
## car's nose points (steer the other way to bring it back to the middle), and
## the track warms from white to amber and red as the tyres reach their limit.

const BAR_SIZE := Vector2(280, 44)

var cmd := 0.0      # the steering the hand is asking for, -1 .. 1
var heading := 0.0  # which way the car's nose points relative to the road, radians (+ = right)
var load := 0.0     # how much of its grip the car is using, 0 .. 1 (the limit)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = BAR_SIZE


## Only redraws when something changes enough to see.
func set_feel(c: float, h: float, l: float) -> void:
	if not visible:
		return
	if absf(c - cmd) > 0.01 or absf(h - heading) > 0.004 or absf(l - load) > 0.02:
		cmd = c
		heading = h
		load = l
		queue_redraw()


func _draw() -> void:
	var half := size.x / 2.0 - 16.0
	var c := Vector2(size.x / 2.0, size.y - 14.0)
	var track := Color(1, 1, 1, 0.3).lerp(Color(Hud.AMBER, 0.9), smoothstep(0.6, 0.95, load)).lerp(Color("#ff5a3c", 0.95), smoothstep(0.95, 1.2, load))
	draw_line(c - Vector2(half, 0), c + Vector2(half, 0), Color(0, 0, 0, 0.35), 11.0, true)
	draw_line(c - Vector2(half, 0), c + Vector2(half, 0), track, 4.0, true)
	draw_line(c + Vector2(0, -10), c + Vector2(0, 10), Color(1, 1, 1, 0.5), 2.0, true)
	# the tilt
	var tx := cmd * half
	draw_line(c + Vector2(tx, -9), c + Vector2(tx, 9), Color(1, 1, 1, 0.95), 5.0, true)
	# the car's nose
	var hx := clampf(heading / 0.3, -1.0, 1.0) * half
	var mark := Color(1, 1, 1, 0.6) if absf(heading) < 0.012 else Color(Hud.AMBER, 0.95)
	draw_colored_polygon(PackedVector2Array([c + Vector2(hx - 8.0, -26.0), c + Vector2(hx + 8.0, -26.0), c + Vector2(hx, -14.0)]), mark)
