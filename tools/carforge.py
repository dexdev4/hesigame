#!/usr/bin/env python3
"""Car forge: builds the game's car bodies as high-detail meshes.

Each design below (one per car shape) gives proportions and styling. The body
is a smooth sweep of cross-sections from the rear bumper (d = 0) to the nose
(d = L) using the same shape rules as scripts/body_builder.gd (so the game's
cabin interior and cockpit fit inside it), but sampled far more finely and
splined, with:
  * glass, black window surrounds and frit cut into the greenhouse,
  * sculpted head and tail lamps (LED strips, projectors, smoked housings),
  * mesh grilles, intakes, diffusers and sill trim, refined along their edges,
  * panel gaps, flush handles, mirrors, wipers, exhausts, spoilers and wings
    added as fitted geometry,
  * a light version (far fewer triangles) for distance and traffic.

Output: assets/models/cars/<shape>.mesh and <shape>_lq.mesh in the CPE2 format
read by CarModel._mesh_kit (surfaces: paint, glass, gloss, dark, under,
chrome, head, tail, accent). Car space: x right, y up, z = -d; front faces
are anticlockwise seen from outside (the loader flips them for Godot).

Run:  python3 tools/carforge.py            (all designs)
      python3 tools/carforge.py hatch      (one design)
"""
import math
import struct
import sys
import os
import numpy as np

OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "models", "cars")

