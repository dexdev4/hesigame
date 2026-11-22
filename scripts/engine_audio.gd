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
## pops, turbo whine, road and wind noise are mixed per sample.

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
var _interior := false
var quiet := false  # replay paused: engine silent

# synth state
var _ph := 0.0
var _n1 := 0.0
var _n2 := 0.0
var _n3 := 0.0
var _pop := 0.0
var _pop_lp := 0.0
var _tph := 0.0
var _vol_s := 0.0
var _load_s := 0.0
var _rpm_s := 900.0
var _speed_s := 0.0
var _decel := 0.0
var _table_off := PackedFloat32Array()  # overrun: same engine, softer and hollower
var _cyl := 4
var _fire_i := -1      # cylinder that fired last, for per-firing variation
var _fire_g := 1.0     # this firing's strength
var _fire_gs := 1.0
var _comb := PackedFloat32Array()  # exhaust pipe delay line
var _comb_i := 0
var _comb_lp := 0.0
var _comb_d := 140
var _cr_c := 1.0   # crank phasor (cos, sin) and its per-sample rotation
var _cr_s := 0.0
var _wh_c := 1.0   # gear whine phasor
var _wh_s := 0.0
var _shift_bark := 0.0
var _st_d := PackedFloat32Array()  # short delay for stereo width
var _st_i := 0

var _sfx := {}
var _players: Array[AudioStreamPlayer] = []
var _squeal: AudioStreamPlayer   # tyres sliding (the drift tune): the screech of rubber at the edge of its grip...
var _scrub: AudioStreamPlayer    # ...and the rougher roar of a tyre fully sideways or spinning
var _squeal_k := 0.0
var _flutter := 0.0              # a slow random waver on the loudness, so the loops never sound like loops
var _rng := RandomNumberGenerator.new()  # the sound's own noise: how much of it is made must never change the game's random numbers


## The two buses the player sets the loudness of (Settings › Display › Audio): "Music" (the chase songs) and "SFX"
## (everything you hear of the driving: the engine, the tyres, the crashes, the score and the menus' ticks).
static func ensure_buses() -> void:
	for n in ["Music", "SFX"]:
		if AudioServer.get_bus_index(n) < 0:
			var i := AudioServer.bus_count
			AudioServer.add_bus(i)
			AudioServer.set_bus_name(i, n)
			AudioServer.set_bus_send(i, "Master")


## How loud each is, 0 (silent) to 1 (full).
static func set_volumes(music: float, sfx: float) -> void:
	ensure_buses()
	for pair in [["Music", music], ["SFX", sfx]]:
		var i := AudioServer.get_bus_index(String(pair[0]))
		var v := clampf(float(pair[1]), 0.0, 1.0)
		AudioServer.set_bus_mute(i, v <= 0.001)
		AudioServer.set_bus_volume_db(i, linear_to_db(maxf(v, 0.001)))


func _ready() -> void:
	ensure_buses()
	_bus = AudioServer.get_bus_index("Engine")
	if _bus < 0:
		_bus = AudioServer.bus_count
		AudioServer.add_bus(_bus)
		AudioServer.set_bus_name(_bus, "Engine")
		AudioServer.set_bus_send(_bus, "SFX")
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
	AudioServer.set_bus_send(_bus, "SFX")  # (the engine is part of the driving's loudness)

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
		p.bus = "SFX"
		add_child(p)
		_players.append(p)
	_sfx["whoosh"] = _make_whoosh()
	_sfx["ping"] = _make_ping()
	_sfx["crash"] = _make_crash()
	_sfx["ding"] = _make_ding()
	_sfx["tick"] = _make_tick()
	_sfx["chime"] = _make_chime()
	_sfx["blowoff"] = _make_blowoff()
	_sfx["siren"] = _make_siren()
	_sfx["glass"] = _make_glass()
	_squeal = AudioStreamPlayer.new()
	_squeal.stream = _make_squeal()
	_squeal.volume_db = -60.0
	_squeal.bus = "SFX"
	add_child(_squeal)
	_scrub = AudioStreamPlayer.new()
	_scrub.stream = _make_scrub()
	_scrub.volume_db = -60.0
	_scrub.bus = "SFX"
	add_child(_scrub)
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
	_cyl = int(_eng.cyl)
	_build_table(_cyl, float(_eng.res), float(_eng.decay), float(_eng.var), float(_eng.uneven), hash(car.id))
	var on := _table.duplicate()
	var env_on := _env.duplicate()
	# overrun table: weaker combustion, lower resonance, so lifting off sounds hollow
	_build_table(_cyl, float(_eng.res) * 0.72, float(_eng.decay) * 1.5, float(_eng.var) * 1.6, float(_eng.uneven), hash(car.id))
	_table_off = _table
	_table = on
	_env = env_on
	# exhaust length sets where the pipe resonates (bigger engines, longer pipes)
	_comb_d = int(RATE * (0.0045 + 0.00035 * _cyl + float(hash(car.id) % 100) * 0.00002))
	_comb.resize(_comb_d)
	_comb.fill(0.0)
	_comb_i = 0
	_st_d.resize(17)
	_st_d.fill(0.0)


