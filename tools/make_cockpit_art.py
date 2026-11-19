#!/usr/bin/env python3
"""Bakes the cockpit art into assets/textures/cockpit/:

  cluster_<car shape>.png   the instrument panel: dial faces with numerals, ticks, the redline, mini gauges,
                            warning lamps and the window the gear and speed readout sits in
  screen_<car shape>.png    the infotainment screen (sat-nav map, a card for the radio text) or the radio's scale
  trim_wood / trim_carbon / trim_brushed .png   tiling finishes for the dash trim strips
  cluster_glare.png         the faint reflection on the glass over the dials

The needles, bezels, wheel and everything with a shape are real geometry (scripts/cabin_parts.gd, car_model.gd);
this is only the flat artwork they sit on. Colours and scales come from the game's own tables, so the art cannot
drift from the car: CABINS (scripts/car_model.gd) gives each cabin's dial colours, and the engine redlines in
scripts/data.gd give each car's rev-counter scale (CarModel.tach_max must agree with tach_max() below).

Needs Pillow and numpy:  python3 tools/make_cockpit_art.py
"""
import math
import os
import re
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "textures", "cockpit")
SS = 3  # supersampling: everything is drawn three times as large and shrunk

FONTS = {
	"inter": "/usr/share/fonts/opentype/inter/Inter-SemiBold.otf",
	"inter_b": "/usr/share/fonts/opentype/inter/Inter-Bold.otf",
	"inter_i": "/usr/share/fonts/opentype/inter/Inter-ExtraBoldItalic.otf",
	"inter_l": "/usr/share/fonts/opentype/inter/Inter-Medium.otf",
	"serif": "/usr/share/fonts/truetype/dejavu/DejaVuSerif-Bold.ttf",
	"sans_b": "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
	"plain": "/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf",
	"plain_b": "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf",
	"mono": "/usr/share/fonts/truetype/dejavu/DejaVuSansMono-Bold.ttf",
}
_fcache = {}


def fnt(key, px):
	k = (key, int(round(px * SS)))
	if k not in _fcache:
		_fcache[k] = ImageFont.truetype(FONTS[key], k[1])
	return _fcache[k]


# ------------------------------------------------------------------ the game's own tables

def parse_value(s):
	s = s.strip()
	if s.startswith("["):
		return [parse_value(x) for x in re.findall(r'"[^"]*"|-?[\d.]+', s)]
	if s.startswith('"'):
		return s.strip('"')
	if s in ("true", "false"):
		return s == "true"
	try:
		return float(s)
	except ValueError:
		return s


def read_game():
	src = open(os.path.join(ROOT, "scripts", "car_model.gd")).read()
	alias = dict(re.findall(r'"(\w+)": "(\w+)"', re.search(r"const CABIN_ALIAS := \{(.*?)\}", src, re.S).group(1)))
	block = re.search(r"const CABINS := \{\n(.*?)\n\}\n", src, re.S).group(1)
	cabins = {}
	for chunk in re.split(r'\n(?=\t"\w+": \{)', block):
		key = re.match(r'\t"(\w+)"', chunk).group(1)
		body = chunk[chunk.index("{") + 1: chunk.rindex("}")]
		cabins[key] = {k: parse_value(v) for k, v in re.findall(r'"(\w+)": (\[[^\]]*\]|"[^"]*"|[^,}\s]+)', body)}
	data = open(os.path.join(ROOT, "scripts", "data.gd")).read()
	cars = re.findall(r'\{"id": "(\w+)".*?"redline": (\d+).*?"shape": "(\w+)"', data, re.S)
	out = []
	for cid, red, shape in cars:
		cab = cabins[alias.get(shape, shape)]
		out.append({"id": cid, "shape": shape, "redline": int(red), "cab": cab, "cabin": alias.get(shape, shape)})
	return out


def tach_max(redline):
	return math.ceil(redline * 1.08 / 1000.0) * 1000


