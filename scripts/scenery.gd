class_name Scenery
extends Node3D
## The endless interstate: our four eastbound lanes, a grass median and the
## westbound carriageway with oncoming traffic, plus everything along it.
##
## Nothing here is streamed. The road meshes stay under the player while their
## shaders scroll; small repeating objects live in "loop" containers shifted by
## (distance mod period); big one-off structures (overpasses, sign gantries,
## billboards, farms) use "slots": a tiny pool re-dressed from a hash of the
## slot number, so the same stretch of road always looks the same.

const VIEW_AHEAD := 700.0
const VIEW_BEHIND := 60.0
const TREE_PERIOD := 600.0
const CHUNK := 150.0                    # long strips of trees and rocks are cut into pieces this long, so the renderer can skip the pieces nobody can see
const SCROLL_PERIOD := 3600.0
const OPP_X := -22.0                     # centre of the westbound carriageway
const MEDIAN_X := -11.0                  # halfway between the two inner guardrails
const OPP_LANES: Array[float] = [OPP_X - 5.4, OPP_X - 1.8, OPP_X + 1.8, OPP_X + 5.4]

const PLACES := ["Oak Hollow", "Mercer", "Lakeview", "Granite Falls", "Port Ellis", "Ashford", "Red Mesa",
	"Kingsbridge", "Dunmore", "Silver Creek", "Cedar Point", "Halloway", "Bristow", "New Carver"]
const ADS := [
	["REDLINE OIL", "Keeps it in the red", "#b0122a", "#f3f5ef"],
	["MOTEL 4", "Next exit · Free coffee", "#1f4e8c", "#f5b52e"],
	["BURGER BARN", "2 km · Open late", "#e0a020", "#2a1a08"],
	["CLOSE PASSES PAY", "Drive like it matters", "#1b1e23", "#f5b52e"],
	["GRIPMAX TYRES", "Corners on rails", "#2d4a36", "#f3f5ef"],
	["KESTREL MOTORS", "Your first car. Your last chance.", "#f3f5ef", "#0d6a42"],
]

var _road_mats: Array[ShaderMaterial] = []
var _grass_mat: ShaderMaterial
var _loops: Array = []      # [container, period]
var _slots: Array = []      # {period, offset, pool, setup}
var _km_sign: Node3D
var _km_label: Label3D
var _gantry: Node3D
var _clouds: Node3D
var _far_mats: Array[ShaderMaterial] = []
var _pool_mat: StandardMaterial3D
var _pools: MeshInstance3D
var _rock_mat: StandardMaterial3D
var _oncoming: Array = []   # {model, x, z, v}
var _t := 0.0

var M := {}  # shared materials


func _ready() -> void:
	M.concrete = CarModel.mat(Color("#a9a59c"), 0.0, 0.9)
	M.concrete_dark = CarModel.mat(Color("#7f7c75"), 0.0, 0.9)
	M.steel = CarModel.mat(Color("#b9bfc5"), 0.0, 0.35, 0.6)
	M.steel_dark = CarModel.mat(Color("#6c7278"), 0.0, 0.6, 0.4)
	M.white = CarModel.mat(Color("#eceae2"), 0.0, 0.7)
	M.amber = CarModel.mat(Color("#ffb020"), 2.5)
	M.lamp = CarModel.mat(Color("#f4ecc8"), 2.0)
	M.sign = CarModel.mat(Color("#0d6a42"), 0.0, 0.5)
	M.wood = CarModel.mat(Color("#6b5238"), 0.0, 0.95)
	M.wire = CarModel.mat(Color("#2a2c2e"), 0.0, 0.6)
	# the right-hand rail, its posts and markers get a gap where a fuel stop's exit lane leaves
	M.steel_cut = _cut_mat(Color("#b9bfc5"), 0.35, 0.6)
	M.steel_dark_cut = _cut_mat(Color("#6c7278"), 0.6, 0.4)
	M.wire_cut = _cut_mat(Color("#2a2c2e"), 0.6, 0.0)
	M.white_cut = _cut_mat(Color("#eceae2"), 0.7, 0.0)
	M.amber_cut = _cut_mat(Color("#ffb020"), 0.5, 0.0, 2.5)
	for k in 2:
		var gs := GasStation.new()
		gs.visible = false
		add_child(gs)
		_station_nodes.append(gs)

	var length := VIEW_AHEAD + VIEW_BEHIND
	var mid_z := -(VIEW_AHEAD - VIEW_BEHIND) / 2.0

	# --- road surfaces
	for cx in [0.0, OPP_X]:
		var mat := ShaderMaterial.new()
		mat.shader = load("res://shaders/road.gdshader")
		mat.set_shader_parameter("center_x", cx)
		mat.set_shader_parameter("median_side", -1.0 if cx == 0.0 else 1.0)  # (the median is on the left of ours and the right of the westbound one)
		var road := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(Data.RAIL * 2.0 + 1.0, length)
		pm.subdivide_depth = 40
		road.mesh = pm
		road.material_override = mat
		road.position = Vector3(cx, 0, mid_z)
		road.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(road)
		_road_mats.append(mat)
	_grass_mat = ShaderMaterial.new()
	_grass_mat.shader = load("res://shaders/grass.gdshader")
	_grass_mat.set_shader_parameter("edge_r", Data.RAIL + 0.5)
	_grass_mat.set_shader_parameter("edge_l", OPP_X - Data.RAIL - 0.5)
	var grass := MeshInstance3D.new()
	var gm := PlaneMesh.new()
	gm.size = Vector2(1600, length + 600)
	grass.mesh = gm
	grass.material_override = _grass_mat
	grass.position = Vector3(0, -0.03, mid_z - 300)
	grass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(grass)

	# --- continuous rails, fence wires and power lines
	var rails := [Data.RAIL, -Data.RAIL, OPP_X + Data.RAIL, OPP_X - Data.RAIL]
	var static_parts := {M.steel: [], M.wire: [], M.wood: []}
	for x in rails:
		if x == Data.RAIL:
			continue  # the right-hand rail is built in 4 m pieces (_build_loops) so fuel stops can open it
		var face: float = -0.04 * signf(x)  # lobes sit on the road side of the posts
		static_parts[M.steel].append([Vector3(x + face, 0.71, mid_z), Vector3(0.1, 0.13, length)])
		static_parts[M.steel].append([Vector3(x + face, 0.55, mid_z), Vector3(0.1, 0.13, length)])
		static_parts[M.wire].append([Vector3(x, 0.63, mid_z), Vector3(0.07, 0.05, length)])
	for x in [Data.RAIL + 14.0, OPP_X - Data.RAIL - 12.0]:
		for y in [0.55, 1.05]:
			static_parts[M.wood].append([Vector3(x, y, mid_z), Vector3(0.05, 0.1, length)])
	for dx in [-1.4, 0.0, 1.4]:
		static_parts[M.wire].append([Vector3(Data.RAIL + 24.0 + dx, 11.15, mid_z), Vector3(0.03, 0.03, length)])
	add_child(_merged(static_parts))

	_build_loops()
	_build_swell()
	_build_hills()
	_build_rocks()
	_build_far()
	_build_sea()
	_build_km_sign()
	_build_gantry()
	_add_slot(1300.0, 420.0, 2, _setup_sign_gantry)
	_add_slot(2100.0, 1150.0, 2, _setup_overpass)
	_add_slot(900.0, 260.0, 2, _setup_billboard)
	_add_slot(350.0, 90.0, 3, _setup_farm)
	_add_slot(2600.0, 700.0, 2, _setup_speed_sign)


# ---------------------------------------------------------------- fuel stops

## Fuel stops only ever stand at these sites: SITE metres into every
## TREE_PERIOD of road (game.gd places them). The repeating tree pattern
## keeps the ground there clear for the exit lane and the forecourt.
const SITE := 300.0

