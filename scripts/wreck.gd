class_name Wreck
extends RefCounted
## A car that has been hit and is no longer driven: a rigid body on the road,
## seen from above, that slides, spins and comes to rest the way a real one does.
##
## - Its four tyres rub on the road: sideways they hold up to the car's grip
##   however fast it slides, along their direction they only drag (rolling
##   resistance plus whatever braking is left), and every patch of rubber is
##   pushed by the car's own movement at that corner. Each tyre holds in
##   proportion to the weight on it, and the weight moves as a real car's does:
##   onto the front wheels as it slows, onto the outer ones as it is pushed
##   sideways (its centre of gravity is above the road), and a tyre pressed
##   harder grips a little less for each kilo (load sensitivity). So a car
##   braking in a slide swings its tail out more readily, and the air pushes back
##   on it too, harder side-on than nose-on. The yaw damping, the way a sliding
##   car straightens out and the way a spin dies away all come out of that.
## - A hit is an impulse at the point of contact along its normal, shared out by
##   mass and by how far the point is from the car's centre: a push through the
##   middle only shoves the car, a push at a corner spins it. How much it bounces
##   depends on how hard it is, as measured in real crashes: a bumper tap at
##   walking pace springs back with about 0.4 of the closing speed, a crash at
##   speed crumples the metal and keeps about 0.05 (bounce). Along the surface the
##   panels scrape at a glancing touch and dig into each other in a hard hit
##   (contact_mu).
## - The wheels stay on the road and the body moves on its springs above them,
##   as a real car's does: it rolls and pitches about the middle of the car at
##   hub height (where CarModel._pose_body turns it). The tyres push the car at
##   road level, below its centre of gravity, so the body leans against the push:
##   out of a turn, nose down as it slows and squatting as it speeds up, and a car
##   sliding sideways dips on the side it slides towards (its wheels are held back).
##   How far is a road car's roll and pitch gradient (ROLL_K, PITCH_K for each g),
##   more for a tall car and less for a low one. Each way it moves is a spring and
##   a damper set like a road car's (ROLL_HZ, PITCH_HZ, ZETA), so a sudden change
##   (a slide starting or ending, the push swinging round as the car spins) rocks
##   it over and back before it settles; a blow rocks it as well (kick), and the
##   bump stops end its travel. It never rolls over: on a flat road its tyres grip
##   at about 1 g and lifting a car over its outer wheels takes its track over
##   twice the height of its centre of gravity (about 1.4 g; a guardrail is built
##   to catch and turn a car, not to trip it).
##
## Road coordinates (x across, y along); `yaw` is the heading (+ = nose to the
## right), `w` its rate. kept apart from the game so it can be tested on its own
## (tools/crash_test.gd).

const G := 9.81
const EPS := 0.35          # m/s: slower than this a tyre sticks rather than slides (friction fades out linearly)
const MAX_STEP := 1.0 / 120.0
const ROLL_RES := 0.03     # rolling resistance, in g
const MAX_SPIN := 3.2      # rad/s (about one turn in two seconds): no car spins faster than this, however hard it is hit
const AIR := 0.00034       # air drag per unit mass nose-on (1/m: 0.5 x air density x Cd 0.32 x 2.2 m² / 1400 kg)...
const AIR_SIDE := 0.0013   # ...and side-on (Cd about 1, the side 3.5 times the front)
const LOAD_SENS := 0.12    # a tyre carrying twice its share of the weight grips 12% less for it

## How heavy each kind of vehicle is, against an ordinary car.
const MASS := {"truck": 3.5, "van": 1.5, "suv": 1.25, "hatch": 0.85, "compact": 0.85}
## How high its centre of gravity is (m): what moves the weight between the wheels, and how far the body leans.
const CG_H := {"truck": 1.3, "van": 0.92, "suv": 0.72, "hyper": 0.46, "super": 0.47, "rcoupe": 0.48, "halcyon": 0.47, "lastexit": 0.46, "static": 0.47}
const CG_CAR := 0.55
## How high its wheel hubs are (m): the body rolls and pitches about that height.
const HUB_H := {"truck": 0.5, "van": 0.36, "suv": 0.37}
const HUB_CAR := 0.33
## How high its bumper beams and sills take a blow (m), and a guardrail's beam.
const BUMPER_H := {"truck": 0.75, "van": 0.58, "suv": 0.55}
const BUMPER_CAR := 0.46
const RAIL_H := 0.55

