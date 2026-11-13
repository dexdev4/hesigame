class_name CarDamage
extends RefCounted
## What has happened to one car's body in crashes: dents pressed into its shell, scuffed paint, cracked glass,
## broken lamps and lost parts.
##
## A hit becomes a dent (a point in the car's own space, the way it was pushed, how wide and how deep). The dent
## is pressed into a private copy of the car's real meshes: every vertex near it moves along the push by a
## smooth falloff with a little crumple in it, its normal tilts down into the dent (so the reflections bend
## round it) and its baked ambient-occlusion colour darkens (scuffed, dirty paint). Because the body, its
## lamps and its glass are one shell, they all crumple together.
##
## The work is done on the engine's worker threads, a few thousand vertices at a time in parallel (`step` starts a
## batch and collects it, without ever waiting), so a hard knock never makes a long frame: the dents appear a moment
## after the blow, like a crumple. All the dents waiting are pressed in together, one pass over the vertices.
##
## The dents can be written out (`state`) and put back (`restore`), which is how a car keeps its damage from one
## run to the next, until it is paid for at the garage.
##
## Cars are in their own space: x across (+ right), y up, z along with the nose at -length (CarModel).

const MAX_DENTS := 8
const CHUNK := 6000   # vertices a worker takes at a time

signal done  # a batch of dents has been pressed into the meshes the car draws

## Every car with dents to press, being pressed or just pressed: the game steps them each frame (see `step`).
static var active: Array[CarDamage] = []

var model: CarModel
var dents: Array = []   # {p: Vector3, d: Vector3 (the push, unit), r: radius, a: depth}
var level := 0.0        # how knocked about it is: 0 untouched, 1 badly, 2 wrecked
var front := 0.0        # ...and where: the nose, the tail
var rear := 0.0
var sides := 0.0
var lamps_out := false
var smoking := false
var _queue: Array = []   # dents waiting to be pressed in
var _targets: Array = []  # {mi: MeshInstance3D, mesh: ArrayMesh, surfs: [{arrays: Array, prim: int}], inv: Transform3D, batch: Array}
var _prepared := false
var _group := -1          # the worker task pressing the current batch (-1: none)
var _jobs: Array = []     # [target, surface, first vertex, one past the last] for the current batch


func _init(m: CarModel) -> void:
	model = m


## Put `d` on the list the game steps every frame (nothing happens twice).
static func start(d: CarDamage) -> void:
	if not active.has(d):
		active.append(d)


## A number read back from a saved record (anything else, a gap or a word, counts as `fallback`, so that a damaged
## save file can't break the car).
static func num(v: Variant, fallback := 0.0) -> float:
	if (v is float or v is int) and is_finite(float(v)):
		return float(v)
	return fallback


## A number for the save file: rounded, and never one that JSON cannot hold.
static func _q(x: float) -> float:
	return snappedf(x, 0.001) if is_finite(x) else 0.0


## The game is closing: wait for the batches still on the worker threads (so that none is left running).
static func finish_all() -> void:
	for d in active:
		if d._group >= 0:
			WorkerThreadPool.wait_for_group_task_completion(d._group)
			d._group = -1
			d._jobs = []
	active.clear()


## A blow at `p` (the car's own space) pushing the shell along `d`, of `strength` (the change of speed it
## gave this car, m/s: 3 is a tap, 10 a hard knock).
func hit(p: Vector3, d: Vector3, strength: float) -> void:
	var a := clampf((strength - 1.0) * 0.045, 0.0, 0.46)
	if a < 0.03:
		return
	var r := 0.5 + a * 2.2
	d = d.normalized()
	if absf(d.z) > 0.6:
		d = (d + Vector3(0.0, -0.3, 0.0)).normalized()  # (a bonnet or a boot lid buckles down as well as in)
	# a blow close to an earlier dent deepens it instead of making another
	for dt in dents:
		if (dt.p as Vector3).distance_to(p) < 0.4 and (dt.d as Vector3).dot(d) > 0.5:
			var more := minf(a, 0.5 - float(dt.a))
			if more > 0.01:
				dt.a = float(dt.a) + more
				dt.r = maxf(float(dt.r), r)
				_queue.append({"p": dt.p, "d": dt.d, "r": r, "a": more})
				start(self)
			_account(p, a)
			return
	if dents.size() >= MAX_DENTS:
		return
	var dent := {"p": p, "d": d, "r": r, "a": a}
	dents.append(dent)
	_queue.append(dent.duplicate())
	# a hard knock at the nose or the tail also shortens the whole end of the car
	var half_l := float(model.shape.l) / 2.0
	if strength >= 8.0 and (p.z < -half_l * 1.4 or p.z > -half_l * 0.6) and dents.size() < MAX_DENTS:
		var wide := {"p": Vector3(0.0, 0.5, p.z), "d": d, "r": 1.5, "a": minf(0.04 + (strength - 8.0) * 0.025, 0.16)}
		dents.append(wide)
		_queue.append(wide.duplicate())
	_account(p, a)
	start(self)