## Police speed checks (SpeedTrap) are parked at this site in every TREE_PERIOD of road, on the right outside the rail
## (the fuel stop's ground is 115 to 445 m in, its signs at 0 and 300): the bushes, trees and rocks keep it clear.
const TRAP_SITE := 520.0
const TRAP_HALF := 9.0     # m: half the length of the bay
const TRAP_WIDTH := 6.5    # m: how far beyond the rail it is kept clear

var _station_nodes: Array[GasStation] = []
var _stations: Array = []  # info dictionaries from game.gd: {z, name, prices, color}


## True if a tree, bush or rock at pattern position pz (and side x) would stand
## on a fuel stop's exit lane, forecourt or signs.
static func site_clear(pz: float, x: float) -> bool:
	if x < 0.0:
		return false
	if x < Data.RAIL + TRAP_WIDTH and absf(fposmod(pz - VIEW_BEHIND - TRAP_SITE + TREE_PERIOD / 2.0, TREE_PERIOD) - TREE_PERIOD / 2.0) < TRAP_HALF:
		return true  # a speed check's bay
	# road distance from the site, in -300..300 (pattern z maps to road z - VIEW_BEHIND)
	var rel := fposmod(pz - VIEW_BEHIND - SITE + TREE_PERIOD / 2.0, TREE_PERIOD) - TREE_PERIOD / 2.0
	if x < GasStation.OUTER_X + 2.5 and rel > -GasStation.EXIT_START - 15.0 and rel < GasStation.MERGE_END + 15.0:
		return true
	if x < Data.RAIL + 14.5 and rel > -GasStation.FORE - 25.0 and rel < GasStation.FORE + 15.0:
		return true  # forecourt, kiosk and price pylon, back to the farm fence
	for sign_rel in [-300.0, 0.0]:  # the approach signs (the one 600 m out lands on the previous site)
		if x < Data.RAIL + 9.4 and absf(rel - sign_rel) < 10.0:
			return true
	return false


## Road z of station site n.
static func site_z(n: int) -> float:
	return n * TREE_PERIOD + SITE


## The fuel stops to show (the next one, and the last one for the replay).
func set_stations(list: Array) -> void:
	_stations = list
	for i in _station_nodes.size():
		var node := _station_nodes[i]
		if i < list.size():
			var info: Dictionary = list[i]
			if node.get_meta("info_id", -1.0) != float(info.z):
				node.set_meta("info_id", float(info.z))
				node.set_info(info)
		else:
			node.visible = false


func _near_station(z_road: float) -> bool:
	for st in _stations:
		var rel: float = z_road - float(st.z)
		if rel > -GasStation.SIGNS[0] - 50.0 and rel < GasStation.MERGE_END + 60.0:
			return true
	return false


func _update_stations(base_z: float) -> void:
	var cuts := [Vector2(-1.0e6, -1.0e6), Vector2(-1.0e6, -1.0e6)]
	for i in _station_nodes.size():
		var node := _station_nodes[i]
		if i >= _stations.size():
			node.visible = false
			continue
		var sz: float = _stations[i].z
		var ahead := sz - base_z
		node.visible = ahead < VIEW_AHEAD + GasStation.SIGNS[0] and ahead > -GasStation.MERGE_END - VIEW_BEHIND - 40.0
		node.position.z = -ahead
		cuts[i] = Vector2(-(sz - GasStation.EXIT_START - 1.0 - base_z), -(sz + GasStation.MERGE_END + 1.0 - base_z))
	for m in [M.steel_cut, M.steel_dark_cut, M.wire_cut, M.white_cut, M.amber_cut]:
		(m as ShaderMaterial).set_shader_parameter("cut_a", cuts[0])
		(m as ShaderMaterial).set_shader_parameter("cut_b", cuts[1])


func _cut_mat(c: Color, rough: float, metal: float, glow := 0.0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/roadside_cut.gdshader")
	m.set_shader_parameter("albedo", c)
	m.set_shader_parameter("roughness", rough)
	m.set_shader_parameter("metallic", metal)
	m.set_shader_parameter("glow", glow)
	return m


# ---------------------------------------------------------------- building helpers

## One MeshInstance from boxes grouped by material: {material: [[center, size, basis?], ...]}.
func _merged(parts: Dictionary, shadows := true) -> MeshInstance3D:
	var mesh := ArrayMesh.new()
	var mats: Array = []
	for m in parts:
		if parts[m].is_empty():
			continue
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for b in parts[m]:
			st.set_uv(Vector2((b[0] as Vector3).z, 0.0))  # the box centre, for the fuel-stop gap
			if b.size() > 2 and b[2] is Basis:
				CarModel._box(st, b[0], b[1], b[2])
			else:
				CarModel._box(st, b[0], b[1])
		st.commit(mesh)
		mats.append(m)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	for i in mats.size():
		mi.set_surface_override_material(i, mats[i])
	if not shadows:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


func _loop(period: float) -> Node3D:
	var n := Node3D.new()
	add_child(n)
	_loops.append([n, period])
	return n


## local z positions for a loop: one every `period`, covering the view window.
func _loop_zs(period: float) -> Array:
	var zs := []
	var z := VIEW_BEHIND + period
	while z > -(VIEW_AHEAD + period):
		zs.append(z)
		z -= period
	return zs


func _build_loops() -> void:
	# guardrail posts on all four rails, every 4 m
	var posts := {M.steel_dark: [], M.steel_dark_cut: []}
	for z in _loop_zs(4.0):
		if z < -220.0:
			break
		for x in [Data.RAIL + 0.08, -Data.RAIL - 0.08, OPP_X + Data.RAIL + 0.08, OPP_X - Data.RAIL - 0.08]:
			posts[M.steel_dark_cut if x > 0.0 else M.steel_dark].append([Vector3(x, 0.3, z), Vector3(0.12, 0.6, 0.12)])
	_loop(4.0).add_child(_merged(posts, false))
	# right-hand guardrail in 4 m pieces, moving with the road (fuel stops open a gap in it)
	var rail_r := {M.steel_cut: [], M.wire_cut: []}
	for z in _loop_zs(4.0):
		var x: float = Data.RAIL - 0.04
		rail_r[M.steel_cut].append([Vector3(x, 0.71, z - 2.0), Vector3(0.1, 0.13, 4.0)])
		rail_r[M.steel_cut].append([Vector3(x, 0.55, z - 2.0), Vector3(0.1, 0.13, 4.0)])
		rail_r[M.wire_cut].append([Vector3(Data.RAIL, 0.63, z - 2.0), Vector3(0.07, 0.05, 4.0)])
	_loop(4.0).add_child(_merged(rail_r))

	# delineator posts with amber reflectors, every 25 m
	var delin := {M.white: [], M.amber: [], M.white_cut: [], M.amber_cut: []}
	for z in _loop_zs(25.0):
		for x in [Data.RAIL + 0.7, OPP_X - Data.RAIL - 0.7]:
			var right: bool = x > 0.0
			delin[M.white_cut if right else M.white].append([Vector3(x, 0.55, z), Vector3(0.1, 1.1, 0.1)])
			delin[M.amber_cut if right else M.amber].append([Vector3(x, 0.95, z + 0.055), Vector3(0.07, 0.14, 0.02)])
	_loop(25.0).add_child(_merged(delin, false))

	# twin-arm lamps in the median, every 55 m
	var lamps := {M.steel_dark: [], M.lamp: []}
	for z in _loop_zs(55.0):
		lamps[M.steel_dark].append([Vector3(MEDIAN_X, 5.0, z), Vector3(0.24, 10.0, 0.24)])
		lamps[M.steel_dark].append([Vector3(MEDIAN_X, 10.0, z), Vector3(8.0, 0.16, 0.16)])
		for s in [-1.0, 1.0]:
			lamps[M.lamp].append([Vector3(MEDIAN_X + s * 3.9, 9.88, z), Vector3(1.0, 0.16, 0.38)])
	_loop(55.0).add_child(_merged(lamps))
	# pools of lamplight on both carriageways, shown at night (see set_night)
	var pst := SurfaceTool.new()
	pst.begin(Mesh.PRIMITIVE_TRIANGLES)
	pst.set_normal(Vector3.UP)
	for z in _loop_zs(55.0):
		for cx in [MEDIAN_X + 7.0, MEDIAN_X - 7.0]:
			var hw := 9.0
			var hl := 10.0
			var v := [Vector3(cx - hw, 0.04, z - hl), Vector3(cx + hw, 0.04, z - hl), Vector3(cx + hw, 0.04, z + hl), Vector3(cx - hw, 0.04, z + hl)]
			var uv := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
			for k in [0, 2, 1, 0, 3, 2]:
				pst.set_uv(uv[k])
				pst.add_vertex(v[k])
	var pools := MeshInstance3D.new()
	pools.mesh = pst.commit()
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.86, 0.6, 0.55))
	g.set_color(1, Color(1.0, 0.8, 0.5, 0.0))
	g.add_point(0.45, Color(1.0, 0.84, 0.58, 0.3))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(0.5, 0.0)
	_pool_mat = StandardMaterial3D.new()
	_pool_mat.albedo_texture = gt
	_pool_mat.albedo_color = Color(1, 1, 1, 0)
	_pool_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_pool_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_pool_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_pool_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	_pool_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	pools.material_override = _pool_mat
	pools.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pools.visible = false
	_pools = pools
	_loop(55.0).add_child(pools)

	# farm fences, every 3 m
	var fence := {M.wood: []}
	for z in _loop_zs(3.0):
		for x in [Data.RAIL + 14.0, OPP_X - Data.RAIL - 12.0]:
			fence[M.wood].append([Vector3(x, 0.65, z), Vector3(0.12, 1.3, 0.12)])
	_loop(3.0).add_child(_merged(fence, false))

	# power-line poles, every 60 m
	var poles := {M.wood: [], M.white: []}
	for z in _loop_zs(60.0):
		var x := Data.RAIL + 24.0
		poles[M.wood].append([Vector3(x, 6.0, z), Vector3(0.3, 12.0, 0.3)])
		poles[M.wood].append([Vector3(x, 11.0, z), Vector3(3.4, 0.18, 0.18)])
		for dx in [-1.4, 0.0, 1.4]:
			poles[M.white].append([Vector3(x + dx, 11.15, z), Vector3(0.1, 0.22, 0.1)])
	_loop(60.0).add_child(_merged(poles))


