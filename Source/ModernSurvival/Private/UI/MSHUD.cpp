#include "UI/MSHUD.h"

#include "AI/MSAICharacter.h"
#include "AI/MSAttackHelicopter.h"
#include "Combat/MSCombatSubsystem.h"
#include "Combat/MSHealthComponent.h"
#include "Core/MSRules.h"
#include "Data/MSDataSubsystem.h"
#include "Game/MSGameState.h"
#include "Player/MSPlayerCharacter.h"
#include "Player/MSPlayerState.h"
#include "Weapons/MSWeapon.h"
#include "Camera/CameraComponent.h"
#include "Engine/Canvas.h"
#include "Engine/Engine.h"
#include "Engine/Font.h"
#include "Engine/World.h"
#include "EngineUtils.h"

namespace
{
	const FLinearColor White(0.92f, 0.93f, 0.9f, 1.f);
	const FLinearColor Dim(0.65f, 0.67f, 0.62f, 0.9f);
	const FLinearColor Amber(1.f, 0.75f, 0.25f, 1.f);
	const FLinearColor Red(1.f, 0.2f, 0.15f, 1.f);
	const FLinearColor Shadow(0.f, 0.f, 0.f, 0.6f);

	FString WithThousands(int32 Value)
	{
		FString Raw = FString::FromInt(FMath::Abs(Value));
		FString Out;
		for (int32 I = 0; I < Raw.Len(); ++I)
		{
			if (I > 0 && (Raw.Len() - I) % 3 == 0)
			{
				Out.AppendChar(TEXT(','));
			}
			Out.AppendChar(Raw[I]);
		}
		return Value < 0 ? TEXT("-") + Out : Out;
	}
}

void AMSHUD::Text(const FString& Str, float X, float Y, const FLinearColor& Color, float Scale, bool bCenter, bool bRight, bool bLarge)
{
	UFont* Font = bLarge ? GEngine->GetLargeFont() : GEngine->GetMediumFont();
	const float Sc = Scale * S;
	float W = 0.f, H = 0.f;
	GetTextSize(Str, W, H, Font, Sc);
	float DrawX = X;
	if (bCenter)
	{
		DrawX -= W * 0.5f;
	}
	else if (bRight)
	{
		DrawX -= W;
	}
	DrawText(Str, Shadow * FLinearColor(1, 1, 1, Color.A), DrawX + 2.f * S, Y + 2.f * S, Font, Sc);
	DrawText(Str, Color, DrawX, Y, Font, Sc);
}

void AMSHUD::Bar(float X, float Y, float W, float H, float Fraction, const FLinearColor& Fill)
{
	DrawRect(FLinearColor(0.f, 0.f, 0.f, 0.45f), X, Y, W, H);
	DrawRect(Fill, X, Y, W * FMath::Clamp(Fraction, 0.f, 1.f), H);
}

void AMSHUD::DrawHUD()
{
	Super::DrawHUD();
	if (!Canvas)
	{
		return;
	}
	const UMSDataSubsystem* Data = UMSDataSubsystem::Get(this);
	if (!Data)
	{
		return;
	}
	const FMSLookRow& Look = Data->GetLook();
	S = Canvas->ClipY / 1080.f * Look.HUDScale;
	CX = Canvas->ClipX * 0.5f;
	CY = Canvas->ClipY * 0.5f;

	const AMSPlayerCharacter* Player = PlayerOwner ? PlayerOwner->GetPawn<AMSPlayerCharacter>() : nullptr;
	const AMSGameState* GS = GetWorld()->GetGameState<AMSGameState>();
	const AMSPlayerState* PS = PlayerOwner ? PlayerOwner->GetPlayerState<AMSPlayerState>() : nullptr;

	DrawWaveInfo(GS, Player);
	DrawCash(PS, Look);
	DrawBanner(GS);
	DrawStragglers(GS);
	DrawHelicopterBar();
	if (Player && !Player->IsDead())
	{
		DrawCrosshair(Player, Look);
		DrawHitmarker(Player, Look);
		DrawDamageIndicators(Player, Look);
		DrawAmmoAndEquipment(Player);
		DrawPrompts(Player, GS);
	}
}

