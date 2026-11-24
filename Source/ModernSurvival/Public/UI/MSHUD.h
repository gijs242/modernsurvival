#pragma once

#include "CoreMinimal.h"
#include "GameFramework/HUD.h"
#include "MSHUD.generated.h"

class AMSPlayerCharacter;
class AMSGameState;
class AMSPlayerState;
struct FMSLookRow;

/**
 * In-game HUD drawn on the canvas: wave, enemies left, cash (+popups), ammo, equipment, crosshair
 * (sized by current spread), hitmarkers, damage-direction arcs, interact prompt, last stand,
 * skip-break bar, wave banners, straggler markers and helicopter health. Sizes/colours/timings
 * are in DT_LookFeel. Menus (shop, pause, game over) are UMG widgets in MSMenuWidgets.
 */
UCLASS()
class MODERNSURVIVAL_API AMSHUD : public AHUD
{
	GENERATED_BODY()

public:
	virtual void DrawHUD() override;

private:
	void DrawCrosshair(const AMSPlayerCharacter* Player, const FMSLookRow& Look);
	void DrawHitmarker(const AMSPlayerCharacter* Player, const FMSLookRow& Look);
	void DrawDamageIndicators(const AMSPlayerCharacter* Player, const FMSLookRow& Look);
	void DrawWaveInfo(const AMSGameState* GS, const AMSPlayerCharacter* Player);
	void DrawCash(const AMSPlayerState* PS, const FMSLookRow& Look);
	void DrawAmmoAndEquipment(const AMSPlayerCharacter* Player);
	void DrawPrompts(const AMSPlayerCharacter* Player, const AMSGameState* GS);
	void DrawBanner(const AMSGameState* GS);
	void DrawStragglers(const AMSGameState* GS);
	void DrawHelicopterBar();
	void DrawTeammates(const AMSPlayerCharacter* Self);

	void Text(const FString& Str, float X, float Y, const FLinearColor& Color, float Scale, bool bCenter = false, bool bRight = false, bool bLarge = false);
	void Bar(float X, float Y, float W, float H, float Fraction, const FLinearColor& Fill);

	float S = 1.f;     // UI scale (1 at 1080p)
	float CX = 0.f;
	float CY = 0.f;
};
