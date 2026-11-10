#!/usr/bin/env python3
"""Builds assets/sounds/*.ogg from free recordings (needs ffmpeg + numpy).

Sources (download into one folder, pass it as the first argument):
  * The Free Firearm Sound Library — CC0 — https://opengameart.org/content/the-free-firearm-sound-library
    (extract "Prepared SFX Library")
  * Gun reload sounds (airsoft) — CC0 — https://opengameart.org/content/gun-reload-sounds
  * 2 high quality explosions — CC-BY 3.0 (Michel Baradari) — https://opengameart.org/content/2-high-quality-explosions
  * Impact sounds — CC0 (qubodup) — https://opengameart.org/content/impact
  * Equipment Clicks II — CC0 — https://opengameart.org/content/equipment-clicks-ii
    (assaultriflereload1_0.wav, shotguncock_0.wav and equipmentclicks.wav go directly in the folder;
     explosions.7z into expl/, qubodupImpact.7z into impact/)

    python3 tools/make_sounds.py <source_dir>
Each gunshot is found by its onset, trimmed with its natural tail, faded, normalised and stored as mono OGG.
"_far" variants come from the mid-distance recordings and are used for enemies / teammates further away.
"""
import os
import subprocess
import sys

import numpy as np

SRC = sys.argv[1]
OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "assets", "sounds")
LIB = os.path.join(SRC, "Prepared SFX Library")
RATE = 44100

# game sound name -> (recording, tail seconds, pitch)
SHOTS = {
    "pistol": ("Bersa/F_47P.wav", 0.9, 1.0), "pistol_far": ("Bersa/F_41P.wav", 1.4, 1.0),
    "m9": ("Walther PPQ/X_39P.wav", 0.9, 1.0), "m9_far": ("Walther PPQ/X_31P.wav", 1.4, 1.0),
    "m1911": ("1911/A_42P.wav", 1.0, 1.0), "m1911_far": ("1911/A_34P.wav", 1.5, 1.0),
    "smg": ("Carl Gustav M45/G_31P.wav", 0.7, 1.0), "smg_far": ("Carl Gustav M45/G_20P.wav", 1.2, 1.0),
    "shotgun": ("Nova/O_21P.wav", 1.4, 1.0), "shotgun_far": ("Nova/O_17P.wav", 2.0, 1.0),
    "ar": ("AR-15/D_32P.wav", 1.0, 1.0), "ar_far": ("AR-15/D_24P.wav", 1.6, 1.0),
    "l85": ("AR-15/D_32P.wav", 1.0, 1.06), "l85_far": ("AR-15/D_24P.wav", 1.6, 1.06),
    "ak47": ("AK-47/C_28P.wav", 1.1, 1.0), "ak47_far": ("AK-47/C_31P.wav", 1.6, 1.0),
    "g3a3": ("Savage 10 .300 Blackout/T_27P.wav", 1.2, 1.0), "g3a3_far": ("Savage 10 .300 Blackout/T_17P.wav", 1.8, 1.0),
    "scar": ("Tikka/W_29P.wav", 1.2, 1.05), "scar_far": ("Tikka/W_24P.wav", 1.8, 1.05),
    "dmr": ("Mosin Nagant/M_21P.wav", 1.8, 1.0), "dmr_far": ("Mosin Nagant/M_26P.wav", 2.4, 1.0),
    "mosin": ("Mosin Nagant/M_21P.wav", 1.8, 0.96), "mosin_far": ("Mosin Nagant/M_26P.wav", 2.4, 0.96),
    "svd": ("Arisaka/E_25P.wav", 1.6, 1.04), "svd_far": ("Arisaka/E_18P.wav", 2.2, 1.04),
    "lmg": ("SKS/U_14P.wav", 1.1, 0.9), "lmg_far": ("SKS/U_19P.wav", 1.7, 0.9),
    "mg250": ("AK-47/C_28P.wav", 1.1, 0.88), "mg250_far": ("AK-47/C_31P.wav", 1.7, 0.88),
    "enemy_rifle": ("AK-47/C_31P.wav", 1.6, 1.0), "enemy_shotgun": ("CD/H_16P.wav", 1.9, 1.0),
    "enemy_lmg": ("SKS/U_19P.wav", 1.7, 0.9), "turret": ("Carl Gustav M45/G_20P.wav", 1.0, 1.15),
    "gunship": ("Model 12/K_17P.wav", 2.4, 0.55), "launcher": ("Model 12/K_22P.wav", 1.6, 0.6),
}


