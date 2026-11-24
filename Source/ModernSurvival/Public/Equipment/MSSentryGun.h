#pragma once

#include "CoreMinimal.h"
#include "GameFramework/Actor.h"
#include "Combat/MSCombatTypes.h"
#include "Weapons/MSWeaponHolder.h"
#include "MSSentryGun.generated.h"

class UBoxComponent;
class UMSHealthComponent;
class AMSWeapon;

/**
 * Deployable turret: finds the closest visible hostile, turns, spins up and fires.
 * DT_Equipment "Sentry". Targeting and firing run on the server; turret aim is replicated.
 */
UCLASS()
class MODERNSURVIVAL_API AMSSentryGun : public AActor, public IMSWeaponHolder
{
	GENERATED_BODY()

public:
	AMSSentryGun();
	/** Server only. */
	void Deploy(FName EquipmentRow, AController* InInstigator, EMSTeam InTeam);

	virtual void GetAimRay(FVector& OutStart, FVector& OutDirection) const override;
	virtual EMSTeam GetHolderTeam() const override { return Team; }
	virtual AController* GetHolderController() const override { return InstigatorController; }
	virtual bool HasInfiniteAmmo() const override { return true; }
	virtual float GetExtraSpreadDegrees() const override { return 0.5f; }

	virtual void Tick(float DeltaSeconds) override;
	virtual void GetLifetimeReplicatedProps(TArray<FLifetimeProperty>& OutLifetimeProps) const override;
	float GetLifetimeLeft() const { return LifeLeft; }

protected:
	UFUNCTION() void HandleDied(UMSHealthComponent* InHealth, const FMSDamageInfo& KillingBlow);
	UFUNCTION() void OnRep_Row() { BuildVisual(); }
	UFUNCTION() void OnRep_Aim();
	void BuildVisual();

	UPROPERTY(VisibleAnywhere, Category = "Sentry") TObjectPtr<UBoxComponent> Base;
	UPROPERTY(VisibleAnywhere, Category = "Sentry") TObjectPtr<USceneComponent> Turret;
	UPROPERTY(VisibleAnywhere, Category = "Sentry") TObjectPtr<UMSHealthComponent> Health;
	UPROPERTY(Transient) TObjectPtr<AMSWeapon> Gun;
	UPROPERTY(Transient) TObjectPtr<AController> InstigatorController;
	UPROPERTY(ReplicatedUsing = OnRep_Row) FName RowName;
	UPROPERTY(ReplicatedUsing = OnRep_Aim) FRotator TurretAim = FRotator::ZeroRotator;

	EMSTeam Team = EMSTeam::Player;
	TWeakObjectPtr<AActor> Target;
	float LifeLeft = 90.f;
	float SpinUp = 0.f;
	float TargetTimer = 0.f;
	bool bVisualBuilt = false;
};