# ------------------------------------------------------------------ designs
# body / gh / pillars / wheel / tyre / corner / flare / fender / crease_h /
# tumble / roof_drop follow scripts/car_model.gd PROFILES (keep them in step).
# New keys:
#   head / tail: lamp shapes {"u": [inner, outer] (fraction of half width),
#     "lo": [y at inner, y at outer], "hi": [...], "drl": "top"|"L"|"ring"|"none",
#     "proj": n projector lenses, "bar": [y0, y1] full-width light bar (tail)}
#   round_head: [[u, y, r]] round lamps (rear-engine coupe)
#   grille: {"w": half width fraction, "y": [y0, y1], "kind": "mesh"|"bars"|"kidney"|"slot"}
#   intake: lower intake {"w", "y"}; side_intake: [d0, d1, y0, y1]
#   doors: door shut-line positions along d; handles: d of each handle
#   hood: "scoop"|"dome"|"vents"|None; stripes: True; spoiler: kind
#   exhaust: list of [x, y] tip centres (pairs mirror themselves)
DESIGNS = {
    "hatch": {
        "W": 1.76, "L": 4.0,
        "body": [[0.0, 0.84, 0.88], [0.08, 0.92, 0.95], [0.35, 0.97, 0.99], [1.2, 0.98, 1.0], [2.4, 0.95, 1.0], [3.15, 0.89, 1.0], [3.62, 0.84, 0.98], [3.9, 0.76, 0.93], [4.0, 0.66, 0.88]],
        "gh": [0.12, 3.12, 0.64, 2.22, 0.97, 1.43, 0.92, 0.74], "pillars": [[0.0, 0.24], [0.52, 0.57], [0.93, 1.0]],
        "roof_drop": 0.08, "wheel": [0.33, 0.78, 3.28], "tyre": [0.215, 0.215], "corner": [0.18, 0.3], "flare": [0.02, 0.02], "crease_h": 0.66, "tumble": 0.06,
        "head": {"u": [0.42, 0.93], "lo": [0.74, 0.72], "hi": [0.8, 0.84], "drl": "top", "proj": 1},
        "tail": {"u": [0.5, 0.98], "lo": [0.86, 0.86], "hi": [0.98, 1.0], "drl": "none"},
        "grille": {"w": 0.36, "y": [0.6, 0.72], "kind": "mesh"}, "intake": {"w": 0.62, "y": [0.24, 0.42]},
        "doors": [3.02, 2.02, 1.12], "handles": [2.2, 1.28], "spoiler": "roof", "exhaust": [[0.42, 0.26]], "sill": True,
    },
    "sedan": {
        "W": 1.84, "L": 4.7,
        "body": [[0.0, 0.86, 0.9], [0.1, 0.93, 0.96], [0.5, 0.98, 1.0], [1.2, 0.99, 1.0], [3.0, 0.96, 1.0], [3.7, 0.9, 1.0], [4.3, 0.84, 0.97], [4.6, 0.75, 0.92], [4.7, 0.66, 0.88]],
        "gh": [0.95, 3.56, 1.56, 2.76, 0.98, 1.41, 0.93, 0.78], "pillars": [[0.0, 0.14], [0.49, 0.53], [0.93, 1.0]],
        "roof_drop": 0.03, "wheel": [0.335, 0.98, 3.8], "tyre": [0.235, 0.235], "corner": [0.2, 0.3], "flare": [0.025, 0.02], "crease_h": 0.68, "tumble": 0.06,
        "head": {"u": [0.4, 0.94], "lo": [0.7, 0.7], "hi": [0.76, 0.81], "drl": "L", "proj": 2},
        "tail": {"u": [0.52, 0.99], "lo": [0.84, 0.84], "hi": [0.93, 0.96], "drl": "none", "bar": [0.88, 0.905]},
        "grille": {"w": 0.34, "y": [0.52, 0.7], "kind": "bars"}, "intake": {"w": 0.66, "y": [0.24, 0.4]},
        "doors": [3.48, 2.4, 1.28], "handles": [2.58, 1.45], "spoiler": "lip", "exhaust": [[0.52, 0.27], [-0.52, 0.27]], "sill": True, "splitter": True,
    },
    "suv": {
        "W": 1.96, "L": 4.8,
        "body": [[0.0, 1.0, 0.92], [0.12, 1.08, 0.98], [0.6, 1.12, 1.0], [3.6, 1.1, 1.0], [4.2, 1.04, 1.0], [4.62, 0.98, 0.96], [4.8, 0.88, 0.9]],
        "gh": [0.22, 3.9, 0.4, 3.25, 1.11, 1.78, 0.95, 0.86], "pillars": [[0.0, 0.1], [0.36, 0.4], [0.66, 0.7], [0.94, 1.0]],
        "roof_drop": 0.03, "wheel": [0.38, 0.92, 3.85], "tyre": [0.245, 0.245], "corner": [0.2, 0.28], "flare": [0.03, 0.03], "crease_h": 0.66, "tumble": 0.05,
        "head": {"u": [0.38, 0.95], "lo": [0.86, 0.84], "hi": [0.93, 0.98], "drl": "top", "proj": 2},
        "tail": {"u": [0.55, 0.99], "lo": [0.96, 0.96], "hi": [1.1, 1.12], "drl": "none"},
        "grille": {"w": 0.38, "y": [0.62, 0.84], "kind": "bars"}, "intake": {"w": 0.7, "y": [0.34, 0.5]},
        "doors": [3.75, 2.62, 1.45], "handles": [2.8, 1.62], "spoiler": "roof", "exhaust": [[0.5, 0.36]], "sill": True, "cladding": True, "rails": True,
    },
    "msedan": {
        "W": 1.82, "L": 4.58,
        "body": [[0.0, 0.8, 0.9], [0.08, 0.9, 0.96], [0.22, 0.96, 0.99], [0.85, 0.97, 1.0], [3.1, 0.94, 1.0], [3.6, 0.89, 1.0], [4.1, 0.85, 0.98], [4.44, 0.8, 0.94], [4.58, 0.7, 0.88]],
        "gh": [0.88, 3.12, 1.44, 2.44, 0.96, 1.43, 0.93, 0.78], "pillars": [[0.0, 0.16], [0.47, 0.51], [0.92, 1.0]],
        "roof_drop": 0.03, "wheel": [0.34, 0.98, 3.74], "tyre": [0.265, 0.245], "corner": [0.2, 0.28], "flare": [0.04, 0.035], "crease_h": 0.7, "tumble": 0.06,
        "head": {"u": [0.36, 0.92], "lo": [0.7, 0.7], "hi": [0.77, 0.81], "drl": "ring", "proj": 2},
        "tail": {"u": [0.5, 0.99], "lo": [0.82, 0.82], "hi": [0.9, 0.94], "drl": "L"},
        "grille": {"w": 0.3, "y": [0.56, 0.71], "kind": "kidney"}, "intake": {"w": 0.74, "y": [0.22, 0.42]},
        "doors": [3.05, 2.12, 1.18], "handles": [2.28, 1.34], "hood": "dome", "spoiler": "lip", "exhaust": [[0.5, 0.26], [0.62, 0.26], [-0.5, 0.26], [-0.62, 0.26]], "sill": True, "splitter": True, "gills": True,
    },
    "muscle": {
        "W": 1.94, "L": 4.8,
        "body": [[0.0, 0.86, 0.94], [0.12, 0.95, 0.98], [0.6, 0.98, 1.0], [1.4, 0.98, 1.0], [3.3, 0.96, 1.0], [4.4, 0.93, 0.99], [4.7, 0.87, 0.96], [4.8, 0.76, 0.93]],
        "gh": [1.18, 3.32, 1.62, 2.78, 0.98, 1.33, 0.92, 0.75], "pillars": [[0.0, 0.22], [0.9, 1.0]],
        "roof_drop": 0.02, "wheel": [0.355, 0.95, 3.85], "tyre": [0.275, 0.255], "corner": [0.14, 0.16], "flare": [0.04, 0.03], "crease_h": 0.6, "tumble": 0.04,
        "head": {"u": [0.5, 0.92], "lo": [0.66, 0.66], "hi": [0.78, 0.78], "drl": "ring", "proj": 2},
        "tail": {"u": [0.08, 0.96], "lo": [0.8, 0.8], "hi": [0.9, 0.9], "drl": "none", "segments": 3},
        "grille": {"w": 0.92, "y": [0.6, 0.8], "kind": "mesh", "full": True}, "intake": {"w": 0.6, "y": [0.26, 0.4]},
        "doors": [3.22, 1.78], "handles": [2.0], "hood": "scoop", "stripes": True, "spoiler": "lip", "exhaust": [[0.62, 0.27], [-0.62, 0.27]], "sill": False,
    },
    "fastback": {
        "W": 1.92, "L": 4.75,
        "body": [[0.0, 0.84, 0.94], [0.12, 0.93, 0.98], [0.5, 0.96, 1.0], [1.6, 0.97, 1.0], [3.3, 0.95, 1.0], [4.3, 0.9, 0.99], [4.65, 0.82, 0.95], [4.75, 0.72, 0.92]],
        "gh": [0.42, 3.3, 1.78, 2.8, 0.96, 1.31, 0.92, 0.74], "pillars": [[0.0, 0.42], [0.9, 1.0]],
        "wheel": [0.355, 0.95, 3.76], "tyre": [0.285, 0.255], "corner": [0.16, 0.2], "flare": [0.045, 0.035], "fender": [0.02, 0.0], "crease_h": 0.62, "tumble": 0.05,
        "head": {"u": [0.48, 0.94], "lo": [0.66, 0.68], "hi": [0.74, 0.8], "drl": "L", "proj": 2},
        "tail": {"u": [0.42, 0.97], "lo": [0.76, 0.76], "hi": [0.86, 0.86], "drl": "none", "segments": 3},
        "grille": {"w": 0.5, "y": [0.48, 0.68], "kind": "mesh"}, "intake": {"w": 0.7, "y": [0.24, 0.38]},
        "doors": [3.2, 1.82], "handles": [2.02], "hood": "scoop", "stripes": True, "spoiler": "ducktail", "exhaust": [[0.6, 0.27], [-0.6, 0.27]], "sill": True,
    },
    "super": {
        "W": 2.0, "L": 4.5,
        "body": [[0.0, 0.8, 0.9], [0.12, 0.9, 0.96], [0.5, 0.93, 1.0], [1.45, 0.88, 1.0], [2.4, 0.84, 1.0], [3.5, 0.74, 1.0], [3.95, 0.66, 0.98], [4.35, 0.56, 0.93], [4.5, 0.48, 0.88]],
        "gh": [1.45, 3.5, 2.05, 2.86, 0.84, 1.2, 0.86, 0.66], "pillars": [[0.0, 0.26], [0.9, 1.0]],
        "roof_drop": 0.04, "wheel": [0.35, 0.86, 3.52], "tyre": [0.305, 0.255], "corner": [0.26, 0.4], "flare": [0.06, 0.05], "fender": [0.04, 0.06], "crease_h": 0.55, "tumble": 0.1,
        "head": {"u": [0.5, 0.95], "lo": [0.5, 0.54], "hi": [0.55, 0.62], "drl": "top", "proj": 0},
        "tail": {"u": [0.2, 0.98], "lo": [0.66, 0.66], "hi": [0.72, 0.74], "drl": "none", "bar": [0.68, 0.7]},
        "grille": None, "intake": {"w": 0.86, "y": [0.2, 0.42]}, "side_intake": [1.55, 2.05, 0.42, 0.72],
        "doors": [3.2, 2.15], "handles": [], "hood": "vents", "spoiler": "lip", "exhaust": [[0.18, 0.32], [-0.18, 0.32]], "sill": True, "splitter": True, "diffuser": True,
    },
    "rcoupe": {
        "W": 1.9, "L": 4.5,
        "body": [[0.0, 0.8, 0.9], [0.12, 0.88, 0.96], [0.6, 0.9, 1.0], [1.2, 0.9, 1.0], [2.6, 0.88, 1.0], [3.3, 0.82, 1.0], [3.9, 0.72, 0.97], [4.35, 0.62, 0.92], [4.5, 0.55, 0.88]],
        "gh": [0.45, 3.32, 1.72, 2.64, 0.9, 1.29, 0.9, 0.7], "pillars": [[0.0, 0.3], [0.9, 1.0]],
        "roof_drop": 0.08, "wheel": [0.345, 1.0, 3.45], "tyre": [0.305, 0.245], "corner": [0.32, 0.4], "flare": [0.085, 0.045], "fender": [0.04, 0.075], "crease_h": 0.6, "tumble": 0.08,
        "round_head": [[0.72, 0.66, 0.1]],
        "tail": {"u": [0.06, 0.98], "lo": [0.7, 0.7], "hi": [0.75, 0.76], "drl": "none", "bar": [0.715, 0.735]},
        "grille": {"w": 0.45, "y": [0.32, 0.4], "kind": "slot"}, "intake": {"w": 0.8, "y": [0.2, 0.32]}, "side_intake": [1.15, 1.45, 0.48, 0.66],
        "doors": [3.12, 1.95], "handles": [2.1], "hood": "vents", "stripes": True, "spoiler": "ducktail", "exhaust": [[0.18, 0.3], [-0.18, 0.3]], "sill": True, "diffuser": True,
    },
    "hyper": {
        "W": 2.05, "L": 4.75,
        "body": [[0.0, 0.78, 0.92], [0.12, 0.88, 0.97], [0.6, 0.9, 1.0], [1.65, 0.86, 1.0], [2.6, 0.8, 1.0], [3.7, 0.7, 1.0], [4.2, 0.6, 0.97], [4.6, 0.5, 0.92], [4.75, 0.42, 0.88]],
        "gh": [1.65, 3.72, 2.3, 3.1, 0.78, 1.13, 0.84, 0.62], "pillars": [[0.0, 0.3], [0.9, 1.0]],
        "roof_drop": 0.05, "wheel": [0.36, 0.95, 3.72], "tyre": [0.335, 0.275], "corner": [0.3, 0.46], "flare": [0.07, 0.06], "fender": [0.06, 0.085], "crease_h": 0.55, "tumble": 0.11,
        "head": {"u": [0.52, 0.96], "lo": [0.44, 0.48], "hi": [0.48, 0.55], "drl": "top", "proj": 0},
        "tail": {"u": [0.3, 0.98], "lo": [0.62, 0.6], "hi": [0.67, 0.68], "drl": "none", "segments": 2},
        "grille": None, "intake": {"w": 0.9, "y": [0.18, 0.38]}, "side_intake": [1.7, 2.35, 0.38, 0.72],
        "doors": [3.4, 2.4], "handles": [], "hood": "vents", "stripes": True, "spoiler": "wing", "exhaust": [[0.0, 0.42], [0.12, 0.42], [-0.12, 0.42]], "sill": True, "splitter": True, "diffuser": True,
    },
}

# ------------------------------------------------------------------ shape rules (after body_builder.gd)


def smooth_stations(st, sub=3):
    out = []
    n = len(st)
    for i in range(n - 1):
        p0 = st[max(i - 1, 0)]
        p1 = st[i]
        p2 = st[i + 1]
        p3 = st[min(i + 2, n - 1)]
        for k in range(sub):
            t = k / sub
            row = []
            for c in range(3):
                a, b, cc, d = p0[c], p1[c], p2[c], p3[c]
                row.append(0.5 * (2 * b + (-a + cc) * t + (2 * a - 5 * b + 4 * cc - d) * t * t + (-a + 3 * b - 3 * cc + d) * t ** 3))
            out.append(row)
    out.append(list(st[-1]))
    return out


