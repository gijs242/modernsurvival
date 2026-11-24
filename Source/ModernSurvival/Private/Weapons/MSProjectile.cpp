#include "Weapons/MSProjectile.h"

#include "Combat/MSCombatLibrary.h"
#include "FX/MSFXLibrary.h"
#include "ModernSurvival.h"
#include "Components/PointLightComponent.h"
#include "Components/SphereComponent.h"
#include "GameFramework/ProjectileMovementComponent.h"

AMSProjectile::AMSProjectile()
{
	Collision = CreateDefaultSubobject<USphereComponent>(TEXT("Collision"));
	Collision->InitSphereRadius(8.f);
	Collision->SetCollisionProfileName(TEXT("Projectile"));
	Collision->SetCollisionResponseToChannel(ECC_MSWeapon, ECR_Ignore);
	Collision->SetNotifyRigidBodyCollision(true);
	SetRootComponent(Collision);

	Movement = CreateDefaultSubobject<UProjectileMovementComponent>(TEXT("Movement"));
	Movement->bRotationFollowsVelocity = true;
	Movement->bShouldBounce = false;
	Movement->InitialSpeed = 0.f;
	Movement->bAutoActivate = false;

	UPointLightComponent* Glow = CreateDefaultSubobject<UPointLightComponent>(TEXT("Glow"));
	Glow->SetupAttachment(Collision);
	Glow->SetIntensityUnits(ELightUnits::Unitless);
	Glow->SetIntensity(8000.f);
	Glow->SetAttenuationRadius(400.f);
	Glow->SetLightColor(FLinearColor(1.f, 0.55f, 0.2f));
	Glow->SetCastShadows(false);

	InitialLifeSpan = 8.f;
}

void AMSProjectile::BeginPlay()
{
	Super::BeginPlay();
	Collision->OnComponentHit.AddDynamic(this, &AMSProjectile::OnHit);
	UMSFXLibrary::AddPlaceholderShape(this, Collision, TEXT("Cylinder"), FTransform(FRotator(90, 0, 0), FVector(-10, 0, 0), FVector(0.07f, 0.07f, 0.35f)), FLinearColor(0.1f, 0.12f, 0.08f), false);
}

void AMSProjectile::Launch(const FMSExplosionParams& InExplosion, const FVector& Velocity, float GravityScale, AController* InInstigator, EMSTeam InTeam, AActor* IgnoreActor)
{
	Explosion = InExplosion;
	InstigatorController = InInstigator;
	Team = InTeam;
	if (IgnoreActor)
	{
		Collision->IgnoreActorWhenMoving(IgnoreActor, true);
	}
	Movement->ProjectileGravityScale = GravityScale;
	Movement->Velocity = Velocity;
	Movement->Activate(true);
}

void AMSProjectile::OnHit(UPrimitiveComponent* HitComp, AActor* OtherActor, UPrimitiveComponent* OtherComp, FVector NormalImpulse, const FHitResult& Hit)
{
	Detonate(Hit.ImpactPoint + Hit.ImpactNormal * 10.f);
}

void AMSProjectile::LifeSpanExpired()
{
	Detonate(GetActorLocation());
}

void AMSProjectile::Detonate(const FVector& Location)
{
	if (bDetonated)
	{
		return;
	}
	bDetonated = true;
	UMSCombatLibrary::Explode(this, Location, Explosion, InstigatorController, this, Team);
	Destroy();
}
