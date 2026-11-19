#!/usr/bin/env python3
"""Converts a car model in the "Redline Rush garage exporter" layout into a game mesh.

That layout (unlike the older models, which convert_coupe.py splits by their painted texture) names every part by its
material, and keeps the glass, the interior, the steering wheel, the lamps, the wheels and the brake callipers as nodes of
their own. Material names are either the designer's own export's ("Trim_Black", see BY_MAT) or tools/garage/export.js's,
"category:key" (the category is the game's surface: "gloss:trim", "dark:tl"). Colours are as the garage designer keeps
them: linear, a 2.2 power of the colour it was given (so the 2.2 root gives back exactly the designer's colour). The car faces -z with its tail at +z, metres, y up (so only the tail is moved to z = 0: CarModel space is x right,
y up, the rear bumper at z = 0 and the nose towards -z).

    python3 tools/convert_garage.py MODEL.glb OUT.mesh [lq]

writes OUT.mesh (CPE2, the surfaces CarModel draws) and, without lq, tools/profiles/OUT.json (the measurements
tools/gen_imported.py turns into the car's profile). With lq: the light distance version (vertices merged on a 6 cm grid).

The interior, the steering wheel, the wheels and the brake callipers go into OUT_parts/ (see the end), for the game to put on
the car; the profile also says what colour the inside of the body is ("back": the designer draws the back faces of the body
and the greenhouse in it, seen through the glass), and where the driver's eyes are ("eye").
"""
import json
import os
import struct
import sys

import numpy as np

src, out = sys.argv[1:3]
LQ = "lq" in sys.argv[3:]
GRID = next((float(a[5:]) for a in sys.argv[3:] if a.startswith("grid=")), 0.06)   # the light version's merge grid, metres

# material -> game surface (CarModel: paint, glass, dark, gloss, under, chrome, plate, head, headlens, grille, tail)
BY_MAT = {
    "Paint": "paint", "Trim_Black": "gloss", "Matte_Black": "dark", "Interior_Shelf": "dark", "Wheel_Well": "under",
    "Grille_Mesh": "grille", "Headlight_Housing": "gloss", "Dark": "dark", "Taillight_Lens": "dark", "Satin_Metal": "chrome",
    "Plate": "plate", "Chrome": "chrome", "Rim_Inner": "gloss", "Glass": "glass",
    "Light_DRL": "head", "Light_Projector": "head", "Light_Indicator": "headlens", "Light_Tail": "tail",
}
CATEGORIES = {"paint", "glass", "dark", "gloss", "under", "chrome", "plate", "head", "headlens", "grille", "tail", "brake"}
SKIP_NODES = ("Interior", "SteeringWheel", "Wheel_", "Caliper_")


def kind_of(mname):
    """The game surface a material goes into: by its name in the designer's own export, or by its category (export.js)."""
    if mname in BY_MAT:
        return BY_MAT[mname]
    cat = mname.split(":")[0] if ":" in mname else None
    return cat if cat in CATEGORIES else None

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


def srgb(c):
    """A linear colour value as the designer's colour (it keeps colours as a 2.2 power of the colour it was given)."""
    c = max(0.0, min(1.0, float(c)))
    return c ** (1 / 2.2)


def tex_average(ti):
    """The average colour (linear) of a texture embedded in the file."""
    import io
    from PIL import Image
    img = j["images"][j["textures"][ti]["source"]]
    bv = j["bufferViews"][img["bufferView"]]
    o = bv.get("byteOffset", 0)
    a = np.asarray(Image.open(io.BytesIO(B[o:o + bv["byteLength"]])).convert("RGB"), dtype=np.float64) / 255.0
    lin = np.where(a <= 0.04045, a / 12.92, ((a + 0.055) / 1.055) ** 2.4)
    return lin.reshape(-1, 3).mean(0)


