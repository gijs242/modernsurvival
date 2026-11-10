"""Turns a Poly Haven scanned tree (millions of leaf triangles) into a game-ready tree.

  * trunk + branches: real geometry, decimated
  * foliage: a leaf-cluster texture rendered from the real leaves, on crossed alpha cards
    placed where the real tree's leaves are (k-means on leaf positions)

    blender -b --factory-startup -P tools/make_game_tree.py -- <tree.gltf> <out.glb> [cards=160]
"""
import bpy
import bmesh
import math
import os
import random
import sys

import numpy as np
from mathutils import Matrix, Vector

argv = sys.argv[sys.argv.index("--") + 1:]
SRC, OUT = argv[0], argv[1]
CARDS = int(argv[2]) if len(argv) > 2 else 160
TEX_RES = 1024
random.seed(7)

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)
for o in list(bpy.context.scene.objects):
    if o.type != "MESH" or o.name == "Cube" or "LOD" not in o.name:
        bpy.data.objects.remove(o)
tree = [o for o in bpy.context.scene.objects if o.type == "MESH"][0]
bpy.context.view_layer.objects.active = tree
tree.select_set(True)
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

# split by material
bpy.ops.object.mode_set(mode="EDIT")
bpy.ops.mesh.separate(type="MATERIAL")
bpy.ops.object.mode_set(mode="OBJECT")
parts = [o for o in bpy.context.scene.objects if o.type == "MESH"]
leaves = [o for o in parts if "leaves" in o.data.materials[0].name.lower()][0]
wood = [o for o in parts if o is not leaves]
print("leaves tris", len(leaves.data.polygons), "wood parts", [(o.name, len(o.data.polygons)) for o in wood])

# ---- leaf positions -> card centres (k-means)
co = np.empty(len(leaves.data.vertices) * 3)
leaves.data.vertices.foreach_get("co", co)
co = co.reshape(-1, 3)
sample = co[np.random.default_rng(1).choice(len(co), min(len(co), 60000), replace=False)]
k = CARDS
cent = sample[np.random.default_rng(2).choice(len(sample), k, replace=False)]
for _ in range(12):
    d = ((sample[:, None, :] - cent[None, :, :]) ** 2).sum(-1)
    lab = d.argmin(1)
    for j in range(k):
        pts = sample[lab == j]
        if len(pts):
            cent[j] = pts.mean(0)
spread = np.array([np.sqrt(((sample[lab == j] - cent[j]) ** 2).sum(1).mean()) if (lab == j).any() else 0.3 for j in range(k)])

# ---- render a leaf-cluster texture from a chunk of real foliage (transparent background)
scene = bpy.context.scene
for o in wood:
    o.hide_render = True