# ------------------------------------------------------------------ drawing

def hexc(s):
	s = s.lstrip("#")
	return tuple(int(s[i:i + 2], 16) for i in (0, 2, 4))


def mix(a, b, t):
	return tuple(int(round(x + (y - x) * t)) for x, y in zip(a, b))


def mul(c, k):
	return tuple(max(0, min(255, int(round(v * k)))) for v in c)


class Layer:
	"""A supersampled RGB surface. Coordinates are in final pixels."""

	def __init__(self, w, h, bg=(0, 0, 0)):
		self.w, self.h = w, h
		self.img = Image.new("RGB", (w * SS, h * SS), bg)
		self.d = ImageDraw.Draw(self.img)

	def line(self, p0, p1, col, width=1.0):
		self.d.line([(p0[0] * SS, p0[1] * SS), (p1[0] * SS, p1[1] * SS)], fill=col, width=max(1, int(round(width * SS))))

	def poly(self, pts, col):
		self.d.polygon([(x * SS, y * SS) for x, y in pts], fill=col)

	def circle(self, c, r, col, width=0):
		box = [(c[0] - r) * SS, (c[1] - r) * SS, (c[0] + r) * SS, (c[1] + r) * SS]
		if width:
			self.d.ellipse(box, outline=col, width=max(1, int(round(width * SS))))
		else:
			self.d.ellipse(box, fill=col)

	def rrect(self, box, r, col, width=0):
		b = [box[0] * SS, box[1] * SS, box[2] * SS, box[3] * SS]
		if width:
			self.d.rounded_rectangle(b, radius=r * SS, outline=col, width=max(1, int(round(width * SS))))
		else:
			self.d.rounded_rectangle(b, radius=r * SS, fill=col)

	def text(self, xy, s, key, px, col, anchor="mm"):
		self.d.text((xy[0] * SS, xy[1] * SS), s, font=fnt(key, px), fill=col, anchor=anchor)

	def arc_band(self, c, r0, r1, a0, a1, col, steps=80):
		pts = []
		for i in range(steps + 1):
			a = a0 + (a1 - a0) * i / steps
			pts.append((c[0] + r1 * math.sin(a), c[1] - r1 * math.cos(a)))
		for i in range(steps, -1, -1):
			a = a0 + (a1 - a0) * i / steps
			pts.append((c[0] + r0 * math.sin(a), c[1] - r0 * math.cos(a)))
		self.poly(pts, col)

	def array(self):
		return np.asarray(self.img, dtype=np.float32) / 255.0

	def final(self, glow=0.0):
		im = self.img.resize((self.w, self.h), Image.LANCZOS)
		return im


def ang(f):
	"""The needle's angle (radians clockwise from twelve o'clock) at a fraction of full scale: the same sweep as
	CarModel.set_gauges, from -2.2 rad (lower left) to +2.2 rad (lower right)."""
	return -2.2 + 4.4 * f


def on_dial(c, r, f):
	a = ang(f)
	return (c[0] + r * math.sin(a), c[1] - r * math.cos(a))


def radial(w, h, c, R, col_in, col_out, power=1.6):
	"""A disc of colour fading from the middle to the rim, as an RGB array over the whole w x h (supersampled) area."""
	yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
	d = np.sqrt((xx - c[0]) ** 2 + (yy - c[1]) ** 2) / R
	t = np.clip(d, 0, 1) ** power
	a = np.array(col_in, np.float32)
	b = np.array(col_out, np.float32)
	return (a[None, None, :] * (1 - t[..., None]) + b[None, None, :] * t[..., None]), d


# ------------------------------------------------------------------ the instrument cluster

# The panel is 0.32 x 0.12 m (CabinParts.CLUSTER_W/H); the dials are 0.05 m in radius, 0.095 m either side of the middle
CW, CH = 1024, 384
DIAL_R = 160
DIAL_CX = (204, 820)  # rev counter on the left, speedometer on the right (as the car lays them out)
DIAL_CY = 192

