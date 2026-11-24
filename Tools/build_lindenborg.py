#!/usr/bin/env python3
"""Build the grey-box layout for the Lindenborg map (rsg de Borgen, Waezenburglaan 55, Leek).

    python3 Tools/build_lindenborg.py            # download (cached) + build
    python3 Tools/build_lindenborg.py --offline  # rebuild from Tools/.cache only
    python3 Tools/build_lindenborg.py --intact   # without the abandoned / war-damage pass

Sources (all public, see RawAssets/Lindenborg/SOURCES.md for licences):
  * 3D BAG (TU Delft / 3DGI): school footprint (LoD0) and roof parts with heights (LoD1.3),
    neighbouring buildings.                                     -> "Measured" / "Context"
  * AHN4 DTM 0.5 m (PDOK WCS): ground height                   -> terrain mesh
  * BGT (PDOK OGC API): roads, paths, parking, yards, grass, water -> terrain materials, parking
  * Everything inside the building and the schoolyard props are GUESSED (no public floor plan
    found) and go to the "Guessed" layer. See NOTES_FOR_ME.md for what to send to replace them.

Output (consumed by Scripts/setup_project.py inside Unreal):
  RawAssets/Lindenborg/lindenborg_layout.json   boxes, spawn points, buy stations, nav bounds...
  RawAssets/Lindenborg/terrain.obj/.mtl          AHN terrain with BGT surface materials
  Docs/lindenborg_plan_*.png                     plan previews

Coordinates: Unreal cm. Origin = school footprint centroid at the school's ground level
(NAP from 3D BAG b3_h_maaiveld). X = east, Y = south (so the map is not mirrored), Z = up.
"""
from __future__ import annotations

import json
import math
import sys
import urllib.parse
import urllib.request
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

from lindenborg_ruin import ENTRANCE_CLEAR, Ruin

ROOT = Path(__file__).resolve().parent.parent
CACHE = ROOT / "Tools" / ".cache" / "lindenborg"
OUT = ROOT / "RawAssets" / "Lindenborg"
DOCS = ROOT / "Docs"

SCHOOL_PAND = "NL.IMBAG.Pand.0022100000007775"
CONTEXT_RADIUS = 230.0       # m, neighbouring buildings
TERRAIN_HALF = 180.0         # m, terrain mesh half size
TERRAIN_CELL = 2.0           # m
CELL = 0.5                   # m, raster for floors / plan
STOREY_TOP = 3.70            # m, first floor finished level (guess: typical 1985 school, 3.6-3.7 m)
GROUND_TOP = 0.10            # m, ground floor finished level above terrain
SLAB = 0.30
ROOF_SLAB = 0.40
WALL_T = 0.30
INNER_T = 0.15
UA = "ModernSurvivalGreybox/1.0 (map build script)"


# --------------------------------------------------------------------------------------------- fetch

def fetch(url: str, path: Path, offline: bool) -> bytes:
    if path.exists():
        return path.read_bytes()
    if offline:
        raise SystemExit(f"missing cache {path} (run without --offline)")
    path.parent.mkdir(parents=True, exist_ok=True)
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=120) as r:
        data = r.read()
    path.write_bytes(data)
    return data


def fetch_3dbag(bbox, offline):
    items = []
    url = "https://api.3dbag.nl/collections/pand/items?" + urllib.parse.urlencode({"bbox": ",".join(f"{v:.0f}" for v in bbox), "limit": 100})
    page = 0
    while url and page < 30:
        data = json.loads(fetch(url, CACHE / f"3dbag_{page:02d}.json", offline))
        # Each page carries its own CityJSON transform (vertices are quantised per page).
        page_transform = data["metadata"]["transform"]
        items.extend((f, page_transform) for f in data.get("features", []))
        url = next((l["href"] for l in data.get("links", []) if l.get("rel") == "next"), None)
        page += 1
    return items


def fetch_bgt(collection, bbox, offline):
    crs = "http://www.opengis.net/def/crs/EPSG/0/28992"
    q = urllib.parse.urlencode({"bbox": ",".join(f"{v:.0f}" for v in bbox), "bbox-crs": crs, "crs": crs, "limit": 1000, "f": "json"})
    data = json.loads(fetch(f"https://api.pdok.nl/lv/bgt/ogc/v1/collections/{collection}/items?{q}", CACHE / f"bgt_{collection}.json", offline))
    return data.get("features", [])


def fetch_ahn(bbox, offline):
    q = (f"SERVICE=WCS&VERSION=2.0.1&REQUEST=GetCoverage&COVERAGEID=dtm_05m&FORMAT=image/tiff"
         f"&SUBSET=x({bbox[0]:.0f},{bbox[2]:.0f})&SUBSET=y({bbox[1]:.0f},{bbox[3]:.0f})")
    path = CACHE / "ahn_dtm_05m.tif"
    fetch("https://service.pdok.nl/rws/ahn/wcs/v1_0?" + q, path, offline)
    a = np.array(Image.open(path), dtype=np.float64)
    a[a > 1e30] = np.nan
    return a  # row 0 = north (max y)


# --------------------------------------------------------------------------------------------- cityjson

def cityjson_vertices(feature_doc):
    tr = feature_doc["metadata"]["transform"] if "metadata" in feature_doc else None
    return tr


def decode_feature(item, transform):
    s, t = transform["scale"], transform["translate"]
    V = [(v[0] * s[0] + t[0], v[1] * s[1] + t[1], v[2] * s[2] + t[2]) for v in item["vertices"]]
    return V


def signed_area(poly):
    return 0.5 * sum(poly[i][0] * poly[(i + 1) % len(poly)][1] - poly[(i + 1) % len(poly)][0] * poly[i][1] for i in range(len(poly)))


def building_info(item, transform):
    """Returns dict(id, attrs, footprint (outer ring XY), parts [(ring XY, roof_z)])"""
    V = decode_feature(item, transform)
    out = []
    for oid, obj in item["CityObjects"].items():
        if obj["type"] != "Building":
            continue
        attrs = obj.get("attributes", {})
        lod0 = next((g for g in obj.get("geometry", []) if str(g["lod"]) == "0"), None)
        if not lod0:
            continue
        ring = [V[i][:2] for i in lod0["boundaries"][0][0]]
        parts = []
        for cid in obj.get("children", []):
            child = item["CityObjects"].get(cid, {})
            g13 = next((g for g in child.get("geometry", []) if str(g["lod"]) == "1.3"), None)
            if not g13:
                continue
            sem = g13["semantics"]
            for si, surf in enumerate(g13["boundaries"][0]):
                if sem["surfaces"][sem["values"][0][si]]["type"] == "RoofSurface":
                    r = [V[i] for i in surf[0]]
                    parts.append(([p[:2] for p in r], sum(p[2] for p in r) / len(r)))
        out.append({"id": oid, "attrs": attrs, "footprint": ring, "parts": parts})
    return out


# --------------------------------------------------------------------------------------------- frames

class Frame:
    """Local metres around origin, optionally rotated into the building's axes."""

    def __init__(self, e0, n0, z0, theta_deg):
        self.e0, self.n0, self.z0 = e0, n0, z0
        self.theta = math.radians(theta_deg)
        self.c, self.s = math.cos(self.theta), math.sin(self.theta)

    def to_local(self, e, n):
        return e - self.e0, n - self.n0

    def to_b(self, x, y):          # local -> building frame
        return x * self.c + y * self.s, -x * self.s + y * self.c

    def from_b(self, u, v):        # building frame -> local
        return u * self.c - v * self.s, u * self.s + v * self.c

    def rd_to_b(self, e, n):
        return self.to_b(*self.to_local(e, n))

    @staticmethod
    def ue(x, y, z):
        return [round(x * 100, 1), round(-y * 100, 1), round(z * 100, 1)]

    def yaw_ue(self, local_angle_rad):
        return round(-math.degrees(local_angle_rad), 3)


