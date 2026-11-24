class_name LedBoard
extends RefCounted
## Rows of seven-segment LED figures for the fuel stations' price boards: a quad for each price, a dark face with the
## figures lit on it (shaders/led_board.gdshader draws them, so a price is two shader parameters and no geometry).

const SHADER := preload("res://shaders/led_board.gdshader")
const ASPECT := 3.34   # a row's width over its height (the shader's: five figures and the decimal point)
const CELLS := 5       # three figures before the point and two after: 999.99 is the most it can show
const AMBER := Color("#ffa010")
const DAY := 2.3       # how brightly a lit figure glows by day and by night (HDR: it blooms where the game has bloom)
const NIGHT := 3.6


## A row of figures `height` metres tall (and ASPECT times that wide), facing +z, its middle at `pos`.
static func row(height: float, pos: Vector3, color := AMBER) -> MeshInstance3D:
	var q := QuadMesh.new()
	q.size = Vector2(height * ASPECT, height)
	var m := ShaderMaterial.new()
	m.shader = SHADER
	m.set_shader_parameter("lit_color", color)
	m.set_shader_parameter("level", DAY)
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.material_override = m
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	set_price(mi, 0.0)
	return mi


## The figures in each of the five cells for a price (0..9, or 10 for a blank cell): right-aligned, with no leading
## zeros, two decimals, and 999.99 for anything more.
static func cells_for(price: float) -> PackedFloat32Array:
	var digits := ("%.2f" % clampf(price, 0.0, 999.99)).replace(".", "")
	var cells := PackedFloat32Array([10.0, 10.0, 10.0, 10.0, 10.0])
	var first := CELLS - digits.length()
	for i in digits.length():
		cells[first + i] = float(digits.unicode_at(i) - 48)
	return cells


## Show a price on a row.
static func set_price(mi: MeshInstance3D, price: float) -> void:
	var c := cells_for(price)
	var m := mi.material_override as ShaderMaterial
	m.set_shader_parameter("cells_a", Vector4(c[0], c[1], c[2], c[3]))
	m.set_shader_parameter("cell_b", c[4])


## Day (k = 0) to night (k = 1): the figures glow harder in the dark.
static func set_night(mi: MeshInstance3D, k: float) -> void:
	(mi.material_override as ShaderMaterial).set_shader_parameter("level", lerpf(DAY, NIGHT, k))
