#include "Player/MSCameraFeelComponent.h"

#include "Core/MSEngineCompat.h"
#include "Core/MSRules.h"
#include "Data/MSDataSubsystem.h"
#include "Camera/CameraComponent.h"
#include "Engine/World.h"
#include "GameFramework/Controller.h"
#include "GameFramework/Pawn.h"
#include "GameFramework/PlayerController.h"

UMSCameraFeelComponent::UMSCameraFeelComponent()
{
	PrimaryComponentTick.bCanEverTick = true;
	// After movement so the camera sees this frame's position.
	PrimaryComponentTick.TickGroup = TG_PostPhysics;
}

void UMSCameraFeelComponent::AddTrauma(float Amount)
{
	Trauma = FMath::Clamp(Trauma + Amount, 0.f, 1.f);
}

void UMSCameraFeelComponent::AddRecoil(float Pitch, float Yaw, float ApplySpeed, float RecoverySpeed, float RecoveryFraction)
{
	PendingRecoil.Pitch += Pitch;
	PendingRecoil.Yaw += Yaw;
	RecoilApplySpeed = FMath::Max(1.f, ApplySpeed);
	RecoilRecoverySpeed = RecoverySpeed;
	RecoilRecoveryFraction = FMath::Clamp(RecoveryFraction, 0.f, 1.f);
	LastRecoilTime = GetWorld() ? GetWorld()->GetTimeSeconds() : 0.0;
}

void UMSCameraFeelComponent::NotifyLookInput(float PitchDelta)
{
	if (PitchDelta < 0.f)
	{
		RecoverablePitch = FMath::Max(0.f, RecoverablePitch + PitchDelta);
	}
}

void UMSCameraFeelComponent::NotifyLanded(float FallSpeed)
{
	const UMSDataSubsystem* Data = UMSDataSubsystem::Get(this);
	const float Dip = Data ? Data->GetPlayerFeel().LandingDip : 4.f;
	DipVelocity -= FMath::Clamp(FallSpeed / 1000.f, 0.f, 2.f) * Dip * 18.f;
}

void UMSCameraFeelComponent::AddTraumaAtLocation(UWorld* World, const FVector& Location, float MaxTrauma, float Radius)
{
	if (!World || MaxTrauma <= 0.f)
	{
		return;
	}
	for (FConstPlayerControllerIterator It = World->GetPlayerControllerIterator(); It; ++It)
	{
		const APlayerController* PC = It->Get();
		const APawn* Pawn = PC ? PC->GetPawn() : nullptr;
		if (!Pawn)
		{
			continue;
		}
		if (UMSCameraFeelComponent* Feel = Pawn->FindComponentByClass<UMSCameraFeelComponent>())
		{
			Feel->AddTrauma(MSRules::ExplosionTrauma(MaxTrauma, FVector::Dist(Pawn->GetActorLocation(), Location), Radius));
		}
	}
}

