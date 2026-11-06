class_name EngineAudio
extends Node
## Synthesised car audio, no sound files.
##
## The engine is a small drivetrain model (rpm, six gears, shift timing,
## throttle load) driving a firing-order wavetable: one table holds a full
## four-stroke cycle with one combustion pulse per cylinder, each with its own
## timing and strength, so a V8 burbles and an I4 buzzes. The raw signal goes
## through an "Engine" bus (EQ for exhaust body, overdrive for grit, a
## low-pass that opens with throttle). Exhaust rasp, intake roar, lift-off
## pops, turbo whine, tyre squeal, road and wind noise are mixed per sample.

const RATE := 22050.0
const TABLE := 2048
const RATIOS: Array[float] = [3.30, 2.15, 1.58, 1.24, 1.0, 0.84]

## Read by the HUD.
var rpm := 900.0
var gear := 1
var redline := 7000.0

var _eng := {}
var _table := PackedFloat32Array()
var _env := PackedFloat32Array()
var _player: AudioStreamPlayer
var _pb: AudioStreamGeneratorPlayback
var _bus := 0
var _dist: AudioEffectDistortion
var _lp: AudioEffectLowPassFilter

# drivetrain state
var _load := 0.0
var _shift_t := 0.0
var _blip_t := 0.0
var _limiter_t := 0.0
var _boost := 0.0
var _live := false
var _speed := 0.0
var _slip := 0.0

# synth state
var _ph := 0.0
var _n1 := 0.0
var _n2 := 0.0
var _n3 := 0.0
var _pop := 0.0
var _pop_lp := 0.0
var _tph := 0.0
var _sv_low := 0.0
var _sv_band := 0.0
var _sq_ph := 0.0
var _vol_s := 0.0
var _load_s := 0.0
var _rpm_s := 900.0
var _slip_s := 0.0
var _speed_s := 0.0
var _decel := 0.0

var _sfx := {}
var _players: Array[AudioStreamPlayer] = []


func _ready() -> void:
	_bus = AudioServer.get_bus_index("Engine")
	if _bus < 0:
		_bus = AudioServer.bus_count
		AudioServer.add_bus(_bus)
		AudioServer.set_bus_name(_bus, "Engine")
		AudioServer.set_bus_send(_bus, "Master")
		var eq := AudioEffectEQ6.new()
		eq.set_band_gain_db(0, 3.0)    # 32 Hz: chest thump
		eq.set_band_gain_db(1, 6.0)    # 100 Hz: exhaust body
		eq.set_band_gain_db(2, 2.0)    # 320 Hz
		eq.set_band_gain_db(3, -1.0)   # 1 kHz
		eq.set_band_gain_db(4, -5.0)   # 3.2 kHz
		eq.set_band_gain_db(5, -14.0)  # 10 kHz: no fizz
		AudioServer.add_bus_effect(_bus, eq)
		_dist = AudioEffectDistortion.new()
		_dist.mode = AudioEffectDistortion.MODE_OVERDRIVE
		_dist.drive = 0.25
		_dist.pre_gain = 0.0
		_dist.post_gain = -3.0
		_dist.keep_hf_hz = 6000.0
		AudioServer.add_bus_effect(_bus, _dist)
		_lp = AudioEffectLowPassFilter.new()
		_lp.cutoff_hz = 2400.0
		_lp.resonance = 0.65
		AudioServer.add_bus_effect(_bus, _lp)
		var comp := AudioEffectCompressor.new()
		comp.threshold = -10.0
		comp.ratio = 4.0
		AudioServer.add_bus_effect(_bus, comp)
	else:
		_dist = AudioServer.get_bus_effect(_bus, 1) as AudioEffectDistortion
		_lp = AudioServer.get_bus_effect(_bus, 2) as AudioEffectLowPassFilter

	var gen := AudioStreamGenerator.new()
	gen.mix_rate = RATE
	gen.buffer_length = 0.1
	_player = AudioStreamPlayer.new()
	_player.stream = gen
	_player.bus = "Engine"
	_player.volume_db = -2.0
	add_child(_player)
	_player.play()
	_pb = _player.get_stream_playback() as AudioStreamGeneratorPlayback
	for i in 6:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	_sfx["whoosh"] = _make_whoosh()
	_sfx["crash"] = _make_crash()
	_sfx["ding"] = _make_ding()
	_sfx["blowoff"] = _make_blowoff()
	if _eng.is_empty():
		set_car(Data.CARS[0])


func set_enabled(on: bool) -> void:
	AudioServer.set_bus_mute(0, not on)


## Load the engine character of a car from Data.CARS.
func set_car(car: Dictionary) -> void:
	_eng = car.engine
	redline = float(_eng.redline)
	rpm = float(_eng.idle)
	_rpm_s = rpm
	gear = 1
	_build_table(int(_eng.cyl), float(_eng.res), float(_eng.decay), float(_eng.var), float(_eng.uneven), hash(car.id))


