#include "Equipment/MSSentryGun.h"

#include "Combat/MSCombatLibrary.h"
#include "Combat/MSCombatSubsystem.h"
#include "Combat/MSHealthComponent.h"
#include "Data/MSDataSubsystem.h"
#include "FX/MSFXLibrary.h"
#include "Weapons/MSWeapon.h"
#include "Components/BoxComponent.h"
#include "Engine/World.h"
#include "Kismet/GameplayStatics.h"
#include "Net/UnrealNetwork.h"

AMSSentryGun::AMSSentryGun()
{
	PrimaryActorTick.bCanEverTick = true;
	Base = CreateDefaultSubobject<UBoxComponent>(TEXT("Base"));
	Base->InitBoxExtent(FVector(35.f, 35.f, 55.f));
	Base->SetCollisionProfileName(TEXT("BlockAllDynamic"));
	Base->SetCollisionResponseToChannel(ECC_MSWeapon, ECR_Block);
	Base->SetCanEverAffectNavigation(true);   // AI walk around it (dynamic navmesh)
	SetRootComponent(Base);
	Turret = CreateDefaultSubobject<USceneComponent>(TEXT("Turret"));
	Turret->SetupAttachment(Base);
	Turret->SetRelativeLocation(FVector(0.f, 0.f, 45.f));
	Health = CreateDefaultSubobject<UMSHealthComponent>(TEXT("Health"));
	Health->Team = EMSTeam::Player;
	bReplicates = true;
}

void AMSSentryGun::GetLifetimeReplicatedProps(TArray<FLifetimeProperty>& OutLifetimeProps) const
{
	Super::GetLifetimeReplicatedProps(OutLifetimeProps);
	DOREPLIFETIME(AMSSentryGun, RowName);
	DOREPLIFETIME(AMSSentryGun, TurretAim);
}

void AMSSentryGun::OnRep_Aim()
{
	Turret->SetWorldRotation(TurretAim);
}

void AMSSentryGun::BuildVisual()
{
	if (bVisualBuilt || RowName.IsNone() || GetNetMode() == NM_DedicatedServer)
	{
		return;
	}
	bVisualBuilt = true;
	const FLinearColor C = UMSDataSubsystem::Get(this)->GetEquipment(RowName).PlaceholderColor;
	// Tripod + box body + barrel shroud.
	for (int32 I = 0; I < 3; ++I)
	{
		const float Yaw = 120.f * I;
		UMSFXLibrary::AddPlaceholderShape(this, Base, TEXT("Cylinder"), FTransform(FRotator(25.f, Yaw, 0.f), FRotator(0.f, Yaw, 0.f).Vector() * 18.f + FVector(0, 0, -25.f), FVector(0.04f, 0.04f, 0.6f)), C * 0.5f, false);
	}
	UMSFXLibrary::AddPlaceholderShape(this, Turret, TEXT("Cube"), FTransform(FRotator::ZeroRotator, FVector(0, 0, 0), FVector(0.45f, 0.3f, 0.25f)), C, false);
	UMSFXLibrary::AddPlaceholderShape(this, Turret, TEXT("Cube"), FTransform(FRotator::ZeroRotator, FVector(-5, 0, 22), FVector(0.3f, 0.35f, 0.04f)), C * 0.7f, false);
}

