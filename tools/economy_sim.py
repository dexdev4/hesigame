#!/usr/bin/env python3
"""What a run earns and costs, and how fast the cars can really be driven, measured in the real game.

It runs the game headless with its autopilot (`--autotest --godmode`, so the run never ends) once for each car, highway
and speed asked for. The autopilot is not a person (it takes few risks and is slow to get past a car), so read the figures
as what a steady, careful driver makes: they are the same for every car, which is what a balance check needs.

Stages (the default): the game prints an economy line at the end of every boss race (Game._econ_line): how long the run
has gone, how far, how fast, how many hits, the score, the money (score / 40 + distance / 50 + boss prizes) and the fuel.
Each stage's own figures are the difference between one line and the next (a lost race is run again, so a stage can
have several lines).
  python3 tools/economy_sim.py [--cars pulse,vanta] [--routes 0,6,13] [--speed auto|M/S[,M/S...]] [--stages 3]
                               [--seeds N] [--jobs 4] [--seed 7] [--keep]
  --speed auto   the autopilot drives at 85% of the car's top speed, at most 70 m/s (each car is driven like itself)
  --stages N     until the Nth boss race has been run
  --seeds N      N runs of each on different roads (the seeds from --seed up)
  --summary      one line for each car and highway instead of every stage: the first stage and its boss race, averaged
                 over the seeds: time, distance, points, income (with the prize when the race was won), what the fuel
                 would cost at average prices, the net, the net a minute and how often the autopilot won the race

Sweep (`--sweep`): for the top speeds. The car is driven at each speed through the traffic of each stage for a few
kilometres, with nothing else going on (the stage and boss targets are set sky high), and the table says how fast it
really went, what it made and what it hit: points and hits per km.
  python3 tools/economy_sim.py --sweep [--cars lastexit] [--speed 30,45,60,75] [--start-stages 1,4,8] [--look 0.9]
                               [--metres 4000] [--seeds N] [--extra=--flat-traffic]
  --look S       how many seconds of road the autopilot wants ahead before it stops braking (its old 16 m is far too
                 little above 50 m/s: it is a stand-in driver, not the game)
  --extra=FLAGS  more flags for the game (e.g. --flat-traffic: the traffic as it was before it thinned at speed)
"""
import argparse
import concurrent.futures
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, ".."))
LINE = re.compile(r"economy: car (\w+) route (\d+) stage (\d+) (WON|LOST) \| ([\d.]+) s, ([\d.]+) m, mean (\d+) km/h, hits (\d+) \| "
                  r"score (\d+) \(this race (\d+), the boss (\d+)\) \| gross \$(\d+) = score \$(\d+) \+ distance \$(\d+) \+ prizes \$(\d+) \| "
                  r"fuel ([\d.]+) L burnt, \$(\d+) paid")
FIELDS = ["car", "route", "stage", "won", "time", "dist", "kmh", "hits", "score", "race", "boss", "gross", "score_d", "dist_d", "prize", "litres", "fuel_paid"]


def car_table():
    """id -> (price, top speed m/s) from Data.CARS."""
    src = open(os.path.join(ROOT, "scripts", "data.gd")).read()
    out = {}
    for m in re.finditer(r'\{"id": "(\w+)".*?"price": (\d+).*?"top": ([\d.]+)', src, re.S):
        out[m.group(1)] = (int(m.group(2)), float(m.group(3)))
    return out


FUEL_PRICE = {"regular": 3.4, "mid": 8.4, "premium": 18.4}   # average $ a litre (Data.FUEL_GRADES: +$5 and +$15 on regular)


def car_fuel_grade():
    src = open(os.path.join(ROOT, "scripts", "data.gd")).read()
    return {m.group(1): m.group(2) for m in re.finditer(r'\{"id": "(\w+)", "fuel": "(\w+)"', src)}