def smoothstep(e0, e1, x):
    t = min(max((x - e0) / (e1 - e0), 0.0), 1.0) if e1 != e0 else (1.0 if x >= e1 else 0.0)
    return t * t * (3 - 2 * t)


def lerp(a, b, t):
    return a + (b - a) * t


class Body:
    def __init__(self, D):
        self.D = D
        self.w = D["W"]
        self.l = D["L"]
        self.g = D["gh"]
        self.r = D["wheel"][0]
        self.axles = [D["wheel"][1], D["wheel"][2]]
        self.R = self.r + 0.055
        g5 = self.g[5]
        self.floor_y = 0.28 if g5 > 1.6 else (0.17 if g5 < 1.2 else 0.2)
        self.st = smooth_stations(D["body"])
        self.rc_r, self.rc_f = D.get("corner", [0.2, 0.26])
        self.flare = D.get("flare", [0.03, 0.03])
        self.fender = D.get("fender", [0.0, 0.0])
        self.crease = D.get("crease_h", 0.7)
        self.tumble = D.get("tumble", 0.06)
        self.pillars = [[lerp(self.g[0], self.g[1], a), lerp(self.g[0], self.g[1], b), "paint" if i == 0 else "gloss"]
                        for i, (a, b) in enumerate(D["pillars"])]

    def station(self, d, idx):
        st = self.st
        if d <= st[0][0]:
            return st[0][idx]
        for i in range(len(st) - 1):
            a, b = st[i], st[i + 1]
            if d <= b[0]:
                t = (d - a[0]) / max(b[0] - a[0], 1e-6)
                return lerp(a[idx], b[idx], t)
        return st[-1][idx]

    def top(self, d):
        return self.station(d, 1)

    @staticmethod
    def pull(e, rc):
        if e >= rc or rc <= 0:
            return 0.0
        u = rc - e
        return rc - math.sqrt(max(rc * rc - u * u, 0.0))

    def axle_amount(self, d, v):
        br = math.exp(-((d - self.axles[0]) / 0.62) ** 2)
        bf = math.exp(-((d - self.axles[1]) / 0.62) ** 2)
        return v[0] * br + v[1] * bf

    def hw(self, d):
        base = self.w / 2 * self.station(d, 2)
        p = self.pull(d, self.rc_r) + self.pull(self.l - d, self.rc_f)
        return (base - p) * (1 + self.axle_amount(d, self.flare))

    def arch_y(self, d):
        y = self.floor_y
        for a in self.axles:
            dd = abs(d - a)
            if dd < self.R:
                y = max(y, self.r + math.sqrt(self.R ** 2 - dd * dd))
        return y

    @staticmethod
    def ease(s, k):
        s = min(max(s, 0.0), 1.0)
        m = 1.0 / (1.0 - k / 2.0)
        if s <= 1.0 - k:
            return m * s
        u = s - (1.0 - k)
        return m * (1.0 - k) + m * (u - u * u / (2 * k))

    def roof_line(self, d):
        g = self.g
        drop = self.D.get("roof_drop", 0.0)
        return g[5] - drop * (1 - smoothstep(g[2], lerp(g[2], g[3], 0.7), d))

    def roof_y(self, d):
        g = self.g
        t = self.top(d)
        if d <= g[0] or d >= g[1]:
            return t
        if d < g[2]:
            return t + (self.roof_line(g[2]) - t) * self.ease((d - g[0]) / max(g[2] - g[0], 0.01), 0.4)
        if d > g[3]:
            return t + (g[5] - t) * self.ease((g[1] - d) / max(g[1] - g[3], 0.01), 0.3)
        return self.roof_line(d) + 0.012 * math.sin(math.pi * (d - g[2]) / max(g[3] - g[2], 0.01))

    def hood_lift(self, d, x):
        g = self.g
        kind = self.D.get("hood")
        d0 = g[1] + 0.1
        d1 = self.l - 0.38
        if d <= d0 or d >= d1 or kind not in ("scoop", "dome"):
            return 0.0
        along = smoothstep(d0, d0 + 0.25, d) * (1 - smoothstep(d1 - 0.18, d1, d))
        if kind == "scoop":
            across = 1 - smoothstep(0.24, 0.34, abs(x))
            rise = lerp(0.035, 0.07, smoothstep(d0, d1, d))
            return rise * along * across * (1 - smoothstep(d1 - 0.36, d1 - 0.3, d))
        return 0.026 * along * (1 - smoothstep(0.1, 0.3, abs(x)))

    def section19(self, d):
        """The 19-point right half section of body_builder.gd."""
        g = self.g
        t = self.top(d)
        hwd = self.hw(d)
        yb = self.arch_y(d)
        fb = self.axle_amount(d, self.fender)
        ts = t + fb
        fy = self.floor_y
        Hf = max(ts - fy, 0.08)
        p = [None] * 19
        p[0] = (0.0, fy)
        p[1] = (hwd * 0.6, fy)
        p[2] = (hwd * 0.62, yb)
        p[3] = (hwd * 0.82, yb)
        hs = [0.035, 0.12, 0.42, self.crease, self.crease + (1 - self.crease) * 0.55]
        xs = [0.93, 0.975, 1.0, 0.996, 0.996 - self.tumble * 0.5]
        lo = yb
        for k in range(5):
            y = max(fy + Hf * hs[k], lo + 0.004)
            y = min(y, ts - 0.02 + 0.003 * k)
            lo = y
            p[4 + k] = (hwd * xs[k], y)
        p[9] = (hwd * (0.996 - self.tumble * 0.85), max(ts - 0.014, p[8][1] + 0.002))
        p[10] = (hwd * (0.996 - self.tumble), max(ts, p[9][1] + 0.002))
        e0 = 0.996 - self.tumble
        flat = [(hwd * (e0 - 0.015), ts + 0.006), (hwd * (e0 - 0.035), ts + 0.009 - fb * 0.1), (hwd * (e0 - 0.055), t + 0.012 + fb * 0.75),
                (hwd * (e0 - 0.08), t + 0.015 + fb * 0.45), (hwd * 0.78, t + 0.02 + fb * 0.12), (hwd * 0.6, t + 0.024),
                (hwd * 0.32, t + 0.027), (0.0, t + 0.028)]
        if d > g[1] + 0.1:
            flat = [(q[0], q[1] + self.hood_lift(d, q[0])) for q in flat]
        roof = self.roof_y(d)
        gh_h = roof - t
        if gh_h <= 0.0005:
            for k in range(8):
                p[11 + k] = flat[k]
            return p
        full = max(g[5] - t, 0.05)
        hk = min(max(gh_h / full, 0.0), 1.0)
        gw_base = min(self.w / 2 * g[6], hwd * 0.915)
        gw_roof = self.w / 2 * g[7]
        xs_top = lerp(gw_base, min(gw_roof * 1.03, gw_base), hk)
        drop = min(max(gh_h * 0.22, 0.0), 0.055)
        y0 = t + 0.012
        ytop = max(roof - drop, y0 + 0.002)
        hk2 = min(max(gh_h / 0.2, 0.0), 1.0)
        cab = [(gw_base, y0), (lerp(gw_base, xs_top, 0.33), lerp(y0, ytop, 0.33)), (lerp(gw_base, xs_top, 0.66), lerp(y0, ytop, 0.66)),
               (xs_top, ytop), (xs_top - 0.022 * hk2, ytop + drop * 0.55), (xs_top - 0.075 * hk2, roof - drop * 0.08),
               ((xs_top - 0.075 * hk2) * 0.55, roof + 0.02), (0.0, roof + 0.026)]
        bl = smoothstep(0.0, 0.05, gh_h)
        for k in range(8):
            p[11 + k] = (lerp(flat[k][0], cab[k][0], bl), lerp(flat[k][1], cab[k][1], bl))
        return p


# per segment of the 19-point section: how many sub-steps (HQ, LQ)
SEG_SUB_HQ = [2, 1, 1, 2] + [3] * 6 + [2, 2, 2, 2, 3, 3, 2, 2]
SEG_SUB_LQ = [1, 1, 1, 1] + [1] * 6 + [1] * 8


def catmull(p0, p1, p2, p3, t):
    return tuple(0.5 * (2 * b + (-a + c) * t + (2 * a - 5 * b + 4 * c - d) * t * t + (-a + 3 * b - 3 * c + d) * t ** 3)
                 for a, b, c, d in zip(p0, p1, p2, p3))


