extends Node
## What building a car's body kit costs, and a fingerprint of what it builds (so that a change that is meant to make it
## quicker can be shown not to have changed a vertex):
##   godot --headless --path . tools/kit_test.tscn            (times, and one fingerprint for every kit)
##   godot --headless --path . tools/kit_test.tscn -- --print  (one line for each kit and mesh: to diff two builds)
##   godot --headless --path . tools/kit_test.tscn -- --verify (are the baked shells what measuring now gives?)
## Every kit the game uses is built for the first time, in the order the game meets them: each of the cars (its own style:
## the flags that shape its body), then the traffic's body types and the police car. A kit is built once a session and
## kept, so the first time is the one that hitches. Prints the time for the body and for its distant light version, and a
## hash of every mesh in it (the surfaces' vertices, normals, colours, UVs and indices, the cabin and the lamps).

var _lines: Array = []


func _ready() -> void:
	if OS.get_cmdline_user_args().has("--verify"):
		_verify_shells()
		return
	var full := OS.get_cmdline_user_args().has("--print")
	var notes := OS.get_cmdline_user_args().has("--notes")  # (what each kit's time went on: the engine's PerfProbe notes)
	PerfProbe.on = notes
	var total := 0.0
	var all_h := 0
	var jobs: Array = []
	for c in Data.CARS:
		jobs.append([String(c.id), String(c.shape), c.style])
	for sh in ["sedan", "hatch", "suv", "van", "truck"]:
		jobs.append(["traffic " + sh, sh, CarModel.traffic_style(sh)])
	jobs.append(["police", "sedan", {"rim": "steel", "badge": "POLICE", "plate": "PD 911"}])
	for job in jobs:
		var line := "%-16s" % job[0]
		for lq in [false, true]:
			var t0 := Time.get_ticks_usec()
			var kit: Dictionary = CarModel._kit(job[1], job[2], lq)
			var ms := float(Time.get_ticks_usec() - t0) / 1000.0
			total += ms
			if notes:
				var parts := []
				for e in PerfProbe.events:
					parts.append("%s %.1f" % [String(e[0]).strip_edges(), e[1]])
				print("    ", "; ".join(parts))
				PerfProbe.events.clear()
			var h := _hash_kit(kit, full, "%s%s" % [job[0], " lq" if lq else ""])
			all_h = all_h ^ h
			line += "  %s %7.1f ms (hash %08x)" % ["far " if lq else "body", ms, h & 0xffffffff]
		print(line)
	print("== %d kits, %.0f ms in all, fingerprint %08x" % [jobs.size() * 2, total, all_h & 0xffffffff])
	for l in _lines:
		print(l)
	get_tree().quit()


## Is every baked shell (assets/models/car_shells.shells) what measuring the body now gives? (Run it after changing a car
## mesh, a car's size or CarModel._shell_of; if it says no, run tools/bake_shells.tscn.)
func _verify_shells() -> void:
	var f := FileAccess.open_compressed(CarModel.SHELLS_FILE, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	var baked := {}
	if f != null:
		var d: Variant = f.get_var()
		if d is Dictionary and int((d as Dictionary).get("version", 0)) == CarModel.SHELLS_VERSION:
			baked = (d as Dictionary).get("shells", {})
	var n := preload("res://tools/bake_shells.gd").measure_all()
	var fresh: Dictionary = CarModel.baked_now
	var bad := 0
	for k in fresh:
		if not baked.has(k):
			print("MISSING  %s" % k)
			bad += 1
		elif baked[k] != fresh[k]:
			print("DIFFERS  %s" % k)
			bad += 1
	for k in baked:
		if not fresh.has(k):
			print("UNUSED   %s" % k)
			bad += 1
	print("== %d meshes, %d shells measured now, %d baked: %s" % [n, fresh.size(), baked.size(), "all the same" if bad == 0 else "%d wrong: run tools/bake_shells.tscn" % bad])
	get_tree().quit(1 if bad > 0 else 0)


func _hash_mesh(m: Mesh) -> int:
	var h := 17
	if m == null:
		return h
	for si in m.get_surface_count():
		var a := m.surface_get_arrays(si)
		for k in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_COLOR, Mesh.ARRAY_TEX_UV, Mesh.ARRAY_INDEX]:
			if a[k] != null:
				h = (h * 31) ^ hash(a[k])
		h = (h * 31) ^ m.surface_get_primitive_type(si)
	return h


func _hash_kit(kit: Dictionary, full: bool, label: String) -> int:
	var h := 7
	var keys := kit.keys()
	keys.sort()
	for k in keys:
		var v: Variant = kit[k]
		var hv := 0
		if v is Mesh:
			hv = _hash_mesh(v)
		elif v is Dictionary:  # (the shell)
			hv = 0
			var ks := (v as Dictionary).keys()
			ks.sort()
			for kk in ks:
				hv = (hv * 31) ^ int(hash((v as Dictionary)[kk]))
		else:
			hv = int(hash(v))
		h = (h * 131) ^ hv ^ int(hash(str(k)))
		if full:
			_lines.append("%s %s %08x" % [label, k, hv & 0xffffffff])
	return h
