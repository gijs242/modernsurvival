#!/usr/bin/env python3
"""Downloads the free weapon models used by the game and converts them with Blender.

The converted GLBs are already committed in assets/weapons/, so you only need this to rebuild or tweak them.
Requires Blender 4.x on PATH (and `7z` for the SMG archive).

    python3 tools/fetch_weapons.py           # download + extract into build/weapon_src
    blender -b --factory-startup -P tools/convert_weapons.py -- build/weapon_src assets/weapons
"""
import os
import subprocess
import urllib.request
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DST = os.path.join(ROOT, "build", "weapon_src")
BASE = "https://opengameart.org/sites/default/files/"
FILES = {
    # name in convert_weapons.py : (file, licence, author, page)
    "fpsweapons": ("fpsweapons.zip", "CC-BY-SA 3.0", "biglew", "https://opengameart.org/content/fps-weapons"),
    "smg": ("submachine_gun.7z", "CC-BY 4.0", "kutejnikov", "https://opengameart.org/content/bullpup-submachine-gun"),
    "m60": ("m60.zip", "CC-BY 4.0", "mightydinosaurcol", "https://opengameart.org/content/m60-machine-gun"),
    "RPG7": ("RPG7.zip", "CC0", "lucian-pavel", "https://opengameart.org/content/low-poly-rpg7"),
    "mk2_grenade": ("mk2_grenade.zip", "CC0", "lonesomeducky", "https://opengameart.org/content/mk2-grenade"),
}

os.makedirs(DST, exist_ok=True)
for name, (fname, *_rest) in FILES.items():
    out = os.path.join(DST, name)
    if os.path.isdir(out):
        continue
    print("downloading", fname)
    tmp = os.path.join(DST, fname)
    req = urllib.request.Request(BASE + fname, headers={"User-Agent": "Mozilla/5.0"})
    with urllib.request.urlopen(req, timeout=300) as r, open(tmp, "wb") as f:
        f.write(r.read())
    os.makedirs(out, exist_ok=True)
    if fname.endswith(".zip"):
        zipfile.ZipFile(tmp).extractall(out)
    else:
        subprocess.run(["7z", "x", "-y", "-o" + out, tmp], check=True, stdout=subprocess.DEVNULL)
# the scanned bolt-action rifle comes from Poly Haven via tools/fetch_assets.py
link = os.path.join(DST, "polyhaven")
if not os.path.exists(link):
    os.symlink(os.path.join(ROOT, "assets", "props"), link)
print("done ->", DST)
