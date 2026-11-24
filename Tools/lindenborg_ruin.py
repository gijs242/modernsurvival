"""Abandoned / war-damaged dressing for the Lindenborg map.

Used by Tools/build_lindenborg.py (skip it with --intact). Everything is seeded, so the same
damage comes out every run; change RUIN_SEED for a different layout, or the numbers in
RuinSettings to make it more or less wrecked.

Added geometry goes to the "Destruction" data layer. Pieces of the measured shell that are
"destroyed" (roof holes, wall breaches) are simply not emitted; --intact gives the clean building.
Gameplay rules kept by this pass:
  * nothing is placed within ENTRANCE_CLEAR m of the main entrance or the buy stations,
  * doors are never breached or blocked, corridors only get low (< 0.3 m) debris,
  * bushes and tall grass have no collision: they hide you but don't stop bullets.
"""
from __future__ import annotations

import math
from dataclasses import dataclass

import numpy as np

RUIN_SEED = 1985          # the building's construction year
ENTRANCE_CLEAR = 14.0     # m


@dataclass
class RuinSettings:
    roof_holes_two_storey: int = 2       # roof only: rubble lands on the first floor
    holes_through_both: int = 1          # roof + first floor gone: rubble on the ground floor
    roof_holes_single: int = 1           # aula / single-storey roof
    wall_breaches: int = 7
    room_wall_removed: float = 0.35      # share of classroom partition walls knocked down
    corridor_wall_holes: float = 0.08    # share of corridor wall pieces blown out
    desks_scattered: float = 0.7         # rest of the desk rows are gone
    boarded_windows: float = 0.3         # ground-floor windows boarded up
    floor_debris: int = 220
    ceiling_panels: int = 60
    sandbag_nests: int = 7
    containers: int = 4
    barrels: int = 26
    tyres: int = 18
    bushes: int = 140
    grass_patches: int = 90
    scorch_marks: int = 10
    ruined_houses: float = 0.15


LAYER = "Destruction"


def to_local(bx):
    return bx["center"][0] / 100.0, -bx["center"][1] / 100.0


def z_range(bx):
    return (bx["center"][2] - bx["size"][2] / 2) / 100.0, (bx["center"][2] + bx["size"][2] / 2) / 100.0


