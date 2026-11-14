#!/usr/bin/env python3
"""Builds the cockpit's view of each car's bodywork from inside: the roof,
pillars and door tops, as a small mesh (assets/models/inner/NAME.inner).

The car meshes are one-sided shells that were split into paint and glass by
their texture, triangle by triangle, so the edge of every window is ragged
(teeth of a few centimetres). Seen from outside that does not matter, but
from the driver's seat the windscreen edge is half a metre away. So this tool
takes every triangle round the cabin that is seen from inside, paint and
glass alike, as an opaque shell, and describes the three openings the driver
looks out of (the windscreen and the two front side windows) as smooth
masks: for each, the plane of the glass and a small greyscale image of where
the glass is, blurred so the teeth melt away. The game cuts the shell open
wherever a mask is over one half, which leaves headliner, A-pillars and door
frames with clean curved edges, whatever the model's texture did.

File format: u32 vertex count, u32 index count, the vertex positions (3 x
float32 each), the indices (int32), then three window slots (windscreen,
left, right): u32 present, and if present 16 float32 (plane centre, normal,
u axis, v axis, then the mask's u0, v0, width, height in metres), u16 w,
u16 h and w * h mask bytes. Laid out so the game can read the big blocks
straight into packed arrays.

Usage: python3 tools/make_inner.py          (all player cars)
"""
import os
import struct
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
MODELS = os.path.join(HERE, "..", "assets", "models")
OUT = os.path.join(MODELS, "inner")

# the player's cars: the mesh each one is built from
CARS = ["hatchback", "sport_sedan", "compact_coupe", "starter_coupe", "car_kestrel", "car_vanta", "car_bruiser",
        "car_halcyon", "car_copperhead", "car_marshal", "car_static", "car_lastexit"]
SMOOTH_RINGS = 5


def read_cpe2(path):
    d = open(path, "rb").read()
    assert d[:4] == b"CPE2", path
    o = 4
    n = struct.unpack_from("<I", d, o)[0]
    o += 4
    out = {}
    for _ in range(n):
        ln = struct.unpack_from("<I", d, o)[0]
        o += 4
        name = d[o:o + ln].decode()
        o += ln
        nv = struct.unpack_from("<I", d, o)[0]
        o += 4
        pos = np.frombuffer(d, np.float32, nv * 3, o).reshape(-1, 3)
        o += nv * 12
        nor = np.frombuffer(d, np.float32, nv * 3, o).reshape(-1, 3)
        o += nv * 12
        ni = struct.unpack_from("<I", d, o)[0]
        o += 4
        idx = np.frombuffer(d, np.uint32, ni, o).astype(np.int64)
        o += ni * 4
        out[name] = (pos, nor, idx)
    return out


CELL = 0.001    # the shell keeps the model's own triangles (welded to 1 mm)
PIXEL = 0.005   # window mask resolution, metres
BLUR = 0.025    # how far the window masks are smoothed, metres
OPEN = 0.03     # glass patches narrower than twice this are frame, not window, metres


def plane_frame(pts, n_hint):
    """(centre, normal, u, v) of the best-fit plane through points; u runs across, v up the glass."""
    c = pts.mean(0)
    _, _, vt = np.linalg.svd(pts - c, full_matrices=False)
    n = vt[2]
    if n.dot(n_hint) < 0:
        n = -n
    up = np.array([0.0, 1.0, 0.0])
    u = np.cross(up, n)
    if np.linalg.norm(u) < 1e-6:
        u = np.array([1.0, 0.0, 0.0])
    u /= np.linalg.norm(u)
    v = np.cross(n, u)
    return c, n, u, v


def box_blur(img, r):
    k = 2 * r + 1
    for ax in (0, 1):
        pad = [(0, 0), (0, 0)]
        pad[ax] = (r + 1, r)
        cs = np.cumsum(np.pad(img, pad), axis=ax, dtype=np.float64)
        img = (np.take(cs, np.arange(k, cs.shape[ax]), axis=ax) - np.take(cs, np.arange(0, cs.shape[ax] - k), axis=ax)) / k
    return img


def opening(img, r):
    """Erode then dilate by r pixels: thin slivers and small specks of 'glass' in the frame disappear."""
    er = (box_blur(img, r) > 0.999).astype(np.float64)
    return (box_blur(er, r) > 0.001).astype(np.float64)


def closing(img, r):
    """Dilate then erode by r pixels: little teeth of frame that stick into the window are filled in."""
    di = (box_blur(img, r) > 0.001).astype(np.float64)
    return (box_blur(di, r) > 0.999).astype(np.float64)


