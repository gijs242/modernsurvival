#pragma once

#include "CoreMinimal.h"
#include "StateTreeTaskBase.h"
#include "StateTreeConditionBase.h"
#include "AI/MSCombatBrainComponent.h"
#include "MSStateTreeNodes.generated.h"

/** No per-instance data: all state lives in UMSCombatBrainComponent on the AI controller. */
USTRUCT()
struct MODERNSURVIVAL_API FMSStateTreeEmptyInstanceData
{
	GENERATED_BODY()
};

/**
 * Runs one brain activity (take cover, hold cover, flank, rush, melee, advance, hunt, follow)
 * while the state is active. Succeeds when the activity completes or something more important
 * comes up, so the tree re-selects.
 */
USTRUCT(meta = (DisplayName = "MS Activity", Category = "Modern Survival"))
struct MODERNSURVIVAL_API FMSStateTreeTask_Activity : public FStateTreeTaskCommonBase
{
	GENERATED_BODY()

	using FInstanceDataType = FMSStateTreeEmptyInstanceData;

	virtual const UStruct* GetInstanceDataType() const override { return FInstanceDataType::StaticStruct(); }
	virtual EStateTreeRunStatus EnterState(FStateTreeExecutionContext& Context, const FStateTreeTransitionResult& Transition) const override;
	virtual EStateTreeRunStatus Tick(FStateTreeExecutionContext& Context, const float DeltaTime) const override;
	virtual void ExitState(FStateTreeExecutionContext& Context, const FStateTreeTransitionResult& Transition) const override;

	UPROPERTY(EditAnywhere, Category = "Parameter") EMSBrainActivity Activity = EMSBrainActivity::Hunt;
};

/** Asks the brain a yes/no question (has target, uses cover, wants flank, ...). */
USTRUCT(meta = (DisplayName = "MS Brain Query", Category = "Modern Survival"))
struct MODERNSURVIVAL_API FMSStateTreeCondition_Brain : public FStateTreeConditionCommonBase
{
	GENERATED_BODY()

	using FInstanceDataType = FMSStateTreeEmptyInstanceData;

	virtual const UStruct* GetInstanceDataType() const override { return FInstanceDataType::StaticStruct(); }
	virtual bool TestCondition(FStateTreeExecutionContext& Context) const override;

	UPROPERTY(EditAnywhere, Category = "Parameter") EMSBrainQuery Query = EMSBrainQuery::HasTarget;
	UPROPERTY(EditAnywhere, Category = "Parameter") bool bInvertResult = false;
};
