#include "AI/MSCombatBrainComponent.h"

#include "AI/MSAICharacter.h"
#include "AI/MSEnvQuery.h"
#include "Combat/MSCombatLibrary.h"
#include "Combat/MSCombatSubsystem.h"
#include "Combat/MSHealthComponent.h"
#include "Data/MSDataSubsystem.h"
#include "ModernSurvival.h"
#include "Weapons/MSWeapon.h"
#include "AIController.h"
#include "Engine/World.h"
#include "EnvironmentQuery/EnvQueryManager.h"
#include "GameFramework/CharacterMovementComponent.h"
#include "GameFramework/PlayerController.h"
#include "Navigation/PathFollowingComponent.h"
#include "Perception/AIPerceptionComponent.h"
#include "Perception/AISense_Sight.h"

UMSCombatBrainComponent::UMSCombatBrainComponent()
{
	PrimaryComponentTick.bCanEverTick = true;
}

void UMSCombatBrainComponent::BeginPlay()
{
	Super::BeginPlay();
	if (UMSAISubsystem* AI = UMSAISubsystem::Get(this))
	{
		AI->Register(this);
	}
}

void UMSCombatBrainComponent::EndPlay(const EEndPlayReason::Type Reason)
{
	if (UMSAISubsystem* AI = UMSAISubsystem::Get(this))
	{
		AI->Unregister(this);
	}
	Super::EndPlay(Reason);
}

AAIController* UMSCombatBrainComponent::GetAI() const
{
	return Cast<AAIController>(GetOwner());
}

const FMSAIBehaviourRow& UMSCombatBrainComponent::GetBehaviour() const
{
	const UMSDataSubsystem* Data = UMSDataSubsystem::Get(this);
	static const FMSAIBehaviourRow Defaults;
	if (!Data)
	{
		return Defaults;
	}
	return Data->GetBehaviour(Pawn.IsValid() ? Pawn->GetEnemyRow().BehaviourRow : FName(TEXT("Default")));
}

FVector UMSCombatBrainComponent::GetClaimedLocation() const
{
	if (bMoving && (CurrentActivity == EMSBrainActivity::TakeCover || CurrentActivity == EMSBrainActivity::Flank))
	{
		return MoveDestination;
	}
	return Pawn.IsValid() ? Pawn->GetActorLocation() : FVector::ZeroVector;
}

void UMSCombatBrainComponent::Possess(AMSAICharacter* InPawn)
{
	Pawn = InPawn;
	Target = nullptr;
	CurrentActivity = EMSBrainActivity::None;
	FlankCooldownLeft = FMath::FRandRange(2.f, 6.f);
	ReactionLeft = InPawn ? InPawn->GetEnemyRow().FirstShotDelay : 0.5f;
	if (InPawn && InPawn->GetWeapon())
	{
		WeaponFiredHandle = InPawn->GetWeapon()->OnFired.AddUObject(this, &UMSCombatBrainComponent::OnWeaponFired);
	}
}

void UMSCombatBrainComponent::Release()
{
	if (Pawn.IsValid() && Pawn->GetWeapon())
	{
		Pawn->GetWeapon()->OnFired.Remove(WeaponFiredHandle);
		Pawn->GetWeapon()->SetTriggerHeld(false);
	}
	if (CurrentActivity != EMSBrainActivity::None)
	{
		EndActivity(CurrentActivity);
	}
	Pawn = nullptr;
	CurrentActivity = EMSBrainActivity::None;
}

void UMSCombatBrainComponent::SetFallbackEnabled(bool bEnabled)
{
	bFallback = bEnabled;
}

void UMSCombatBrainComponent::NotifyDamaged(const FMSDamageInfo& Info)
{
	// Getting shot reveals the shooter.
	AActor* Shooter = Info.Instigator ? Info.Instigator->GetPawn() : Info.Causer.Get();
	if (Shooter && UMSCombatLibrary::AreHostile(Pawn.Get(), Shooter))
	{
		if (!Target.IsValid() || !bHasLOS)
		{
			Target = Shooter;
		}
		LastKnownLocation = Shooter->GetActorLocation();
	}
}

