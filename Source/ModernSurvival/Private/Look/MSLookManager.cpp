#include "Look/MSLookManager.h"

#include "Combat/MSHealthComponent.h"
#include "Data/MSDataSubsystem.h"
#include "Player/MSPlayerCharacter.h"
#include "Components/PostProcessComponent.h"
#include "Engine/World.h"
#include "GameFramework/PlayerController.h"
#include "HAL/IConsoleManager.h"

AMSLookManager::AMSLookManager()
{
	PrimaryActorTick.bCanEverTick = true;
	PostProcess = CreateDefaultSubobject<UPostProcessComponent>(TEXT("PostProcess"));
	PostProcess->bUnbound = true;
	PostProcess->Priority = 10.f;
	SetRootComponent(PostProcess);
}

void AMSLookManager::BeginPlay()
{
	Super::BeginPlay();
	ApplyBaseGrade();
}

void AMSLookManager::ApplyBaseGrade()
{
	const UMSDataSubsystem* Data = UMSDataSubsystem::Get(this);
	if (!Data)
	{
		return;
	}
	const FMSLookRow& L = Data->GetLook();
	FPostProcessSettings& S = PostProcess->Settings;

	S.bOverride_ColorSaturation = true;
	S.ColorSaturation = FVector4(L.Saturation, L.Saturation, L.Saturation, 1.f);
	S.bOverride_ColorContrast = true;
	S.ColorContrast = FVector4(L.Contrast, L.Contrast, L.Contrast, 1.f);
	S.bOverride_ColorContrastShadows = true;
	S.ColorContrastShadows = FVector4(L.ShadowsContrast, L.ShadowsContrast, L.ShadowsContrast, 1.f);
	S.bOverride_ColorGainHighlights = true;
	S.ColorGainHighlights = FVector4(L.HighlightTint.R * L.HighlightsGain, L.HighlightTint.G * L.HighlightsGain, L.HighlightTint.B * L.HighlightsGain, 1.f);
	S.bOverride_ColorGainShadows = true;
	S.ColorGainShadows = FVector4(L.ShadowTint.R, L.ShadowTint.G, L.ShadowTint.B, 1.f);
	S.bOverride_WhiteTemp = true;
	S.WhiteTemp = L.WhiteTemp;

	S.bOverride_FilmGrainIntensity = true;
	S.FilmGrainIntensity = L.FilmGrainIntensity;
	S.bOverride_FilmGrainIntensityShadows = true;
	S.FilmGrainIntensityShadows = L.FilmGrainShadows;

	S.bOverride_VignetteIntensity = true;
	S.VignetteIntensity = L.VignetteIntensity;
	S.bOverride_BloomIntensity = true;
	S.BloomIntensity = L.BloomIntensity;
	S.bOverride_SceneFringeIntensity = true;
	S.SceneFringeIntensity = L.ChromaticAberration;

	S.bOverride_AutoExposureBias = true;
	S.AutoExposureBias = L.ExposureBias;
	S.bOverride_AutoExposureMinBrightness = true;
	S.AutoExposureMinBrightness = L.ExposureMinEV;
	S.bOverride_AutoExposureMaxBrightness = true;
	S.AutoExposureMaxBrightness = L.ExposureMaxEV;

	// Lumen on, motion blur off (it smears recoil).
	S.bOverride_DynamicGlobalIlluminationMethod = true;
	S.DynamicGlobalIlluminationMethod = EDynamicGlobalIlluminationMethod::Lumen;
	S.bOverride_ReflectionMethod = true;
	S.ReflectionMethod = EReflectionMethod::Lumen;
	S.bOverride_MotionBlurAmount = true;
	S.MotionBlurAmount = 0.f;

	if (IConsoleVariable* Sharpen = IConsoleManager::Get().FindConsoleVariable(TEXT("r.Tonemapper.Sharpen")))
	{
		Sharpen->Set(L.SharpenAmount, ECVF_SetByGameSetting);
	}
}

void AMSLookManager::Tick(float DeltaSeconds)
{
	Super::Tick(DeltaSeconds);
	const UMSDataSubsystem* Data = UMSDataSubsystem::Get(this);
	const APlayerController* PC = GetWorld()->GetFirstPlayerController();
	const AMSPlayerCharacter* Player = PC ? PC->GetPawn<AMSPlayerCharacter>() : nullptr;
	if (!Data || !Player || !Player->GetHealth())
	{
		return;
	}
	const FMSLookRow& L = Data->GetLook();
	const float HealthFrac = Player->GetHealth()->GetHealthFraction();
	const float Target = Player->IsDowned() ? 1.f : FMath::Clamp(1.f - HealthFrac / FMath::Max(0.01f, L.LowHealthThreshold), 0.f, 1.f);
	LowHealthBlend = FMath::FInterpTo(LowHealthBlend, Target, DeltaSeconds, 6.f);

	FPostProcessSettings& S = PostProcess->Settings;
	const float Sat = L.Saturation * (1.f - L.LowHealthDesaturate * LowHealthBlend);
	S.ColorSaturation = FVector4(Sat, Sat, Sat, 1.f);
	S.VignetteIntensity = L.VignetteIntensity + L.LowHealthVignette * LowHealthBlend + L.ADSVignetteAdd * Player->GetADSAlpha();
	// Blood-red tint at the edges when hurt.
	S.bOverride_ColorGainMidtones = true;
	S.ColorGainMidtones = FVector4(1.f + 0.25f * LowHealthBlend, 1.f - 0.12f * LowHealthBlend, 1.f - 0.12f * LowHealthBlend, 1.f);
}