# the body on its springs
const ROLL_K := 0.05       # rad of roll for each g pushing an ordinary car sideways (2.9 degrees: a road car's)...
const PITCH_K := 0.03      # ...and of pitch for each g slowing it (1.7 degrees: the suspension's anti-dive takes some)
const REF_ARM := 0.25      # m: the ordinary car's body weight above the hubs it rolls about (more leans further)
const ROLL_HZ := 1.6       # how fast it rocks from side to side...
const PITCH_HZ := 1.8      # ...and nose to tail
const ZETA := 0.33         # the dampers: a third of critical (an overshoot of about a third, settled within a second)
const ROLL_MAX := 0.06     # rad: the bump stops (the springs' travel, which the wheel arches leave room for)
const PITCH_MAX := 0.04
const UNSPRUNG := 0.12     # the share of the car's weight that hangs under the springs (wheels, brakes, axles)
const ROLL_R2 := 0.36      # m²: the body's radius of gyration, squared, rolling (0.6 m)...
const PITCH_R2 := 1.44     # ...and pitching (1.2 m)

var pos := Vector2.ZERO     # the middle of the car
var vel := Vector2.ZERO     # m/s
var yaw := 0.0
var w := 0.0                # yaw rate, rad/s (+ = clockwise seen from above)
var mass := 1.0
var shape: HitShape
var grip := 0.95            # what the tyres hold sideways, in g
var brake := 0.5            # how much of the tyres' grip still drags the car along its length (0 = rolling free)
var rear_lock := false      # the rear wheels are locked: they slide, pulling against whichever way their rubber is going
var cg_h := CG_CAR          # height of the centre of gravity, m
var bumper_h := BUMPER_CAR  # height its bumpers and sills take a blow at, m
var roll := 0.0             # the body on its springs: rad, + = right side up (CarModel's sign)...
var pitch := 0.0            # ...and + = nose down
var roll_v := 0.0           # rad/s
var pitch_v := 0.0
var _wheels := PackedVector2Array()
var _ax := 0.0              # its acceleration along itself and across (m/s², + forward and to the right): where the weight goes
var _ay := 0.0
var _hub := HUB_CAR         # what the body turns about, and where its own weight is (the wheels' taken out), m
var _hs := 0.58
var _lean := 1.0            # how far it leans for a push, against the ordinary car
var _roll_max := ROLL_MAX
var _pitch_max := PITCH_MAX


static func make(shape_id: String) -> Wreck:
	var b := Wreck.new()
	b.shape = HitShape.of(shape_id)
	b.mass = MASS.get(shape_id, 1.0)
	b.cg_h = CG_H.get(shape_id, CG_CAR)
	b.bumper_h = BUMPER_H.get(shape_id, BUMPER_CAR)
	b._wheels = b.shape.wheel_points()
	b._springs(HUB_H.get(shape_id, HUB_CAR))
	return b


## The body on its springs: the car's weight less the wheels hanging at the hubs is the body's, and the higher that is
## above the hubs it turns about, the further it leans for a push (a low sports car less, an SUV or a van more). A low
## car's stiffer springs have less travel too.
func _springs(hub: float) -> void:
	_hub = hub
	_hs = (cg_h - UNSPRUNG * hub) / (1.0 - UNSPRUNG)
	_lean = clampf((_hs - hub) / REF_ARM, 0.4, 2.0)
	_roll_max = ROLL_MAX * clampf(_lean, 0.6, 1.0)
	_pitch_max = PITCH_MAX * clampf(_lean, 0.6, 1.0)


