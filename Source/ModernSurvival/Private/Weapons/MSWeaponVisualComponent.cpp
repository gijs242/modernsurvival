#include "Weapons/MSWeaponVisualComponent.h"

#include "Core/MSEngineCompat.h"
#include "FX/MSFXLibrary.h"
#include "ModernSurvival.h"
#include "Components/StaticMeshComponent.h"
#include "Engine/StaticMesh.h"
#include "GameFramework/Actor.h"

UMSWeaponVisualComponent::UMSWeaponVisualComponent()
{
	PrimaryComponentTick.bCanEverTick = true;
}

void UMSWeaponVisualComponent::ClearVisual()
{
	for (UStaticMeshComponent* Part : Parts)
	{
		if (Part)
		{
			Part->DestroyComponent();
		}
	}
	Parts.Reset();
	MovingPart = nullptr;
}

void UMSWeaponVisualComponent::MarkFirstPerson(UStaticMeshComponent* Comp, bool bFirstPerson)
{
	if (!Comp)
	{
		return;
	}
	Comp->SetCollisionEnabled(ECollisionEnabled::NoCollision);
	if (bFirstPerson)
	{
		// UE 5.6+ first-person rendering: own FOV and squashed toward the eye so it never clips walls.
#if MS_WITH_FIRST_PERSON_RENDERING
		Comp->FirstPersonPrimitiveType = EFirstPersonPrimitiveType::FirstPerson;
#endif
		Comp->SetCastShadow(false);
		Comp->bCastHiddenShadow = false;
	}
}

void UMSWeaponVisualComponent::BuildVisual_Implementation(const FMSWeaponRow& Row, bool bFirstPerson)
{
	ClearVisual();
	AActor* Owner = GetOwner();
	UStaticMesh* Mesh = Row.Mesh.IsNull() ? nullptr : Row.Mesh.LoadSynchronous();
	if (!Mesh || !Owner)
	{
		BuildPlaceholder(Row, bFirstPerson);
		return;
	}

	// Auto-orient: the longest horizontal axis is the barrel; the far end from the origin is the muzzle.
	const FBox Box = Mesh->GetBoundingBox();
	const FVector Size = Box.GetSize();
	const bool bAlongX = Size.X >= Size.Y;
	const float MinAlong = bAlongX ? Box.Min.X : Box.Min.Y;
	const float MaxAlong = bAlongX ? Box.Max.X : Box.Max.Y;
	const bool bPositive = FMath::Abs(MaxAlong) >= FMath::Abs(MinAlong);
	float Yaw = 0.f;
	if (bAlongX)
	{
		Yaw = bPositive ? 0.f : 180.f;
	}
	else
	{
		Yaw = bPositive ? -90.f : 90.f;
	}
	const float Length = FMath::Max(Size.X, Size.Y);
	// glTF in metres imports ~1 unit long; real guns are 20..130 cm.
	const float AutoScale = Length < 5.f ? 100.f : 1.f;
	const float ForwardExtent = FMath::Max(FMath::Abs(MaxAlong), FMath::Abs(MinAlong)) * AutoScale;

	UStaticMeshComponent* Comp = NewObject<UStaticMeshComponent>(Owner, NAME_None, RF_Transient);
	Comp->SetStaticMesh(Mesh);
	Comp->SetupAttachment(this);
	const FTransform AutoFix(FRotator(0.f, Yaw, 0.f), FVector::ZeroVector, FVector(AutoScale));
	Comp->SetRelativeTransform(AutoFix * Row.MeshTransform);
	Comp->RegisterComponent();
	Owner->AddInstanceComponent(Comp);
	MarkFirstPerson(Comp, bFirstPerson);
	Parts.Add(Comp);

	MuzzleLocal = Row.MeshTransform.TransformPosition(FVector(ForwardExtent, 0.f, -3.5f));
}

