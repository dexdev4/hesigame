extends SceneTree
## The drift tune's car (DriftModel), no window needed:
##   godot --headless --path . --script tools/drift_test.gd
## Drives it with scripted hands and feet and checks that it behaves like a real drift car with CarX-style assists:
## it runs straight and true at highway speed, changes lanes without sliding, slides when you start a drift (a flick
## of the handbrake), holds the slide on the throttle with the assist counter-steering, comes back straight when you
## lift off, and spins without the assist if you do nothing about it. Exits non-zero if a check fails.

var _fails := 0
var _checks := 0


class Car:
	var v := 0.0
	var yaw := 0.0
	var course := 0.0
	var yaw_rate := 0.0
	var steer := 0.0


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_fails += 1
		print("  FAIL: ", what)


## Runs `secs` seconds at 60 Hz; `inputs(t, car) -> [cmd, gas, brk]`. Returns what happened.
func _run(st: Dictionary, v0: float, secs: float, inputs: Callable, assist := true, log_every := 0.0) -> Dictionary:
	var c := Car.new()
	c.v = v0
	var s := DriftModel.state()
	var dt := 1.0 / 60.0
	var t := 0.0
	var out := {"max_beta": 0.0, "drift_t": 0.0, "beta_end": 0.0, "v_end": 0.0, "x": 0.0, "spun": false, "max_yaw": 0.0, "beta_at": {}, "max_course": 0.0, "max_x": 0.0}
	var x := 0.0
	var next_log := 0.0
	while t < secs:
		var inp: Array = inputs.call(t, c)
		DriftModel.drive(c, dt, st, 2.6, float(inp[0]), bool(inp[1]), bool(inp[2]), assist, s)
		x += c.v * sin(c.course) * dt
		out.max_course = maxf(out.max_course, absf(c.course))
		out.max_x = maxf(out.max_x, absf(x))
		var b := absf(DriftModel.angle(c))
		out.max_beta = maxf(out.max_beta, b)
		out.max_yaw = maxf(out.max_yaw, absf(c.yaw))
		if b > deg_to_rad(15.0):
			out.drift_t += dt
		if b > deg_to_rad(80.0):
			out.spun = true
		t += dt
		for mark in [1.0, 2.0, 3.0, 4.0, 5.0, 6.0]:
			if absf(t - mark) < dt * 0.5:
				out.beta_at[mark] = rad_to_deg(DriftModel.angle(c))
		if log_every > 0.0 and t >= next_log:
			next_log += log_every
			print("    t=%.2f v=%.1f beta=%+.1f deg yaw=%+.1f course=%+.1f steer=%+.1f r=%+.2f spin=%.2f thr=%.2f" % [t, c.v, rad_to_deg(DriftModel.angle(c)), rad_to_deg(c.yaw), rad_to_deg(c.course), rad_to_deg(c.steer), c.yaw_rate, s.spin, s.throttle])
	out.beta_end = rad_to_deg(DriftModel.angle(c))
	out.v_end = c.v
	out.x = x
	return out


