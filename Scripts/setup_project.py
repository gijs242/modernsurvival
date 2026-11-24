"""One-click project setup, run INSIDE the Unreal Editor (Tools > Execute Python Script, or the
Output Log in "Python" mode:  py "<Project>/Scripts/setup_project.py").

It is idempotent - run it again after changing CSVs or regenerating the Lindenborg layout.

Steps (each step logs and keeps going if something fails; read the Output Log):
  1. Import placeholder audio      RawAssets/Audio/*.wav      -> /Game/Audio
  2. Import placeholder weapons    RawAssets/Weapons/*.glb    -> /Game/Art/Weapons/SM_<name>
  3. Import tuning tables          Data/*.csv                 -> /Game/Data/DT_* and CT_FeelCurves
  4. Build the enemy StateTree     (C++ editor module)        -> /Game/AI/ST_Enemy
  5. Grey-box materials                                       -> /Game/Art/Greybox/MI_*
  6. Build maps                    L_MainMenu, L_TestGrey, L_Lindenborg (from RawAssets/Lindenborg)

Pass step names to run only some:  py ".../setup_project.py" data statetree maps
"""
import json
import math
import os
import sys

import unreal

PROJECT = unreal.Paths.convert_relative_path_to_full(unreal.Paths.project_dir())
RAW = os.path.join(PROJECT, "RawAssets")
DATA = os.path.join(PROJECT, "Data")

asset_tools = unreal.AssetToolsHelpers.get_asset_tools()
eal = unreal.EditorAssetLibrary
eas = unreal.get_editor_subsystem(unreal.EditorActorSubsystem)
les = unreal.get_editor_subsystem(unreal.LevelEditorSubsystem)

PROBLEMS = []


def log(msg):
    unreal.log("[MS setup] " + msg)


def warn(msg):
    PROBLEMS.append(msg)
    unreal.log_warning("[MS setup] " + msg)


def step(fn):
    def run(*a, **k):
        log("---- " + fn.__name__)
        try:
            return fn(*a, **k)
        except Exception as e:  # keep going; report at the end
            warn("{} failed: {}".format(fn.__name__, e))
    run.__name__ = fn.__name__
    return run


def import_task(filename, dest, name=None, factory=None):
    t = unreal.AssetImportTask()
    t.set_editor_property("filename", filename)
    t.set_editor_property("destination_path", dest)
    if name:
        t.set_editor_property("destination_name", name)
    t.set_editor_property("replace_existing", True)
    t.set_editor_property("automated", True)
    t.set_editor_property("save", True)
    if factory:
        t.set_editor_property("factory", factory)
    return t


# ------------------------------------------------------------------------------------------ 1 audio

@step
def import_audio():
    folder = os.path.join(RAW, "Audio")
    tasks = [import_task(os.path.join(folder, f), "/Game/Audio") for f in sorted(os.listdir(folder)) if f.lower().endswith(".wav")]
    asset_tools.import_asset_tasks(tasks)
    log("imported {} sounds".format(len(tasks)))


# ------------------------------------------------------------------------------------------ 2 weapons

@step
def import_weapons():
    folder = os.path.join(RAW, "Weapons")
    for f in sorted(os.listdir(folder)):
        if not f.lower().endswith(".glb"):
            continue
        name = os.path.splitext(f)[0]
        raw_dest = "/Game/Art/Weapons/Raw/" + name
        asset_tools.import_asset_tasks([import_task(os.path.join(folder, f), raw_dest)])
        meshes = []
        for path in eal.list_assets(raw_dest, recursive=True, include_folder=False):
            obj = eal.load_asset(path)
            if isinstance(obj, unreal.StaticMesh):
                box = obj.get_bounding_box()
                size = box.max - box.min
                meshes.append((size.x * size.y * size.z, path, obj))
        if not meshes:
            warn("no static mesh imported from " + f)
            continue
        meshes.sort(key=lambda m: -m[0])
        target = "/Game/Art/Weapons/SM_" + name
        if eal.does_asset_exist(target):
            eal.delete_asset(target)
        eal.duplicate_asset(meshes[0][1].split(".")[0], target)
        log("weapon {} -> {}".format(f, target))
    eal.save_directory("/Game/Art/Weapons")


# ------------------------------------------------------------------------------------------ 3 data

