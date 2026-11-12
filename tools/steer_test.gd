extends SceneTree
## Steering response test, no window needed:
##   godot --headless --path . --script tools/steer_test.gd
## Drives SteerModel and SteerInput with scripted hands (steps, flicks, a tilt
## with sensor noise) and prints how quickly the car answers.


class Car:
	var v := 30.0
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


func _first(out: Array, idx: int, thr: float) -> float:
	for r in out:
		if absf(r[idx]) >= thr:
			return r[0]
	return NAN


## A command the hand ramps up over 60 ms, held.
func _flick(c: Car, feel: Dictionary, target: float, boosted: bool) -> Array:
	var inp := SteerInput.new()
	var out := []
	var t := 0.0
	var dt := 1.0 / 120.0
	while t < 1.5:
		var raw := target * minf(1.0, t / 0.06)
		var cmd := inp.boosted(raw, dt, feel.lead) if boosted else raw
		_step(c, dt, cmd, feel)
		t += dt
		out.append([t, c.x, c.vx, c.yaw])
	return out


## Steer hard one way until a given time, then the other way until the nose
## is back along the road: how long to change lane by 3.7 m.
func _lane_change(v: float, feel: Dictionary, boosted: bool) -> Array:
	var best := [0.0, 0.0, 0.0]
	var best_err := 1e9
	for k in range(5, 80):
		var t1 := k * 0.02
		var c := Car.new()
		c.v = v
		var inp := SteerInput.new()
		var dt := 1.0 / 120.0
		var t := 0.0
		var phase := 0
		while t < 4.0:
			var raw := 1.0
			if phase == 0 and t >= t1:
				phase = 1
			if phase == 1:
				raw = -1.0
				if c.yaw <= 0.0:
					phase = 2
			if phase == 2:
				if absf(c.x - 3.7) < best_err:
					best_err = absf(c.x - 3.7)
					best = [t, c.x, t1]
				break
			var cmd := inp.boosted(raw, dt, feel.lead) if boosted else raw
			_step(c, dt, cmd, feel)
			t += dt
	return best


func _initialize() -> void:
	print("== steering model: the car's answer to a 60 ms flick (time to 3 cm / 25 cm / 1 m sideways) and a 3.7 m lane change")
	for feel_id in SteerModel.FEEL_ORDER:
		var feel := SteerModel.feel(feel_id)
		for v in [20.0, 35.0, 55.0]:
			var row := ""
			for target in [0.25, 0.5, 1.0]:
				var c := Car.new()
				c.v = v
				var out := _flick(c, feel, target, true)
				row += "  c=%.2f: %.3f %.3f %.2f" % [target, _first(out, 1, 0.03), _first(out, 1, 0.25), _first(out, 1, 1.0)]
			var lc := _lane_change(v, feel, true)
			print("%-9s v=%2d |%s | lane change %.2f s (%.2f m)" % [feel_id, v, row, lc[0], lc[1]])

	for with_gyro in [false, true]:
		print("== tilt filter%s: a 12 degree tilt made in 150 ms (min-jerk), the phone's sensor noisy (0.5 degree) at 50 Hz" % (" with the gyroscope" if with_gyro else ""))
		var rng := RandomNumberGenerator.new()
		rng.seed = 7
		var inp := SteerInput.new()
		var dt := 1.0 / 90.0
		var t := 0.0
		var sensor := 0.0
		var spin := 0.0
		var next_sensor := 0.0
		var rows := []
		while t < 1.0:
			if t >= next_sensor:  # the accelerometer and gyroscope report 50 times a second, 30 ms late
				var u := clampf((t - 0.03 - 0.2) / 0.15, 0.0, 1.0)
				var truth := 12.0 * (10.0 * pow(u, 3) - 15.0 * pow(u, 4) + 6.0 * pow(u, 5))
				var rate := 12.0 * (30.0 * pow(u, 2) - 60.0 * pow(u, 3) + 30.0 * pow(u, 4)) / 0.15 if (u > 0.0 and u < 1.0) else 0.0
				sensor = truth + rng.randfn(0.0, 0.5)
				spin = deg_to_rad(rate + rng.randfn(0.0, 1.5)) if with_gyro else 0.0
				next_sensor += 0.02
			var cmd := inp.tilt(deg_to_rad(sensor), dt, spin)
			rows.append([t, cmd])
			t += dt
		var t10 := NAN
		var t90 := NAN
		var peak := 0.0
		var target := SteerInput.dead(12.0 / SteerInput.TILT_FULL, SteerInput.TILT_DEAD / SteerInput.TILT_FULL)
		for r in rows:
			if is_nan(t10) and r[1] >= 0.1 * target:
				t10 = r[0] - 0.2
			if is_nan(t90) and r[1] >= 0.9 * target:
				t90 = r[0] - 0.2
			peak = maxf(peak, r[1])
		print("  command reaches 10%% of its final value %.0f ms after the hand starts, 90%% after %.0f ms (the hand itself takes 150), overshoot %.0f%%" % [t10 * 1000.0, t90 * 1000.0, (peak / target - 1.0) * 100.0])
		# jitter while the hand is still
		inp.reset()
		var worst := 0.0
		var sum_sq := 0.0
		var n := 0
		t = 0.0
		next_sensor = 0.0
		while t < 4.0:
			if t >= next_sensor:
				sensor = rng.randfn(0.0, 0.5) + 0.3 * sin(t * TAU * 8.0)  # sensor noise and a little hand tremor
				spin = deg_to_rad(rng.randfn(0.0, 1.5) + 0.3 * TAU * 8.0 * cos(t * TAU * 8.0)) if with_gyro else 0.0
				next_sensor += 0.02
			var cmd := inp.tilt(deg_to_rad(sensor), dt, spin)
			if t > 0.5:
				worst = maxf(worst, absf(cmd))
				sum_sq += cmd * cmd
				n += 1
			t += dt
		print("  hand held still: command jitter rms %.4f, worst %.4f (zero means the car drives dead straight)" % [sqrt(sum_sq / n), worst])
	quit()