def dominant_angle(rings):
    # Length-weighted mean of edge angles modulo 90 degrees (4x angle trick for circular mean).
    sx = sy = 0.0
    for ring in rings:
        for i in range(len(ring)):
            a, b = ring[i], ring[(i + 1) % len(ring)]
            dx, dy = b[0] - a[0], b[1] - a[1]
            L = math.hypot(dx, dy)
            ang = math.atan2(dy, dx)
            sx += L * math.cos(4 * ang)
            sy += L * math.sin(4 * ang)
    return math.degrees(math.atan2(sy, sx) / 4)


# --------------------------------------------------------------------------------------------- raster

class Grid:
    def __init__(self, umin, vmin, umax, vmax, cell):
        self.umin, self.vmin, self.cell = umin, vmin, cell
        self.cols = int(math.ceil((umax - umin) / cell))
        self.rows = int(math.ceil((vmax - vmin) / cell))

    def mask(self, polys_b):
        im = Image.new("L", (self.cols, self.rows), 0)
        d = ImageDraw.Draw(im)
        for poly in polys_b:
            d.polygon([((u - self.umin) / self.cell - 0.5, (v - self.vmin) / self.cell - 0.5) for u, v in poly], fill=1)
        return np.array(im, dtype=bool)

    def values(self, polys_vals):
        a = np.full((self.rows, self.cols), np.nan)
        for poly, val in polys_vals:
            m = self.mask([poly])
            a[m] = val
        return a

    def cell_center(self, r, c):
        return self.umin + (c + 0.5) * self.cell, self.vmin + (r + 0.5) * self.cell

    def rect_to_b(self, r0, c0, r1, c1):
        # inclusive cell rect -> (u0, v0, u1, v1) metres
        return (self.umin + c0 * self.cell, self.vmin + r0 * self.cell, self.umin + (c1 + 1) * self.cell, self.vmin + (r1 + 1) * self.cell)

    def sample(self, arr, u, v):
        c = int((u - self.umin) / self.cell)
        r = int((v - self.vmin) / self.cell)
        if 0 <= r < self.rows and 0 <= c < self.cols:
            return arr[r, c]
        return None


def largest_rectangle(M):
    rows, cols = M.shape
    h = np.zeros(cols, dtype=np.int32)
    best_area, best = 0, None
    for r in range(rows):
        h = np.where(M[r], h + 1, 0)
        stack = []
        for c in range(cols + 1):
            cur = int(h[c]) if c < cols else 0
            start = c
            while stack and stack[-1][1] > cur:
                sc, sh = stack.pop()
                area = sh * (c - sc)
                if area > best_area:
                    best_area, best = area, (r - sh + 1, sc, r, c - 1)
                start = sc
            stack.append((start, cur))
    return best_area, best


def decompose(M, min_cells=1, max_rects=800):
    M = M.copy()
    rects = []
    while M.any() and len(rects) < max_rects:
        area, rect = largest_rectangle(M)
        if not rect or area < min_cells:
            break
        r0, c0, r1, c1 = rect
        M[r0:r1 + 1, c0:c1 + 1] = False
        rects.append(rect)
    return rects, M


# --------------------------------------------------------------------------------------------- layout

class Layout:
    def __init__(self, frame: Frame):
        self.f = frame
        self.boxes = []
        self.areas = []
        self.spawns = []
        self.stations = []
        self.windows = []          # exterior window openings (for boarding up)
        self.player_start = None
        self.nav = None

    @staticmethod
    def _extra(entry, pitch, roll, shape, collision):
        # Optional fields only when they differ from the defaults (keeps the JSON small).
        if pitch:
            entry["pitch"] = round(pitch, 2)
        if roll:
            entry["roll"] = round(roll, 2)
        if shape != "Cube":
            entry["shape"] = shape
        if not collision:
            entry["collision"] = False
        return entry

    def box_b(self, name, layer, folder, u0, v0, u1, v1, z0, z1, material, kind="block", pitch=0.0, roll=0.0, shape="Cube", collision=True):
        """Axis-aligned box in the building frame (metres)."""
        if u1 - u0 < 0.02 or v1 - v0 < 0.02 or z1 - z0 < 0.02:
            return
        cu, cv = (u0 + u1) / 2, (v0 + v1) / 2
        x, y = self.f.from_b(cu, cv)
        self.boxes.append(self._extra({
            "name": name, "layer": layer, "folder": folder, "material": material, "kind": kind,
            "center": Frame.ue(x, y, (z0 + z1) / 2),
            "size": [round((u1 - u0) * 100, 1), round((v1 - v0) * 100, 1), round((z1 - z0) * 100, 1)],
            "yaw": self.f.yaw_ue(self.f.theta),
        }, pitch, roll, shape, collision))

    def box_local(self, name, layer, folder, cx, cy, length, width, z0, z1, angle, material, kind="block", pitch=0.0, roll=0.0, shape="Cube", collision=True):
        """Box in local metres rotated by angle (radians, CCW from east). pitch/roll in degrees."""
        if length < 0.02 or width < 0.02 or z1 - z0 < 0.02:
            return
        self.boxes.append(self._extra({
            "name": name, "layer": layer, "folder": folder, "material": material, "kind": kind,
            "center": Frame.ue(cx, cy, (z0 + z1) / 2),
            "size": [round(length * 100, 1), round(width * 100, 1), round((z1 - z0) * 100, 1)],
            "yaw": self.f.yaw_ue(angle),
        }, pitch, roll, shape, collision))


def wall_with_openings(L: Layout, name, layer, folder, p, q, inward, z0, z1, bands, openings_fn, material, thickness=WALL_T):
    """Wall along p->q (local metres), inner side = inward unit normal. Cuts window/door openings
    per storey band (zb0, zb1) using openings_fn(length, band_index) -> [(s0, s1, h0, h1)]."""
    dx, dy = q[0] - p[0], q[1] - p[1]
    length = math.hypot(dx, dy)
    if length < 0.3:
        return
    ux, uy = dx / length, dy / length
    ang = math.atan2(dy, dx)
    off = (inward[0] * thickness / 2, inward[1] * thickness / 2)

    def piece(s0, s1, h0, h1, tag):
        if s1 - s0 < 0.05 or h1 - h0 < 0.05:
            return
        m = (s0 + s1) / 2
        cx, cy = p[0] + ux * m + off[0], p[1] + uy * m + off[1]
        L.box_local(f"{name}_{tag}", layer, folder, cx, cy, s1 - s0, thickness, h0, h1, ang, material, "wall")

    covered_low = z0
    for bi, (b0, b1) in enumerate(bands):
        lo, hi = max(z0, b0), min(z1, b1)
        if hi - lo < 0.05:
            continue
        ops = openings_fn(length, bi) if (lo <= b0 + 0.01 and hi >= b1 - 0.01) else []
        if not ops:
            piece(0, length, lo, hi, f"b{bi}")
            continue
        # Solid parts: below the lowest opening sill per span, above heads, and piers.
        cursor = 0.0
        for k, (s0, s1, h0, h1) in enumerate(sorted(ops)):
            if h0 > 0.05:
                m = (s0 + s1) / 2
                L.windows.append({"x": p[0] + ux * m + inward[0] * (thickness + 0.03), "y": p[1] + uy * m + inward[1] * (thickness + 0.03),
                                  "angle": ang, "width": s1 - s0, "z0": lo + h0, "z1": lo + h1, "band": bi, "wall": name})
            piece(cursor, s0, lo, hi, f"b{bi}p{k}")
            piece(s0, s1, lo, lo + h0, f"b{bi}s{k}")
            piece(s0, s1, lo + h1, hi, f"b{bi}l{k}")
            cursor = s1
        piece(cursor, length, lo, hi, f"b{bi}p{len(ops)}")
        covered_low = hi
    # Anything above the last band (parapet, high hall walls).
    top_band = max(b1 for _, b1 in bands) if bands else z0
    if z1 > top_band + 0.05:
        piece(0, length, max(z0, top_band), z1, "top")