void UMSCombatBrainComponent::NotifyHeardNoise(const FVector& Location, AActor* Source)
{
	if (!bHasLOS)
	{
		LastKnownLocation = Location;
		if (!Target.IsValid() && Source && UMSCombatLibrary::AreHostile(Pawn.Get(), Source))
		{
			Target = Source;
		}
	}
}

// ------------------------------------------------------------------------------------------- queries

bool UMSCombatBrainComponent::Query(EMSBrainQuery Q) const
{
	const AMSAICharacter* P = Pawn.Get();
	if (!P)
	{
		return Q == EMSBrainQuery::IsDead;
	}
	const FMSEnemyRow& Row = P->GetEnemyRow();
	switch (Q)
	{
	case EMSBrainQuery::IsDead: return P->IsDead();
	case EMSBrainQuery::HasTarget:
	{
		const UMSHealthComponent* H = UMSHealthComponent::Find(Target.Get());
		return Target.IsValid() && (!H || !H->IsDead());
	}
	case EMSBrainQuery::HasLineOfSight: return bHasLOS;
	case EMSBrainQuery::LostTarget:
		return Query(EMSBrainQuery::HasTarget) && GetBehaviour().bUsesCover && !bHasLOS
			&& GetWorld()->GetTimeSeconds() - LastSeenTime > GetBehaviour().MaxCombatTimeWithoutLOS;
	case EMSBrainQuery::IsMeleeArchetype: return Row.Archetype == EMSEnemyArchetype::Dog || (Row.Weapon.IsNone() && Row.MeleeDamage > 0.f);
	case EMSBrainQuery::IsRusher: return Row.Archetype == EMSEnemyArchetype::Rusher;
	case EMSBrainQuery::UsesCover: return GetBehaviour().bUsesCover;
	case EMSBrainQuery::WantsFlank: return bFlankWanted && Query(EMSBrainQuery::HasTarget);
	case EMSBrainQuery::IsFriendly: return P->GetHolderTeam() == EMSTeam::Player;
	}
	return false;
}

EMSBrainActivity UMSCombatBrainComponent::SelectActivity(bool bIgnoreFlank) const
{
	if (Query(EMSBrainQuery::IsDead)) return EMSBrainActivity::Dead;
	if (!Query(EMSBrainQuery::HasTarget)) return Query(EMSBrainQuery::IsFriendly) ? EMSBrainActivity::Follow : EMSBrainActivity::Hunt;
	if (Query(EMSBrainQuery::LostTarget)) return EMSBrainActivity::Hunt;
	if (Query(EMSBrainQuery::IsMeleeArchetype)) return EMSBrainActivity::Melee;
	if (Query(EMSBrainQuery::IsRusher)) return EMSBrainActivity::Rush;
	if (!Query(EMSBrainQuery::UsesCover)) return EMSBrainActivity::Advance;
	if (!bIgnoreFlank && Query(EMSBrainQuery::WantsFlank)) return EMSBrainActivity::Flank;
	return EMSBrainActivity::TakeCover;
}

int32 UMSCombatBrainComponent::GroupOf(EMSBrainActivity A) const
{
	switch (A)
	{
	case EMSBrainActivity::Dead: return 0;
	case EMSBrainActivity::Hunt:
	case EMSBrainActivity::Follow: return 1;
	case EMSBrainActivity::Melee: return 2;
	case EMSBrainActivity::Rush: return 3;
	case EMSBrainActivity::Advance: return 4;
	case EMSBrainActivity::Flank: return 5;
	case EMSBrainActivity::TakeCover:
	case EMSBrainActivity::HoldCover:
	case EMSBrainActivity::Reposition: return 6;
	default: return 99;
	}
}

