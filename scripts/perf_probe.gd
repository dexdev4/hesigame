class_name PerfProbe
extends RefCounted
## Where the frame goes (`--perf`, a test aid): the sections of Game._process timed in
## microseconds and averaged, plus what the renderer was asked to draw (instances,
## triangles, draw calls, for the main view, its shadow pass and the rear-view mirror)
## and how many triangles the scene holds, by kind. Meant for comparing builds:
##   godot --headless --path . --fixed-fps 60 --quit-after 3000 -- --autotest --fast --perf
## measures the script side without a window (the renderer's numbers are zero there); under
## a window (xvfb, `--rendering-method mobile --rendering-driver vulkan`) the draw numbers are
## the real renderer's.

var every := 600           # frames between reports
var frames := 0
var _acc := {}
var _last := 0
var _tri_cache := {}


func begin() -> void:
	_last = Time.get_ticks_usec()


## Charge the time since the last mark (or begin) to `section`.
func mark(section: String) -> void:
	var n := Time.get_ticks_usec()
	_acc[section] = int(_acc.get(section, 0)) + (n - _last)
	_last = Time.get_ticks_usec()


## True when a report is due.
func end_frame() -> bool:
	frames += 1
	return frames % every == 0


func _mesh_tris(m: Mesh) -> int:
	var id := m.get_instance_id()
	if _tri_cache.has(id):
		return _tri_cache[id]
	var n := 0
	if m is ArrayMesh:
		for si in m.get_surface_count():
			var il: int = (m as ArrayMesh).surface_get_array_index_len(si)
			n += (il if il > 0 else (m as ArrayMesh).surface_get_array_len(si)) / 3
	elif m is PrimitiveMesh:
		var arr := m.surface_get_arrays(0)
		var idx: Variant = arr[Mesh.ARRAY_INDEX]
		n = (idx.size() if idx != null else arr[Mesh.ARRAY_VERTEX].size()) / 3
	_tri_cache[id] = n
	return n


## Instances and triangles (and the shadow casters among them) below a node.
func _walk(n: Node, out: Dictionary) -> void:
	if n is Node3D and not (n as Node3D).visible:
		return
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		if mi.mesh:
			var t := _mesh_tris(mi.mesh)
			out.inst += 1
			out.tris += t
			if mi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
				out.sh_inst += 1
				out.sh_tris += t
	elif n is MultiMeshInstance3D:
		var mm := (n as MultiMeshInstance3D).multimesh
		if mm and mm.mesh:
			var count := mm.visible_instance_count if mm.visible_instance_count >= 0 else mm.instance_count
			var t := _mesh_tris(mm.mesh) * count
			out.inst += 1
			out.tris += t
			if (n as MultiMeshInstance3D).cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
				out.sh_inst += 1
				out.sh_tris += t
	for c in n.get_children():
		_walk(c, out)


func _scene_line(label: String, roots: Array) -> void:
	var g := {"inst": 0, "tris": 0, "sh_inst": 0, "sh_tris": 0}
	for r: Node in roots:
		_walk(r, g)
	print("[perf] scene %-12s %4d instances, %8d triangles | shadow casters %4d, %8d triangles (visibility ranges and the view are not applied)" % [label, g.inst, g.tris, g.sh_inst, g.sh_tris])


func report(game: Node, player_model: Node, traffic_models: Array, scenery: Node, mirror_viewport: SubViewport) -> void:
	var tot := 0
	for k in _acc:
		tot += int(_acc[k])
	var keys := _acc.keys()
	keys.sort_custom(func(a: String, b: String) -> bool: return _acc[a] > _acc[b])
	var parts := []
	for k in keys:
		parts.append("%s %.3f" % [k, float(_acc[k]) / float(frames) / 1000.0])
	print("[perf] %d frames, %.3f ms of script per frame: %s" % [frames, float(tot) / float(frames) / 1000.0, ", ".join(parts)])
	_scene_line("player", [player_model])
	_scene_line("traffic(%d)" % traffic_models.size(), traffic_models)
	_scene_line("scenery", [scenery])
	var rs := RenderingServer
	var vp := game.get_viewport().get_viewport_rid()
	print("[perf] drawn, main view: %d objects, %d triangles, %d draw calls | its shadow pass: %d objects, %d triangles, %d draw calls" % [
		rs.viewport_get_render_info(vp, rs.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, rs.VIEWPORT_RENDER_INFO_OBJECTS_IN_FRAME),
		rs.viewport_get_render_info(vp, rs.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, rs.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME),
		rs.viewport_get_render_info(vp, rs.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, rs.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME),
		rs.viewport_get_render_info(vp, rs.VIEWPORT_RENDER_INFO_TYPE_SHADOW, rs.VIEWPORT_RENDER_INFO_OBJECTS_IN_FRAME),
		rs.viewport_get_render_info(vp, rs.VIEWPORT_RENDER_INFO_TYPE_SHADOW, rs.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME),
		rs.viewport_get_render_info(vp, rs.VIEWPORT_RENDER_INFO_TYPE_SHADOW, rs.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME)])
	if mirror_viewport:
		var mv := mirror_viewport.get_viewport_rid()
		print("[perf] drawn, mirror (update mode %d): %d objects, %d triangles, %d draw calls | its shadow pass: %d objects, %d triangles, %d draw calls" % [
			mirror_viewport.render_target_update_mode,
			rs.viewport_get_render_info(mv, rs.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, rs.VIEWPORT_RENDER_INFO_OBJECTS_IN_FRAME),
			rs.viewport_get_render_info(mv, rs.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, rs.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME),
			rs.viewport_get_render_info(mv, rs.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, rs.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME),
			rs.viewport_get_render_info(mv, rs.VIEWPORT_RENDER_INFO_TYPE_SHADOW, rs.VIEWPORT_RENDER_INFO_OBJECTS_IN_FRAME),
			rs.viewport_get_render_info(mv, rs.VIEWPORT_RENDER_INFO_TYPE_SHADOW, rs.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME),
			rs.viewport_get_render_info(mv, rs.VIEWPORT_RENDER_INFO_TYPE_SHADOW, rs.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME)])
	print("[perf] all viewports: %d objects, %d triangles, %d draw calls; %d nodes" % [
		rs.get_rendering_info(rs.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME), rs.get_rendering_info(rs.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
		rs.get_rendering_info(rs.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME), Performance.get_monitor(Performance.OBJECT_NODE_COUNT)])
