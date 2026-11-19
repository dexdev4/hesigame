class_name SteerInput
extends RefCounted
## Turns what the player's hand does (tilting the phone, a stick, an on-screen
## wheel, a swipe...) into the steering command, -1 (full left) .. 1 (full
## right), with as little delay as the sensors allow:
##
## - a smooth dead zone (nothing is lost to a jump when the hand leaves it),
## - tilt is read through a one-euro filter: very steady when the hand is
##   still, hardly any lag when it moves, plus a short look-ahead that makes up
##   for the sensor's own delay,
## - "boosted": a quick movement of the hand is answered a little ahead of
##   itself, so a decisive flick gets a decisive turn-in and the car starts
##   moving at once, while a slow steady input is left exactly as it is.
## It is kept apart from the game so it can be tested on its own (tools/steer_test.gd).

const TILT_FULL := 16.0        # degrees of tilt that mean full lock
const TILT_DEAD := 0.9         # degrees of tilt that count as straight ahead (the default of the Settings slider)
const TILT_MIN_CUTOFF := 1.5   # Hz: how hard sensor jitter is filtered while the hand is still
const TILT_BETA := 0.25        # ...and how fast that opens up with the hand's speed (Hz per degree/second)
const TILT_D_CUTOFF := 5.0     # Hz: smoothing of the speed estimate itself
const TILT_AHEAD := 0.015      # seconds the angle is extrapolated to make up for the sensor's delay
const TILT_AHEAD_MAX := 3.0    # ...but never by more than this many degrees
const EXPO := 1.1              # small commands are softened a touch for fine corrections
const RATE_LP := 40.0          # Hz: smoothing of the command's rate of change
const BOOST_MAX := 0.6         # most a quick movement adds to the command

var tilt_dead := TILT_DEAD     # degrees of tilt that count as straight ahead (Settings > Dead zones)
var _tilt_x := 0.0             # filtered tilt, degrees
var _tilt_dx := 0.0            # its speed, degrees per second
var _tilt_raw := 0.0
var _tilt_init := false
var _prev := 0.0               # the command last time, for its rate of change
var _rate := 0.0
var _prev_init := false


func reset() -> void:
	_tilt_init = false
	_prev_init = false
	_tilt_dx = 0.0
	_rate = 0.0


## Nothing inside the dead zone, then straight up to 1: no jump at its edge.
static func dead(x: float, dz: float) -> float:
	var a := absf(x)
	return 0.0 if a <= dz else signf(x) * minf((a - dz) / (1.0 - dz), 1.0)


## Sensitivity and the response curve.
static func shape(raw: float, sens: float) -> float:
	var c := clampf(raw * sens, -1.0, 1.0)
	return signf(c) * pow(absf(c), EXPO)


static func _alpha(cutoff: float, dt: float) -> float:
	var tau := 1.0 / (TAU * cutoff)
	return 1.0 / (1.0 + tau / maxf(dt, 0.0001))


## The phone's tilt (radians from where it was held at the start) as a raw
## command, -1 .. 1: filtered, looked ahead and passed through the dead zone.
## `spin` is how fast the phone is turning (radians/second, from the gyroscope,
## 0 if it has none): the filter opens up the moment the hand starts to move,
## without waiting for the accelerometer to show it. Only its size is used.
func tilt(angle: float, dt: float, spin := 0.0) -> float:
	var deg := rad_to_deg(angle)
	if not _tilt_init:
		_tilt_init = true
		_tilt_x = deg
		_tilt_raw = deg
		_tilt_dx = 0.0
	_tilt_dx += ((deg - _tilt_raw) / maxf(dt, 0.0001) - _tilt_dx) * _alpha(TILT_D_CUTOFF, dt)
	_tilt_raw = deg
	var speed := maxf(absf(_tilt_dx), rad_to_deg(absf(spin)))
	_tilt_x += (deg - _tilt_x) * _alpha(TILT_MIN_CUTOFF + TILT_BETA * speed, dt)
	var ahead := _tilt_x + clampf(TILT_AHEAD * _tilt_dx, -TILT_AHEAD_MAX, TILT_AHEAD_MAX)
	return dead(ahead / TILT_FULL, clampf(tilt_dead, 0.0, TILT_FULL * 0.5) / TILT_FULL)


## A quick movement of the command gets a little more than it asked for,
## `lead` seconds' worth of its own speed, then settles on what was asked.
func boosted(c: float, dt: float, lead: float) -> float:
	if not _prev_init:
		_prev_init = true
		_prev = c
		_rate = 0.0
	_rate += ((c - _prev) / maxf(dt, 0.0001) - _rate) * (1.0 - exp(-dt * RATE_LP))
	_prev = c
	var b := clampf(lead * _rate, -BOOST_MAX, BOOST_MAX)
	if c == 0.0:
		b = 0.0  # nothing asked for, nothing added: letting go never steers the other way
	elif b * c < 0.0:
		b = signf(b) * minf(absf(b), absf(c) * 0.6)  # unwinding: helps the command back, but never to the other side
	return clampf(c + b, -1.0, 1.0)
