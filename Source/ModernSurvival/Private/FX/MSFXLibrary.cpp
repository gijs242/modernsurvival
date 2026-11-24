#include "FX/MSFXLibrary.h"

#include "ModernSurvival.h"
#include "Components/PointLightComponent.h"
#include "Components/StaticMeshComponent.h"
#include "Engine/StaticMesh.h"
#include "Engine/World.h"
#include "Materials/MaterialInstanceDynamic.h"
#include "NiagaraFunctionLibrary.h"
#include "NiagaraSystem.h"

AMSFlashActor::AMSFlashActor()
{
	PrimaryActorTick.bCanEverTick = true;
	SetRootComponent(CreateDefaultSubobject<USceneComponent>(TEXT("Root")));
	Light = CreateDefaultSubobject<UPointLightComponent>(TEXT("Light"));
	Light->SetupAttachment(GetRootComponent());
	Light->SetCastShadows(false);
	Light->SetIntensityUnits(ELightUnits::Unitless);
	Light->SetIntensity(0.f);
	Light->SetVisibility(false);
	Shape = CreateDefaultSubobject<UStaticMeshComponent>(TEXT("Shape"));
	Shape->SetupAttachment(GetRootComponent());
	Shape->SetCollisionEnabled(ECollisionEnabled::NoCollision);
	Shape->SetCastShadow(false);
	Shape->SetVisibility(false);
	InitialLifeSpan = 3.f;
}

void AMSFlashActor::InitLight(float Intensity, float Radius, const FLinearColor& Color, float Duration)
{
	LightStart = Intensity;
	LightDuration = FMath::Max(Duration, 0.01f);
	Light->SetVisibility(true);
	Light->SetIntensity(Intensity);
	Light->SetAttenuationRadius(Radius);
	Light->SetLightColor(Color);
}

void AMSFlashActor::InitShape(UStaticMesh* Mesh, const FLinearColor& Color, const FVector& StartScale, const FVector& EndScale, float Duration)
{
	if (!Mesh)
	{
		return;
	}
	Shape->SetStaticMesh(Mesh);
	if (UMaterialInterface* Base = UMSFXLibrary::GetBasicMaterial())
	{
		UMaterialInstanceDynamic* MID = UMaterialInstanceDynamic::Create(Base, this);
		MID->SetVectorParameterValue(TEXT("Color"), Color);
		Shape->SetMaterial(0, MID);
	}
	Shape->SetVisibility(true);
	Shape->SetRelativeScale3D(StartScale);
	ScaleStart = StartScale;
	ScaleEnd = EndScale;
	ShapeDuration = FMath::Max(Duration, 0.01f);
}

void AMSFlashActor::Tick(float DeltaSeconds)
{
	Super::Tick(DeltaSeconds);
	Age += DeltaSeconds;
	if (LightDuration > 0.f)
	{
		const float T = FMath::Clamp(Age / LightDuration, 0.f, 1.f);
		Light->SetIntensity(LightStart * (1.f - T) * (1.f - T));
	}
	if (ShapeDuration > 0.f)
	{
		const float T = FMath::Clamp(Age / ShapeDuration, 0.f, 1.f);
		Shape->SetRelativeScale3D(FMath::Lerp(ScaleStart, ScaleEnd, FMath::Sqrt(T)));
		if (T >= 1.f)
		{
			Shape->SetVisibility(false);
		}
	}
	if (!MoveVelocity.IsZero())
	{
		AddActorWorldOffset(MoveVelocity * DeltaSeconds);
	}
	if (Age > FMath::Max(LightDuration, ShapeDuration))
	{
		Destroy();
	}
}

