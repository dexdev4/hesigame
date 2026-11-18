#!/usr/bin/env python3
"""Converts a car model in the "Redline Rush garage exporter" layout into a game mesh.

That layout (unlike the older models, which convert_coupe.py splits by their painted texture) names every part by its
material, and keeps the glass, the interior, the steering wheel, the lamps, the wheels and the brake callipers as nodes of
their own. The car faces -z with its tail at +z, metres, y up (so only the tail is moved to z = 0: CarModel space is x right,
y up, the rear bumper at z = 0 and the nose towards -z).

    python3 tools/convert_garage.py MODEL.glb OUT.mesh [lq]

writes OUT.mesh (CPE2, the surfaces CarModel draws) and, without lq, tools/profiles/OUT.json (the measurements
tools/gen_imported.py turns into the car's profile). With lq: the light distance version (vertices merged on a 6 cm grid).

Left out: the interior and the steering wheel (the game builds each car's cockpit itself), the wheels and the callipers (the
game's own wheels, in the rim style chosen in the workshop, stand where the model's wheels are).
"""
import json
import os
import struct
import sys

import numpy as np

src, out = sys.argv[1:3]
LQ = "lq" in sys.argv[3:]

# material -> game surface (CarModel: paint, glass, dark, gloss, under, chrome, plate, head, headlens, grille, tail)
BY_MAT = {
    "Paint": "paint", "Trim_Black": "gloss", "Matte_Black": "dark", "Interior_Shelf": "dark", "Wheel_Well": "under",
    "Grille_Mesh": "grille", "Headlight_Housing": "gloss", "Dark": "dark", "Taillight_Lens": "tail", "Satin_Metal": "chrome",
    "Plate": "plate", "Chrome": "chrome", "Rim_Inner": "gloss", "Glass": "glass",
    "Light_DRL": "head", "Light_Projector": "head", "Light_Indicator": "head", "Light_Tail": "tail",
}
SKIP_NODES = ("Interior", "SteeringWheel", "Wheel_", "Caliper_")

d = open(src, "rb").read()
ln = struct.unpack("<I", d[12:16])[0]
j = json.loads(d[20:20 + ln])
off = 20 + ln
bl = struct.unpack("<I", d[off:off + 4])[0]
B = d[off + 8:off + 8 + bl]
CT = {5126: np.float32, 5123: np.uint16, 5125: np.uint32, 5121: np.uint8}
NC = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}


def acc(i):
    a = j["accessors"][i]
    bv = j["bufferViews"][a["bufferView"]]
    o = bv.get("byteOffset", 0) + a.get("byteOffset", 0)
    n = a["count"] * NC[a["type"]]
    arr = np.frombuffer(B, dtype=CT[a["componentType"]], count=n, offset=o).astype(np.float64 if a["componentType"] == 5126 else np.int64)
    return arr.reshape(a["count"], NC[a["type"]]) if NC[a["type"]] > 1 else arr


