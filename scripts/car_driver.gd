class_name CarDriver
extends RefCounted
## How a computer-driven car (a boss rival, the police car) finds its way through the traffic the way a good player's
## car would. It looks a few seconds ahead, picks a line through the cars (a place across the road, not only a lane)
## and a speed, and follows them smoothly: sideways it moves along a curve that starts and ends gently (a lane change
## takes about as long as the player's, a second or so), along the road it speeds up and brakes without jolts, and it
## makes up its mind once, early, rather than darting about.
##
## Each planning round (about three a second, spread over a few frames so no frame pays for all of it) tries a handful
## of lines (the lanes, the line it is on, and a line alongside each slower car at the clearance it dares), plays each
## forward for a few seconds against where the other cars will be, and gives it a mark: the road it makes (a line with a
## car in the way makes less), the points it would score passing cars close (if it wants them), and what it costs to
## move over. A line that would hit a car is out. It keeps the line it is on unless another is clearly better.
##
## The cars it looks at are anything with x, z (rear bumper), v, vx, w, l, lane, tlane and reach_h (the Vehicle of
## game.gd, or anything of the sort); the road is the lanes' centres (`lanes`) and how far from the middle a car may go.

# ---- how it drives: set by whoever makes it (CarDriver.set_risk, then anything it wants different: see Game._make_boss_driver and _make_cop_driver)
var lanes: Array = [-5.4, -1.8, 1.8, 5.4]  # across the road, the centre of each lane
var road_half := 6.1             # the furthest from the middle its centre may go
var risk := 0.5                  # 0 careful .. 1 reckless: only for the callers to derive the rest from
var lat_accel := 12.0            # the hardest it moves sideways, m/s² (the player's car does about 14)
var d_min := 1.1                 # the quickest it changes a lane, s
var a_max := 7.0                 # the hardest it speeds up, m/s²
var b_max := 10.0                # the hardest it brakes, m/s²
var b_comf := 6.0                # how hard it will brake to settle in behind a car (it looks ahead so as not to need more)
var arcade_follow := false       # behind a car it keeps its throttle until it must brake (instead of easing off as it closes in)
var free_gain := 0.0             # above 0, on a free road it speeds up flat out until it is within a_max / free_gain m/s of the speed it wants
                                 # and eases on from there (an arcade car), instead of easing up to it all the way (a driver)
var margin_target := 0.8         # the room it leaves alongside a car it passes, m
var margin_hard := 0.2           # the least it will plan to pass with, m
var follow_gap := 4.0            # the closest it follows a car, m, plus follow_t seconds of speed
var follow_t := 0.5
var crash_buf := 1.5             # the room it must have left, m, plus crash_t seconds of the speed it closes at, for a line to count as clear of a car ahead
var crash_t := 0.2
var react_t := 0.8               # and, closing on a slower car, the road it covers in this many seconds at the speed it closes at
                                 # (the room to stop short if that car makes a move it had no warning of)
var pts_weight := 0.05           # metres of road a point of passing score is worth to it (0: it does not care)
var pull_x := 0.0                # a place across the road it would like to be in (pull_w metres of road per metre away from it)
var pull_w := 0.0
var end_speed_w := 0.0           # seconds of road the speed it is left with at the end of a line is worth (so a line that leaves it crawling is not a good one)
var progress_w := 1.0            # how much it values the road a line makes against everything else it weighs (a car that is after something values it more)
var goal_z := 0.0                # a car it is after: where that car's rear end is now,
var goal_v := 0.0                # how fast it goes,
var goal_cap := false            # and (if set) road made beyond it earns nothing: the point is to get up to it, not past it
var edge_x := 1.0e9              # beyond this far from the middle (the outer lanes' edge) there is a cost to drive,
var edge_cost := 0.0             # this many metres of road, as it is not a place to drive but to go round on
var lane_hold := 1.0             # what it costs to be between lanes, metres of road per metre from a lane's centre
var horizon := 4.0               # how far ahead it plans, s (longer when it is slow, to see a gap that is further off in time)
var plan_every := 0.3            # how often it plans, s
var dwell_t := 0.9               # how long it sticks to a move it has begun before it will think of another, s
var min_vlat := 0.8              # the slowest sideways speed it plans a lane change for, m/s (a car that rolls on slowly moves over slowly)
var move_cost := 2.2             # what it costs to move over, metres of road per metre moved
var switch_need := 5.0           # how much better another line must be (metres of road) for it to leave the one it is on
var debug := false               # print what it makes of each round (for the test)
var report_airbag := false       # print each time the last-resort guard steps in (for the test)
var _log := ""
var airbags := 0                 # how many times the last-resort guard had to step in (it should be next to never)
var detail_x := 1.0e9            # print how this line (if it is tried) is played forward (for the test)

