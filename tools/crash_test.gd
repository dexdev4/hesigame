extends SceneTree
## Hit boxes and crash physics, no window needed:
##   godot --headless --path . --script tools/crash_test.gd
## Checks HitShape (the outlines really follow the cars, contact is found
## exactly when the outlines overlap and the contact point is where they touch)
## and Wreck (a sliding car brakes and straightens out, a spin dies away in a
## fraction of a turn, an impact conserves momentum, loses energy, and an
## off-centre one spins the car the right way) and prints how long real crash
## scenarios take to play out. Exits with a non-zero code if a check fails.

var _fails := 0
var _checks := 0


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_fails += 1
		print("  FAIL: ", what)


func _near(a: float, b: float, tol: float) -> bool:
	return absf(a - b) <= tol


## A car as a wreck body: the middle at (x, z + l/2)... given as the rear bumper position and heading about the middle.
func _car(id: String, x: float, z: float, yaw := 0.0, vel := Vector2.ZERO) -> Wreck:
	var b := Wreck.make(id)
	b.pos = Vector2(x, z + b.shape.length / 2.0)
	b.yaw = yaw
	b.vel = vel
	return b


func _contact(a: Wreck, b: Wreck) -> Dictionary:
	return HitShape.contact(a.outline(), b.outline())


func _initialize() -> void:
	_hit_shapes()
	_free_motion()
	_impacts()
	_scenarios()
	print("== %d checks, %d failed" % [_checks, _fails])
	quit(1 if _fails > 0 else 0)


# ---------------------------------------------------------------- outlines

