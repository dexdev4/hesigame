class_name DriftModel
extends RefCounted
## The drift tune (a rare boss reward): the player's car as a rear-wheel-drive drift car, driven the way a real one
## is. It is a single-track ("bicycle") car with a tyre at each axle:
##  - each tyre's sideways force follows its slip angle (the angle between where it points and where it is going)
##    on a curve like a real tyre's (a simplified Pacejka "magic formula"): it builds quickly, peaks at 10 to 14
##    degrees and falls to about 83% of the peak in a full slide;
##  - the engine drives the rear wheels, and a tyre has only so much grip all told (the friction circle): what it
##    puts down as drive it cannot give sideways, and once the drive asks for more than it has, it spins and holds
##    little sideways at all. So the throttle steers the car: more of it swings the tail wider, less lets it come back;
##  - the weight moves between the axles as the car speeds up and slows down (more on the rear wheels under power,
##    more on the front when braking or lifting off), and each axle grips with the weight on it;
##  - the tune: a big steering angle (50 degrees), more power at the rear wheels, and drift tyres on the back that
##    are stiff while they grip (so the car runs straight and true at speed) but let go sooner (so it slides when
##    you ask it to). The brake pedal is the handbrake while you steer or slide (it locks the rear wheels), the
##    footbrake when you run straight.
## The steering is speed-sensitive while the tyres grip (a full movement of the hand asks for about what they can
## hold at that speed, as in the game's ordinary steering) and opens up to the full lock as the car slides.
## The drift assist does what CarX Drift Racing's does: as the tail slides it counter-steers for you (it points the
## front wheels where the front of the car is going, and your steering is added to that), it stops the angle running
## away into a spin past MAX_ANGLE, it steadies the car as a slide ends, and while the car runs straight it keeps the
## rear wheels from spinning up (so flat out on a straight is not a spin); steer or slide and the power is all yours.
## Everything else is the physics: you start a slide (the handbrake with the wheel turned, or power in a turn), hold
## it with the throttle and steer the angle and the line. On a straight road a drift is never a steady thing (a car
## sliding sideways is always turning), so it is a weave: one way, then flicked into the other.
## Kept apart from the game so it can be tested on its own (tools/drift_test.gd).

const G := 9.81
const LOCK := 0.87          # rad (50 degrees): a drift car's steering angle kit
const TYRE_C := 1.5         # the shape of the tyre curve (with B: where it peaks, and how far it falls past the peak)
const FRONT_B := 7.0        # the front tyres' stiffness: peak at 14 degrees of slip
const REAR_B := 10.0        # the rear drift tyres': stiffer while they grip (the car is stable when it runs straight), peak at 10
const REAR_GRIP := 0.84     # ...and they let go sooner: they hold this much of the fronts' grip
const POWER := 1.35         # the tune's drive at the rear wheels against the car's own
const SPIN_LAT := 0.3       # a spinning or locked tyre still holds this share of its grip sideways
const CG_H := 0.5           # height of the centre of gravity, m (how much weight moves between the axles)
const FRONT_W := 0.52       # the share of the weight on the front wheels at rest
const STEER_RATE := 5.5     # rad/s the front wheels turn, by hand and assist together
const MIN_V := 4.0          # m/s: slower than this the car is driven as an ordinary one (SteerModel)
# the drift assist
const ASSIST_CS := 0.9      # how much of the counter-steer it puts on (1: the front wheels point where the front is going)
const ASSIST_HAND := 0.42   # how much of the hand's steering counts in a full slide (the rest is the assist's)
const MAX_ANGLE := 0.87     # rad (50 degrees): past this it stops the car spinning round...
const LIMIT_K := 30.0       # ...this hard (rad/s² for each radian past it)
const TRACTION := 0.8       # running straight, it lets the rear tyres put down this share of their grip as drive
const GRIP_SPAN := 1.6      # running straight, a full movement of the hand asks for this much more than the tyres hold
const SETTLE := 1.5         # 1/s of yaw damping it adds as a slide ends (no tank-slapper on the way out)


## A fresh state for a car with the tune (what the model keeps between steps).
static func state() -> Dictionary:
	return {"throttle": 0.0, "ax": 0.0, "spin": 0.0, "slide": 0.0, "beta": 0.0, "lat": 0.0, "handbrake": false, "hb_t": 9.0}


## The drift angle: how far the car's direction of travel is from where its nose points (radians, + = sliding to its
## right, which is the nose pointing left of where it goes).
static func angle(p: Object) -> float:
	return wrapf(float(p.course) - float(p.yaw), -PI, PI)