const TCHAR* UMSCombatBrainComponent::ActivityName(EMSBrainActivity A)
{
	switch (A)
	{
	case EMSBrainActivity::Dead: return TEXT("Dead");
	case EMSBrainActivity::Hunt: return TEXT("Hunt");
	case EMSBrainActivity::Follow: return TEXT("Follow");
	case EMSBrainActivity::Melee: return TEXT("Melee");
	case EMSBrainActivity::Rush: return TEXT("Rush");
	case EMSBrainActivity::Advance: return TEXT("Advance");
	case EMSBrainActivity::Flank: return TEXT("Flank");
	case EMSBrainActivity::TakeCover: return TEXT("TakeCover");
	case EMSBrainActivity::HoldCover: return TEXT("HoldCover");
	case EMSBrainActivity::Reposition: return TEXT("Reposition");
	default: return TEXT("None");
	}
}

// ------------------------------------------------------------------------------------------- perception

void UMSCombatBrainComponent::UpdateTarget()
{
	AMSAICharacter* P = Pawn.Get();
	AAIController* AI = GetAI();
	UMSCombatSubsystem* Combat = UMSCombatSubsystem::Get(this);
	if (!P || !AI || !Combat || P->IsDead())
	{
		return;
	}
	const EMSTeam Team = P->GetHolderTeam();
	const FVector Eye = P->GetPawnViewLocation();

	// 1) Hostiles AI Perception currently sees.
	TArray<AActor*> Seen;
	if (UAIPerceptionComponent* Perception = AI->GetPerceptionComponent())
	{
		Perception->GetCurrentlyPerceivedActors(UAISense_Sight::StaticClass(), Seen);
	}
	AActor* Best = nullptr;
	float BestDist = TNumericLimits<float>::Max();
	for (AActor* A : Seen)
	{
		const UMSHealthComponent* H = UMSHealthComponent::Find(A);
		if (!H || H->IsDead() || !UMSCombatLibrary::AreHostile(P, A))
		{
			continue;
		}
		// Prefer whoever is closest; keep the current target unless someone is much closer.
		float D = FVector::Dist(Eye, A->GetActorLocation());
		if (A == Target.Get())
		{
			D *= 0.7f;
		}
		if (D < BestDist)
		{
			Best = A;
			BestDist = D;
		}
	}

	// 2) Nobody in sight: wave enemies always know roughly where the player is (they converge on you);
	//    the friendly squad only reacts to what is near.
	if (!Best)
	{
		if (const UMSHealthComponent* Known = UMSHealthComponent::Find(Target.Get()))
		{
			if (!Known->IsDead())
			{
				Best = Target.Get();
			}
		}
	}
	if (!Best)
	{
		const float Range = Team == EMSTeam::Player ? 2500.f : 1000000.f;
		if (UMSHealthComponent* Closest = Combat->FindClosestHostile(Team, Eye, Range, false, P))
		{
			Best = Closest->GetOwner();
			if (Team != EMSTeam::Player)
			{
				// Approximate knowledge: a few metres off so they search, not beeline.
				LastKnownLocation = Best->GetActorLocation() + FVector(FMath::FRandRange(-400.f, 400.f), FMath::FRandRange(-400.f, 400.f), 0.f);
			}
		}
	}
	if (Best != Target.Get())
	{
		ReactionLeft = P->GetEnemyRow().FirstShotDelay;
	}
	Target = Best;
	SetFaceTarget(Target.IsValid() && (bHasLOS || CurrentActivity == EMSBrainActivity::HoldCover));

	// Flank decision, rolled on a cooldown so it doesn't flicker.
	if (FlankCooldownLeft <= 0.f && Target.IsValid())
	{
		const FMSAIBehaviourRow& B = GetBehaviour();
		FlankCooldownLeft = B.FlankCooldown;
		const UMSAISubsystem* AISub = UMSAISubsystem::Get(this);
		bFlankWanted = FMath::FRand() < B.FlankChance && (!AISub || AISub->CountFlankers() < B.MaxSimultaneousFlankers);
	}
}

