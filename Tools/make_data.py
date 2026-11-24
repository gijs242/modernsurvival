#!/usr/bin/env python3
"""Generate (or validate) the tuning CSVs in Data/ from the row structs in MSDataTypes.h.

    python3 Tools/make_data.py            # regenerate every CSV from the tables below
    python3 Tools/make_data.py --check    # CI: every CSV column matches a C++ field, every row parses

You normally edit the CSVs directly (or the DataTables in the editor) — this script is the
starting point and the schema check. Columns are parsed out of the C++ header, so the CSVs can
never drift from the code without --check failing.
"""
from __future__ import annotations

import csv
import io
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
HEADER = ROOT / "Source/ModernSurvival/Public/Data/MSDataTypes.h"
DATA = ROOT / "Data"

# ----------------------------------------------------------------------------- schema parsing

FIELD_RE = re.compile(r"UPROPERTY\([^)]*\)\s*(?P<type>[\w:<>, ]+?)\s+(?P<name>\w+)\s*(?:=\s*(?P<default>[^;]+))?;")


def parse_structs() -> dict[str, list[tuple[str, str, str | None]]]:
    text = HEADER.read_text()
    structs: dict[str, list[tuple[str, str, str | None]]] = {}
    for m in re.finditer(r"struct MODERNSURVIVAL_API (F\w+Row) : public FTableRowBase\s*\{(.*?)\n\};", text, re.S):
        fields = []
        for f in FIELD_RE.finditer(m.group(2)):
            fields.append((f.group("type").strip(), f.group("name"), f.group("default")))
        structs[m.group(1)] = fields
    enums: dict[str, list[str]] = {}
    for m in re.finditer(r"enum class (EMS\w+) : uint8\s*\{(.*?)\};", text, re.S):
        enums[m.group(1)] = [v.split("=")[0].strip() for v in m.group(2).split(",") if v.strip()]
    structs["__enums__"] = enums  # type: ignore[assignment]
    return structs


def _nums(s: str) -> list[float]:
    return [float(x.rstrip("f")) for x in re.findall(r"-?\d+(?:\.\d+)?f?", s)]


def fmt(v: float) -> str:
    return f"{float(v):.6f}"


def ue_value(ctype: str, value) -> str:
    """Format a python value (or a C++ default string) as Unreal ImportText."""
    if ctype.startswith("TSoft"):
        return value or ""
    if ctype in ("float", "double"):
        return fmt(float(str(value).rstrip("f"))) if value is not None else "0.000000"
    if ctype in ("int32", "uint8"):
        return str(int(value)) if value is not None else "0"
    if ctype == "bool":
        return "True" if str(value).lower() in ("true", "1") else "False"
    if ctype == "FText":
        if value is None or "FText" in str(value):
            return ""
        return str(value)
    if ctype == "FName":
        if value is None or value == "NAME_None":
            return "None"
        return str(value).strip('"')
    if ctype == "FVector":
        x, y, z = value if isinstance(value, (tuple, list)) else (_nums(value) or [0, 0, 0])
        return f"(X={fmt(x)},Y={fmt(y)},Z={fmt(z)})"
    if ctype == "FRotator":
        p, y, r = value if isinstance(value, (tuple, list)) else (_nums(value) or [0, 0, 0])
        return f"(Pitch={fmt(p)},Yaw={fmt(y)},Roll={fmt(r)})"
    if ctype == "FLinearColor":
        c = list(value) if isinstance(value, (tuple, list)) else _nums(value)
        if len(c) == 3:
            c.append(1.0)
        return f"(R={fmt(c[0])},G={fmt(c[1])},B={fmt(c[2])},A={fmt(c[3])})"
    if ctype == "FTransform":
        # value: None or dict(yaw=, pitch=, roll=, loc=(x,y,z), scale=s)
        return "(Rotation=(X=0.000000,Y=0.000000,Z=0.000000,W=1.000000),Translation=(X=0.000000,Y=0.000000,Z=0.000000),Scale3D=(X=1.000000,Y=1.000000,Z=1.000000))"
    if ctype.startswith("EMS"):
        return str(value).split("::")[-1]
    raise ValueError(f"unsupported type {ctype}")


# ----------------------------------------------------------------------------- content

W = "/Game/Art/Weapons/SM_{0}.SM_{0}"
A = "/Game/Audio/{0}.{0}"

PLAYER_FEEL = {"Default": {}}