def quat_mat(q):
    x, y, z, w = q
    return np.array([[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
                     [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
                     [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]])


def node_xf(n):
    R = quat_mat(n["rotation"]) if "rotation" in n else np.eye(3)
    S = np.diag(n.get("scale", [1, 1, 1]))
    return R @ S, np.array(n.get("translation", [0, 0, 0]), float)


root = j["nodes"][j["scenes"][j.get("scene", 0)]["nodes"][0]]
assert "matrix" not in root and root.get("translation", [0, 0, 0]) == [0, 0, 0] or "translation" not in root, "a moved root node is not handled"
parts = {}      # surface -> [positions (n*3,3) model space, normals]
wheels = []     # [name, translation, tyre width]
for ci in root.get("children", []):
    n = j["nodes"][ci]
    name = n.get("name", "")
    M, t = node_xf(n)
    if name.startswith("Wheel_"):
        prim = j["meshes"][n["mesh"]]["primitives"][0]
        wp = acc(prim["attributes"]["POSITION"])
        wheels.append([name, t, float(wp[:, 0].max() - wp[:, 0].min()), float(wp[:, 1].max())])
        continue
    if name.startswith(SKIP_NODES) or "mesh" not in n:
        continue
    for q in j["meshes"][n["mesh"]]["primitives"]:
        mname = j["materials"][q["material"]].get("name", "") if "material" in q else ""
        kind = BY_MAT.get(mname)
        if kind is None:
            print("leaving out", name, mname)
            continue
        P = acc(q["attributes"]["POSITION"]) @ M.T + t
        N = acc(q["attributes"]["NORMAL"]) @ M.T
        T = acc(q["indices"]).reshape(-1) if "indices" in q else np.arange(len(P))
        # a flat part on the nose or the tail (lamps, grille, plate) that faces into the car is turned round: the exporter
        # wrote the nose's lamps and grille facing backwards, and the game would never draw them (back faces are not drawn)
        zc = float(P[:, 2].mean())
        nz = float(N[:, 2].mean())
        if (zc < -1.5 and nz > 0.5) or (zc > 1.5 and nz < -0.5):
            print("turning round", name, mname, "(it faced into the car)")
            N = -N
            T = T.reshape(-1, 3)[:, [0, 2, 1]].reshape(-1)
        s = parts.setdefault(kind, [[], []])
        s[0].append(P[T])
        s[1].append(N[T])

# the rearmost point of the car (a chrome bumper, the exhausts) goes to z = 0, so the hit box takes in all of it; where the
# model's own number plate is goes into the profile ("plate": [y, z]), and the game puts its plate there
REAR = float(np.concatenate([np.concatenate(v[0]) for k, v in parts.items() if k != "glass"])[:, 2].max())


def to_game(p):
    return np.stack([p[:, 0], p[:, 1], p[:, 2] - REAR], 1)


res = {}
for kind, (ps, ns) in parts.items():
    pp = to_game(np.concatenate(ps))
    nn = np.concatenate(ns)
    nn /= np.maximum(np.linalg.norm(nn, axis=1, keepdims=True), 1e-9)
    res[kind] = (pp.astype(np.float32), nn.astype(np.float32))
    print(kind, len(pp) // 3, "tris")


def measure():
    """The car's proportions, as convert_coupe.py measures them (tools/gen_imported.py reads them)."""
    P0 = np.concatenate([res[k][0] for k in res if k in ("paint", "gloss", "dark", "chrome", "under", "grille", "plate", "tail", "head")])
    G = res["glass"][0]
    L = float(-P0[:, 2].min())
    low = P0[P0[:, 1] < 0.8]   # (below the mirrors)
    W = float(2 * np.abs(low[:, 0]).max())
    D = -P0[:, 2]
    roof0 = float(max(P0[:, 1].max(), G[:, 1].max()))
    side = G[np.abs(G[:, 0]) > 0.45]
    belt = float(np.percentile(side[:, 1], 8)) if len(side) else 0.9
    up = G[G[:, 1] > belt + 0.07]
    gd = -up[:, 2] if len(up) else -G[:, 2]
    g0 = float(np.percentile(gd, 0.5))
    g1 = float(np.percentile(gd, 99.5))
    allp = np.concatenate([P0, G])
    hi = -allp[allp[:, 1] > roof0 - 0.045, 2]
    g2 = float(hi.min())
    g3 = float(hi.max())
    wbase = float(np.abs(side[:, 0]).max()) if len(side) else W / 2 * 0.8
    wsel = up[(-up[:, 2]) > g1 - 0.25]
    ws_hw = float(np.abs(wsel[:, 0]).max()) if len(wsel) else wbase * 0.7
    top = allp[allp[:, 1] > roof0 - 0.08]
    wroof = float(np.abs(top[:, 0]).max()) if len(top) else W / 2
    body = []
    for dd in [0.0, 0.1, 0.3, 0.7, 1.2, 1.8, 2.4, 3.0, 3.5, 3.9, 4.2, L]:
        if dd > L:
            continue
        sel = np.abs(D - dd) < 0.06
        if not sel.any():
            continue
        tp = float(P0[sel, 1].max())
        if g0 < dd < g1:
            tp = min(tp, belt + 0.04)
        body.append([round(dd, 3), round(tp, 3), round(float(np.abs(P0[sel, 0]).max()) / (W / 2), 3)])
    front = [w for w in wheels if w[1][2] < 0]
    rear = [w for w in wheels if w[1][2] >= 0]
    r = float(np.mean([w[3] for w in wheels]))
    rear_d = float(np.mean([REAR - w[1][2] for w in rear]))
    front_d = float(np.mean([REAR - w[1][2] for w in front]))
    wx = [float(np.mean([abs(w[1][0]) for w in rear])), float(np.mean([abs(w[1][0]) for w in front]))]
    tyre = float(np.mean([w[2] for w in wheels]))
    axles = sorted(set(round(REAR - w[1][2], 2) for w in wheels))
    plate = None
    if "plate" in res:
        pp = res["plate"][0]
        plate = [round(float((pp[:, 1].min() + pp[:, 1].max()) / 2), 3), round(float(pp[:, 2].max()), 3)]
    return {"plate": plate, "L": round(L, 3), "W": round(W, 3), "roof": round(roof0, 3), "belt": round(belt, 3),
            "gh": [round(g0, 3), round(g1, 3), round(g2, 3), round(g3, 3), round(belt, 3), round(roof0, 3), round(wbase / (W / 2), 3), round(wroof / (W / 2), 3)],
            "body": body, "wheel": [round(r, 3), round(rear_d, 3), round(front_d, 3)], "wheel_x": [round(wx[0], 3), round(wx[1], 3)],
            "tyre": round(tyre, 3), "ws_hw": round(ws_hw, 3), "axles": [float(a) for a in axles]}


if not LQ:
    prof = measure()
    pdir = os.path.join(os.path.dirname(os.path.abspath(__file__)), "profiles")
    os.makedirs(pdir, exist_ok=True)
    json.dump(prof, open(os.path.join(pdir, os.path.splitext(os.path.basename(out))[0] + ".json"), "w"))
    print("profile", {k: prof[k] for k in ("L", "W", "roof", "belt", "gh", "wheel", "wheel_x", "tyre", "axles")})

# binary, as convert_coupe.py writes it: magic, surface count, then per surface: name, vertex count, positions, normals,
# index count, indices (vertices shared where position and normal match)
order = ["paint", "glass", "dark", "under", "chrome", "gloss", "grille", "plate", "headlens", "head", "tail"]
with open(out, "wb") as f:
    f.write(b"CPE2")
    names = [k for k in order if k in res]
    f.write(struct.pack("<I", len(names)))
    for k in names:
        pp, nn = res[k]
        if LQ:
            key = np.round(pp / 0.06).astype(np.int64)
            uq, inv = np.unique(key, axis=0, return_inverse=True)
            inv = inv.reshape(-1)
            cnt = np.bincount(inv, minlength=len(uq)).astype(np.float64)
            vp = np.stack([np.bincount(inv, weights=pp[:, a], minlength=len(uq)) for a in range(3)], 1) / cnt[:, None]
            vn = np.stack([np.bincount(inv, weights=nn[:, a], minlength=len(uq)) for a in range(3)], 1)
            vn /= np.maximum(np.linalg.norm(vn, axis=1, keepdims=True), 1e-9)
            tri = inv.reshape(-1, 3)
            ok = (tri[:, 0] != tri[:, 1]) & (tri[:, 1] != tri[:, 2]) & (tri[:, 0] != tri[:, 2])
            idx = tri[ok].reshape(-1).astype(np.uint32)
        else:
            key = np.round(np.concatenate([pp, nn], 1) * 20000).astype(np.int64)
            uq, inv = np.unique(key, axis=0, return_inverse=True)
            inv = inv.reshape(-1)
            first = np.zeros(len(uq), np.int64)
            first[inv[::-1]] = np.arange(len(inv))[::-1]
            vp = pp[first]
            vn = nn[first]
            idx = inv.astype(np.uint32)
        nb = k.encode()
        f.write(struct.pack("<I", len(nb)))
        f.write(nb)
        f.write(struct.pack("<I", len(vp)))
        f.write(vp.astype(np.float32).tobytes())
        f.write(vn.astype(np.float32).tobytes())
        f.write(struct.pack("<I", len(idx)))
        f.write(idx.tobytes())
        print(k, "verts", len(vp), "idx", len(idx))
print("wrote", out)