# ---- what it is doing
var target_x := 0.0              # where it is heading across the road
var ax := 0.0                    # its sideways acceleration now (what the next curve starts from)
var a_lon := 0.0                 # its acceleration along the road now
var _moving := false             # on a curve now
var _t0 := 0.0                   # when the curve began (on the driver's clock), and how long it takes
var _dur := 1.0
var _x0 := 0.0
var _c3 := 0.0
var _c4 := 0.0
var _c5 := 0.0
var _v0 := 0.0                   # sideways speed and acceleration at the start of the curve
var _a0 := 0.0
var _clock := 0.0
var _plan_in := 0.0              # seconds to the next planning round
var _cands := PackedFloat32Array()
var _cursor := 0
var _best_x := 0.0
var _best_cost := 1.0e18
var _hold_cost := 1.0e18
var _hold_ok := true
var _hold_crash := 0.0           # when the line it is on would hit something, s (0 when it would not)
var _best_crash := 0.0
var _hold_x := 0.0
var _dwell := 0.0                # seconds since the last curve began: it does not change its mind again at once
# the cars it is looking at, taken at the start of a planning round
var _n := 0
var _oz := PackedFloat32Array()
var _ol := PackedFloat32Array()
var _ov := PackedFloat32Array()
var _ox0 := PackedFloat32Array()
var _ox1 := PackedFloat32Array()
var _mg := PackedFloat32Array()
var _inside := PackedByteArray()  # 1 for a car it is already alongside, in its strip of the road, when the round begins (another car ran into it, say)
var _plan_v := 0.0               # the speed it was going when the round began
var _plan_vwant := 0.0
var _plan_h := 4.0               # how far ahead this round looks, s
var _plan_x := 0.0               # ...and where it was, and how it was moving (every line is tried from that, the same
var _plan_z := 0.0               # moment the cars it is looking at were taken at)
var _plan_vx := 0.0
var _plan_ax := 0.0
const STEP := 0.2                # seconds between the moments a line is checked at
var per_frame := 1               # lines tried a frame (so that no frame pays for a whole round of planning)


## How it drives from how much it dares: 0 a careful driver who leaves room and takes the lanes the long way round, 1 a
## reckless one who passes a car with a hand's width to spare, brakes late and hard and goes where the points are.
func set_risk(r: float) -> void:
	risk = clampf(r, 0.0, 1.0)
	lat_accel = lerpf(9.0, 14.0, risk)
	d_min = lerpf(1.4, 1.05, risk)
	a_max = lerpf(5.5, 8.5, risk)
	b_max = lerpf(8.0, 11.0, risk)
	b_comf = lerpf(4.5, 7.0, risk)
	margin_target = lerpf(1.1, 0.22, risk)
	margin_hard = lerpf(0.4, 0.16, risk)
	follow_gap = lerpf(7.0, 2.5, risk)
	follow_t = lerpf(1.0, 0.3, risk)
	react_t = lerpf(1.0, 0.45, risk)
	pts_weight = lerpf(0.015, 0.1, risk)
	move_cost = lerpf(2.6, 1.2, risk)
	switch_need = lerpf(6.0, 3.0, risk)


## Forget what it was doing (it has been put somewhere else).
func reset(me) -> void:
	_moving = false
	target_x = me.x
	ax = 0.0
	a_lon = 0.0
	_cands.clear()
	_cursor = 0
	_plan_in = 0.0
	_dwell = 0.0


