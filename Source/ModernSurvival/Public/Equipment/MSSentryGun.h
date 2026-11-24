#pragma once

#include "CoreMinimal.h"
#include "GameFramework/Actor.h"
#include "Combat/MSCombatTypes.h"
#include "Weapons/MSWeaponHolder.h"
#include "MSSentryGun.generated.h"

class UBoxComponent;
class UMSHealthComponent;
class AMSWeapon;

/** Deployable turret: finds the closest visible hostile, turns, spins up and fires. DT_Equipment "Sentry". */
UCLASS()
class MODERNSURVIVAL_API AMSSentryGun : public AActor, public IMSWeaponHolder
{
	GENERATED_BODY()

public:
	AMSSentryGun();
	void Deploy(FName EquipmentRow, AController* InInstigator, EMSTeam InTeam);

	virtual void GetAimRay(FVector& OutStart, FVector& OutDirection) const override;
	virtual EMSTeam GetHolderTeam() const override { return Team; }
	virtual AController* GetHolderController() const override { return InstigatorController; }
	virtual bool HasInfiniteAmmo() const override { return true; }
	virtual float GetExtraSpreadDegrees() const override { return 0.5f; }

	virtual void Tick(float DeltaSeconds) override;
	float GetLifetimeLeft() const { return LifeLeft; }

protected:
	UFUNCTION() void HandleDied(UMSHealthComponent* InHealth, const FMSDamageInfo& KillingBlow);

	UPROPERTY(VisibleAnywhere, Category = "Sentry") TObjectPtr<UBoxComponent> Base;
	UPROPERTY(VisibleAnywhere, Category = "Sentry") TObjectPtr<USceneComponent> Turret;
	UPROPERTY(VisibleAnywhere, Category = "Sentry") TObjectPtr<UMSHealthComponent> Health;
	UPROPERTY(Transient) TObjectPtr<AMSWeapon> Gun;
	UPROPERTY(Transient) TObjectPtr<AController> InstigatorController;

	FName RowName;
	EMSTeam Team = EMSTeam::Player;
	TWeakObjectPtr<AActor> Target;
	float LifeLeft = 90.f;
	float SpinUp = 0.f;
	float TargetTimer = 0.f;
};