## The car's track over twice the height of its centre of gravity: the sideways push, in g, it would take to lift it
## over its outer wheels (the static stability factor; about 1.4 for a car, more for a sports car). Its tyres grip at
## about 1 g, so on a flat road it cannot roll.
func tip_g() -> float:
	return shape.track / cg_h


## The bounce of a blow between two cars (0 dead .. 1 rubber) at a closing speed (m/s): measured coefficients of
## restitution of car-to-car impacts fall from about 0.4 for a bumper tap to 0.05 for a crash at speed.
static func bounce(closing: float) -> float:
	return 0.05 + 0.35 * exp(-closing / 4.0)


## A steel guardrail's: the beam gives and springs back a little.
static func rail_bounce(closing: float) -> float:
	return 0.08 + 0.22 * exp(-closing / 5.0)


## Friction along the surface of a blow: paint and trim scraping past at a glancing touch, panels digging into each
## other in a hard one.
static func contact_mu(closing: float) -> float:
	return 0.3 + 0.3 * smoothstep(3.0, 12.0, closing)


## Heading as a unit vector.
func heading() -> Vector2:
	return Vector2(sin(yaw), cos(yaw))


## The world outline of the car (turned about its middle); without the door mirrors for the guardrails.
func outline(with_mirrors := true) -> Array[PackedVector2Array]:
	return shape.world(pos.x, pos.y - shape.length / 2.0, yaw, shape.length / 2.0, with_mirrors)


## Speed of whatever is at world point p (on the body).
func point_vel(p: Vector2) -> Vector2:
	var r := p - pos
	return vel + w * Vector2(r.y, -r.x)


func energy() -> float:
	return 0.5 * mass * vel.length_squared() + 0.5 * mass * shape.k2 * w * w


## The clockwise turning effect of a force f at arm r.
static func _turn(r: Vector2, f: Vector2) -> float:
	return r.y * f.x - r.x * f.y


## One step of free movement: the tyres (or the body) rubbing on the road.
func step(dt: float) -> void:
	var n := maxi(1, ceili(dt / MAX_STEP))
	var h := dt / float(n)
	for _i in n:
		_sub(h)


func _sub(dt: float) -> void:
	var hd := heading()
	var rt := Vector2(hd.y, -hd.x)
	var acc := Vector2.ZERO
	var tq := 0.0
	var loads := wheel_loads()
	for i in 4:
		var lw := _wheels[i]
		var load := loads[i]
		var mu := grip * (1.0 - LOAD_SENS * (load * 4.0 - 1.0))
		var r := rt * lw.x + hd * lw.y
		var pv := vel + w * Vector2(r.y, -r.x)
		var u := pv.dot(hd)
		var s := pv.dot(rt)
		var fs: float
		var fu: float
		if rear_lock and i < 2:
			# a locked wheel slides: it holds nothing sideways of its own, its rubber only drags against the way it is
			# going. So the rear of the car has nothing to keep it behind the front, and the slightest swing grows into a
			# spin until the car slides backwards (as a real one does when its rear wheels lock)
			var sp := sqrt(u * u + s * s + EPS * EPS)
			fu = -mu * u / sp
			fs = -mu * s / sp
		else:
			fs = -mu * s / sqrt(s * s + EPS * EPS)
			fu = -(ROLL_RES + brake * mu) * u / sqrt(u * u + EPS * EPS)
			var m := sqrt(fu * fu + fs * fs)
			if m > mu:  # the friction circle: no more than the tyre can give all told
				fu *= mu / m
				fs *= mu / m
		var f := (hd * fu + rt * fs) * (G * load)
		acc += f
		tq += _turn(r, f) / shape.k2
	# the air, harder side-on
	var sp2 := vel.length()
	if sp2 > 1.0:
		var side := vel.dot(rt) / sp2
		acc -= vel * (sp2 * lerpf(AIR, AIR_SIDE, side * side) / mass)
	_ax = lerpf(_ax, acc.dot(hd), 0.5)
	_ay = lerpf(_ay, acc.dot(rt), 0.5)
	vel += acc * dt
	w += tq * dt
	w = clampf(w, -MAX_SPIN, MAX_SPIN)
	pos += vel * dt
	yaw += w * dt
	if vel.length_squared() < 0.0009 and absf(w) < 0.01:
		vel = Vector2.ZERO  # at rest
		w = 0.0
	sway(_ax, _ay, dt)  # the body leans against the tyres' push