STYLE_OF = {  # the dial design for each car, by shape
	"hot_hatch": "modern", "sport_sedan": "sport", "compact": "modern", "coupe": "classic", "kestrel": "plain",
	"vanta": "classic", "bruiser": "retro", "halcyon": "track", "copperhead": "retro", "static": "track",
	"marshal": "sport", "lastexit": "track",
}
STYLES = {
	#          face centre / rim,           numeral font, numeral size, tick widths, rings, mph ring, mini gauges
	"modern": dict(face=("#202328", "#08090b"), font="inter", num=0.150, major=0.024, minor=0.010, rings=1, mph=True, mini=True),
	"sport": dict(face=("#241a1a", "#080505"), font="inter_i", num=0.150, major=0.030, minor=0.011, rings=1, mph=True, mini=True, accent_ticks=True),
	"classic": dict(face=("#2a2520", "#0c0a08"), font="serif", num=0.150, major=0.020, minor=0.008, rings=2, mph=True, mini=True),
	"retro": dict(face=("#1c1c1c", "#050505"), font="sans_b", num=0.152, major=0.034, minor=0.014, rings=1, mph=False, mini=False),
	"plain": dict(face=("#26282b", "#0e0f11"), font="plain", num=0.150, major=0.022, minor=0.0, rings=0, mph=False, mini=False),
	"track": dict(face=("#17191c", "#050506"), font="inter_b", num=0.150, major=0.026, minor=0.0, rings=1, mph=False, mini=True, segments=True),
}
RED = (232, 38, 28)


