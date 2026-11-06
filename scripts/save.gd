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
	}


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
		if k != "perm":
			data[k] = parsed[k]
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
