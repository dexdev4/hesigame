class_name Wreck
extends RefCounted
## A car that has been hit and is no longer driven: a rigid body on the road,
## seen from above, that slides, spins and comes to rest the way a real one does.
##
## - Its four tyres rub on the road: sideways they hold up to the car's grip
##   however fast it slides, along their direction they only drag (rolling
##   resistance plus whatever braking is left), and every patch of rubber is
##   pushed by the car's own movement at that corner. The yaw damping, the way a
##   sliding car straightens out and the way a spin dies away (a few rad/s lasting
##   half a second, not a spinning top) all come out of that, nothing is faked.
## - A hit is an impulse at the point of contact along its normal with a little
##   bounce (a crumpling car keeps about a fifth of its closing speed) and the
##   paint's friction along the surface, shared out by mass and by how far the
##   point is from the car's centre: a push through the middle only shoves the car,
##   a push at a corner spins it.
##
## Road coordinates (x across, y along); `yaw` is the heading (+ = nose to the
## right), `w` its rate. kept apart from the game so it can be tested on its own
## (tools/crash_test.gd).

const G := 9.81
const EPS := 0.35          # m/s: slower than this a tyre sticks rather than slides (friction fades out linearly)
const MAX_STEP := 1.0 / 120.0
const ROLL_RES := 0.03     # rolling resistance, in g
const BODY_MU := 0.6       # a body on its roof or side sliding on tarmac, in g
const MAX_SPIN := 3.2      # rad/s (about one turn in two seconds): no car spins faster than this, however hard it is hit

## How heavy each kind of vehicle is, against an ordinary car.
const MASS := {"truck": 3.5, "van": 1.5, "suv": 1.25, "hatch": 0.85, "compact": 0.85}

var pos := Vector2.ZERO     # the middle of the car
var vel := Vector2.ZERO     # m/s
var yaw := 0.0
var w := 0.0                # yaw rate, rad/s (+ = clockwise seen from above)
var mass := 1.0
var shape: HitShape
var grip := 0.95            # what the tyres hold sideways, in g
var brake := 0.5            # how much of the tyres' grip still drags the car along its length (0 = rolling free)
var on_wheels := true       # false: lying on its roof or side
var in_air := false
var _wheels := PackedVector2Array()


static func make(shape_id: String) -> Wreck:
	var b := Wreck.new()
	b.shape = HitShape.of(shape_id)
	b.mass = MASS.get(shape_id, 1.0)
	b._wheels = b.shape.wheel_points()
	return b


## Heading as a unit vector.
func heading() -> Vector2:
	return Vector2(sin(yaw), cos(yaw))


## The world outline of the car (turned about its middle).
func outline() -> Array[PackedVector2Array]:
	return shape.world(pos.x, pos.y - shape.length / 2.0, yaw, shape.length / 2.0)


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
	if not in_air:
		var hd := heading()
		var rt := Vector2(hd.y, -hd.x)
		var acc := Vector2.ZERO
		var tq := 0.0
		for lw in _wheels:
			var r := rt * lw.x + hd * lw.y
			var pv := vel + w * Vector2(r.y, -r.x)
			var u := pv.dot(hd)
			var s := pv.dot(rt)
			var fu := 0.0
			var fs := 0.0
			if on_wheels:
				fs = -grip * s / sqrt(s * s + EPS * EPS)
				fu = -(ROLL_RES + brake * grip) * u / sqrt(u * u + EPS * EPS)
				var m := sqrt(fu * fu + fs * fs)
				if m > grip:  # the friction circle: no more than the tyre can give all told
					fu *= grip / m
					fs *= grip / m
			else:
				var sp := sqrt(u * u + s * s + EPS * EPS)
				fu = -BODY_MU * u / sp
				fs = -BODY_MU * s / sp
			var f := (hd * fu + rt * fs) * (G * 0.25)
			acc += f
			tq += _turn(r, f) / shape.k2
		vel += acc * dt
		w += tq * dt
	w = clampf(w, -MAX_SPIN, MAX_SPIN)
	pos += vel * dt
	yaw += w * dt
	if not in_air and vel.length_squared() < 0.0009 and absf(w) < 0.01:
		vel = Vector2.ZERO  # at rest
		w = 0.0


# ---------------------------------------------------------------- impacts

## An impact between two bodies at world point p, n pointing from a to b (b = null:
## an immovable wall). Both are changed; returns the size of the impulse (per unit
## of a car's mass, so roughly the change of speed the bump gave a car).
## `e` is the bounce (0 = dead, 1 = rubber), `mu` the friction along the contact,
## `min_sep` the least speed the two are to part at (0 = whatever the bounce gives).
static func impact(a: Wreck, b: Wreck, n: Vector2, p: Vector2, e := 0.2, mu := 0.25, min_sep := 0.0) -> float:
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
	return j / a.mass


## Push two overlapping bodies apart along n (a to b) by `depth`, the lighter one moving more.
static func separate(a: Wreck, b: Wreck, n: Vector2, depth: float) -> void:
	if b == null:
		a.pos -= n * depth
		return
	var ka := b.mass / (a.mass + b.mass)
	a.pos -= n * (depth * ka)
	b.pos += n * (depth * (1.0 - ka))
