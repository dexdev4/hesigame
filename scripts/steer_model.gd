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

const LOCK := 0.6           # most the front wheels can turn, radians
const WHEEL_RATE := 40.0    # how fast the wheels follow the command, in spans per second
const YAW_GAIN := 60.0      # how fast the nose settles on the turn rate the wheels ask for, 1/s
const COURSE_GAIN := 40.0   # how fast the direction of travel follows the nose (the tyres biting), 1/s
const TYRE_PEAK := 1.25     # the tyres hold this much more sideways force than the steering asks for


static func feel(id: String) -> Dictionary:
	return FEELS.get(id, FEELS.standard)


## The most sideways acceleration (m/s^2) the steering will ask for at this
## grip: what a full-lock command gives.
static func usable(grip: float, auth: float) -> float:
	return grip * auth


## The front-wheel angle a full command means at speed v (radians): the angle
## at which the tyres give about 95 % of the usable grip, never more than the lock.
static func span(grip: float, auth: float, wheelbase: float, v: float) -> float:
	return minf(LOCK, atan(usable(grip, auth) * wheelbase / maxf(v * v, 0.01)) * 0.95)


## One step of the player's car. `p` is any object with steer, yaw_rate, yaw
## and course (radians, radians/s); `grip` is the car's sideways grip right now
## (after braking, the verge and so on) and `wheelbase` in metres.
static func drive(p: Object, dt: float, v: float, grip: float, auth: float, wheelbase: float, cmd: float, assist: bool) -> void:
	var sp := span(grip, auth, wheelbase, v)
	var want := clampf(cmd, -1.0, 1.0) * sp
	if absf(cmd) < 0.001 and assist and v > 3.0:
		# steering assist: ease the nose back parallel to the road
		want = clampf(atan(-p.yaw * 1.6 * wheelbase / maxf(v, 0.5)), -sp * 0.5, sp * 0.5)
	if v < 0.2:
		want = p.steer if absf(cmd) < 0.001 else clampf(cmd, -1.0, 1.0) * LOCK  # parked: the wheels turn but the car does not
	p.steer = move_toward(p.steer, want, maxf(sp, 0.06) * WHEEL_RATE * dt)
	# the nose: turn rate from the wheel angle, reached with a very short lag (the car's weight)
	var r_want: float = v * tan(p.steer) / wheelbase
	p.yaw_rate = lerpf(p.yaw_rate, r_want, minf(1.0, dt * YAW_GAIN))
	p.yaw = clampf(p.yaw + p.yaw_rate * dt, -0.7, 0.7)
	# the direction of travel follows the nose as fast as the tyres can push it
	# round (sideways force = speed x turn rate); past that the car slides
	var slip: float = p.yaw - p.course
	var max_turn := usable(grip, auth) / maxf(v, 1.0)
	p.course += clampf(slip * COURSE_GAIN, -max_turn * TYRE_PEAK, max_turn * TYRE_PEAK) * dt
	p.course = clampf(p.course, -0.7, 0.7)
