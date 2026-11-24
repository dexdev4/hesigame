extends Node
## Measures the shell of every imported car body (CarModel._shell_of: for each spot on the floor plan the lowest roof, and
## for each height how far out the walls are, which keeps the cockpit and the cabin inside the bodywork) and writes the
## lot to assets/models/car_shells.shells, which the game reads instead of measuring (that took 60 to 150 ms for each body,
## in the middle of a race for a boss's). Run it again whenever a car mesh (assets/models/*.mesh), a car's size or the
## measuring changes (the game ignores a baked shell whose mesh file is not the size it was measured for, and measures
## that body itself, which is the slow way; `tools/kit_test.tscn -- --verify` says whether the baked ones are right):
##   godot --headless --path . tools/bake_shells.tscn

func _ready() -> void:
	var n := measure_all()
	var f := FileAccess.open_compressed(CarModel.SHELLS_FILE, FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	if f == null:
		push_error("cannot write %s" % CarModel.SHELLS_FILE)
		get_tree().quit(1)
		return
	f.store_var({"version": CarModel.SHELLS_VERSION, "shells": CarModel.baked_now})
	f.close()
	print("baked %d shells for %d meshes into %s (%d bytes)" % [CarModel.baked_now.size(), n, CarModel.SHELLS_FILE, FileAccess.get_file_as_bytes(CarModel.SHELLS_FILE).size()])
	get_tree().quit()


## Measure every imported body's shell afresh (into CarModel.baked_now): how many meshes it went through. Used by
## tools/kit_test.gd's --verify too.
static func measure_all() -> int:
	CarModel.bake_mode = true
	CarModel.baked_now = {}
	var n := 0
	for id in CarModel.PROFILES:
		var pr: Dictionary = CarModel.PROFILES[id]
		if not pr.has("mesh") or not Data.SHAPES.has(id):
			continue
		CarModel._kit(id, {}, false)
		n += 1
		if pr.has("mesh_lq"):
			CarModel._kit(id, {}, true)
			n += 1
	return n