func _hit_shapes() -> void:
	print("== hit boxes")
	for id in Data.SHAPES:
		var h := HitShape.of(id)
		var xr := HitShape.x_range(h.world(0.0, 0.0, 0.0))
		var yr := HitShape.y_range(h.world(0.0, 0.0, 0.0))
		var sh: Dictionary = Data.SHAPES[id]
		# the outline is the car: about its width and length (less the pulled-in edge, plus any flare), and symmetric
		_check(absf(xr.x + xr.y) < 0.01, "%s: outline is symmetric (%.3f %.3f)" % [id, xr.x, xr.y])
		_check(_near(xr.y - xr.x, float(sh.w), 0.2), "%s: outline width %.2f is the car's %.2f" % [id, xr.y - xr.x, sh.w])
		_check(_near(yr.y - yr.x, float(sh.l), 0.2 if id != "truck" else 0.3), "%s: outline length %.2f is the car's %.2f" % [id, yr.y - yr.x, sh.l])
		# each part is convex and counter-clockwise
		for part in h.parts:
			var n := part.size()
			var convex := true
			for i in n:
				var a := part[i]
				var b := part[(i + 1) % n]
				var c := part[(i + 2) % n]
				if (b - a).cross(c - b) < -0.0001:
					convex = false
			_check(convex, "%s: outline is convex and counter-clockwise" % id)
	# two cars side by side: touching exactly when their outlines overlap
	var k := HitShape.of("kestrel")
	for gap: float in [-0.3, -0.1, -0.05, 0.05, 0.3]:
		var a := _car("kestrel", 0.0, 0.0)
		var b := _car("kestrel", 1.9 + gap, 0.0)  # centres 1.9 + gap apart: the outline is 1.82 wide (pulled in 0.04 a side)
		var hit := not _contact(a, b).is_empty()
		var ow := k.x_reach(0.0).y * 2.0
		var want: bool = 1.9 + gap < ow
		_check(hit == want, "side by side, centres %.2f apart (outline %.2f wide): contact %s" % [1.9 + gap, ow, hit])
		var g := HitShape.lateral_gap(a.outline(), b.outline())
		_check(_near(g, 1.9 + gap - ow, 0.02), "lateral gap %.3f = %.3f" % [g, 1.9 + gap - ow])
	# the empty corner of a rectangle is not a hit: noses and tails in step
	var a2 := _car("kestrel", 0.0, 0.0)
	var b2 := _car("kestrel", 1.82, 4.1)  # B's tail over A's nose corner: the boxes overlap there, the cars do not
	_check(_contact(a2, b2).is_empty(), "nose corner against tail corner: outlines apart although the boxes overlap")
	# push apart along the normal by the depth and they just touch, whatever the angle
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var bad := 0
	var tested := 0
	var ids := ["kestrel", "van", "truck", "hatch", "suv", "hyper"]
	for i in 400:
		var ia: String = ids[rng.randi() % ids.size()]
		var ib: String = ids[rng.randi() % ids.size()]
		var pa := _car(ia, 0.0, 0.0, rng.randf_range(-PI, PI))
		var pb := _car(ib, rng.randf_range(-3.0, 3.0), rng.randf_range(-4.0, 8.0), rng.randf_range(-PI, PI))
		var c := _contact(pa, pb)
		if c.is_empty():
			continue
		tested += 1
		var n: Vector2 = c.n
		var ok: bool = _near(n.length(), 1.0, 0.001) and float(c.depth) > 0.0
		pb.pos += n * (float(c.depth) + 0.002)
		var again := 0
		while not _contact(pa, pb).is_empty() and again < 4 and (ia == "truck" or ib == "truck"):
			var c2 := _contact(pa, pb)  # the truck is two pieces: it may take a second push to clear the other
			pb.pos += (c2.n as Vector2) * (float(c2.depth) + 0.002)
			again += 1
		ok = ok and _contact(pa, pb).is_empty()
		if not ok:
			bad += 1
	_check(bad == 0 and tested > 40, "pushing apart along the contact normal by its depth always separates (%d of %d overlapping pairs bad)" % [bad, tested])
	# the contact point lies on both outlines
	var off := 0
	for i in 200:
		var pa := _car("sedan", 0.0, 0.0, rng.randf_range(-0.5, 0.5))
		var pb := _car("suv", rng.randf_range(-2.0, 2.0), rng.randf_range(-3.0, 6.0), rng.randf_range(-0.5, 0.5))
		var c := _contact(pa, pb)
		if c.is_empty():
			continue
		for pt: Dictionary in [{"b": pa}, {"b": pb}]:
			var inside := false
			for part in (pt.b as Wreck).outline():
				var dmin := 1e9
				var m := part.size()
				for q in m:
					var e1 := part[q]
					var e2 := part[(q + 1) % m]
					var t := clampf((c.p - e1).dot(e2 - e1) / (e2 - e1).length_squared(), 0.0, 1.0)
					dmin = minf(dmin, (e1 + (e2 - e1) * t).distance_to(c.p))
				inside = inside or Geometry2D.is_point_in_polygon(c.p, part) or dmin < 0.12
			if not inside:
				off += 1
	_check(off == 0, "the contact point is on both cars (%d misses)" % off)
	# a long way down the road (road coordinates run into the tens of thousands): the contact point is still where they touch
	for z0: float in [0.0, 552.0, 24000.0, 90000.0]:
		var pa := _car("sedan", 0.0, z0, 0.0, Vector2(0.0, 30.0))
		var pb := _car("sedan", 0.6, z0 + 4.2, 0.0, Vector2(0.0, 20.0))
		var cz := _contact(pa, pb)
		_check(not cz.is_empty() and absf(cz.p.y - (z0 + 4.45)) < 0.25 and cz.p.x > 0.0 and cz.p.x < 0.8, "contact point %s at z=%.0f (wanted about 0.3, %.2f)" % [str(cz.get("p", "none")), z0, z0 + 4.45])
	# the guardrail
	var half := k.x_reach(0.0).y
	var r := _car("kestrel", 7.8, 0.0, 0.0)  # the car's side reaches 7.8 + 0.9 = 8.7, rail at 8.8: clear
	_check(HitShape.wall_contact(r.outline(), 8.8, 1.0).is_empty(), "car clear of the rail")
	r.pos.x = 8.0
	var wc := HitShape.wall_contact(r.outline(), 8.8, 1.0)
	_check(not wc.is_empty() and _near(wc.depth, 8.0 + half - 8.8, 0.02), "car %.0f cm through the rail: depth %.3f" % [(8.0 + half - 8.8) * 100.0, wc.get("depth", -1.0)])
	var rr := _car("kestrel", 7.7, 0.0, 0.4)  # nose turned towards the rail: the nose corner touches it first
	wc = HitShape.wall_contact(rr.outline(), 8.8, 1.0)
	print("  rail, nose in at 0.4 rad, middle of the car at x=7.7: ", "no contact" if wc.is_empty() else "depth %.2f at y %.2f (the nose is at y %.2f)" % [wc.depth, wc.p.y - rr.pos.y, rr.shape.length / 2.0])