func _account(p: Vector3, a: float) -> void:
	level += a * 2.2
	var half_l := float(model.shape.l) / 2.0
	if p.z < -half_l * 1.3:
		front += a
	elif p.z > -half_l * 0.7:
		rear += a
	else:
		sides += a


func busy() -> bool:
	return not _queue.is_empty() or _group >= 0


## The dents as plain numbers (a list of [x, y, z, push x, push y, push z, radius, depth]), to be saved.
func state() -> Array:
	var rows: Array = []
	for dt in dents:
		var p: Vector3 = dt.p
		var d: Vector3 = dt.d
		rows.append([_q(p.x), _q(p.y), _q(p.z), _q(d.x), _q(d.y), _q(d.z), _q(float(dt.r)), _q(float(dt.a))])
	return rows


## Put dents written out by `state` back on the car (they are pressed in on the worker threads, as a new blow's are).
func restore(rows: Array) -> void:
	dents.clear()
	_queue.clear()
	for row in rows:
		if not row is Array or (row as Array).size() < 8:
			continue
		var f: Array = row
		var dent := {"p": Vector3(num(f[0]), num(f[1]), num(f[2])), "d": Vector3(num(f[3]), num(f[4]), num(f[5])).normalized(),
			"r": clampf(num(f[6], 0.5), 0.1, 3.0), "a": clampf(num(f[7]), 0.0, 0.6)}
		if dents.size() >= MAX_DENTS:
			break
		dents.append(dent)
		_queue.append(dent.duplicate())
	if not _queue.is_empty():
		start(self)


## Carry on pressing dents. Starts a batch for everything waiting, and when a batch has finished puts it into the
## meshes the car draws. Never waits (unless `block`, for tests): the game calls it every frame. True while there
## is more to do.
func step(_budget_us := 0, block := false) -> bool:
	if _group >= 0:
		if not block and not WorkerThreadPool.is_group_task_completed(_group):
			return true
		WorkerThreadPool.wait_for_group_task_completion(_group)
		_group = -1
		_jobs = []
		if is_instance_valid(model):
			_rebuild()
			done.emit()
	if _queue.is_empty():
		return false
	if not is_instance_valid(model):  # (the car has been removed from the road)
		_queue.clear()
		return false
	if not _prepared:
		_prepare()  # (copying the meshes is a frame's work on its own)
		return true
	_start_batch()
	if block:
		return step(0, true)
	return true


## Private copies of the shell's meshes (the kit's meshes are shared by every car of its kind).
func _prepare() -> void:
	_prepared = true
	for mi in model.damage_targets():
		if mi == null or mi.mesh == null or not mi.mesh is ArrayMesh:
			continue
		var src := mi.mesh as ArrayMesh
		var surfs: Array = []
		var copy := ArrayMesh.new()
		var overrides: Array = []
		for s in src.get_surface_count():
			var arrays := src.surface_get_arrays(s)
			var prim := src.surface_get_primitive_type(s)
			surfs.append({"arrays": arrays, "prim": prim})
			copy.add_surface_from_arrays(prim, arrays)
			overrides.append(mi.get_surface_override_material(s))
		mi.mesh = copy
		for s in overrides.size():
			mi.set_surface_override_material(s, overrides[s])
		_targets.append({"mi": mi, "mesh": copy, "surfs": surfs, "inv": mi.transform.affine_inverse(), "batch": []})