def refine_section(p19, subs):
    """Splined section: returns [(x, y, s)] with s the fractional 19-point index."""
    out = []
    groups = [(0, 4), (4, 10), (10, 18)]  # (first, last) index of each smooth run

    def group_of(i):
        for a, b in groups:
            if a <= i < b:
                return a, b
        return 10, 18
    for i in range(18):
        n = subs[i]
        a, b = group_of(i)
        for k in range(n):
            t = k / n
            if i < 4:  # floor and wheel-well corners stay straight
                x = lerp(p19[i][0], p19[i + 1][0], t)
                y = lerp(p19[i][1], p19[i + 1][1], t)
            else:
                q0 = p19[max(i - 1, a)]
                q3 = p19[min(i + 2, b)]
                x, y = catmull(q0, p19[i], p19[i + 1], q3, t)
            out.append((x, y, i + t))
    out.append((p19[18][0], p19[18][1], 18.0))
    return out


def end_recede(B, d, x, y):
    """How far a body point near either end is pulled back towards the middle
    of the car (positive = towards the other end)."""
    E = 0.42
    bx, bt, bb = B.D.get("bow", [0.11, 0.16, 0.07])
    L = B.l
    u = min(abs(x) / (B.w / 2), 1.0)
    out = 0.0
    for e, sign in ((d, 1.0), (L - d, -1.0)):
        if e < E:
            w = (1.0 - e / E) ** 2
            top = B.top(min(max(d, 0.0), L))
            ym = B.floor_y + (top - B.floor_y) * 0.42  # bumper height
            v = (y - ym) / max(top - ym, 0.05) if y > ym else (ym - y) / max(ym - B.floor_y, 0.05)
            g = (bt if y > ym else bb) * min(v, 1.4) ** 2
            out += sign * w * (bx * u * u + g)
    return out


def end_z(B, x, y, front=True):
    """z of the nose (front) or tail face at (x, y)."""
    d = B.l if front else 0.0
    return -(d + end_recede(B, d, x, y))


def sample_ds(B, lq):
    L = B.l
    step = 0.2 if lq else 0.045
    ds = list(np.linspace(0, L, int(math.ceil(L / step)) + 1))
    na = 5 if lq else 17
    for a in B.axles:
        for k in range(na):
            ds.append(a + B.R * (-1 + 2 * k / (na - 1)) * 0.999)
        ds += [a - B.R * 1.002, a + B.R * 1.002]
    nc = 3 if lq else 14
    for k in range(nc):
        th = math.pi / 2 * k / (nc - 1)
        ds.append(B.rc_r * (1 - math.cos(th)))
        ds.append(L - B.rc_f * (1 - math.cos(th)))
    g = B.g
    for v in [g[0], g[1], g[2], g[3], g[1] + 0.09]:
        ds.append(v)
    for pl in B.pillars:
        ds += [pl[0], pl[1]]
    ds = sorted(min(max(d, 0.0), L) for d in ds)
    out = []
    for d in ds:
        if not out or d - out[-1] > 0.004:
            out.append(d)
    return out


# ------------------------------------------------------------------ classification


def superellipse(p, q, n=6.0):
    return abs(2 * p - 1) ** n + abs(2 * q - 1) ** n


class Styler:
    """Decides what each bit of the body surface is (paint, glass, lamp...)."""

    def __init__(self, B):
        self.B = B
        self.D = B.D
        self.hw_max = B.w / 2

    def lamp(self, spec, x, y, emissive):
        """Class inside a lamp shape, or None."""
        u = abs(x) / self.hw_max
        u0, u1 = spec["u"]
        if u < u0 or u > u1:
            return None
        p = (u - u0) / (u1 - u0)
        lo = lerp(spec["lo"][0], spec["lo"][1], p)
        hi = lerp(spec["hi"][0], spec["hi"][1], p)
        if y < lo or y > hi:
            return None
        q = (y - lo) / max(hi - lo, 1e-4)
        se = superellipse(p, q, 5.0)
        if se > 1.0:
            return None
        if se > 0.86:
            return "gloss"  # the lamp's dark surround
        drl = spec.get("drl", "none")
        if emissive == "head":
            # projector lenses and the LED daytime light
            n = spec.get("proj", 1)
            for k in range(n):
                cu = lerp(0.3, 0.75, (k + 0.5) / n) if n > 1 else 0.5
                cx = lerp(u0, u1, cu) * self.hw_max
                cy = lerp(lo, hi, 0.42)
                rr = min(hi - lo, (u1 - u0) * self.hw_max / max(n, 1)) * 0.3
                dd = math.hypot(abs(x) - cx, y - cy)
                if dd < rr:
                    return "head" if dd < rr * 0.72 else "chrome"
            if drl == "top" and q > 0.74:
                return "head"
            if drl == "L" and (q < 0.2 or p > 0.86):
                return "head"
            if drl == "ring" and 0.5 < se < 0.7:
                return "head"
            if drl == "none" and n == 0:
                return "head"
            return "chrome"  # reflector housing
        segs = spec.get("segments", 0)
        if segs and abs(math.sin(p * math.pi * segs)) < 0.12:
            return "gloss"  # dividers between lamp segments
        if q > 0.12 and q < 0.88 and abs(q - 0.5) < 0.08 and drl == "none" and not segs:
            return "gloss"  # a smoked band across the middle
        return emissive

    def round_lamp(self, x, y):
        for u, cy, rr in self.D.get("round_head", []):
            cx = u * self.hw_max
            dd = math.hypot(abs(x) - cx, y - cy)
            if dd < rr:
                if dd > rr * 0.86:
                    return "chrome"
                if dd < rr * 0.42:
                    return "head"
                return "head" if dd > rr * 0.72 else "chrome"
        return None

    def grille(self, x, y):
        G = self.D.get("grille")
        if not G:
            return None
        ax = abs(x)
        y0, y1 = G["y"]
        if y < y0 or y > y1:
            return None
        kind = G["kind"]
        gw = G["w"] * self.hw_max
        if kind == "kidney":  # two rounded kidneys either side of the centre
            if ax < 0.025 or ax > gw:
                return None
            p = (ax - 0.025) / (gw - 0.025)
            q = (y - y0) / (y1 - y0)
            se = superellipse(p, q, 4.0)
            if se > 1:
                return None
            if se > 0.7:
                return "chrome"
            return "under"  # slats are added as geometry (add_grille_bars)
        if ax > gw:
            return None
        p = 0.5 + ax / (2 * gw)
        q = (y - y0) / (y1 - y0)
        se = superellipse(p, q, 6.0 if kind != "slot" else 10.0)
        if se > 1:
            return None
        if se > 0.8:
            return "chrome" if kind in ("bars", "kidney") else "gloss"
        return "under"  # bars / mesh are added as geometry (add_grille_bars)

    def intake(self, x, y):
        I = self.D.get("intake")
        if not I:
            return None
        ax = abs(x)
        y0, y1 = I["y"]
        gw = I["w"] * self.hw_max
        if ax > gw or y < y0 or y > y1:
            return None
        p = 0.5 + ax / (2 * gw)
        q = (y - y0) / (y1 - y0)
        se = superellipse(p, q, 7.0)
        if se > 1:
            return None
        if se > 0.82:
            return "gloss"
        return "under"

    def greenhouse(self, s, d):
        B = self.B
        g = B.g
        seg = int(math.floor(s))
        ws = d > g[3]
        rs = d < g[2]
        if seg == 10:
            return "gloss"  # window seal along the belt
        if 11 <= seg <= 13:
            for i, pl in enumerate(B.pillars):
                if pl[0] - 0.0005 <= d <= pl[1] + 0.0005:
                    return pl[2]
            # black frit and surround round the side glass
            if s < 11.12 or s > 13.86:
                return "gloss"
            for pl in B.pillars:
                if abs(d - pl[0]) < 0.022 or abs(d - pl[1]) < 0.022:
                    return "gloss"
            return "glass"
        if seg == 14:
            return "paint" if (ws or rs) else "gloss"
        if seg == 15:
            return "paint"
        if ws or rs:
            # windscreen / rear window with a dark frit band round the edge
            if s < 16.25:
                return "gloss"
            if ws and (d > g[1] - 0.06 or d < g[3] + 0.035):
                return "gloss"
            if rs and (d < g[0] + 0.05 or d > g[2] - 0.035):
                return "gloss"
            return "glass"
        return "paint"

    def classify(self, x, y, d, nx, ny, nz, s, cap):
        """Surface class of a point on the body."""
        B = self.B
        D = self.D
        self.x_abs = abs(x)
        L = B.l
        if cap == 0 and s < 3.0:
            return "under"
        if cap == 0 and s < 4.0:
            return "dark"  # wheel-arch lip / sill bottom
        forward = nz < -0.25 or cap == 2
        rearward = nz > 0.25 or cap == 1
        # nose: lamps, grille, intake, splitter
        if d > L - 0.75 and (forward or (abs(nx) > 0.45 and d > L - 0.26)):
            c = self.round_lamp(x, y) if D.get("round_head") else None
            if c is None and D.get("head"):
                c = self.lamp(D["head"], x, y, "head")
            if c is None:
                c = self.grille(x, y)
            if c is None and forward:
                c = self.intake(x, y)
            if c is None and forward and y < B.floor_y + 0.07:
                c = "gloss"  # lower lip
            if c:
                return c
        # tail: lamps, diffuser
        if d < 0.62 and (rearward or (abs(nx) > 0.45 and d < 0.16)):
            c = self.lamp(D["tail"], x, y, "tail") if D.get("tail") else None
            if c is None and D.get("tail") and D["tail"].get("bar") and rearward:
                y0, y1 = D["tail"]["bar"]
                if y0 < y < y1 and abs(x) < D["tail"]["u"][0] * self.hw_max + 0.02:
                    c = "tail"
            if c is None and rearward and D.get("diffuser") and y < B.floor_y + 0.17 and abs(x) < 0.72 * self.hw_max:
                c = "under"
            if c is None and rearward and y < B.floor_y + 0.13 and abs(x) < 0.9 * self.hw_max:
                c = "gloss"  # black lower valance
            if c is None and rearward and abs(x) < 0.3 and abs(y - (B.floor_y + 0.29)) < 0.085 and d < 0.2:
                c = "gloss"  # number-plate recess
            if c:
                return c
        if cap:
            return "paint"
        g = B.g
        cab = g[0] + 0.0005 < d < g[1] - 0.0005
        if s >= 10.0 and cab:
            return self.greenhouse(s, d)
        if s >= 12.0 and g[1] < d < g[1] + 0.09:
            return "gloss"  # cowl at the foot of the windscreen
        # side intakes behind the doors (mid-engine cars)
        si = D.get("side_intake")
        if si and 4.0 <= s <= 10.0 and si[0] < d < si[1] and si[2] < y < si[3]:
            p = (d - si[0]) / (si[1] - si[0])
            q = (y - si[2]) / (si[3] - si[2])
            se = superellipse(p, q, 4.0)
            if se < 1:
                return "gloss" if se > 0.75 else "under"
        # bonnet vents / gills
        if D.get("hood") == "vents" and s > 14.0 and g[1] + 0.25 < d < g[1] + 0.6 and 0.2 < abs(x) < 0.4:
            return "under"  # louvres added as geometry
        if D.get("gills") and 7.5 < s < 9.0 and B.axles[1] + 0.32 < d < B.axles[1] + 0.58:
            return "under"
        # black sills, cladding round the arches (SUV)
        if D.get("sill") and s < 4.55:
            return "gloss"
        if D.get("cladding") and s < 5.6:
            return "dark"
        return "paint"


