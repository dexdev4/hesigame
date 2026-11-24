class_name SignKit
extends RefCounted
## Lettering and panels for the road signs, set out the way real signs are: one letter height across a sign, names
## against the left margin and distances against the right in columns of their own (never padded with spaces), text
## centred on the line it is written on, and a white line round a panel, inset from its edge.
##
## The em (the size of the letters) is given in metres; a capital letter is CAP of it. Every line is its own Label3D, so
## the rows of two columns cannot drift apart.

const PX := 96                  # the size the glyphs are drawn at, for every sign (one glyph atlas for all of them)
const CAP := 0.714              # height of a capital, as a fraction of the em (Open Sans, the engine's default font)
const CAP_SHIFT := 0.0285       # how far a line box's middle is above the middle of its capitals, in ems
const WHITE := Color("#f3f5ef")
const LETTERS := 0.025          # how far in front of a panel's face the letters go


## Width in metres of `s` set with an em of `em` metres.
static func width(s: String, em: float) -> float:
	return ThemeDB.fallback_font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, PX).x * em / PX


## The em that makes the widest of `lines` fit in `max_w` metres, but no bigger than `em`.
static func fit_em(lines: Array, em: float, max_w: float) -> float:
	var w := 0.0
	for s in lines:
		w = maxf(w, width(String(s), 1.0))
	return minf(em, max_w / maxf(w, 0.001))


## One line of lettering. `pos` is where the line is anchored: its left end (HORIZONTAL_ALIGNMENT_LEFT), its right end
## (RIGHT) or its middle (CENTER); vertically it sits with the middle of its capitals on pos.y.
static func line(s: String, em: float, col: Color, pos: Vector3, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_CENTER, basis := Basis()) -> Label3D:
	var l := Label3D.new()
	l.text = s
	l.font_size = PX
	l.pixel_size = em / PX
	l.modulate = col
	l.outline_size = 0
	l.horizontal_alignment = align
	l.transform = Transform3D(basis, pos + basis * Vector3(0.0, CAP_SHIFT * em, 0.0))
	return l


## Several rows of lettering in one label (one draw for all of them): `rows` one under the other, `pitch` metres from one
## row's capitals to the next row's, the first row's capitals on pos.y, and every row anchored as for line(). The rows of
## two blocks made with the same pitch (a column of names and a column of figures) line up exactly: both are made of
## lines of the same height.
static func block(rows: Array, em: float, col: Color, pos: Vector3, pitch: float, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_CENTER, basis := Basis()) -> Label3D:
	var l := Label3D.new()
	l.text = "\n".join(PackedStringArray(rows))
	l.font_size = PX
	l.pixel_size = em / PX
	l.modulate = col
	l.outline_size = 0
	l.horizontal_alignment = align
	l.line_spacing = pitch * PX / em - ThemeDB.fallback_font.get_height(PX)  # (the height of a line, and this on top, is the pitch)
	var middle := (rows.size() - 1) / 2.0 * pitch  # from the first row down to the middle of the block, which is where the label is centred
	l.transform = Transform3D(basis, pos + basis * Vector3(0.0, CAP_SHIFT * em - middle, 0.0))
	return l


## Change the text of a line made with line(), shrinking it to `max_w` metres if it would be wider (em: its full size).
static func set_text(l: Label3D, s: String, em: float, max_w := 0.0) -> void:
	l.text = s
	var k := 1.0 if max_w <= 0.0 else minf(1.0, max_w / maxf(width(s, em), 0.001))
	var old: float = l.pixel_size * PX
	var y_old := CAP_SHIFT * old
	l.pixel_size = em * k / PX
	l.position.y += CAP_SHIFT * em * k - y_old  # keep the capitals' middle where it was


## The boxes of a panel, as [material, centre, size] triples: a face, and a line of line_mat round it that is
## `inset` from the edge and `thick` wide. c is the middle of the front of the face (z the front); the line stands a
## hair proud of it and the letters go in front of that (z + LETTERS).
static func panel(face: Material, line_mat: Material, c: Vector3, w: float, h: float, inset := 0.12, thick := 0.06, depth := 0.08) -> Array:
	var out: Array = [[face, c + Vector3(0.0, 0.0, -depth / 2.0), Vector3(w, h, depth)]]
	var iw := w - 2.0 * inset
	var ih := h - 2.0 * inset
	var z := c.z + 0.008
	out.append([line_mat, Vector3(c.x, c.y + ih / 2.0 - thick / 2.0, z), Vector3(iw, thick, 0.016)])
	out.append([line_mat, Vector3(c.x, c.y - ih / 2.0 + thick / 2.0, z), Vector3(iw, thick, 0.016)])
	out.append([line_mat, Vector3(c.x - iw / 2.0 + thick / 2.0, c.y, z), Vector3(thick, ih - 2.0 * thick, 0.016)])
	out.append([line_mat, Vector3(c.x + iw / 2.0 - thick / 2.0, c.y, z), Vector3(thick, ih - 2.0 * thick, 0.016)])
	return out

