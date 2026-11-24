#pragma once

#include "CoreMinimal.h"
#include "GameFramework/Actor.h"
#include "Kismet/BlueprintFunctionLibrary.h"
#include "MSFXLibrary.generated.h"

class UNiagaraSystem;
class UPointLightComponent;
class UStaticMeshComponent;
class UStaticMesh;
class UMaterialInterface;

/**
 * Short-lived placeholder effect: a light flash plus an optional scaling/moving basic shape.
 * Every FX entry point below uses the Niagara system from the DataTable when one is set and
 * falls back to this, so final VFX can be dropped in without code changes.
 */
UCLASS(NotPlaceable)
class MODERNSURVIVAL_API AMSFlashActor : public AActor
{
	GENERATED_BODY()

public:
	AMSFlashActor();
	virtual void Tick(float DeltaSeconds) override;

	void InitLight(float Intensity, float Radius, const FLinearColor& Color, float Duration);
	void InitShape(UStaticMesh* Mesh, const FLinearColor& Color, const FVector& StartScale, const FVector& EndScale, float Duration);
	void InitMotion(const FVector& Velocity) { MoveVelocity = Velocity; }

	UPROPERTY(VisibleAnywhere, Category = "FX") TObjectPtr<UPointLightComponent> Light;
	UPROPERTY(VisibleAnywhere, Category = "FX") TObjectPtr<UStaticMeshComponent> Shape;

private:
	float LightStart = 0.f;
	float LightDuration = 0.f;
	FVector ScaleStart = FVector::OneVector;
	FVector ScaleEnd = FVector::OneVector;
	float ShapeDuration = 0.f;
	float Age = 0.f;
	FVector MoveVelocity = FVector::ZeroVector;
};

UCLASS()
class MODERNSURVIVAL_API UMSFXLibrary : public UBlueprintFunctionLibrary
{
	GENERATED_BODY()

public:
	static void SpawnMuzzleFlash(UWorld* World, const FTransform& Muzzle, UNiagaraSystem* FX, float LightIntensity, USceneComponent* AttachTo);
	static void SpawnImpact(UWorld* World, const FHitResult& Hit, UNiagaraSystem* FX, bool bFlesh);
	static void SpawnTracer(UWorld* World, const FVector& Start, const FVector& End, UNiagaraSystem* FX);
	static void SpawnExplosion(UWorld* World, const FVector& Location, float Radius, UNiagaraSystem* FX);

	/** Creates a basic-shape mesh component (Cube/Sphere/Cylinder/Cone) tinted with Color. Used by all placeholders. */
	static UStaticMeshComponent* AddPlaceholderShape(AActor* Owner, USceneComponent* Parent, FName Shape, const FTransform& Relative, const FLinearColor& Color, bool bCollision);

	static UStaticMesh* GetBasicShape(FName Shape);
	static UMaterialInterface* GetBasicMaterial();
};
