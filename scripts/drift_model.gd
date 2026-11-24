class_name DriftModel
extends RefCounted
## The drift tune (a rare boss reward, or Settings › Dev › Drift mode): the player's car as a rear-wheel-drive drift
## car, driven the way a real one is. A single-track ("bicycle") car with a tyre at each axle:
##  - The front tyres' sideways force follows their slip angle on a Pacejka "magic formula" curve: it builds quickly,
##    peaks at about 12 degrees and falls to about 80% of the peak in a full slide. Braking takes some of their grip.
##  - The rear tyres are worked out with combined slip: how fast the driven wheels spin against the road (the slip
##    ratio) and how far the rear of the car is sliding sideways (the slip angle) together give one slip, and the
##    tyre's force points against it. So the power, the grip and the slide blend into each other smoothly: a little
##    wheelspin costs a little sideways grip, a lot of it lets the tail come round, and easing off gives it back.
##  - The rear wheels have a speed of their own (they spin up under power and slow under the brakes and the road's
##    drag), worked out implicitly so it is steady at any speed. The engine's pull falls as the wheels near the top
##    speed, which is the rev limiter: wheelspin never runs away.
##  - The weight moves between the axles as the car speeds up and slows down (springs: it takes a tenth of a second),
##    and each axle grips with the weight on it.
##  - The pedals: GAS is the throttle (it comes in over a fifth of a second, not at once). BRAKE is the handbrake while
##    you throw the car in (steering, and not yet sliding much: it locks the rear wheels and the tail steps out), and
##    the footbrake otherwise (mostly on the front wheels, so braking in a slide moves the weight forward and the angle
##    grows a little, as in a real car; in a slide more of the braking goes to the front, so it never snaps the car round).
##    Steering against a slide with BRAKE held is the handbrake again: the flick into the next drift.
## The drift assist does what CarX Drift Racing's does, all of it gently. As the tail slides it counter-steers for you
## (the front wheels follow where the front of the car is going), and your hand no longer turns the wheels straight
## through: in a slide it asks for an ANGLE. Hands off, the car holds about 36 degrees; steer into the slide and it asks
## for up to 48, steer out of it and it asks for less, down to about 23, and further out the slide ends or (with the
## brake) flicks into the other. Holding GAS holds that angle: it eases the power off as the angle nears it (looking at
## where the angle is heading as well as where it is), and helps the car's yaw towards it, damped. It also keeps a held
## drift running straight: it steers against the line curving away and draws it gently back to the road's direction.
## Past about 46 degrees it leans on the car progressively rather than snapping it back, it steadies the car as a slide
## ends, and while the car runs straight it keeps the rear wheels from spinning up. All of the holding lets go while
## you steer hard the other way, so a flick from one drift into the other is yours.
## Kept apart from the game so it can be tested on its own (tools/drift_test.gd).

