#pragma once

#include "CoreMinimal.h"
#include "UObject/Interface.h"
#include "Combat/MSCombatTypes.h"
#include "MSWeaponHolder.generated.h"

UINTERFACE(MinimalAPI, meta = (CannotImplementInterfaceInBlueprint))
class UMSWeaponHolder : public UInterface
{
	GENERATED_BODY()
};

/** Anything that carries an AMSWeapon: the player, AI soldiers, the sentry and the helicopter. */
class MODERNSURVIVAL_API IMSWeaponHolder
{
	GENERATED_BODY()

public:
	/** Where shots come from and where they go (camera for the player, eyes->target for AI). */
	virtual void GetAimRay(FVector& OutStart, FVector& OutDirection) const = 0;
	virtual EMSTeam GetHolderTeam() const = 0;
	virtual AController* GetHolderController() const = 0;

	virtual float GetADSAlpha() const { return 0.f; }
	virtual float GetMoveSpreadFraction() const { return 0.f; }
	virtual bool IsAirborne() const { return false; }
	virtual float GetWeaponDamageScale() const { return 1.f; }
	/** Additional cone (degrees) on top of the weapon spread: AI aim error. */
	virtual float GetExtraSpreadDegrees() const { return 0.f; }
	virtual bool IsLocalPlayerHolder() const { return false; }
	virtual bool HasInfiniteAmmo() const { return false; }

	virtual void OnWeaponFired(const FMSWeaponRow& Row, int32 ShotIndex) {}
	virtual void OnWeaponHit(const FMSHitReport& Report) {}
};