void AMSHUD::DrawCrosshair(const AMSPlayerCharacter* Player, const FMSLookRow& Look)
{
	const AMSWeapon* W = Player->GetCurrentWeapon();
	if (!W || Player->GetADSAlpha() > 0.5f || Player->IsSprinting())
	{
		return;
	}
	// Spread cone -> pixels using the camera FOV (stays correct when FOV changes).
	const float FOV = Player->GetCamera() ? Player->GetCamera()->FieldOfView : 90.f;
	const float PixelsPerDeg = Canvas->ClipX / FMath::Max(1.f, FOV);
	const float Gap = FMath::Max(4.f * S, W->GetCurrentSpread() * PixelsPerDeg);
	const float Len = Look.CrosshairSize * S;
	const FLinearColor C(1.f, 1.f, 1.f, 0.85f * (1.f - Player->GetADSAlpha() * 2.f));
	const float T = 2.f * S;
	DrawLine(CX - Gap - Len, CY, CX - Gap, CY, C, T);
	DrawLine(CX + Gap, CY, CX + Gap + Len, CY, C, T);
	DrawLine(CX, CY - Gap - Len, CX, CY - Gap, C, T);
	DrawLine(CX, CY + Gap, CX, CY + Gap + Len, C, T);
	DrawRect(C, CX - 1.f * S, CY - 1.f * S, 2.f * S, 2.f * S);
}

void AMSHUD::DrawHitmarker(const AMSPlayerCharacter* Player, const FMSLookRow& Look)
{
	const FMSRecentHit& Hit = Player->GetLastHit();
	const float Age = static_cast<float>(GetWorld()->GetTimeSeconds() - Hit.Time);
	const float Duration = Look.HitmarkerDuration * (Hit.bKilled ? 1.6f : 1.f);
	if (Age < 0.f || Age > Duration)
	{
		return;
	}
	const float T = Age / Duration;
	// Pop: starts big, snaps to size in the first quarter, fades in the last half.
	const float Pop = FMath::Lerp(Look.HitmarkerPopScale, 1.f, FMath::Clamp(T * 4.f, 0.f, 1.f));
	const float Alpha = 1.f - FMath::Clamp((T - 0.5f) * 2.f, 0.f, 1.f);
	FLinearColor C = Hit.bKilled ? Look.HitmarkerKillColor : (Hit.bArmor ? Look.HitmarkerArmorColor : Look.HitmarkerColor);
	C.A = Alpha;
	const float Gap = Look.HitmarkerGap * S * Pop;
	const float Size = Look.HitmarkerSize * S * Pop * (Hit.bHeadshot ? 1.25f : 1.f);
	const float Thick = Look.HitmarkerThickness * S * (Hit.bKilled ? 1.6f : 1.f);
	for (const FVector2D& D : {FVector2D(1, 1), FVector2D(-1, 1), FVector2D(1, -1), FVector2D(-1, -1)})
	{
		const FVector2D Dir = D.GetSafeNormal();
		DrawLine(CX + Dir.X * Gap, CY + Dir.Y * Gap, CX + Dir.X * (Gap + Size), CY + Dir.Y * (Gap + Size), C, Thick);
	}
}

void AMSHUD::DrawDamageIndicators(const AMSPlayerCharacter* Player, const FMSLookRow& Look)
{
	const double Now = GetWorld()->GetTimeSeconds();
	const FVector Loc = Player->GetActorLocation();
	const float Yaw = Player->GetControlRotation().Yaw;
	const float Radius = Look.DamageIndicatorRadius * S;
	for (const FMSRecentDamage& D : Player->GetRecentDamage())
	{
		const float Age = static_cast<float>(Now - D.Time);
		if (Age > Look.DamageIndicatorDuration || D.SourceLocation.IsNearlyZero())
		{
			continue;
		}
		const float Angle = MSRules::DamageIndicatorAngle(MSRules::FVec3(Loc.X, Loc.Y, Loc.Z), Yaw, MSRules::FVec3(D.SourceLocation.X, D.SourceLocation.Y, D.SourceLocation.Z));
		const float Alpha = 1.f - Age / Look.DamageIndicatorDuration;
		const FLinearColor C(0.85f, 0.08f, 0.05f, 0.85f * Alpha);
		// Arc of short segments; screen up = forward, so angle 0 is the top.
		const int32 Segments = 8;
		const float Half = Look.DamageIndicatorArcDeg * 0.5f;
		for (int32 I = 0; I < Segments; ++I)
		{
			const float A0 = FMath::DegreesToRadians(Angle - Half + Look.DamageIndicatorArcDeg * I / Segments - 90.f);
			const float A1 = FMath::DegreesToRadians(Angle - Half + Look.DamageIndicatorArcDeg * (I + 1) / Segments - 90.f);
			const float Thick = (6.f - FMath::Abs(I - Segments * 0.5f) * 0.8f) * S;
			DrawLine(CX + FMath::Cos(A0) * Radius, CY + FMath::Sin(A0) * Radius, CX + FMath::Cos(A1) * Radius, CY + FMath::Sin(A1) * Radius, C, Thick);
		}
	}
}