def draw_dial(L, M, c, kind, st, cols, tmax, redline):
	R = DIAL_R
	ink = hexc(cols[1])
	acc = hexc(cols[0])
	font = st["font"]
	# --- the face: a soft disc, lighter in the middle, with the shadow the hood above it throws
	arr, d = radial(L.w * SS, L.h * SS, (c[0] * SS, c[1] * SS), R * SS, hexc(st["face"][0]), hexc(st["face"][1]))
	yy = np.mgrid[0:L.h * SS, 0:L.w * SS][0].astype(np.float32) / SS
	hood = 1.0 - 0.55 * np.clip(((c[1] - R * 0.05) - yy) / (R * 0.95), 0, 1) ** 1.6
	arr = arr * hood[..., None]
	disc = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGB")
	mask = Image.new("L", disc.size, 0)
	ImageDraw.Draw(mask).ellipse([(c[0] - R) * SS, (c[1] - R) * SS, (c[0] + R) * SS, (c[1] + R) * SS], fill=255)
	L.img.paste(disc, (0, 0), mask)
	# --- light-guide rings around the rim
	if st["rings"] >= 1:
		M.circle(c, R * 0.925, mul(acc, 0.85), width=R * 0.012)
	if st["rings"] >= 2:
		M.circle(c, R * 0.80, mul(ink, 0.35), width=R * 0.006)
	# --- the scale
	if kind == "speed":
		top, major_every, minor_every = 300.0, 30.0, 10.0
		labels = [(v, str(int(v))) for v in range(0, 301, 30)]
	else:
		top, major_every, minor_every = tmax / 1000.0, 1.0, 0.5
		labels = [(v, str(int(v))) for v in range(0, int(top) + 1)]
	r_out = R * 0.865
	n = int(round(top / minor_every))
	red_from = (redline / 1000.0) if kind == "tach" else None
	for i in range(n + 1):
		v = i * minor_every
		f = v / top
		is_major = abs((v / major_every) - round(v / major_every)) < 1e-6
		in_red = red_from is not None and v >= red_from - 1e-6
		col = RED if in_red else (acc if (is_major and st.get("accent_ticks")) else ink)
		if is_major:
			p0, p1, w = on_dial(c, r_out, f), on_dial(c, r_out - R * 0.125, f), R * st["major"]
		else:
			if st["minor"] <= 0.0:
				continue
			p0, p1, w = on_dial(c, r_out, f), on_dial(c, r_out - R * 0.065, f), R * st["minor"]
		M.line(p0, p1, col, w)
	if kind == "tach":  # the redline: a band round the outside of the scale from the red mark to the end
		M.arc_band(c, R * 0.885, R * 0.915, ang(red_from / top), ang(1.0), RED)
	if st.get("segments") and kind == "tach":  # track cars: a bar of lit segments under the numerals
		for i in range(int(top * 2)):
			v0 = i / 2.0
			if v0 >= top:
				break
			f0, f1 = v0 / top + 0.004, (v0 + 0.5) / top - 0.004
			col = RED if v0 >= red_from - 1e-6 else mul(acc, 0.55)
			M.arc_band(c, R * 0.47, R * 0.53, ang(f0), ang(f1), col, steps=6)
	for v, s in labels:
		f = v / top
		in_red = red_from is not None and v >= red_from - 1e-6
		M.text(on_dial(c, R * 0.655, f), s, font, R * st["num"] * (1.15 if kind == "tach" else 1.0), RED if in_red else ink)
	# --- units, the mph ring, the mini gauge
	if kind == "speed":
		M.text((c[0], c[1] + R * 0.30), "km/h", "inter_l", R * 0.115, mul(ink, 0.8))
		if st["mph"]:
			for mph in range(20, 181, 20):
				f = mph * 1.609344 / top
				M.text(on_dial(c, R * 0.435, f), str(mph), "inter_l", R * 0.082, mul(acc, 0.9))
			for mph in range(10, 181, 10):
				f = mph * 1.609344 / top
				M.line(on_dial(c, R * 0.515, f), on_dial(c, R * 0.545, f), mul(acc, 0.7), R * 0.008)
	else:
		M.text((c[0], c[1] + R * 0.30), "x1000 r/min", "inter_l", R * 0.105, mul(ink, 0.8))
	if st["mini"]:
		yb = c[1] + R * 0.62
		labels2 = ("E", "F") if kind == "speed" else ("C", "H")
		w = R * 0.62
		M.text((c[0] - w * 0.62, yb), labels2[0], "inter_l", R * 0.085, mul(ink, 0.75))
		M.text((c[0] + w * 0.62, yb), labels2[1], "inter_l", R * 0.085, mul(ink, 0.75))
		for i in range(5):
			x0 = c[0] - w * 0.42 + i * w * 0.2
			lit = i < (3 if kind == "speed" else 2)
			M.rrect((x0, yb - R * 0.045, x0 + w * 0.15, yb + R * 0.045), R * 0.012, (mul(acc, 0.9) if lit else mul(ink, 0.18)))
		# a pump or a thermometer above the bar
		if kind == "speed":
			px, py, s = c[0], yb - R * 0.15, R * 0.075
			M.rrect((px - s, py - s, px + s * 0.4, py + s), s * 0.2, mul(ink, 0.55))
			M.line((px + s * 0.4, py - s * 0.4), (px + s * 1.1, py + s * 0.1), mul(ink, 0.55), R * 0.014)
		else:
			px, py, s = c[0], yb - R * 0.15, R * 0.07
			M.rrect((px - s * 0.22, py - s, px + s * 0.22, py + s * 0.5), s * 0.2, mul(ink, 0.55))
			M.circle((px, py + s * 0.62), s * 0.45, mul(ink, 0.55))