# ---------------------------------------------------------------- plants, hills and rocks

var _flora := {}          # kind of country (Flora.KINDS) -> the loop holding its plants, built the first time it is wanted
var _hills: Array = []    # the hills of each side: [right, left]
var _swells: Array = []   # the rolling ground of each side
var _sea: MeshInstance3D
var _sea_mat: ShaderMaterial
var _rocks_holder: Node3D


func _flora_cfg() -> Dictionary:
	return {"period": TREE_PERIOD, "behind": VIEW_BEHIND, "rail": Data.RAIL, "opp_x": OPP_X, "median_x": MEDIAN_X, "site_clear": site_clear, "ground": ground_at}


const SWELL_FROM := 18.0   # m beyond the rail where the ground begins to roll
const HILLS_FROM := 78.0   # ...and where the hills begin


## How high the rolling ground stands (m, before the country's relief) d metres beyond the rail, pz along one TREE_PERIOD of
## road, on the right (side 1) or the left (-1) of the highway: flat by the road, swelling out to a few metres and then giving way to the hills.
static func swell_h(d: float, pz: float, side: float) -> float:
	var w := TAU / TREE_PERIOD
	var ph := 0.0 if side > 0.0 else 2.1
	var ramp := smoothstep(SWELL_FROM, SWELL_FROM + 40.0, d) * (1.0 - smoothstep(HILLS_FROM + 20.0, HILLS_FROM + 50.0, d))
	var h := 1.5 * sin(pz * w * 3.0 + ph + d * 0.03) + 1.0 * sin(pz * w * 8.0 + 1.3 + ph - d * 0.02) + 1.2 * sin(d * 0.05 + pz * w * 2.0 + ph * 1.7)
	return maxf(0.0, h + 0.7) * ramp * 0.9


## How high the hills stand d metres beyond the rail (they begin HILLS_FROM out).
static func hill_h(d: float, pz: float, side: float) -> float:
	var w := TAU / TREE_PERIOD
	var seed_ph := 0.0 if side > 0.0 else 2.3
	var dh := d - HILLS_FROM  # metres out from the hills' foot
	if dh <= 0.0:
		return 0.0
	var ramp := smoothstep(0.0, 70.0, dh)
	var hh := 14.0 + 9.0 * sin(pz * w * 2.0 + seed_ph) + 7.0 * sin(pz * w * 5.0 + 1.7 + seed_ph) + 4.0 * sin(pz * w * 11.0 + dh * 0.02)
	hh += 10.0 * sin(dh * 0.018 + pz * w * 3.0 + seed_ph)
	return maxf(0.0, maxf(0.0, hh) * ramp - 0.5)


## (swell, hill) heights at world x and pattern z (what Flora puts its plants on).
static func ground_at(x: float, pz: float) -> Vector2:
	var side := 1.0 if x > 0.0 else -1.0
	var d := (x - Data.RAIL) if x > 0.0 else (OPP_X - Data.RAIL - x)
	if d < 0.0:
		return Vector2.ZERO
	return Vector2(swell_h(d, pz, side), hill_h(d, pz, side))


## Make the plants of a kind of country (Flora) now, if that has not been done: about 40 ms. It is called when a highway is
## chosen (set_biome), and by the garage ahead of time (Game._warm_up_list), so that a run does not start with it.
func warm_flora(kind: String) -> void:
	if _flora.has(kind):
		return
	var t0 := PerfProbe.t()
	var data := Flora.build(kind, _flora_cfg())
	var holder := _loop(TREE_PERIOD)
	holder.visible = false
	# A multimesh is drawn whole or not at all, and the plants run the length of three TREE_PERIODs (1800 m, far more than can
	# be seen at once, and the shadow maps reach 90 m). So each kind of plant is cut into pieces CHUNK metres long: the
	# renderer then skips the pieces behind the car, beyond the far plane or out of the shadows' reach, and a piece
	# whose middle is farther than the plant's range (where the depth fog has hidden it) is not drawn at all.
	for b: Dictionary in data.batches:
		var groups := {}
		for item in b.items:
			var k := int(floor((item[0] as Transform3D).origin.z / CHUNK))
			if not groups.has(k):
				groups[k] = []
			(groups[k] as Array).append(item)
		for k in groups:
			var piece: Array = groups[k]
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_colors = true
			mm.mesh = b.mesh
			mm.instance_count = piece.size()
			for i in piece.size():
				mm.set_instance_transform(i, piece[i][0])
				mm.set_instance_color(i, piece[i][1])
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			mmi.material_override = Flora.material(bool(b.thin))
			if not b.shadow:
				mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			if float(b.range) > 0.0:
				mmi.visibility_range_end = float(b.range)
			holder.add_child(mmi)
	# soft contact shadows under the big plants, so they sit on the ground beyond the shadow distance
	var blob_mat := _blob_material()
	var sgroups := {}
	for t in data.blobs:
		var sk := int(floor((t as Transform3D).origin.z / CHUNK))
		if not sgroups.has(sk):
			sgroups[sk] = []
		(sgroups[sk] as Array).append(t)
	for sk in sgroups:
		var sitems: Array = sgroups[sk]
		var smm := MultiMesh.new()
		smm.transform_format = MultiMesh.TRANSFORM_3D
		smm.mesh = CarModel._shadow()
		smm.instance_count = sitems.size()
		for i in sitems.size():
			smm.set_instance_transform(i, sitems[i])
		var smi := MultiMeshInstance3D.new()
		smi.multimesh = smm
		smi.material_override = blob_mat
		smi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		smi.visibility_range_end = 300.0
		holder.add_child(smi)
	_flora[kind] = holder
	PerfProbe.note("plants of the %s country" % kind, t0)


