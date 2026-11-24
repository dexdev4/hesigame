class_name CarTextures
extends RefCounted
## Lamp lens and grille textures, drawn in code once at start-up. Each lamp
## texture comes as an albedo map and an emission map. Texture u runs from the
## inner end of the lamp to the outer end, v from bottom to top.

static var _cache := {}


## Returns [albedo, emission] ImageTextures.
static func _make(key: String, wpx: int, hpx: int, fn: Callable) -> Array:
	if _cache.has(key):
		return _cache[key]
	var ia := Image.create(wpx, hpx, false, Image.FORMAT_RGBA8)
	var ie := Image.create(wpx, hpx, false, Image.FORMAT_RGBA8)
	for y in hpx:
		var v := 1.0 - (y + 0.5) / hpx
		for x in wpx:
			var u := (x + 0.5) / wpx
			var c: Array = fn.call(u, v)
			ia.set_pixel(x, y, c[0])
			ie.set_pixel(x, y, c[1])
	ia.generate_mipmaps()
	ie.generate_mipmaps()
	var res := [ImageTexture.create_from_image(ia), ImageTexture.create_from_image(ie)]
	_cache[key] = res
	return res


## Headlight: smoked chrome housing, two projector lenses in reflector bowls,
## an LED running-light guide along the top and down the outer end, and an
## amber indicator at the corner. halo adds light rings round the projectors.
static func headlight(halo := false) -> Array:
	return _make("head%s" % halo, 256, 64, func(u: float, v: float) -> Array:
		var aspect := 3.8
		var alb := Color(0.1, 0.11, 0.125).lerp(Color(0.3, 0.32, 0.35), v)
		var emi := Color(0, 0, 0)
		for cx in [0.3, 0.58]:
			var dx: float = (u - cx) * aspect
			var dy: float = v - 0.42
			var dist: float = sqrt(dx * dx + dy * dy)
			if dist < 0.3:
				var b := 0.32 + 0.55 * (1.0 - dist / 0.3)
				alb = Color(b, b, b * 1.04)
			if halo and dist > 0.24 and dist < 0.29:
				alb = Color(0.92, 0.95, 1.0)
				emi = Color(0.9, 0.95, 1.0)
			if dist < 0.15:
				alb = Color(0.04, 0.05, 0.07)
				emi = Color(0.22, 0.24, 0.28)
				var hx: float = dx + 0.05
				var hy: float = dy - 0.05
				if hx * hx + hy * hy < 0.0016:
					alb = Color(1, 1, 1)
		var drl := (v > 0.74 and v < 0.85 and u > 0.08 and u < 0.9) or (u > 0.84 and u < 0.9 and v > 0.28 and v < 0.85)
		if drl:
			alb = Color(0.95, 0.96, 1.0)
			emi = Color(1, 1, 1)
		if u > 0.92 and u < 0.985 and v > 0.18 and v < 0.7:
			alb = Color(0.95, 0.56, 0.12)
		if u < 0.015 or u > 0.99 or v < 0.06 or v > 0.95:
			alb = Color(0.05, 0.055, 0.06)
			emi = Color(0, 0, 0)
		return [alb, emi])


## Tail light: deep red lens, a C-shaped LED light guide round the outer part,
## a block of small LED cells, and a clear reverse lamp at the inner end.
static func taillight() -> Array:
	return _make("tail", 256, 64, func(u: float, v: float) -> Array:
		var alb := Color(0.34, 0.03, 0.03).lerp(Color(0.5, 0.06, 0.05), v)
		var emi := Color(0.2, 0.01, 0.0)
		if u < 0.17 and v > 0.25 and v < 0.75:
			alb = Color(0.82, 0.83, 0.85)
			emi = Color(0, 0, 0)
		var bar := false
		if u > 0.84 and u < 0.9 and v > 0.16 and v < 0.88:
			bar = true
		if v > 0.78 and v < 0.88 and u > 0.22 and u < 0.9:
			bar = true
		if v > 0.16 and v < 0.25 and u > 0.38 and u < 0.9:
			bar = true
		if u > 0.4 and u < 0.8 and v > 0.34 and v < 0.66:
			var cu := fmod(u * 22.0, 1.0)
			var cv := fmod(v * 6.0, 1.0)
			if cu > 0.25 and cu < 0.75 and cv > 0.3 and cv < 0.7:
				bar = true
		if bar:
			alb = Color(1.0, 0.25, 0.2)
			emi = Color(1.0, 0.1, 0.05)
		if u < 0.012 or u > 0.99 or v < 0.05 or v > 0.95:
			alb = Color(0.07, 0.03, 0.03)
			emi = Color(0, 0, 0)
		return [alb, emi])


## Grille mesh: offset rows of cells with lighter frames.
static func grille() -> Array:
	return _make("grille", 256, 96, func(u: float, v: float) -> Array:
		var gy := v * 9.0
		var row := int(floor(gy))
		var gx := u * 26.0 + (0.5 if row % 2 == 1 else 0.0)
		var fx := fmod(gx, 1.0)
		var fy := fmod(gy, 1.0)
		var edge := minf(minf(fx, 1.0 - fx), minf(fy, 1.0 - fy))
		var c := Color(0.02, 0.022, 0.025)
		if edge < 0.14:
			c = Color(0.17, 0.18, 0.2)
		return [c, Color(0, 0, 0)])
