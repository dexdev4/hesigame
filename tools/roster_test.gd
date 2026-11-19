extends SceneTree
## The cars side by side, no window needed:
##   godot --headless --path . --script tools/roster_test.gd
## Works every car in Data.CARS through CarStats and SteerModel (the same code the game and the garage use) and prints
## what it does: how quickly it gets going, how far it takes to stop, how fast it changes lane (and while braking),
## how it answers half a push of the hand, how long a knock's swing lasts, what a crash does to it and how far a tank
## goes. Then it checks the things that must hold: the Pulse is the reference, no car is beaten at everything by a
## cheaper one, every car is good at something and weak at something, and the numbers stay in their bounds.
## `--` arguments: `--quiet` prints only the checks, `--markdown` prints the garage's table of the cars.

class Car:
	var v := 30.0
	var x := 0.0
	var steer := 0.0
	var yaw := 0.0
	var yaw_rate := 0.0
	var course := 0.0
	var vx := 0.0
	var l := 4.25


var fails := 0
var checks := 0


func check(ok: bool, what: String) -> void:
	checks += 1
	if not ok:
		fails += 1
		print("  FAIL: ", what)


## One manoeuvre at constant speed v: full command one way for `t1`, then the other way until the nose is back along
## the road. Returns [how far over (m) it ended up, how long it took (s)].
func manoeuvre(st: Dictionary, v: float, braking: bool, t1: float, auth: float) -> Array:
	var c := Car.new()
	c.v = v
	var t := 0.0
	var dt := 1.0 / 120.0
	var phase := 0
	var grip := CarStats.grip_at(st, v, braking, false)
	while t < 4.0:
		var cmd := 1.0
		if phase == 0 and t >= t1:
			phase = 1
		if phase == 1:
			cmd = -1.0
			if c.yaw <= 0.0:
				break
		SteerModel.drive(c, dt, v, grip, auth, c.l * 0.6, cmd, false, st.gain, st.quick)
		c.vx = v * sin(c.course)
		c.x += c.vx * dt
		t += dt
	return [c.x, t]


## Seconds to change lane (3.7 m) with the quickest full-command manoeuvre, or INF if the car cannot do it.
func lane_change(st: Dictionary, v: float, braking: bool, auth := 1.4) -> float:
	var lo := 0.02
	var hi := 1.5
	if float(manoeuvre(st, v, braking, hi, auth)[0]) < 3.7:
		return INF
	for _i in 14:
		var mid := (lo + hi) * 0.5
		if float(manoeuvre(st, v, braking, mid, auth)[0]) < 3.7:
			lo = mid
		else:
			hi = mid
	return float(manoeuvre(st, v, braking, hi, auth)[1])


## How far sideways (m) the car has moved after `t` seconds of a steady half push (command 0.5) at speed v.
func half_push(st: Dictionary, v: float, t_end: float, push := 0.5) -> float:
	var c := Car.new()
	c.v = v
	var t := 0.0
	var dt := 1.0 / 120.0
	while t < t_end:
		var grip := CarStats.grip_at(st, v, false, false)
		SteerModel.drive(c, dt, v, grip, 1.4, c.l * 0.6, push, false, st.gain, st.quick)
		c.vx = v * sin(c.course)
		c.x += c.vx * dt
		t += dt
	return c.x


## The heading (degrees) a knock that swung the nose at `w` rad/s leaves after it has worn off (see Game._yaw_kick).
func swing_deg(st: Dictionary, w: float) -> float:
	var kick: float = w * float(st.swing_catch)
	return rad_to_deg(kick * kick / (2.0 * float(st.swing_decay)) * signf(kick) / maxf(absf(kick), 0.0001))


## The change of speed (m/s) the car takes from a square rear-end hit on a car of an ordinary weight at `closing` m/s.
func crash_dv(st: Dictionary, closing: float) -> float:
	var m_other := 1.0
	return 1.2 * closing * m_other / (float(st.mass) + m_other)


## `--markdown`: the cars as the garage shows them, as a table for the README.
func markdown() -> void:
	print("| Car | Price | 0-100 km/h | Top speed | 100-0 km/h | Grip | Agility | Stability | Weight | Range | Fuel, tank |")
	print("|---|---|---|---|---|---|---|---|---|---|---|")
	for c in Data.CARS:
		var st := CarStats.compute(c)
		var sh := CarStats.sheet(st)
		print("| %s | $%s | %.1f s | %d km/h | %d m | %.2f g | %s | %s | %s kg | %.1f km | %s, %d L |" % [c.name, Fmt.num(c.price), sh.t100, roundi(sh.top_kmh), roundi(sh.stop_m), sh.grip_g,
			CarStats.agility_word(sh.agility).capitalize(), CarStats.stability_word(sh.stability).capitalize(), Fmt.num(roundi(sh.kg)), sh.range_km,
			String(Data.FUEL_GRADES[c.get("fuel", "regular")].name), int(c.get("tank", 45))])


