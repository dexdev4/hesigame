class_name FloatStick
extends Control
## Floating analog stick: it appears wherever a finger lands (away from the
## pedals and buttons), centred on that spot, and the knob follows the finger.
## Only the sideways push steers. The game feeds it touches; this draws it.

const RADIUS := 86.0  # how far the knob travels for full lock, before Pedal size

var origin := Vector2.ZERO
var knob := Vector2.ZERO  # offset of the knob from the origin, clamped to the radius
var active := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func radius() -> float:
	return RADIUS * float(Save.setting("pedal_scale"))


func press(pos: Vector2) -> void:
	origin = pos
	knob = Vector2.ZERO
	active = true
	queue_redraw()


func drag(pos: Vector2) -> void:
	knob = (pos - origin).limit_length(radius())
	queue_redraw()


func release() -> void:
	active = false
	knob = Vector2.ZERO
	queue_redraw()


## -1 (full left) .. 1 (full right), with a small dead zone in the middle.
func value() -> float:
	if not active:
		return 0.0
	var v := knob.x / (radius() * 0.8)  # full lock at four-fifths of the way out
	return 0.0 if absf(v) < 0.03 else clampf(v, -1.0, 1.0)


func _draw() -> void:
	if not active:
		return
	var r := radius()
	draw_circle(origin, r + 6.0, Color(0, 0, 0, 0.22))
	draw_arc(origin, r, 0.0, TAU, 48, Color(1, 1, 1, 0.55), 3.0, true)
	# the steering axis: only left-right counts
	draw_line(origin - Vector2(r - 12.0, 0), origin + Vector2(r - 12.0, 0), Color(1, 1, 1, 0.25), 2.0)
	var k := origin + knob
	draw_circle(k, r * 0.42, Color(0.06, 0.07, 0.08, 0.55))
	draw_circle(k, r * 0.38, Color(Hud.AMBER, 0.85))
	draw_circle(k, r * 0.16, Color(1, 1, 1, 0.5))