void AMSHUD::DrawWaveInfo(const AMSGameState* GS, const AMSPlayerCharacter* Player)
{
	if (!GS)
	{
		return;
	}
	const float X = 40.f * S;
	float Y = 32.f * S;
	Text(FString::Printf(TEXT("WAVE %d"), FMath::Max(1, GS->Wave + (GS->Phase == EMSMatchPhase::Intermission ? 1 : 0))), X, Y, White, 1.6f, false, false, true);
	Y += 46.f * S;
	if (GS->Phase == EMSMatchPhase::Combat)
	{
		Text(FString::Printf(TEXT("Enemies left: %d"), GS->EnemiesRemaining), X, Y, Dim, 1.f);
	}
	else if (GS->Phase == EMSMatchPhase::Intermission)
	{
		Text(FString::Printf(TEXT("Next wave in %d"), FMath::CeilToInt(GS->GetPhaseTimeLeft())), X, Y, Amber, 1.1f);
		Y += 28.f * S;
		Text(TEXT("Hold [N] to start now (bonus cash)"), X, Y, Dim, 0.85f);
		if (Player && Player->GetSkipHoldFraction() > 0.f)
		{
			Bar(X, Y + 26.f * S, 220.f * S, 5.f * S, Player->GetSkipHoldFraction(), Amber);
		}
	}
}

void AMSHUD::DrawCash(const AMSPlayerState* PS, const FMSLookRow& Look)
{
	if (!PS)
	{
		return;
	}
	const float X = Canvas->ClipX - 40.f * S;
	float Y = 32.f * S;
	Text(FString::Printf(TEXT("$%s"), *WithThousands(PS->GetCash())), X, Y, FLinearColor(0.55f, 0.95f, 0.45f, 1.f), 1.6f, false, true, true);
	Y += 48.f * S;
	const double Now = GetWorld()->GetTimeSeconds();
	const TArray<FMSCashEvent>& Events = PS->GetRecentCash();
	for (int32 I = Events.Num() - 1; I >= 0; --I)
	{
		const FMSCashEvent& E = Events[I];
		const float Age = static_cast<float>(Now - E.Time);
		if (Age > Look.CashPopupDuration)
		{
			continue;
		}
		const float Alpha = 1.f - FMath::Clamp((Age / Look.CashPopupDuration - 0.6f) / 0.4f, 0.f, 1.f);
		const FString Line = FString::Printf(TEXT("%s %s$%s"), *E.Reason.ToString(), E.Amount >= 0 ? TEXT("+") : TEXT(""), *WithThousands(E.Amount));
		Text(Line, X, Y - Age * 12.f * S, FLinearColor(0.75f, 1.f, 0.6f, Alpha), 0.9f, false, true);
		Y += 24.f * S;
	}
}

void AMSHUD::DrawAmmoAndEquipment(const AMSPlayerCharacter* Player)
{
	const float X = Canvas->ClipX - 40.f * S;
	float Y = Canvas->ClipY - 150.f * S;
	if (const AMSWeapon* W = Player->GetCurrentWeapon())
	{
		Text(W->GetRow().DisplayName.ToString(), X, Y, Dim, 0.9f, false, true);
		Y += 26.f * S;
		const bool bLow = W->GetAmmoInMag() <= FMath::Max(1, W->GetRow().MagazineSize / 4);
		Text(FString::Printf(TEXT("%d"), W->GetAmmoInMag()), X - 110.f * S, Y, bLow ? Red : White, 1.8f, false, true, true);
		Text(FString::Printf(TEXT("/ %d"), W->GetReserveAmmo()), X, Y + 14.f * S, Dim, 1.1f, false, true);
		if (W->IsReloading())
		{
			Bar(CX - 60.f * S, CY + 60.f * S, 120.f * S, 4.f * S, W->GetReloadProgress(), White);
		}
		else if (W->GetAmmoInMag() == 0)
		{
			Text(W->GetReserveAmmo() > 0 ? TEXT("RELOAD [R]") : TEXT("NO AMMO"), CX, CY + 50.f * S, Red, 0.9f, true);
		}
		else if (bLow)
		{
			Text(TEXT("LOW AMMO"), CX, CY + 50.f * S, Amber, 0.8f, true);
		}
	}
	// Equipment row.
	Y = Canvas->ClipY - 60.f * S;
	struct FEntry { EMSEquipmentSlot Slot; const TCHAR* Label; };
	const FEntry Entries[] = {
		{EMSEquipmentSlot::Frag, TEXT("[G] Frag")}, {EMSEquipmentSlot::Claymore, TEXT("[3] Claymore")},
		{EMSEquipmentSlot::Sentry, TEXT("[4] Sentry")}, {EMSEquipmentSlot::Airstrike, TEXT("[5] Airstrike")},
		{EMSEquipmentSlot::Squad, TEXT("[6] Squad")}};
	FString Line;
	for (const FEntry& E : Entries)
	{
		const int32 N = Player->GetEquipmentCount(E.Slot);
		if (N > 0 || E.Slot == EMSEquipmentSlot::Frag)
		{
			Line += FString::Printf(TEXT("%s x%d    "), E.Label, N);
		}
	}
	Text(Line.TrimEnd(), X, Y, Dim, 0.8f, false, true);

	// Armor bar (bottom left). Health has no bar: the screen edges go red instead.
	const UMSHealthComponent* H = Player->GetHealth();
	if (H && H->GetArmor() > 0.f)
	{
		Text(TEXT("ARMOR"), 40.f * S, Canvas->ClipY - 70.f * S, Dim, 0.8f);
		Bar(40.f * S, Canvas->ClipY - 44.f * S, 220.f * S, 8.f * S, H->GetArmor() / FMath::Max(1.f, H->GetMaxArmor()), FLinearColor(0.4f, 0.75f, 1.f, 0.9f));
	}
	if (Player->GetGrenadeCookTime() > 0.f)
	{
		const float Fuse = UMSDataSubsystem::Get(this)->GetEquipment(TEXT("Frag")).FuseTime;
		Bar(CX - 50.f * S, CY + 75.f * S, 100.f * S, 5.f * S, 1.f - Player->GetGrenadeCookTime() / FMath::Max(0.1f, Fuse), Red);
	}
}

