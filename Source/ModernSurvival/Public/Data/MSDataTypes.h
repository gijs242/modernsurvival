// DataTable row structs and shared enums.
//
// Every tuning number in the game is a field below. The source of truth is <Project>/Data/<Table>.csv;
// Scripts/setup_project.py imports each CSV into /Game/Data/DT_<Table>. Column names in the CSV are the
// field names here. Feel curves (recoil patterns, falloff shapes) live in Data/FeelCurves.csv as a
// CurveTable and are referenced by row name.

#pragma once

#include "CoreMinimal.h"
#include "Engine/DataTable.h"
#include "MSDataTypes.generated.h"

class UStaticMesh;
class USkeletalMesh;
class USoundBase;
class UNiagaraSystem;
class UAnimInstance;
class UTexture2D;

UENUM(BlueprintType)
enum class EMSTeam : uint8
{
	Player = 0,
	Enemy = 1,
	Neutral = 255
};

UENUM(BlueprintType)
enum class EMSFireMode : uint8
{
	Semi,
	Auto,
	Burst
};

UENUM(BlueprintType)
enum class EMSWeaponClass : uint8
{
	Pistol,
	SMG,
	AssaultRifle,
	Shotgun,
	LMG,
	Sniper,
	Launcher
};

UENUM(BlueprintType)
enum class EMSEnemyArchetype : uint8
{
	Rifleman,
	Rusher,
	Dog,
	Juggernaut,
	Helicopter,
	FriendlySoldier
};

UENUM(BlueprintType)
enum class EMSDamageKind : uint8
{
	Bullet,
	Explosive,
	Melee,
	Fall
};

UENUM(BlueprintType)
enum class EMSShopCategory : uint8
{
	Weapons,
	Equipment,
	AirSupport
};

UENUM(BlueprintType)
enum class EMSShopItemKind : uint8
{
	Weapon,
	Ammo,
	Armor,
	FragGrenades,
	Claymores,
	Sentry,
	Airstrike,
	AISquad
};

// ------------------------------------------------------------------------------------------------
// Player movement, health and first-person feel. One row: "Default".
USTRUCT(BlueprintType)
struct MODERNSURVIVAL_API FMSPlayerFeelRow : public FTableRowBase
{
	GENERATED_BODY()