WEAPONS = {
    "Pistol_P9": dict(DisplayName="P9 Service Pistol", WeaponClass="Pistol", FireMode="Semi", RoundsPerMinute=420,
                      Damage=34, HeadshotMultiplier=2.0, FalloffStart=1200, FalloffEnd=3000, MinDamageFraction=0.55,
                      MagazineSize=15, MaxReserveAmmo=90, ReloadTime=1.5, ReloadEmptyTime=1.8, EquipTime=0.3,
                      HipSpread=1.6, ADSSpread=0.2, SpreadPerShot=0.5, MaxSpread=4,
                      RecoilPitchMin=0.9, RecoilPitchMax=1.2, RecoilYawMin=-0.35, RecoilYawMax=0.35,
                      KickBack=2.8, KickPitch=4.5, KickRoll=1.6, ShotTrauma=0.05,
                      ADSFOV=70, ADSTime=0.16, HipOffset=(26, 13, -14), ADSOffset=(30, 0, 0), MoveSpeedMultiplier=1.05,
                      AmmoPrice=100, Mesh=W.format("pistol"), FireSound=A.format("pistol"), FireSoundFar=A.format("pistol_far"),
                      ReloadSound=A.format("mag_in"), DryFireSound=A.format("dry"), PlaceholderSize=(20, 3.5, 13), TracerEveryNth=0),
    "Pistol_Sentinel": dict(DisplayName="Sentinel .45", WeaponClass="Pistol", FireMode="Semi", RoundsPerMinute=360,
                      Damage=48, HeadshotMultiplier=2.2, FalloffStart=1000, FalloffEnd=2800, MinDamageFraction=0.5,
                      MagazineSize=8, MaxReserveAmmo=64, ReloadTime=1.6, ReloadEmptyTime=1.9, EquipTime=0.3,
                      HipSpread=1.8, ADSSpread=0.25, SpreadPerShot=0.7, MaxSpread=4.5,
                      RecoilPitchMin=1.4, RecoilPitchMax=1.8, RecoilYawMin=-0.4, RecoilYawMax=0.5,
                      KickBack=3.4, KickPitch=6.5, KickRoll=2.0, ShotTrauma=0.07,
                      ADSFOV=70, ADSTime=0.17, HipOffset=(26, 13, -14), ADSOffset=(30, 0, 0), MoveSpeedMultiplier=1.05,
                      AmmoPrice=120, Mesh=W.format("m1911"), FireSound=A.format("m1911"), FireSoundFar=A.format("m1911_far"),
                      ReloadSound=A.format("mag_in"), DryFireSound=A.format("dry"), PlaceholderSize=(21, 3.5, 13), TracerEveryNth=0),
    "SMG_Viper": dict(DisplayName="Viper SMG", WeaponClass="SMG", FireMode="Auto", RoundsPerMinute=880,
                      Damage=25, HeadshotMultiplier=1.6, FalloffStart=1200, FalloffEnd=3200, MinDamageFraction=0.55,
                      MagazineSize=32, MaxReserveAmmo=256, ReloadTime=1.9, ReloadEmptyTime=2.3,
                      HipSpread=1.8, ADSSpread=0.35, SpreadPerShot=0.25, MaxSpread=5,
                      RecoilPitchMin=0.32, RecoilPitchMax=0.48, RecoilYawMin=-0.32, RecoilYawMax=0.36, RecoilPatternCurve="Recoil.SMG",
                      KickBack=1.8, KickPitch=1.6, KickRoll=1.0, ShotTrauma=0.035,
                      ADSFOV=65, ADSTime=0.18, ADSOffset=(26, 0, 0), MoveSpeedMultiplier=1.05,
                      AmmoPrice=200, Mesh=W.format("smg"), FireSound=A.format("smg"), FireSoundFar=A.format("smg_far"),
                      ReloadSound=A.format("mag_in"), DryFireSound=A.format("dry"), PlaceholderSize=(48, 5, 12)),
    "AR_Kestrel": dict(DisplayName="Kestrel Carbine", WeaponClass="AssaultRifle", FireMode="Auto", RoundsPerMinute=760,
                      Damage=31, HeadshotMultiplier=1.8, FalloffStart=2500, FalloffEnd=6000, MinDamageFraction=0.65,
                      MagazineSize=30, MaxReserveAmmo=240, ReloadTime=2.1, ReloadEmptyTime=2.6,
                      HipSpread=2.4, ADSSpread=0.12, SpreadPerShot=0.3,
                      RecoilPitchMin=0.42, RecoilPitchMax=0.6, RecoilYawMin=-0.22, RecoilYawMax=0.3, RecoilPatternCurve="Recoil.AR",
                      ADSFOV=60, ADSTime=0.22, ADSOffset=(24, 0, 0),
                      AmmoPrice=250, Mesh=W.format("l85"), FireSound=A.format("l85"), FireSoundFar=A.format("l85_far"),
                      ReloadSound=A.format("mag_in"), DryFireSound=A.format("dry"), PlaceholderSize=(70, 5, 14)),
    "AR_Brigand": dict(DisplayName="Brigand Rifle", WeaponClass="AssaultRifle", FireMode="Auto", RoundsPerMinute=640,
                      Damage=37, HeadshotMultiplier=1.8, FalloffStart=2200, FalloffEnd=5500, MinDamageFraction=0.65,
                      MagazineSize=30, MaxReserveAmmo=210, ReloadTime=2.3, ReloadEmptyTime=2.8,
                      HipSpread=2.6, ADSSpread=0.16, SpreadPerShot=0.4,
                      RecoilPitchMin=0.6, RecoilPitchMax=0.82, RecoilYawMin=-0.4, RecoilYawMax=0.42, RecoilPatternCurve="Recoil.Brigand",
                      KickBack=2.8, KickPitch=2.8, KickRoll=1.6, ShotTrauma=0.07,
                      ADSFOV=60, ADSTime=0.24, ADSOffset=(24, 0, 0), MoveSpeedMultiplier=0.97,
                      AmmoPrice=250, Mesh=W.format("ak47"), FireSound=A.format("ak47"), FireSoundFar=A.format("ak47_far"),
                      ReloadSound=A.format("mag_in"), DryFireSound=A.format("dry"), PlaceholderSize=(80, 5, 14)),
    "BR_Ranger": dict(DisplayName="Ranger Battle Rifle", WeaponClass="AssaultRifle", FireMode="Auto", RoundsPerMinute=560,
                      Damage=50, HeadshotMultiplier=1.9, FalloffStart=3500, FalloffEnd=8000, MinDamageFraction=0.7,
                      MagazineSize=20, MaxReserveAmmo=160, ReloadTime=2.4, ReloadEmptyTime=2.9,
                      HipSpread=2.8, ADSSpread=0.12, SpreadPerShot=0.5, MaxSpread=7,
                      RecoilPitchMin=0.9, RecoilPitchMax=1.15, RecoilYawMin=-0.45, RecoilYawMax=0.5, RecoilPatternCurve="Recoil.AR",
                      KickBack=3.4, KickPitch=3.6, KickRoll=1.8, ShotTrauma=0.09,
                      ADSFOV=55, ADSTime=0.27, ADSOffset=(24, 0, 0), MoveSpeedMultiplier=0.95,
                      AmmoPrice=300, Mesh=W.format("g3a3"), FireSound=A.format("g3a3"), FireSoundFar=A.format("g3a3_far"),
                      ReloadSound=A.format("mag_in"), DryFireSound=A.format("dry"), PlaceholderSize=(95, 5, 15)),
    "Shotgun_Breacher": dict(DisplayName="Breacher Pump", WeaponClass="Shotgun", FireMode="Semi", RoundsPerMinute=75,
                      Damage=22, PelletCount=8, PelletSpread=3.2, HeadshotMultiplier=1.3, Range=4000,
                      FalloffStart=400, FalloffEnd=1600, MinDamageFraction=0.15,
                      MagazineSize=7, MaxReserveAmmo=42, ReloadTime=0.6, ReloadEmptyTime=0.6, bReloadPerShell=True, ReloadPerShellTime=0.55,
                      HipSpread=1.5, ADSSpread=0.6, SpreadPerShot=0, MaxSpread=3,
                      RecoilPitchMin=3.0, RecoilPitchMax=3.8, RecoilYawMin=-0.8, RecoilYawMax=0.8, RecoilRecoverySpeed=14,
                      KickBack=6.5, KickUp=1.2, KickPitch=9, KickRoll=3, KickStiffness=200, ShotTrauma=0.16,
                      ADSFOV=65, ADSTime=0.24, ADSOffset=(24, 0, 0), MoveSpeedMultiplier=0.98, ImpactImpulse=20000,
                      AmmoPrice=200, FireSound=A.format("shotgun"), FireSoundFar=A.format("shotgun_far"),
                      ReloadSound=A.format("pump"), DryFireSound=A.format("dry"), PlaceholderSize=(90, 5, 12), TracerEveryNth=0),
    "LMG_Hammer": dict(DisplayName="Hammer LMG", WeaponClass="LMG", FireMode="Auto", RoundsPerMinute=620,
                      Damage=40, HeadshotMultiplier=1.6, FalloffStart=3500, FalloffEnd=8000, MinDamageFraction=0.7,
                      MagazineSize=100, MaxReserveAmmo=300, ReloadTime=5.8, ReloadEmptyTime=6.4, EquipTime=0.8,
                      HipSpread=3.6, ADSSpread=0.3, SpreadPerShot=0.2, MaxSpread=7,
                      RecoilPitchMin=0.5, RecoilPitchMax=0.7, RecoilYawMin=-0.45, RecoilYawMax=0.45, RecoilPatternCurve="Recoil.LMG",
                      KickBack=2.6, KickPitch=2.2, ShotTrauma=0.07,
                      ADSFOV=58, ADSTime=0.38, ADSOffset=(24, 0, 0), MoveSpeedMultiplier=0.85,
                      AmmoPrice=450, Mesh=W.format("lmg"), FireSound=A.format("lmg"), FireSoundFar=A.format("lmg_far"),
                      ReloadSound=A.format("mag_in"), DryFireSound=A.format("dry"), PlaceholderSize=(105, 9, 20), TracerEveryNth=2),
    "Rifle_Bolt": dict(DisplayName="Bolt-Action Rifle", WeaponClass="Sniper", FireMode="Semi", RoundsPerMinute=48,
                      Damage=160, HeadshotMultiplier=2.5, Range=30000, FalloffStart=10000, FalloffEnd=20000, MinDamageFraction=0.8,
                      MagazineSize=5, MaxReserveAmmo=40, ReloadTime=2.8, ReloadEmptyTime=3.3, EquipTime=0.6,
                      HipSpread=5, ADSSpread=0.0, SpreadPerShot=0, MaxSpread=8,
                      RecoilPitchMin=3.2, RecoilPitchMax=3.8, RecoilYawMin=-0.6, RecoilYawMax=0.6, RecoilRecoverySpeed=10,
                      KickBack=6, KickPitch=7, KickRoll=2.4, ShotTrauma=0.14,
                      ADSFOV=22, ADSTime=0.32, ADSSwayMultiplier=0.5, ADSOffset=(22, 0, 0), MoveSpeedMultiplier=0.92,
                      AmmoPrice=300, Mesh=W.format("dmr"), FireSound=A.format("mosin"), FireSoundFar=A.format("mosin_far"),
                      ReloadSound=A.format("bolt"), DryFireSound=A.format("dry"), PlaceholderSize=(115, 5, 14), TracerEveryNth=1),
    "Sniper_Longbow": dict(DisplayName="Longbow Marksman", WeaponClass="Sniper", FireMode="Semi", RoundsPerMinute=200,
                      Damage=95, HeadshotMultiplier=2.5, Range=25000, FalloffStart=8000, FalloffEnd=16000, MinDamageFraction=0.8,
                      MagazineSize=10, MaxReserveAmmo=60, ReloadTime=2.6, ReloadEmptyTime=3.1, EquipTime=0.55,
                      HipSpread=4.5, ADSSpread=0.02, SpreadPerShot=0.6, MaxSpread=8,
                      RecoilPitchMin=1.8, RecoilPitchMax=2.3, RecoilYawMin=-0.5, RecoilYawMax=0.5,
                      KickBack=4.5, KickPitch=5, ShotTrauma=0.11,
                      ADSFOV=28, ADSTime=0.3, ADSSwayMultiplier=0.45, ADSOffset=(22, 0, 0), MoveSpeedMultiplier=0.93,
                      AmmoPrice=350, Mesh=W.format("svd"), FireSound=A.format("svd"), FireSoundFar=A.format("svd_far"),
                      ReloadSound=A.format("mag_in"), DryFireSound=A.format("dry"), PlaceholderSize=(110, 5, 15), TracerEveryNth=1),
    "Launcher_Thumper": dict(DisplayName="Thumper Rocket Launcher", WeaponClass="Launcher", FireMode="Semi", RoundsPerMinute=40,
                      Damage=350, HeadshotMultiplier=1.0, bProjectile=True, ProjectileSpeed=5500, ProjectileGravityScale=0.1,
                      ExplosionRadius=550, ExplosionInnerRadius=150, ExplosionTrauma=0.8, ExplosionSound=A.format("explosion"),
                      MagazineSize=1, MaxReserveAmmo=5, ReloadTime=2.8, ReloadEmptyTime=2.8, EquipTime=0.7,
                      HipSpread=1.5, ADSSpread=0.1, SpreadPerShot=0, MaxSpread=3,
                      RecoilPitchMin=2.5, RecoilPitchMax=3.0, RecoilYawMin=-0.5, RecoilYawMax=0.5,
                      KickBack=8, KickPitch=6, ShotTrauma=0.2,
                      ADSFOV=55, ADSTime=0.35, ADSOffset=(24, 0, -4), MoveSpeedMultiplier=0.88,
                      AmmoPrice=600, Mesh=W.format("launcher"), FireSound=A.format("launcher"), FireSoundFar=A.format("launcher"),
                      ReloadSound=A.format("mag_in"), DryFireSound=A.format("dry"), PlaceholderSize=(100, 11, 11), TracerEveryNth=0),
    # Not for sale: turret, helicopter.
    "Sentry_Gun": dict(DisplayName="Sentry Gun", WeaponClass="LMG", FireMode="Auto", RoundsPerMinute=700,
                      Damage=24, HeadshotMultiplier=1.5, MagazineSize=9999, MaxReserveAmmo=0, HipSpread=1.6, ADSSpread=1.6,
                      FireSound=A.format("turret"), FireSoundFar=A.format("lmg_far"), TracerEveryNth=2),
    "Heli_Minigun": dict(DisplayName="Helicopter Minigun", WeaponClass="LMG", FireMode="Auto", RoundsPerMinute=1500,
                      Damage=14, HeadshotMultiplier=1.0, Range=20000, FalloffStart=6000, FalloffEnd=15000,
                      MagazineSize=9999, MaxReserveAmmo=0, HipSpread=2.5, ADSSpread=2.5,
                      FireSound=A.format("gunship"), FireSoundFar=A.format("gunship"), TracerEveryNth=3),
}