UStaticMesh* UMSFXLibrary::GetBasicShape(FName ShapeName)
{
	static TMap<FName, TWeakObjectPtr<UStaticMesh>> Cache;
	if (TWeakObjectPtr<UStaticMesh>* Found = Cache.Find(ShapeName))
	{
		if (Found->IsValid())
		{
			return Found->Get();
		}
	}
	const FString Path = FString::Printf(TEXT("/Engine/BasicShapes/%s.%s"), *ShapeName.ToString(), *ShapeName.ToString());
	UStaticMesh* Mesh = LoadObject<UStaticMesh>(nullptr, *Path);
	Cache.Add(ShapeName, Mesh);
	return Mesh;
}

UMaterialInterface* UMSFXLibrary::GetBasicMaterial()
{
	static TWeakObjectPtr<UMaterialInterface> Cached;
	if (!Cached.IsValid())
	{
		Cached = LoadObject<UMaterialInterface>(nullptr, TEXT("/Engine/BasicShapes/BasicShapeMaterial.BasicShapeMaterial"));
	}
	return Cached.Get();
}

UStaticMeshComponent* UMSFXLibrary::AddPlaceholderShape(AActor* Owner, USceneComponent* Parent, FName ShapeName, const FTransform& Relative, const FLinearColor& Color, bool bCollision)
{
	if (!Owner)
	{
		return nullptr;
	}
	UStaticMeshComponent* Comp = NewObject<UStaticMeshComponent>(Owner, NAME_None, RF_Transient);
	Comp->SetStaticMesh(GetBasicShape(ShapeName));
	if (UMaterialInterface* Base = GetBasicMaterial())
	{
		UMaterialInstanceDynamic* MID = UMaterialInstanceDynamic::Create(Base, Comp);
		MID->SetVectorParameterValue(TEXT("Color"), Color);
		Comp->SetMaterial(0, MID);
	}
	if (bCollision)
	{
		Comp->SetCollisionProfileName(TEXT("BlockAll"));
	}
	else
	{
		Comp->SetCollisionEnabled(ECollisionEnabled::NoCollision);
	}
	Comp->SetupAttachment(Parent ? Parent : Owner->GetRootComponent());
	Comp->SetRelativeTransform(Relative);
	Comp->RegisterComponent();
	Owner->AddInstanceComponent(Comp);
	return Comp;
}

void UMSFXLibrary::SpawnMuzzleFlash(UWorld* World, const FTransform& Muzzle, UNiagaraSystem* FX, float LightIntensity, USceneComponent* AttachTo)
{
	if (!World)
	{
		return;
	}
	if (FX)
	{
		if (AttachTo)
		{
			UNiagaraFunctionLibrary::SpawnSystemAttached(FX, AttachTo, NAME_None, Muzzle.GetLocation(), Muzzle.Rotator(), EAttachLocation::KeepWorldPosition, true);
		}
		else
		{
			UNiagaraFunctionLibrary::SpawnSystemAtLocation(World, FX, Muzzle.GetLocation(), Muzzle.Rotator());
		}
	}
	if (LightIntensity <= 0.f)
	{
		return;
	}
	FActorSpawnParameters Params;
	Params.SpawnCollisionHandlingOverride = ESpawnActorCollisionHandlingMethod::AlwaysSpawn;
	if (AMSFlashActor* Flash = World->SpawnActor<AMSFlashActor>(Muzzle.GetLocation(), Muzzle.Rotator(), Params))
	{
		Flash->InitLight(LightIntensity, 600.f, FLinearColor(1.f, 0.72f, 0.38f), 0.06f);
		if (!FX)
		{
			Flash->InitShape(GetBasicShape(TEXT("Sphere")), FLinearColor(4.f, 2.6f, 0.9f), FVector(0.06f), FVector(0.14f), 0.04f);
		}
	}
}

