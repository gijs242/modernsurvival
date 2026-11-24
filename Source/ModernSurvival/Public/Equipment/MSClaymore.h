#pragma once

#include "CoreMinimal.h"
#include "GameFramework/Actor.h"
#include "Data/MSDataTypes.h"
#include "MSClaymore.generated.h"

/** Directional mine: arms after a moment, triggers on hostiles in a cone in front. DT_Equipment "Claymore". */
UCLASS()
class MODERNSURVIVAL_API AMSClaymore : public AActor
{
	GENERATED_BODY()

public:
	AMSClaymore();
	void Arm(FName EquipmentRow, AController* InInstigator, EMSTeam InTeam);
	virtual void Tick(float DeltaSeconds) override;

protected:
	void Detonate();

	UPROPERTY(Transient) TObjectPtr<AController> InstigatorController;
	UPROPERTY(Transient) TObjectPtr<class UPointLightComponent> Blink;
	FName RowName;
	EMSTeam Team = EMSTeam::Player;
	float ArmLeft = 1.f;
	float TriggerLeft = -1.f;
	float CheckTimer = 0.f;
	bool bArmed = false;
};