	// Health ------------------------------------------------------------------
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Health") float MaxHealth = 100.f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Health") float RegenDelay = 4.f;          // s after last hit
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Health") float RegenRate = 45.f;          // hp/s
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Health") float ArmorAbsorb = 0.8f;        // share of damage armor soaks
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Health") float FallDamageMinSpeed = 1100.f; // cm/s
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Health") float FallDamagePerSpeed = 0.12f;

	// Last stand --------------------------------------------------------------
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "LastStand") int32 LastStandsPerGame = 1;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "LastStand") float LastStandDuration = 10.f;     // survive this long to get up
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "LastStand") float LastStandHealth = 80.f;       // downed health pool
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "LastStand") float LastStandReviveHealth = 50.f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "LastStand") float LastStandMoveSpeed = 80.f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "LastStand") float LastStandEyeHeight = 40.f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "LastStand") float LastStandInvulnerableTime = 1.5f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "LastStand") FName LastStandWeapon = "Pistol_P9";

	// Movement (cm, cm/s) -----------------------------------------------------
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Movement") float WalkSpeed = 420.f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Movement") float SprintSpeed = 640.f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Movement") float CrouchSpeed = 210.f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Movement") float ADSSpeedMultiplier = 0.6f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Movement") float Acceleration = 3200.f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Movement") float BrakingDeceleration = 2600.f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Movement") float GroundFriction = 8.f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Movement") float JumpZVelocity = 390.f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Movement") float AirControl = 0.25f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Movement") float CapsuleRadius = 34.f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Movement") float CapsuleHalfHeight = 90.f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Movement") float CrouchedHalfHeight = 56.f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Movement") float StandEyeHeight = 70.f;     // above capsule centre
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Movement") float CrouchEyeHeight = 34.f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Movement") float EyeHeightInterpSpeed = 12.f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Movement") float SprintMinForwardInput = 0.5f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Movement") float SprintToFireTime = 0.18f;  // s before you can shoot after sprint

	// Slide -------------------------------------------------------------------
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Slide") float SlideMinSpeed = 520.f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Slide") float SlideBoost = 260.f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Slide") float SlideMaxSpeed = 950.f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Slide") float SlideDuration = 0.85f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Slide") float SlideGroundFriction = 0.6f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Slide") float SlideBraking = 350.f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Slide") float SlideCooldown = 0.6f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Slide") float SlideCameraRoll = 6.f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Slide") float SlideFOVAdd = 6.f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Slide") float SlideTrauma = 0.12f;

	// Camera -------------------------------------------------------------------
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Camera") float BaseFOV = 90.f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Camera") float SprintFOVAdd = 5.f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Camera") float FOVInterpSpeed = 10.f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Camera") float LookSensitivity = 1.f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Camera") float ADSSensitivityMultiplier = 0.7f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Camera") float GamepadLookRate = 160.f;      // deg/s at full stick
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Camera") float MouseDegreesPerUnit = 2.5f;   // raw mouse delta -> degrees
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Camera") float ViewModelFOV = 74.f;          // weapon is drawn with its own FOV
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Camera") float ViewModelADSFOV = 58.f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Camera") float ViewModelScale = 0.6f;        // squashes the gun toward the eye so it never clips walls
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Camera") float BobFrequency = 1.9f;          // Hz at walk speed
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Camera") float BobVertical = 0.55f;          // cm
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Camera") float BobHorizontal = 0.35f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Camera") float SprintBobMultiplier = 1.8f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Camera") float ADSBobMultiplier = 0.15f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Camera") float LandingDip = 4.f;             // cm per 1000 cm/s fall speed
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Camera") float StrafeRoll = 0.8f;            // deg at full strafe

	// Weapon sway / view-model motion -----------------------------------------
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Sway") float LookSwayAmount = 0.035f;        // deg of lag per deg/s of look
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Sway") float LookSwayMax = 4.f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Sway") float SwayStiffness = 140.f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Sway") float SwayDamping = 16.f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Sway") float MoveSwayAmount = 1.2f;          // cm at full speed
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Sway") float IdleBreathAmplitude = 0.25f;    // deg
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Sway") float IdleBreathFrequency = 0.35f;    // Hz
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Sway") FVector SprintWeaponOffset = FVector(-4.f, 6.f, -6.f);
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Sway") FRotator SprintWeaponRotation = FRotator(-12.f, 28.f, -10.f);
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Sway") float SprintPoseInterpSpeed = 9.f;

	// Interaction ---------------------------------------------------------------
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Interact") float InteractRange = 230.f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Interact") float MeleeDamage = 150.f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Interact") float MeleeRange = 160.f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Interact") float MeleeCooldown = 0.9f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Interact") float GrenadeCookMax = 3.f;
};