def largest_patch(img):
    """Keep only the biggest connected area of a binary image."""
    h, w = img.shape
    label = np.zeros((h, w), np.int32)
    best, best_n, cur = 0, 0, 0
    for y0 in range(h):
        for x0 in range(w):
            if img[y0, x0] < 0.5 or label[y0, x0]:
                continue
            cur += 1
            stack = [(y0, x0)]
            label[y0, x0] = cur
            n = 0
            while stack:
                y, x = stack.pop()
                n += 1
                for yy, xx in ((y + 1, x), (y - 1, x), (y, x + 1), (y, x - 1)):
                    if 0 <= yy < h and 0 <= xx < w and img[yy, xx] > 0.5 and not label[yy, xx]:
                        label[yy, xx] = cur
                        stack.append((yy, xx))
            if n > best_n:
                best, best_n = cur, n
    return (label == best).astype(np.float64) if best else img


def raster_mask(tris_uv, margin=0.06):
    """Fill the triangles (n, 3, 2) of a window into a blurred greyscale mask; returns (u0, v0, w_m, h_m, bytes, w, h)."""
    lo = tris_uv.reshape(-1, 2).min(0) - margin
    hi = tris_uv.reshape(-1, 2).max(0) + margin
    w = int(np.ceil((hi[0] - lo[0]) / PIXEL))
    h = int(np.ceil((hi[1] - lo[1]) / PIXEL))
    img = np.zeros((h, w), np.float64)
    for t in tris_uv:
        q = (t - lo) / PIXEL
        x0, x1 = int(np.floor(q[:, 0].min())), int(np.ceil(q[:, 0].max()))
        y0, y1 = int(np.floor(q[:, 1].min())), int(np.ceil(q[:, 1].max()))
        xs, ys = np.meshgrid(np.arange(x0, x1 + 1) + 0.5, np.arange(y0, y1 + 1) + 0.5)
        a, b, c = q
        d = (b[1] - c[1]) * (a[0] - c[0]) + (c[0] - b[0]) * (a[1] - c[1])
        if abs(d) < 1e-12:
            continue
        l1 = ((b[1] - c[1]) * (xs - c[0]) + (c[0] - b[0]) * (ys - c[1])) / d
        l2 = ((c[1] - a[1]) * (xs - c[0]) + (a[0] - c[0]) * (ys - c[1])) / d
        inside = (l1 >= -0.02) & (l2 >= -0.02) & (l1 + l2 <= 1.02)
        yy = np.clip(ys[inside].astype(int) - 0, 0, h - 1)
        xx = np.clip(xs[inside].astype(int) - 0, 0, w - 1)
        img[yy, xx] = 1.0
    img = closing(img, int(round(OPEN / PIXEL)))
    img = opening(img, int(round(OPEN / PIXEL)))
    img = largest_patch(img)
    r = max(2, int(round(BLUR / PIXEL / 1.7)))
    for _ in range(3):
        img = box_blur(img, r)
    return lo[0], lo[1], w * PIXEL, h * PIXEL, np.clip(img * 255.0 + 0.5, 0, 255).astype(np.uint8), w, h