void UMSFXLibrary::SpawnImpact(UWorld* World, const FHitResult& Hit, UNiagaraSystem* FX, bool bFlesh)
{
	if (!World)
	{
		return;
	}
	if (FX)
	{
		UNiagaraFunctionLibrary::SpawnSystemAtLocation(World, FX, Hit.ImpactPoint, Hit.ImpactNormal.Rotation());
		return;
	}
	FActorSpawnParameters Params;
	Params.SpawnCollisionHandlingOverride = ESpawnActorCollisionHandlingMethod::AlwaysSpawn;
	if (AMSFlashActor* Puff = World->SpawnActor<AMSFlashActor>(Hit.ImpactPoint + Hit.ImpactNormal * 2.f, FRotator::ZeroRotator, Params))
	{
		const FLinearColor Color = bFlesh ? FLinearColor(0.35f, 0.02f, 0.02f) : FLinearColor(0.32f, 0.3f, 0.27f);
		Puff->InitShape(GetBasicShape(TEXT("Sphere")), Color, FVector(0.03f), FVector(bFlesh ? 0.18f : 0.12f), 0.18f);
		Puff->InitMotion(Hit.ImpactNormal * 120.f);
	}
}

void UMSFXLibrary::SpawnTracer(UWorld* World, const FVector& Start, const FVector& End, UNiagaraSystem* FX)
{
	if (!World)
	{
		return;
	}
	const FVector Dir = (End - Start).GetSafeNormal();
	if (FX)
	{
		UNiagaraFunctionLibrary::SpawnSystemAtLocation(World, FX, Start, Dir.Rotation());
		return;
	}
	const float Length = FVector::Dist(Start, End);
	if (Length < 300.f)
	{
		return;
	}
	// A short glowing streak that flies down the bullet path at ~ 25000 cm/s.
	const float Speed = 25000.f;
	const float Duration = FMath::Min(Length / Speed, 0.6f);
	FActorSpawnParameters Params;
	Params.SpawnCollisionHandlingOverride = ESpawnActorCollisionHandlingMethod::AlwaysSpawn;
	const FRotator Rot = FRotationMatrix::MakeFromZ(Dir).Rotator();
	if (AMSFlashActor* Streak = World->SpawnActor<AMSFlashActor>(Start + Dir * 150.f, Rot, Params))
	{
		const FVector Scale(0.012f, 0.012f, 1.6f);
		Streak->InitShape(GetBasicShape(TEXT("Cylinder")), FLinearColor(6.f, 4.f, 1.5f), Scale, Scale, Duration);
		Streak->InitMotion(Dir * Speed);
	}
}

void UMSFXLibrary::SpawnExplosion(UWorld* World, const FVector& Location, float Radius, UNiagaraSystem* FX)
{
	if (!World)
	{
		return;
	}
	if (FX)
	{
		UNiagaraFunctionLibrary::SpawnSystemAtLocation(World, FX, Location);
	}
	FActorSpawnParameters Params;
	Params.SpawnCollisionHandlingOverride = ESpawnActorCollisionHandlingMethod::AlwaysSpawn;
	if (AMSFlashActor* Boom = World->SpawnActor<AMSFlashActor>(Location + FVector(0, 0, 50), FRotator::ZeroRotator, Params))
	{
		Boom->InitLight(400000.f, Radius * 4.f, FLinearColor(1.f, 0.6f, 0.3f), 0.35f);
		if (!FX)
		{
			const float S = Radius / 100.f;
			Boom->InitShape(GetBasicShape(TEXT("Sphere")), FLinearColor(3.f, 1.2f, 0.3f), FVector(S * 0.2f), FVector(S * 0.9f), 0.25f);
		}
	}
	// Lingering smoke puff.
	if (!FX)
	{
		if (AMSFlashActor* Smoke = World->SpawnActor<AMSFlashActor>(Location + FVector(0, 0, 80), FRotator::ZeroRotator, Params))
		{
			const float S = Radius / 100.f;
			Smoke->InitShape(GetBasicShape(TEXT("Sphere")), FLinearColor(0.06f, 0.06f, 0.06f), FVector(S * 0.4f), FVector(S * 1.1f), 1.6f);
			Smoke->InitMotion(FVector(0, 0, 60));
		}
	}
}