def mat_tag(m):
    """A material as it is written into a surface's name: colour (sRGB), metalness, roughness, clear coat and its roughness,
    the glow (colour, strength), the pattern the game's shader draws on it (0 none, see car_paint.gdshader) and whether it is a
    lamp lit only with the headlights (1: see CarModel.material_of): "e1a11a~0.00~0.42~1.00~0.03~000000~0.0~0~0"."""
    pbr = m.get("pbrMetallicRoughness", {})
    c = list(pbr.get("baseColorFactor", [1, 1, 1, 1]))
    if "baseColorTexture" in pbr:   # (a texture darkens the colour: the game has no texture for it, so the colour takes its average)
        avg = tex_average(pbr["baseColorTexture"]["index"])
        c = [c[k] * avg[k] for k in range(3)] + c[3:]
    hexc = "".join("%02x" % int(round(srgb(v) * 255)) for v in c[:3])
    ext = m.get("extensions", {})
    cc = ext.get("KHR_materials_clearcoat", {})
    e = m.get("emissiveFactor", [0, 0, 0])
    es = float(ext.get("KHR_materials_emissive_strength", {}).get("emissiveStrength", 1.0)) if any(v > 0 for v in e) else 0.0
    ehex = "".join("%02x" % int(round(srgb(v) * 255)) for v in e[:3])
    ex = m.get("extras", {})
    return "%s~%.2f~%.2f~%.2f~%.2f~%s~%.1f~%d~%d" % (hexc, float(pbr.get("metallicFactor", 1.0)), float(pbr.get("roughnessFactor", 1.0)),
        float(cc.get("clearcoatFactor", 0.0)), float(cc.get("clearcoatRoughnessFactor", 0.0)), ehex, es, int(ex.get("pattern", 0)), int(ex.get("beam", 0)))


def glass_tag(m):
    """Glass as it is written into a surface's name: its tint (sRGB) and how opaque it is."""
    pbr = m.get("pbrMetallicRoughness", {})
    c = pbr.get("baseColorFactor", [0, 0, 0, 0.5])
    hexc = "".join("%02x" % int(round(srgb(v) * 255)) for v in c[:3])
    return "glass~%s~%.2f~%.2f" % (hexc, float(c[3]) if len(c) > 3 else 0.5, float(pbr.get("roughnessFactor", 0.05)))


PLAIN = ("paint",)   # (the paint is the one the workshop sets; everything else is the model's own)


def exact(kind, m):
    """The surface a part goes into: the game's own for PLAIN ones, otherwise its category with the model's exact material
    ("gloss~0b0c0e~0.00~0.42~0.25~0.03~000000~0.0"): the game still treats it as its category (hit box, cabin shell), and draws it as the model has it."""
    if kind == "glass":
        return glass_tag(m)   # (the model's own tint and how much of the cabin shows through)
    if kind in PLAIN:
        return kind
    return kind + "~" + mat_tag(m)