// ------------------------------------------------------------------------------------------------
// Weapons: used by the player, enemies (by row name), turrets and the helicopter.
USTRUCT(BlueprintType)
struct MODERNSURVIVAL_API FMSWeaponRow : public FTableRowBase
{
	GENERATED_BODY()

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "General") FText DisplayName;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "General") EMSWeaponClass WeaponClass = EMSWeaponClass::AssaultRifle;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "General") EMSFireMode FireMode = EMSFireMode::Auto;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "General") float RoundsPerMinute = 750.f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "General") int32 BurstCount = 3;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "General") float EquipTime = 0.45f;

	// Damage --------------------------------------------------------------------
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Damage") float Damage = 30.f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Damage") int32 PelletCount = 1;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Damage") float HeadshotMultiplier = 2.f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Damage") float Range = 15000.f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Damage") float FalloffStart = 2500.f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Damage") float FalloffEnd = 6000.f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Damage") float MinDamageFraction = 0.6f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Damage") float ImpactImpulse = 6000.f;
	// Projectile weapons (launchers) ---------------------------------------------
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Projectile") bool bProjectile = false;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Projectile") float ProjectileSpeed = 6000.f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Projectile") float ProjectileGravityScale = 0.15f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Projectile") float ExplosionRadius = 0.f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Projectile") float ExplosionInnerRadius = 0.f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Projectile") float ExplosionTrauma = 0.f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Projectile") TSoftObjectPtr<USoundBase> ExplosionSound;

	// Ammo ----------------------------------------------------------------------
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Ammo") int32 MagazineSize = 30;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Ammo") int32 MaxReserveAmmo = 210;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Ammo") float ReloadTime = 2.1f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Ammo") float ReloadEmptyTime = 2.6f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Ammo") bool bReloadPerShell = false;    // shotguns
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Ammo") float ReloadPerShellTime = 0.5f;

	// Accuracy (cone half-angle in degrees) -------------------------------------
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Accuracy") float HipSpread = 2.5f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Accuracy") float ADSSpread = 0.15f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Accuracy") float MoveSpreadAdd = 1.5f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Accuracy") float AirSpreadAdd = 4.f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Accuracy") float SpreadPerShot = 0.35f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Accuracy") float SpreadRecovery = 6.f;  // deg/s
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Accuracy") float MaxSpread = 6.f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Accuracy") float PelletSpread = 0.f;   // extra cone for shotguns

	// Recoil (camera, degrees per shot) -----------------------------------------
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Recoil") float RecoilPitchMin = 0.45f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Recoil") float RecoilPitchMax = 0.65f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Recoil") float RecoilYawMin = -0.25f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Recoil") float RecoilYawMax = 0.3f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Recoil") float ADSRecoilMultiplier = 0.75f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Recoil") float RecoilApplySpeed = 30.f;     // how fast the kick reaches the camera (1/s)
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Recoil") float RecoilRecoverySpeed = 9.f;   // deg/s pulled back after firing
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Recoil") float RecoilRecoveryFraction = 0.65f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Recoil") FName RecoilPatternCurve = NAME_None; // FeelCurves row: yaw bias by shot index
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Recoil") float FirstShotRecoilMultiplier = 1.4f;

	// View-model kick (spring) ---------------------------------------------------
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Kick") float KickBack = 2.4f;      // cm
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Kick") float KickUp = 0.4f;        // cm
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Kick") float KickPitch = 2.2f;     // deg
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Kick") float KickRoll = 1.2f;      // deg, random sign
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Kick") float KickStiffness = 260.f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Kick") float KickDamping = 22.f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Kick") float ADSKickMultiplier = 0.55f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Kick") float ShotTrauma = 0.06f;   // camera shake per shot

	// Aim down sights ------------------------------------------------------------
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "ADS") float ADSFOV = 60.f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "ADS") float ADSTime = 0.22f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "ADS") float ADSSwayMultiplier = 0.25f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "ADS") FVector HipOffset = FVector(28.f, 14.f, -16.f);   // weapon pivot vs camera
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "ADS") FVector ADSOffset = FVector(22.f, 0.f, -9.5f);
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "ADS") float SwayMultiplier = 1.f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "ADS") float MoveSpeedMultiplier = 1.f;

	// Shop ------------------------------------------------------------------------
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Shop") int32 AmmoPrice = 200;

	// Art (soft references: empty = placeholder) -----------------------------------
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Art") TSoftObjectPtr<UStaticMesh> Mesh;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Art") FTransform MeshTransform;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Art") FVector MuzzleOffset = FVector(55.f, 0.f, 3.f);
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Art") FVector PlaceholderSize = FVector(60.f, 5.f, 9.f);
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Art") FLinearColor PlaceholderColor = FLinearColor(0.08f, 0.08f, 0.08f);
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Art") TSoftObjectPtr<USoundBase> FireSound;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Art") TSoftObjectPtr<USoundBase> FireSoundFar;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Art") TSoftObjectPtr<USoundBase> ReloadSound;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Art") TSoftObjectPtr<USoundBase> DryFireSound;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Art") TSoftObjectPtr<UNiagaraSystem> MuzzleFlashFX;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Art") TSoftObjectPtr<UNiagaraSystem> TracerFX;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Art") TSoftObjectPtr<UNiagaraSystem> ImpactFX;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Art") float FireSoundVolume = 1.f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Art") float FarSoundDistance = 3000.f; // cm: crossfade dry -> far
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Art") float MuzzleLightIntensity = 40000.f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Art") int32 TracerEveryNth = 3;
};