void AMSSentryGun::Deploy(FName EquipmentRow, AController* InInstigator, EMSTeam InTeam)
{
	RowName = EquipmentRow;
	InstigatorController = InInstigator;
	Team = InTeam;
	const FMSEquipmentRow& Row = UMSDataSubsystem::Get(this)->GetEquipment(RowName);
	LifeLeft = Row.Lifetime;
	Health->Team = Team;
	Health->SetMaxHealth(Row.Health, true);
	Health->OnDied.AddDynamic(this, &AMSSentryGun::HandleDied);
	TurretAim = Turret->GetComponentRotation();
	BuildVisual();

	FActorSpawnParameters Params;
	Params.Owner = this;
	Params.SpawnCollisionHandlingOverride = ESpawnActorCollisionHandlingMethod::AlwaysSpawn;
	Gun = GetWorld()->SpawnActor<AMSWeapon>(AMSWeapon::StaticClass(), GetActorTransform(), Params);
	if (Gun)
	{
		Gun->Setup(Row.TurretWeapon, this, false);
		Gun->AttachToComponent(Turret, FAttachmentTransformRules::SnapToTargetNotIncludingScale);
		Gun->SetActorRelativeLocation(FVector(15.f, 0.f, 5.f));
		Gun->SetEquipped(true);
	}
	UGameplayStatics::PlaySoundAtLocation(this, Row.UseSound.LoadSynchronous(), GetActorLocation());
}

void AMSSentryGun::GetAimRay(FVector& OutStart, FVector& OutDirection) const
{
	OutStart = Gun ? Gun->GetMuzzleTransform().GetLocation() : Turret->GetComponentLocation();
	OutDirection = Turret->GetForwardVector();
}

void AMSSentryGun::Tick(float DeltaSeconds)
{
	Super::Tick(DeltaSeconds);
	if (RowName.IsNone() || Health->IsDead() || !HasAuthority())
	{
		return;
	}
	const FMSEquipmentRow& Row = UMSDataSubsystem::Get(this)->GetEquipment(RowName);
	LifeLeft -= DeltaSeconds;
	if (LifeLeft <= 0.f)
	{
		FMSDamageInfo Info;
		Info.SourceTeam = EMSTeam::Neutral;
		Health->Kill(Info);
		return;
	}
	TargetTimer -= DeltaSeconds;
	if (TargetTimer <= 0.f)
	{
		TargetTimer = 0.2f;
		const UMSCombatSubsystem* Combat = UMSCombatSubsystem::Get(this);
		const UMSHealthComponent* H = Combat ? Combat->FindClosestHostile(Team, Turret->GetComponentLocation(), Row.Range, true, this) : nullptr;
		Target = H ? H->GetOwner() : nullptr;
	}
	AActor* T = Target.Get();
	if (!T)
	{
		SpinUp = FMath::Max(0.f, SpinUp - DeltaSeconds);
		if (Gun)
		{
			Gun->SetTriggerHeld(false);
		}
		// Idle sweep.
		Turret->AddLocalRotation(FRotator(0.f, 25.f * DeltaSeconds, 0.f));
		TurretAim = Turret->GetComponentRotation();
		return;
	}
	const FVector To = UMSCombatSubsystem::GetAimPoint(T) - Turret->GetComponentLocation();
	const FRotator NewRot = FMath::RInterpConstantTo(Turret->GetComponentRotation(), To.Rotation(), DeltaSeconds, Row.TurnSpeed);
	Turret->SetWorldRotation(NewRot);
	TurretAim = NewRot;
	const float Angle = FMath::RadiansToDegrees(FMath::Acos(FMath::Clamp(FVector::DotProduct(NewRot.Vector(), To.GetSafeNormal()), -1.f, 1.f)));
	if (Angle <= Row.FireConeDeg)
	{
		SpinUp += DeltaSeconds;
	}
	if (Gun)
	{
		Gun->SetTriggerHeld(Angle <= Row.FireConeDeg && SpinUp >= Row.SpinUpTime);
	}
}

void AMSSentryGun::HandleDied(UMSHealthComponent* InHealth, const FMSDamageInfo& KillingBlow)
{
	if (!HasAuthority())
	{
		return;
	}
	if (Gun)
	{
		Gun->Destroy();
		Gun = nullptr;
	}
	FMSExplosionParams Small;
	Small.Damage = 0.f;
	Small.OuterRadius = 150.f;
	Small.Trauma = 0.2f;
	Small.TraumaRadius = 800.f;
	UMSCombatLibrary::Explode(this, GetActorLocation(), Small, InstigatorController, this, EMSTeam::Neutral);
	Destroy();
}
