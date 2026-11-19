extends SceneTree
## How the traffic brakes, cars in a line on a straight road, no window and no game needed:
##   godot --headless --path . --script tools/traffic_test.gd
## Drives the law every traffic car follows (CarDriver.traffic_driver, accel_step, look_ahead, with the car ahead's brake
## lights read as Game._update_traffic reads them) at 120 steps a second behind scripted cars: a stopped car 400 m ahead,
## a slower one, a car that brakes to a stop (with one car behind it, and with a line of six), a car that pulls in 14 m
## ahead, a stopped one that appears 30 m ahead (and one too close to stop for), an open road. Checks that no car touches
## the one ahead, that a car stops no closer than 3 m behind a stopped one, that the steady braking is never harder than
## it should be (and never harder than a car's tyres give, 9 m/s², even when it has to hurry), that the brake comes on at a
## rate a car's brake can (no jump in how hard it brakes: the old law set the speed to the other car's when it was 60 cm
## off, which was a stop in one step), and that on an open road a car speeds up as it always has (2.2 m/s² at most)
## without overshooting. Exits with a non-zero code if a check fails. (The engine's own notes about objects it was not
## asked to free, printed as it exits, are to be ignored.)

const DT := 1.0 / 120.0
const CAR_L := 4.4

var _fails := 0
var _checks := 0


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_fails += 1
		print("  FAIL: ", what)


## Car 0 is scripted: its speed is lead_v(t) (below 0: it is not there). Cars 1 to n each follow the one before, gap0
## metres behind it (rear to front), all at v0 to begin with, and want to go `want`. With `appear` > 0 car 0 is not
## there until then, and then is appear_gap metres in front of car 1 (n must be 1). Returns the worst of what happened to
## any of the followers, and the last one's.
func _sim(n: int, gap0: float, v0: float, want: float, lead_v: Callable, seconds: float, appear := 0.0, appear_gap := 0.0) -> Dictionary:
	var drv := CarDriver.traffic_driver()
	var z := PackedFloat64Array()   # each car's rear
	var v := PackedFloat64Array()
	var a := PackedFloat64Array()
	for k in n + 1:
		z.append(float(n - k) * (CAR_L + gap0) + 1000.0)
		v.append(v0)
		a.append(0.0)
	var seen := appear <= 0.0
	var r := {"touched": false, "gap_min": 1.0e9, "a_min": 0.0, "a_max": 0.0, "jerk_down": 0.0, "v_max": 0.0, "flicker": 0, "first_brake": -1.0,
		"v": 0.0, "gap_end": 1.0e9}
	var lights: Array = []
	for k in n + 1:
		lights.append(false)
	var t := 0.0
	while t < seconds:
		var lv: float = lead_v.call(t)
		var lv_next: float = lead_v.call(t + DT)
		if not seen and t >= appear:
			seen = true
			z[0] = z[1] + CAR_L + appear_gap
		if seen and lv >= 0.0:
			var acc0 := (lv_next - lv) / DT
			a[0] = acc0
			v[0] = lv
			z[0] += lv * DT
		for k in range(1, n + 1):
			var gap := z[k - 1] - (z[k] + CAR_L)
			var has_lead := (k > 1 or (seen and lv >= 0.0)) and gap <= drv.look_ahead(v[k])
			# (what the car ahead will be doing in half a second, if it is braking, as Game._update_traffic reads it)
			var vc := maxf(v[k - 1] + minf(a[k - 1], 0.0) * 0.5, 0.0)
			var a_new := drv.accel_step(v[k], a[k], want, gap if has_lead else 1.0e9, vc, DT)
			r.jerk_down = minf(r.jerk_down, (a_new - a[k]) / DT)
			a[k] = a_new
			v[k] = maxf(0.0, v[k] + a[k] * DT)
			if v[k] == 0.0 and a[k] < 0.0:
				a[k] = 0.0
			r.a_min = minf(r.a_min, a[k])
			r.a_max = maxf(r.a_max, a[k])
			r.v_max = maxf(r.v_max, v[k])
			z[k] += v[k] * DT
			var g2 := z[k - 1] - (z[k] + CAR_L)
			if k > 1 or (seen and lv >= 0.0):
				r.gap_min = minf(r.gap_min, g2)
				if g2 < 0.0:
					r.touched = true
			if r.first_brake < 0.0 and a[k] < -1.0:
				r.first_brake = t
			var on: bool = a[k] < (-0.4 if lights[k] else -1.0)
			if on != lights[k]:
				r.flicker += 1
			lights[k] = on
		t += DT
	r.v = v[n]
	r.gap_end = (z[n - 1] - (z[n] + CAR_L)) if (n > 1 or seen) else 1.0e9
	return r


