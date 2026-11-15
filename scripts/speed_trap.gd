class_name SpeedTrap
extends RefCounted
## The police speed checks. A patrol car sits parked outside the guardrail, a speed check every 5 to 15 km of road. A car
## that goes past one faster than LIMIT starts a police chase (Game: _trap_pass, _start_cop). The radar jammer, one of
## the rewards for beating a boss, warns of the next one WARN metres before it so there is time to slow down.
## The rules are kept apart from the game so they can be tested on their own (tools/trap_test.gd).

const LIMIT := 120.0 / 3.6     # m/s: the limit, 120 km/h
const CATCH := 120.5 / 3.6     # m/s: faster than this as the car goes past and the chase starts (the speedometer shows whole km/h: 120 on it is never caught)
const WARN := 250.0            # m: how far ahead the radar jammer warns of a speed check
const SPAWN := 760.0           # m: a trap is put on the road when it is this far ahead (a little past what can be seen)
const GONE := 170.0            # m: and taken off again this far behind (the mirror sees it for a moment)
const GAP_MIN := 5000.0        # m: the least road between one speed check and the next
const GAP_MAX := 15000.0       # m: and the most
const FIRST_MIN := 2500.0      # m: the first one is nearer than that (a first run is 5 to 8 km, and it should meet one)
const FIRST_MAX := 7000.0
const BAY_X := 11.8           # m: the patrol car's middle across the road, outside the rail (Data.RAIL is 8.8) with room to spare
const TURN := 0.35             # radians: its nose is turned this far towards the road, as if waiting to pull out
const DELAY := 2.0             # s: from the check to the police car pulling out onto the road behind you
const QUIET := 1500.0          # m: no speed check this far after a boss race or a pursuit is over (nor during one: Game._update_traps)


## Road z of the speed check at site n (a place in every TREE_PERIOD of road where the scenery keeps a bay clear).
static func site_z(n: int) -> float:
	return n * Scenery.TREE_PERIOD + Scenery.TRAP_SITE


## The site of the first speed check of a run that starts at road z `from_z`.
static func first_site(from_z: float, rng: RandomNumberGenerator) -> int:
	return ceili((from_z + rng.randf_range(FIRST_MIN, FIRST_MAX) - Scenery.TRAP_SITE) / Scenery.TREE_PERIOD)


## How many sites on from the last one the next speed check is (5 to 15 km of road, to the nearest site).
static func gap_sites(rng: RandomNumberGenerator) -> int:
	return rng.randi_range(ceili(GAP_MIN / Scenery.TREE_PERIOD), floori(GAP_MAX / Scenery.TREE_PERIOD))


## Does a car at this speed (m/s) set the speed check off as it goes past? It must be over the limit by more than
## the speedometer can show: a car that reads 120 km/h is not caught.
static func speeding(v: float) -> bool:
	return v > CATCH


## What a car that goes past a speed check at speed v (m/s) is told: "chase" (it was speeding), "clear" (it was not), or
## "ignored" (the check does not count: it is the boss's turn, a chase is already on, or the car is at a fuel stop or has
## crashed: `busy`).
static func verdict(v: float, phase: String, busy: bool) -> String:
	if phase != "cruise" or busy:
		return "ignored"
	return "chase" if speeding(v) else "clear"


## The fuel stops stand at a site of their own in every TREE_PERIOD: no speed check is put in the stretch of road the
## stop's exit lane, forecourt and signs take up (it never comes to that as the two sites differ, but this is the rule).
static func clear_of_stops(z: float, stop_z: float) -> bool:
	return absf(z - stop_z) > 300.0