# ------------------------------------------------------------------ mesh building


class Mesh:
    def __init__(self):
        self.surf = {}

    def tri(self, kind, a, b, c, na, nb, nc):
        """Add a triangle wound anticlockwise seen from its normal side."""
        a, b, c = np.asarray(a, float), np.asarray(b, float), np.asarray(c, float)
        na, nb, nc = np.asarray(na, float), np.asarray(nb, float), np.asarray(nc, float)
        if np.dot(np.cross(b - a, c - a), na + nb + nc) < 0:
            b, c, nb, nc = c, b, nc, nb
        s = self.surf.setdefault(kind, ([], []))
        s[0].extend([a, b, c])
        s[1].extend([na, nb, nc])

    def tris_np(self, kind, P, N):
        """Bulk add (already wound) triangles: P, N arrays (n, 3, 3)."""
        if len(P) == 0:
            return
        s = self.surf.setdefault(kind, ([], []))
        s[0].extend(P.reshape(-1, 3))
        s[1].extend(N.reshape(-1, 3))

    def quad(self, kind, a, b, c, d, n):
        self.tri(kind, a, b, c, n, n, n)
        self.tri(kind, a, c, d, n, n, n)

    def box(self, kind, center, size, basis=None):
        c = np.asarray(center, float)
        hx, hy, hz = np.asarray(size, float) / 2
        Bm = np.eye(3) if basis is None else np.asarray(basis, float)
        ax = [Bm[:, 0], Bm[:, 1], Bm[:, 2]]
        h = [hx, hy, hz]
        for i in range(3):
            for sgn in (-1, 1):
                n = ax[i] * sgn
                u = ax[(i + 1) % 3] * h[(i + 1) % 3]
                v = ax[(i + 2) % 3] * h[(i + 2) % 3]
                o = c + n * h[i]
                self.quad(kind, o - u - v, o + u - v, o + u + v, o - u + v, n)

    def cyl(self, kind, center, r, length, axis, segs=16, caps=True, cap_kind=None):
        c = np.asarray(center, float)
        axv = np.asarray(axis, float)
        axv = axv / np.linalg.norm(axv)
        tmp = np.array([0, 1, 0]) if abs(axv[1]) < 0.9 else np.array([1, 0, 0])
        u = np.cross(axv, tmp)
        u /= np.linalg.norm(u)
        v = np.cross(axv, u)
        h = axv * length / 2
        for k in range(segs):
            a0 = 2 * math.pi * k / segs
            a1 = 2 * math.pi * (k + 1) / segs
            d0 = u * math.cos(a0) + v * math.sin(a0)
            d1 = u * math.cos(a1) + v * math.sin(a1)
            self.tri(kind, c - h + d0 * r, c - h + d1 * r, c + h + d1 * r, d0, d1, d1)
            self.tri(kind, c - h + d0 * r, c + h + d1 * r, c + h + d0 * r, d0, d1, d0)
            if caps:
                ck = cap_kind or kind
                self.tri(ck, c + h, c + h + d0 * r, c + h + d1 * r, axv, axv, axv)
                self.tri(ck, c - h, c - h + d1 * r, c - h + d0 * r, -axv, -axv, -axv)

    def ellipsoid(self, kind, center, radii, su=14, sv=8, half=None):
        c = np.asarray(center, float)
        r = np.asarray(radii, float)
        pts = []
        for i in range(sv + 1):
            th = math.pi * i / sv
            row = []
            for j in range(su + 1):
                ph = 2 * math.pi * j / su
                n = np.array([math.sin(th) * math.cos(ph), math.cos(th), math.sin(th) * math.sin(ph)])
                row.append((c + n * r, n / r / np.linalg.norm(n / r)))
            pts.append(row)
        for i in range(sv):
            for j in range(su):
                a, b, cc, d = pts[i][j], pts[i][j + 1], pts[i + 1][j + 1], pts[i + 1][j]
                if half is not None and not half(a[0] - c):
                    continue
                self.tri(kind, a[0], b[0], cc[0], a[1], b[1], cc[1])
                self.tri(kind, a[0], cc[0], d[0], a[1], cc[1], d[1])


