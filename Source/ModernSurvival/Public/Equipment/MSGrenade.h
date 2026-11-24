#pragma once

#include "CoreMinimal.h"
#include "GameFramework/Actor.h"
#include "Data/MSDataTypes.h"
#include "TimerManager.h"
#include "MSGrenade.generated.h"

class USphereComponent;
class UProjectileMovementComponent;

/** Thrown frag. Bounces, explodes when the (cooked) fuse runs out. Numbers: DT_Equipment "Frag". */
UCLASS()
class MODERNSURVIVAL_API AMSGrenade : public AActor
{
	GENERATED_BODY()

public:
	AMSGrenade();
	void Arm(FName EquipmentRow, const FVector& Velocity, float Fuse, AController* InInstigator, EMSTeam InTeam, AActor* IgnoreActor);

protected:
	void Detonate();

	UPROPERTY(VisibleAnywhere, Category = "Grenade") TObjectPtr<USphereComponent> Collision;
	UPROPERTY(VisibleAnywhere, Category = "Grenade") TObjectPtr<UProjectileMovementComponent> Movement;
	UPROPERTY(Transient) TObjectPtr<AController> InstigatorController;
	FName RowName;
	EMSTeam Team = EMSTeam::Player;
	FTimerHandle FuseTimer;
};