def load(path, pitch=1.0):
    rate = int(RATE / pitch)        # play back at RATE later -> pitch shift
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", path, "-ac", "1", "-ar", str(rate), "-f", "f32le", "-"],
                         capture_output=True, check=True).stdout
    return np.frombuffer(raw, np.float32).copy()


def save(name, x):
    x = x / max(1e-6, np.abs(x).max()) * 0.89
    os.makedirs(OUT, exist_ok=True)
    out = os.path.join(OUT, name + ".ogg")
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "f32le", "-ar", str(RATE), "-ac", "1", "-i", "-",
                    "-c:a", "libvorbis", "-q:a", "5", out], input=x.astype(np.float32).tobytes(), check=True)
    return os.path.getsize(out)


def shot(x, tail):
    """Cut from just before the first strong transient through `tail` seconds, with a smooth fade."""
    env = np.abs(x)
    thr = env.max() * 0.25
    start = int(np.argmax(env > thr))
    start = max(0, start - int(0.004 * RATE))
    end = min(len(x), start + int(tail * RATE))
    y = x[start:end].copy()
    fade = np.ones(len(y))
    n = int(len(y) * 0.45)
    fade[-n:] = np.linspace(1, 0, n) ** 2
    fade[:int(0.002 * RATE)] = np.linspace(0, 1, int(0.002 * RATE))
    return y * fade


def events(x, count, min_gap=0.12):
    """Split a handling recording into its `count` strongest separate events."""
    win = int(0.01 * RATE)
    env = np.convolve(np.abs(x), np.ones(win) / win, mode="same")
    order = np.argsort(env)[::-1]
    picks = []
    for i in order:
        if all(abs(i - p) > min_gap * RATE for p in picks):
            picks.append(i)
        if len(picks) == count:
            break
    out = []
    for p in sorted(picks):
        a = max(0, p - int(0.03 * RATE))
        b = min(len(x), p + int(0.22 * RATE))
        y = x[a:b].copy()
        y *= np.r_[np.linspace(0, 1, int(0.005 * RATE)), np.ones(len(y) - int(0.005 * RATE) - int(0.08 * RATE)), np.linspace(1, 0, int(0.08 * RATE))]
        out.append(y)
    return out


total = 0
for name, (rel, tail, pitch) in SHOTS.items():
    total += save(name, shot(load(os.path.join(LIB, rel), pitch), tail))
# reloads (airsoft rifle reload: mag out, mag in, bolt) and shotgun pump
r = events(load(os.path.join(SRC, "assaultriflereload1_0.wav")), 3)
for n, y in zip(["mag_out", "mag_in", "bolt"], r):
    total += save(n, y)
total += save("pump", load(os.path.join(SRC, "shotguncock_0.wav")))
clicks = events(load(os.path.join(SRC, "equipmentclicks.wav")), 4, 0.25)
total += save("dry", clicks[0][: int(0.08 * RATE)])
total += save("swap", clicks[1])
# explosions & impacts
total += save("explosion", load(os.path.join(SRC, "expl", "explosions", "explode.wav")))
imp = os.path.join(SRC, "impact", "qubodupImpact")
total += save("impact", load(os.path.join(imp, "qubodupImpactStone.flac")))
total += save("impact_metal", load(os.path.join(imp, "qubodupImpactMetal.flac")))
total += save("impact_flesh", load(os.path.join(imp, "qubodupImpactMeat01.flac")))
print(f"wrote {len(SHOTS) + 10} sounds, {total / 1024:.0f} KB total -> {OUT}")