## One step. `p` is the player's car (v: speed, yaw: heading, course: direction of travel, yaw_rate, steer: the
## front wheels' angle; radians, + to the right); `st` its stats (CarStats.compute: grip, accel, top, pull, brake);
## `wheelbase` in metres; `cmd` the hand's steering (-1 .. 1), `gas` and `brk` the pedals, `assist` the drift assist;
## `s` the model's state (state()). Moves nothing: the game moves the car along p.course at p.v.
static func drive(p: Object, dt: float, st: Dictionary, wheelbase: float, cmd: float, gas: bool, brk: bool, assist: bool, s: Dictionary) -> void:
	var n := maxi(1, ceili(dt / (1.0 / 240.0)))
	var h := dt / float(n)
	var L := maxf(wheelbase, 1.5)
	var a := L * (1.0 - FRONT_W)   # the centre of gravity to the front axle...
	var b := L - a                 # ...and to the rear
	var k2 := a * b * 0.95         # yaw inertia per unit mass
	var mu := float(st.grip) / G
	var mu_r := mu * REAR_GRIP
	s.throttle = move_toward(float(s.throttle), 1.0 if gas else 0.0, (5.0 if gas else 8.0) * dt)
	cmd = clampf(cmd, -1.0, 1.0)
	s.hb_t = 0.0 if (brk and (absf(cmd) > 0.25 or absf(angle(p)) > 0.1)) else float(s.hb_t) + dt   # (how long since the handbrake was pulled)
	for _i in n:
		var v: float = p.v
		var beta := angle(p)
		var u := v * cos(beta)
		var vy := v * sin(beta)
		var r: float = p.yaw_rate
		var uu := maxf(absf(u), 0.5)
		var slide := smoothstep(0.05, 0.3, absf(beta))
		# steering: the hand (speed-sensitive while the tyres grip, the full lock in a slide or at a crawl), and
		# (assist) the counter-steer that points the front wheels where the front is going
		var front_dir := atan2(vy + a * r, uu)
		var span := clampf(atan(mu * G * L / maxf(v * v, 1.0)) * GRIP_SPAN, 0.04, LOCK)
		var open := maxf(pow(slide, 1.5), 1.0 - smoothstep(6.0, 14.0, v))
		if float(s.hb_t) < 0.4:
			open = maxf(open, 0.5)   # (with the handbrake pulled the wheel has the lock to throw the car in)
		var want := cmd * lerpf(span, LOCK, open)
		if assist:
			want = front_dir * ASSIST_CS * slide + want * lerpf(1.0, ASSIST_HAND, slide)
		p.steer = move_toward(float(p.steer), clampf(want, -LOCK, LOCK), STEER_RATE * h)
		var d: float = p.steer
		# the weight on each axle (per unit mass, m/s²): more on the rear under power, on the front when slowing
		var ax: float = s.ax
		var nf := maxf(G * FRONT_W - ax * CG_H / L, 0.8)
		var nr := maxf(G * (1.0 - FRONT_W) + ax * CG_H / L, 0.8)
		var cap_f := mu * nf
		var cap_r := mu_r * nr
		# the pedals: drive at the rear wheels; the brake is the handbrake while steering or sliding, else the footbrake
		var handbrake := brk and (absf(cmd) > 0.25 or absf(beta) > 0.1)
		var fx_f := 0.0
		var fx_r := float(s.throttle) * CarStats.thrust(st, v) * POWER
		var spin := 0.0
		if handbrake:
			fx_r = -cap_r * 0.9 * signf(u)
			spin = 1.0
		elif brk:
			var bk := CarStats.braking(st, v)
			fx_f = -minf(bk * 0.65, cap_f * 0.95) * signf(u)
			fx_r = -minf(bk * 0.35, cap_r * 0.95) * signf(u)
		else:
			if assist and slide < 0.2 and absf(cmd) < 0.7 and float(s.hb_t) > 1.0:
				fx_r = minf(fx_r, cap_r * TRACTION)   # (no drift asked for: the assist keeps the wheels from spinning up)
			if fx_r > cap_r:
				spin = clampf((fx_r - cap_r) / (cap_r * 0.5), 0.0, 1.0)   # (wheelspin)
				fx_r = cap_r * 0.95
		var lat_f := sqrt(maxf(cap_f * cap_f - fx_f * fx_f, 0.0))
		var lat_r := sqrt(maxf(cap_r * cap_r - fx_r * fx_r, cap_r * cap_r * SPIN_LAT * SPIN_LAT))
		if spin > 0.0:
			lat_r = lerpf(lat_r, cap_r * SPIN_LAT, spin)
		# the tyres
		var af := front_dir - d
		var ar := atan2(vy - b * r, uu)
		var fy_f := -lat_f * sin(TYRE_C * atan(FRONT_B * af))
		var fy_r := -lat_r * sin(TYRE_C * atan(REAR_B * ar))
		# the car: forces in its own frame (x forward, y right), turning with it
		var dg := CarStats.drag(v)
		var dx := dg * u / maxf(v, 0.1)
		var dy := dg * vy / maxf(v, 0.1) * 2.5   # (side-on the air and the rolling tyres take more)
		var fx := fx_r + fx_f * cos(d) - fy_f * sin(d) - dx
		var fy := fy_r + fy_f * cos(d) + fx_f * sin(d) - dy
		var dr := (a * (fy_f * cos(d) + fx_f * sin(d)) - b * fy_r) / k2
		if assist:
			var over := absf(beta) - MAX_ANGLE
			if over > 0.0:
				dr += signf(beta) * over * LIMIT_K   # (the spin is stopped: the nose is brought back round...)
				if r * signf(beta) < 0.0:
					dr -= r * 4.0   # (...and its swing taken out)
			dr -= r * SETTLE * (1.0 - slide) * smoothstep(0.0, 0.1, absf(beta))
		u += (fx + vy * r) * h
		vy += (fy - u * r) * h
		r += dr * h
		s.ax = lerpf(ax, fx, 0.15)
		p.yaw_rate = r
		p.yaw = float(p.yaw) + r * h
		var nv := sqrt(u * u + vy * vy)
		p.v = nv
		if nv > 0.05:
			p.course = float(p.yaw) + atan2(vy, u)
		s.spin = spin
		s.lat = fy
	s.slide = smoothstep(0.05, 0.3, absf(angle(p)))
	s.beta = angle(p)
	s.handbrake = brk and (absf(cmd) > 0.25 or absf(angle(p)) > 0.1)