mn, mx = co.min(0), co.max(0)
c0 = cent[np.argsort(spread)[len(spread) // 2]]
cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
scene.collection.objects.link(cam)
cam.data.type = "ORTHO"
chunk = float(np.median(spread)) * 3.2
cam.data.ortho_scale = chunk
cam.location = Vector(c0) + Vector((0, -10, 0))
cam.rotation_euler = (math.pi / 2, 0, 0)
cam.data.clip_start = 10 - chunk * 0.6
cam.data.clip_end = 10 + chunk * 0.6
scene.camera = cam
sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
sun.data.energy = 3.5
sun.rotation_euler = (math.radians(50), 0, math.radians(30))
scene.collection.objects.link(sun)
world = bpy.data.worlds.new("w")
world.use_nodes = True
world.node_tree.nodes["Background"].inputs[0].default_value = (0.6, 0.65, 0.7, 1)
world.node_tree.nodes["Background"].inputs[1].default_value = 0.8
scene.world = world
scene.render.engine = "CYCLES"
scene.cycles.samples = 24
scene.cycles.use_denoising = False
scene.cycles.device = "CPU"
scene.render.film_transparent = True
scene.render.resolution_x = scene.render.resolution_y = TEX_RES
scene.render.image_settings.file_format = "PNG"
scene.render.image_settings.color_mode = "RGBA"
tex_path = os.path.splitext(OUT)[0] + "_leaves.png"
scene.render.filepath = tex_path
bpy.ops.render.render(write_still=True)
# fade the square render into a ragged round cluster so the cards don't show straight edges
im = bpy.data.images.load(tex_path)
px = np.array(im.pixels[:]).reshape(TEX_RES, TEX_RES, 4)
yy, xx = np.mgrid[0:TEX_RES, 0:TEX_RES] / (TEX_RES - 1) * 2 - 1
ang = np.arctan2(yy, xx)
wob = 1.0 + 0.12 * np.sin(ang * 5 + 1.3) + 0.08 * np.sin(ang * 11 + 0.4) + 0.05 * np.sin(ang * 23)
r = np.sqrt(xx ** 2 + yy ** 2) / (0.92 * wob)
mask = np.clip((1.0 - r) / 0.25, 0, 1)
px[:, :, 3] *= mask
im.pixels[:] = px.ravel()
im.filepath_raw = tex_path
im.file_format = "PNG"
im.save()
print("rendered", tex_path)

# ---- decimate wood
for o in wood:
    bpy.context.view_layer.objects.active = o
    total = len(o.data.polygons)
    target = 9000 if "trunk" in o.data.materials[0].name.lower() else 6000
    if total > target:
        mod = o.modifiers.new("dec", "DECIMATE")
        mod.ratio = target / total
        bpy.ops.object.modifier_apply(modifier="dec")
    print("wood", o.name, total, "->", len(o.data.polygons))
bpy.data.objects.remove(leaves)

# ---- build the card mesh: 3 crossed quads per cluster
mesh = bpy.data.meshes.new("leaf_cards")
bm = bmesh.new()
uv = bm.loops.layers.uv.new()
for j in range(k):
    c = Vector(cent[j])
    s = max(0.3, float(spread[j]) * 1.9)
    yaw = random.random() * math.pi
    for q in range(3):
        if q < 2:
            m = Matrix.Rotation(yaw + q * math.pi / 2, 3, "Z") @ Matrix.Rotation(random.uniform(-0.3, 0.3), 3, "X")
            corners = [Vector((-s, 0, -s)), Vector((s, 0, -s)), Vector((s, 0, s)), Vector((-s, 0, s))]
        else:
            m = Matrix.Rotation(yaw, 3, "Z")
            corners = [Vector((-s, -s, 0)), Vector((s, -s, 0)), Vector((s, s, 0)), Vector((-s, s, 0))]
        vs = [bm.verts.new(c + m @ p) for p in corners]
        f = bm.faces.new(vs)
        for loop, (u, v) in zip(f.loops, [(0, 0), (1, 0), (1, 1), (0, 1)]):
            loop[uv].uv = (u, v)
bm.to_mesh(mesh)
bm.free()
cards = bpy.data.objects.new("leaves", mesh)
scene.collection.objects.link(cards)
mat = bpy.data.materials.new("leaf_cards")
mat.use_nodes = True
mat.blend_method = "CLIP"
nt = mat.node_tree
bsdf = nt.nodes["Principled BSDF"]
img = nt.nodes.new("ShaderNodeTexImage")
img.image = bpy.data.images.load(tex_path)
nt.links.new(img.outputs["Color"], bsdf.inputs["Base Color"])
nt.links.new(img.outputs["Alpha"], bsdf.inputs["Alpha"])
bsdf.inputs["Roughness"].default_value = 0.8
mesh.materials.append(mat)
# smooth upward-ish normals on foliage so cards light like a canopy, not like flat planes
for p in mesh.polygons:
    p.use_smooth = True

# ---- export (ground at y=0)
objs = [o for o in scene.objects if o.type == "MESH"]
zmin = min((o.matrix_world @ Vector(b)).z for o in objs for b in o.bound_box)
for o in objs:
    o.location.z -= zmin
for o in list(scene.objects):
    if o.type != "MESH":
        bpy.data.objects.remove(o)
bpy.ops.object.select_all(action="SELECT")
bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", export_image_format="AUTO", export_apply=True)
tris = sum(len(o.data.polygons) for o in scene.objects if o.type == "MESH")
print("EXPORTED", OUT, "faces", tris)