## One frame of driving `me` (its x, z, v, vx, lane, tlane and braking are set) among `others`.
## v_want: the speed it would like to go.
func step(me, others: Array, dt: float, v_want: float) -> void:
	_clock += dt
	_dwell += dt
	_plan_in -= dt
	if _cands.is_empty() and _plan_in <= 0.0:
		_begin(me, others, v_want)
	if not _cands.is_empty():
		var upto := mini(_cursor + per_frame, _cands.size())
		while _cursor < upto:
			_try(me, _cands[_cursor])
			_cursor += 1
		if _cursor >= _cands.size():
			_commit(me)
	var x_prev: float = me.x
	var z_prev: float = me.z
	_follow(me)
	_drive(me, others, dt, v_want)
	_airbag(me, others, x_prev, z_prev)
	me.lane = _nearest_lane(me.x)
	me.tlane = _nearest_lane(target_x)


func _nearest_lane(x: float) -> int:
	var k := 0
	for i in lanes.size():
		if absf(float(lanes[i]) - x) < absf(float(lanes[k]) - x):
			k = i
	return k


func _follow(me) -> void:
	if not _moving:
		me.vx = 0.0
		ax = 0.0
		return
	var t := _clock - _t0
	if t >= _dur:
		_moving = false
		me.x = target_x
		me.vx = 0.0
		ax = 0.0
		return
	var t2 := t * t
	var t3 := t2 * t
	me.x = _x0 + _v0 * t + 0.5 * _a0 * t2 + _c3 * t3 + _c4 * t3 * t + _c5 * t3 * t2
	me.vx = _v0 + _a0 * t + 3.0 * _c3 * t2 + 4.0 * _c4 * t3 + 5.0 * _c5 * t3 * t
	ax = _a0 + 6.0 * _c3 * t + 12.0 * _c4 * t2 + 20.0 * _c5 * t3


## Start a curve to xt now.
func _go(me, xt: float) -> void:
	xt = clampf(xt, -road_half, road_half)
	var dx: float = absf(xt - me.x)
	if dx < 0.04 and absf(me.vx) < 0.2:
		target_x = me.x
		_moving = false
		return
	_x0 = me.x
	_v0 = me.vx
	_a0 = ax
	var c := _curve(_x0, _v0, _a0, xt, duration(absf(xt - me.x) + absf(me.vx) * 0.25, me.v))
	_dur = c[0]
	_c3 = c[1]
	_c4 = c[2]
	_c5 = c[3]
	_t0 = _clock
	target_x = xt
	_moving = true
	_dwell = 0.0


## Where a car's rearmost point is: its z, or further back when it is a wreck that has slewed across the road.
func _rear(o) -> float:
	return minf(o.z, o.reach_z)


## Where it will be across the road `ahead` seconds from now if it carries on along its curve.
func _x_at(me, ahead: float) -> float:
	if not _moving:
		return me.x
	var t := _clock - _t0 + ahead
	if t >= _dur:
		return target_x
	var t2 := t * t
	var t3 := t2 * t
	return _x0 + _v0 * t + 0.5 * _a0 * t2 + _c3 * t3 + _c4 * t3 * t + _c5 * t3 * t2


## The strip across the road a car can be in: where it is and, if it is moving over (or about to, it has signalled),
## the road between there and the middle of its lane. Returns [low, high].
func _extent(o) -> Array:
	var hw: float = maxf(o.reach_h, o.w * 0.5)
	var xe: float = o.x
	if o.tlane != o.lane and o.tlane >= 0 and o.tlane < lanes.size():
		xe = float(lanes[o.tlane])
	return [minf(o.x, xe) - hw, maxf(o.x, xe) + hw]