def right_way_out(P, N, T, label, liner=False, ends=(-2.0, 2.0)):
    """Turn round the pieces of a part that the exporter wrote inside out (the side mirrors: every face pointing in), and flat
    panels on the nose or tail that face into the car (the lamps and grille): the game draws front faces only, and lights a
    face by its normal. A piece is a run of triangles joined by shared corners."""
    tri = T.reshape(-1, 3)
    key = np.round(P / 1e-4).astype(np.int64)
    _, vid = np.unique(key, axis=0, return_inverse=True)
    vid = vid.reshape(-1)
    parent = np.arange(vid.max() + 1)

    def find(a):
        while parent[a] != a:
            parent[a] = parent[parent[a]]
            a = parent[a]
        return a
    for a, b, c in vid[tri]:
        ra, rb, rc = find(a), find(b), find(c)
        parent[rb] = ra
        parent[find(rc)] = ra
    comp = np.array([find(v) for v in vid[tri[:, 0]]])
    flip = np.zeros(len(tri), bool)
    for cid in np.unique(comp):
        sel = comp == cid
        pts = P[tri[sel]]
        cen = pts.reshape(-1, 3).mean(0)
        size = pts.reshape(-1, 3).max(0) - pts.reshape(-1, 3).min(0)
        g = np.cross(pts[:, 1] - pts[:, 0], pts[:, 2] - pts[:, 0])
        if size.min() > 0.01 and sel.sum() >= 12:
            # a closed solid (nearly every edge shared by two triangles) whose faces all point in: inside out. (A wheel-arch
            # liner faces in and is meant to: it is seen from the wheel's side.)
            e = np.sort(np.concatenate([vid[tri[sel]][:, [0, 1]], vid[tri[sel]][:, [1, 2]], vid[tri[sel]][:, [2, 0]]]), axis=1)
            _, cnt = np.unique(e, axis=0, return_counts=True)
            outward = float((np.sum(g * (pts.mean(1) - cen), 1) > 0).mean())
            if float((cnt == 2).mean()) > 0.8 and outward < 0.1 and not liner:
                flip |= sel
        else:
            nz = float(N[tri[sel]].reshape(-1, 3)[:, 2].mean())
            if (cen[2] < ends[0] + 0.25 and nz > 0.5) or (cen[2] > ends[1] - 0.25 and nz < -0.5):   # (on the nose, or the tail)
                flip |= sel
    if flip.any():
        print("turning round", int(flip.sum()), "triangles of", label, "(they faced inwards)")
        tri = tri.copy()
        tri[flip] = tri[flip][:, [0, 2, 1]]
        N = N.copy()
        N[np.unique(tri[flip])] *= -1.0
    return N, tri.reshape(-1)


root = j["nodes"][j["scenes"][j.get("scene", 0)]["nodes"][0]]
assert "matrix" not in root and root.get("translation", [0, 0, 0]) == [0, 0, 0] or "translation" not in root, "a moved root node is not handled"
_bz = [(j["accessors"][q["attributes"]["POSITION"]]["min"][2], j["accessors"][q["attributes"]["POSITION"]]["max"][2])
       for q in j["meshes"][j["nodes"][next(i for i in root["children"] if j["nodes"][i].get("name") == "Body")]["mesh"]]["primitives"]]
ENDS = (min(a for a, b in _bz), max(b for a, b in _bz))   # the nose and the tail of the body, along z
parts = {}      # surface -> [positions (n*3,3) model space, normals]
wheels = []     # [name, translation, tyre width, radius]
extras = []     # the parts the body leaves out: [name, node, rotation, translation] (written to the car's parts folder)
for ci in root.get("children", []):
    n = j["nodes"][ci]
    name = n.get("name", "")
    M, t = node_xf(n)
    if name.startswith("Wheel_"):
        prim = j["meshes"][n["mesh"]]["primitives"][0]
        wp = acc(prim["attributes"]["POSITION"])
        wheels.append([name, t, float(wp[:, 0].max() - wp[:, 0].min()), float(wp[:, 1].max()), float(n.get("extras", {}).get("rim", 0.0))])
    if name.startswith(SKIP_NODES) and "mesh" in n:
        extras.append([name, n, M, t])
    if name.startswith(SKIP_NODES) or "mesh" not in n:
        continue
    for q in j["meshes"][n["mesh"]]["primitives"]:
        mname = j["materials"][q["material"]].get("name", "") if "material" in q else ""
        kind = kind_of(mname)
        if kind is None:
            print("leaving out", name, mname)
            continue
        P = acc(q["attributes"]["POSITION"]) @ M.T + t
        N = acc(q["attributes"]["NORMAL"]) @ M.T
        T = acc(q["indices"]).reshape(-1) if "indices" in q else np.arange(len(P))
        N, T = right_way_out(P, N, T, name + " " + mname, kind == "under", ENDS)
        s = parts.setdefault(exact(kind, j["materials"][q["material"]]), [[], []])
        s[0].append(P[T])
        s[1].append(N[T])