static var _blob_mat: StandardMaterial3D


## The soft patch of shade under a plant: fainter than a car's (a plant near the car has its real shadow as well).
static func _blob_material() -> StandardMaterial3D:
	if _blob_mat == null:
		var g := Gradient.new()
		g.set_color(0, Color(0, 0, 0, 0.3))
		g.set_color(1, Color(0, 0, 0, 0.0))
		g.add_point(0.55, Color(0, 0, 0, 0.2))
		var tex := GradientTexture2D.new()
		tex.gradient = g
		tex.fill = GradientTexture2D.FILL_RADIAL
		tex.fill_from = Vector2(0.5, 0.5)
		tex.fill_to = Vector2(0.5, 0.0)
		tex.width = 64
		tex.height = 64
		_blob_mat = StandardMaterial3D.new()
		_blob_mat.albedo_texture = tex
		_blob_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_blob_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_blob_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	return _blob_mat


## The landscape of the highway being driven (a Data.BIOMES entry).
func set_biome(land: Dictionary) -> void:
	for k in ["grass_a", "grass_b", "field", "dirt", "accent"]:
		_grass_mat.set_shader_parameter(k, land[k])
	_grass_mat.set_shader_parameter("style", int(land.get("style", 0)))
	_grass_mat.set_shader_parameter("sea_x", float(land.get("sea_x", -1.0e5)))
	if _rock_mat:
		_rock_mat.albedo_color = (land.dirt as Color).lerp(Color("#8d8a82"), 0.55)
	var kind: String = land.get("flora", "temperate")
	warm_flora(kind)
	for k in _flora:
		(_flora[k] as Node3D).visible = k == kind
	_set_far(kind)
	var shore: float = land.get("sea_x", 0.0)
	var by_the_sea: bool = land.has("sea_x")
	_sea.visible = by_the_sea
	if by_the_sea:
		_sea.position.x = shore - 1300.0
		_sea_mat.set_shader_parameter("shore_x", shore)
	(_hills[1] as Node3D).visible = not by_the_sea   # (the left of a coast road is the beach and the sea)
	(_swells[1] as Node3D).visible = not by_the_sea
	var relief: float = Flora.RELIEF.get(kind, 1.0)  # (how much the ground rolls here: the swells and the rocks on them are raised by it)
	for sw in _swells:
		(sw as Node3D).scale.y = relief
	if _rocks_holder:
		_rocks_holder.scale.y = relief


## Rolling country beyond the fields on both sides: low hills with darker woods along their crests, one seamless
## TREE_PERIOD strip repeated (so it scrolls with the road like the plants). They are drawn with the ground's own shader, so
## their colour carries on from the fields without a seam, and follows the highway's country (set_biome).
func _build_hills() -> void:
	var nx := 16
	var nz := 60
	for side in [1.0, -1.0]:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for i in nx:
			for j in nz:
				var xa := float(i) / nx
				var xb := float(i + 1) / nx
				var za := float(j) / nz * TREE_PERIOD
				var zb := float(j + 1) / nz * TREE_PERIOD
				var quad := [[xa, za], [xb, za], [xb, zb], [xa, zb]]
				var verts: Array = []
				var cols: Array = []
				for q in quad:
					var d: float = HILLS_FROM + float(q[0]) * 260.0
					var hx := hill_h(d, q[1], side) if q[0] > 0.0 else -0.5
					var px: float = (Data.RAIL + d) if side > 0.0 else (OPP_X - Data.RAIL - d)
					verts.append(Vector3(px, hx, VIEW_BEHIND - q[1]))
					# woods on the higher ground, meadow below
					var wood := smoothstep(16.0, 26.0, hx)
					cols.append(Color(1, 1, 1).lerp(Color(0.62, 0.7, 0.58), wood))
				var n: Vector3 = ((verts[1] as Vector3) - (verts[0] as Vector3)).cross((verts[3] as Vector3) - (verts[0] as Vector3)).normalized()
				if n.y < 0.0:
					n = -n
				for k in [0, 1, 2, 0, 2, 3]:
					st.set_color(cols[k])
					st.set_normal(n)
					st.add_vertex(verts[k])
		st.generate_normals()
		var mesh := st.commit()
		var holder := _loop(TREE_PERIOD)
		for rep in 3:
			var mi := MeshInstance3D.new()
			mi.mesh = mesh
			mi.material_override = _grass_mat
			mi.position.z = -float(rep) * TREE_PERIOD
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			holder.add_child(mi)
		_hills.append(holder)


## The ground rolling gently beside the road, out to where the hills take over: a strip of low swells, one TREE_PERIOD
## repeated, in the ground's own shader (so there is no seam), raised by the country's relief (set_biome). It is what keeps
## the land from being a table: the plants stand on it (Flora).
func _build_swell() -> void:
	var nd := 16
	var nz := 50
	var d0 := SWELL_FROM - 6.0
	var d1 := HILLS_FROM + 52.0
	for side in [1.0, -1.0]:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for i in nd:
			for j in nz:
				var quad := [[i, j], [i + 1, j], [i + 1, j + 1], [i, j + 1]]
				var verts: Array = []
				for q in quad:
					var d := lerpf(d0, d1, float(q[0]) / nd)
					var pz := float(q[1]) / nz * TREE_PERIOD
					var px: float = (Data.RAIL + d) if side > 0.0 else (OPP_X - Data.RAIL - d)
					verts.append(Vector3(px, swell_h(d, pz, side), VIEW_BEHIND - pz))
				for k in [0, 1, 2, 0, 2, 3]:
					st.set_color(Color(1, 1, 1))
					st.set_normal(Vector3.UP)
					st.add_vertex(verts[k])
		st.generate_normals()
		var mesh := st.commit()
		var holder := _loop(TREE_PERIOD)
		for rep in 3:
			var mi := MeshInstance3D.new()
			mi.mesh = mesh
			mi.material_override = _grass_mat
			mi.position.z = -float(rep) * TREE_PERIOD
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			holder.add_child(mi)
		_swells.append(holder)