def run_one(job):
    car, route, speed, stages, seed, keep = job
    work = tempfile.mkdtemp(prefix="econ_")
    user = os.path.join(work, "godot", "app_userdata", "Redline Rush")
    os.makedirs(user)
    cars = list(car_table())
    json.dump({"cash": 100000, "owned": cars, "selected": car, "unlocked": cars, "routes": 14}, open(os.path.join(user, "save.json"), "w"))
    frames = 16000 * stages + 6000
    cmd = ["godot", "--headless", "--path", ROOT, "--fixed-fps", "60", "--quit-after", str(frames), "--",
           "--autotest", "--orient=portrait", "--godmode", "--seed=%d" % seed, "--car=" + car, "--route=%d" % route, "--autospeed=%.1f" % speed]
    env = dict(os.environ, XDG_DATA_HOME=work)
    p = subprocess.run(cmd, capture_output=True, text=True, env=env, timeout=1800)
    rows = []
    for ln in p.stdout.splitlines():
        m = LINE.search(ln)
        if m:
            v = list(m.groups())
            row = dict(zip(FIELDS, v))
            for k in FIELDS:
                if k not in ("car", "won"):
                    row[k] = float(row[k])
            row["speed"] = speed
            rows.append(row)
    if keep:
        open(os.path.join(work, "log.txt"), "w").write(p.stdout)
        print("kept", work, file=sys.stderr)
    else:
        shutil.rmtree(work, ignore_errors=True)
    return (car, route, speed, seed), [r for r in rows if r["stage"] <= stages]


ODO = re.compile(r"odometer (\d+) m: ([\d.]+) s, mean (\d+) km/h, score (\d+), hits (\d+), fuel ([\d.]+) L, stage (\d+)")


def sweep_one(job):
    car, route, speed, start_stage, look, metres, seed, extra = job
    work = tempfile.mkdtemp(prefix="sweep_")
    user = os.path.join(work, "godot", "app_userdata", "Redline Rush")
    os.makedirs(user)
    cars = list(car_table())
    json.dump({"cash": 100000, "owned": cars, "selected": car, "unlocked": cars, "routes": 14}, open(os.path.join(user, "save.json"), "w"))
    frames = int(metres / max(speed, 10.0) * 60.0) + 900
    cmd = ["godot", "--headless", "--path", ROOT, "--fixed-fps", "60", "--quit-after", str(frames), "--",
           "--autotest", "--orient=portrait", "--godmode", "--seed=%d" % seed, "--car=" + car, "--route=%d" % route,
           "--autospeed=%.1f" % speed, "--autolook=%.2f" % look, "--target-scale=1000", "--start-stage=%d" % start_stage, "--odometer=500"] + extra
    env = dict(os.environ, XDG_DATA_HOME=work)
    p = subprocess.run(cmd, capture_output=True, text=True, env=env, timeout=1800)
    rows = [tuple(float(x) for x in m.groups()) for m in map(ODO.search, p.stdout.splitlines()) if m]
    shutil.rmtree(work, ignore_errors=True)
    # the last reading that is at most `metres` in, and the one 1 km in (the first km is the road filling up)
    rows = [r for r in rows if r[0] <= metres + 1]
    return (car, route, speed, start_stage), rows


