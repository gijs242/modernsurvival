#pragma once

#include "CoreMinimal.h"
#include "Kismet/BlueprintFunctionLibrary.h"
#include "Combat/MSCombatTypes.h"
#include "MSCombatLibrary.generated.h"

struct FHitResult;
class UPrimitiveComponent;

UCLASS()
class MODERNSURVIVAL_API UMSCombatLibrary : public UBlueprintFunctionLibrary
{
	GENERATED_BODY()

public:
	/** Finds the health component of Target (or its owners) and applies damage + physics impulse. */
	UFUNCTION(BlueprintCallable, Category = "Combat") static FMSHitReport DealDamage(AActor* Target, const FMSDamageInfo& Info, UPrimitiveComponent* HitComponent = nullptr);

	/** Radial damage with line-of-sight, camera trauma for nearby players, sound and FX. */
	UFUNCTION(BlueprintCallable, Category = "Combat", meta = (WorldContext = "WorldContext"))
	static void Explode(const UObject* WorldContext, FVector Location, const FMSExplosionParams& Params, AController* Instigator, AActor* Causer, EMSTeam SourceTeam);

	/** True if the hit is a headshot: a component tagged "Head" or a bone whose name contains "head". */
	static bool IsHeadshot(const FHitResult& Hit);

	/** Bullet damage for one pellet before the target's own modifiers. Pure; unit tested. */
	static float ComputeBulletDamage(const FMSWeaponRow& Weapon, float Distance, bool bHeadshot, float DamageScale);

	UFUNCTION(BlueprintPure, Category = "Combat") static EMSTeam GetTeam(const AActor* Actor);
	UFUNCTION(BlueprintPure, Category = "Combat") static bool AreHostile(const AActor* A, const AActor* B);
};
