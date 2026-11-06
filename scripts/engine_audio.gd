class_name EngineAudio
extends Node
## Synthesised sound, no audio files: a live engine + wind generator, and
## one-shot effects (whoosh, crash, chime) rendered into WAV buffers at start.

const RATE := 22050.0

var _gen_player: AudioStreamPlayer
var _pb: AudioStreamGeneratorPlayback
var _phase := 0.0
var _phase2 := 0.0
var _lp := 0.0
var _wind_lp := 0.0
var _freq := 50.0
var _vol := 0.0
var _cut := 0.15
var _wind := 0.0
var _t_freq := 50.0
var _t_vol := 0.0
var _t_cut := 0.15
var _t_wind := 0.0
var _sfx := {}
var _players: Array[AudioStreamPlayer] = []


func _ready() -> void:
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = RATE
	gen.buffer_length = 0.1
	_gen_player = AudioStreamPlayer.new()
	_gen_player.stream = gen
	_gen_player.volume_db = -4.0
	add_child(_gen_player)
	_gen_player.play()
	_pb = _gen_player.get_stream_playback() as AudioStreamGeneratorPlayback
	for i in 5:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	_sfx["whoosh"] = _make_whoosh()
	_sfx["crash"] = _make_crash()
	_sfx["ding"] = _make_ding()


func set_enabled(on: bool) -> void:
	AudioServer.set_bus_mute(0, not on)


## Called every frame with the player's speed (m/s) and the car's top speed.
func drive(v: float, top: float, gas: bool, live: bool) -> void:
	var gears := 6.0
	var span := top / gears
	var gear := minf(gears - 1.0, floorf(v / span))
	var frac := clampf((v - gear * span) / span, 0.0, 1.0)
	var rpm := 0.22 + 0.78 * frac
	_t_freq = 36.0 + rpm * 100.0 + gear * 7.0
	_t_cut = clampf(0.05 + rpm * (0.35 if gas else 0.16), 0.03, 0.6)
	_t_vol = (0.32 if gas else 0.18) if live else 0.07
	_t_wind = minf(0.22, pow(v / 70.0, 2.0) * 0.22)


func _process(delta: float) -> void:
	if _pb == null:
		return
	var k := clampf(delta * 12.0, 0.0, 1.0)
	_freq = lerpf(_freq, _t_freq, k)
	_vol = lerpf(_vol, _t_vol, k * 0.6)
	_cut = lerpf(_cut, _t_cut, k)
	_wind = lerpf(_wind, _t_wind, k * 0.3)
	var n := _pb.get_frames_available()
	var inc := _freq / RATE
	for i in n:
		_phase = fmod(_phase + inc, 1.0)
		_phase2 = fmod(_phase2 + inc * 0.5, 1.0)
		var s := (_phase * 2.0 - 1.0) + (0.45 if _phase2 < 0.5 else -0.45)
		_lp += _cut * (s - _lp)
		_wind_lp += 0.09 * ((randf() * 2.0 - 1.0) - _wind_lp)
		var o := _lp * _vol + _wind_lp * _wind * 2.0
		_pb.push_frame(Vector2(o, o))


func play(name: String, pitch := 1.0, vol_db := 0.0) -> void:
	if not _sfx.has(name):
		return
	for p in _players:
		if not p.playing:
			p.stream = _sfx[name]
			p.pitch_scale = pitch
			p.volume_db = vol_db
			p.play()
			return


func _wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 30000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = int(RATE)
	w.stereo = false
	w.data = bytes
	return w


func _make_whoosh() -> AudioStreamWAV:
	var n := int(RATE * 0.4)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	var lp2 := 0.0
	for i in n:
		var t := float(i) / n
		var env := minf(1.0, t * 12.0) * pow(1.0 - t, 2.0)
		var c := lerpf(0.5, 0.05, t)
		lp += c * ((randf() * 2.0 - 1.0) - lp)
		lp2 += 0.02 * (lp - lp2)
		out[i] = (lp - lp2) * env * 1.6
	return _wav(out)


func _make_crash() -> AudioStreamWAV:
	var n := int(RATE * 0.8)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / n
		var env := pow(1.0 - t, 3.0)
		lp += lerpf(0.4, 0.04, t) * ((randf() * 2.0 - 1.0) - lp)
		var thump := sin(TAU * lerpf(70.0, 35.0, t) * float(i) / RATE) * pow(1.0 - t, 5.0)
		out[i] = (lp * 1.4 + thump * 0.8) * env
	return _wav(out)


func _make_ding() -> AudioStreamWAV:
	var n := int(RATE * 0.18)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / n
		var tri := 2.0 * absf(2.0 * fmod(520.0 * float(i) / RATE, 1.0) - 1.0) - 1.0
		out[i] = tri * pow(1.0 - t, 2.0) * 0.35
	return _wav(out)