void UMSCombatBrainComponent::UpdateLineOfSight()
{
	AMSAICharacter* P = Pawn.Get();
	AActor* T = Target.Get();
	if (!P || !T)
	{
		bHasLOS = false;
		return;
	}
	const float Dist = FVector::Dist(P->GetActorLocation(), T->GetActorLocation());
	bHasLOS = Dist <= P->GetEnemyRow().SightRadius && UMSCombatSubsystem::HasLineOfSight(GetWorld(), P->GetPawnViewLocation(), T, P);
	if (bHasLOS)
	{
		LastSeenTime = GetWorld()->GetTimeSeconds();
		LastKnownLocation = T->GetActorLocation();
	}
}

void UMSCombatBrainComponent::SetFaceTarget(bool bFace)
{
	AMSAICharacter* P = Pawn.Get();
	AAIController* AI = GetAI();
	if (!P || !AI)
	{
		return;
	}
	UCharacterMovementComponent* Move = P->GetCharacterMovement();
	if (bFace && Target.IsValid())
	{
		AI->SetFocus(Target.Get());
		Move->bOrientRotationToMovement = false;
		Move->bUseControllerDesiredRotation = true;
	}
	else
	{
		AI->ClearFocus(EAIFocusPriority::Gameplay);
		Move->bOrientRotationToMovement = true;
		Move->bUseControllerDesiredRotation = false;
	}
}

// ------------------------------------------------------------------------------------------- firing

void UMSCombatBrainComponent::AllowFire(float ExtraAimError)
{
	FireAllowedUntil = GetWorld()->GetTimeSeconds() + 0.25;
	ExtraAimErrorThisFrame = ExtraAimError;
}

void UMSCombatBrainComponent::OnWeaponFired()
{
	BurstLeft = FMath::Max(0, BurstLeft - 1);
}

void UMSCombatBrainComponent::UpdateFiring(float Dt)
{
	AMSAICharacter* P = Pawn.Get();
	AMSWeapon* Weapon = P ? P->GetWeapon() : nullptr;
	AActor* T = Target.Get();
	if (!Weapon)
	{
		return;
	}
	auto Release = [&]()
	{
		if (bTriggerDown)
		{
			Weapon->SetTriggerHeld(false);
			bTriggerDown = false;
		}
	};
	const FMSEnemyRow& Row = P->GetEnemyRow();
	const bool bAllowed = GetWorld()->GetTimeSeconds() < FireAllowedUntil;
	if (!T || !bHasLOS || !bAllowed || P->IsDead() || P->GetFlinchTimeLeft() > 0.f)
	{
		Release();
		if (!bHasLOS)
		{
			ReactionLeft = FMath::Max(ReactionLeft, Row.FirstShotDelay * 0.5f);
		}
		return;
	}

	// Aim at the chest, with an error cone that grows with distance and target speed.
	const FVector AimPoint = UMSCombatSubsystem::GetAimPoint(T);
	P->SetAimPoint(AimPoint);
	const float Dist = FVector::Dist(P->GetActorLocation(), AimPoint);
	if (Dist > Row.EngageRangeMax || Dist < Row.EngageRangeMin * 0.25f)
	{
		Release();
		return;
	}
	// Only shoot roughly where we face.
	const FVector ToTarget = (AimPoint - P->GetActorLocation()).GetSafeNormal2D();
	if (FVector::DotProduct(ToTarget, P->GetActorForwardVector().GetSafeNormal2D()) < 0.85f)
	{
		Release();
		return;
	}
	const float TargetSpeed = T->GetVelocity().Size();
	const float Error = (Row.AimErrorDegrees * (0.75f + 0.5f * FMath::Clamp(Dist / FMath::Max(1.f, Row.EngageRangeMax), 0.f, 1.f))
		+ Row.AimErrorMovingTarget * FMath::Clamp(TargetSpeed / 600.f, 0.f, 1.5f)
		+ ExtraAimErrorThisFrame) / P->GetAccuracyMultiplier();
	P->SetAimError(Error);

	if (ReactionLeft > 0.f)
	{
		ReactionLeft -= Dt;
		Release();
		return;
	}
	if (BurstPauseLeft > 0.f)
	{
		BurstPauseLeft -= Dt;
		Release();
		return;
	}
	if (BurstLeft <= 0)
	{
		if (bTriggerDown)
		{
			// Burst finished: pause.
			Release();
			BurstPauseLeft = FMath::FRandRange(Row.BurstPauseMin, Row.BurstPauseMax);
			return;
		}
		BurstLeft = FMath::RandRange(FMath::Max(1, Row.BurstMin), FMath::Max(Row.BurstMin, Row.BurstMax));
	}
	if (Weapon->GetRow().FireMode == EMSFireMode::Semi)
	{
		Weapon->SetTriggerHeld(false);   // pulse: the weapon's own fire rate limits semi-autos
	}
	Weapon->SetTriggerHeld(true);
	bTriggerDown = true;
}