func _initialize() -> void:
	_stopped()
	_slower()
	_braking_lead()
	_cut_in()
	_appears()
	_open_road()
	_look()
	print("== %d checks, %d failed" % [_checks, _fails])
	quit(1 if _fails > 0 else 0)


func _stopped() -> void:
	for v0 in [15.0, 22.0, 31.0, 36.0]:
		var r := _sim(1, 400.0, v0, 33.0, func(_t: float) -> float: return 0.0, 60.0)
		# (the stopped car is 400 m ahead: a first gap of 400 m with the lead 0.0 fast; the car is put there by gap0)
		var tag := "from %.0f m/s to a stopped car 400 m ahead" % v0
		print("  %s: braking begins at %.1f s, hardest %.2f m/s², quickest onset %.1f m/s³, stops %.1f m behind it, %d brake-light changes" % [tag, r.first_brake, -r.a_min, -r.jerk_down, r.gap_end, r.flicker])
		_check(not r.touched, tag + ": never touches it")
		_check(float(r.v) < 0.05, tag + ": comes to a stop")
		_check(float(r.gap_end) > 3.0 and float(r.gap_end) < 9.0, tag + ": stops 3 to 9 m behind it (%.1f)" % r.gap_end)
		_check(-float(r.a_min) < 3.2, tag + ": the steady braking is never harder than 3.2 m/s² (%.2f)" % -r.a_min)
		_check(-float(r.jerk_down) <= 12.0, tag + ": the brake comes on at no more than 12 m/s³ (%.1f)" % -r.jerk_down)
		if v0 <= 31.0:  # (a car at 36 m/s sees the car 320 m off, the most it looks, with the steady braking only just wanted, and lifts and brakes again once)
			_check(r.flicker <= 2, tag + ": the brake lights come on once and go off once (%d changes)" % r.flicker)


func _slower() -> void:
	for tri in [[31.0, 20.0, 150.0], [28.0, 18.5, 60.0], [24.0, 20.5, 40.0]]:
		var v0: float = tri[0]
		var vl: float = tri[1]
		var g0: float = tri[2]
		var r := _sim(1, g0, v0, v0 + 2.0, func(_t: float) -> float: return vl, 90.0)
		var tag := "%.0f m/s behind a car doing %.1f, %.0f m back" % [v0, vl, g0]
		print("  %s: hardest %.2f m/s², closest %.1f m, ends %.1f m behind at %.1f m/s" % [tag, -r.a_min, r.gap_min, r.gap_end, r.v])
		_check(not r.touched and float(r.gap_min) > 3.0, tag + ": never closer than 3 m (%.1f)" % r.gap_min)
		_check(absf(float(r.v) - vl) < 0.6, tag + ": settles in at its speed (%.2f)" % r.v)
		_check(-float(r.a_min) < 3.2, tag + ": the steady braking is never harder than 3.2 m/s² (%.2f)" % -r.a_min)
		_check(-float(r.jerk_down) <= 12.0, tag + ": the brake comes on at no more than 12 m/s³ (%.1f)" % -r.jerk_down)


func _braking_lead() -> void:
	# the car ahead brakes to a stop at 3 m/s² from 25 m/s, with cars behind it doing the same speed 12 m apart
	for n in [1, 6]:
		var r := _sim(n, 12.0, 25.0, 27.0, func(t: float) -> float: return maxf(0.0, 25.0 - 3.0 * t), 40.0)
		var tag := "behind a car that brakes to a stop at 3 m/s² (%d car%s behind it, 12 m apart at 25 m/s)" % [n, "" if n == 1 else "s"]
		print("  %s: hardest %.2f m/s², quickest onset %.1f m/s³, closest %.1f m" % [tag, -r.a_min, -r.jerk_down, r.gap_min])
		_check(not r.touched and float(r.gap_min) > 1.0, tag + ": nobody touches anybody, nobody closer than 1 m (%.1f)" % r.gap_min)
		_check(float(r.v) < 0.05, tag + ": the last one stops too")
		_check(-float(r.a_min) <= 9.0 + 1e-6, tag + ": never harder than a car's tyres give (%.2f)" % -r.a_min)
		_check(-float(r.jerk_down) <= 46.0, tag + ": the brake comes on at 45 m/s³ at the most (%.1f)" % -r.jerk_down)


