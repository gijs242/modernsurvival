#include "Equipment/MSAirstrike.h"

#include "Combat/MSCombatLibrary.h"
#include "Data/MSDataSubsystem.h"
#include "Components/PointLightComponent.h"
#include "Engine/World.h"

AMSAirstrike::AMSAirstrike()
{
	PrimaryActorTick.bCanEverTick = true;
	SetRootComponent(CreateDefaultSubobject<USceneComponent>(TEXT("Root")));
	Flare = CreateDefaultSubobject<UPointLightComponent>(TEXT("Flare"));
	Flare->SetupAttachment(GetRootComponent());
	Flare->SetRelativeLocation(FVector(0, 0, 40));
	Flare->SetIntensityUnits(ELightUnits::Unitless);
	Flare->SetIntensity(20000.f);
	Flare->SetAttenuationRadius(600.f);
	Flare->SetLightColor(FLinearColor(1.f, 0.1f, 0.05f));
	Flare->SetCastShadows(false);
}

void AMSAirstrike::Begin(FName EquipmentRow, AController* InInstigator, EMSTeam InTeam)
{
	RowName = EquipmentRow;
	InstigatorController = InInstigator;
	Team = InTeam;
	DelayLeft = UMSDataSubsystem::Get(this)->GetEquipment(RowName).StrikeDelay;
	bStarted = true;
}

void AMSAirstrike::Tick(float DeltaSeconds)
{
	Super::Tick(DeltaSeconds);
	if (!bStarted)
	{
		return;
	}
	const FMSEquipmentRow& Row = UMSDataSubsystem::Get(this)->GetEquipment(RowName);
	Flare->SetIntensity(FMath::Abs(FMath::Sin(GetWorld()->GetTimeSeconds() * 10.0)) * 20000.f);
	if (DelayLeft > 0.f)
	{
		DelayLeft -= DeltaSeconds;
		return;
	}
	NextBomb -= DeltaSeconds;
	if (NextBomb > 0.f)
	{
		return;
	}
	NextBomb = Row.StrikeInterval;
	const int32 Count = FMath::Max(1, Row.StrikeExplosions);
	const float T = Count > 1 ? static_cast<float>(BombsDropped) / (Count - 1) - 0.5f : 0.f;
	const FVector Along = GetActorForwardVector() * Row.StrikeLength * T;
	const FVector Scatter(FMath::FRandRange(-Row.StrikeScatter, Row.StrikeScatter), FMath::FRandRange(-Row.StrikeScatter, Row.StrikeScatter), 0.f);
	const FVector Above = GetActorLocation() + Along + Scatter + FVector(0, 0, 4000.f);
	FHitResult Hit;
	FVector Ground = Above - FVector(0, 0, 4000.f);
	if (GetWorld()->LineTraceSingleByChannel(Hit, Above, Above - FVector(0, 0, 8000.f), ECC_Visibility))
	{
		Ground = Hit.ImpactPoint;
	}
	UMSCombatLibrary::Explode(this, Ground + FVector(0, 0, 30), FMSExplosionParams::FromEquipment(Row), InstigatorController, this, Team);
	if (++BombsDropped >= Count)
	{
		Destroy();
	}
}