// ------------------------------------------------------------------------------------------- movement

bool UMSCombatBrainComponent::RequestMove(const FVector& Location, float Acceptance)
{
	AAIController* AI = GetAI();
	if (!AI)
	{
		return false;
	}
	MoveDestination = Location;
	const EPathFollowingRequestResult::Type R = AI->MoveToLocation(Location, Acceptance, true, true, true, true, nullptr, true);
	bMoving = R == EPathFollowingRequestResult::RequestSuccessful;
	return R != EPathFollowingRequestResult::Failed;
}

bool UMSCombatBrainComponent::RequestMoveToActor(AActor* Goal, float Acceptance)
{
	AAIController* AI = GetAI();
	if (!AI || !Goal)
	{
		return false;
	}
	MoveDestination = Goal->GetActorLocation();
	const EPathFollowingRequestResult::Type R = AI->MoveToActor(Goal, Acceptance, true, true, true, nullptr, true);
	bMoving = R == EPathFollowingRequestResult::RequestSuccessful;
	return R != EPathFollowingRequestResult::Failed;
}

bool UMSCombatBrainComponent::IsMoveIdle() const
{
	const AAIController* AI = GetAI();
	return !AI || AI->GetMoveStatus() == EPathFollowingStatus::Idle;
}

void UMSCombatBrainComponent::RunQuery(bool bFlank)
{
	UMSAISubsystem* AI = UMSAISubsystem::Get(this);
	UEnvQuery* QueryAsset = AI ? (bFlank ? AI->GetFlankQuery() : AI->GetCoverQuery()) : nullptr;
	if (!QueryAsset || !Pawn.IsValid())
	{
		QueryState = EMSQueryState::Failed;
		return;
	}
	QueryState = EMSQueryState::Waiting;
	++QueryGeneration;
	FEnvQueryRequest Request(QueryAsset, Pawn.Get());
	Request.Execute(EEnvQueryRunMode::SingleResult, this, &UMSCombatBrainComponent::OnQueryFinished);
}

void UMSCombatBrainComponent::OnQueryFinished(TSharedPtr<FEnvQueryResult> Result)
{
	if (QueryState != EMSQueryState::Waiting)
	{
		return;
	}
	if (Result.IsValid() && Result->IsSuccessful() && Result->Items.Num() > 0)
	{
		QueryResult = Result->GetItemAsLocation(0);
		QueryState = EMSQueryState::Done;
	}
	else
	{
		QueryState = EMSQueryState::Failed;
	}
}