# ---------------------------------------------------------------- free movement

func _run(b: Wreck, secs: float, dt := 1.0 / 60.0) -> Dictionary:
	var t := 0.0
	var yaw0 := b.yaw
	var p0 := b.pos
	var w_max := 0.0
	var t_spin := -1.0  # when it stopped turning
	var t_stop := -1.0
	var e_prev := b.energy()
	var e_grew := 0.0
	while t < secs:
		b.step(dt)
		t += dt
		w_max = maxf(w_max, absf(b.w))
		e_grew = maxf(e_grew, b.energy() - e_prev)
		e_prev = b.energy()
		if t_spin < 0.0 and absf(b.w) < 0.05:
			t_spin = t
		if t_stop < 0.0 and b.vel.length() < 0.05 and absf(b.w) < 0.02:
			t_stop = t
			break
	return {"t_stop": t_stop, "t_spin": t_spin, "turned": b.yaw - yaw0, "dist": b.pos.distance_to(p0), "w_max": w_max, "e_grew": e_grew, "end": b.pos - p0}


func _free_motion() -> void:
	print("== a car sliding on its tyres, with no hit")
	# straight on: it only drags
	var b := _car("sedan", 0.0, 0.0, 0.0, Vector2(0.0, 30.0))
	var res := _run(b, 20.0)
	var a_expect := (Wreck.ROLL_RES + b.brake * b.grip) * Wreck.G
	print("  nose first at 30 m/s: stops in %.1f s over %.0f m (drag %.1f m/s^2 -> %.1f s, %.0f m); never turned (%.3f rad)" % [res.t_stop, res.dist, a_expect, 30.0 / a_expect, 900.0 / (2.0 * a_expect), res.turned])
	_check(res.t_stop > 0.0 and _near(res.dist, 900.0 / (2.0 * a_expect), 20.0), "straight on stops where the drag says")
	_check(absf(res.turned) < 0.01, "straight on it keeps its heading")
	# across its path: the tyres scrub sideways at about 1 g
	b = _car("sedan", 0.0, 0.0, PI / 2.0, Vector2(0.0, 30.0))
	res = _run(b, 20.0)
	var s_expect := b.grip * Wreck.G
	print("  sideways at 30 m/s: stops in %.1f s over %.0f m (scrub %.1f m/s^2 -> %.1f s, %.0f m); turned %.2f rad" % [res.t_stop, res.dist, s_expect, 30.0 / s_expect, 900.0 / (2.0 * s_expect), res.turned])
	_check(res.t_stop > 0.0 and _near(res.dist, 900.0 / (2.0 * s_expect), 8.0), "sideways it scrubs at the tyres' grip")
	_check(absf(res.turned) < 0.15, "sliding sideways it does not start to spin by itself (%.3f rad)" % res.turned)
	# a spin standing still
	for rate: float in [1.5, 3.0]:
		b = _car("sedan", 0.0, 0.0)
		b.w = rate
		res = _run(b, 10.0)
		print("  spinning at %.1f rad/s on the spot: stops turning after %.2f s and %.2f rad (%.2f turns)" % [rate, res.t_spin, res.turned, res.turned / TAU])
		_check(res.t_spin > 0.0 and res.turned < PI, "a %.1f rad/s spin on the spot is over in less than half a turn" % rate)
	# a violent hit: moving and spinning
	for rate: float in [1.0, 2.0, 3.2]:
		b = _car("sedan", 0.0, 0.0, 0.0, Vector2(2.0, 28.0))
		b.w = rate
		res = _run(b, 15.0)
		print("  28 m/s and spinning at %.1f rad/s: spin over after %.2f s, %.2f turns in all; stopped after %.1f s, %.0f m on" % [rate, res.t_spin, res.turned / TAU, res.t_stop, res.dist])
		_check(res.t_stop > 0.0, "it comes to rest")
		_check(absf(res.turned) < TAU * 1.5, "less than a turn and a half in all at %.1f rad/s (%.2f)" % [rate, res.turned / TAU])
		_check(res.e_grew < 0.001, "its energy never grows (%.5f)" % res.e_grew)
	# on its roof
	b = _car("sedan", 0.0, 0.0, 0.0, Vector2(0.0, 30.0))
	b.on_wheels = false
	res = _run(b, 20.0)
	print("  on its roof at 30 m/s: stops in %.1f s over %.0f m" % [res.t_stop, res.dist])
	_check(res.t_stop > 0.0 and res.t_stop < 10.0, "a car on its roof comes to rest")
	# the truck
	b = _car("truck", 0.0, 0.0, 0.0, Vector2(0.0, 20.0))
	b.w = 0.8
	res = _run(b, 20.0)
	print("  truck at 20 m/s turning at 0.8 rad/s: stops in %.1f s over %.0f m, turned %.2f rad" % [res.t_stop, res.dist, res.turned])
	_check(res.t_stop > 0.0, "the truck comes to rest")


