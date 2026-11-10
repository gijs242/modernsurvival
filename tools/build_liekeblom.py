#!/usr/bin/env python3
"""Builds assets/maps/liekeblom.json — a to-scale model of Winkelcentrum De Liekeblom (Leek, NL)
and the surrounding town centre — from open data:

  * BAG (Kadaster, via PDOK)        building footprints + every shop unit with its floor area     (CC0)
  * 3D BAG (TU Delft / 3DGI)        measured LoD2.2 3D building shapes                            (CC BY 4.0)
  * OpenStreetMap                   mall corridors, entrances, shops, streets, parking, water     (ODbL)

Usage:
    pip install shapely mapbox-earcut numpy pyproj
    python3 tools/build_liekeblom.py            # downloads into build/liekeblom_src, writes assets/maps/liekeblom.json

Coordinates in the output: metres, x = east, z = south (Godot: north is -Z), y = up, origin = mall centre.
"""
import json
import math
import os
import sys
import urllib.parse
import urllib.request
from collections import defaultdict

import mapbox_earcut as earcut
import numpy as np
from shapely.geometry import LineString, Point, Polygon, box
from shapely.ops import unary_union

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "build", "liekeblom_src")
OUT = os.path.join(ROOT, "assets", "maps", "liekeblom.json")
MALL_PAND = "0022100000000253"
BBOX_RD = (222000, 575250, 222320, 575560)     # Dutch RD New (EPSG:28992)
UA = {"User-Agent": "modernsurvival-mapbuilder/1.0"}


# --------------------------------------------------------------------------- download
def fetch(name, url, data=None):
    os.makedirs(SRC, exist_ok=True)
    path = os.path.join(SRC, name)
    if os.path.exists(path):
        return json.load(open(path))
    print("downloading", name)
    req = urllib.request.Request(url, headers=UA, data=data)
    with urllib.request.urlopen(req, timeout=180) as r:
        d = json.loads(r.read())
    json.dump(d, open(path, "w"))
    return d


def fetch_all():
    b = ",".join(map(str, BBOX_RD))
    wfs = "https://service.pdok.nl/lv/bag/wfs/v2_0?service=WFS&version=2.0.0&request=GetFeature&outputFormat=application/json&srsName=EPSG:28992"
    panden = fetch("panden.json", f"{wfs}&typeNames=bag:pand&bbox={b},EPSG:28992&count=1000")
    vbo = fetch("vbo.json", f"{wfs}&typeNames=bag:verblijfsobject&bbox={b},EPSG:28992&count=2000")
    path = os.path.join(SRC, "bag3d.json")
    if os.path.exists(path):
        bag3d = json.load(open(path))
    else:
        url = f"https://api.3dbag.nl/collections/pand/items?bbox={b}&limit=50"
        feats = []
        while url:
            print("downloading 3D BAG page", len(feats) // 50 + 1)
            d = json.load(urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=180))
            for f in d["features"]:
                f["_transform"] = d["metadata"]["transform"]
            feats += d["features"]
            url = next((l["href"] for l in d.get("links", []) if l.get("rel") == "next"), None)
        bag3d = {"features": feats}
        json.dump(bag3d, open(path, "w"))
    from pyproj import Transformer
    t = Transformer.from_crs("EPSG:28992", "EPSG:4326", always_xy=True)
    lo0, la0 = t.transform(BBOX_RD[0], BBOX_RD[1])
    lo1, la1 = t.transform(BBOX_RD[2], BBOX_RD[3])
    osm = fetch("osm.json", f"https://api.openstreetmap.org/api/0.6/map.json?bbox={lo0:.5f},{la0:.5f},{lo1:.5f},{la1:.5f}")
    return panden, vbo, bag3d, osm