## The last resort: it must never be inside another car. If a move has put it in one, undo what did it: held back
## if it ran up behind the car, kept where it was if it swung into its side. (Planning and braking see to it that
## this is next to never needed; it is here so that the rare case does not show as one car driving through another.)
func _airbag(me, others: Array, x_prev: float, z_prev: float) -> void:
	for o in others:
		if o == me:
			continue
		var orear: float = _rear(o)
		var hw: float = maxf(o.reach_h, o.w * 0.5) + me.w * 0.5
		if absf(o.x - me.x) >= hw - 0.02:
			continue
		if o.z + o.l <= me.z + 0.02 or orear >= me.z + me.l - 0.02:
			continue
		# inside it now. If it was inside it a moment ago, it was the other car that did it: nothing to undo
		if absf(o.x - x_prev) < hw - 0.02 and o.z + o.l > z_prev + 0.02 and orear < z_prev + me.l - 0.02:
			continue
		airbags += 1
		if report_airbag:
			print("      airbag at t=%.2f: ego x %.2f z %.1f v %.1f (was z %.1f x %.2f) a_lon %.1f | car x %.2f [reach %.2f] z %.1f (rear %.1f) l %.1f v %.1f lane %d tlane %d" % [_clock, me.x, me.z, me.v, z_prev, x_prev, a_lon, o.x, o.reach_h, o.z, orear, o.l, o.v, o.lane, o.tlane])
		if z_prev + me.l <= orear + 0.05 and me.z + me.l > orear:
			me.z = orear - me.l - 0.05  # it ran up behind it: held there (and it brakes as hard as it can from here)
			a_lon = -b_max
		else:
			me.x = x_prev  # it swung into its side: kept where it was
			me.vx = 0.0
			ax = 0.0
			_moving = false
			target_x = me.x
			_plan_in = 0.0
		return


# ---------------------------------------------------------------- the curve across the road

## How long a move of dx metres across the road takes at speed v: about as long as a lane change of the player's,
## and longer for a car that is going slowly (it can only move over as fast as it rolls on).
func duration(dx: float, v: float) -> float:
	var vlim := maxf(minf(0.17 * v, 6.5), min_vlat)
	var d := d_min * (0.55 + 0.45 * minf(dx / 3.6, 1.0))
	return maxf(d, maxf(1.875 * dx / vlim, sqrt(5.77 * dx / lat_accel)))


## The curve from where it is (position, sideways speed and acceleration) to rest at xt in about d seconds: a quintic
## that starts and ends gently, so that making up its mind again halfway does not jolt it. Made again, slower, when the
## move would ask more of the car than it can give sideways (a new line taken in the middle of another can). Returns the
## time it takes and the three coefficients.
func _curve(x0: float, v0: float, a0: float, xt: float, d: float) -> PackedFloat64Array:
	var dx := xt - x0
	var a_cap := lat_accel * 1.15
	var c3 := 0.0
	var c4 := 0.0
	var c5 := 0.0
	for attempt in 8:
		var d2 := d * d
		var d3 := d2 * d
		c3 = (20.0 * dx - 12.0 * v0 * d - 3.0 * a0 * d2) / (2.0 * d3)
		c4 = (-30.0 * dx + 16.0 * v0 * d + 3.0 * a0 * d2) / (2.0 * d2 * d2)
		c5 = (12.0 * dx - 6.0 * v0 * d - a0 * d2) / (2.0 * d2 * d3)
		var peak := 0.0
		for k in 17:
			var t := d * float(k) / 16.0
			peak = maxf(peak, absf(a0 + 6.0 * c3 * t + 12.0 * c4 * t * t + 20.0 * c5 * t * t * t))
		if peak <= a_cap:
			break
		d *= clampf(sqrt(peak / a_cap), 1.06, 1.5)
	return PackedFloat64Array([d, c3, c4, c5])


## How hard it speeds up (or eases off) on a free road: the intelligent driver model's free term, which takes it up to
## the speed it wants smoothly and without overshooting; a little over it, it just lifts off.
func _idm_free(v: float, v0: float) -> float:
	if free_gain > 0.0:
		return clampf((v0 - v) * free_gain, -b_comf, a_max)
	if v <= v0:
		return a_max * (1.0 - pow(v / maxf(v0, 1.0), 4.0))
	return -b_comf * clampf((v - v0) / 6.0, 0.0, 1.0)


## What a car `gap` metres ahead going at vc allows it (the most it may speed up by, below zero when it must brake): the
## following term of the intelligent driver model, with the gap it wants worked out from how much braking it takes
## to match the other car's speed (not from its own speed, which would have it braking hard a long way off). It
## wants to be follow_gap and follow_t seconds behind it, plus the road the braking will take. At that distance it
## just holds its speed, and it brakes more the closer it is than that: early and gently, and only as hard as it has to.
func _idm_int(v: float, gap: float, vc: float) -> float:
	var dv := maxf(v - vc, 0.0)
	var s_star := follow_gap + follow_t * (vc + 0.5 * dv) + dv * react_t + dv * dv / (2.0 * b_comf)
	var q := s_star / maxf(gap, 0.1)
	var a := a_max * 0.8 * (1.0 - q * q)
	return 1.0e9 if (arcade_follow and a > 0.0) else a