func _build_table(cyl: int, res: float, decay: float, variance: float, uneven: float, seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	_table.resize(TABLE)
	_env.resize(TABLE)
	_table.fill(0.0)
	var offsets: Array[float] = []
	var amps: Array[float] = []
	for k in cyl:
		var off := float(k) / cyl
		# alternate early/late firing on "banks" for an uneven V-engine burble
		off += uneven * (0.5 if k % 2 == 0 else -0.5) / cyl * rng.randf_range(0.6, 1.0)
		offsets.append(off)
		amps.append(1.0 + variance * rng.randf_range(-1.0, 1.0))
	for j in TABLE:
		var t := float(j) / TABLE
		var s := 0.0
		for k in cyl:
			var tp := fposmod(t - offsets[k], 1.0) * cyl  # time since this cylinder fired, in firing intervals
			if tp < 3.0:
				var e := exp(-tp * decay)
				s += amps[k] * (e * sin(TAU * res * tp + 0.4) + 0.9 * exp(-tp * decay * 2.6))
		_table[j] = s
	# remove DC, normalise
	var mean := 0.0
	for j in TABLE:
		mean += _table[j]
	mean /= TABLE
	var peak := 0.0001
	for j in TABLE:
		_table[j] -= mean
		peak = maxf(peak, absf(_table[j]))
	for j in TABLE:
		_table[j] /= peak
	# smoothed pulse envelope, used to modulate exhaust rasp
	var acc := 0.0
	for _round in 2:
		for j in TABLE:
			acc += 0.02 * (absf(_table[j]) - acc)
			_env[j] = acc


func _rpm_for(v: float, top: float, g: int) -> float:
	return v / maxf(top, 1.0) * redline * 0.93 * RATIOS[g - 1] / RATIOS[RATIOS.size() - 1]


## Called every frame. slip 0..1 drives tyre squeal.
func drive(v: float, top: float, gas: bool, brake: bool, slip: float, live: bool, dt: float) -> void:
	if _eng.is_empty():
		return
	_live = live
	_speed = v
	_slip = slip
	var idle := float(_eng.idle)
	var n := RATIOS.size()
	var prev_gear := gear
	if _shift_t > 0.0:
		_shift_t -= dt
	else:
		if gear < n and _rpm_for(v, top, gear) > redline * 0.95 and gas:
			gear += 1
			_shift_t = 0.24
		elif gear > 1 and _rpm_for(v, top, gear) < redline * 0.42:
			gear -= 1
			_shift_t = 0.16
			if brake or not gas:
				_blip_t = 0.14
	if gear > prev_gear and _eng.turbo and _boost > 0.4:
		play("blowoff", randf_range(0.95, 1.08), -6.0)
	var target := _rpm_for(v, top, gear)
	if gear == 1 and v < 7.0:
		target = maxf(target, idle + (1900.0 if gas else 0.0) * (1.0 - v / 7.0))  # clutch slip
	target = clampf(target, idle, redline)
	var k := 1.0 - exp(-dt * (7.0 if _shift_t > 0.0 else 16.0))
	if _blip_t > 0.0:
		_blip_t -= dt
		target = minf(redline, target + 900.0)
	rpm = lerpf(rpm, target, k)
	var want_load := 1.0 if gas else 0.0
	if _shift_t > 0.1:
		want_load = 0.0  # throttle lifted during the shift
	if _blip_t > 0.0:
		want_load = 0.7
	if gas and rpm > redline * 0.985:
		_limiter_t += dt
		if fmod(_limiter_t, 0.09) < 0.04:
			want_load = 0.0
	_load = lerpf(_load, want_load, 1.0 - exp(-dt * 14.0))
	_decel = 1.0 if (not gas and rpm > redline * 0.42 and _shift_t <= 0.0) else 0.0
	if _eng.turbo:
		var bt := clampf((rpm / redline - 0.3) * 1.6, 0.0, 1.0) * _load
		_boost = lerpf(_boost, bt, 1.0 - exp(-dt * (2.5 if bt > _boost else 6.0)))
	# bus colour: more grit and brightness with load and revs
	var rr := rpm / redline
	if _dist:
		_dist.drive = 0.18 + 0.42 * _load * (0.4 + 0.6 * rr)
	if _lp:
		_lp.cutoff_hz = 700.0 + 5200.0 * (0.25 + 0.75 * _load) * (0.3 + 0.7 * rr)


func _process(_delta: float) -> void:
	if _pb == null:
		return
	var n := _pb.get_frames_available()
	if n > 0:
		_pb.push_buffer(synth(n))


## Renders n stereo frames of engine/road audio from the current drive state.
func synth(n: int) -> PackedVector2Array:
	var buf := PackedVector2Array()
	buf.resize(n)
	if _table.is_empty():
		return buf
	var target_vol := (0.38 if _live else 0.16)
	var rasp := float(_eng.get("rasp", 0.4))
	var pop_p := float(_eng.get("pops", 0.5)) * 0.00035 * _decel
	var turbo: bool = _eng.get("turbo", false)
	var step := 1.0 / maxf(1.0, n)
	var rpm0 := _rpm_s
	var load0 := _load_s
	for i in n:
		# smooth control values across the buffer to avoid zipper noise
		_rpm_s = lerpf(rpm0, rpm, (i + 1) * step)
		_load_s = lerpf(load0, _load, (i + 1) * step)
		_vol_s += 0.0005 * (target_vol - _vol_s)
		_slip_s += 0.002 * (_slip - _slip_s)
		_speed_s += 0.001 * (_speed - _speed_s)
		var ld := _load_s
		_ph += (_rpm_s / 120.0) * TABLE / RATE  # four-stroke: one firing cycle per two revolutions
		if _ph >= TABLE:
			_ph -= TABLE
		var i0 := int(_ph)
		var fr := _ph - i0
		var s := lerpf(_table[i0], _table[(i0 + 1) & (TABLE - 1)], fr)
		var e := _env[i0]
		var nz := randf() * 2.0 - 1.0
		_n1 += 0.3 * (nz - _n1)    # mid noise: exhaust rasp
		_n2 += 0.04 * (nz - _n2)   # low noise: road rumble
		_n3 += 0.6 * (nz - _n3)    # bright noise: intake hiss
		var out := s * (0.32 + 0.68 * ld)
		out += _n1 * e * rasp * (0.25 + 0.75 * ld) * 1.4
		out += (_n3 - _n1) * ld * (_rpm_s / redline) * 0.12
		# lift-off pops and crackles
		if randf() < pop_p:
			_pop = randf_range(0.5, 1.0)
		_pop *= 0.9965
		_pop_lp += 0.35 * (nz * _pop - _pop_lp)
		out += _pop_lp * 1.3
		out *= _vol_s
		# turbo whine
		if turbo:
			_tph = fmod(_tph + (900.0 + _boost * 2600.0) / RATE, 1.0)
			out += sin(TAU * _tph) * _boost * 0.025
		# tyre squeal: resonant band-pass on noise
		if _slip_s > 0.02:
			_sq_ph = fmod(_sq_ph + 7.0 / RATE, 1.0)
			var fc := 1500.0 + 260.0 * sin(TAU * _sq_ph)
			var f := 2.0 * sin(PI * fc / RATE)
			_sv_low += f * _sv_band
			var high := nz - _sv_low - 0.06 * _sv_band
			_sv_band += f * high
			out += _sv_band * 0.04 * _slip_s
		# road and wind
		var sp := _speed_s / 70.0
		out += _n2 * sp * 0.5 + _n1 * sp * sp * 0.08
		buf[i] = Vector2(out, out)
	return buf


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


## Pass-by: band of noise that sweeps down in pitch (Doppler) as the car goes past.
func _make_whoosh() -> AudioStreamWAV:
	var n := int(RATE * 0.55)
	var out := PackedFloat32Array()
	out.resize(n)
	var low := 0.0
	var band := 0.0
	for i in n:
		var t := float(i) / n
		var env := pow(sin(PI * minf(1.0, t * 1.4)), 2.0) * (1.0 - t)
		var fc := lerpf(2600.0, 380.0, pow(t, 0.7))
		var f := 2.0 * sin(PI * fc / RATE)
		var nz := randf() * 2.0 - 1.0
		low += f * band
		var high := nz - low - 0.5 * band
		band += f * high
		out[i] = band * env * 0.9
	return _wav(out)


## Impact: low body thump, inharmonic metal ring and a little glass.
func _make_crash() -> AudioStreamWAV:
	var n := int(RATE * 1.0)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	var partials := [[233.0, 0.25, 9.0], [377.0, 0.2, 7.0], [611.0, 0.16, 11.0], [1043.0, 0.1, 14.0], [1697.0, 0.06, 18.0]]
	for i in n:
		var t := float(i) / RATE
		var nz := randf() * 2.0 - 1.0
		lp += lerpf(0.45, 0.03, minf(1.0, t * 2.0)) * (nz - lp)
		var s := lp * exp(-t * 5.0) * 1.3
		s += sin(TAU * lerpf(80.0, 40.0, minf(1.0, t * 3.0)) * t) * exp(-t * 9.0) * 0.9
		for p in partials:
			s += sin(TAU * p[0] * t) * p[1] * exp(-t * p[2])
		if t > 0.05 and t < 0.5 and randf() < 0.004:
			s += nz * 0.6  # glass tinkle
		out[i] = s * 0.8
	return _wav(out)


func _make_ding() -> AudioStreamWAV:
	var n := int(RATE * 0.22)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		out[i] = (sin(TAU * 660.0 * t) * 0.6 + sin(TAU * 1320.0 * t) * 0.2) * exp(-t * 16.0) * 0.4
	return _wav(out)


## Turbo blow-off valve "pssht" on upshifts.
func _make_blowoff() -> AudioStreamWAV:
	var n := int(RATE * 0.45)
	var out := PackedFloat32Array()
	out.resize(n)
	var prev := 0.0
	for i in n:
		var t := float(i) / n
		var nz := randf() * 2.0 - 1.0
		var hp := nz - prev
		prev = nz
		var flutter := 0.75 + 0.25 * sin(TAU * 34.0 * t * 0.45)
		out[i] = hp * minf(1.0, t * 25.0) * pow(1.0 - t, 1.6) * flutter * 0.35
	return _wav(out)
