class_name BossMusic
extends Node
## The music for a boss race or a police chase: one of a handful of songs, and a different one, picked at random, each
## time one starts (never the song that played last).
##
## A song starts where it gets going rather than at its beginning (`start`: a bar line on the song's beat, where its quiet
## intro ends) and swells in over a couple of seconds; when the encounter is over it fades out. If an encounter outlasts
## the song, the song carries on from the same place again. The song for the next encounter is picked, and loaded on a
## worker thread, as soon as one starts, so that starting a chase never waits for a file.
##
## To add a song: put the mp3 in assets/audio, let Godot import it, and add a line to SONGS (`tools/song_points.py` finds
## where it gets going and how loud it is).

signal started(index: int)  # a song has begun

const DB := -1.5         # the level the songs play at (before the `gain` of each)
const FADE_IN := 2.5     # seconds
const SWAP_FADE := 1.0   # seconds: a song still fading out from the encounter before is cleared away this fast

## name, file, `start`: where it plays from, in seconds (and where it carries on from, should it run out), `gain`: dB, to
## bring them all to the loudness of the first (-11.9 LUFS, measured over the 90 s that play from the start).
const SONGS := [
	{"name": "Cold Iron Street", "path": "res://assets/audio/cold_iron_street.mp3", "start": 50.0, "gain": 0.0},
	{"name": "Beneath The Slab", "path": "res://assets/audio/beneath_the_slab.mp3", "start": 17.96, "gain": 0.3},
	{"name": "Sledgehammer Cavern", "path": "res://assets/audio/sledgehammer_cavern.mp3", "start": 18.35, "gain": 1.1},
	{"name": "Weight of the Maw", "path": "res://assets/audio/weight_of_the_maw.mp3", "start": 49.985, "gain": 0.7},
]

## The game's sound setting: nothing plays (or is loaded) while it is off.
var enabled := true:
	set(v):
		enabled = v
		if not v:
			halt()
		elif _next >= 0:
			_ask(_next)
## Test aid (--music=): always this song (-1: pick at random).
var forced := -1
var current := -1   # the song that is playing, or that played last
var on := false     # an encounter is on: the music is wanted

var _players: Array[AudioStreamPlayer] = []
var _tweens: Array = [null, null]
var _cur := 0           # which of the two players has `current` (the other may still be fading out the song before)
var _next := -1         # the song picked for the next encounter, being loaded
var _asked: Dictionary = {}  # the files the loader thread has been asked for
var _rng := RandomNumberGenerator.new()  # (its own: picking a song must not move the simulation's random numbers)


func _ready() -> void:
	_rng.randomize()
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.volume_db = -60.0
		add_child(p)
		_players.append(p)
	_pick_next()


## The song for the next encounter: any but `last` (-1: none yet), chosen by `r`, a number from 0 up to 1.
static func pick(count: int, last: int, r: float) -> int:
	if count <= 1:
		return 0
	if last < 0 or last >= count:
		return clampi(int(r * count), 0, count - 1)
	var k := clampi(int(r * (count - 1)), 0, count - 2)
	return k + 1 if k >= last else k


## A song by number (1 is the first) or by part of its name (--music=slab).
static func find(text: String) -> int:
	if text.is_valid_int():
		return clampi(text.to_int() - 1, 0, SONGS.size() - 1)
	var want := text.to_lower().replace("_", " ")
	for i in SONGS.size():
		if String(SONGS[i].name).to_lower().contains(want):
			return i
	return -1


## An encounter starts (or goes on): the music comes in.
func play() -> void:
	if not enabled or _players.is_empty():
		return
	if on and _players[_cur].playing:
		_fade(_cur, DB + float(SONGS[current].gain), FADE_IN)  # (the same encounter: back up to full volume)
		return
	var i := _next if _next >= 0 else pick(SONGS.size(), current, _rng.randf())
	var s := _stream(i)
	for _n in SONGS.size():  # (a song that cannot be loaded gives way to the next)
		if s != null:
			break
		i = (i + 1) % SONGS.size()
		s = _stream(i)
	if s == null:
		return
	var old := _cur
	if _players[old].playing:
		_fade(old, -60.0, SWAP_FADE, true)  # (a rematch, say: the song of the encounter before is still dying away)
	_cur = 1 - _cur
	current = i
	on = true
	s.loop = true
	s.loop_offset = float(SONGS[i].start)
	var p := _players[_cur]
	_kill(_cur)
	p.stream = s
	p.volume_db = -40.0
	p.play(float(SONGS[i].start))
	_fade(_cur, DB + float(SONGS[i].gain), FADE_IN)
	started.emit(i)
	_pick_next()


## The encounter is over: the music fades out over `fade` seconds.
func stop(fade := 6.0) -> void:
	on = false
	if _players.size() == 2 and _players[_cur].playing:
		_fade(_cur, -60.0, fade, true)


## Silence at once.
func halt() -> void:
	on = false
	for i in _players.size():
		_kill(i)
		_release(i)


func set_paused(paused: bool) -> void:
	for p in _players:
		p.stream_paused = paused


## Choose the song for the next encounter, and have it loaded while the current one plays.
func _pick_next() -> void:
	_next = forced if forced >= 0 and forced < SONGS.size() else pick(SONGS.size(), current, _rng.randf())
	_ask(_next)


func _ask(i: int) -> void:
	var path: String = SONGS[i].path
	if enabled and not _asked.has(path) and ResourceLoader.load_threaded_request(path) == OK:
		_asked[path] = true


## A song's stream: from the loader thread if it was asked for (it waits only if that is not done yet), else loaded here.
func _stream(i: int) -> AudioStreamMP3:
	var path: String = SONGS[i].path
	var res: Resource = null
	if _asked.has(path):
		_asked.erase(path)
		res = ResourceLoader.load_threaded_get(path)
	if res == null:
		res = load(path)
	return res as AudioStreamMP3


func _fade(i: int, db: float, secs: float, then_release := false) -> void:
	_kill(i)
	var tw := create_tween()
	var step := tw.tween_property(_players[i], "volume_db", db, secs)
	if then_release:
		step.set_trans(Tween.TRANS_SINE)
		tw.tween_callback(_release.bind(i))
	_tweens[i] = tw


func _kill(i: int) -> void:
	if _tweens[i] != null:
		(_tweens[i] as Tween).kill()
		_tweens[i] = null


## A player that has finished lets go of its song (a song is several megabytes).
func _release(i: int) -> void:
	_players[i].stop()
	_players[i].stream = null