# ---------------------------------------------------------------- along the road

## Speed up and brake the way the intelligent driver model does (a smooth approach to the speed it wants, early and
## gentle braking behind a slower car, the gap it likes kept to a car it follows), eased in and out by a limit on how
## fast the acceleration may change, and never closer to a car in the way than the room it needs.
func _drive(me, others: Array, dt: float, v_want: float) -> void:
	var a_int := 1.0e9   # (what the cars in its way allow it)
	var hb: float = me.w * 0.5
	var xa: float = me.x
	var xb: float = _x_at(me, 0.6)
	var xc: float = _x_at(me, 1.2)
	for o in others:
		if o == me:
			continue
		var orear: float = _rear(o)
		var olen: float = o.l + (o.z - orear)
		var g: float = orear - (me.z + me.l)
		if g < -olen - 0.5 or g > 160.0:
			continue  # (behind it, or too far ahead to matter yet)
		var ext: Array = _extent(o)
		var lat: float = minf(minf(_gap_to(ext, xa, hb), _gap_to(ext, xb, hb)), _gap_to(ext, xc, hb))
		if lat < margin_hard:
			var vc: float = maxf(o.v, 0.0)
			if g < 0.0:
				if lat < 0.0 and me.v > vc and -g < 0.4 * olen:
					a_int = minf(a_int, -b_comf)  # (it is in the tail of one: it falls back out of it)
				continue  # (alongside: the line it is on is what keeps clear of it, and steering away is what gets it out)
			a_int = minf(a_int, _idm_int(me.v, g, vc))
	var a_t: float = clampf(minf(_idm_free(me.v, v_want), a_int), -b_max, a_max)
	var rate := 14.0 if a_t > a_lon else 45.0  # (it eases onto the throttle, and onto the brake a little quicker)
	a_lon = move_toward(a_lon, a_t, rate * dt)
	var v1: float = maxf(0.0, me.v + a_lon * dt)
	me.braking = a_lon < -1.5
	me.v = v1
	me.z += v1 * dt


# ---------------------------------------------------------------- planning

func _gap_to(ext: Array, x: float, hb: float) -> float:
	return maxf(float(ext[0]) - (x + hb), (x - hb) - float(ext[1]))


func _begin(me, others: Array, v_want: float) -> void:
	_plan_in = plan_every
	_plan_v = me.v
	_plan_vwant = v_want
	_plan_h = clampf(170.0 / maxf(me.v, 12.0), horizon, horizon * 1.75)
	_plan_x = me.x
	_plan_z = me.z
	_plan_vx = me.vx
	_plan_ax = ax
	var look: float = clampf(me.v * _plan_h * 1.1, 90.0, 260.0)
	_n = 0
	_oz.resize(others.size())
	_ol.resize(others.size())
	_ov.resize(others.size())
	_ox0.resize(others.size())
	_ox1.resize(others.size())
	_mg.resize(others.size())
	_inside.resize(others.size())
	for o in others:
		if o == me:
			continue
		var orear: float = _rear(o)
		if o.z + o.l < me.z - 12.0 or orear > me.z + look:
			continue
		var ext: Array = _extent(o)
		_oz[_n] = orear
		_ol[_n] = o.l + (o.z - orear)
		_inside[_n] = 1 if (_gap_to(ext, me.x, me.w * 0.5) < margin_hard + 0.1 and orear < me.z + me.l + 0.3 and orear + _ol[_n] > me.z - 0.3) else 0
		_ov[_n] = maxf(o.v, 0.0)
		_ox0[_n] = ext[0]
		_ox1[_n] = ext[1]
		_n += 1
	if debug:
		var seen_o := ""
		for i in _n:
			if _oz[i] + _ol[i] > me.z - 3.0 and _oz[i] < me.z + 140.0:
				seen_o += "\n          ahead %.0f m (len %.1f) x [%.2f,%.2f] v %.1f" % [_oz[i] - (me.z + me.l), _ol[i], _ox0[i], _ox1[i], _ov[i]]
		print("      look from z %.1f x %.2f v %.1f:%s" % [me.z, me.x, me.v, seen_o])
	# the lines to try: the one it is on, each lane, and a line alongside each of the nearest slower cars
	_cands.clear()
	_hold_x = target_x if _moving else me.x
	_hold_x = clampf(_hold_x, -road_half, road_half)
	_add(_hold_x)
	if pull_w > 0.0:
		_add(pull_x)
	for lx in lanes:
		_add(float(lx))
	var seen := 0
	var order: Array = []
	for i in _n:
		if _oz[i] + _ol[i] > me.z and _ov[i] < me.v + 1.0:
			order.append(i)
	order.sort_custom(func(a: int, b: int) -> bool: return _oz[a] < _oz[b])
	var hb: float = me.w * 0.5
	for i: int in order:
		if seen >= 3 or _cands.size() >= 12:
			break
		_add(_ox0[i] - margin_target - hb)
		_add(_ox1[i] + margin_target + hb)
		seen += 1
	_cursor = 0
	_best_x = _hold_x
	_best_cost = 1.0e18
	_hold_cost = 1.0e18
	_hold_ok = true
	_hold_crash = 0.0
	_best_crash = 0.0