# ---------------------------------------------------------------- impacts

func _total_p(a: Wreck, b: Wreck) -> Vector2:
	return a.vel * a.mass + b.vel * b.mass


func _impacts() -> void:
	print("== impacts")
	# a centred rear-end shunt: nobody spins, momentum is conserved, the bounce is the bounce
	var a := _car("sedan", 0.0, 0.0, 0.0, Vector2(0.0, 30.0))
	var b := _car("sedan", 0.0, 4.5, 0.0, Vector2(0.0, 20.0))  # just touching ahead of it
	var c := _contact(a, b)
	_check(not c.is_empty(), "nose into the tail: contact")
	var p0 := _total_p(a, b)
	var e0 := a.energy() + b.energy()
	var j := Wreck.impact(a, b, c.n, c.p, 0.2, 0.25)
	print("  centred rear-end 30 into 20 m/s: speeds %.1f / %.1f m/s after, spin %.3f / %.3f, impulse %.1f" % [a.vel.y, b.vel.y, a.w, b.w, j])
	_check(_near(a.w, 0.0, 0.01) and _near(b.w, 0.0, 0.01), "a centred hit gives no spin")
	_check(_near((_total_p(a, b) - p0).length(), 0.0, 0.001), "momentum is conserved")
	_check(_near(b.vel.y - a.vel.y, 0.2 * 10.0, 0.01), "they part at a fifth of the closing speed")
	_check(a.energy() + b.energy() < e0, "energy is lost")
	# the same, but the front car sits 0.9 m to one side: it is hit on its right rear corner and turns the way the push turns it
	for side: float in [-1.0, 1.0]:
		a = _car("sedan", 0.0, 0.0, 0.0, Vector2(0.0, 30.0))
		b = _car("sedan", side * 0.9, 4.4, 0.0, Vector2(0.0, 20.0))
		c = _contact(a, b)
		_check(not c.is_empty(), "offset rear-end: contact")
		p0 = _total_p(a, b)
		e0 = a.energy() + b.energy()
		j = Wreck.impact(a, b, c.n, c.p, 0.2, 0.25)
		print("  rear-end offset %+.1f m: spin of the struck car %+.2f rad/s, of the striker %+.2f (contact at x %.2f)" % [side * 0.9, b.w, a.w, c.p.x])
		# the striker's nose is on its own right (side +1) and the struck car's tail corner on its left: the push at each
		# end is on the same side of its car's middle, so both are turned clockwise for +1 and anticlockwise for -1
		_check(b.w * side > 0.0, "the struck car is turned by a push on its tail corner (side %+.0f, w %+.2f)" % [side, b.w])
		_check(a.w * side > 0.0, "the striker is turned by the push on its nose (side %+.0f, w %+.2f)" % [side, a.w])
		_check(_near((_total_p(a, b) - p0).length(), 0.0, 0.01), "momentum conserved in the offset hit")
		_check(a.energy() + b.energy() <= e0 + 0.001, "no energy gained")
		_check(absf(b.w) < Wreck.MAX_SPIN and absf(a.w) < Wreck.MAX_SPIN, "spins are below the cap")
	# a side swipe: A moves sideways into the flank of B
	a = _car("sedan", 0.0, 0.0, 0.0, Vector2(2.5, 25.0))
	b = _car("sedan", 1.72, 0.4, 0.0, Vector2(0.0, 25.0))
	c = _contact(a, b)
	_check(not c.is_empty(), "side swipe: contact")
	j = Wreck.impact(a, b, c.n, c.p, 0.2, 0.25)
	print("  side swipe at 2.5 m/s: lateral speeds %.2f / %.2f, spins %+.2f / %+.2f, impulse %.2f" % [a.vel.x, b.vel.x, a.w, b.w, j])
	_check(a.vel.x < 2.5 and b.vel.x > 0.0, "the swipe pushes the other car away and slows the sideways movement")
	_check(a.vel.y < 25.0 + 0.001 and b.vel.y > 24.99, "the paint's friction drags them along, the faster one gives")
	# the truck: a car at 30 m/s into the back of a truck at 18
	a = _car("sedan", 0.0, 0.0, 0.0, Vector2(0.0, 30.0))
	b = _car("truck", 0.0, 4.45, 0.0, Vector2(0.0, 18.0))
	c = _contact(a, b)
	_check(not c.is_empty(), "car into the back of the truck: contact")
	j = Wreck.impact(a, b, c.n, c.p, 0.2, 0.25)
	print("  car at 30 m/s into the back of a truck at 18: car %.1f, truck %.1f m/s afterwards" % [a.vel.y, b.vel.y])
	_check(a.vel.y < 20.0 and b.vel.y > 18.0 and b.vel.y < 22.0, "the car gives up most of its speed, the heavy truck gains a little (momentum shared out by weight)")
	_check(_near(a.vel.y + 3.5 * b.vel.y, 30.0 + 3.5 * 18.0, 0.01), "momentum is conserved with the truck")
	# the guardrail: a car at 29 m/s and 5 degrees into the rail on the right
	a = _car("sedan", 7.0, 0.0, 0.1, Vector2(2.9, 29.0))
	var wc := HitShape.wall_contact(a.outline(), 8.8, 1.0)
	while wc.is_empty():
		a.pos += a.vel * (1.0 / 240.0)
		wc = HitShape.wall_contact(a.outline(), 8.8, 1.0)
	e0 = a.energy()
	j = Wreck.impact(a, null, wc.n, wc.p, 0.25, 0.3)
	print("  rail at 29 m/s, 6 degrees off, nose in: afterwards %.2f across %.2f along, spin %+.2f rad/s (the nose is pushed back to the road), impulse %.2f" % [a.vel.x, a.vel.y, a.w, j])
	_check(a.point_vel(wc.p).x <= 0.0, "the corner that hit the rail is moving off it")
	_check(a.w < 0.0, "the rail pushes the nose back towards the road")
	_check(a.vel.y < 29.0 and a.vel.y > 25.0, "it scrapes along it and loses some speed")
	_check(a.energy() < e0, "energy is lost on the rail")
	# a hit is never a net force out of nowhere: a car at rest shoved by a slow one stays calm
	a = _car("sedan", 0.0, 0.0, 0.0, Vector2(0.0, 5.0))
	b = _car("sedan", 0.0, 4.45, 0.0, Vector2(0.0, 0.0))
	c = _contact(a, b)
	j = Wreck.impact(a, b, c.n, c.p, 0.2, 0.25)
	_check(b.vel.y > 0.0 and b.vel.y < 5.0 and absf(b.w) < 0.001, "a nudge only nudges")


