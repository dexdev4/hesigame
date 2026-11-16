extends Node
## What a crash does to a car's meshes, and what it costs the frame it happens in:
##   godot --headless --path . tools/damage_test.tscn
## Builds cars, gives each the same fixed blows (a hard knock at the nose, a tap at the side, one more on the first), steps
## the damage the way the game does (one `step` a frame, never waiting) until it is all pressed in, and prints how long the
## longest frame's share of it took, how many frames it took, and a fingerprint of what the car's meshes came to: the
## vertices exactly (they are what a dent moves), the normals and the colours (a dent tilts and darkens them) by their
## sums, since the engine keeps those in less than full precision. Run on two builds, the vertex fingerprints must be the
## same and the sums within a few thousandths.

var _cars: Array = ["copperhead", "vector", "marshal"]


func _ready() -> void:
	for id in _cars:
		var c := Data.car_by_id(id)
		var m := CarModel.new()
		add_child(m)
		m.build(String(c.shape), Color(c.color), Color("#b5322a"), c.style)
		var shape: Dictionary = m.shape
		var d := m.damage()
		var l: float = shape.l
		d.hit(Vector3(0.1, 0.55, -l * 0.97), Vector3(0.0, 0.0, 1.0), 11.0)  # a hard knock at the nose
		d.hit(Vector3(0.85, 0.6, -l * 0.5), Vector3(-1.0, 0.0, 0.0), 6.0)    # a tap on the right side
		var frames := 0
		var worst := 0.0
		var total := 0.0
		while CarDamage.active.has(d):
			var t0 := Time.get_ticks_usec()
			var more := d.step()
			var ms := float(Time.get_ticks_usec() - t0) / 1000.0
			worst = maxf(worst, ms)
			total += ms
			frames += 1
			if not more:
				CarDamage.active.erase(d)
			await get_tree().process_frame
			if frames > 400:
				break
		d.hit(Vector3(0.1, 0.55, -l * 0.97), Vector3(0.0, 0.0, 1.0), 9.0)  # and another, on the first
		while CarDamage.active.has(d):
			var t0 := Time.get_ticks_usec()
			var more := d.step()
			var ms := float(Time.get_ticks_usec() - t0) / 1000.0
			worst = maxf(worst, ms)
			total += ms
			frames += 1
			if not more:
				CarDamage.active.erase(d)
			await get_tree().process_frame
			if frames > 800:
				break
		var hv := 7
		var sn := 0.0
		var sc := 0.0
		var nv := 0
		for mi in m.damage_targets():
			var mesh := mi.mesh
			for si in mesh.get_surface_count():
				var a := mesh.surface_get_arrays(si)
				var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
				hv = (hv * 31) ^ hash(v)
				nv += v.size()
				if a[Mesh.ARRAY_NORMAL] != null:
					for n in (a[Mesh.ARRAY_NORMAL] as PackedVector3Array):
						sn += n.x + 2.0 * n.y + 3.0 * n.z
				if a[Mesh.ARRAY_COLOR] != null:
					for col in (a[Mesh.ARRAY_COLOR] as PackedColorArray):
						sc += col.r + col.g + col.b
		print("%-11s %d frames, %.1f ms in all, the longest frame %.1f ms | %d vertices, vertices %08x, normals %.2f, colours %.2f" % [id, frames, total, worst, nv, hv & 0xffffffff, sn, sc])
		m.queue_free()
	get_tree().quit()
