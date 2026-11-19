extends Node
## The lettering on the cars (Lettering, CarLettering, TailFrames), apart from the game:
##   godot --headless --path . tools/lettering_test.tscn
## For every name a car can wear (the garage's cars, the bosses, the police, the traffic's makes on each of its bodies), every
## haulier and every fixed number plate: that its typeface has every character, that its mesh is sound (triangles, no gaps
## in the numbers, a sane size), what it costs (triangles, against a budget, and how long it takes to build: it is built
## before a run, see Game._warm_up_list), that it is built once and kept, that it sits on the tail (TailFrames still fits the
## body's own triangles, so the letters neither hang in the air nor sink into the panel) and clear of the tail lamps.
## Exits with a non-zero code if a check fails.

const TRI_BUDGET := 7000       # triangles in one car's name (a long name in a serif face with a chamfer runs to 6,000)
const FLEET_BUDGET := 12000    # ...in a haulier's name
const BUILD_MS := 40.0         # to build one (desktop, headless: a phone takes three to five times as long)
const FIT := 0.004             # how far, m, the tail may be from where TailFrames says it is, under the name

const BakeTails := preload("res://tools/bake_tails.gd")

var _fails := 0
var _checks := 0


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_fails += 1
		print("  FAIL: ", what)


func _ready() -> void:
	_designs()
	var names: Array = []   # [shape, text]
	for car in Data.CARS:
		names.append([String(car.shape), String(car.style.badge)])
	names.append(["sedan", "POLICE"])
	for shape in ["sedan", "hatch", "suv", "van"]:
		for make in CarModel.MAKES:
			names.append([shape, String(make)])
	for n in names:
		_name(n[0], n[1])
	for car in Data.CARS:
		_plate(String(car.style.plate))
	for f in CarModel.FLEETS:
		_fleet(String(f))
	for car in Data.CARS:
		_on_tail(String(car.shape), String(car.style.badge))
	_on_tail("sedan", "POLICE")
	for shape in ["sedan", "hatch", "suv", "van"]:
		_on_tail(shape, "MERIT")
	_frames()
	print("== %d checks, %d failed" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)


func _designs() -> void:
	for car in Data.CARS:
		_check(CarLettering.has_design(String(car.style.badge)), "%s's name %s has a design of its own" % [car.id, car.style.badge])
	for make in CarModel.MAKES:
		_check(CarLettering.MAKES.has(make), "the make %s has a typeface" % make)
	for f in CarModel.FLEETS:
		_check(CarLettering.FLEETS.has(f), "the haulier %s has a typeface" % f)
	var all: Array = []
	all.append_array(CarLettering.BADGES.keys())
	all.append_array(CarLettering.MAKES.keys())
	for t in all:
		var s := CarLettering.spec(t)
		var font := CarLettering.font_of(s)
		_check(font != null, "%s: its typeface loads (%s)" % [t, s.font])
		if font == null:
			continue
		for word in [String(s.text), String(s.get("trim", ""))]:
			for ch in word:
				if ch != " ":
					_check(font.has_char(ch.unicode_at(0)), "%s: %s has the character %s" % [t, s.font, ch])
		_check(CarLettering.material(String(s.finish)) != null and CarLettering.material(String(s.trim_finish)) != null, "%s: its finishes exist" % t)
	for f in CarLettering.FLEETS:
		var font: Font = Fonts.file(String(CarLettering.FLEETS[f].font))
		for ch in String(f):
			if ch != " ":
				_check(font.has_char(ch.unicode_at(0)), "%s: has the character %s" % [f, ch])


func _sound(m: ArrayMesh, what: String) -> int:
	var tris := 0
	var bad := 0
	for si in m.get_surface_count():
		var v: PackedVector3Array = m.surface_get_arrays(si)[Mesh.ARRAY_VERTEX]
		var n: PackedVector3Array = m.surface_get_arrays(si)[Mesh.ARRAY_NORMAL]
		tris += v.size() / 3
		for i in v.size():
			if not (is_finite(v[i].x) and is_finite(v[i].y) and is_finite(v[i].z)) or absf(n[i].length() - 1.0) > 0.01:
				bad += 1
	_check(tris > 20 and bad == 0, "%s: a sound mesh (%d triangles, %d bad vertices)" % [what, tris, bad])
	return tris


