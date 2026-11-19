#!/usr/bin/env python3
"""Outlines of every car seen from above, for the game's hit boxes
(scripts/hulls.gd).

A hit box has to follow the car it belongs to: a tapering nose, the rounded
tail corners and the wheel-arch flares are all places where one car can
touch another without the rectangle of its length and width being touched.
So for every shape the whole body below the beltline (from just above the
road to just under the side windows: bumpers, flares, lamps, plates, push
bars, exhausts) and the tyres are flattened onto the road, the convex outline
is taken, mirrored so the two sides match, and cut down to at most 14 corners
a side, always dropping the one that loses the least area. The door mirrors,
which stand out past that outline above the beltline, are pieces of their own
(one each side, under "mirrors": they meet other cars, not the guardrails,
which they stand above). The corners are in metres: x across the car, d from the rear
bumper forwards. The truck is two pieces, the box and the cab, because its
outline is not convex.

Also written: the axle positions and track the wheels' road contact uses.

Usage: python3 tools/make_hulls.py            (writes scripts/hulls.gd)
       python3 tools/make_hulls.py --sheet X  (also draws a contact sheet PNG)
"""
import os
import re
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import make_inner as mi  # noqa: E402  (read_cpe2)

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, ".."))
BODY_KINDS = ["paint", "gloss", "glass", "under", "dark", "tail", "head", "chrome", "grille", "plate", "headlens"]
BAND = (0.15, 0.62)        # heights of the lower body, metres, for a car whose profile has no beltline (the truck)
LOW = 0.06                 # below this only the tyres reach (and they count anyway)
MAX_PER_SIDE = 14          # corners per side after simplification
MIRROR_CORNERS = 6


def profiles():
    """shape id -> {mesh, wheel [r, rear_d, front_d], wheel_x} from car_model.gd's PROFILES."""
    s = open(os.path.join(ROOT, "scripts", "car_model.gd")).read()
    blk = s[s.index("const PROFILES"):]
    out = {}
    cur = None
    for line in blk.split("\n"):
        m = re.match(r'\t"(\w+)":\s*\{', line)
        if m:
            cur = m.group(1)
            out[cur] = {}
        if cur:
            m = re.search(r'"mesh": "res://([^"]+)"', line)
            if m:
                out[cur]["mesh"] = m.group(1)
            m = re.search(r'"wheel": \[([^\]]*)\]', line)
            if m:
                out[cur]["wheel"] = [float(v) for v in m.group(1).split(",")]
            m = re.search(r'"wheel_x": \[([^\]]*)\]', line)
            if m:
                out[cur]["wheel_x"] = [float(v) for v in m.group(1).split(",")]
            m = re.search(r'"gh": \[([^\]]*)\]', line)
            if m:
                out[cur]["gh"] = [float(v) for v in m.group(1).split(",")]
            m = re.search(r'"parts": "res://([^"]+)"', line)
            if m:
                out[cur]["parts"] = m.group(1)
        if line.startswith("static") or line.startswith("func"):
            break
    return {k: v for k, v in out.items() if "mesh" in v}


def shapes():
    s = open(os.path.join(ROOT, "scripts", "data.gd")).read()
    return {a: (float(b), float(c)) for a, b, c in re.findall(r'"(\w+)":\s*\{"w": ([0-9.]+), "l": ([0-9.]+)', s)}


def hull(pts):
    """Convex hull (Andrew's monotone chain), counter-clockwise, of an (n, 2) array."""
    pts = sorted(set(map(tuple, np.round(pts, 4))))
    if len(pts) < 3:
        return np.array(pts)

    def cross(o, a, b):
        return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])

    lo = []
    for p in pts:
        while len(lo) >= 2 and cross(lo[-2], lo[-1], p) <= 0:
            lo.pop()
        lo.append(p)
    up = []
    for p in reversed(pts):
        while len(up) >= 2 and cross(up[-2], up[-1], p) <= 0:
            up.pop()
        up.append(p)
    return np.array(lo[:-1] + up[:-1])


def area(poly):
    x, y = poly[:, 0], poly[:, 1]
    return 0.5 * float(np.sum(x * np.roll(y, -1) - np.roll(x, -1) * y))