// ------------------------------------------------------------------------------------------------
// Enemies (and the friendly AI squad, which reuses the same character).
USTRUCT(BlueprintType)
struct MODERNSURVIVAL_API FMSEnemyRow : public FTableRowBase
{
	GENERATED_BODY()

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "General") FText DisplayName;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "General") EMSEnemyArchetype Archetype = EMSEnemyArchetype::Rifleman;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "General") int32 CashReward = 100;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "General") FName BehaviourRow = "Default"; // DT_AIBehaviour row

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Health") float Health = 100.f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Health") float DamageReduction = 0.f;     // 0..1, juggernaut armor
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Health") float HeadshotMultiplierScale = 1.f; // scales the weapon's headshot mult
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Health") float ExplosiveDamageScale = 1.f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Health") bool bFlinches = true;

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Movement") float WalkSpeed = 300.f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Movement") float RunSpeed = 500.f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Movement") float CapsuleRadius = 34.f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Movement") float CapsuleHalfHeight = 90.f;

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Weapon") FName Weapon = "AR_Kestrel";      // DT_Weapons row; None = melee only
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Weapon") float WeaponDamageScale = 0.35f;  // enemy bullets hurt less than yours
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Weapon") float AimErrorDegrees = 3.5f;     // base cone at engage range
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Weapon") float AimErrorMovingTarget = 2.f; // extra when the player moves fast
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Weapon") float FirstShotDelay = 0.6f;      // reaction time after spotting
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Weapon") int32 BurstMin = 3;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Weapon") int32 BurstMax = 6;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Weapon") float BurstPauseMin = 0.5f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Weapon") float BurstPauseMax = 1.1f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Weapon") float EngageRangeMin = 300.f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Weapon") float EngageRangeMax = 4500.f;

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Melee") float MeleeDamage = 0.f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Melee") float MeleeRange = 150.f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Melee") float MeleeCooldown = 1.2f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Melee") float MeleeLunge = 0.f;            // cm/s impulse (dogs)

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Perception") float SightRadius = 6000.f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Perception") float LoseSightRadius = 7000.f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Perception") float PeripheralVisionHalfAngle = 75.f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Perception") float HearingRange = 5000.f;

	// Helicopter only --------------------------------------------------------------------
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Air") float OrbitRadius = 3500.f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Air") float OrbitAltitude = 2500.f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Air") float OrbitSpeed = 900.f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Air") float RocketInterval = 6.f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Air") FName RocketWeapon = "Launcher_Thumper";

	// Art -----------------------------------------------------------------------------------
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Art") TSoftObjectPtr<USkeletalMesh> SkeletalMesh;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Art") TSoftClassPtr<UAnimInstance> AnimClass;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Art") TSoftObjectPtr<UStaticMesh> StaticMesh;     // helicopter body
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Art") FTransform MeshTransform;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Art") FLinearColor PlaceholderColor = FLinearColor(0.25f, 0.27f, 0.2f);
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Art") float PlaceholderScale = 1.f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Art") TSoftObjectPtr<USoundBase> AlertSound;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Art") TSoftObjectPtr<USoundBase> DeathSound;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Art") TSoftObjectPtr<USoundBase> LoopSound;      // helicopter rotor
};

// ------------------------------------------------------------------------------------------------
// AI behaviour knobs shared by archetypes (cover, flanking, EQS). Rows: Default, Rusher, Juggernaut, Dog, Squad
USTRUCT(BlueprintType)
struct MODERNSURVIVAL_API FMSAIBehaviourRow : public FTableRowBase
{
	GENERATED_BODY()

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Cover") bool bUsesCover = true;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Cover") float CoverSearchRadius = 1800.f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Cover") float CoverGridSpacing = 180.f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Cover") float CoverCrouchHeight = 90.f;   // must be hidden at this height
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Cover") float CoverPeekHeight = 155.f;    // and able to shoot at this height (or sideways)
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Cover") float CoverPeekSideOffset = 70.f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Cover") float CoverPreferredDistance = 1600.f; // to the target
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Cover") float CoverMinDistanceToTarget = 600.f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Cover") float CoverAllySpacing = 250.f;   // keep apart from other AI
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Cover") float CoverHoldTimeMin = 2.5f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Cover") float CoverHoldTimeMax = 6.f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Cover") float PeekTimeMin = 1.2f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Cover") float PeekTimeMax = 2.6f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Cover") float HideTimeMin = 0.8f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Cover") float HideTimeMax = 2.f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Cover") float SuppressedDamageThreshold = 25.f; // dmg in 2 s that forces a cover change

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Flank") float FlankChance = 0.3f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Flank") float FlankCooldown = 12.f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Flank") float FlankMinAngle = 60.f;      // vs target's facing
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Flank") float FlankSearchRadius = 2500.f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Flank") int32 MaxSimultaneousFlankers = 2;

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Advance") float AdvanceWhenNoCoverDistance = 1200.f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Advance") float RushStopDistance = 250.f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Advance") float StrafeWhileFiring = 0.5f; // 0..1 chance of side-steps
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Advance") float AcceptanceRadius = 60.f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Advance") float RepathInterval = 0.6f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Advance") float MaxCombatTimeWithoutLOS = 8.f; // then hunt
};