TABLES = {
    "PlayerFeel": "MSPlayerFeelRow", "Weapons": "MSWeaponRow", "Enemies": "MSEnemyRow", "Waves": "MSWaveRow",
    "GameRules": "MSGameRulesRow", "ShopItems": "MSShopItemRow", "Equipment": "MSEquipmentRow", "LookFeel": "MSLookRow",
    "Acoustics": "MSAcousticRow", "AIBehaviour": "MSAIBehaviourRow",
}


@step
def import_data():
    for name, struct in TABLES.items():
        row_struct = unreal.load_object(None, "/Script/ModernSurvival." + struct)
        if not row_struct:
            warn("row struct {} not found - is the C++ module compiled?".format(struct))
            continue
        factory = unreal.CSVImportFactory()
        settings = factory.get_editor_property("automated_import_settings")
        settings.set_editor_property("import_row_struct", row_struct)
        settings.set_editor_property("import_type", unreal.CSVImportType.ECSV_DATA_TABLE)
        factory.set_editor_property("automated_import_settings", settings)
        asset_tools.import_asset_tasks([import_task(os.path.join(DATA, name + ".csv"), "/Game/Data", "DT_" + name, factory)])
        log("DT_{} <- Data/{}.csv".format(name, name))
    factory = unreal.CSVImportFactory()
    settings = factory.get_editor_property("automated_import_settings")
    settings.set_editor_property("import_type", unreal.CSVImportType.ECSV_CURVE_TABLE)
    settings.set_editor_property("import_curve_interp_mode", unreal.RichCurveInterpMode.RCIM_CUBIC)
    factory.set_editor_property("automated_import_settings", settings)
    asset_tools.import_asset_tasks([import_task(os.path.join(DATA, "FeelCurves.csv"), "/Game/Data", "CT_FeelCurves", factory)])
    eal.save_directory("/Game/Data")


# ------------------------------------------------------------------------------------------ 4 statetree

@step
def build_statetree():
    result = unreal.MSEditorBuildLibrary.build_enemy_state_tree("/Game/AI/ST_Enemy")
    ok, text = (result if isinstance(result, tuple) else (result, ""))
    (log if ok else warn)("StateTree: " + str(text))


# ------------------------------------------------------------------------------------------ 5 materials

MATERIALS = {
    "Wall": (0.55, 0.55, 0.53), "Floor": None, "Roof": (0.25, 0.25, 0.26), "Interior": (0.75, 0.62, 0.5),
    "Concrete": (0.5, 0.5, 0.48), "Stairs": (0.25, 0.35, 0.6), "Furniture": (0.45, 0.32, 0.2), "Context": (0.42, 0.44, 0.48),
    "Car": (0.35, 0.08, 0.06), "Shed": (0.2, 0.25, 0.2), "Bikes": (0.15, 0.15, 0.15), "Cover": (0.35, 0.38, 0.3),
    "Crate": (0.3, 0.25, 0.15), "Guessed": (0.8, 0.5, 0.3),
    "MAT_grass": (0.18, 0.24, 0.12), "MAT_road": (0.07, 0.07, 0.07), "MAT_paving": (0.33, 0.31, 0.29),
    "MAT_water": (0.04, 0.07, 0.09), "MAT_parking": (0.16, 0.16, 0.16),
    # Abandoned / destroyed dressing (Tools/lindenborg_ruin.py)
    "Rubble": (0.36, 0.33, 0.3), "Debris": (0.42, 0.38, 0.33), "Panel": (0.7, 0.68, 0.62), "Rust": (0.3, 0.14, 0.07),
    "Planks": (0.33, 0.24, 0.15), "BurntCar": (0.05, 0.045, 0.04), "Scorch": (0.02, 0.02, 0.02), "Sandbag": (0.42, 0.38, 0.26),
    "Container": (0.22, 0.26, 0.2), "Tyre": (0.03, 0.03, 0.03), "Overgrowth": (0.12, 0.2, 0.07), "Grass": (0.25, 0.3, 0.12),
    "Ruin": (0.3, 0.28, 0.27),
}
MAT_CACHE = {}


