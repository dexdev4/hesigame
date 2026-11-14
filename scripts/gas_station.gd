class_name GasStation
extends Node3D
## A fuel stop on the right of the highway. An exit lane peels off the
## right-hand lane, runs past a forecourt with a canopy, two pump islands and
## a kiosk, then merges back. Blue service signs on the approach and a tall
## price pylon show this station's prices.
##
## Positions along the road are given as rel = (road distance) - (the
## station's distance, at the pumps); in the node's own space z = -rel.

const EXIT_START := 170.0   # the exit lane starts to peel off this far before the pumps
const EXIT_FULL := 120.0    # ...and is a full lane from here on
const FORE := 32.0          # the forecourt runs this far either side of the pumps
const MERGE_END := 130.0    # the slip road has merged back in by here
const LANE_X := 9.2         # centre of the exit lane
const OUTER_X := 11.6       # its outer edge, lined by a guardrail
const PUMP_X := 17.0        # where a car stops, between the two pump islands
const PUMPS := [-3.6, 3.6]  # the pumps along each island (rel), nearer one first
const SIGNS := [600.0, 300.0]  # approach signs, metres before the pumps
# The lettering (see SignKit): an em is the size of the letters, in metres; names and prices are each set against a margin
const KIOSK_EM := 0.46
const PYLON_NAME_EM := 0.56
const PYLON_EM := 0.38
const SIGN_W := 4.6
const SIGN_H := 3.5


## The car's right-hand limit at rel metres from the pumps: the taper into the
## exit lane, the outer rail, and the taper of the slip road back again.
static func right_edge(rel: float) -> float:
	if rel <= -EXIT_START or rel >= MERGE_END:
		return Data.RAIL
	if rel < -EXIT_FULL:
		return lerpf(Data.RAIL, OUTER_X, (rel + EXIT_START) / (EXIT_START - EXIT_FULL))
	if rel > FORE:
		return lerpf(OUTER_X, Data.RAIL, (rel - FORE) / (MERGE_END - FORE))
	return OUTER_X


var _flat := {}    # material -> SurfaceTool (ground, markings: no shadows)
var _solid := {}   # material -> SurfaceTool (structures)
var _brand: StandardMaterial3D
var _pylon_name: Label3D
var _pylon_prices: Label3D
var _approach: Array = []  # per sign: {"name": Label3D, "prices": Label3D (the three prices, one under the other)}
var _kiosk_sign: Label3D


