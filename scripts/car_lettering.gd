class_name CarLettering
extends RefCounted
## The names on the cars. Every car has its own lettering, in a typeface that suits it (a slab serif on the muscle car, a
## wide technical face on the supercar, stencil on the car called Last Exit), in a finish that suits it (chrome, gold, black,
## a lit neon), and it is not printed on the paint: it is real lettering (see Lettering), standing a few millimetres off
## the tail with a dark groove round every letter, as if it were set into the panel, laid on the tail exactly as that body's
## tail lies (TailFrames: how far back, how it leans, how it curves).
##
## What a car's name looks like is looked up by the name's text: BADGES for the cars of the garage, the bosses and the police,
## MAKES for the traffic (it has a make each). A name that is in neither gets the plain look.

## text: what is spelt (default: the name itself; a script face wants "Comet", not "COMET"); trim: a last word in another
## finish ("GS" in red); font / wght: the typeface (a variable one at that weight); cap: the height of a capital, m;
## depth: how far the letters stand off the panel; bevel: the chamfer on their front edge; halo: how far the groove round
## them reaches (0: none); tracking: space between letters, in em; skew: slant; finish / trim_finish: see FINISHES;
## gap: the space before the trim, m; dy: moved up (+) or down, m.
const BADGES := {
	"PULSE": {"font": "RussoOne-Regular.ttf", "cap": 0.058, "tracking": 0.05, "finish": "chrome"},
	"VECTOR GS": {"font": "ChakraPetch-Bold.ttf", "text": "VECTOR", "trim": "GS", "cap": 0.050, "tracking": 0.12, "skew": 0.2, "finish": "chrome", "trim_finish": "yellow", "gap": 0.04},
	"HORNET": {"font": "RacingSansOne-Regular.ttf", "cap": 0.066, "tracking": 0.02, "finish": "black", "halo": 0.0},
	"COMET": {"font": "KaushanScript-Regular.ttf", "text": "Comet", "cap": 0.085, "depth": 0.006, "bevel": 0.0015, "halo": 0.0022, "finish": "chrome"},
	"KESTREL": {"font": "Oxanium-Variable.ttf", "wght": 500.0, "cap": 0.052, "tracking": 0.2, "depth": 0.0035, "bevel": 0.001, "halo": 0.003, "finish": "gunmetal"},
	"VANTA GT": {"font": "Orbitron-Variable.ttf", "wght": 800.0, "text": "VANTA", "trim": "GT", "cap": 0.050, "tracking": 0.10, "finish": "chrome", "trim_finish": "red", "gap": 0.04},
	"BRUISER": {"font": "AlfaSlabOne-Regular.ttf", "cap": 0.064, "tracking": 0.03, "depth": 0.009, "bevel": 0.0022, "halo": 0.004, "finish": "chrome"},
	"HALCYON R": {"font": "Michroma-Regular.ttf", "text": "HALCYON", "trim": "R", "cap": 0.040, "tracking": 0.16, "depth": 0.006, "finish": "gunmetal", "trim_finish": "yellow", "gap": 0.05},
	"COPPERHEAD": {"font": "StardosStencil-Bold.ttf", "cap": 0.058, "tracking": 0.08, "depth": 0.008, "finish": "chrome"},
	"MARSHAL": {"font": "Cinzel-Variable.ttf", "wght": 800.0, "cap": 0.056, "tracking": 0.2, "depth": 0.0035, "bevel": 0.001, "halo": 0.003, "finish": "chrome"},
	"BLUE STATIC": {"font": "Audiowide-Regular.ttf", "cap": 0.052, "tracking": 0.08, "depth": 0.006, "finish": "neon_blue"},
	"LAST EXIT": {"font": "SairaStencilOne-Regular.ttf", "cap": 0.058, "tracking": 0.12, "depth": 0.008, "finish": "gold"},
	"POLICE": {"font": "RussoOne-Regular.ttf", "cap": 0.07, "tracking": 0.08, "depth": 0.003, "bevel": 0.0, "halo": 0.0, "finish": "police_blue"},
}

## The traffic's makes.
const MAKES := {
	"ARCO": {"font": "RussoOne-Regular.ttf", "cap": 0.05, "tracking": 0.06},
	"NOVA": {"font": "Orbitron-Variable.ttf", "wght": 700.0, "cap": 0.046, "tracking": 0.12},
	"CIVITA": {"font": "Marcellus-Regular.ttf", "cap": 0.05, "tracking": 0.1},
	"LUMEN": {"font": "Michroma-Regular.ttf", "cap": 0.036, "tracking": 0.12},
	"VEGA": {"font": "RacingSansOne-Regular.ttf", "cap": 0.054, "tracking": 0.04},
	"ORIX": {"font": "Audiowide-Regular.ttf", "cap": 0.048, "tracking": 0.08},
	"TERRA": {"font": "AlfaSlabOne-Regular.ttf", "cap": 0.052, "tracking": 0.04},
	"KITE": {"font": "Oxanium-Variable.ttf", "wght": 600.0, "cap": 0.052, "tracking": 0.14},
	"MERIT": {"font": "Cinzel-Variable.ttf", "wght": 700.0, "cap": 0.05, "tracking": 0.12},
	"AXON": {"font": "ChakraPetch-Bold.ttf", "cap": 0.05, "tracking": 0.1},
}