def icon(M, kind, c, s, col):
	x, y = c
	w = max(1.0, s * 0.10)
	if kind == "engine":
		M.poly([(x - 0.5 * s, y - 0.2 * s), (x - 0.18 * s, y - 0.2 * s), (x - 0.18 * s, y - 0.36 * s), (x + 0.28 * s, y - 0.36 * s),
			(x + 0.28 * s, y - 0.2 * s), (x + 0.5 * s, y - 0.2 * s), (x + 0.5 * s, y + 0.28 * s), (x - 0.34 * s, y + 0.28 * s), (x - 0.5 * s, y + 0.1 * s)], col)
	elif kind == "oil":
		M.poly([(x - 0.5 * s, y + 0.05 * s), (x - 0.2 * s, y - 0.2 * s), (x + 0.25 * s, y - 0.2 * s), (x + 0.5 * s, y - 0.3 * s),
			(x + 0.5 * s, y - 0.12 * s), (x + 0.3 * s, y + 0.3 * s), (x - 0.35 * s, y + 0.3 * s)], col)
	elif kind == "battery":
		M.rrect((x - 0.5 * s, y - 0.28 * s, x + 0.5 * s, y + 0.3 * s), s * 0.06, col, width=w)
		M.rrect((x - 0.36 * s, y - 0.42 * s, x - 0.18 * s, y - 0.28 * s), 0, col)
		M.rrect((x + 0.18 * s, y - 0.42 * s, x + 0.36 * s, y - 0.28 * s), 0, col)
	elif kind == "abs":
		M.circle((x, y), s * 0.5, col, width=w)
		M.text((x, y), "ABS", "inter_b", s * 0.3, col)
	elif kind == "brake":
		M.circle((x, y), s * 0.5, col, width=w)
		M.text((x, y + s * 0.02), "!", "inter_b", s * 0.62, col)
	elif kind == "belt":
		M.circle((x, y - 0.3 * s), s * 0.14, col)
		M.line((x - 0.12 * s, y - 0.1 * s), (x + 0.36 * s, y + 0.42 * s), col, w * 1.6)
		M.line((x - 0.3 * s, y + 0.1 * s), (x + 0.1 * s, y + 0.42 * s), col, w * 1.2)
	elif kind == "beam":
		M.poly([(x - 0.1 * s, y - 0.4 * s), (x + 0.1 * s, y - 0.4 * s), (x + 0.42 * s, y - 0.3 * s), (x + 0.42 * s, y + 0.3 * s), (x + 0.1 * s, y + 0.4 * s), (x - 0.1 * s, y + 0.4 * s)], col)
		for k in range(4):
			M.line((x - 0.22 * s, y - 0.3 * s + k * 0.2 * s), (x - 0.5 * s, y - 0.22 * s + k * 0.2 * s), col, w)


def make_cluster(car):
	st = STYLES[STYLE_OF.get(car["shape"], "modern")]
	cab = car["cab"]
	cols = cab.get("dials", ["#f5b52e", "#e6e6e6", "#ff4a2a"])
	L = Layer(CW, CH, (4, 4, 5))
	M = Layer(CW, CH, (0, 0, 0))
	tmax = tach_max(car["redline"])
	draw_dial(L, M, (DIAL_CX[0], DIAL_CY), "tach", st, cols, tmax, car["redline"])
	draw_dial(L, M, (DIAL_CX[1], DIAL_CY), "speed", st, cols, tmax, car["redline"])
	acc = hexc(cols[0])
	ink = hexc(cols[1])
	# --- the window between the dials that holds the gear and speed readout
	wx0, wx1, wy0, wy1 = 384, 640, 70, 250
	L.rrect((wx0, wy0, wx1, wy1), 14, (7, 9, 11))
	M.rrect((wx0, wy0, wx1, wy1), 14, mul(acc, 0.32), width=1.6)
	M.line((wx0 + 22, wy0 + 52), (wx1 - 22, wy0 + 52), mul(acc, 0.22), 1.2)  # the strip the gear sits on
	# --- warning lamps, unlit
	lamps = ["engine", "oil", "battery", "abs", "brake", "belt", "beam"]
	for i, k in enumerate(lamps):
		icon(M, k, (512 + (i - 3) * 40, 322), 25, mul(ink, 0.22))
	if st.get("segments"):  # shift lights along the top
		for i in range(11):
			t = i / 10.0
			col = (60, 200, 90) if t < 0.5 else ((230, 190, 40) if t < 0.8 else (230, 50, 40))
			M.circle((512 + (i - 5) * 24, 28), 6.5, mul(col, 0.3))
	# glow: the marks bleed a little light, as backlit print does
	glow = M.img.filter(ImageFilter.GaussianBlur(radius=3.0 * SS))
	base = L.array() + M.array() + np.asarray(glow, np.float32) / 255.0 * 0.45
	im = Image.fromarray(np.clip(base * 255.0, 0, 255).astype(np.uint8), "RGB").resize((CW, CH), Image.LANCZOS)
	# rounded corners: the panel is cut out of its rectangle
	alpha = Image.new("L", (CW * 2, CH * 2), 0)
	ImageDraw.Draw(alpha).rounded_rectangle([0, 0, CW * 2 - 1, CH * 2 - 1], radius=70, fill=255)
	alpha = alpha.resize((CW, CH), Image.LANCZOS)
	im.putalpha(alpha)
	return im