EMSActivityResult UMSCombatBrainComponent::TickQueryMove(float Dt, bool bAllowFiring)
{
	const FMSAIBehaviourRow& B = GetBehaviour();
	if (bAllowFiring)
	{
		AllowFire(2.5f);   // moving fire is less accurate
	}
	switch (QueryState)
	{
	case EMSQueryState::Waiting:
		return ActivityTime > 3.f ? EMSActivityResult::Failed : EMSActivityResult::Running;
	case EMSQueryState::Failed:
	case EMSQueryState::Idle:
		return EMSActivityResult::Failed;
	case EMSQueryState::Done:
		if (!bMoving)
		{
			if (FVector::Dist2D(QueryResult, Pawn->GetActorLocation()) <= B.AcceptanceRadius + 30.f)
			{
				return EMSActivityResult::Succeeded;
			}
			if (!RequestMove(QueryResult, B.AcceptanceRadius))
			{
				return EMSActivityResult::Failed;
			}
			if (!bMoving)
			{
				return EMSActivityResult::Succeeded;   // already at goal
			}
		}
		if (IsMoveIdle())
		{
			bMoving = false;
			return FVector::Dist2D(QueryResult, Pawn->GetActorLocation()) <= B.AcceptanceRadius + 80.f
				? EMSActivityResult::Succeeded : EMSActivityResult::Failed;
		}
		return ActivityTime > 15.f ? EMSActivityResult::Failed : EMSActivityResult::Running;
	}
	return EMSActivityResult::Failed;
}

// ------------------------------------------------------------------------------------------- activities

void UMSCombatBrainComponent::BeginActivity(EMSBrainActivity A)
{
	AMSAICharacter* P = Pawn.Get();
	CurrentActivity = A;
	ActivityTime = 0.f;
	RepathTimer = 0.f;
	StrafeTimer = FMath::FRandRange(0.5f, 1.5f);
	bMoving = false;
	QueryState = EMSQueryState::Idle;
	if (!P)
	{
		return;
	}
	const FMSAIBehaviourRow& B = GetBehaviour();
	switch (A)
	{
	case EMSBrainActivity::TakeCover:
		P->SetRunning(true);
		P->SetCoverCrouch(false);
		RunQuery(false);
		break;
	case EMSBrainActivity::Flank:
		P->SetRunning(true);
		P->SetCoverCrouch(false);
		bFlanking = true;
		bFlankWanted = false;
		RunQuery(true);
		break;
	case EMSBrainActivity::HoldCover:
		CoverPoint = P->GetActorLocation();
		HoldLeft = FMath::FRandRange(B.CoverHoldTimeMin, B.CoverHoldTimeMax);
		bPeeking = false;
		PhaseLeft = FMath::FRandRange(B.HideTimeMin, B.HideTimeMax) * 0.5f;
		P->SetCoverCrouch(true);
		SetFaceTarget(true);
		break;
	case EMSBrainActivity::Rush:
	case EMSBrainActivity::Melee:
	case EMSBrainActivity::Hunt:
		P->SetRunning(true);
		P->SetCoverCrouch(false);
		break;
	case EMSBrainActivity::Advance:
	case EMSBrainActivity::Reposition:
	case EMSBrainActivity::Follow:
		P->SetRunning(A == EMSBrainActivity::Follow);
		P->SetCoverCrouch(false);
		break;
	default:
		break;
	}
}

void UMSCombatBrainComponent::EndActivity(EMSBrainActivity A)
{
	if (A == EMSBrainActivity::Flank)
	{
		bFlanking = false;
	}
	if (A == EMSBrainActivity::HoldCover && Pawn.IsValid())
	{
		Pawn->SetCoverCrouch(false);
	}
	QueryState = EMSQueryState::Idle;
	if (CurrentActivity == A)
	{
		CurrentActivity = EMSBrainActivity::None;
	}
}

