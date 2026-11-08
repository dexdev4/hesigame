class_name Replay
extends RefCounted
## Rolling recording of the last LENGTH seconds of a run, for the replay
## editor. Each frame holds the player's state and every nearby car's state
## by id; car models are looked up by id when the frame is shown.

const LENGTH := 20.0
const RATE := 30.0  # frames recorded per second

var frames: Array[Dictionary] = []
var clock := 0.0     # seconds of driving recorded since the run started
var _acc := 0.0


func clear() -> void:
	frames.clear()
	clock = 0.0
	_acc = 0.0


## Advance the recording clock; true when it is time to store a frame.
func tick(dt: float) -> bool:
	clock += dt
	_acc += dt
	if _acc < 1.0 / RATE:
		return false
	_acc = fmod(_acc, 1.0 / RATE)
	return true


func push(f: Dictionary) -> void:
	f["t"] = clock
	frames.append(f)
	while frames.size() > 2 and frames[0].t < clock - LENGTH:
		frames.pop_front()


func empty() -> bool:
	return frames.size() < 2


func start_t() -> float:
	return frames[0].t if not frames.is_empty() else 0.0


func end_t() -> float:
	return frames[-1].t if not frames.is_empty() else 0.0


func duration() -> float:
	return end_t() - start_t()


## The recording at time `t`, blended between the two nearest frames.
func sample(t: float) -> Dictionary:
	var n := frames.size()
	if n == 0:
		return {}
	if t <= frames[0].t:
		return frames[0]
	if t >= frames[-1].t:
		return frames[-1]
	# binary search for the frame just before t
	var lo := 0
	var hi := n - 1
	while hi - lo > 1:
		var mid := (lo + hi) / 2
		if frames[mid].t <= t:
			lo = mid
		else:
			hi = mid
	var a: Dictionary = frames[lo]
	var b: Dictionary = frames[hi]
	var k: float = (t - float(a.t)) / maxf(float(b.t) - float(a.t), 0.0001)
	var out := a.duplicate()
	out.t = t
	var pa: PackedFloat32Array = a.p
	var pb: PackedFloat32Array = b.p
	var p := pa.duplicate()
	for i in p.size():
		p[i] = lerpf(pa[i], pb[i], k)
	# angles: blend along the short way round
	for i in [P_YAW, P_ROLL]:
		p[i] = pa[i] + wrapf(pb[i] - pa[i], -PI, PI) * k
	out.p = p
	var cars := {}
	var ca: Dictionary = a.cars
	var cb: Dictionary = b.cars
	for id in ca:
		var va: PackedFloat32Array = ca[id]
		if cb.has(id):
			var vb: PackedFloat32Array = cb[id]
			var v := va.duplicate()
			for i in 4:
				v[i] = lerpf(va[i], vb[i], k)
			cars[id] = v
		else:
			cars[id] = va
	out.cars = cars
	return out


# indices into a frame's player array "p"
const P_X := 0
const P_Z := 1
const P_V := 2
const P_VX := 3
const P_YAW := 4
const P_ROLL := 5
const P_AIR := 6
const P_CRASH := 7   # 1 while the last-life crash is playing
const P_GAS := 8
const P_BRAKE := 9
const P_STEER := 10
const P_GHOST := 11  # invulnerable glow
const P_PITCH := 12

# indices into each car's array: x, z, v, vx, braking, signal direction
const C_X := 0
const C_Z := 1
const C_V := 2
const C_VX := 3
const C_BRAKE := 4
const C_SIG := 5