// ------------------------------------------------------------------------------------------------
// Waves. Row name = wave number ("1", "2", ...). Past the last row the endless rules in GameRules apply.
USTRUCT(BlueprintType)
struct MODERNSURVIVAL_API FMSWaveRow : public FTableRowBase
{
	GENERATED_BODY()

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Wave") int32 Riflemen = 6;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Wave") int32 Rushers = 0;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Wave") int32 Dogs = 0;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Wave") int32 Juggernauts = 0;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Wave") int32 Helicopters = 0;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Wave") float HealthMultiplier = 1.f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Wave") float DamageMultiplier = 1.f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Wave") float AccuracyMultiplier = 1.f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Wave") int32 MaxAlive = 10;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Wave") float SpawnInterval = 1.2f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Wave") int32 ClearBonus = 250;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Wave") FName RiflemanRow = "Rifleman";
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Wave") FName RusherRow = "ShotgunRusher";
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Wave") FName DogRow = "AttackDog";
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Wave") FName JuggernautRow = "Juggernaut";
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Wave") FName HelicopterRow = "AttackHelicopter";
};

// ------------------------------------------------------------------------------------------------
// Global game rules. One row: "Default".
USTRUCT(BlueprintType)
struct MODERNSURVIVAL_API FMSGameRulesRow : public FTableRowBase
{
	GENERATED_BODY()

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Flow") float IntermissionTime = 30.f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Flow") float FirstIntermissionTime = 10.f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Flow") float SkipHoldTime = 0.6f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Flow") float GameOverDelay = 2.5f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Flow") float StragglerRevealTime = 45.f; // last few enemies get marked on HUD
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Flow") int32 StragglerCount = 3;

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Cash") int32 StartingCash = 500;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Cash") int32 HeadshotBonus = 50;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Cash") int32 MeleeBonus = 50;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Cash") int32 ExplosiveBonus = 0;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Cash") float CashMultiplier = 1.f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Cash") int32 SkipBonusPerSecond = 10;   // cash for each skipped break second

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Spawning") float SpawnMinDistance = 1500.f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Spawning") float SpawnMaxDistance = 9000.f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Spawning") float SpawnPreferredDistance = 3500.f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Spawning") float SpawnViewMarginDeg = 20.f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Spawning") float SpawnBehindBonus = 0.5f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Spawning") float SpawnPointCooldown = 2.5f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Spawning") float SpawnJitterRadius = 150.f;

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Endless") float CountGrowthPerWave = 0.08f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Endless") float HealthGrowthPerWave = 0.06f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Endless") float DamageGrowthPerWave = 0.03f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Endless") float AccuracyGrowthPerWave = 0.02f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Endless") float MaxHealthMultiplier = 4.f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Endless") float MaxDamageMultiplier = 2.5f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Endless") float MaxAccuracyMultiplier = 1.8f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Endless") int32 MaxAliveCap = 32;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Endless") int32 ClearBonusGrowth = 50;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Endless") int32 HelicopterEveryNWaves = 5;

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "World") int32 MaxCorpses = 20;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "World") float CorpseLifetime = 25.f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "World") FName StartingWeapon = "Pistol_P9";
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "World") FName StartingPrimary = "SMG_Viper";
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "World") int32 StartingFrags = 2;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "World") int32 MaxWeaponsCarried = 2;

	// Co-op ------------------------------------------------------------------------------------
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Coop") float CoopEnemiesPerExtraPlayer = 0.6f;   // +60% enemies per extra player
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Coop") float CoopMaxAlivePerExtraPlayer = 0.4f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Coop") float BleedOutTime = 30.f;               // downed with no revive -> dead
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Coop") float ReviveTime = 3.f;                  // hold Interact on a downed teammate
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Coop") float ReviveRange = 170.f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Coop") bool bRespawnDeadAtIntermission = true;  // dead teammates come back at the next break
};