# ------------------------------------------------------------------ infotainment screens

def road_map(M, box, acc, seed):
	"""A little night-mode sat-nav map in `box`: blocks, parks, roads, the route and the car."""
	x0, y0, x1, y1 = box
	rng = np.random.default_rng(seed)
	w, h = x1 - x0, y1 - y0
	M.d.rectangle([x0 * SS, y0 * SS, x1 * SS, y1 * SS], fill=(10, 20, 31))
	for _ in range(46):  # city blocks
		bx, by = x0 + rng.random() * w, y0 + rng.random() * h
		bw, bh = 6 + rng.random() * w * 0.12, 6 + rng.random() * h * 0.14
		M.d.rectangle([bx * SS, by * SS, min(x1, bx + bw) * SS, min(y1, by + bh) * SS], fill=(14, 29, 44))
	for _ in range(4):  # parks
		bx, by = x0 + rng.random() * w * 0.8, y0 + rng.random() * h * 0.8
		M.rrect((bx, by, min(x1, bx + w * 0.16), min(y1, by + h * 0.18)), 5, (14, 44, 34))
	for k in range(6):  # side streets
		yy = y0 + h * (0.12 + k * 0.16 + rng.random() * 0.04)
		M.line((x0, yy), (x1, yy + (rng.random() - 0.5) * h * 0.12), (34, 56, 78), 2.0)
		xx = x0 + w * (0.08 + k * 0.17 + rng.random() * 0.04)
		M.line((xx, y0), (xx + (rng.random() - 0.5) * w * 0.1, y1), (34, 56, 78), 2.0)
	# the main road and the route along it, with the car on it
	pts = [(x0 + w * 0.5, y1), (x0 + w * 0.5, y0 + h * 0.62), (x0 + w * 0.62, y0 + h * 0.4), (x0 + w * 0.62, y0 + h * 0.12), (x0 + w * 0.78, y0)]
	for a, b in zip(pts, pts[1:]):
		M.line(a, b, (58, 84, 108), 8.0)
	for a, b in zip(pts, pts[1:]):
		M.line(a, b, acc, 4.0)
	cx, cy = x0 + w * 0.5, y0 + h * 0.84
	M.circle((cx, cy), 9, (230, 240, 255))
	M.poly([(cx, cy - 15), (cx + 9, cy + 6), (cx, cy + 2), (cx - 9, cy + 6)], acc)
	M.circle((x0 + w * 0.78, y0 + 5), 6, (255, 255, 255))


