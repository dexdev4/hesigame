class_name CarStats
extends RefCounted
## What a car can do, worked out from its row in Data.CARS, the upgrades bought for it, the boons picked up in the run
## and its damage. The game, the garage and tools/roster_test.gd all use these sums, so what the garage says is what
## the car does. The Pulse is the reference car: all its traits are neutral (1.0, 3.0, 1,400 kg), so a car with the
## table's defaults drives exactly as every car did before the traits existed.
##
## The traits, and what each one does to the driving:
##  - accel, pull: the engine pulls with `accel` m/s² from a standstill and keeps `1 - (v/top)^pull` of it at speed v.
##    A low `pull` (a big torquey V8) is strong low down and fades early; a high one (a car that revs and breathes
##    through the top end, or a turbo that wakes up late) holds on to its pull and keeps going to the top.
##  - top: the speed it is trying to reach (drag holds it a few per cent short: `terminal_speed`).
##  - brake: braking, m/s².
##  - grip: sideways grip, m/s², which is the most the steering can ask for.
##  - agility: how readily the car answers the steering. It is the gain of the steering about the middle (a small
##    movement of the hand moves a twitchy car more, SteerModel.shape_cmd), and how quickly the wheels, the nose and
##    the direction of travel follow it. A full command asks for the same share of the grip in every car.
##  - stability: how settled the car stays. A stable car loses less grip as it goes faster (`lift`), keeps more of it
##    when it brakes (`brk_grip`) and wears off a swing from a knock sooner (`swing_decay`, `swing_catch`).
##  - kg: weight. It is how hard the car hits in a crash (`mass`, 1.0 = 1,400 kg: an ordinary car).
##  - range: how far a full tank goes, km, driven flat out. The tank decides what a fill costs.

const REF_KG := 1400.0        # the weight of an ordinary car, which is a crash mass of 1.0
const FLAT_OUT_RANGE := 16.5  # the Pulse's range: what `range` was for every car before it was a trait of its own
const LAT_REF := 4.3          # the sideways speed (m/s) the autopilot allows itself on 9.2 of grip

const PERM_KEYS := ["accel", "brake", "handling", "top"]


## `levels` is how many of each permanent upgrade the player has bought for this car (id -> level, see Data.PERM),
## `mods` the boons of the run (Game.Run.mods, empty for none) and `wear` its damage (0 .. 1, Save.wear).
static func compute(c: Dictionary, levels: Dictionary = {}, mods: Dictionary = {}, wear := 0.0) -> Dictionary:
	var fx := damage_effects(wear)
	var lv_accel := float(levels.get("accel", 0))
	var lv_brake := float(levels.get("brake", 0))
	var lv_handling := float(levels.get("handling", 0))
	var lv_top := float(levels.get("top", 0))
	var m_accel := float(mods.get("accel", 1.0))
	var m_brake := float(mods.get("brake", 1.0))
	var m_handling := float(mods.get("handling", 1.0))
	var m_top := float(mods.get("top", 1.0))
	var grip: float = float(c.grip) * (1.0 + 0.06 * lv_handling) * m_handling * float(fx.grip)
	var agility := float(c.get("agility", 1.0))
	var stable := float(c.get("stability", 1.0))
	var kg := float(c.get("kg", REF_KG))
	return {
		"accel": float(c.accel) * (1.0 + 0.06 * lv_accel) * m_accel * float(fx.accel),
		"brake": float(c.brake) * (1.0 + 0.06 * lv_brake) * m_brake * float(fx.brake),
		"grip": grip,
		"top": float(c.top) * (1.0 + 0.04 * lv_top) * m_top * float(fx.top),
		"pull": float(c.get("pull", 3.0)),
		# the steering: the gain about the middle, and how fast the car follows it
		"gain": agility,
		"quick": agility,
		# stability: grip lost at top speed, grip kept while braking, how fast a knock's swing wears off, how much of it the driver catches
		"lift": clampf(0.18 - 0.3 * (stable - 1.0), -0.05, 0.4),
		"brk_grip": clampf(0.75 + 0.25 * (stable - 1.0), 0.55, 0.92),
		"swing_decay": 6.5 * stable,
		"swing_catch": 0.6 / stable,
		"agility": agility,
		"stability": stable,
		"kg": kg,
		"mass": kg / REF_KG,
		# the tank, and how far it goes
		"tank": float(c.get("tank", 45)),
		"range_km": float(c.get("range", FLAT_OUT_RANGE)),
		"grade": String(c.get("fuel", "regular")),
		"fuel_use": float(fx.fuel),
		# how fast sideways the autopilot lets itself go (a stand-in driver: a person's limit is the steering model's): the
		# Pulse's 4.3 m/s, more in a grippier car, as it always was for the Pulse in the upgrades, the boons and the damage
		"lat": LAT_REF * sqrt(float(c.grip) / 9.2) * (1.0 + 0.04 * lv_handling) * sqrt(m_handling) * (1.0 - 0.10 * clampf(wear, 0.0, 1.0)),
	}