def simplify_side(chain, keep):
    """Drop corners of a convex chain, always the one that loses the least area, down to `keep`."""
    chain = [tuple(p) for p in chain]
    while len(chain) > keep:
        best, best_a = None, 1e9
        for i in range(1, len(chain) - 1):
            a, b, c = chain[i - 1], chain[i], chain[i + 1]
            ar = abs((b[0] - a[0]) * (c[1] - a[1]) - (c[0] - a[0]) * (b[1] - a[1])) / 2.0
            if ar < best_a:
                best, best_a = i, ar
        chain.pop(best)
    return chain


def clip(poly, n, c):
    """The part of a convex polygon where n . p <= c."""
    out = []
    for i in range(len(poly)):
        a, b = poly[i], poly[(i + 1) % len(poly)]
        fa, fb = n[0] * a[0] + n[1] * a[1] - c, n[0] * b[0] + n[1] * b[1] - c
        if fa <= 0:
            out.append(a)
        if (fa <= 0) != (fb <= 0):
            t = fa / (fa - fb)
            out.append((a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t))
    return out


def fit_out(simple, pts, d_range=None):
    """The simplified outline's edges moved out until every point is inside them: an outline with no more corners that
    holds the whole car (dropping a corner alone would cut a sliver off it), counter-clockwise; d kept to d_range."""
    poly = [(-9.0, -9.0), (9.0, -9.0), (9.0, 30.0), (-9.0, 30.0)]
    n_ = len(simple)
    area2 = sum(simple[i][0] * simple[(i + 1) % n_][1] - simple[(i + 1) % n_][0] * simple[i][1] for i in range(n_))
    sgn = 1.0 if area2 > 0 else -1.0
    for i in range(n_):
        a, b = np.array(simple[i]), np.array(simple[(i + 1) % n_])
        e = b - a
        ln = float(np.hypot(*e))
        if ln < 1e-6:
            continue
        nrm = np.array([e[1], -e[0]]) * sgn / ln   # outward
        poly = clip(poly, nrm, float((pts @ nrm).max()))
    if d_range:
        poly = clip(poly, (0.0, -1.0), -d_range[0])
        poly = clip(poly, (0.0, 1.0), d_range[1])
    out = []
    for x, d in poly:   # (rounded outwards, and corners that came out the same dropped)
        q = (round(x + (0.0005 if x > 0 else -0.0005), 3), round(d, 3))
        if not out or abs(q[0] - out[-1][0]) + abs(q[1] - out[-1][1]) > 0.002:
            out.append(q)
    if len(out) > 2 and abs(out[0][0] - out[-1][0]) + abs(out[0][1] - out[-1][1]) <= 0.002:
        out.pop()
    return out


def outline(pts, keep=MAX_PER_SIDE, d_range=None):
    """Symmetric convex outline (list of (x, d), counter-clockwise) holding all the points (x, d)."""
    m = np.vstack([pts, pts * np.array([-1.0, 1.0])])
    h = hull(m)
    right = [p for p in h if p[0] > 1e-4]
    right.sort(key=lambda p: p[1])
    # the front and rear ends are flat edges across the middle when the hull has no corner on the centre line
    right = simplify_side(right, keep)
    left = [(-p[0], p[1]) for p in reversed(right)]
    return fit_out([tuple(p) for p in right + left], h, d_range)


def body_points(surf, kinds, d_lo=None, d_hi=None, band=BAND):
    out = []
    for k in kinds:
        if k not in surf:
            continue
        p = surf[k][0][np.unique(surf[k][2])]
        d = -p[:, 2]
        m = np.ones(len(p), bool)
        if band:
            m &= (p[:, 1] >= band[0]) & (p[:, 1] <= band[1])
        if d_lo is not None:
            m &= d >= d_lo
        if d_hi is not None:
            m &= d <= d_hi
        out.append(np.stack([p[m, 0], d[m]], 1))
    return np.vstack(out)


def tyres(prof):
    """The tyres of a model with its own wheels, seen from above: four corners each (x, d)."""
    if "parts" not in prof:
        return np.zeros((0, 2))
    import json
    base = os.path.join(ROOT, prof["parts"])
    man = json.load(open(os.path.join(base, "parts.json")))
    out = []
    for w in man.get("wheels", []):
        surf = mi.read_cpe2(os.path.join(base, w["file"]))
        p = np.vstack([v[0] for v in surf.values()])
        x0, x1 = p[:, 0].min() + w["pos"][0], p[:, 0].max() + w["pos"][0]
        r = float(np.abs(p[:, 1:]).max())
        d = -w["pos"][2]
        out += [(x0, d - r), (x1, d - r), (x1, d + r), (x0, d + r)]
    return np.array(out)


