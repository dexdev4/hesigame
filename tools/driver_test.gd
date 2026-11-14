extends SceneTree
## The computer driver (CarDriver), no window needed:
##   godot --headless --path . --script tools/driver_test.gd
## Drives one car through stand-in traffic (cars that hold a lane at their own speed, follow the car ahead and
## now and then change lane, like the game's) and checks what matters about how it drives: it never touches a car;
## it moves sideways along a smooth curve (the acceleration and jerk of its sideways speed stay inside bounds, no
## jumps, no turning back the way it came at once) and along the road without jolts; it goes round a stopped car in
## its lane, through a gap in a wall of them, and stops short of a wall with none; and in dense traffic it keeps
## the speed up. Prints how it did, and exits with a non-zero code if a check fails.

class Car:
	var x := 0.0
	var z := 0.0
	var v := 0.0
	var vx := 0.0
	var w := 1.9
	var l := 4.5
	var lane := 0
	var tlane := 0
	var reach_h := 0.95
	var reach_z := 0.0
	var braking := false
	var cruise := 25.0
	var sig_t := 0.0
	var lc_t := 5.0
	var stopped := false

const LANES: Array = [-5.4, -1.8, 1.8, 5.4]
const DT := 1.0 / 60.0

var _fails := 0
var _checks := 0
var _rng := RandomNumberGenerator.new()


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_fails += 1
		print("  FAIL: ", what)


func _initialize() -> void:
	_scenario_empty()
	_scenario_stopped_car()
	_scenario_wall_with_gap()
	_scenario_full_wall()
	_scenario_swiped()
	_scenario_traffic()
	print("== cost of a frame of driving in dense traffic: mean %.0f µs, worst %d µs" % [float(_step_sum) / maxf(float(_step_n), 1.0), _step_max])
	_check(_airbags <= 12, "the last-resort guard was needed %d times in all (a handful at most)" % _airbags)
	print("== %d checks, %d failed" % [_checks, _fails])
	quit(1 if _fails > 0 else 0)


func _driver(risk: float) -> CarDriver:
	var d := CarDriver.new()
	d.lanes = LANES
	d.set_risk(risk)
	return d


func _ego(lane: int, z: float, v: float) -> Car:
	var c := _car(lane, z, v)
	c.cruise = 0.0
	return c


func _car(lane: int, z: float, v: float) -> Car:
	var c := Car.new()
	c.lane = lane
	c.tlane = lane
	c.x = LANES[lane]
	c.z = z
	c.v = v
	c.cruise = v
	return c


## What the traffic does in a frame: hold the lane at its speed, slow down behind a car, now and then change lane.
func _traffic_step(cars: Array, ego: Car, dt: float, lane_changes: bool) -> void:
	var everyone: Array = cars.duplicate()
	everyone.append(ego)
	for o: Car in everyone:
		o.reach_z = o.z  # (what the game keeps for every car: how far back it reaches)
	for c: Car in cars:
		if c.stopped:
			continue
		var gap := 1.0e9
		var lead: Car = null
		for o: Car in everyone:
			if o != c and o.z > c.z and o.z - (c.z + c.l) < gap and absf(o.x - c.x) < (o.w + c.w) / 2.0 + 0.35:
				gap = o.z - (c.z + c.l)
				lead = o
		var want := c.cruise
		if lead and gap < 45.0:
			want = minf(want, lead.v + (gap - 9.0) * 0.35)
		var dv := want - c.v
		c.v += minf(dv, 2.2 * dt) if dv > 0.0 else maxf(dv, -(9.0 if gap < 6.0 else 5.0) * dt)
		c.v = maxf(0.0, c.v)
		if lead and gap < 0.6:
			c.v = minf(c.v, lead.v)
		c.z += c.v * dt
		c.vx = 0.0
		if not lane_changes:
			continue
		if c.tlane == c.lane:
			c.lc_t -= dt
			if c.lc_t <= 0.0:
				c.lc_t = _rng.randf_range(4.0, 11.0)
				var nl := c.lane + (-1 if _rng.randf() < 0.5 else 1)
				if nl >= 0 and nl < 4 and _lane_open(c, nl, everyone):
					c.tlane = nl
					c.sig_t = 1.15
		elif c.sig_t > 0.0:
			c.sig_t -= dt
		else:
			var d: float = LANES[c.tlane] - c.x
			var lat := minf(1.9, c.v * 0.14)
			var step := lat * dt * signf(d)
			c.vx = lat * signf(d)
			if absf(d) <= absf(step):
				c.x = LANES[c.tlane]
				c.lane = c.tlane
			else:
				c.x += step


