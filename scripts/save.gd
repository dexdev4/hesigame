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
		"owned": ["pulse"], "selected": "pulse", "unlocked": [],
		"perm": {"accel": 0, "brake": 0, "handling": 0, "top": 0, "lives": 0},  # old shared upgrades (moved to perm_cars)
		"perm_cars": {},  # car id -> {upgrade id: level}: each car is upgraded on its own
		"sound": true, "assist": false, "free_steer": true, "looks": {},
		"routes": 1, "route_sel": 0, "route_best": {},  # world map: highways open, chosen, best score on each
		"cam": _cam_defaults(),
		"settings": SETTING_DEFAULTS.duplicate(true),
	}


## Gameplay settings. Pedal positions are screen fractions of the pedal centre;
## an empty array means the default spot in the bottom corner.
const SETTING_DEFAULTS := {
	"steer_sens": 1.0, "pedal_scale": 1.0, "haptics": true, "shake": true, "units": "kmh",
	"gas_pos": [], "brake_pos": [], "wheel_pos": [], "arrows_pos": [],
	"steer_mode": "swipe",        # swipe, wheel, buttons, tilt or stick
	"tilt_invert": false,
	"orientation": "portrait",    # portrait or landscape; fixed, never follows the phone's sensor
	"mirror": true,               # on-screen rear-view mirror
	"mirror_scale": 1.0,
	"mirror_pos": [],
	"gfx": "",                    # high, medium or low; empty until the first launch picks one
	# developer tools
	"dev_lives": false,           # infinite lives
	"dev_fps": false,             # frame-rate counter
}


func setting(key: String) -> Variant:
	if not data.settings.has(key):
		data.settings[key] = SETTING_DEFAULTS[key] if not SETTING_DEFAULTS[key] is Array else []
	return data.settings[key]


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
		if k != "perm" and k != "cam" and k != "settings" and k != "perm_cars":
			data[k] = parsed[k]
	if parsed.has("cam") and parsed.cam is Dictionary:
		for k in parsed.cam:
			if k == "mode" and Data.CAM_MODES.has(parsed.cam.mode):
				data.cam.mode = parsed.cam.mode
			elif data.cam.has(k) and parsed.cam[k] is Dictionary:
				for kk in parsed.cam[k]:
					data.cam[k][kk] = float(parsed.cam[k][kk])
	if parsed.has("settings") and parsed.settings is Dictionary:
		for k in parsed.settings:
			if SETTING_DEFAULTS.has(k):
				data.settings[k] = parsed.settings[k]
	if parsed.has("perm") and parsed.perm is Dictionary:
		for k in parsed.perm:
			data.perm[k] = int(parsed.perm[k])
	# steering assist used to snap the car into lanes; it now only straightens
	# the car up, and starts off so the car drives freely like a real one
	if not parsed.has("free_steer"):
		data.assist = false
		data["free_steer"] = true
	# the starter car is always in the garage (older saves started with another car, which they keep)
	if data.owned is Array and not data.owned.has("pulse"):
		data.owned.insert(0, "pulse")
	if parsed.has("perm_cars") and parsed.perm_cars is Dictionary:
		for cid in parsed.perm_cars:
			var lv: Dictionary = {}
			for k in parsed.perm_cars[cid]:
				lv[k] = int(parsed.perm_cars[cid][k])
			data.perm_cars[cid] = lv
	else:
		# upgrades used to be shared by every car: give each owned car the
		# levels already paid for, so nothing is lost
		for cid in data.owned:
			data.perm_cars[cid] = (data.perm as Dictionary).duplicate()
	# JSON numbers load as floats; keep counters as ints.
	for k in ["cash", "best", "runs", "routes", "route_sel"]:
		data[k] = int(data[k])


func persist() -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data))


## The paint and wheels chosen in the workshop for a car, over its factory look.
func car_color(c: Dictionary) -> Color:
	var lk: Dictionary = data.get("looks", {}).get(c.id, {})
	var col: String = lk.get("color", "")
	return Color(col) if col != "" else Color(c.color)


func car_style(c: Dictionary) -> Dictionary:
	var st: Dictionary = (c.style as Dictionary).duplicate()
	var lk: Dictionary = data.get("looks", {}).get(c.id, {})
	for k in ["rim", "rim_color"]:
		if lk.has(k):
			st[k] = lk[k]
	return st


func set_look(id: String, key: String, value: String) -> void:
	if not data.has("looks") or not data.looks is Dictionary:
		data["looks"] = {}
	var lk: Dictionary = data.looks.get(id, {})
	if value == "":
		lk.erase(key)
	else:
		lk[key] = value
	data.looks[id] = lk
	persist()


## Developer tools: own and unlock every car.
func unlock_all_cars() -> void:
	for c in Data.CARS:
		if not data.owned.has(c.id):
			data.owned.append(c.id)
		if c.boss >= 0 and not data.unlocked.has(c.id):
			data.unlocked.append(c.id)
	persist()


## Developer tools: every permanent upgrade at its top level.
func max_all_upgrades() -> void:
	for c in Data.CARS:
		for p in Data.PERM:
			set_perm(p.id, int(p.max), c.id)
	persist()


## Developer tools: wipe cars, cash and upgrades but keep settings and camera.
func reset_progress() -> void:
	var keep_settings: Dictionary = data.settings
	var keep_cam: Dictionary = data.cam
	var keep := {"sound": data.sound, "assist": data.assist}
	data = defaults()
	data.settings = keep_settings
	data.cam = keep_cam
	data.merge(keep, true)
	persist()


## Level of an upgrade on a car (the selected car unless one is named).
func perm_level(id: String, car := "") -> int:
	var cid: String = car if car != "" else data.selected
	return int(data.perm_cars.get(cid, {}).get(id, 0))


func set_perm(id: String, level: int, car := "") -> void:
	var cid: String = car if car != "" else data.selected
	var lv: Dictionary = data.perm_cars.get(cid, {})
	lv[id] = level
	data.perm_cars[cid] = lv


func owns(id: String) -> bool:
	return data.owned.has(id)


func is_unlocked(id: String) -> bool:
	return data.unlocked.has(id)