# --------------------------------------------------------------------------- helpers
def triangulate(poly3d, holes3d=()):
    """Triangulate a planar 3D polygon (with optional holes). Returns list of 3D points (3 per triangle)."""
    pts = np.array(poly3d, float)
    if len(pts) < 3:
        return []
    n = np.zeros(3)
    for i in range(len(pts)):                      # Newell normal
        a, b = pts[i], pts[(i + 1) % len(pts)]
        n += [(a[1] - b[1]) * (a[2] + b[2]), (a[2] - b[2]) * (a[0] + b[0]), (a[0] - b[0]) * (a[1] + b[1])]
    ax = int(np.argmax(np.abs(n)))
    keep = [i for i in range(3) if i != ax]
    rings = [pts] + [np.array(h, float) for h in holes3d if len(h) >= 3]
    flat = np.concatenate([r[:, keep] for r in rings])
    ends = np.cumsum([len(r) for r in rings]).astype(np.uint32)
    idx = earcut.triangulate_float64(flat, ends)
    allp = np.concatenate(rings)
    out = []
    for t in range(0, len(idx), 3):
        a, b, c = allp[idx[t]], allp[idx[t + 1]], allp[idx[t + 2]]
        if np.dot(np.cross(b - a, c - a), n) < 0:      # keep CityJSON's outward orientation
            b, c = c, b
        out += [a, b, c]
    return out


def clip_polygon_below(poly, h):
    """Keep the part of a 3D polygon with z >= h (Sutherland–Hodgman against one plane)."""
    out = []
    n = len(poly)
    for i in range(n):
        a, b = poly[i], poly[(i + 1) % n]
        ain, bin_ = a[2] >= h, b[2] >= h
        if ain:
            out.append(a)
        if ain != bin_:
            t = (h - a[2]) / (b[2] - a[2])
            out.append(a + (b - a) * t)
    return out


class Frame:
    """RD -> local metres (x east, z south)."""
    def __init__(self, cx, cy):
        self.cx, self.cy = cx, cy

    def xz(self, x, y):
        return (round(x - self.cx, 3), round(-(y - self.cy), 3))


def flat(tris, F, base):
    """3D RD triangles (NAP heights) -> flat list [x,y,z,...] in local coords."""
    out = []
    for p in tris:
        x, z = F.xz(p[0], p[1])
        out += [x, round(float(p[2]) - base, 3), z]
    return out


