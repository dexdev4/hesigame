#!/usr/bin/env python3
"""How the traffic brakes, measured in the real game.

Runs the game headless (`--autotest --fast --no-traps --godmode`) through scenes that make the traffic brake, with a
fresh save for each, and reads the line the game prints when it quits (`traffic braking: ...`, from
`Game._brake_stats`): how much of the time the traffic's cars are braking, how hard, how quickly the brake comes on, how
often a car's speed is snapped to the one ahead's (the last-resort rule that used to be a slam to a stop), and how often
a car stops from speed in under 0.7 s.

usage:
  python3 tools/traffic_brake.py [--scenes cruise,slow,queue,far,crash] [--seeds 3] [--jobs 4] [--frames 9000]

Scenes: `cruise` (the autopilot at its own pace, no boss), `slow` (the autopilot at 14 m/s: the traffic comes up behind it),
`queue` and `far` (the player stops in its lane in a police pursuit: behind a stopped car, or braking to a stop with a car
following it in), `crash` (the player runs into the car ahead: the wreck is across the road for the cars behind it).
"""
import argparse
import concurrent.futures
import os
import re
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, ".."))
SCENES = {
    "cruise": ["--target-scale=1000"],
    "slow": ["--target-scale=1000", "--autospeed=14"],
    "queue": ["--cop-block=queue"],
    "far": ["--cop-block=far"],
    "crash": ["--target-scale=1000", "--collide-at=25:rear:3"],
}
LINE = re.compile(r"traffic braking: (\d+) car-steps moving, ([\d.]+)% braking, ([\d.]+)% harder than 7 m/s², (\d+) slams \(over 10 m/s²\), hardest ([\d.]+) m/s², brake onset up to (\d+) m/s³, (\d+) last-resort snaps, (\d+) stops from speed in under 0.7 s, cars overlapped (\d+) frames")


def run_one(job):
    scene, seed, frames, extra = job
    work = tempfile.mkdtemp(prefix="trafficbrake_")
    os.makedirs(os.path.join(work, "godot", "app_userdata", "Redline Rush"))
    cmd = ["godot", "--headless", "--path", ROOT, "--fixed-fps", "60", "--quit-after", str(frames), "--",
           "--autotest", "--fast", "--no-traps", "--orient=portrait", "--godmode", "--seed=%d" % seed] + SCENES[scene] + extra
    p = subprocess.run(cmd, capture_output=True, text=True, env=dict(os.environ, XDG_DATA_HOME=work), timeout=1500)
    shutil.rmtree(work, ignore_errors=True)
    found = None
    for ln in p.stdout.splitlines():
        m = LINE.search(ln)
        if m:
            found = [float(g) for g in m.groups()]
    return scene, found, p.stdout


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--scenes", default="cruise,slow,queue,far,crash")
    ap.add_argument("--seeds", type=int, default=3)
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--jobs", type=int, default=4)
    ap.add_argument("--frames", type=int, default=9000)
    ap.add_argument("--extra", default="")
    ap.add_argument("--dump", default="")
    a = ap.parse_args()
    jobs = [(s, a.seed + k, a.frames, a.extra.split()) for s in a.scenes.split(",") for k in range(a.seeds)]
    rows = {}
    with concurrent.futures.ThreadPoolExecutor(max_workers=a.jobs) as ex:
        for done, (scene, found, out) in enumerate(ex.map(run_one, jobs), 1):
            print("\r%d/%d" % (done, len(jobs)), end="", file=sys.stderr, flush=True)
            if a.dump:
                with open("%s_%s_%d.txt" % (a.dump, scene, done), "w") as f:
                    f.write(out)
            if found:
                rows.setdefault(scene, []).append(found)
            else:
                rows.setdefault(scene, [])
    print(file=sys.stderr)
    print("%-7s %9s %6s %6s %6s %6s %7s %6s %6s %5s" % ("scene", "car-steps", "brake%", ">7 %", "slams", "worst", "onset", "snaps", "stops", "ovl"))
    for scene, vals in rows.items():
        if not vals:
            print("%-7s no result" % scene)
            continue
        n = len(vals)
        tot = lambda i: sum(v[i] for v in vals)
        worst = max(v[4] for v in vals)
        onset = max(v[5] for v in vals)
        print("%-7s %9.0f %6.1f %6.2f %6.0f %6.1f %7.0f %6.0f %6.0f %5.0f   (totals over %d runs, worst of them for 'worst' and 'onset')" % (
            scene, tot(0), tot(1) / n, tot(2) / n, tot(3), worst, onset, tot(6), tot(7), tot(8), n))


if __name__ == "__main__":
    main()
