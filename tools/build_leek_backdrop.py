#!/usr/bin/env python3
"""Builds assets/maps/leek_backdrop.json — a low-detail model of the town of Leek around the playable
De Liekeblom area, used as scenery only (no collision, no gameplay).

  * BAG (Kadaster, via PDOK)   building footprints                                  (CC0)
  * 3D BAG (TU Delft / 3DGI)   measured roof heights (70th percentile) per building (CC BY 4.0)
  * OpenStreetMap              streets, water, parks, woods, farmland               (ODbL)

Usage:
    pip install shapely pyproj
    python3 tools/build_leek_backdrop.py      # downloads into build/leek_src, writes assets/maps/leek_backdrop.json

Same frame as liekeblom.json: metres, x = east, z = south, origin = mall centre (origin_rd).
Buildings already modelled in detail by liekeblom.json are left out.
"""
import json
import os
import urllib.request

from shapely.geometry import Polygon

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "build", "leek_src")
OUT = os.path.join(ROOT, "assets", "maps", "leek_backdrop.json")
DETAIL = os.path.join(ROOT, "assets", "maps", "liekeblom.json")
HALF = 1250.0                                   # metres around the mall
UA = {"User-Agent": "modernsurvival-mapbuilder/1.0"}

ROAD_W = {"motorway": 14, "trunk": 12, "primary": 10, "secondary": 9, "tertiary": 8, "unclassified": 6,
          "residential": 6, "living_street": 5, "service": 4, "pedestrian": 5, "cycleway": 2.5,
          "footway": 1.8, "path": 1.5, "track": 3}
AREAS = {("landuse", "grass"): "grass", ("landuse", "meadow"): "grass", ("leisure", "park"): "grass",
         ("landuse", "recreation_ground"): "grass", ("leisure", "pitch"): "grass", ("landuse", "forest"): "forest",
         ("natural", "wood"): "forest", ("landuse", "farmland"): "farm", ("natural", "water"): "water",
         ("landuse", "basin"): "water", ("amenity", "parking"): "parking"}


def get_json(url):
    for attempt in range(4):
        try:
            with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=180) as r:
                return json.loads(r.read())
        except Exception as e:                   # flaky networks: retry with backoff
            print("  retry", attempt + 1, e)
            import time
            time.sleep(2 ** attempt * 2)
    raise RuntimeError("download failed: " + url)


def cached(name, fn):
    os.makedirs(SRC, exist_ok=True)
    path = os.path.join(SRC, name)
    if os.path.exists(path):
        return json.load(open(path))
    d = fn()
    json.dump(d, open(path, "w"))
    return d