def material(name):
    if name in MAT_CACHE:
        return MAT_CACHE[name]
    if MATERIALS.get(name, 0) is None:
        mat = unreal.load_asset("/Engine/EngineMaterials/WorldGridMaterial")   # floors: 1 m grid for scale
    else:
        path = "/Game/Art/Greybox/MI_" + name
        mat = unreal.load_asset(path) if eal.does_asset_exist(path) else None
        if not mat:
            mat = asset_tools.create_asset("MI_" + name, "/Game/Art/Greybox", unreal.MaterialInstanceConstant, unreal.MaterialInstanceConstantFactoryNew())
            unreal.MaterialEditingLibrary.set_material_instance_parent(mat, unreal.load_asset("/Engine/BasicShapes/BasicShapeMaterial"))
        color = MATERIALS.get(name, (0.6, 0.6, 0.6))
        unreal.MaterialEditingLibrary.set_material_instance_vector_parameter_value(mat, "Color", unreal.LinearColor(color[0], color[1], color[2], 1.0))
        eal.save_loaded_asset(mat)
    MAT_CACHE[name] = mat
    return mat


@step
def build_materials():
    for name in MATERIALS:
        material(name)


# ------------------------------------------------------------------------------------------ level helpers

SHAPES = {}


def shape_mesh(name="Cube"):
    if name not in SHAPES:
        SHAPES[name] = unreal.load_asset("/Engine/BasicShapes/" + name)
    return SHAPES[name]


def cube():
    return shape_mesh("Cube")


def open_or_create_level(path, partitioned=False):
    """Opens the level (creating it if needed) and clears every actor we placed before."""
    if eal.does_asset_exist(path):
        les.load_level(path)
    else:
        try:
            les.new_level(path, partitioned)
        except TypeError:
            les.new_level(path)
    for a in eas.get_all_level_actors():
        if isinstance(a, (unreal.WorldSettings, unreal.Brush)) and not isinstance(a, unreal.Volume):
            continue
        eas.destroy_actor(a)


def spawn(cls, loc, yaw=0.0, label=None, folder=None):
    a = eas.spawn_actor_from_class(cls, unreal.Vector(*loc), unreal.Rotator(roll=0.0, pitch=0.0, yaw=yaw))
    if a:
        if label:
            a.set_actor_label(label)
        if folder:
            a.set_folder_path(folder)
    return a


def box(name, center, size, yaw=0.0, mat="Wall", folder="Greybox", tags=(), pitch=0.0, roll=0.0, shape="Cube", collision=True):
    a = spawn(unreal.StaticMeshActor, center, yaw, name, folder)
    if not a:
        return None
    if pitch or roll:
        a.set_actor_rotation(unreal.Rotator(roll=roll, pitch=pitch, yaw=yaw), False)
    smc = a.static_mesh_component
    smc.set_static_mesh(shape_mesh(shape))
    if not collision:
        # Foliage, decals, ceiling tiles: you can see/shoot through, AI paths through.
        smc.set_collision_profile_name("NoCollision")
        smc.set_editor_property("can_ever_affect_navigation", False)
    smc.set_material(0, material(mat))
    a.set_actor_scale3d(unreal.Vector(size[0] / 100.0, size[1] / 100.0, size[2] / 100.0))
    if tags:
        a.set_editor_property("tags", [unreal.Name(t) for t in tags])
    return a


def ms_class(name):
    return unreal.load_class(None, "/Script/ModernSurvival." + name)


def add_lighting(sun_pitch=-38.0, sun_yaw=35.0, sun_intensity=6.0, sun_color=(255, 244, 228), fog_density=0.02, sky_intensity=1.0):
    sun = spawn(unreal.DirectionalLight, (0, 0, 2000), 0, "Sun", "Lighting")
    sun.set_actor_rotation(unreal.Rotator(roll=0, pitch=sun_pitch, yaw=sun_yaw), False)
    lc = sun.get_component_by_class(unreal.DirectionalLightComponent)
    lc.set_mobility(unreal.ComponentMobility.MOVABLE)
    lc.set_editor_property("intensity", sun_intensity)
    lc.set_editor_property("atmosphere_sun_light", True)
    lc.set_editor_property("light_color", unreal.Color(sun_color[0], sun_color[1], sun_color[2], 255))
    spawn(unreal.SkyAtmosphere, (0, 0, 0), 0, "SkyAtmosphere", "Lighting")
    sky = spawn(unreal.SkyLight, (0, 0, 500), 0, "SkyLight", "Lighting")
    slc = sky.get_component_by_class(unreal.SkyLightComponent)
    slc.set_mobility(unreal.ComponentMobility.MOVABLE)
    slc.set_editor_property("real_time_capture", True)
    slc.set_editor_property("intensity", sky_intensity)
    fog = spawn(unreal.ExponentialHeightFog, (0, 0, 0), 0, "HeightFog", "Lighting")
    fc = fog.get_component_by_class(unreal.ExponentialHeightFogComponent)
    fc.set_editor_property("fog_density", fog_density)
    fc.set_editor_property("volumetric_fog", True)
    try:
        spawn(unreal.VolumetricCloud, (0, 0, 0), 0, "Clouds", "Lighting")
    except Exception:
        pass


