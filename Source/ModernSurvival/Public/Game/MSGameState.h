#pragma once

#include "CoreMinimal.h"
#include "GameFramework/GameStateBase.h"
#include "MSGameState.generated.h"

class UNiagaraSystem;
class USoundBase;

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

/**
 * What every player's HUD shows: wave, phase, timers, enemies left, who is ready. Replicated.
 * Times are server world time (use GetServerWorldTimeSeconds on clients).
 */
UCLASS()
class MODERNSURVIVAL_API AMSGameState : public AGameStateBase
{
	GENERATED_BODY()

public:
	virtual void GetLifetimeReplicatedProps(TArray<FLifetimeProperty>& OutLifetimeProps) const override;

	UPROPERTY(Replicated, BlueprintReadOnly, Category = "Match") EMSMatchPhase Phase = EMSMatchPhase::WaitingToStart;
	UPROPERTY(Replicated, BlueprintReadOnly, Category = "Match") int32 Wave = 0;
	/** Enemies of this wave not yet killed (spawned + still queued). */
	UPROPERTY(Replicated, BlueprintReadOnly, Category = "Match") int32 EnemiesRemaining = 0;
	UPROPERTY(Replicated, BlueprintReadOnly, Category = "Match") int32 EnemiesAlive = 0;
	UPROPERTY(Replicated, BlueprintReadOnly, Category = "Match") double PhaseEndTime = 0.0;
	UPROPERTY(Replicated, BlueprintReadOnly, Category = "Match") double MatchStartTime = 0.0;
	UPROPERTY(Replicated, BlueprintReadOnly, Category = "Match") bool bRevealStragglers = false;
	UPROPERTY(Replicated, BlueprintReadOnly, Category = "Match") double WaveBannerTime = -100.0;
	UPROPERTY(Replicated, BlueprintReadOnly, Category = "Match") bool bLastBannerWasClear = false;
	/** Co-op ready-up for skipping the break ("1/2 ready"). */
	UPROPERTY(Replicated, BlueprintReadOnly, Category = "Match") int32 PlayersReady = 0;
	UPROPERTY(Replicated, BlueprintReadOnly, Category = "Match") int32 PlayersInMatch = 1;
	UPROPERTY(BlueprintReadOnly, Category = "Match") FMSGameOverStats FinalStats;

	UFUNCTION(BlueprintPure, Category = "Match") float GetPhaseTimeLeft() const;
	/** Server time on every machine (HUD timers and banners). */
	double GetMatchTime() const { return GetServerWorldTimeSeconds(); }
	bool IsCoop() const { return PlayersInMatch > 1; }

	/** Explosion flash/smoke/sound/shake on every machine (damage was done on the server). */
	UFUNCTION(NetMulticast, Unreliable)
	void MulticastExplosionFX(FVector_NetQuantize Location, float Radius, UNiagaraSystem* FX, USoundBase* Sound, float Trauma, float TraumaRadius);
};