const G := 9.81
const LOCK := 0.87          # rad (50 degrees): a drift car's steering angle kit
const MF_C := 1.6           # the tyre curve's shape (Pacejka C)...
const MF_B := 1.49          # ...and B, set so that it peaks at a normalised slip of 1
const FRONT_PEAK := 0.21    # rad (12 degrees): the front tyres' slip angle at their peak
const REAR_PEAK := 0.15     # rad (8.5 degrees): the rear drift tyres', stiffer
const KAPPA_PEAK := 0.11    # the slip ratio at which a tyre drives (or brakes) hardest
const REAR_GRIP := 0.86     # the rear tyres hold this share of the fronts' grip
const POWER := 1.65         # the tune's drive at the rear wheels against the car's own
const CG_H := 0.5           # height of the centre of gravity, m
const FRONT_W := 0.52       # the share of the weight on the front wheels at rest
const WHEEL_J := 0.04       # the rear wheels' and driveline's inertia, as a share of the car's mass (at the tyre)
const HANDBRAKE := 38.0     # m/s² the handbrake slows the rear wheels by (it locks them)
const STEER_RATE := 4.5     # rad/s the front wheels turn, by hand and assist together
const THROTTLE_IN := 5.0    # 1/s: how fast the throttle opens...
const THROTTLE_OUT := 7.0   # ...and closes
const MIN_V := 4.0          # m/s: slower than this the car is driven as an ordinary one (SteerModel)
# the drift assist
const ASSIST_CS := 0.9      # how much of the counter-steer it puts on (1: the front wheels point where the front is going)
const ASSIST_HAND := 0.3    # how much of the hand's steering turns the front wheels in a full slide (it also sets the angle: ANGLE_BASE)
const MAX_ANGLE := 0.8      # rad (46 degrees): past this it leans on the car...
const LIMIT_K := 14.0       # ...this hard (rad/s² for each radian past it, growing with it)
const LIMIT_DAMP := 3.5     # ...and takes out the swing that is carrying it further, this much
const ANGLE_BASE := 0.62    # rad (36 degrees): the drift angle it holds with your hands off...
const ANGLE_RANGE := 0.22   # ...more (up to 48) steering into the slide, less (down to 23) steering out of it
const HOLD_SPAN := 0.18     # rad: it eases the power off over this much past the angle asked for
const LINE_D := 0.18        # rad of steering for each rad/s the line is curving away: a held drift runs straight...
const LINE_P := 0.06        # ...and is drawn gently back towards the road's direction (rad of steering per rad off it)
const ANGLE_K := 10.0       # rad/s² for each rad short of the angle asked for, while GAS holds a slide: it helps hold it...
const ANGLE_D := 1.2        # ...damped (per rad/s of the angle changing), so it settles rather than swings
const HOLD_LEAD := 0.45     # s: ...looking this far ahead at the way the angle is going
const TRACTION := 0.8       # running straight, it lets the rear tyres put down this share of their grip as drive
const GRIP_SPAN := 1.6      # running straight, a full movement of the hand asks for this much more than the tyres hold
const SETTLE := 1.4         # 1/s of yaw damping it adds as a slide ends (no tank-slapper on the way out)


## A fresh state for a car with the tune (what the model keeps between steps). wr < 0: the wheels' speed is not yet set.
static func state() -> Dictionary:
	return {"throttle": 0.0, "ax": 0.0, "spin": 0.0, "slide": 0.0, "beta": 0.0, "lat": 0.0, "handbrake": false, "hb_t": 9.0, "wr": -1.0, "bp": 0.0, "db": 0.0,
		"cp": 0.0, "dc": 0.0, "target": ANGLE_BASE}


## The drift angle: how far the car's direction of travel is from where its nose points (radians, + = sliding to its
## right, which is the nose pointing left of where it goes).
static func angle(p: Object) -> float:
	return wrapf(float(p.course) - float(p.yaw), -PI, PI)


## The tyre curve, 0 .. 1 of the grip, for a slip normalised to the peak (1 at the peak).
static func _mf(s: float) -> float:
	return sin(MF_C * atan(MF_B * s))


## The rear tyres' force (per unit mass: x along the car, y across it) at wheel speed `wr`, the car moving at `u`
## along itself and its rear sliding sideways at slip angle `ar`, with `cap` of grip.
static func _rear(wr: float, u: float, ar: float, cap: float) -> Vector2:
	var sx := (wr - u) / maxf(absf(u), 3.0) / KAPPA_PEAK
	var sy := tan(clampf(ar, -1.4, 1.4)) / tan(REAR_PEAK)
	var sm := sqrt(sx * sx + sy * sy)
	if sm < 0.000001:
		return Vector2.ZERO
	var f := cap * _mf(sm)
	return Vector2(f * sx / sm, -f * sy / sm)