def add_nav_bounds(center, size, yaw=0.0):
    vol = spawn(unreal.NavMeshBoundsVolume, center, yaw, "NavMeshBounds", "Navigation")
    # Volumes spawned by the editor get a 200 uu cube brush.
    vol.set_actor_scale3d(unreal.Vector(size[0] / 200.0, size[1] / 200.0, size[2] / 200.0))
    return vol


def add_spawn_point(name, loc, kind="GROUND", min_wave=1, yaw=0.0, folder="Gameplay/SpawnPoints"):
    a = spawn(ms_class("MSSpawnPoint"), loc, yaw, name, folder)
    a.set_editor_property("kind", getattr(unreal.MSSpawnKind, kind))
    a.set_editor_property("min_wave", min_wave)
    return a


def add_buy_station(category, loc, yaw):
    a = spawn(ms_class("MSBuyStation"), loc, yaw, "BuyStation_" + category, "Gameplay/BuyStations")
    enum = {"Weapons": "WEAPONS", "Equipment": "EQUIPMENT", "AirSupport": "AIR_SUPPORT"}[category]
    a.set_editor_property("category", getattr(unreal.MSShopCategory, enum))
    a.rerun_construction_scripts()
    return a


def set_game_mode(class_name):
    world = unreal.get_editor_subsystem(unreal.UnrealEditorSubsystem).get_editor_world()
    ws = world.get_world_settings()
    ws.set_editor_property("default_game_mode", ms_class(class_name))


# ------------------------------------------------------------------------------------------ 6a main menu

@step
def build_main_menu():
    open_or_create_level("/Game/Maps/L_MainMenu")
    add_lighting(-12.0, 210.0)
    box("Ground", (0, 0, -50), (6000, 6000, 100), 0, "Floor")
    for i, (x, y, h) in enumerate([(900, -200, 120), (1000, 0, 120), (950, 150, 240), (1150, -80, 120), (800, 300, 90)]):
        box("Crate_%d" % i, (x, y, h / 2), (120, 120, h), i * 17.0, "Crate")
    box("Wall", (1400, 0, 200), (60, 1600, 400), 0, "Concrete")
    start = spawn(unreal.PlayerStart, (0, 0, 120), 0, "PlayerStart")
    set_game_mode("MSMenuGameMode")
    les.save_current_level()


# ------------------------------------------------------------------------------------------ 6b grey test map