## Boulders and rock outcrops along the verges and out on the hills: lumpy faceted stones in clusters (a big one with a few
## small ones beside it), one TREE_PERIOD strip repeated. Each piece of the strip is its own mesh, drawn only while it is near.
## Colour follows the highway's country (set_biome).
func _build_rocks() -> void:
	var holder := _loop(TREE_PERIOD)
	_rocks_holder = holder
	var rng := RandomNumberGenerator.new()
	rng.seed = 53
	var pattern: Array = []
	for k in 150:
		var z := rng.randf() * TREE_PERIOD
		var right := rng.randf() < 0.5
		var x: float = (Data.RAIL + rng.randf_range(5.0, 95.0)) if right else (OPP_X - Data.RAIL - rng.randf_range(5.0, 95.0))
		if site_clear(z, x):
			continue
		var big := rng.randf_range(0.7, 2.6) * (1.0 + 2.0 * float(rng.randf() < 0.12))
		pattern.append([Vector3(x, 0, z), big, rng.randf() * TAU])
		for q in rng.randi_range(1, 4):
			pattern.append([Vector3(x + rng.randf_range(-2.2, 2.2) * big, 0, z + rng.randf_range(-2.2, 2.2) * big), big * rng.randf_range(0.25, 0.6), rng.randf() * TAU])
	var chunks := {}  # which CHUNK of the strip -> its SurfaceTool
	for it in pattern:
		var c: Vector3 = it[0]
		var r: float = it[1]
		var ck := int(floor(fposmod(c.z, TREE_PERIOD) / CHUNK))
		if not chunks.has(ck):
			var nst := SurfaceTool.new()
			nst.begin(Mesh.PRIMITIVE_TRIANGLES)
			chunks[ck] = nst
		var st: SurfaceTool = chunks[ck]
		var pos := Vector3(c.x, ground_at(c.x, c.z).x, -c.z + VIEW_BEHIND)  # (on the swell: the holder's height is the country's relief)
		var tone := 0.88 + 0.2 * rng.randf()
		var tint := Color(tone, tone * rng.randf_range(0.97, 1.03), tone * rng.randf_range(0.95, 1.05))
		# a squashed, faceted blob: an icosphere-ish ellipsoid with jittered radii per ring
		var seg := 7
		var rings := 4
		var verts: Array = []
		for i in rings + 1:
			var th := PI * i / rings
			var row: Array = []
			for j in seg:
				var ph := TAU * j / seg + float(it[2])
				var jit := 0.78 + 0.4 * fposmod(sin(float(i * 17 + j * 31) + float(it[2]) * 5.0) * 43758.5, 1.0)
				row.append(pos + Vector3(sin(th) * cos(ph) * 1.25, cos(th) * 0.8 + 0.25, sin(th) * sin(ph)) * r * jit - Vector3(0, r * 0.2, 0))
			verts.append(row)
		for i in rings:
			for j in seg:
				var a: Vector3 = verts[i][j]
				var b: Vector3 = verts[i][(j + 1) % seg]
				var c2: Vector3 = verts[i + 1][(j + 1) % seg]
				var d: Vector3 = verts[i + 1][j]
				for tri in [[a, b, c2], [a, c2, d]]:
					var gn: Vector3 = ((tri[1] as Vector3) - (tri[0] as Vector3)).cross((tri[2] as Vector3) - (tri[0] as Vector3))
					var n: Vector3 = gn.normalized()
					if n.dot((tri[0] as Vector3) - (pos + Vector3(0, r * 0.3, 0))) < 0.0:
						n = -n
					# wound so that the outside is the front (Godot's front faces are the clockwise ones): a face wound the
					# other way is seen as a back face, whose normal the shader turns round, and is lit from inside
					var order: Array = [0, 1, 2] if gn.dot(n) < 0.0 else [0, 2, 1]
					for vi in order:
						st.set_normal(n)  # flat shading: faceted stone
						st.set_color(tint)
						st.add_vertex(tri[vi])
	_rock_mat = StandardMaterial3D.new()
	_rock_mat.albedo_color = Color("#8a8478")
	_rock_mat.vertex_color_use_as_albedo = true
	_rock_mat.roughness = 0.95
	_rock_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	for ck in chunks:
		var mesh := (chunks[ck] as SurfaceTool).commit()
		for rep in 3:
			var mi := MeshInstance3D.new()
			mi.mesh = mesh
			mi.material_override = _rock_mat
			mi.position.z = -float(rep) * TREE_PERIOD
			mi.visibility_range_end = 300.0
			holder.add_child(mi)


## Night: street lamps come on and light the road, reflectors and road studs
## shine brighter. k = 0 (day) .. 1 (night).
func set_night(k: float) -> void:
	(M.lamp as StandardMaterial3D).emission_energy_multiplier = lerpf(0.15, 7.0, k)
	(M.lamp as StandardMaterial3D).albedo_color = Color("#9a9a92").lerp(Color("#f4ecc8"), k)
	(M.amber as StandardMaterial3D).emission_energy_multiplier = lerpf(1.2, 4.0, k)
	(M.amber_cut as ShaderMaterial).set_shader_parameter("glow", lerpf(1.2, 4.0, k))
	for gs in _station_nodes:
		gs.set_night(k)  # (the fuel stops' LED prices and lit signs)
	if _pool_mat:
		_pool_mat.albedo_color = Color(1, 1, 1, k)
		_pools.visible = k > 0.02
	for m in _road_mats:
		(m as ShaderMaterial).set_shader_parameter("stud_glow", lerpf(0.5, 3.0, k))


## The time of day on the horizon: mountains and clouds take its colours.
func set_sky_tint(tint: Color, haze: Color) -> void:
	for m in _far_mats:
		m.set_shader_parameter("tint", tint)
		m.set_shader_parameter("haze_col", haze)


## The sea beside a coast road, on the left of the highway beyond the beach (the ground's shader draws the sand down to the shore).
func _build_sea() -> void:
	_sea = MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(2600.0, 2600.0)
	_sea.mesh = pm
	_sea_mat = ShaderMaterial.new()
	_sea_mat.shader = load("res://shaders/sea.gdshader")
	_sea.material_override = _sea_mat
	_sea.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_sea.position = Vector3(-130.0 - 1300.0, 0.02, -640.0)
	_sea.visible = false
	add_child(_sea)


## The ranges on the horizon for each kind of country: two layers drawn at 900 m and 600 m but scaled to look like ranges
## 2 km and 1.3 km away. [distance, height range, base height, foot colour, top colour, haze, seed, mesas, jaggedness, size].
const FAR := {
	"temperate": [[900.0, 112.0, 32.0, Color("#5e6f86"), Color("#a2adb9"), 0.58, 11, false, 0.0, 1.0], [600.0, 53.0, 12.0, Color("#4b5f38"), Color("#76844f"), 0.42, 23, false, 0.0, 1.0]],
	"autumn": [[900.0, 112.0, 32.0, Color("#666a86"), Color("#aab0c2"), 0.56, 12, false, 0.1, 1.0], [600.0, 53.0, 12.0, Color("#6a5a36"), Color("#a38a52"), 0.42, 24, false, 0.1, 1.0]],
	"conifer": [[900.0, 130.0, 34.0, Color("#40586a"), Color("#8aa0ab"), 0.55, 13, false, 0.4, 1.0], [600.0, 62.0, 12.0, Color("#2a4733"), Color("#56765a"), 0.4, 25, false, 0.55, 1.0]],
	"desert": [[900.0, 120.0, 30.0, Color("#9c6a58"), Color("#d4a587"), 0.5, 14, true, 0.0, 1.0], [600.0, 50.0, 10.0, Color("#b3804f"), Color("#dbb083"), 0.42, 26, true, 0.0, 1.0]],
	"coast": [[900.0, 112.0, 30.0, Color("#86a3b8"), Color("#c0d2de"), 0.6, 15, false, 0.0, 0.4], [600.0, 53.0, 12.0, Color("#5f8250"), Color("#93ab6a"), 0.42, 27, false, 0.0, 0.5]],
	"snow": [[900.0, 135.0, 36.0, Color("#7d8fa6"), Color("#f1f5f9"), 0.5, 16, false, 0.6, 1.0], [600.0, 62.0, 14.0, Color("#98a6b4"), Color("#e4ebf2"), 0.42, 28, false, 0.45, 1.0]],
}
var _far_layers: Array = []   # [MeshInstance3D, ...]
var _far_kind := ""


## The silhouette of one range, all the way round the front (a ribbon of triangles standing at L[0] metres).
func _far_mesh(L: Array) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = L[6]
	var steps := 90
	var phase := rng.randf() * 10.0
	var prev_top := Vector3.ZERO
	var prev_bot := Vector3.ZERO
	for i in steps + 1:
		var a := deg_to_rad(lerpf(-120.0, 120.0, float(i) / steps))
		var f := 0.5 + 0.3 * sin(a * 7.0 + phase) + 0.2 * sin(a * 17.0 + phase * 2.0)
		if bool(L[7]):  # mesas: flat tops and steep sides
			f = clampf(f * 2.3 - 0.6, 0.0, 1.0) * 0.85 + 0.12 * sin(a * 31.0 + phase)
		f += float(L[8]) * (0.3 * sin(a * 61.0 + phase * 3.0) + 0.18 * sin(a * 113.0 + phase))  # jagged peaks
		var hgt: float = L[2] * float(L[9]) + L[1] * float(L[9]) * maxf(f, 0.05) * rng.randf_range(0.9, 1.08)
		var dir := Vector3(sin(a), 0, -cos(a))
		var top: Vector3 = dir * L[0] + Vector3(0, hgt, 0)
		var bot: Vector3 = dir * L[0] + Vector3(0, -20, 0)
		if i > 0:
			st.add_vertex(prev_bot)
			st.add_vertex(prev_top)
			st.add_vertex(top)
			st.add_vertex(prev_bot)
			st.add_vertex(top)
			st.add_vertex(bot)
		prev_top = top
		prev_bot = bot
	return st.commit()


