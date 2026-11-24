extends Node
## The plants along the highway (Flora), apart from the game:
##   godot --headless --path . tools/flora_test.tscn
## For each of the six kinds of country: that it can be built and builds the same twice, how many plants and how many
## triangles it puts in the scene (a budget, so that a richer country does not quietly make the phone hotter), that no plant
## stands where a fuel stop or a speed check needs the ground bare, that every plant stands on the ground (the swell of
## the land raised by the country's relief, or the hills) and not in the air or under it, and how long it takes to build.
## Also that every plant has a mesh with a sane size and colour, that the highways' landscapes (Data.BIOMES) name a kind
## that exists and have what the ground shader and the horizon need, and that the ground functions agree with each other.
## (A scene, because Data is an autoload.) Exits with a non-zero code if a check fails.

const TRIANGLE_BUDGET := 450000   # triangles all the plants of one kind add up to in the scene (three repeats of 600 m of road)
const INSTANCE_BUDGET := 8000
const BUILD_MS := 150.0           # (desktop, headless: a phone takes three to five times as long)

var _fails := 0
var _checks := 0


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_fails += 1
		print("  FAIL: ", what)


func _ready() -> void:
	_meshes()
	_land()
	for kind in Flora.KINDS:
		_kind(kind)
	print("== %d checks, %d failed" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)


func _cfg() -> Dictionary:
	return {"period": Scenery.TREE_PERIOD, "behind": Scenery.VIEW_BEHIND, "rail": Data.RAIL, "opp_x": Scenery.OPP_X, "median_x": Scenery.MEDIAN_X,
		"site_clear": Scenery.site_clear, "ground": Scenery.ground_at}


func _tris(m: Mesh) -> int:
	var n := 0
	for s in m.get_surface_count():
		n += int(m.surface_get_array_len(s) / 3)
	return n


func _meshes() -> void:
	for key in Flora.PROPS:
		var m := Flora.mesh(key)
		var t := _tris(m)
		var bb := m.get_aabb()
		_check(t > 20 and t < 600, "%s has a sane number of triangles (%d)" % [key, t])
		_check(bb.size.y > 0.2 and bb.size.y < 30.0 and bb.size.x < 14.0 and bb.size.z < 14.0, "%s has a sane size (%.1f x %.1f x %.1f m)" % [key, bb.size.x, bb.size.y, bb.size.z])
		_check(bb.position.y > -0.3 and bb.position.y < 0.3, "%s stands on the ground (its foot is at %.2f)" % [key, bb.position.y])
		var arr := m.surface_get_arrays(0)
		var cols: PackedColorArray = arr[Mesh.ARRAY_COLOR]
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var bad := 0
		for i in cols.size():
			var c := cols[i]
			if not (c.r >= 0.0 and c.g >= 0.0 and c.b >= 0.0 and c.r <= 1.0 and c.g <= 1.0 and c.b <= 1.0):
				bad += 1
		for v in verts:
			if is_nan(v.x) or is_nan(v.y) or is_nan(v.z):
				bad += 1
		_check(cols.size() == verts.size() and bad == 0, "%s has a colour for every vertex, all of them real (%d bad)" % [key, bad])
		_check(Flora.material(Flora.thin(key)) != null, "%s has a material" % key)
	_check(Flora.material(true).cull_mode == BaseMaterial3D.CULL_DISABLED and Flora.material(false).cull_mode == BaseMaterial3D.CULL_BACK, "blades are drawn from both sides and solid plants are not")
	_check(Flora.material(false).vertex_color_is_srgb, "the colours are read as sRGB (as linear they came out three times too bright)")