class Ruin:
    def __init__(self, layout, frame, settings: RuinSettings | None = None):
        self.L = layout
        self.F = frame
        self.S = settings or RuinSettings()
        self.rng = np.random.default_rng(RUIN_SEED)
        self.keep_clear = []        # (x, y, radius) in local metres
        self.removed = 0
        self.added_before = len(layout.boxes)

    # ------------------------------------------------------------------------------ helpers

    def clear(self, x, y, extra=0.0):
        return all(math.hypot(x - cx, y - cy) > r + extra for cx, cy, r in self.keep_clear)

    def add(self, name, folder, x, y, length, width, z0, z1, angle, material, kind="rubble", **kw):
        self.L.box_local(name, LAYER, "Lindenborg/Destruction/" + folder, x, y, length, width, z0, z1, angle, material, kind, **kw)

    def rubble_pile(self, name, folder, x, y, z0, radius, peak, n, chunks_material="Rubble"):
        """A mound of tilted chunks; a flat base piece keeps it walkable for the navmesh."""
        r = self.rng
        self.add(f"{name}_base", folder, x, y, radius * 1.5, radius * 1.3, z0 - 0.05, z0 + min(0.25, peak * 0.3),
                 r.uniform(0, math.pi), "Rubble", "rubble", roll=float(r.uniform(-3, 3)))
        for i in range(n):
            d = min(radius, abs(r.normal(0.0, radius * 0.45)))
            a = r.uniform(0, 2 * math.pi)
            px, py = x + d * math.cos(a), y + d * math.sin(a)
            size = r.uniform(0.35, 1.5) * (1.15 - 0.6 * d / radius)
            h = max(0.15, peak * (1.0 - d / radius) * r.uniform(0.6, 1.1))
            thick = r.uniform(0.2, 0.55) * max(0.5, size)
            self.add(f"{name}_{i:02d}", folder, px, py, size, size * r.uniform(0.45, 1.0), max(z0 - 0.1, z0 + h - thick), z0 + h,
                     r.uniform(0, math.pi), chunks_material, "rubble", pitch=float(r.uniform(-28, 28)), roll=float(r.uniform(-28, 28)))

    # ------------------------------------------------------------------------------ 1) holes in roofs / floors

    def plan_holes(self, G, foot, two_storey, height, protect_b):
        """Picks collapse areas (building-frame cell rects). Returns (roof_hole_mask, floor_hole_mask, holes)."""
        r = self.rng
        roof_hole = np.zeros_like(foot)
        floor_hole = np.zeros_like(foot)
        holes = []

        def erode(m, cells):
            out = m.copy()
            for _ in range(cells):
                e = out.copy()
                e[1:, :] &= out[:-1, :]
                e[:-1, :] &= out[1:, :]
                e[:, 1:] &= out[:, :-1]
                e[:, :-1] &= out[:, 1:]
                out = e
            return out

        cell = G.cell
        single = foot & ~two_storey
        plan = ([("roof", two_storey)] * self.S.roof_holes_two_storey + [("through", two_storey)] * self.S.holes_through_both
                + [("roof_single", single)] * self.S.roof_holes_single)
        for kind, region in plan:
            candidates = np.argwhere(erode(region, int(5.0 / cell)) & ~roof_hole)
            r.shuffle(candidates)
            for rr, cc in candidates[:400]:
                u, v = G.cell_center(rr, cc)
                if any(math.hypot(u - pu, v - pv) < pr for pu, pv, pr in protect_b):
                    continue
                if any(math.hypot(u - hu, v - hv) < 18.0 for hu, hv, _ in [(h["u"], h["v"], 0) for h in holes]):
                    continue
                hw, hd = r.uniform(5.0, 8.5), r.uniform(4.0, 6.5)
                c0, c1 = int(cc - hw / 2 / cell), int(cc + hw / 2 / cell)
                r0, r1 = int(rr - hd / 2 / cell), int(rr + hd / 2 / cell)
                rect = np.zeros_like(foot)
                rect[max(0, r0):r1, max(0, c0):c1] = True
                rect &= region
                # Ragged edge: nibble random cells off the rectangle border.
                border = rect & ~erode(rect, 2)
                rect[border & (r.random(rect.shape) < 0.45)] = False
                roof_hole |= rect
                if kind == "through":
                    floor_hole |= erode(rect, 1)
                roof_h = float(np.nanmax(np.where(rect, height, np.nan)))
                holes.append({"kind": kind, "u": u, "v": v, "w": hw, "d": hd, "roof_h": roof_h})
                break
        return roof_hole, floor_hole, holes

    def dress_holes(self, holes, ground_top, first_top, roof_slab):
        r = self.rng
        for i, h in enumerate(holes):
            x, y = self.F.from_b(h["u"], h["v"])
            if h["kind"] == "roof":
                base, peak, n = first_top, 1.0, 22
            elif h["kind"] == "through":
                base, peak, n = ground_top, 1.9, 40
            else:
                base, peak, n = ground_top, 1.2, 28
            radius = min(h["w"], h["d"]) * 0.55
            self.rubble_pile(f"Collapse_{i}", "Collapses", x, y, base, radius, peak, n)
            # Big roof slabs that came down at an angle (good cover, and they read as "collapsed").
            for k in range(3 if h["kind"] != "roof" else 2):
                a = self.F.theta + r.uniform(-0.4, 0.4) + (math.pi / 2 if k % 2 else 0.0)
                off = r.uniform(-radius * 0.6, radius * 0.6)
                sx, sy = x + off * math.cos(a + math.pi / 2), y + off * math.sin(a + math.pi / 2)
                length = r.uniform(2.5, 4.2)
                tilt = r.uniform(18, 38)
                zc = base + math.sin(math.radians(tilt)) * length / 2
                self.add(f"FallenSlab_{i}_{k}", "Collapses", sx, sy, length, r.uniform(1.5, 2.8), zc - roof_slab / 2, zc + roof_slab / 2,
                         a, "Roof", "rubble", pitch=float(tilt * (1 if r.random() < 0.5 else -1)), roll=float(r.uniform(-8, 8)))
            # Hanging bits at the hole edge: twisted beams.
            for k in range(2):
                a = self.F.theta + r.uniform(-0.2, 0.2)
                self.add(f"Beam_{i}_{k}", "Collapses", x + r.uniform(-2, 2), y + r.uniform(-2, 2), r.uniform(3, 5), 0.25,
                         h["roof_h"] - 1.6, h["roof_h"] - 1.35, a, "Rust", "rubble", pitch=float(r.uniform(15, 35)), roll=float(r.uniform(-10, 10)))

    # ------------------------------------------------------------------------------ 2) wall breaches

    def breach_walls(self, ground_top, storey_top):
        r = self.rng
        boxes = self.L.boxes
        doors = [(a["where"][0] / 100.0, -a["where"][1] / 100.0) for a in self.L.areas if a["type"] == "door"]
        candidates = []
        for bx in boxes:
            if not bx["name"].startswith("ExtWall_") or bx["kind"] != "wall":
                continue
            z0, z1 = z_range(bx)
            x, y = to_local(bx)
            if z0 > 0.5 or bx["size"][0] < 100 or not self.clear(x, y):
                continue
            if any(math.hypot(x - dx, y - dy) < 5.0 for dx, dy in doors):
                continue
            candidates.append(bx)
        r.shuffle(candidates)
        chosen, walls_used = [], set()
        for bx in candidates:
            wall_id = bx["name"].split("_")[1]
            if wall_id in walls_used:
                continue
            walls_used.add(wall_id)
            chosen.append(bx)
            if len(chosen) >= self.S.wall_breaches:
                break
        remove = set()
        for i, bx in enumerate(chosen):
            cx, cy = to_local(bx)
            wall_id = bx["name"].split("_")[1]
            for j, other in enumerate(boxes):
                if not other["name"].startswith(f"ExtWall_{wall_id}_"):
                    continue
                ox, oy = to_local(other)
                z0, z1 = z_range(other)
                d = math.hypot(ox - cx, oy - cy)
                if (z0 < storey_top - 0.1 and d < 2.2) or (d < 1.1 and r.random() < 0.5):
                    remove.add(j)
            yaw = -math.radians(bx["yaw"])
            nx, ny = -math.sin(yaw), math.cos(yaw)
            for side in (-1, 1):
                self.rubble_pile(f"Breach_{i}_{'in' if side > 0 else 'out'}", "Breaches", cx + nx * side * 1.6, cy + ny * side * 1.6,
                                 ground_top if side > 0 else 0.0, 1.6, 0.8, 10)
        self.removed += len(remove)
        self.L.boxes = [b for j, b in enumerate(boxes) if j not in remove]

    # ------------------------------------------------------------------------------ 3) interior wreckage

    def wreck_interior(self):
        r = self.rng
        keep = []
        for bx in self.L.boxes:
            name = bx["name"]
            x, y = to_local(bx)
            z0, z1 = z_range(bx)
            if name.startswith("RoomWall_") and r.random() < self.S.room_wall_removed:
                self.removed += 1
                self.rubble_pile(f"Wall{name[8:]}", "Interior", x, y, z0, 1.2, 0.5, 6)
                continue
            if name.startswith("CorrWall_") and r.random() < self.S.corridor_wall_holes and bx["size"][0] > 150:
                self.removed += 1
                continue
            if name.startswith("Desks_"):
                self.removed += 1
                if r.random() < self.S.desks_scattered:
                    yaw = -math.radians(bx["yaw"])
                    half = bx["size"][0] / 200.0
                    for k in range(3):
                        t = r.uniform(-half, half)
                        dx, dy = x + t * math.cos(yaw) + r.normal(0, 0.5), y + t * math.sin(yaw) + r.normal(0, 0.5)
                        a = yaw + r.uniform(-0.8, 0.8)
                        if r.random() < 0.35:   # tipped on its side: a 0.75 m shield
                            self.add(f"Desk{name[5:]}_{k}", "Interior", dx, dy, 1.2, 0.75, z0, z0 + 0.6, a, "Furniture", "prop", roll=90.0)
                        else:
                            self.add(f"Desk{name[5:]}_{k}", "Interior", dx, dy, 1.2, 0.6, z0, z0 + 0.75, a, "Furniture", "prop")
                continue
            keep.append(bx)
        self.L.boxes = keep

    def board_windows(self):
        r = self.rng
        for i, w in enumerate(self.L.windows):
            if w["band"] != 0 or r.random() > self.S.boarded_windows or not self.clear(w["x"], w["y"]):
                continue
            span = w["z1"] - w["z0"]
            for k in range(3):
                z = w["z0"] + span * (0.2 + 0.3 * k)
                self.add(f"Board_{i}_{k}", "Windows", w["x"], w["y"], w["width"] + 0.3, 0.04, z, z + 0.2, w["angle"], "Planks", "prop",
                         pitch=float(r.uniform(-12, 12)))

    def scatter_debris(self, G, foot, two_storey, ground_top, first_top):
        r = self.rng
        cells_g = np.argwhere(foot)
        cells_f = np.argwhere(two_storey)
        for i in range(self.S.floor_debris):
            upstairs = r.random() < 0.45
            rr, cc = (cells_f if upstairs else cells_g)[r.integers(0, len(cells_f if upstairs else cells_g))]
            x, y = self.F.from_b(*G.cell_center(rr, cc))
            if not self.clear(x, y, -6.0):
                continue
            z = first_top if upstairs else ground_top
            s = r.uniform(0.2, 0.7)
            self.add(f"Debris_{i:03d}", "Debris", x, y, s, s * r.uniform(0.4, 1.0), z, z + r.uniform(0.05, 0.25), r.uniform(0, math.pi),
                     "Debris", "debris", roll=float(r.uniform(-10, 10)))
        for i in range(self.S.ceiling_panels):
            upstairs = r.random() < 0.5
            rr, cc = (cells_f if upstairs else cells_g)[r.integers(0, len(cells_f if upstairs else cells_g))]
            x, y = self.F.from_b(*G.cell_center(rr, cc))
            z = first_top if upstairs else ground_top
            tilt = r.uniform(5, 40)
            self.add(f"CeilingPanel_{i:02d}", "Debris", x, y, 1.2, 0.6, z + 0.2, z + 0.23, r.uniform(0, math.pi), "Panel", "debris",
                     pitch=float(tilt), collision=False)

    # ------------------------------------------------------------------------------ 4) outside

    def outside(self, z_at, free_at, school_poly_test, main_mid, out_dir):
        r = self.rng
        S = self.S
        # Burnt-out cars: darker, pushed off their bays.
        jitter = {}
        for bx in self.L.boxes:
            if bx["name"].startswith(("Car_", "CarTop_")):
                idx = bx["name"].split("_")[1]
                jitter.setdefault(idx, (float(r.uniform(-25, 25)), r.random() < 0.85))
                j, burnt = jitter[idx]
                bx["yaw"] = round(bx["yaw"] + j, 2)
                if burnt:
                    bx["material"] = "BurntCar"
                bx["layer"] = LAYER
                bx["folder"] = "Lindenborg/Destruction/Vehicles"
                if bx["name"].startswith("Car_") and burnt and r.random() < 0.6:
                    x, y = to_local(bx)
                    self.add(f"Scorch_{bx['name']}", "Ground", x, y, r.uniform(4, 6), r.uniform(3, 4.5), z_at(x, y) + 0.01, z_at(x, y) + 0.03,
                             r.uniform(0, math.pi), "Scorch", "decal", collision=False)

        def spot(min_r, max_r, clearance):
            for _ in range(200):
                a = r.uniform(0, 2 * math.pi)
                d = r.uniform(min_r, max_r)
                x, y = d * math.cos(a), d * math.sin(a)
                if free_at(x, y, clearance) and self.clear(x, y, clearance) and not school_poly_test(x, y, clearance):
                    return x, y
            return None

        # Abandoned defensive positions: U-shaped sandbag walls facing the school.
        for i in range(S.sandbag_nests):
            p = spot(25, 70, 3.0)
            if not p:
                continue
            x, y = p
            face = math.atan2(-y, -x)
            z = z_at(x, y)
            walls = [(0.0, 0.0, 3.2), (-1.4, 1.5, 1.8), (-1.4, -1.5, 1.8)]   # (back offset, side offset, length)
            for k, (bo, so, length) in enumerate(walls):
                wx = x + bo * math.cos(face) - so * math.sin(face)
                wy = y + bo * math.sin(face) + so * math.cos(face)
                wa = face + (math.pi / 2 if k == 0 else 0.0)
                for row in range(3):
                    shrink = 0.06 * row
                    self.add(f"Sandbags_{i}_{k}_{row}", "Outside", wx, wy, length - shrink, 0.55 - shrink, z + row * 0.3, z + row * 0.3 + 0.3,
                             wa + r.uniform(-0.04, 0.04), "Sandbag", "cover")
        for i in range(S.containers):
            p = spot(20, 90, 5.0)
            if not p:
                continue
            x, y = p
            z = z_at(x, y)
            a = r.uniform(0, math.pi)
            self.add(f"Container_{i}", "Outside", x, y, 6.06, 2.44, z, z + 2.59, a, "Container", "cover", roll=float(r.choice([0.0, 0.0, 6.0])))
            if i == 0:   # one stacked crooked on top
                self.add(f"Container_{i}_top", "Outside", x + 0.4, y - 0.2, 6.06, 2.44, z + 2.6, z + 5.19, a + 0.15, "Rust", "cover")
        for i in range(S.barrels):
            p = spot(8, 95, 0.8)
            if not p:
                continue
            x, y = p
            z = z_at(x, y)
            if r.random() < 0.3:
                self.add(f"Barrel_{i}", "Outside", x, y, 0.58, 0.58, z, z + 0.88, r.uniform(0, math.pi), "Rust", "prop", roll=90.0, shape="Cylinder")
            else:
                self.add(f"Barrel_{i}", "Outside", x, y, 0.58, 0.58, z, z + 0.88, 0.0, "Rust", "prop", shape="Cylinder")
        for i in range(S.tyres):
            p = spot(8, 95, 0.6)
            if not p:
                continue
            x, y = p
            z = z_at(x, y)
            for k in range(int(r.integers(1, 4))):    # little stacks
                self.add(f"Tyre_{i}_{k}", "Outside", x, y, 0.66, 0.66, z + k * 0.22, z + k * 0.22 + 0.22, 0.0, "Tyre", "prop", shape="Cylinder")
        for i in range(S.scorch_marks):
            p = spot(10, 100, 2.0)
            if p:
                x, y = p
                self.add(f"Scorch_{i}", "Ground", x, y, r.uniform(3, 7), r.uniform(3, 7), z_at(x, y) + 0.01, z_at(x, y) + 0.03,
                         r.uniform(0, math.pi), "Scorch", "decal", collision=False)
        # Overgrowth: bushes hugging the walls and spread over the grounds; tall grass patches.
        for i in range(S.bushes):
            p = spot(0, 110, 1.0) if r.random() < 0.6 else None
            if p is None:
                # Against the building: try a point just outside the footprint.
                for _ in range(60):
                    x, y = r.uniform(-75, 75), r.uniform(-50, 50)
                    if school_poly_test(x, y, 2.5) and not school_poly_test(x, y, 0.0) and self.clear(x, y):
                        p = (x, y)
                        break
            if not p:
                continue
            x, y = p
            z = z_at(x, y)
            w = r.uniform(1.0, 2.6)
            self.add(f"Bush_{i:03d}", "Overgrowth", x, y, w, w * r.uniform(0.7, 1.0), z - 0.2, z + r.uniform(0.8, 1.7), r.uniform(0, math.pi),
                     "Overgrowth", "foliage", shape="Sphere", collision=False)
        for i in range(S.grass_patches):
            p = spot(0, 120, 0.5)
            if not p:
                continue
            x, y = p
            z = z_at(x, y)
            self.add(f"TallGrass_{i:03d}", "Overgrowth", x, y, r.uniform(1.5, 3.5), r.uniform(1.2, 3.0), z - 0.1, z + 0.45, r.uniform(0, math.pi),
                     "Grass", "foliage", shape="Sphere", collision=False)

    def ruin_context(self, z_at):
        r = self.rng
        for bx in self.L.boxes:
            if bx["layer"] != "Context" or not bx["name"].startswith("Bldg_") or r.random() > self.S.ruined_houses:
                continue
            z0, z1 = z_range(bx)
            new_top = z0 + r.uniform(1.8, 3.6)
            if new_top >= z1:
                continue
            bx["size"][2] = round((new_top - z0) * 100, 1)
            bx["center"][2] = round((z0 + new_top) / 2 * 100, 1)
            bx["material"] = "Ruin"
            x, y = to_local(bx)
            self.rubble_pile(f"Ruin_{bx['name']}", "Neighbourhood", x, y, max(0.0, z0 + 0.2), max(2.0, min(bx["size"][0], bx["size"][1]) / 250), 1.5, 12)

    def summary(self):
        added = sum(1 for b in self.L.boxes if b["layer"] == LAYER)
        return {"seed": RUIN_SEED, "added_boxes": added, "removed_boxes": self.removed}