func _lane_open(c: Car, nl: int, everyone: Array) -> bool:
	var lx: float = LANES[nl]
	for o: Car in everyone:
		if o == c:
			continue
		if absf(o.x - lx) < 2.6 or o.tlane == nl:
			# (the game leaves a car such as the boss, or the player, more room behind: it comes up fast)
			var rear := 24.0 if o.stopped == false and o.cruise == 0.0 else 14.0
			if o.z + o.l > c.z - rear and o.z < c.z + c.l + 16.0:
				return false
	return true


class Stats:
	var t := 0.0
	var n := 0
	var vx := 0.0
	var ax := 0.0
	var ax_max := 0.0
	var j2 := 0.0
	var jumps := 0
	var rev := 0
	var sign := 0
	var flip_t := -9.0
	var lc := 0
	var lane := -1
	var v_sum := 0.0
	var v := 0.0
	var a_max := 0.0
	var b_max := 0.0
	var overlaps := 0
	var min_gap := 99.0
	var yaw_rate_max := 0.0
	var yaw := 0.0
	var started := false
	var passed := {}     # car -> closest lateral gap while alongside
	var was_ahead := {}


func _observe(st: Stats, ego: Car, cars: Array) -> void:
	st.t += DT
	if not st.started:
		st.started = true
		st.vx = ego.vx
		st.v = ego.v
		st.lane = ego.lane
		st.yaw = atan2(ego.vx, maxf(ego.v, 1.0))
		return
	var ax := (ego.vx - st.vx) / DT
	var jerk := (ax - st.ax) / DT
	st.ax_max = maxf(st.ax_max, absf(ax))
	st.j2 += jerk * jerk
	st.n += 1
	if absf(ego.vx - st.vx) > 1.5:
		st.jumps += 1
	var sg := int(signf(ego.vx)) if absf(ego.vx) > 0.5 else 0
	if sg != 0 and st.sign != 0 and sg != st.sign and st.t - st.flip_t > 0.05:
		if st.t - st.flip_t < 1.2:
			st.rev += 1
		st.flip_t = st.t
	if sg != 0:
		st.sign = sg
	st.vx = ego.vx
	st.ax = ax
	if ego.lane != st.lane:
		st.lc += 1
		st.lane = ego.lane
	var al := (ego.v - st.v) / DT
	st.a_max = maxf(st.a_max, al)
	st.b_max = maxf(st.b_max, -al)
	st.v = ego.v
	st.v_sum += ego.v * DT
	var yaw := atan2(ego.vx, maxf(ego.v, 1.0))
	st.yaw_rate_max = maxf(st.yaw_rate_max, absf(yaw - st.yaw) / DT)
	st.yaw = yaw
	for c: Car in cars:
		var lat := absf(c.x - ego.x) - (c.w + ego.w) / 2.0
		var overlap_z := c.z < ego.z + ego.l and c.z + c.l > ego.z
		if overlap_z:
			if lat < -0.02:
				st.overlaps += 1
				if st.overlaps == 1 and OS.get_environment("DRIVER_DEBUG") != "":
					print("    first overlap at %.1f s: ego x %.2f z %.1f v %.1f vx %.2f | car x %.2f z %.1f v %.1f vx %.2f lane %d tlane %d sig %.2f" % [st.t, ego.x, ego.z, ego.v, ego.vx, c.x, c.z, c.v, c.vx, c.lane, c.tlane, c.sig_t])
			st.min_gap = minf(st.min_gap, lat)
			st.passed[c] = minf(float(st.passed.get(c, 99.0)), lat)