func _init() -> void:
	var asphalt := CarModel.mat(Color("#6d7074"), 0.0, 0.9)  # matches the highway surface
	var concrete := CarModel.mat(Color("#bdb9ae"), 0.0, 0.9)
	var paint := CarModel.mat(Color("#e7e5dc"), 0.0, 0.7)
	var white := CarModel.mat(Color("#f2f1ec"), 0.0, 0.55)
	var steel := CarModel.mat(Color("#b9bfc5"), 0.0, 0.35, 0.6)
	var steel_dark := CarModel.mat(Color("#6c7278"), 0.0, 0.6, 0.4)
	var dark := CarModel.mat(Color("#1d1f22"), 0.0, 0.6)
	var wall := CarModel.mat(Color("#d8d2c4"), 0.0, 0.85)
	var lightm := CarModel.mat(Color("#f6f2e4"), 1.8)
	var blue := CarModel.mat(Color("#1f4e8c"), 0.0, 0.5)
	_brand = StandardMaterial3D.new()
	_brand.albedo_color = Color("#c62828")
	_brand.roughness = 0.45

	# --- exit lane, forecourt and markings
	var step := 5.0
	var r := -EXIT_START
	while r < MERGE_END - 0.01:
		var r2 := minf(r + step, MERGE_END)
		var o1 := right_edge(r) + 0.35
		var o2 := right_edge(r2) + 0.35
		_quad_flat(asphalt, Vector3(7.02, 0.006, -r), Vector3(o1, 0.006, -r), Vector3(o2, 0.006, -r2), Vector3(7.02, 0.006, -r2))
		# the outer edge line, broken where the forecourt opens off the lane
		if r2 <= -FORE or r >= FORE:
			var e1 := right_edge(r) - 0.3
			var e2 := right_edge(r2) - 0.3
			_quad_flat(paint, Vector3(e1 - 0.08, 0.011, -r), Vector3(e1 + 0.08, 0.011, -r), Vector3(e2 + 0.08, 0.011, -r2), Vector3(e2 - 0.08, 0.011, -r2))
		r = r2
	# broken white line where the lane leaves the highway (short dashes)
	var dz := -EXIT_START + 12.0
	while dz < MERGE_END - 12.0:
		_quad_flat(paint, Vector3(7.03, 0.011, -dz), Vector3(7.25, 0.011, -dz), Vector3(7.25, 0.011, -dz - 3.0), Vector3(7.03, 0.011, -dz - 3.0))
		dz += 7.0
	_box_flat(concrete, Vector3((OUTER_X - 0.3 + 21.8) / 2.0, 0.012, 0.0), Vector3(21.8 - OUTER_X + 0.3, 0.024, FORE * 2.0))
	for x in [14.6, 19.4]:  # pump islands
		_box_solid(concrete, Vector3(x, 0.09, 0.0), Vector3(1.2, 0.18, 13.0))
		_box_solid(paint, Vector3(x, 0.181, 0.0), Vector3(1.24, 0.004, 13.04))

	# --- guardrail round the outside of the exit lane and the slip road
	for seg in [[-EXIT_START + 1.0, -FORE], [FORE, MERGE_END - 1.0]]:
		var a: float = seg[0]
		while a < seg[1] - 0.01:
			var b := minf(a + 4.0, seg[1])
			var pa := Vector3(right_edge(a) + 0.04, 0.0, -a)
			var pb := Vector3(right_edge(b) + 0.04, 0.0, -b)
			for y in [0.71, 0.55]:
				CarModel._strap(_st(_solid, steel), pa + Vector3(0, y - 0.065, 0), pb + Vector3(0, y - 0.065, 0), 0.13, 0.1)
			_box_solid(steel_dark, pa + Vector3(0.08, 0.3, 0), Vector3(0.12, 0.6, 0.12))
			a = b

	# --- canopy over the pumps, on four pillars, lit from underneath
	_box_solid(white, Vector3(16.8, 5.25, 0.0), Vector3(9.0, 0.5, 22.0))
	_box_flat(CarModel.mat(Color("#e9e6dc"), 0.55), Vector3(16.8, 4.995, 0.0), Vector3(8.8, 0.01, 21.8))  # lit ceiling under the canopy
	for side in [-1.0, 1.0]:
		_box_solid(_brand, Vector3(16.8, 5.25, side * 11.03), Vector3(9.06, 0.56, 0.06))
		_box_solid(_brand, Vector3(16.8 + side * 4.53, 5.25, 0.0), Vector3(0.06, 0.56, 22.06))
	for x in [14.6, 19.4]:
		for z in [-7.0, 7.0]:
			_box_solid(white, Vector3(x, 2.6, z), Vector3(0.45, 5.0, 0.45))
		for k in 3:
			_box_solid(lightm, Vector3(x, 4.99, -6.0 + k * 6.0), Vector3(2.4, 0.02, 1.2))

	# --- pumps: two to an island, with a lit screen and a nozzle each side
	for x in [14.6, 19.4]:
		for z in PUMPS:
			_box_solid(white, Vector3(x, 1.06, z), Vector3(0.62, 1.76, 0.95))
			_box_solid(_brand, Vector3(x, 1.86, z), Vector3(0.64, 0.24, 0.97))
			for side in [-1.0, 1.0]:
				_box_solid(dark, Vector3(x + side * 0.32, 1.25, z), Vector3(0.02, 0.36, 0.5))
				_box_solid(lightm, Vector3(x + side * 0.335, 1.32, z), Vector3(0.01, 0.12, 0.34))
				_box_solid(dark, Vector3(x + side * 0.34, 0.9, z + 0.32), Vector3(0.06, 0.22, 0.08))
				CarModel._strap(_st(_solid, dark), Vector3(x + side * 0.34, 0.95, z + 0.36), Vector3(x + side * 0.36, 0.3, z + 0.5), 0.03, 0.03)

	# --- kiosk past the pumps, with a glass front facing the forecourt
	var kz := -24.0
	_box_solid(wall, Vector3(18.6, 1.75, kz), Vector3(6.0, 3.5, 10.0))
	_box_solid(dark, Vector3(18.6, 3.6, kz), Vector3(6.6, 0.25, 10.6))
	_box_solid(CarModel._glass_solid(), Vector3(15.58, 1.45, kz), Vector3(0.06, 2.2, 7.5))
	_box_solid(dark, Vector3(15.55, 1.15, kz + 2.0), Vector3(0.08, 2.3, 1.2))
	_box_solid(_brand, Vector3(15.52, 3.05, kz), Vector3(0.1, 0.6, 8.0))
	_kiosk_sign = SignKit.line("SUNSET FUEL", KIOSK_EM, Color.WHITE, Vector3(15.45, 3.05, kz), HORIZONTAL_ALIGNMENT_CENTER, Basis(Vector3.UP, -PI / 2.0))
	add_child(_kiosk_sign)

	# --- price pylon before the forecourt, facing the traffic: the brand's name over a board of prices (the grade against
	# the left margin, its price against the right, so the figures line up), the post behind the boards
	var pz := 46.0
	var pw := 3.1
	var amber := Color("#ffb52e")
	_box_solid(steel_dark, Vector3(12.8, 3.0, pz - 0.3), Vector3(0.45, 6.0, 0.45))
	_box_solid(_brand, Vector3(12.8, 6.9, pz), Vector3(pw, 1.0, 0.35))
	_box_solid(dark, Vector3(12.8, 5.25, pz), Vector3(pw, 2.3, 0.3))
	_pylon_name = SignKit.line("FUEL", PYLON_NAME_EM, Color.WHITE, Vector3(12.8, 6.9, pz + 0.2))
	add_child(_pylon_name)
	add_child(SignKit.block(_grades(), PYLON_EM, amber, Vector3(12.8 - pw / 2.0 + 0.3, 5.87, pz + 0.17), 0.62, HORIZONTAL_ALIGNMENT_LEFT))
	_pylon_prices = SignKit.block(["0.00", "0.00", "0.00"], PYLON_EM, amber, Vector3(12.8 + pw / 2.0 - 0.3, 5.87, pz + 0.17), 0.62, HORIZONTAL_ALIGNMENT_RIGHT)
	add_child(_pylon_prices)

	# --- blue service signs on the approach: "FUEL" against the left margin and the distance against the right, a line,
	# the station's name centred, then the three prices in two columns (grade left, price right)
	for dist in SIGNS:
		var sz: float = dist
		var sx := Data.RAIL + 2.4
		var cy := 3.4
		var zf := sz + 0.06          # the front of the panel
		var zt := zf + SignKit.LETTERS
		var edge := 0.45             # from the panel's edge to its lettering
		var left := sx - SIGN_W / 2.0 + edge
		var right := sx + SIGN_W / 2.0 - edge
		for px in [-1.7, 1.7]:
			_box_solid(steel_dark, Vector3(sx + px, 1.85, sz - 0.1), Vector3(0.12, 3.7, 0.12))
		for b in SignKit.panel(blue, white, Vector3(sx, cy, zf), SIGN_W, SIGN_H, 0.12, 0.06, 0.12):
			_box_solid(b[0], b[1], b[2])
		_box_solid(white, Vector3(sx, cy + 0.78, zf + 0.008), Vector3(right - left, 0.04, 0.016))
		add_child(SignKit.line("FUEL", 0.58, Color.WHITE, Vector3(left, cy + 1.15, zt), HORIZONTAL_ALIGNMENT_LEFT))
		add_child(SignKit.line("%d m" % int(dist), 0.58, Color.WHITE, Vector3(right, cy + 1.15, zt), HORIZONTAL_ALIGNMENT_RIGHT))
		var nm := SignKit.line("", 0.48, Color("#ffd54f"), Vector3(sx, cy + 0.4, zt))
		add_child(nm)
		add_child(SignKit.block(_grades(), 0.42, Color.WHITE, Vector3(left, cy - 0.15, zt), 0.5, HORIZONTAL_ALIGNMENT_LEFT))
		var prices := SignKit.block(["0.00", "0.00", "0.00"], 0.42, Color.WHITE, Vector3(right, cy - 0.15, zt), 0.5, HORIZONTAL_ALIGNMENT_RIGHT)
		add_child(prices)
		_approach.append({"name": nm, "prices": prices})

	_commit(_flat, false)
	_commit(_solid, true)