## The body on its springs for dt seconds, with the car pushed at `ax` m/s² forward and `ay` to its right (the wreck's
## own tyres, or the driving model's for a car still being driven).
func sway(ax: float, ay: float, dt: float) -> void:
	var r := spring(roll, roll_v, lean_roll(ay), ROLL_HZ, _roll_max, dt)
	roll = r.x
	roll_v = r.y
	var p := spring(pitch, pitch_v, lean_pitch(ax), PITCH_HZ, _pitch_max, dt)
	pitch = p.x
	pitch_v = p.y


## Where the body comes to rest, rolled, while the car is pushed at `ay` m/s² to its right (it leans away: out of a
## turn, towards the side a slide is going); and pitched, while it speeds up at `ax` (nose down when slowing).
func lean_roll(ay: float) -> float:
	return ROLL_K * _lean * ay / G


func lean_pitch(ax: float) -> float:
	return -PITCH_K * _lean * ax / G


## One mode of the body on its spring and damper: angle x, rate v, resting at eq, rocking at hz, for dt seconds; past
## three quarters of `lim` it meets the rubber of the bump stop, which stiffens sharply, and it goes no further than
## `lim`. Returns the new (angle, rate).
static func spring(x: float, v: float, eq: float, hz: float, lim: float, dt: float) -> Vector2:
	var k := TAU * hz
	var n := maxi(1, ceili(dt / MAX_STEP))
	var h := dt / float(n)
	for _i in n:
		var a := -k * k * (x - eq) - 2.0 * ZETA * k * v
		var over := absf(x) - lim * 0.75
		if over > 0.0:
			a -= signf(x) * over * k * k * 12.0 + v * k * 1.5
		v += a * h
		x += v * h
		if absf(x) > lim:
			x = signf(x) * lim
			if v * x > 0.0:
				v *= -0.2
	return Vector2(x, v)


## A blow changed the car's velocity by `dv` (road frame) with a push at `at` m above the road: it rocks the body on its
## springs. Seen along each of the car's axes the push lands above or below the body's own centre of gravity, and the
## wheels hanging at the hubs are dragged along by the bottom of the body, so the blow swings the top of the body as
## well as moving it (_rock).
func kick(dv: Vector2, at: float) -> void:
	var hd := heading()
	var rt := Vector2(hd.y, -hd.x)
	roll_v -= _rock(dv.dot(rt), at, ROLL_R2)    # (the top swung to the right is the right side going down)
	pitch_v += _rock(dv.dot(hd), at, PITCH_R2)  # (the top swung forward is the nose going down)


## How fast a blow worth `j` m/s of the whole car's speed along one of its axes, landing at height `at`, swings the top
## of the body that way (rad/s). The body (the sprung part, its radius of gyration squared `r2`) takes the blow and
## passes some of it to the wheels through the suspension at hub height, which moves with them: the impulses that
## satisfy that, worked out exactly.
func _rock(j: float, at: float, r2: float) -> float:
	var ms := 1.0 - UNSPRUNG
	var ii := ms * r2
	var a := at - _hs
	var b := _hub - _hs
	var to_wheels := j * (1.0 / ms + a * b / ii) / (1.0 / UNSPRUNG + 1.0 / ms + b * b / ii)
	return (j * a - to_wheels * b) / ii