var _airbags := 0
var _step_n := 0
var _step_sum := 0
var _step_max := 0


func _line(name: String, st: Stats) -> void:
	print("  %-22s %4.0f s  %2d lane changes, mean %.1f m/s, sideways accel max %.1f jerk rms %.0f, %d jumps, %d quick reversals, along: speed up %.1f brake %.1f m/s², yaw rate max %.2f rad/s, overlaps %d, closest %.2f m" % [
		name, st.t, st.lc, st.v_sum / maxf(st.t, 0.01), st.ax_max, sqrt(st.j2 / maxf(float(st.n), 1.0)), st.jumps, st.rev, st.a_max, st.b_max,
		st.yaw_rate_max, st.overlaps, st.min_gap])


## The smoothness every run must keep.
func _smooth(name: String, st: Stats, ax_bound: float) -> void:
	_check(st.overlaps == 0, "%s: it never touched a car (%d frames overlapping)" % [name, st.overlaps])
	_check(st.jumps == 0, "%s: no jumps in its sideways speed (%d)" % [name, st.jumps])
	_check(st.ax_max < ax_bound, "%s: sideways acceleration stays under %.0f m/s² (%.1f)" % [name, ax_bound, st.ax_max])
	_check(st.yaw_rate_max < 1.2, "%s: it never turns faster than 1.2 rad/s (%.2f)" % [name, st.yaw_rate_max])
	_check(st.b_max < 12.5, "%s: it never brakes harder than 12.5 m/s² (%.1f)" % [name, st.b_max])
	_check(st.a_max < 9.0, "%s: it never speeds up harder than 9 m/s² (%.1f)" % [name, st.a_max])


func _run(driver: CarDriver, ego: Car, cars: Array, seconds: float, v_want: float, lane_changes: bool, name: String) -> Stats:
	var st := Stats.new()
	driver.reset(ego)
	for i in int(seconds / DT):
		_traffic_step(cars, ego, DT, lane_changes)
		driver.step(ego, cars, DT, v_want)
		_observe(st, ego, cars)
	_airbags += driver.airbags
	_line(name, st)
	return st


func _scenario_empty() -> void:
	print("== an empty road")
	var ego := _ego(1, 0.0, 30.0)
	var st := _run(_driver(0.7), ego, [], 20.0, 45.0, false, "empty")
	_smooth("empty road", st, 1.0)
	_check(st.lc == 0, "empty road: it holds its lane (%d lane changes)" % st.lc)
	_check(absf(ego.v - 45.0) < 0.6, "empty road: it reaches the speed it wants (%.1f)" % ego.v)


func _scenario_stopped_car() -> void:
	print("== a stopped car in its lane")
	for risk in [0.2, 0.6, 1.0]:
		var ego := _ego(1, 0.0, 42.0)
		var stop := _car(1, 260.0, 0.0)
		stop.stopped = true
		var st := _run(_driver(risk), ego, [stop], 14.0, 45.0, false, "stopped car, risk %.1f" % risk)
		_smooth("stopped car, risk %.1f" % risk, st, 1.35 * lerpf(9.0, 14.0, risk))
		_check(ego.z > stop.z + stop.l, "stopped car, risk %.1f: it got past (%.0f m, the car at %.0f)" % [risk, ego.z, stop.z])
		_check(st.lc >= 1 and st.lc <= 3, "stopped car, risk %.1f: it changed lane (%d times)" % [risk, st.lc])
		_check(st.min_gap >= 0.1, "stopped car, risk %.1f: it passed with room (%.2f m)" % [risk, st.min_gap])


