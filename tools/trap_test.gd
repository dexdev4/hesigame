extends Node
## The police speed checks, no window needed (a scene, not a --script, as the scenery needs the game's autoloads):
##   godot --headless --path . tools/trap_test.tscn
## Checks the rules in SpeedTrap on their own: the limit, how far apart the checks are, that every one stands in a bay the
## scenery keeps clear (and clear of the fuel stops), what a car going past one is told, and that the patrol car fits in
## its bay. Exits with a non-zero code if a check fails. (The game itself, with the pursuit that follows, is exercised by
## the autotest: see the README's --trap-at.)

var fails := 0
var checks := 0


func check(ok: bool, what: String) -> void:
	checks += 1
	if not ok:
		fails += 1
		print("  FAIL: ", what)


func _ready() -> void:
	# the limit is 120 km/h, and only faster than that counts
	check(is_equal_approx(SpeedTrap.LIMIT * 3.6, 120.0), "the limit is 120 km/h")
	check(not SpeedTrap.speeding(SpeedTrap.LIMIT) and not SpeedTrap.speeding(30.0) and SpeedTrap.speeding(33.6) and SpeedTrap.speeding(60.0), "faster than 120 km/h is speeding")
	check(not SpeedTrap.speeding(120.4 / 3.6) and SpeedTrap.speeding(120.6 / 3.6), "a speedometer that reads 120 km/h is not caught, 121 is")
	check(is_equal_approx(SpeedTrap.WARN, 250.0), "the radar jammer warns 250 m ahead")
	check(SpeedTrap.QUIET > SpeedTrap.SPAWN and SpeedTrap.SPAWN > SpeedTrap.WARN and SpeedTrap.GONE < SpeedTrap.SPAWN, "the distances are in order: warning, on the road, quiet after an encounter")

	# the checks are 5 to 15 km apart, on the road's own sites, and the first is nearer
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var lo := 1e9
	var hi := 0.0
	var sum := 0.0
	var n := 4000
	for _i in n:
		var g := float(SpeedTrap.gap_sites(rng)) * Scenery.TREE_PERIOD
		lo = minf(lo, g)
		hi = maxf(hi, g)
		sum += g
	check(lo >= 5000.0 and hi <= 15000.0, "the gap between checks is %.1f to %.1f km (5 to 15)" % [lo / 1000.0, hi / 1000.0])
	check(sum / n > 9000.0 and sum / n < 11500.0, "the mean gap is %.1f km" % (sum / n / 1000.0))
	var first_lo := 1e9
	var first_hi := 0.0
	for _i in 2000:
		var z := SpeedTrap.site_z(SpeedTrap.first_site(0.0, rng))
		first_lo = minf(first_lo, z)
		first_hi = maxf(first_hi, z)
	check(first_lo >= SpeedTrap.FIRST_MIN - 1.0 and first_hi <= SpeedTrap.FIRST_MAX + Scenery.TREE_PERIOD, "the first check is %.1f to %.1f km into the run" % [first_lo / 1000.0, first_hi / 1000.0])
	var z0 := SpeedTrap.first_site(1234.0, rng)
	check(SpeedTrap.site_z(z0) >= 1234.0 + SpeedTrap.FIRST_MIN - 1.0, "the first check is never nearer than the least")

	# every check stands in a bay the scenery keeps clear
	for site in [0, 1, 7, 33, 120]:
		var z := SpeedTrap.site_z(site)
		check(is_equal_approx(fposmod(z - Scenery.TRAP_SITE, Scenery.TREE_PERIOD), 0.0), "site %d is at the trap phase" % site)
		var pz := fposmod(z + Scenery.VIEW_BEHIND, Scenery.TREE_PERIOD)  # (the scenery's own pattern position of road z)
		for x in [Data.RAIL + 1.0, Data.RAIL + 3.0, Data.RAIL + 5.0]:
			check(Scenery.site_clear(pz, x), "the bay at site %d is clear at %.1f m from the middle" % [site, x])
		check(not Scenery.site_clear(pz, Data.RAIL + 8.0), "the ground past the bay (site %d) is not kept clear" % site)
		check(not Scenery.site_clear(pz, -(Data.RAIL + 3.0)), "the left side is not kept clear for a bay (site %d)" % site)
		check(not Scenery.site_clear(fposmod(pz + 40.0, Scenery.TREE_PERIOD), Data.RAIL + 3.0), "a bay is short (site %d)" % site)

	# the patrol car fits in the bay: past the rail, inside what is kept clear, its length inside it
	var half_w := Data.SHAPES.sedan.w / 2.0
	var half_l := Data.SHAPES.sedan.l / 2.0
	check(is_equal_approx(SpeedTrap.BAY_X, Data.RAIL + 3.0), "the patrol car stands 3 m past the rail")
	check(SpeedTrap.BAY_X - half_w > Data.RAIL + 0.7 and SpeedTrap.BAY_X + half_w < Data.RAIL + Scenery.TRAP_WIDTH, "the patrol car is clear of the rail and inside the bay's width")
	check(half_l * 1.25 < Scenery.TRAP_HALF, "the patrol car, turned, is shorter than its bay")

	# the bay is nowhere near a fuel stop's ground (115 to 445 m into a period) or its signs (0 and 300)
	var s := Scenery.SITE
	check(Scenery.TRAP_SITE - Scenery.TRAP_HALF > s + GasStation.MERGE_END + 15.0, "the bay starts after the fuel stop's slip road is over")
	check(Scenery.TRAP_SITE + Scenery.TRAP_HALF < Scenery.TREE_PERIOD - 8.0, "and ends before the next period's first approach sign")
	check(SpeedTrap.clear_of_stops(5000.0, 4000.0) and not SpeedTrap.clear_of_stops(4100.0, 4000.0), "a check is kept well away from a fuel stop")

	# what a car going past is told
	check(SpeedTrap.verdict(40.0, "cruise", false) == "chase", "going past at 144 km/h starts a chase")
	check(SpeedTrap.verdict(33.0, "cruise", false) == "clear", "going past at 119 km/h is clear")
	check(SpeedTrap.verdict(SpeedTrap.LIMIT, "cruise", false) == "clear", "exactly 120 km/h is clear")
	for phase in ["boss", "incoming", "cop"]:
		check(SpeedTrap.verdict(60.0, phase, false) == "ignored", "the check does not count in a %s phase" % phase)
	check(SpeedTrap.verdict(60.0, "cruise", true) == "ignored", "the check does not count at a fuel stop or after a crash")

	print("%d checks, %d failed" % [checks, fails])
	get_tree().quit(1 if fails > 0 else 0)