func _add(x: float) -> void:
	x = clampf(x, -road_half, road_half)
	for i in _cands.size():
		if absf(_cands[i] - x) < 0.25:
			return
	_cands.append(x)


## The mark for the line to xt: lower is better.
func _try(me, xt: float) -> void:
	var is_hold := _cursor == 0
	var x0: float = _plan_x
	var dx: float = xt - x0
	var cf: PackedFloat64Array = _curve(x0, _plan_vx, _plan_ax, xt, duration(absf(dx) + absf(_plan_vx) * 0.25, _plan_v))
	var d: float = cf[0]
	var c3: float = cf[1]
	var c4: float = cf[2]
	var c5: float = cf[3]
	var v0: float = _plan_vx
	var a0: float = _plan_ax
	var hb: float = me.w * 0.5
	var lb: float = me.l
	var zb: float = _plan_z
	var ve: float = _plan_v
	var a_s: float = a_lon
	var t := 0.0
	var steps := int(_plan_h / STEP)
	var crash_at := -1.0
	var hardest := 0.0   # the hardest it has to brake along the line
	for i in _n:
		_mg[i] = 99.0
	for k in steps:
		t += STEP
		var xb: float = xt
		if t < d:
			var t2 := t * t
			var t3 := t2 * t
			xb = x0 + v0 * t + 0.5 * a0 * t2 + c3 * t3 + c4 * t3 * t + c5 * t3 * t2
		var a_int := 1.0e9
		for i in _n:
			var zc: float = _oz[i] + _ov[i] * t
			var gap: float = zc - (zb + lb)
			if gap > 200.0 or zc + _ol[i] < zb - 5.0:
				continue
			var lat: float = maxf(_ox0[i] - (xb + hb), (xb - hb) - _ox1[i])
			if lat < margin_hard + 0.1:
				if _inside[i] == 1 and gap < 0.5:
					_mg[i] = minf(_mg[i], lat)  # (already inside its strip of the road: what counts is that it gets clear)
				elif gap >= -0.8:
					# ahead in its way: it must follow, and a plan that only just stops short of it is not one to make
					# (the gap is what is left worst of the moment between two looks, and some more for what no plan foresees)
					a_int = minf(a_int, _idm_int(ve, gap, _ov[i]))
					var closing := maxf(ve - _ov[i], 0.0)
					if gap - 0.5 * STEP * closing < crash_buf + crash_t * closing:
						crash_at = t if crash_at < 0.0 else crash_at
				elif zc + _ol[i] > zb - 0.8:
					crash_at = t if crash_at < 0.0 else crash_at  # side by side, touching
			elif gap < 1.5 and zc + _ol[i] > zb - 1.5:
				_mg[i] = minf(_mg[i], lat)
		if debug and absf(xt - detail_x) < 0.011:
			var nz := -1
			for i in _n:
				if _oz[i] + _ov[i] * t > zb - 2.0 and (nz < 0 or _oz[i] < _oz[nz]):
					nz = i
			print("        step t=%.1f xb=%.2f zb=%.1f ve=%.1f a_int=%.1f | nearest: %s" % [t, xb, zb, ve, a_int, ("z %.1f x [%.2f,%.2f] v %.1f gap %.1f" % [_oz[nz] + _ov[nz] * t, _ox0[nz], _ox1[nz], _ov[nz], _oz[nz] + _ov[nz] * t - zb - lb]) if nz >= 0 else "-"])
		var a: float = clampf(minf(_idm_free(ve, _plan_vwant), a_int), -b_max, a_max)
		a_s = move_toward(a_s, a, (14.0 if a > a_s else 45.0) * STEP)  # (the brake and the throttle take a moment, as they do for real)
		hardest = minf(hardest, a_s)
		var v1: float = maxf(0.0, ve + a_s * STEP)
		zb += (ve + v1) * 0.5 * STEP
		ve = v1
	var made: float = zb - _plan_z
	if goal_cap:
		made = minf(made, maxf(0.0, goal_z - _plan_z + goal_v * t))
	var cost: float = -progress_w * (made + end_speed_w * ve)
	# the score from passing cars close, if it wants it
	var sf: float = pow(maxf(_plan_v, 12.0) / 25.0, 1.5)
	var pts := 0.0
	var shortfall := 0.0
	for i in _n:
		var m: float = _mg[i]
		if m < 90.0:
			if _inside[i] == 0 and _oz[i] + _ov[i] * t + _ol[i] < zb:  # (it is past: that counts)
				if m < 0.35:
					pts += 245.0
				elif m < 1.0:
					pts += 25.0 + 95.0 * (2.0 - m)
				else:
					pts += 25.0
			shortfall += maxf(0.0, margin_target - m)
	cost -= pts_weight * sf * pts
	cost += lerpf(60.0, 6.0, risk) * shortfall
	cost += progress_w * 1.2 * pow(maxf(0.0, -hardest - 4.0), 2.0)  # (a line that has it standing on the brake is a worse one)
	cost += move_cost * absf(dx)
	if not is_hold:
		if _moving and signf(xt - target_x) * signf(target_x - x0) < 0.0:
			cost += 14.0  # (the other way from the way it is going)
		cost += 3.0 if _dwell < dwell_t - 0.1 else 0.0
	var off := 1.0e9
	for lx in lanes:
		off = minf(off, absf(xt - float(lx)))
	cost += lane_hold * off
	if pull_w > 0.0:
		cost += pull_w * absf(xt - pull_x)
	if absf(xt) > road_half - 0.25:
		cost += 6.0  # (the barrier is near)
	if absf(xt) > edge_x:
		cost += edge_cost
	if crash_at >= 0.0:
		cost = 1.0e9 - crash_at * 1000.0
	if debug:
		_log += "  [%.2f:%s%.0f]" % [xt, "X" if crash_at >= 0.0 else "", cost if crash_at < 0.0 else crash_at]
	if is_hold:
		_hold_cost = cost
		_hold_ok = crash_at < 0.0
		_hold_crash = maxf(crash_at, 0.0)
	if cost < _best_cost:
		_best_cost = cost
		_best_x = xt
		_best_crash = maxf(crash_at, 0.0)


## Take the best line, if it is clearly better than the one it is on.
func _commit(me) -> void:
	_cands.clear()
	if debug:
		print("      plan at %.2f: x %.2f z %.1f v %.1f hold %.2f %s best %.2f (%.0f) obstacles %d |%s" % [_clock, me.x, me.z, me.v, _hold_x, "ok" if _hold_ok else "HIT", _best_x, _best_cost, _n, _log])
		_log = ""
	var need := switch_need
	if not _hold_ok:
		need = -1.0e9  # (the line it is on would hit something: any other that does not is better)
	elif _moving and _dwell < dwell_t:
		need = 20.0  # (it has only just made up its mind)
	if not _hold_ok and _best_crash > 0.0 and _best_crash < _hold_crash + 0.8:
		return  # (every line hits something and none holds off for long: it does not dart from one to another)
	if absf(_best_x - _hold_x) > 0.15 and _best_cost < _hold_cost - need:
		_go(me, _best_x)
	elif _moving and not _hold_ok:
		_go(me, _best_x)