void UMSWeaponVisualComponent::BuildPlaceholder(const FMSWeaponRow& Row, bool bFirstPerson)
{
	AActor* Owner = GetOwner();
	if (!Owner)
	{
		return;
	}
	// Basic shapes are 100 cm; build a recognisable gun silhouette with its sight line at Z = 0.
	const FVector S = Row.PlaceholderSize;                // length, width, height (cm)
	const FLinearColor Dark = Row.PlaceholderColor;
	const FLinearColor Darker = Dark * 0.6f;
	const float L = S.X;
	const float W = S.Y;
	const float H = S.Z;
	const bool bPistol = Row.WeaponClass == EMSWeaponClass::Pistol;
	const bool bLauncher = Row.WeaponClass == EMSWeaponClass::Launcher;

	auto Box = [&](const FVector& Center, const FVector& Extent, const FLinearColor& Color, FName Shape = TEXT("Cube"), const FRotator& Rot = FRotator::ZeroRotator)
	{
		UStaticMeshComponent* C = UMSFXLibrary::AddPlaceholderShape(Owner, this, Shape, FTransform(Rot, Center, Extent / 100.f), Color, false);
		MarkFirstPerson(C, bFirstPerson);
		Parts.Add(C);
		return C;
	};

	if (bLauncher)
	{
		Box(FVector(L * 0.25f, 0, -W * 0.5f), FVector(W, W, L), Dark, TEXT("Cylinder"), FRotator(90, 0, 0));
		Box(FVector(0, 0, -W - 6.f), FVector(5, 3, 12), Darker);
		MuzzleLocal = FVector(L * 0.75f, 0, -W * 0.5f);
		return;
	}

	const float ReceiverLen = bPistol ? L : L * 0.45f;
	// Receiver / slide.
	UStaticMeshComponent* Receiver = Box(FVector(ReceiverLen * 0.5f - (bPistol ? 4.f : 10.f), 0, -H * 0.3f), FVector(ReceiverLen, W, H * 0.45f), Dark);
	if (bPistol)
	{
		MovingPart = Receiver;
		MovingPartRest = Receiver->GetRelativeLocation();
		Box(FVector(-2.f, 0, -H * 0.75f), FVector(4.f, W * 0.9f, H * 0.6f), Darker, TEXT("Cube"), FRotator(-15, 0, 0)); // grip
		MuzzleLocal = FVector(ReceiverLen - 4.f, 0, -H * 0.3f);
		return;
	}
	// Barrel + handguard.
	const float BarrelStart = ReceiverLen - 10.f;
	const float BarrelLen = L - ReceiverLen;
	Box(FVector(BarrelStart + BarrelLen * 0.5f, 0, -H * 0.3f), FVector(BarrelLen, 2.2f, 2.2f), Darker, TEXT("Cylinder"), FRotator(90, 0, 0));
	Box(FVector(BarrelStart + BarrelLen * 0.3f, 0, -H * 0.3f), FVector(BarrelLen * 0.55f, W * 1.1f, H * 0.4f), Dark);
	// Magazine, grip, stock, sight.
	Box(FVector(ReceiverLen * 0.4f, 0, -H * 0.85f), FVector(5.f, W * 0.8f, H * 0.8f), Darker, TEXT("Cube"), FRotator(-8, 0, 0));
	Box(FVector(ReceiverLen * 0.05f, 0, -H * 0.8f), FVector(4.f, W * 0.9f, H * 0.6f), Darker, TEXT("Cube"), FRotator(-15, 0, 0));
	Box(FVector(-14.f, 0, -H * 0.35f), FVector(24.f, W * 0.9f, H * 0.55f), Dark);
	Box(FVector(ReceiverLen * 0.3f, 0, -1.2f), FVector(6.f, 2.5f, 2.5f), Darker);
	UStaticMeshComponent* Bolt = Box(FVector(ReceiverLen * 0.25f, W * 0.55f, -H * 0.25f), FVector(6.f, 1.f, 1.5f), Darker);
	MovingPart = Bolt;
	MovingPartRest = Bolt->GetRelativeLocation();
	MuzzleLocal = FVector(BarrelStart + BarrelLen, 0, -H * 0.3f);
}

FTransform UMSWeaponVisualComponent::GetMuzzleTransform_Implementation() const
{
	return FTransform(GetComponentRotation(), GetComponentTransform().TransformPosition(MuzzleLocal));
}

void UMSWeaponVisualComponent::SetVisualHidden(bool bHidden)
{
	SetVisibility(!bHidden, true);
}

void UMSWeaponVisualComponent::PlayFireAnim()
{
	MovingPartKick = 1.f;
}

void UMSWeaponVisualComponent::TickComponent(float DeltaTime, ELevelTick TickType, FActorComponentTickFunction* ThisTickFunction)
{
	Super::TickComponent(DeltaTime, TickType, ThisTickFunction);
	if (MovingPart && MovingPartKick > 0.f)
	{
		MovingPartKick = FMath::Max(0.f, MovingPartKick - DeltaTime * 14.f);
		MovingPart->SetRelativeLocation(MovingPartRest - FVector(4.f * MovingPartKick, 0.f, 0.f));
	}
}
