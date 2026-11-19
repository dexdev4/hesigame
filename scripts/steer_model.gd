class_name SteerModel
extends RefCounted
## How the player's car answers the steering: a bicycle model (the car turns
## only by rolling forward on turned front wheels) with a tyre grip limit. It
## is kept apart from the game so it can be tested on its own (tools/steer_test.gd).
##
## The command (-1 .. 1) asks for a share of the sideways grip the steering may
## use at the current speed, so the same push feels alike at 60 and 200 km/h.
## The wheels, the nose and the direction of travel then follow it with short
## lags (tens of milliseconds), so the car's sideways speed builds as fast as
## the tyres allow and the first movement is visible straight away.

## Feel presets (Settings > Steering response). `auth` is how much of the car's
## grip stat the steering may use (an arcade highway racer lets the driver lean
## harder on the tyres than a road car would), `lead` how many seconds ahead of
## the hand a quick movement is answered (see SteerInput.boosted).
const FEELS := {
	"relaxed": {"auth": 1.05, "lead": 0.03, "label": "RELAXED"},
	"standard": {"auth": 1.4, "lead": 0.08, "label": "STANDARD"},
	"sharp": {"auth": 1.75, "lead": 0.11, "label": "SHARP"},
}
const FEEL_ORDER := ["relaxed", "standard", "sharp"]

const LOCK := 0.52          # most the front wheels can turn, radians (the tightest turn is about 4.6 m in radius)
const WHEEL_RATE := 40.0    # how fast the wheels follow the command at speed, in spans per second
const YAW_GAIN := 60.0      # how fast the nose settles on the turn rate the wheels ask for at speed, 1/s
const COURSE_GAIN := 40.0   # how fast the direction of travel follows the nose (the tyres biting) at speed, 1/s
const TYRE_PEAK := 1.25     # the tyres hold this much more sideways force than the steering asks for

## Below about 70 km/h the car steers the way a real one does, and the steering gets quicker and sharper
## towards highway speed (from SLOW_V1 up it is as it always was):
##  - a hand turns the front wheels at SLOW_SLEW, so lock to lock takes about a second, not a twentieth of one;
##  - a full command asks for SLOW_ACCEL of sideways acceleration (a brisk, comfortable turn) instead of all the
##    grip, so the car does not whip round at parking speeds;
##  - the nose and the direction of travel take their time (a tyre needs to roll about half a metre to build its
##    force, which is longer the slower the car goes).
const SLOW_SLEW := 1.1      # rad/s
const SLOW_ACCEL := 5.5     # m/s² at the standard feel on a car with 9.2 of grip
const SLOW_V0 := 5.0        # m/s: below this the steering is as slow as it gets
const SLOW_V1 := 20.0       # m/s: from this up it is as it always was
const SLEW_V0 := 9.0        # m/s: the wheels stay as slow as a hand until about 30 km/h, and are quick again by SLOW_V1+2


static func feel(id: String) -> Dictionary:
	return FEELS.get(id, FEELS.standard)


## The most sideways acceleration (m/s^2) the steering will ask for at this
## grip: what a full-lock command gives.
static func usable(grip: float, auth: float) -> float:
	return grip * auth


## 0 at a crawl, 1 from highway speed: how much of the quick, sharp steering the car has at speed v.
static func blend(v: float) -> float:
	return smoothstep(SLOW_V0, SLOW_V1, v)


## What a full command asks for at speed v: gentle at a crawl, all the usable grip from SLOW_V1 up.
static func usable_at(grip: float, auth: float, v: float) -> float:
	var full := usable(grip, auth)
	var slow := minf(full, SLOW_ACCEL * (auth / 1.4) * sqrt(grip / 9.2))
	return lerpf(slow, full, blend(v))


## The front-wheel angle a full command means at speed v (radians): the angle
## at which the tyres give about 95 % of the usable grip, never more than the lock.
static func span(grip: float, auth: float, wheelbase: float, v: float) -> float:
	return minf(LOCK, atan(usable_at(grip, auth, v) * wheelbase / maxf(v * v, 0.01)) * 0.95)


## What the car makes of the hand's command: the gain is how much a small movement of the hand counts for (1 is the
## reference car's; a twitchy car's is over 1, a calm one's under it). A full command is a full command in every
## car, and the curve is smooth and gentle about the middle (its slope there is the gain, at the ends 1 / gain), so a
## hand that is not quite still does not set a twitchy car wandering.
static func shape_cmd(cmd: float, gain: float) -> float:
	var c := clampf(cmd, -1.0, 1.0)
	if absf(gain - 1.0) < 0.001:
		return c
	var a := absf(c)
	return signf(c) * gain * a / (1.0 + (gain - 1.0) * a)


## One step of the player's car. `p` is any object with steer, yaw_rate, yaw
## and course (radians, radians/s); `grip` is the car's sideways grip right now
## (after braking, the verge and so on) and `wheelbase` in metres. `gain` and
## `quick` are the car's agility (CarStats): the gain of the steering about the
## middle (see shape_cmd) and how much faster (or slower) than the reference car
## the wheels, the nose and the direction of travel follow it at speed.
static func drive(p: Object, dt: float, v: float, grip: float, auth: float, wheelbase: float, cmd: float, assist: bool, gain := 1.0, quick := 1.0) -> void:
	var sp := span(grip, auth, wheelbase, v)
	var want := shape_cmd(cmd, gain) * sp
	if absf(cmd) < 0.001 and assist and v > 3.0:
		# steering assist: ease the nose back parallel to the road
		want = clampf(atan(-p.yaw * 1.6 * wheelbase / maxf(v, 0.5)), -sp * 0.5, sp * 0.5)
	if v < 0.2:
		want = p.steer if absf(cmd) < 0.001 else clampf(cmd, -1.0, 1.0) * LOCK  # parked: the wheels turn but the car does not
	var k := blend(v)
	var q := lerpf(1.0, quick, k)  # (the car's own quickness shows at speed; at a crawl they all steer alike)
	p.steer = move_toward(p.steer, want, lerpf(SLOW_SLEW, maxf(sp, 0.06) * WHEEL_RATE * quick, smoothstep(SLEW_V0, SLOW_V1 + 2.0, v)) * dt)
	# the nose: turn rate from the wheel angle, reached with a short lag (the car's weight; longer at a crawl)
	var r_want: float = v * tan(p.steer) / wheelbase
	p.yaw_rate = lerpf(p.yaw_rate, r_want, minf(1.0, dt * lerpf(clampf(v * 1.8, 8.0, YAW_GAIN), YAW_GAIN, k) * q))
	p.yaw = clampf(p.yaw + p.yaw_rate * dt, -0.7, 0.7)
	# the direction of travel follows the nose as fast as the tyres can push it
	# round (sideways force = speed x turn rate); past that the car slides
	var slip: float = p.yaw - p.course
	var max_turn := usable_at(grip, auth, v) / maxf(v, 1.0)
	var course_gain := lerpf(clampf(v * 2.2, 8.0, COURSE_GAIN), COURSE_GAIN, k) * q
	p.course += clampf(slip * course_gain, -max_turn * TYRE_PEAK, max_turn * TYRE_PEAK) * dt
	p.course = clampf(p.course, -0.7, 0.7)
