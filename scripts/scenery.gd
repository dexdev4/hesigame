class_name Scenery
extends Node3D
## The endless highway. Everything here stays near the player: the road is a
## fixed mesh whose shader scrolls, and repeating roadside objects sit in
## containers that are shifted by (distance mod period) every frame.

const VIEW_AHEAD := 700.0
const VIEW_BEHIND := 60.0
const TREE_PERIOD := 600.0

var _road_mat: ShaderMaterial
var _grass_mat: ShaderMaterial
var _posts: Node3D
var _lamps: Node3D
var _trees: Node3D
var _km_sign: Node3D
var _km_label: Label3D
var _gantry: Node3D


func _ready() -> void:
	var length := VIEW_AHEAD + VIEW_BEHIND
	var mid_z := -(VIEW_AHEAD - VIEW_BEHIND) / 2.0

	_road_mat = ShaderMaterial.new()
	_road_mat.shader = load("res://shaders/road.gdshader")
	var road := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(Data.RAIL * 2.0 + 1.0, length)
	pm.subdivide_depth = 40
	road.mesh = pm
	road.material_override = _road_mat
	road.position = Vector3(0, 0, mid_z)
	road.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(road)

	_grass_mat = ShaderMaterial.new()
	_grass_mat.shader = load("res://shaders/grass.gdshader")
	var grass := MeshInstance3D.new()
	var gm := PlaneMesh.new()
	gm.size = Vector2(900, length + 400)
	grass.mesh = gm
	grass.material_override = _grass_mat
	grass.position = Vector3(0, -0.03, mid_z - 200)
	grass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(grass)

	var steel := CarModel.mat(Color("#b9bfc5"), 0.0, 0.35, 0.6)
	var steel_dark := CarModel.mat(Color("#6c7278"), 0.0, 0.6, 0.4)
	for s in [-1.0, 1.0]:
		var rail := MeshInstance3D.new()
		rail.mesh = CarModel.box_mesh(Vector3(0.1, 0.34, length))
		rail.material_override = steel
		rail.position = Vector3(s * Data.RAIL, 0.64, mid_z)
		add_child(rail)

	# guardrail posts, every 4 m
	_posts = Node3D.new()
	add_child(_posts)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = CarModel.box_mesh(Vector3(0.12, 0.6, 0.12))
	var count := int(200.0 / 4.0) + 2
	mm.instance_count = count * 2
	for i in count:
		for side in 2:
			var x := (Data.RAIL + 0.08) * (1.0 if side == 1 else -1.0)
			mm.set_instance_transform(i * 2 + side, Transform3D(Basis(), Vector3(x, 0.3, -float(i - 2) * 4.0)))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = steel_dark
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_posts.add_child(mmi)

	# street lamps, alternating sides every 55 m (period 110 m)
	_lamps = Node3D.new()
	add_child(_lamps)
	var head_mat := CarModel.mat(Color("#f4ecc8"), 2.0)
	for i in range(-1, int(VIEW_AHEAD / 55.0) + 3):
		var side := 1.0 if i % 2 == 0 else -1.0
		var z := -float(i) * 55.0
		var x := side * (Data.RAIL + 0.9)
		_add_mesh(_lamps, CarModel.box_mesh(Vector3(0.2, 9.0, 0.2)), Vector3(x, 4.5, z), steel_dark)
		_add_mesh(_lamps, CarModel.box_mesh(Vector3(3.4, 0.14, 0.14)), Vector3(x - side * 1.6, 9.0, z), steel_dark)
		_add_mesh(_lamps, CarModel.box_mesh(Vector3(1.0, 0.16, 0.36)), Vector3(x - side * 3.1, 8.9, z), head_mat)

	_build_trees()
	_build_km_sign()
	_build_gantry()