EMSActivityResult UMSCombatBrainComponent::TickActivity(EMSBrainActivity A, float Dt)
{
	AMSAICharacter* P = Pawn.Get();
	if (!P)
	{
		return EMSActivityResult::Failed;
	}
	CurrentActivity = A;
	if (A == EMSBrainActivity::Dead)
	{
		return EMSActivityResult::Running;
	}
	if (P->IsDead())
	{
		return EMSActivityResult::Failed;
	}
	ActivityTime += Dt;
	RepathTimer -= Dt;
	StrafeTimer -= Dt;

	// Interrupt when something more important came up (or this activity's reason went away).
	const EMSBrainActivity Desired = SelectActivity(true);
	const int32 MyGroup = GroupOf(A);
	const int32 DesiredGroup = GroupOf(Desired);
	if (DesiredGroup < MyGroup || (MyGroup == 1 && DesiredGroup != 1))
	{
		return EMSActivityResult::Succeeded;
	}

	const FMSAIBehaviourRow& B = GetBehaviour();
	const FMSEnemyRow& Row = P->GetEnemyRow();
	AActor* T = Target.Get();
	const float Dist = T ? FVector::Dist2D(P->GetActorLocation(), T->GetActorLocation()) : 0.f;

	switch (A)
	{
	case EMSBrainActivity::TakeCover:
		return TickQueryMove(Dt, true);

	case EMSBrainActivity::Flank:
		return TickQueryMove(Dt, false);

	case EMSBrainActivity::HoldCover:
	{
		HoldLeft -= Dt;
		PhaseLeft -= Dt;
		const UMSHealthComponent* H = P->GetHealth();
		if (H && H->GetRecentDamage(2.f) > B.SuppressedDamageThreshold)
		{
			return EMSActivityResult::Succeeded;   // under fire: move to new cover
		}
		if (HoldLeft <= 0.f)
		{
			return EMSActivityResult::Succeeded;
		}
		if (!bPeeking && PhaseLeft <= 0.f)
		{
			// Peek: stand; if standing still can't see, side-step out.
			bPeeking = true;
			PhaseLeft = FMath::FRandRange(B.PeekTimeMin, B.PeekTimeMax);
			P->SetCoverCrouch(false);
			if (T && !UMSCombatSubsystem::HasLineOfSight(GetWorld(), CoverPoint + FVector(0, 0, B.CoverPeekHeight - 90.f), T, P))
			{
				const FVector Right = FVector::CrossProduct((T->GetActorLocation() - CoverPoint).GetSafeNormal2D(), FVector::UpVector);
				const FVector Left = CoverPoint - Right * B.CoverPeekSideOffset;
				const FVector RightPt = CoverPoint + Right * B.CoverPeekSideOffset;
				const bool bRightClear = UMSCombatSubsystem::HasLineOfSight(GetWorld(), RightPt + FVector(0, 0, 60), T, P);
				RequestMove(bRightClear ? RightPt : Left, 20.f);
			}
		}
		else if (bPeeking && PhaseLeft <= 0.f)
		{
			bPeeking = false;
			PhaseLeft = FMath::FRandRange(B.HideTimeMin, B.HideTimeMax);
			P->SetCoverCrouch(true);
			if (FVector::Dist2D(P->GetActorLocation(), CoverPoint) > 30.f)
			{
				RequestMove(CoverPoint, 15.f);
			}
		}
		if (bPeeking)
		{
			AllowFire();
		}
		return EMSActivityResult::Running;
	}

	case EMSBrainActivity::Rush:
	{
		if (Dist > B.RushStopDistance)
		{
			if (RepathTimer <= 0.f)
			{
				RepathTimer = B.RepathInterval;
				RequestMoveToActor(T, B.RushStopDistance * 0.8f);
			}
		}
		else if (StrafeTimer <= 0.f && FMath::FRand() < B.StrafeWhileFiring)
		{
			StrafeTimer = FMath::FRandRange(0.8f, 1.6f);
			const FVector Side = FVector::CrossProduct((T->GetActorLocation() - P->GetActorLocation()).GetSafeNormal2D(), FVector::UpVector) * (FMath::RandBool() ? 1.f : -1.f);
			RequestMove(P->GetActorLocation() + Side * 250.f, 40.f);
		}
		if (Dist <= Row.EngageRangeMax)
		{
			AllowFire(1.f);
		}
		return EMSActivityResult::Running;
	}

	case EMSBrainActivity::Melee:
	{
		if (RepathTimer <= 0.f)
		{
			RepathTimer = B.RepathInterval;
			RequestMoveToActor(T, 30.f);
		}
		P->TryMelee(T);
		return EMSActivityResult::Running;
	}

	case EMSBrainActivity::Advance:
	case EMSBrainActivity::Reposition:
	{
		const float Stop = FMath::Max(Row.EngageRangeMin, B.RushStopDistance);
		if (Dist > Stop && RepathTimer <= 0.f)
		{
			RepathTimer = B.RepathInterval * 1.5f;
			RequestMoveToActor(T, Stop);
		}
		AllowFire(A == EMSBrainActivity::Advance ? 0.5f : 1.5f);
		if (A == EMSBrainActivity::Reposition && ActivityTime > 3.f)
		{
			return EMSActivityResult::Succeeded;
		}
		return EMSActivityResult::Running;
	}

	case EMSBrainActivity::Hunt:
	{
		if (RepathTimer <= 0.f)
		{
			RepathTimer = 1.5f;
			const FVector Dest = LastKnownLocation.IsNearlyZero() && T ? T->GetActorLocation() : LastKnownLocation;
			if (!Dest.IsNearlyZero())
			{
				RequestMove(Dest, 150.f);
			}
			// Close in on the real position over time.
			if (T)
			{
				LastKnownLocation = FMath::Lerp(LastKnownLocation, T->GetActorLocation(), 0.5f);
			}
		}
		return EMSActivityResult::Running;
	}

	case EMSBrainActivity::Follow:
	{
		const APlayerController* PC = GetWorld()->GetFirstPlayerController();
		APawn* Leader = PC ? PC->GetPawn() : nullptr;
		const float FollowDist = UMSDataSubsystem::Get(this)->GetEquipment(TEXT("AISquad")).SquadFollowDistance;
		if (Leader && RepathTimer <= 0.f)
		{
			RepathTimer = 1.f;
			if (FVector::Dist2D(Leader->GetActorLocation(), P->GetActorLocation()) > FollowDist)
			{
				RequestMoveToActor(Leader, FollowDist * 0.6f);
			}
		}
		return EMSActivityResult::Running;
	}

	default:
		return EMSActivityResult::Failed;
	}
}

