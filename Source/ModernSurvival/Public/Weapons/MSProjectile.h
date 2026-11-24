#pragma once

#include "CoreMinimal.h"
#include "GameFramework/Actor.h"
#include "Combat/MSCombatTypes.h"
#include "MSProjectile.generated.h"

class USphereComponent;
class UProjectileMovementComponent;

/** Rocket / launcher round. Explodes on impact using explosion params from the weapon row. */
UCLASS()
class MODERNSURVIVAL_API AMSProjectile : public AActor
{
	GENERATED_BODY()

public:
	AMSProjectile();

	void Launch(const FMSExplosionParams& InExplosion, const FVector& Velocity, float GravityScale, AController* InInstigator, EMSTeam InTeam, AActor* IgnoreActor);

protected:
	virtual void BeginPlay() override;
	virtual void LifeSpanExpired() override;

	UFUNCTION() void OnHit(UPrimitiveComponent* HitComp, AActor* OtherActor, UPrimitiveComponent* OtherComp, FVector NormalImpulse, const FHitResult& Hit);
	void Detonate(const FVector& Location);

	UPROPERTY(VisibleAnywhere, Category = "Projectile") TObjectPtr<USphereComponent> Collision;
	UPROPERTY(VisibleAnywhere, Category = "Projectile") TObjectPtr<UProjectileMovementComponent> Movement;

	UPROPERTY(Transient) FMSExplosionParams Explosion;
	UPROPERTY(Transient) TObjectPtr<AController> InstigatorController;
	EMSTeam Team = EMSTeam::Neutral;
	bool bDetonated = false;
};