## Everything waiting becomes one batch of jobs for the worker threads.
func _start_batch() -> void:
	var waiting := _queue
	_queue = []
	_jobs = []
	for ti in _targets.size():
		var tg: Dictionary = _targets[ti]
		var inv: Transform3D = tg.inv
		var rows: Array = []
		for dent in waiting:
			var r: float = dent.r
			var rs := r * 1.45  # the paint is scuffed a little beyond where the metal is pushed in
			rows.append([inv * (dent.p as Vector3), (inv.basis * (dent.d as Vector3)).normalized(), r, rs, rs * rs, float(dent.a)])
		tg.batch = rows
		var surfs: Array = tg.surfs
		for si in surfs.size():
			var n := (((surfs[si] as Dictionary).arrays as Array)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
			var i := 0
			while i < n:
				_jobs.append([ti, si, i, mini(i + CHUNK, n)])
				i += CHUNK
	if _jobs.is_empty():
		return
	_group = WorkerThreadPool.add_group_task(_work, _jobs.size(), -1, false, "car damage")


## One job, on a worker thread: press every dent of the batch into a run of vertices. (Only reads what the main thread
## leaves alone while a batch runs, and writes only its own vertices.)
func _work(idx: int) -> void:
	var job: Array = _jobs[idx]
	var tg: Dictionary = _targets[job[0]]
	var arrays: Array = ((tg.surfs as Array)[job[1]] as Dictionary).arrays
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var has_n := false
	var has_c := false
	var nv: Variant = arrays[Mesh.ARRAY_NORMAL]
	if nv is PackedVector3Array and (nv as PackedVector3Array).size() == verts.size():
		norms = nv
		has_n = true
	var cv: Variant = arrays[Mesh.ARRAY_COLOR]
	if cv is PackedColorArray and (cv as PackedColorArray).size() == verts.size():
		cols = cv
		has_c = true
	var batch: Array = tg.batch
	for i in range(int(job[2]), int(job[3])):
		var v := verts[i]
		var moved := false
		var nn := Vector3.ZERO
		var have_nn := false
		var shade := 1.0
		for e: Array in batch:
			var c: Vector3 = e[0]
			var dv := v - c
			var d2 := dv.length_squared()
			if d2 >= float(e[4]):
				continue
			var r: float = e[2]
			var rs: float = e[3]
			var a: float = e[5]
			var d := sqrt(d2)
			var t := maxf(0.0, 1.0 - d / r)
			var w := t * t * (3.0 - 2.0 * t)
			var ts := 1.0 - d / rs
			shade *= 1.0 - 0.62 * (ts * ts * (3.0 - 2.0 * ts))  # (the scuff reaches beyond the dent itself)
			if w > 0.0:
				# a little crumple in it: the depth ripples smoothly across the panel (smooth, so that the layers of the
				# shell, a lamp and the bumper round it, move together and do not push through one another)
				var crumple := 1.0 + 0.45 * sin(v.x * 9.0 + v.z * 5.0) * sin(v.y * 11.0 + v.x * 4.0 + 1.3)
				if has_n:
					if not have_nn:
						nn = norms[i]
						have_nn = true
					var g := dv / maxf(d, 0.001)
					var gt := g - nn * g.dot(nn)
					var slope := a * 6.0 * t * (1.0 - t) / r  # how steeply the dent's wall climbs here
					nn = (nn - gt * slope * 2.5).normalized()
				v += (e[1] as Vector3) * (a * w * crumple)
				moved = true
		if moved:
			verts[i] = v
			if has_n and have_nn:
				norms[i] = nn
		if has_c and shade < 0.9999:
			var col := cols[i]
			cols[i] = Color(col.r * shade, col.g * shade, col.b * shade, col.a)


## Put the changed vertices into the meshes the cars draw.
func _rebuild() -> void:
	for tg in _targets:
		var mesh: ArrayMesh = tg.mesh
		var mi: MeshInstance3D = tg.mi
		# a MeshInstance3D forgets the materials it overrides as soon as its mesh loses its surfaces: keep them
		var keep: Array = []
		if is_instance_valid(mi):
			for s in mi.get_surface_override_material_count():
				keep.append(mi.get_surface_override_material(s))
		mesh.clear_surfaces()
		for sf in tg.surfs:
			mesh.add_surface_from_arrays(sf.prim, sf.arrays)
		if is_instance_valid(mi):
			for s in mini(keep.size(), mi.get_surface_override_material_count()):
				if keep[s] != null:
					mi.set_surface_override_material(s, keep[s])
