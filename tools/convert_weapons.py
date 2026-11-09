"""Converts free weapon models into game-ready GLBs in assets/weapons/.

Run with Blender 4.x (it does the format conversion and normalisation):
    blender -b --factory-startup -P tools/convert_weapons.py -- <source_dir> <out_dir>

<source_dir> must contain the extracted downloads listed in tools/fetch_weapons.py.
Every output GLB is normalised so that in Godot:
  * the barrel points down -Z, +Y is up, real-world scale (metres)
  * the origin sits on the sight line, roughly above the pistol grip  -> aiming down sights = (0, 0, -eye relief)
  * child nodes: Muzzle, Eject, GripR, GripL (+ Mag when the magazine is a separate part)
  * untextured parts use materials named gun_metal / gun_polymer / gun_wood, which the game swaps for PBR materials
"""
import bpy
import bmesh
import math
import os
import sys
from mathutils import Matrix, Vector

argv = sys.argv[sys.argv.index("--") + 1:]
SRC, OUT = argv[0], argv[1]
ONLY = argv[2].split(",") if len(argv) > 2 else None

# Blender axes: barrel must end up pointing +Y with +Z up (glTF export turns +Y into -Z).
WEAPONS = [
    {"id": "ar", "src": "fpsweapons/FPSWeapons.blend", "keep": ["=M4 Carbine", "=M4 Magazine", "=EOTech"],
     "mag": "M4 Magazine", "length": 0.84, "length_of": "M4 Carbine", "grip": 0.33, "hand": 0.66,
     "sight": {"object": "EOTech", "z_frac": 0.62}, "mats": {"*": "gun_metal", "EOTech": "gun_polymer", "M4 Magazine": "gun_metal"},
     "pre": "m4"},
    {"id": "shotgun", "src": "fpsweapons/FPSWeapons.blend", "keep": ["=Mossberg 500"], "length": 0.98,
     "grip": 0.2, "hand": 0.64, "sight": {"top_at": 0.92}, "mats": {"Material.013": "gun_metal", "Material.015": "gun_polymer", "*": "gun_metal"}},
    {"id": "smg", "src": "smg/export/smg.FBX", "drop": ["bullet"], "mag": "magazine", "rot_z": 180, "length": 0.74,
     "grip": 0.42, "hand": 0.68, "sight": {"object": "sight", "z_frac": 0.5}, "tex": "smg"},
    {"id": "lmg", "src": "m60/m60.fbx", "rot_z": 180, "length": 1.1, "grip": 0.36, "hand": 0.62, "sight": {"top_at": 0.45}},
    {"id": "launcher", "src": "RPG7/RPG7.fbx", "pre": "rpg", "length": 1.25, "grip": 0.42, "hand": 0.58,
     "sight": {"top_at": 0.62, "x_side": -1}},
    {"id": "dmr", "src": "polyhaven/bolt_action_rifle_7_62/bolt_action_rifle_7_62.gltf",
     "drop": ["bolt_b", "bullet"], "rot_z": 90, "length": 1.15, "grip": 0.3, "hand": 0.55,
     "sight": {"object": "scope", "z_frac": 0.55}},
    {"id": "frag", "src": "mk2_grenade/mk2_grenade.glb", "grenade": True},
]


def clear():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def import_any(path):
    ext = os.path.splitext(path)[1].lower()
    if ext == ".blend":
        with bpy.data.libraries.load(path) as (src, dst):
            dst.objects = src.objects
        for o in dst.objects:
            if o is not None:
                bpy.context.scene.collection.objects.link(o)
    elif ext == ".fbx":
        bpy.ops.import_scene.fbx(filepath=path)
    elif ext == ".obj":
        bpy.ops.wm.obj_import(filepath=path)
    else:
        bpy.ops.import_scene.gltf(filepath=path)


def name_match(name, pats):
    for p in pats:
        if p.startswith("="):
            if name == p[1:]:
                return True
        elif p.lower() in name.lower():
            return True
    return False


def meshes():
    return [o for o in bpy.context.scene.objects if o.type == "MESH"]


def bake_all():
    """Apply every object's world transform into its mesh and unparent."""
    for o in list(bpy.context.scene.objects):
        if o.type != "MESH":
            bpy.data.objects.remove(o)
    for o in meshes():
        mw = o.matrix_world.copy()
        o.parent = None
        if o.data.users > 1:
            o.data = o.data.copy()
        o.data.transform(mw)
        o.matrix_world = Matrix.Identity(4)


def transform_all(m):
    for o in meshes():
        o.data.transform(m)


def bounds(objs=None):
    objs = objs or meshes()
    pts = [v.co for o in objs for v in o.data.vertices]
    mn = Vector((min(p[i] for p in pts) for i in range(3)))
    mx = Vector((max(p[i] for p in pts) for i in range(3)))
    return mn, mx


def verts_in(y0, y1, objs=None):
    return [v.co for o in (objs or meshes()) for v in o.data.vertices if y0 <= v.co.y <= y1]


def empty(name, pos):
    e = bpy.data.objects.new(name, None)
    e.location = pos
    bpy.context.scene.collection.objects.link(e)
    return e


