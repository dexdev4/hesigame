extends Node
## The model cars' own lamps behave as a real car's do:
##   godot --headless --path . tools/lamp_test.tscn
## - the lamps lit with the headlights (the projectors, bulbs and amber parking lamps: tagged in their surface's name) glow
##   only faintly by day and fully at dusk (CarModel.set_night);
## - the third brake light (its surface "brake~...") is there, dark, and lights only while the car brakes, and not at all once
##   a crash has put the lamps out;
## - every tail lamp surface of the model is drawn (none is dropped when a model has more than one).
## Exits 1 if anything is wrong.

var _bad := 0


func _fail(msg: String) -> void:
	_bad += 1
	print("FAIL  ", msg)


## The surface names of a CPE2 mesh file.
static func _names(path: String) -> Array:
	var f := FileAccess.open(path, FileAccess.READ)
	var out: Array = []
	if f == null or f.get_buffer(4).get_string_from_ascii() != "CPE2":
		return out
	var n := f.get_32()
	for _i in n:
		out.append(f.get_buffer(f.get_32()).get_string_from_utf8())
		var nv := f.get_32()
		f.seek(f.get_position() + nv * 24)
		var ni := f.get_32()
		f.seek(f.get_position() + ni * 4)
	return out


func _ready() -> void:
	var jobs: Array = []
	for c in Data.CARS:
		jobs.append([String(c.id), String(c.shape), Color(c.color), c.style])
	for sh in ["sedan", "hatch", "suv", "van"]:
		jobs.append(["traffic " + sh, sh, Color("#2f5d8c"), CarModel.traffic_style(sh)])
	var beams := 0
	var brakes := 0
	for job in jobs:
		var shape_id: String = job[1]
		var pr: Dictionary = CarModel.PROFILES.get(shape_id, {})
		if not pr.has("mesh"):
			continue
		var names := _names(String(pr.mesh))
		var n_beam := 0
		var n_tail := 0
		var has_brake := false
		for nm in names:
			var p := String(nm).split("~")
			if p[0] == "head" and p.size() > 9 and p[9] == "1":
				n_beam += 1
			if p[0] == "tail":
				n_tail += 1
			if p[0] == "brake":
				has_brake = true
		var before := CarModel._beam_lamps.size()
		var m := CarModel.new()
		add_child(m)
		m.build(shape_id, job[2], Color("#b5322a"), job[3])
		# (a car built a second time shares its materials with the first: count only the first)
		var added := CarModel._beam_lamps.size() - before
		if n_beam > 0 and added == 0 and before == 0:
			_fail("%s: %d lamps lit with the headlights in its mesh, none taken up by the game" % [job[0], n_beam])
		var tails: Mesh = m._tails.mesh
		if n_tail > 0 and (tails == null or tails.get_surface_count() != n_tail):
			_fail("%s: %d tail lamp surfaces in its mesh, %d drawn" % [job[0], n_tail, tails.get_surface_count() if tails else 0])
		if has_brake:
			brakes += 1
			if m._brake_mi == null:
				_fail("%s: has a third brake light, but the game made none" % job[0])
			else:
				if m._brake_mi.visible:
					_fail("%s: third brake light lit while not braking" % job[0])
				m.set_brake(true)
				if not m._brake_mi.visible:
					_fail("%s: third brake light not lit while braking" % job[0])
				m.set_brake(false)
				if m._brake_mi.visible:
					_fail("%s: third brake light still lit after braking" % job[0])
				m.break_lamps()
				m.set_brake(true)
				if m._brake_mi.visible:
					_fail("%s: third brake light lit with the lamps smashed" % job[0])
		print("%-16s beam lamps %d, tail surfaces %d, third brake light %s" % [job[0], n_beam, n_tail, "yes" if has_brake else "no"])
		beams += n_beam
		m.queue_free()
	# by day a glint, at dusk the lamp's full glow
	CarModel.set_night(0.0, Vector3(0, 1, 0))
	for bl in CarModel._beam_lamps:
		var e := (bl[0] as StandardMaterial3D).emission_energy_multiplier
		if absf(e - float(bl[1]) * CarModel.BEAM_DAY) > 1e-4:
			_fail("a beam lamp glows %.3f by day (want %.3f)" % [e, float(bl[1]) * CarModel.BEAM_DAY])
	CarModel.set_night(1.0, Vector3(0, -1, 0))
	for bl in CarModel._beam_lamps:
		var e := (bl[0] as StandardMaterial3D).emission_energy_multiplier
		if absf(e - float(bl[1])) > 1e-4:
			_fail("a beam lamp glows %.3f at night (want %.3f)" % [e, float(bl[1])])
	CarModel.set_night(0.0, Vector3(0, 1, 0))
	if beams == 0:
		_fail("no car has a lamp lit with the headlights")
	if brakes == 0:
		_fail("no car has a third brake light")
	print("== %d cars, %d beam lamp materials, %d third brake lights: %s" % [jobs.size(), CarModel._beam_lamps.size(), brakes, "all as they should be" if _bad == 0 else "%d wrong" % _bad])
	get_tree().quit(1 if _bad > 0 else 0)
