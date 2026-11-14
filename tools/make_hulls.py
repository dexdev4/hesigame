#!/usr/bin/env python3
"""Outlines of every car seen from above, for the game's hit boxes
(scripts/hulls.gd).

A hit box has to follow the car it belongs to: a tapering nose, the rounded
tail corners and the wheel-arch flares are all places where one car can
touch another without the rectangle of its length and width being touched.
So for every shape the lower body (below the beltline, which leaves out the
mirrors and the roof) is flattened onto the road, its convex outline is
taken, mirrored so the two sides match, and cut down to a handful of corners
(at most 7 per side) with the least loss of area. The corners are in metres:
x across the car, d from the rear bumper forwards. The truck is two pieces,
the box and the cab, because its outline is not convex.

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
BODY_KINDS = ["paint", "gloss", "glass", "under", "dark", "tail", "head", "chrome"]
BAND = (0.15, 0.62)        # heights of the lower body, metres (mirrors sit above it)
MAX_PER_SIDE = 7           # corners per side after simplification


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


def outline(pts, keep=MAX_PER_SIDE):
    """Symmetric convex outline (list of (x, d), counter-clockwise from the rear right) of points (x, d)."""
    m = np.vstack([pts, pts * np.array([-1.0, 1.0])])
    h = hull(m)
    right = [p for p in h if p[0] > 1e-4]
    right.sort(key=lambda p: p[1])
    # the front and rear ends are flat edges across the middle when the hull has no corner on the centre line
    right = simplify_side(right, keep)
    left = [(-p[0], p[1]) for p in reversed(right)]
    out = [(round(p[0], 3), round(p[1], 3)) for p in right + left]
    return out


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


def build(sid, prof, wl):
    surf = mi.read_cpe2(os.path.join(ROOT, prof["mesh"]))
    w, length = wl
    if sid == "truck":
        # box (everything behind the cab) and cab (its lower body, without the mirrors)
        cut = 8.6
        box = body_points(surf, BODY_KINDS + ["cargo"], d_hi=cut + 0.05, band=None)
        cab = body_points(surf, BODY_KINDS, d_lo=cut - 0.05, band=(0.15, 1.3))
        parts = [outline(box, 4), outline(cab, 6)]
    else:
        parts = [outline(body_points(surf, BODY_KINDS))]
    # keep to the nominal length: the model's lamps and trim stand a centimetre or two outside it
    fixed = []
    for part in parts:
        fixed.append([(x, min(max(d, 0.0), length)) for x, d in part])
    return fixed


def fmt(parts):
    return "[" + ", ".join("[" + ", ".join("%g, %g" % (x, d) for x, d in p) + "]" for p in parts) + "]"


def main():
    prof = profiles()
    sh = shapes()
    out = ["class_name Hulls", "extends RefCounted",
           "## Each car's outline seen from above, for its hit box. GENERATED by tools/make_hulls.py from the",
           "## car models: do not edit by hand. `parts` are convex outlines as flat x, d lists (metres: x across",
           "## the car, d from the rear bumper forwards), `axles` the rear and front axle's d, `track` half the",
           "## distance between the wheels.", "", "const DATA := {"]
    sheet = {}
    for sid in sorted(prof):
        wl = sh[sid]
        parts = build(sid, prof[sid], wl)
        wheel = prof[sid].get("wheel", [0.35, 0.8, wl[1] - 0.9])
        wx = prof[sid].get("wheel_x", [wl[0] / 2.0 - 0.12, wl[0] / 2.0 - 0.12])
        out.append('\t"%s": {"parts": %s, "axles": [%g, %g], "track": %g},' % (sid, fmt(parts), wheel[1], wheel[2], round(sum(wx) / len(wx), 3)))
        sheet[sid] = (parts, wheel, wx, wl)
        n = sum(len(p) for p in parts)
        print("%-12s %2d corners  width %.2f (shape %.2f)  length %.2f (shape %.2f)" % (
            sid, n, 2 * max(abs(x) for p in parts for x, _ in p), wl[0], max(d for p in parts for _, d in p), wl[1]))
    out.append("}")
    out.append("")
    open(os.path.join(ROOT, "scripts", "hulls.gd"), "w").write("\n".join(out))
    if "--sheet" in sys.argv:
        draw_sheet(sheet, sys.argv[sys.argv.index("--sheet") + 1], prof)


def draw_sheet(sheet, path, prof):
    from PIL import Image, ImageDraw
    ids = [k for k in ("kestrel", "halcyon", "vanta", "suv", "van", "hatch", "hyper", "muscle", "truck") if k in sheet]
    scale = 70.0
    cell_w, cell_h = 330, 560
    img = Image.new("RGB", (cell_w * min(len(ids), 5), cell_h * ((len(ids) + 4) // 5)), (24, 26, 30))
    dr = ImageDraw.Draw(img)
    for i, sid in enumerate(ids):
        parts, wheel, wx, wl = sheet[sid]
        ox = (i % 5) * cell_w + cell_w / 2
        oy = (i // 5) * cell_h + cell_h - 30
        sc = scale if wl[1] < 6 else 40.0
        surf = mi.read_cpe2(os.path.join(ROOT, prof[sid]["mesh"]))
        for k, (p, n, ix) in surf.items():
            pp = p[np.unique(ix)]
            for x, z in zip(pp[::3, 0], -pp[::3, 2]):
                dr.point((ox + x * sc, oy - z * sc), fill=(90, 96, 110))
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