## The ranges of a kind of country (set_biome).
func _set_far(kind: String) -> void:
	if kind == _far_kind:
		return
	_far_kind = kind
	var layers: Array = FAR.get(kind, FAR.temperate)
	for i in layers.size():
		var L: Array = layers[i]
		(_far_layers[i] as MeshInstance3D).mesh = _far_mesh(L)
		var m := _far_mats[i]
		m.set_shader_parameter("base_col", L[3])
		m.set_shader_parameter("top_col", L[4])
		m.set_shader_parameter("haze", L[5])
		m.set_shader_parameter("max_h", float(L[1]) * float(L[9]) + float(L[2]) * float(L[9]))


## Mountains and clouds on the horizon. They stay at a fixed distance.
func _build_far() -> void:
	var far := Node3D.new()
	add_child(far)
	var shader: Shader = load("res://shaders/far.gdshader")
	for i in 2:
		var mi := MeshInstance3D.new()
		var m := ShaderMaterial.new()
		m.shader = shader
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		far.add_child(mi)
		_far_layers.append(mi)
		_far_mats.append(m)
	_set_far("temperate")

	# clouds: soft radial puffs, a few quads each
	_clouds = Node3D.new()
	far.add_child(_clouds)
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.4, Color(1, 1, 1, 0.75))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	var cm := ShaderMaterial.new()
	cm.shader = shader
	cm.set_shader_parameter("cloud", true)
	cm.set_shader_parameter("puff", tex)
	_far_mats.append(cm)
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	var rng2 := RandomNumberGenerator.new()
	rng2.seed = 99
	for i in 20:
		var a := deg_to_rad(rng2.randf_range(-75.0, 75.0))
		var r := rng2.randf_range(430.0, 820.0)
		var base := Vector3(sin(a) * r, rng2.randf_range(105.0, 200.0), -cos(a) * r)
		var w := rng2.randf_range(105.0, 200.0)
		for k in 4:
			var puff := MeshInstance3D.new()
			puff.mesh = q
			puff.material_override = cm
			puff.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			puff.position = base + Vector3(rng2.randf_range(-0.35, 0.35) * w, rng2.randf_range(-0.05, 0.12) * w, 0).rotated(Vector3.UP, -a)
			puff.scale = Vector3(w * rng2.randf_range(0.45, 0.8), w * rng2.randf_range(0.22, 0.36), 1)
			puff.rotation.y = -a
			_clouds.add_child(puff)


const KM_EM := 0.46      # letter size of the kilometre marker
const KM_W := 1.9        # its panel


func _build_km_sign() -> void:
	_km_sign = Node3D.new()
	add_child(_km_sign)
	var x := Data.RAIL + 1.6
	var parts := {CarModel.mat(Color("#8a9096")): [[Vector3(x, 1.2, 0), Vector3(0.12, 2.4, 0.12)]], M.white: [], M.sign: []}
	_add_boxes(parts, SignKit.panel(M.sign, M.white, Vector3(x, 2.85, 0.06), KM_W, 1.1, 0.09, 0.05, 0.07))
	_km_sign.add_child(_merged(parts))
	_km_label = SignKit.line("km 1", KM_EM, SignKit.WHITE, Vector3(x, 2.85, 0.06 + SignKit.LETTERS))
	_km_sign.add_child(_km_label)


func _build_gantry() -> void:
	_gantry = Node3D.new()
	add_child(_gantry)
	var parts := {M.steel_dark: [], M.white: [], M.sign: []}
	for s in [-1.0, 1.0]:
		parts[M.steel_dark].append([Vector3(s * (Data.RAIL + 0.7), 3.6, 0), Vector3(0.4, 7.2, 0.4)])
	parts[M.steel_dark].append([Vector3(0, 6.95, 0), Vector3(Data.RAIL * 2 + 1.8, 0.5, 0.4)])
	_add_boxes(parts, SignKit.panel(M.sign, M.white, Vector3(0, 5.5, 0.175), 8.6, 2.3, 0.2, 0.1, 0.15))
	for i in 10:
		for r in 2:
			var x := -Data.ROAD_HALF + i * 1.44 + (0.36 if r == 0 else 1.08)
			parts[M.white].append([Vector3(x, 0.01, -0.36 - r * 0.72), Vector3(0.72, 0.02, 0.72)])
	_gantry.add_child(_merged(parts))
	_gantry.add_child(SignKit.line("FINISH", 1.2, SignKit.WHITE, Vector3(0, 5.5, 0.175 + SignKit.LETTERS)))
	_gantry.visible = false


# ---------------------------------------------------------------- slots

func _add_slot(period: float, offset: float, count: int, setup: Callable) -> void:
	var pool: Array[Node3D] = []
	for i in count:
		var n := Node3D.new()
		n.set_meta("k", -999999)
		add_child(n)
		pool.append(n)
	_slots.append({"period": period, "offset": offset, "pool": pool, "setup": setup})


func _clear(n: Node3D) -> void:
	for c in n.get_children():
		c.queue_free()


## Add boxes made by SignKit.panel (material, centre, size) to a parts dictionary for _merged.
static func _add_boxes(parts: Dictionary, boxes: Array) -> void:
	for b in boxes:
		if not parts.has(b[0]):
			parts[b[0]] = []
		parts[b[0]].append([b[1], b[2]])


const GANTRY_EM := 0.7       # letter size on the exit gantry (one size on all its panels, as on a real road)
const GANTRY_EDGE := 0.55    # from a panel's edge to its lettering
const GANTRY_GAP := 0.9      # between a name and its distance


func _setup_sign_gantry(n: Node3D, k: int) -> void:
	_clear(n)
	var exit_no := 10 + posmod(k * 7, 89)
	var a: String = PLACES[posmod(k * 3, PLACES.size())]       # the exit's town
	var b: String = PLACES[posmod(k * 5 + 2, PLACES.size())]   # the towns straight on, and how far
	var c: String = PLACES[posmod(k * 11 + 5, PLACES.size())]
	var db := "%d km" % (12 + posmod(k * 13, 60))
	var dc := "%d km" % (40 + posmod(k * 17, 90))
	var parts := {M.steel_dark: [], M.white: [], M.sign: []}
	for x in [Data.RAIL + 1.0, -Data.RAIL - 0.9]:
		parts[M.steel_dark].append([Vector3(x, 4.0, 0), Vector3(0.45, 8.0, 0.45)])
	parts[M.steel_dark].append([Vector3(0, 7.9, 0), Vector3(Data.RAIL * 2.0 + 2.4, 0.35, 0.5)])
	parts[M.steel_dark].append([Vector3(0, 7.5, 0), Vector3(Data.RAIL * 2.0 + 2.4, 0.12, 0.3)])
	# Lettering like a real sign's: names against the left margin, distances against the right in their own column,
	# every line the same height, and each panel as wide as its longest line needs (within what fits between the posts).
	var names := maxf(SignKit.width(b, 1.0), SignKit.width(c, 1.0))
	var dists := maxf(SignKit.width(db, 1.0), SignKit.width(dc, 1.0))
	var towns := maxf(SignKit.width(a, 1.0), SignKit.width("1 km", 1.0))
	var em := minf(GANTRY_EM, minf((8.4 - GANTRY_GAP - 2.0 * GANTRY_EDGE) / (names + dists), (6.6 - 2.0 * GANTRY_EDGE) / towns))
	var w_thru := maxf(5.0, em * (names + dists) + GANTRY_GAP + 2.0 * GANTRY_EDGE)
	var w_exit := maxf(4.4, em * towns + 2.0 * GANTRY_EDGE)
	var zf := 0.31                      # the front of the panels
	var zt := zf + SignKit.LETTERS      # and of the lettering
	var white := SignKit.WHITE
	var x_thru := -3.6                  # over the left lanes
	_add_boxes(parts, SignKit.panel(M.sign, M.white, Vector3(x_thru, 6.5, zf), w_thru, 2.4))
	var left := x_thru - w_thru / 2.0 + GANTRY_EDGE
	var right := x_thru + w_thru / 2.0 - GANTRY_EDGE
	n.add_child(SignKit.block([b, c], em, white, Vector3(left, 7.0, zt), 1.0, HORIZONTAL_ALIGNMENT_LEFT))
	n.add_child(SignKit.block([db, dc], em, white, Vector3(right, 7.0, zt), 1.0, HORIZONTAL_ALIGNMENT_RIGHT))
	var x_exit := 4.6                   # over the right lanes, the exit's side
	_add_boxes(parts, SignKit.panel(M.sign, M.white, Vector3(x_exit, 6.5, zf), w_exit, 2.4))
	left = x_exit - w_exit / 2.0 + GANTRY_EDGE
	n.add_child(SignKit.block([a, "1 km"], em, white, Vector3(left, 7.0, zt), 1.0, HORIZONTAL_ALIGNMENT_LEFT))
	# the exit number on a tab of its own under the right-hand corner
	var tab_em := 0.42
	var tab_w := SignKit.width("EXIT %d" % exit_no, tab_em) + 0.7
	var tab_x := x_exit + w_exit / 2.0 - 0.35 - tab_w / 2.0
	_add_boxes(parts, SignKit.panel(M.sign, M.white, Vector3(tab_x, 4.95, zf), tab_w, 0.7, 0.06, 0.04))
	n.add_child(SignKit.line("EXIT %d" % exit_no, tab_em, white, Vector3(tab_x, 4.95, zt)))
	n.add_child(_merged(parts))