func _scenario_wall_with_gap() -> void:
	print("== a wall of stopped cars with a gap")
	for gap_lane in [0, 2, 3]:
		var cars: Array = []
		for l in 4:
			if l != gap_lane:
				var c := _car(l, 300.0, 0.0)
				c.stopped = true
				cars.append(c)
		var ego := _ego(1, 0.0, 40.0)
		var st := _run(_driver(0.8), ego, cars, 16.0, 45.0, false, "wall, gap in lane %d" % gap_lane)
		_smooth("wall, gap in lane %d" % gap_lane, st, 1.35 * lerpf(9.0, 14.0, 0.8))
		_check(ego.z > 330.0, "wall, gap in lane %d: it went through the gap (%.0f m)" % [gap_lane, ego.z])


func _scenario_full_wall() -> void:
	print("== a wall of stopped cars with no way through")
	var cars: Array = []
	for l in 4:
		var c := _car(l, 300.0, 0.0)
		c.stopped = true
		cars.append(c)
	var ego := _ego(1, 0.0, 40.0)
	var st := _run(_driver(1.0), ego, cars, 20.0, 45.0, false, "wall, no gap")
	_check(st.overlaps == 0, "wall, no gap: it stopped short without touching anything")
	_check(ego.z + ego.l < 300.0, "wall, no gap: it is still short of the wall (%.1f)" % (ego.z + ego.l))
	_check(st.b_max < 12.5, "wall, no gap: it did not brake harder than 12.5 m/s² (%.1f)" % st.b_max)


## Another car moves over onto it (so that they overlap by half a metre): it steers clear, and does not slam the brakes
## (it would only fall back out of the overlap more slowly than the way out sideways) or call on the guard.
func _scenario_swiped() -> void:
	print("== another car runs into its side")
	for risk in [0.3, 0.9]:
		var ego := _ego(2, 0.0, 38.0)
		var other := _car(3, 1.0, 38.0)
		other.cruise = 38.0
		other.x = 3.3  # (1.5 m between their middles: they overlap by 0.4 m)
		var driver := _driver(risk)
		var st := _run(driver, ego, [other], 6.0, 38.0, false, "run into, risk %.1f" % risk)
		_check(st.overlaps < 75, "run into, risk %.1f: it got clear of the car quickly (%d frames inside it)" % [risk, st.overlaps])
		_check(ego.x < other.x - (ego.w + other.w) / 2.0 - 0.1, "run into, risk %.1f: it ended clear of it (%.2f m apart)" % [risk, other.x - ego.x])
		_check(st.jumps == 0, "run into, risk %.1f: no jumps in its sideways speed (%d)" % [risk, st.jumps])
		_check(st.b_max < 6.0, "run into, risk %.1f: it did not slam the brakes (%.1f m/s²)" % [risk, st.b_max])
		_check(driver.airbags == 0, "run into, risk %.1f: the last-resort guard was not needed (%d)" % [risk, driver.airbags])


