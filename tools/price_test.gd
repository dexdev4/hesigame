extends Node
## Fuel prices (Data.pump_price, Data.raised_price), apart from the game:
##   godot --headless --path . tools/price_test.tscn
## Checks that a pump price ends in 9 and moves in steps of ten cents, that the price a stop asks is never less than 5% or
## more than 25% above the one before for any price a run can reach, whatever the rise it rolled, that it is the nearest
## pump price to the rise it rolled (so the climb really is spread over 5 to 25%), and what 30 stops in a row cost on
## average. (A scene, because Data is an autoload.) Exits with a non-zero code if a check fails.

var _fails := 0
var _checks := 0


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_fails += 1
		print("  FAIL: ", what)


func _ready() -> void:
	seed(7)
	_pump()
	_rise()
	_run()
	print("== %d checks, %d failed" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)


func _pump() -> void:
	var bad := 0
	for i in 2000:
		var v := randf_range(0.5, 900.0)
		var p := Data.pump_price(v)
		var cents := roundi(p * 100.0) % 10
		if cents != 9 or p > v + 0.0901 or p < v - 0.1001:
			bad += 1
	_check(bad == 0, "a pump price ends in 9 and is within a dime of the price it was made from (%d of 2000 were not)" % bad)
	_check(is_equal_approx(Data.pump_price(3.5), 3.59) and is_equal_approx(Data.pump_price(3.499), 3.49), "3.50 becomes 3.59, 3.499 becomes 3.49")


func _rise() -> void:
	var out_of_range := 0
	var off_nearest := 0
	var worst_lo := 9.0
	var worst_hi := 0.0
	var n := 0
	for i in 6000:
		var p := Data.pump_price(randf_range(2.4, 600.0) if i % 3 > 0 else randf_range(2.4, 30.0))
		var rise := randf_range(Data.PRICE_RISE_MIN, Data.PRICE_RISE_MAX)
		var q := Data.raised_price(p, rise)
		var got := q / p - 1.0
		n += 1
		worst_lo = minf(worst_lo, got)
		worst_hi = maxf(worst_hi, got)
		if got < Data.PRICE_RISE_MIN - 1e-9 or got > Data.PRICE_RISE_MAX + 1e-9:
			out_of_range += 1
			if out_of_range < 4:
				print("    %.2f x (1 + %.4f) -> %.2f, a rise of %.4f" % [p, rise, q, got])
		# within a dime of what the rise asked for, unless the 5% to 25% limit moved it
		var want := p * (1.0 + rise)
		if absf(q - want) > 0.1001 and got > Data.PRICE_RISE_MIN + 0.002 and got < Data.PRICE_RISE_MAX - 0.002:
			off_nearest += 1
	_check(out_of_range == 0, "the price asked is 5%% to 25%% above the one before in all %d cases (%d were not; the rises came out between %.1f%% and %.1f%%)" % [n, out_of_range, worst_lo * 100.0, worst_hi * 100.0])
	_check(off_nearest == 0, "the price asked is the pump price nearest to the rise rolled (%d of %d were further than a dime away)" % [off_nearest, n])
	# a small price (a rise of 5% on $2.49 is only 12 cents): still a rise of at least 5%, and never nothing
	var q := Data.raised_price(2.49, 0.05)
	_check(q >= 2.49 * 1.05 - 1e-9 and q > 2.49, "$2.49 at the smallest rise becomes $%.2f" % q)
	var all_ends_in_9 := true
	for i in 500:
		var qq := Data.raised_price(Data.pump_price(randf_range(2.4, 90.0)), randf_range(0.05, 0.25))
		all_ends_in_9 = all_ends_in_9 and roundi(qq * 100.0) % 10 == 9
	_check(all_ends_in_9, "a raised price is still a pump price (ends in 9)")


func _run() -> void:
	# thirty stops in a row, a hundred runs: the mean rise, and where the price gets to
	var rises := 0.0
	var count := 0
	var at := {5: 0.0, 10: 0.0, 20: 0.0, 30: 0.0}
	var runs := 100
	for r in runs:
		var p := Data.pump_price(randf_range(2.4, 4.4))
		for k in range(1, 31):
			var q := Data.raised_price(p, randf_range(Data.PRICE_RISE_MIN, Data.PRICE_RISE_MAX))
			rises += q / p - 1.0
			count += 1
			p = q
			if at.has(k):
				at[k] += p / float(runs)
	var mean := rises / count
	_check(mean > 0.14 and mean < 0.16, "the mean rise of a stop is about 15%% (%.1f%%)" % (mean * 100.0))
	print("  regular, on average over %d runs that begin at $3.40: after 5 rises (the 6th stop) $%.2f, after 10 $%.2f, after 20 $%.2f, after 30 $%.2f (the first stop of a run is $2.40 to $4.40)" % [runs, at[5], at[10], at[20], at[30]])