void UMSCameraFeelComponent::TickComponent(float DeltaTime, ELevelTick TickType, FActorComponentTickFunction* ThisTickFunction)
{
	Super::TickComponent(DeltaTime, TickType, ThisTickFunction);
	APawn* Pawn = Cast<APawn>(GetOwner());
	AController* Controller = Pawn ? Pawn->GetController() : nullptr;
	const UMSDataSubsystem* Data = UMSDataSubsystem::Get(this);
	if (!Camera || !Pawn || !Data)
	{
		return;
	}
	const FMSPlayerFeelRow& Feel = Data->GetPlayerFeel();
	const FMSLookRow& Look = Data->GetLook();
	const float Dt = FMath::Min(DeltaTime, 0.1f);

	// --- Recoil: apply pending kick over a few frames, then recover part of it.
	if (Controller)
	{
		const float Alpha = FMath::Clamp(RecoilApplySpeed * Dt, 0.f, 1.f);
		const FRotator Step = PendingRecoil * Alpha;
		PendingRecoil -= Step;
		FRotator Control = Controller->GetControlRotation();
		Control.Pitch = FRotator::NormalizeAxis(Control.Pitch + Step.Pitch);
		Control.Yaw += Step.Yaw;
		RecoverablePitch += Step.Pitch * RecoilRecoveryFraction;

		const double Now = GetWorld()->GetTimeSeconds();
		if (Now - LastRecoilTime > 0.12 && RecoverablePitch > 0.f)
		{
			const float NewRecoverable = MSRules::RecoilRecoveryStep(RecoverablePitch, RecoilRecoverySpeed, Dt);
			Control.Pitch = FRotator::NormalizeAxis(Control.Pitch - (RecoverablePitch - NewRecoverable));
			RecoverablePitch = NewRecoverable;
		}
		Control.Pitch = FMath::Clamp(Control.Pitch, -89.f, 89.f);
		Controller->SetControlRotation(Control);
	}

	// --- Eye height (smoothed in "above the feet" space so crouching doesn't pop).
	if (SmoothedEyeHeight < 0.f)
	{
		SmoothedEyeHeight = Input.EyeHeightAboveFeet;
	}
	SmoothedEyeHeight = FMath::FInterpTo(SmoothedEyeHeight, Input.EyeHeightAboveFeet, Dt, Feel.EyeHeightInterpSpeed);

	// --- Head bob.
	const float SpeedFrac = Input.WalkSpeed > 0.f ? Input.HorizontalSpeed / Input.WalkSpeed : 0.f;
	const float TargetBob = (Input.bGrounded && !Input.bSliding) ? FMath::Clamp(SpeedFrac, 0.f, 1.6f) : 0.f;
	BobAmount = FMath::FInterpTo(BobAmount, TargetBob, Dt, 8.f);
	BobPhase += Dt * Feel.BobFrequency * FMath::Max(0.6f, SpeedFrac) * 2.f * PI;
	const float BobMul = FMath::Lerp(1.f, Feel.SprintBobMultiplier, Input.SprintAlpha) * FMath::Lerp(1.f, Feel.ADSBobMultiplier, Input.ADSAlpha) * BobAmount;
	const float BobZ = FMath::Sin(BobPhase * 2.f) * Feel.BobVertical * BobMul;
	const float BobY = FMath::Sin(BobPhase) * Feel.BobHorizontal * BobMul;

	// --- Landing dip spring.
	MSRules::SpringStep(DipOffset, DipVelocity, 0.f, 120.f, 14.f, Dt);

	// --- Trauma shake.
	Trauma = FMath::Max(0.f, Trauma - Look.TraumaDecay * Dt);
	NoiseTime += Dt * Look.ShakeFrequency;
	const float Shake = MSRules::TraumaToShake(Trauma, Look.TraumaExponent);
	const FRotator ShakeRot(
		Look.ShakeMaxPitch * Shake * FMath::PerlinNoise1D(NoiseTime + 11.3f),
		Look.ShakeMaxYaw * Shake * FMath::PerlinNoise1D(NoiseTime + 47.1f),
		Look.ShakeMaxRoll * Shake * FMath::PerlinNoise1D(NoiseTime + 91.7f));
	const FVector ShakeOffset = FVector(
		FMath::PerlinNoise1D(NoiseTime + 3.3f),
		FMath::PerlinNoise1D(NoiseTime + 7.7f),
		FMath::PerlinNoise1D(NoiseTime + 5.5f)) * Look.ShakeMaxOffset * Shake;

	// --- Roll (slide, strafe).
	const float TargetRoll = (Input.bSliding ? Feel.SlideCameraRoll : 0.f) + Input.StrafeInput * Feel.StrafeRoll * (1.f - Input.ADSAlpha);
	CurrentRoll = FMath::FInterpTo(CurrentRoll, TargetRoll, Dt, 8.f);

	// --- FOV.
	const float HipFOV = Feel.BaseFOV + Feel.SprintFOVAdd * Input.SprintAlpha + (Input.bSliding ? Feel.SlideFOVAdd : 0.f);
	const float TargetFOV = FMath::Lerp(HipFOV, Input.ADSFOV, Input.ADSAlpha);
	CurrentFOV = FMath::FInterpTo(CurrentFOV, TargetFOV, Dt, Feel.FOVInterpSpeed * (Input.ADSAlpha > 0.01f ? 2.f : 1.f));
	Camera->SetFieldOfView(CurrentFOV);
	CurrentViewModelFOV = FMath::Lerp(Feel.ViewModelFOV, Feel.ViewModelADSFOV, Input.ADSAlpha);
#if MS_WITH_FIRST_PERSON_RENDERING
	Camera->bEnableFirstPersonFieldOfView = true;
	Camera->bEnableFirstPersonScale = true;
	Camera->FirstPersonFieldOfView = CurrentViewModelFOV;
	Camera->FirstPersonScale = Feel.ViewModelScale;
#endif

	// --- Apply: camera position relative to the capsule, rotation = control rotation + shake + roll.
	Camera->SetRelativeLocation(FVector(0.f, BobY, SmoothedEyeHeight - Input.CapsuleHalfHeight + BobZ + DipOffset) + ShakeOffset);
	const FRotator ControlRot = Controller ? Controller->GetControlRotation() : Pawn->GetActorRotation();
	FRotator Final = ControlRot + ShakeRot;
	Final.Roll += CurrentRoll;
	Camera->SetWorldRotation(Final);
}