def inside(poly, p, tol=0.01):
    """Is point p within tol of the convex counter-clockwise outline poly (or inside it)?"""
    n = len(poly)
    for i in range(n):
        a, b = np.array(poly[i]), np.array(poly[(i + 1) % n])
        e = b - a
        if e[0] * (p[1] - a[1]) - e[1] * (p[0] - a[0]) < -tol * np.hypot(*e):
            return False
    return True


def edge_x(poly, d):
    """How far out (x) a symmetric convex outline reaches at d."""
    best = 0.0
    for i in range(len(poly)):
        (x0, d0), (x1, d1) = poly[i], poly[(i + 1) % len(poly)]
        if min(d0, d1) <= d <= max(d0, d1):
            best = max(best, x0 if d1 == d0 else x0 + (x1 - x0) * (d - d0) / (d1 - d0))
    return best


def mirror_piece(out, body):
    """A convex piece each side round the door mirrors' points (x, d) (both sides alike), reaching 2 cm into the body's
    outline all along it, so the mirror's stalk between the two is in one or the other."""
    if len(out) < 6:
        return []
    side = out[out[:, 0] > 0]
    side = np.vstack([side, out[out[:, 0] < 0] * np.array([-1.0, 1.0])])   # (both sides alike)
    root = np.array([(edge_x(body, d) - 0.02, d) for d in side[:, 1]])
    side = np.vstack([side, root])
    h = hull(side)
    if len(h) < 3:
        return []
    h = [tuple(p) for p in h]
    while len(h) > MIRROR_CORNERS:   # (the corner that loses the least area, as for the body)
        best, best_a = None, 1e9
        for i in range(len(h)):
            a, b, c = h[i - 1], h[i], h[(i + 1) % len(h)]
            ar = abs((b[0] - a[0]) * (c[1] - a[1]) - (c[0] - a[0]) * (b[1] - a[1])) / 2.0
            if ar < best_a:
                best, best_a = i, ar
        h.pop(best)
    right = fit_out(h, np.array(side))
    left = [(-x, d) for x, d in reversed(right)]
    return [right, left]


def build(sid, prof, wl):
    surf = mi.read_cpe2(os.path.join(ROOT, prof["mesh"]))
    w, length = wl
    if sid == "truck":
        # box (everything behind the cab) and cab (its lower body, without the mirrors)
        cut = 8.6
        box = body_points(surf, BODY_KINDS + ["cargo"], d_hi=cut + 0.05, band=None)
        cab = body_points(surf, BODY_KINDS, d_lo=cut - 0.05, band=(0.15, 1.3))
        parts = [outline(box, 4), outline(cab, 6)]
    elif "gh" in prof:
        # everything up to a little under the side windows, and the tyres; then of what stands higher, whatever reaches
        # out past that: the door mirrors (beside the front of the side windows) as pieces of their own, anything else
        # (high wings over the rear wheels, a rear wing's end plates) as part of the body
        gh = prof["gh"]
        top = gh[4] - 0.06
        low = np.vstack([body_points(surf, BODY_KINDS, band=(LOW, top)), tyres(prof).reshape(-1, 2)])
        base = outline(low)
        kinds = [k for k in BODY_KINDS if k != "glass"]
        high = body_points(surf, kinds, band=(top, 9.0))
        out = np.array([p for p in high if not inside(base, p)]).reshape(-1, 2)
        near = (out[:, 1] > gh[1] - 0.55) & (out[:, 1] < gh[1] + 0.4) if len(out) else np.zeros(0, bool)
        body = outline(np.vstack([low, out[~near]])) if (~near).any() else base
        parts = [body]
        prof["mirrors"] = mirror_piece(out[near] if near.any() else np.zeros((0, 2)), body)
    else:
        parts = [outline(body_points(surf, BODY_KINDS))]
    # keep to the nominal length (it is measured from the same model, so this only takes off rounding)
    return [fit_out(part, np.array(part), (0.0, length)) for part in parts]