# the rearmost point of the car (a chrome bumper, the exhausts) goes to z = 0, so the hit box takes in all of it; where the
# model's own number plate is goes into the profile ("plate": [y, z]), and the game puts its plate there
REAR = float(np.concatenate([np.concatenate(v[0]) for k, v in parts.items() if k.split("~")[0] != "glass"])[:, 2].max())


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
    P0 = np.concatenate([res[k][0] for k in res if k.split("~")[0] in ("paint", "gloss", "dark", "chrome", "under", "grille", "plate", "tail", "head", "headlens")])
    G = np.concatenate([res[k][0] for k in res if k.split("~")[0] == "glass"])
    L = float(-P0[:, 2].min())
    D = -P0[:, 2]
    roof0 = float(max(P0[:, 1].max(), G[:, 1].max()))
    side = G[np.abs(G[:, 0]) > 0.45]
    belt = float(np.percentile(side[:, 1], 8)) if len(side) else 0.9
    up = G[G[:, 1] > belt + 0.07]
    gd = -up[:, 2] if len(up) else -G[:, 2]
    g0 = float(np.percentile(gd, 0.5))
    g1 = float(np.percentile(gd, 99.5))
    # the width of the body and the tyres, without the door mirrors (which stand out above the beltline beside the front of
    # the side windows: on a low car they hang below 0.8 m), as tools/make_hulls.py outlines the body
    mirror = (P0[:, 1] > belt - 0.06) & (D > g1 - 0.55) & (D < g1 + 0.4)
    W = float(2 * max(np.abs(P0[~mirror, 0]).max(), max((abs(w[1][0]) + w[2] / 2 for w in wheels), default=0.0)))
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
        lo = sel & (P0[:, 1] < 0.8)   # (the width below the mirrors)
        body.append([round(dd, 3), round(tp, 3), round(float(np.abs(P0[lo if lo.any() else sel, 0]).max()) / (W / 2), 3)])
    front = [w for w in wheels if w[1][2] < 0]
    rear = [w for w in wheels if w[1][2] >= 0]
    r = float(np.mean([w[3] for w in wheels]))
    rear_d = float(np.mean([REAR - w[1][2] for w in rear]))
    front_d = float(np.mean([REAR - w[1][2] for w in front]))
    wx = [float(np.mean([abs(w[1][0]) for w in rear])), float(np.mean([abs(w[1][0]) for w in front]))]
    tyre = float(np.mean([w[2] for w in wheels]))
    axles = sorted(set(round(REAR - w[1][2], 2) for w in wheels))
    plate = None
    plates = [res[k][0] for k in res if k.split("~")[0] == "plate"]
    if plates:  # (the model's own number plate at the back: the game letters that one)
        pp = np.concatenate(plates)
        pp = pp[pp[:, 2] > -0.6]
        if len(pp):
            plate = [round(float((pp[:, 1].min() + pp[:, 1].max()) / 2), 3), round(float(pp[:, 2].max()), 3)]
    pm = next((m for m in j["materials"] if m.get("name") in ("Paint", "paint:paint")), None)
    paint_pbr = None
    if pm:
        pbr = pm.get("pbrMetallicRoughness", {})
        c = pbr.get("baseColorFactor", [1, 1, 1, 1])
        cc = pm.get("extensions", {}).get("KHR_materials_clearcoat", {})
        paint_pbr = ["#" + "".join("%02x" % int(round(srgb(v) * 255)) for v in c[:3]), float(pbr.get("metallicFactor", 0.0)), float(pbr.get("roughnessFactor", 0.5)),
                     float(cc.get("clearcoatFactor", 0.0)), float(cc.get("clearcoatRoughnessFactor", 0.0))]
    inside = j.get("extras", {}).get("interior", {})   # (export.js: the colours of the inside, and the driver's eyes)
    eye = None
    if "eye" in inside:
        e = inside["eye"]
        eye = [round(float(e[0]), 3), round(float(e[1]), 3), round(float(e[2]) - REAR, 3)]
    rims = [w[4] for w in wheels if len(w) > 4 and w[4] > 0]
    return {"plate": plate, "paint_pbr": paint_pbr, "back": inside.get("shell"), "shelf": inside.get("shelf"), "eye": eye,
            "rim": round(float(np.mean(rims)), 4) if rims else None, "L": round(L, 3), "W": round(W, 3), "roof": round(roof0, 3), "belt": round(belt, 3),
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
ORDER = ["paint", "glass", "dark", "under", "chrome", "gloss", "grille", "plate", "headlens", "head", "tail", "brake"]


def write_cpe2(path, res, lq=False):
    def rank(k):
        c = k.split("~")[0]
        return (ORDER.index(c) if c in ORDER else len(ORDER), k)
    with open(path, "wb") as f:
        f.write(b"CPE2")
        names = sorted(res, key=rank)
        blobs = []
        for k in names:
            pp, nn = res[k]
            if lq:
                key = np.round(pp / GRID).astype(np.int64)
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
            if len(idx) == 0:
                continue   # (a small part merged away to nothing in the light version)
            nb = k.encode()
            blobs.append(struct.pack("<I", len(nb)) + nb + struct.pack("<I", len(vp)) + vp.astype(np.float32).tobytes()
                         + vn.astype(np.float32).tobytes() + struct.pack("<I", len(idx)) + idx.tobytes())
        f.write(struct.pack("<I", len(blobs)))
        for b in blobs:
            f.write(b)


write_cpe2(out, res, LQ)
print("wrote", out)

# the parts the body leaves out, as the model has them, for the game to put on the car: each wheel and brake calliper in its
# own space (about the wheel's centre), the interior in the car's space and the steering wheel in its own (with where it sits)
if not LQ:
    pdir = os.path.splitext(out)[0] + "_parts"
    os.makedirs(pdir, exist_ok=True)
    manifest = {"wheels": [], "calipers": [], "cabin": "", "steer": {}}
    cabin = {}
    for name, n, M, t in extras:
        local = {}
        for q in j["meshes"][n["mesh"]]["primitives"]:
            m = j["materials"][q["material"]] if "material" in q else {}
            P = acc(q["attributes"]["POSITION"])
            N = acc(q["attributes"]["NORMAL"])
            T = acc(q["indices"]).reshape(-1) if "indices" in q else np.arange(len(P))
            if name != "Interior":
                N, T = right_way_out(P, N, T, name + " " + m.get("name", ""), False, (-99.0, 99.0))
            key = "part~" + mat_tag(m)
            if name == "Interior":   # (in the car's space)
                P = to_game(P @ M.T + t)
                N = N @ M.T
                dst = cabin
            else:
                dst = local
            nn = N[T] / np.maximum(np.linalg.norm(N[T], axis=1, keepdims=True), 1e-9)
            pt = P[T]
            if key in dst:
                dst[key] = (np.concatenate([dst[key][0], pt]).astype(np.float32), np.concatenate([dst[key][1], nn]).astype(np.float32))
            else:
                dst[key] = (pt.astype(np.float32), nn.astype(np.float32))
        if name == "Interior":
            continue
        fname = name.lower() + ".mesh"
        write_cpe2(os.path.join(pdir, fname), local)
        pos = [round(float(t[0]), 4), round(float(t[1]), 4), round(float(t[2] - REAR), 4)]
        if name.startswith("Wheel_"):
            manifest["wheels"].append({"file": fname, "pos": pos})
        elif name.startswith("Caliper_"):
            manifest["calipers"].append({"file": fname, "pos": pos})
        elif name == "SteeringWheel":
            manifest["steer"] = {"file": fname, "pos": pos, "rot": [float(v) for v in n.get("rotation", [0, 0, 0, 1])]}
    if cabin:
        write_cpe2(os.path.join(pdir, "interior.mesh"), cabin)
        manifest["cabin"] = "interior.mesh"
    json.dump(manifest, open(os.path.join(pdir, "parts.json"), "w"), indent=1)
    print("wrote", pdir, {k: (len(v) if isinstance(v, list) else bool(v)) for k, v in manifest.items()})
