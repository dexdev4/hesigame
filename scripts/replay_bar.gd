class_name ReplayBar
extends Control
## Replay timeline: the whole recording as a track, the trimmed clip in
## amber between its IN and OUT markers, and a playhead you drag to scrub.

signal scrub(frac: float)

var pos := 0.0     # playhead, 0..1 of the recording
var a := 0.0       # clip start
var b := 1.0       # clip end
var length := 20.0 # seconds in the recording (for the tick marks)
var keys: Array = []  # camera keyframes, 0..1 of the recording

const PAD := 16.0


func _init() -> void:
	custom_minimum_size = Vector2(0, 84)
	mouse_filter = Control.MOUSE_FILTER_STOP
	size_flags_horizontal = Control.SIZE_EXPAND_FILL


func set_state(p: float, ca: float, cb: float, len_s: float) -> void:
	if p != pos or ca != a or cb != b or len_s != length:
		pos = p
		a = ca
		b = cb
		length = len_s
		queue_redraw()


func set_keys(k: Array) -> void:
	if k != keys:
		keys = k
		queue_redraw()


func _x(f: float) -> float:
	return PAD + clampf(f, 0.0, 1.0) * (size.x - PAD * 2.0)


func _draw() -> void:
	var y := size.y * 0.55
	var w := size.x - PAD * 2.0
	draw_rect(Rect2(PAD, y - 6, w, 12), Color(1, 1, 1, 0.2))
	draw_rect(Rect2(_x(a), y - 6, _x(b) - _x(a), 12), Hud.AMBER)
	# a tick every second, taller every five
	var secs := int(length)
	for s in secs + 1:
		var x := _x(float(s) / maxf(length, 0.001))
		var tall := s % 5 == 0
		draw_line(Vector2(x, y + 12), Vector2(x, y + (24 if tall else 17)), Color(1, 1, 1, 0.7 if tall else 0.35), 2.0)
	# IN and OUT markers
	for f in [a, b]:
		var x := _x(f)
		draw_rect(Rect2(x - 2, y - 20, 4, 40), Hud.LINE)
	# camera keyframes: diamonds above the track
	for f in keys:
		var x := _x(float(f))
		var c := Vector2(x, y - 22)
		draw_colored_polygon(PackedVector2Array([c + Vector2(0, -8), c + Vector2(7, 0), c + Vector2(0, 8), c + Vector2(-7, 0)]), Hud.AMBER)
		draw_polyline(PackedVector2Array([c + Vector2(0, -8), c + Vector2(7, 0), c + Vector2(0, 8), c + Vector2(-7, 0), c + Vector2(0, -8)]), Color(0, 0, 0, 0.6), 1.5)
	# playhead
	var px := _x(pos)
	draw_circle(Vector2(px, y), 15.0, Color(0, 0, 0, 0.45))
	draw_circle(Vector2(px, y), 12.0, Hud.LINE)
	draw_circle(Vector2(px, y), 5.0, Hud.TAIL)


func _gui_input(event: InputEvent) -> void:
	var p := Vector2(-1, -1)
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		p = (event as InputEventMouseButton).position
	elif event is InputEventMouseMotion and ((event as InputEventMouseMotion).button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		p = (event as InputEventMouseMotion).position
	if p.x >= 0.0:
		scrub.emit(clampf((p.x - PAD) / maxf(size.x - PAD * 2.0, 1.0), 0.0, 1.0))
		accept_event()
