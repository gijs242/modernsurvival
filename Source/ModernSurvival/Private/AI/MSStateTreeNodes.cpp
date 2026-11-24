#include "AI/MSStateTreeNodes.h"

#include "AI/MSCombatBrainComponent.h"
#include "GameFramework/Actor.h"
#include "StateTreeExecutionContext.h"

namespace
{
	UMSCombatBrainComponent* BrainFrom(FStateTreeExecutionContext& Context)
	{
		// The StateTree component lives on the AI controller, which owns the brain.
		const AActor* Owner = Cast<AActor>(Context.GetOwner());
		return Owner ? Owner->FindComponentByClass<UMSCombatBrainComponent>() : nullptr;
	}

	EStateTreeRunStatus ToStatus(EMSActivityResult Result)
	{
		switch (Result)
		{
		case EMSActivityResult::Succeeded: return EStateTreeRunStatus::Succeeded;
		case EMSActivityResult::Failed: return EStateTreeRunStatus::Failed;
		default: return EStateTreeRunStatus::Running;
		}
	}
}

EStateTreeRunStatus FMSStateTreeTask_Activity::EnterState(FStateTreeExecutionContext& Context, const FStateTreeTransitionResult& Transition) const
{
	UMSCombatBrainComponent* Brain = BrainFrom(Context);
	if (!Brain)
	{
		return EStateTreeRunStatus::Failed;
	}
	Brain->BeginActivity(Activity);
	return EStateTreeRunStatus::Running;
}

EStateTreeRunStatus FMSStateTreeTask_Activity::Tick(FStateTreeExecutionContext& Context, const float DeltaTime) const
{
	UMSCombatBrainComponent* Brain = BrainFrom(Context);
	return Brain ? ToStatus(Brain->TickActivity(Activity, DeltaTime)) : EStateTreeRunStatus::Failed;
}

void FMSStateTreeTask_Activity::ExitState(FStateTreeExecutionContext& Context, const FStateTreeTransitionResult& Transition) const
{
	if (UMSCombatBrainComponent* Brain = BrainFrom(Context))
	{
		Brain->EndActivity(Activity);
	}
}

bool FMSStateTreeCondition_Brain::TestCondition(FStateTreeExecutionContext& Context) const
{
	const UMSCombatBrainComponent* Brain = BrainFrom(Context);
	const bool bResult = Brain && Brain->Query(Query);
	return bInvertResult ? !bResult : bResult;
}
