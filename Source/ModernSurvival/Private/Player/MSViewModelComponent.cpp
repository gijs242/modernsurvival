#include "Player/MSViewModelComponent.h"

#include "Core/MSRules.h"
#include "Data/MSDataSubsystem.h"
#include "Components/SceneComponent.h"

UMSViewModelComponent::UMSViewModelComponent()
{
	PrimaryComponentTick.bCanEverTick = true;
	PrimaryComponentTick.TickGroup = TG_PostPhysics;
}

void UMSViewModelComponent::OnShot(float KickScale)
{
	const float Scale = KickScale * FMath::Lerp(1.f, WeaponRow.ADSKickMultiplier, Input.ADSAlpha);
	// Kick as a velocity impulse so the spring gives a snappy, physical recoil.
	KickBackV -= WeaponRow.KickBack * Scale * 40.f;
	KickUpV += WeaponRow.KickUp * Scale * 40.f;
	KickPitchV += WeaponRow.KickPitch * Scale * 40.f;
	KickRollV += WeaponRow.KickRoll * Scale * 40.f * (FMath::RandBool() ? 1.f : -1.f);
}

void UMSViewModelComponent::TickComponent(float DeltaTime, ELevelTick TickType, FActorComponentTickFunction* ThisTickFunction)
{
	Super::TickComponent(DeltaTime, TickType, ThisTickFunction);
	const UMSDataSubsystem* Data = UMSDataSubsystem::Get(this);
	if (!Pivot || !Data)
	{
		return;
	}
	const FMSPlayerFeelRow& Feel = Data->GetPlayerFeel();
	const float Dt = FMath::Min(DeltaTime, 0.1f);
	Time += Dt;

	// ADS blend with an ease so the sight snaps into place at the end.
	const float A = Input.ADSAlpha;
	const float ADSEase = A * A * (3.f - 2.f * A);
	const float SwayScale = WeaponRow.SwayMultiplier * FMath::Lerp(1.f, WeaponRow.ADSSwayMultiplier, A);

	// Look sway: the gun lags behind where you look.
	const float TargetYaw = FMath::Clamp(-Input.LookRate.X * Feel.LookSwayAmount, -Feel.LookSwayMax, Feel.LookSwayMax) * SwayScale;
	const float TargetPitch = FMath::Clamp(Input.LookRate.Y * Feel.LookSwayAmount, -Feel.LookSwayMax, Feel.LookSwayMax) * SwayScale;
	MSRules::SpringStep(SwayYaw, SwayYawV, TargetYaw, Feel.SwayStiffness, Feel.SwayDamping, Dt);
	MSRules::SpringStep(SwayPitch, SwayPitchV, TargetPitch, Feel.SwayStiffness, Feel.SwayDamping, Dt);

	// Kick springs.
	MSRules::SpringStep(KickBack, KickBackV, 0.f, WeaponRow.KickStiffness, WeaponRow.KickDamping, Dt);
	MSRules::SpringStep(KickUp, KickUpV, 0.f, WeaponRow.KickStiffness, WeaponRow.KickDamping, Dt);
	MSRules::SpringStep(KickPitch, KickPitchV, 0.f, WeaponRow.KickStiffness, WeaponRow.KickDamping, Dt);
	MSRules::SpringStep(KickRoll, KickRollV, 0.f, WeaponRow.KickStiffness, WeaponRow.KickDamping, Dt);

	// Movement: figure-eight bob and a lean into strafes.
	const float MoveScale = Feel.MoveSwayAmount * Input.BobAmount * FMath::Lerp(1.f, 0.2f, A) * FMath::Lerp(1.f, 1.6f, Input.SprintAlpha);
	const FVector Bob(0.f, FMath::Sin(Input.BobPhase) * MoveScale, -FMath::Abs(FMath::Cos(Input.BobPhase)) * MoveScale * 0.7f);
	const float StrafeLean = Input.WalkSpeed > 0.f ? FMath::Clamp(Input.LocalVelocity.Y / Input.WalkSpeed, -1.f, 1.f) : 0.f;

	// Idle breathing (much less when aiming).
	const float Breath = Feel.IdleBreathAmplitude * FMath::Lerp(1.f, 0.35f, A);
	const FRotator BreathRot(FMath::Sin(Time * Feel.IdleBreathFrequency * 2.f * PI) * Breath, FMath::Sin(Time * Feel.IdleBreathFrequency * PI) * Breath * 0.6f, 0.f);

	// Sprint pose.
	SprintAlphaSmoothed = FMath::FInterpTo(SprintAlphaSmoothed, Input.SprintAlpha * (1.f - A), Dt, Feel.SprintPoseInterpSpeed);
	const float S = SprintAlphaSmoothed;

	// Equip: rise from below. Reload: tilt. Melee/throw: quick jab.
	EquipAlpha = FMath::Min(1.f, EquipAlpha + Dt / FMath::Max(0.05f, WeaponRow.EquipTime));
	const float EquipDrop = (1.f - EquipAlpha) * (1.f - EquipAlpha);
	const float ReloadTilt = Input.bReloading ? FMath::Sin(FMath::Clamp(Input.ReloadProgress, 0.f, 1.f) * PI) : 0.f;
	MeleeTime += Dt;
	ThrowTime += Dt;
	const float Jab = MeleeTime < 0.35f ? FMath::Sin(MeleeTime / 0.35f * PI) : 0.f;
	const float Throw = ThrowTime < 0.5f ? FMath::Sin(ThrowTime / 0.5f * PI) : 0.f;
	const float Downed = Input.bDowned ? 1.f : 0.f;

	FVector Loc = FMath::Lerp(WeaponRow.HipOffset, WeaponRow.ADSOffset, ADSEase);
	Loc += Bob + FVector(KickBack, 0.f, KickUp);
	Loc += Feel.SprintWeaponOffset * S;
	Loc += FVector(-6.f, 2.f, -18.f) * EquipDrop;
	Loc += FVector(-3.f, 0.f, -6.f) * ReloadTilt;
	Loc += FVector(18.f, -6.f, 4.f) * Jab;
	Loc += FVector(-4.f, 0.f, -14.f) * Throw;
	Loc += FVector(0.f, 0.f, -2.f) * Downed;

	FRotator Rot(SwayPitch + KickPitch, SwayYaw, KickRoll - StrafeLean * 3.f * (1.f - A));
	Rot += BreathRot;
	Rot += Feel.SprintWeaponRotation * S;
	Rot += FRotator(-30.f, 0.f, 0.f) * EquipDrop;
	Rot += FRotator(-12.f, 10.f, 35.f) * ReloadTilt;
	Rot += FRotator(-10.f, -25.f, 0.f) * Jab;
	Rot += FRotator(-35.f, 0.f, 0.f) * Throw;
	Rot += FRotator(0.f, 0.f, 15.f) * Downed;

	Pivot->SetRelativeLocationAndRotation(Loc, Rot);
}