// ------------------------------------------------------------------------------------------------
// What the three buy stations sell.
USTRUCT(BlueprintType)
struct MODERNSURVIVAL_API FMSShopItemRow : public FTableRowBase
{
	GENERATED_BODY()

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Shop") FText DisplayName;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Shop") FText Description;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Shop") EMSShopCategory Category = EMSShopCategory::Weapons;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Shop") EMSShopItemKind Kind = EMSShopItemKind::Weapon;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Shop") FName WeaponRow = NAME_None;     // Kind = Weapon/Ammo
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Shop") FName EquipmentRow = NAME_None;  // DT_Equipment row
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Shop") int32 Price = 1000;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Shop") int32 UnlockWave = 1;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Shop") int32 Quantity = 1;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Shop") int32 SortOrder = 0;
};

// ------------------------------------------------------------------------------------------------
// Equipment and air support. A wide row: each kind reads the fields that apply to it.
USTRUCT(BlueprintType)
struct MODERNSURVIVAL_API FMSEquipmentRow : public FTableRowBase
{
	GENERATED_BODY()

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "General") FText DisplayName;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "General") int32 MaxCarried = 4;

	// Explosives (frag, claymore, airstrike bombs) ------------------------------
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Explosive") float Damage = 200.f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Explosive") float InnerRadius = 150.f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Explosive") float OuterRadius = 600.f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Explosive") float MinDamageFraction = 0.1f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Explosive") float SelfDamageScale = 0.5f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Explosive") float Trauma = 0.7f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Explosive") float TraumaRadius = 2500.f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Explosive") float Impulse = 120000.f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Explosive") float FuseTime = 3.f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Explosive") float ThrowSpeed = 1500.f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Explosive") float Bounciness = 0.35f;

	// Claymore --------------------------------------------------------------------
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Claymore") float TriggerRadius = 250.f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Claymore") float TriggerHalfAngle = 60.f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Claymore") float ArmTime = 1.f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Claymore") float TriggerDelay = 0.25f;

	// Sentry ----------------------------------------------------------------------
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Sentry") float Lifetime = 90.f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Sentry") float Health = 600.f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Sentry") float Range = 3500.f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Sentry") float TurnSpeed = 140.f;       // deg/s
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Sentry") float FireConeDeg = 4.f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Sentry") float SpinUpTime = 0.5f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Sentry") FName TurretWeapon = "Sentry_Gun";

	// Airstrike -------------------------------------------------------------------
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Airstrike") float StrikeDelay = 3.f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Airstrike") int32 StrikeExplosions = 8;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Airstrike") float StrikeLength = 3000.f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Airstrike") float StrikeInterval = 0.12f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Airstrike") float StrikeScatter = 250.f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Airstrike") float DesignateRange = 15000.f;

	// AI squad --------------------------------------------------------------------
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Squad") int32 SquadSize = 2;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Squad") FName SquadEnemyRow = "FriendlySoldier";
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Squad") float SquadFollowDistance = 500.f;

	// Armor -----------------------------------------------------------------------
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Armor") float ArmorAmount = 250.f;

	// Art -------------------------------------------------------------------------
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Art") TSoftObjectPtr<UStaticMesh> Mesh;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Art") FLinearColor PlaceholderColor = FLinearColor(0.2f, 0.22f, 0.15f);
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Art") TSoftObjectPtr<USoundBase> UseSound;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Art") TSoftObjectPtr<USoundBase> ExplosionSound;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Art") TSoftObjectPtr<UNiagaraSystem> ExplosionFX;
};

// ------------------------------------------------------------------------------------------------
// Look & feel: post-process grade, camera shake, HUD feedback. One row: "Default".
USTRUCT(BlueprintType)
struct MODERNSURVIVAL_API FMSLookRow : public FTableRowBase
{
	GENERATED_BODY()