def set_material_names(cfg):
    mats = cfg.get("mats")
    if not mats:
        return
    for o in meshes():
        for slot in o.material_slots:
            m = slot.material
            key = o.name if o.name in mats else (m.name if m and m.name in mats else "*")
            target = mats.get(key, mats.get("*"))
            if target:
                nm = bpy.data.materials.get(target) or bpy.data.materials.new(target)
                nm.use_nodes = True
                slot.material = nm
        if not o.material_slots:
            o.data.materials.append(bpy.data.materials.get(mats.get(o.name, mats["*"])) or bpy.data.materials.new(mats.get(o.name, mats["*"])))


def smg_textures():
    d = os.path.join(SRC, "smg")
    mat = bpy.data.materials.new("smg_pbr")
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes["Principled BSDF"]

    def img(n, color=True):
        t = nt.nodes.new("ShaderNodeTexImage")
        t.image = bpy.data.images.load(os.path.join(d, n))
        if not color:
            t.image.colorspace_settings.name = "Non-Color"
        return t
    base = img("D.tga")
    nt.links.new(base.outputs["Color"], bsdf.inputs["Base Color"])
    gloss = img("G.tga", False)
    inv = nt.nodes.new("ShaderNodeInvert")
    nt.links.new(gloss.outputs["Color"], inv.inputs["Color"])
    nt.links.new(inv.outputs["Color"], bsdf.inputs["Roughness"])
    nrm = img("N.tga", False)
    nm = nt.nodes.new("ShaderNodeNormalMap")
    nt.links.new(nrm.outputs["Color"], nm.inputs["Color"])
    nt.links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])
    bsdf.inputs["Metallic"].default_value = 0.6
    for o in meshes():
        o.data.materials.clear()
        o.data.materials.append(mat)