func _initialize() -> void:
	if "--markdown" in OS.get_cmdline_user_args():
		markdown()
		quit()
		return
	var quiet := "--quiet" in OS.get_cmdline_user_args()
	var rows := {}
	for c in Data.CARS:
		var st := CarStats.compute(c)
		var r := {
			"st": st,
			"t100": CarStats.time_to(st, 0.0, 27.78),
			"t100_150": CarStats.time_to(st, 27.78, 41.67),
			"term": CarStats.terminal_speed(st) * 3.6,
			"b100": CarStats.stopping_distance(st, 27.78),
			"b150": CarStats.stopping_distance(st, 41.67),
			"lc25": lane_change(st, 25.0, false),
			"lc40": lane_change(st, 40.0, false),
			"lc40b": lane_change(st, 40.0, true),
			"lc60": lane_change(st, 60.0, false) if float(st.top) > 55.0 else INF,
			"half": half_push(st, 35.0, 0.6),
			"swing": swing_deg(st, 1.0),
			"dv": crash_dv(st, 8.0),
			"lpk": float(st.tank) / float(st.range_km),
		}
		rows[c.id] = r
	if not quiet:
		print("== along the road, flat out on a flat road: 0-100 km/h and 100-150 km/h in s, the speed it settles at, metres to stop from 100 and 150 km/h")
		print("%-11s %6s %8s %7s %7s %7s" % ["car", "0-100", "100-150", "top", "100-0", "150-0"])
		for c in Data.CARS:
			var r: Dictionary = rows[c.id]
			print("%-11s %6.2f %8.2f %5.0f   %7.1f %7.1f" % [c.id, r.t100, r.t100_150, r.term, r.b100, r.b150])
		print("== sideways, the standard steering feel: seconds to change lane (3.7 m) at 90, 145 and 215 km/h, at 145 braking hard;")
		print("   metres moved in 0.6 s by half a push at 125 km/h; degrees the nose is left turned by a knock that swung it 1 rad/s")
		print("%-11s %6s %6s %6s %7s %7s %7s" % ["car", "90", "145", "215", "145 brk", "half", "swing"])
		for c in Data.CARS:
			var r: Dictionary = rows[c.id]
			print("%-11s %6.2f %6.2f %6s %7.2f %7.2f %7.1f" % [c.id, r.lc25, r.lc40, ("%.2f" % r.lc60) if is_finite(r.lc60) else "  -  ", r.lc40b, r.half, r.swing])
		print("== weight and fuel: kg, speed change (m/s) in a rear-end hit at 8 m/s closing, range flat out (km), litres a km flat out, tank (L), $ a km flat out at average prices")
		var price := {"regular": 3.4, "mid": 8.4, "premium": 18.4}
		print("%-11s %5s %5s %6s %6s %5s %6s" % ["car", "kg", "dv", "range", "L/km", "tank", "$/km"])
		for c in Data.CARS:
			var r: Dictionary = rows[c.id]
			var st: Dictionary = r.st
			print("%-11s %5.0f %5.1f %6.1f %6.2f %5.0f %6.1f" % [c.id, st.kg, r.dv, st.range_km, r.lpk, st.tank, r.lpk * price[st.grade]])

	print("== checks")
	var pulse: Dictionary = rows["pulse"]
	var ps: Dictionary = pulse.st
	# the reference car is neutral: it drives exactly as every car did before the traits
	check(is_equal_approx(ps.gain, 1.0) and is_equal_approx(ps.lift, 0.18) and is_equal_approx(ps.brk_grip, 0.75) and is_equal_approx(ps.pull, 3.0), "the Pulse is neutral")
	check(is_equal_approx(ps.mass, 1.0) and is_equal_approx(ps.range_km, CarStats.FLAT_OUT_RANGE), "the Pulse weighs an ordinary car and goes the reference range")
	check(is_equal_approx(ps.lat, 4.3), "the Pulse's autopilot sideways speed is what it was")
	check(is_equal_approx(CarStats.thrust(ps, 20.0), 5.4 * (1.0 - pow(20.0 / 50.0, 3.0))), "the Pulse's engine is the old formula")
	check(is_equal_approx(CarStats.grip_at(ps, 40.0, true, false), 9.2 * (1.0 - 0.18 * 0.8) * 0.75), "the Pulse's grip is the old formula")
	# the neutral steering gain changes nothing
	for cmd in [-1.0, -0.4, 0.0, 0.3, 1.0]:
		check(is_equal_approx(SteerModel.shape_cmd(cmd, 1.0), cmd), "gain 1 passes the command through (%.1f)" % cmd)
	check(is_equal_approx(SteerModel.shape_cmd(1.0, 1.5), 1.0) and is_equal_approx(SteerModel.shape_cmd(-1.0, 0.7), -1.0), "a full command is full in every car")
	check(SteerModel.shape_cmd(0.3, 1.4) > 0.3 and SteerModel.shape_cmd(0.3, 0.8) < 0.3, "a twitchy car moves more for the same push, a calm one less")
	# the table stays in bounds, and every car has something it is good at and something it is not
	var ids: Array = []
	for c in Data.CARS:
		ids.append(String(c.id))
	for c in Data.CARS:
		var id := String(c.id)
		var r: Dictionary = rows[id]
		var st: Dictionary = r.st
		check(float(st.pull) >= 2.0 and float(st.pull) <= 5.5, "%s: pull in bounds (%.1f)" % [id, st.pull])
		check(float(st.agility) >= 0.7 and float(st.agility) <= 1.6, "%s: agility in bounds (%.2f)" % [id, st.agility])
		check(float(st.stability) >= 0.7 and float(st.stability) <= 1.6, "%s: stability in bounds (%.2f)" % [id, st.stability])
		check(float(st.kg) >= 900.0 and float(st.kg) <= 2100.0, "%s: weight in bounds (%.0f)" % [id, st.kg])
		check(float(st.range_km) >= 10.0 and float(st.range_km) <= 26.0, "%s: range in bounds (%.1f)" % [id, st.range_km])
		check(is_finite(r.lc40) and r.lc40 > 0.6 and r.lc40 < 1.5, "%s: changes lane at 145 km/h in a believable time (%.2f s)" % [id, r.lc40])
		check(not c.has("lat"), "%s: no dead 'lat' stat in the table" % id)
	# what a player would compare: bigger is better in every one of these
	var goods := func(r: Dictionary) -> Dictionary:
		var st: Dictionary = r.st
		return {"0-100": 1.0 / float(r.t100), "100-150": 1.0 / float(r.t100_150), "top": float(r.term), "braking": 1.0 / float(r.b100),
			"lane change": 1.0 / float(r.lc40), "half push": float(r.half), "stability": float(st.stability),
			"weight": float(st.kg), "range": float(st.range_km), "economy": 1.0 / float(r.lpk)}
	# no car is beaten at everything (to within 3 %) by one that costs less: it would never be worth buying
	for i in Data.CARS.size():
		for j in Data.CARS.size():
			var a: Dictionary = Data.CARS[i]
			var b: Dictionary = Data.CARS[j]
			if i == j or int(a.price) <= int(b.price):
				continue
			var ga: Dictionary = goods.call(rows[a.id])
			var gb: Dictionary = goods.call(rows[b.id])  # (b is the cheaper car)
			var b_ahead := 0
			var b_not_behind := true
			for k in ga:
				if float(gb[k]) > float(ga[k]) * 1.03:
					b_ahead += 1
				if float(gb[k]) < float(ga[k]) * 0.97:
					b_not_behind = false
			check(not (b_not_behind and b_ahead > 0), "%s ($%d) is beaten at everything by the cheaper %s ($%d)" % [a.id, a.price, b.id, b.price])
	# every car of the first five is a specialist: it beats the Pulse at two things by 5 % or more, and is worse at one thing by 5 % or more
	var gp: Dictionary = goods.call(rows["pulse"])
	for c in Data.CARS:
		if int(c.price) == 0 or int(c.price) > 1200:
			continue
		var g: Dictionary = goods.call(rows[c.id])
		var up: Array = []
		var down: Array = []
		for k in g:
			if float(g[k]) > float(gp[k]) * 1.05:
				up.append(k)
			elif float(g[k]) < float(gp[k]) * 0.95:
				down.append(k)
		if not quiet:
			print("%-8s better than the Pulse at: %s | worse at: %s" % [c.id, ", ".join(up), ", ".join(down)])
		check(up.size() >= 2 and down.size() >= 1, "%s is a real trade-off against the Pulse (better at %d things, worse at %d)" % [c.id, up.size(), down.size()])
	# a car that costs more is at least as good overall as one that costs less (a weighted blend of what matters on this road), within the cheap tier a side-step
	var score := func(st: Dictionary) -> float:
		return pow(float(st.accel), 0.2) * pow(CarStats.terminal_speed(st), 0.22) * pow(float(st.brake), 0.14) * pow(float(st.grip), 0.2) * pow(float(st.agility), 0.07) * pow(float(st.stability), 0.07) * pow(float(st.range_km), 0.04) * pow(float(st.mass), 0.02)
	var ranked: Array = Data.CARS.duplicate()
	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.price) < int(b.price))
	if not quiet:
		print("== overall rating by price (the blend the checks use: a car that costs more should rate at least as high)")
	var prev := 0.0
	var prev_id := ""
	for c in ranked:
		var s: float = score.call(rows[c.id].st)
		if not quiet:
			print("%-11s $%-6d %.3f" % [c.id, c.price, s])
		if prev_id != "":
			check(s >= prev * 0.985, "%s rates no worse than the cheaper %s (%.3f against %.3f)" % [c.id, prev_id, s, prev])
		prev = s
		prev_id = String(c.id)
	print("%d checks, %d failed" % [checks, fails])
	quit(1 if fails > 0 else 0)