ENEMY_FALLBACK_SOUNDS = dict()
ENEMIES = {
    "Rifleman": dict(DisplayName="Rifleman", Archetype="Rifleman", CashReward=100, Health=100,
                     Weapon="AR_Kestrel", WeaponDamageScale=0.3, AimErrorDegrees=3.2, BehaviourRow="Default",
                     PlaceholderColor=(0.24, 0.26, 0.2)),
    "ShotgunRusher": dict(DisplayName="Shotgun Rusher", Archetype="Rusher", CashReward=120, Health=130,
                     Weapon="Shotgun_Breacher", WeaponDamageScale=0.26, AimErrorDegrees=2.0, BurstMin=1, BurstMax=1,
                     BurstPauseMin=0.9, BurstPauseMax=1.3, EngageRangeMin=0, EngageRangeMax=900,
                     WalkSpeed=360, RunSpeed=580, BehaviourRow="Rusher", PlaceholderColor=(0.3, 0.22, 0.16)),
    "AttackDog": dict(DisplayName="Attack Dog", Archetype="Dog", CashReward=100, Health=60, Weapon="None",
                     MeleeDamage=24, MeleeRange=140, MeleeCooldown=0.9, MeleeLunge=650,
                     WalkSpeed=500, RunSpeed=920, CapsuleRadius=30, CapsuleHalfHeight=42,
                     SightRadius=8000, PeripheralVisionHalfAngle=110, BehaviourRow="Dog", PlaceholderColor=(0.18, 0.14, 0.1)),
    "Juggernaut": dict(DisplayName="Juggernaut", Archetype="Juggernaut", CashReward=600, Health=1800,
                     DamageReduction=0.3, HeadshotMultiplierScale=0.6, ExplosiveDamageScale=0.8, bFlinches=False,
                     Weapon="LMG_Hammer", WeaponDamageScale=0.28, AimErrorDegrees=3.8, BurstMin=8, BurstMax=18,
                     BurstPauseMin=0.6, BurstPauseMax=1.0, EngageRangeMax=3500,
                     WalkSpeed=170, RunSpeed=210, CapsuleRadius=44, CapsuleHalfHeight=96, PlaceholderScale=1.15,
                     BehaviourRow="Juggernaut", PlaceholderColor=(0.12, 0.12, 0.12)),
    "AttackHelicopter": dict(DisplayName="Attack Helicopter", Archetype="Helicopter", CashReward=1000, Health=2600,
                     ExplosiveDamageScale=1.6, HeadshotMultiplierScale=0, Weapon="Heli_Minigun", WeaponDamageScale=0.45,
                     AimErrorDegrees=2.5, BurstMin=15, BurstMax=30, BurstPauseMin=1.5, BurstPauseMax=3.0,
                     EngageRangeMax=9000, SightRadius=15000, LoseSightRadius=16000, PeripheralVisionHalfAngle=180,
                     OrbitRadius=3500, OrbitAltitude=2400, OrbitSpeed=900, RocketInterval=7, RocketWeapon="Launcher_Thumper",
                     LoopSound=A.format("gunship"), PlaceholderColor=(0.16, 0.18, 0.15)),
    "FriendlySoldier": dict(DisplayName="Squad Soldier", Archetype="FriendlySoldier", CashReward=0, Health=350,
                     Weapon="AR_Kestrel", WeaponDamageScale=1.0, AimErrorDegrees=1.6, FirstShotDelay=0.35,
                     BehaviourRow="Squad", PlaceholderColor=(0.25, 0.3, 0.38)),
}