func _initialize() -> void:
	var car: Dictionary = Data.CARS[0]
	for c in Data.CARS:
		if c.id == "pulse":
			car = c
	var st := CarStats.compute(car)
	print("== the drift tune on the Pulse (grip %.1f, accel %.1f, top %.0f km/h)" % [float(st.grip), float(st.accel), float(st.top) * 3.6])
	# 1. straight and true at highway speed, even nudged
	var r := _run(st, 40.0, 10.0, func(t: float, _c) -> Array: return [0.04 if t < 0.15 else 0.0, true, false])
	print("  40 m/s, a nudge of the wheel and hands off: biggest slide %.2f deg, nose ends %.2f deg off (%.0f m across)" % [rad_to_deg(r.max_beta), r.beta_end, r.x])
	_check(r.max_beta < deg_to_rad(2.0) and absf(r.beta_end) < 0.5, "it runs straight at 40 m/s and a nudge dies away")
	# 2. a lane change at speed does not slide
	r = _run(st, 35.0, 4.0, func(t: float, _c) -> Array: return [0.5 if t < 0.5 else (-0.5 if t < 1.0 else 0.0), true, false])
	print("  lane change at 35 m/s: biggest slide %.1f deg, %.1f m across" % [rad_to_deg(r.max_beta), r.x])
	_check(r.max_beta < deg_to_rad(5.0), "a lane change at speed stays on the tyres' grip")
	_check(absf(r.x) > 1.0, "...and does move it across")
	# 3. a drift: a flick of the handbrake with the wheel turned, then the throttle and hands off: the assist holds it
	# (a driver who keeps the car going down the road while it slides: steers against the line it is curving away on)
	var drift := func(t: float, c) -> Array:
		if t < 0.35:
			return [0.75, false, true]
		if t < 4.0:
			return [clampf(-1.0 * c.course - 0.3 * c.yaw_rate, -0.6, 0.6), true, false]
		return [clampf(-1.0 * c.course - 0.3 * c.yaw_rate, -0.6, 0.6), false, false]
	r = _run(st, 28.0, 7.0, drift, true)
	print("  handbrake flick at 28 m/s, then the throttle, steering to keep it down the road: biggest angle %.0f deg, %.1f s past 15 deg, %s; %.1f deg at 3 s, %.1f deg at 6 s (2 s after lifting off); %.1f m/s at the end" % [
		rad_to_deg(r.max_beta), r.drift_t, "spun" if r.spun else "never spun", float(r.beta_at.get(3.0, 0.0)), float(r.beta_at.get(6.0, 0.0)), r.v_end])
	_check(r.max_beta > deg_to_rad(20.0), "the handbrake starts a slide")
	_check(not r.spun and r.max_beta < deg_to_rad(65.0), "with the assist it never spins round")
	_check(absf(float(r.beta_at.get(6.0, 99.0))) < 8.0, "lifting off brings it back straight within 2 s")
	_check(r.v_end > 12.0, "it keeps going (%.1f m/s)" % r.v_end)
	_check(r.max_course < deg_to_rad(35.0), "a driver can keep it going down the road while it slides (its line strays %.0f deg at most)" % rad_to_deg(r.max_course))
	# 4. the same with no assist and no counter-steer: a real car spins
	r = _run(st, 28.0, 5.0, func(t: float, _c) -> Array: return [0.75, false, true] if t < 0.35 else [0.0, true, false], false)
	print("  the same with no assist and no counter-steer: biggest angle %.0f deg, %s" % [rad_to_deg(r.max_beta), "spun round" if r.spun else "did not spin"])
	_check(r.spun, "without the assist and a hand on the wheel, it spins (it is a real car)")
	# 5. power in a turn: the throttle alone swings the tail out at a modest speed
	r = _run(st, 14.0, 3.0, func(t: float, _c) -> Array: return [0.6, true, false])
	print("  full power in a turn at 14 m/s: biggest angle %.0f deg" % rad_to_deg(r.max_beta))
	_check(r.max_beta > deg_to_rad(12.0), "power in a turn makes the tail step out")
	# 6. from one side to the other: a drift to the right, then a flick into one to the left
	var swap := func(t: float, c) -> Array:
		if t < 0.35:
			return [0.75, false, true]
		if t < 2.0:
			return [clampf(-1.0 * c.course - 0.3 * c.yaw_rate, -0.6, 0.6), true, false]
		if t < 2.45:
			return [-1.0, false, true]
		return [clampf(-1.0 * c.course - 0.3 * c.yaw_rate, -0.6, 0.6), true, false]
	r = _run(st, 28.0, 5.5, swap, true)
	print("  a drift one way, then flicked the other with the handbrake: %.0f deg at 2 s, %.0f deg at 3 s, %.0f deg at 4 s; its line strayed %.0f deg at most" % [float(r.beta_at.get(2.0, 0.0)), float(r.beta_at.get(3.0, 0.0)), float(r.beta_at.get(4.0, 0.0)), rad_to_deg(r.max_course)])
	_check(signf(float(r.beta_at.get(2.0, 0.0))) != signf(float(r.beta_at.get(3.0, 0.0))) and absf(float(r.beta_at.get(3.0, 0.0))) > 10.0, "it can be flicked from one drift into the other")
	_check(r.drift_t > 2.0, "the throttle holds a drift (%.1f s past 15 degrees)" % r.drift_t)
	_check(r.max_course < deg_to_rad(35.0), "...and the driver keeps it going down the road")
	_check(not r.spun, "...without spinning")
	print("== %d checks, %d failed" % [_checks, _fails])
	quit(1 if _fails > 0 else 0)