@step
def build_test_grey():
    open_or_create_level("/Game/Maps/L_TestGrey")
    set_game_mode("MSGameMode")
    add_lighting()
    S = 5000  # half size (cm)
    box("Floor", (0, 0, -25), (2 * S + 400, 2 * S + 400, 50), 0, "Floor", "Greybox/Floor")
    for i, (x, y, sx, sy) in enumerate([(0, S, 2 * S, 60), (0, -S, 2 * S, 60), (S, 0, 60, 2 * S), (-S, 0, 60, 2 * S)]):
        box("Perimeter_%d" % i, (x, y, 200), (sx, sy, 400), 0, "Concrete", "Greybox/Walls")

    # Cover: low walls, crates, pillars in rings around the centre.
    import random
    rnd = random.Random(42)
    n = 0
    for ring in (1400, 2400, 3400):
        for k in range(10):
            a = 2 * math.pi * (k + rnd.random() * 0.5) / 10
            x, y = ring * math.cos(a), ring * math.sin(a)
            kind = rnd.choice(["low", "low", "crate", "pillar", "tall"])
            yaw = math.degrees(a) + 90
            if kind == "low":
                box("LowWall_%d" % n, (x, y, 55), (420, 40, 110), yaw, "Cover", "Greybox/Cover")
            elif kind == "crate":
                box("Crate_%d" % n, (x, y, 60), (120, 120, 120), yaw + 20, "Crate", "Greybox/Cover")
                box("Crate_%db" % n, (x + 130, y, 60), (120, 120, 120), yaw, "Crate", "Greybox/Cover")
            elif kind == "pillar":
                box("Pillar_%d" % n, (x, y, 150), (60, 60, 300), 0, "Concrete", "Greybox/Cover")
            else:
                box("TallWall_%d" % n, (x, y, 140), (360, 40, 280), yaw, "Cover", "Greybox/Cover")
            n += 1

    # North building: a small room (tight echo) and a big hall (long reverb) for the acoustics test.
    def room(prefix, cx, cy, sx, sy, h, door_side_y):
        t = 30
        box(prefix + "_N", (cx, cy + sy / 2, h / 2), (sx, t, h), 0, "Wall", "Greybox/Building")
        box(prefix + "_E", (cx + sx / 2, cy, h / 2), (t, sy, h), 0, "Wall", "Greybox/Building")
        box(prefix + "_W", (cx - sx / 2, cy, h / 2), (t, sy, h), 0, "Wall", "Greybox/Building")
        door = 240
        seg = (sx - door) / 2
        box(prefix + "_S1", (cx - sx / 2 + seg / 2, cy - sy / 2, h / 2), (seg, t, h), 0, "Wall", "Greybox/Building")
        box(prefix + "_S2", (cx + sx / 2 - seg / 2, cy - sy / 2, h / 2), (seg, t, h), 0, "Wall", "Greybox/Building")
        box(prefix + "_Lintel", (cx, cy - sy / 2, (h + 260) / 2), (door, t, h - 260), 0, "Wall", "Greybox/Building")
        box(prefix + "_Roof", (cx, cy, h + 15), (sx + t, sy + t, 30), 0, "Roof", "Greybox/Building")
    room("SmallRoom", -1800, 3900, 600, 600, 300, -1)
    room("Hall", 1200, 3700, 2200, 1400, 800, -1)

    # Ramp up to a 3 m platform (vertical fights).
    box("Platform", (-3500, -3200, 150), (1200, 800, 300), 0, "Concrete", "Greybox/Platform")
    ramp = box("Ramp", (-2350, -3200, 150), (1200, 400, 40), 0, "Concrete", "Greybox/Platform")
    ramp.set_actor_rotation(unreal.Rotator(roll=0.0, pitch=14.0, yaw=0.0), False)

    for i in range(16):
        a = 2 * math.pi * i / 16
        add_spawn_point("Spawn_%02d" % i, (4500 * math.cos(a), 4500 * math.sin(a), 20), "GROUND", 1, math.degrees(a) + 180)
    for i, (x, y) in enumerate([(-4000, -4000), (4000, -4000), (4000, 4000), (-4000, 4000)]):
        add_spawn_point("AirSpawn_%d" % i, (x * 1.5, y * 1.5, 4000), "AIR", 1)
    add_buy_station("Weapons", (-500, -700, 0), 90)
    add_buy_station("Equipment", (500, -700, 0), 90)
    add_buy_station("AirSupport", (0, -1100, 0), 90)
    spawn(unreal.PlayerStart, (0, -1800, 120), 90, "PlayerStart")
    add_nav_bounds((0, 0, 500), (2 * S + 200, 2 * S + 200, 2000))
    les.save_current_level()


# ------------------------------------------------------------------------------------------ 6c Lindenborg

def import_terrain(layout_dir):
    """Imports terrain.obj and returns (static mesh, actor transform fix). OBJ axis conventions
    differ between importers, so we detect what happened from the bounds and undo it."""
    task = import_task(os.path.join(layout_dir, "terrain_import.obj"), "/Game/Maps/Lindenborg", "SM_Terrain")
    asset_tools.import_asset_tasks([task])
    mesh = None
    for path in eal.list_assets("/Game/Maps/Lindenborg", recursive=False, include_folder=False):
        obj = eal.load_asset(path)
        if isinstance(obj, unreal.StaticMesh) and "Terrain" in obj.get_name():
            mesh = obj
    return mesh