func _land() -> void:
	for kind in Flora.KINDS:
		_check(Flora.RELIEF.has(kind) and float(Flora.RELIEF[kind]) > 0.3 and float(Flora.RELIEF[kind]) < 3.0, "%s has a relief" % kind)
		_check(Scenery.FAR.has(kind) and (Scenery.FAR[kind] as Array).size() == 2, "%s has two ranges on the horizon" % kind)
	for key in Data.BIOMES:
		var b: Dictionary = Data.BIOMES[key]
		_check(Flora.KINDS.has(b.get("flora", "")), "the %s country names a kind of plants that exists (%s)" % [key, str(b.get("flora", ""))])
		for k in ["grass_a", "grass_b", "field", "dirt", "accent", "fog", "sky", "hor"]:
			_check(b.has(k) and b[k] is Color, "the %s country has a colour for %s" % [key, k])
		_check(int(b.get("style", -1)) >= 0 and int(b.get("style", -1)) <= 4, "the %s country has a ground style (0 to 4)" % key)
	for r in Data.ROUTES:
		_check(Data.BIOMES.has(r.biome), "highway %s runs through a country that exists (%s)" % [r.name, r.biome])
	# the ground: flat at the road, rolling beyond, the hills past them, and the same on both sides of the road
	_check(Scenery.swell_h(0.0, 100.0, 1.0) == 0.0 and Scenery.swell_h(10.0, 250.0, 1.0) == 0.0 and Scenery.swell_h(10.0, 250.0, -1.0) == 0.0, "the ground is flat by the road")
	var hi := 0.0
	var neg := 0
	for i in 4000:
		var d := randf_range(0.0, 200.0)
		var pz := randf() * Scenery.TREE_PERIOD
		var side := 1.0 if randf() < 0.5 else -1.0
		var h := Scenery.swell_h(d, pz, side)
		hi = maxf(hi, h)
		if h < 0.0 or is_nan(h) or Scenery.hill_h(d, pz, side) < 0.0:
			neg += 1
	_check(neg == 0, "the ground is never below the flat (%d points were)" % neg)
	_check(hi > 1.5 and hi < 6.0, "the swells reach a few metres (highest %.1f m)" % hi)
	var period_ok := true
	for i in 200:
		var d := randf_range(10.0, 190.0)
		var pz := randf() * Scenery.TREE_PERIOD
		var a := Scenery.swell_h(d, pz, 1.0) + Scenery.hill_h(d, pz, 1.0)
		var b := Scenery.swell_h(d, pz + Scenery.TREE_PERIOD, 1.0) + Scenery.hill_h(d, pz + Scenery.TREE_PERIOD, 1.0)
		if absf(a - b) > 0.001:
			period_ok = false
	_check(period_ok, "the ground repeats every TREE_PERIOD (it is built once and repeated along the road)")
	var ga := Scenery.ground_at(Data.RAIL + 40.0, 123.0)
	var gb := Scenery.ground_at(Scenery.OPP_X - Data.RAIL - 40.0, 123.0)
	_check(is_equal_approx(ga.x, Scenery.swell_h(40.0, 123.0, 1.0)) and is_equal_approx(gb.x, Scenery.swell_h(40.0, 123.0, -1.0)), "ground_at finds the swell on either side of the highway")
	_check(Scenery.ground_at(0.0, 10.0) == Vector2.ZERO or Scenery.ground_at(0.0, 10.0).x == 0.0, "no ground height on the road itself")


func _kind(kind: String) -> void:
	var t0 := Time.get_ticks_usec()
	var a := Flora.build(kind, _cfg())
	var ms := float(Time.get_ticks_usec() - t0) / 1000.0
	var b := Flora.build(kind, _cfg())
	var inst := 0
	var tris := 0
	var h_a := 0
	var h_b := 0
	var off_ground := 0
	var in_site := 0
	var out_of_range := 0
	var keys_seen := {}
	var relief := float(Flora.RELIEF[kind])
	for batch in a.batches:
		keys_seen[batch.key] = true
		inst += (batch.items as Array).size()
		tris += _tris(batch.mesh) * (batch.items as Array).size()
		for it in batch.items:
			var tr: Transform3D = it[0]
			var c: Color = it[1]
			h_a = (h_a * 31) ^ int(hash(tr.origin.snapped(Vector3(0.001, 0.001, 0.001))))
			if is_nan(tr.origin.x) or is_nan(tr.origin.y) or is_nan(tr.origin.z) or tr.basis.get_scale().x < 0.1 or tr.basis.get_scale().x > 4.0:
				out_of_range += 1
			if c.r < 0.0 or c.g < 0.0 or c.b < 0.0 or c.r > 6.0 or c.g > 6.0 or c.b > 6.0:
				out_of_range += 1
			# pattern position of this plant: z along one period (the plants were laid out in three repeats)
			var pz := fposmod(Scenery.VIEW_BEHIND - tr.origin.z, Scenery.TREE_PERIOD)
			if Scenery.site_clear(pz, tr.origin.x):
				in_site += 1
			var g := Scenery.ground_at(tr.origin.x, pz)
			var want := maxf(g.x * relief, g.y)
			if absf(tr.origin.y - want) > 0.01:
				off_ground += 1
	for batch in b.batches:
		for it in batch.items:
			h_b = (h_b * 31) ^ int(hash((it[0] as Transform3D).origin.snapped(Vector3(0.001, 0.001, 0.001))))
	for batch in a.batches:
		_check(Flora.PROPS.has(batch.key) and batch.mesh != null, "%s: every batch is a plant with a mesh (%s)" % [kind, batch.key])
	_check(inst > 400 and inst <= INSTANCE_BUDGET, "%s: %d plants (budget %d)" % [kind, inst, INSTANCE_BUDGET])
	_check(tris > 50000 and tris <= TRIANGLE_BUDGET, "%s: %d triangles in the scene (budget %d)" % [kind, tris, TRIANGLE_BUDGET])
	_check(in_site == 0, "%s: no plant on a fuel stop or a speed check (%d were)" % [kind, in_site])
	_check(off_ground == 0, "%s: every plant stands on the ground (%d did not)" % [kind, off_ground])
	_check(out_of_range == 0, "%s: sizes and tints are sane (%d were not)" % [kind, out_of_range])
	_check(h_a == h_b and h_a != 0, "%s: built twice, the plants stand in the same places" % kind)
	_check(ms < BUILD_MS, "%s: built in %.1f ms (limit %.0f)" % [kind, ms, BUILD_MS])
	_check((a.blobs as Array).size() > 20, "%s: the big plants have their soft shadows (%d)" % [kind, (a.blobs as Array).size()])
	_check(keys_seen.has("tuft") or keys_seen.has("tall"), "%s: there is grass along the road" % kind)
	print("  %-9s %5d plants, %7d triangles, %d kinds of plant, %.1f ms" % [kind, inst, tris, keys_seen.size(), ms])
