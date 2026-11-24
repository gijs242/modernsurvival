#include "Combat/MSCombatSubsystem.h"

#include "Combat/MSHealthComponent.h"
#include "CollisionQueryParams.h"
#include "Engine/World.h"
#include "GameFramework/Pawn.h"

UMSCombatSubsystem* UMSCombatSubsystem::Get(const UObject* WorldContext)
{
	const UWorld* World = WorldContext ? WorldContext->GetWorld() : nullptr;
	return World ? World->GetSubsystem<UMSCombatSubsystem>() : nullptr;
}

void UMSCombatSubsystem::Register(UMSHealthComponent* Health)
{
	if (Health)
	{
		Combatants.AddUnique(Health);
	}
}

void UMSCombatSubsystem::Unregister(UMSHealthComponent* Health)
{
	Combatants.Remove(Health);
}

static bool AreHostile(EMSTeam A, EMSTeam B)
{
	return A != B && A != EMSTeam::Neutral && B != EMSTeam::Neutral;
}

TArray<UMSHealthComponent*> UMSCombatSubsystem::GetHostiles(EMSTeam Team) const
{
	TArray<UMSHealthComponent*> Out;
	for (UMSHealthComponent* H : Combatants)
	{
		if (IsValid(H) && !H->IsDead() && AreHostile(Team, H->GetTeam()))
		{
			Out.Add(H);
		}
	}
	return Out;
}

TArray<UMSHealthComponent*> UMSCombatSubsystem::GetAllies(EMSTeam Team) const
{
	TArray<UMSHealthComponent*> Out;
	for (UMSHealthComponent* H : Combatants)
	{
		if (IsValid(H) && !H->IsDead() && H->GetTeam() == Team)
		{
			Out.Add(H);
		}
	}
	return Out;
}

FVector UMSCombatSubsystem::GetAimPoint(const AActor* Target)
{
	if (!Target)
	{
		return FVector::ZeroVector;
	}
	if (const APawn* Pawn = Cast<APawn>(Target))
	{
		// Aim at the chest: between centre and eyes.
		return FMath::Lerp(Pawn->GetActorLocation(), Pawn->GetPawnViewLocation(), 0.6f);
	}
	return Target->GetActorLocation();
}

bool UMSCombatSubsystem::HasLineOfSight(const UWorld* World, const FVector& From, const AActor* Target, const AActor* Ignore)
{
	if (!World || !Target)
	{
		return false;
	}
	FCollisionQueryParams Params(SCENE_QUERY_STAT(MSLineOfSight), false, Ignore);
	Params.AddIgnoredActor(Target);
	if (Ignore)
	{
		TArray<AActor*> Attached;
		Ignore->GetAttachedActors(Attached);
		Params.AddIgnoredActors(Attached);
	}
	TArray<AActor*> TargetAttached;
	Target->GetAttachedActors(TargetAttached);
	Params.AddIgnoredActors(TargetAttached);
	// Two rays (chest, head) so a target behind a low wall is still visible.
	const FVector Chest = GetAimPoint(Target);
	const APawn* Pawn = Cast<APawn>(Target);
	const FVector Head = Pawn ? Pawn->GetPawnViewLocation() : Chest;
	return !World->LineTraceTestByChannel(From, Chest, ECC_Visibility, Params)
		|| !World->LineTraceTestByChannel(From, Head, ECC_Visibility, Params);
}

UMSHealthComponent* UMSCombatSubsystem::FindClosestHostile(EMSTeam Team, const FVector& Eye, float Range, bool bRequireLOS, const AActor* Ignore) const
{
	UMSHealthComponent* Best = nullptr;
	float BestDistSq = Range * Range;
	for (UMSHealthComponent* H : GetHostiles(Team))
	{
		const AActor* Owner = H->GetOwner();
		const float DistSq = FVector::DistSquared(Eye, GetAimPoint(Owner));
		if (DistSq >= BestDistSq)
		{
			continue;
		}
		if (bRequireLOS && !HasLineOfSight(GetWorld(), Eye, Owner, Ignore))
		{
			continue;
		}
		Best = H;
		BestDistSq = DistSq;
	}
	return Best;
}