## The grades' names, one for each row of a price board (REG, MID, PREM).
static func _grades() -> Array:
	var out: Array = []
	for g in Data.FUEL_ORDER:
		out.append(String(Data.FUEL_GRADES[g].short))
	return out


## Station name, prices and brand colour (info from game.gd).
func set_info(info: Dictionary) -> void:
	_brand.albedo_color = Color(info.color)
	var nm: String = String(info.name).to_upper()
	SignKit.set_text(_kiosk_sign, nm, KIOSK_EM, 7.0)
	SignKit.set_text(_pylon_name, nm, PYLON_NAME_EM, 2.8)
	var p: Dictionary = info.prices
	var prices := PackedStringArray()
	for g in Data.FUEL_ORDER:
		prices.append("%.2f" % p[g])
	_pylon_prices.text = "\n".join(prices)
	for s in _approach:
		(s.prices as Label3D).text = "\n".join(prices)
		SignKit.set_text(s.name, nm, 0.48, SIGN_W - 0.9)


# ---------------------------------------------------------------- building helpers

func _st(group: Dictionary, m: Material) -> SurfaceTool:
	if not group.has(m):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		group[m] = st
	return group[m]


func _quad_flat(m: Material, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	CarModel._quad(_st(_flat, m), a, b, c, d, Vector3.UP)


func _box_flat(m: Material, c: Vector3, size: Vector3) -> void:
	CarModel._box(_st(_flat, m), c, size)


func _box_solid(m: Material, c: Vector3, size: Vector3, basis := Basis()) -> void:
	CarModel._box(_st(_solid, m), c, size, basis)


func _commit(group: Dictionary, shadows: bool) -> void:
	var mesh := ArrayMesh.new()
	var mats: Array = []
	for m in group:
		(group[m] as SurfaceTool).commit(mesh)
		mats.append(m)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	for i in mats.size():
		mi.set_surface_override_material(i, mats[i])
	if not shadows:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
