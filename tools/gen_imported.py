#!/usr/bin/env python3
"""Writes the profiles of the imported cars into scripts/car_model.gd
(PROFILES) and scripts/data.gd (SHAPES), between the IMPORTED markers, from
the measurements tools/convert_coupe.py saved in tools/profiles/.

Run after converting a model:   python3 tools/gen_imported.py
"""
import json, os, math
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..")

# shape id -> profile json (the converted model's name)
MANIFEST = {
    "kestrel": "car_kestrel", "bruiser": "car_bruiser", "copperhead": "car_copperhead",
    "halcyon": "car_halcyon", "static": "car_static",
    "marshal": "car_marshal", "lastexit": "car_lastexit", "vanta": "car_vanta",
    "suv": "car_traffic_suv", "van": "car_traffic_van", "truck": "car_traffic_truck",
}
TRAFFIC = {"suv", "van", "truck"}
FLAGS = {"van": {"van": True}, "truck": {"truck": True}}


def fmt(v):
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, str):
        return '"%s"' % v
    if isinstance(v, (list, tuple)):
        return "[" + ", ".join(fmt(x) for x in v) + "]"
    return ("%.3f" % v).rstrip("0").rstrip(".") if isinstance(v, float) else str(v)


def entry(sid, name):
    d = json.load(open(os.path.join(HERE, "profiles", name + ".json")))
    gh = d["gh"]
    roof = d["roof"]
    mid = gh[2] + (gh[3] - gh[2]) * 0.45
    eye_back = 1.3 + max(0.0, 1.22 - roof) * 1.6  # seated further back in very low cars, so the wheel is a fair reach away
    eye_d = gh[1] - eye_back
    # roof height over the seat: on cars whose roof starts further forward than the seat it slopes down there
    t = min(max((eye_d - gh[0]) / max(gh[2] - gh[0], 0.01), 0.0), 1.0)
    roof_at = gh[4] + (roof - gh[4]) * (t * t * (3 - 2 * t)) ** 0.7
    eye_y = min(gh[4] + 0.36, roof_at - 0.17)
    pr = {
        "mesh": "res://assets/models/%s.mesh" % name,
        "mesh_lq": "res://assets/models/%s_lq.mesh" % name,
        "body": d["body"], "gh": gh, "pillars": [[0.0, 0.28], [0.5, 0.54], [0.93, 1.0]],
        "rim_frac": 0.7, "tyre": [d["tyre"], d["tyre"]], "wheel": d["wheel"], "wheel_x": d["wheel_x"],
        "plate_y": 0.62, "badge_y": 0.74, "eye_back": round(eye_back, 2), "eye_y": round(eye_y, 3),
        "dash_drop": 0.17 if roof < 1.2 else (0.12 if roof < 1.32 else 0.0),
        "dash_hw": round(min(d["ws_hw"] * 0.85, 0.7), 2), "ws_base_hw": round(min(d["ws_hw"] * 0.8, 0.7), 2),
        "mirror_d": round(gh[3] - 0.05, 2),
    }
    if sid in TRAFFIC:
        pr["lod_near"] = 18.0
        pr["no_cabin"] = sid == "truck"
        pr["plate_y"] = 0.82 if sid == "truck" else 0.7
        pr["badge_y"] = 0.95
        if sid == "truck":
            ax = d["axles"]
            pr["wheel"] = [d["wheel"][0], ax[0], ax[-1]]
            pr["extra_axles"] = ax[1:-1]
            pr["truck"] = True
    lines = ['\t"%s": {' % sid]
    keys = list(pr.keys())
    chunk = []
    for k in keys:
        chunk.append('"%s": %s' % (k, fmt(pr[k])))
    lines.append("\t\t" + ",\n\t\t".join(chunk) + "},")
    extra = "".join(', "%s": true' % k for k in FLAGS.get(sid, {}))
    shape = '\t"%s": {"w": %.2f, "l": %.2f, "b": 0.8, "t": %.2f, "c0": 0.15, "c1": 0.66, "ins": 0.15%s},' % (sid, d["W"], d["L"], d["roof"], extra)
    return "\n".join(lines), shape


def patch(path, begin, end, text):
    s = open(path).read()
    i = s.index(begin)
    j = s.index(end)
    s = s[:i + len(begin)] + "\n" + text + "\n\t" + s[j:]
    open(path, "w").write(s)


profs, shapes = [], []
for sid, name in MANIFEST.items():
    if not os.path.exists(os.path.join(HERE, "profiles", name + ".json")):
        continue
    p, sh = entry(sid, name)
    profs.append(p)
    shapes.append(sh)
patch(os.path.join(ROOT, "scripts", "car_model.gd"), "# BEGIN IMPORTED PROFILES", "# END IMPORTED PROFILES", "\n".join(profs))
patch(os.path.join(ROOT, "scripts", "data.gd"), "# BEGIN IMPORTED SHAPES", "# END IMPORTED SHAPES", "\n".join(shapes))
print("wrote", ", ".join(MANIFEST))