## How much a car's wear (0 as new .. 1 wrecked, see Save.wear) takes off its performance, as multipliers on its stats
## (and on its fuel use). Worse damage, worse car: a wrecked one has 40% less acceleration, 35% less braking, a quarter
## less top speed and a fifth less grip.
static func damage_effects(wear: float) -> Dictionary:
	var w := clampf(wear, 0.0, 1.0)
	return {"accel": 1.0 - 0.40 * w, "brake": 1.0 - 0.35 * w, "top": 1.0 - 0.25 * w, "grip": 1.0 - 0.20 * w, "fuel": 1.0 + 0.20 * w}


# ---------------------------------------------------------------- along the road

## What the engine gives at speed v with the throttle open (m/s²), before drag.
static func thrust(st: Dictionary, v: float) -> float:
	return float(st.accel) * maxf(0.0, 1.0 - pow(v / float(st.top), float(st.pull))) * (1.15 if v < 10.0 else 1.0)


## What the air and the road take back at speed v (m/s²).
static func drag(v: float) -> float:
	return 0.3 + 0.00022 * v * v


## What the brakes give at speed v (m/s²): less once the car is crawling.
static func braking(st: Dictionary, v: float) -> float:
	return float(st.brake) * (1.0 if v > 3.0 else 0.4)


## The sideways grip right now: it falls as the car goes faster (the more so the less stable it is), on the grass
## verge, and when the brakes are on. `vr` is the car's speed as a share of its top speed (the game works it out once
## a frame, before the speed changes).
static func grip_for(st: Dictionary, vr: float, v: float, braking_hard: bool, on_verge: bool) -> float:
	return float(st.grip) * (1.0 - float(st.lift) * clampf(vr, 0.0, 1.2)) * (0.6 if on_verge else 1.0) * (float(st.brk_grip) if braking_hard and v > 3.0 else 1.0)


## The same from the speed alone.
static func grip_at(st: Dictionary, v: float, braking_hard: bool, on_verge: bool) -> float:
	return grip_for(st, v / float(st.top), v, braking_hard, on_verge)


## Litres a car burns per metre with the throttle on or off at `vr` (its speed as a share of its top speed), before
## the run's eco boon (see Game).
static func fuel_per_m(st: Dictionary, gas: bool, vr: float, station_scale := 1.0) -> float:
	return float(st.tank) / (float(st.range_km) * 1000.0 * station_scale) * (0.55 + (0.25 if gas else 0.0) + 0.2 * clampf(vr * vr, 0.0, 1.0)) * float(st.fuel_use)


## The speed the car settles at on a flat road with the throttle open (m/s): a little under `top`, where drag
## takes as much as the engine gives.
static func terminal_speed(st: Dictionary) -> float:
	var v: float = st.top
	for _i in 60:
		var x := maxf(0.0, 1.0 - drag(v) / float(st.accel))
		v = float(st.top) * pow(x, 1.0 / float(st.pull))
	return v


## Seconds to go from speed `v0` to `v1` (m/s) flat out on a flat road; INF if it never gets there.
static func time_to(st: Dictionary, v0: float, v1: float) -> float:
	var v := v0
	var t := 0.0
	var dt := 0.01
	while v < v1:
		var a := thrust(st, v) - drag(v)
		if a <= 0.01:
			return INF
		v += a * dt
		t += dt
		if t > 120.0:
			return INF
	return t


## Metres to stop from speed v (m/s) with the brakes full on (the drag helps a little).
static func stopping_distance(st: Dictionary, v: float) -> float:
	var x := 0.0
	var dt := 0.01
	while v > 0.0:
		x += v * dt
		v -= (braking(st, v) + drag(v)) * dt
	return x


# ---------------------------------------------------------------- what the garage shows

## The numbers a driver understands, worked out from `st`: 0-100 km/h in seconds, the speed it settles at in km/h,
## metres to stop from 100 km/h, grip in g, the two handling traits, weight in kg and range in km.
static func sheet(st: Dictionary) -> Dictionary:
	return {
		"t100": time_to(st, 0.0, 100.0 / 3.6),
		"top_kmh": terminal_speed(st) * 3.6,
		"stop_m": stopping_distance(st, 100.0 / 3.6),
		"grip_g": float(st.grip) / 9.81,
		"agility": float(st.agility),
		"stability": float(st.stability),
		"kg": float(st.kg),
		"range_km": float(st.range_km),
	}


## One word for how a car answers the steering (the garage shows it beside the bar).
static func agility_word(a: float) -> String:
	if a < 0.9:
		return "HEAVY"
	if a < 0.97:
		return "CALM"
	if a < 1.06:
		return "NEUTRAL"
	if a < 1.2:
		return "SHARP"
	if a < 1.45:
		return "QUICK"
	return "TWITCHY"


## One word for how settled a car stays at speed, braking and after a knock.
static func stability_word(s: float) -> String:
	if s < 0.8:
		return "LOOSE"
	if s < 0.95:
		return "LIVELY"
	if s < 1.06:
		return "NEUTRAL"
	if s < 1.2:
		return "SETTLED"
	if s < 1.4:
		return "PLANTED"
	return "SOLID"

