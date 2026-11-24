#pragma once

#include "CoreMinimal.h"
#include "GameFramework/Actor.h"
#include "Data/MSDataTypes.h"
#include "MSAirstrike.generated.h"

/**
 * Bombing run: after StrikeDelay a line of explosions walks across the marked point along the
 * direction the player was facing. DT_Equipment "Airstrike". Placeholder: red marker flare.
 */
UCLASS()
class MODERNSURVIVAL_API AMSAirstrike : public AActor
{
	GENERATED_BODY()

public:
	AMSAirstrike();
	void Begin(FName EquipmentRow, AController* InInstigator, EMSTeam InTeam);
	virtual void Tick(float DeltaSeconds) override;

protected:
	UPROPERTY(Transient) TObjectPtr<AController> InstigatorController;
	UPROPERTY(Transient) TObjectPtr<class UPointLightComponent> Flare;
	FName RowName;
	EMSTeam Team = EMSTeam::Player;
	float DelayLeft = 3.f;
	float NextBomb = 0.f;
	int32 BombsDropped = 0;
	bool bStarted = false;
};
