extends SceneTree
## The sign lettering kit, no window needed:
##   godot --headless --path . --script tools/sign_test.gd
## Checks SignKit: that text fitted to a width never comes out wider than it, that the line round a panel lies inside
## its face with the same gap on every side, that a line is anchored where it is told (left, right or middle) with the
## middle of its capitals on the height asked for, that shrinking a line keeps it there, and that the constants for
## the font (a capital's height and where it sits in its line) agree with the font itself. Exits with a non-zero
## code if a check fails. (The engine's own notes about the labels it was not asked to free, printed as it exits, are
## to be ignored.)

var _fails := 0
var _checks := 0


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_fails += 1
		print("  FAIL: ", what)


func _near(a: float, b: float, tol: float) -> bool:
	return absf(a - b) <= tol


func _initialize() -> void:
	_font()
	_fit()
	_panel()
	_lines()
	print("== %d checks, %d failed" % [_checks, _fails])
	quit(1 if _fails > 0 else 0)


func _font() -> void:
	var f := ThemeDB.fallback_font
	# where a line's middle is above the middle of its capitals, as the font has it (the line box runs from the
	# descent to the ascent, and a capital stands CAP of the em on the baseline)
	var shift := ((f.get_ascent(SignKit.PX) - f.get_descent(SignKit.PX)) / 2.0 - SignKit.CAP * SignKit.PX / 2.0) / SignKit.PX
	print("  font %s: ascent %.3f em, descent %.3f em; capitals' middle %.4f em below the line's middle (CAP_SHIFT %.4f)" % [
		f.get_font_name(), f.get_ascent(SignKit.PX) / float(SignKit.PX), f.get_descent(SignKit.PX) / float(SignKit.PX), shift, SignKit.CAP_SHIFT])
	_check(_near(shift, SignKit.CAP_SHIFT, 0.004), "CAP_SHIFT agrees with the font (%.4f against %.4f)" % [SignKit.CAP_SHIFT, shift])
	_check(SignKit.width("MM", 1.0) > SignKit.width("M", 1.0), "a longer line is wider")
	_check(_near(SignKit.width("Mercer", 2.0), 2.0 * SignKit.width("Mercer", 1.0), 0.001), "width scales with the em")
	# digits all as wide as each other, so a column of prices lines up whatever the figures
	_check(_near(SignKit.width("1111", 1.0), SignKit.width("8888", 1.0), 0.001), "figures are tabular (a column of prices lines up)")


func _fit() -> void:
	var names := ["Oak Hollow", "Granite Falls", "Kingsbridge", "Mercer", "BLUE FLAME GAS", "LAST CHANCE GAS", "120 km", ""]
	for max_w in [1.0, 2.6, 4.0, 7.3]:
		for em in [0.3, 0.7, 2.0]:
			var got := SignKit.fit_em(names, em, max_w)
			var widest := 0.0
			for s in names:
				widest = maxf(widest, SignKit.width(String(s), got))
			_check(widest <= max_w + 0.0005, "fit_em(%.1f m, em %.1f): the widest line is %.3f m wide" % [max_w, em, widest])
			_check(got <= em + 1e-9, "fit_em never makes the letters bigger than asked (%.3f against %.1f)" % [got, em])
			if SignKit.width("Mercer", em) < max_w and names.size() == 1:
				_check(_near(got, em, 1e-9), "text that fits keeps its size")


func _panel() -> void:
	var face := StandardMaterial3D.new()
	var line := StandardMaterial3D.new()
	for dims in [Vector2(6.2, 2.4), Vector2(1.9, 1.1), Vector2(8.6, 2.3), Vector2(4.6, 3.5)]:
		var c := Vector3(1.5, 5.0, 0.31)
		var boxes := SignKit.panel(face, line, c, dims.x, dims.y, 0.12, 0.06, 0.08)
		_check(boxes.size() == 5, "a panel is a face and four lines")
		var f: Array = boxes[0]
		_check(f[0] == face and f[2] == Vector3(dims.x, dims.y, 0.08), "the face is the size asked for")
		_check(_near((f[1] as Vector3).z + (f[2] as Vector3).z / 2.0, c.z, 1e-6), "the front of the face is at z")
		var lo := Vector2(1e9, 1e9)
		var hi := Vector2(-1e9, -1e9)
		for i in range(1, 5):
			var b: Array = boxes[i]
			var ctr: Vector3 = b[1]
			var sz: Vector3 = b[2]
			_check(b[0] == line, "the lines are in the line's material")
			_check(ctr.z - sz.z / 2.0 < c.z and ctr.z + sz.z / 2.0 > c.z, "the lines stand proud of the face")
			lo = Vector2(minf(lo.x, ctr.x - sz.x / 2.0), minf(lo.y, ctr.y - sz.y / 2.0))
			hi = Vector2(maxf(hi.x, ctr.x + sz.x / 2.0), maxf(hi.y, ctr.y + sz.y / 2.0))
		# the same gap from the face's edge to the line, all the way round
		var face_lo := Vector2(c.x - dims.x / 2.0, c.y - dims.y / 2.0)
		var face_hi := Vector2(c.x + dims.x / 2.0, c.y + dims.y / 2.0)
		_check(_near(lo.x - face_lo.x, 0.12, 1e-6) and _near(lo.y - face_lo.y, 0.12, 1e-6), "the line is inset 0.12 from the left and bottom edges")
		_check(_near(face_hi.x - hi.x, 0.12, 1e-6) and _near(face_hi.y - hi.y, 0.12, 1e-6), "the line is inset 0.12 from the right and top edges")
		# the sides meet the top and bottom without overlapping them
		var top: Array = boxes[1]
		var side: Array = boxes[3]
		_check((side[1] as Vector3).y + (side[2] as Vector3).y / 2.0 <= (top[1] as Vector3).y - (top[2] as Vector3).y / 2.0 + 1e-6, "the sides stop where the top line begins")


