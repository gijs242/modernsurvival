#pragma once

#include "CoreMinimal.h"
#include "GameFramework/Actor.h"
#include "Data/MSDataTypes.h"
#include "MSClaymore.generated.h"

class UPointLightComponent;

/** Directional mine: arms after a moment, triggers on hostiles in a cone in front. DT_Equipment "Claymore". Server logic, replicated. */
UCLASS()
class MODERNSURVIVAL_API AMSClaymore : public AActor
{
	GENERATED_BODY()

public:
	AMSClaymore();
	/** Server only. */
	void Arm(FName EquipmentRow, AController* InInstigator, EMSTeam InTeam);
	virtual void Tick(float DeltaSeconds) override;
	virtual void GetLifetimeReplicatedProps(TArray<FLifetimeProperty>& OutLifetimeProps) const override;

protected:
	void Detonate();
	void BuildVisual();
	UFUNCTION() void OnRep_Row() { BuildVisual(); }

	UPROPERTY(Transient) TObjectPtr<AController> InstigatorController;
	UPROPERTY(VisibleAnywhere, Category = "Claymore") TObjectPtr<UPointLightComponent> Blink;
	UPROPERTY(ReplicatedUsing = OnRep_Row) FName RowName;
	UPROPERTY(Replicated) bool bArmed = false;
	EMSTeam Team = EMSTeam::Player;
	float ArmLeft = 1.f;
	float TriggerLeft = -1.f;
	float CheckTimer = 0.f;
	bool bVisualBuilt = false;
};