def convert(cfg):
    clear()
    src = os.path.join(SRC, cfg["src"])
    import_any(src)
    keep, drop = cfg.get("keep"), cfg.get("drop", [])
    for o in list(meshes()):
        if (keep and not name_match(o.name, keep)) or name_match(o.name, drop):
            bpy.data.objects.remove(o)
    if cfg["id"] == "dmr":
        # Poly Haven rifle: the bolt has two poses (a/b); keep "a". The scope node is parented with a rotation.
        pass
    if cfg.get("pre") == "rpg":
        rot = bpy.data.objects["RPG7"].matrix_world.to_3x3().to_4x4()
        bake_all()
        transform_all(rot.inverted())
    else:
        bake_all()
    if cfg.get("pre") == "m4":
        # The magazine ships raised out of the magwell (2x scale model); seat it.
        for o in meshes():
            if o.name == "M4 Magazine":
                o.data.transform(Matrix.Translation((0, 0, -0.33)))
            if o.name == "EOTech":
                # move the sight from the side of the scene onto the flat-top rail
                mn, mx = bounds([o])
                cmn, cmx = bounds([bpy.data.objects["M4 Carbine"]])
                c = (mn + mx) / 2
                rail_y = cmn.y + (cmx.y - cmn.y) * 0.43
                near = [v.co.z for v in bpy.data.objects["M4 Carbine"].data.vertices if abs(v.co.y - rail_y) < 0.15]
                top = max(near) if near else cmx.z
                o.data.transform(Matrix.Translation((-c.x, rail_y - c.y, top - mn.z - 0.005)))
                # open the holographic window: delete the faces facing along the bore inside the hood
                emn, emx = bounds([o])
                h, wdt = emx.z - emn.z, emx.x - emn.x
                bm = bmesh.new()
                bm.from_mesh(o.data)
                dead = [f for f in bm.faces if abs(f.normal.y) > 0.6
                        and abs(f.calc_center_median().x - (emn.x + emx.x) / 2) < wdt * 0.36
                        and emn.z + h * 0.42 < f.calc_center_median().z < emn.z + h * 0.92]
                bmesh.ops.delete(bm, geom=dead, context="FACES")
                bm.to_mesh(o.data)
                bm.free()
                print("EOTech window faces removed:", len(dead))
    if cfg.get("pre") == "bolt":
        transform_all(Matrix(((0, 0, 1, 0), (1, 0, 0, 0), (0, 1, 0, 0), (0, 0, 0, 1))))   # X->Y, Y->Z, Z->X
    if cfg.get("rot_z"):
        transform_all(Matrix.Rotation(math.radians(cfg["rot_z"]), 4, "Z"))
    if cfg.get("pre") == "rpg":
        # longest axis -> Y, warhead forward
        mn, mx = bounds()
        size = mx - mn
        ax = max(range(3), key=lambda i: size[i])
        if ax == 0:
            transform_all(Matrix.Rotation(math.radians(90), 4, "Z"))
        elif ax == 2:
            transform_all(Matrix.Rotation(math.radians(-90), 4, "X"))
        mn, mx = bounds()
        if (mx.x - mn.x) > (mx.z - mn.z):
            transform_all(Matrix.Rotation(math.radians(90), 4, "Y"))   # lying on its side -> stand it up
        rk = [o for o in meshes() if "Rocket" in o.name][0]
        rmn, rmx = bounds([rk])
        mn, mx = bounds()
        if (rmn.y + rmx.y) / 2 < (mn.y + mx.y) / 2:
            transform_all(Matrix.Rotation(math.radians(180), 4, "Z"))
        # sights/grips must hang down: the grip is the lowest thing around the middle
        mid = verts_in((mn.y + mx.y) / 2 - 0.2, (mn.y + mx.y) / 2 + 0.2)
        zs = sorted(p.z for p in mid)
        if zs and abs(zs[0] - (mn.z + mx.z) / 2) < abs(zs[-1] - (mn.z + mx.z) / 2):
            transform_all(Matrix.Rotation(math.radians(180), 4, "Y"))

    if cfg.get("tex") == "smg":
        smg_textures()
    set_material_names(cfg)

    if cfg.get("grenade"):
        mn, mx = bounds()
        s = 0.11 / (mx.z - mn.z)
        transform_all(Matrix.Scale(s, 4))
        mn, mx = bounds()
        transform_all(Matrix.Translation(-(mn + mx) / 2))
        export(cfg)
        return

    # scale to real length
    ref = [bpy.data.objects[cfg["length_of"]]] if cfg.get("length_of") else None
    mn, mx = bounds(ref)
    s = cfg["length"] / (mx.y - mn.y)
    transform_all(Matrix.Scale(s, 4))
    mn, mx = bounds()
    L = mx.y - mn.y
    # bore height from the muzzle tip
    tip = verts_in(mx.y - L * 0.03, mx.y)
    bore_z = sum(p.z for p in tip) / len(tip)
    bore_x = sum(p.x for p in tip) / len(tip)
    # sight line height
    sc = cfg["sight"]
    sight_x = bore_x
    if "object" in sc:
        so = [o for o in meshes() if sc["object"].lower() in o.name.lower()]
        smn, smx = bounds(so)
        sight_z = smn.z + (smx.z - smn.z) * sc["z_frac"]
        sight_x = (smn.x + smx.x) / 2
    else:
        y = mn.y + L * sc["top_at"]
        sl = verts_in(y - 0.03, y + 0.03)
        sight_z = max(p.z for p in sl) + 0.004
        if sc.get("x_side"):
            sight_x = min(p.x for p in sl) - 0.02 if sc["x_side"] < 0 else max(p.x for p in sl) + 0.02
    grip_y = mn.y + L * cfg["grip"]
    origin = Vector((sight_x, grip_y, sight_z))
    transform_all(Matrix.Translation(-origin))
    mn, mx = bounds()
    bore_z -= origin.z
    # markers
    eo = [o for o in meshes() if o.name == "EOTech"]
    if eo:
        emn, emx = bounds(eo)
        empty("Reticle", (0, (emn.y + emx.y) / 2, 0))
    empty("Muzzle", (bore_x - origin.x, mx.y + 0.005, bore_z))
    empty("Eject", (0.03, (mn.y + L * (cfg["grip"] + 0.12)), bore_z + 0.01))
    gr = verts_in(-0.03, 0.03)
    empty("GripR", (0, 0, min(p.z for p in gr) * 0.55 if gr else bore_z - 0.08))
    hy = mn.y + L * cfg["hand"]
    hl = verts_in(hy - 0.03, hy + 0.03)
    empty("GripL", (0, hy, (min(p.z for p in hl) + 0.01) if hl else bore_z - 0.03))
    if cfg.get("mag"):
        for o in meshes():
            if o.name.lower() == cfg["mag"].lower():
                o.name = "Mag"
    export(cfg)


def export(cfg):
    # merge everything except the magazine into one mesh to keep draw calls low
    body = [o for o in meshes() if o.name != "Mag"]
    bpy.ops.object.select_all(action="DESELECT")
    for o in body:
        o.select_set(True)
    bpy.context.view_layer.objects.active = body[0]
    if len(body) > 1:
        bpy.ops.object.join()
    body[0].name = cfg["id"]
    for o in meshes():
        bpy.context.view_layer.objects.active = o
        bpy.ops.object.select_all(action="DESELECT")
        o.select_set(True)
        for poly in o.data.polygons:
            poly.use_smooth = True
        if hasattr(o.data, 'use_auto_smooth'):
            o.data.use_auto_smooth = True
            o.data.auto_smooth_angle = math.radians(40)
    os.makedirs(OUT, exist_ok=True)
    out = os.path.join(OUT, cfg["id"] + ".glb")
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", export_image_format="JPEG", export_yup=True,
                              export_apply=True, export_extras=False, use_selection=False)
    mn, mx = bounds()
    print(f"EXPORTED {cfg['id']}: {out}  size={[round(v, 3) for v in (mx - mn)]}")


for c in WEAPONS:
    if ONLY and c["id"] not in ONLY:
        continue
    try:
        convert(c)
    except Exception as e:  # noqa: BLE001
        import traceback
        traceback.print_exc()
        print(f"FAILED {c['id']}: {e}")