def body_grid(B, lq):
    """The right half of the body as one smooth grid: rings closing the tail,
    the sections from tail to nose, rings closing the nose. Returns arrays
    pos (nr, ns, 3), nrm, s (section param), d, cap (0 body, 1 tail, 2 nose)."""
    ds = sample_ds(B, lq)
    subs = SEG_SUB_LQ if lq else SEG_SUB_HQ
    secs = [refine_section(B.section19(d), subs) for d in ds]
    ns = len(secs[0])
    rings = [0.0, 0.7] if lq else [0.0, 0.22, 0.45, 0.65, 0.8, 0.91, 0.97]
    rows = []  # (points [(x, y, s)], d, cap)

    def cap_rows(sec, d, cap, order):
        cy = (B.floor_y + B.top(d)) * 0.5
        out = []
        for f in order:
            out.append(([(x * f, cy + (y - cy) * f, s_) for x, y, s_ in sec], d, cap))
        return out
    rows += cap_rows(secs[0], ds[0], 1, rings)
    for d, sec in zip(ds, secs):
        rows.append((sec, d, 0))
    rows += cap_rows(secs[-1], ds[-1], 2, list(reversed(rings)))
    nr = len(rows)
    P = np.zeros((nr, ns, 3))
    S = np.zeros((nr, ns))
    Dd = np.zeros((nr, ns))
    C = np.zeros((nr, ns), int)
    for i, (sec, d, cap) in enumerate(rows):
        for j, (x, y, s_) in enumerate(sec):
            # round the ends: nose and tail curve back in plan and their top
            # and bottom edges roll under, so the bumpers stand proud
            P[i, j] = (x, y, -(d + end_recede(B, d, x, y)))
            S[i, j] = s_
            Dd[i, j] = d
            C[i, j] = cap
    # normals from the grid (central differences)
    N = np.zeros_like(P)
    for i in range(nr):
        for j in range(ns):
            i0, i1 = max(i - 1, 0), min(i + 1, nr - 1)
            j0, j1 = max(j - 1, 0), min(j + 1, ns - 1)
            tv = P[i, j1] - P[i, j0]
            td = P[i1, j] - P[i0, j]
            n = np.cross(tv, td)
            mid = (B.floor_y + B.top(Dd[i, j])) * 0.5
            hint = np.array([P[i, j][0], P[i, j][1] - mid, 0.0])
            if C[i, j] == 1:
                hint = hint * 0.3 + np.array([0, 0, 1.0])
            elif C[i, j] == 2:
                hint = hint * 0.3 + np.array([0, 0, -1.0])
            ln = np.linalg.norm(n)
            if ln < 1e-9:
                n = hint
                ln = np.linalg.norm(n) + 1e-9
            n = n / ln
            if np.dot(n, hint) < 0:
                n = -n
            N[i, j] = n
    return P, N, S, Dd, C


def classify_tris(styler, P, N, S, Dd, caps, depth):
    """Split the triangles where their class changes across them, then sort
    every (sub)triangle into its surface. Arrays: (n, 3, k)."""
    out = {}

    def cls_of(p, n, s, d, cap):
        return styler.classify(p[0], p[1], d, n[0], n[1], n[2], s, cap)

    tp, tn, ts, td, tc = P, N, S, Dd, caps
    for level in range(depth + 1):
        cent_p = tp.mean(1)
        cent_n = tn.mean(1)
        cent_s = ts.mean(1)
        cent_d = td.mean(1)
        cls = np.array([cls_of(cent_p[i], cent_n[i], cent_s[i], cent_d[i], tc[i]) for i in range(len(tp))], dtype=object)
        if level == depth:
            dis = np.zeros(len(tp), bool)
        else:
            dis = np.zeros(len(tp), bool)
            for v in range(3):
                pp = tp[:, v] * 0.88 + cent_p * 0.12
                nn = tn[:, v] * 0.88 + cent_n * 0.12
                ss = ts[:, v] * 0.88 + cent_s * 0.12
                dd = td[:, v] * 0.88 + cent_d * 0.12
                cv = np.array([cls_of(pp[i], nn[i], ss[i], dd[i], tc[i]) for i in range(len(tp))], dtype=object)
                dis |= cv != cls
        keep = ~dis
        for kind in set(cls[keep]):
            sel = keep & (cls == kind)
            o = out.setdefault(kind, ([], []))
            o[0].append(tp[sel])
            o[1].append(tn[sel])
        if not dis.any():
            break
        tp, tn, ts, td, tc = tp[dis], tn[dis], ts[dis], td[dis], tc[dis]

        def sub(x):
            a, b, c = x[:, 0], x[:, 1], x[:, 2]
            ab, bc, ca = (a + b) / 2, (b + c) / 2, (c + a) / 2
            return np.concatenate([np.stack([a, ab, ca], 1), np.stack([ab, b, bc], 1), np.stack([ca, bc, c], 1), np.stack([ab, bc, ca], 1)])
        tp, tn, ts, td = sub(tp), sub(tn), sub(ts[..., None])[..., 0], sub(td[..., None])[..., 0]
        tc = np.concatenate([tc] * 4)
    return out


def build_body(B, lq, mesh):
    st = Styler(B)
    P, N, S, Dd, C = body_grid(B, lq)
    nr, ns, _ = P.shape
    tris_p, tris_n, tris_s, tris_d, tris_c = [], [], [], [], []

    def add(ia, ib, ic):
        cap = max(C[ia], C[ib], C[ic])
        pa0, pb0, pc0 = P[ia], P[ib], P[ic]
        if np.linalg.norm(np.cross(pb0 - pa0, pc0 - pa0)) < 1e-10:
            return  # collapsed (the centre of a cap)
        for side in (1.0, -1.0):
            m = np.array([side, 1.0, 1.0])
            idx = [ia, ib, ic]
            pa, pb, pc = P[ia] * m, P[ib] * m, P[ic] * m
            na, nb, nc = N[ia] * m, N[ib] * m, N[ic] * m
            if np.dot(np.cross(pb - pa, pc - pa), na + nb + nc) < 0:  # anticlockwise from outside
                idx = [ia, ic, ib]
                pb, pc, nb, nc = pc, pb, nc, nb
            tris_p.append([pa, pb, pc])
            tris_n.append([na, nb, nc])
            tris_s.append([S[k] for k in idx])
            tris_d.append([Dd[k] for k in idx])
            tris_c.append(cap)
    for i in range(nr - 1):
        for j in range(ns - 1):
            add((i, j), (i, j + 1), (i + 1, j + 1))
            add((i, j), (i + 1, j + 1), (i + 1, j))
    TP = np.array(tris_p)
    TN = np.array(tris_n)
    TS = np.array(tris_s)
    TD = np.array(tris_d)
    TC = np.array(tris_c)
    depth = 0 if lq else 2
    res = classify_tris(st, TP, TN, TS, TD, TC, depth)
    for kind, (ps, ns_) in res.items():
        mesh.tris_np(kind, np.concatenate(ps), np.concatenate(ns_))


# ------------------------------------------------------------------ fitted details


def surface_point(B, d, s):
    """Point and normal on the right side of the body at section param s."""
    sec = refine_section(B.section19(d), SEG_SUB_HQ)
    for k in range(len(sec) - 1):
        if sec[k][2] <= s <= sec[k + 1][2]:
            t = (s - sec[k][2]) / max(sec[k + 1][2] - sec[k][2], 1e-6)
            x = lerp(sec[k][0], sec[k + 1][0], t)
            y = lerp(sec[k][1], sec[k + 1][1], t)
            tx = sec[k + 1][0] - sec[k][0]
            ty = sec[k + 1][1] - sec[k][1]
            n = np.array([ty, -tx, 0.0])
            ln = np.linalg.norm(n)
            n = n / ln if ln > 0 else np.array([1.0, 0, 0])
            if n[0] < 0 and s < 10:
                n = -n
            return np.array([x, y, -d]), n
    return np.array([sec[-1][0], sec[-1][1], -d]), np.array([0, 1.0, 0])


def side_s_at_height(B, d, y):
    """Section param on the side (4..10) where the body is at height y."""
    sec = refine_section(B.section19(d), SEG_SUB_HQ)
    for k in range(len(sec) - 1):
        if 4.0 <= sec[k][2] < 10.0 and sec[k][1] <= y <= sec[k + 1][1]:
            t = (y - sec[k][1]) / max(sec[k + 1][1] - sec[k][1], 1e-6)
            return lerp(sec[k][2], sec[k + 1][2], t)
    return None


def gap_line_vertical(B, mesh, d, y_lo, y_hi, steps=14):
    """A thin dark shut line down the side at d (both sides)."""
    s0 = side_s_at_height(B, d, y_lo) or 4.6
    s1 = side_s_at_height(B, d, y_hi) or 9.6
    prev = None
    for k in range(steps + 1):
        s = lerp(s0, s1, k / steps)
        p, n = surface_point(B, d, s)
        p = p + n * 0.0016
        if prev is not None:
            for side in (1.0, -1.0):
                m = np.array([side, 1, 1])
                a, b = prev[0] * m, p * m
                nm = n * m
                hw = np.array([0, 0, 0.0028])
                mesh.quad("gloss", a - hw, a + hw, b + hw, b - hw, nm)
        prev = (p, n)


def top_y_at(B, d, x):
    sec = refine_section(B.section19(d), SEG_SUB_HQ)
    x = abs(x)
    for k in range(len(sec) - 1):
        if sec[k][2] >= 10.0 and sec[k][0] >= x >= sec[k + 1][0]:
            t = (sec[k][0] - x) / max(sec[k][0] - sec[k + 1][0], 1e-6)
            return lerp(sec[k][1], sec[k + 1][1], t)
    return sec[-1][1]


