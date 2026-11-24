#pragma once

#include "CoreMinimal.h"
#include "Components/ActorComponent.h"
#include "Data/MSDataTypes.h"
#include "Combat/MSCombatTypes.h"
#include "MSCombatBrainComponent.generated.h"

class AAIController;
class AMSAICharacter;
struct FEnvQueryResult;

/** Conditions the StateTree asks the brain (see FMSStateTreeCondition_Brain). */
UENUM(BlueprintType)
enum class EMSBrainQuery : uint8
{
	IsDead,
	HasTarget,
	HasLineOfSight,
	LostTarget,        // has a target but hasn't seen it for MaxCombatTimeWithoutLOS (cover users only)
	IsMeleeArchetype,
	IsRusher,
	UsesCover,
	WantsFlank,
	IsFriendly
};

/** One leaf behaviour. Each maps 1:1 to a StateTree task (FMSStateTreeTask_Activity). */
UENUM(BlueprintType)
enum class EMSBrainActivity : uint8
{
	None,
	Dead,
	Hunt,        // move toward the target / last known position
	Follow,      // squad: stay near the player
	Melee,       // dogs: chase and bite
	Rush,        // shotgunners: close the distance, fire up close
	Advance,     // juggernauts: walk at you firing
	Flank,       // EQS flank position, then cover
	TakeCover,   // EQS cover position, move there
	HoldCover,   // hide / peek / shoot cycle
	Reposition   // no cover found: push forward a few seconds, then retry
};

enum class EMSQueryState : uint8
{
	Idle,
	Waiting,
	Done,
	Failed
};

enum class EMSActivityResult : uint8
{
	Running,
	Succeeded,
	Failed
};

/**
 * All AI decision helpers and actions, on the AI controller. The StateTree (built by the editor
 * module from FMSStateTreeTask_Activity / FMSStateTreeCondition_Brain nodes) picks which activity
 * runs; this component does the work. If no StateTree asset is assigned, the same selection runs
 * in C++ (fallback), so the game plays before the asset is built.
 */
UCLASS(ClassGroup = (ModernSurvival), meta = (BlueprintSpawnableComponent))
class MODERNSURVIVAL_API UMSCombatBrainComponent : public UActorComponent
{
	GENERATED_BODY()

public:
	UMSCombatBrainComponent();

	void Possess(AMSAICharacter* InPawn);
	void Release();
	void SetFallbackEnabled(bool bEnabled);
	void NotifyDamaged(const FMSDamageInfo& Info);
	void NotifyHeardNoise(const FVector& Location, AActor* Source);

	UFUNCTION(BlueprintPure, Category = "AI") bool Query(EMSBrainQuery Q) const;
	/** The same priority order as the StateTree. bIgnoreFlank is used for interrupt checks. */
	EMSBrainActivity SelectActivity(bool bIgnoreFlank = false) const;

	void BeginActivity(EMSBrainActivity Activity);
	EMSActivityResult TickActivity(EMSBrainActivity Activity, float DeltaTime);
	void EndActivity(EMSBrainActivity Activity);

	AActor* GetTarget() const { return Target.Get(); }
	const FMSAIBehaviourRow& GetBehaviour() const;
	FVector GetClaimedLocation() const;
	bool IsFlanking() const { return bFlanking; }
	bool IsActiveBrain() const { return Pawn.IsValid(); }
	EMSBrainActivity GetCurrentActivity() const { return CurrentActivity; }
	static const TCHAR* ActivityName(EMSBrainActivity A);

	virtual void TickComponent(float DeltaTime, ELevelTick TickType, FActorComponentTickFunction* ThisTickFunction) override;

protected:
	virtual void BeginPlay() override;
	virtual void EndPlay(const EEndPlayReason::Type Reason) override;

private:
	AAIController* GetAI() const;
	void UpdateTarget();
	void UpdateLineOfSight();
	void UpdateFiring(float Dt);
	void AllowFire(float ExtraAimError = 0.f);
	void SetFaceTarget(bool bFace);

	void RunQuery(bool bFlank);
	void OnQueryFinished(TSharedPtr<FEnvQueryResult> Result);
	bool RequestMove(const FVector& Location, float Acceptance);
	bool RequestMoveToActor(AActor* Goal, float Acceptance);
	bool IsMoveIdle() const;
	void OnWeaponFired();
	int32 GroupOf(EMSBrainActivity A) const;
	EMSActivityResult TickQueryMove(float Dt, bool bAllowFiring);

	TWeakObjectPtr<AMSAICharacter> Pawn;
	TWeakObjectPtr<AActor> Target;
	FVector LastKnownLocation = FVector::ZeroVector;
	double LastSeenTime = -100.0;
	bool bHasLOS = false;
	float TargetTimer = 0.f;
	float LOSTimer = 0.f;

	// Firing
	double FireAllowedUntil = 0.0;
	float ExtraAimErrorThisFrame = 0.f;
	float ReactionLeft = 0.f;
	int32 BurstLeft = 0;
	float BurstPauseLeft = 0.f;
	bool bTriggerDown = false;
	FDelegateHandle WeaponFiredHandle;

	// Activity state
	EMSBrainActivity CurrentActivity = EMSBrainActivity::None;
	bool bFallback = false;
	EMSQueryState QueryState = EMSQueryState::Idle;
	FVector QueryResult = FVector::ZeroVector;
	FVector MoveDestination = FVector::ZeroVector;
	bool bMoving = false;
	float ActivityTime = 0.f;
	float RepathTimer = 0.f;
	float StrafeTimer = 0.f;
	float HoldLeft = 0.f;
	bool bPeeking = false;
	float PhaseLeft = 0.f;
	FVector CoverPoint = FVector::ZeroVector;
	bool bFlanking = false;
	bool bFlankWanted = false;
	float FlankCooldownLeft = 0.f;
	int32 QueryGeneration = 0;
};
