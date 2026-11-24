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

# --hitch=MS: every frame that takes MS milliseconds or more, from one end of a frame to the next (so the engine's own
# work and the wait for the screen are in it, not only the script's), is printed with where the script's time went and
# what happened in it: whatever the game noted with PerfProbe.note() since the last frame (a car being built, the
# save being written, a song being loaded...). At the end a summary says how often and how badly the frame hitched and
# what was going on in the frames that did.
static var on := false         # (static, so that any script can note an event)
static var events: Array = []  # [what, milliseconds] noted since the last frame ended
var hitch_ms := 0.0
var skip_frames := 120         # (the first frames of a run load things: they are not counted)
var _cur := {}
var _prev_end := 0
var _spikes: Array = []        # [frame, interval ms, [events]] for every hitch
var _gaps: Array = []          # every frame's interval, ms (after the first skip_frames)


## A time to give to note() (0 when nothing is being measured).
static func t() -> int:
	return Time.get_ticks_usec() if on else 0


## Something that took a while just happened: how long since t0 (a PerfProbe.t()).
static func note(what: String, t0: int) -> void:
	if on:
		var ms := float(Time.get_ticks_usec() - t0) / 1000.0
		if ms >= 0.25:
			events.append([what, ms])


func begin() -> void:
	_last = Time.get_ticks_usec()
	_cur = {}


## Charge the time since the last mark (or begin) to `section`.
func mark(section: String) -> void:
	var n := Time.get_ticks_usec()
	_acc[section] = int(_acc.get(section, 0)) + (n - _last)
	_cur[section] = int(_cur.get(section, 0)) + (n - _last)
	_last = Time.get_ticks_usec()


## True when a report is due.
func end_frame() -> bool:
	frames += 1
	if hitch_ms > 0.0:
		var now := Time.get_ticks_usec()
		if frames == 1 and not events.is_empty():
			var first := []
			var total := 0.0
			for e in events:
				first.append("%s %.1f" % [e[0], e[1]])
				total += float(e[1])
			print("[hitch] before the first frame (the start of the run: not counted below): %s" % ", ".join(first))
		if _prev_end > 0 and frames > skip_frames:
			var gap := float(now - _prev_end) / 1000.0
			_gaps.append(gap)
			if gap >= hitch_ms:
				var script_us := 0
				var parts := []
				var keys := _cur.keys()
				keys.sort_custom(func(a: String, b: String) -> bool: return _cur[a] > _cur[b])
				for k in keys:
					script_us += int(_cur[k])
					if int(_cur[k]) >= 500:
						parts.append("%s %.1f" % [k, float(_cur[k]) / 1000.0])
				var ev := []
				for e in events:
					ev.append("%s %.1f" % [e[0], e[1]])
				_spikes.append([frames, gap, events.duplicate()])
				print("[hitch] frame %d: %.1f ms (the script %.1f ms: %s; the engine says process %.1f, physics %.1f, %d objects, %d nodes)%s" % [frames, gap, float(script_us) / 1000.0, ", ".join(parts),
					Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
					int(Performance.get_monitor(Performance.OBJECT_COUNT)), int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)), (" | " + ", ".join(ev)) if not ev.is_empty() else ""])
		_prev_end = Time.get_ticks_usec()
		events.clear()
	return frames % every == 0


## How often the frame hitched, and what was going on when it did.
func summary() -> String:
	if hitch_ms <= 0.0 or _gaps.is_empty():
		return ""
	var g := _gaps.duplicate()
	g.sort()
	var by := {}
	var bare := 0
	for sp in _spikes:
		if (sp[2] as Array).is_empty():
			bare += 1
		var seen := {}
		for e in sp[2]:
			if not seen.has(e[0]):
				seen[e[0]] = true
				by[e[0]] = [int((by.get(e[0], [0, 0.0]) as Array)[0]) + 1, maxf(float((by.get(e[0], [0, 0.0]) as Array)[1]), float(sp[1]))]
	var names := by.keys()
	names.sort_custom(func(a: String, b: String) -> bool: return by[a][0] > by[b][0])
	var parts := []
	for n in names:
		parts.append("%s in %d (up to %.0f ms)" % [n, by[n][0], by[n][1]])
	return "[hitch] %d frames measured: median %.1f ms, 99th percentile %.1f, worst %.1f; %d took %.0f ms or more, %d of those with nothing noted in them%s" % [
		g.size(), g[g.size() / 2], g[int(g.size() * 0.99)], g[g.size() - 1], _spikes.size(), hitch_ms, bare, ("; noted in them: " + ", ".join(parts)) if not parts.is_empty() else ""]


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


## The heaviest meshes below a node: [triangles, instances, what it is].
func _casters(n: Node, out: Array) -> void:
	if n is Node3D and not (n as Node3D).visible:
		return
	if n is MeshInstance3D and (n as MeshInstance3D).mesh:
		out.append([_mesh_tris((n as MeshInstance3D).mesh), 1, "%s%s %s, %d surfaces, at z=%.0f" % ["[shadow] " if (n as MeshInstance3D).cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF else "", str(n.get_path()).right(60), (n as MeshInstance3D).mesh.get_class(), (n as MeshInstance3D).mesh.get_surface_count(), (n as Node3D).global_position.z]])
	elif n is MultiMeshInstance3D and (n as MultiMeshInstance3D).multimesh and (n as MultiMeshInstance3D).multimesh.mesh:
		var mm := (n as MultiMeshInstance3D).multimesh
		var count := mm.visible_instance_count if mm.visible_instance_count >= 0 else mm.instance_count
		out.append([_mesh_tris(mm.mesh) * count, count, "%s%s multimesh of %s" % ["[shadow] " if (n as MultiMeshInstance3D).cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF else "", n.name, mm.mesh.get_class()]])
	for c in n.get_children():
		_casters(c, out)


func _caster_line(label: String, root: Node) -> void:
	var list: Array = []
	_casters(root, list)
	list.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	var parts := []
	for i in mini(14, list.size()):
		parts.append("%d tri x%d %s" % [list[i][0], list[i][1], list[i][2]])
	print("[perf] heaviest meshes in %s (those that cast shadows are marked): %s" % [label, "; ".join(parts)])


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
	_caster_line("the scenery", scenery)
	if not traffic_models.is_empty():
		_caster_line("the first traffic car", traffic_models[0])
	_caster_line("the player's car", player_model)
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
