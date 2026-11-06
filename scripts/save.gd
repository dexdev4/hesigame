extends Node
## Persistent progress (cash, cars, permanent upgrades, settings).
## Registered as the autoload "Save". Stored as JSON in user://save.json.

const PATH := "user://save.json"

var data: Dictionary = {}


func _ready() -> void:
	load_data()


func defaults() -> Dictionary:
	return {
		"cash": 0, "best": 0, "runs": 0,
		"owned": ["kestrel"], "selected": "kestrel", "unlocked": [],
		"perm": {"accel": 0, "brake": 0, "handling": 0, "top": 0, "lives": 0},
		"sound": true, "assist": true,
		"cam": _cam_defaults(),
	}


func _cam_defaults() -> Dictionary:
	var c: Dictionary = Data.CAM_DEFAULTS.duplicate(true)
	c["mode"] = "chase"
	return c


## Settings for one camera view, with defaults filled in.
func cam(mode: String) -> Dictionary:
	if not data.cam.has(mode) or not data.cam[mode] is Dictionary:
		data.cam[mode] = Data.CAM_DEFAULTS[mode].duplicate()
	var c: Dictionary = data.cam[mode]
	for k in Data.CAM_DEFAULTS[mode]:
		if not c.has(k):
			c[k] = Data.CAM_DEFAULTS[mode][k]
	return c


func load_data() -> void:
	data = defaults()
	if not FileAccess.file_exists(PATH):
		return
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if not parsed is Dictionary:
		return
	for k in parsed:
		if k != "perm" and k != "cam":
			data[k] = parsed[k]
	if parsed.has("cam") and parsed.cam is Dictionary:
		for k in parsed.cam:
			if k == "mode" and Data.CAM_MODES.has(parsed.cam.mode):
				data.cam.mode = parsed.cam.mode
			elif data.cam.has(k) and parsed.cam[k] is Dictionary:
				for kk in parsed.cam[k]:
					data.cam[k][kk] = float(parsed.cam[k][kk])
	if parsed.has("perm") and parsed.perm is Dictionary:
		for k in parsed.perm:
			data.perm[k] = int(parsed.perm[k])
	# JSON numbers load as floats; keep counters as ints.
	for k in ["cash", "best", "runs"]:
		data[k] = int(data[k])


func persist() -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data))


func perm_level(id: String) -> int:
	return int(data.perm.get(id, 0))


func owns(id: String) -> bool:
	return data.owned.has(id)


func is_unlocked(id: String) -> bool:
	return data.unlocked.has(id)
