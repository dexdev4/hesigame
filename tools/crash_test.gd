extends SceneTree
## Hit boxes and crash physics, no window needed:
##   godot --headless --path . --script tools/crash_test.gd
## Checks HitShape (the outlines really follow the cars, contact is found
## exactly when the outlines overlap and the contact point is where they touch)
## and Wreck (a sliding car brakes and straightens out, a spin dies away in a
## fraction of a turn, an impact conserves momentum, loses energy, and an
## off-centre one spins the car the right way; the body leans on its springs the
## way a real car's does, rocks and settles, and never rolls over) and prints how
## long real crash scenarios take to play out. Exits with a non-zero code if a
## check fails.

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
	_springs()
	_scenarios()
	print("== %d checks, %d failed" % [_checks, _fails])
	quit(1 if _fails > 0 else 0)


# ---------------------------------------------------------------- outlines

func _hit_shapes() -> void:
	print("== hit boxes")
	for id in Data.SHAPES:
		var h := HitShape.of(id)
		var xr := HitShape.x_range(h.world(0.0, 0.0, 0.0, 0.0, false))   # (the body, without the door mirrors)
		var yr := HitShape.y_range(h.world(0.0, 0.0, 0.0, 0.0, false))
		var sh: Dictionary = Data.SHAPES[id]
		# the outline is the car: about its width and length (less the pulled-in edge, plus any flare), and symmetric
		_check(absf(xr.x + xr.y) < 0.01, "%s: outline is symmetric (%.3f %.3f)" % [id, xr.x, xr.y])
		_check(_near(xr.y - xr.x, float(sh.w), 0.2), "%s: outline width %.2f is the car's %.2f" % [id, xr.y - xr.x, sh.w])
		_check(_near(yr.y - yr.x, float(sh.l), 0.2 if id != "truck" else 0.3), "%s: outline length %.2f is the car's %.2f" % [id, yr.y - yr.x, sh.l])
		# the door mirrors stand out a little past the body, the same on each side
		if not h.mirrors.is_empty():
			var xm := HitShape.x_range(h.world(0.0, 0.0, 0.0))
			_check(absf(xm.x + xm.y) < 0.01 and xm.y - xr.y > 0.02 and xm.y - xr.y < 0.35, "%s: mirrors stand out %.2f m a side" % [id, xm.y - xr.y])
		# each part is convex and counter-clockwise
		for part in h.parts + h.mirrors:
			var n := part.size()
			var convex := true
			for i in n:
				var a := part[i]
				var b := part[(i + 1) % n]
				var c := part[(i + 2) % n]
				if (b - a).cross(c - b) < -0.0001:
					convex = false
			_check(convex, "%s: outline is convex and counter-clockwise" % id)
	# two cars side by side: touching exactly when their outlines overlap (door mirrors and all)
	var k := HitShape.of("kestrel")
	for gap: float in [-0.3, -0.1, -0.05, 0.05, 0.3]:
		var a := _car("kestrel", 0.0, 0.0)
		var b := _car("kestrel", 1.9 + gap, 0.0)  # centres 1.9 + gap apart: the outline is 1.82 wide (pulled in 0.04 a side)
		var hit := not _contact(a, b).is_empty()
		var ow := HitShape.x_range(k.world(0.0, 0.0, 0.0)).y * 2.0
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
		while not _contact(pa, pb).is_empty() and again < 4:
			var c2 := _contact(pa, pb)  # (a car is more than one piece, the body and its door mirrors, and the truck the box
			# and the cab: when the cars cross deep, the push that clears one pair can press another into each other)
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
	_check(HitShape.wall_contact(r.outline(false), 8.8, 1.0).is_empty(), "car clear of the rail")
	r.pos.x = 8.0
	var wc := HitShape.wall_contact(r.outline(false), 8.8, 1.0)   # (the mirrors stand above the rail)
	_check(not wc.is_empty() and _near(wc.depth, 8.0 + half - 8.8, 0.02), "car %.0f cm through the rail: depth %.3f" % [(8.0 + half - 8.8) * 100.0, wc.get("depth", -1.0)])
	var rr := _car("kestrel", 7.7, 0.0, 0.4)  # nose turned towards the rail: the nose corner touches it first
	wc = HitShape.wall_contact(rr.outline(false), 8.8, 1.0)
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
	# the last-life crash: the rear wheels locked (the driver standing on the brakes). The slightest swing grows into a
	# spin until the car slides backwards, as a real one does; with them rolling the same swing dies away
	for lock: bool in [true, false]:
		b = _car("sedan", 0.0, 0.0, 0.0, Vector2(0.0, 35.0))
		b.brake = 0.5
		b.grip = 0.95
		b.rear_lock = lock
		b.w = 0.15
		res = _run(b, 20.0)
		print("  35 m/s with a 0.15 rad/s swing, rear wheels %s: turned %.0f degrees, stopped after %.1f s and %.0f m" % ["locked" if lock else "rolling", rad_to_deg(res.turned), res.t_stop, res.dist])
		if lock:
			_check(absf(res.turned) > PI * 0.75 and absf(res.turned) < PI * 1.4, "rear wheels locked, a small swing grows into a spin until it slides backwards (%.0f degrees)" % rad_to_deg(res.turned))
		else:
			_check(absf(res.turned) < 0.3, "rolling, the same swing dies away (%.2f rad)" % res.turned)
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
	var wc := HitShape.wall_contact(a.outline(false), 8.8, 1.0)
	while wc.is_empty():
		a.pos += a.vel * (1.0 / 240.0)
		wc = HitShape.wall_contact(a.outline(false), 8.8, 1.0)
	e0 = a.energy()
	j = Wreck.impact(a, null, wc.n, wc.p, 0.25, 0.3)
	print("  rail at 29 m/s, 6 degrees off, nose in: afterwards %.2f across %.2f along, spin %+.2f rad/s (the nose is pushed back to the road), impulse %.2f" % [a.vel.x, a.vel.y, a.w, j])
	_check(a.point_vel(wc.p).x <= 0.0, "the corner that hit the rail is moving off it")
	_check(a.w < 0.0, "the rail pushes the nose back towards the road")
	_check(a.vel.y < 29.0 and a.vel.y > 25.0, "it scrapes along it and loses some speed")
	_check(a.energy() < e0, "energy is lost on the rail")
	# how hard a blow is decides how much it bounces, as in real crashes: a bumper tap springs back, a crash crumples
	_check(Wreck.bounce(1.5) > 0.25 and Wreck.bounce(15.0) < 0.08 and Wreck.bounce(5.0) < Wreck.bounce(2.0), "a tap bounces (%.2f at 1.5 m/s), a crash hardly (%.2f at 15 m/s)" % [Wreck.bounce(1.5), Wreck.bounce(15.0)])
	_check(Wreck.contact_mu(1.0) < Wreck.contact_mu(15.0), "panels dig into each other harder in a hard hit than in a scrape")
	for pair: Array in [[22.0, 20.0], [30.0, 10.0]]:
		a = _car("sedan", 0.0, 0.0, 0.0, Vector2(0.0, pair[0]))
		b = _car("sedan", 0.0, 4.5, 0.0, Vector2(0.0, pair[1]))
		c = _contact(a, b)
		var cl: float = pair[0] - pair[1]
		Wreck.impact(a, b, c.n, c.p)
		var part := (b.vel.y - a.vel.y) / cl
		print("  rear-end at %.0f m/s closing: they part at %.2f of it" % [cl, part])
		_check(_near(part, Wreck.bounce(cl), 0.01), "a %.0f m/s blow parts at the bounce its speed gives (%.2f)" % [cl, part])
	_check(Wreck.bounce(2.0) > 0.25 and Wreck.bounce(20.0) < 0.07, "a 2 m/s tap springs apart, a 20 m/s crash nearly sticks")
	# what it would take to roll a car over on a flat road: more sideways push than its tyres can give
	var tips := ""
	var lowest := 9.0
	for id in ["sedan", "hatch", "compact"] + Data.CARS.map(func(c: Dictionary) -> String: return String(c.shape)):
		var w := Wreck.make(id)
		lowest = minf(lowest, w.tip_g())
		if w.tip_g() <= w.grip:
			tips += " " + id
	print("  the least sideways push that would lift a car over its outer wheels: %.2f g (its tyres hold %.2f g)" % [lowest, Wreck.make("sedan").grip])
	_check(tips == "", "no car's tyres can roll it on flat tarmac (%s)" % tips)
	# where the weight goes
	var bk := _car("sedan", 0.0, 0.0, 0.0, Vector2(0.0, 30.0))
	bk.brake = 1.0
	bk.step(0.25)
	var ld := bk.wheel_loads()
	print("  braking hard: front wheels carry %.0f%% of the weight (rear %.0f%%)" % [(ld[2] + ld[3]) * 100.0, (ld[0] + ld[1]) * 100.0])
	_check(ld[2] + ld[3] > ld[0] + ld[1] + 0.06, "braking puts weight on the front wheels")
	var sl := _car("sedan", 0.0, 0.0, PI / 2.0, Vector2(0.0, 20.0))
	sl.step(0.25)
	ld = sl.wheel_loads()
	print("  sliding sideways: left wheels %.0f%%, right %.0f%%" % [(ld[0] + ld[2]) * 100.0, (ld[1] + ld[3]) * 100.0])
	_check(absf((ld[0] + ld[2]) - (ld[1] + ld[3])) > 0.3 and minf(ld[0] + ld[2], ld[1] + ld[3]) > 0.05, "sliding sideways moves weight onto the outer wheels, without lifting the inner ones")
	# a hit is never a net force out of nowhere: a car at rest shoved by a slow one stays calm
	a = _car("sedan", 0.0, 0.0, 0.0, Vector2(0.0, 5.0))
	b = _car("sedan", 0.0, 4.45, 0.0, Vector2(0.0, 0.0))
	c = _contact(a, b)
	j = Wreck.impact(a, b, c.n, c.p, 0.2, 0.25)
	_check(b.vel.y > 0.0 and b.vel.y < 5.0 and absf(b.w) < 0.001, "a nudge only nudges")