def window_pattern(length, band, bay=3.6, width=2.0, sill=0.9, head=2.8):
    n = int(length // bay)
    if length < 3.0 or n < 1:
        return []
    margin = (length - n * bay) / 2
    return [(margin + i * bay + (bay - width) / 2, margin + i * bay + (bay + width) / 2, sill, head) for i in range(n)]


# --------------------------------------------------------------------------------------------- main build

def main():
    offline = "--offline" in sys.argv
    intact = "--intact" in sys.argv
    OUT.mkdir(parents=True, exist_ok=True)
    DOCS.mkdir(parents=True, exist_ok=True)

    # 1) School + neighbours from 3D BAG ------------------------------------------------------
    school_doc = json.loads(fetch(f"https://api.3dbag.nl/collections/pand/items/{SCHOOL_PAND}", CACHE / "school.json", offline))
    transform = school_doc["metadata"]["transform"]
    school = building_info(school_doc["feature"], transform)[0]
    fp = school["footprint"]
    if signed_area(fp) < 0:
        fp = fp[::-1]
    a = signed_area(fp)
    cx = sum((fp[i][0] + fp[(i + 1) % len(fp)][0]) * (fp[i][0] * fp[(i + 1) % len(fp)][1] - fp[(i + 1) % len(fp)][0] * fp[i][1]) for i in range(len(fp))) / (6 * a)
    cy = sum((fp[i][1] + fp[(i + 1) % len(fp)][1]) * (fp[i][0] * fp[(i + 1) % len(fp)][1] - fp[(i + 1) % len(fp)][0] * fp[i][1]) for i in range(len(fp))) / (6 * a)
    ground_nap = float(school["attrs"]["b3_h_maaiveld"])
    theta = dominant_angle([fp])
    F = Frame(cx, cy, ground_nap, theta)
    print(f"school: area {a:.0f} m2, centroid RD ({cx:.1f}, {cy:.1f}), ground {ground_nap:.2f} m NAP, axis {theta:.2f} deg")

    bbox_ctx = (cx - CONTEXT_RADIUS, cy - CONTEXT_RADIUS, cx + CONTEXT_RADIUS, cy + CONTEXT_RADIUS)
    neighbours = []
    for item, page_transform in fetch_3dbag(bbox_ctx, offline):
        for b in building_info(item, page_transform) if "vertices" in item else []:
            if b["id"] != SCHOOL_PAND:
                neighbours.append(b)
    print(f"context buildings: {len(neighbours)}")

    L = Layout(F)
    ruin = None if intact else Ruin(L, F)

    # 2) School shell (Measured) -------------------------------------------------------------
    parts = []
    for ring, z in school["parts"]:
        h = z - ground_nap
        ring_l = [F.to_local(*p) for p in ring]
        if signed_area(ring_l) < 0:
            ring_l = ring_l[::-1]
        parts.append((ring_l, h))
    fp_l = [F.to_local(*p) for p in fp]
    fp_b = [F.to_b(*p) for p in fp_l]
    us, vs = [p[0] for p in fp_b], [p[1] for p in fp_b]
    G = Grid(min(us) - 2, min(vs) - 2, max(us) + 2, max(vs) + 2, CELL)
    snap = lambda poly: [(round(u / CELL) * CELL, round(v / CELL) * CELL) for u, v in poly]
    part_polys_b = [(snap([F.to_b(*p) for p in ring]), h) for ring, h in parts]
    height = G.values(part_polys_b)                 # roof height above ground per cell
    foot = G.mask([snap(fp_b)]) | ~np.isnan(height)
    height[foot & np.isnan(height)] = np.nanmin(height)
    two_storey = foot & (height > 6.0)
    # Confirmed by the owner: the large single-storey block (north-west, ~630 m2) is a roofed,
    # open-sided bike storage, not an aula. Its sides are open (columns only).
    single_parts = [i for i, (_, h) in enumerate(parts) if h < 6.0]
    shed_idx = max(single_parts, key=lambda i: abs(signed_area(parts[i][0]))) if single_parts else None
    shed = (G.mask([part_polys_b[shed_idx][0]]) & foot & ~two_storey) if shed_idx is not None else np.zeros_like(foot)
    shed_f = shed.astype(float)
    print(f"parts: {[(round(h, 2), round(abs(signed_area(r)))) for r, h in parts]}")

    # Storey bands for window cutting: ground floor and first floor.
    def bands_for(h):
        if h > 6.0:
            return [(GROUND_TOP, STOREY_TOP - SLAB), (STOREY_TOP, h - ROOF_SLAB)]
        return [(GROUND_TOP, h - ROOF_SLAB)]

    # Door positions on the exterior: main entrance faces the parking/street side.
    roads = fetch_bgt("wegdeel", (cx - 160, cy - 160, cx + 160, cy + 160), offline)
    targets = []
    for f in roads:
        p = f["properties"]
        if p.get("functie") in ("parkeervlak", "rijbaan lokale weg", "inrit") and f["geometry"]["type"] == "Polygon":
            ring = f["geometry"]["coordinates"][0]
            ex = sum(q[0] for q in ring) / len(ring)
            ny = sum(q[1] for q in ring) / len(ring)
            lx, ly = F.to_local(ex, ny)
            if math.hypot(lx, ly) < 110:
                targets.append((lx, ly))
    street_dir = (sum(t[0] for t in targets), sum(t[1] for t in targets))
    sd = math.hypot(*street_dir) or 1.0
    street_dir = (street_dir[0] / sd, street_dir[1] / sd)

    edges = []
    shed_columns = []
    for part_i, (ring_l, h) in enumerate(parts):
        n = len(ring_l)
        for i in range(n):
            p, q = ring_l[i], ring_l[(i + 1) % n]
            dx, dy = q[0] - p[0], q[1] - p[1]
            length = math.hypot(dx, dy)
            if length < 0.3:
                continue
            inward = (-dy / length, dx / length)           # CCW ring: interior on the left
            mid = ((p[0] + q[0]) / 2, (p[1] + q[1]) / 2)
            out_pt = (mid[0] - inward[0] * 0.8, mid[1] - inward[1] * 0.8)
            h_out = G.sample(height, *F.to_b(*out_pt))
            h_out = 0.0 if h_out is None or np.isnan(h_out) else float(h_out)
            out_in_shed = bool(G.sample(shed_f, *F.to_b(*out_pt)) or 0.0)
            if part_i == shed_idx:
                if h_out < 0.5:                           # open side: roof on columns every ~5 m
                    k = max(1, int(math.ceil(length / 5.0)))
                    for j in range(k + 1):
                        t = j / k
                        shed_columns.append((p[0] + dx * t + inward[0] * 0.25, p[1] + dy * t + inward[1] * 0.25, h))
                continue
            if out_in_shed:
                h_out = 0.0                               # the shed is outside: full-height wall from the ground
            if h - h_out < 0.5:
                continue                                  # internal edge between equal-height parts
            edges.append({"p": p, "q": q, "inward": inward, "len": length, "h": h, "h_out": h_out, "mid": mid, "faces_shed": out_in_shed})

    # Main entrance: long ground-level edge whose outward normal points most at the street.
    ground_edges = [e for e in edges if e["h_out"] < 0.5 and e["len"] >= 6]
    # Confirmed by the owner: the main entrance is on the SOUTH side. Pick the south-facing outer
    # wall (not facing the bike storage) that also faces the street/parking most.
    def street_score(e):
        out = (-e["inward"][0], -e["inward"][1])
        south = -out[1]
        street = out[0] * street_dir[0] + out[1] * street_dir[1]
        return (2.0 * south + 0.5 * street) * min(e["len"], 30)
    south_edges = [e for e in ground_edges if not e.get("faces_shed") and -(-e["inward"][1]) > 0.5]
    main_edge = max(south_edges or ground_edges, key=street_score)
    perimeter = sum(e["len"] for e in ground_edges)
    if ruin:
        ruin.keep_clear.append((main_edge["mid"][0], main_edge["mid"][1], ENTRANCE_CLEAR))
    exit_every = 38.0
    acc = 0.0
    for e in ground_edges:
        e["doors"] = []
        if e is main_edge:
            s = e["len"] / 2
            e["doors"].append((s - 1.8, s + 1.8))          # double-width main entrance
        acc += e["len"]
        if acc > exit_every and e is not main_edge and e["len"] >= 6:
            acc = 0.0
            s = e["len"] * 0.5
            e["doors"].append((s - 0.9, s + 0.9))          # fire exit / side door
    shed_walls = [e for e in ground_edges if e.get("faces_shed")]
    if shed_walls:
        sw = max(shed_walls, key=lambda e: e["len"])
        if not sw["doors"]:
            sw["doors"].append((sw["len"] / 2 - 0.9, sw["len"] / 2 + 0.9))
    print(f"exterior walls: {len(edges)} segments, ground perimeter {perimeter:.0f} m, main entrance edge {main_edge['len']:.1f} m")

    for wi, e in enumerate(edges):
        doors = e.get("doors", [])

        def openings(length, band, doors=doors, base=e["h_out"]):
            if base > 0.5:
                # Wall above a lower roof: upper-floor windows only.
                return window_pattern(length, band) if band == 1 else []
            ops = window_pattern(length, band)
            if band == 0 and doors:
                ops = [o for o in ops if all(o[1] < d0 - 0.3 or o[0] > d1 + 0.3 for d0, d1 in doors)]
                ops += [(d0, d1, 0.0, 2.4) for d0, d1 in doors]
            return ops

        z0 = e["h_out"] if e["h_out"] > 0.5 else 0.0
        bands = [b for b in bands_for(e["h"]) if b[1] > z0 + 0.1]
        wall_with_openings(L, f"ExtWall_{wi:03d}", "Measured", "Lindenborg/Measured/ExteriorWalls", e["p"], e["q"], e["inward"],
                           z0, e["h"], bands, openings, "Wall")
        for d0, d1 in doors:
            dx, dy = e["q"][0] - e["p"][0], e["q"][1] - e["p"][1]
            s = (d0 + d1) / 2 / e["len"]
            L.areas.append({"name": f"Door_{wi:03d}", "type": "door", "floor": 0,
                            "where": Frame.ue(e["p"][0] + dx * s, e["p"][1] + dy * s, 0)})

    if ruin:
        ruin.breach_walls(GROUND_TOP, STOREY_TOP)

    # Slabs: ground floor, first floor (minus stair voids, added below), roofs.
    def emit_slabs(mask, top, thick, name, layer, folder, material):
        rects, _ = decompose(mask)
        for i, (r0, c0, r1, c1) in enumerate(rects):
            u0, v0, u1, v1 = G.rect_to_b(r0, c0, r1, c1)
            L.box_b(f"{name}_{i:03d}", layer, folder, u0, v0, u1, v1, top - thick, top, material, "floor")
        return len(rects)

    n = emit_slabs(foot & ~shed, GROUND_TOP, SLAB, "GroundFloor", "Measured", "Lindenborg/Measured/Floors", "Floor")
    n += emit_slabs(shed, 0.05, 0.25, "BikeStorageFloor", "Measured", "Lindenborg/Measured/BikeStorage", "MAT_paving")
    for ci, (cx_, cy_, ch) in enumerate(shed_columns):
        L.box_local(f"BikeStorageColumn_{ci:02d}", "Measured", "Lindenborg/Measured/BikeStorage", cx_, cy_, 0.35, 0.35, 0.0, ch - ROOF_SLAB,
                    F.theta, "Concrete", "column")
    roof_hole = np.zeros_like(foot)
    floor_hole = np.zeros_like(foot)
    holes = []
    if ruin:
        pu, pv = F.to_b(*main_edge["mid"])
        roof_hole, floor_hole, holes = ruin.plan_holes(G, foot, two_storey, height, [(pu, pv, ENTRANCE_CLEAR + 6.0)])
        print(f"collapses: {[(h['kind'], round(h['w'], 1), round(h['d'], 1)) for h in holes]}")
    roof_heights = sorted(set(round(h, 2) for _, h in parts))
    nr = 0
    for h in roof_heights:
        m = foot & (np.abs(height - h) < 0.05) & ~roof_hole
        nr += emit_slabs(m, h, ROOF_SLAB, f"Roof_{int(h * 100)}", "Measured", "Lindenborg/Measured/Roofs", "Roof")
    print(f"slabs: ground {n}, roofs {nr}")

    # 3) Guessed interior --------------------------------------------------------------------
    plan_rects_2, _ = decompose(two_storey, min_cells=int(40 / CELL ** 2))
    ground_only = foot & ~two_storey & ~shed
    plan_rects_1, _ = decompose(ground_only, min_cells=int(40 / CELL ** 2))
    stair_void = np.zeros_like(foot)
    room_id = 0
    hall_rect = None
    # The main entrance's rectangle becomes the entrance hall / aula.
    mu, mv = F.to_b(*main_edge["mid"])
    mu_in, mv_in = F.to_b(main_edge["mid"][0] + main_edge["inward"][0] * 3, main_edge["mid"][1] + main_edge["inward"][1] * 3)

    def rect_contains(rect, u, v):
        u0, v0, u1, v1 = G.rect_to_b(*rect)
        return u0 <= u <= u1 and v0 <= v <= v1

    def plan(rect, floor, storey_lo, ceiling, allow_stairs):
        nonlocal room_id, hall_rect
        u0, v0, u1, v1 = G.rect_to_b(*rect)
        w_u, w_v = u1 - u0, v1 - v0
        along_u = w_u >= w_v
        long_len, short_len = (w_u, w_v) if along_u else (w_v, w_u)
        layer, folder = "Guessed", f"Lindenborg/Guessed/Floor{floor}"
        area = w_u * w_v
        has_entrance = floor == 0 and rect_contains(rect, mu_in, mv_in)
        is_hall = floor == 0 and ((has_entrance and area <= 600) or (area > 350 and short_len > 14 and not allow_stairs))
        # In a long wing, only a section around the main doors becomes the entrance hall.
        skip = None
        if has_entrance and not is_hall:
            a_e = (mu_in - u0) if along_u else (mv_in - v0)
            skip = (a_e - 8.0, a_e + 8.0)
            L.areas.append({"name": "EntranceHall", "type": "hall", "floor": 0, "area_m2": round(16 * short_len)})
        kind = "hall" if is_hall else ("double" if short_len >= 15 else ("single" if short_len >= 8 else "open"))
        L.areas.append({"name": f"{'Aula' if is_hall else 'Wing'}_{floor}_{room_id}", "type": kind, "floor": floor,
                        "rect_cm": [Frame.ue(*F.from_b(u0, v0), 0)[:2], Frame.ue(*F.from_b(u1, v1), 0)[:2]], "area_m2": round(area)})
        room_id += 1
        if is_hall and hall_rect is None:
            hall_rect = rect
        if kind in ("hall", "open"):
            if kind == "hall":
                # A few columns for cover.
                for i in range(1, int(long_len // 8)):
                    for j in (0.33, 0.67):
                        a_ = (u0 + i * 8, v0 + j * w_v) if along_u else (u0 + j * w_u, v0 + i * 8)
                        L.box_b(f"Column_{room_id}_{i}_{j}", layer, folder, a_[0] - 0.25, a_[1] - 0.25, a_[0] + 0.25, a_[1] + 0.25, storey_lo, ceiling, "Concrete", "column")
            return
        # Corridor + classrooms (~7.2 m bays, typical Dutch school grid).
        corr_w = 2.8 if kind == "double" else 2.4
        if kind == "double":
            c0 = short_len / 2 - corr_w / 2
            sides = [(0.0, c0, c0), (c0 + corr_w, short_len, c0 + corr_w)]  # (from, to, corridor-wall position)
        else:
            c0 = 0.0
            sides = [(corr_w, short_len, corr_w)]

        def B(a0, b0, a1, b1, z0, z1, nm, mat="Interior", kind_="wall"):
            # (a along long axis, b across) -> building frame
            if along_u:
                L.box_b(nm, layer, folder, u0 + a0, v0 + b0, u0 + a1, v0 + b1, z0, z1, mat, kind_)
            else:
                L.box_b(nm, layer, folder, u0 + b0, v0 + a0, u0 + b1, v0 + a1, z0, z1, mat, kind_)

        bay = 7.2
        n_rooms = max(1, int(long_len // bay))
        room_len = long_len / n_rooms
        door_w = 1.2
        for si, (b_from, b_to, wall_b) in enumerate(sides):
            # Corridor wall with a door per room.
            for k in range(n_rooms):
                a0, a1 = k * room_len, (k + 1) * room_len
                if skip and a1 > skip[0] and a0 < skip[1]:
                    continue
                d0 = a0 + 0.8
                wb0 = wall_b - INNER_T / 2
                B(a0, wb0, d0, wb0 + INNER_T, storey_lo, ceiling, f"CorrWall_{room_id}_{si}_{k}a")
                B(d0 + door_w, wb0, a1, wb0 + INNER_T, storey_lo, ceiling, f"CorrWall_{room_id}_{si}_{k}b")
                B(d0, wb0, d0 + door_w, wb0 + INNER_T, storey_lo + 2.2, ceiling, f"CorrWall_{room_id}_{si}_{k}h")
                if k > 0:
                    B(a0 - INNER_T / 2, b_from, a0 + INNER_T / 2, b_to, storey_lo, ceiling, f"RoomWall_{room_id}_{si}_{k}")
                L.areas.append({"name": f"Classroom_{floor}_{room_id}_{si}_{k}", "type": "classroom", "floor": floor, "area_m2": round(room_len * (b_to - b_from))})
            # Furniture-height cover in rooms (desks rows) - helps fights feel like a school.
            for k in range(n_rooms):
                a0 = k * room_len
                if skip and a0 + room_len > skip[0] and a0 < skip[1]:
                    continue
                for row in range(2):
                    bb = b_from + (b_to - b_from) * (0.35 + 0.3 * row)
                    B(a0 + 1.5, bb - 0.35, a0 + room_len - 1.5, bb + 0.35, storey_lo, storey_lo + 0.75, f"Desks_{room_id}_{si}_{k}_{row}", "Furniture", "prop")
        # Stairs at the corridor ends of first-floor wings.
        if allow_stairs and long_len >= 20:
            ends = [0.6] if long_len < 45 else [0.6, long_len - 6.6]
            for si_, a_start in enumerate(ends):
                upward = a_start < long_len / 2
                b0 = c0 + corr_w - 1.6 if kind == "double" else 0.2
                b1 = b0 + 1.6
                steps = 20
                rise = (STOREY_TOP - GROUND_TOP) / steps
                run = 6.0 / steps
                for s in range(steps):
                    a_s = a_start + (s * run if upward else 6.0 - (s + 1) * run)
                    B(a_s, b0, a_s + run, b1, GROUND_TOP, GROUND_TOP + (s + 1) * rise, f"Stair_{room_id}_{si_}_{s:02d}", "Stairs", "stair")
                # Void in the first floor above the stair + a railing on the open side.
                vu0, vv0, vu1, vv1 = (u0 + a_start, v0 + b0, u0 + a_start + 6.0, v0 + b1) if along_u else (u0 + b0, v0 + a_start, u0 + b1, v0 + a_start + 6.0)
                c_lo, r_lo = int((vu0 - G.umin) / CELL), int((vv0 - G.vmin) / CELL)
                c_hi, r_hi = int(math.ceil((vu1 - G.umin) / CELL)), int(math.ceil((vv1 - G.vmin) / CELL))
                stair_void[r_lo:r_hi, c_lo:c_hi] = True
                rail_b = b0 - 0.05 if kind == "double" else b1
                B(a_start, rail_b, a_start + 6.0, rail_b + 0.05, STOREY_TOP, STOREY_TOP + 1.0, f"Railing_{room_id}_{si_}", "Interior", "railing")
                L.areas.append({"name": f"Stair_{room_id}_{si_}", "type": "stair", "floor": 0})

    for rect in plan_rects_2:
        plan(rect, 0, GROUND_TOP, STOREY_TOP - SLAB, True)
        r0, c0, r1, c1 = rect
        roof_h = float(np.nanmax(height[r0:r1 + 1, c0:c1 + 1]))
        plan(rect, 1, STOREY_TOP, roof_h - ROOF_SLAB, False)
    rack_rects, _ = decompose(shed, min_cells=int(12 / CELL ** 2))
    for ri, rect in enumerate(rack_rects):
        u0, v0, u1, v1 = G.rect_to_b(*rect)
        along_u = (u1 - u0) >= (v1 - v0)
        long_len, short_len = (u1 - u0, v1 - v0) if along_u else (v1 - v0, u1 - u0)
        if long_len < 6.0:
            continue
        rows = int((short_len - 1.2) // 2.6)
        for k in range(rows):
            b = 1.3 + k * 2.6
            if along_u:
                L.box_b(f"BikeRack_{ri}_{k}", "Guessed", "Lindenborg/Guessed/BikeStorage", u0 + 1.0, v0 + b - 0.25, u1 - 1.0, v0 + b + 0.25, 0.05, 0.95, "Bikes", "prop")
            else:
                L.box_b(f"BikeRack_{ri}_{k}", "Guessed", "Lindenborg/Guessed/BikeStorage", u0 + b - 0.25, v0 + 1.0, u0 + b + 0.25, v1 - 1.0, 0.05, 0.95, "Bikes", "prop")
    if shed.any():
        L.areas.append({"name": "BikeStorage", "type": "bike_storage", "floor": 0, "area_m2": round(float(shed.sum()) * CELL * CELL)})

    for rect in plan_rects_1:
        r0, c0, r1, c1 = rect
        roof_h = float(np.nanmax(height[r0:r1 + 1, c0:c1 + 1]))
        plan(rect, 0, GROUND_TOP, roof_h - ROOF_SLAB, False)

    nf = emit_slabs(two_storey & ~stair_void & ~floor_hole, STOREY_TOP, SLAB, "FirstFloor", "Guessed", "Lindenborg/Guessed/FirstFloorSlab", "Floor")
    if ruin:
        ruin.dress_holes(holes, GROUND_TOP, STOREY_TOP, ROOF_SLAB)
        ruin.wreck_interior()
        ruin.board_windows()
        ruin.scatter_debris(G, foot, two_storey & ~stair_void & ~floor_hole, GROUND_TOP, STOREY_TOP)
    print(f"interior: {len(plan_rects_2)} two-storey wings, {len(plan_rects_1)} single-storey areas, first floor slab {nf} boxes, hall {hall_rect is not None}")

    # 4) Context buildings (Measured, LoD1 blocks) -------------------------------------------
    for b in neighbours:
        ring = [F.to_local(*p) for p in b["footprint"]]
        if not ring or min(math.hypot(*p) for p in ring) > CONTEXT_RADIUS:
            continue
        h = float(b["attrs"].get("b3_h_dak_70p") or b["attrs"].get("b3_h_dak_50p") or (ground_nap + 6)) - ground_nap
        base = float(b["attrs"].get("b3_h_maaiveld") or ground_nap) - ground_nap
        ang = math.radians(dominant_angle([ring]))
        fb = Frame(0, 0, 0, math.degrees(ang))
        rb = [fb.to_b(*p) for p in ring]
        us_, vs_ = [p[0] for p in rb], [p[1] for p in rb]
        g = Grid(min(us_), min(vs_), max(us_), max(vs_), 0.5)
        if g.rows * g.cols > 400000:
            continue
        m = g.mask([rb])
        rects, rest = decompose(m, min_cells=8, max_rects=12)
        bid = b["id"].split(".")[-1]
        for i, (r0, c0, r1, c1) in enumerate(rects):
            u0, v0, u1, v1 = g.rect_to_b(r0, c0, r1, c1)
            x, y = fb.from_b((u0 + u1) / 2, (v0 + v1) / 2)
            L.box_local(f"Bldg_{bid}_{i}", "Context", "Lindenborg/Context/Buildings", x, y, u1 - u0, v1 - v0, min(base, 0.0) - 0.2, base + max(h, 2.5), ang, "Context")

    # 5) Terrain (AHN DTM) + BGT surfaces ------------------------------------------------------
    half = TERRAIN_HALF
    bbox_t = (cx - half, cy - half, cx + half, cy + half)
    dtm = fetch_ahn(bbox_t, offline)                 # 0.5 m, row 0 = north
    k = int(TERRAIN_CELL / 0.5)
    n_cells = int(2 * half / TERRAIN_CELL)
    dtm = dtm[: n_cells * k, : n_cells * k].reshape(n_cells, k, n_cells, k)
    import warnings
    with np.errstate(all="ignore"), warnings.catch_warnings():
        warnings.simplefilter("ignore", RuntimeWarning)
        z = np.nanmedian(dtm, axis=(1, 3)) - ground_nap
    # Fill holes (under buildings) by repeated neighbour averaging.
    for _ in range(200):
        nanm = np.isnan(z)
        if not nanm.any():
            break
        pad = np.pad(z, 1, constant_values=np.nan)
        neigh = np.stack([pad[:-2, 1:-1], pad[2:, 1:-1], pad[1:-1, :-2], pad[1:-1, 2:]])
        with np.errstate(all="ignore"), warnings.catch_warnings():
            warnings.simplefilter("ignore", RuntimeWarning)
            fill = np.nanmean(neigh, axis=0)
        z[nanm] = fill[nanm]
    z = np.nan_to_num(z, nan=0.0)
    # Keep the terrain just under the ground floor inside the school footprint.
    print(f"terrain: {n_cells}x{n_cells} cells @ {TERRAIN_CELL} m, z {z.min():.2f}..{z.max():.2f} m rel. school ground")

    # Surface classes from BGT on a 1 m raster (local frame, row 0 = north).
    classes = {"grass": 0, "road": 1, "paving": 2, "water": 3, "parking": 4}
    res = 1.0
    size = int(2 * half / res)
    cls_im = Image.new("L", (size, size), classes["grass"])
    d = ImageDraw.Draw(cls_im)

    def to_px(e, n_):
        lx, ly = F.to_local(e, n_)
        return ((lx + half) / res, (half - ly) / res)

    def draw_layer(feats, pick):
        for f in feats:
            geom = f.get("geometry") or {}
            polys = [geom["coordinates"]] if geom.get("type") == "Polygon" else (geom.get("coordinates", []) if geom.get("type") == "MultiPolygon" else [])
            c = pick(f["properties"])
            if c is None:
                continue
            for poly in polys:
                if poly and len(poly[0]) >= 3:
                    d.polygon([to_px(*q[:2]) for q in poly[0]], fill=c)

    bb = (cx - half, cy - half, cx + half, cy + half)
    draw_layer(fetch_bgt("begroeidterreindeel", bb, offline), lambda p: classes["grass"])
    draw_layer(fetch_bgt("onbegroeidterreindeel", bb, offline), lambda p: classes["paving"])
    draw_layer(fetch_bgt("ondersteunendwegdeel", bb, offline), lambda p: classes["grass"])
    road_feats = fetch_bgt("wegdeel", bb, offline)
    draw_layer(road_feats, lambda p: classes["road"] if p.get("functie", "").startswith("rijbaan") else (classes["parking"] if p.get("functie") == "parkeervlak" else classes["paving"]))
    draw_layer(fetch_bgt("waterdeel", bb, offline), lambda p: classes["water"])
    cls = np.array(cls_im)

    # Parked cars on some parking bays (Guessed props, BGT bay positions are real).
    rng = np.random.default_rng(7)
    car_i = 0
    for f in road_feats:
        p = f["properties"]
        geom = f.get("geometry") or {}
        if p.get("functie") != "parkeervlak" or geom.get("type") != "Polygon":
            continue
        ring = [F.to_local(*q[:2]) for q in geom["coordinates"][0]]
        if max(abs(q[0]) for q in ring) > 120 or max(abs(q[1]) for q in ring) > 120:
            continue
        ang = math.radians(dominant_angle([ring]))
        fb = Frame(0, 0, 0, math.degrees(ang))
        rb = [fb.to_b(*q) for q in ring]
        u0, u1 = min(q[0] for q in rb), max(q[0] for q in rb)
        v0, v1 = min(q[1] for q in rb), max(q[1] for q in rb)
        along = u1 - u0 >= v1 - v0
        length, width = (u1 - u0, v1 - v0) if along else (v1 - v0, u1 - u0)
        if width < 1.8:
            continue
        # Bays are drawn as strips; cars stand across the strip every 2.5 m (perpendicular parking).
        n_bays = int(length // 2.5)
        for i in range(n_bays):
            if rng.random() > 0.45:
                continue
            t = (i + 0.5) * 2.5
            cu, cv = ((u0 + t, (v0 + v1) / 2) if along else ((u0 + u1) / 2, v0 + t))
            x, y = fb.from_b(cu, cv)
            zt = float(z[min(n_cells - 1, int((half - y) / TERRAIN_CELL)), min(n_cells - 1, int((x + half) / TERRAIN_CELL))])
            car_ang = ang + (math.pi / 2 if along else 0.0)
            L.box_local(f"Car_{car_i:03d}", "Guessed", "Lindenborg/Guessed/Props", x, y, min(4.4, width * 0.9), 1.8, zt, zt + 1.0, car_ang, "Car", "prop")
            L.box_local(f"CarTop_{car_i:03d}", "Guessed", "Lindenborg/Guessed/Props", x, y, 2.2, 1.6, zt + 1.0, zt + 1.45, car_ang, "Car", "prop")
            car_i += 1

    # Bike sheds by the main entrance (every Dutch school has them) - Guessed.
    out_n = (-main_edge["inward"][0], -main_edge["inward"][1])
    tan = (main_edge["q"][0] - main_edge["p"][0], main_edge["q"][1] - main_edge["p"][1])
    tl = math.hypot(*tan)
    tan = (tan[0] / tl, tan[1] / tl)
    ang_edge = math.atan2(tan[1], tan[0])
    fp_local_poly = [F.to_local(*p) for p in fp]

    def inside_poly(x, y, poly):
        c = False
        for i in range(len(poly)):
            (x1, y1), (x2, y2) = poly[i], poly[(i + 1) % len(poly)]
            if (y1 > y) != (y2 > y) and x < (x2 - x1) * (y - y1) / (y2 - y1) + x1:
                c = not c
        return c

    def clear_of_school(cx_, cy_, half_len, half_w, ang_):
        ca, sa = math.cos(ang_), math.sin(ang_)
        for du in (-half_len, 0, half_len):
            for dv in (-half_w - 2, 0, half_w + 2):
                if inside_poly(cx_ + du * ca - dv * sa, cy_ + du * sa + dv * ca, fp_local_poly):
                    return False
        return True

    # Write terrain OBJ (UE axes, cm). One material group per surface class.
    names = {v: k_ for k_, v in classes.items()}
    lines = ["# AHN4 DTM terrain around Lindenborg, Leek (2 m grid). Materials from BGT.", "mtllib terrain.mtl"]
    for r in range(n_cells + 1):
        for c in range(n_cells + 1):
            zr = z[min(r, n_cells - 1), min(c, n_cells - 1)]
            x = -half + c * TERRAIN_CELL
            y = half - r * TERRAIN_CELL
            lines.append("v {:.1f} {:.1f} {:.1f}".format(*Frame.ue(x, y, zr - 0.02)))
    faces = {k_: [] for k_ in classes}
    for r in range(n_cells):
        for c in range(n_cells):
            x = -half + (c + 0.5) * TERRAIN_CELL
            y = half - (r + 0.5) * TERRAIN_CELL
            px, py = int((x + half) / res), int((half - y) / res)
            k_ = names[int(cls[min(size - 1, py), min(size - 1, px)])]
            i0 = r * (n_cells + 1) + c + 1
            i1, i2, i3 = i0 + 1, i0 + n_cells + 1, i0 + n_cells + 2
            # UE is left-handed: wind so faces point up after the Y flip.
            faces[k_].append(f"f {i0} {i2} {i1}")
            faces[k_].append(f"f {i1} {i2} {i3}")
    for k_, fl in faces.items():
        if fl:
            lines.append(f"usemtl MAT_{k_}")
            lines.extend(fl)
    (OUT / "terrain.obj").write_text("\n".join(lines) + "\n")
    colors = {"grass": (0.18, 0.24, 0.12), "road": (0.09, 0.09, 0.09), "paving": (0.32, 0.3, 0.28), "water": (0.05, 0.08, 0.1), "parking": (0.2, 0.2, 0.2)}
    (OUT / "terrain.mtl").write_text("".join(f"newmtl MAT_{k_}\nKd {c[0]} {c[1]} {c[2]}\n\n" for k_, c in colors.items()))

    if ruin:
        def z_at(x, y):
            r_ = min(n_cells - 1, max(0, int((half - y) / TERRAIN_CELL)))
            c_ = min(n_cells - 1, max(0, int((x + half) / TERRAIN_CELL)))
            return float(z[r_, c_])

        # Where outdoor props may go: not in water, not inside neighbouring buildings.
        ctx_im = Image.new("L", (size, size), 0)
        cd = ImageDraw.Draw(ctx_im)
        for bx in L.boxes:
            if bx["layer"] != "Context":
                continue
            cx_, cy_ = bx["center"][0] / 100, -bx["center"][1] / 100
            l_, w_ = bx["size"][0] / 200 + 1.0, bx["size"][1] / 200 + 1.0
            a_ = math.radians(-bx["yaw"])
            pts = [(cx_ + dx * math.cos(a_) - dy * math.sin(a_), cy_ + dx * math.sin(a_) + dy * math.cos(a_)) for dx, dy in ((-l_, -w_), (l_, -w_), (l_, w_), (-l_, w_))]
            cd.polygon([((px_ + half) / res, (half - py_) / res) for px_, py_ in pts], fill=1)
        ctx_block = np.array(ctx_im, dtype=bool) | (cls == classes["water"])

        def free_at(x, y, clearance):
            px, py = int((x + half) / res), int((half - y) / res)
            k_ = int(math.ceil(clearance / res))
            if not (k_ <= px < size - k_ and k_ <= py < size - k_):
                return False
            return not ctx_block[py - k_:py + k_ + 1, px - k_:px + k_ + 1].any()

        def near_school(x, y, margin):
            if inside_poly(x, y, fp_local_poly):
                return True
            for i_ in range(len(fp_local_poly)):
                (x1, y1), (x2, y2) = fp_local_poly[i_], fp_local_poly[(i_ + 1) % len(fp_local_poly)]
                dx, dy = x2 - x1, y2 - y1
                t_ = max(0.0, min(1.0, ((x - x1) * dx + (y - y1) * dy) / max(1e-9, dx * dx + dy * dy)))
                if math.hypot(x - (x1 + t_ * dx), y - (y1 + t_ * dy)) < margin:
                    return True
            return False

        ruin.ruin_context(z_at)
        ruin.outside(z_at, free_at, near_school, main_edge["mid"], out_n)
        print(f"destruction: {ruin.summary()}")

    # 6) Gameplay: spawn points, buy stations, player start, nav bounds -----------------------
    bldg_mask_local = Image.new("L", (size, size), 0)
    dm = ImageDraw.Draw(bldg_mask_local)
    for bx in L.boxes:
        solid_ruin = bx["layer"] == "Destruction" and bx.get("collision", True) and bx["kind"] in ("cover", "prop", "rubble")
        if bx["layer"] == "Context" or bx["kind"] in ("wall",) or solid_ruin:
            cx_, cy_ = bx["center"][0] / 100, -bx["center"][1] / 100
            r_ = max(bx["size"][0], bx["size"][1]) / 200 + 1.0
            dm.ellipse([((cx_ - r_ + half) / res, (half - cy_ - r_) / res), ((cx_ + r_ + half) / res, (half - cy_ + r_) / res)], fill=1)
    dm.polygon([to_px(*p) for p in fp], fill=1)
    blocked = np.array(bldg_mask_local, dtype=bool) | (cls == classes["water"])
    spawn_i = 0
    for radius in (70.0, 95.0, 120.0):
        for k_ in range(28):
            a_ = 2 * math.pi * (k_ + (0.5 if radius == 95.0 else 0)) / 28
            x, y = radius * math.cos(a_) * 1.15, radius * math.sin(a_) * 0.95
            px, py = int((x + half) / res), int((half - y) / res)
            if not (0 <= px < size and 0 <= py < size) or blocked[max(0, py - 3):py + 4, max(0, px - 3):px + 4].any():
                continue
            zt = float(z[int((half - y) / TERRAIN_CELL), int((x + half) / TERRAIN_CELL)])
            L.spawns.append({"name": f"Spawn_{spawn_i:02d}", "kind": "Ground", "min_wave": 1 if radius < 120 else 3, "location": Frame.ue(x, y, zt + 0.1),
                             "yaw": round(-math.degrees(math.atan2(-y, -x)), 1)})
            spawn_i += 1
    for k_, (x, y) in enumerate([(-150, -150), (150, -150), (150, 150), (-150, 150)]):
        L.spawns.append({"name": f"AirSpawn_{k_}", "kind": "Air", "min_wave": 1, "location": Frame.ue(x, y, 45.0), "yaw": 0.0})
    # Indoor spawns at far corridor ends (from wave 4: the fight moves inside).
    for i, rect in enumerate(plan_rects_2[:4]):
        u0, v0, u1, v1 = G.rect_to_b(*rect)
        for j, (u_, v_) in enumerate([(u0 + 1.5, (v0 + v1) / 2), (u1 - 1.5, (v0 + v1) / 2)] if (u1 - u0) >= (v1 - v0) else [((u0 + u1) / 2, v0 + 1.5), ((u0 + u1) / 2, v1 - 1.5)]):
            x, y = F.from_b(u_, v_)
            L.spawns.append({"name": f"IndoorSpawn_{i}_{j}", "kind": "Ground", "min_wave": 4, "location": Frame.ue(x, y, GROUND_TOP + 0.05), "yaw": 0.0})

    inside = (main_edge["mid"][0] + main_edge["inward"][0] * 6, main_edge["mid"][1] + main_edge["inward"][1] * 6)
    face_in = math.atan2(main_edge["inward"][1], main_edge["inward"][0])
    L.player_start = {"location": Frame.ue(inside[0], inside[1], GROUND_TOP + 1.0), "yaw": round(-math.degrees(face_in), 1)}
    # Weapons + equipment in the entrance hall, air support outside on the forecourt.
    for cat, off_in, off_t in (("Weapons", 9.0, -6.0), ("Equipment", 9.0, 6.0), ("AirSupport", -9.0, 0.0)):
        x = main_edge["mid"][0] + main_edge["inward"][0] * off_in + tan[0] * off_t
        y = main_edge["mid"][1] + main_edge["inward"][1] * off_in + tan[1] * off_t
        zt = GROUND_TOP if off_in > 0 else float(z[int((half - y) / TERRAIN_CELL), int((x + half) / TERRAIN_CELL)])
        L.stations.append({"category": cat, "location": Frame.ue(x, y, zt), "yaw": round(-math.degrees(math.atan2(-main_edge["inward"][1] * math.copysign(1, off_in), -main_edge["inward"][0] * math.copysign(1, off_in))), 1)})

    nav_half = (max(us) - min(us)) / 2 + 100, (max(vs) - min(vs)) / 2 + 100
    L.nav = {"center": Frame.ue(0, 0, 5), "size_cm": [nav_half[0] * 200 + 2000, nav_half[1] * 200 + 2000, 3000], "yaw": F.yaw_ue(F.theta)}

    layout = {
        "name": "Lindenborg (rsg de Borgen), Waezenburglaan 55, Leek",
        "origin": {"rd_x": round(cx, 3), "rd_y": round(cy, 3), "nap_ground_m": ground_nap, "building_axis_deg": round(theta, 3)},
        "units": "cm, X=east, Y=south, Z=up",
        "storeys": {"ground_floor_top_m": GROUND_TOP, "first_floor_top_m": STOREY_TOP, "note": "first floor level is a guess"},
        "boxes": L.boxes,
        "areas": L.areas,
        "spawn_points": L.spawns,
        "buy_stations": L.stations,
        "player_start": L.player_start,
        "nav_bounds": L.nav,
        "terrain": {"obj": "terrain.obj", "half_size_m": half, "cell_m": TERRAIN_CELL},
        "destruction": ruin.summary() if ruin else {"intact": True},
        "look_row": "Default" if intact else "Abandoned",
    }
    (OUT / "lindenborg_layout.json").write_text(json.dumps(layout, indent=1))
    counts = {}
    for bx in L.boxes:
        counts[bx["layer"]] = counts.get(bx["layer"], 0) + 1
    print(f"boxes per layer: {counts}; spawns {len(L.spawns)}; stations {len(L.stations)}")

    render_previews(L, F, G, fp, cls, half, res)


def render_previews(L: Layout, F: Frame, G: Grid, fp, cls, half, res):
    """Top-down plans so a human (and CI) can eyeball the guess."""
    S = 6  # px per metre
    span = 150.0
    W = H = int(2 * span * S)
    pal = {0: (190, 205, 170), 1: (80, 80, 80), 2: (205, 200, 190), 3: (120, 160, 200), 4: (130, 130, 130)}
    for floor, zlo, zhi in ((0, -0.5, 3.3), (1, 3.4, 7.0)):
        im = Image.new("RGB", (W, H), (240, 240, 236))
        d = ImageDraw.Draw(im)
        # BGT surfaces.
        for py in range(0, cls.shape[0], 2):
            for px in range(0, cls.shape[1], 2):
                x, y = -half + px * res, half - py * res
                if abs(x) < span and abs(y) < span:
                    X, Y = (x + span) * S, (span - y) * S
                    d.rectangle([X, Y, X + 2 * res * S, Y + 2 * res * S], fill=pal.get(int(cls[py, px]), (200, 200, 200)))

        def P(x, y):
            return ((x + span) * S, (span - y) * S)

        for g in range(-int(span), int(span) + 1, 10):
            d.line([P(g, -span), P(g, span)], fill=(205, 205, 200), width=1)
            d.line([P(-span, g), P(span, g)], fill=(205, 205, 200), width=1)

        colors = {"Measured": (20, 20, 20), "Guessed": (200, 40, 30), "Context": (110, 110, 120), "Destruction": (105, 80, 60)}
        for bx in sorted(L.boxes, key=lambda b: b["kind"] != "floor"):
            z0 = (bx["center"][2] - bx["size"][2] / 2) / 100
            z1 = (bx["center"][2] + bx["size"][2] / 2) / 100
            if bx["layer"] != "Context" and not (z1 > zlo + 0.3 and z0 < zhi):
                continue
            if bx["kind"] == "floor" and bx["layer"] != "Context":
                if not (zlo < z1 < zhi):
                    continue
            cx_, cy_ = bx["center"][0] / 100, -bx["center"][1] / 100
            l_, w_ = bx["size"][0] / 200, bx["size"][1] / 200
            a_ = math.radians(-bx["yaw"])
            pts = [(cx_ + dx * math.cos(a_) - dy * math.sin(a_), cy_ + dx * math.sin(a_) + dy * math.cos(a_)) for dx, dy in ((-l_, -w_), (l_, -w_), (l_, w_), (-l_, w_))]
            if bx["kind"] == "floor":
                fill = (225, 225, 215) if bx["layer"] == "Measured" else (235, 215, 210)
            elif bx["kind"] == "stair":
                fill = (60, 90, 200)
            elif bx["kind"] == "prop":
                fill = (170, 120, 60)
            elif bx["kind"] in ("rubble", "debris"):
                fill = (105, 80, 60)
            elif bx["kind"] == "foliage":
                fill = (70, 120, 55)
            elif bx["kind"] == "decal":
                fill = (45, 42, 40)
            elif bx["kind"] == "cover":
                fill = (150, 135, 95)
            else:
                fill = colors[bx["layer"]]
            d.polygon([P(*p) for p in pts], fill=fill)
        for sp in L.spawns:
            x, y = sp["location"][0] / 100, -sp["location"][1] / 100
            col = (20, 160, 40) if sp["kind"] == "Ground" else (20, 120, 200)
            d.ellipse([P(x - 1.2, y + 1.2), P(x + 1.2, y - 1.2)], fill=col)
        for st in L.stations:
            x, y = st["location"][0] / 100, -st["location"][1] / 100
            d.rectangle([P(x - 1.5, y + 1.5), P(x + 1.5, y - 1.5)], fill=(255, 150, 0))
        ps = L.player_start["location"]
        d.polygon([P(ps[0] / 100, -ps[1] / 100 + 2), P(ps[0] / 100 - 1.5, -ps[1] / 100 - 1.5), P(ps[0] / 100 + 1.5, -ps[1] / 100 - 1.5)], fill=(0, 200, 255))
        d.rectangle([10, 10, 560, 120], fill=(255, 255, 255))
        d.text((20, 18), f"Lindenborg, Leek - {'ground' if floor == 0 else 'first'} floor (north up, 10 m grid)", fill=(0, 0, 0))
        d.text((20, 40), "black = measured shell (3D BAG)   red = GUESSED interior   blue = stairs", fill=(0, 0, 0))
        d.text((20, 60), "green dots = spawn points   orange = buy stations   cyan = player start", fill=(0, 0, 0))
        d.text((20, 80), "grey blocks = neighbouring buildings (3D BAG)   ground colours = BGT", fill=(0, 0, 0))
        d.text((20, 100), "brown = rubble / debris / sandbags (Destruction layer)   green = overgrowth", fill=(0, 0, 0))
        im.save(DOCS / f"lindenborg_plan_{'ground' if floor == 0 else 'first'}.png")
    print("previews written to Docs/")


if __name__ == "__main__":
    main()