func _cut_in() -> void:
	# a car pulls in 14 m ahead of one doing 30 m/s, going 25: the follower has to give way, hard if it must, never on the spot
	var r := _sim(1, 14.0, 30.0, 31.0, func(_t: float) -> float: return 25.0, 30.0)
	print("  a car pulls in 14 m ahead at 25 m/s in front of one doing 30: hardest %.2f m/s², quickest onset %.1f m/s³, closest %.1f m" % [-r.a_min, -r.jerk_down, r.gap_min])
	_check(not r.touched and float(r.gap_min) > 1.0, "a car pulled in front of is never run into (closest %.1f m)" % r.gap_min)
	_check(-float(r.a_min) <= 9.0 + 1e-6, "a car pulled in front of brakes no harder than tyres give (%.2f)" % -r.a_min)
	_check(-float(r.jerk_down) <= 46.0, "a car pulled in front of eases onto the brake, at 45 m/s³ at the most (%.1f)" % -r.jerk_down)


func _appears() -> void:
	# a stopped car comes into view 30 m ahead of one doing 20 m/s (a wreck slid across the lane): it takes 6.7 m/s² to stop
	var r := _sim(1, 400.0, 20.0, 22.0, func(_t: float) -> float: return 0.0, 30.0, 2.0, 30.0)
	print("  a stopped car appears 30 m ahead of one doing 20 m/s: hardest %.2f m/s², quickest onset %.1f m/s³, stops %.1f m behind it" % [-r.a_min, -r.jerk_down, r.gap_end])
	_check(not r.touched and float(r.gap_end) > 0.5, "a stopped car that appears 30 m ahead at 20 m/s is stopped for (%.1f m left)" % r.gap_end)
	_check(-float(r.a_min) <= 9.0 + 1e-6, "...with no more braking than tyres give (%.2f)" % -r.a_min)
	_check(-float(r.jerk_down) <= 46.0, "...the brake coming on at 45 m/s³ at the most, not in one step (%.1f)" % -r.jerk_down)
	# and one that appears too close to stop for (12 m at 20 m/s needs 17 m/s²): it brakes as hard as tyres give, and the
	# game's last-resort rule (the 60 cm rule) is what keeps it from driving through (not tested here: it is in the game)
	var r2 := _sim(1, 400.0, 20.0, 22.0, func(_t: float) -> float: return 0.0, 10.0, 2.0, 12.0)
	_check(-float(r2.a_min) > 8.9 and -float(r2.a_min) <= 9.0 + 1e-6, "a stopped car that appears too close to stop for is braked for with all the car has, no more (%.2f)" % -r2.a_min)


func _open_road() -> void:
	var r := _sim(1, 1.0e8, 0.0, 28.0, func(_t: float) -> float: return -1.0, 40.0)
	print("  an open road from a standstill to 28 m/s: speeds up by %.2f m/s² at most, tops out at %.2f m/s" % [r.a_max, r.v_max])
	_check(float(r.a_max) <= 2.2 + 1e-6, "speeds up by 2.2 m/s² at the most (%.2f)" % r.a_max)
	_check(float(r.v_max) <= 28.05, "does not overshoot the speed it wants (%.2f)" % r.v_max)
	_check(float(r.v) > 27.0, "gets up to it (%.2f after 40 s)" % r.v)
	# a car that wants to go slower than it is (making way for the police) lets off, and not harder than 4.5 m/s²
	var r2 := _sim(1, 1.0e8, 30.0, 12.0, func(_t: float) -> float: return -1.0, 20.0)
	_check(-float(r2.a_min) <= 4.5 + 1e-6 and absf(float(r2.v) - 12.0) < 0.5, "slowing to a pace it was told to: no harder than 4.5 m/s² (%.2f), ends at %.1f" % [-r2.a_min, r2.v])


func _look() -> void:
	var d := CarDriver.traffic_driver()
	_check(d.look_ahead(0.0) == 80.0 and d.look_ahead(60.0) == 320.0, "look_ahead is between 80 and 320 m")
	var ok := true
	var prev := 0.0
	for k in 80:
		var l := d.look_ahead(float(k) * 0.5)
		ok = ok and l >= prev
		prev = l
	_check(ok, "the faster a car goes, the further it looks")
	# far enough to stop with the steady braking: v^2 / (2 b) + the room it keeps, for every speed a traffic car has
	var far_enough := true
	for v in [10.0, 20.0, 25.0, 31.0, 36.0]:
		far_enough = far_enough and d.look_ahead(v) >= v * v / (2.0 * 2.4) + 4.0 + 0.1 * v
	_check(far_enough, "it looks far enough ahead to stop at 2.4 m/s² from any speed up to 36 m/s")
