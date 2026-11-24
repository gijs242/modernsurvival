#pragma once

#include "CoreMinimal.h"
#include "Subsystems/WorldSubsystem.h"
#include "Data/MSDataTypes.h"
#include "MSCombatSubsystem.generated.h"

class UMSHealthComponent;

/**
 * Registry of everything with health in the world. Sentries, the AI squad, EQS tests and the HUD
 * use it instead of iterating all actors.
 */
UCLASS()
class MODERNSURVIVAL_API UMSCombatSubsystem : public UWorldSubsystem
{
	GENERATED_BODY()

public:
	static UMSCombatSubsystem* Get(const UObject* WorldContext);

	void Register(UMSHealthComponent* Health);
	void Unregister(UMSHealthComponent* Health);

	/** Living combatants hostile to Team. */
	TArray<UMSHealthComponent*> GetHostiles(EMSTeam Team) const;
	TArray<UMSHealthComponent*> GetAllies(EMSTeam Team) const;

	/** Closest living hostile within Range, optionally requiring a clear line of sight from Eye. */
	UMSHealthComponent* FindClosestHostile(EMSTeam Team, const FVector& Eye, float Range, bool bRequireLOS, const AActor* Ignore) const;

	static bool HasLineOfSight(const UWorld* World, const FVector& From, const AActor* Target, const AActor* Ignore);
	static FVector GetAimPoint(const AActor* Target);

private:
	UPROPERTY(Transient) TArray<TObjectPtr<UMSHealthComponent>> Combatants;
};
