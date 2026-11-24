#pragma once

#include "CoreMinimal.h"
#include "EnvironmentQuery/EnvQueryGenerator.h"
#include "EnvironmentQuery/EnvQueryTest.h"
#include "Subsystems/WorldSubsystem.h"
#include "MSEnvQuery.generated.h"

class UEnvQuery;
class UMSCombatBrainComponent;

/**
 * EQS generator: candidate positions on the navmesh.
 * - Cover mode: a grid around the querier (radius/spacing from the AI behaviour row).
 * - Flank mode: a ring around the target at the preferred engagement distance.
 */
UCLASS(meta = (DisplayName = "MS Cover/Flank Candidates"))
class MODERNSURVIVAL_API UMSEnvQueryGenerator_Candidates : public UEnvQueryGenerator
{
	GENERATED_BODY()

public:
	UMSEnvQueryGenerator_Candidates(const FObjectInitializer& ObjectInitializer);
	virtual void GenerateItems(FEnvQueryInstance& QueryInstance) const override;

	UPROPERTY(EditDefaultsOnly, Category = "Generator") bool bFlank = false;
};

/**
 * EQS test that scores a candidate as cover against the querier's current target:
 * hidden at crouch height (trace from the target's eyes is blocked), able to shoot from standing
 * height or a side step, near the preferred distance, away from other AI, and (flank mode) off to
 * the side of / behind where the target is looking. Fails points with no protection at all.
 */
UCLASS(meta = (DisplayName = "MS Cover Quality"))
class MODERNSURVIVAL_API UMSEnvQueryTest_Cover : public UEnvQueryTest
{
	GENERATED_BODY()

public:
	UMSEnvQueryTest_Cover(const FObjectInitializer& ObjectInitializer);
	virtual void RunTest(FEnvQueryInstance& QueryInstance) const override;

	UPROPERTY(EditDefaultsOnly, Category = "Test") bool bFlankMode = false;

	/** Pure scoring used by the test (and unit tests). */
	static float ScoreCandidate(bool bHiddenLow, bool bCanPeek, float DistToTarget, float PreferredDist, float MinDist, float AllyCrowding, float FlankAngleDeg, float FlankMinAngle, bool bFlankMode);
};

/**
 * Owns the runtime-built EQS query templates (or uses assets from Project Settings if provided),
 * the cover claims so two soldiers don't pick the same spot, and the flanker count.
 */
UCLASS()
class MODERNSURVIVAL_API UMSAISubsystem : public UWorldSubsystem
{
	GENERATED_BODY()

public:
	static UMSAISubsystem* Get(const UObject* WorldContext);

	UEnvQuery* GetCoverQuery();
	UEnvQuery* GetFlankQuery();

	void Register(UMSCombatBrainComponent* Brain) { Brains.AddUnique(Brain); }
	void Unregister(UMSCombatBrainComponent* Brain) { Brains.Remove(Brain); }
	/** Positions claimed by other brains (cover destinations and current positions). */
	void GetClaimedLocations(const UMSCombatBrainComponent* Except, TArray<FVector>& Out) const;
	int32 CountFlankers() const;

private:
	UEnvQuery* BuildQuery(FName Name, bool bFlank);

	UPROPERTY(Transient) TObjectPtr<UEnvQuery> CoverQuery;
	UPROPERTY(Transient) TObjectPtr<UEnvQuery> FlankQuery;
	UPROPERTY(Transient) TArray<TObjectPtr<UMSCombatBrainComponent>> Brains;
};
