#include "Equipment/MSGrenade.h"

#include "Combat/MSCombatLibrary.h"
#include "Data/MSDataSubsystem.h"
#include "FX/MSFXLibrary.h"
#include "ModernSurvival.h"
#include "Components/SphereComponent.h"
#include "Components/StaticMeshComponent.h"
#include "Engine/StaticMesh.h"
#include "GameFramework/ProjectileMovementComponent.h"
#include "TimerManager.h"

AMSGrenade::AMSGrenade()
{
	Collision = CreateDefaultSubobject<USphereComponent>(TEXT("Collision"));
	Collision->InitSphereRadius(5.f);
	Collision->SetCollisionProfileName(TEXT("Projectile"));
	Collision->SetCollisionResponseToChannel(ECC_Pawn, ECR_Ignore);
	Collision->SetCollisionResponseToChannel(ECC_MSWeapon, ECR_Ignore);
	SetRootComponent(Collision);

	Movement = CreateDefaultSubobject<UProjectileMovementComponent>(TEXT("Movement"));
	Movement->bShouldBounce = true;
	Movement->bRotationFollowsVelocity = false;
	Movement->Friction = 0.4f;
	Movement->InitialSpeed = 0.f;
	Movement->bAutoActivate = false;
}

void AMSGrenade::Arm(FName EquipmentRow, const FVector& Velocity, float Fuse, AController* InInstigator, EMSTeam InTeam, AActor* IgnoreActor)
{
	RowName = EquipmentRow;
	InstigatorController = InInstigator;
	Team = InTeam;
	const FMSEquipmentRow& Row = UMSDataSubsystem::Get(this)->GetEquipment(RowName);
	Movement->Bounciness = Row.Bounciness;
	Movement->Velocity = Velocity;
	Movement->Activate(true);
	if (IgnoreActor)
	{
		Collision->IgnoreActorWhenMoving(IgnoreActor, true);
	}
	if (UStaticMesh* Mesh = Row.Mesh.LoadSynchronous())
	{
		UStaticMeshComponent* Comp = UMSFXLibrary::AddPlaceholderShape(this, Collision, TEXT("Sphere"), FTransform::Identity, FLinearColor::White, false);
		Comp->SetStaticMesh(Mesh);
		Comp->SetMaterial(0, nullptr);
		// glTF in metres imports ~0.1 units across; scale it to centimetres.
		const float Len = Mesh->GetBoundingBox().GetSize().GetMax();
		Comp->SetRelativeScale3D(FVector(Len < 2.f ? 100.f : 1.f));
	}
	else
	{
		UMSFXLibrary::AddPlaceholderShape(this, Collision, TEXT("Sphere"), FTransform(FRotator::ZeroRotator, FVector::ZeroVector, FVector(0.07f, 0.07f, 0.1f)), Row.PlaceholderColor, false);
	}
	GetWorldTimerManager().SetTimer(FuseTimer, this, &AMSGrenade::Detonate, FMath::Max(0.02f, Fuse), false);
}

void AMSGrenade::Detonate()
{
	const FMSEquipmentRow& Row = UMSDataSubsystem::Get(this)->GetEquipment(RowName);
	UMSCombatLibrary::Explode(this, GetActorLocation() + FVector(0, 0, 10), FMSExplosionParams::FromEquipment(Row), InstigatorController, this, Team);
	Destroy();
}