	// Grade ------------------------------------------------------------------------
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Grade") float Saturation = 0.72f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Grade") float Contrast = 1.18f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Grade") float ShadowsContrast = 1.1f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Grade") float HighlightsGain = 1.04f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Grade") FLinearColor ShadowTint = FLinearColor(0.93f, 0.98f, 1.03f);
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Grade") FLinearColor HighlightTint = FLinearColor(1.03f, 1.0f, 0.95f);
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Grade") float WhiteTemp = 6300.f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Grade") float FilmGrainIntensity = 0.18f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Grade") float FilmGrainShadows = 0.35f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Grade") float VignetteIntensity = 0.45f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Grade") float BloomIntensity = 0.45f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Grade") float ChromaticAberration = 0.15f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Grade") float ExposureBias = 0.f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Grade") float ExposureMinEV = -1.f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Grade") float ExposureMaxEV = 12.f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Grade") float SharpenAmount = 0.6f;     // r.Tonemapper.Sharpen
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Grade") float LowHealthDesaturate = 0.6f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Grade") float LowHealthVignette = 1.1f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Grade") float LowHealthThreshold = 0.45f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Grade") float ADSVignetteAdd = 0.25f;

	// Camera shake (trauma model) --------------------------------------------------
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Shake") float TraumaDecay = 1.4f;        // per second
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Shake") float TraumaExponent = 2.f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Shake") float ShakeMaxPitch = 6.f;       // deg
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Shake") float ShakeMaxYaw = 5.f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Shake") float ShakeMaxRoll = 8.f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Shake") float ShakeMaxOffset = 6.f;      // cm
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Shake") float ShakeFrequency = 18.f;     // Hz
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Shake") float DamageTraumaPerHP = 0.006f;

	// Hitmarkers & crosshair -------------------------------------------------------
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "HUD") float HitmarkerSize = 11.f;      // px at 1080p
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "HUD") float HitmarkerGap = 5.f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "HUD") float HitmarkerThickness = 2.f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "HUD") float HitmarkerDuration = 0.22f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "HUD") float HitmarkerPopScale = 1.6f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "HUD") FLinearColor HitmarkerColor = FLinearColor(1.f, 1.f, 1.f);
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "HUD") FLinearColor HitmarkerKillColor = FLinearColor(1.f, 0.15f, 0.1f);
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "HUD") FLinearColor HitmarkerArmorColor = FLinearColor(0.4f, 0.8f, 1.f);
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "HUD") TSoftObjectPtr<USoundBase> HitmarkerSound;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "HUD") TSoftObjectPtr<USoundBase> KillSound;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "HUD") float HitmarkerVolume = 0.6f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "HUD") float CrosshairSize = 8.f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "HUD") float CrosshairPixelsPerDegree = 9.f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "HUD") float DamageIndicatorDuration = 1.6f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "HUD") float DamageIndicatorRadius = 150.f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "HUD") float DamageIndicatorArcDeg = 26.f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "HUD") float CashPopupDuration = 1.2f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "HUD") float HUDScale = 1.f;
};

// ------------------------------------------------------------------------------------------------
// Acoustics: rows "Outdoor", "SmallRoom", "LargeRoom". Gunshot echo/reverb by room size.
USTRUCT(BlueprintType)
struct MODERNSURVIVAL_API FMSAcousticRow : public FTableRowBase
{
	GENERATED_BODY()

	// Classification thresholds (read from the "Outdoor" row) ---------------------
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Probe") float SmallRoomMaxDistance = 700.f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Probe") float EnclosedMinHitFraction = 0.6f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Probe") float ProbeDistance = 3000.f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Probe") float ProbeInterval = 0.25f;

	// Reverb (UReverbEffect fields) ----------------------------------------------------
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Reverb") float Density = 0.5f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Reverb") float Diffusion = 0.6f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Reverb") float Gain = 0.32f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Reverb") float GainHF = 0.8f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Reverb") float DecayTime = 1.5f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Reverb") float DecayHFRatio = 0.8f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Reverb") float ReflectionsGain = 0.05f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Reverb") float ReflectionsDelay = 0.02f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Reverb") float LateGain = 1.26f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Reverb") float LateDelay = 0.03f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Reverb") float AirAbsorptionGainHF = 0.994f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Reverb") float ReverbVolume = 0.8f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Reverb") float FadeTime = 0.6f;

	// Gunshot echo tail (delayed, filtered repeat of the far sound) --------------------
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Echo") float EchoDelay = 0.18f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Echo") float EchoVolume = 0.35f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Echo") float EchoPitch = 0.92f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Echo") float ShotVolumeScale = 1.f;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Echo") float ShotLowPassHz = 20000.f;
};