def build(name):
    src = os.path.join(MODELS, name + ".mesh")
    if not os.path.exists(src):
        src = os.path.join(MODELS, "cars", name + ".mesh")
    surf = read_cpe2(src)
    P, N, C = [], [], []
    for sname, cls in (("paint", 0), ("cargo", 0), ("dark", 0), ("gloss", 0), ("glass", 1)):
        if sname not in surf:
            continue
        pos, nor, idx = surf[sname]
        T = idx.reshape(-1, 3)
        P.append(pos[T])        # (t, 3, 3)
        N.append(nor[T])
        C.append(np.full(len(T), cls, np.int8))
    P = np.concatenate(P).astype(np.float64)
    N = np.concatenate(N).astype(np.float64)
    C = np.concatenate(C)
    gl = P[C == 1].reshape(-1, 3)
    gl = gl[gl[:, 1] > 0.8]
    d_base = (-gl[:, 2]).max()                     # the windscreen base
    roof = float(gl[:, 1].max())
    belt = float(np.percentile(gl[:, 1], 6))
    cen = P.mean(1)
    ng = np.cross(P[:, 1] - P[:, 0], P[:, 2] - P[:, 0])      # glTF winding: counter-clockwise is the front
    ng = ng / np.maximum(np.linalg.norm(ng, axis=1, keepdims=True), 1e-9)

    # --- the windows: glass triangles sorted by which way they face
    glass = (C == 1) & (cen[:, 1] > belt - 0.02) & (-cen[:, 2] > d_base - 3.2) & (-cen[:, 2] < d_base + 0.2)
    groups = {
        "windscreen": glass & (ng[:, 2] < -0.3) & (ng[:, 1] > 0.05),
        "left": glass & (ng[:, 0] < -0.5),
        "right": glass & (ng[:, 0] > 0.5),
    }
    slots = []
    info = []
    for kind in ("windscreen", "left", "right"):
        sel = np.where(groups[kind])[0]
        if len(sel) < 20:
            slots.append(None)
            continue
        pts = P[sel].reshape(-1, 3)
        c, n, u, v = plane_frame(pts, ng[sel].mean(0))
        tri_uv = np.stack([np.stack([(P[sel][:, k] - c) @ u, (P[sel][:, k] - c) @ v], 1) for k in range(3)], 1)
        u0, v0, wm, hm, mask, w, h = raster_mask(tri_uv)
        slots.append((c, n, u, v, u0, v0, wm, hm, mask, w, h))
        info.append("%s %d tris %dx%d" % (kind, len(sel), w, h))

    # --- the shell: every triangle above the belt line that is seen from inside, thinned out
    d_lo = d_base - 1.6
    d_hi = d_base + 0.35
    # a triangle goes only if it faces every place the driver's eye could be (the pillars are seen edge-on)
    faces_eye = np.ones(len(cen), bool)
    for ex in (-0.45, -0.3):
        for ey in (roof - 0.28, roof - 0.1):
            for ed in (1.5, 1.15, 0.8):
                ev = np.array([ex, ey, -(d_base - ed)]) - cen
                ev = ev / np.maximum(np.linalg.norm(ev, axis=1, keepdims=True), 1e-9)
                faces_eye &= (ng * ev).sum(1) > 0.05
    keep = (cen[:, 1] > belt - 0.3) & (-cen[:, 2] > d_lo) & (-cen[:, 2] < d_hi) & ~faces_eye
    kt = np.where(keep)[0]
    key = np.round(P.reshape(-1, 3) * 1000).astype(np.int64)
    uq, first, inv = np.unique(key, axis=0, return_index=True, return_inverse=True)
    inv = inv.reshape(-1)
    tv = inv.reshape(-1, 3)
    upos = P.reshape(-1, 3)[first]
    nor_u = np.stack([np.bincount(inv, weights=N.reshape(-1, 3)[:, a], minlength=len(uq)) for a in range(3)], 1)
    ck = np.round(upos / CELL).astype(np.int64)
    cu, cinv = np.unique(ck, axis=0, return_inverse=True)
    cinv = cinv.reshape(-1)
    cc = np.bincount(cinv, minlength=len(cu)).astype(np.float64)
    cpos = np.stack([np.bincount(cinv, weights=upos[:, a], minlength=len(cu)) for a in range(3)], 1) / cc[:, None]
    cnor = np.stack([np.bincount(cinv, weights=nor_u[:, a], minlength=len(cu)) for a in range(3)], 1)
    cnor /= np.maximum(np.linalg.norm(cnor, axis=1, keepdims=True), 1e-9)
    tri = cinv[tv[kt]]
    ok = (tri[:, 0] != tri[:, 1]) & (tri[:, 1] != tri[:, 2]) & (tri[:, 0] != tri[:, 2])
    tri = tri[ok]
    used, remap = np.unique(tri.reshape(-1), return_inverse=True)
    vp, vn = cpos[used], cnor[used]
    idx = remap.reshape(-1, 3)[:, [0, 2, 1]].reshape(-1)    # Godot winds front faces clockwise
    assert len(vp) < 65536
    print(name, "roof %.2f belt %.2f:" % (roof, belt), "; ".join(info), "->", len(vp), "vertices,", len(idx) // 3, "triangles")
    os.makedirs(OUT, exist_ok=True)
    with open(os.path.join(OUT, name + ".inner"), "wb") as f:
        f.write(struct.pack("<II", len(vp), len(idx)))
        f.write(vp.astype("<f4").tobytes())
        f.write(idx.astype("<i4").tobytes())
        for sl in slots:
            if sl is None:
                f.write(struct.pack("<I", 0))
                continue
            c, n, u, v, u0, v0, wm, hm, mask, w, h = sl
            f.write(struct.pack("<I", 1))
            f.write(struct.pack("<16f", *c, *n, *u, *v, u0, v0, wm, hm))
            f.write(struct.pack("<HH", w, h))
            f.write(mask.tobytes())


if __name__ == "__main__":
    for n in (sys.argv[1:] or CARS):
        build(n)