# ---------------------------------------------------------------- scenarios, played out

## A crash played out: first impact, then free movement, bodies [a, b] in 60 Hz steps.
func _play(a: Wreck, b: Wreck, secs: float, label: String) -> void:
	var dt := 1.0 / 60.0
	var t := 0.0
	var w_max := 0.0
	var first := -1.0
	var yaw0a := a.yaw
	var yaw0b := b.yaw
	var j_total := 0.0
	var e_start := a.energy() + b.energy()
	var e_grew := 0.0
	var e_prev := e_start
	var hits := 0
	while t < secs:
		a.step(dt)
		b.step(dt)
		var c := _contact(a, b)
		if not c.is_empty():
			Wreck.separate(a, b, c.n, c.depth)
			var j := Wreck.impact(a, b, c.n, c.p, 0.2, 0.25)
			if j > 0.0:
				hits += 1
				j_total += j
				if first < 0.0:
					first = t
		var e := a.energy() + b.energy()
		if first >= 0.0:
			e_grew = maxf(e_grew, e - e_prev)
		e_prev = e
		w_max = maxf(w_max, maxf(absf(a.w), absf(b.w)))
		t += dt
		if t > 0.5 and a.vel.length() < 0.05 and b.vel.length() < 0.05 and absf(a.w) < 0.02 and absf(b.w) < 0.02:
			break
	print("  %s: contact at %.2f s (%d impulses, total %.1f), peak spin %.2f rad/s; at rest after %.1f s; A turned %.0f deg, B %.0f deg" % [
		label, first, hits, j_total, w_max, t, rad_to_deg(a.yaw - yaw0a), rad_to_deg(b.yaw - yaw0b)])
	_check(first >= 0.0, label + ": the cars met")
	_check(t < secs - 0.01, label + ": they come to rest")
	_check(w_max < Wreck.MAX_SPIN + 0.001, label + ": spin stays below the cap")
	_check(e_grew < 0.05, label + ": no energy appears (%.3f)" % e_grew)
	_check(absf(a.yaw - yaw0a) < TAU * 1.5 and absf(b.yaw - yaw0b) < TAU * 1.5, label + ": nobody turns more than a turn and a half")


