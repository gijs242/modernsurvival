#pragma once

#include "CoreMinimal.h"
#include "GameFramework/Actor.h"
#include "Weapons/MSWeaponHolder.h"
#include "MSTestActors.generated.h"

class UBoxComponent;
class UMSHealthComponent;

/** Minimal weapon holder for automation tests: aims straight down +X from its location. */
UCLASS(NotPlaceable, Transient, HideDropdown)
class AMSTestWeaponHolder : public AActor, public IMSWeaponHolder
{
	GENERATED_BODY()

public:
	AMSTestWeaponHolder();

	virtual void GetAimRay(FVector& OutStart, FVector& OutDirection) const override
	{
		OutStart = GetActorLocation();
		OutDirection = GetActorForwardVector();
	}
	virtual EMSTeam GetHolderTeam() const override { return EMSTeam::Player; }
	virtual AController* GetHolderController() const override { return nullptr; }
	virtual float GetADSAlpha() const override { return 1.f; }
	virtual void OnWeaponFired(const FMSWeaponRow& Row, int32 ShotIndex) override { ++ShotsFired; }
	virtual void OnWeaponHit(const FMSHitReport& Report) override { ++Hits; }

	int32 ShotsFired = 0;
	int32 Hits = 0;
};

/** A box that blocks bullets and has health (enemy team). */
UCLASS(NotPlaceable, Transient, HideDropdown)
class AMSTestTarget : public AActor
{
	GENERATED_BODY()

public:
	AMSTestTarget();

	UPROPERTY() TObjectPtr<UBoxComponent> Box;
	UPROPERTY() TObjectPtr<UMSHealthComponent> Health;
};