def gap_line_top(B, mesh, d0, d1, x, steps=20):
    """A shut line running along the top (bonnet / boot sides) at |x|."""
    prev = None
    for k in range(steps + 1):
        d = lerp(d0, d1, k / steps)
        p = np.array([abs(x), top_y_at(B, d, abs(x)) + 0.0016, -d])
        if prev is not None:
            for side in (1.0, -1.0):
                m = np.array([side, 1, 1])
                hw = np.array([0.0028, 0, 0])
                mesh.quad("gloss", prev * m - hw, prev * m + hw, p * m + hw, p * m - hw, np.array([0, 1.0, 0]))
        prev = p


def gap_line_across(B, mesh, d, x_max, steps=16):
    prev = None
    for k in range(steps + 1):
        x = lerp(-x_max, x_max, k / steps)
        p = np.array([x, top_y_at(B, d, x) + 0.0016, -d])
        if prev is not None:
            hw = np.array([0, 0, 0.0028])
            mesh.quad("gloss", prev - hw, prev + hw, p + hw, p - hw, np.array([0, 1.0, 0]))
        prev = p


def add_details(B, mesh, lq):
    D = B.D
    g = B.g
    L = B.l
    W = B.w
    # wing mirrors: body-coloured housing on a gloss arm, mirror glass behind
    dm = lerp(g[0], g[1], 0.955)
    tm = B.top(dm)
    gwb = min(W / 2 * g[6], B.hw(dm) * 0.915)
    for sd in (1.0, -1.0):
        hc = np.array([sd * (gwb + 0.18), tm + 0.12, -dm + 0.02])
        mesh.box("gloss", [sd * (gwb + 0.05), tm + 0.05, -dm + 0.03], [0.1, 0.045, 0.12])
        mesh.box("gloss", [sd * (gwb + 0.11), tm + 0.085, -dm + 0.03], [0.1, 0.03, 0.05])
        mesh.ellipsoid("paint", hc, [0.12, 0.068, 0.07], 8 if lq else 18, 4 if lq else 10)
        if not lq:
            mesh.ellipsoid("chrome", hc + np.array([0, 0, 0.03]), [0.1, 0.055, 0.05], 16, 8, half=lambda v: v[2] > 0.005)
    if lq:
        return
    # shut lines: doors, bonnet, boot
    doors = D.get("doors", [])
    y_lo = B.floor_y + 0.08
    for dd in doors:
        gap_line_vertical(B, mesh, dd, y_lo, B.top(dd) - 0.03)
    hood_d = g[1] + 0.13
    xh = B.hw(hood_d) * 0.72
    gap_line_across(B, mesh, hood_d, xh)
    gap_line_top(B, mesh, hood_d, L - 0.32, xh)
    if g[0] > 0.45:  # a boot lid
        bd = g[0] - 0.08
        xb = B.hw(bd) * 0.72
        gap_line_across(B, mesh, bd, xb)
        gap_line_top(B, mesh, 0.2, bd, xb)
    elif g[0] < 0.3:  # hatch: tailgate line round the rear window
        gap_line_across(B, mesh, 0.08, B.hw(0.08) * 0.8)
    # bumper shut line across the tail
    ys = B.floor_y + (B.top(0.0) - B.floor_y) * 0.55
    prev = None
    span = B.hw(0.05) * 0.86
    for k in range(25):
        x = lerp(-span, span, k / 24)
        p = np.array([x, ys, end_z(B, x, ys, False) + 0.0016])
        if prev is not None:
            hwv = np.array([0, 0.0028, 0])
            mesh.quad("gloss", prev - hwv, prev + hwv, p + hwv, p - hwv, np.array([0, 0, 1.0]))
        prev = p
    # flush door handles
    for hd in D.get("handles", []):
        yh = B.top(hd) - 0.13
        s = side_s_at_height(B, hd, yh)
        if s is None:
            continue
        p, n = surface_point(B, hd, s)
        for sd in (1.0, -1.0):
            m = np.array([sd, 1, 1])
            c = (p + n * 0.012) * m
            mesh.box("chrome", c, [0.022, 0.026, 0.16])
            mesh.box("gloss", (p + n * 0.003) * m, [0.012, 0.04, 0.2])
    # wipers at the foot of the windscreen
    for k in range(2):
        x0, x1 = (-0.1, -0.68) if k == 0 else (0.42, -0.06)
        da, db = g[1] - 0.07, g[1] - 0.14
        a = np.array([x0, top_y_at(B, da, x0) + 0.016, -da])
        b = np.array([x1, top_y_at(B, db, x1) + 0.016, -db])
        mid = (a + b) / 2
        dirv = b - a
        ln = np.linalg.norm(dirv)
        xv = dirv / ln
        zv = np.cross(xv, np.array([0, 1.0, 0]))
        zv /= np.linalg.norm(zv)
        yv = np.cross(zv, xv)
        mesh.box("gloss", mid, [ln, 0.012, 0.02], np.stack([xv, yv, zv], 1))
    # shark-fin antenna and third brake light
    da2 = g[2] + 0.18
    mesh.box("gloss", [0, B.roof_y(da2) + 0.05, -da2], [0.06, 0.06, 0.16])
    d3 = g[2] + 0.015
    mesh.box("tail", [0, B.roof_y(d3) + 0.035, -d3], [0.36, 0.022, 0.04])
    # exhausts
    for ex, ey in D.get("exhaust", []):
        zt = end_z(B, ex, ey, False)
        c = np.array([ex, ey, zt + 0.0])
        mesh.cyl("chrome", c, 0.042, 0.1, [0, 0, 1], 18, caps=False)
        mesh.cyl("under", c + np.array([0, 0, 0.001]), 0.034, 0.101, [0, 0, 1], 18, caps=True)
    # spoilers and wings
    sp = D.get("spoiler")
    if sp == "lip":
        t0 = B.top(0.12)
        hw0 = B.hw(0.12)
        mesh.box("paint", [0, t0 + 0.012, -0.07], [hw0 * 1.6, 0.018, 0.06], rot_x(0.25))
    elif sp == "ducktail":
        t0 = B.top(0.1)
        hw0 = B.hw(0.1)
        mesh.box("paint", [0, t0 + 0.03, -0.1], [hw0 * 1.85, 0.04, 0.2], rot_x(0.35))
        mesh.box("gloss", [0, t0 + 0.06, -0.01], [hw0 * 1.8, 0.012, 0.02])
    elif sp == "roof":  # over the top of the rear window, at the end of the roof
        dr = g[2] - 0.02
        ry = B.roof_y(g[2] + 0.04)
        mesh.box("paint", [0, ry + 0.012, -dr], [W * g[7] * 1.02, 0.026, 0.24], rot_x(-0.12))
        mesh.box("gloss", [0, ry - 0.006, -(dr - 0.1)], [W * g[7] * 0.98, 0.012, 0.04])
    elif sp == "wing":
        ty = B.top(0.25) + 0.32
        for sd in (1.0, -1.0):
            mesh.box("gloss", [sd * 0.45, ty - 0.15, -0.3], [0.04, 0.3, 0.16], rot_x(0.2))
        mesh.box("gloss", [0, ty, -0.2], [W * 0.92, 0.035, 0.32], rot_x(0.12))
        for sd in (1.0, -1.0):
            mesh.box("gloss", [sd * W * 0.46, ty - 0.05, -0.2], [0.02, 0.16, 0.36])
    if D.get("splitter"):
        span = B.hw(L - 0.1) * 1.8
        for k in range(12):  # in pieces that follow the curve of the nose
            xk = -span / 2 + span * (k + 0.5) / 12
            zs = end_z(B, xk, B.floor_y + 0.01, True)
            mesh.box("gloss", [xk, B.floor_y + 0.005, zs + 0.07], [span / 12 + 0.003, 0.018, 0.16])
    if D.get("rails"):
        for sd in (1.0, -1.0):
            x = sd * W / 2 * g[7] * 0.85
            mesh.box("gloss", [x, g[5] + 0.06, -(g[2] + g[3]) / 2], [0.04, 0.03, g[3] - g[2] + 0.2])
            for t in range(3):
                dz = lerp(g[2] - 0.05, g[3] + 0.05, t / 2)
                mesh.box("gloss", [x, g[5] + 0.035, -dz], [0.05, 0.05, 0.06])
    if D.get("hood") == "scoop":  # open front of the scoop
        d1 = L - 0.38
        ys = B.top(d1 - 0.36) + 0.05
        mesh.box("under", [0, ys + 0.012, -(d1 - 0.33)], [0.44, 0.03, 0.012])