// ------------------------------------------------------------------------------------------- tick

void UMSCombatBrainComponent::TickComponent(float DeltaTime, ELevelTick TickType, FActorComponentTickFunction* ThisTickFunction)
{
	Super::TickComponent(DeltaTime, TickType, ThisTickFunction);
	AMSAICharacter* P = Pawn.Get();
	if (!P)
	{
		return;
	}
	FlankCooldownLeft -= DeltaTime;
	TargetTimer -= DeltaTime;
	LOSTimer -= DeltaTime;
	if (TargetTimer <= 0.f)
	{
		TargetTimer = 0.25f + FMath::FRand() * 0.1f;
		UpdateTarget();
	}
	if (LOSTimer <= 0.f)
	{
		LOSTimer = 0.1f;
		UpdateLineOfSight();
	}
	UpdateFiring(DeltaTime);

	if (!bFallback)
	{
		return;
	}
	// C++ fallback that mirrors the StateTree built by the editor module.
	if (CurrentActivity == EMSBrainActivity::None)
	{
		BeginActivity(SelectActivity());
	}
	const EMSBrainActivity Running = CurrentActivity;
	const EMSActivityResult Result = TickActivity(Running, DeltaTime);
	if (Result == EMSActivityResult::Running)
	{
		return;
	}
	EndActivity(Running);
	EMSBrainActivity Next = SelectActivity();
	if (Running == EMSBrainActivity::TakeCover && GroupOf(Next) == 6)
	{
		Next = Result == EMSActivityResult::Succeeded ? EMSBrainActivity::HoldCover : EMSBrainActivity::Reposition;
	}
	BeginActivity(Next);
}
