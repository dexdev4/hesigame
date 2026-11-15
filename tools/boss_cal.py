#!/usr/bin/env python3
"""How the bosses score and drive, measured in real boss races.

Runs the game headless (`--autotest --fast --no-traps --godmode`: no police speed checks to slow the autopilot) once for each highway, stage and seed asked for, and reads what the
game prints at the end of the first boss race: the rival's score, the autopilot's own, and how the boss drove (its mean
speed, lane changes, hard braking and how many razor passes, near misses and close cuts it made). The player is the
autopilot, which only matters as a car in the boss's way: the rival's score is its own.

usage:
  python3 tools/boss_cal.py [--routes 0,3,6,13] [--stages 1,2,3,4] [--seeds 3] [--jobs 4] [--seed 1] [--extra=--flag ...]

Output: one line for each highway and stage, averaged over the seeds. `--sk X` forces every boss to race at skill X
(the game's `--boss-sk`), which is how a skill is measured on its own.
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
RACE = re.compile(r"boss race route (\d+) stage (\d+) skill ([\d.]+) edge ([\d.]+): you (\d+), ([A-Za-z ]+?) (\d+) (\{.*\})?")
DRIVE = re.compile(r"drove (\d+) s: (\d+) lane changes, mean ([\d.]+) m/s.*?(\d+) hard-brake frames.*?overlapped a car in (\d+) frames")


def run_one(job):
    route, stage, seed, sk, extra = job
    work = tempfile.mkdtemp(prefix="bosscal_")
    os.makedirs(os.path.join(work, "godot", "app_userdata", "Redline Rush"))
    cmd = ["godot", "--headless", "--path", ROOT, "--fixed-fps", "60", "--quit-after", "9000", "--",
           "--autotest", "--fast", "--no-traps", "--orient=portrait", "--godmode", "--seed=%d" % seed, "--route=%d" % route, "--start-stage=%d" % stage] + extra
    if sk is not None:
        cmd.append("--boss-sk=%s" % sk)
    p = subprocess.run(cmd, capture_output=True, text=True, env=dict(os.environ, XDG_DATA_HOME=work), timeout=900)
    shutil.rmtree(work, ignore_errors=True)
    race = drive = None
    for ln in p.stdout.splitlines():
        m = RACE.search(ln)
        if m and race is None:
            labels = m.group(8) or ""
            count = lambda name: int(re.search(r'"%s": (\d+)' % name, labels).group(1)) if re.search(r'"%s": (\d+)' % name, labels) else 0
            race = {"skill": float(m.group(3)), "edge": float(m.group(4)), "you": int(m.group(5)), "boss": int(m.group(7)),
                    "razor": count("RAZOR PASS"), "near": count("NEAR MISS"), "cut": count("CLOSE CUT"), "plain": count("")}
            continue
        m = DRIVE.search(ln)
        if m and race is not None and drive is None:
            drive = {"secs": int(m.group(1)), "lc": int(m.group(2)), "mean": float(m.group(3)), "hard": int(m.group(4)), "overlap": int(m.group(5))}
    return (route, stage), (race, drive)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--routes", default="0,3,6,13")
    ap.add_argument("--stages", default="1,2,3,4")
    ap.add_argument("--seeds", type=int, default=3)
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--jobs", type=int, default=4)
    ap.add_argument("--sk", default=None)
    ap.add_argument("--extra", default="")
    a = ap.parse_args()
    extra = a.extra.split()
    jobs = [(int(r), int(s), a.seed + k, a.sk, extra) for r in a.routes.split(",") for s in a.stages.split(",") for k in range(a.seeds)]
    groups = {}
    with concurrent.futures.ThreadPoolExecutor(max_workers=a.jobs) as ex:
        for done, (key, (race, drive)) in enumerate(ex.map(run_one, jobs), 1):
            print("\r%d/%d" % (done, len(jobs)), end="", file=sys.stderr, flush=True)
            if race:
                groups.setdefault(key, []).append((race, drive))
    print(file=sys.stderr)
    print("%-3s %-5s %5s %5s | %7s %7s | %5s %5s %5s | %6s %4s %5s %4s   (%d seeds)" % (
        "hw", "stage", "skill", "edge", "boss", "you", "razor", "near", "cut", "m/s", "lc", "brake", "ovl", a.seeds))
    for (route, stage), rows in sorted(groups.items()):
        n = len(rows)
        avg = lambda f: sum(f(r, d) for r, d in rows) / n
        print("%-3d %-5d %5.2f %5.2f | %7.0f %7.0f | %5.1f %5.1f %5.1f | %6.1f %4.1f %5.1f %4.1f" % (
            route, stage, rows[0][0]["skill"], rows[0][0]["edge"], avg(lambda r, d: r["boss"]), avg(lambda r, d: r["you"]),
            avg(lambda r, d: r["razor"]), avg(lambda r, d: r["near"]), avg(lambda r, d: r["cut"]),
            avg(lambda r, d: d["mean"] if d else 0.0), avg(lambda r, d: d["lc"] if d else 0.0), avg(lambda r, d: d["hard"] if d else 0.0), avg(lambda r, d: d["overlap"] if d else 0.0)))


if __name__ == "__main__":
    main()
