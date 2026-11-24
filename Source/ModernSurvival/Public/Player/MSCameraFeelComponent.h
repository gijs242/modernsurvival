#pragma once

#include "CoreMinimal.h"
#include "Components/ActorComponent.h"
#include "MSCameraFeelComponent.generated.h"

class UCameraComponent;

/** Per-frame state the character feeds into the camera feel. */
struct FMSCameraFeelInput
{
	float HorizontalSpeed = 0.f;
	float WalkSpeed = 420.f;
	bool bGrounded = true;
	float SprintAlpha = 0.f;
	bool bSliding = false;
	float ADSAlpha = 0.f;
	float ADSFOV = 60.f;
	float EyeHeightAboveFeet = 160.f;
	float CapsuleHalfHeight = 90.f;
	float StrafeInput = 0.f;
};

/**
 * Everything the first-person camera does on top of the control rotation: eye height smoothing,
 * head bob, FOV (sprint/slide/ADS), trauma-based shake (explosions, damage, shots), slide and
 * strafe roll, landing dip and recoil climb + recovery. All numbers come from DT_PlayerFeel and
 * DT_LookFeel (and the weapon row for recoil).
 */
UCLASS(ClassGroup = (ModernSurvival), meta = (BlueprintSpawnableComponent))
class MODERNSURVIVAL_API UMSCameraFeelComponent : public UActorComponent
{
	GENERATED_BODY()

public:
	UMSCameraFeelComponent();

	void SetCamera(UCameraComponent* InCamera) { Camera = InCamera; }
	void SetInput(const FMSCameraFeelInput& InInput) { Input = InInput; }

	/** Adds trauma (0..1). Shake = trauma^exponent, so small hits are subtle. */
	UFUNCTION(BlueprintCallable, Category = "Camera") void AddTrauma(float Amount);
	UFUNCTION(BlueprintPure, Category = "Camera") float GetTrauma() const { return Trauma; }

	/** Kicks the view. Applied over a few frames (ApplySpeed), recovered after the spray ends. */
	void AddRecoil(float Pitch, float Yaw, float ApplySpeed, float RecoverySpeed, float RecoveryFraction);
	/** Player look input this frame, so pulling down against recoil counts as compensation. */
	void NotifyLookInput(float PitchDelta);
	void NotifyLanded(float FallSpeed);

	/** Every player camera within Radius of Location gets trauma scaled by distance. */
	static void AddTraumaAtLocation(UWorld* World, const FVector& Location, float MaxTrauma, float Radius);

	virtual void TickComponent(float DeltaTime, ELevelTick TickType, FActorComponentTickFunction* ThisTickFunction) override;

	float GetBobPhase() const { return BobPhase; }
	float GetBobAmount() const { return BobAmount; }

private:
	UPROPERTY(Transient) TObjectPtr<UCameraComponent> Camera;
	FMSCameraFeelInput Input;

	float Trauma = 0.f;
	float NoiseTime = 0.f;
	float SmoothedEyeHeight = -1.f;
	float BobPhase = 0.f;
	float BobAmount = 0.f;
	float CurrentFOV = 90.f;
	float CurrentViewModelFOV = 74.f;
	float CurrentRoll = 0.f;
	float DipOffset = 0.f;
	float DipVelocity = 0.f;

	FRotator PendingRecoil = FRotator::ZeroRotator;
	float RecoilApplySpeed = 30.f;
	float RecoilRecoverySpeed = 9.f;
	float RecoilRecoveryFraction = 0.65f;
	float RecoverablePitch = 0.f;
	double LastRecoilTime = -10.0;
};
