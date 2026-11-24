#pragma once

#include "CoreMinimal.h"
#include "GameFramework/Actor.h"
#include "Data/MSDataTypes.h"
#include "TimerManager.h"
#include "MSGrenade.generated.h"

class USphereComponent;
class UProjectileMovementComponent;

/** Thrown frag. Bounces, explodes when the (cooked) fuse runs out. Numbers: DT_Equipment "Frag". Server-simulated, replicated. */
UCLASS()
class MODERNSURVIVAL_API AMSGrenade : public AActor
{
	GENERATED_BODY()

public:
	AMSGrenade();
	/** Server only. */
	void Arm(FName EquipmentRow, const FVector& Velocity, float Fuse, AController* InInstigator, EMSTeam InTeam, AActor* IgnoreActor);
	virtual void GetLifetimeReplicatedProps(TArray<FLifetimeProperty>& OutLifetimeProps) const override;

protected:
	void Detonate();
	UFUNCTION() void OnRep_Row();
	void BuildVisual();

	UPROPERTY(VisibleAnywhere, Category = "Grenade") TObjectPtr<USphereComponent> Collision;
	UPROPERTY(VisibleAnywhere, Category = "Grenade") TObjectPtr<UProjectileMovementComponent> Movement;
	UPROPERTY(Transient) TObjectPtr<AController> InstigatorController;
	UPROPERTY(ReplicatedUsing = OnRep_Row) FName RowName;
	EMSTeam Team = EMSTeam::Player;
	FTimerHandle FuseTimer;
	bool bVisualBuilt = false;
};
