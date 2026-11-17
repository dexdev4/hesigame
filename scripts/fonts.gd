class_name Fonts
extends RefCounted
## The typefaces of the game, all of them bundled (assets/fonts, SIL Open Font Licence: see assets/fonts/licenses), so that
## the game looks the same on every phone. (It used to ask the phone for "Impact", "Oswald" or "sans-serif" and got whatever
## the phone had.)
##
##   display()  titles, buttons, the score: Chakra Petch Bold, an angular face with cut corners
##   body()     text in sentences: Chakra Petch SemiBold
##   mono()     small labels and the figures that change (speed, distance, money): Oxanium ExtraBold, angular too, and its
##              figures are all the same width, so a number does not shiver as it counts
##
## The road signs do NOT use these: they are lettered by SignKit in the engine's own font, which suits them (see
## SignKit). The lettering on the cars is CarLettering's.

const DIR := "res://assets/fonts/"
const WGHT := 0x77676874   # the 'wght' axis of a variable font (its four characters as a number)

static var _cache := {}


static func file(name: String) -> FontFile:
	if not _cache.has(name):
		_cache[name] = load(DIR + name) as FontFile
	return _cache[name]


## `name` at the weight `wght` (a variable font), with `fallbacks` for the characters it lacks.
static func variable(name: String, wght: float, fallbacks: Array = []) -> FontVariation:
	var key := "%s@%d" % [name, int(wght)]
	if not _cache.has(key):
		var v := FontVariation.new()
		v.base_font = file(name)
		v.variation_opentype = {WGHT: wght}
		v.fallbacks = fallbacks
		_cache[key] = v
	return _cache[key]


static func display() -> Font:
	return file("ChakraPetch-Bold.ttf")


static func body() -> Font:
	return file("ChakraPetch-SemiBold.ttf")


static func mono() -> Font:
	return variable("Oxanium-Variable.ttf", 800.0, [file("ChakraPetch-Bold.ttf")])