## The hauliers' names, along the sides of their trailers: a typeface for each.
const FLEETS := {
	"NORTHLINE FREIGHT": {"font": "RussoOne-Regular.ttf", "tracking": 0.04},
	"PRAIRIE HAULAGE": {"font": "AlfaSlabOne-Regular.ttf", "tracking": 0.02},
	"BLUE RIDGE LOGISTICS": {"font": "Michroma-Regular.ttf", "tracking": 0.04, "narrow": true},
	"IRONWAY CARGO": {"font": "StardosStencil-Bold.ttf", "tracking": 0.06},
	"COASTAL MOVERS": {"font": "Audiowide-Regular.ttf", "tracking": 0.04},
	"SUMMIT EXPRESS": {"font": "RacingSansOne-Regular.ttf", "tracking": 0.04},
	"REDROCK TRANSPORT": {"font": "Staatliches-Regular.ttf", "tracking": 0.06},
}
const FLEET_FONT := "Staatliches-Regular.ttf"
const FLEET_CAP := 0.36     # the height of a capital, m
const FLEET_LENGTH := 4.6   # the longest a name may run along the trailer, m (a longer one is made smaller)

## The number plates: a tall narrow face, as plates have.
const PLATE_FONT := "Staatliches-Regular.ttf"

const DEFAULT := {"font": "ChakraPetch-Bold.ttf", "cap": 0.05, "depth": 0.007, "bevel": 0.0018, "halo": 0.0035, "tracking": 0.06, "skew": 0.0,
	"finish": "chrome", "trim_finish": "chrome", "gap": 0.03, "dy": 0.0}

## What the letters are made of. (A finish with "glow" is a lit one: a lamp. The others are the car paint shader's metals and enamels.)
const FINISHES := {
	"chrome": {},   # (CarModel's own chrome)
	"gunmetal": {"base_color": Color("#555a61"), "metallic": 1.0, "roughness": 0.26, "coat": 0.0, "reflect_amount": 0.9, "reflect_f0": 0.6, "metal_tint": 1.0},
	"gold": {"base_color": Color("#e0b04a"), "metallic": 1.0, "roughness": 0.18, "coat": 0.0, "reflect_amount": 1.0, "reflect_f0": 0.7, "metal_tint": 1.0},
	"brass": {"base_color": Color("#cf9a58"), "metallic": 1.0, "roughness": 0.2, "coat": 0.0, "reflect_amount": 1.0, "reflect_f0": 0.65, "metal_tint": 1.0},
	"black": {"base_color": Color("#0d0e10"), "metallic": 0.0, "roughness": 0.16, "coat": 0.9, "coat_roughness": 0.03, "reflect_amount": 1.0, "reflect_f0": 0.05},
	"red": {"base_color": Color("#c4161c"), "metallic": 0.0, "roughness": 0.2, "coat": 0.9, "coat_roughness": 0.03, "reflect_amount": 1.0, "reflect_f0": 0.05},
	"yellow": {"base_color": Color("#f1b823"), "metallic": 0.0, "roughness": 0.2, "coat": 0.9, "coat_roughness": 0.03, "reflect_amount": 1.0, "reflect_f0": 0.05},
	"police_blue": {"base_color": Color("#1b3f8f"), "metallic": 0.0, "roughness": 0.35, "coat": 0.4, "reflect_amount": 0.6, "reflect_f0": 0.04},
	"neon_blue": {"glow": 2.4, "color": Color("#d4eeff")},
}


# ---------------------------------------------------------------- looking things up

## The look of the name `text`: the car's own, a make's, or the plain one.
static func spec(text: String) -> Dictionary:
	var s := DEFAULT.duplicate()
	if BADGES.has(text):
		s.merge(BADGES[text], true)
	elif MAKES.has(text):
		s.merge(MAKES[text], true)
	if not s.has("text"):
		s["text"] = text
	return s


static func font_of(s: Dictionary) -> Font:
	var wght := float(s.get("wght", 0.0))
	if wght > 0.0:
		return Fonts.variable(String(s.font), wght, [Fonts.file("ChakraPetch-Bold.ttf")])
	return Fonts.file(String(s.font))


static func material(finish: String) -> Material:
	if finish == "chrome":
		return CarModel._chrome()
	var f: Dictionary = FINISHES.get(finish, {})
	if f.has("glow"):
		return CarModel.lamp(f.color, float(f.glow))
	return CarModel._car_shader_mat("lettering|" + finish, f)


static func groove_material() -> Material:
	return CarModel._car_shader_mat("lettering|groove", {"base_color": Color("#050607"), "metallic": 0.0, "roughness": 0.5, "coat": 0.0,
		"reflect_amount": 0.25, "reflect_f0": 0.04})


# ---------------------------------------------------------------- the name on a tail