## The share of the car's weight on each wheel (rear left, rear right, front left, front right; they add up to 1):
## each axle's share at rest (by where the axles are about the middle), plus what slowing down puts on the front
## wheels and being pushed sideways puts on the outer ones, as the last steps' acceleration has it.
func wheel_loads() -> PackedFloat32Array:
	var yf := _wheels[2].y
	var yr := _wheels[0].y
	var wb := maxf(yf - yr, 1.0)
	var front := -yr / wb
	var t2 := maxf(shape.track * 2.0, 0.8)
	var dlong := -cg_h * _ax / (wb * G)   # (+: onto the front axle)
	var dlat := cg_h * _ay / (t2 * G) * 0.5   # (+: onto each left wheel; the side's share is split between its two)
	var loads := PackedFloat32Array([(1.0 - front - dlong) * 0.5 + dlat, (1.0 - front - dlong) * 0.5 - dlat, (front + dlong) * 0.5 + dlat, (front + dlong) * 0.5 - dlat])
	var sum := 0.0
	for i in 4:
		loads[i] = maxf(loads[i], 0.01)
		sum += loads[i]
	for i in 4:
		loads[i] /= sum
	return loads


# ---------------------------------------------------------------- impacts

## An impact between two bodies at world point p, n pointing from a to b (b = null:
## an immovable wall). Both are changed; returns the size of the impulse (per unit
## of a car's mass, so roughly the change of speed the bump gave a car).
## `e` is the bounce (0 = dead, 1 = rubber), `mu` the friction along the contact,
## `min_sep` the least speed the two are to part at (0 = whatever the bounce gives).
## `e` < 0 and `mu` < 0 (the defaults) are worked out from how hard the blow is (bounce, rail_bounce, contact_mu).
static func impact(a: Wreck, b: Wreck, n: Vector2, p: Vector2, e := -1.0, mu := -1.0, min_sep := 0.0) -> float:
	var va0 := a.vel
	var vb0 := b.vel if b else Vector2.ZERO
	var ra := p - a.pos
	var ima := 1.0 / a.mass
	var iia := 1.0 / (a.mass * a.shape.k2)
	var rb := Vector2.ZERO
	var imb := 0.0
	var iib := 0.0
	var vb := Vector2.ZERO
	if b:
		rb = p - b.pos
		imb = 1.0 / b.mass
		iib = 1.0 / (b.mass * b.shape.k2)
		vb = b.point_vel(p)
	var closing := (a.point_vel(p) - vb).dot(n)
	if closing <= 0.0:
		return 0.0
	if e < 0.0:
		e = bounce(closing) if b else rail_bounce(closing)
	if mu < 0.0:
		mu = contact_mu(closing) if b else 0.35  # (a car's side scraping along the steel)
	var la := _turn(ra, n)
	var lb := _turn(rb, n)
	var kn := ima + imb + la * la * iia + lb * lb * iib
	var j := (1.0 + maxf(e, min_sep / closing)) * closing / kn
	a.vel -= n * (j * ima)
	a.w -= la * j * iia
	if b:
		b.vel += n * (j * imb)
		b.w += lb * j * iib
	# friction along the surface
	var t := Vector2(n.y, -n.x)
	var vt := (a.point_vel(p) - (b.point_vel(p) if b else Vector2.ZERO)).dot(t)
	var ta := _turn(ra, t)
	var tb := _turn(rb, t)
	var kt := ima + imb + ta * ta * iia + tb * tb * iib
	var jt := clampf(vt / kt, -mu * j, mu * j)
	a.vel -= t * (jt * ima)
	a.w -= ta * jt * iia
	if b:
		b.vel += t * (jt * imb)
		b.w += tb * jt * iib
	a.w = clampf(a.w, -MAX_SPIN, MAX_SPIN)
	if b:
		b.w = clampf(b.w, -MAX_SPIN, MAX_SPIN)
	# the bodies rock on their springs: the blow lands between the two cars' bumpers, or on the rail's beam
	var at := (a.bumper_h + b.bumper_h) * 0.5 if b else RAIL_H
	a.kick(a.vel - va0, at)
	if b:
		b.kick(b.vel - vb0, at)
	return j / a.mass


## Push two overlapping bodies apart along n (a to b) by `depth`, the lighter one moving more.
static func separate(a: Wreck, b: Wreck, n: Vector2, depth: float) -> void:
	if b == null:
		a.pos -= n * depth
		return
	var ka := b.mass / (a.mass + b.mass)
	a.pos -= n * (depth * ka)
	b.pos += n * (depth * (1.0 - ka))
