#!/usr/bin/env python3
"""Where a song gets going, and how loud it is: the numbers for a line of SONGS in scripts/boss_music.gd.

    python3 tools/song_points.py assets/audio/*.mp3

Needs ffmpeg and numpy. For each song it prints its length and tempo, the bars where the energy steps up, the start to use
(the first big step up into the loud part of the song, on a bar line: where the quiet intro ends, or the heaviest part begins)
and the gain that brings the part that plays to the same loudness as the first song (-11.9 LUFS, measured over 90 s from the start). The tempo and the beats are found by folding the song's onsets over every tempo from 70 to 175 bpm: songs made
on a fixed grid give a sharp peak, so a beat can be found to within a few milliseconds. It takes the strongest beat for the first
of the bar, which is right for the songs it was made for (steady four-four with the kick on the one); if the start it names sounds
a beat early or late, move it by one beat. It is a guide, not a verdict: listen at the start it names.
"""
import re
import subprocess
import sys

import numpy as np

SR = 22050
HOP = 256
REFERENCE_LUFS = -11.9  # how loud the first song, Cold Iron Street, is over the part that plays


def decode(path):
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", path, "-ac", "1", "-ar", str(SR), "-f", "s16le", "-"],
                         capture_output=True, check=True).stdout
    return np.frombuffer(raw, dtype=np.int16).astype(np.float32) / 32768.0


def onsets(x):
    """Spectral flux: how much new sound begins in each 11.6 ms frame."""
    n = 1024
    w = np.hanning(n).astype(np.float32)
    frames = 1 + (len(x) - n) // HOP
    idx = np.arange(n)[None, :] + HOP * np.arange(frames)[:, None]
    mag = np.abs(np.fft.rfft(x[idx] * w, axis=1))
    flux = np.concatenate([[0.0], np.maximum(0.0, np.diff(np.log1p(mag * 20), axis=0)).sum(axis=1)])
    fps = SR / HOP
    return np.maximum(flux - np.convolve(flux, np.ones(int(fps)) / fps, mode="same"), 0.0), fps


def beat_grid(flux, fps):
    """(bpm, time of a beat in seconds, how sharp the peak is)."""
    t = np.arange(len(flux)) / fps
    best = None
    for bpm in np.arange(70, 175, 0.05):
        p = 60.0 / bpm
        bins = np.minimum(((t % p) / p * 48).astype(int), 47)
        acc = np.bincount(bins, weights=flux, minlength=48)
        acc3 = acc + np.roll(acc, 1) + np.roll(acc, -1)
        score = acc3.max() / (acc3.mean() + 1e-9)
        if best is None or score > best[0]:
            best = (score, bpm, (int(np.argmax(acc3)) + 0.5) / 48 * p)
    return best[1], best[2], best[0]


def bar_energy(x, bpm, phase, offset):
    """Energy in dB of each bar (four beats), the bars starting `offset` beats after `phase`."""
    beat = 60.0 / bpm
    t0 = phase + offset * beat
    n = int((len(x) / SR - t0) / (4 * beat))
    e = [10 * np.log10(np.mean(x[int((t0 + i * 4 * beat) * SR):int((t0 + (i + 1) * 4 * beat) * SR)] ** 2) + 1e-12) for i in range(n)]
    return t0, 4 * beat, np.array(e)


def loudness(path, start, length=90):
    out = subprocess.run(["ffmpeg", "-nostats", "-ss", str(start), "-t", str(length), "-i", path, "-af", "ebur128=peak=true", "-f", "null", "-"],
                         capture_output=True, text=True).stderr
    m = re.findall(r"I:\s+(-?[\d.]+) LUFS", out)
    return float(m[-1]) if m else float("nan")


def analyse(path):
    x = decode(path)
    flux, fps = onsets(x)
    bpm, phase, sharp = beat_grid(flux, fps)
    # the strongest beat (the kick) is taken to be the first of the bar
    t0, bar, e = bar_energy(x, bpm, phase, 0)
    top = np.percentile(e, 90)
    print("%s: %.1f s, %.2f bpm (beat peak %.1fx the average), bars of %.3f s from %.3f s" % (path, len(x) / SR, bpm, sharp, bar, t0))
    steps = [(e[i] - e[i - 1], i) for i in range(1, len(e)) if e[i] - e[i - 1] >= 3.0]
    print("  steps up of 3 dB or more at: " + (", ".join("%.2f s (+%.1f dB)" % (t0 + i * bar, d) for d, i in steps) or "none"))
    # the start: the first bar that is a big step up (2 dB or more) into the loud part, and stays in it (within 3.5 dB
    # of the loud part's level, for eight bars)
    start = None
    for i in range(1, len(e) - 8):
        if e[i] - e[i - 1] >= 2.0 and all(e[i + j] >= top - 3.5 for j in range(8)):
            start = t0 + i * bar
            break
    if start is None:
        start = t0 + int(np.argmax(e >= top - 3.0)) * bar
    lufs = loudness(path, start)
    print("  start %.2f s (bar %d); %.1f LUFS from there for 90 s -> gain %+.1f dB" % (start, round((start - t0) / bar), lufs, REFERENCE_LUFS - lufs))
    name = path.split("/")[-1].rsplit(".", 1)[0]
    print('  {"name": "%s", "path": "res://%s", "start": %.2f, "gain": %.1f},' % (name.replace("_", " ").title(), path.lstrip("./"), start, REFERENCE_LUFS - lufs))


if __name__ == "__main__":
    for p in sys.argv[1:] or ["--help"]:
        if p in ("-h", "--help"):
            print(__doc__)
            break
        analyse(p)