func _setup_overpass(n: Node3D, _k: int) -> void:
	_clear(n)
	var left := OPP_X - Data.RAIL - 9.0
	var right := Data.RAIL + 9.0
	var cx := (left + right) / 2.0
	var span := right - left
	var parts := {M.concrete: [], M.concrete_dark: [], M.steel: []}
	parts[M.concrete].append([Vector3(cx, 7.0, 0), Vector3(span, 0.8, 12.0)])
	parts[M.concrete_dark].append([Vector3(cx, 6.45, 0), Vector3(span, 0.3, 10.0)])
	for z in [-5.6, 5.6]:
		parts[M.concrete].append([Vector3(cx, 7.85, z), Vector3(span, 0.9, 0.4)])
		parts[M.steel].append([Vector3(cx, 8.45, z), Vector3(span, 0.08, 0.08)])
	for x in [Data.RAIL + 2.6, MEDIAN_X, OPP_X - Data.RAIL - 2.6]:
		for z in [-3.2, 3.2]:
			parts[M.concrete].append([Vector3(x, 3.15, z), Vector3(1.1, 6.3, 1.1)])
		parts[M.concrete_dark].append([Vector3(x, 6.1, 0), Vector3(1.6, 0.4, 9.0)])
	# embankments at both ends
	for s in [-1.0, 1.0]:
		var ex: float = right + 7.0 if s > 0 else left - 7.0
		parts[M.concrete_dark].append([Vector3(ex, 2.3, 0), Vector3(16.0, 3.0, 14.0), Basis(Vector3.BACK, s * 0.42)])
		parts[M.concrete].append([Vector3(ex - s * 7.8, 3.8, 0), Vector3(1.4, 7.6, 13.0)])
	n.add_child(_merged(parts))
	# the name of the county in letters on the deck's edge (centred on it, over the right-hand carriageway)
	n.add_child(SignKit.line("REDLINE COUNTY", 0.56, Color("#5b5953"), Vector3(-2.0, 7.0, 6.02)))


func _setup_billboard(n: Node3D, k: int) -> void:
	_clear(n)
	var ad: Array = ADS[posmod(k, ADS.size())]
	var right := posmod(k, 3) != 1
	var x := Data.RAIL + 13.0 if right else OPP_X - Data.RAIL - 13.0
	var root := Node3D.new()
	root.position = Vector3(x, 0, 0)
	root.rotation.y = -0.3 if right else 0.3  # turned a little towards the road, to the drivers coming up to it
	n.add_child(root)
	var bg := CarModel.mat(Color(ad[2]), 0.0, 0.6)
	var parts := {M.steel_dark: [], M.white: [], bg: []}
	for dx in [-3.5, 3.5]:
		parts[M.steel_dark].append([Vector3(dx, 3.5, 0), Vector3(0.35, 7.0, 0.35)])
	parts[M.steel_dark].append([Vector3(0, 6.8, -0.2), Vector3(12.6, 0.15, 1.0)])  # catwalk
	parts[M.white].append([Vector3(0, 9.4, 0), Vector3(12.8, 5.0, 0.3)])
	parts[bg].append([Vector3(0, 9.4, 0.08), Vector3(12.2, 4.4, 0.3)])
	root.add_child(_merged(parts))
	# a headline with a line under it, both centred, the pair centred on the board (an ad sets its own letter size, to fill the board)
	var fg := Color(ad[3])
	var em_h := SignKit.fit_em([ad[0]], 2.0, 10.6)
	var em_t := SignKit.fit_em([ad[1]], 0.95, 10.6)
	var cap_h := SignKit.CAP * em_h
	var cap_t := SignKit.CAP * em_t
	var gap := 0.55 * cap_h
	var top := 9.4 + (cap_h + gap + cap_t) / 2.0
	root.add_child(SignKit.line(ad[0], em_h, fg, Vector3(0, top - cap_h / 2.0, 0.26)))
	root.add_child(SignKit.line(ad[1], em_t, fg, Vector3(0, top - cap_h - gap - cap_t / 2.0, 0.26)))


## The speed limit (SpeedTrap.LIMIT: the speed checks catch anyone over it), on a white board on two posts by the right-hand
## rail, in the units the speedometer shows. A sign shows the units of the moment it is put up.
func _setup_speed_sign(n: Node3D, _k: int) -> void:
	_clear(n)
	var mph: bool = Save.setting("units") == "mph"
	var figure := "75" if mph else "120"
	var root := Node3D.new()
	root.position = Vector3(Data.RAIL + 2.7, 0, 0)
	n.add_child(root)
	var ink := CarModel.mat(Color("#15171a"), 0.0, 0.6)
	var parts := {CarModel.mat(Color("#8a9096")): [[Vector3(-0.55, 1.6, 0), Vector3(0.1, 3.2, 0.1)], [Vector3(0.55, 1.6, 0), Vector3(0.1, 3.2, 0.1)]],
		M.white: [], ink: []}
	_add_boxes(parts, SignKit.panel(M.white, ink, Vector3(0, 3.05, 0.06), 1.55, 2.0, 0.09, 0.045, 0.07))
	root.add_child(_merged(parts, false))
	var col := Color("#15171a")
	root.add_child(SignKit.line("SPEED", 0.27, col, Vector3(0, 3.7, 0.1 + SignKit.LETTERS)))
	root.add_child(SignKit.line("LIMIT", 0.27, col, Vector3(0, 3.38, 0.1 + SignKit.LETTERS)))
	root.add_child(SignKit.line(figure, SignKit.fit_em([figure], 0.9, 1.2), col, Vector3(0, 2.68, 0.1 + SignKit.LETTERS)))


