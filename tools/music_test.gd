extends SceneTree
## Checks the chase music's choice of song: `godot --headless --path . --script tools/music_test.gd`
##
## A song is picked at random but never the one that played last, every song comes up and none is favoured, and the
## list of songs is sound (each file loads, each starts well inside its song, no two are named alike).

var _fails := 0
var _checks := 0


func check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_fails += 1
		print("  FAILED: ", what)


func _init() -> void:
	var n := BossMusic.SONGS.size()
	print("== picking a song (", n, " songs)")
	# every `last`, every value of the random number: never the last song, and all the others come up evenly
	for last in range(-1, n):
		var counts := PackedInt32Array()
		counts.resize(n)
		var steps := 4000
		for k in steps:
			var i := BossMusic.pick(n, last, (k + 0.5) / steps)
			check(i >= 0 and i < n, "pick(%d, %d) is a song" % [n, last])
			if i >= 0 and i < n:
				counts[i] += 1
		if last >= 0:
			check(counts[last] == 0, "never the song that played last (%d)" % last)
		var others := 0
		var lo := steps
		var hi := 0
		for i in n:
			if i != last or last < 0:
				others += 1
				lo = mini(lo, counts[i])
				hi = maxi(hi, counts[i])
		check(lo > 0, "every other song comes up (last %d)" % last)
		check(hi - lo <= 1, "evenly: %s (last %d)" % [str(counts), last])
	# the edges of the random number
	for last in range(-1, n):
		for r in [0.0, 0.999999, 1.0]:
			var i := BossMusic.pick(n, last, r)
			check(i >= 0 and i < n and i != last, "pick at r=%s (last %d) -> %d" % [r, last, i])
	check(BossMusic.pick(1, 0, 0.5) == 0 and BossMusic.pick(1, -1, 0.9) == 0, "a single song is always that song")
	check(BossMusic.pick(0, -1, 0.5) == 0, "no songs does not break")

	print("== a long run of encounters")
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var last := -1
	var counts := PackedInt32Array()
	counts.resize(n)
	var repeats := 0
	var runs := 20000
	for k in runs:
		var i := BossMusic.pick(n, last, rng.randf())
		if i == last:
			repeats += 1
		counts[i] += 1
		last = i
	check(repeats == 0, "no song twice in a row over %d encounters" % runs)
	var worst := 0.0
	for i in n:
		worst = maxf(worst, absf(float(counts[i]) / runs - 1.0 / n))
	check(worst < 0.02, "each song about 1/%d of the time (off by %.3f at most)" % [n, worst])
	print("  shares: ", ", ".join(PackedStringArray(Array(counts).map(func(c: int) -> String: return "%.1f%%" % (100.0 * c / runs)))))

	print("== finding a song for --music=")
	check(BossMusic.find("1") == 0 and BossMusic.find("4") == n - 1, "by number")
	check(BossMusic.find("99") == n - 1 and BossMusic.find("0") == 0, "a number off the list stays on it")
	check(BossMusic.find("slab") == 1, "by part of the name")
	check(BossMusic.find("Weight of the Maw") == 3 and BossMusic.find("weight_of_the_maw") == 3, "by the whole name, or its file name")
	check(BossMusic.find("sledge") == 2 and BossMusic.find("COLD") == 0, "in any case")
	check(BossMusic.find("no such song") == -1, "a name that is not there")

	print("== the list of songs")
	var names := {}
	for i in n:
		var song: Dictionary = BossMusic.SONGS[i]
		var path: String = song.path
		check(not names.has(song.name), "%s: named once" % song.name)
		names[song.name] = true
		check(ResourceLoader.exists(path), "%s: %s is there" % [song.name, path])
		var res := load(path) as AudioStreamMP3
		check(res != null, "%s: loads as an mp3" % song.name)
		if res == null:
			continue
		var length := res.get_length()
		var start := float(song.start)
		check(start >= 0.0 and start < length - 45.0, "%s: starts at %.2f s of %.1f s, with time to play" % [song.name, start, length])
		check(absf(float(song.gain)) <= 3.0, "%s: gain %.1f dB is a small trim" % [song.name, float(song.gain)])
		print("  %-20s %6.1f s long, plays from %6.2f s, %+.1f dB" % [song.name, length, start, float(song.gain)])

	print("== %d checks, %d failed" % [_checks, _fails])
	quit(1 if _fails > 0 else 0)
