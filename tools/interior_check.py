#!/usr/bin/env python3
"""Checks that no car's interior pokes out of its bodywork.

For every car with its own interior (assets/models/car_X_parts/: the interior mesh, and the steering wheel where it sits),
each vertex of it looks out along the five ways out of a car (left, right, up, forwards, backwards): if it can see out
along any of them without meeting the body or the glass, it is outside the car. Tested against the body drawn near
(car_X.mesh) and against the light one drawn far away (car_X_lq.mesh, whose vertices are merged on a 6 cm grid, so its
skin can lie a few centimetres inside the real one): the game draws the interior only as near as the first (see
CarModel.build), but it is checked against both.

    python3 tools/interior_check.py [car_X ...]       (no names: every car with an interior)

Exits with 1 if any vertex is outside the near body.
"""
import glob
import json
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, ".."))
sys.path.insert(0, HERE)
import make_inner as mi  # noqa: E402  (read_cpe2)

CELL = 0.05
EPS = 1e-4


def triangles(path):
    surf = mi.read_cpe2(path)
    return np.vstack([p[ix.reshape(-1, 3)] for p, n, ix in surf.values()])


def quat_mat(q):
    x, y, z, w = q
    return np.array([[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
                     [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
                     [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]])


class Caster:
    """Rays along one axis (k, sign) against a set of triangles, binned on the plane across that axis."""

    def __init__(self, tris, k):
        self.k = k
        self.ij = [a for a in range(3) if a != k]
        t2 = tris[:, :, self.ij]
        lo = np.floor(t2.min(1) / CELL).astype(int)
        hi = np.floor(t2.max(1) / CELL).astype(int)
        self.bins = {}
        for n in range(len(tris)):
            for a in range(lo[n, 0], hi[n, 0] + 1):
                for b in range(lo[n, 1], hi[n, 1] + 1):
                    self.bins.setdefault((a, b), []).append(n)
        self.tris = tris

    def blocked(self, pts, sign):
        """For each point: does a ray from it along this axis (towards sign) meet a triangle?"""
        out = np.zeros(len(pts), bool)
        cells = np.floor(pts[:, self.ij] / CELL).astype(int)
        order = {}
        for n, c in enumerate(map(tuple, cells)):
            order.setdefault(c, []).append(n)
        i, j = self.ij
        for c, idx in order.items():
            cand = self.bins.get(c)
            if not cand:
                continue
            T = self.tris[cand]                      # (m, 3, 3)
            P = pts[idx]                             # (q, 3)
            a, b, cc = T[:, 0], T[:, 1], T[:, 2]
            # barycentric coordinates of each point in each triangle, on the plane across the axis
            v0 = (b - a)[:, [i, j]]
            v1 = (cc - a)[:, [i, j]]
            den = v0[:, 0] * v1[:, 1] - v1[:, 0] * v0[:, 1]
            ok = np.abs(den) > 1e-12
            if not ok.any():
                continue
            T, a, b, cc, v0, v1, den = T[ok], a[ok], b[ok], cc[ok], v0[ok], v1[ok], den[ok]
            w = P[:, None, [i, j]] - a[None, :, [i, j]]          # (q, m, 2)
            u = (w[..., 0] * v1[None, :, 1] - v1[None, :, 0] * w[..., 1]) / den[None]
            v = (v0[None, :, 0] * w[..., 1] - w[..., 0] * v0[None, :, 1]) / den[None]
            inside = (u >= -1e-9) & (v >= -1e-9) & (u + v <= 1 + 1e-9)
            depth = a[None, :, self.k] + u * (b - a)[None, :, self.k] + v * (cc - a)[None, :, self.k]
            hit = inside & ((depth - P[:, None, self.k]) * sign > EPS)
            out[idx] |= hit.any(1)
        return out


def outside(points, tris):
    """Which points can see out of the triangles' shell along any of the five ways out (x both ways, up, z both ways).
    (The points are nudged a fraction of a millimetre off the centre line and the grid of the model's sections, so a ray
    never runs exactly along a seam between triangles, where float rounding leaves hairline gaps.)"""
    points = points + np.array([0.00037, 0.00029, 0.00041])
    seen = np.zeros(len(points), bool)
    for k, signs in ((0, (1, -1)), (1, (1,)), (2, (1, -1))):
        cast = Caster(tris, k)
        for s in signs:
            seen |= ~cast.blocked(points, s)
    return seen


def interior_points(name):
    pdir = os.path.join(ROOT, "assets", "models", name + "_parts")
    man = json.load(open(os.path.join(pdir, "parts.json")))
    pts = []
    if man.get("cabin"):
        surf = mi.read_cpe2(os.path.join(pdir, man["cabin"]))
        pts.append(np.vstack([p[np.unique(ix)] for p, n, ix in surf.values()]))
    st = man.get("steer") or {}
    if st:
        surf = mi.read_cpe2(os.path.join(pdir, st["file"]))
        p = np.vstack([p[np.unique(ix)] for p, n, ix in surf.values()])
        pts.append(p @ quat_mat(st["rot"]).T + np.array(st["pos"]))
    return np.vstack(pts) if pts else np.zeros((0, 3))


def main():
    names = sys.argv[1:] or sorted(os.path.basename(os.path.dirname(p))[:-6] for p in glob.glob(os.path.join(ROOT, "assets", "models", "*_parts", "parts.json")))
    bad = 0
    for name in names:
        pts = interior_points(name)
        if not len(pts):
            continue
        res = []
        for body in (name + ".mesh", name + "_lq.mesh"):
            tris = triangles(os.path.join(ROOT, "assets", "models", body))
            out = outside(pts, tris)
            far = ""
            if out.any():
                # how far out: from each such vertex to the nearest vertex of the body
                bv = tris.reshape(-1, 3)
                d = [float(np.sqrt(((bv - p) ** 2).sum(1)).min()) for p in pts[out][:200]]
                far = " (up to %.1f cm from the skin, e.g. at x %.2f y %.2f z %.2f)" % (100 * max(d), *pts[out][int(np.argmax(d))])
            res.append("%s %d out%s" % ("near" if body.endswith("r.mesh") or not body.endswith("_lq.mesh") else "far", int(out.sum()), far))
            if not body.endswith("_lq.mesh") and out.any():
                bad += 1
        print("%-20s %6d interior vertices: %s" % (name, len(pts), "; ".join(res)))
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
