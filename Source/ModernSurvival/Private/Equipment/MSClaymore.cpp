#include "Equipment/MSClaymore.h"

#include "Combat/MSCombatLibrary.h"
#include "Combat/MSCombatSubsystem.h"
#include "Combat/MSHealthComponent.h"
#include "Data/MSDataSubsystem.h"
#include "FX/MSFXLibrary.h"
#include "Components/PointLightComponent.h"
#include "Kismet/GameplayStatics.h"
#include "Net/UnrealNetwork.h"

AMSClaymore::AMSClaymore()
{
	PrimaryActorTick.bCanEverTick = true;
	SetRootComponent(CreateDefaultSubobject<USceneComponent>(TEXT("Root")));
	Blink = CreateDefaultSubobject<UPointLightComponent>(TEXT("Blink"));
	Blink->SetupAttachment(GetRootComponent());
	Blink->SetRelativeLocation(FVector(8.f, 0.f, 22.f));
	Blink->SetIntensityUnits(ELightUnits::Unitless);
	Blink->SetIntensity(0.f);
	Blink->SetAttenuationRadius(120.f);
	Blink->SetLightColor(FLinearColor::Red);
	Blink->SetCastShadows(false);
	bReplicates = true;
}

void AMSClaymore::GetLifetimeReplicatedProps(TArray<FLifetimeProperty>& OutLifetimeProps) const
{
	Super::GetLifetimeReplicatedProps(OutLifetimeProps);
	DOREPLIFETIME(AMSClaymore, RowName);
	DOREPLIFETIME(AMSClaymore, bArmed);
}

void AMSClaymore::BuildVisual()
{
	if (bVisualBuilt || RowName.IsNone() || GetNetMode() == NM_DedicatedServer)
	{
		return;
	}
	bVisualBuilt = true;
	const FMSEquipmentRow& Row = UMSDataSubsystem::Get(this)->GetEquipment(RowName);
	// Curved plate on two little legs, facing +X.
	UMSFXLibrary::AddPlaceholderShape(this, nullptr, TEXT("Cube"), FTransform(FRotator(0, 0, 0), FVector(0, 0, 14), FVector(0.05f, 0.24f, 0.13f)), Row.PlaceholderColor, false);
	UMSFXLibrary::AddPlaceholderShape(this, nullptr, TEXT("Cylinder"), FTransform(FRotator(15, 0, 0), FVector(-4, -8, 4), FVector(0.01f, 0.01f, 0.1f)), Row.PlaceholderColor, false);
	UMSFXLibrary::AddPlaceholderShape(this, nullptr, TEXT("Cylinder"), FTransform(FRotator(15, 0, 0), FVector(-4, 8, 4), FVector(0.01f, 0.01f, 0.1f)), Row.PlaceholderColor, false);
	UGameplayStatics::PlaySoundAtLocation(this, LoadObject<USoundBase>(nullptr, TEXT("/Game/Audio/mag_in.mag_in")), GetActorLocation(), 0.5f);
}

void AMSClaymore::Arm(FName EquipmentRow, AController* InInstigator, EMSTeam InTeam)
{
	RowName = EquipmentRow;
	InstigatorController = InInstigator;
	Team = InTeam;
	ArmLeft = UMSDataSubsystem::Get(this)->GetEquipment(RowName).ArmTime;
	BuildVisual();
}

void AMSClaymore::Tick(float DeltaSeconds)
{
	Super::Tick(DeltaSeconds);
	if (RowName.IsNone())
	{
		return;
	}
	if (bArmed)
	{
		Blink->SetIntensity(FMath::Fmod(GetWorld()->GetTimeSeconds(), 1.0) < 0.1 ? 800.f : 0.f);
	}
	if (!HasAuthority())
	{
		return;
	}
	const FMSEquipmentRow& Row = UMSDataSubsystem::Get(this)->GetEquipment(RowName);
	if (!bArmed)
	{
		ArmLeft -= DeltaSeconds;
		bArmed = ArmLeft <= 0.f;
		return;
	}
	if (TriggerLeft >= 0.f)
	{
		TriggerLeft -= DeltaSeconds;
		if (TriggerLeft < 0.f)
		{
			Detonate();
		}
		return;
	}
	CheckTimer -= DeltaSeconds;
	if (CheckTimer > 0.f)
	{
		return;
	}
	CheckTimer = 0.1f;
	const UMSCombatSubsystem* Combat = UMSCombatSubsystem::Get(this);
	if (!Combat)
	{
		return;
	}
	const FVector Here = GetActorLocation() + FVector(0, 0, 20);
	const FVector Fwd = GetActorForwardVector();
	const float CosLimit = FMath::Cos(FMath::DegreesToRadians(Row.TriggerHalfAngle));
	for (const UMSHealthComponent* H : Combat->GetHostiles(Team))
	{
		const AActor* A = H->GetOwner();
		const FVector To = A->GetActorLocation() - Here;
		if (To.Size() > Row.TriggerRadius || FVector::DotProduct(To.GetSafeNormal2D(), Fwd) < CosLimit)
		{
			continue;
		}
		if (UMSCombatSubsystem::HasLineOfSight(GetWorld(), Here, A, this))
		{
			TriggerLeft = Row.TriggerDelay;
			UGameplayStatics::PlaySoundAtLocation(this, LoadObject<USoundBase>(nullptr, TEXT("/Game/Audio/dry.dry")), Here);
			return;
		}
	}
}

void AMSClaymore::Detonate()
{
	const FMSEquipmentRow& Row = UMSDataSubsystem::Get(this)->GetEquipment(RowName);
	// Blast centred a little in front: it is directional.
	UMSCombatLibrary::Explode(this, GetActorLocation() + GetActorForwardVector() * Row.InnerRadius * 0.6f + FVector(0, 0, 30), FMSExplosionParams::FromEquipment(Row), InstigatorController, this, Team);
	Destroy();
}