def write_offset_obj(layout_dir, offset):
    """Writes terrain_import.obj with all coordinates positive (asymmetric X/Y extents) so the
    import orientation can be detected unambiguously."""
    src = os.path.join(layout_dir, "terrain.obj")
    dst = os.path.join(layout_dir, "terrain_import.obj")
    with open(src) as f, open(dst, "w") as o:
        for line in f:
            if line.startswith("v "):
                x, y, z = (float(v) for v in line.split()[1:4])
                o.write("v {:.1f} {:.1f} {:.1f}\n".format(x + offset[0], y + offset[1], z + offset[2]))
            else:
                o.write(line)


def terrain_fix(mesh, expected_center):
    """Finds the signed axis permutation (and unit scale) the importer applied, from the bounds
    centre, and returns (rotation, scale) for the actor. The OBJ was offset so every axis has a
    different, positive centre, which makes the match unambiguous."""
    b = mesh.get_bounding_box()
    center = [(b.min.x + b.max.x) / 2, (b.min.y + b.max.y) / 2, (b.min.z + b.max.z) / 2]
    s = max(abs(c) for c in center) / max(expected_center)
    s = min((0.01, 1.0, 100.0), key=lambda u: abs(math.log(s / u)))   # importers only ever use m<->cm factors
    P = [[0] * 3 for _ in range(3)]
    used = set()
    for i in range(3):
        j = min((k for k in range(3) if k not in used), key=lambda k: abs(abs(center[i]) / s - expected_center[k]))
        used.add(j)
        P[i][j] = 1 if center[i] > 0 else -1
    det = (P[0][0] * (P[1][1] * P[2][2] - P[1][2] * P[2][1]) - P[0][1] * (P[1][0] * P[2][2] - P[1][2] * P[2][0])
           + P[0][2] * (P[1][0] * P[2][1] - P[1][1] * P[2][0]))
    # Actor: world = R * S * v_imported + L with R * S = P^T / s.
    x_axis = unreal.Vector(*P[0])
    scale = unreal.Vector(1.0 / s, 1.0 / s, 1.0 / s)
    if det < 0:
        x_axis = unreal.Vector(-P[0][0], -P[0][1], -P[0][2])
        scale = unreal.Vector(-1.0 / s, 1.0 / s, 1.0 / s)
    rot = unreal.MathLibrary.make_rot_from_xz(x_axis, unreal.Vector(*P[2]))
    log("terrain import: bounds centre {} unit scale {:.3f} axes {} det {}".format([round(c) for c in center], s, P, det))
    return rot, scale