func _build_table(cyl: int, res: float, decay: float, variance: float, uneven: float, seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	_table = PackedFloat32Array()
	_env = PackedFloat32Array()
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


## Cockpit view: the engine is heard through the bulkhead, darker and closer.
func set_interior(on: bool) -> void:
	_interior = on


## How hard the tyres are sliding, 0 (gripping) .. 1 (fully sideways, or spinning), at `v` m/s. A tyre screeches most
## around the edge of its grip and less as it goes fully sideways, where the scrub of rubber dragged over the road takes
## over; both are louder and higher the faster the car is going, and both stop when the tyres grip again.
func set_squeal(k: float, dt: float, v := 25.0) -> void:
	_squeal_k = move_toward(_squeal_k, clampf(k, 0.0, 1.0), dt * (8.0 if k > _squeal_k else 4.0))
	if _squeal == null:
		return
	if _squeal_k < 0.02:
		for pl in [_squeal, _scrub]:
			if pl.playing:
				pl.stop()
		return
	_flutter = lerpf(_flutter, _rng.randf_range(-1.0, 1.0), minf(1.0, dt * 3.0))
	var sp := clampf(v / 35.0, 0.25, 1.15)
	var screech := smoothstep(0.03, 0.35, _squeal_k) * (1.0 - 0.35 * smoothstep(0.6, 1.0, _squeal_k)) * sp
	var scrub := smoothstep(0.35, 1.0, _squeal_k) * sp
	for pair in [[_squeal, screech * (0.62 + 0.08 * _flutter)], [_scrub, scrub * (0.55 + 0.06 * _flutter)]]:
		var pl: AudioStreamPlayer = pair[0]
		var vol: float = pair[1]
		if vol < 0.01:
			if pl.playing:
				pl.stop()
			continue
		if not pl.playing:
			pl.play(_rng.randf() * 1.5)   # (from somewhere in the loop: never the same start twice)
		pl.volume_db = linear_to_db(vol)
	_squeal.pitch_scale = 0.9 + 0.12 * _squeal_k + 0.1 * (sp - 0.7) + 0.015 * _flutter
	_scrub.pitch_scale = 0.75 + 0.35 * sp


## Called every frame with the player's speed and pedals.
func drive(v: float, top: float, gas: bool, brake: bool, live: bool, dt: float) -> void:
	if _eng.is_empty():
		return
	_live = live
	_speed = v
	var idle := float(_eng.idle)
	var n := RATIOS.size()
	var prev_gear := gear
	if _shift_t > 0.0:
		_shift_t -= dt
	else:
		if gear < n and _rpm_for(v, top, gear) > redline * 0.95 and gas:
			gear += 1
			_shift_t = 0.24
			_shift_bark = float(_eng.get("pops", 0.5))  # ignition cut on the upshift
		elif gear > 1 and _rpm_for(v, top, gear) < redline * 0.42:
			gear -= 1
			_shift_t = 0.16
			if brake or not gas:
				_blip_t = 0.14
	if gear > prev_gear and _eng.turbo and _boost > 0.4:
		play("blowoff", _rng.randf_range(0.95, 1.08), -6.0)
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
		_lp.cutoff_hz = (700.0 + 5200.0 * (0.25 + 0.75 * _load) * (0.3 + 0.7 * rr)) * (0.55 if _interior else 1.0)


func _process(_delta: float) -> void:
	if _pb == null or AudioServer.is_bus_mute(0):
		return  # nobody would hear it: the garage, or the sound turned off in Settings
	var n := _pb.get_frames_available()
	if n > 0:
		_pb.push_buffer(synth(n))


## Renders n stereo frames of engine/road audio from the current drive state.
func synth(n: int) -> PackedVector2Array:
	var buf := PackedVector2Array()
	buf.resize(n)
	if _table.is_empty() or _table_off.is_empty() or _comb.is_empty():
		return buf
	var target_vol := 0.0 if quiet else (0.38 if _live else 0.16)
	var rasp := float(_eng.get("rasp", 0.4)) * 1.4
	var pop_p := float(_eng.get("pops", 0.5)) * 0.00035 * _decel
	var bark_p := 0.004 * _shift_bark if _shift_t > 0.1 else 0.0
	var turbo: bool = _eng.get("turbo", false)
	var step := 1.0 / maxf(1.0, n)
	# crank rumble and gear whine oscillators, retuned once per buffer
	var wc := TAU * rpm / 60.0 / RATE
	var cr_cos := cos(wc)
	var cr_sin := sin(wc)
	var ww := TAU * minf(rpm / 60.0 * 17.0, 9000.0) / RATE
	var wh_cos := cos(ww)
	var wh_sin := sin(ww)
	var crank_amp := 0.07 * (1.0 - rpm / redline) * (0.5 + 0.5 * _load)
	var whine_amp := 0.006 * (1.0 if gear <= 3 else 0.4) * (0.4 + 0.6 * (1.0 - _load)) * minf(1.0, _speed / 8.0)
	var fire_k := float(_cyl) / TABLE
	var rng := _rng  # (a local: GDScript reads those far faster than members)
	var tb := _table
	var tb_off := _table_off
	var env := _env
	var comb := _comb
	var comb_d := _comb_d
	var std := _st_d
	# GDScript reads locals far faster than members, so the loop runs on copies
	var nrm := sqrt(_cr_c * _cr_c + _cr_s * _cr_s)  # keep the phasors from drifting
	var cr_c := _cr_c / nrm
	var cr_s := _cr_s / nrm
	nrm = sqrt(_wh_c * _wh_c + _wh_s * _wh_s)
	var wh_c := _wh_c / nrm
	var wh_s := _wh_s / nrm
	var ph := _ph
	var n1 := _n1
	var n2 := _n2
	var n3 := _n3
	var pop := _pop
	var pop_lp := _pop_lp
	var fire_i := _fire_i
	var fire_g := _fire_g
	var fire_gs := _fire_gs
	var comb_lp := _comb_lp
	var comb_i := _comb_i
	var vol_s := _vol_s
	var speed_s := _speed_s
	var speed_t := _speed
	var st_i := _st_i
	var tph := _tph
	var boost := _boost
	var rpm0 := _rpm_s
	var drpm := (rpm - _rpm_s) * step
	var load0 := _load_s
	var dload := (_load - _load_s) * step
	var inv_red := 1.0 / redline
	var ph_k := TABLE / RATE / 120.0  # four-stroke: one firing cycle per two revolutions
	for i in n:
		# smooth control values across the buffer to avoid zipper noise
		var rpm_s := rpm0 + drpm * (i + 1)
		var ld := load0 + dload * (i + 1)
		vol_s += 0.0005 * (target_vol - vol_s)
		speed_s += 0.001 * (speed_t - speed_s)
		ph += rpm_s * ph_k
		if ph >= TABLE:
			ph -= TABLE
		var i0 := int(ph)
		var fr := ph - i0
		var i1 := (i0 + 1) & (TABLE - 1)
		var s_on := tb[i0] + (tb[i1] - tb[i0]) * fr
		var s_off := tb_off[i0]  # the soft overrun table needs no interpolation
		var mixk := minf(ld * 1.3, 1.0)
		var s := s_off + (s_on - s_off) * mixk
		var nz := rng.randf() * 2.0 - 1.0
		# no two combustion strokes are identical: each firing gets its own
		# strength, rougher at idle and off throttle
		var fi := int(ph * fire_k)
		if fi != fire_i:
			fire_i = fi
			fire_g = 1.0 + (0.09 + 0.12 * (1.0 - ld)) * (rng.randf() * 2.0 - 1.0)
		fire_gs += 0.05 * (fire_g - fire_gs)
		n1 += 0.3 * (nz - n1)    # mid noise: exhaust rasp
		n2 += 0.04 * (nz - n2)   # low noise: road rumble
		n3 += 0.6 * (nz - n3)    # bright noise: intake hiss
		var out := s * fire_gs * (0.32 + 0.68 * ld)
		# crank rotation: a low lumpy rumble (rotating phasor, no sin() per sample)
		var cr := cr_c * cr_cos - cr_s * cr_sin
		cr_s = cr_c * cr_sin + cr_s * cr_cos
		cr_c = cr
		out += cr_s * crank_amp
		out += n1 * env[i0] * rasp * (0.25 + 0.75 * ld)
		out += (n3 - n1) * ld * (rpm_s * inv_red) * 0.12
		# lift-off pops and crackles, and the bark of an upshift's ignition cut
		if pop_p > 0.0 and rng.randf() < pop_p:
			pop = rng.randf_range(0.5, 1.0)
		elif bark_p > 0.0 and rng.randf() < bark_p:
			pop = rng.randf_range(0.6, 1.0)
		if pop > 0.001:
			pop *= 0.9965
			pop_lp += 0.35 * (nz * pop - pop_lp)
			out += pop_lp * 1.3
		# exhaust pipe: a feedback comb filter gives the hollow resonance of a
		# real system, darkened in the loop like a muffler would
		comb_lp += 0.45 * (comb[comb_i] - comb_lp)
		var piped := out + comb_lp * 0.42
		comb[comb_i] = piped
		comb_i += 1
		if comb_i >= comb_d:
			comb_i = 0
		out = (out * 0.3 + piped * 0.7) * 0.85
		# gearbox whine, strongest in the low gears and on the overrun
		var wr := wh_c * wh_cos - wh_s * wh_sin
		wh_s = wh_c * wh_sin + wh_s * wh_cos
		wh_c = wr
		out = (out + wh_s * whine_amp) * vol_s
		if turbo:
			tph += (900.0 + boost * 2600.0) / RATE
			if tph >= 1.0:
				tph -= 1.0
			out += sin(TAU * tph) * boost * 0.025
		# road and wind
		var sp := speed_s / 70.0
		out += n2 * sp * 0.5 + n1 * sp * sp * 0.08
		# a few samples of delay on one side widens the sound without blurring it
		var dl := std[st_i]
		std[st_i] = out
		st_i += 1
		if st_i >= 17:
			st_i = 0
		buf[i] = Vector2(out * 0.92 + dl * 0.08, out * 0.8 + dl * 0.2)
	_rpm_s = rpm
	_load_s = _load
	_ph = ph
	_n1 = n1
	_n2 = n2
	_n3 = n3
	_pop = pop
	_pop_lp = pop_lp
	_fire_i = fire_i
	_fire_g = fire_g
	_fire_gs = fire_gs
	_comb = comb
	_comb_lp = comb_lp
	_comb_i = comb_i
	_vol_s = vol_s
	_speed_s = speed_s
	_st_d = std
	_st_i = st_i
	_tph = tph
	_cr_c = cr_c
	_cr_s = cr_s
	_wh_c = wh_c
	_wh_s = wh_s
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


func _wav(samples: PackedFloat32Array, rate := RATE) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 30000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = int(rate)
	w.stereo = false
	w.data = bytes
	return w


## The scoring sound: a whoosh of air past the car, the faster the closer. A band of noise whose pitch sweeps up as it
## comes and down as it goes (a resonant filter from 320 Hz up to 2.8 kHz and back down to 520), over a low rush of air
## for weight and a faint falling tone that gives it its "fwoosh". Made at the full rate (the top of it needs the room);
## the game plays it lower and louder for a bigger score.
func _make_whoosh() -> AudioStreamWAV:
	var rate := SFX_RATE
	var n := int(rate * 0.5)
	var out := PackedFloat32Array()
	out.resize(n)
	var low := 0.0
	var band := 0.0
	var low2 := 0.0
	var band2 := 0.0
	var soft := 0.0
	var rush := 0.0
	var ph := 0.0
	for i in n:
		var t := float(i) / n
		var env := smoothstep(0.0, 0.26, t) * pow(1.0 - smoothstep(0.26, 1.0, t), 1.6)
		var fc := 320.0 + 2480.0 * exp(-pow((t - 0.3) / 0.17, 2.0)) + 200.0 * t
		var f := 2.0 * sin(PI * fc / rate)
		var nz := _rng.randf() * 2.0 - 1.0
		# two resonant band-passes one after the other (about Q 2 each: a band that falls away steeply on both sides)
		low += f * band
		band += f * (nz - low - 0.5 * band)
		low2 += f * band2
		band2 += f * (band - low2 - 0.5 * band2)
		soft += (band2 - soft) * 0.42         # (and the top taken off, above about 4 kHz)
		rush += (nz - rush) * 0.035           # (the low rush of air, under 250 Hz)
		var tf := lerpf(560.0, 170.0, t)
		ph += TAU * tf / rate
		out[i] = (soft * 1.1 + rush * 1.4 + sin(ph) * 0.1) * env
	return _wav(_level(out, 0.42), rate)


## A multiplier's ping (each time it goes up a whole number): a bright, clean strike of glass, quick to open and a third
## of a second to ring out, with a quieter shimmer a twelfth and an octave and a half above it.
func _make_ping() -> AudioStreamWAV:
	var rate := SFX_RATE
	var buf := PackedFloat32Array()
	buf.resize(int(rate * 0.6))
	var f0 := 1568.0   # G6
	for i in buf.size():
		var t := float(i) / rate
		var open := 1.0 - exp(-t * 2200.0)
		var s := sin(TAU * f0 * t) * exp(-t * 9.0)
		s += sin(TAU * f0 * 3.0 * t) * 0.18 * exp(-t * 22.0)
		s += sin(TAU * f0 * 2.76 * t) * 0.12 * exp(-t * 30.0)
		s += (_rng.randf() * 2.0 - 1.0) * 0.25 * exp(-t * 1800.0)   # (the tick of the strike)
		buf[i] = s * open
	return _wav(_level(_room(buf), 0.34), rate)


## The ping's pitch for a multiplier of n (2 and up): a step up a major scale for each whole number.
const MAJOR := [0, 2, 4, 5, 7, 9, 11, 12]
static func ping_pitch(n: int) -> float:
	return pow(2.0, float(MAJOR[clampi(n - 2, 0, MAJOR.size() - 1)]) / 12.0)


## Tyres sliding on tarmac: a cluster of close, wavering tones (the rubber's stick-slip) over a rough hiss, a loop of
## 1.2 s whose tones each fit a whole number of cycles into it, so it repeats without a click.
func _make_squeal() -> AudioStreamWAV:
	# A tyre's screech is not a note: the tread sticks and slips against the road hundreds of times a second, never
	# evenly, and that rough chatter rings the tyre and the road in bands that wander. So: a train of stick-slip clicks at
	# irregular intervals (about 650 a second, each a different size) plus a little hiss, rung through three resonances
	# around 1, 1.7 and 2.6 kHz whose pitches drift slowly and shake a little, with a random chatter on the loudness.
	var rate := 32000.0   # (its bands are under 3 kHz: this rate is plenty, and it is made quicker as the game starts)
	var T := 1.7
	var n := int(rate * T)
	var m := int(rate * 0.08)   # (made 80 ms longer, and that end blended into the start)
	var out := PackedFloat32Array()
	out.resize(n + m)
	var res := [[980.0, 9.0, 1.0], [1690.0, 11.0, 0.75], [2620.0, 8.0, 0.4]]   # centre, Q, level
	var st := []
	for r_ in res:
		st.append([0.0, 0.0, 0.0, 0.0])   # (low, band, drift, shake)
	var next_click := 0.0
	var click := 0.0
	var chatter := 1.0
	var chat_s := 1.0
	var chat_t := 0.0
	var hiss_lp := 0.0
	var peak := 0.0
	for i in n + m:
		# the stick-slip: a click now and then, sometimes a short burst of them
		next_click -= 1.0
		var x := 0.0
		if next_click <= 0.0:
			click = _rng.randf_range(0.3, 1.0) * (1.0 if _rng.randf() < 0.85 else 1.8)
			next_click = rate / 650.0 * _rng.randf_range(0.45, 1.6)
			x = click
		var nz := _rng.randf() * 2.0 - 1.0
		hiss_lp += 0.35 * (nz - hiss_lp)
		x += (nz - hiss_lp) * 0.22
		# the loudness chatters (the tyre loading and unloading, 6-16 times a second)
		chat_t -= 1.0
		if chat_t <= 0.0:
			chat_t = rate / _rng.randf_range(6.0, 16.0)
			chatter = _rng.randf_range(0.6, 1.0)
		var sig := 0.0
		for k in res.size():
			var r_: Array = res[k]
			var s_: Array = st[k]
			s_[2] = lerpf(float(s_[2]), _rng.randf_range(-1.0, 1.0), 0.00004)   # the slow drift of the band...
			s_[3] = lerpf(float(s_[3]), _rng.randf_range(-1.0, 1.0), 0.004)     # ...and its shake
			var fc := float(r_[0]) * (1.0 + 2.2 * float(s_[2]) * 0.06 + float(s_[3]) * 0.02)
			var f := 2.0 * sin(PI * fc / rate)
			var q := 1.0 / float(r_[1])
			s_[0] = float(s_[0]) + f * float(s_[1])
			s_[1] = float(s_[1]) + f * (x - float(s_[0]) - q * float(s_[1]))
			sig += float(s_[1]) * float(r_[2])
		chat_s += (chatter - chat_s) * 0.0015   # (eased, so the chatter never clicks)
		var y := sig * chat_s
		out[i] = y
		peak = maxf(peak, absf(y))
	for i in m:
		var k2 := float(i) / float(m)
		out[i] = out[i] * k2 + out[n + i] * (1.0 - k2)
	out.resize(n)
	var g := 0.85 / maxf(peak, 0.0001)
	for i in n:
		out[i] = clampf(out[i] * g, -1.0, 1.0)
	var w := _wav(out, rate)
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_begin = 0
	w.loop_end = n
	return w


## The scrub: a tyre dragged sideways over the road, or spinning, roars more than it screeches: a broad rumble of
## rubber on grit (noise between about 120 and 900 Hz), grainy, with a slow surge in it.
func _make_scrub() -> AudioStreamWAV:
	var rate := SFX_RATE
	var T := 2.0
	var n := int(rate * T)
	var m := int(rate * 0.08)
	var out := PackedFloat32Array()
	out.resize(n + m)
	var lp1 := 0.0
	var lp2 := 0.0
	var hp := 0.0
	var surge := 0.0
	var grain := 0.0
	var peak := 0.0
	for i in n + m:
		var nz := _rng.randf() * 2.0 - 1.0
		lp1 += 0.11 * (nz - lp1)       # (about 900 Hz)
		lp2 += 0.11 * (lp1 - lp2)
		hp += 0.017 * (lp2 - hp)       # (less of what is below about 120 Hz)
		var band := lp2 - hp
		surge = lerpf(surge, _rng.randf_range(0.55, 1.0), 0.00008)
		if _rng.randf() < 0.004:
			grain = _rng.randf_range(0.6, 1.4)   # (bits of grit)
		grain = lerpf(grain, 1.0, 0.002)
		var y := band * surge * grain
		out[i] = y
		peak = maxf(peak, absf(y))
	for i in m:
		var k := float(i) / float(m)
		out[i] = out[i] * k + out[n + i] * (1.0 - k)
	out.resize(n)
	var g := 0.8 / maxf(peak, 0.0001)
	for i in n:
		out[i] = clampf(out[i] * g, -1.0, 1.0)
	var w := _wav(out, rate)
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_begin = 0
	w.loop_end = n
	return w


## Impact: low body thump, inharmonic metal ring and a little glass.
func _make_crash() -> AudioStreamWAV:
	var n := int(RATE * 1.0)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	var partials := [[233.0, 0.25, 9.0], [377.0, 0.2, 7.0], [611.0, 0.16, 11.0], [1043.0, 0.1, 14.0], [1697.0, 0.06, 18.0]]
	for i in n:
		var t := float(i) / RATE
		var nz := _rng.randf() * 2.0 - 1.0
		lp += lerpf(0.45, 0.03, minf(1.0, t * 2.0)) * (nz - lp)
		var s := lp * exp(-t * 5.0) * 1.3
		s += sin(TAU * lerpf(80.0, 40.0, minf(1.0, t * 3.0)) * t) * exp(-t * 9.0) * 0.9
		for p in partials:
			s += sin(TAU * p[0] * t) * p[1] * exp(-t * p[2])
		if t > 0.05 and t < 0.5 and _rng.randf() < 0.004:
			s += nz * 0.6  # glass tinkle
		out[i] = s * 0.8
	return _wav(out)


const SFX_RATE := 44100.0  # the bells are made at the full rate: a sparkle on top needs the room


## One soft bell strike added into `buf` from sample `at`: an FM strike that settles to a pure tone, a quieter
## octave shimmer, a bright partial that dies at once and a two-millisecond tick for presence.
func _bell(buf: PackedFloat32Array, at: int, f0: float, gain: float, decay := 9.5, max_len := 0.5) -> void:
	var rate := SFX_RATE
	var n := mini(buf.size(), at + int(rate * max_len))  # (a bell is made for no longer than it is heard: this is built at start-up)
	for i in range(at, n):
		var t := float(i - at) / rate
		var env := (1.0 - exp(-t * 1100.0)) * exp(-t * decay)             # about a millisecond to open, then a soft fall
		if t > 0.01 and env < 0.0004:
			break  # (it has died away)
		var idx := 2.3 * exp(-t * 26.0)                                      # the FM depth: metallic at the strike, pure after
		var mod := sin(TAU * f0 * 3.5 * t)
		var tone := sin(TAU * f0 * t + idx * mod) * 0.78
		var shimmer := sin(TAU * f0 * 2.0 * t + 0.5 * idx * mod) * 0.4 * exp(-t * 12.0)
		var spark := sin(TAU * f0 * 5.02 * t) * 0.2 * exp(-t * 38.0)
		var tick := (_rng.randf() * 2.0 - 1.0) * exp(-t * 1100.0) * 0.3
		buf[i] += (tone + shimmer + spark + tick) * env * gain


## Adds a little room to a dry sound: three quiet, short echoes.
func _room(dry: PackedFloat32Array) -> PackedFloat32Array:
	var out := dry.duplicate()
	for e in [[0.019, 0.2], [0.043, 0.12], [0.071, 0.07]]:
		var d := int(SFX_RATE * float(e[0]))
		for i in range(d, dry.size()):
			out[i] += dry[i - d] * float(e[1])
	return out


## Brings the loudest sample to `peak`.
func _level(buf: PackedFloat32Array, peak: float) -> PackedFloat32Array:
	var m := 0.0001
	for v in buf:
		m = maxf(m, absf(v))
	var k := peak / m
	for i in buf.size():
		buf[i] *= k
	return buf


## The sound of a menu button going down: a short, soft, dry tick.
func _make_tick() -> AudioStreamWAV:
	var buf := PackedFloat32Array()
	buf.resize(int(SFX_RATE * 0.06))
	for i in buf.size():
		var t := float(i) / SFX_RATE
		buf[i] = (sin(TAU * 1750.0 * t) * 0.7 + sin(TAU * 2630.0 * t) * 0.3) * exp(-t * 110.0) * minf(1.0, t * 900.0)
	return _wav(_level(buf, 0.2), SFX_RATE)


## A soft, glassy bell (G5): the menus' and the game's little rewards (the game plays it higher or lower).
func _make_ding() -> AudioStreamWAV:
	var buf := PackedFloat32Array()
	buf.resize(int(SFX_RATE * 0.5))
	_bell(buf, 0, 784.0, 1.0)
	return _wav(_level(_room(buf), 0.32), SFX_RATE)


## A bigger reward (a boss beaten, an escape, a new highway): a rising three-note arpeggio with a last sparkle.
func _make_chime() -> AudioStreamWAV:
	var buf := PackedFloat32Array()
	buf.resize(int(SFX_RATE * 1.25))
	var notes := [[784.0, 0.0, 0.9], [987.8, 0.085, 0.9], [1174.7, 0.17, 0.95], [1568.0, 0.27, 0.8]]
	for nt in notes:
		_bell(buf, int(SFX_RATE * float(nt[1])), float(nt[0]), float(nt[2]), 6.5, 0.55)
	return _wav(_level(_room(buf), 0.36), SFX_RATE)


## Glass breaking: a sharp snap, then a shower of small bright pieces landing.
func _make_glass() -> AudioStreamWAV:
	var n := int(RATE * 0.7)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		var nz := _rng.randf() * 2.0 - 1.0
		lp += 0.3 * (nz - lp)
		var hp := nz - lp  # (high-passed noise)
		out[i] = hp * exp(-t * 85.0) * 1.0 + hp * exp(-t * 7.0) * 0.1
	for k in 40:
		var at := int(RATE * pow(_rng.randf(), 1.8) * 0.55)  # (more early than late)
		var f := _rng.randf_range(2200.0, 6200.0)
		var dec := _rng.randf_range(35.0, 90.0)
		var amp := _rng.randf_range(0.1, 0.32) * (1.0 - float(at) / float(n))
		for j in int(RATE * 0.08):
			if at + j >= n:
				break
			var tt := float(j) / RATE
			out[at + j] += sin(TAU * f * tt) * exp(-tt * dec) * amp
	var m := 0.0001
	for v in out:
		m = maxf(m, absf(v))
	for i in n:
		out[i] *= 0.5 / m
	return _wav(out)


## One rise-and-fall of a police wail (played on repeat during a pursuit).
func _make_siren() -> AudioStreamWAV:
	var n := int(RATE * 1.1)
	var out := PackedFloat32Array()
	out.resize(n)
	var ph := 0.0
	for i in n:
		var t := float(i) / n
		var f := 640.0 + 520.0 * sin(PI * t)
		ph += f / RATE
		var env := minf(1.0, t * 20.0) * minf(1.0, (1.0 - t) * 20.0)
		out[i] = (sin(TAU * ph) * 0.7 + sin(TAU * ph * 2.0) * 0.15) * env * 0.35
	return _wav(out)


## Turbo blow-off valve "pssht" on upshifts.
func _make_blowoff() -> AudioStreamWAV:
	var n := int(RATE * 0.45)
	var out := PackedFloat32Array()
	out.resize(n)
	var prev := 0.0
	for i in n:
		var t := float(i) / n
		var nz := _rng.randf() * 2.0 - 1.0
		var hp := nz - prev
		prev = nz
		var flutter := 0.75 + 0.25 * sin(TAU * 34.0 * t * 0.45)
		out[i] = hp * minf(1.0, t * 25.0) * pow(1.0 - t, 1.6) * flutter * 0.35
	return _wav(out)
