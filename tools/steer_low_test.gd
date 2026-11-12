extends SceneTree
## Low-speed steering test, no window needed:
##   godot --headless --path . --script tools/steer_low_test.gd
## A car at a steady speed is given a full (or half) steering command at once and held. Prints how the wheels,
## the nose and the sideways travel answer, to compare with what a real car does at that speed:
##   - the front wheels take a real hand about a second to go from straight to full lock;
##   - the tightest turn a car makes is about 4.5 m in radius (a turn rate of speed / 4.5);
##   - a car turned that hard at 30 km/h is already asking more of its tyres than they give.


class Car:
	var v := 10.0
	var x := 0.0
	var steer := 0.0
	var yaw := 0.0
	var yaw_rate := 0.0
	var course := 0.0
	var vx := 0.0
	var grip := 9.2
	var l := 4.25
	var top := 50.0


func _grip(c: Car) -> float:
	return c.grip * (1.0 - 0.18 * clampf(c.v / c.top, 0.0, 1.2))


func _step(c: Car, dt: float, cmd: float, feel: Dictionary) -> void:
	SteerModel.drive(c, dt, c.v, _grip(c), feel.auth, c.l * 0.6, cmd, false)
	c.vx = c.v * sin(c.course)
	c.x += c.vx * dt


func _initialize() -> void:
	var feel := SteerModel.feel("standard")
	print("== a command of 1.0 (full) and 0.5 held from the start, standard feel; wheel = front-wheel angle (deg), nose = heading (deg), x = sideways travel (m)")
	print("%5s %5s | %-26s | %-28s | %-22s | %s" % ["v", "cmd", "wheel at 0.1 s / 0.3 s / 1 s", "nose at 0.2 s / 0.5 s / 1 s", "x at 0.5 s / 1 s / 2 s", "turn rate at 0.5 s, and the tightest turn's radius"])
	for v in [2.0, 4.0, 6.0, 8.0, 12.0, 16.0, 22.0, 35.0]:
		for cmd in [1.0, 0.5]:
			var c := Car.new()
			c.v = v
			var dt := 1.0 / 120.0
			var t := 0.0
			var snap := {}
			while t < 2.0:
				_step(c, dt, cmd, feel)
				t += dt
				for mark in [0.1, 0.2, 0.3, 0.5, 1.0, 2.0]:
					if not snap.has(mark) and t >= mark:
						snap[mark] = [rad_to_deg(c.steer), rad_to_deg(c.yaw), c.x, c.yaw_rate]
			var rate: float = snap[0.5][3]
			var radius: float = float(v) / maxf(absf(rate), 0.001)
			print("%5.1f %5.1f | %5.1f %5.1f %5.1f          | %5.1f %5.1f %5.1f            | %5.2f %5.2f %5.2f      | %.2f rad/s, radius %.1f m" % [
				v, cmd, snap[0.1][0], snap[0.3][0], snap[1.0][0], snap[0.2][1], snap[0.5][1], snap[1.0][1],
				snap[0.5][2], snap[1.0][2], snap[2.0][2], rate, radius])
	print("== the wheels going from full lock to the other side (time to pass the middle, and to reach 90% of the other lock)")
	for v in [2.0, 8.0, 20.0]:
		var c := Car.new()
		c.v = v
		var dt := 1.0 / 240.0
		for i in 480:
			_step(c, dt, 1.0, feel)
		var a0 := c.steer
		var t := 0.0
		var t_mid := NAN
		var t_far := NAN
		while t < 3.0:
			_step(c, dt, -1.0, feel)
			t += dt
			if is_nan(t_mid) and c.steer <= 0.0:
				t_mid = t
			if is_nan(t_far) and c.steer <= -0.9 * a0:
				t_far = t
		print("  v=%4.1f m/s: from %.1f deg one way: middle after %.2f s, 90%% of the other way after %.2f s" % [v, rad_to_deg(a0), t_mid, t_far])
	quit()