class NoseBoxes:
    """Boxes laid on the curved nose: wide ones are split so they hug it."""

    def __init__(self, B, mesh):
        self.B = B
        self.mesh = mesh
        self.styler = Styler(B)

    def in_lamp(self, x, y):
        D = self.B.D
        if D.get("head") and self.styler.lamp(D["head"], x, y, "head"):
            return True
        return bool(D.get("round_head") and self.styler.round_lamp(x, y))

    def box(self, kind, c, size):
        x, y = c[0], c[1]
        w = size[0]
        n = max(1, int(w / 0.06))
        for k in range(n):
            xk = x - w / 2 + w * (k + 0.5) / n
            if self.in_lamp(xk, y) or self.in_lamp(xk, y - size[1] / 2) or self.in_lamp(xk, y + size[1] / 2):
                continue  # never across the headlamps
            z = end_z(self.B, xk, y, True) - 0.004
            self.mesh.box(kind, [xk, y, z], [w / n + 0.002, size[1], size[2]])


def add_openings(B, mesh):
    """Slats, mesh and fins laid across the dark openings."""
    D = B.D
    L = B.l
    hw = B.w / 2
    zf = 0.0
    real_mesh = mesh
    mesh = NoseBoxes(B, real_mesh)
    G = D.get("grille")
    if G:
        y0, y1 = G["y"]
        gw = G["w"] * hw
        kind = G["kind"]
        if kind in ("bars", "slot", "kidney"):
            n = 2 if kind == "slot" else max(3, int((y1 - y0) / 0.032))
            for k in range(n):
                y = lerp(y0, y1, (k + 0.5) / n)
                q = (y - y0) / (y1 - y0)
                half = gw * (1 - abs(2 * q - 1) ** 6) ** (1 / 6) * 0.94
                if kind == "kidney":
                    for sd in (1.0, -1.0):
                        mesh.box("chrome", [sd * (0.025 + half) / 2, y, zf], [half - 0.035, 0.008, 0.012])
                else:
                    mesh.box("chrome" if kind == "bars" else "gloss", [0, y, zf], [half * 2, 0.012, 0.014])
            if kind == "kidney":
                for sd in (1.0, -1.0):
                    for k in range(1, 6):
                        x = sd * lerp(0.03, gw, k / 6)
                        mesh.box("chrome", [x, (y0 + y1) / 2, zf], [0.006, (y1 - y0) * 0.8, 0.012])
        elif kind == "mesh":
            # a diamond mesh: two sets of diagonal strands
            nrow = max(3, int((y1 - y0) / 0.028))
            for k in range(nrow + 1):
                y = lerp(y0, y1, k / nrow)
                mesh.box("gloss", [0, y, zf], [gw * 2 * 0.96, 0.007, 0.012])
            ncol = int(gw * 2 / 0.05)
            for k in range(ncol + 1):
                x = lerp(-gw, gw, k / ncol) * 0.95
                mesh.box("gloss", [x, (y0 + y1) / 2, zf], [0.007, (y1 - y0) * 0.92, 0.012])
    I = D.get("intake")
    if I:
        y0, y1 = I["y"]
        gw = I["w"] * hw
        for k in range(3):
            y = lerp(y0, y1, (k + 1) / 4)
            mesh.box("gloss", [0, y, zf], [gw * 1.8, 0.01, 0.014])
        for sd in (1.0, -1.0):
            mesh.box("gloss", [sd * gw * 0.45, (y0 + y1) / 2, zf], [0.02, (y1 - y0) * 0.86, 0.016])
    mesh = real_mesh
    if D.get("diffuser"):
        for k in range(-3, 4):
            x = k * 0.16
            mesh.box("gloss", [x, B.floor_y + 0.08, end_z(B, x, B.floor_y + 0.08, False) - 0.1], [0.012, 0.15, 0.24])
    if D.get("hood") == "vents":
        g = B.g
        for sd in (1.0, -1.0):
            for k in range(7):
                d = lerp(g[1] + 0.27, g[1] + 0.58, k / 6)
                x = sd * 0.3
                y = top_y_at(B, d, 0.3)
                mesh.box("gloss", [x, y + 0.004, -d], [0.19, 0.008, 0.022], rot_x(-0.35))
    si = D.get("side_intake")
    if si:
        for k in range(4):
            y = lerp(si[2], si[3], (k + 1) / 5)
            dm = (si[0] + si[1]) / 2
            s = side_s_at_height(B, dm, y)
            if s is None:
                continue
            p, n = surface_point(B, dm, s)
            for sd in (1.0, -1.0):
                mesh.box("gloss", (p + n * 0.002) * np.array([sd, 1, 1]), [0.012, 0.01, (si[1] - si[0]) * 0.8])
    if D.get("gills"):
        a = B.axles[1]
        for k in range(4):
            d = a + 0.35 + k * 0.06
            s0 = 7.6
            p, n = surface_point(B, d, 8.2)
            for sd in (1.0, -1.0):
                mesh.box("chrome", (p + n * 0.004) * np.array([sd, 1, 1]), [0.008, 0.07, 0.012])


def add_stripes(B, mesh):
    """Twin racing stripes laid over boot, roof and bonnet (never the glass)."""
    g = B.g
    L = B.l
    spans = [(0.12, g[0] - 0.02), (g[2] + 0.02, g[3] - 0.02), (g[1] + 0.03, L - 0.28)]
    for x0, x1 in ((0.08, 0.15), (0.18, 0.25)):
        for d0, d1 in spans:
            if d1 - d0 < 0.05:
                continue
            n = max(2, int((d1 - d0) / 0.04))
            prev = None
            for k in range(n + 1):
                d = lerp(d0, d1, k / n)
                row = [np.array([x, top_y_at(B, d, x) + 0.0022, -d]) for x in (x0, x1)]
                if prev is not None:
                    for side in (1.0, -1.0):
                        m = np.array([side, 1, 1])
                        mesh.quad("accent", prev[0] * m, prev[1] * m, row[1] * m, row[0] * m, np.array([0, 1.0, 0]))
                prev = row


def rot_x(a):
    c, s = math.cos(a), math.sin(a)
    return np.array([[1, 0, 0], [0, c, -s], [0, s, c]])


# ------------------------------------------------------------------ output


def write_mesh(mesh, path):
    order = ["paint", "glass", "gloss", "dark", "under", "chrome", "accent", "head", "tail"]
    names = [k for k in order if k in mesh.surf and len(mesh.surf[k][0])]
    os.makedirs(os.path.dirname(path), exist_ok=True)
    total = 0
    with open(path, "wb") as f:
        f.write(b"CPE2")
        f.write(struct.pack("<I", len(names)))
        for k in names:
            pp = np.asarray(mesh.surf[k][0], np.float64).reshape(-1, 3)
            nn = np.asarray(mesh.surf[k][1], np.float64).reshape(-1, 3)
            nn /= np.maximum(np.linalg.norm(nn, axis=1, keepdims=True), 1e-9)
            key = np.round(np.concatenate([pp, nn], 1) * 20000).astype(np.int64)
            uq, inv = np.unique(key, axis=0, return_inverse=True)
            inv = inv.reshape(-1)
            first = np.zeros(len(uq), np.int64)
            first[inv[::-1]] = np.arange(len(inv))[::-1]
            vp = pp[first].astype(np.float32)
            vn = nn[first].astype(np.float32)
            idx = inv.astype(np.uint32)
            nb = k.encode()
            f.write(struct.pack("<I", len(nb)))
            f.write(nb)
            f.write(struct.pack("<I", len(vp)))
            f.write(vp.tobytes())
            f.write(vn.tobytes())
            f.write(struct.pack("<I", len(idx)))
            f.write(idx.tobytes())
            total += len(idx) // 3
    return total


def forge(name):
    D = DESIGNS[name]
    B = Body(D)
    for lq in (False, True):
        mesh = Mesh()
        build_body(B, lq, mesh)
        add_details(B, mesh, lq)
        if not lq:
            add_openings(B, mesh)
        if D.get("stripes"):
            add_stripes(B, mesh)
        path = os.path.join(OUT, name + ("_lq" if lq else "") + ".mesh")
        n = write_mesh(mesh, path)
        print("%-9s %s %6d triangles  %s" % (name, "LQ" if lq else "HQ", n, os.path.relpath(path)))


if __name__ == "__main__":
    names = sys.argv[1:] or list(DESIGNS)
    for nm in names:
        forge(nm)