func _setup_farm(n: Node3D, k: int) -> void:
	_clear(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = k * 7919 + 13
	if rng.randf() < 0.3:
		return  # open fields here
	var right := rng.randf() < 0.55
	var x := (Data.RAIL + rng.randf_range(40.0, 140.0)) if right else (OPP_X - Data.RAIL - rng.randf_range(40.0, 140.0))
	var root := Node3D.new()
	root.position = Vector3(x, 0, rng.randf_range(-60.0, 60.0))
	root.rotation.y = rng.randf_range(-0.6, 0.6)
	n.add_child(root)
	var kind := rng.randi() % 3
	var wall := CarModel.mat(Color("#8e2f25") if kind == 0 else Color("#e6e1d3"), 0.0, 0.9)
	var roof := CarModel.mat(Color("#4a4d52") if kind != 0 else Color("#6a6a66"), 0.0, 0.7, 0.2)
	var w := 10.0 if kind == 0 else 8.0
	var d := 16.0 if kind == 0 else 10.0
	var h := 6.0 if kind == 0 else 3.4
	var parts := {wall: [[Vector3(0, h / 2.0, 0), Vector3(w, h, d)]], roof: [], M.white: []}
	var pitch := 0.62 if kind == 0 else 0.5
	var half := w / 2.0 / cos(pitch) + 0.3
	for s in [-1.0, 1.0]:
		parts[roof].append([Vector3(s * w / 4.0, h + w / 4.0 * tan(pitch), 0), Vector3(half, 0.15, d + 0.6), Basis(Vector3.BACK, -s * pitch)])
	# gable ends filled with a narrowing stack
	for i in 4:
		var f := (i + 0.5) / 4.0
		parts[wall].append([Vector3(0, h + f * w / 2.0 * tan(pitch) * 0.95, 0), Vector3(w * (1.0 - f) * 0.98, w / 2.0 * tan(pitch) / 4.0, d - 0.1)])
	if kind == 0:
		parts[M.white].append([Vector3(0, 2.2, d / 2.0 + 0.02), Vector3(4.0, 4.4, 0.05)])
		parts[wall].append([Vector3(0, 2.2, d / 2.0 + 0.05), Vector3(3.6, 4.0, 0.05)])
	else:
		parts[M.white].append([Vector3(-2.0, 1.1, d / 2.0 + 0.02), Vector3(1.0, 2.1, 0.05)])
	root.add_child(_merged(parts))
	if kind != 2 and rng.randf() < 0.7:  # grain silo
		var silo := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 2.4
		cm.bottom_radius = 2.4
		cm.height = 12.0
		silo.mesh = cm
		silo.material_override = CarModel.mat(Color("#b8bcbf"), 0.0, 0.4, 0.7)
		silo.position = Vector3(w / 2.0 + 4.0, 6.0, -d / 4.0)
		root.add_child(silo)
		var dome := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 2.4
		sm.height = 2.4
		sm.is_hemisphere = true
		dome.mesh = sm
		dome.material_override = silo.material_override
		dome.position = silo.position + Vector3(0, 6.0, 0)
		root.add_child(dome)


func _update_slots(base_z: float) -> void:
	for sl in _slots:
		var period: float = sl.period
		var offset: float = sl.offset
		var pool: Array = sl.pool
		var k0 := int(floor((base_z - VIEW_BEHIND - offset) / period))
		for i in pool.size():
			var k := k0 + i
			var n: Node3D = pool[posmod(k, pool.size())]
			if n.get_meta("k") != k:
				n.set_meta("k", k)
				(sl.setup as Callable).call(n, k)
			var zrel := k * period + offset - base_z
			n.position.z = -zrel
			# nothing else stands where a fuel stop is (overpasses, gantries, billboards, farms)
			n.visible = zrel < VIEW_AHEAD and zrel > -VIEW_BEHIND - 20.0 and not _near_station(k * period + offset)


# ---------------------------------------------------------------- oncoming traffic

var _replay_snap: Array = []  # oncoming cars' positions when the replay opened
var _in_replay := false


## While the replay plays, oncoming cars only move with replay time (which can
## run backwards); none are added or removed. end_replay puts them back.
## High graphics: fine asphalt grain catches the light.
func set_detail(on: bool) -> void:
	for m in _road_mats:
		m.set_shader_parameter("detail", 1.0 if on else 0.0)


func begin_replay() -> void:
	_in_replay = true
	_replay_snap = []
	for c in _oncoming:
		_replay_snap.append(c.z)


func end_replay() -> void:
	for i in mini(_replay_snap.size(), _oncoming.size()):
		_oncoming[i].z = _replay_snap[i]
	_replay_snap = []
	_in_replay = false


func _update_oncoming(base_z: float, dt: float) -> void:
	if _in_replay:
		for c in _oncoming:
			c.z -= c.v * dt
			c.model.position = Vector3(c.x, 0, -(c.z - base_z))
			c.model.spin(c.v, absf(dt))
		return
	for i in range(_oncoming.size() - 1, -1, -1):
		var c: Dictionary = _oncoming[i]
		c.z -= c.v * dt
		if c.z < base_z - 90.0:
			c.model.queue_free()
			_oncoming.remove_at(i)
			continue
		c.model.position = Vector3(c.x, 0, -(c.z - base_z))
		c.model.spin(c.v, dt)
	if _oncoming.size() < 10 and randf() < dt * 2.0:
		var lane := randi() % 4
		var z := base_z + randf_range(400.0, 480.0)
		for o in _oncoming:
			if absf(o.x - OPP_LANES[lane]) < 1.0 and absf(o.z - z) < 40.0:
				return
		var r := randf()
		var shape := "sedan"
		if lane <= 1 and r < 0.2:
			shape = "truck"
		elif r < 0.3:
			shape = "van"
		elif r < 0.5:
			shape = "suv"
		elif r < 0.7:
			shape = "hatch"
		var m := CarModel.new()
		if shape == "truck":
			m.build(shape, Color(Data.TRUCK_BOX_COLORS.pick_random()), Color(Data.TRUCK_CAB_COLORS.pick_random()), CarModel.traffic_style(shape))
		else:
			m.build(shape, Color(Data.TRAFFIC_COLORS.pick_random()), Color("#b5322a"), CarModel.traffic_style(shape))
		m.rotation.y = PI  # heading towards us
		# Place it before it is ever drawn. A new node sits at the origin (the
		# player's position) until moved, so adding it unplaced showed the car
		# right behind the player for one frame.
		m.position = Vector3(OPP_LANES[lane], 0, -(z - base_z))
		add_child(m)
		var v := randf_range(22.0, 30.0) if shape == "truck" else randf_range(26.0, 35.0)
		_oncoming.append({"model": m, "x": OPP_LANES[lane], "z": z, "v": v})


# ---------------------------------------------------------------- per frame

## base_z: the player's travelled distance. finish_z < 0 hides the gantry.
func update_view(base_z: float, finish_z: float, dt := 0.016) -> void:
	_t += dt
	var scroll := fmod(base_z, SCROLL_PERIOD)
	for m in _road_mats:
		m.set_shader_parameter("scroll", scroll)
	_grass_mat.set_shader_parameter("scroll", scroll)
	if _sea.visible:
		_sea_mat.set_shader_parameter("time_s", _t)
	for lp in _loops:
		lp[0].position.z = fmod(base_z, lp[1])
	_update_slots(base_z)
	_update_stations(base_z)
	_update_oncoming(base_z, dt)
	_clouds.position.x = fmod(_t * 1.5, 200.0) - 100.0
	var next_km := ceilf((base_z - 20.0) / 1000.0) * 1000.0
	if next_km < 1000.0:
		next_km = 1000.0
	_km_sign.position.z = -(next_km - base_z)
	var km_text := "km %d" % int(next_km / 1000.0)
	if _km_label.text != km_text:
		SignKit.set_text(_km_label, km_text, KM_EM, KM_W - 0.58)
	_km_sign.visible = next_km - base_z < VIEW_AHEAD
	if finish_z >= 0.0 and finish_z - base_z < VIEW_AHEAD and finish_z - base_z > -VIEW_BEHIND:
		_gantry.visible = true
		_gantry.position.z = -(finish_z - base_z)
	else:
		_gantry.visible = false