def main():
    detail = json.load(open(DETAIL))
    ox, oy = detail["origin_rd"]
    bbox = (ox - HALF, oy - HALF, ox + HALF, oy + HALF)
    b = ",".join(f"{v:.0f}" for v in bbox)
    known = {bd["id"] for bd in detail["buildings"]}
    rd = (222000, 575250, 222320, 575560)

    def xz(x, y):
        return [round(x - ox, 1), round(-(y - oy), 1)]

    # ---------------- BAG footprints (1000 per page)
    def bag():
        feats, start = [], 0
        while True:
            print("BAG page", start // 1000 + 1)
            d = get_json("https://service.pdok.nl/lv/bag/wfs/v2_0?service=WFS&version=2.0.0&request=GetFeature"
                         f"&outputFormat=application/json&srsName=EPSG:28992&typeNames=bag:pand&bbox={b},EPSG:28992"
                         f"&count=1000&startIndex={start}")
            feats += [{"id": f["properties"]["identificatie"], "g": f["geometry"]} for f in d["features"]]
            if len(d["features"]) < 1000:
                return feats
            start += 1000
    panden = cached("panden.json", bag)

    # ---------------- 3D BAG roof heights (attributes only are kept)
    def heights():
        out, url, page = {}, f"https://api.3dbag.nl/collections/pand/items?bbox={b}&limit=50", 0
        while url:
            page += 1
            if page % 10 == 1:
                print("3D BAG page", page)
            d = get_json(url)
            for f in d["features"]:
                for oid, o in f["CityObjects"].items():
                    a = o.get("attributes", {})
                    if "b3_h_dak_70p" in a and a["b3_h_dak_70p"] is not None:
                        out[oid.replace("NL.IMBAG.Pand.", "")] = [round(a["b3_h_dak_70p"] - (a.get("b3_h_maaiveld") or 0.0), 1),
                                                                  a.get("b3_dak_type", "")]
            url = next((l["href"] for l in d.get("links", []) if l.get("rel") == "next"), None)
        return out
    hts = cached("heights.json", heights)

    # ---------------- OpenStreetMap, in tiles (the API caps nodes per request)
    from pyproj import Transformer
    to_ll = Transformer.from_crs("EPSG:28992", "EPSG:4326", always_xy=True)
    to_rd = Transformer.from_crs("EPSG:4326", "EPSG:28992", always_xy=True)
    N = 4
    nodes, ways = {}, {}
    for i in range(N):
        for j in range(N):
            x0 = bbox[0] + (bbox[2] - bbox[0]) * i / N
            x1 = bbox[0] + (bbox[2] - bbox[0]) * (i + 1) / N
            y0 = bbox[1] + (bbox[3] - bbox[1]) * j / N
            y1 = bbox[1] + (bbox[3] - bbox[1]) * (j + 1) / N
            lo0, la0 = to_ll.transform(x0, y0)
            lo1, la1 = to_ll.transform(x1, y1)
            d = cached(f"osm_{i}_{j}.json", lambda: (print("OSM tile", i, j), get_json(
                f"https://api.openstreetmap.org/api/0.6/map.json?bbox={lo0:.5f},{la0:.5f},{lo1:.5f},{la1:.5f}"))[1])
            for e in d["elements"]:
                if e["type"] == "node":
                    nodes[e["id"]] = (e["lon"], e["lat"])
                elif e["type"] == "way":
                    ways[e["id"]] = e

    def pts_of(w):
        out = []
        for n in w["nodes"]:
            if n in nodes:
                x, y = to_rd.transform(*nodes[n])
                out += xz(x, y)
        return out

    roads, areas = [], []
    for w in ways.values():
        t = w.get("tags", {})
        hw = t.get("highway")
        if hw in ROAD_W and t.get("area") != "yes" and t.get("tunnel") != "yes":
            p = pts_of(w)
            if len(p) >= 4:
                roads.append([ROAD_W[hw], p])
            continue
        if t.get("waterway") in ("canal", "river", "stream", "ditch", "drain"):
            p = pts_of(w)
            if len(p) >= 4:
                roads.append([{"canal": 12, "river": 14, "stream": 4}.get(t["waterway"], 2.0), p, "water"])
            continue
        if w["nodes"][0] == w["nodes"][-1]:
            for (k, v), kind in AREAS.items():
                if t.get(k) == v:
                    p = pts_of(w)
                    if len(p) >= 8:
                        areas.append([kind, p])
                    break

    # ---------------- buildings
    blds = []
    for f in panden:
        if f["id"] in known:
            continue
        g = f["g"]
        rings = g["coordinates"] if g["type"] == "Polygon" else g["coordinates"][0]
        poly = Polygon(rings[0]).simplify(0.4, preserve_topology=True)
        if poly.is_empty or poly.area < 6.0 or poly.geom_type != "Polygon":
            continue
        cx, cz = xz(poly.centroid.x, poly.centroid.y)
        if rd[0] <= poly.centroid.x <= rd[2] and rd[1] <= poly.centroid.y <= rd[3]:
            continue                                  # inside the detailed map
        h, roof = hts.get(f["id"], [None, ""])
        if h is None or h < 2.0:
            h = 3.0 if poly.area < 40 else 7.0       # sheds / missing data: typical Leek heights
        ring = []
        for x, y in list(poly.exterior.coords)[:-1]:
            ring += xz(x, y)
        blds.append([round(min(h, 60.0), 1), 1 if roof == "slanted" else 0, ring])

    # the detailed map's extent (tools/build_liekeblom.py BBOX_RD): the backdrop stays outside it
    rd = (222000, 575250, 222320, 575560)
    a0, a1 = xz(rd[0], rd[3]), xz(rd[2], rd[1])
    out = {"name": "Leek (backdrop)", "origin_rd": [ox, oy], "half": HALF, "detail_rect": [a0[0], a0[1], a1[0] - a0[0], a1[1] - a0[1]], "buildings": blds, "roads": roads, "areas": areas,
           "credits": "BAG (Kadaster) CC0; 3D BAG (TU Delft / 3DGI) CC BY 4.0; (c) OpenStreetMap contributors ODbL"}
    json.dump(out, open(OUT, "w"), separators=(",", ":"))
    print(f"wrote {len(blds)} buildings, {len(roads)} streets/waterways, {len(areas)} areas -> {OUT} "
          f"({os.path.getsize(OUT) / 1024:.0f} KB)")


if __name__ == "__main__":
    main()