def fmt(parts):
    return "[" + ", ".join("[" + ", ".join("%g, %g" % (x, d) for x, d in p) + "]" for p in parts) + "]"


def main():
    prof = profiles()
    sh = shapes()
    out = ["class_name Hulls", "extends RefCounted",
           "## Each car's outline seen from above, for its hit box. GENERATED by tools/make_hulls.py from the",
           "## car models: do not edit by hand. `parts` are convex outlines as flat x, d lists (metres: x across",
           "## the car, d from the rear bumper forwards), `mirrors` the door mirrors' outlines (they stand out past the",
           "## body above the beltline: they meet other cars, not the guardrails), `axles` the rear and front axle's d,",
           "## `track` half the distance between the wheels.", "", "const DATA := {"]
    sheet = {}
    for sid in sorted(prof):
        wl = sh[sid]
        parts = build(sid, prof[sid], wl)
        wheel = prof[sid].get("wheel", [0.35, 0.8, wl[1] - 0.9])
        wx = prof[sid].get("wheel_x", [wl[0] / 2.0 - 0.12, wl[0] / 2.0 - 0.12])
        mir = prof[sid].get("mirrors", [])
        out.append('\t"%s": {"parts": %s, %s"axles": [%g, %g], "track": %g},' % (sid, fmt(parts), ('"mirrors": %s, ' % fmt(mir)) if mir else "",
                                                                             wheel[1], wheel[2], round(sum(wx) / len(wx), 3)))
        sheet[sid] = (parts + mir, wheel, wx, wl)
        n = sum(len(p) for p in parts + mir)
        print("%-12s %2d corners  width %.2f (shape %.2f)  length %.2f (shape %.2f)" % (
            sid, n, 2 * max(abs(x) for p in parts for x, _ in p), wl[0], max(d for p in parts for _, d in p), wl[1]))
    out.append("}")
    out.append("")
    open(os.path.join(ROOT, "scripts", "hulls.gd"), "w").write("\n".join(out))
    if "--sheet" in sys.argv:
        draw_sheet(sheet, sys.argv[sys.argv.index("--sheet") + 1], prof)


def draw_sheet(sheet, path, prof):
    from PIL import Image, ImageDraw
    ids = [k for k in ("hot_hatch", "sport_sedan", "compact", "coupe", "kestrel", "vanta", "bruiser", "halcyon", "copperhead",
                       "marshal", "static", "lastexit", "sedan", "hatch", "suv", "van") if k in sheet]
    scale = 80.0
    cell_w, cell_h = 260, 500
    cols = 8
    img = Image.new("RGB", (cell_w * min(len(ids), cols), cell_h * ((len(ids) + cols - 1) // cols)), (24, 26, 30))
    dr = ImageDraw.Draw(img)
    for i, sid in enumerate(ids):
        parts, wheel, wx, wl = sheet[sid]
        ox = (i % cols) * cell_w + cell_w / 2
        oy = (i // cols) * cell_h + cell_h - 30
        sc = scale if wl[1] < 6 else 40.0
        surf = mi.read_cpe2(os.path.join(ROOT, prof[sid]["mesh"]))
        for k, (p, n, ix) in surf.items():
            pp = p[np.unique(ix)]
            for x, z in zip(pp[::2, 0], -pp[::2, 2]):
                dr.point((ox + x * sc, oy - z * sc), fill=(90, 96, 110))
        for x, d in tyres(prof[sid]):
            dr.point((ox + x * sc, oy - d * sc), fill=(200, 200, 90))
        for part in parts:
            pts = [(ox + x * sc, oy - d * sc) for x, d in part]
            dr.polygon(pts, outline=(255, 90, 60))
        for ax, d in ((0, wheel[1]), (1, wheel[2])):
            x = wx[min(ax, len(wx) - 1)]
            for sgn in (-1, 1):
                dr.rectangle((ox + sgn * x * sc - 4, oy - d * sc - wheel[0] * sc, ox + sgn * x * sc + 4, oy - d * sc + wheel[0] * sc), outline=(120, 200, 255))
        dr.text((ox - 40, oy + 8), "%s %.2f x %.2f" % (sid, wl[0], wl[1]), fill=(255, 255, 255))
    img.save(path)


if __name__ == "__main__":
    main()
