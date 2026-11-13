class_name CarDamage
extends RefCounted
## What has happened to one car's body in crashes: dents pressed into its shell, scuffed paint, cracked glass,
## broken lamps and lost parts.
##
## A hit becomes a dent (a point in the car's own space, the way it was pushed, how wide and how deep). The dent
## is pressed into a private copy of the car's real meshes: every vertex near it moves along the push by a
## smooth falloff with a little crumple in it, its normal tilts down into the dent (so the reflections bend
## round it) and its baked ambient-occlusion colour darkens (scuffed, dirty paint). Because the body, its
## lamps and its glass are one shell, they all crumple together. The work is done a few milliseconds a frame
## (`step`), so a pile-up of cars never makes a frame long: a dent presses in over a few frames, like a crumple.
##
## Cars are in their own space: x across (+ right), y up, z along with the nose at -length (CarModel).

const MAX_DENTS := 8

var model: CarModel
var dents: Array = []   # {p: Vector3, d: Vector3 (the push, unit), r: radius, a: depth}
var level := 0.0        # how knocked about it is: 0 untouched, 1 badly, 2 wrecked
var front := 0.0        # ...and where: the nose, the tail
var rear := 0.0
var sides := 0.0
var lamps_out := false
var smoking := false
var _queue: Array = []  # dents waiting to be pressed in
var _targets: Array = []  # {mi: MeshInstance3D, mesh: ArrayMesh, surfs: [{arrays: Array, prim: int}], inv: Transform3D, dirty: bool}
var _prepared := false


func _init(m: CarModel) -> void:
	model = m


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
	return not _queue.is_empty()


## Press the waiting dents in, for at most `budget_us` microseconds. True while there is more to do.
func step(budget_us: int) -> bool:
	if _queue.is_empty():
		return false
	if not is_instance_valid(model):  # (the car has been removed from the road)
		_queue.clear()
		return false
	var t0 := Time.get_ticks_usec()
	if not _prepared:
		_prepare()
		return true  # (copying the meshes is a frame's work on its own)
	while not _queue.is_empty():
		var dent: Dictionary = _queue[0]
		for tg in _targets:  # (a target that has finished this dent returns at once; one that has not carries on where it stopped)
			if not _press(tg, dent, t0, budget_us):
				return true  # out of time: carry on next frame
		_queue.pop_front()
		for tg in _targets:
			tg.pos_surf = 0
			tg.pos_vert = 0
		if Time.get_ticks_usec() - t0 > budget_us:
			break
	if _queue.is_empty():
		_rebuild()
		return false
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
		_targets.append({"mi": mi, "mesh": copy, "surfs": surfs, "inv": mi.transform.affine_inverse(), "dirty": false, "pos_surf": 0, "pos_vert": 0})


## Press one dent into one target's vertices, resuming where it left off. False if it ran out of time.
func _press(tg: Dictionary, dent: Dictionary, t0: int, budget_us: int) -> bool:
	var inv: Transform3D = tg.inv
	var c: Vector3 = inv * (dent.p as Vector3)
	var dir: Vector3 = (inv.basis * (dent.d as Vector3)).normalized()
	var r: float = dent.r
	var a: float = dent.a
	var rs := r * 1.45  # the paint is scuffed a little beyond where the metal is pushed in
	var r2 := rs * rs
	var surfs: Array = tg.surfs
	var si: int = tg.pos_surf
	while si < surfs.size():
		var arrays: Array = surfs[si].arrays
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var norms: Variant = arrays[Mesh.ARRAY_NORMAL]
		var cols: Variant = arrays[Mesh.ARRAY_COLOR]
		var has_n: bool = norms is PackedVector3Array and (norms as PackedVector3Array).size() == verts.size()
		var has_c: bool = cols is PackedColorArray and (cols as PackedColorArray).size() == verts.size()
		var i: int = tg.pos_vert if si == tg.pos_surf else 0
		var n := verts.size()
		while i < n:
			var v := verts[i]
			var dv := v - c
			var d2 := dv.length_squared()
			if d2 < r2:
				var d := sqrt(d2)
				var t := maxf(0.0, 1.0 - d / r)
				var w := t * t * (3.0 - 2.0 * t)
				var ts := 1.0 - d / rs
				var scuff := ts * ts * (3.0 - 2.0 * ts)
				# a little crumple in it: the depth ripples smoothly across the panel (smooth, so that the layers of the
				# shell, a lamp and the bumper round it, move together and do not push through one another)
				var crumple := 1.0 + 0.45 * sin(v.x * 9.0 + v.z * 5.0) * sin(v.y * 11.0 + v.x * 4.0 + 1.3)
				if w > 0.0:
					verts[i] = v + dir * (a * w * crumple)
				if has_n and w > 0.0:
					var nn: Vector3 = (norms as PackedVector3Array)[i]
					var g := dv / maxf(d, 0.001)
					var gt := g - nn * g.dot(nn)
					var slope := a * 6.0 * t * (1.0 - t) / r  # how steeply the dent's wall climbs here
					(norms as PackedVector3Array)[i] = (nn - gt * slope * 2.5).normalized()
				if has_c:
					var col: Color = (cols as PackedColorArray)[i]
					var f := 1.0 - 0.62 * scuff
					(cols as PackedColorArray)[i] = Color(col.r * f, col.g * f, col.b * f, col.a)
			i += 1
			if (i & 4095) == 0 and Time.get_ticks_usec() - t0 > budget_us:
				tg.pos_surf = si
				tg.pos_vert = i
				tg.dirty = true
				return false
		si += 1
		tg.pos_surf = si
		tg.pos_vert = 0
	tg.dirty = true
	return true


## Put the changed vertices into the meshes the cars draw.
func _rebuild() -> void:
	for tg in _targets:
		if not tg.dirty:
			continue
		tg.dirty = false
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
