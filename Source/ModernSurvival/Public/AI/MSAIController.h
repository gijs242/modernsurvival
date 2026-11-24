#pragma once

#include "CoreMinimal.h"
#include "AIController.h"
#include "Perception/AIPerceptionTypes.h"
#include "Combat/MSCombatTypes.h"
#include "MSAIController.generated.h"

class UAIPerceptionComponent;
class UAISenseConfig_Sight;
class UAISenseConfig_Hearing;
class UAISenseConfig_Damage;
class UStateTreeAIComponent;
class UMSCombatBrainComponent;

/**
 * AI Perception (sight, hearing, damage) + StateTree (asset from Project Settings, built by the
 * editor module) + the combat brain that does the actual work. Perception ranges come from the
 * pawn's DT_Enemies row.
 */
UCLASS()
class MODERNSURVIVAL_API AMSAIController : public AAIController
{
	GENERATED_BODY()

public:
	AMSAIController(const FObjectInitializer& ObjectInitializer);

	void ConfigureFromPawn();
	void NotifyDamaged(const FMSDamageInfo& Info);
	void OnPawnDied();
	UMSCombatBrainComponent* GetBrain() const { return Brain; }
	bool IsUsingStateTree() const { return bUsingStateTree; }

	virtual FGenericTeamId GetGenericTeamId() const override;
	virtual ETeamAttitude::Type GetTeamAttitudeTowards(const AActor& Other) const override;

protected:
	virtual void OnPossess(APawn* InPawn) override;
	virtual void OnUnPossess() override;

	UFUNCTION() void HandlePerception(AActor* Actor, FAIStimulus Stimulus);

	UPROPERTY(VisibleAnywhere, Category = "AI") TObjectPtr<UAIPerceptionComponent> Perception;
	UPROPERTY(VisibleAnywhere, Category = "AI") TObjectPtr<UAISenseConfig_Sight> SightConfig;
	UPROPERTY(VisibleAnywhere, Category = "AI") TObjectPtr<UAISenseConfig_Hearing> HearingConfig;
	UPROPERTY(VisibleAnywhere, Category = "AI") TObjectPtr<UAISenseConfig_Damage> DamageConfig;
	UPROPERTY(VisibleAnywhere, Category = "AI") TObjectPtr<UStateTreeAIComponent> StateTree;
	UPROPERTY(VisibleAnywhere, Category = "AI") TObjectPtr<UMSCombatBrainComponent> Brain;

	bool bUsingStateTree = false;
};