func _name(shape: String, text: String) -> void:
	var t0 := Time.get_ticks_usec()
	var parts := CarLettering.parts(text, TailFrames.of(shape))
	var ms := float(Time.get_ticks_usec() - t0) / 1000.0
	var tris := 0
	for p in parts:
		tris += _sound(p.mesh, "%s on the %s" % [text, shape])
	var bb: AABB = (parts[0].mesh as ArrayMesh).get_aabb()
	var width: float = float(parts[parts.size() - 1].x) + float(parts[parts.size() - 1].width) - float(parts[0].x)
	_check(tris <= TRI_BUDGET, "%s on the %s: %d triangles (budget %d)" % [text, shape, tris, TRI_BUDGET])
	_check(ms < BUILD_MS, "%s on the %s: built in %.1f ms (limit %.0f)" % [text, shape, ms, BUILD_MS])
	_check(width > 0.15 and width < 0.62 and bb.size.y > 0.03 and bb.size.y < 0.12, "%s on the %s: a sane size (%.2f m wide, %.3f m high)" % [text, shape, width, bb.size.y])
	var t1 := Time.get_ticks_usec()
	var again := CarLettering.parts(text, TailFrames.of(shape))
	_check(again[0].mesh == parts[0].mesh and Time.get_ticks_usec() - t1 < 2000, "%s on the %s: built once and kept" % [text, shape])
	if ms > 0.2:   # (the first time it was built: shared meshes come back at once)
		print("  %-12s on %-11s %5d triangles  %.1f ms" % [text, shape, tris, ms])


func _plate(text: String) -> void:
	var mi := CarLettering.plate(text, 0.6, 0.0145)
	var tris := _sound(mi.mesh, "plate " + text)
	var bb: AABB = (mi.mesh as ArrayMesh).get_aabb()
	_check(bb.size.x < 0.46 and bb.size.y < 0.1, "plate %s fits on the plate (%.2f x %.2f m)" % [text, bb.size.x, bb.size.y])
	_check(tris < 2000, "plate %s: %d triangles" % [text, tris])
	mi.free()


func _fleet(text: String) -> void:
	var t0 := Time.get_ticks_usec()
	var mis := CarLettering.fleet(text, Color.WHITE, 1.25, 2.95, -3.9)
	var ms := float(Time.get_ticks_usec() - t0) / 1000.0
	var tris := _sound(mis[0].mesh, text)
	var bb: AABB = (mis[0].mesh as ArrayMesh).get_aabb()
	_check(bb.size.x <= CarLettering.FLEET_LENGTH + 0.01 and bb.size.y < 0.6, "%s fits along the trailer (%.2f m)" % [text, bb.size.x])
	_check(tris <= FLEET_BUDGET and ms < BUILD_MS * 2.0, "%s: %d triangles, %.1f ms" % [text, tris, ms])
	print("  %-22s %5d triangles  %.1f ms  %.2f m long" % [text, tris, ms, bb.size.x])
	for mi in mis:
		mi.free()


## The name lies on the tail: under each end and the middle of it the body is where the frame says it is, and no tail lamp
## is behind it.
func _on_tail(shape: String, text: String) -> void:
	var kit: Dictionary = CarModel._kit(shape)
	var fr := TailFrames.of(shape)
	var s := CarLettering.spec(text)
	var parts := CarLettering.parts(text, fr)
	var x0: float = parts[0].x
	var x1: float = float(parts[parts.size() - 1].x) + float(parts[parts.size() - 1].width)
	var y: float = float(fr.y) + float(s.dy)
	var worst := 0.0
	for x in [x0, (x0 + x1) * 0.5, x1]:
		for dy in [-0.4, 0.4]:
			var yy: float = y + dy * float(s.cap)
			var want: float = float(fr.z) + float(fr.slope) * (yy - float(fr.y)) + (float(fr.bow) * x * x if absf(float(fr.bow)) > 0.05 else 0.0)
			worst = maxf(worst, absf(BakeTails.tail_z(kit, x, yy) - want))
	_check(worst < FIT, "%s on the %s lies on the tail (off by %.1f mm at most)" % [text, shape, worst * 1000.0])
	var lamps := 0
	var tails: Mesh = kit.get("tails")
	if tails != null:
		for si in tails.get_surface_count():
			var arr := tails.surface_get_arrays(si)
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var idx: Variant = arr[Mesh.ARRAY_INDEX]
			var n: int = (idx as PackedInt32Array).size() if idx != null else v.size()
			for k in n:
				var p := v[(idx as PackedInt32Array)[k]] if idx != null else v[k]
				if p.z > -0.1 and p.x > x0 and p.x < x1 and absf(p.y - y) < float(s.cap) * 0.6:
					lamps += 1
	_check(lamps == 0, "%s on the %s is clear of the tail lamps (%d lamp points behind it)" % [text, shape, lamps])


func _frames() -> void:
	for id in TailFrames.FRAMES:
		if not Data.SHAPES.has(id):
			continue
		var live: Dictionary = BakeTails.measure(id)
		var fr: Dictionary = TailFrames.FRAMES[id]
		var ok: bool = absf(float(live.y) - float(fr.y)) < 0.002 and absf(float(live.z) - float(fr.z)) < 0.001 and absf(float(live.slope) - float(fr.slope)) < 0.01
		_check(ok, "TailFrames still fits the %s's body (run tools/bake_tails.tscn after changing a body)" % id)