## The meshes of the name `text` for a body: [{"mesh", "finish", "x", "width"}] in order, the first at x (its left edge), as
## (each word is bent to the curve of the tail about its own middle: a name in two finishes is for a flat tail)
## they lie in the plane of the tail (before the tail's frame is put on).
static func parts(text: String, frame: Dictionary) -> Array:
	var s := spec(text)
	var font := font_of(s)
	var bow := float(frame.get("bow", 0.0))
	var o := {"cap": s.cap, "depth": s.depth, "bevel": s.bevel, "halo": s.halo, "tracking": s.tracking, "skew": s.skew,
		"bow": snappedf(bow, 0.05) if absf(bow) > 0.05 else 0.0, "align": -1}   # (bodies that curve alike share the meshes)
	var out: Array = []
	var x := 0.0
	var words: Array = [[String(s.text), String(s.finish)]]
	if String(s.get("trim", "")) != "":
		words.append([String(s.trim), String(s.trim_finish)])
	for w in words:
		var r: Dictionary = Lettering.word(w[0], font, o)
		out.append({"mesh": r.mesh, "finish": w[1], "x": x, "width": r.width, "halo": s.halo > 0.0})
		x += float(r.width) + float(s.gap)
	var total: float = x - float(s.gap)
	for p in out:
		p.x = float(p.x) - total * 0.5
	return out


## The name `text` laid on the tail of body `shape_id`: MeshInstance3Ds, in the space of the body (its origin at the tail, the car
## going off towards -z), a hair above the panel. The caller puts them in the body and chooses how far away they show.
static func badge(shape_id: String, text: String) -> Array:
	var fr := TailFrames.of(shape_id)
	var s := spec(text)
	var y: float = float(fr.y) + float(s.dy)
	var z: float = float(fr.z) + float(fr.slope) * float(s.dy) + 0.0012   # (just off the panel, so the groove does not flicker with it)
	var out: Array = []
	for p in parts(text, fr):
		var mi := MeshInstance3D.new()
		mi.mesh = p.mesh
		mi.set_surface_override_material(0, material(String(p.finish)))
		if (p.mesh as ArrayMesh).get_surface_count() > 1:
			mi.set_surface_override_material(1, groove_material())
		mi.position = Vector3(float(p.x), y, z)
		mi.rotation.x = atan(float(fr.slope))
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		out.append(mi)
	return out


## Make the name now (the meshes are kept), so that the first car that wears it is not built in the middle of a race.
static func warm(shape_id: String, text: String) -> void:
	parts(text, TailFrames.of(shape_id))


## Does the name `text` have a look of its own (a car of the garage, a boss, the police: not a make of the traffic)?
static func has_design(text: String) -> bool:
	return BADGES.has(text)


## The number plate's characters, raised a little off the plate: a mesh instance at the middle of the plate (y, and z the face of
## the plate), in the dark blue ink of a plate. The text is fixed (a car of the garage, a boss, the police): the traffic's
## plates change from car to car, so they are printed (Label3D) instead.
static func plate(text: String, y: float, z: float) -> MeshInstance3D:
	var r: Dictionary = Lettering.word(text, Fonts.file(PLATE_FONT), {"cap": 0.066, "depth": 0.0016, "tracking": 0.05, "align": 0})
	var mi := MeshInstance3D.new()
	mi.mesh = r.mesh
	mi.set_surface_override_material(0, CarModel._car_shader_mat("lettering|plate", {"base_color": Color("#16213f"), "metallic": 0.0,
		"roughness": 0.5, "coat": 0.0, "reflect_amount": 0.15, "reflect_f0": 0.04}))
	mi.position = Vector3(0.0, y, z)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## A haulier's name for both sides of a trailer (the right one first): flat letters, standing a hand's breadth off the side, read
## from outside. `colour`: the letters' colour.
static func fleet(text: String, colour: Color, side_x: float, y: float, z: float) -> Array:
	var f: Dictionary = FLEETS.get(text, {})
	var font: Font = Fonts.file(String(f.get("font", FLEET_FONT)))
	var cap := FLEET_CAP
	var tracking := float(f.get("tracking", 0.05))
	var r: Dictionary = Lettering.word(text, font, {"cap": cap, "depth": 0.012, "tracking": tracking, "align": 0})
	if float(r.width) > FLEET_LENGTH:   # (a long name in a wide face: the same face, smaller, so that it fits the trailer)
		cap = cap * FLEET_LENGTH / float(r.width)
		r = Lettering.word(text, font, {"cap": cap, "depth": 0.012, "tracking": tracking, "align": 0})
	var mat := CarModel.mat(colour, 0.0, 0.55)
	var out: Array = []
	for s in [1.0, -1.0]:
		var mi := MeshInstance3D.new()
		mi.mesh = r.mesh
		mi.set_surface_override_material(0, mat)
		mi.position = Vector3(s * side_x, y, z)
		mi.rotation.y = s * PI / 2.0
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		out.append(mi)
	return out


static func warm_fleet(text: String) -> void:
	fleet(text, Color.WHITE, 0.0, 0.0, 0.0)


static func warm_plate(text: String) -> void:
	plate(text, 0.0, 0.0)