@step
def build_lindenborg():
    layout_dir = os.path.join(RAW, "Lindenborg")
    with open(os.path.join(layout_dir, "lindenborg_layout.json")) as f:
        L = json.load(f)
    open_or_create_level("/Game/Maps/L_Lindenborg", partitioned=True)
    set_game_mode("MSGameMode")
    abandoned = L.get("look_row", "Default") == "Abandoned"
    if abandoned:
        # Overcast, low hazy sun, thick dust in the air.
        add_lighting(-22.0, 140.0, sun_intensity=2.5, sun_color=(214, 214, 200), fog_density=0.045, sky_intensity=0.8)
    else:
        add_lighting(-35.0, 140.0)
    look = spawn(ms_class("MSLookManager"), (0, 0, 300), 0, "LookManager", "Lighting")
    look.set_editor_property("look_row", L.get("look_row", "Default"))

    layers = {}
    try:
        dls = unreal.get_editor_subsystem(unreal.DataLayerEditorSubsystem)
        for name in ("Measured", "Guessed", "Context", "Destruction"):
            path = "/Game/Maps/Lindenborg/DL_" + name
            asset = unreal.load_asset(path) if eal.does_asset_exist(path) else None
            if not asset:
                factory = unreal.DataLayerFactory() if hasattr(unreal, "DataLayerFactory") else None
                asset = asset_tools.create_asset("DL_" + name, "/Game/Maps/Lindenborg", unreal.DataLayerAsset, factory)
            params = unreal.DataLayerCreationParameters()
            params.set_editor_property("data_layer_asset", asset)
            layers[name] = dls.create_data_layer_instance(params)
        log("data layers: " + ", ".join(layers))
    except Exception as e:
        warn("data layers unavailable ({}); using folders + actor tags instead".format(e))
        dls = None

    by_layer = {"Measured": [], "Guessed": [], "Context": [], "Destruction": []}
    boxes = L["boxes"]
    with unreal.ScopedSlowTask(len(boxes), "Building Lindenborg grey-box") as task:
        task.make_dialog(True)
        for i, b in enumerate(boxes):
            if task.should_cancel():
                break
            task.enter_progress_frame(1)
            a = box(b["name"], b["center"], b["size"], b["yaw"], b["material"], b["folder"], (b["layer"], b["kind"]),
                    b.get("pitch", 0.0), b.get("roll", 0.0), b.get("shape", "Cube"), b.get("collision", True))
            if a:
                try:
                    a.set_editor_property("is_spatially_loaded", False)
                except Exception:
                    pass
                by_layer[b["layer"]].append(a)
    if dls:
        for name, actors in by_layer.items():
            if actors and name in layers:
                dls.add_actors_to_data_layer(actors, layers[name])

    # Terrain from AHN (one mesh, BGT surface materials).
    try:
        half = L["terrain"]["half_size_m"] * 100.0
        offset = (half + 5000.0, half + 15000.0, 2000.0)          # asymmetric => detectable orientation
        write_offset_obj(layout_dir, offset)
        mesh = import_terrain(layout_dir)
        if mesh:
            body = mesh.get_editor_property("body_setup")
            body.set_editor_property("collision_trace_flag", unreal.CollisionTraceFlag.CTF_USE_COMPLEX_AS_SIMPLE)
            for idx, sm in enumerate(mesh.get_editor_property("static_materials")):
                slot = str(sm.get_editor_property("material_slot_name"))
                key = next((k for k in MATERIALS if k.startswith("MAT_") and k[4:] in slot), None)
                if key:
                    mesh.set_material(idx, material(key))
            eal.save_loaded_asset(mesh)
            zs = [float(l.split()[3]) for l in open(os.path.join(layout_dir, "terrain.obj")) if l.startswith("v ")]
            expected_center = [offset[0], offset[1], offset[2] + (max(zs) + min(zs)) / 2]
            rot, scale = terrain_fix(mesh, expected_center)
            t = spawn(unreal.StaticMeshActor, (0, 0, 0), 0, "Terrain_AHN", "Lindenborg/Context")
            t.static_mesh_component.set_static_mesh(mesh)
            t.set_actor_rotation(rot, False)
            t.set_actor_scale3d(scale)
            # Place so the mesh's offset origin lands at -offset (computed after rotation/scale).
            src_origin = unreal.Vector(-offset[0], -offset[1], -offset[2])
            t.set_actor_location(src_origin, False, False)
            by_layer["Context"].append(t)
            if dls and "Context" in layers:
                dls.add_actors_to_data_layer([t], layers["Context"])
        else:
            raise RuntimeError("terrain mesh not imported")
    except Exception as e:
        warn("terrain import failed ({}); placing a flat ground plane instead".format(e))
        box("Ground_Flat", (0, 0, -30), (36000, 36000, 40), 0, "MAT_paving", "Lindenborg/Context")

    for sp in L["spawn_points"]:
        add_spawn_point(sp["name"], sp["location"], sp["kind"].upper(), sp["min_wave"], sp["yaw"])
    for st in L["buy_stations"]:
        add_buy_station(st["category"], st["location"], st["yaw"])
    ps = L["player_start"]
    spawn(unreal.PlayerStart, ps["location"], ps["yaw"], "PlayerStart", "Gameplay")
    nav = L["nav_bounds"]
    add_nav_bounds(nav["center"], nav["size_cm"], nav["yaw"])
    les.save_current_level()
    log("Lindenborg: {} boxes ({})".format(len(boxes), {k: len(v) for k, v in by_layer.items()}))


# ------------------------------------------------------------------------------------------ main

STEPS = {
    "audio": import_audio, "weapons": import_weapons, "data": import_data, "statetree": build_statetree,
    "materials": build_materials, "menu": build_main_menu, "testmap": build_test_grey, "lindenborg": build_lindenborg,
}


def main(argv):
    wanted = [a for a in argv if a in STEPS] or list(STEPS)
    if "maps" in argv:
        wanted = ["materials", "menu", "testmap", "lindenborg"]
    for name in wanted:
        STEPS[name]()
    eal.save_directory("/Game/")
    if PROBLEMS:
        unreal.log_warning("[MS setup] finished with {} problem(s):\n  - {}".format(len(PROBLEMS), "\n  - ".join(PROBLEMS)))
    else:
        log("finished without problems. Open /Game/Maps/L_TestGrey and press Play.")


if __name__ == "__main__":
    main(sys.argv[1:])