AI_BEHAVIOUR = {
    "Default": {},
    "Rusher": dict(bUsesCover=False, FlankChance=0.5, FlankCooldown=8, StrafeWhileFiring=0.8, RushStopDistance=220),
    "Dog": dict(bUsesCover=False, FlankChance=0.4, FlankCooldown=6, RushStopDistance=80, AcceptanceRadius=30, RepathInterval=0.3),
    "Juggernaut": dict(bUsesCover=False, FlankChance=0.0, RushStopDistance=600, StrafeWhileFiring=0.0),
    "Squad": dict(FlankChance=0.0, CoverPreferredDistance=1400, CoverSearchRadius=1200, CoverHoldTimeMin=3, CoverHoldTimeMax=8),
}


def make_waves() -> dict[str, dict]:
    waves = {}
    for w in range(1, 21):
        rif = 5 + w + (w // 3)
        rush = 0 if w < 3 else 1 + (w - 2) // 2
        dogs = 0 if w < 5 else 2 + (w - 5) // 2
        jugg = 0 if w < 8 else 1 + (w - 8) // 5
        heli = 1 if w in (10, 15) else (2 if w == 20 else 0)
        if w == 7:                # dog wave
            dogs, rif = dogs + 8, rif - 4
        if w == 12:               # juggernaut wave
            jugg += 2
        if w in (10, 15, 20):     # helicopter waves are a bit lighter on the ground
            rif = max(4, rif - 3)
        waves[str(w)] = dict(Riflemen=rif, Rushers=rush, Dogs=dogs, Juggernauts=jugg, Helicopters=heli,
                             HealthMultiplier=round(1 + 0.05 * (w - 1), 3), DamageMultiplier=round(1 + 0.03 * (w - 1), 3),
                             AccuracyMultiplier=round(1 + 0.02 * (w - 1), 3), MaxAlive=min(6 + w, 24),
                             SpawnInterval=round(max(0.5, 1.6 - 0.05 * w), 2), ClearBonus=250 + 75 * (w - 1))
    return waves


GAME_RULES = {"Default": {}}

SHOP = {
    # Weapons station
    "Buy_Sentinel": dict(DisplayName="Sentinel .45", Description="Heavy pistol. Hits hard, small magazine.", Category="Weapons", Kind="Weapon", WeaponRow="Pistol_Sentinel", Price=500, UnlockWave=1, SortOrder=10),
    "Buy_Viper": dict(DisplayName="Viper SMG", Description="Fast-firing SMG for close quarters.", Category="Weapons", Kind="Weapon", WeaponRow="SMG_Viper", Price=1000, UnlockWave=1, SortOrder=20),
    "Buy_Breacher": dict(DisplayName="Breacher Pump", Description="Pump shotgun. Devastating up close.", Category="Weapons", Kind="Weapon", WeaponRow="Shotgun_Breacher", Price=1250, UnlockWave=2, SortOrder=30),
    "Buy_Kestrel": dict(DisplayName="Kestrel Carbine", Description="All-round assault rifle.", Category="Weapons", Kind="Weapon", WeaponRow="AR_Kestrel", Price=1500, UnlockWave=1, SortOrder=40),
    "Buy_Brigand": dict(DisplayName="Brigand Rifle", Description="Harder-hitting rifle with stronger recoil.", Category="Weapons", Kind="Weapon", WeaponRow="AR_Brigand", Price=1750, UnlockWave=3, SortOrder=50),
    "Buy_Bolt": dict(DisplayName="Bolt-Action Rifle", Description="One shot, one kill. Scoped.", Category="Weapons", Kind="Weapon", WeaponRow="Rifle_Bolt", Price=2000, UnlockWave=3, SortOrder=60),
    "Buy_Ranger": dict(DisplayName="Ranger Battle Rifle", Description="Full-power rifle. Kicks like a mule.", Category="Weapons", Kind="Weapon", WeaponRow="BR_Ranger", Price=2250, UnlockWave=4, SortOrder=70),
    "Buy_Longbow": dict(DisplayName="Longbow Marksman", Description="Semi-auto marksman rifle.", Category="Weapons", Kind="Weapon", WeaponRow="Sniper_Longbow", Price=2500, UnlockWave=5, SortOrder=80),
    "Buy_Hammer": dict(DisplayName="Hammer LMG", Description="100-round belt. Holds a corridor on its own.", Category="Weapons", Kind="Weapon", WeaponRow="LMG_Hammer", Price=3000, UnlockWave=6, SortOrder=90),
    "Buy_Thumper": dict(DisplayName="Thumper Launcher", Description="Rockets. The answer to helicopters and juggernauts.", Category="Weapons", Kind="Weapon", WeaponRow="Launcher_Thumper", Price=3500, UnlockWave=8, SortOrder=100),
    "Buy_Ammo": dict(DisplayName="Refill Ammo", Description="Fills reserve ammo for the weapon in your hands.", Category="Weapons", Kind="Ammo", Price=0, UnlockWave=1, SortOrder=0),
    # Equipment station
    "Buy_Armor": dict(DisplayName="Body Armor", Description="Absorbs most incoming damage until it breaks.", Category="Equipment", Kind="Armor", EquipmentRow="Armor", Price=1000, UnlockWave=2, SortOrder=10),
    "Buy_Frags": dict(DisplayName="Frag Grenades x2", Description="Hold G to cook, release to throw.", Category="Equipment", Kind="FragGrenades", EquipmentRow="Frag", Price=300, UnlockWave=1, Quantity=2, SortOrder=20),
    "Buy_Claymores": dict(DisplayName="Claymores x2", Description="Directional mines. Face them where enemies come from.", Category="Equipment", Kind="Claymores", EquipmentRow="Claymore", Price=500, UnlockWave=2, Quantity=2, SortOrder=30),
    "Buy_Sentry": dict(DisplayName="Sentry Gun", Description="Automated turret. Place it with F.", Category="Equipment", Kind="Sentry", EquipmentRow="Sentry", Price=3000, UnlockWave=5, SortOrder=40),
    # Air support station
    "Buy_Airstrike": dict(DisplayName="Airstrike", Description="Mark a spot. A bombing run walks across it.", Category="AirSupport", Kind="Airstrike", EquipmentRow="Airstrike", Price=3000, UnlockWave=4, SortOrder=10),
    "Buy_Squad": dict(DisplayName="AI Squad", Description="Two soldiers who follow you and fight.", Category="AirSupport", Kind="AISquad", EquipmentRow="AISquad", Price=4000, UnlockWave=6, SortOrder=20),
}

EQUIPMENT = {
    "Frag": dict(DisplayName="Frag Grenade", MaxCarried=4, Damage=260, InnerRadius=180, OuterRadius=650, Trauma=0.7, FuseTime=3.2, ThrowSpeed=1500,
                 Mesh="/Game/Art/Weapons/SM_frag.SM_frag", ExplosionSound=A.format("explosion")),
    "Claymore": dict(DisplayName="Claymore", MaxCarried=4, Damage=320, InnerRadius=150, OuterRadius=550, Trauma=0.6, TriggerRadius=260,
                     TriggerHalfAngle=60, ArmTime=1.2, TriggerDelay=0.2, ExplosionSound=A.format("explosion")),
    "Sentry": dict(DisplayName="Sentry Gun", MaxCarried=1, Lifetime=90, Health=600, Range=3500, TurnSpeed=150, FireConeDeg=4, SpinUpTime=0.4,
                   TurretWeapon="Sentry_Gun", UseSound=A.format("swap")),
    "Airstrike": dict(DisplayName="Airstrike", MaxCarried=2, Damage=600, InnerRadius=300, OuterRadius=900, Trauma=1.0, TraumaRadius=5000,
                      StrikeDelay=3, StrikeExplosions=9, StrikeLength=3200, StrikeInterval=0.11, StrikeScatter=250, SelfDamageScale=1.0,
                      ExplosionSound=A.format("explosion")),
    "AISquad": dict(DisplayName="AI Squad", MaxCarried=1, SquadSize=2, SquadEnemyRow="FriendlySoldier", SquadFollowDistance=500),
    "Armor": dict(DisplayName="Body Armor", MaxCarried=1, ArmorAmount=250),
    "HeliRocket": dict(DisplayName="Helicopter Rocket", Damage=220, InnerRadius=120, OuterRadius=500, Trauma=0.7, SelfDamageScale=0,
                       ExplosionSound=A.format("explosion")),
}

LOOK = {"Default": {}}

ACOUSTICS = {
    "Outdoor": dict(SmallRoomMaxDistance=700, EnclosedMinHitFraction=0.6, ProbeDistance=3000, ProbeInterval=0.25,
                    Density=0.3, Diffusion=0.4, Gain=0.15, GainHF=0.6, DecayTime=0.9, DecayHFRatio=0.5,
                    ReflectionsGain=0.01, ReflectionsDelay=0.05, LateGain=0.6, LateDelay=0.08, ReverbVolume=0.5,
                    EchoDelay=0.42, EchoVolume=0.4, EchoPitch=0.9, ShotVolumeScale=1.0, ShotLowPassHz=20000),
    "SmallRoom": dict(Density=1.0, Diffusion=1.0, Gain=0.45, GainHF=0.85, DecayTime=0.55, DecayHFRatio=0.9,
                      ReflectionsGain=0.9, ReflectionsDelay=0.004, LateGain=1.4, LateDelay=0.008, ReverbVolume=0.9,
                      EchoDelay=0.035, EchoVolume=0.45, EchoPitch=0.97, ShotVolumeScale=1.1, ShotLowPassHz=14000),
    "LargeRoom": dict(Density=0.9, Diffusion=0.9, Gain=0.4, GainHF=0.75, DecayTime=2.4, DecayHFRatio=0.75,
                      ReflectionsGain=0.4, ReflectionsDelay=0.02, LateGain=1.5, LateDelay=0.035, ReverbVolume=0.9,
                      EchoDelay=0.14, EchoVolume=0.55, EchoPitch=0.94, ShotVolumeScale=1.05, ShotLowPassHz=16000),
}


def recoil_curves() -> list[tuple[str, list[float]]]:
    """Yaw bias (degrees) added per shot index 0..30. Shapes the spray so it is learnable."""
    import math
    out = []
    def mk(name, f):
        out.append((name, [round(f(i), 4) for i in range(31)]))
    mk("Recoil.AR", lambda i: 0.12 * math.sin(i * 0.45) + (0.05 if i > 8 else 0.0))
    mk("Recoil.Brigand", lambda i: 0.0 if i < 4 else (0.22 if (i // 6) % 2 == 0 else -0.25))
    mk("Recoil.SMG", lambda i: 0.18 * math.sin(i * 0.9))
    mk("Recoil.LMG", lambda i: -0.1 + 0.15 * math.sin(i * 0.25))
    return out


TABLES = {
    "PlayerFeel": ("FMSPlayerFeelRow", PLAYER_FEEL),
    "Weapons": ("FMSWeaponRow", WEAPONS),
    "Enemies": ("FMSEnemyRow", ENEMIES),
    "AIBehaviour": ("FMSAIBehaviourRow", AI_BEHAVIOUR),
    "Waves": ("FMSWaveRow", make_waves()),
    "GameRules": ("FMSGameRulesRow", GAME_RULES),
    "ShopItems": ("FMSShopItemRow", SHOP),
    "Equipment": ("FMSEquipmentRow", EQUIPMENT),
    "LookFeel": ("FMSLookRow", LOOK),
    "Acoustics": ("FMSAcousticRow", ACOUSTICS),
}


def write_all(schema) -> None:
    DATA.mkdir(exist_ok=True)
    for table, (struct, rows) in TABLES.items():
        fields = schema[struct]
        names = {f[1] for f in fields}
        buf = io.StringIO()
        wr = csv.writer(buf, lineterminator="\n")
        wr.writerow(["---"] + [f[1] for f in fields])
        for row_name, values in rows.items():
            unknown = set(values) - names
            if unknown:
                raise SystemExit(f"{table}.{row_name}: unknown fields {sorted(unknown)}")
            wr.writerow([row_name] + [ue_value(t, values.get(n, d)) for t, n, d in fields])
        (DATA / f"{table}.csv").write_text(buf.getvalue())
        print(f"wrote Data/{table}.csv ({len(rows)} rows, {len(fields)} columns)")
    curves = recoil_curves()
    buf = io.StringIO()
    wr = csv.writer(buf, lineterminator="\n")
    wr.writerow(["---"] + [str(i) for i in range(31)])
    for name, vals in curves:
        wr.writerow([name] + [f"{v:.4f}" for v in vals])
    (DATA / "FeelCurves.csv").write_text(buf.getvalue())
    print(f"wrote Data/FeelCurves.csv ({len(curves)} curves)")


VALUE_CHECKS = {
    "float": re.compile(r"^-?\d+(\.\d+)?$"),
    "int32": re.compile(r"^-?\d+$"),
    "bool": re.compile(r"^(True|False)$"),
    "FVector": re.compile(r"^\(X=-?[\d.]+,Y=-?[\d.]+,Z=-?[\d.]+\)$"),
    "FRotator": re.compile(r"^\(Pitch=-?[\d.]+,Yaw=-?[\d.]+,Roll=-?[\d.]+\)$"),
    "FLinearColor": re.compile(r"^\(R=-?[\d.]+,G=-?[\d.]+,B=-?[\d.]+,A=-?[\d.]+\)$"),
}


def check_all(schema) -> int:
    enums = schema["__enums__"]
    errors = 0
    weapon_rows: set[str] = set()
    enemy_rows: set[str] = set()
    tables_rows: dict[str, list[dict]] = {}
    for table, (struct, _) in TABLES.items():
        path = DATA / f"{table}.csv"
        if not path.exists():
            print(f"ERROR missing {path}")
            errors += 1
            continue
        fields = {n: t for t, n, _ in schema[struct]}
        rows = list(csv.DictReader(path.open()))
        tables_rows[table] = rows
        header = list(rows[0].keys()) if rows else []
        for col in header[1:]:
            if col not in fields:
                print(f"ERROR {table}.csv: column {col} is not a field of {struct}")
                errors += 1
        for name in fields:
            if name not in header:
                print(f"WARN  {table}.csv: field {name} missing (C++ default used)")
        for r in rows:
            rn = r["---"]
            for col, val in r.items():
                t = fields.get(col)
                if t is None:
                    continue
                if t.startswith("EMS"):
                    if val not in enums.get(t, []):
                        print(f"ERROR {table}.{rn}.{col}: '{val}' is not a value of {t} {enums.get(t)}")
                        errors += 1
                elif t in VALUE_CHECKS and not VALUE_CHECKS[t].match(val):
                    print(f"ERROR {table}.{rn}.{col}: '{val}' is not a valid {t}")
                    errors += 1
        if table == "Weapons":
            weapon_rows = {r["---"] for r in rows}
        if table == "Enemies":
            enemy_rows = {r["---"] for r in rows}

    # Cross-references between tables.
    def ref(table, col, valid, allow_none=True):
        nonlocal errors
        for r in tables_rows.get(table, []):
            v = r.get(col, "None")
            if (allow_none and v in ("None", "")) or v in valid:
                continue
            print(f"ERROR {table}.{r['---']}.{col}: '{v}' not found")
            errors += 1
    equipment_rows = {r["---"] for r in tables_rows.get("Equipment", [])}
    behaviour_rows = {r["---"] for r in tables_rows.get("AIBehaviour", [])}
    ref("Enemies", "Weapon", weapon_rows)
    ref("Enemies", "RocketWeapon", weapon_rows)
    ref("Enemies", "BehaviourRow", behaviour_rows, allow_none=False)
    ref("ShopItems", "WeaponRow", weapon_rows)
    ref("ShopItems", "EquipmentRow", equipment_rows)
    ref("Equipment", "TurretWeapon", weapon_rows)
    ref("Equipment", "SquadEnemyRow", enemy_rows)
    for col in ("RiflemanRow", "RusherRow", "DogRow", "JuggernautRow", "HelicopterRow"):
        ref("Waves", col, enemy_rows)
    for col in ("StartingWeapon", "StartingPrimary"):
        ref("GameRules", col, weapon_rows)
    ref("PlayerFeel", "LastStandWeapon", weapon_rows)
    curve_names = set()
    curves_path = DATA / "FeelCurves.csv"
    if curves_path.exists():
        curve_names = {r["---"] for r in csv.DictReader(curves_path.open())}
    ref("Weapons", "RecoilPatternCurve", curve_names)
    # Waves must be 1..N without gaps.
    nums = sorted(int(r["---"]) for r in tables_rows.get("Waves", []))
    if nums != list(range(1, len(nums) + 1)):
        print(f"ERROR Waves.csv rows must be 1..N, got {nums}")
        errors += 1
    for row in ("PlayerFeel", "GameRules", "LookFeel"):
        if not any(r["---"] == "Default" for r in tables_rows.get(row, [])):
            print(f"ERROR {row}.csv needs a 'Default' row")
            errors += 1
    for row in ("Outdoor", "SmallRoom", "LargeRoom"):
        if not any(r["---"] == row for r in tables_rows.get("Acoustics", [])):
            print(f"ERROR Acoustics.csv needs a '{row}' row")
            errors += 1
    print("data check:", "OK" if errors == 0 else f"{errors} error(s)")
    return errors


if __name__ == "__main__":
    schema = parse_structs()
    if "--check" in sys.argv:
        sys.exit(1 if check_all(schema) else 0)
    write_all(schema)
    sys.exit(1 if check_all(schema) else 0)