## Cars at the game's speeds in each lane, as dense as the game makes them at its heaviest.
func _scenario_traffic() -> void:
	print("== dense traffic")
	for risk in [0.2, 0.6, 1.0]:
		var tot_v := 0.0
		var tot_lc := 0
		var worst := {"ax": 0.0, "rev": 0, "b": 0.0}
		var runs := 0
		for seed_v in [11, 12, 13]:
			_rng.seed = seed_v
			var cars: Array = []
			for k in 30:
				var lane := _rng.randi() % 4
				var z := _rng.randf_range(-60.0, 420.0)
				var ok := absf(z) > 30.0 or absf(LANES[lane] - LANES[2]) > 2.0  # (not on top of where it starts)
				for o: Car in cars:
					if absf(o.x - LANES[lane]) < 2.0 and absf(o.z - z) < 14.0:
						ok = false
				if not ok:
					continue
				var c := _car(lane, z, [31.0, 27.5, 24.0, 20.5][lane] + _rng.randf_range(-1.6, 1.6))
				c.lc_t = _rng.randf_range(2.0, 9.0)
				cars.append(c)
			var ego := _ego(2, 0.0, 38.0)
			var st := Stats.new()
			var driver := _driver(risk)
			driver.reset(ego)
			driver.report_airbag = OS.get_environment("DRIVER_AIRBAG") != ""
			var tr0 := OS.get_environment("DRIVER_TRACE").split(":")
			if OS.get_environment("DRIVER_DETAIL") != "":
				driver.detail_x = float(OS.get_environment("DRIVER_DETAIL"))
			driver.debug = tr0.size() == 4 and absf(float(tr0[0]) - risk) < 0.01 and int(tr0[1]) == seed_v
			var lead_tail := 0.0
			for i in int(70.0 / DT):
				_traffic_step(cars, ego, DT, true)
				var t0 := Time.get_ticks_usec()
				driver.step(ego, cars, DT, 50.0)
				var us := Time.get_ticks_usec() - t0
				_step_n += 1
				_step_sum += us
				_step_max = maxi(_step_max, us)
				_observe(st, ego, cars)
				var tr := OS.get_environment("DRIVER_TRACE").split(":")
				if tr.size() == 4:
					driver.debug = absf(float(tr[0]) - risk) < 0.01 and int(tr[1]) == seed_v and st.t >= float(tr[2]) and st.t <= float(tr[3])
				if tr.size() == 4 and absf(float(tr[0]) - risk) < 0.01 and int(tr[1]) == seed_v and st.t >= float(tr[2]) and st.t <= float(tr[3]) and i % 12 == 0:
					var near: Car = null
					for c: Car in cars:
						if c.z + c.l > ego.z and c.z < ego.z + 80.0 and (near == null or c.z < near.z):
							if absf(c.x - ego.x) < 3.4:
								near = c
					if OS.get_environment("DRIVER_CARS") != "":
						for c: Car in cars:
							if c.z + c.l > ego.z and c.z < ego.z + 130.0:
								print("          car lane %d>%d x %.2f z %.1f (gap %.1f) v %.1f sig %.2f" % [c.lane, c.tlane, c.x, c.z, c.z - ego.z - ego.l, c.v, c.sig_t])
					print("      t=%.2f ego x %.2f z %.1f v %.1f vx %.2f a_lon %.1f tgt %.2f | %s" % [st.t, ego.x, ego.z, ego.v, ego.vx, driver.a_lon, driver.target_x,
						("car x %.2f z %.1f (gap %.1f) v %.1f lane %d tlane %d" % [near.x, near.z, near.z - ego.z - ego.l, near.v, near.lane, near.tlane]) if near else "-"])
				# the road is kept populated ahead, the way the game does
				for c: Car in cars.duplicate():
					if c.z < ego.z - 120.0:
						cars.erase(c)
						lead_tail = 1.0
				if i % 30 == 0 and cars.size() < 28:
					var lane2 := _rng.randi() % 4
					var z2 := ego.z + _rng.randf_range(380.0, 440.0)
					var free := true
					for o: Car in cars:
						if absf(o.x - LANES[lane2]) < 2.0 and absf(o.z - z2) < 25.0:
							free = false
					if free:
						var c2 := _car(lane2, z2, [31.0, 27.5, 24.0, 20.5][lane2] + _rng.randf_range(-1.6, 1.6))
						c2.lc_t = _rng.randf_range(2.0, 9.0)
						cars.append(c2)
			_airbags += driver.airbags
			if driver.airbags > 0:
				print("    (the guard stepped in %d times)" % driver.airbags)
			_line("traffic risk %.1f seed %d" % [risk, seed_v], st)
			_smooth("traffic risk %.1f seed %d" % [risk, seed_v], st, 1.35 * lerpf(9.0, 14.0, risk))
			tot_v += st.v_sum / st.t
			tot_lc += st.lc
			runs += 1
			worst.ax = maxf(float(worst.ax), st.ax_max)
			worst.rev = maxi(int(worst.rev), st.rev)
		print("  -> risk %.1f: mean speed %.1f m/s, %.1f lane changes a run" % [risk, tot_v / runs, float(tot_lc) / runs])
		_check(tot_v / runs > 28.0, "traffic risk %.1f: it keeps the speed up (%.1f m/s on average)" % [risk, tot_v / runs])
