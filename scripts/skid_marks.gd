class_name SkidMarks
extends MeshInstance3D
## Black tyre marks laid on the road while a car slides. Points are kept in
## road coordinates (x across, z along the road) and the mesh is only rebuilt
## when a point is added; scrolling just moves the node.

const WIDTH := 0.24
const MAX_POINTS := 900
const STEP := 0.3  # metres between points along a mark

var _im := ImmediateMesh.new()
var _strips: Array = []      # [{"pts": Array[Vector3] (x, z, strength)}]
var _open := {}              # wheel index -> strip being drawn
var _origin := 0.0           # road z the mesh vertices are measured from
var _dirty := false
var _count := 0


func _ready() -> void:
	mesh = _im
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.03, 0.03, 0.03, 1.0)
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.75
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	material_override = m
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Extend the mark under `wheel` to road position (x, z).
func add_point(wheel: int, x: float, z: float, strength: float) -> void:
	if _strips.is_empty():
		_origin = z
	var st: Dictionary = _open.get(wheel, {})
	if st.is_empty():
		st = {"pts": []}
		_strips.append(st)
		_open[wheel] = st
	var pts: Array = st.pts
	if not pts.is_empty():
		var last: Vector3 = pts[-1]
		if Vector2(last.x - x, last.y - z).length() < STEP:
			return
	pts.append(Vector3(x, z, clampf(strength, 0.0, 1.0)))
	_count += 1
	while _count > MAX_POINTS and not _strips.is_empty():
		_count -= (_strips[0].pts as Array).size()
		for k in _open.keys():
			if _open[k] == _strips[0]:
				_open.erase(k)
		_strips.remove_at(0)
	_dirty = true


## The tyre stopped sliding: the next point starts a new mark.
func lift(wheel: int) -> void:
	_open.erase(wheel)


func clear_all() -> void:
	_strips.clear()
	_open.clear()
	_count = 0
	_dirty = true


func update_view(base_z: float) -> void:
	position.z = base_z - _origin
	if not _dirty:
		return
	_dirty = false
	_im.clear_surfaces()
	var any := false
	for st in _strips:
		if (st.pts as Array).size() >= 2:
			any = true
	if not any:
		return
	_im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for st in _strips:
		var pts: Array = st.pts
		var n := pts.size()
		if n < 2:
			continue
		for i in n - 1:
			var a: Vector3 = pts[i]
			var b: Vector3 = pts[i + 1]
			var d := Vector2(b.x - a.x, b.y - a.y).normalized()
			var side := Vector2(d.y, -d.x) * WIDTH * 0.5
			# fade in at the start and out at the end of each mark
			var ka := a.z * 0.6 * minf(1.0, i / 3.0) * minf(1.0, (n - 1 - i) / 3.0)
			var kb := b.z * 0.6 * minf(1.0, (i + 1) / 3.0) * minf(1.0, (n - 2 - i) / 3.0)
			var p0 := Vector3(a.x - side.x, 0.012, -(a.y - _origin) + side.y)
			var p1 := Vector3(a.x + side.x, 0.012, -(a.y - _origin) - side.y)
			var p2 := Vector3(b.x - side.x, 0.012, -(b.y - _origin) + side.y)
			var p3 := Vector3(b.x + side.x, 0.012, -(b.y - _origin) - side.y)
			var ca := Color(1, 1, 1, ka)
			var cb := Color(1, 1, 1, kb)
			for v in [[p0, ca], [p2, cb], [p1, ca], [p1, ca], [p2, cb], [p3, cb]]:
				_im.surface_set_color(v[1])
				_im.surface_set_normal(Vector3.UP)
				_im.surface_add_vertex(v[0])
	_im.surface_end()
