#pragma once

#include "CoreMinimal.h"
#include "Data/MSDataTypes.h"
#include "MSCombatTypes.generated.h"

class AController;
class USoundBase;
class UNiagaraSystem;

USTRUCT(BlueprintType)
struct MODERNSURVIVAL_API FMSDamageInfo
{
	GENERATED_BODY()

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Damage") float Amount = 0.f;
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Damage") EMSDamageKind Kind = EMSDamageKind::Bullet;
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Damage") bool bHeadshot = false;
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Damage") FVector HitLocation = FVector::ZeroVector;
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Damage") FVector SourceLocation = FVector::ZeroVector;
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Damage") FVector ImpulseDirection = FVector::ZeroVector;
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Damage") float Impulse = 0.f;
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Damage") FName HitBone = NAME_None;
	/** Who gets credit (player controller for the player's sentries, claymores and airstrikes too). */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Damage") TObjectPtr<AController> Instigator = nullptr;
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Damage") TObjectPtr<AActor> Causer = nullptr;
	/** Team of whoever dealt the damage (used for friendly-fire checks when the instigator is gone). */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Damage") EMSTeam SourceTeam = EMSTeam::Neutral;
};

/** Result of a damage application, reported back to the shooter for hitmarkers. */
USTRUCT(BlueprintType)
struct MODERNSURVIVAL_API FMSHitReport
{
	GENERATED_BODY()

	UPROPERTY(BlueprintReadOnly, Category = "Damage") bool bHitDamageable = false;
	UPROPERTY(BlueprintReadOnly, Category = "Damage") bool bKilled = false;
	UPROPERTY(BlueprintReadOnly, Category = "Damage") bool bHeadshot = false;
	UPROPERTY(BlueprintReadOnly, Category = "Damage") bool bArmorHit = false;
	UPROPERTY(BlueprintReadOnly, Category = "Damage") float HealthDamage = 0.f;
};

USTRUCT(BlueprintType)
struct MODERNSURVIVAL_API FMSExplosionParams
{
	GENERATED_BODY()

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Explosion") float Damage = 200.f;
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Explosion") float InnerRadius = 150.f;
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Explosion") float OuterRadius = 600.f;
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Explosion") float MinDamageFraction = 0.1f;
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Explosion") float SelfDamageScale = 0.5f;
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Explosion") float Trauma = 0.7f;
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Explosion") float TraumaRadius = 2500.f;
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Explosion") float Impulse = 120000.f;
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Explosion") TObjectPtr<USoundBase> Sound = nullptr;
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Explosion") TObjectPtr<UNiagaraSystem> FX = nullptr;

	static FMSExplosionParams FromEquipment(const FMSEquipmentRow& Row);
	static FMSExplosionParams FromWeapon(const FMSWeaponRow& Row);
};