# --------------------------------------------------------------------------- main
def main():
    panden, vbo, bag3d, osm = fetch_all()
    mall_feat = next(f for f in panden["features"] if f["properties"]["identificatie"] == MALL_PAND)
    mall_rd = Polygon(mall_feat["geometry"]["coordinates"][0])
    c = mall_rd.centroid
    F = Frame(c.x, c.y)
    mall_poly = Polygon([F.xz(x, y) for x, y in mall_rd.exterior.coords])

    # ---------------- OSM
    from pyproj import Transformer
    tr = Transformer.from_crs("EPSG:4326", "EPSG:28992", always_xy=True)
    nodes = {}
    for e in osm["elements"]:
        if e["type"] == "node":
            x, y = tr.transform(e["lon"], e["lat"])
            nodes[e["id"]] = (F.xz(x, y), e.get("tags", {}))
    ways = [e for e in osm["elements"] if e["type"] == "way"]

    corridors, entrances, pois, roads, areas = [], [], [], [], []
    for w in ways:
        t = w.get("tags", {})
        pts = [nodes[n][0] for n in w["nodes"] if n in nodes]
        if len(pts) < 2:
            continue
        hw = t.get("highway")
        if hw == "corridor":
            corridors.append(pts)
        elif hw:
            roads.append({"kind": hw, "pts": pts, "name": t.get("name", "")})
        if t.get("amenity") == "parking" and pts[0] == pts[-1]:
            areas.append({"kind": "parking", "pts": pts})
        elif t.get("natural") == "water" and pts[0] == pts[-1]:
            areas.append({"kind": "water", "pts": pts})
        elif t.get("landuse") in ("grass", "forest") and pts[0] == pts[-1]:
            areas.append({"kind": t["landuse"], "pts": pts})
    street_pois = []
    for nid, (p, t) in nodes.items():
        k2 = t.get("amenity") or t.get("shop")
        if k2 in ("restaurant", "cafe", "fast_food", "bar", "pub", "ice_cream", "bench", "waste_basket", "bicycle_parking") and not mall_poly.buffer(1.0).contains(Point(p)):
            street_pois.append({"kind": k2, "pos": p, "name": t.get("name", "")})
    mall_buf = mall_poly.buffer(0.8)
    FIXTURES = {"bench", "toilets", "atm", "parcel_locker", "vending_machine", "fountain", "post_box"}
    for nid, (p, t) in nodes.items():
        if t.get("entrance") and mall_buf.exterior.distance(Point(p)) < 3.0:
            entrances.append(p)
        kind = t.get("shop") or t.get("amenity")
        if kind and mall_poly.buffer(1.5).contains(Point(p)):
            pois.append({"name": t.get("name", ""), "kind": kind, "pos": p, "fixture": kind in FIXTURES,
                         "hn": t.get("addr:housenumber", "")})

    # ---------------- BAG units inside the mall (the real shop units with floor areas)
    units = []
    for f in vbo["features"]:
        pr = f["properties"]
        if pr["pandidentificatie"] != MALL_PAND:
            continue
        use = pr["gebruiksdoel"]
        use = use[0] if isinstance(use, list) else use
        if "woon" in use:
            continue                                       # apartments are upstairs
        x, y = f["geometry"]["coordinates"][:2]
        units.append({"num": f"{pr['huisnummer']}{pr.get('huisletter') or ''}", "area": pr["oppervlakte"], "use": use, "pos": F.xz(x, y)})
    # label each unit: first by matching house number (e.g. OSM "16-20" covers BAG unit 18), then nearest POI
    shop_pois = [p for p in pois if not p["fixture"]]

    def hn_match(hn, num):
        import re
        n = re.match(r"(\d+)", num)
        if not hn or not n:
            return False
        n = int(n.group(1))
        for part in hn.replace(";", ",").split(","):
            part = part.strip()
            m = re.match(r"(\d+)\s*-\s*(\d+)$", part)
            if m and int(m.group(1)) <= n <= int(m.group(2)):
                return True
            if part.lower() == num.lower():
                return True
        return False
    used = set()
    for u in units:
        match = next((p for p in shop_pois if hn_match(p["hn"], u["num"])), None)
        if match:
            used.add(id(match))
            u["kind"], u["label"], u["seed"] = match["kind"], match["name"], match["pos"]
    for u in units:
        if "kind" in u:
            continue
        best, bd = None, 1e9
        for p in shop_pois:
            if id(p) in used:
                continue
            d = math.dist(u["pos"], p["pos"])
            if d < bd:
                best, bd = p, d
        if best and bd < 12:
            used.add(id(best))
            u["kind"], u["label"] = best["kind"], best["name"]
        else:
            u["kind"], u["label"] = ("vacant" if u["area"] < 30 else "retail"), ""

    # ---------------- 3D buildings
    buildings = []
    mall_heights = None
    for feat in bag3d["features"]:
        bid = feat["id"]
        T = feat["_transform"]
        V = np.array(feat["vertices"], float) * T["scale"] + T["translate"]
        bobj = feat["CityObjects"][bid]
        base = bobj["attributes"].get("b3_h_maaiveld") or 0.0
        is_mall = MALL_PAND in bid
        walls, roofs_slanted, roofs_flat = [], [], []
        for cid in bobj.get("children", []):
            part = feat["CityObjects"][cid]
            geo = [g for g in part.get("geometry", []) if g["lod"] == "2.2"]
            if not geo:
                continue
            g = geo[0]
            shells = g["boundaries"] if g["type"] == "Solid" else [g["boundaries"]]
            types = [s["type"] for s in g["semantics"]["surfaces"]]
            vals = g["semantics"]["values"][0] if g["type"] == "Solid" else g["semantics"]["values"]
            for i, surf in enumerate(shells[0]):
                st = types[vals[i]] if vals[i] is not None else "WallSurface"
                if st == "GroundSurface":
                    continue
                ring = V[surf[0]]
                holes = [V[h] for h in surf[1:]]
                if st == "RoofSurface":
                    tris = triangulate(ring, holes)
                    nz = abs(np.cross(ring[1] - ring[0], ring[2] - ring[0])[2]) / (np.linalg.norm(np.cross(ring[1] - ring[0], ring[2] - ring[0])) + 1e-9)
                    (roofs_flat if nz > 0.97 else roofs_slanted).extend(tris)
                else:
                    if is_mall and ring[:, 2].min() - base < 0.6:
                        # mall outer walls: we keep the part above the shop fronts and generate the
                        # ground floor ourselves (with real door openings)
                        ring = np.array(clip_polygon_below(list(ring), base + GF_H))
                        if len(ring) < 3:
                            continue
                        holes = []
                    walls.extend(triangulate(ring, holes))
        if not (walls or roofs_flat or roofs_slanted):
            continue
        # footprint (local) for minimap / navigation
        fp = None
        for pf in panden["features"]:
            if pf["properties"]["identificatie"] in bid:
                fp = [F.xz(x, y) for x, y in pf["geometry"]["coordinates"][0]]
                break
        b = {"id": bid.split(".")[-1], "mall": is_mall, "walls": flat(walls, F, base), "roof_flat": flat(roofs_flat, F, base),
             "roof_slanted": flat(roofs_slanted, F, base), "footprint": fp,
             "height": round((bobj["attributes"].get("b3_h_dak_70p") or base + 6) - base, 2)}
        buildings.append(b)
        if is_mall:
            mall_heights = (roofs_flat + roofs_slanted, base)

    # ---------------- interior grid aligned to the building (so walls come out straight)
    ring = list(mall_poly.exterior.coords)
    hist = defaultdict(float)
    for (x0, z0), (x1, z1) in zip(ring, ring[1:]):
        ang = math.degrees(math.atan2(z1 - z0, x1 - x0)) % 90.0
        hist[round(ang)] += math.hypot(x1 - x0, z1 - z0)
    theta = math.radians(max(hist, key=hist.get))
    ct, st = math.cos(theta), math.sin(theta)
    to_uv = lambda x, z: (x * ct + z * st, -x * st + z * ct)
    to_xz = lambda u, v: (round(u * ct - v * st, 3), round(u * st + v * ct, 3))
    mall_uv = Polygon([to_uv(*p) for p in ring])
    minu, minv, maxu, maxv = mall_uv.bounds
    CELL = 0.5
    nx, nz = int((maxu - minu) / CELL) + 2, int((maxv - minv) / CELL) + 2
    cu = lambda i: minu + (i + 0.5) * CELL
    cv = lambda j: minv + (j + 0.5) * CELL

    # roof heightfield under the real 3D BAG roof
    rtris, rbase = mall_heights
    roof_h = np.full((nz, nx), 99.0)
    for t0 in range(0, len(rtris), 3):
        tri = []
        for pnt in rtris[t0:t0 + 3]:
            u, v = to_uv(*F.xz(pnt[0], pnt[1]))
            tri.append((u, v, float(pnt[2]) - rbase))
        (x0, z0, h0), (x1, z1, h1), (x2, z2, h2) = tri
        den = (z1 - z2) * (x0 - x2) + (x2 - x1) * (z0 - z2)
        if abs(den) < 1e-9:
            continue
        i0 = max(0, int((min(x0, x1, x2) - minu) / CELL)); i1 = min(nx - 1, int((max(x0, x1, x2) - minu) / CELL) + 1)
        j0 = max(0, int((min(z0, z1, z2) - minv) / CELL)); j1 = min(nz - 1, int((max(z0, z1, z2) - minv) / CELL) + 1)
        for j in range(j0, j1 + 1):
            for i in range(i0, i1 + 1):
                px, pz = cu(i), cv(j)
                l0 = ((z1 - z2) * (px - x2) + (x2 - x1) * (pz - z2)) / den
                l1 = ((z2 - z0) * (px - x2) + (x0 - x2) * (pz - z2)) / den
                l2 = 1 - l0 - l1
                if l0 >= -0.01 and l1 >= -0.01 and l2 >= -0.01:
                    roof_h[j, i] = min(roof_h[j, i], l0 * h0 + l1 * h1 + l2 * h2)

    inside = np.zeros((nz, nx), bool)
    edge = np.zeros((nz, nx), bool)            # cells touching the outer wall
    corridor = np.zeros((nz, nx), bool)
    cor_lines = [LineString([to_uv(*q) for q in c]) for c in corridors]
    ent_uv = [to_uv(*e) for e in entrances]
    ent_lines = []
    for e in ent_uv:
        if cor_lines:
            near = min(cor_lines, key=lambda l: l.distance(Point(e)))
            q = near.interpolate(near.project(Point(e)))
            ent_lines.append(LineString([e, (q.x, q.y)]))
    inner = mall_uv.buffer(-0.25)
    near_edge = mall_uv.exterior.buffer(1.2)
    for j in range(nz):
        for i in range(nx):
            p = Point(cu(i), cv(j))
            if not inner.contains(p):
                continue
            inside[j, i] = True
            edge[j, i] = near_edge.contains(p)
            if any(l.distance(p) < 2.6 for l in cor_lines) or any(l.distance(p) < 1.8 for l in ent_lines):
                corridor[j, i] = True

    import heapq
    region = np.full((nz, nx), -1, int)
    region[corridor] = 0
    seeds = []
    for k, u in enumerate(units, start=1):
        sp = to_uv(*u.get("seed", u["pos"]))
        i, j = int((sp[0] - minu) / CELL), int((sp[1] - minv) / CELL)
        best = None
        for r in range(0, 40):
            for dj in range(-r, r + 1):
                for di in range(-r, r + 1):
                    jj, ii = j + dj, i + di
                    if 0 <= jj < nz and 0 <= ii < nx and inside[jj, ii] and not corridor[jj, ii]:
                        best = (jj, ii)
                        break
                if best:
                    break
            if best:
                break
        if best:
            seeds.append((k, best, math.sqrt(max(u["area"], 10.0))))
    dist = np.full((nz, nx), np.inf)
    pq = []
    for k, (j, i), w in seeds:
        dist[j, i] = 0.0
        region[j, i] = k
        heapq.heappush(pq, (0.0, j, i, k, w))
    while pq:
        d, j, i, k, w = heapq.heappop(pq)
        if d > dist[j, i] or region[j, i] != k:
            continue
        for dj, di in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            jj, ii = j + dj, i + di
            if 0 <= jj < nz and 0 <= ii < nx and inside[jj, ii] and not corridor[jj, ii]:
                nd = d + 1.0 / w
                if nd < dist[jj, ii]:
                    dist[jj, ii] = nd
                    region[jj, ii] = k
                    heapq.heappush(pq, (nd, jj, ii, k, w))

    # space no unit reached: enclosed by corridors -> the open main hall; against the outer wall -> extra shop
    hall = np.zeros((nz, nx), bool)
    k_next = len(units) + 1
    for j in range(nz):
        for i in range(nx):
            if inside[j, i] and region[j, i] == -1:
                comp, stack = [], [(j, i)]
                region[j, i] = -2
                while stack:
                    a0, b0 = stack.pop()
                    comp.append((a0, b0))
                    for da, db in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                        aa, bb = a0 + da, b0 + db
                        if 0 <= aa < nz and 0 <= bb < nx and inside[aa, bb] and region[aa, bb] == -1:
                            region[aa, bb] = -2
                            stack.append((aa, bb))
                touches_outside = any(edge[a0, b0] for a0, b0 in comp)
                area = len(comp) * CELL * CELL
                if not touches_outside or area < 12:
                    for a0, b0 in comp:
                        region[a0, b0] = 0
                        hall[a0, b0] = not touches_outside
                    continue
                cz_ = np.mean([cv(c[0]) for c in comp]); cx_ = np.mean([cu(c[1]) for c in comp])
                units.append({"num": "-", "area": round(area), "use": "winkelfunctie", "pos": to_xz(cx_, cz_), "kind": "retail", "label": ""})
                for a0, b0 in comp:
                    region[a0, b0] = k_next
                k_next += 1
    openspace = region == 0

    def ceil_at(j, i):
        return roof_h[j, i] if roof_h[j, i] < 90 else 4.0

    # suspended ceilings in shops (<= 3.2 m); the hall and corridors stay open to the (glass) roof
    ceilings = []
    rows = defaultdict(list)
    for j in range(nz):
        for i in range(nx):
            if inside[j, i] and region[j, i] > 0:
                rows[(j, round(min(3.2, ceil_at(j, i) - 0.15), 1))].append(i)
    for (j, h), xs in rows.items():
        xs.sort()
        s0 = xs[0]
        for a0, b0 in zip(xs, xs[1:] + [None]):
            if b0 != a0 + 1:
                u0, u1 = minu + s0 * CELL, minu + (a0 + 1) * CELL
                v0, v1 = minv + j * CELL, minv + (j + 1) * CELL
                ceilings.append({"pts": [to_xz(u0, v0), to_xz(u1, v0), to_xz(u1, v1), to_xz(u0, v1)], "h": h})
                s0 = b0

    # walls on region boundaries (merged into straight runs)
    segs = defaultdict(list)
    for j in range(nz):
        for i in range(nx):
            if not inside[j, i]:
                continue
            for dj, di, ori in ((0, 1, "u"), (1, 0, "v")):
                jj, ii = j + dj, i + di
                if not (0 <= jj < nz and 0 <= ii < nx) or not inside[jj, ii]:
                    continue
                ra, rb = region[j, i], region[jj, ii]
                if ra == rb:
                    continue
                if ra == 0 or rb == 0:
                    kind, shop = "front", (rb if ra == 0 else ra)
                    h = round(max(ceil_at(j, i), ceil_at(jj, ii)) - 0.05, 1)
                    side = -1 if ra == 0 else 1          # which side of the line the open space is on
                else:
                    kind, shop, side = "partition", -(min(ra, rb) * 1000 + max(ra, rb)), 0
                    h = round(min(3.2, ceil_at(j, i) - 0.15, ceil_at(jj, ii) - 0.15), 1)
                if ori == "u":   # wall at constant u
                    line, span = minu + (i + 1) * CELL, (minv + j * CELL, minv + (j + 1) * CELL)
                else:            # wall at constant v
                    line, span = minv + (j + 1) * CELL, (minu + i * CELL, minu + (i + 1) * CELL)
                segs[(ori, round(line, 3), kind, h, shop, side)].append(span)
    walls = []
    for (ori, line, kind, h, shop, side), spans in segs.items():
        spans.sort()
        s0, s1 = spans[0]
        for a0, b0 in spans[1:] + [(None, None)]:
            if a0 is not None and abs(a0 - s1) < 1e-6:
                s1 = b0
                continue
            if ori == "u":
                pa, pb = to_xz(line, s0), to_xz(line, s1)
                nrm = (ct * side, st * side)
            else:
                pa, pb = to_xz(s0, line), to_xz(s1, line)
                nrm = (-st * side, ct * side)
            walls.append({"a": pa, "b": pb, "kind": kind, "h": h, "shop": shop, "open_n": [round(nrm[0], 3), round(nrm[1], 3)]})
            if a0 is not None:
                s0, s1 = a0, b0
    # straighten staircase runs: merge each shop's front (and each partition) into lines and simplify
    from shapely.geometry import MultiLineString
    from shapely.ops import linemerge
    grouped = defaultdict(list)
    for w in walls:
        grouped[(w["kind"], w["shop"])].append(w)
    walls = []
    for (kind, shop), ws in grouped.items():
        hmax = max(w["h"] for w in ws)
        n_avg = (np.mean([w["open_n"][0] for w in ws]), np.mean([w["open_n"][1] for w in ws]))
        merged = linemerge(MultiLineString([[tuple(w["a"]), tuple(w["b"])] for w in ws]))
        lines = list(merged.geoms) if merged.geom_type == "MultiLineString" else [merged]
        for ln in lines:
            sl = ln.simplify(0.75, preserve_topology=False)
            cs = list(sl.coords)
            for pa, pb in zip(cs, cs[1:]):
                if math.dist(pa, pb) < 0.05:
                    continue
                dx, dz = pb[0] - pa[0], pb[1] - pa[1]
                L = math.hypot(dx, dz)
                nrm = (-dz / L, dx / L)
                if nrm[0] * n_avg[0] + nrm[1] * n_avg[1] < 0:
                    nrm = (-nrm[0], -nrm[1])
                walls.append({"a": [round(pa[0], 3), round(pa[1], 3)], "b": [round(pb[0], 3), round(pb[1], 3)], "kind": kind, "h": hmax,
                              "shop": shop if kind == "front" else -1, "open_n": [round(nrm[0], 3), round(nrm[1], 3)] if kind == "front" else [0, 0]})
    by_shop = defaultdict(list)
    for w in walls:
        if w["kind"] == "front":
            by_shop[w["shop"]].append(w)
    door_of = {}
    for shop, ws in by_shop.items():
        best = max(ws, key=lambda w: math.dist(w["a"], w["b"]))
        L = math.dist(best["a"], best["b"])
        if L >= 2.4:
            best["door"] = round(L / 2, 2)
            mid = ((best["a"][0] + best["b"][0]) / 2, (best["a"][1] + best["b"][1]) / 2)
            door_of[shop] = (mid, (-best["open_n"][0], -best["open_n"][1]))

    shops = []
    for k, u in enumerate(units, start=1):
        cells = np.argwhere(region == k)
        if len(cells) == 0:
            continue
        cuv = (cu(0) + cells[:, 1].mean() * CELL, cv(0) + cells[:, 0].mean() * CELL)
        d = door_of.get(k)
        shops.append({"id": k, "num": u["num"], "kind": u["kind"], "label": u["label"], "area_bag": u["area"],
                      "area_game": round(len(cells) * CELL * CELL, 1), "center": list(to_xz(*cuv)),
                      "door": [round(d[0][0], 3), round(d[0][1], 3)] if d else None, "inward": [round(d[1][0], 3), round(d[1][1], 3)] if d else None,
                      "size": [round((cells[:, 1].max() - cells[:, 1].min() + 1) * CELL, 1), round((cells[:, 0].max() - cells[:, 0].min() + 1) * CELL, 1)]})

    # open-space cells (corridor + hall) as merged strips, with the roof height above them
    open_strips = []
    for j in range(nz):
        i = 0
        while i < nx:
            if openspace[j, i]:
                s0 = i
                while i < nx and openspace[j, i]:
                    i += 1
                hh = float(np.min([ceil_at(j, q) for q in range(s0, i)]))
                hl = bool(hall[j, s0:i].any())
                u0, u1, v0, v1 = minu + s0 * CELL, minu + i * CELL, minv + j * CELL, minv + (j + 1) * CELL
                open_strips.append({"pts": [to_xz(u0, v0), to_xz(u1, v0), to_xz(u1, v1), to_xz(u0, v1)], "roof": round(hh, 2), "hall": hl})
            else:
                i += 1
    hall_cells = np.argwhere(hall)
    hall_center = list(to_xz(cu(0) + hall_cells[:, 1].mean() * CELL, cv(0) + hall_cells[:, 0].mean() * CELL)) if len(hall_cells) else [0, 0]

    # glass roof: mall roof triangles above the open space
    for b in buildings:
        if not b["mall"]:
            continue
        keep_f, keep_s, glass = [], [], []
        for key, keep in (("roof_flat", keep_f), ("roof_slanted", keep_s)):
            arr = b[key]
            for t0 in range(0, len(arr), 9):
                tri = arr[t0:t0 + 9]
                gx, gy, gz = (tri[0] + tri[3] + tri[6]) / 3, (tri[1] + tri[4] + tri[7]) / 3, (tri[2] + tri[5] + tri[8]) / 3
                u, v = to_uv(gx, gz)
                i, j = int((u - minu) / CELL), int((v - minv) / CELL)
                over_open = 0 <= j < nz and 0 <= i < nx and openspace[j, i]
                (glass if over_open and gy > 4.2 else keep).extend(tri)
        b["roof_flat"], b["roof_slanted"], b["roof_glass"] = keep_f, keep_s, glass

    # mall ground-floor shell (outer walls up to the roof edge) with door openings at the entrances
    shell = []
    cen = mall_poly.centroid
    for a0, b0 in zip(ring, ring[1:]):
        seg = LineString([a0, b0])
        if seg.length < 0.05:
            continue
        mid = seg.interpolate(0.5, normalized=True)
        dx, dz = cen.x - mid.x, cen.y - mid.y
        L = math.hypot(dx, dz) or 1
        u, v = to_uv(mid.x + dx / L * 0.8, mid.y + dz / L * 0.8)
        i, j = min(nx - 1, max(0, int((u - minu) / CELL))), min(nz - 1, max(0, int((v - minv) / CELL)))
        h = round(min(GF_H, ceil_at(j, i)), 2)
        doors = [round(seg.project(Point(e)), 2) for e in entrances if seg.distance(Point(e)) < 1.5]
        shell.append({"a": [round(a0[0], 3), round(a0[1], 3)], "b": [round(b0[0], 3), round(b0[1], 3)], "h": h, "doors": doors})

    # spawn points: street points near the edge of the playable area, outside buildings
    bx0, bz0, bx1, bz1 = (BBOX_RD[0] - c.x + 12, -(BBOX_RD[3] - c.y) + 12, BBOX_RD[2] - c.x - 12, -(BBOX_RD[1] - c.y) - 12)
    fps_ = [Polygon(b["footprint"]).buffer(1.0) for b in buildings if b.get("footprint")]
    blocked = unary_union(fps_)
    cand = []
    for r in roads:
        if r["kind"] in ("tertiary", "residential", "service", "pedestrian", "footway"):
            ls = LineString(r["pts"])
            for t in np.linspace(0, ls.length, max(2, int(ls.length / 4))):
                q = ls.interpolate(t)
                edge_d = min(q.x - bx0, bx1 - q.x, q.y - bz0, bz1 - q.y)
                if 6 < edge_d < 40 and not blocked.contains(q):
                    cand.append((q.x, q.y))
    spawns = []
    for p in sorted(cand, key=lambda p: -math.hypot(*p)):
        if all(math.dist(p, s2) > 25 for s2 in spawns):
            spawns.append((round(p[0], 2), round(p[1], 2)))
        if len(spawns) >= 10:
            break

    out = {
        "name": "Winkelcentrum De Liekeblom, Leek",
        "origin_rd": [round(c.x, 3), round(c.y, 3)],
        "bounds": [round(bx0, 1), round(bz0, 1), round(bx1, 1), round(bz1, 1)],
        "ground_floor_h": GF_H,
        "buildings": buildings,
        "mall": {"footprint": [list(p) for p in mall_poly.exterior.coords], "shell": shell, "corridors": corridors,
                 "entrances": entrances, "pois": pois, "units": units, "shops": shops, "walls": walls, "ceilings": ceilings,
                 "open": open_strips, "hall_center": hall_center, "theta": round(theta, 5)},
        "spawns": spawns,
        "street_pois": street_pois,
        "roads": roads,
        "areas": areas,
        "credits": "BAG (Kadaster, CC0) via PDOK; 3D BAG (TU Delft/3DGI, CC BY 4.0); © OpenStreetMap contributors (ODbL)",
    }
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    json.dump(out, open(OUT, "w"), separators=(",", ":"), default=lambda o: o.tolist() if hasattr(o, "tolist") else float(o))
    print(f"wrote {OUT}: {len(buildings)} buildings, {len(shops)} shops, {len(walls)} interior walls, "
          f"{len(ceilings)} ceiling strips, {len(entrances)} entrances, {len(corridors)} corridors, {len(roads)} roads, {len(spawns)} spawns")
    for s in shops:
        print(f"  unit {s['num']:>5} {s['kind']:<14} {s['label'][:24]:<24} BAG {s['area_bag']:>5} m²  game {s['area_game']:>7} m²")
    return out


GF_H = 3.4    # height of the mall's ground floor we rebuild (shop fronts + door openings)

if __name__ == "__main__":
    if len(sys.argv) > 1:
        SRC = sys.argv[1]
    main()
