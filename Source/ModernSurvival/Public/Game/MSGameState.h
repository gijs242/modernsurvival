#pragma once

#include "CoreMinimal.h"
#include "GameFramework/GameStateBase.h"
#include "MSGameState.generated.h"

UENUM(BlueprintType)
enum class EMSMatchPhase : uint8
{
	WaitingToStart,
	Intermission,
	Combat,
	GameOver
};

USTRUCT(BlueprintType)
struct MODERNSURVIVAL_API FMSGameOverStats
{
	GENERATED_BODY()

	UPROPERTY(BlueprintReadOnly, Category = "Stats") int32 WaveReached = 0;
	UPROPERTY(BlueprintReadOnly, Category = "Stats") int32 Kills = 0;
	UPROPERTY(BlueprintReadOnly, Category = "Stats") int32 Headshots = 0;
	UPROPERTY(BlueprintReadOnly, Category = "Stats") int32 CashEarned = 0;
	UPROPERTY(BlueprintReadOnly, Category = "Stats") float TimeSurvived = 0.f;
	UPROPERTY(BlueprintReadOnly, Category = "Stats") int32 BestWave = 0;
	UPROPERTY(BlueprintReadOnly, Category = "Stats") bool bNewBest = false;
};

/** What the HUD shows: wave, phase, timers, enemies left. */
UCLASS()
class MODERNSURVIVAL_API AMSGameState : public AGameStateBase
{
	GENERATED_BODY()

public:
	UPROPERTY(BlueprintReadOnly, Category = "Match") EMSMatchPhase Phase = EMSMatchPhase::WaitingToStart;
	UPROPERTY(BlueprintReadOnly, Category = "Match") int32 Wave = 0;
	/** Enemies of this wave not yet killed (spawned + still queued). */
	UPROPERTY(BlueprintReadOnly, Category = "Match") int32 EnemiesRemaining = 0;
	UPROPERTY(BlueprintReadOnly, Category = "Match") int32 EnemiesAlive = 0;
	UPROPERTY(BlueprintReadOnly, Category = "Match") double PhaseEndTime = 0.0;
	UPROPERTY(BlueprintReadOnly, Category = "Match") double MatchStartTime = 0.0;
	UPROPERTY(BlueprintReadOnly, Category = "Match") bool bRevealStragglers = false;
	UPROPERTY(BlueprintReadOnly, Category = "Match") double WaveBannerTime = -100.0;
	UPROPERTY(BlueprintReadOnly, Category = "Match") bool bLastBannerWasClear = false;
	UPROPERTY(BlueprintReadOnly, Category = "Match") FMSGameOverStats FinalStats;

	UFUNCTION(BlueprintPure, Category = "Match") float GetPhaseTimeLeft() const;
};
