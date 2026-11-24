#pragma once

#include "CoreMinimal.h"
#include "GameFramework/Character.h"
#include "Combat/MSCombatTypes.h"
#include "Weapons/MSWeaponHolder.h"
#include "MSAICharacter.generated.h"

class UMSHealthComponent;
class AMSWeapon;
class UAudioComponent;

/**
 * Enemy soldier, rusher, dog, juggernaut, and the friendly squad soldier. Everything comes from a
 * DT_Enemies row. Behaviour lives in AMSAIController (StateTree + UMSCombatBrainComponent).
 *
 * Art: if the row has a SkeletalMesh (+ AnimClass, e.g. retargeted from the Game Animation Sample)
 * it is used and the bone named "head" counts for headshots; otherwise a placeholder body is built
 * from basic shapes with a "Head"-tagged sphere.
 */
UCLASS()
class MODERNSURVIVAL_API AMSAICharacter : public ACharacter, public IMSWeaponHolder
{
	GENERATED_BODY()

public:
	AMSAICharacter(const FObjectInitializer& ObjectInitializer);

	/** Call right after spawning (before or after possession). */
	UFUNCTION(BlueprintCallable, Category = "AI") void InitFromRow(FName InEnemyRow, float HealthMultiplier, float DamageMultiplier, float AccuracyMultiplier, EMSTeam InTeam);

	// --- IMSWeaponHolder
	virtual void GetAimRay(FVector& OutStart, FVector& OutDirection) const override;
	virtual EMSTeam GetHolderTeam() const override { return Team; }
	virtual AController* GetHolderController() const override { return GetController(); }
	virtual float GetWeaponDamageScale() const override;
	virtual float GetExtraSpreadDegrees() const override { return CurrentAimError; }
	virtual bool HasInfiniteAmmo() const override { return true; }
	virtual float GetMoveSpreadFraction() const override;

	// --- Used by the brain
	void SetAimPoint(const FVector& Point) { AimPoint = Point; }
	void SetAimError(float Degrees) { CurrentAimError = Degrees; }
	void SetRunning(bool bRun);
	void SetCoverCrouch(bool bCrouch);
	bool TryMelee(AActor* Target);
	AMSWeapon* GetWeapon() const { return Weapon; }
	const FMSEnemyRow& GetEnemyRow() const { return EnemyRow; }
	FName GetEnemyRowName() const { return EnemyRowName; }
	EMSEnemyArchetype GetArchetype() const { return EnemyRow.Archetype; }
	float GetAccuracyMultiplier() const { return AccuracyMultiplier; }
	UMSHealthComponent* GetHealth() const { return Health; }
	bool IsDead() const;
	float GetFlinchTimeLeft() const { return FlinchTimeLeft; }

	virtual void Tick(float DeltaSeconds) override;
	virtual FVector GetPawnViewLocation() const override;
	virtual void GetLifetimeReplicatedProps(TArray<FLifetimeProperty>& OutLifetimeProps) const override;
	virtual void OnStartCrouch(float HalfHeightAdjust, float ScaledHalfHeightAdjust) override;
	virtual void OnEndCrouch(float HalfHeightAdjust, float ScaledHalfHeightAdjust) override;

protected:
	virtual void BeginPlay() override;
	virtual void EndPlay(const EEndPlayReason::Type Reason) override;
	void BuildVisual();
	/** Row-driven setup that every machine does (clients via OnRep_EnemyRow). */
	void ApplyRowLocally();
	UFUNCTION() void OnRep_EnemyRow();
	void BuildPlaceholderHumanoid(float Scale, bool bHeavy);
	void BuildPlaceholderDog();
	void SetupHitbox(UPrimitiveComponent* Comp, bool bHead);

	UFUNCTION() void HandleDamaged(UMSHealthComponent* InHealth, const FMSDamageInfo& Info, float HealthDamage, float ArmorDamage);
	UFUNCTION() void HandleDied(UMSHealthComponent* InHealth, const FMSDamageInfo& KillingBlow);

	UPROPERTY(VisibleAnywhere, BlueprintReadOnly, Category = "Components") TObjectPtr<UMSHealthComponent> Health;
	UPROPERTY(VisibleAnywhere, BlueprintReadOnly, Category = "Components") TObjectPtr<USceneComponent> WeaponAnchor;
	UPROPERTY(Transient) TObjectPtr<AMSWeapon> Weapon;
	UPROPERTY(Transient) TArray<TObjectPtr<UPrimitiveComponent>> PlaceholderParts;
	UPROPERTY(Transient) TObjectPtr<UPrimitiveComponent> PlaceholderTorso;
	UPROPERTY(Transient) TObjectPtr<UAudioComponent> LoopAudio;

	UPROPERTY(ReplicatedUsing = OnRep_EnemyRow) FName EnemyRowName;
	FMSEnemyRow EnemyRow;
	UPROPERTY(Replicated) EMSTeam Team = EMSTeam::Enemy;
	float DamageMultiplier = 1.f;
	float AccuracyMultiplier = 1.f;
	FVector AimPoint = FVector::ZeroVector;
	float CurrentAimError = 3.f;
	float MeleeCooldownLeft = 0.f;
	float FlinchTimeLeft = 0.f;
	bool bInitialized = false;
	bool bPlaceholder = true;
};