func _lines() -> void:
	var p := Vector3(2.0, 6.0, 0.3)
	var em := 0.7
	var left := SignKit.line("Lakeview", em, Color.WHITE, p, HORIZONTAL_ALIGNMENT_LEFT)
	var right := SignKit.line("12 km", em, Color.WHITE, p, HORIZONTAL_ALIGNMENT_RIGHT)
	var mid := SignKit.line("Oak Hollow", em, Color.WHITE, p)
	_check(left.horizontal_alignment == HORIZONTAL_ALIGNMENT_LEFT and right.horizontal_alignment == HORIZONTAL_ALIGNMENT_RIGHT and mid.horizontal_alignment == HORIZONTAL_ALIGNMENT_CENTER, "the alignment is the one asked for")
	_check(left.position.x == p.x and right.position.x == p.x and mid.position.x == p.x and left.position.z == p.z, "a line is anchored where it is told")
	_check(left.position.y == right.position.y and right.position.y == mid.position.y, "lines of one row share one height, whatever they say")
	_check(_near(left.position.y, p.y + SignKit.CAP_SHIFT * em, 1e-5), "the middle of the capitals is on the height asked for")
	_check(_near(left.pixel_size * SignKit.PX, em, 1e-5) and left.font_size == SignKit.PX, "the letters are em metres")
	_check(left.outline_size == 0, "no outline round the letters")
	# set_text: a line that is too long shrinks, and its capitals stay where they were
	var row := SignKit.line("", em, Color.WHITE, p, HORIZONTAL_ALIGNMENT_CENTER)
	SignKit.set_text(row, "SUNSET FUEL", em, 1.2)
	var w := SignKit.width(row.text, row.pixel_size * SignKit.PX)
	_check(w <= 1.2 + 0.0005, "set_text shrinks a line to the width (%.3f m of 1.2)" % w)
	_check(_near(row.position.y, p.y + SignKit.CAP_SHIFT * row.pixel_size * SignKit.PX, 1e-5), "a shrunk line keeps its capitals' middle on the height")
	SignKit.set_text(row, "AB", em, 1.2)
	_check(_near(row.pixel_size * SignKit.PX, em, 1e-5), "a short line is back at full size")
	_check(_near(row.position.y, p.y + SignKit.CAP_SHIFT * em, 1e-5), "and still on the height")
	# a block of rows: one label whose rows are `pitch` apart, the first row's capitals on the height asked for
	var names := SignKit.block(["Lakeview", "Ashford", "Mercer"], em, Color.WHITE, p, 1.0, HORIZONTAL_ALIGNMENT_LEFT)
	var dists := SignKit.block(["12 km", "40 km", "7 km"], em, Color.WHITE, p, 1.0, HORIZONTAL_ALIGNMENT_RIGHT)
	var height := ThemeDB.fallback_font.get_height(SignKit.PX)
	_check(names.text.count("\n") == 2 and names.text.begins_with("Lakeview"), "a block has its rows one under the other")
	_check(_near((height + names.line_spacing) * names.pixel_size, 1.0, 1e-4), "the rows of a block are the pitch apart (%.4f m)" % ((height + names.line_spacing) * names.pixel_size))
	_check(names.position == dists.position - Vector3(0.0, 0.0, 0.0) and names.line_spacing == dists.line_spacing, "two blocks with one pitch, at one place, have their rows level")
	# the label is centred on the middle of its rows: two rows of pitch 1 have their middle half a pitch below the first
	_check(_near(names.position.y, p.y - 1.0 + SignKit.CAP_SHIFT * em, 1e-5), "the first row's capitals are on the height (the block hangs from it)")
	var one := SignKit.block(["Mercer"], em, Color.WHITE, p, 1.0)
	_check(_near(one.position.y, left.position.y, 1e-5), "a block of one row is the same as a line")
	# turned about the vertical (the kiosk's sign, the garage wall's), the line keeps its height
	var turned := SignKit.line("EXIT 12", em, Color.WHITE, p, HORIZONTAL_ALIGNMENT_CENTER, Basis(Vector3.UP, PI))
	_check(_near(turned.position.y, p.y + SignKit.CAP_SHIFT * em, 1e-5), "a line turned about the vertical is at the same height")