func _scenarios() -> void:
	print("== crashes played out (A = the player's car)")
	# 40 m/s into the rear left corner of a car doing 25, a lane change's worth of angle
	var a := _car("kestrel", 0.0, 0.0, 0.1, Vector2(4.0, 40.0))
	var b := _car("sedan", 1.7, 5.5, 0.0, Vector2(0.0, 25.0))
	_play(a, b, 20.0, "40 into 25, corner hit")
	a = _car("kestrel", 0.0, 0.0, 0.0, Vector2(0.0, 45.0))
	b = _car("truck", 0.6, 6.0, 0.0, Vector2(0.0, 18.0))
	_play(a, b, 20.0, "45 into the back of a truck, 0.6 m off centre")
	a = _car("kestrel", 0.0, 0.0, -0.12, Vector2(-3.0, 38.0))
	b = _car("suv", -1.85, 1.0, 0.0, Vector2(0.0, 30.0))
	_play(a, b, 20.0, "38 side swipe into an SUV doing 30")
	a = _car("kestrel", 0.0, 0.0, 0.0, Vector2(0.0, 35.0))
	b = _car("van", 0.0, 5.0, 0.0, Vector2(0.0, 22.0))
	_play(a, b, 20.0, "35 square into a van doing 22")
	a = _car("hyper", 0.0, 0.0, 0.25, Vector2(7.0, 50.0))
	b = _car("sedan", 1.6, 4.0, 0.0, Vector2(0.0, 28.0))
	_play(a, b, 25.0, "50 into a sedan at an angle")
	# along the guardrail: a car drifts into it at a few degrees, for good
	for yaw: float in [0.05, 0.12, 0.25]:
		var c := _car("sedan", 7.0, 0.0, yaw, Vector2(33.0 * sin(yaw), 33.0 * cos(yaw)))
		var dt := 1.0 / 60.0
		var t := 0.0
		var through := 0.0
		var hits := 0
		var w_max := 0.0
		var y_end := 0.0
		var e_prev := c.energy()
		var e_grew := 0.0
		while t < 15.0:
			c.step(dt)
			var wc := HitShape.wall_contact(c.outline(), 8.8, 1.0)
			if not wc.is_empty():
				through = maxf(through, float(wc.depth))
				c.pos.x -= float(wc.depth)
				if Wreck.impact(c, null, wc.n, wc.p, 0.25, 0.3) > 0.0:
					hits += 1
			e_grew = maxf(e_grew, c.energy() - e_prev)
			e_prev = c.energy()
			w_max = maxf(w_max, absf(c.w))
			t += dt
			if t > 1.0 and c.vel.length() < 0.05 and absf(c.w) < 0.02:
				break
		print("  rail, drifting in at %.0f degrees at 33 m/s: %d bumps, deepest %.2f m, peak spin %.2f rad/s, ends %.1f s later %.0f m on facing %.0f degrees off the road" % [rad_to_deg(yaw), hits, through, w_max, t, c.pos.y, rad_to_deg(c.yaw)])
		_check(hits > 0 and w_max < Wreck.MAX_SPIN + 0.001 and e_grew < 0.01, "rail at %.2f rad: bumps, bounded spin, no energy gained" % yaw)
	# many random crashes: nothing blows up, nothing spins like a top
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var worst_turns := 0.0
	var worst_w := 0.0
	var worst_t := 0.0
	var n_ok := 0
	var ids := ["sedan", "suv", "van", "hatch", "truck"]
	for i in 300:
		var va := rng.randf_range(20.0, 55.0)
		var vb := rng.randf_range(10.0, 32.0)
		var ya := rng.randf_range(-0.35, 0.35)
		var ca := _car("kestrel", rng.randf_range(-1.8, 1.8), 0.0, ya, Vector2(va * sin(ya), va * cos(ya)))
		var cb: Wreck = _car(ids[rng.randi() % ids.size()], 0.0, rng.randf_range(3.0, 7.0), rng.randf_range(-0.05, 0.05), Vector2(0.0, vb))
		var dt := 1.0 / 60.0
		var t := 0.0
		var wmax := 0.0
		var y0a := ca.yaw
		var y0b := cb.yaw
		var met := false
		while t < 25.0:
			ca.step(dt)
			cb.step(dt)
			var c := _contact(ca, cb)
			if not c.is_empty():
				met = true
				Wreck.separate(ca, cb, c.n, c.depth)
				Wreck.impact(ca, cb, c.n, c.p, 0.2, 0.25)
			wmax = maxf(wmax, maxf(absf(ca.w), absf(cb.w)))
			t += dt
			if met and t > 1.0 and ca.vel.length() < 0.05 and cb.vel.length() < 0.05:
				break
		if not met:
			continue
		n_ok += 1
		worst_turns = maxf(worst_turns, maxf(absf(ca.yaw - y0a), absf(cb.yaw - y0b)) / TAU)
		worst_w = maxf(worst_w, wmax)
		worst_t = maxf(worst_t, t)
	print("  %d random crashes: worst spin %.2f rad/s, most any car turned %.2f revolutions, longest %.1f s to rest" % [n_ok, worst_w, worst_turns, worst_t])
	_check(n_ok > 200, "most random pairs actually met")
	_check(worst_turns < 1.5, "no random crash turns a car more than a turn and a half (%.2f)" % worst_turns)
	_check(worst_t < 24.0, "every random crash ends")