void AMSHUD::DrawPrompts(const AMSPlayerCharacter* Player, const AMSGameState* GS)
{
	const FText Prompt = Player->GetInteractPrompt();
	if (!Prompt.IsEmpty())
	{
		Text(Prompt.ToString(), CX, CY + 110.f * S, White, 1.f, true);
	}
	if (Player->IsDowned())
	{
		Text(TEXT("LAST STAND"), CX, CY - 160.f * S, Red, 1.5f, true, false, true);
		Text(FString::Printf(TEXT("Survive %.1fs to get back up"), Player->GetLastStandTimeLeft()), CX, CY - 115.f * S, White, 1.f, true);
	}
}

void AMSHUD::DrawBanner(const AMSGameState* GS)
{
	if (!GS)
	{
		return;
	}
	const float Age = static_cast<float>(GetWorld()->GetTimeSeconds() - GS->WaveBannerTime);
	if (Age < 0.f || Age > 3.5f)
	{
		return;
	}
	const float Alpha = FMath::Clamp(Age * 4.f, 0.f, 1.f) * (1.f - FMath::Clamp((Age - 2.5f), 0.f, 1.f));
	const FString Title = GS->bLastBannerWasClear ? TEXT("WAVE SURVIVED") : FString::Printf(TEXT("WAVE %d"), GS->Wave);
	Text(Title, CX, Canvas->ClipY * 0.22f, FLinearColor(1.f, 1.f, 1.f, Alpha), 2.2f, true, false, true);
}

void AMSHUD::DrawStragglers(const AMSGameState* GS)
{
	if (!GS || !GS->bRevealStragglers)
	{
		return;
	}
	const UMSCombatSubsystem* Combat = UMSCombatSubsystem::Get(this);
	if (!Combat)
	{
		return;
	}
	for (const UMSHealthComponent* H : Combat->GetHostiles(EMSTeam::Player))
	{
		const FVector P = Project(H->GetOwner()->GetActorLocation() + FVector(0, 0, 120.f));
		if (P.Z <= 0.f)
		{
			continue;
		}
		const float R = 8.f * S;
		const FLinearColor C(1.f, 0.25f, 0.2f, 0.9f);
		DrawLine(P.X, P.Y - R, P.X + R, P.Y, C, 2.f * S);
		DrawLine(P.X + R, P.Y, P.X, P.Y + R, C, 2.f * S);
		DrawLine(P.X, P.Y + R, P.X - R, P.Y, C, 2.f * S);
		DrawLine(P.X - R, P.Y, P.X, P.Y - R, C, 2.f * S);
	}
}

void AMSHUD::DrawHelicopterBar()
{
	for (TActorIterator<AMSAttackHelicopter> It(GetWorld()); It; ++It)
	{
		const UMSHealthComponent* H = It->GetHealth();
		if (H && !H->IsDead())
		{
			Text(TEXT("ATTACK HELICOPTER"), CX, 30.f * S, Red, 0.9f, true);
			Bar(CX - 200.f * S, 58.f * S, 400.f * S, 6.f * S, H->GetHealthFraction(), Red);
			return;
		}
	}
}