## One step. `p` is the player's car (v: speed, yaw: heading, course: direction of travel, yaw_rate, steer: the
## front wheels' angle; radians, + to the right); `st` its stats (CarStats.compute); `wheelbase` in metres; `cmd`
## the hand's steering (-1 .. 1), `gas` and `brk` the pedals, `assist` the drift assist; `s` the model's state.
## Moves nothing: the game moves the car along p.course at p.v.
static func drive(p: Object, dt: float, st: Dictionary, wheelbase: float, cmd: float, gas: bool, brk: bool, assist: bool, s: Dictionary) -> void:
	var n := maxi(1, ceili(dt / (1.0 / 240.0)))
	var h := dt / float(n)
	var L := maxf(wheelbase, 1.5)
	var a := L * (1.0 - FRONT_W)   # the centre of gravity to the front axle...
	var b := L - a                 # ...and to the rear
	var k2 := a * b * 0.95         # yaw inertia per unit mass
	var mu := float(st.grip) / G
	var mu_r := mu * REAR_GRIP
	cmd = clampf(cmd, -1.0, 1.0)
	s.throttle = move_toward(float(s.throttle), 1.0 if gas else 0.0, (THROTTLE_IN if gas else THROTTLE_OUT) * dt)
	if float(s.wr) < 0.0:
		s.wr = float(p.v) * cos(angle(p))
	# the brake pedal: the handbrake to throw the car in (steering, at speed, not yet well into a slide); the footbrake
	# otherwise
	var beta0 := absf(angle(p))
	var out := cmd * signf(angle(p)) > 0.3 and beta0 > 0.1   # (steering against the slide: the way into the next one)
	var handbrake: bool = brk and float(p.v) > 6.0 and ((beta0 < 0.32 and (absf(cmd) > 0.3 or beta0 > 0.06)) or out)
	s.hb_t = 0.0 if handbrake else float(s.hb_t) + dt
	for _i in n:
		var v: float = p.v
		var beta := angle(p)
		var u := v * cos(beta)
		var vy := v * sin(beta)
		var r: float = p.yaw_rate
		var uu := maxf(absf(u), 0.5)
		var slide := smoothstep(0.08, 0.35, absf(beta))
		s.db = lerpf(float(s.db), (beta - float(s.bp)) / h, minf(1.0, h / 0.08))   # (how fast the angle is changing, smoothed)
		s.bp = beta
		s.dc = lerpf(float(s.dc), wrapf(float(p.course) - float(s.cp), -PI, PI) / h, minf(1.0, h / 0.1))   # (and the line, curving)
		s.cp = float(p.course)
		# the angle asked for: steering into the slide (the way the nose points) asks for more, out of it for less
		var into := -cmd * signf(beta)
		s.target = clampf(ANGLE_BASE + ANGLE_RANGE * into, 0.4, MAX_ANGLE - 0.02)
		# steering: the hand (speed-sensitive while the tyres grip, the full lock in a slide or at a crawl), and (assist)
		# the counter-steer that points the front wheels where the front is going
		var front_dir := atan2(vy + a * r, uu)
		var span := clampf(atan(mu * G * L / maxf(v * v, 1.0)) * GRIP_SPAN, 0.04, LOCK)
		var open := maxf(pow(slide, 1.5), 1.0 - smoothstep(6.0, 14.0, v))
		if float(s.hb_t) < 0.4:
			open = maxf(open, 0.5)   # (with the handbrake pulled the wheel has the lock to throw the car in)
		var want := cmd * lerpf(span, LOCK, open)
		if assist:
			want = front_dir * ASSIST_CS * slide + want * lerpf(1.0, ASSIST_HAND, slide)
			# the line: in a slide it steers against the line curving away, so a held drift runs straight down the road
			want -= slide * (float(s.dc) * LINE_D + wrapf(float(p.course), -PI, PI) * LINE_P)
		p.steer = move_toward(float(p.steer), clampf(want, -LOCK, LOCK), STEER_RATE * h)
		var d: float = p.steer
		# the weight on each axle (per unit mass, m/s²): more on the rear under power, on the front when slowing
		var ax: float = s.ax
		var nf := maxf(G * FRONT_W - ax * CG_H / L, 0.8)
		var nr := maxf(G * (1.0 - FRONT_W) + ax * CG_H / L, 0.8)
		var cap_f := mu * nf
		var cap_r := mu_r * nr
		# the engine at the rear wheels (its pull falls as they near the top speed: the rev limiter)
		var wr: float = s.wr
		var drive := float(s.throttle) * CarStats.thrust(st, maxf(wr, 0.0)) * POWER
		if assist:
			if slide > 0.0:   # it eases off as the angle passes the one asked for (where it is heading, not only where it is): holding GAS holds the drift
				var ahead := absf(beta) + signf(beta) * float(s.db) * HOLD_LEAD
				drive *= clampf(1.0 - (ahead - float(s.target)) / HOLD_SPAN, 0.15, 1.0)
			if slide < 0.2 and absf(cmd) < 0.7 and float(s.hb_t) > 1.0:
				drive = minf(drive, cap_r * TRACTION)   # (no drift asked for: no wheelspin on the straight)
		# the brakes: the footbrake mostly on the front, the handbrake on the rear wheels
		var brk_f := 0.0
		var brk_r := 0.0
		if handbrake:
			brk_r = HANDBRAKE
		elif brk:
			var bk := CarStats.braking(st, v)
			var rear := lerpf(0.35, 0.22, slide)   # (in a slide the brakes are balanced to the front: no snap)
			brk_f = bk * (1.0 - rear)
			brk_r = bk * rear
		# the front tyres
		var fx_f := -minf(brk_f, cap_f * 0.95) * signf(u)
		var lat_f := sqrt(maxf(cap_f * cap_f - fx_f * fx_f, 0.0))
		var af := front_dir - d
		var fy_f := -lat_f * _mf(absf(af) / FRONT_PEAK) * signf(af)
		# the rear tyres, combined slip, and the rear wheels' speed (implicit: steady however stiff the tyre is)
		var ar := atan2(vy - b * r, uu)
		var fr := _rear(wr, u, ar, cap_r)
		var kk := maxf((_rear(wr + 0.05, u, ar, cap_r).x - fr.x) / 0.05, 0.0)
		wr += h / WHEEL_J * (drive - fr.x) / (1.0 + h * kk / WHEEL_J)
		if brk_r > 0.0:
			wr = move_toward(wr, 0.0, brk_r * h / WHEEL_J)   # (the brake torque against the wheel; the road turns it back)
		wr = maxf(wr, 0.0)
		s.wr = wr
		fr = _rear(wr, u, ar, cap_r)
		var fx_r := fr.x
		var fy_r := fr.y
		# the car: forces in its own frame (x forward, y right), turning with it
		var dg := CarStats.drag(v)
		var dx := dg * u / maxf(v, 0.1)
		var dy := dg * vy / maxf(v, 0.1) * 2.5   # (side-on the air and the rolling tyres take more)
		var fx := fx_r + fx_f * cos(d) - fy_f * sin(d) - dx
		var fy := fy_r + fy_f * cos(d) + fx_f * sin(d) - dy
		var dr := (a * (fy_f * cos(d) + fx_f * sin(d)) - b * fy_r) / k2
		if assist:
			# past the limit it leans on the car, harder the further past, and takes out the swing carrying it on
			var over := absf(beta) - MAX_ANGLE
			if over > 0.0:
				dr += signf(beta) * over * LIMIT_K * (1.0 + over * 4.0)
			var past := smoothstep(MAX_ANGLE - 0.15, MAX_ANGLE + 0.1, absf(beta))
			if r * signf(beta) < 0.0:
				dr -= r * LIMIT_DAMP * past
			dr -= r * SETTLE * (1.0 - slide) * smoothstep(0.0, 0.1, absf(beta))
			# holding the angle asked for while GAS holds the slide (the nose is turned towards it: + yaw lowers beta)
			var hold := slide * float(s.throttle) * smoothstep(-0.75, -0.35, -cmd * signf(beta))   # (let go when the hand swings it the other way)
			if hold > 0.0:
				dr -= signf(beta) * (float(s.target) - absf(beta)) * ANGLE_K * hold - float(s.db) * ANGLE_D * hold
		u += (fx + vy * r) * h
		vy += (fy - u * r) * h
		r += dr * h
		s.ax = lerpf(ax, fx, minf(1.0, h / 0.1))   # (the springs: the weight moves over a tenth of a second)
		p.yaw_rate = r
		p.yaw = float(p.yaw) + r * h
		var nv := sqrt(u * u + vy * vy)
		p.v = nv
		if nv > 0.05:
			p.course = float(p.yaw) + atan2(vy, u)
		s.spin = clampf(((wr - u) / maxf(absf(u), 3.0) - KAPPA_PEAK) / 0.4, 0.0, 1.0)
		s.lat = fy
	s.slide = smoothstep(0.08, 0.35, absf(angle(p)))
	s.beta = angle(p)
	s.handbrake = handbrake