def make_screen(car):
	cab = car["cab"]
	kind = cab.get("screen", "wide")
	acc = hexc(cab.get("accent", cab.get("ambient", "#4aa3ff")))
	seed = abs(hash(car["shape"])) % 1000
	if kind == "retro":
		W, H = 512, 181
		L = Layer(W, H, (16, 12, 8))
		L.rrect((6, 6, W - 7, H - 7), 10, (26, 20, 13))
		L.rrect((6, 6, W - 7, H - 7), 10, (92, 74, 48), width=2.0)
		amber = (255, 170, 60)
		y = 148
		L.line((24, y), (W - 24, y), mul(amber, 0.5), 2.0)
		for i in range(0, 41):
			x = 24 + (W - 48) * i / 40.0
			big = i % 5 == 0
			L.line((x, y), (x, y - (14 if big else 7)), mul(amber, 0.8 if big else 0.5), 2.0 if big else 1.2)
			if big:
				L.text((x, y + 14), str(88 + i // 2), "plain_b", 15, mul(amber, 0.85))
		px = 24 + (W - 48) * (98.4 - 88) / 20.0
		L.line((px, y + 4), (px, 20), (255, 60, 40), 3.0)
		return L.final()
	W, H = (512, 297) if kind == "wide" else (256, 376)
	L = Layer(W, H, (8, 12, 18))
	L.rrect((3, 3, W - 4, H - 4), 8, (11, 18, 27))
	# the card the radio text prints on (the text itself is a Label3D)
	if kind == "wide":
		card = (14, 12, W - 14, 118)
		map_box = (14, 128, W - 14, H - 34)
	else:
		card = (10, 10, W - 10, 132)
		map_box = (10, 142, W - 10, H - 40)
	L.rrect(card, 8, (14, 26, 40))
	L.rrect((card[0], card[1] + 10, card[0] + 4, card[3] - 10), 2, acc)
	road_map(L, map_box, acc, seed)
	L.rrect(map_box, 4, (40, 70, 98), width=1.5)
	# a status bar and four soft buttons
	L.text((W - 18, H - 17), "12 min", "inter_b", 14, (210, 225, 240), anchor="rm")
	for i in range(4):
		x = 22 + i * 34
		L.rrect((x, H - 28, x + 24, H - 8), 5, mul(acc, 0.55) if i == 0 else (28, 44, 60))
	return L.final()


# ------------------------------------------------------------------ trim finishes

def periodic_noise(n, rng, octaves=((2, 1.0), (4, 0.5), (8, 0.25), (16, 0.12))):
	"""Smooth noise that tiles: sums of low whole-number frequencies."""
	yy, xx = np.mgrid[0:n, 0:n].astype(np.float32) / n
	out = np.zeros((n, n), np.float32)
	for f, a in octaves:
		for _ in range(3):
			kx, ky = rng.integers(0, f + 1), rng.integers(0, f + 1)
			ph = rng.random() * math.tau
			out += a * np.cos(math.tau * (kx * xx + ky * yy) + ph)
	return out / (np.abs(out).max() + 1e-6)


def save_gray(arr, name, tint=(1.0, 1.0, 1.0)):
	rgb = np.stack([np.clip(arr * t, 0, 1) for t in tint], -1)
	Image.fromarray((rgb * 255).astype(np.uint8), "RGB").save(os.path.join(OUT, name))


def make_trim():
	n = 256
	rng = np.random.default_rng(7)
	yy, xx = np.mgrid[0:n, 0:n].astype(np.float32)
	# carbon fibre: a 2x2 twill, each fibre lit across its width
	c = 8
	i, j = (xx // c).astype(int), (yy // c).astype(int)
	fx, fy = (xx % c) / c, (yy % c) / c
	horiz = ((i + j) % 4) < 2
	across = np.where(horiz, fy, fx)
	shade = 0.30 + 0.55 * np.sin(across * math.pi) ** 1.5
	shade = shade * (0.9 + 0.1 * periodic_noise(n, rng))
	save_gray(shade * 0.62, "trim_carbon.png", (1.0, 1.0, 1.04))
	# brushed metal: long horizontal scratches
	rows = rng.random((n, 1)).astype(np.float32)
	streak = np.tile(rows, (1, n))
	k = np.zeros(n, np.float32)
	k[:41] = 1.0
	streak = np.real(np.fft.ifft(np.fft.fft(streak, axis=1) * np.fft.fft(k)[None, :], axis=1)) / 41.0
	fine = rng.random((n, n)).astype(np.float32) * 0.5 + np.tile(rng.random((n, 1)).astype(np.float32), (1, n)) * 0.5
	brushed = 0.80 + 0.30 * (streak - 0.5) + 0.07 * (fine - 0.5)
	save_gray(brushed * 0.85, "trim_brushed.png", (1.0, 1.0, 1.03))
	# wood: open-pore walnut, grain running along the strip
	warp = periodic_noise(n, rng, ((1, 1.0), (2, 0.6), (3, 0.35)))
	g = np.sin(math.tau * (yy / n * 9.0 + warp * 0.9 + 0.03 * np.sin(xx / n * math.tau * 2.0)))
	g2 = np.sin(math.tau * (yy / n * 23.0 + warp * 1.6))
	pores = (rng.random((n, n)) > 0.985).astype(np.float32)
	pores = np.real(np.fft.ifft(np.fft.fft(pores, axis=1) * np.fft.fft(np.r_[np.ones(6), np.zeros(n - 6)])[None, :], axis=1))
	tone = 0.52 + 0.20 * g + 0.08 * g2 - 0.25 * np.clip(pores, 0, 1)
	save_gray(np.clip(tone, 0.12, 0.9), "trim_wood.png", (1.0, 0.78, 0.55))


def make_glare():
	"""The faint reflection on the glass over the dials: two soft diagonal bands across each dial, as white with alpha
	(the game lays it over the panel with additive blending)."""
	w, h = 512, 192
	yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
	a = np.zeros((h, w), np.float32)
	r = DIAL_R / 2.0
	for cx in (DIAL_CX[0] / 2.0, DIAL_CX[1] / 2.0):
		cy = DIAL_CY / 2.0
		dx, dy = xx - cx, yy - cy
		inside = np.clip((r * 0.97 - np.sqrt(dx * dx + dy * dy)) / 2.0, 0, 1)
		d = (dx * 0.87 + dy * 0.5) / r  # across the bands
		band = np.exp(-((d + 0.55) / 0.34) ** 2) * 0.95 + np.exp(-((d + 0.05) / 0.12) ** 2) * 0.5
		fade = np.clip(1.0 - (dy / r + 1.0) / 1.6, 0.25, 1.0)  # stronger towards the top
		a = np.maximum(a, band * fade * inside * 0.16)
	img = np.zeros((h, w, 4), np.uint8)
	img[..., :3] = 255
	img[..., 3] = np.clip(a * 255, 0, 255).astype(np.uint8)
	Image.fromarray(img, "RGBA").save(os.path.join(OUT, "cluster_glare.png"), optimize=True)


def main():
	os.makedirs(OUT, exist_ok=True)
	cars = read_game()
	assert len(cars) == 12, "expected the 12 cars of scripts/data.gd, found %d" % len(cars)
	only = sys.argv[1] if len(sys.argv) > 1 else ""
	for car in cars:
		if only and only not in ("cluster", "screens", car["shape"]):
			continue
		if only in ("", "cluster", car["shape"]):
			make_cluster(car).save(os.path.join(OUT, "cluster_%s.png" % car["shape"]), optimize=True)
		if only in ("", "screens", car["shape"]):
			make_screen(car).save(os.path.join(OUT, "screen_%s.png" % car["shape"]), optimize=True)
		print(car["shape"], "tach to", tach_max(car["redline"]) // 1000, "redline", car["redline"])
	if only in ("", "trim"):
		make_trim()
		make_glare()


if __name__ == "__main__":
	main()
