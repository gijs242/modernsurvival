#!/usr/bin/env python3
"""Downloads the free CC0 assets the game uses (ambientCG textures, Poly Haven HDRI + props).

Run from the project root:  python3 tools/fetch_assets.py
Everything is CC0 (public domain). Already-downloaded files are skipped.
"""
import io
import json
import os
import sys
import urllib.request
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
UA = {"User-Agent": "modernsurvival-asset-fetch/1.0"}

# folder name -> ambientCG asset id
TEXTURES = {
    "asphalt": "Asphalt031",
    "dirt": "Ground054",
    "concrete": "Concrete034",
    "concrete_wall": "Concrete046",
    "bricks": "Bricks105",
    "corrugated": "CorrugatedSteel005",
    "painted_metal": "PaintedMetal006",
    "rust": "Metal041B",
    "fabric": "Fabric061",
    "planks": "Planks037A",
    "plaster": "PaintedPlaster017",
    "burlap": "Fabric045",
}
MAPS = {"_Color.jpg": "albedo.jpg", "_NormalGL.jpg": "normal.jpg", "_Roughness.jpg": "roughness.jpg",
        "_AmbientOcclusion.jpg": "ao.jpg", "_Metalness.jpg": "metallic.jpg"}

HDRI = "kloofendal_48d_partly_cloudy_puresky"
MODELS = ["concrete_road_barrier", "barrel_03", "old_military_crate", "wooden_crate_01", "ammo_box",
          "metal_jerrycan_green", "street_lamp_01", "utility_box_01", "wooden_military_crate", "service_pistol",
          "modular_chainlink_fence", "covered_car", "plastic_crate_01", "bolt_action_rifle_7_62"]


def get(url):
    with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=180) as r:
        return r.read()


def textures():
    for name, aid in TEXTURES.items():
        out = os.path.join(ROOT, "assets", "textures", name)
        if os.path.exists(os.path.join(out, "albedo.jpg")):
            continue
        os.makedirs(out, exist_ok=True)
        print("texture", name, aid)
        z = zipfile.ZipFile(io.BytesIO(get(f"https://ambientcg.com/get?file={aid}_1K-JPG.zip")))
        for n in z.namelist():
            for suf, dst in MAPS.items():
                if n.endswith(suf):
                    with open(os.path.join(out, dst), "wb") as f:
                        f.write(z.read(n))


def hdri():
    out = os.path.join(ROOT, "assets", "hdri", "sky.hdr")
    if os.path.exists(out):
        return
    os.makedirs(os.path.dirname(out), exist_ok=True)
    files = json.loads(get(f"https://api.polyhaven.com/files/{HDRI}"))
    url = files["hdri"]["2k"]["hdr"]["url"]
    print("hdri", HDRI)
    with open(out, "wb") as f:
        f.write(get(url))


def models():
    for mid in MODELS:
        out = os.path.join(ROOT, "assets", "props", mid)
        if os.path.exists(os.path.join(out, mid + ".gltf")):
            continue
        try:
            files = json.loads(get(f"https://api.polyhaven.com/files/{mid}"))
            g = files["gltf"]["1k"]["gltf"]
        except Exception as e:  # noqa: BLE001
            print("skip model", mid, e)
            continue
        print("model", mid)
        os.makedirs(out, exist_ok=True)
        with open(os.path.join(out, mid + ".gltf"), "wb") as f:
            f.write(get(g["url"]))
        for rel, inc in g.get("include", {}).items():
            p = os.path.join(out, rel)
            os.makedirs(os.path.dirname(p), exist_ok=True)
            with open(p, "wb") as f:
                f.write(get(inc["url"]))


if __name__ == "__main__":
    for step in (textures, hdri, models):
        try:
            step()
        except Exception as e:  # noqa: BLE001
            print(f"{step.__name__} failed: {e}", file=sys.stderr)
    print("done")
