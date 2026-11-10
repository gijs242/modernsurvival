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
    "roof_dark": "RoofingTiles013A",
    "gravel": "Gravel023",
}
MAPS = {"_Color.jpg": "albedo.jpg", "_NormalGL.jpg": "normal.jpg", "_Roughness.jpg": "roughness.jpg",
        "_AmbientOcclusion.jpg": "ao.jpg", "_Metalness.jpg": "metallic.jpg"}

# Poly Haven photo-scanned textures (override the ambientCG set of the same name)
PH_TEXTURES = {
    "bricks": "red_brick_03", "asphalt": "asphalt_02",
    "roof_dark": "grey_roof_tiles_02", "plaster": "painted_plaster_wall", "concrete": "dirty_concrete",
    "concrete_wall": "cracked_concrete_wall", "gravel": "gravel_concrete_03", "corrugated": "rusty_corrugated_iron",
    "planks": "weathered_brown_planks", "dirt": "dirt",
    # mall interior
    "mall_floor": "marble_01", "shop_floor": "laminate_floor_02", "wood_fine": "fine_grained_wood",
    "bay_floor": "concrete_floor_worn_001", "denim": "denim_fabric", "leather": "leather_white", "metal_plate": "metal_plate",
}
# HD texture pack: the surfaces you look at most get 4K maps, everything else 2K
PH_4K = {"mall_floor", "plaster", "bricks", "shop_floor", "concrete"}
PH_MAPS = {"Diffuse": "albedo.jpg", "nor_gl": "normal.jpg", "Rough": "roughness.jpg", "AO": "ao.jpg"}

HDRI = "kloofendal_48d_partly_cloudy_puresky"
MODELS = ["concrete_road_barrier", "barrel_03", "old_military_crate", "wooden_crate_01", "ammo_box",
          "metal_jerrycan_green", "street_lamp_01", "utility_box_01", "wooden_military_crate", "service_pistol",
          "covered_car", "plastic_crate_01", "bolt_action_rifle_7_62",
          # clutter
          "trashbag", "metal_trash_can", "cardboard_box_01", "cement_bag", "plastic_crate_02",
          "potted_plant_02", "potted_plant_04",
          "plastic_monobloc_chair_01", "rollershutter_door",
          "portable_generator", "wooden_crate_02", "painted_wooden_bench", "metal_toolbox",
          # mall furniture and shop fittings
          "Sofa_01", "ArmChair_01", "modern_arm_chair_01", "modern_coffee_table_01", "CashRegister_01", "WetFloorSign_01",
          "painted_wooden_shelves", "painted_wooden_cabinet", "metal_office_desk", "Television_01", "korean_fire_extinguisher_01",
          "hand_truck", "industrial_storage_cart", "plastic_crate_03", "planter_box_03", "metal_tool_chest", "Shelf_01",
          "side_table_01", "round_wooden_table_01", "drawer_cabinet"]


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


def ph_textures():
    for name, pid in PH_TEXTURES.items():
        out = os.path.join(ROOT, "assets", "textures", name)
        marker = os.path.join(out, "SOURCE")
        if os.path.exists(marker) and open(marker).read().strip() == "polyhaven:" + pid + ("@4k" if name in PH_4K else ""):
            continue
        print("texture", name, "<- polyhaven", pid)
        files = json.loads(get(f"https://api.polyhaven.com/files/{pid}"))
        os.makedirs(out, exist_ok=True)
        for f in os.listdir(out):
            os.remove(os.path.join(out, f))
        for key, dst in PH_MAPS.items():
            res = "4k" if name in PH_4K else "2k"
            if key in files and res in files[key]:
                with open(os.path.join(out, dst), "wb") as fh:
                    fh.write(get(files[key][res]["jpg"]["url"]))
        with open(marker, "w") as fh:
            fh.write("polyhaven:" + pid + ("@4k" if name in PH_4K else ""))


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
    for step in (textures, ph_textures, hdri, models):
        try:
            step()
        except Exception as e:  # noqa: BLE001
            print(f"{step.__name__} failed: {e}", file=sys.stderr)
    print("done")
