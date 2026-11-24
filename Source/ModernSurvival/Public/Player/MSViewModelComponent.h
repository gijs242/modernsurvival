#pragma once

#include "CoreMinimal.h"
#include "Components/ActorComponent.h"
#include "Data/MSDataTypes.h"
#include "MSViewModelComponent.generated.h"

/** Per-frame state the character feeds into the view model. */
struct FMSViewModelInput
{
	float ADSAlpha = 0.f;
	float SprintAlpha = 0.f;
	FVector2D LookRate = FVector2D::ZeroVector;   // deg/s (yaw, pitch)
	FVector LocalVelocity = FVector::ZeroVector;  // cm/s in camera space
	float WalkSpeed = 420.f;
	bool bGrounded = true;
	bool bReloading = false;
	float ReloadProgress = 0.f;
	bool bDowned = false;
	float BobPhase = 0.f;
	float BobAmount = 0.f;
};

/**
 * Procedural first-person weapon motion on the WeaponPivot component: hip/ADS blend, look sway
 * (spring lag), movement bob, idle breathing, sprint pose, per-shot kick springs, equip/reload/
 * melee poses. Values come from DT_PlayerFeel (sway) and the current weapon row (offsets, kick).
 *
 * With real arms + animations (Lyra / Game Animation Sample) keep this component: it moves the
 * whole arms rig, and the animation plays inside it.
 */
UCLASS(ClassGroup = (ModernSurvival), meta = (BlueprintSpawnableComponent))
class MODERNSURVIVAL_API UMSViewModelComponent : public UActorComponent
{
	GENERATED_BODY()

public:
	UMSViewModelComponent();

	void SetPivot(USceneComponent* InPivot) { Pivot = InPivot; }
	void SetWeaponRow(const FMSWeaponRow* InRow) { WeaponRow = InRow ? *InRow : FMSWeaponRow(); bHasWeapon = InRow != nullptr; }
	void SetInput(const FMSViewModelInput& InInput) { Input = InInput; }

	void OnShot(float KickScale);
	void OnEquip() { EquipAlpha = 0.f; }
	void OnMelee() { MeleeTime = 0.f; }
	void OnThrow() { ThrowTime = 0.f; }

	virtual void TickComponent(float DeltaTime, ELevelTick TickType, FActorComponentTickFunction* ThisTickFunction) override;

private:
	UPROPERTY(Transient) TObjectPtr<USceneComponent> Pivot;
	FMSWeaponRow WeaponRow;
	bool bHasWeapon = false;
	FMSViewModelInput Input;

	// Springs: value / velocity pairs.
	float SwayYaw = 0.f, SwayYawV = 0.f;
	float SwayPitch = 0.f, SwayPitchV = 0.f;
	float KickBack = 0.f, KickBackV = 0.f;
	float KickUp = 0.f, KickUpV = 0.f;
	float KickPitch = 0.f, KickPitchV = 0.f;
	float KickRoll = 0.f, KickRollV = 0.f;
	float SprintAlphaSmoothed = 0.f;
	float EquipAlpha = 1.f;
	float MeleeTime = 10.f;
	float ThrowTime = 10.f;
	float Time = 0.f;
};