func _add_mesh(parent: Node3D, mesh: Mesh, pos: Vector3, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.position = pos
	parent.add_child(mi)
	return mi


func _build_trees() -> void:
	_trees = Node3D.new()
	add_child(_trees)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	# One period of random trees, repeated three times so the visible window is always covered.
	var pattern: Array = []
	var z := 0.0
	while z < TREE_PERIOD:
		z += rng.randf_range(4.0, 11.0)
		var side := -1.0 if rng.randf() < 0.5 else 1.0
		pattern.append({"z": z, "x": side * (Data.RAIL + 4.0 + rng.randf() * 40.0), "k": rng.randf(), "s": rng.randf_range(0.8, 1.5)})

	var trunks := MultiMesh.new()
	var crowns := MultiMesh.new()
	var pines := MultiMesh.new()
	for m in [trunks, crowns, pines]:
		m.transform_format = MultiMesh.TRANSFORM_3D
		m.use_colors = true
	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius = 0.18
	trunk_mesh.bottom_radius = 0.26
	trunk_mesh.height = 1.0
	trunk_mesh.radial_segments = 6
	trunks.mesh = trunk_mesh
	var crown_mesh := SphereMesh.new()
	crown_mesh.radius = 1.0
	crown_mesh.height = 1.8
	crown_mesh.radial_segments = 8
	crown_mesh.rings = 5
	crowns.mesh = crown_mesh
	var pine_mesh := CylinderMesh.new()
	pine_mesh.top_radius = 0.0
	pine_mesh.bottom_radius = 1.0
	pine_mesh.height = 1.0
	pine_mesh.radial_segments = 7
	pines.mesh = pine_mesh

	var items: Array = []
	for rep in 3:
		for p in pattern:
			items.append({"z": -(p.z + rep * TREE_PERIOD) + VIEW_BEHIND, "x": p.x, "k": p.k, "s": p.s})
	var n_pine := 0
	var n_round := 0
	for it in items:
		if it.k > 0.5:
			n_pine += 1
		else:
			n_round += 1
	trunks.instance_count = items.size()
	crowns.instance_count = n_round
	pines.instance_count = n_pine
	var ir := 0
	var ip := 0
	for i in items.size():
		var it: Dictionary = items[i]
		var s: float = it.s
		var pos := Vector3(it.x, 0, it.z)
		var trunk_h := 1.6 * s if it.k > 0.5 else 2.6 * s
		trunks.set_instance_transform(i, Transform3D(Basis().scaled(Vector3(s, trunk_h, s)), pos + Vector3(0, trunk_h / 2.0, 0)))
		trunks.set_instance_color(i, Color("#4f3d2a"))
		if it.k > 0.5:
			var h: float = (6.0 + it.k * 6.0) * s
			var r: float = (1.6 + it.k) * s
			pines.set_instance_transform(ip, Transform3D(Basis().scaled(Vector3(r, h, r)), pos + Vector3(0, trunk_h + h / 2.0 - 0.3, 0)))
			pines.set_instance_color(ip, Color("#24402a") if it.k > 0.75 else Color("#2c4a2c"))
			ip += 1
		else:
			var r2: float = (2.0 + it.k * 3.0) * s
			crowns.set_instance_transform(ir, Transform3D(Basis().scaled(Vector3(r2, r2, r2)), pos + Vector3(0, trunk_h + r2 * 0.6, 0)))
			crowns.set_instance_color(ir, Color("#3e5a2e") if it.k > 0.25 else Color("#4c6a35"))
			ir += 1
	var leaf := StandardMaterial3D.new()
	leaf.vertex_color_use_as_albedo = true
	leaf.roughness = 1.0
	for m in [trunks, crowns, pines]:
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = m
		mmi.material_override = leaf
		_trees.add_child(mmi)


func _build_km_sign() -> void:
	_km_sign = Node3D.new()
	add_child(_km_sign)
	var x := Data.RAIL + 1.6
	_add_mesh(_km_sign, CarModel.box_mesh(Vector3(0.12, 2.4, 0.12)), Vector3(x, 1.2, 0), CarModel.mat(Color("#8a9096")))
	_add_mesh(_km_sign, CarModel.box_mesh(Vector3(1.4, 0.9, 0.08)), Vector3(x, 2.85, 0), CarModel.mat(Color("#0d6a42"), 0.0, 0.5))
	_km_label = Label3D.new()
	_km_label.font_size = 64
	_km_label.pixel_size = 0.006
	_km_label.modulate = Color("#f3f5ef")
	_km_label.position = Vector3(x, 2.85, 0.05)
	_km_label.outline_size = 0
	_km_sign.add_child(_km_label)


func _build_gantry() -> void:
	_gantry = Node3D.new()
	add_child(_gantry)
	var steel := CarModel.mat(Color("#8a9096"), 0.0, 0.5, 0.5)
	for s in [-1.0, 1.0]:
		_add_mesh(_gantry, CarModel.box_mesh(Vector3(0.4, 7.2, 0.4)), Vector3(s * (Data.RAIL + 0.7), 3.6, 0), steel)
	_add_mesh(_gantry, CarModel.box_mesh(Vector3(Data.RAIL * 2 + 1.8, 0.5, 0.4)), Vector3(0, 6.95, 0), steel)
	_add_mesh(_gantry, CarModel.box_mesh(Vector3(8.6, 2.3, 0.15)), Vector3(0, 5.5, 0.1), CarModel.mat(Color("#0d6a42"), 0.0, 0.5))
	_add_mesh(_gantry, CarModel.box_mesh(Vector3(8.2, 1.9, 0.02)), Vector3(0, 5.5, 0.19), CarModel.mat(Color("#f3f5ef")))
	_add_mesh(_gantry, CarModel.box_mesh(Vector3(7.9, 1.6, 0.02)), Vector3(0, 5.5, 0.21), CarModel.mat(Color("#0d6a42"), 0.0, 0.5))
	var lbl := Label3D.new()
	lbl.text = "FINISH"
	lbl.font_size = 220
	lbl.pixel_size = 0.0075
	lbl.modulate = Color("#f3f5ef")
	lbl.position = Vector3(0, 5.5, 0.24)
	_gantry.add_child(lbl)
	# chequered strip across the road
	var white := CarModel.mat(Color("#f3f5ef"), 0.0, 0.8)
	for i in 10:
		for r in 2:
			var x := -Data.ROAD_HALF + i * 1.44 + (0.36 if r == 0 else 1.08)
			_add_mesh(_gantry, CarModel.box_mesh(Vector3(0.72, 0.02, 0.72)), Vector3(x, 0.01, -0.36 - r * 0.72), white)
	_gantry.visible = false


## base_z: the player's travelled distance. finish_z < 0 hides the gantry.
func update_view(base_z: float, finish_z: float) -> void:
	_road_mat.set_shader_parameter("scroll", fmod(base_z, 360.0))
	_grass_mat.set_shader_parameter("scroll", fmod(base_z, 360.0))
	_posts.position.z = fmod(base_z, 4.0)
	_lamps.position.z = fmod(base_z, 110.0)
	_trees.position.z = fmod(base_z, TREE_PERIOD)
	var next_km := ceilf((base_z - 20.0) / 1000.0) * 1000.0
	if next_km < 1000.0:
		next_km = 1000.0
	_km_sign.position.z = -(next_km - base_z)
	_km_label.text = "km %d" % int(next_km / 1000.0)
	_km_sign.visible = next_km - base_z < VIEW_AHEAD
	if finish_z >= 0.0 and finish_z - base_z < VIEW_AHEAD and finish_z - base_z > -VIEW_BEHIND:
		_gantry.visible = true
		_gantry.position.z = -(finish_z - base_z)
	else:
		_gantry.visible = false