def sweep(a):
    jobs = []
    extra = a.extra.split() if a.extra else []
    for car in a.cars.split(","):
        for route in [int(x) for x in a.routes.split(",")]:
            for sp in [float(x) for x in a.speed.split(",")]:
                for st in [int(x) for x in a.start_stages.split(",")]:
                    for k in range(a.seeds):
                        jobs.append((car, route, sp, st, a.look, a.metres, a.seed + k, extra))
    print("%-10s %2s %5s %5s | %6s %6s %7s | %6s %6s %6s   (%d seeds)" % ("car", "hw", "m/s", "stage", "km/h", "pts/km", "hits/km", "secs", "metres", "L/km", a.seeds))
    totals = {}
    with concurrent.futures.ThreadPoolExecutor(max_workers=a.jobs) as ex:
        for (car, route, sp, st), rows in ex.map(sweep_one, jobs):
            if len(rows) < 2:
                continue
            first, last = rows[0], rows[-1]          # from the first 500 m to the end: the road is full by then
            t = totals.setdefault((car, route, sp, st), [0.0] * 6)
            t[0] += last[0] - first[0]
            t[1] += last[1] - first[1]
            t[2] += last[3] - first[3]
            t[3] += last[4] - first[4]
            t[4] += last[5] - first[5]
            t[5] += 1
    for (car, route, sp, st), (dm, dt, pts, hits, litres, n) in totals.items():
        print("%-10s %2d %5.1f %5d | %6.0f %6.0f %7.2f | %6.0f %6.0f %6.2f" % (car, route, sp, st, dm / dt * 3.6, pts / dm * 1000.0, hits / dm * 1000.0, dt / n, dm / n, litres / dm * 1000.0))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--cars", default="pulse,vanta,halcyon,lastexit")
    ap.add_argument("--routes", default="0,6,13")
    ap.add_argument("--speed", default="auto")
    ap.add_argument("--stages", type=int, default=3)
    ap.add_argument("--jobs", type=int, default=4)
    ap.add_argument("--seed", type=int, default=7)
    ap.add_argument("--keep", action="store_true")
    ap.add_argument("--sweep", action="store_true")
    ap.add_argument("--summary", action="store_true")
    ap.add_argument("--seeds", type=int, default=1)
    ap.add_argument("--extra", default="")
    ap.add_argument("--start-stages", default="1,4,8")
    ap.add_argument("--look", type=float, default=0.9)
    ap.add_argument("--metres", type=float, default=4000.0)
    a = ap.parse_args()
    if a.sweep:
        sweep(a)
        return
    table = car_table()
    jobs = []
    for car in a.cars.split(","):
        for route in [int(x) for x in a.routes.split(",")]:
            speeds = [min(0.85 * table[car][1], 70.0)] if a.speed == "auto" else [float(x) for x in a.speed.split(",")]
            for sp in speeds:
                for k in range(a.seeds):
                    jobs.append((car, route, sp, a.stages, a.seed + k, a.keep))
    results = {}
    with concurrent.futures.ThreadPoolExecutor(max_workers=a.jobs) as ex:
        for key, rows in ex.map(run_one, jobs):
            results[key] = rows
    if a.summary:
        grades = car_fuel_grade()
        print("%-10s %2s %5s | %6s %7s %7s %7s %7s %7s %7s %6s %7s %7s   (%d seeds; first stage and its boss race)" % (
            "car", "hw", "m/s", "secs", "metres", "points", "income", "fuel$", "net", "net/min", "won", "race", "boss", a.seeds))
        groups = {}
        for (car, route, sp, seed), rows in results.items():
            if rows:
                groups.setdefault((car, route, sp), []).append(rows[0])
        for (car, route, sp), firsts in groups.items():
            n = len(firsts)
            avg = lambda k: sum(r[k] for r in firsts) / n
            fuel = avg("litres") * FUEL_PRICE[grades[car]]
            income = avg("gross")
            won = sum(1 for r in firsts if r["won"] == "WON")
            print("%-10s %2d %5.1f | %6.0f %7.0f %7.0f %7.0f %7.0f %7.0f %7.0f %3d/%d %7.0f %7.0f" % (
                car, route, sp, avg("time"), avg("dist"), avg("score"), income, fuel, income - fuel, (income - fuel) / avg("time") * 60.0, won, n, avg("race"), avg("boss")))
        return
    print("%-10s %2s %5s %2s %-4s %6s %7s %5s %4s %7s %7s %6s %6s %6s %5s %6s" % (
        "car", "hw", "m/s", "st", "race", "secs", "metres", "km/h", "hits", "points", "income", "score$", "dist$", "prize", "fuelL", "fuel$"))
    for (car, route, sp, seed), rows in results.items():
        prev = None
        for r in rows:
            if prev is not None and r["time"] < prev["time"]:
                prev = None  # (a new run: the car was wrecked or ran dry and the autotest began again)
            d = lambda k: r[k] - (prev[k] if prev else 0.0)
            print("%-10s %2d %5.1f %2d %-4s %6.0f %7.0f %5.0f %4.0f %7.0f %7.0f %6.0f %6.0f %6.0f %5.1f %6.0f" % (
                car, route, sp, r["stage"], r["won"], d("time"), d("dist"), r["kmh"], d("hits"), d("score"), d("gross"), d("score_d"), d("dist_d"), d("prize"), d("litres"), d("fuel_paid")))
            prev = r
    json.dump({"%s|%d|%.1f|%d" % k: v for k, v in results.items()}, open(os.path.join(tempfile.gettempdir(), "economy_sim_last.json"), "w"))


if __name__ == "__main__":
    main()