# ---------------------------------------------------------------- the body on its springs

## Runs a body for `secs`, returning the extremes of its roll and pitch and where they ended.
func _sway_run(b: Wreck, secs: float) -> Dictionary:
	var dt := 1.0 / 60.0
	var t := 0.0
	var out := {"roll_max": 0.0, "roll_min": 0.0, "pitch_max": 0.0, "pitch_min": 0.0, "t_stop": -1.0, "finite": true}
	while t < secs:
		b.step(dt)
		t += dt
		out.roll_max = maxf(out.roll_max, b.roll)
		out.roll_min = minf(out.roll_min, b.roll)
		out.pitch_max = maxf(out.pitch_max, b.pitch)
		out.pitch_min = minf(out.pitch_min, b.pitch)
		if is_nan(b.roll) or is_nan(b.pitch) or is_inf(b.roll) or is_inf(b.pitch):
			out.finite = false
		if out.t_stop < 0.0 and b.vel.length() < 0.05 and absf(b.w) < 0.02:
			out.t_stop = t
	out.roll = b.roll
	out.pitch = b.pitch
	return out


func _springs() -> void:
	print("== the body on its springs")
	# the signs are CarModel's: a positive roll lifts the right side, a positive pitch puts the nose (-z) down
	var probe := Wreck.make("sedan")
	var up := Basis.from_euler(Vector3(0.0, 0.0, probe.lean_roll(Wreck.G))) * Vector3(1.0, 0.0, 0.0)
	var nose := Basis.from_euler(Vector3(-probe.lean_pitch(-Wreck.G), 0.0, 0.0)) * Vector3(0.0, 0.0, -1.0)
	_check(up.y > 0.0, "pushed to its right (round a right-hand turn), the right side rises: the body leans out")
	_check(nose.y < 0.0, "slowing, the nose goes down")
	print("  a sedan leans %.1f degrees for each g sideways and pitches %.1f for each g of braking; a Halcyon %.1f, an SUV %.1f" % [
		rad_to_deg(probe.lean_roll(Wreck.G)), rad_to_deg(probe.lean_pitch(-Wreck.G)), rad_to_deg(Wreck.make("halcyon").lean_roll(Wreck.G)), rad_to_deg(Wreck.make("suv").lean_roll(Wreck.G))])
	_check(Wreck.make("halcyon").lean_roll(Wreck.G) < probe.lean_roll(Wreck.G) and probe.lean_roll(Wreck.G) < Wreck.make("suv").lean_roll(Wreck.G), "a low sports car leans less than a sedan, an SUV more")
	_check(rad_to_deg(probe.lean_roll(Wreck.G)) > 1.5 and rad_to_deg(probe.lean_roll(Wreck.G)) < 6.0, "a sedan's roll is a road car's: 1.5 to 6 degrees for each g")
	# sliding sideways: it dips on the side it is sliding towards (here its left: the car faces across the road, moving up it)
	var b := _car("sedan", 0.0, 0.0, PI / 2.0, Vector2(0.0, 20.0))
	var r := _sway_run(b, 0.7)
	print("  sliding sideways at 20 m/s: after 0.7 s the body is rolled %+.1f degrees (right side up), at most %+.1f" % [rad_to_deg(r.roll), rad_to_deg(r.roll_max)])
	_check(r.roll > 0.025, "sliding to its left, its left side dips and the right side rises (%.3f rad)" % r.roll)
	_check(r.roll_max <= Wreck.ROLL_MAX + 0.0001, "...no further than the bump stops")
	r = _sway_run(b, 12.0)
	print("  ...it stops after %.1f s; the body rocks back to %+.1f degrees, then settles at %+.2f" % [0.7 + r.t_stop, rad_to_deg(r.roll_min), rad_to_deg(r.roll)])
	_check(r.roll_min < -0.004, "as the slide stops, the body rocks back past level (%.3f rad)" % r.roll_min)
	_check(absf(r.roll) < 0.002 and absf(r.pitch) < 0.002, "...and settles level (%.4f, %.4f rad)" % [r.roll, r.pitch])
	# braking in a straight line: the nose dips; let go and it rocks back
	b = _car("sedan", 0.0, 0.0, 0.0, Vector2(0.0, 30.0))
	b.brake = 1.0
	r = _sway_run(b, 0.8)
	print("  braking hard at 30 m/s: the nose is %.1f degrees down after 0.8 s" % rad_to_deg(r.pitch))
	_check(r.pitch > 0.015 and r.pitch_max <= Wreck.PITCH_MAX + 0.0001, "braking hard dips the nose (%.3f rad), within the bump stops" % r.pitch)
	r = _sway_run(b, 8.0)
	_check(r.pitch_min < -0.002 and absf(r.pitch) < 0.002, "stopping, it rocks back nose up (%.3f rad) and settles" % r.pitch_min)
	# a blow: a car standing still is hit on its right side by a car coming across at 6 m/s
	var a := _car("sedan", 0.0, 0.0, 0.0)
	var o := _car("sedan", 1.85, 0.6, -PI / 2.0, Vector2(-6.0, 0.0))
	var ct := _contact(o, a)
	_check(not ct.is_empty(), "the side blow touches")
	if not ct.is_empty():
		Wreck.impact(o, a, ct.n, ct.p)
		print("  hit on its right side at 6 m/s: shoved %.1f m/s, the body set rolling at %+.2f rad/s" % [a.vel.length(), a.roll_v])
		r = _sway_run(a, 6.0)
		print("  ...it rolls between %+.1f and %+.1f degrees and ends at %+.2f" % [rad_to_deg(r.roll_min), rad_to_deg(r.roll_max), rad_to_deg(r.roll)])
		_check(a.roll_v != 0.0 or r.roll_max - r.roll_min > 0.01, "a side blow rocks the body")
		_check(r.roll_max <= Wreck.ROLL_MAX + 0.0001 and r.roll_min >= -Wreck.ROLL_MAX - 0.0001, "...within the bump stops")
		_check(absf(r.roll) < 0.002, "...and it settles (%.4f rad)" % r.roll)
	# a rear-end shunt: the car behind takes the blow on its nose, below its centre of gravity, and dips it; the car in
	# front is shoved from behind and its nose lifts
	a = _car("sedan", 0.0, 0.0, 0.0, Vector2(0.0, 30.0))
	o = _car("sedan", 0.0, 4.45, 0.0, Vector2(0.0, 18.0))
	ct = _contact(a, o)
	Wreck.impact(a, o, ct.n, ct.p)
	print("  a 12 m/s rear-end shunt: the car behind pitches at %+.2f rad/s (nose down +), the car in front at %+.2f" % [a.pitch_v, o.pitch_v])
	_check(a.pitch_v > 0.0 and o.pitch_v < 0.0, "a shunt dips the nose of the car behind and lifts the one in front's")
	# the springs never run away: random blows and slides, every body stays within its travel and finite
	var rng := RandomNumberGenerator.new()
	rng.seed = 23
	var worst_r := 0.0
	var worst_p := 0.0
	var finite := true
	for i in 120:
		var ids := ["sedan", "suv", "van", "halcyon", "truck", "hot_hatch"]
		var w := _car(ids[i % ids.size()], 0.0, 0.0, rng.randf_range(-PI, PI), Vector2(rng.randf_range(-8.0, 8.0), rng.randf_range(0.0, 45.0)))
		w.w = rng.randf_range(-3.0, 3.0)
		w.kick(Vector2(rng.randf_range(-15.0, 15.0), rng.randf_range(-15.0, 15.0)), rng.randf_range(0.3, 1.0))
		var rr := _sway_run(w, 12.0)
		worst_r = maxf(worst_r, maxf(rr.roll_max, -rr.roll_min))
		worst_p = maxf(worst_p, maxf(rr.pitch_max, -rr.pitch_min))
		finite = finite and rr.finite
	print("  120 random slides, spins and blows: the most any body rolled %.1f degrees, pitched %.1f" % [rad_to_deg(worst_r), rad_to_deg(worst_p)])
	_check(finite, "every body stays finite")
	_check(worst_r <= Wreck.ROLL_MAX + 0.0001 and worst_p <= Wreck.PITCH_MAX + 0.0001, "and within its bump stops (never anywhere near rolling over)")


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
			var j := Wreck.impact(a, b, c.n, c.p)
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
			var wc := HitShape.wall_contact(c.outline(false), 8.8, 1.0)
			if not wc.is_empty():
				through = maxf(through, float(wc.depth))
				c.pos.x -= float(wc.depth)
				if Wreck.impact(c, null, wc.n, wc.p) > 0.0:
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
				Wreck.impact(ca, cb, c.n, c.p)
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
	# (the hardest of these is one clean blow: the Kestrel at 190 km/h clipping the rear corner of a sedan at 105, which
	# turns the sedan a turn and a half before it stops, never at the spin cap. With the hit boxes as exact as the cars,
	# the corner is where the car's corner is, a little further from the middle than the old pulled-in box: 1.51 turns
	# against 1.47. What keeps a car from spinning like a top is the cap on the spin rate, checked above.)
	_check(worst_turns < 1.6, "no random crash turns a car more than about a turn and a half (%.2f)" % worst_turns)
	_check(worst_t < 24.0, "every random crash ends")
