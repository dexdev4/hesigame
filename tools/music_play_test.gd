extends SceneTree
## Plays the chase music for real (on the engine's silent audio driver) and checks what a chase would hear:
## `godot --headless --path . --script tools/music_play_test.gd`
##
## A song starts where it gets going and swells in, a new encounter gets a new song, a rematch a moment after a loss clears
## the dying song away, pausing stops it, switching the sound off silences it at once and a song that was loaded ahead
## starts without a wait. (Takes about twenty seconds: it waits for the music to play.)

var _fails := 0
var _checks := 0


func check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_fails += 1
		print("  FAILED: ", what)


func wait(seconds: float) -> void:
	await create_timer(seconds).timeout


func playing_count(m: BossMusic) -> int:
	var k := 0
	for p in m.get_children():
		if p is AudioStreamPlayer and (p as AudioStreamPlayer).playing:
			k += 1
	return k


func current_player(m: BossMusic) -> AudioStreamPlayer:
	return m.get_child(m._cur) as AudioStreamPlayer


func _initialize() -> void:
	var m := BossMusic.new()
	root.add_child(m)
	var started: Array[int] = []
	m.started.connect(func(i: int) -> void: started.append(i))

	print("== a song begins")
	await wait(1.0)  # (the first song is being loaded on a worker thread)
	check(m._next >= 0 and m.current == -1, "a song is chosen for the first encounter")
	var t0 := Time.get_ticks_usec()
	m.play()
	var took := (Time.get_ticks_usec() - t0) / 1000.0
	print("  play() took %.1f ms with the song loaded ahead" % took)
	check(took < 50.0, "starting a chase does not wait for the file (%.1f ms)" % took)
	check(m.on and m.current >= 0 and started.size() == 1, "an encounter is on, with a song")
	check(playing_count(m) == 1, "one player is playing")
	var first := m.current
	var start := float(BossMusic.SONGS[first].start)
	await wait(0.4)
	var pl := current_player(m)
	check(pl.playing and pl.get_playback_position() >= start and pl.get_playback_position() < start + 3.0, "it is playing from its start point (%.1f s into a song that starts at %.1f s)" % [pl.get_playback_position(), start])
	check(pl.volume_db > -40.0 and pl.volume_db < BossMusic.DB + float(BossMusic.SONGS[first].gain), "and swelling in (%.1f dB)" % pl.volume_db)
	await wait(2.4)
	check(absf(pl.volume_db - (BossMusic.DB + float(BossMusic.SONGS[first].gain))) < 0.2, "at its full volume (%.2f dB)" % pl.volume_db)
	check(pl.stream is AudioStreamMP3 and (pl.stream as AudioStreamMP3).loop and absf((pl.stream as AudioStreamMP3).loop_offset - start) < 0.001, "looping back to its start point, should the chase outlast it")

	print("== the same encounter goes on")
	m.play()
	check(m.current == first and started.size() == 1 and playing_count(m) == 1, "asking again does not change the song")

	print("== the encounter ends")
	m.stop(0.5)
	check(not m.on, "no encounter is on")
	await wait(0.9)
	check(playing_count(m) == 0, "the music has faded out and stopped")
	check(current_player(m).stream == null, "and let go of its song")

	print("== the next encounter")
	m.play()
	check(m.current != first and started.size() == 2, "a different song (%s after %s)" % [BossMusic.SONGS[m.current].name, BossMusic.SONGS[first].name])
	var second := m.current

	print("== a rematch while the song is still dying away")
	m.stop(6.0)
	await wait(0.4)
	var dying := current_player(m)
	check(dying.playing, "the song is still playing as it fades")
	m.play()
	check(m.current != second and started.size() == 3, "a new song (%s)" % BossMusic.SONGS[m.current].name)
	check(playing_count(m) == 2 and not current_player(m) == dying, "the new song comes in on the other player while the old one dies away")
	await wait(1.3)
	check(playing_count(m) == 1 and current_player(m).playing, "the old song is cleared away, the new one plays on")
	var third := m.current

	print("== pausing")
	var pp := current_player(m)
	m.set_paused(true)
	var at := pp.get_playback_position()
	await wait(0.4)
	check(absf(pp.get_playback_position() - at) < 0.06, "the song stands still while paused")
	m.set_paused(false)
	await wait(0.4)
	check(pp.get_playback_position() > at + 0.2, "and goes on when resumed")

	print("== the sound is switched off and on")
	m.enabled = false
	check(playing_count(m) == 0 and not m.on, "silence at once")
	var before := started.size()
	m.play()
	check(playing_count(m) == 0 and started.size() == before, "nothing plays while it is off")
	m.enabled = true
	await wait(0.3)
	m.play()
	check(playing_count(m) == 1 and started.size() == before + 1, "and it plays again when it is on")
	m.halt()

	print("== a dozen encounters")
	var seq: Array[int] = []
	seq.append(m.current)
	for k in 11:
		await wait(0.1)
		m.stop(0.05)
		await wait(0.15)
		m.play()
		seq.append(m.current)
	var repeats := 0
	for k in range(1, seq.size()):
		if seq[k] == seq[k - 1]:
			repeats += 1
	print("  songs: ", seq)
	check(repeats == 0, "never the same song twice running")
	check(seq.size() == 12 and seq.any(func(i: int) -> bool: return i != seq[0]), "and more than one song")
	m.halt()
	m.queue_free()

	print("== a song asked for by number")
	var f := BossMusic.new()
	f.forced = 2
	root.add_child(f)
	await wait(0.6)
	for k in 3:
		f.play()
		check(f.current == 2, "forced song %d: %s" % [k, BossMusic.SONGS[f.current].name])
		await wait(0.1)
		f.stop(0.05)
		await wait(0.2)
	f.halt()

	print("== playing before the song was loaded ahead")
	var c := BossMusic.new()
	root.add_child(c)
	t0 = Time.get_ticks_usec()
	c.play()  # (straight away: the worker thread has hardly begun)
	took = (Time.get_ticks_usec() - t0) / 1000.0
	print("  play() took %.1f ms with the song not ready" % took)
	check(c.on and playing_count(c) == 1, "it still plays (the first call waits for the file)")
	c.halt()

	print("== %d checks, %d failed" % [_checks, _fails])
	quit(1 if _fails > 0 else 0)
